# test-cohort.R — Stage 5 cohort-view (faceting) tests.
#
# Covers plot_journey_cohort(): panel counts for NULL vs subset case_ids, the
# align_start rebase (every case's first box at elapsed hour 0), cross-facet
# colour consistency (same location -> same fill in every panel), the max_cases
# guard, and the universal render gate in both absolute and start-aligned modes.
#
# Run with: testthat::test_file("tests/testthat/test-cohort.R")

library(testthat)
library(dplyr)
library(ggplot2)

source("../../R/utils.R")
source("../../R/validate.R")
source("../../R/transform.R")
source("../../R/render.R")
source("../../R/plot_patient_journey.R")
source("../../R/cohort.R")

# ── Shared fixture — 3 cases sharing a common vocabulary of locations ──────────

t0  <- as.POSIXct("2024-01-01 08:00:00", tz = "UTC")
hrs <- function(h) t0 + h * 3600

loc_cats <- c("ed_location_move", "location_move")

# Each case visits ED -> Ward, with one differing (case 3 also visits Theatre).
# Cases start at different absolute times so the absolute-time facets differ but
# align_start collapses them onto one axis.
cohort_log <- function() {
  dplyr::bind_rows(
    tibble::tibble(
      caseID    = "C1", K_Number = "K1",
      timestamp = c(hrs(0), hrs(1), hrs(3)),
      act_type  = c("ed_location_move", "obs", "location_move"),
      activity  = c("ED", "BP check", "Ward")
    ),
    tibble::tibble(
      caseID    = "C2", K_Number = "K2",
      timestamp = c(hrs(24), hrs(24.5), hrs(27)),
      act_type  = c("ed_location_move", "obs", "location_move"),
      activity  = c("ED", "BP check", "Ward")
    ),
    tibble::tibble(
      caseID    = "C3", K_Number = "K3",
      timestamp = c(hrs(50), hrs(51), hrs(53), hrs(56)),
      act_type  = c("ed_location_move", "location_move", "location_move", "obs"),
      activity  = c("ED", "Theatre", "Ward", "BP check")
    )
  )
}

n_panels <- function(p) nrow(ggplot2::ggplot_build(p)$layout$layout)

# ── Panel counts ────────────────────────────────────────────────────────────────

test_that("NULL case_ids facets every case in the data", {
  p <- plot_journey_cohort(cohort_log())
  expect_s3_class(p, "ggplot")
  expect_equal(n_panels(p), 3L)
})

test_that("a case_ids subset facets only the requested cases", {
  p <- plot_journey_cohort(cohort_log(), case_ids = c("C1", "C3"))
  expect_equal(n_panels(p), 2L)
})

# ── align_start rebases each case to elapsed hour 0 ─────────────────────────────

test_that("align_start puts every case's first box at elapsed hour 0", {
  res <- plot_journey_cohort(cohort_log(), align_start = TRUE, return_data = TRUE)
  firsts <- res$boxes |>
    dplyr::group_by(case_id) |>
    dplyr::summarise(first_xmin = min(xmin), .groups = "drop")
  expect_true(all(firsts$first_xmin == 0))
})

test_that("absolute mode keeps each case on its own datetime range", {
  res <- plot_journey_cohort(cohort_log(), return_data = TRUE)
  expect_s3_class(res$boxes$xmin, "POSIXct")
  firsts <- res$boxes |>
    dplyr::group_by(case_id) |>
    dplyr::summarise(first_xmin = min(xmin), .groups = "drop")
  # Three cases start at three different absolute times.
  expect_equal(dplyr::n_distinct(firsts$first_xmin), 3L)
})

# ── Cross-facet colour consistency ──────────────────────────────────────────────

test_that("the same location gets the same fill hex in every panel", {
  p  <- plot_journey_cohort(cohort_log(), return_data = TRUE)$plot
  bd <- ggplot2::ggplot_build(p)
  # Layer 1 is the geom_rect box layer; join its fill back to the box location.
  rect_data <- bd$data[[1]]
  boxes     <- plot_journey_cohort(cohort_log(), return_data = TRUE)$boxes
  boxes     <- dplyr::filter(boxes, !terminal)

  # Same number of rects as non-terminal boxes, and each location resolves to
  # exactly one fill colour across all panels.
  expect_equal(nrow(rect_data), nrow(boxes))
  by_loc <- tibble::tibble(location = boxes$location, fill = rect_data$fill) |>
    dplyr::group_by(location) |>
    dplyr::summarise(n_hex = dplyr::n_distinct(fill), .groups = "drop")
  expect_true(all(by_loc$n_hex == 1L))
})

# ── max_cases guard ─────────────────────────────────────────────────────────────

test_that("max_cases aborts with advice to pass explicit case_ids", {
  expect_error(
    plot_journey_cohort(cohort_log(), max_cases = 2L),
    regexp = "max_cases"
  )
})

test_that("raising max_cases lets all cases through", {
  p <- plot_journey_cohort(cohort_log(), max_cases = 100L)
  expect_equal(n_panels(p), 3L)
})

# ── Universal render gate, both modes ───────────────────────────────────────────

test_that("absolute cohort renders cleanly (universal gate)", {
  p <- plot_journey_cohort(cohort_log(), show_duration = TRUE)
  expect_s3_class(p, "ggplot")
  expect_no_warning(ggplot2::ggplot_build(p))
})

test_that("start-aligned cohort renders cleanly (universal gate)", {
  p <- plot_journey_cohort(cohort_log(), align_start = TRUE, show_duration = TRUE)
  expect_s3_class(p, "ggplot")
  expect_no_warning(ggplot2::ggplot_build(p))
})

test_that("terminal_activities is forwarded per case", {
  # Give C1 a terminal Ward-> Discharged move; it should render as a marker,
  # i.e. produce a terminal box that is dropped from the rect layer.
  log <- dplyr::bind_rows(
    cohort_log(),
    tibble::tibble(
      caseID = "C1", K_Number = "K1",
      timestamp = hrs(5), act_type = "location_move", activity = "Discharged"
    )
  )
  res <- plot_journey_cohort(log, terminal_activities = "Discharged",
                             return_data = TRUE)
  expect_true(any(res$boxes$terminal))
  expect_no_warning(ggplot2::ggplot_build(res$plot))
})

# ── Visual regression baselines (vdiffr) ────────────────────────────────────────

test_that("absolute cohort plot matches its baseline", {
  skip_if_not_installed("vdiffr")
  p <- plot_journey_cohort(cohort_log(), show_duration = TRUE, ncol = 1)
  vdiffr::expect_doppelganger("cohort-absolute", p)
})

test_that("start-aligned cohort plot matches its baseline", {
  skip_if_not_installed("vdiffr")
  p <- plot_journey_cohort(cohort_log(), align_start = TRUE,
                           show_duration = TRUE, ncol = 1)
  vdiffr::expect_doppelganger("cohort-aligned", p)
})
