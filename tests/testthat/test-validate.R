# test-validate.R — Tests for validate_event_log()
#
# Run with: testthat::test_file("tests/testthat/test-validate.R")

library(testthat)
library(dplyr)

# ── Shared test fixture ────────────────────────────────────────────────────────

make_valid_log <- function() {
  tibble::tibble(
    caseID    = "SP-001",
    K_Number  = "K001",
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
  case     = "caseID",
  patient  = "K_Number"
)

loc_cats <- c("ed_location_move", "location_move")

# ── 1. data type check ────────────────────────────────────────────────────────

test_that("non-data-frame input aborts with informative message", {
  expect_error(
    validate_event_log(list(a = 1), cols, "SP-001", loc_cats),
    regexp = "data frame or tibble"
  )
})

# ── 2. Missing columns ────────────────────────────────────────────────────────

test_that("missing column produces error listing missing and present columns", {
  bad <- make_valid_log() |> dplyr::select(-act_type)
  err <- expect_error(validate_event_log(bad, cols, "SP-001", loc_cats))
  expect_match(conditionMessage(err), "act_type")
})

# ── 3. Unknown case_id ────────────────────────────────────────────────────────

test_that("unknown case_id aborts and shows available IDs", {
  err <- expect_error(
    validate_event_log(make_valid_log(), cols, "SP-999", loc_cats)
  )
  expect_match(conditionMessage(err), "SP-001")
})

# ── 4. Timestamp coercion ─────────────────────────────────────────────────────

test_that("character timestamps that parse cleanly are accepted", {
  log <- make_valid_log() |>
    dplyr::mutate(timestamp = as.character(timestamp))
  expect_no_error(validate_event_log(log, cols, "SP-001", loc_cats))
})

test_that("unparseable timestamp aborts and names the bad row", {
  log <- make_valid_log() |>
    dplyr::mutate(timestamp = as.character(timestamp))
  log$timestamp[2] <- "not-a-date"
  err <- expect_error(validate_event_log(log, cols, "SP-001", loc_cats))
  expect_match(conditionMessage(err), "parse")
})

# ── 5. No location events ─────────────────────────────────────────────────────

test_that("no matching location act_types aborts with near-match suggestion", {
  log <- make_valid_log() |>
    dplyr::mutate(act_type = dplyr::recode(
      act_type,
      "ed_location_move" = "obs",
      "location_move"    = "clerk_review"
    ))
  err <- expect_error(
    validate_event_log(log, cols, "SP-001", loc_cats)
  )
  expect_match(conditionMessage(err), "location_categories")
})

# ── 6. Empty activity on location move ───────────────────────────────────────

test_that("NA activity on a location move aborts", {
  log <- make_valid_log()
  log$activity[1] <- NA_character_   # first row is ed_location_move
  err <- expect_error(validate_event_log(log, cols, "SP-001", loc_cats))
  expect_match(conditionMessage(err), "non-empty")
})

test_that("blank activity on a location move aborts", {
  log <- make_valid_log()
  log$activity[1] <- "   "
  err <- expect_error(validate_event_log(log, cols, "SP-001", loc_cats))
  expect_match(conditionMessage(err), "non-empty")
})

# ── 7. Multiple patients under one caseID ────────────────────────────────────

test_that("multiple K_Numbers under one caseID warns but does not abort", {
  log <- make_valid_log()
  log$K_Number[3] <- "K002"  # introduce a second patient on same spell
  expect_warning(
    validate_event_log(log, cols, "SP-001", loc_cats),
    regexp = "2 distinct"
  )
})

# ── 8. Stable sort on duplicate timestamps ────────────────────────────────────

test_that("duplicate timestamps are sorted stably (row order preserved within tie)", {
  log <- make_valid_log()
  # Give rows 2 and 3 the same timestamp
  log$timestamp[3] <- log$timestamp[2]
  result <- validate_event_log(log, cols, "SP-001", loc_cats)
  # After stable sort, original row 2 should still precede original row 3
  tied <- result |> dplyr::filter(timestamp == log$timestamp[2])
  expect_equal(tied$activity, c("BP check", "Ward"))
})

# ── 9. Happy path ─────────────────────────────────────────────────────────────

test_that("valid log returns a tibble for the correct spell only", {
  log <- dplyr::bind_rows(
    make_valid_log(),
    make_valid_log() |> dplyr::mutate(caseID = "SP-002", K_Number = "K002")
  )
  result <- validate_event_log(log, cols, "SP-001", loc_cats)
  expect_true(is.data.frame(result))
  expect_equal(unique(result$caseID), "SP-001")
})

test_that("returned tibble is sorted ascending by timestamp", {
  log <- make_valid_log() |>
    dplyr::arrange(dplyr::desc(timestamp))  # deliberately reversed
  result <- validate_event_log(log, cols, "SP-001", loc_cats)
  expect_true(all(diff(as.numeric(result$timestamp)) >= 0))
})

# ── 10. Case column literally named "case_id" (data-mask collision) ─────────

test_that("filtering works when the case column is itself named case_id", {
  # dplyr::filter()'s data mask resolves a bare `case_id` against a data
  # column of that name before the function argument; validate_event_log()
  # must filter correctly regardless of what the case column is called.
  log <- tibble::tibble(
    case_id   = c("C1", "C1", "C2"),
    timestamp = as.POSIXct(c("2024-01-01 08:00", "2024-01-01 09:00",
                             "2024-01-01 08:00"), tz = "UTC"),
    act_type  = c("location_move", "obs", "location_move"),
    activity  = c("ED", "BP check", "ED")
  )
  cols2 <- list(time = "timestamp", act_type = "act_type",
               activity = "activity", case = "case_id", patient = NULL)

  result <- validate_event_log(log, cols2, "C1", loc_cats)
  expect_equal(unique(result$case_id), "C1")
  expect_equal(nrow(result), 2)
})
