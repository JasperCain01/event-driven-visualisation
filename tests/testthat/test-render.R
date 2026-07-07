# test-render.R — Tests for Stage 1 visual quick-win features.
# This file currently covers Stage 1a (duration labels). Later Stage 1
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

# ── 1a. format_duration() ──────────────────────────────────────────────────────

test_that("format_duration() gives exact strings at each bucket boundary", {
  expect_equal(format_duration(0),     "0s")
  expect_equal(format_duration(59),    "59s")
  expect_equal(format_duration(60),    "1m")
  expect_equal(format_duration(3599),  "59m")
  expect_equal(format_duration(3600),  "1h")
  expect_equal(format_duration(3660),  "1h 1m")
  expect_equal(format_duration(86399), "23h 59m")
  expect_equal(format_duration(86400), "1d 0h")
  expect_equal(format_duration(90000), "1d 1h")
})

test_that("format_duration() is vectorised and NA-safe", {
  out <- format_duration(c(0, 3600, NA, 90000))
  expect_equal(out, c("0s", "1h", NA_character_, "1d 1h"))
})

# ── 1a. show_duration layer toggling ──────────────────────────────────────────

test_that("show_duration = FALSE (default) adds no duration-label layer", {
  p_off <- plot_patient_journey(small_log(), case_id = "SP-001")
  p_on  <- plot_patient_journey(small_log(), case_id = "SP-001", show_duration = TRUE)

  expect_equal(length(p_off$layers) + 1L, length(p_on$layers))
  expect_no_warning(ggplot2::ggplot_build(p_off))
})

test_that("show_duration = TRUE labels every non-terminal box, none for terminal", {
  r <- plot_patient_journey(terminal_log(), case_id = "SP-001",
                            terminal_activities = "Discharged",
                            show_duration = TRUE, return_data = TRUE)

  n_non_terminal <- sum(!r$boxes$terminal)

  built <- ggplot2::ggplot_build(r$plot)
  layer_classes <- vapply(r$plot$layers, function(l) class(l$geom)[1], character(1))
  dur_layer_idx <- which(layer_classes == "GeomText")[1]

  expect_false(is.na(dur_layer_idx))
  expect_equal(nrow(built$data[[dur_layer_idx]]), n_non_terminal)
  expect_no_warning(ggplot2::ggplot_build(r$plot))
})

test_that("end_inferred boxes get a '+' suffix; terminal boxes get no label", {
  # No terminal_activities supplied: the final box's end is inferred (no
  # successor move event tells us when it ended).
  r <- plot_patient_journey(small_log(), case_id = "SP-001",
                            show_duration = TRUE, return_data = TRUE)

  expect_true(r$boxes$end_inferred[nrow(r$boxes)])
  expect_false(any(r$boxes$end_inferred[-nrow(r$boxes)]))

  labels <- format_duration(as.numeric(r$boxes$duration, units = "secs"))
  labels <- ifelse(r$boxes$end_inferred, paste0(labels, "+"), labels)

  expect_true(grepl("\\+$", labels[nrow(r$boxes)]))
  expect_false(any(grepl("\\+$", labels[-nrow(r$boxes)])))

  # Terminal boxes never get a duration label at all: with terminal_activities
  # supplied, the terminal row is dropped from `boxes` before the label layer
  # is built (render.R filters `terminal` out before the geom_text() layer).
  rt <- plot_patient_journey(terminal_log(), case_id = "SP-001",
                             terminal_activities = "Discharged",
                             show_duration = TRUE, return_data = TRUE)
  built <- ggplot2::ggplot_build(rt$plot)
  layer_classes <- vapply(rt$plot$layers, function(l) class(l$geom)[1], character(1))
  dur_layer_idx <- which(layer_classes == "GeomText")[1]
  expect_equal(nrow(built$data[[dur_layer_idx]]), sum(!rt$boxes$terminal))
})

test_that("universal render gate: show_duration = TRUE builds without warning", {
  p <- plot_patient_journey(small_log(), case_id = "SP-001", show_duration = TRUE)
  expect_no_warning(ggplot2::ggplot_build(p))
})
