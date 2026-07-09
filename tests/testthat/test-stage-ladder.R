# test-stage-ladder.R — Stage 5b staircase-view tests.
#
# Covers plot_stage_ladder(): the universal render gate, stage vertical ordering
# (first-appearance and explicit stage_order, plus errors on unknown stages),
# duration labels, terminal-stage-as-point, and stage_targets band layers. Also
# exercises the complaint_example dataset end-to-end through BOTH the band layout
# (plot_patient_journey) and the staircase (plot_stage_ladder), and confirms the
# still-open complaint triggers the ongoing-spell indication.
#
# Run with: testthat::test_file("tests/testthat/test-stage-ladder.R")

library(testthat)
library(dplyr)
library(ggplot2)

geom_classes <- function(p) vapply(p$layers, function(l) class(l$geom)[1], character(1))

ladder <- function(case_id, ...) {
  suppressMessages(plot_stage_ladder(
    complaint_example, case_id = case_id,
    stage_categories = "stage_change", case_col = "complaint_id",
    terminal_activities = "Formal letter sent", ...
  ))
}

# ── Universal render gate ───────────────────────────────────────────────────────

test_that("the staircase renders cleanly (universal gate)", {
  p <- ladder("CMP-01")
  expect_s3_class(p, "ggplot")
  expect_no_warning(ggplot2::ggplot_build(p))
})

# ── Stage vertical ordering ─────────────────────────────────────────────────────

test_that("first stage sits at the top (highest y) by first appearance", {
  res <- suppressMessages(plot_stage_ladder(
    complaint_example, case_id = "CMP-01",
    stage_categories = "stage_change", case_col = "complaint_id",
    terminal_activities = "Formal letter sent", return_data = TRUE
  ))
  b <- res$boxes
  # Acknowledgement is the first stage -> should have the largest y.
  expect_equal(b$y[b$stage == "Acknowledgement"][1], max(b$y))
  expect_equal(b$y[b$stage == "Formal letter sent"][1], min(b$y))
})

test_that("stage_order pins an explicit vertical ordering", {
  rev_order <- c("Formal letter sent", "Senior review", "Under review",
                 "Assigned", "Triage", "Acknowledgement")
  res <- suppressMessages(plot_stage_ladder(
    complaint_example, case_id = "CMP-01",
    stage_categories = "stage_change", case_col = "complaint_id",
    terminal_activities = "Formal letter sent",
    stage_order = rev_order, return_data = TRUE
  ))
  b <- res$boxes
  # With the order reversed, Acknowledgement (listed last) is now at the bottom.
  expect_equal(b$y[b$stage == "Acknowledgement"][1], min(b$y))
  expect_equal(b$y[b$stage == "Formal letter sent"][1], max(b$y))
})

test_that("stage_order missing a present stage aborts naming it", {
  expect_error(
    suppressMessages(plot_stage_ladder(
      complaint_example, case_id = "CMP-01",
      stage_categories = "stage_change", case_col = "complaint_id",
      terminal_activities = "Formal letter sent",
      stage_order = c("Acknowledgement", "Triage")   # omits later stages
    )),
    regexp = "stage_order"
  )
})

# ── Duration labels ─────────────────────────────────────────────────────────────

test_that("duration labels are present at segment midpoints", {
  p  <- ladder("CMP-01", show_duration = TRUE)
  gc <- geom_classes(p)
  expect_true("GeomText" %in% gc)
  txt <- p$layers[[which(gc == "GeomText")[1]]]$data
  expect_true(all(c("dur_label", "x_mid") %in% names(txt)))
  # end_inferred segments carry the "+" suffix; a fully-closed case does not.
  expect_false(any(grepl("\\+", txt$dur_label)))
})

test_that("show_duration = FALSE drops the duration-label layer", {
  p <- ladder("CMP-01", show_duration = FALSE)
  expect_false("GeomText" %in% geom_classes(p))
})

# ── stage_targets band layers ───────────────────────────────────────────────────

test_that("stage_targets adds exactly one band layer per targeted stage", {
  p0 <- ladder("CMP-01")
  base_rects <- sum(geom_classes(p0) == "GeomRect")

  p1 <- ladder("CMP-01", stage_targets = c("Under review" = 48))
  p2 <- ladder("CMP-01", stage_targets = c("Under review" = 48, "Triage" = 12))

  expect_equal(sum(geom_classes(p1) == "GeomRect"), base_rects + 1L)
  expect_equal(sum(geom_classes(p2) == "GeomRect"), base_rects + 2L)
})

