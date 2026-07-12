# pivot_wide.R — Wide-to-long pivot wrapper
#
# Milestone-style event logs are commonly stored wide: one row per case, one
# column per timestamp ("arrival_time", "triage_time", "discharge_time", …).
# plot_case_timeline() needs the long form (one row per event). This file
# reshapes the former into the latter.
#
# Public entry point: pivot_events_longer()


# ── Milestone-name prettification ────────────────────────────────────────────

# Turn a wide column name into a display label: strip a trailing timestamp
# suffix, replace separators with spaces, then title-case.
# "arrival_time" -> "Arrival"; "triage_at" -> "Triage"; "region.code" -> "Region Code"
prettify_milestone <- function(x) {
  x <- sub("(_datetime|_date|_time|_ts|_at)$", "", x, ignore.case = TRUE)
  x <- gsub("[_.]", " ", x)
  tools::toTitleCase(x)
}


# ── pivot_events_longer ──────────────────────────────────────────────────────

# Reshape a wide, one-row-per-case event log (a column per milestone
# timestamp) into the long, one-row-per-event form plot_case_timeline()
# expects.
#
#   data          wide data frame, one row per case
#   case_col      column identifying each case
#   time_cols     character vector of wide column names to pivot
#   state_cols    subset of time_cols that mark a state change;
#                 these get act_type "state_change"
#   act_type_map  named character vector: time_cols entry -> act_type, for
#                 non-state milestones. NULL = milestone name is used as-is
#   activity_map  named character vector: time_cols entry -> display label.
#                 NULL = derived from the milestone name (see
#                 prettify_milestone())
#   drop_na       drop rows whose milestone timestamp is NA (the milestone
#                 didn't happen for that case) — default TRUE
#   tz            forwarded to coerce_datetime_column()
#   time_col_out, act_type_col_out, activity_col_out
#                 output column names, matching plot_case_timeline()'s
#                 time_col/act_type_col/activity_col arguments
#
#' Pivot a wide milestone-timestamp event log into long form
#'
#' Milestone-style event logs are commonly stored wide: one row per case, one
#' column per timestamp (`"arrival_time"`, `"triage_time"`,
#' `"discharge_time"`, ...). [plot_case_timeline()] needs the long form
#' (one row per event); this reshapes the former into the latter. The pivot
#' and the plot agree out of the box: state columns emit
#' `act_type = "state_change"`, which is exactly what you pass as
#' `state_events` to [plot_case_timeline()].
#'
#' @param data Wide data frame, one row per case.
#' @param case_col Column identifying each case.
#' @param time_cols Character vector of wide column names to pivot.
#' @param state_cols Subset of `time_cols` that mark a state change; these
#'   get `act_type = "state_change"`.
#' @param act_type_map Named character vector: `time_cols` entry -> act_type,
#'   for non-state milestones. `NULL` = the milestone name is used as-is.
#' @param activity_map Named character vector: `time_cols` entry -> display
#'   label. `NULL` = derived from the milestone name (see
#'   `prettify_milestone()`): strip a trailing timestamp suffix, replace
#'   separators with spaces, then title-case.
#' @param drop_na Logical; drop rows whose milestone timestamp is `NA` (the
#'   milestone didn't happen for that case). Default `TRUE`.
#' @param tz Timezone forwarded to the internal datetime coercion.
#' @param time_col_out,act_type_col_out,activity_col_out Output column
#'   names, matching [plot_case_timeline()]'s `time_col`/`act_type_col`/
#'   `activity_col` arguments.
#'
#' @return A long tibble: case, time, act_type, activity, then any
#'   passthrough columns from `data` untouched — ready to pass straight into
#'   [plot_case_timeline()].
#'
#' @examples
#' wide <- data.frame(
#'   case_id = c("A", "B"),
#'   arrival_time = as.POSIXct(c("2024-01-01 08:00", "2024-01-01 09:00")),
#'   discharge_time = as.POSIXct(c("2024-01-01 12:00", "2024-01-01 14:00"))
#' )
#' pivot_events_longer(wide, case_col = "case_id",
#'                      time_cols = c("arrival_time", "discharge_time"),
#'                      state_cols = c("arrival_time", "discharge_time"))
#'
#' @export
pivot_events_longer <- function(
    data,
    case_col,
    time_cols,
    state_cols       = NULL,
    act_type_map     = NULL,
    activity_map     = NULL,
    drop_na          = TRUE,
    tz               = "UTC",
    time_col_out     = "timestamp",
    act_type_col_out = "act_type",
    activity_col_out = "activity"
) {

  # ── 1. case_col and time_cols must exist ───────────────────────────────────
  required <- c(case_col, time_cols)
  missing  <- setdiff(required, names(data))

  if (length(missing) > 0) {
    cli::cli_abort(c(
      "The following required columns are missing from {.arg data}:",
      "x" = "{.val {missing}}",
      "i" = "Columns present in {.arg data}: {.val {names(data)}}"
    ))
  }

  # ── 2. state_cols must be a subset of time_cols ────────────────────────────
  if (!is.null(state_cols)) {
    offenders <- setdiff(state_cols, time_cols)
    if (length(offenders) > 0) {
      cli::cli_abort(c(
        "{.arg state_cols} must be a subset of {.arg time_cols}.",
        "x" = "Not present in {.arg time_cols}: {.val {offenders}}"
      ))
    }
  }

  # ── 3. Coerce every time_cols column to POSIXct ─────────────────────────────
  for (col in time_cols) {
    data[[col]] <- coerce_datetime_column(data[[col]], col, tz = tz)
  }

  # ── 4. Pivot longer — passthrough columns (metadata) come along
  #        automatically ───────────────────────────────────────────────────────
  long <- tidyr::pivot_longer(
    data,
    cols      = tidyr::all_of(time_cols),
    names_to  = ".milestone",
    values_to = time_col_out
  )

  # ── 5. Drop NA-timestamp rows (milestone didn't happen for that case) ──────
  if (drop_na) {
    na_mask <- is.na(long[[time_col_out]])
    if (any(na_mask)) {
      counts  <- table(long$.milestone[na_mask])
      bullets <- vapply(seq_along(counts), function(i) {
        cli::format_inline("{.field {names(counts)[i]}}: {as.integer(counts[i])} row(s)")
      }, character(1))

      cli::cli_inform(c(
        "i" = "Dropped {sum(na_mask)} row(s) with NA {.field {time_col_out}}
               (milestone did not occur for that case):",
        stats::setNames(bullets, rep("*", length(bullets)))
      ))
    }
    long <- long[!na_mask, ]
  }

  # ── 6/7. act_type / activity per milestone ──────────────────────────────────
  milestones <- unique(long$.milestone)

  act_type_lookup <- stats::setNames(vapply(milestones, function(m) {
    if (!is.null(state_cols) && m %in% state_cols) {
      "state_change"
    } else if (!is.null(act_type_map) && m %in% names(act_type_map)) {
      unname(act_type_map[[m]])
    } else {
      m
    }
  }, character(1)), milestones)

  activity_lookup <- stats::setNames(vapply(milestones, function(m) {
    if (!is.null(activity_map) && m %in% names(activity_map)) {
      unname(activity_map[[m]])
    } else {
      prettify_milestone(m)
    }
  }, character(1)), milestones)

  long[[act_type_col_out]] <- unname(act_type_lookup[long$.milestone])
  long[[activity_col_out]] <- unname(activity_lookup[long$.milestone])

  # ── 8. Drop .milestone; fixed column order ──────────────────────────────────
  long$.milestone <- NULL

  front       <- c(case_col, time_col_out, act_type_col_out, activity_col_out)
  passthrough <- setdiff(names(long), front)

  long[, c(front, passthrough)]
}
