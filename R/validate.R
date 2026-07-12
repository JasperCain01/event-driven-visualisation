# validate.R — Input validation for plot_case_timeline()
#
# validate_event_log() is the single entry point. It performs all checks in a
# deliberate order (cheapest / most likely to fail first) and returns a
# cleaned, single-case, time-sorted tibble (or the whole `data`, unfiltered,
# when `cols$case` is NULL — a single unnamed series) on success, or calls
# cli::cli_abort() with an actionable message on failure.
#
# state_events has no default anywhere in the package. Its "argument missing"
# failure mode is handled by require_state_events(), called by every entry
# point right after schema resolution (state_events may have been filled in
# from the schema by then, so a plain missing() check at that point would be
# wrong — NULL is the right test). Its "supplied but matches nothing" failure
# mode is handled here, in validate_event_log(), once the case has been
# resolved and filtered.


# ── act_type discovery (the `state_events` error-driven discovery mechanism) ──

# Format the distinct act_type values present in `data`, ordered by
# frequency (most common first), with row counts — at most 10. This is the
# single source of truth for "what act_type values exist here", reused by
# both the missing-state_events error and the no-rows-matched error.
describe_act_types <- function(data, act_type_col) {
  freq  <- sort(table(data[[act_type_col]]), decreasing = TRUE)
  freq  <- utils::head(freq, 10)
  parts <- sprintf('"%s" (%d row%s)', names(freq), as.integer(freq),
                   ifelse(freq == 1, "", "s"))
  paste(parts, collapse = ", ")
}

# Abort with the discovery-driven error when state_events is still NULL after
# schema/argument resolution. Called by every entry point.
require_state_events <- function(state_events, data, act_type_col) {
  if (!is.null(state_events)) return(invisible(state_events))

  example <- names(sort(table(data[[act_type_col]]), decreasing = TRUE))[1]

  cli::cli_abort(c(
    "{.arg state_events} is required: name the {.field act_type} value(s)
     that open a state (a long-running condition), as opposed to
     point-in-time events.",
    "i" = "Distinct {.field {act_type_col}} values in {.arg data}: {describe_act_types(data, act_type_col)}",
    "i" = "Example: {.code state_events = \"{example}\"}"
  ))
}


# ── Shared schema/state_events resolution for every entry point ─────────────

# Runs autodetect_schema() when schema = "auto", validates the schema class,
# applies per-field precedence (explicit arg > schema field > hardcoded
# default), and requires state_events to end up non-NULL (aborting with the
# discovery-error listing if not). Returns the resolved values as a list.
#
# missing() cannot be forwarded across function calls, so every *_missing
# flag must be captured by the caller in ITS OWN frame, e.g.
# `time_col_missing = missing(time_col)`.
resolve_entry_args <- function(data, schema,
                               state_events, state_events_missing,
                               time_col, time_col_missing,
                               case_col, case_col_missing,
                               act_type_col, act_type_col_missing,
                               activity_col, activity_col_missing) {

  if (identical(schema, "auto")) {
    schema <- autodetect_schema(
      data,
      state_events = if (state_events_missing) NULL else state_events
    )
  }

  if (!is.null(schema) && !inherits(schema, "event_log_schema")) {
    cli::cli_abort(c(
      "{.arg schema} must be an {.cls event_log_schema} object, the string
       {.val auto}, or {.code NULL}.",
      "x" = "You supplied an object of class {.cls {class(schema)}}."
    ))
  }

  if (state_events_missing) state_events <- NULL

  if (!is.null(schema)) {
    if (time_col_missing     && !is.null(schema$time_col))     time_col     <- schema$time_col
    if (case_col_missing     && !is.null(schema$case_col))     case_col     <- schema$case_col
    if (act_type_col_missing && !is.null(schema$act_type_col)) act_type_col <- schema$act_type_col
    if (activity_col_missing && !is.null(schema$activity_col)) activity_col <- schema$activity_col
    if (is.null(state_events) && !is.null(schema$state_events)) state_events <- schema$state_events
  }

  state_events <- require_state_events(state_events, data, act_type_col)

  list(
    state_events = state_events,
    time_col     = time_col,
    case_col     = case_col,
    act_type_col = act_type_col,
    activity_col = activity_col
  )
}


# ── Case resolution (§4.3) ────────────────────────────────────────────────────

# Resolve `case_id` against `cols$case`, applying the single-series and
# single-case-auto-pick ergonomics. Returns the resolved case_id, or NULL when
# cols$case is NULL (the whole of `data` is one unnamed series).
resolve_case_id <- function(data, cols, case_id) {
  if (is.null(cols$case)) {
    if (!is.null(case_id)) {
      cli::cli_abort(c(
        "{.arg case_id} was supplied but {.code case_col = NULL} says the
         data has no case column."
      ))
    }
    return(NULL)
  }

  if (!cols$case %in% names(data)) {
    cli::cli_abort(c(
      "{.arg case_col} {.val {cols$case}} was not found in {.arg data}.",
      "i" = "Columns present in {.arg data}: {.val {names(data)}}",
      "i" = "If the data is a single series with no id column, pass
             {.code case_col = NULL}."
    ))
  }

  if (is.null(case_id)) {
    available_ids <- unique(data[[cols$case]])

    if (length(available_ids) == 1) {
      cli::cli_inform(c(
        "i" = "{.arg case_id} not supplied; using the only case {.val {available_ids}}."
      ))
      return(available_ids)
    }

    shown <- if (length(available_ids) > 10) {
      c(utils::head(available_ids, 10), cli::symbol$ellipsis)
    } else {
      as.character(available_ids)
    }
    cli::cli_abort(c(
      "{.arg case_id} not supplied, and column {.field {cols$case}} has
       {length(available_ids)} distinct values.",
      "i" = "First 10: {.val {shown}}",
      "i" = "Pass {.arg case_id}, or compare cases with {.fn plot_cohort_timeline}."
    ))
  }

  if (length(case_id) != 1L || is.na(case_id)) {
    cli::cli_abort(c(
      "{.arg case_id} must be a single non-missing value.",
      "i" = "To visualise several cases, call the function once per case."
    ))
  }

  available_ids <- unique(data[[cols$case]])
  if (!case_id %in% available_ids) {
    shown <- if (length(available_ids) > 10) {
      c(utils::head(available_ids, 10), cli::symbol$ellipsis)
    } else {
      as.character(available_ids)
    }
    cli::cli_abort(c(
      "{.val {case_id}} was not found in column {.field {cols$case}}.",
      "i" = "Available case IDs (first 10): {.val {shown}}"
    ))
  }

  case_id
}


