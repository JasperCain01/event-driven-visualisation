# test-orchestration.R — Stage 9 direct tests for plot_case_timeline()'s
# own orchestration logic (title auto-generation, exclude_categories row
# accounting, and the full return_data = TRUE shape), as opposed to the
# render-path/defect-regression coverage in test-fixes.R and test-render.R.
#
# Run with: testthat::test_file("tests/testthat/test-orchestration.R")

library(testthat)
library(dplyr)
library(ggplot2)

t0  <- as.POSIXct("2024-01-01 08:00:00", tz = "UTC")
hrs <- function(h) t0 + h * 3600

standard_log <- function() {
  tibble::tibble(
    case_id   = "SP-001",
    timestamp = c(hrs(0), hrs(1), hrs(2), hrs(4), hrs(5), hrs(8)),
    act_type  = c("ed_location_move", "obs", "clerk_review",
                  "location_move", "obs", "clerk_review"),
    activity  = c("ED", "Triage obs", "Initial review",
                  "Ward", "Ward obs", "Dr review")
  )
}

STATE_EVENTS <- c("ed_location_move", "location_move")

# ── Auto-generated title format ─────────────────────────────────────────────────

test_that("auto title is 'Case <case_id>'", {
  p <- plot_case_timeline(standard_log(), case_id = "SP-001", state_events = STATE_EVENTS)
  expect_equal(p$labels$title, "Case SP-001")
})

test_that("title stays NULL when case_col = NULL (nothing to name)", {
  log <- standard_log() |> dplyr::select(-case_id)
  p <- plot_case_timeline(log, state_events = STATE_EVENTS, case_col = NULL)
  expect_null(p$labels$title)
})

test_that("an explicit title overrides auto-generation", {
  p <- plot_case_timeline(standard_log(), case_id = "SP-001", state_events = STATE_EVENTS,
                          title = "My Custom Title")
  expect_equal(p$labels$title, "My Custom Title")
})

# ── exclude_categories row accounting ───────────────────────────────────────────

test_that("exclude_categories drops exactly the matching rows and informs the count", {
  log <- standard_log()
  n_obs <- sum(log$act_type == "obs")
  expect_true(n_obs > 0)

  expect_message(
    r <- plot_case_timeline(log, case_id = "SP-001", state_events = STATE_EVENTS,
                            exclude_categories = "obs", return_data = TRUE),
    regexp = paste0("Dropped ", n_obs, " row")
  )

  # None of the surviving point events should be the excluded act_type.
  expect_false("obs" %in% r$events$act_type)
  # Boxes are unaffected — exclude_categories only touches point events here.
  expect_equal(nrow(r$boxes), 2L)
})

test_that("exclude_categories with no matching rows plots silently (no drop message)", {
  log <- standard_log()
  expect_no_message(
    plot_case_timeline(log, case_id = "SP-001", state_events = STATE_EVENTS,
                       exclude_categories = "nonexistent_type")
  )
})

test_that("exclude_categories removing every state event aborts with a clear message", {
  log <- standard_log()
  expect_error(
    plot_case_timeline(log, case_id = "SP-001", state_events = STATE_EVENTS,
                       exclude_categories = c("ed_location_move", "location_move")),
    regexp = "No state events remain"
  )
})

# ── return_data = TRUE shape ─────────────────────────────────────────────────────

test_that("return_data = TRUE returns list(plot, boxes, events, summary)", {
  r <- plot_case_timeline(standard_log(), case_id = "SP-001", state_events = STATE_EVENTS,
                          return_data = TRUE)
  expect_named(r, c("plot", "boxes", "events", "summary"))
  expect_s3_class(r$plot, "ggplot")
  expect_true(is.data.frame(r$boxes))
  expect_true(is.data.frame(r$events))
  expect_true(is.data.frame(r$summary))
})

test_that("return_data summary has one row per box, with the expected columns", {
  r <- plot_case_timeline(standard_log(), case_id = "SP-001", state_events = STATE_EVENTS,
                          return_data = TRUE)
  expect_named(
    r$summary,
    c("case_id", "state", "xmin", "xmax", "duration_secs", "end_inferred", "terminal")
  )
  expect_equal(nrow(r$summary), nrow(r$boxes))
  expect_equal(r$summary$state, r$boxes$state)
  expect_true(all(r$summary$case_id == "SP-001"))
})

test_that("return_data summary agrees with summarise_case_durations() for the same case", {
  r <- plot_case_timeline(standard_log(), case_id = "SP-001", state_events = STATE_EVENTS,
                          return_data = TRUE)
  cohort_summary <- summarise_case_durations(
    standard_log(), case_ids = "SP-001",
    state_events = STATE_EVENTS,
    case_col = "case_id",
    include_inferred = TRUE
  )
  actual   <- r$summary[order(r$summary$xmin), ] |> dplyr::select(-case_id)
  expected <- cohort_summary[order(cohort_summary$xmin), ] |>
    dplyr::select(state, xmin, xmax, duration_secs, end_inferred, terminal)
  expect_equal(actual, expected, ignore_attr = "n_inferred_excluded")
})

test_that("return_data = FALSE (default) returns just the plot, not a list", {
  p <- plot_case_timeline(standard_log(), case_id = "SP-001", state_events = STATE_EVENTS)
  expect_s3_class(p, "ggplot")
  expect_false(identical(names(p), c("plot", "boxes", "events", "summary")))
})
