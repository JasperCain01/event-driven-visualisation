# test-render.R — Tests for Stage 1 visual quick-win features.
# This file currently covers Stage 1e (high-cardinality event-type
# bucketing). Later Stage 1 sub-stages append their own tests here.
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

# 8 distinct event types among the point events, with a clear frequency order:
# type_a (x5) > type_b (x4) > type_c (x3) > type_d..type_h (x1 each)
high_cardinality_log <- function() {
  types <- c(rep("type_a", 5), rep("type_b", 4), rep("type_c", 3),
            "type_d", "type_e", "type_f", "type_g", "type_h")
  n <- length(types)
  tibble::tibble(
    caseID    = "SP-001",
    K_Number  = "K001",
    timestamp = c(hrs(0), hrs(seq_len(n))),
    act_type  = c("location_move", types),
    activity  = c("Ward", paste0("event ", seq_len(n)))
  )
}

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

# ── 1e. bucket_top_n() ─────────────────────────────────────────────────────────

test_that("bucket_top_n() leaves x unchanged when distinct count <= top_n", {
  x <- c("a", "a", "b", "c")
  expect_equal(bucket_top_n(x, 3), x)
  expect_equal(bucket_top_n(x, 10), x)
})

test_that("bucket_top_n() keeps the most frequent values and collapses the rest", {
  x <- c(rep("a", 5), rep("b", 4), rep("c", 3), "d", "e")
  expect_message(out <- bucket_top_n(x, 3), regexp = "Other")
  expect_equal(out, ifelse(x %in% c("a", "b", "c"), x, "Other"))
})

# ── 1e. event_type_top_n wiring ─────────────────────────────────────────────────

test_that("event_type_top_n = NULL (default) leaves act_type untouched", {
  p_off <- plot_patient_journey(small_log(), case_id = "SP-001")
  expect_no_warning(ggplot2::ggplot_build(p_off))
})

test_that("event_type_top_n collapses the long tail into 'Other'", {
  expect_message(
    r <- plot_patient_journey(high_cardinality_log(), case_id = "SP-001",
                         event_type_top_n = 3, return_data = TRUE),
    regexp = "Other"
  )

  built <- ggplot2::ggplot_build(r$plot)
  layer_classes <- vapply(r$plot$layers, function(l) class(l$geom)[1], character(1))
  point_idx <- which(layer_classes == "GeomPoint")[1]
  point_data <- built$data[[point_idx]]

  # 3 kept types + "Other" = 4 distinct colour groups in the point layer
  expect_equal(length(unique(point_data$colour)), 4L)
})

test_that("event_type_top_n is a no-op when under the threshold", {
  r <- plot_patient_journey(high_cardinality_log(), case_id = "SP-001",
                            event_type_top_n = 20, return_data = TRUE)

  built <- ggplot2::ggplot_build(r$plot)
  layer_classes <- vapply(r$plot$layers, function(l) class(l$geom)[1], character(1))
  point_idx <- which(layer_classes == "GeomPoint")[1]

  # 8 distinct event types, none collapsed (canonical returned events table
  # is never mutated by the render-only bucketing either)
  expect_equal(length(unique(built$data[[point_idx]]$colour)), 8L)
  expect_false("Other" %in% r$events$act_type)
})

test_that("universal render gate: event_type_top_n builds without warning", {
  p <- suppressMessages(
    plot_patient_journey(high_cardinality_log(), case_id = "SP-001",
                         event_type_top_n = 3)
  )
  expect_no_warning(ggplot2::ggplot_build(p))
})