test_that("a breached target draws a firebrick excess segment", {
  # CMP-03 stalls ~21 days in Under review; a 5-day (120h) target is breached.
  p  <- ladder("CMP-03", stage_targets = c("Under review" = 120))
  firebrick <- vapply(p$layers, function(l) {
    isTRUE(l$aes_params$colour == "firebrick")
  }, logical(1))
  expect_true(any(firebrick))
})

test_that("stage_targets naming an unknown stage aborts", {
  expect_error(
    ladder("CMP-01", stage_targets = c("Nonexistent stage" = 10)),
    regexp = "stage_targets"
  )
})

# ── Terminal stage as a point marker ────────────────────────────────────────────

test_that("the terminal stage renders as a point, not a segment", {
  res <- suppressMessages(plot_stage_ladder(
    complaint_example, case_id = "CMP-01",
    stage_categories = "stage_change", case_col = "complaint_id",
    terminal_activities = "Formal letter sent", return_data = TRUE
  ))
  gc  <- geom_classes(res$plot)
  expect_true("GeomPoint" %in% gc)
  pt_data <- res$plot$layers[[which(gc == "GeomPoint")[1]]]$data
  expect_true(all(pt_data$terminal))
  expect_true("Formal letter sent" %in% pt_data$stage)
})

# ── complaint_example end-to-end in BOTH layouts ────────────────────────────────

test_that("complaint_example renders in the band layout", {
  p <- suppressMessages(plot_patient_journey(
    complaint_example, case_id = "CMP-02",
    location_categories = "stage_change", case_col = "complaint_id",
    patient_col = NULL, terminal_activities = "Formal letter sent",
    state_label = "Stage", show_duration = TRUE
  ))
  expect_s3_class(p, "ggplot")
  expect_no_warning(ggplot2::ggplot_build(p))
})

test_that("complaint_example renders in the staircase layout", {
  p <- ladder("CMP-02")
  expect_s3_class(p, "ggplot")
  expect_no_warning(ggplot2::ggplot_build(p))
})

test_that("state_label sets the fill legend title in the band layout", {
  p  <- suppressMessages(plot_patient_journey(
    complaint_example, case_id = "CMP-02",
    location_categories = "stage_change", case_col = "complaint_id",
    patient_col = NULL, state_label = "Stage"
  ))
  # The fill scale's name drives the legend title.
  fill_scale <- p$scales$get_scales("fill")
  expect_equal(fill_scale$name, "Stage")
})

# ── Still-open complaint triggers the ongoing-spell indication (band) ───────────

test_that("the still-open complaint (CMP-04) marks the spell as open", {
  res <- suppressMessages(plot_patient_journey(
    complaint_example, case_id = "CMP-04",
    location_categories = "stage_change", case_col = "complaint_id",
    patient_col = NULL, terminal_activities = "Formal letter sent",
    return_data = TRUE
  ))
  expect_true(attr(res$boxes, "spell_open"))
})

# ── Visual regression baseline (vdiffr) ─────────────────────────────────────────

test_that("stage-ladder plot matches its baseline", {
  skip_if_not_installed("vdiffr")
  p <- ladder("CMP-03", stage_targets = c("Under review" = 120))
  vdiffr::expect_doppelganger("stage-ladder-cmp03", p)
})

# ── Regression: stage_targets bands every visit to a revisited stage ────────────

test_that("stage_targets bands and marks every visit to a revisited stage", {
  # TCK-01 enters "In Progress" twice (3h->8h and 31h->40h); both visits
  # breach a 2h target, so the single band layer must carry one row per
  # visit and the firebrick excess layer must mark both.
  res <- suppressMessages(plot_stage_ladder(
    support_ticket_example, case_id = "TCK-01",
    stage_categories = "status_change", case_col = "ticket_id",
    terminal_activities = "Closed",
    stage_targets = c("In Progress" = 2), return_data = TRUE
  ))
  gc <- geom_classes(res$plot)
  band_idx <- which(gc == "GeomRect")
  expect_length(band_idx, 1L)   # still exactly one band layer per stage
  expect_equal(nrow(res$plot$layers[[band_idx]]$data), 2L)
  fb <- which(vapply(res$plot$layers, function(l) {
    isTRUE(l$aes_params$colour == "firebrick")
  }, logical(1)))
  expect_length(fb, 1L)
  expect_equal(nrow(res$plot$layers[[fb]]$data), 2L)
  expect_no_warning(ggplot2::ggplot_build(res$plot))
})
