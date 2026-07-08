# test-transform-lanes.R — Stage 4 swimlane tests.
#
# Covers the lane-aware path of derive_point_events() (vertical arithmetic and
# lane ordering), the null path staying byte-identical to the pre-Stage-4
# midline behaviour, conditional y-axis visibility, and a universal render gate
# with lanes + duration labels + reference lines switched on together.
#
# Run with: testthat::test_file("tests/testthat/test-transform-lanes.R")

library(testthat)
library(dplyr)
library(ggplot2)

# ── Shared fixtures ─────────────────────────────────────────────────────────────

t0 <- as.POSIXct("2024-01-01 08:00:00", tz = "UTC")
hrs <- function(h) t0 + h * 3600

loc_cats <- c("ed_location_move", "location_move")

cols_base <- list(
  time     = "timestamp",
  act_type = "act_type",
  activity = "activity",
  case     = "caseID",
  patient  = "K_Number"
)
cols_lane <- c(cols_base, list(lane = "lane"))

# One ED location box; four point events across three lanes.
# First-appearance lane order: Nursing, Medical, Diagnostics.
lane_log <- function() {
  tibble::tibble(
    caseID    = "SP-001",
    K_Number  = "K001",
    timestamp = c(hrs(0), hrs(1), hrs(2), hrs(3), hrs(4)),
    act_type  = c("ed_location_move", "obs", "clerk_review",
                  "test_ordered", "obs"),
    activity  = c("ED", "Obs 1", "Dr review", "Bloods", "Obs 2"),
    lane      = c("Nursing", "Nursing", "Medical", "Diagnostics", "Nursing")
  )
}

# ── Lane y arithmetic (hand-computed for 3 lanes) ───────────────────────────────

test_that("lane y positions match the hand-computed band centres", {
  log   <- lane_log()
  boxes <- derive_location_boxes(log, cols_lane, loc_cats, box_height = 1)
  evts  <- derive_point_events(log, boxes, cols_lane, loc_cats, box_height = 1)

  # base = 1.3, lane_gap = 0.05, lane_height = 1.
  # y_i = base + i*gap + (i - 0.5)*height
  #   Nursing     (i=1) -> 1.3 + 0.05 + 0.5 = 1.85
  #   Medical     (i=2) -> 1.3 + 0.10 + 1.5 = 2.90
  #   Diagnostics (i=3) -> 1.3 + 0.15 + 2.5 = 3.95
  y_of <- function(act) evts$y[evts$activity == act]
  expect_equal(y_of("Obs 1"),     1.85)
  expect_equal(y_of("Dr review"), 2.90)
  expect_equal(y_of("Bloods"),    3.95)
  # Second Nursing event lands back on the Nursing lane.
  expect_equal(y_of("Obs 2"),     1.85)
})

test_that("lane column is stored as a factor in first-appearance order", {
  log   <- lane_log()
  boxes <- derive_location_boxes(log, cols_lane, loc_cats, box_height = 1)
  evts  <- derive_point_events(log, boxes, cols_lane, loc_cats, box_height = 1)

  expect_true(is.factor(evts$lane))
  expect_equal(levels(evts$lane), c("Nursing", "Medical", "Diagnostics"))
})

test_that("a factor lane column pins an explicit lane ordering", {
  log <- lane_log()
  # Force the reverse ordering; lane 1 (bottom) is now Diagnostics.
  log$lane <- factor(log$lane,
                     levels = c("Diagnostics", "Medical", "Nursing"))

  boxes <- derive_location_boxes(log, cols_lane, loc_cats, box_height = 1)
  evts  <- derive_point_events(log, boxes, cols_lane, loc_cats, box_height = 1)

  # Diagnostics is now lane 1 -> 1.85, Nursing lane 3 -> 3.95.
  expect_equal(evts$y[evts$activity == "Bloods"], 1.85)
  expect_equal(evts$y[evts$activity == "Obs 1"],  3.95)
  expect_equal(levels(evts$lane),
               c("Diagnostics", "Medical", "Nursing"))
})

