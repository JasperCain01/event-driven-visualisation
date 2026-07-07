# test-render.R — Tests for Stage 1 visual quick-win features.
# This file currently covers Stage 1f (colourblind-safe default palette).
# Later Stage 1 sub-stages append their own tests here.
#
# Run with: testthat::test_file("tests/testthat/test-render.R")

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

# ── 1f. journey_palette() — "okabe" style (new default) ────────────────────────

test_that("okabe locations and events never share a hex for co-indexed levels", {
  loc_cols <- journey_palette(c("A", "B", "C"), "location", "okabe")
  evt_cols <- journey_palette(c("A", "B", "C"), "event", "okabe")

  expect_length(setdiff(unname(loc_cols), unname(evt_cols)), 3L)
})

test_that("okabe events are the Okabe-Ito hues offset by 4 positions", {
  evt_cols <- journey_palette(c("e1", "e2", "e3"), "event", "okabe")
  # event 1 gets colour index 5 (1-indexed), wrapping past 8
  expect_equal(unname(evt_cols), .okabe_ito[c(5, 6, 7)])
})

test_that("okabe locations are lightened toward white, not the raw saturated hue", {
  loc_cols <- journey_palette(c("l1", "l2"), "location", "okabe")
  expect_false(unname(loc_cols[1]) %in% .okabe_ito)
  expect_true(all(grepl("^#[0-9A-Fa-f]{6,8}$", loc_cols)))
})

test_that("okabe palette recycles past 8 distinct levels without erroring", {
  levs <- paste0("L", 1:10)
  expect_no_error(loc_cols <- journey_palette(levs, "location", "okabe"))
  expect_no_error(evt_cols <- journey_palette(levs, "event", "okabe"))
  expect_length(loc_cols, 10L)
  expect_length(evt_cols, 10L)
})

test_that("journey_palette() defaults to palette_style = 'okabe'", {
  expect_equal(
    journey_palette(c("A", "B"), "event"),
    journey_palette(c("A", "B"), "event", "okabe")
  )
})

# ── 1f. journey_palette() — "brewer" style (opt-out, old default) ──────────────

test_that("brewer style reproduces the prior Set2/Dark2 output exactly", {
  skip_if_not_installed("RColorBrewer")

  levs <- c("A", "B", "C")
  loc_cols <- journey_palette(levs, "location", "brewer")
  evt_cols <- journey_palette(levs, "event", "brewer")

  expect_equal(unname(loc_cols), RColorBrewer::brewer.pal(3, "Set2"))
  expect_equal(unname(evt_cols), RColorBrewer::brewer.pal(3, "Dark2"))
})

test_that("invalid palette_style aborts with a clear match.arg error", {
  expect_error(
    journey_palette(c("A", "B"), "location", "viridis"),
    regexp = "should be one of"
  )
})

# ── 1f. end-to-end rendering ────────────────────────────────────────────────────

test_that("default (okabe) render builds without warning", {
  p <- plot_patient_journey(small_log(), case_id = "SP-001")
  expect_no_warning(ggplot2::ggplot_build(p))
})

test_that("palette_style = 'brewer' render builds without warning", {
  p <- plot_patient_journey(small_log(), case_id = "SP-001", palette_style = "brewer")
  expect_no_warning(ggplot2::ggplot_build(p))
})
