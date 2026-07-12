# render.R — ggplot2 rendering layer
#
# The rendering layer is split into two pieces (Stage 5's refactor):
#   journey_layers()      — builds the geom layers only (no scales/theme), plus
#                           the metadata the scale/theme assembly needs.
#   render_journey_plot() — assembles those layers with the x-scale, y-scale,
#                           optional facet, and theme into a finished ggplot.
#
# Splitting the geoms out lets a second consumer (plot_cohort_timeline()) reuse
# the exact same layer construction across facet panels, and lets the x-axis be
# either datetime (single case, absolute time) or numeric elapsed-hours (a
# cohort of start-aligned cases) without duplicating any geom code.
#
# Because all data shaping is done upstream, swapping this for a plotly/ggiraph
# renderer is a matter of writing a sibling assembler consuming journey_layers().
# Stage 7 does exactly this: render_journey_plot_interactive() in
# render_interactive.R reuses render_journey_plot() verbatim, with
# opts$interactive = TRUE switching journey_layers() to emit ggiraph's
# tooltip-bearing geoms (boxes, terminal markers, event points) in place of
# their static equivalents.


# ── journey_layers ────────────────────────────────────────────────────────────
#
# Build every geom layer for a journey plot from the two tidy tables and an opts
# list. Returns list(layers = <list of ggplot layers>, meta = <list>) where meta
# carries the derived values the scale/theme assembly needs (colour vectors,
# level counts, lane-axis breaks, the labels-rendered flag, and the x-axis
# scaling context). Adds no scales or theme — those belong to the assembler.
#
# opts$x_scale ∈ {"datetime", "elapsed_hours"} (default "datetime") selects
# whether the box/event x columns are POSIXct instants or numeric elapsed hours.
# The layer geometry is unit-agnostic: every width/gap computation is expressed
# in the same units as the incoming x columns, so the two modes share one code
# path.
journey_layers <- function(boxes, events, opts) {

  # ── Unpack opts ────────────────────────────────────────────────────────────
  show_labels      <- opts$show_labels
  label_max        <- opts$label_max
  show_duration    <- opts$show_duration
  label_boxes      <- opts$label_boxes
  reference_lines  <- opts$reference_lines
  event_type_top_n <- opts$event_type_top_n
  case_open        <- opts$case_open %||% FALSE
  lanes_active     <- opts$lanes_active %||% FALSE
  state_palette    <- opts$state_palette
  event_palette    <- opts$event_palette
  palette_style    <- opts$palette_style
  box_height       <- opts$box_height
  box_gap_prop     <- opts$box_gap_prop
  x_scale          <- opts$x_scale %||% "datetime"
  interactive      <- opts$interactive %||% FALSE

  # ── Derived layout values ──────────────────────────────────────────────────
  # Spans are in the x columns' native units: seconds for datetime input
  # (difftime), hours for elapsed-hours input (plain numeric subtraction). Every
  # downstream width/gap computation stays in those same units, so both modes
  # share one arithmetic path.
  span_in_x_units <- function(xmin, xmax) {
    if (x_scale == "datetime") {
      as.numeric(difftime(max(xmax), min(xmin), units = "secs"))
    } else {
      max(xmax) - min(xmin)
    }
  }

  # With free per-panel x-axes (an absolute-time cohort), the visual gap must
  # be sized against each panel's own span: sizing it against the whole
  # cohort's calendar span rendered every box of a months-apart cohort at many
  # times its true width, because each facet panel's axis only covers its own
  # case. Fixed/shared axes (single case, start-aligned cohort) keep one
  # global span — there the whole plot is a single panel-width.
  facet_by  <- opts$facet_by
  per_panel <- !is.null(facet_by) && facet_by %in% names(boxes) &&
    identical(opts$facet_scales %||% "free_x", "free_x")

  if (per_panel) {
    boxes <- boxes |>
      dplyr::group_by(.data[[facet_by]]) |>
      dplyr::mutate(.gap_span = span_in_x_units(xmin, xmax)) |>
      dplyr::ungroup()
  } else {
    boxes <- dplyr::mutate(boxes, .gap_span = span_in_x_units(xmin, xmax))
  }

  # Axis-break selection sees the widest single panel, not the sum of panel
  # spans plus the calendar dead time between cases. Without faceting this is
  # exactly the whole-timeline span, as before.
  total_span <- max(boxes$.gap_span)
  # Anchor for reference_lines' offset_hours: the case's first event. When a
  # synthetic before-first-state box exists it already carries the earliest
  # event timestamp, so min(boxes$xmin) covers both cases.
  first_event_time <- min(boxes$xmin)

  # Midline y for event points
  midline_y <- box_height / 2

  # Number of events, needed early: label logic influences the y-scale
  n_events <- nrow(events)

  # High-cardinality event-type bucketing — done before colour/shape scales
  # (and the point/legend layers that use them) are built, so "Other" is
  # what gets scaled and drawn, not the raw long tail.
  if (!is.null(event_type_top_n) && n_events > 0) {
    events$act_type <- bucket_top_n(events$act_type, event_type_top_n)
  }

  # Swimlanes: when active, point events already carry their per-lane y from
  # derive_point_events(); otherwise every event is drawn on the box midline.
  # Both the point layer and the ggrepel label layer draw from this one table
  # so labels attach to the same coordinates as the points.
  show_lane_axis <- lanes_active && n_events > 0 && "lane" %in% names(events)
  event_points   <- if (lanes_active) events else dplyr::mutate(events, y = midline_y)

  # Split terminal markers (zero-duration end states, e.g. "Closed") from
  # true stays — terminals render as a vertical marker, never as a box.
  term_boxes <- dplyr::filter(boxes, terminal)
  term_boxes$.gap_span <- NULL   # render-only helper; keep layer data clean
  boxes      <- dplyr::filter(boxes, !terminal)

  # Shrink each box's rendered xmax by a fixed amount so all gaps are the same
  # absolute width on screen. The gap is expressed as a proportion of the
  # box's own PANEL span (not each box's own width), ensuring consistency
  # regardless of how long individual stays are. Guard with pmax so a very
  # short box can never render with negative width. xmin_render (not xmin) is
  # the base: it staggers boxes whose predecessor was nudged over them after a
  # shared timestamp.
  boxes <- dplyr::mutate(
    boxes,
    .gap = .gap_span * box_gap_prop,
    xmax_render = xmin_render + pmax(
      as.numeric(xmax - xmin_render, units = "secs") - .gap,
      .gap   # minimum render width = one gap unit
    ),
    .gap_span = NULL,
    .gap      = NULL
  )

  # ── Colour scales ──────────────────────────────────────────────────────────
  state_levels <- unique(boxes$state)
  evt_levels   <- if (nrow(events) > 0) unique(events$act_type) else character(0)

  # Use caller-supplied palettes if provided, otherwise auto-generate
  state_colours <- state_palette %||%
    journey_palette(state_levels, "state", palette_style)
  evt_colours <- event_palette %||%
    journey_palette(evt_levels, "event", palette_style)

  # ── Assemble the geom layers in draw order ─────────────────────────────────
  # No global aes — each layer owns its data and mapping to keep layers
  # independent and swappable. Every layer's data frame carries whatever facet
  # variable was added upstream, so faceting splits them automatically.
  layers <- list()

  # ── Layer 1: state boxes ─────────────────────────────────────────────────
  # Uses xmax_render (= xmax minus a small gap proportion) so adjacent boxes
  # are visually separated. The gap is purely cosmetic — stored xmax/duration
  # values reflect the true interval.
  #
  # Interactive mode (Stage 7) swaps in ggiraph's geom_rect_interactive() with
  # a tooltip built from the TRUE (unrendered) xmin/xmax so a nudged/staggered
  # box's tooltip never overclaims — it must not overclaim an imputed end any
  # more than the show_duration label may.
  if (interactive) {
    box_tooltips <- dplyr::mutate(
      boxes,
      tooltip = paste0(
        state, "\n",
        format_duration(as.numeric(duration, units = "secs")),
        ifelse(end_inferred, " (end inferred)", ""), "\n",
        "Entry: ", .format_instant(xmin, x_scale), "\n",
        "Exit: ",  .format_instant(xmax, x_scale),
        ifelse(end_inferred, " (inferred)", "")
      )
    )
    layers <- c(layers, list(
      ggiraph::geom_rect_interactive(
        data = box_tooltips,
        ggplot2::aes(
          xmin    = xmin_render,
          xmax    = xmax_render,
          ymin    = ymin,
          ymax    = ymax,
          fill    = state,
          tooltip = tooltip
        ),
        colour    = NA,
        linewidth = 0,
        alpha     = 0.85
      )
    ))
  } else {
    layers <- c(layers, list(
      ggplot2::geom_rect(
        data = boxes,
        ggplot2::aes(
          xmin  = xmin_render,
          xmax  = xmax_render,
          ymin  = ymin,
          ymax  = ymax,
          fill  = state
        ),
        colour    = NA,    # no border needed — gap between boxes provides separation
        linewidth = 0,
        alpha     = 0.85
      )
    ))
  }

  # ── Layer 1a: duration labels ─────────────────────────────────────────────
  # Reserved y-range [box_height, 1.12*box_height] per the layout budget —
  # sits just above the band, never atop the boxes/events/labels below it.
  # Only non-terminal boxes get a label; end_inferred boxes (the imputed
  # final stay) are suffixed "+" so the label never overclaims a data-backed end.
  if (show_duration && nrow(boxes) > 0) {
    duration_labels <- dplyr::mutate(
      boxes,
      x_mid     = xmin_render + (xmax_render - xmin_render) / 2,
      dur_label = format_duration(as.numeric(duration, units = "secs")),
      dur_label = ifelse(end_inferred, paste0(dur_label, "+"), dur_label)
    )

    layers <- c(layers, list(
      ggplot2::geom_text(
        data = duration_labels,
        ggplot2::aes(x = x_mid, y = box_height * 1.04, label = dur_label),
        vjust  = 0,
        size   = 2.6,
        colour = "grey30"
      )
    ))
  }

  # ── Layer 1b: direct box labelling ────────────────────────────────────────
  # Nudged slightly off the event midline (box_height/2) so labels don't sit
  # directly under event points. check_overlap = TRUE silently drops
  # colliding labels rather than pulling in a new dependency for collision
  # avoidance — acceptable here because, unlike show_labels' event labels,
  # missing a box label is a minor readability loss, not a broken feature.
  if (label_boxes && nrow(boxes) > 0) {
    box_labels <- dplyr::mutate(
      boxes,
      x_mid = xmin_render + (xmax_render - xmin_render) / 2
    )

    layers <- c(layers, list(
      ggplot2::geom_text(
        data = box_labels,
        ggplot2::aes(x = x_mid, y = box_height / 2 + 0.06, label = state),
        size          = 2.6,
        check_overlap = TRUE
      )
    ))
  }

  # ── Layer 1c: ongoing-case indication ─────────────────────────────────────
  # Converse of the terminal-state marker: the case never reached a state
  # named in terminal_activities — the data feed just stopped. Marks the
  # final box's right edge as open-ended rather than implying its (inferred)
  # xmax is a known, true end. Data-driven (not annotate()) so it faces the
  # correct panel when faceted.
  #
  # Single-case: opts$case_open flags the one case. Cohort: opts$open_cases
  # lists the case ids whose case never reached a terminal state, and each
  # open case's final box gets the marker in its own facet panel.
  open_cases <- opts$open_cases
  if (!is.null(facet_by) && facet_by %in% names(boxes) &&
      length(open_cases) > 0) {
    final_box <- boxes |>
      dplyr::filter(.data[[facet_by]] %in% open_cases) |>
      dplyr::group_by(.data[[facet_by]]) |>
      dplyr::slice_tail(n = 1) |>
      dplyr::ungroup()
  } else if (case_open && nrow(boxes) > 0) {
    final_box <- dplyr::slice_tail(boxes, n = 1)
  } else {
    final_box <- NULL
  }

  if (!is.null(final_box) && nrow(final_box) > 0) {
    ongoing_label <- dplyr::mutate(final_box, y = box_height * 1.04)

    layers <- c(layers, list(
      ggplot2::geom_segment(
        data = final_box,
        ggplot2::aes(x = xmax, xend = xmax, y = ymin, yend = ymax),
        colour    = "grey25",
        linetype  = "dashed",
        linewidth = 0.8
      ),
      ggplot2::geom_text(
        data = ongoing_label,
        ggplot2::aes(x = xmax, y = y),
        label    = "(ongoing)",
        hjust    = 1,
        vjust    = 0,
        size     = 2.6,
        fontface = "italic",
        colour   = "grey25"
      )
    ))
  }

  # ── Layer 1d: reference / target-threshold lines ─────────────────────────
  # Reserved y-range [1.12*box_height, 1.3*box_height] per the layout budget —
  # sits above the duration-label row, never atop the boxes/events below it.
  # offset_hours is anchored to the first event: datetime mode adds seconds,
  # elapsed-hours mode adds hours directly.
  if (!is.null(reference_lines)) {
    ref_x <- if (x_scale == "datetime") {
      first_event_time + reference_lines$offset_hours * 3600
    } else {
      first_event_time + reference_lines$offset_hours
    }
    ref_lines <- dplyr::mutate(reference_lines, x = ref_x)

    layers <- c(layers, list(
      ggplot2::geom_vline(
        data      = ref_lines,
        ggplot2::aes(xintercept = x),
        colour    = "firebrick",
        linetype  = "dashed",
        linewidth = 0.5
      ),
      ggplot2::geom_text(
        data = ref_lines,
        ggplot2::aes(x = x, y = box_height * 1.14, label = label),
        hjust  = -0.05,
        vjust  = 0,
        size   = 2.8,
        colour = "firebrick"
      )
    ))
  }

  # ── Layer 2: terminal state markers ──────────────────────────────────────
  # A terminal state (e.g. "Closed") is an instant, not a stay: a vertical
  # bar at its timestamp with a direct label, outside the fill legend.
  if (nrow(term_boxes) > 0) {
    if (interactive) {
      term_tooltips <- dplyr::mutate(
        term_boxes,
        tooltip = paste0(state, "\nAt: ", .format_instant(xmin, x_scale))
      )
      layers <- c(layers, list(
        ggiraph::geom_segment_interactive(
          data = term_tooltips,
          ggplot2::aes(x = xmin, xend = xmin, y = ymin, yend = ymax, tooltip = tooltip),
          colour    = "grey25",
          linewidth = 1.1
        ),
        ggiraph::geom_text_interactive(
          data = term_tooltips,
          ggplot2::aes(x = xmin, y = ymax, label = state, tooltip = tooltip),
          hjust    = 1.1,
          vjust    = -0.6,
          size     = 3,
          fontface = "italic",
          colour   = "grey25"
        )
      ))
    } else {
      layers <- c(layers, list(
        ggplot2::geom_segment(
          data = term_boxes,
          ggplot2::aes(x = xmin, xend = xmin, y = ymin, yend = ymax),
          colour    = "grey25",
          linewidth = 1.1
        ),
        ggplot2::geom_text(
          data = term_boxes,
          ggplot2::aes(x = xmin, y = ymax, label = state),
          hjust    = 1.1,
          vjust    = -0.6,
          size     = 3,
          fontface = "italic",
          colour   = "grey25"
        )
      ))
    }
  }

  # ── Layer 3: instantaneous event points ──────────────────────────────────
  # Interactive mode gives every point (whether on the single midline or
  # stacked into swimlanes) a tooltip — the swimlane points get tooltips too,
  # per Stage 7.
  if (nrow(events) > 0) {
    if (interactive) {
      event_tooltips <- dplyr::mutate(
        event_points,
        tooltip = paste0(activity, "\n", act_type, "\n", .format_instant(x, x_scale))
      )
      layers <- c(layers, list(
        ggiraph::geom_point_interactive(
          data = event_tooltips,
          ggplot2::aes(
            x       = x,
            y       = y,
            colour  = act_type,
            shape   = act_type,
            tooltip = tooltip
          ),
          size   = 3,
          stroke = 0.8
        )
      ))
    } else {
      layers <- c(layers, list(
        ggplot2::geom_point(
          data = event_points,
          ggplot2::aes(
            x      = x,
            y      = y,
            colour = act_type,
            shape  = act_type
          ),
          size   = 3,
          stroke = 0.8
        )
      ))
    }
  }

  # ── Layer 4: optional event labels via ggrepel ────────────────────────────
  labels_will_render <- show_labels && n_events > 0 && n_events <= label_max

  if (show_labels && n_events > label_max) {
    cli::cli_inform(c(
      "!" = "{n_events} events exceed {.arg label_max} ({label_max}); labels suppressed.",
      "i" = "Increase {.arg label_max} or use {.arg exclude_categories} to reduce event count."
    ))
  }

  if (labels_will_render) {
    layers <- c(layers, list(
      ggrepel::geom_text_repel(
        data = event_points,
        ggplot2::aes(x = x, y = y, label = activity),
        size          = 2.8,
        direction     = "y",
        nudge_y       = -box_height * 0.7,
        segment.size  = 0.3,
        segment.color = "grey50",
        max.overlaps  = Inf,   # the user asked for labels; show them all
        colour        = "grey20",
        # Fixed seed so label placement is reproducible run-to-run — ggrepel's
        # repulsion is stochastic, which otherwise makes the plot (and its
        # vdiffr baseline) non-deterministic.
        seed          = 42
      )
    ))
  }

  # Lane-axis breaks/labels are computed from the (possibly bucketed) events so
  # the assembler can label each lane at its band centre.
  lane_axis <- if (show_lane_axis) {
    events |>
      dplyr::distinct(lane, y) |>
      dplyr::arrange(y)
  } else {
    NULL
  }

  list(
    layers = layers,
    meta   = list(
      state_colours      = state_colours,
      evt_colours        = evt_colours,
      evt_levels         = evt_levels,
      n_events           = n_events,
      show_lane_axis     = show_lane_axis,
      lane_axis          = lane_axis,
      labels_will_render = labels_will_render,
      x_scale            = x_scale,
      total_span         = total_span
    )
  )
}


