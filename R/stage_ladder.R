# stage_ladder.R — Staircase view of a linear stage process (Stage 5b)
#
# The band layout (plot_patient_journey()) answers "what happened when" by
# putting time on the x-axis and a single location band on the y-axis. For a
# strictly linear process — a complaint moving Acknowledgement -> Triage -> ...
# -> Formal letter sent, a purchase order raised -> approved -> fulfilled — the
# more compelling question is "where does the time go", which wants the stage on
# the y-axis. plot_stage_ladder() draws exactly that: one horizontal segment per
# stage, first stage at the top, so the case walks down-and-to-the-right like a
# Gantt chart, with thin grey connectors forming the staircase.
#
# It never re-derives box geometry: stages ARE boxes, so it calls the same
# derive_location_boxes() the band layout uses. Only the rendering differs.


# ── plot_stage_ladder ──────────────────────────────────────────────────────────
#
# stage_categories names the act_type value(s) marking a stage entry (the direct
# analogue of location_categories). stage_order pins the vertical order; NULL
# uses first appearance. stage_targets is a named numeric vector mapping a stage
# name to its allowed dwell in hours — rendered as a light band from stage entry
# to entry+target, with any excess dwell drawn in firebrick.
plot_stage_ladder <- function(
    data, case_id,
    stage_categories,
    stage_order = NULL,

    time_col     = "timestamp",
    act_type_col = "act_type",
    activity_col = "activity",
    case_col     = "caseID",
    patient_col  = NULL,

    tz = "UTC",
    terminal_activities = NULL,
    stage_targets = NULL,

    show_duration = TRUE,

    palette_style    = c("okabe", "brewer"),
    location_palette = NULL,
    tail_strategy    = "last_event",
    title            = NULL,
    return_data      = FALSE
) {

  palette_style <- match.arg(palette_style)

  cols <- list(
    time     = time_col,
    act_type = act_type_col,
    activity = activity_col,
    case     = case_col,
    patient  = patient_col,
    lane     = NULL
  )

  # ── Validate + derive stage boxes through the shared pipeline ──────────────
  spell <- validate_event_log(data, cols, case_id, stage_categories, tz = tz)

  boxes <- derive_location_boxes(
    spell, cols, stage_categories,
    box_height          = 1,   # irrelevant: ladder overrides y with stage rank
    tail_strategy       = tail_strategy,
    terminal_activities = terminal_activities
  )
  boxes <- dplyr::rename(boxes, stage = location)

  # ── Resolve the vertical stage ordering ────────────────────────────────────
  present <- unique(boxes$stage)
  if (is.null(stage_order)) {
    stage_levels <- present            # first-appearance order
  } else {
    unknown <- setdiff(present, stage_order)
    if (length(unknown) > 0) {
      cli::cli_abort(c(
        "{.arg stage_order} does not list every stage present in the data.",
        "x" = "Missing from {.arg stage_order}: {.val {unknown}}",
        "i" = "Present stages: {.val {present}}"
      ))
    }
    stage_levels <- intersect(stage_order, present)  # keep the caller's order
  }
  n_stages <- length(stage_levels)

  # First stage at the TOP: rank 1 -> highest y so the case descends the ladder.
  boxes$stage_rank <- match(boxes$stage, stage_levels)
  boxes$y          <- n_stages - boxes$stage_rank + 1

  # ── Colours: one hue per stage (shared by segments and points) ─────────────
  stage_colours <- location_palette %||%
    journey_palette(stage_levels, "location", palette_style)

  seg_boxes  <- dplyr::filter(boxes, !terminal)
  term_boxes <- dplyr::filter(boxes, terminal)

  if (is.null(title)) {
    title <- if (is.null(cols$patient)) {
      paste0("Case ", case_id)
    } else {
      paste0("Patient ", spell[[cols$patient]][1], " — Spell ", case_id)
    }
  }

  # ── Base plot ──────────────────────────────────────────────────────────────
  half <- 0.30   # half-height of the target-band rectangles, in y (rank) units
  p <- ggplot2::ggplot()

  # ── Layer: staircase connectors ────────────────────────────────────────────
  # Between consecutive stages in time order, a thin grey elbow: horizontal from
  # the previous stage's end to the next stage's start (they are contiguous, so
  # this is a point) then vertical down to the next stage's row. Drawn first so
  # the coloured stage segments sit on top.
  if (nrow(boxes) > 1) {
    ordered <- boxes[order(boxes$xmin), ]
    connectors <- dplyr::tibble(
      x    = ordered$xmax[-nrow(ordered)],
      y    = ordered$y[-nrow(ordered)],
      yend = ordered$y[-1]
    )
    p <- p +
      ggplot2::geom_segment(
        data = connectors,
        ggplot2::aes(x = x, xend = x, y = y, yend = yend),
        colour    = "grey70",
        linewidth = 0.4
      )
  }

  # ── Layer: per-stage target bands (one band layer per targeted stage) ──────
  # A light band from stage entry to entry + target hours on that stage's row;
  # dwell beyond the target is redrawn in firebrick (the per-stage breach made
  # visual). One geom_rect layer is added per targeted stage, as specified.
  if (!is.null(stage_targets)) {
    if (is.null(names(stage_targets)) || any(names(stage_targets) == "")) {
      cli::cli_abort(c(
        "{.arg stage_targets} must be a named numeric vector (stage -> hours).",
        "i" = "Example: {.code c('Under review' = 168)} for a one-week target."
      ))
    }
    unknown_targets <- setdiff(names(stage_targets), stage_levels)
    if (length(unknown_targets) > 0) {
      suggestions <- suggest_matches(unknown_targets, stage_levels)
      hint <- if (length(suggestions) > 0) {
        cli::format_inline("Did you mean {.val {suggestions}}?")
      } else {
        cli::format_inline("Known stages: {.val {stage_levels}}")
      }
      cli::cli_abort(c(
        "{.arg stage_targets} names stage(s) not present: {.val {unknown_targets}}.",
        "i" = hint
      ))
    }

    # Excess-dwell segments are collected here and drawn AFTER the coloured
    # stage segments so the breach shows on top of its stage's own hue.
    excess_layers <- list()

    for (stg in names(stage_targets)) {
      row <- seg_boxes[seg_boxes$stage == stg, ]
      if (nrow(row) == 0) next   # stage present only as a terminal marker
      target_secs <- stage_targets[[stg]] * 3600
      band <- dplyr::tibble(
        xmin = row$xmin[1],
        xmax = row$xmin[1] + target_secs,
        ymin = row$y[1] - half,
        ymax = row$y[1] + half
      )
      p <- p +
        ggplot2::geom_rect(
          data = band,
          ggplot2::aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
          fill = "grey85", alpha = 0.6
        )

      # Excess dwell beyond the target, in firebrick (deferred to draw on top).
      dwell_secs <- as.numeric(row$xmax[1] - row$xmin[1], units = "secs")
      if (!row$end_inferred[1] && dwell_secs > target_secs) {
        excess <- dplyr::tibble(
          x    = row$xmin[1] + target_secs,
          xend = row$xmax[1],
          y    = row$y[1]
        )
        excess_layers <- c(excess_layers, list(
          ggplot2::geom_segment(
            data = excess,
            ggplot2::aes(x = x, xend = xend, y = y, yend = y),
            colour    = "firebrick",
            linewidth = 4,
            lineend   = "butt"
          )
        ))
      }
    }
  } else {
    excess_layers <- list()
  }

  # ── Layer: the stage segments themselves ───────────────────────────────────
  if (nrow(seg_boxes) > 0) {
    p <- p +
      ggplot2::geom_segment(
        data = seg_boxes,
        ggplot2::aes(x = xmin, xend = xmax, y = y, yend = y, colour = stage),
        linewidth = 4,
        lineend   = "round"
      )
  }

  # Breach excess sits on top of its stage's coloured segment.
  p <- p + excess_layers

  # ── Layer: terminal stage as a point marker (not a segment) ────────────────
  if (nrow(term_boxes) > 0) {
    p <- p +
      ggplot2::geom_point(
        data = term_boxes,
        ggplot2::aes(x = xmin, y = y, colour = stage),
        size = 4, shape = 18
      )
  }

  # ── Layer: duration labels at each segment midpoint ────────────────────────
  # end_inferred segments get a "+" suffix (the end is imputed); terminal stages
  # are instantaneous and carry no duration label.
  if (show_duration && nrow(seg_boxes) > 0) {
    dur <- dplyr::mutate(
      seg_boxes,
      x_mid     = xmin + (xmax - xmin) / 2,
      dur_label = format_duration(as.numeric(duration, units = "secs")),
      dur_label = ifelse(end_inferred, paste0(dur_label, "+"), dur_label)
    )
    p <- p +
      ggplot2::geom_text(
        data = dur,
        ggplot2::aes(x = x_mid, y = y + 0.28, label = dur_label),
        size = 2.6, colour = "grey30", vjust = 0
      )
  }

  # ── Scales + theme ─────────────────────────────────────────────────────────
  total_span_secs <- as.numeric(
    difftime(max(boxes$xmax), min(boxes$xmin), units = "secs")
  )

  p <- p +
    ggplot2::scale_x_datetime(
      date_breaks = choose_date_breaks(total_span_secs),
      date_labels = choose_date_labels(total_span_secs),
      expand      = ggplot2::expansion(mult = 0.04)
    ) +
    ggplot2::scale_y_continuous(
      breaks = n_stages - seq_len(n_stages) + 1,
      labels = stage_levels,
      expand = ggplot2::expansion(mult = c(0.08, 0.12))
    ) +
    ggplot2::scale_colour_manual(values = stage_colours, guide = "none") +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      axis.title.y       = ggplot2::element_blank(),
      axis.text.y        = ggplot2::element_text(size = 9, colour = "grey20"),
      panel.grid.major.y = ggplot2::element_blank(),
      panel.grid.minor.y = ggplot2::element_blank(),
      panel.grid.minor.x = ggplot2::element_blank(),
      panel.grid.major.x = ggplot2::element_line(colour = "grey88", linewidth = 0.4),
      plot.title         = ggplot2::element_text(size = 12, face = "bold", hjust = 0),
      plot.margin        = ggplot2::margin(8, 14, 8, 8)
    ) +
    ggplot2::labs(title = title, x = NULL)

  if (return_data) {
    list(plot = p, boxes = boxes)
  } else {
    p
  }
}
