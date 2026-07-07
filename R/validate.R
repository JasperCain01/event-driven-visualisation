# validate.R — Input validation for plot_patient_journey()
#
# validate_event_log() is the single entry point. It performs all checks in a
# deliberate order (cheapest / most likely to fail first) and returns a cleaned,
# single-spell, time-sorted tibble on success, or calls cli::cli_abort() with
# an actionable message on failure.

validate_event_log <- function(data, cols, case_id, location_categories,
                               tz = "UTC") {

  # ── 1. data must be a data frame / tibble ──────────────────────────────────
  if (!is.data.frame(data)) {
    cli::cli_abort(c(
      "{.arg data} must be a data frame or tibble.",
      "x" = "You supplied an object of class {.cls {class(data)}}."
    ))
  }

  # ── 1b. case_id must be a single non-missing value ────────────────────────
  # A vector case_id would crash the bare `if` in check 3 with an obscure
  # "condition has length > 1" error; abort cleanly instead.
  if (length(case_id) != 1L || is.na(case_id)) {
    cli::cli_abort(c(
      "{.arg case_id} must be a single non-missing value.",
      "i" = "To visualise several cases, call the function once per case."
    ))
  }

  # ── 2. Required columns must exist ─────────────────────────────────────────
  required <- unlist(cols, use.names = FALSE)
  missing  <- setdiff(required, names(data))

  if (length(missing) > 0) {
    cli::cli_abort(c(
      "The following required columns are missing from {.arg data}:",
      "x" = "{.val {missing}}",
      "i" = "Columns present in {.arg data}: {.val {names(data)}}"
    ))
  }

  # ── 3. case_id must exist in the case column ───────────────────────────────
  available_ids <- unique(data[[cols$case]])

  if (!case_id %in% available_ids) {
    # Show up to 10 IDs so the message stays readable
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

  # ── 4. Filter to the single spell ─────────────────────────────────────────
  # .env$case_id (not bare case_id) — a data mask resolves unqualified names
  # against columns before the calling environment, so if the case column
  # happens to be named "case_id" (a very natural choice, and exactly what
  # pivot_events_longer()'s docs use), a bare `case_id` here would silently
  # compare the column to itself instead of to the argument.
  spell <- dplyr::filter(data, .data[[cols$case]] == .env$case_id)

  if (nrow(spell) == 0) {
    cli::cli_abort("Filtering to case {.val {case_id}} produced an empty data frame.")
  }

  # ── 5. Multiple patients under one caseID is suspicious ───────────────────
  # cols$patient may be NULL — patient/entity ID is optional for event logs
  # that have no second identifier (e.g. non-clinical processes).
  if (!is.null(cols$patient)) {
    n_patients <- dplyr::n_distinct(spell[[cols$patient]])
    if (n_patients > 1) {
      cli::cli_warn(c(
        "!" = "Case {.val {case_id}} maps to {n_patients} distinct values of {.field {cols$patient}}.",
        "i" = "Expected one patient per spell. Proceeding with all rows."
      ))
    }
  }

  # ── 6. Coerce timestamp to POSIXct ────────────────────────────────────────
  spell[[cols$time]] <- coerce_datetime_column(spell[[cols$time]], cols$time, tz = tz)

  # Warn (not abort) if duplicate timestamps exist — stable sort handles them
  n_dupes <- sum(duplicated(spell[[cols$time]]))
  if (n_dupes > 0) {
    cli::cli_inform(c(
      "i" = "{n_dupes} duplicate timestamp(s) in case {.val {case_id}}. Row order preserved within ties."
    ))
  }

  # ── 7. Stable sort by timestamp ───────────────────────────────────────────
  # Record original row position so ties are broken deterministically
  spell <- spell |>
    dplyr::mutate(.orig_row = dplyr::row_number()) |>
    dplyr::arrange(.data[[cols$time]], .orig_row)

  # ── 8. At least one location event must match location_categories ──────────
  loc_rows <- dplyr::filter(spell, .data[[cols$act_type]] %in% location_categories)

  if (nrow(loc_rows) == 0) {
    present    <- unique(spell[[cols$act_type]])
    suggestions <- suggest_matches(location_categories, present)

    hint <- if (length(suggestions) > 0) {
      cli::format_inline("Did you mean: {.val {suggestions}}?")
    } else {
      cli::format_inline(
        "Present {.field {cols$act_type}} values: {.val {present}}"
      )
    }

    cli::cli_abort(c(
      "No rows in {.field {cols$act_type}} match {.arg location_categories}.",
      "x" = "Supplied: {.val {location_categories}}",
      "i" = hint
    ))
  }

  # ── 9. Location move events must have non-empty activity ──────────────────
  bad_activity <- loc_rows |>
    dplyr::filter(is.na(.data[[cols$activity]]) |
                    trimws(.data[[cols$activity]]) == "") |>
    dplyr::pull(.orig_row)

  if (length(bad_activity) > 0) {
    cli::cli_abort(c(
      "Location-move events must have a non-empty {.field {cols$activity}} (location name).",
      "x" = "Offending original row(s): {.val {bad_activity}}"
    ))
  }

  spell
}
