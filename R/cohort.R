# cohort.R — Cohort view via faceting
#
# plot_cohort_timeline() lays several cases out as a small-multiples grid, one
# facet panel per case, so cohorts can be compared at a glance. It is a distinct
# axis from swimlanes (Stage 4): swimlanes stack concurrent tracks *within* one
# case; the cohort view compares *across* cases via ggplot2::facet_wrap().
#
# It never re-implements box/event derivation: every case is run through the
# same validate_event_log() + build_journey_tables() pipeline the single-case
# path uses, the results are bound with a `case_id` column, and journey_layers()
# draws them. Two modes:
#   * absolute time  — facet_wrap(scales = "free_x"), each panel on its own
#                      datetime range;
#   * align_start    — every case rebased to elapsed hours from its own first
#                      state event, drawn on one shared numeric axis
#                      (scales = "fixed") so durations line up for comparison.


# ── Rebase one case's tables to elapsed hours from its first box ──────────────
#
# Converts the POSIXct x-position columns (xmin/xmax/xmin_render and event
# x/timestamp) to numeric hours measured from the case's earliest box start, so
# start-aligned cases share a "+Nh" axis. The `duration` column is deliberately
# left as a difftime: it feeds format_duration() for the duration labels and
# must keep true clock units, not be reinterpreted as hours.
#
# Always rebases events$x/timestamp, even when events has zero rows: hrs()
# is safe on an empty POSIXct vector (difftime() returns numeric(0)), and
# skipping the conversion left a case with no point events holding onto its
# original POSIXct type while every other case's events became numeric -
# dplyr::bind_rows() across cases then failed to reconcile the mismatched
# column types for align_start = TRUE cohorts.
.rebase_to_elapsed_hours <- function(boxes, events) {
  origin <- min(boxes$xmin)
  hrs <- function(x) as.numeric(difftime(x, origin, units = "hours"))

  boxes$xmin        <- hrs(boxes$xmin)
  boxes$xmax        <- hrs(boxes$xmax)
  boxes$xmin_render <- hrs(boxes$xmin_render)

  events$x         <- hrs(events$x)
  events$timestamp <- hrs(events$timestamp)

  list(boxes = boxes, events = events)
}