# ── validate_event_log ────────────────────────────────────────────────────────

validate_event_log <- function(data, cols, case_id, state_events,
                               tz = "UTC") {

  # ── 1. data must be a data frame / tibble ──────────────────────────────────
  if (!is.data.frame(data)) {
    cli::cli_abort(c(
      "{.arg data} must be a data frame or tibble.",
      "x" = "You supplied an object of class {.cls {class(data)}}."
    ))
  }

  # ── 2. Required columns must exist ─────────────────────────────────────────
  # unlist() drops NULL list elements (cols$case when case_col = NULL,
  # cols$lane unless swimlanes were requested), so those roles are simply not
  # required. cols$case is excluded here and checked separately by
  # resolve_case_id() below, which gives a case_col-specific hint
  # ("pass case_col = NULL for a single series") instead of this generic
  # message.
  required <- unlist(cols[setdiff(names(cols), "case")], use.names = FALSE)
  missing  <- setdiff(required, names(data))

  if (length(missing) > 0) {
    cli::cli_abort(c(
      "The following required columns are missing from {.arg data}:",
      "x" = "{.val {missing}}",
      "i" = "Columns present in {.arg data}: {.val {names(data)}}"
    ))
  }

  # ── 3. Resolve and filter to a single case (§4.3), or keep the whole
  #        dataset as one unnamed series when cols$case is NULL ─────────────
  case_id <- resolve_case_id(data, cols, case_id)

  if (is.null(cols$case)) {
    case_data <- data
  } else {
    # .env$case_id (not bare case_id) — a data mask resolves unqualified names
    # against columns before the calling environment, so if the case column
    # happens to be named "case_id" (a very natural choice, and exactly what
    # pivot_events_longer()'s docs use), a bare `case_id` here would silently
    # compare the column to itself instead of to the argument.
    case_data <- dplyr::filter(data, .data[[cols$case]] == .env$case_id)

    if (nrow(case_data) == 0) {
      cli::cli_abort("Filtering to case {.val {case_id}} produced an empty data frame.")
    }
  }

  # ── 4. Coerce timestamp to POSIXct ────────────────────────────────────────
  case_data[[cols$time]] <- coerce_datetime_column(case_data[[cols$time]], cols$time, tz = tz)

  # Warn (not abort) if duplicate timestamps exist — stable sort handles them
  n_dupes <- sum(duplicated(case_data[[cols$time]]))
  if (n_dupes > 0) {
    cli::cli_inform(c(
      "i" = "{n_dupes} duplicate timestamp(s) in the data. Row order preserved within ties."
    ))
  }

  # ── 5. Stable sort by timestamp ───────────────────────────────────────────
  # Record original row position so ties are broken deterministically
  case_data <- case_data |>
    dplyr::mutate(.orig_row = dplyr::row_number()) |>
    dplyr::arrange(.data[[cols$time]], .orig_row)

  # ── 6. At least one state event must match state_events ───────────────────
  state_rows <- dplyr::filter(case_data, .data[[cols$act_type]] %in% state_events)

  if (nrow(state_rows) == 0) {
    present    <- unique(case_data[[cols$act_type]])
    suggestions <- suggest_matches(state_events, present)

    hint <- if (length(suggestions) > 0) {
      cli::format_inline("Did you mean: {.val {suggestions}}?")
    } else {
      cli::format_inline(
        "Distinct {.field {cols$act_type}} values: {describe_act_types(case_data, cols$act_type)}"
      )
    }

    cli::cli_abort(c(
      "No rows in {.field {cols$act_type}} match {.arg state_events}.",
      "x" = "Supplied: {.val {state_events}}",
      "i" = hint
    ))
  }

  # ── 7. State events must have non-empty activity ──────────────────────────
  bad_activity <- state_rows |>
    dplyr::filter(is.na(.data[[cols$activity]]) |
                    trimws(.data[[cols$activity]]) == "") |>
    dplyr::pull(.orig_row)

  if (length(bad_activity) > 0) {
    cli::cli_abort(c(
      "State events must have a non-empty {.field {cols$activity}} (state name).",
      "x" = "Offending original row(s): {.val {bad_activity}}"
    ))
  }

  # Resolution (§4.3: NULL, an auto-picked single case, or a validated
  # explicit case_id) happened above and is not otherwise recoverable from
  # `case_data` when cols$case is NULL — carry it back to the caller so
  # entry points can build titles/summaries without re-running resolution
  # (which would re-emit its cli_inform() messages).
  attr(case_data, "case_id") <- case_id

  case_data
}
