# test-render.R — Tests for Stage 1 visual quick-win features.
# This file currently covers Stage 1b (reference lines). Later Stage 1
# sub-stages append their own tests here.
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

# ── 1b. reference_lines validation ─────────────────────────────────────────────

test_that("reference_lines = NULL (default) is accepted and adds no layer", {
  expect_no_error(validate_reference_lines(NULL))

  p_off <- plot_patient_journey(small_log(), case_id = "SP-001")
  expect_no_warning(ggplot2::ggplot_build(p_off))
})

test_that("non-data-frame reference_lines aborts", {
  expect_error(
    plot_patient_journey(small_log(), case_id = "SP-001",
                         reference_lines = c(4)),
    regexp = "data frame"
  )
})

test_that("reference_lines missing required columns aborts naming them", {
  expect_error(
    plot_patient_journey(small_log(), case_id = "SP-001",
                         reference_lines = data.frame(hours = 4, lbl = "x")),
    regexp = "offset_hours"
  )
})

test_that("reference_lines with non-numeric offset_hours aborts", {
  expect_error(
    plot_patient_journey(
      small_log(), case_id = "SP-001",
      reference_lines = data.frame(offset_hours = "4", label = "4h target")
    ),
    regexp = "numeric"
  )
})

test_that("empty reference_lines data frame aborts", {
  expect_error(
    plot_patient_journey(
      small_log(), case_id = "SP-001",
      reference_lines = data.frame(offset_hours = numeric(0), label = character(0))
    ),
    regexp = "at least one row"
  )
})

# ── 1b. reference_lines rendering ──────────────────────────────────────────────

test_that("reference_lines adds a vline + text layer, positioned from the first event", {
  ref <- data.frame(offset_hours = 4, label = "4h target")

  p_off <- plot_patient_journey(small_log(), case_id = "SP-001")
  p_on  <- plot_patient_journey(small_log(), case_id = "SP-001", reference_lines = ref)

  expect_equal(length(p_off$layers) + 2L, length(p_on$layers))

  layer_classes <- vapply(p_on$layers, function(l) class(l$geom)[1], character(1))
  expect_true("GeomVline" %in% layer_classes)

  vline_idx <- which(layer_classes == "GeomVline")[1]
  built <- ggplot2::ggplot_build(p_on)
  expected_x <- as.numeric(hrs(0)) + 4 * 3600  # first event is at hrs(0)
  expect_equal(as.numeric(built$data[[vline_idx]]$xintercept[1]), expected_x)
})

test_that("multiple reference_lines each render their own vline + label", {
  ref <- data.frame(offset_hours = c(2, 4), label = c("2h", "4h"))
  p <- plot_patient_journey(small_log(), case_id = "SP-001", reference_lines = ref)

  layer_classes <- vapply(p$layers, function(l) class(l$geom)[1], character(1))
  vline_idx <- which(layer_classes == "GeomVline")[1]
  built <- ggplot2::ggplot_build(p)
  expect_equal(nrow(built$data[[vline_idx]]), 2L)
})

test_that("universal render gate: reference_lines builds without warning", {
  ref <- data.frame(offset_hours = 4, label = "4h target")
  p <- plot_patient_journey(small_log(), case_id = "SP-001", reference_lines = ref)
  expect_no_warning(ggplot2::ggplot_build(p))
})