#' Visualise several cases as a faceted small-multiples grid
#'
#' Lays several cases out one facet panel per case, via
#' [ggplot2::facet_wrap()], so a cohort can be compared at a glance. Every
#' case is run through the same validate + derive pipeline
#' [plot_case_timeline()] uses, so per-state colours stay consistent
#' across panels.
#'
#' @param data A data frame or tibble containing the event log for the whole
#'   cohort.
#' @param state_events Character vector of `act_type` values that open a
#'   state. Required — no default; see [plot_case_timeline()] for the
#'   discovery-error behaviour when omitted.
#' @param case_ids Character vector of cases to plot, or `NULL` (default) to
#'   plot every case in `data`, subject to `max_cases`.
#' @param time_col,act_type_col,activity_col,case_col Column-name
#'   mappings, as in [plot_case_timeline()]. `case_col` is required for a
#'   cohort (it cannot be `NULL` — a cohort needs a case column).
#' @param schema An [event_log_schema()] object, the literal string
#'   `"auto"`, or `NULL` — see [plot_case_timeline()].
#' @param tz Timezone used when parsing character timestamps.
#' @param terminal_activities Character vector of terminal `activity` values.
#'   A case whose series never reaches one renders with the `(ongoing)`
#'   open-case marker in its own panel.
#' @param exclude_categories Character vector of `act_type` values to drop
#'   before plotting, or `NULL`.
#' @param tail_strategy Strategy for inferring each case's final box end
#'   time, as in [plot_case_timeline()].
#' @param align_start Logical. `FALSE` (default) compares cases on absolute
#'   time (free per-panel x range); `TRUE` rebases each case to its first
#'   state event and compares them on one shared elapsed-hours axis.
#' @param ncol Number of facet columns, or `NULL` to let `facet_wrap()`
#'   choose.
#' @param max_cases Guard against faceting too many cases at once (a hang,
#'   not a plot); aborts with advice to pass explicit `case_ids` if exceeded.
#' @param show_duration,label_boxes,event_type_top_n,state_label,state_palette,event_palette,palette_style,box_height,box_gap_prop,title
#'   Passthrough render options mirroring [plot_case_timeline()].
#' @param return_data Logical; if `TRUE`, return `list(plot, boxes, events)`
#'   instead of just the plot.
#'
#' @return A `ggplot` object, or a list when `return_data = TRUE`.
#'
#' @examples
#' plot_cohort_timeline(complaint_example, case_col = "complaint_id",
#'                      state_events = "stage_change",
#'                      case_ids = c("CMP-01", "CMP-02"))
#'
#' @export
plot_cohort_timeline <- function(
    data,
    state_events,
    case_ids = NULL,

    time_col     = "timestamp",
    act_type_col = "act_type",
    activity_col = "activity",
    case_col     = "case_id",

    schema = NULL,

    tz = "UTC",
    terminal_activities = NULL,
    exclude_categories  = NULL,
    tail_strategy       = "last_event",

    # Cohort layout
    align_start = FALSE,
    ncol        = NULL,
    # Faceting hundreds of cases is a hang, not a plot. Guard against it and
    # tell the caller to pass explicit case_ids.
    max_cases   = 25L,

    # Passthrough render options (mirroring plot_case_timeline())
    show_duration    = FALSE,
    label_boxes      = FALSE,
    event_type_top_n = NULL,
    state_label      = "State",
    state_palette    = NULL,
    event_palette    = NULL,
    palette_style    = c("okabe", "brewer"),
    box_height       = 0.25,
    box_gap_prop     = 0.003,
    title            = NULL,

    return_data = FALSE
) {

  if (!is.data.frame(data)) {
    cli::cli_abort(c(
      "{.arg data} must be a data frame or tibble.",
      "x" = "You supplied an object of class {.cls {class(data)}}."
    ))
  }

  if (is.null(case_col)) {
    cli::cli_abort(c(
      "{.arg case_col} cannot be {.code NULL}: a cohort needs a case column.",
      "i" = "Use {.fn plot_case_timeline} for a single unnamed series."
    ))
  }

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

  # Cohort compares across cases; no swimlanes here, so lane is always NULL.
  cols <- list(
    time     = time_col,
    act_type = act_type_col,
    activity = activity_col,
    case     = case_col,
    lane     = NULL
  )

  if (!case_col %in% names(data)) {
    cli::cli_abort(c(
      "{.arg case_col} {.val {case_col}} was not found in {.arg data}.",
      "i" = "Columns present in {.arg data}: {.val {names(data)}}"
    ))
  }

  # NULL case_ids → every case in the data, in first-appearance order.
  if (is.null(case_ids)) {
    case_ids <- unique(data[[case_col]])
  }
  case_ids <- unique(case_ids)

  if (length(case_ids) == 0) {
    cli::cli_abort("No cases to plot: {.arg case_ids} is empty and {.arg data} has no cases.")
  }

  if (length(case_ids) > max_cases) {
    cli::cli_abort(c(
      "Refusing to facet {length(case_ids)} cases (>{.arg max_cases} = {max_cases}).",
      "x" = "Faceting hundreds of cases produces an unreadable, slow plot.",
      "i" = "Pass an explicit {.arg case_ids} subset, or raise {.arg max_cases}
             if you really want them all."
    ))
  }

  # ── Build per-case tables through the shared pipeline, then bind ───────────
  x_scale <- if (align_start) "elapsed_hours" else "datetime"

  boxes_list  <- vector("list", length(case_ids))
  events_list <- vector("list", length(case_ids))
  open_cases  <- character(0)   # cases whose series never reached a terminal

  for (i in seq_along(case_ids)) {
    cid <- case_ids[[i]]

    case_data <- validate_event_log(data, cols, cid, state_events, tz = tz)

    if (!is.null(exclude_categories)) {
      case_data <- dplyr::filter(case_data, !(.data[[cols$act_type]] %in% exclude_categories))
      if (!any(case_data[[cols$act_type]] %in% state_events)) {
        cli::cli_abort(c(
          "No state events remain for case {.val {cid}} after {.arg exclude_categories}.",
          "i" = "Remove {.val {intersect(exclude_categories, state_events)}}
                 from {.arg exclude_categories}."
        ))
      }
    }

    tables <- build_journey_tables(case_data, cols, state_events,
                                   box_height          = box_height,
                                   tail_strategy       = tail_strategy,
                                   terminal_activities = terminal_activities)
    boxes_c  <- tables$boxes
    events_c <- tables$events

    if (isTRUE(attr(boxes_c, "case_open"))) {
      open_cases <- c(open_cases, as.character(cid))
    }

    if (align_start) {
      rebased  <- .rebase_to_elapsed_hours(boxes_c, events_c)
      boxes_c  <- rebased$boxes
      events_c <- rebased$events
    }

    boxes_c$case_id  <- cid
    events_c$case_id <- cid

    boxes_list[[i]]  <- boxes_c
    events_list[[i]] <- events_c
  }

  boxes_all  <- dplyr::bind_rows(boxes_list)
  events_all <- dplyr::bind_rows(events_list)

  # ── Cross-facet colour consistency ─────────────────────────────────────────
  # Build the palettes ONCE over the union of levels across all cases, so a
  # state (or event type) maps to the same hex in every panel. Passing them
  # explicitly makes the guarantee independent of per-panel level order.
  if (is.null(state_palette)) {
    state_palette <- journey_palette(unique(boxes_all$state), "state",
                                     palette_style)
  }
  if (is.null(event_palette) && nrow(events_all) > 0) {
    # The palette must cover what journey_layers() will actually draw: with
    # event_type_top_n set, the long tail is bucketed to "Other" at render
    # time, and a palette built over the raw levels left "Other" falling
    # back to the silent na.value grey. Bucket here the same way (message
    # suppressed — journey_layers() informs once when it buckets for real).
    evt_vals <- events_all$act_type
    if (!is.null(event_type_top_n)) {
      evt_vals <- suppressMessages(bucket_top_n(evt_vals, event_type_top_n))
    }
    event_palette <- journey_palette(unique(evt_vals), "event", palette_style)
  }

  if (is.null(title)) {
    title <- paste0("Cohort \u2014 ", length(case_ids), " case",
                    if (length(case_ids) == 1) "" else "s",
                    if (align_start) " (start-aligned)" else "")
  }

  opts <- list(
    show_labels      = FALSE,
    label_max        = 30L,
    show_duration    = show_duration,
    label_boxes      = label_boxes,
    reference_lines  = NULL,
    event_type_top_n = event_type_top_n,
    state_palette    = state_palette,
    event_palette    = event_palette,
    palette_style    = palette_style,
    box_height       = box_height,
    box_gap_prop     = box_gap_prop,
    title            = title,
    state_label      = state_label,
    x_scale          = x_scale,
    facet_by         = "case_id",
    facet_scales     = if (align_start) "fixed" else "free_x",
    ncol             = ncol,
    case_open        = FALSE,        # single-case flag; cohort uses open_cases
    open_cases       = open_cases,   # per-case markers, one per open panel
    lanes_active     = FALSE
  )

  p <- render_journey_plot(boxes_all, events_all, opts)

  if (return_data) {
    list(plot = p, boxes = boxes_all, events = events_all)
  } else {
    p
  }
}
