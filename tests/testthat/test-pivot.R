# test-pivot.R — Tests for pivot_events_longer()
#
# Run with: testthat::test_file("tests/testthat/test-pivot.R")

library(testthat)
library(dplyr)
library(ggplot2)

source("../../R/utils.R")
source("../../R/validate.R")
source("../../R/transform.R")
source("../../R/render.R")
source("../../R/plot_patient_journey.R")
source("../../R/pivot_wide.R")

# ── Shared fixture ────────────────────────────────────────────────────────────
# 3 cases, cols case_id, patient_id, arrival_time, triage_time, ward_time,
# discharge_time, diagnosis.

t0 <- as.POSIXct("2024-01-01 08:00:00", tz = "UTC")
hrs <- function(h) t0 + h * 3600

make_wide_fixture <- function() {
  tibble::tibble(
    case_id        = c("C1", "C2", "C3"),
    patient_id     = c("P1", "P2", "P3"),
    arrival_time   = c(hrs(0),   hrs(1),   hrs(2)),
    triage_time    = c(hrs(0.5), hrs(1.5), NA),       # never triaged for C3
    ward_time      = c(hrs(1),   hrs(2.5), hrs(3)),
    discharge_time = c(hrs(2),   hrs(4),   hrs(5)),
    diagnosis      = c("Chest pain", "Fall", "Sepsis")
  )
}

time_cols <- c("arrival_time", "triage_time", "ward_time", "discharge_time")


# ── Basic pivot ────────────────────────────────────────────────────────────────

test_that("basic pivot produces correct row count and act_type values", {
  long <- suppressMessages(pivot_events_longer(
    make_wide_fixture(),
    case_col      = "case_id",
    time_cols     = time_cols,
    patient_col   = "patient_id",
    location_cols = c("arrival_time", "ward_time")
  ))

  # 3 + 3 + 2 = 8 rows for arrival/ward/discharge (always present) plus
  # triage for C1/C2 only (C3's is NA and dropped) = 3*3 + 2 = 11
  expect_equal(nrow(long), 11)

  expect_true(all(c("case_id", "patient_id", "timestamp", "act_type",
                    "activity", "diagnosis") %in% names(long)))

  arrival_rows <- long |> dplyr::filter(activity == "Arrival")
  expect_equal(unique(arrival_rows$act_type), "location_move")

  ward_rows <- long |> dplyr::filter(activity == "Ward")
  expect_equal(unique(ward_rows$act_type), "location_move")

  triage_rows <- long |> dplyr::filter(case_id == "C1", act_type != "location_move",
                                       act_type != "discharge_time")
  expect_true(nrow(triage_rows) >= 1)
})

test_that("milestone labels are suffix-stripped, not raw column names", {
  long <- suppressMessages(pivot_events_longer(
    make_wide_fixture(),
    case_col  = "case_id",
    time_cols = time_cols
  ))

  expect_true("Arrival" %in% long$activity)
  expect_false("Arrival Time" %in% long$activity)
  expect_true("Triage" %in% long$activity)
  expect_true("Ward" %in% long$activity)
  expect_true("Discharge" %in% long$activity)
})

test_that("act_type_map and activity_map override the defaults", {
  long <- suppressMessages(pivot_events_longer(
    make_wide_fixture(),
    case_col      = "case_id",
    time_cols     = time_cols,
    location_cols = c("arrival_time", "ward_time"),
    act_type_map  = c(triage_time = "triage_event"),
    activity_map  = c(discharge_time = "Discharged Home")
  ))

  triage_rows <- long |> dplyr::filter(act_type == "triage_event")
  expect_true(nrow(triage_rows) > 0)

  discharge_rows <- long |> dplyr::filter(activity == "Discharged Home")
  expect_true(nrow(discharge_rows) > 0)
})


# ── Validation errors ────────────────────────────────────────────────────────

test_that("missing case_col aborts naming missing and present columns", {
  err <- expect_error(
    pivot_events_longer(make_wide_fixture(), case_col = "nope", time_cols = time_cols)
  )
  expect_match(conditionMessage(err), "nope")
  expect_match(conditionMessage(err), "case_id")
})

test_that("missing time_cols entry aborts naming it", {
  err <- expect_error(
    pivot_events_longer(make_wide_fixture(), case_col = "case_id",
                        time_cols = c("arrival_time", "not_a_column"))
  )
  expect_match(conditionMessage(err), "not_a_column")
})

test_that("location_cols not a subset of time_cols aborts naming the offender", {
  err <- expect_error(
    pivot_events_longer(make_wide_fixture(), case_col = "case_id",
                        time_cols = c("arrival_time", "ward_time"),
                        location_cols = c("arrival_time", "discharge_time"))
  )
  expect_match(conditionMessage(err), "discharge_time")
})


# ── NA milestone handling ────────────────────────────────────────────────────

test_that("NA milestone timestamps are dropped with an informative message", {
  msg <- capture_messages(
    long <- pivot_events_longer(make_wide_fixture(), case_col = "case_id",
                                time_cols = time_cols)
  )
  expect_true(any(grepl("triage_time", msg)))
  expect_false(any(is.na(long$timestamp)))
  # C3 never triaged -> only arrival/ward/discharge rows for C3
  expect_equal(nrow(long |> dplyr::filter(case_id == "C3")), 3)
})

test_that("drop_na = FALSE keeps NA-timestamp rows", {
  long <- suppressMessages(pivot_events_longer(
    make_wide_fixture(), case_col = "case_id", time_cols = time_cols,
    drop_na = FALSE
  ))
  expect_true(any(is.na(long$timestamp)))
})


# ── Equal-timestamp milestones (exercises the Stage 0.5 stagger fix) ────────

test_that("equal-timestamp milestones pivot cleanly and render under the universal gate", {
  wide <- make_wide_fixture()
  wide$triage_time[1] <- wide$arrival_time[1]   # C1: arrival == triage

  long <- suppressMessages(pivot_events_longer(
    wide, case_col = "case_id", time_cols = time_cols,
    patient_col = "patient_id", location_cols = c("arrival_time", "ward_time")
  ))

  p <- plot_patient_journey(
    long, case_id = "C1", case_col = "case_id", patient_col = "patient_id",
    time_col = "timestamp", act_type_col = "act_type", activity_col = "activity"
  )
  expect_s3_class(p, "ggplot")
  expect_no_warning(ggplot2::ggplot_build(p))
})


# ── End-to-end into plot_patient_journey() ──────────────────────────────────

test_that("pivoted output feeds plot_patient_journey() directly", {
  long <- suppressMessages(pivot_events_longer(
    make_wide_fixture(), case_col = "case_id", time_cols = time_cols,
    patient_col = "patient_id", location_cols = c("arrival_time", "ward_time")
  ))

  p <- plot_patient_journey(
    long, case_id = "C2", case_col = "case_id", patient_col = "patient_id",
    time_col = "timestamp", act_type_col = "act_type", activity_col = "activity"
  )
  expect_s3_class(p, "ggplot")
  expect_no_warning(ggplot2::ggplot_build(p))
})

test_that("passthrough columns (e.g. diagnosis) survive the pivot untouched", {
  long <- suppressMessages(pivot_events_longer(
    make_wide_fixture(), case_col = "case_id", time_cols = time_cols,
    patient_col = "patient_id"
  ))

  expect_true("diagnosis" %in% names(long))
  c1_diag <- unique(long$diagnosis[long$case_id == "C1"])
  expect_equal(c1_diag, "Chest pain")
})
