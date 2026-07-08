# test-support-ticket.R — Stage 8 generalisation-polish tests.
#
# Covers the third example dataset (support_ticket_example — non-healthcare,
# proving the package leaves the NHS sector entirely), exercised end-to-end
# through all three plotting functions, the still-open ticket's ongoing-spell
# indication, and theme_journey() extraction regression checks (both
# renderers' final themes carry the shared base plus their own additions).
#
# Run with: testthat::test_file("tests/testthat/test-support-ticket.R")

library(testthat)
library(dplyr)
library(ggplot2)

stages <- c("Open", "Assigned", "In Progress", "Waiting on Customer", "Resolved", "Closed")

# ── Dataset sanity ───────────────────────────────────────────────────────────────

test_that("support_ticket_example has the expected shape and no patient column", {
  expect_true(is.data.frame(support_ticket_example))
  expect_setequal(
    names(support_ticket_example),
    c("ticket_id", "timestamp", "act_type", "activity")
  )
  expect_true(all(c("TCK-01", "TCK-04") %in% support_ticket_example$ticket_id))
  status_rows <- support_ticket_example[support_ticket_example$act_type == "status_change", ]
  expect_true(all(status_rows$activity %in% stages))
})

# ── End-to-end: band layout ──────────────────────────────────────────────────────

test_that("support_ticket_example renders in the band layout with state_label = Status", {
  p <- suppressMessages(plot_patient_journey(
    support_ticket_example, case_id = "TCK-01",
    location_categories = "status_change", case_col = "ticket_id",
    patient_col = NULL, terminal_activities = "Closed", state_label = "Status"
  ))
  expect_s3_class(p, "ggplot")
  expect_no_warning(ggplot2::ggplot_build(p))
  expect_equal(p$scales$get_scales("fill")$name, "Status")
})

test_that("the still-open ticket (TCK-04) triggers the ongoing-spell indication", {
  res <- suppressMessages(plot_patient_journey(
    support_ticket_example, case_id = "TCK-04",
    location_categories = "status_change", case_col = "ticket_id",
    patient_col = NULL, terminal_activities = "Closed", return_data = TRUE
  ))
  expect_true(attr(res$boxes, "spell_open"))
})

# ── End-to-end: staircase layout ─────────────────────────────────────────────────

test_that("support_ticket_example renders in the staircase layout", {
  p <- suppressMessages(plot_stage_ladder(
    support_ticket_example, case_id = "TCK-03",
    stage_categories = "status_change", case_col = "ticket_id",
    terminal_activities = "Closed"
  ))
  expect_s3_class(p, "ggplot")
  expect_no_warning(ggplot2::ggplot_build(p))
})

# ── End-to-end: cohort layout ────────────────────────────────────────────────────

test_that("support_ticket_example renders in the cohort layout", {
  p <- suppressMessages(plot_journey_cohort(
    support_ticket_example,
    location_categories = "status_change", case_col = "ticket_id",
    patient_col = NULL, terminal_activities = "Closed", state_label = "Status",
    case_ids = c("TCK-01", "TCK-02", "TCK-03", "TCK-05", "TCK-06")
  ))
  expect_s3_class(p, "ggplot")
  expect_no_warning(ggplot2::ggplot_build(p))
})

# ── theme_journey() extraction: shared base + per-renderer additions ────────────

test_that("theme_journey() supplies the shared grid/title styling", {
  th <- theme_journey(base_size = 11)
  built <- ggplot2::calc_element("panel.grid.major.x", th)
  expect_equal(built$colour, "grey88")
  expect_equal(built$linewidth, 0.4)
  expect_s3_class(ggplot2::calc_element("panel.grid.major.y", th), "element_blank")
  title_el <- ggplot2::calc_element("plot.title", th)
  expect_equal(title_el$face, "bold")
  expect_equal(title_el$size, 12)
})

test_that("the band renderer's final theme layers legend styling on theme_journey()", {
  p <- suppressMessages(plot_patient_journey(support_ticket_example, case_id = "TCK-01",
    location_categories = "status_change", case_col = "ticket_id", patient_col = NULL))
  expect_equal(p$theme$legend.position, "bottom")
  grid_x <- ggplot2::calc_element("panel.grid.major.x", p$theme)
  expect_equal(grid_x$colour, "grey88")
})

test_that("the staircase renderer's final theme suppresses the colour legend and sets its own margin", {
  p <- suppressMessages(plot_stage_ladder(
    support_ticket_example, case_id = "TCK-01",
    stage_categories = "status_change", case_col = "ticket_id"
  ))
  expect_equal(p$scales$get_scales("colour")$guide, "none")
  expect_equal(p$theme$plot.margin, ggplot2::margin(8, 14, 8, 8))
  grid_x <- ggplot2::calc_element("panel.grid.major.x", p$theme)
  expect_equal(grid_x$colour, "grey88")
})
