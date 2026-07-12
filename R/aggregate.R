# aggregate.R — Cohort aggregate / statistical views (Stage 6)
#
# Where plot_cohort_timeline() (Stage 5) shows many cases as small multiples,
# this file reduces a cohort to *numbers*: per-stay durations, per-state summary
# statistics, breach rates against a target, and a transition (flow) summary.
#
# It never re-implements box derivation: every case is run through the same
# validate_event_log() + derive_state_boxes() pipeline the plotting functions
# use (via the internal .collect_journey() helper), so the statistics describe
# exactly what the plots draw.
#
# GLOBAL RULE — every duration statistic in this file respects `end_inferred`.
# The final box of a non-terminal case has an *imputed* end time (the data feed
# stopped; we invented an xmax for rendering). Including that in a mean duration
# would silently contaminate it with a rendering convenience. Every summariser
# takes
#   include_inferred = FALSE   (default)  -> imputed final-stay durations are
#                                            excluded from stats; the number
#                                            excluded is reported.
#   include_inferred = TRUE               -> they are included, but the flag
#                                            column travels with the output so a
#                                            caller can see what they ingested.
# Transition dwell is intrinsically immune (a "from" state always has a
# successor state event, so it is never the imputed final box) but threads the
# argument for a uniform API.


# ── .collect_journey ────────────────────────────────────────────────────────────
#
# Run the shared validate + derive pipeline once per case and return two tidy
# tables the summarisers build on:
#   stays      — one row per state box across the whole cohort, carrying
#                case_id, state, xmin, xmax, duration_secs, end_inferred,
#                terminal.
#   case_spans — one row per case: case_start (first state event) and
#                case_end (last event of any kind for that case). These are
#                real recorded timestamps, so whole-case elapsed time never
#                depends on the imputed final-box end.
#
# case_ids = NULL -> every case in `data`, first-appearance order.
.collect_journey <- function(data, cols, state_events, case_ids,
                             exclude_categories  = NULL,
                             tz                  = "UTC",
                             terminal_activities = NULL,
                             tail_strategy       = "last_event") {

  if (!is.data.frame(data)) {
    cli::cli_abort(c(
      "{.arg data} must be a data frame or tibble.",
      "x" = "You supplied an object of class {.cls {class(data)}}."
    ))
  }

  if (!cols$case %in% names(data)) {
    cli::cli_abort(c(
      "{.arg case_col} {.val {cols$case}} was not found in {.arg data}.",
      "i" = "Columns present in {.arg data}: {.val {names(data)}}"
    ))
  }

  if (is.null(case_ids)) case_ids <- unique(data[[cols$case]])
  case_ids <- unique(case_ids)

  if (length(case_ids) == 0) {
    cli::cli_abort("No cases to summarise: {.arg case_ids} is empty and {.arg data} has no cases.")
  }

  stays_list  <- vector("list", length(case_ids))
  spans_list  <- vector("list", length(case_ids))

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

    boxes <- derive_state_boxes(
      case_data, cols, state_events,
      tail_strategy       = tail_strategy,
      terminal_activities = terminal_activities
    )

    stays_list[[i]] <- .stays_from_boxes(boxes, cid)

    spans_list[[i]] <- dplyr::tibble(
      case_id    = cid,
      case_start = min(boxes$xmin),
      case_end   = max(case_data[[cols$time]])
    )
  }

  list(
    stays      = dplyr::bind_rows(stays_list),
    case_spans = dplyr::bind_rows(spans_list)
  )
}


# ── Small NA-safe stat helpers ──────────────────────────────────────────────────
#
# A state whose only stays are excluded (all imputed) leaves an empty vector;
# mean()/quantile() of that should be NA, not NaN or an error.
.safe_mean <- function(x) if (length(x) == 0) NA_real_ else mean(x)
.safe_quantile <- function(x, p) {
  if (length(x) == 0) return(NA_real_)
  unname(stats::quantile(x, p, type = 7))
}


