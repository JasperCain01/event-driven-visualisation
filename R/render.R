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
  location_palette <- opts$location_palette
  event_palette    <- opts$event_palette
  box_height       <- opts$box_height
  plot_title       <- opts$title

  # ── Derived layout values ──────────────────────────────────────────────────
  total_span_secs <- as.numeric(
    difftime(max(boxes$xmax), min(boxes$xmin), units = "secs")
  )
  date_breaks <- choose_date_breaks(total_span_secs)
  date_labels <- choose_date_labels(total_span_secs)

  # Midline y for event points: slightly below centre so location labels sit above
  midline_y    <- box_height * 0.45
  label_y      <- box_height * 0.82  # y for location name text inside box

  # ── Colour scales ──────────────────────────────────────────────────────────
  loc_levels <- unique(boxes$location)
  evt_levels <- if (nrow(events) > 0) unique(events$act_type) else character(0)

  # Use caller-supplied palettes if provided, otherwise auto-generate
  loc_colours <- location_palette %||% journey_palette(loc_levels, "location")
  evt_colours <- event_palette    %||% journey_palette(evt_levels, "event")

  # ── Base plot ──────────────────────────────────────────────────────────────
  # No global aes — each layer owns its data and mapping to keep layers
  # independent and swappable. x is datetime, y is a fixed [0, box_height] band.
  p <- ggplot2::ggplot() +

    # ── Layer 1: location boxes ──────────────────────────────────────────────
    # geom_rect needs xmin/xmax as numeric for datetime axes — coerce inline.
    # Trade-off: ggplot2's datetime handling for geom_rect requires this;
    # coercing here keeps box data as POSIXct everywhere else.
    ggplot2::geom_rect(
      data = boxes,
      ggplot2::aes(
        xmin  = xmin,
        xmax  = xmax,
        ymin  = ymin,
        ymax  = ymax,
        fill  = location
      ),
      colour = "grey40",   # thin border separates adjacent same-coloured boxes
      linewidth = 0.3,
      alpha  = 0.82
    ) +

    # ── Layer 2: location name labels ────────────────────────────────────────
    # Placed at the top of the box (label_y) so they don't clash with midline
    # event points. Long names are clipped by the box edge — a future extension
    # could use ggfittext for shrink-to-fit behaviour.
    ggplot2::geom_text(
      data = boxes,
      ggplot2::aes(
        x     = xmin + (xmax - xmin) / 2,
        y     = label_y,
        label = location
      ),
      size     = 3.2,
      fontface = "bold",
      colour   = "grey15",
      vjust    = 0.5
    )

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
  n_events <- nrow(events)

  if (show_labels && n_events > 0) {
    if (n_events > label_max) {
      cli::cli_inform(c(
        "!" = "{n_events} events exceed {.arg label_max} ({label_max}); labels suppressed.",
        "i" = "Increase {.arg label_max} or use {.arg exclude_categories} to reduce event count."
      ))
    } else {
      p <- p +
        ggrepel::geom_text_repel(
          data = dplyr::mutate(events, y = midline_y),
          ggplot2::aes(x = x, y = y, label = activity),
          size          = 2.8,
          direction     = "y",
          nudge_y       = -0.18,
          segment.size  = 0.3,
          segment.color = "grey50",
          max.overlaps  = 20,
          colour        = "grey20"
        )
    }
  }

  # ── Scales ────────────────────────────────────────────────────────────────
  p <- p +
    ggplot2::scale_x_datetime(
      date_breaks = date_breaks,
      date_labels = date_labels,
      expand      = ggplot2::expansion(mult = 0.02)
    ) +
    ggplot2::scale_y_continuous(
      limits = c(0, box_height),
      expand = ggplot2::expansion(mult = c(0.05, 0.15))
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
      # Legends
      legend.position  = "bottom",
      legend.box       = "horizontal",
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
