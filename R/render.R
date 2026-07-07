# render.R — ggplot2 rendering layer
#
# render_journey_plot() is the only function in the codebase that touches ggplot.
# It consumes the two tidy tables produced by build_journey_tables() and an opts
# list from the public function, and returns a ggplot object ready for display
# or further customisation.
#
# Because all data shaping is done upstream, swapping this for a plotly/ggiraph
# renderer is a matter of writing a sibling function consuming the same tables.


render_journey_plot <- function(boxes, events, opts) {

  # ── Unpack opts ────────────────────────────────────────────────────────────
  show_labels      <- opts$show_labels
  label_max        <- opts$label_max
  show_duration    <- opts$show_duration
  label_boxes      <- opts$label_boxes
  reference_lines  <- opts$reference_lines
  event_type_top_n <- opts$event_type_top_n
  spell_open       <- opts$spell_open %||% FALSE
  location_palette <- opts$location_palette
  event_palette    <- opts$event_palette
  palette_style    <- opts$palette_style
  box_height       <- opts$box_height
  box_gap_prop     <- opts$box_gap_prop
  plot_title       <- opts$title

  # ── Derived layout values ──────────────────────────────────────────────────
  total_span_secs <- as.numeric(
    difftime(max(boxes$xmax), min(boxes$xmin), units = "secs")
  )
  # Anchor for reference_lines' offset_hours: the spell's first event. When a
  # synthetic pre-admission box exists it already carries the earliest event
  # timestamp, so min(boxes$xmin) covers both cases.
  first_event_time <- min(boxes$xmin)
  date_breaks <- choose_date_breaks(total_span_secs)
  date_labels <- choose_date_labels(total_span_secs)

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

  # Split terminal markers (zero-duration end states, e.g. "Discharged") from
  # true stays — terminals render as a vertical marker, never as a box.
  term_boxes <- dplyr::filter(boxes, terminal)
  boxes      <- dplyr::filter(boxes, !terminal)

  # Shrink each box's rendered xmax by a fixed number of seconds so all gaps
  # are the same absolute width on screen. The gap is expressed as a proportion
  # of the TOTAL journey span (not each box's own width), ensuring consistency
  # regardless of how long individual stays are.
  # Guard with pmax so a very short box can never render with negative width.
  # xmin_render (not xmin) is the base: it staggers boxes whose predecessor
  # was nudged over them after a shared timestamp.
  gap_secs <- total_span_secs * box_gap_prop
  boxes <- dplyr::mutate(
    boxes,
    xmax_render = xmin_render + pmax(
      as.numeric(xmax - xmin_render, units = "secs") - gap_secs,
      gap_secs   # minimum render width = one gap unit
    )
  )

  # ── Colour scales ──────────────────────────────────────────────────────────
  loc_levels <- unique(boxes$location)
  evt_levels <- if (nrow(events) > 0) unique(events$act_type) else character(0)

  # Use caller-supplied palettes if provided, otherwise auto-generate
  loc_colours <- location_palette %||%
    journey_palette(loc_levels, "location", palette_style)
  evt_colours <- event_palette %||%
    journey_palette(evt_levels, "event", palette_style)

  # ── Base plot ──────────────────────────────────────────────────────────────
  # No global aes — each layer owns its data and mapping to keep layers
  # independent and swappable. x is datetime, y is a fixed [0, box_height] band.
  p <- ggplot2::ggplot() +

    # ── Layer 1: location boxes ──────────────────────────────────────────────
    # Uses xmax_render (= xmax minus a small gap proportion) so adjacent boxes
    # are visually separated. The gap is purely cosmetic — stored xmax/duration
    # values reflect the true clinical interval.
    ggplot2::geom_rect(
      data = boxes,
      ggplot2::aes(
        xmin  = xmin_render,
        xmax  = xmax_render,
        ymin  = ymin,
        ymax  = ymax,
        fill  = location
      ),
      colour    = NA,    # no border needed — gap between boxes provides separation
      linewidth = 0,
      alpha     = 0.85
    )

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

    p <- p +
      ggplot2::geom_text(
        data = duration_labels,
        ggplot2::aes(x = x_mid, y = box_height * 1.04, label = dur_label),
        vjust  = 0,
        size   = 2.6,
        colour = "grey30"
      )
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

    p <- p +
      ggplot2::geom_text(
        data = box_labels,
        ggplot2::aes(x = x_mid, y = box_height / 2 + 0.06, label = location),
        size          = 2.6,
        check_overlap = TRUE
      )
  }

  # ── Layer 1c: ongoing-spell indication ────────────────────────────────────
  # Converse of the terminal-state marker: the case never reached a state
  # named in terminal_activities — the data feed just stopped. Marks the
  # final box's right edge as open-ended rather than implying its (inferred)
  # xmax is a known, true end.
  if (spell_open && nrow(boxes) > 0) {
    final_box <- dplyr::slice_tail(boxes, n = 1)

    p <- p +
      ggplot2::geom_segment(
        data = final_box,
        ggplot2::aes(x = xmax, xend = xmax, y = ymin, yend = ymax),
        colour    = "grey25",
        linetype  = "dashed",
        linewidth = 0.8
      ) +
      ggplot2::annotate(
        "text",
        x        = final_box$xmax,
        y        = box_height * 1.04,
        label    = "(ongoing)",
        hjust    = 1,
        vjust    = 0,
        size     = 2.6,
        fontface = "italic",
        colour   = "grey25"
      )
  }

  # ── Layer 1d: reference / target-threshold lines ─────────────────────────
  # Reserved y-range [1.12*box_height, 1.3*box_height] per the layout budget —
  # sits above the duration-label row, never atop the boxes/events below it.
  if (!is.null(reference_lines)) {
    ref_lines <- dplyr::mutate(
      reference_lines,
      x = first_event_time + offset_hours * 3600
    )

    p <- p +
      ggplot2::geom_vline(
        data      = ref_lines,
        ggplot2::aes(xintercept = x),
        colour    = "firebrick",
        linetype  = "dashed",
        linewidth = 0.5
      ) +
      ggplot2::geom_text(
        data = ref_lines,
        ggplot2::aes(x = x, y = box_height * 1.14, label = label),
        hjust  = -0.05,
        vjust  = 0,
        size   = 2.8,
        colour = "firebrick"
      )
  }

  # ── Layer 2: terminal state markers ──────────────────────────────────────
  # A terminal state (e.g. "Discharged") is an instant, not a stay: a vertical
  # bar at its timestamp with a direct label, outside the fill legend.
  if (nrow(term_boxes) > 0) {
    p <- p +
      ggplot2::geom_segment(
        data = term_boxes,
        ggplot2::aes(x = xmin, xend = xmin, y = ymin, yend = ymax),
        colour    = "grey25",
        linewidth = 1.1
      ) +
      ggplot2::geom_text(
        data = term_boxes,
        ggplot2::aes(x = xmin, y = ymax, label = location),
        hjust    = 1.1,
        vjust    = -0.6,
        size     = 3,
        fontface = "italic",
        colour   = "grey25"
      )
  }

  # ── Layer 3: instantaneous event points ──────────────────────────────────
  if (nrow(events) > 0) {
    p <- p +
      ggplot2::geom_point(
        data = dplyr::mutate(events, y = midline_y),
        ggplot2::aes(
          x      = x,
          y      = y,
          colour = act_type,
          shape  = act_type
        ),
        size   = 3,
        stroke = 0.8
      )
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
    p <- p +
      ggrepel::geom_text_repel(
        data = dplyr::mutate(events, y = midline_y),
        ggplot2::aes(x = x, y = y, label = activity),
        size          = 2.8,
        direction     = "y",
        nudge_y       = -box_height * 0.7,
        segment.size  = 0.3,
        segment.color = "grey50",
        max.overlaps  = Inf,   # the user asked for labels; show them all
        colour        = "grey20"
      )
  }

  # ── Scales ────────────────────────────────────────────────────────────────
  # No hard y limits: with limits = c(0, box_height), labels nudged below the
  # band were censored to NA and silently dropped — every label vanished.
  # Instead, expand the lower range only when labels are actually rendered.
  y_expand_lower <- if (labels_will_render) 1.2 else 0.05

  p <- p +
    ggplot2::scale_x_datetime(
      date_breaks = date_breaks,
      date_labels = date_labels,
      expand      = ggplot2::expansion(mult = 0.02)
    ) +
    ggplot2::scale_y_continuous(
      expand = ggplot2::expansion(mult = c(y_expand_lower, 0.15))
    ) +
    ggplot2::scale_fill_manual(
      values = loc_colours,
      name   = "Location"
    )

  # Only add colour/shape scales if there are events to render
  if (nrow(events) > 0) {
    # Use a fixed set of shapes that are distinguishable when printed in B&W
    n_shapes <- length(evt_levels)
    shape_vals <- c(16, 17, 15, 18, 1, 2, 0, 5, 8, 4)[seq_len(min(n_shapes, 10))]
    if (n_shapes > 10) {
      shape_vals <- rep(shape_vals, length.out = n_shapes)
    }

    p <- p +
      ggplot2::scale_colour_manual(
        values = evt_colours,
        name   = "Event type"
      ) +
      ggplot2::scale_shape_manual(
        values = shape_vals,
        name   = "Event type"
      )
  }

  # ── Theme ─────────────────────────────────────────────────────────────────
  p <- p +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      # y-axis carries no meaningful information in a single-lane timeline
      axis.title.y  = ggplot2::element_blank(),
      axis.text.y   = ggplot2::element_blank(),
      axis.ticks.y  = ggplot2::element_blank(),
      # Keep only vertical gridlines for time reference; horizontal are noise
      panel.grid.major.y = ggplot2::element_blank(),
      panel.grid.minor.y = ggplot2::element_blank(),
      panel.grid.minor.x = ggplot2::element_blank(),
      panel.grid.major.x = ggplot2::element_line(colour = "grey88", linewidth = 0.4),
      # Legends — stacked vertically: two side-by-side legends overflow the
      # plot width at realistic category counts, clipping titles and entries
      legend.position  = "bottom",
      legend.box       = "vertical",
      legend.margin    = ggplot2::margin(t = 2, b = 0),
      legend.box.margin = ggplot2::margin(0, 0, 0, 0),
      legend.title     = ggplot2::element_text(size = 9, face = "bold"),
      legend.text      = ggplot2::element_text(size = 8),
      # Title
      plot.title       = ggplot2::element_text(size = 12, face = "bold", hjust = 0),
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
