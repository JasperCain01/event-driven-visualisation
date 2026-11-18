# test-validate.R — Tests for validate_event_log()
#
# Run with: testthat::test_file("tests/testthat/test-validate.R")

library(testthat)
library(dplyr)

# ── Shared test fixture ────────────────────────────────────────────────────────

make_valid_log <- function() {
  tibble::tibble(
    case_id   = "SP-001",
    timestamp = as.POSIXct(c("2024-01-01 08:00", "2024-01-01 09:00",
                              "2024-01-01 10:00", "2024-01-01 12:00"),
                            tz = "UTC"),
    act_type  = c("ed_location_move", "obs", "location_move", "clerk_review"),
    activity  = c("ED", "BP check", "Ward", "Dr visit")
  )
}

cols <- list(
  time     = "timestamp",
  act_type = "act_type",
  activity = "activity",
  case     = "case_id"
)

state_evts <- c("ed_location_move", "location_move")

# ── 1. data type check ────────────────────────────────────────────────────────

test_that("non-data-frame input aborts with informative message", {
  expect_error(
    validate_event_log(list(a = 1), cols, "SP-001", state_evts),
    regexp = "data frame or tibble"
  )
})

# ── 2. Missing columns ────────────────────────────────────────────────────────

test_that("missing column produces error listing missing and present columns", {
  bad <- make_valid_log() |> dplyr::select(-act_type)
  err <- expect_error(validate_event_log(bad, cols, "SP-001", state_evts))
  expect_match(conditionMessage(err), "act_type")
})

# ── 3. Unknown case_id ────────────────────────────────────────────────────────

test_that("unknown case_id aborts and shows available IDs", {
  err <- expect_error(
    validate_event_log(make_valid_log(), cols, "SP-999", state_evts)
  )
  expect_match(conditionMessage(err), "SP-001")
})

# ── 4. Timestamp coercion ─────────────────────────────────────────────────────

test_that("character timestamps that parse cleanly are accepted", {
  log <- make_valid_log() |>
    dplyr::mutate(timestamp = as.character(timestamp))
  expect_no_error(validate_event_log(log, cols, "SP-001", state_evts))
})

test_that("unparseable timestamp aborts and names the bad row", {
  log <- make_valid_log() |>
    dplyr::mutate(timestamp = as.character(timestamp))
  log$timestamp[2] <- "not-a-date"
  err <- expect_error(validate_event_log(log, cols, "SP-001", state_evts))
  expect_match(conditionMessage(err), "parse")
})

# ── 5. No state events ────────────────────────────────────────────────────────

test_that("no matching state act_types aborts with near-match suggestion", {
  log <- make_valid_log() |>
    dplyr::mutate(act_type = dplyr::recode(
      act_type,
      "ed_location_move" = "obs",
      "location_move"    = "clerk_review"
    ))
  err <- expect_error(
    validate_event_log(log, cols, "SP-001", state_evts)
  )
  expect_match(conditionMessage(err), "state_events")
})

# ── 6. Empty activity on state event ─────────────────────────────────────────

test_that("NA or blank activity on a state event aborts", {
  log <- make_valid_log()
  log$activity[1] <- NA_character_   # first row is ed_location_move
  err <- expect_error(validate_event_log(log, cols, "SP-001", state_evts))
  expect_match(conditionMessage(err), "non-empty")

  log$activity[1] <- "   "
  err <- expect_error(validate_event_log(log, cols, "SP-001", state_evts))
  expect_match(conditionMessage(err), "non-empty")
})

# ── 7. Stable sort on duplicate timestamps ────────────────────────────────────

test_that("the log is sorted ascending by time, stably within duplicate timestamps", {
  log <- make_valid_log() |>
    dplyr::arrange(dplyr::desc(timestamp))  # deliberately reversed
  result <- validate_event_log(log, cols, "SP-001", state_evts)
  expect_true(all(diff(as.numeric(result$timestamp)) >= 0))

  # Give rows 2 and 3 the same timestamp: original row 2 must still precede row 3.
  log <- make_valid_log()
  log$timestamp[3] <- log$timestamp[2]
  result <- validate_event_log(log, cols, "SP-001", state_evts)
  tied <- result |> dplyr::filter(timestamp == log$timestamp[2])
  expect_equal(tied$activity, c("BP check", "Ward"))
})

# ── 8. Happy path ─────────────────────────────────────────────────────────────

test_that("valid log returns a tibble for the correct case only", {
  # The fixture's case column is literally named `case_id`, the same name as
  # the function argument. dplyr::filter()'s data mask would resolve a bare
  # `case_id` to the column, so this also guards that collision.
  log <- dplyr::bind_rows(
    make_valid_log(),
    make_valid_log() |> dplyr::mutate(case_id = "SP-002")
  )
  result <- validate_event_log(log, cols, "SP-001", state_evts)
  expect_true(is.data.frame(result))
  expect_equal(unique(result$case_id), "SP-001")
})

# ── 10. Case resolution (§4.3) ────────────────────────────────────────────────

test_that("case_col = NULL keeps the whole data frame as one unnamed series", {
  log <- make_valid_log() |> dplyr::select(-case_id)
  cols_no_case <- list(time = "timestamp", act_type = "act_type",
                       activity = "activity", case = NULL)
  result <- validate_event_log(log, cols_no_case, NULL, state_evts)
  expect_equal(nrow(result), nrow(log))
})

test_that("case_id supplied with case_col = NULL aborts", {
  log <- make_valid_log() |> dplyr::select(-case_id)
  cols_no_case <- list(time = "timestamp", act_type = "act_type",
                       activity = "activity", case = NULL)
  err <- expect_error(validate_event_log(log, cols_no_case, "SP-001", state_evts))
  expect_match(conditionMessage(err), "case_col")
})

test_that("case_id = NULL with a single distinct case auto-resolves it", {
  expect_message(
    result <- validate_event_log(make_valid_log(), cols, NULL, state_evts),
    regexp = "only case"
  )
  expect_equal(attr(result, "case_id"), "SP-001")
})

test_that("case_id = NULL with multiple distinct cases aborts naming them", {
  log <- dplyr::bind_rows(
    make_valid_log(),
    make_valid_log() |> dplyr::mutate(case_id = "SP-002")
  )
  err <- expect_error(validate_event_log(log, cols, NULL, state_evts))
  expect_match(conditionMessage(err), "SP-002")
  expect_match(conditionMessage(err), "plot_cohort_timeline")
})

test_that("missing case_col hints at case_col = NULL for a single series", {
  cols_bad <- list(time = "timestamp", act_type = "act_type",
                   activity = "activity", case = "nope")
  err <- expect_error(validate_event_log(make_valid_log(), cols_bad, "SP-001", state_evts))
  expect_match(conditionMessage(err), "case_col = NULL")
})
