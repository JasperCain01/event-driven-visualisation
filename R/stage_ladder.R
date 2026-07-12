# stage_ladder.R — Staircase view of a linear stage process (Stage 5b)
#
# The band layout (plot_case_timeline()) answers "what happened when" by
# putting time on the x-axis and a single state band on the y-axis. For a
# strictly linear process — a complaint moving Acknowledgement -> Triage -> ...
# -> Formal letter sent, a purchase order raised -> approved -> fulfilled — the
# more compelling question is "where does the time go", which wants the stage on
# the y-axis. plot_stage_ladder() draws exactly that: one horizontal segment per
# stage, first stage at the top, so the case walks down-and-to-the-right like a
# Gantt chart, with thin grey connectors forming the staircase.
#
# It never re-derives box geometry: stages ARE boxes, so it calls the same
# derive_state_boxes() the band layout uses. Only the rendering differs.


# ── plot_stage_ladder ──────────────────────────────────────────────────────────
#
#' Visualise a linear stage process as a staircase
#'
#' For a strictly linear process (a complaint moving through fixed stages, a
#' purchase order raised then approved then fulfilled), the compelling
#' question is "where does the time go" — this puts stage on the y-axis (first
#' stage at the top) and draws one horizontal segment per stage, with thin
#' grey connectors forming a staircase as the case walks down-and-right like a
#' Gantt chart. It reuses the same box derivation [plot_case_timeline()]
#' uses; only the rendering differs.
#'
#' @param data A data frame or tibble containing the event log.
#' @param state_events Character vector of `act_type` value(s) marking a
#'   stage entry. Required — no default; see [plot_case_timeline()] for the
#'   discovery-error behaviour when omitted.
#' @param case_id The single case identifier to visualise, or `NULL` — see
#'   [plot_case_timeline()] for the resolution rules.
#' @param stage_order Character vector pinning the vertical stage order, or
#'   `NULL` (default) to use first-appearance order. Every stage present in
#'   the data must appear in `stage_order` if supplied.
#' @param time_col,act_type_col,activity_col,case_col Column-name mappings,
#'   as in [plot_case_timeline()]. `case_col` may be `NULL` for a single
#'   unnamed series (`case_id` must then also be `NULL`).
#' @param schema An [event_log_schema()] object, the literal string
#'   `"auto"`, or `NULL` — see [plot_case_timeline()].
#' @param tz Timezone used when parsing character timestamps.
#' @param terminal_activities Character vector of terminal `activity` values.
#' @param stage_targets Named numeric vector mapping a stage name to its
#'   allowed dwell in hours, rendered as a light band from stage entry to
#'   entry + target; dwell beyond it is drawn in firebrick. When a case
#'   revisits a stage, every visit is banded against the same target
#'   ([summarise_breach_rate()] instead sums a case's visits into one total
#'   dwell). An open (end-inferred) stage draws only its *proven* excess —
#'   dwell observed up to the last recorded event, never the imputed end.
#'   `NULL` = no targets shown.
#' @param show_duration Logical; show a formatted duration label at each
#'   segment's midpoint.
#' @param palette_style Auto-palette style: `"okabe"` (default) or
#'   `"brewer"`.
#' @param state_palette Named character vector (stage -> hex colour)
#'   overriding the automatic palette, or `NULL`.
#' @param tail_strategy Strategy for inferring the final stage's end time.
#' @param title Plot title; `NULL` auto-generates `"Case <case_id>"` unless
#'   `case_col = NULL`.
#' @param return_data Logical; if `TRUE`, return `list(plot, boxes)` instead
#'   of just the plot.
#'
#' @return A `ggplot` object, or a list when `return_data = TRUE`.
#'
#' @examples
#' plot_stage_ladder(
#'   complaint_example, case_id = "CMP-01",
#'   state_events = "stage_change", case_col = "complaint_id"
#' )
#'
#' @export
plot_stage_ladder <- function(
    data,
    state_events,
    case_id     = NULL,
    stage_order = NULL,

    time_col     = "timestamp",
    act_type_col = "act_type",
    activity_col = "activity",
    case_col     = "case_id",

    schema = NULL,

    tz = "UTC",
    terminal_activities = NULL,
    stage_targets = NULL,

    show_duration = TRUE,

    palette_style = c("okabe", "brewer"),
    state_palette = NULL,
    tail_strategy = "last_event",
    title         = NULL,
    return_data   = FALSE
) {

  palette_style <- match.arg(palette_style)

  resolved <- resolve_entry_args(
    data, schema,
    state_events, missing(state_events),
    time_col,     missing(time_col),
    case_col,     missing(case_col),
    act_type_col, missing(act_type_col),
    activity_col, missing(activity_col)
  )
  state_events <- resolved$state_events
  time_col     <- resolved$time_col
  case_col     <- resolved$case_col
  act_type_col <- resolved$act_type_col
  activity_col <- resolved$activity_col

  cols <- list(
    time     = time_col,
    act_type = act_type_col,
    activity = activity_col,
    case     = case_col,
    lane     = NULL
  )

  # ── Validate + derive stage boxes through the shared pipeline ──────────────
  case_data <- validate_event_log(data, cols, case_id, state_events, tz = tz)
  case_id   <- attr(case_data, "case_id")

  boxes <- derive_state_boxes(
    case_data, cols, state_events,
    box_height          = 1,   # irrelevant: ladder overrides y with stage rank
    tail_strategy       = tail_strategy,
    terminal_activities = terminal_activities
  )
  boxes <- dplyr::rename(boxes, stage = state)

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
  stage_colours <- state_palette %||%
    journey_palette(stage_levels, "state", palette_style)

  seg_boxes  <- dplyr::filter(boxes, !terminal)
  term_boxes <- dplyr::filter(boxes, terminal)

  if (is.null(title) && !is.null(cols$case)) {
    title <- paste0("Case ", case_id)
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
      rows <- seg_boxes[seg_boxes$stage == stg, ]
      if (nrow(rows) == 0) next   # stage present only as a terminal marker
      target_secs <- stage_targets[[stg]] * 3600

      # One band per VISIT: a case can re-enter a stage (a ticket bounced
      # back to "In Progress"), and each visit is measured against the same
      # target. Still exactly one geom_rect layer per targeted stage — the
      # layer's data simply carries one row per visit. Note the numeric
      # counterpart differs by design: summarise_breach_rate() sums a case's
      # visits to a stage into one total dwell.
      band <- dplyr::tibble(
        xmin = rows$xmin,
        xmax = rows$xmin + target_secs,
        ymin = rows$y - half,
        ymax = rows$y + half
      )
      p <- p +
        ggplot2::geom_rect(
          data = band,
          ggplot2::aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
          fill = "grey85", alpha = 0.6
        )

      # Excess dwell beyond the target, in firebrick (deferred to draw on
      # top), for every breaching visit. An open (end_inferred) stage counts
      # only its PROVEN dwell: elapsed time up to the last observed event is
      # a lower bound, so a breach already visible is real and must show —
      # but the excess is capped at that last observed instant, so a
      # median/fixed-imputed end never inflates it.
      end_proven <- rows$xmax
      if (any(rows$end_inferred)) {
        last_observed <- max(case_data[[cols$time]])
        end_proven[rows$end_inferred] <-
          pmin(rows$xmax[rows$end_inferred], last_observed)
      }
      dwell_secs <- as.numeric(end_proven - rows$xmin, units = "secs")
      breached   <- dwell_secs > target_secs
      if (any(breached)) {
        excess <- dplyr::tibble(
          x    = rows$xmin[breached] + target_secs,
          xend = end_proven[breached],
          y    = rows$y[breached]
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
    theme_timeline(base_size = 11) +
    ggplot2::theme(
      axis.title.y = ggplot2::element_blank(),
      axis.text.y  = ggplot2::element_text(size = 9, colour = "grey20"),
      plot.margin  = ggplot2::margin(8, 14, 8, 8)
    ) +
    ggplot2::labs(title = title, x = NULL)

  if (return_data) {
    list(plot = p, boxes = boxes)
  } else {
    p
  }
}
