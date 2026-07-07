# test-render.R — Tests for Stage 1 visual quick-win features.
# This file currently covers Stage 1c (ongoing-spell indication). Later
# Stage 1 sub-stages append their own tests here.
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
  # Final location move is "Ward" — never reaches a terminal state.
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

# ── 1c. spell_open attribute ────────────────────────────────────────────────────

test_that("spell_open is FALSE when terminal_activities is NULL (default)", {
  r <- plot_patient_journey(small_log(), case_id = "SP-001", return_data = TRUE)
  expect_false(attr(r$boxes, "spell_open"))
})

test_that("spell_open is TRUE when the final move is not in terminal_activities", {
  r <- plot_patient_journey(small_log(), case_id = "SP-001",
                            terminal_activities = "Discharged",
                            return_data = TRUE)
  expect_true(attr(r$boxes, "spell_open"))
})

test_that("spell_open is FALSE when the final move IS in terminal_activities", {
  r <- plot_patient_journey(terminal_log(), case_id = "SP-001",
                            terminal_activities = "Discharged",
                            return_data = TRUE)
  expect_false(attr(r$boxes, "spell_open"))
})

# ── 1c. ongoing-spell rendering ────────────────────────────────────────────────

has_ongoing_annotation <- function(p) {
  built <- ggplot2::ggplot_build(p)
  any(vapply(built$data, function(d) {
    "label" %in% names(d) && any(d$label == "(ongoing)")
  }, logical(1)))
}

test_that("spell_open = FALSE renders no '(ongoing)' annotation", {
  p_default <- plot_patient_journey(small_log(), case_id = "SP-001")
  p_reached <- plot_patient_journey(terminal_log(), case_id = "SP-001",
                                    terminal_activities = "Discharged")
  expect_false(has_ongoing_annotation(p_default))
  expect_false(has_ongoing_annotation(p_reached))
  expect_no_warning(ggplot2::ggplot_build(p_default))
  expect_no_warning(ggplot2::ggplot_build(p_reached))
})

test_that("spell_open = TRUE renders the '(ongoing)' annotation", {
  p_on <- plot_patient_journey(small_log(), case_id = "SP-001",
                               terminal_activities = "Discharged")
  expect_true(has_ongoing_annotation(p_on))
})

test_that("spell_open = TRUE adds a dashed geom_segment + '(ongoing)' annotation", {
  p_off <- plot_patient_journey(small_log(), case_id = "SP-001")
  p_on  <- plot_patient_journey(small_log(), case_id = "SP-001",
                                terminal_activities = "Discharged")

  # geom_segment + annotate("text") = 2 extra layers
  expect_equal(length(p_off$layers) + 2L, length(p_on$layers))

  layer_classes <- vapply(p_on$layers, function(l) class(l$geom)[1], character(1))
  expect_true("GeomSegment" %in% layer_classes)

  seg_idx <- which(layer_classes == "GeomSegment")[1]
  built   <- ggplot2::ggplot_build(p_on)

  r <- plot_patient_journey(small_log(), case_id = "SP-001",
                            terminal_activities = "Discharged", return_data = TRUE)
  last_box <- r$boxes[nrow(r$boxes), ]
  expect_equal(as.numeric(built$data[[seg_idx]]$x[1]), as.numeric(last_box$xmax))
})

test_that("universal render gate: spell_open = TRUE builds without warning", {
  p <- plot_patient_journey(small_log(), case_id = "SP-001",
                            terminal_activities = "Discharged")
  expect_no_warning(ggplot2::ggplot_build(p))
})