# ── 6a. Per-stay durations ──────────────────────────────────────────────────────
#
# One row per state stay across the cohort. This is the detail table every
# other 6a/6c function is built on.
#
#' Summarise per-stay durations across a cohort
#'
#' One row per state stay across the cohort — the detail table the other
#' aggregate functions build on. Every duration statistic in this package
#' respects `end_inferred`: the final box of a non-terminal case has an
#' *imputed* end time, and including it in a mean duration would silently
#' contaminate it with a rendering convenience.
#'
#' @param data A data frame or tibble containing the event log for the whole
#'   cohort.
#' @param state_events Character vector of `act_type` values that open a
#'   state. Required — no default; see [plot_case_timeline()] for the
#'   discovery-error behaviour when omitted.
#' @param case_ids Character vector of cases to include, or `NULL` (default)
#'   for every case in `data`.
#' @param time_col,act_type_col,activity_col,case_col Column-name
#'   mappings, as in [plot_case_timeline()]. `case_col` is required (it
#'   cannot be `NULL` — a cohort needs a case column).
#' @param schema An [event_log_schema()] object, the literal string
#'   `"auto"`, or `NULL` — see [plot_case_timeline()].
#' @param tz Timezone used when parsing character timestamps.
#' @param terminal_activities Character vector of terminal `activity` values.
#' @param exclude_categories Character vector of `act_type` values to drop
#'   before summarising, or `NULL`.
#' @param tail_strategy Strategy for inferring the final box's end time.
#' @param include_inferred Logical. `FALSE` (default) drops the imputed
#'   final-stay rows and records how many were removed in
#'   `attr(result, "n_inferred_excluded")`; `TRUE` keeps every row (the
#'   `end_inferred` column still flags the imputed ones).
#'
#' @return A tibble with one row per stay (`case_id`, `state`, `xmin`,
#'   `xmax`, `duration_secs`, `end_inferred`, `terminal`), carrying
#'   `attr(., "n_inferred_excluded")`.
#'
#' @examples
#' summarise_case_durations(
#'   complaint_example, case_col = "complaint_id",
#'   state_events = "stage_change"
#' )
#'
#' @export
summarise_case_durations <- function(
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
    include_inferred    = FALSE
) {

  if (is.null(case_col)) {
    cli::cli_abort(c(
      "{.arg case_col} cannot be {.code NULL}: a cohort needs a case column."
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

  cols <- list(
    time = time_col, act_type = act_type_col, activity = activity_col,
    case = case_col, lane = NULL
  )

  collected <- .collect_journey(
    data, cols, state_events, case_ids,
    exclude_categories  = exclude_categories,
    tz                  = tz,
    terminal_activities = terminal_activities,
    tail_strategy       = tail_strategy
  )
  stays <- collected$stays

  n_excluded <- sum(stays$end_inferred)
  if (!include_inferred) {
    stays <- dplyr::filter(stays, !end_inferred)
  } else {
    n_excluded <- 0L
  }

  attr(stays, "n_inferred_excluded") <- n_excluded
  stays
}


# ── 6a. Per-state duration statistics ───────────────────────────────────────────
#
# Built on summarise_case_durations(): one row per distinct state with the
# case count, mean/median/p25/p75 dwell in seconds, and the number of imputed
# final stays excluded from those statistics.
#
#' Summarise per-state duration statistics across a cohort
#'
#' Built on [summarise_case_durations()]: one row per distinct state
#' with the case count, mean/median/p25/p75 dwell in seconds, and the number
#' of imputed final stays excluded from those statistics.
#'
#' @inheritParams summarise_case_durations
#'
#' @return A tibble with one row per state (`state`, `n_cases`,
#'   `mean_secs`, `median_secs`, `p25_secs`, `p75_secs`,
#'   `n_inferred_excluded`). `n_cases` counts every case that visited the
#'   state; the statistics are computed only over the *included* stays, so
#'   a state seen only as an imputed final stay reports `NA` statistics
#'   when `include_inferred = FALSE`.
#'
#' @examples
#' summarise_state_durations(
#'   complaint_example, case_col = "complaint_id",
#'   state_events = "stage_change"
#' )
#'
#' @export
summarise_state_durations <- function(
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
    include_inferred    = FALSE
) {

  # Pull the full detail table (all stays, flag intact) so per-state excluded
  # counts can be computed here rather than lost to an upstream filter.
  stays <- summarise_case_durations(
    data,
    state_events        = state_events,
    case_ids            = case_ids,
    time_col = time_col, act_type_col = act_type_col, activity_col = activity_col,
    case_col = case_col, schema = schema,
    tz = tz, terminal_activities = terminal_activities,
    exclude_categories = exclude_categories, tail_strategy = tail_strategy,
    include_inferred = TRUE
  )

  stays$.use <- if (include_inferred) TRUE else !stays$end_inferred

  stays |>
    dplyr::group_by(state) |>
    dplyr::summarise(
      n_cases             = dplyr::n_distinct(case_id),
      mean_secs           = .safe_mean(duration_secs[.use]),
      median_secs         = .safe_quantile(duration_secs[.use], 0.5),
      p25_secs            = .safe_quantile(duration_secs[.use], 0.25),
      p75_secs            = .safe_quantile(duration_secs[.use], 0.75),
      n_inferred_excluded = sum(end_inferred & !.use),
      .groups             = "drop"
    )
}


# ── 6b. Breach rate against a target ────────────────────────────────────────────
#
# What fraction of cases exceed `target_hours`? Two scopes:
#   scope = "case"            — whole-case elapsed time: first state event to
#                              last recorded event. Both endpoints are real
#                              timestamps, so nothing is inferred (end_inferred
#                              is FALSE for every row and include_inferred is a
#                              no-op).
#   scope = "<state name>"    — dwell within one state (e.g. a 4-hour
#                              standard = time in that state). A case that
#                              never visited the state contributes no row.
#                              When that state is the imputed final box, its
#                              dwell is inferred; include_inferred = FALSE
#                              drops those cases and reports the count.
#
# An unknown scope name aborts with a did-you-mean hint over the states
# actually present in the cohort.
#
#' Summarise breach rate against a target duration
#'
#' What fraction of cases exceed `target_hours`?
#'
#' @param data A data frame or tibble containing the event log for the whole
#'   cohort.
#' @param target_hours Single numeric target, in hours.
#' @param scope Either `"case"` (whole-case elapsed time: first state event
#'   to last recorded event — both endpoints are real timestamps, so
#'   `include_inferred` is a no-op) or the name of a state present in the
#'   cohort (dwell within that one state, e.g. a 4-hour standard). A case
#'   that never visited the state contributes no row. An unknown scope name
#'   aborts with a did-you-mean hint.
#' @param case_ids Character vector of cases to include, or `NULL` (default)
#'   for every case in `data`.
#' @param state_events Character vector of `act_type` values that open a
#'   state. Required — no default; see [plot_case_timeline()] for the
#'   discovery-error behaviour when omitted.
#' @param time_col,act_type_col,activity_col,case_col Column-name
#'   mappings, as in [plot_case_timeline()]. `case_col` is required (it
#'   cannot be `NULL` — a cohort needs a case column).
#' @param schema An [event_log_schema()] object, the literal string
#'   `"auto"`, or `NULL` — see [plot_case_timeline()].
#' @param tz Timezone used when parsing character timestamps.
#' @param terminal_activities Character vector of terminal `activity` values.
#' @param exclude_categories Character vector of `act_type` values to drop
#'   before summarising, or `NULL`.
#' @param tail_strategy Strategy for inferring the final box's end time.
#' @param include_inferred Logical; see [summarise_case_durations()]. When
#'   `scope` is a state whose final stay is the imputed final box,
#'   `FALSE` (default) drops those cases and reports the count.
#'
#' @return A tibble (`case_id`, `elapsed_hours`, `breached`, `end_inferred`)
#'   with the cohort breach fraction in `attr(., "breach_rate")` and the
#'   excluded count in `attr(., "n_inferred_excluded")`.
#'
#' @examples
#' summarise_breach_rate(
#'   complaint_example, target_hours = 24 * 7, scope = "case",
#'   case_col = "complaint_id", state_events = "stage_change"
#' )
#'
#' @export
summarise_breach_rate <- function(
    data,
    target_hours,
    scope    = "case",
    case_ids = NULL,
    state_events,
    time_col     = "timestamp",
    act_type_col = "act_type",
    activity_col = "activity",
    case_col     = "case_id",
    schema = NULL,
    tz = "UTC",
    terminal_activities = NULL,
    exclude_categories  = NULL,
    tail_strategy       = "last_event",
    include_inferred    = FALSE
) {

  if (!is.numeric(target_hours) || length(target_hours) != 1L || is.na(target_hours)) {
    cli::cli_abort(c(
      "{.arg target_hours} must be a single non-missing number (hours).",
      "x" = "You supplied {.obj_type_friendly {target_hours}}."
    ))
  }
  if (!is.character(scope) || length(scope) != 1L) {
    cli::cli_abort("{.arg scope} must be a single string: {.val case} or a state name.")
  }
  if (is.null(case_col)) {
    cli::cli_abort(c(
      "{.arg case_col} cannot be {.code NULL}: a cohort needs a case column."
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

  cols <- list(
    time = time_col, act_type = act_type_col, activity = activity_col,
    case = case_col, lane = NULL
  )

  collected <- .collect_journey(
    data, cols, state_events, case_ids,
    exclude_categories  = exclude_categories,
    tz                  = tz,
    terminal_activities = terminal_activities,
    tail_strategy       = tail_strategy
  )

  if (identical(scope, "case")) {
    out <- collected$case_spans |>
      dplyr::mutate(
        elapsed_hours = as.numeric(difftime(case_end, case_start, units = "hours")),
        end_inferred  = FALSE
      ) |>
      dplyr::select(case_id, elapsed_hours, end_inferred)
    n_excluded <- 0L
  } else {
    present <- unique(collected$stays$state)
    if (!scope %in% present) {
      suggestions <- suggest_matches(scope, present)
      hint <- if (length(suggestions) > 0) {
        cli::format_inline("Did you mean {.val {suggestions}}?")
      } else {
        cli::format_inline("States present in the cohort: {.val {present}}")
      }
      cli::cli_abort(c(
        "{.arg scope} {.val {scope}} is neither {.val case} nor a state present in the cohort.",
        "i" = hint
      ))
    }

    stage <- dplyr::filter(collected$stays, state == scope)

    # One dwell per case for this state. If a case visits the state more than
    # once, sum the dwells (total time spent in that state); an imputed final
    # visit taints the case, so carry end_inferred = any(end_inferred).
    stage <- stage |>
      dplyr::group_by(case_id) |>
      dplyr::summarise(
        elapsed_hours = sum(duration_secs) / 3600,
        end_inferred  = any(end_inferred),
        .groups       = "drop"
      )

    n_excluded <- if (include_inferred) 0L else sum(stage$end_inferred)
    if (!include_inferred) stage <- dplyr::filter(stage, !end_inferred)
    out <- stage
  }

  out$breached <- out$elapsed_hours > target_hours
  out <- dplyr::select(out, case_id, elapsed_hours, breached, end_inferred)

  attr(out, "breach_rate") <- if (nrow(out) == 0) NA_real_ else mean(out$breached)
  attr(out, "n_inferred_excluded") <- n_excluded
  out
}


# ── 6c. Transition summary ──────────────────────────────────────────────────────
#
# Reduce the cohort to directed state-to-state transitions. For each case,
# consecutive stays (ordered by entry time) form a from -> to pair; the dwell of
# that transition is the time spent in the "from" state before the move. A "from"
# state always has a successor, so it is never the imputed final box — transition
# dwell is intrinsically real (include_inferred is threaded only for API
# symmetry and never excludes anything here).
#
#' Summarise directed state-to-state transitions across a cohort
#'
#' For each case, consecutive stays (ordered by entry time) form a
#' from -> to pair; the dwell of that transition is the time spent in the
#' "from" state before the move. A "from" state always has a successor, so
#' it is never the imputed final box — transition dwell is intrinsically
#' real (`include_inferred` is threaded only for API symmetry and never
#' excludes anything here).
#'
#' @inheritParams summarise_case_durations
#'
#' @return A tibble (`from_state`, `to_state`, `n`, `mean_dwell_secs`,
#'   `median_dwell_secs`), one row per distinct ordered pair, sorted by
#'   descending `n`.
#'
#' @examples
#' summarise_transitions(
#'   complaint_example, case_col = "complaint_id",
#'   state_events = "stage_change"
#' )
#'
#' @export
summarise_transitions <- function(
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
    include_inferred    = FALSE
) {

  if (is.null(case_col)) {
    cli::cli_abort(c(
      "{.arg case_col} cannot be {.code NULL}: a cohort needs a case column."
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

  cols <- list(
    time = time_col, act_type = act_type_col, activity = activity_col,
    case = case_col, lane = NULL
  )

  stays <- .collect_journey(
    data, cols, state_events, case_ids,
    exclude_categories  = exclude_categories,
    tz                  = tz,
    terminal_activities = terminal_activities,
    tail_strategy       = tail_strategy
  )$stays

  pairs <- stays |>
    dplyr::arrange(case_id, xmin) |>
    dplyr::group_by(case_id) |>
    dplyr::mutate(
      to_state   = dplyr::lead(state),
      dwell_secs = duration_secs
    ) |>
    dplyr::ungroup() |>
    dplyr::filter(!is.na(to_state)) |>
    dplyr::rename(from_state = state)

  if (nrow(pairs) == 0) {
    return(dplyr::tibble(
      from_state        = character(),
      to_state          = character(),
      n                 = integer(),
      mean_dwell_secs   = numeric(),
      median_dwell_secs = numeric()
    ))
  }

  pairs |>
    dplyr::group_by(from_state, to_state) |>
    dplyr::summarise(
      n                 = dplyr::n(),
      mean_dwell_secs   = mean(dwell_secs),
      median_dwell_secs = stats::median(dwell_secs),
      .groups           = "drop"
    ) |>
    dplyr::arrange(dplyr::desc(n), from_state, to_state)
}


# ── 6c. Transition flow diagram ─────────────────────────────────────────────────
#
# A hand-rolled flow diagram (no new heavy dependency — locked decision 4). Nodes
# are the distinct states laid out left-to-right by their average step index
# across cases (so the common forward flow reads as a left-to-right spine);
# directed edges are drawn as arrowed curves whose width encodes transition
# frequency, labelled with the mean dwell in the "from" state.
#
#' Plot a directed transition-flow diagram for a cohort
#'
#' A hand-rolled flow diagram: nodes are the distinct states laid out
#' left-to-right by their average step index across cases, so the common
#' forward flow reads as a left-to-right spine; directed edges are drawn as
#' arrowed curves whose width encodes transition frequency, labelled with
#' the mean dwell in the "from" state. Forward transitions (to a later node)
#' bow one way, backward transitions the other, so a re-entry loop is
#' visually separable from the forward flow it mirrors.
#'
#' @inheritParams summarise_case_durations
#' @param min_n Only draw transitions observed at least this many times.
#' @param title Plot title; `NULL` auto-generates one from the case count.
#' @param return_data Logical; if `TRUE`, return
#'   `list(plot, nodes, edges, transitions)` instead of just the plot.
#'
#' @return A `ggplot` object, or a list when `return_data = TRUE`.
#'
#' @examples
#' plot_transition_summary(
#'   complaint_example, case_col = "complaint_id",
#'   state_events = "stage_change"
#' )
#'
#' @export
plot_transition_summary <- function(
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
    min_n = 1L,
    title = NULL,
    return_data = FALSE
) {

  if (is.null(case_col)) {
    cli::cli_abort(c(
      "{.arg case_col} cannot be {.code NULL}: a cohort needs a case column."
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

  cols <- list(
    time = time_col, act_type = act_type_col, activity = activity_col,
    case = case_col, lane = NULL
  )

  stays <- .collect_journey(
    data, cols, state_events, case_ids,
    exclude_categories  = exclude_categories,
    tz                  = tz,
    terminal_activities = terminal_activities,
    tail_strategy       = tail_strategy
  )$stays

  transitions <- summarise_transitions(
    data,
    state_events        = state_events,
    case_ids            = case_ids,
    time_col = time_col, act_type_col = act_type_col, activity_col = activity_col,
    case_col = case_col,
    tz = tz, terminal_activities = terminal_activities,
    exclude_categories = exclude_categories, tail_strategy = tail_strategy
  )
  transitions <- dplyr::filter(transitions, n >= min_n)

  if (nrow(transitions) == 0) {
    cli::cli_abort(c(
      "No transitions to plot.",
      "i" = "The cohort has no state-to-state moves at or above
             {.arg min_n} = {min_n}."
    ))
  }

  # ── Node layout: order states by mean step index across cases ───────────────
  step_idx <- stays |>
    dplyr::arrange(case_id, xmin) |>
    dplyr::group_by(case_id) |>
    dplyr::mutate(step = dplyr::row_number()) |>
    dplyr::ungroup()

  nodes <- step_idx |>
    dplyr::group_by(state) |>
    dplyr::summarise(mean_step = mean(step), visits = dplyr::n(), .groups = "drop") |>
    dplyr::arrange(mean_step, state) |>
    dplyr::mutate(x = dplyr::row_number(), y = 0)

  node_x <- stats::setNames(nodes$x, nodes$state)

  edges <- transitions |>
    dplyr::mutate(
      x    = node_x[from_state],
      xend = node_x[to_state],
      # Forward edges (x < xend) curve upward; backward/self edges curve the
      # other way so re-entries don't overplot the forward spine.
      forward   = xend >= x,
      curvature = ifelse(forward, -0.25, 0.30),
      dwell_lab = format_duration(mean_dwell_secs),
      # Nodes all sit on the y = 0 spine; edges run node-to-node along it.
      y = 0, yend = 0,
      # Midpoint for the dwell label, nudged along the curve's bow.
      x_mid = (x + xend) / 2,
      y_mid = ifelse(forward, 0.22, -0.22)
    )

  if (is.null(title)) {
    n_cases <- dplyr::n_distinct(stays$case_id)
    title <- paste0("Transition summary \u2014 ", n_cases, " case",
                    if (n_cases == 1) "" else "s")
  }

  # ── Assemble the plot ───────────────────────────────────────────────────────
  # geom_curve does not accept a vector `curvature`, so forward and backward
  # edges are drawn as two layers.
  arrow_spec <- ggplot2::arrow(length = ggplot2::unit(0.14, "inches"), type = "closed")

  p <- ggplot2::ggplot()

  fwd <- dplyr::filter(edges, forward)
  bwd <- dplyr::filter(edges, !forward)

  if (nrow(fwd) > 0) {
    p <- p + ggplot2::geom_curve(
      data = fwd,
      ggplot2::aes(x = x, y = y, xend = xend, yend = y, linewidth = n),
      curvature = -0.25, colour = "grey45", alpha = 0.8,
      arrow = arrow_spec, lineend = "round"
    )
  }
  if (nrow(bwd) > 0) {
    p <- p + ggplot2::geom_curve(
      data = bwd,
      ggplot2::aes(x = x, y = y, xend = xend, yend = y, linewidth = n),
      curvature = 0.30, colour = "grey45", alpha = 0.8,
      arrow = arrow_spec, lineend = "round"
    )
  }

  p <- p +
    ggplot2::geom_text(
      data = edges,
      ggplot2::aes(x = x_mid, y = y_mid, label = dwell_lab),
      size = 2.6, colour = "grey30"
    ) +
    ggplot2::geom_label(
      data = nodes,
      ggplot2::aes(x = x, y = y, label = state),
      size = 3, fill = "grey95", colour = "grey10",
      label.padding = ggplot2::unit(0.3, "lines"), fontface = "bold"
    ) +
    ggplot2::scale_linewidth_continuous(
      name = "cases", range = c(0.4, 3.5),
      breaks = scales_int_breaks(edges$n)
    ) +
    ggplot2::scale_y_continuous(limits = c(-0.6, 0.6)) +
    ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = 0.12)) +
    ggplot2::theme_void(base_size = 11) +
    ggplot2::theme(
      plot.title      = ggplot2::element_text(size = 12, face = "bold", hjust = 0),
      legend.position = "bottom",
      plot.margin     = ggplot2::margin(10, 14, 10, 14)
    ) +
    ggplot2::labs(title = title)

  if (return_data) {
    list(plot = p, nodes = nodes, edges = edges, transitions = transitions)
  } else {
    p
  }
}


# Integer-valued legend breaks for the edge-width scale: transition counts are
# whole numbers, so a fractional break would be meaningless.
scales_int_breaks <- function(x) {
  rng <- range(x, na.rm = TRUE)
  br  <- unique(round(seq(rng[1], rng[2], length.out = 4)))
  br[br >= 1]
}


# ── 6e. Timeline + per-state duration summary, stacked (stretch) ────────────────
#
#' Plot a single case's timeline stacked above its per-state duration summary
#'
#' `patchwork`-stacks a single case's timeline ([plot_case_timeline()])
#' above a bar chart of that case's per-state dwell. Requires the
#' `patchwork` package (Suggests only).
#'
#' @param data A data frame or tibble containing the event log.
#' @param case_id The single case identifier to visualise, or `NULL` — see
#'   [plot_case_timeline()] for the resolution rules.
#' @param state_events Character vector of `act_type` values that open a
#'   state. Required — no default; see [plot_case_timeline()] for the
#'   discovery-error behaviour when omitted.
#' @param heights Relative heights `c(timeline, bars)` passed to
#'   `patchwork::wrap_plots()`.
#' @param ... Additional arguments forwarded to [plot_case_timeline()].
#'
#' @return A `patchwork` object.
#'
#' @examples
#' \donttest{
#' if (requireNamespace("patchwork", quietly = TRUE)) {
#'   plot_case_timeline_with_summary(
#'     example_journey,
#'     state_events = c("location_move", "ed_location_move")
#'   )
#' }
#' }
#'
#' @export
plot_case_timeline_with_summary <- function(
    data,
    case_id = NULL,
    state_events,
    heights = c(2, 1),
    ...
) {

  if (!requireNamespace("patchwork", quietly = TRUE)) {
    cli::cli_abort(c(
      "{.pkg patchwork} is required for {.fn plot_case_timeline_with_summary}.",
      "i" = "Install it with {.code install.packages(\"patchwork\")}."
    ))
  }

  # The timeline. return_data gives us the per-stay summary for free (Stage 6d).
  # state_events is forwarded, not evaluated here, so an omitted argument
  # still triggers plot_case_timeline()'s own discovery-error message rather
  # than a generic "argument is missing" error — R's missing() propagates
  # through this kind of pass-through forwarding.
  res <- plot_case_timeline(
    data, case_id = case_id,
    state_events = state_events,
    return_data = TRUE, ...
  )

  timeline <- res$plot
  summary  <- res$summary

  # Per-state dwell bars, in visit order. Imputed final stays carry the
  # package's usual "+" suffix on their label rather than a separate legend.
  summary <- summary |>
    dplyr::mutate(
      state   = factor(state, levels = unique(state)),
      hours   = duration_secs / 3600,
      dur_lab = ifelse(end_inferred,
                       paste0(format_duration(duration_secs), "+"),
                       format_duration(duration_secs))
    )

  # Bar colours must reuse the exact palette the timeline's fill scale used.
  # The timeline's fill levels are the non-terminal boxes (including any
  # synthetic "(before first state)" box) in first-appearance order; the
  # summary drops the before-first-state artefact and keeps terminal stays,
  # so building a fresh palette over the summary's own levels shifted every
  # hue by one whenever the two level sets differed. Stays absent from the
  # timeline's fill scale (terminals) take the palette positions AFTER the
  # shared levels, leaving the shared assignments untouched. A
  # state_palette or palette_style forwarded to the timeline through `...`
  # is honoured here too.
  dots            <- list(...)
  timeline_levels <- unique(res$boxes$state[!res$boxes$terminal])
  all_levels      <- c(timeline_levels,
                       setdiff(levels(summary$state), timeline_levels))
  bar_cols <- dots$state_palette %||%
    journey_palette(all_levels, "state", dots$palette_style %||% "okabe")

  bars <- ggplot2::ggplot(
    summary,
    ggplot2::aes(x = state, y = hours, fill = state)
  ) +
    ggplot2::geom_col(width = 0.7, show.legend = FALSE) +
    ggplot2::geom_text(
      ggplot2::aes(label = dur_lab),
      vjust = -0.35, size = 2.6, colour = "grey30"
    ) +
    ggplot2::scale_fill_manual(values = bar_cols, guide = "none") +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.12))) +
    ggplot2::labs(x = NULL, y = "Dwell (hours)") +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      panel.grid.major.x = ggplot2::element_blank(),
      panel.grid.minor   = ggplot2::element_blank(),
      axis.text.x        = ggplot2::element_text(angle = 20, hjust = 1)
    )

  patchwork::wrap_plots(timeline, bars, ncol = 1, heights = heights)
}
