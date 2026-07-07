# test-render.R — Tests for Stage 1 visual quick-win features.
# This file currently covers Stage 1d (direct box labelling). Later Stage 1
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

terminal_log <- function() {
  small_log() |>
    dplyr::add_row(caseID = "SP-001", K_Number = "K001",
                   timestamp = hrs(9), act_type = "location_move",
                   activity = "Discharged")
}

# ── 1d. label_boxes layer toggling ─────────────────────────────────────────────

test_that("label_boxes = FALSE (default) adds no box-label layer", {
  p_off <- plot_patient_journey(small_log(), case_id = "SP-001")
  p_on  <- plot_patient_journey(small_log(), case_id = "SP-001", label_boxes = TRUE)

  expect_equal(length(p_off$layers) + 1L, length(p_on$layers))
  expect_no_warning(ggplot2::ggplot_build(p_off))
})

test_that("label_boxes = TRUE labels every non-terminal box with its location", {
  r <- plot_patient_journey(small_log(), case_id = "SP-001",
                            label_boxes = TRUE, return_data = TRUE)

  layer_classes <- vapply(r$plot$layers, function(l) class(l$geom)[1], character(1))
  label_layer_idx <- which(layer_classes == "GeomText")[1]

  expect_false(is.na(label_layer_idx))
  built <- ggplot2::ggplot_build(r$plot)
  expect_equal(nrow(built$data[[label_layer_idx]]), nrow(r$boxes))
})

test_that("label_boxes = TRUE excludes terminal boxes (they keep their own label)", {
  r <- plot_patient_journey(terminal_log(), case_id = "SP-001",
                            terminal_activities = "Discharged",
                            label_boxes = TRUE, return_data = TRUE)

  layer_classes <- vapply(r$plot$layers, function(l) class(l$geom)[1], character(1))
  # Two GeomText layers exist here: the terminal marker's direct label
  # (Stage 0.5) and this stage's box-centre label. The box-centre layer must
  # only cover the non-terminal boxes.
  label_layer_idxs <- which(layer_classes == "GeomText")
  built <- ggplot2::ggplot_build(r$plot)
  n_non_terminal <- sum(!r$boxes$terminal)

  expect_true(any(vapply(label_layer_idxs, function(i) {
    nrow(built$data[[i]]) == n_non_terminal
  }, logical(1))))
})

test_that("universal render gate: label_boxes = TRUE builds without warning", {
  p <- plot_patient_journey(small_log(), case_id = "SP-001", label_boxes = TRUE)
  expect_no_warning(ggplot2::ggplot_build(p))
})
