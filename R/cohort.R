# cohort.R — Cohort view via faceting
#
# plot_journey_cohort() lays several spells out as a small-multiples grid, one
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
#                      move, drawn on one shared numeric axis (scales = "fixed")
#                      so durations line up for comparison.


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
#' [plot_patient_journey()] uses, so per-location colours stay consistent
#' across panels.
#'
#' @param data A data frame or tibble containing the event log for the whole
#'   cohort.
#' @param case_ids Character vector of cases to plot, or `NULL` (default) to
#'   plot every case in `data`, subject to `max_cases`.
#' @param location_categories Character vector of `act_type` values that mark
#'   a move to a new exclusive state.
#' @param time_col,act_type_col,activity_col,case_col,patient_col Column-name
#'   mappings, as in [plot_patient_journey()].
#' @param tz Timezone used when parsing character timestamps.
#' @param terminal_activities Character vector of terminal `activity` values.
#' @param exclude_categories Character vector of `act_type` values to drop
#'   before plotting, or `NULL`.
#' @param align_start Logical. `FALSE` (default) compares cases on absolute
#'   time (free per-panel x range); `TRUE` rebases each case to its first
#'   move and compares them on one shared elapsed-hours axis.
#' @param ncol Number of facet columns, or `NULL` to let `facet_wrap()`
#'   choose.
#' @param max_cases Guard against faceting too many spells at once (a hang,
#'   not a plot); aborts with advice to pass explicit `case_ids` if exceeded.
#' @param show_duration,label_boxes,event_type_top_n,state_label,location_palette,event_palette,palette_style,box_height,box_gap_prop,title
#'   Passthrough render options mirroring [plot_patient_journey()].
#' @param return_data Logical; if `TRUE`, return `list(plot, boxes, events)`
#'   instead of just the plot.
#'
#' @return A `ggplot` object, or a list when `return_data = TRUE`.
#'
#' @examples
#' plot_journey_cohort(complaint_example, case_col = "complaint_id",
#'                      location_categories = "stage_change",
#'                      patient_col = NULL, case_ids = c("CMP-01", "CMP-02"))
#'
#' @export
plot_journey_cohort <- function(
    data,
    case_ids = NULL,

    location_categories = c("location_move", "ed_location_move"),

    time_col     = "timestamp",
    act_type_col = "act_type",
    activity_col = "activity",
    case_col     = "caseID",
    patient_col  = "K_Number",

    tz = "UTC",
    terminal_activities = NULL,
    exclude_categories  = NULL,

    # Cohort layout
    align_start = FALSE,
    ncol        = NULL,
    # Faceting hundreds of spells is a hang, not a plot. Guard against it and
    # tell the caller to pass explicit case_ids.
    max_cases   = 25L,

    # Passthrough render options (mirroring plot_patient_journey())
    show_duration    = FALSE,
    label_boxes      = FALSE,
    event_type_top_n = NULL,
    state_label      = "Location",
    location_palette = NULL,
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

  # Cohort compares across cases; no swimlanes here, so lane is always NULL.
  cols <- list(
    time     = time_col,
    act_type = act_type_col,
    activity = activity_col,
    case     = case_col,
    patient  = patient_col,
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
      "x" = "Faceting hundreds of spells produces an unreadable, slow plot.",
      "i" = "Pass an explicit {.arg case_ids} subset, or raise {.arg max_cases}
             if you really want them all."
    ))
  }

  # ── Build per-case tables through the shared pipeline, then bind ───────────
  x_scale <- if (align_start) "elapsed_hours" else "datetime"

  boxes_list  <- vector("list", length(case_ids))
  events_list <- vector("list", length(case_ids))

  for (i in seq_along(case_ids)) {
    cid <- case_ids[[i]]

    spell <- validate_event_log(data, cols, cid, location_categories, tz = tz)

    if (!is.null(exclude_categories)) {
      spell <- dplyr::filter(spell, !(.data[[cols$act_type]] %in% exclude_categories))
      if (!any(spell[[cols$act_type]] %in% location_categories)) {
        cli::cli_abort(c(
          "No location events remain for case {.val {cid}} after {.arg exclude_categories}.",
          "i" = "Remove {.val {intersect(exclude_categories, location_categories)}}
                 from {.arg exclude_categories}."
        ))
      }
    }

    tables <- build_journey_tables(spell, cols, location_categories,
                                   box_height          = box_height,
                                   terminal_activities = terminal_activities)
    boxes_c  <- tables$boxes
    events_c <- tables$events

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
  # location (or event type) maps to the same hex in every panel. Passing them
  # explicitly makes the guarantee independent of per-panel level order.
  if (is.null(location_palette)) {
    location_palette <- journey_palette(unique(boxes_all$location), "location",
                                        palette_style)
  }
  if (is.null(event_palette) && nrow(events_all) > 0) {
    event_palette <- journey_palette(unique(events_all$act_type), "event",
                                     palette_style)
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
    location_palette = location_palette,
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
    spell_open       = FALSE,   # per-case open-spell markers are Stage 6/v2
    lanes_active     = FALSE
  )

  p <- render_journey_plot(boxes_all, events_all, opts)

  if (return_data) {
    list(plot = p, boxes = boxes_all, events = events_all)
  } else {
    p
  }
}