test_that("lane_gap and lane_height feed straight into the arithmetic", {
  log   <- lane_log()
  boxes <- derive_location_boxes(log, cols_lane, loc_cats, box_height = 1)
  evts  <- derive_point_events(log, boxes, cols_lane, loc_cats,
                               box_height = 1, lane_height = 2, lane_gap = 0.1)

  # base = 1.3; y_i = 1.3 + i*0.1 + (i - 0.5)*2
  #   Nursing (i=1) -> 1.3 + 0.1 + 1 = 2.4
  #   Medical (i=2) -> 1.3 + 0.2 + 3 = 4.5
  expect_equal(evts$y[evts$activity == "Obs 1"],     2.4)
  expect_equal(evts$y[evts$activity == "Dr review"], 4.5)
})

# ── Null path: byte-identical to the pre-Stage-4 midline ────────────────────────

test_that("lane_col = NULL keeps every event on the box midline", {
  log   <- lane_log()
  boxes <- derive_location_boxes(log, cols_base, loc_cats, box_height = 1)
  evts  <- derive_point_events(log, boxes, cols_base, loc_cats, box_height = 1)

  expect_true(all(evts$y == 0.5))          # box_height / 2
  expect_false("lane" %in% names(evts))    # no lane column added
})

test_that("empty point-event set still returns a lane column when lanes active", {
  # Location moves only — no point events.
  log <- tibble::tibble(
    caseID    = "SP-001",
    K_Number  = "K001",
    timestamp = c(hrs(0), hrs(2)),
    act_type  = c("ed_location_move", "location_move"),
    activity  = c("ED", "Ward"),
    lane      = c("Nursing", "Nursing")
  )
  boxes <- derive_location_boxes(log, cols_lane, loc_cats, box_height = 1)
  evts  <- derive_point_events(log, boxes, cols_lane, loc_cats, box_height = 1)

  expect_equal(nrow(evts), 0L)
  expect_true("lane" %in% names(evts))
})

# ── Plot-level fixture ──────────────────────────────────────────────────────────

plot_lane_log <- function() {
  tibble::tibble(
    caseID    = "SP-001",
    K_Number  = "K001",
    timestamp = c(hrs(0), hrs(0.5), hrs(1), hrs(1.5), hrs(4), hrs(4.5), hrs(6)),
    act_type  = c("ed_location_move", "obs", "clerk_review", "test_ordered",
                  "location_move", "obs", "clerk_review"),
    activity  = c("ED", "Triage obs", "Dr review", "Bloods",
                  "Ward", "Ward obs", "Consultant review"),
    lane      = c("Nursing", "Nursing", "Medical", "Diagnostics",
                  "Nursing", "Nursing", "Medical")
  )
}

# ── Conditional y-axis visibility ───────────────────────────────────────────────

test_that("y-axis text/ticks stay blank without lanes", {
  p <- plot_patient_journey(plot_lane_log(), case_id = "SP-001")
  expect_true(inherits(p$theme$axis.text.y,  "element_blank"))
  expect_true(inherits(p$theme$axis.ticks.y, "element_blank"))
})

test_that("y-axis text/ticks become visible with lanes", {
  p <- plot_patient_journey(plot_lane_log(), case_id = "SP-001",
                            lane_col = "lane")
  expect_false(inherits(p$theme$axis.text.y,  "element_blank"))
  expect_false(inherits(p$theme$axis.ticks.y, "element_blank"))
  expect_true(inherits(p$theme$axis.text.y, "element_text"))
})

# ── Universal render gate ───────────────────────────────────────────────────────

test_that("lanes render cleanly (universal gate)", {
  p <- plot_patient_journey(plot_lane_log(), case_id = "SP-001",
                            lane_col = "lane")
  expect_s3_class(p, "ggplot")
  expect_no_warning(ggplot2::ggplot_build(p))
})

test_that("lanes + duration labels + reference lines render together (gate)", {
  p <- plot_patient_journey(
    plot_lane_log(), case_id = "SP-001",
    lane_col        = "lane",
    show_duration   = TRUE,
    reference_lines = data.frame(offset_hours = 4, label = "4h target")
  )
  expect_s3_class(p, "ggplot")
  expect_no_warning(ggplot2::ggplot_build(p))
})

# ── lane_col validation ─────────────────────────────────────────────────────────

test_that("an unknown lane_col aborts with a helpful message", {
  expect_error(
    plot_patient_journey(plot_lane_log(), case_id = "SP-001",
                         lane_col = "laen"),
    regexp = "lane_col"
  )
})
