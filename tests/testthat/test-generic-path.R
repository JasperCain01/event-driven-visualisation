# test-generic-path.R — Tests the REDESIGN_PLAN.md §1 objective directly: a
# first-time user with any timestamped event log gets a correct plot in one
# call, with exactly one explicit declaration (state_events), and never
# encounters healthcare vocabulary unless looking at the clinical example
# dataset.
#
# Run with: testthat::test_file("tests/testthat/test-generic-path.R")

library(testthat)
library(dplyr)
library(ggplot2)

# ── 1. The §1 acceptance snippet, verbatim ───────────────────────────────────

orders <- data.frame(
  case_id   = c("A-1", "A-1", "A-1", "A-2", "A-2"),
  timestamp = as.POSIXct("2026-01-01") + c(0, 3600, 7200, 0, 5400),
  act_type  = c("status", "note", "status", "status", "status"),
  activity  = c("Raised", "Chased supplier", "Approved", "Raised", "Approved")
)

test_that("the §1 acceptance snippet renders in one call with one declaration", {
  p <- plot_case_timeline(orders, state_events = "status", case_id = "A-1")
  expect_s3_class(p, "ggplot")
  expect_no_warning(ggplot2::ggplot_build(p))
})

test_that("the example_journey quick-start snippet renders in one call", {
  p <- plot_case_timeline(example_journey,
                          state_events = c("location_move", "ed_location_move"))
  expect_s3_class(p, "ggplot")
  expect_no_warning(ggplot2::ggplot_build(p))
})

# ── 2. Missing state_events aborts listing distinct act_type values ─────────

test_that("missing state_events aborts listing act_type values with counts and 'state'", {
  err <- expect_error(plot_case_timeline(orders, case_id = "A-1"))
  msg <- conditionMessage(err)
  expect_match(msg, "state")
  expect_match(msg, '"status" \\(4 rows\\)')
})

# ── 3. case_id resolution ────────────────────────────────────────────────────

test_that("case_id = NULL with a single case renders and informs which case was used", {
  single <- orders[orders$case_id == "A-1", ]
  expect_message(
    p <- plot_case_timeline(single, state_events = "status"),
    regexp = "only case"
  )
  expect_s3_class(p, "ggplot")
})

test_that("case_id = NULL with multiple cases aborts naming ids and plot_cohort_timeline", {
  err <- expect_error(plot_case_timeline(orders, state_events = "status"))
  msg <- conditionMessage(err)
  expect_match(msg, "A-1")
  expect_match(msg, "A-2")
  expect_match(msg, "plot_cohort_timeline")
})

# ── 4. case_col = NULL single-series plot ────────────────────────────────────

test_that("case_col = NULL builds a single-series plot with no case_id", {
  single <- orders[orders$case_id == "A-1", -1]  # drop case_id column
  p <- plot_case_timeline(single, state_events = "status", case_col = NULL)
  expect_s3_class(p, "ggplot")
  expect_no_warning(ggplot2::ggplot_build(p))
  expect_null(p$labels$title)
})

test_that("case_col = NULL with case_id supplied aborts", {
  single <- orders[orders$case_id == "A-1", -1]
  err <- expect_error(
    plot_case_timeline(single, state_events = "status", case_col = NULL, case_id = "A-1")
  )
  expect_match(conditionMessage(err), "case_col")
})

test_that("plot_cohort_timeline() with case_col = NULL aborts", {
  err <- expect_error(
    plot_cohort_timeline(orders, state_events = "status", case_col = NULL)
  )
  expect_match(conditionMessage(err), "case_col")
})

test_that("summarisers with case_col = NULL abort", {
  err <- expect_error(
    summarise_case_durations(orders, state_events = "status", case_col = NULL)
  )
  expect_match(conditionMessage(err), "case_col")
})

# ── 5. A schema built once drives every entry point (schema-everywhere) ─────

test_that("one schema drives plot_case_timeline, plot_cohort_timeline, plot_stage_ladder, and summarise_case_durations", {
  s <- event_log_schema(
    time_col = "timestamp", act_type_col = "act_type", activity_col = "activity",
    case_col = "case_id", state_events = "status"
  )

  p1 <- plot_case_timeline(orders, case_id = "A-1", schema = s)
  expect_s3_class(p1, "ggplot")

  p2 <- plot_cohort_timeline(orders, schema = s)
  expect_s3_class(p2, "ggplot")

  p3 <- plot_stage_ladder(orders, case_id = "A-1", schema = s)
  expect_s3_class(p3, "ggplot")

  d <- summarise_case_durations(orders, schema = s)
  expect_true(is.data.frame(d))
})

# ── 6. Extra unused columns are tolerated end-to-end ─────────────────────────

test_that("an inert extra column is tolerated end-to-end", {
  with_extra <- orders
  with_extra$region <- "north"
  p <- plot_case_timeline(with_extra, state_events = "status", case_id = "A-1")
  expect_s3_class(p, "ggplot")
  expect_no_warning(ggplot2::ggplot_build(p))
})

# ── 7. Grep gate as a test: no clinical vocabulary leaks into a generic plot ─

test_that("a generic-data plot carries no clinical vocabulary in labels or titles", {
  p <- plot_case_timeline(orders, state_events = "status", case_id = "A-1")
  built <- ggplot2::ggplot_build(p)
  rendered_text <- unlist(lapply(built$data, function(d) {
    if ("label" %in% names(d)) as.character(d$label) else character(0)
  }))
  rendered_text <- c(rendered_text, p$labels$title)
  expect_false(any(grepl("\\(pre-admission\\)|Patient ", rendered_text)))
})