# ── render_journey_plot ─────────────────────────────────────────────────────
#
# Assemble the finished ggplot: geom layers from journey_layers(), then the
# x-scale (datetime or elapsed-hours), y-scale, optional facet, colour/shape
# scales, and theme. Returns a ggplot ready for display.
#
# opts$facet_by (default NULL) names a column present in every layer's data on
# which to facet_wrap — set by plot_cohort_timeline(); NULL leaves a single
# panel, byte-identical to the pre-Stage-5 single-case output.
render_journey_plot <- function(boxes, events, opts) {

  x_scale     <- opts$x_scale %||% "datetime"
  box_height  <- opts$box_height
  plot_title  <- opts$title
  state_label <- opts$state_label %||% "State"
  facet_by    <- opts$facet_by

  # ── Geom layers + the metadata the scales/theme need ───────────────────────
  jl    <- journey_layers(boxes, events, opts)
  meta  <- jl$meta

  p <- ggplot2::ggplot() + jl$layers

  # ── x-scale: datetime instants, or numeric elapsed hours ───────────────────
  if (x_scale == "datetime") {
    x_scale_layer <- ggplot2::scale_x_datetime(
      date_breaks = choose_date_breaks(meta$total_span),
      date_labels = choose_date_labels(meta$total_span),
      expand      = ggplot2::expansion(mult = 0.02)
    )
  } else {
    x_scale_layer <- ggplot2::scale_x_continuous(
      labels = function(x) paste0("+", x, "h"),
      expand = ggplot2::expansion(mult = 0.02)
    )
  }

  # ── y-scale ────────────────────────────────────────────────────────────────
  # No hard y limits: with limits = c(0, box_height), labels nudged below the
  # band were censored to NA and silently dropped — every label vanished.
  # Instead, expand the lower range only when labels are actually rendered.
  y_expand_lower <- if (meta$labels_will_render) 1.2 else 0.05

  # With swimlanes active the y-axis carries meaning: label each lane at its
  # band centre. Without lanes the axis stays unlabelled (single timeline).
  if (meta$show_lane_axis) {
    y_scale <- ggplot2::scale_y_continuous(
      breaks = meta$lane_axis$y,
      labels = as.character(meta$lane_axis$lane),
      expand = ggplot2::expansion(mult = c(y_expand_lower, 0.15))
    )
  } else {
    y_scale <- ggplot2::scale_y_continuous(
      expand = ggplot2::expansion(mult = c(y_expand_lower, 0.15))
    )
  }

  p <- p +
    x_scale_layer +
    y_scale +
    ggplot2::scale_fill_manual(
      values = meta$state_colours,
      name   = state_label
    )

  # Only add colour/shape scales if there are events to render
  if (meta$n_events > 0) {
    # Use a fixed set of shapes that are distinguishable when printed in B&W
    n_shapes <- length(meta$evt_levels)
    shape_vals <- c(16, 17, 15, 18, 1, 2, 0, 5, 8, 4)[seq_len(min(n_shapes, 10))]
    if (n_shapes > 10) {
      shape_vals <- rep(shape_vals, length.out = n_shapes)
    }

    p <- p +
      ggplot2::scale_colour_manual(
        values = meta$evt_colours,
        name   = "Event type"
      ) +
      ggplot2::scale_shape_manual(
        values = shape_vals,
        name   = "Event type"
      )
  }

  # ── Optional cohort faceting ───────────────────────────────────────────────
  # facet_scales is "free_x" for absolute-time cohorts (each case keeps its own
  # date range) and "fixed" for start-aligned cohorts (compared on one shared
  # elapsed-hours axis). NULL facet_by → single panel, unchanged.
  if (!is.null(facet_by)) {
    p <- p +
      ggplot2::facet_wrap(
        ggplot2::vars(.data[[facet_by]]),
        scales = opts$facet_scales %||% "free_x",
        ncol   = opts$ncol
      )
  }

  # ── Theme ─────────────────────────────────────────────────────────────────
  # Swimlanes turn the y-axis into a meaningful lane index, so its text/ticks
  # become visible only then; a single-lane timeline keeps them blank.
  axis_text_y  <- if (meta$show_lane_axis) {
    ggplot2::element_text(size = 8, colour = "grey30")
  } else {
    ggplot2::element_blank()
  }
  axis_ticks_y <- if (meta$show_lane_axis) {
    ggplot2::element_line(colour = "grey80", linewidth = 0.3)
  } else {
    ggplot2::element_blank()
  }

  p <- p +
    theme_timeline(base_size = 11) +
    ggplot2::theme(
      # y-axis carries no meaningful information in a single-lane timeline,
      # but names each lane when swimlanes are active
      axis.title.y  = ggplot2::element_blank(),
      axis.text.y   = axis_text_y,
      axis.ticks.y  = axis_ticks_y,
      # Legends — stacked vertically: two side-by-side legends overflow the
      # plot width at realistic category counts, clipping titles and entries
      legend.position  = "bottom",
      legend.box       = "vertical",
      legend.margin    = ggplot2::margin(t = 2, b = 0),
      legend.box.margin = ggplot2::margin(0, 0, 0, 0),
      legend.title     = ggplot2::element_text(size = 9, face = "bold"),
      legend.text      = ggplot2::element_text(size = 8),
      plot.subtitle    = ggplot2::element_text(size = 9,  colour = "grey40"),
      # Extra breathing room at the bottom for ggrepel labels
      plot.margin      = ggplot2::margin(8, 12, 8, 8)
    ) +
    ggplot2::labs(
      title    = plot_title,
      x        = NULL
    )

  p
}
