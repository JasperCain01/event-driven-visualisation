# test-fixes.R — Regression tests for defects found in the 2026-07 review.
# Each test names the defect it guards against. These exercise the full
# pipeline including render, so ggplot2/ggrepel are required.
#
# Run with: testthat::test_file("tests/testthat/test-fixes.R")

library(testthat)
library(dplyr)
library(ggplot2)

source("../../R/utils.R")
source("../../R/validate.R")
source("../../R/transform.R")
source("../../R/render.R")
source("../../R/plot_patient_journey.R")

# ── Shared fixtures ────────────────────────────────────────────────────────────

t0 <- as.POSIXct("2024-01-01 08:00:00", tz = "UTC")
hrs <- function(h) t0 + h * 3600

small_log <- function() {
  tibble::tibble(
    caseID    = "SP-001",
    K_Number  = "K001",
    timestamp = c(hrs(0), hrs(1), hrs(2), hrs(4), hrs(5), hrs(8)),
    act_type  = c("ed_location_move", "obs", "clerk_review",
                  "location_move", "obs", "clerk_review"),
    activity  = c("ED", "Triage obs", "Initial review",
                  "Ward", "Ward obs", "Dr review")
  )
}

same_ts_log <- function() {
  # ED and Ward moves share a timestamp — the zero-width-nudge scenario
  tibble::tibble(
    caseID    = "X",
    K_Number  = "K1",
    timestamp = c(hrs(0), hrs(0), hrs(4)),
    act_type  = c("location_move", "location_move", "obs"),
    activity  = c("ED", "Ward", "Final obs")
  )
}


# ── Defect 1: show_labels dropped every label via y-limit censoring ───────────

test_that("show_labels = TRUE renders without dropping label rows", {
  p <- plot_patient_journey(small_log(), case_id = "SP-001", show_labels = TRUE)
  # Pre-fix, ggplot_build() warned "Removed N rows containing missing values"
  # because labels were nudged below hard scale limits and censored to NA.
  expect_no_warning(built <- ggplot2::ggplot_build(p))
  # The repel layer must carry every event (4 non-location rows)
  layer_rows <- vapply(built$data, nrow, integer(1))
  expect_true(4L %in% layer_rows)
})

test_that("default plot (labels off) also builds without warnings", {
  p <- plot_patient_journey(small_log(), case_id = "SP-001")
  expect_no_warning(ggplot2::ggplot_build(p))
})


# ── Defect 2: terminal state was extended into a fake stay ────────────────────

test_that("terminal_activities gives the final move zero duration, not a median box", {
  log <- small_log() |>
    dplyr::add_row(caseID = "SP-001", K_Number = "K001",
                   timestamp = hrs(9), act_type = "location_move",
                   activity = "Discharged")
  r <- plot_patient_journey(log, case_id = "SP-001",
                            terminal_activities = "Discharged",
                            return_data = TRUE)
  last_box <- r$boxes[nrow(r$boxes), ]
  expect_true(last_box$terminal)
  expect_false(last_box$end_inferred)
  expect_equal(as.numeric(last_box$duration, units = "secs"), 0)
  expect_no_warning(ggplot2::ggplot_build(r$plot))
})

test_that("without terminal_activities the final box end is flagged as inferred", {
  r <- plot_patient_journey(small_log(), case_id = "SP-001", return_data = TRUE)
  expect_true(r$boxes$end_inferred[nrow(r$boxes)])
  expect_false(any(r$boxes$end_inferred[-nrow(r$boxes)]))
})


# ── Defect 3: stored duration falsely reported as unaffected by the nudge ─────

test_that("zero-width box stores true duration 0, and the message says so", {
  expect_message(
    r <- plot_patient_journey(same_ts_log(), case_id = "X", return_data = TRUE),
    regexp = "true value"
  )
  expect_equal(as.numeric(r$boxes$duration[1], units = "secs"), 0)
})


# ── Defect 4: nudged box hidden underneath its successor ──────────────────────

test_that("render-space stagger prevents the nudged box being overlapped", {
  suppressMessages(
    r <- plot_patient_journey(same_ts_log(), case_id = "X", return_data = TRUE)
  )
  # Second box's render start must clear the first box's (nudged) end
  expect_true(r$boxes$xmin_render[2] >= r$boxes$xmax[1])
  # True xmin is untouched — data is never falsified
  expect_equal(r$boxes$xmin[2], r$boxes$xmin[1])
})


# ── Defect 5a: typo'd tail_strategy crashed with an unrelated error ───────────

test_that("invalid tail_strategy aborts with a clear match.arg error", {
  expect_error(
    plot_patient_journey(small_log(), case_id = "SP-001",
                         tail_strategy = "medain"),
    regexp = "should be one of"
  )
})


# ── Defect 5b: excluding all location categories crashed cryptically ──────────

test_that("exclude_categories removing all location events aborts cleanly", {
  expect_error(
    suppressMessages(
      plot_patient_journey(small_log(), case_id = "SP-001",
                           exclude_categories = c("location_move",
                                                  "ed_location_move"))
    ),
    regexp = "No location events remain"
  )
})


# ── Defect 5c: vector case_id crashed with "condition has length > 1" ─────────

test_that("vector case_id aborts with a clear message", {
  expect_error(
    plot_patient_journey(small_log(), case_id = c("SP-001", "SP-002")),
    regexp = "single"
  )
})

test_that("NA case_id aborts with a clear message", {
  expect_error(
    plot_patient_journey(small_log(), case_id = NA_character_),
    regexp = "single"
  )
})


# ── Defect 6: character timestamps silently parsed as UTC ─────────────────────

test_that("tz argument controls parsing of character timestamps", {
  log <- small_log() |> dplyr::mutate(timestamp = format(timestamp, "%Y-%m-%d %H:%M:%S"))
  r <- plot_patient_journey(log, case_id = "SP-001", tz = "Europe/London",
                            return_data = TRUE)
  expect_equal(attr(r$boxes$xmin, "tzone"), "Europe/London")
})

test_that("POSIXct input keeps its own tzone regardless of tz argument", {
  r <- plot_patient_journey(small_log(), case_id = "SP-001",
                            tz = "Australia/Sydney", return_data = TRUE)
  expect_equal(attr(r$boxes$xmin, "tzone"), "UTC")
})


# ── patient_col = NULL support ─────────────────────────────────────────────────

test_that("patient_col = NULL works for logs with no secondary identifier", {
  log <- small_log() |> dplyr::select(-K_Number)
  p <- plot_patient_journey(log, case_id = "SP-001", patient_col = NULL)
  expect_s3_class(p, "ggplot")
  expect_match(p$labels$title, "^Case SP-001$")
})
