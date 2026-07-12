# test-aggregate.R — Stage 6 cohort aggregate / statistical view tests.
#
# Covers the summarisers in R/aggregate.R against a small hand-computed fixture
# so every mean / median / quantile / breach flag / transition count can be
# checked by eye:
#   6a  summarise_case_durations() / summarise_state_durations(), including
#       the end_inferred exclusion rule and n_inferred_excluded reporting.
#   6b  summarise_breach_rate() in both "case" and per-state scope, the
#       unknown-scope abort, and include_inferred behaviour.
#   6c  summarise_transitions() exact n / dwell values, plus the
#       plot_transition_summary() render gate on a multi-path cohort.
#   6d  plot_case_timeline(return_data = TRUE)$summary shape.
#   6e  plot_case_timeline_with_summary() returns a patchwork that assembles
#       cleanly.
#
# Run with: testthat::test_file("tests/testthat/test-aggregate.R")

library(testthat)
library(dplyr)
library(ggplot2)

# ── Hand-computed fixture ───────────────────────────────────────────────────────
#
# Three cases over states A/B/C plus a terminal "Discharge". Hour offsets are
# chosen so every derived duration is a round number of seconds.
#
#   X1 (full, reaches terminal): A@0 B@2 C@5 Discharge@9
#        A = 2h (7200s)   B = 3h (10800s)   C = 4h (14400s)   Discharge = 0
#   X2 (still open, no terminal): A@0 B@1 C@3, obs@4
#        A = 1h (3600s)   B = 2h (7200s)   C = inferred 1h (3600s, end_inferred)
#   X3 (skips C):                 A@0 B@2 Discharge@6
#        A = 2h (7200s)   B = 4h (14400s)   Discharge = 0
#
t0  <- as.POSIXct("2024-01-01 00:00:00", tz = "UTC")
hrs <- function(h) t0 + h * 3600
LOC <- c("location_move")

fixture <- function() {
  dplyr::bind_rows(
    tibble::tibble(
      case_id = "X1",
      timestamp = hrs(c(0, 2, 5, 9)),
      act_type  = "location_move",
      activity  = c("A", "B", "C", "Discharge")
    ),
    tibble::tibble(
      case_id = "X2",
      timestamp = hrs(c(0, 1, 3, 4)),
      act_type  = c("location_move", "location_move", "location_move", "obs"),
      activity  = c("A", "B", "C", "obs event")
    ),
    tibble::tibble(
      case_id = "X3",
      timestamp = hrs(c(0, 2, 6)),
      act_type  = "location_move",
      activity  = c("A", "B", "Discharge")
    )
  )
}

# Shared argument set for every summariser call on the fixture.
agg <- function(fn, ...) {
  suppressMessages(fn(
    fixture(),
    state_events = LOC,
    case_col = "case_id",
    terminal_activities = "Discharge",
    ...
  ))
}

# ── 6a. Per-stay durations ──────────────────────────────────────────────────────

test_that("summarise_case_durations drops inferred stays by default and reports the count", {
  jd <- agg(summarise_case_durations)
  # 10 stays total across the three cases; X2's inferred C stay is dropped -> 9.
  expect_equal(nrow(jd), 9L)
  expect_equal(attr(jd, "n_inferred_excluded"), 1L)
  expect_false(any(jd$end_inferred))
  expect_setequal(names(jd),
    c("case_id", "state", "xmin", "xmax", "duration_secs", "end_inferred", "terminal"))
})

test_that("include_inferred = TRUE keeps every stay and zeroes the excluded count", {
  jd <- agg(summarise_case_durations, include_inferred = TRUE)
  expect_equal(nrow(jd), 10L)
  expect_equal(attr(jd, "n_inferred_excluded"), 0L)
  expect_equal(sum(jd$end_inferred), 1L)
  # The one inferred stay is X2's final C box.
  inf <- jd[jd$end_inferred, ]
  expect_equal(inf$case_id, "X2")
  expect_equal(inf$state, "C")
})

test_that("per-stay duration_secs match the hand-computed values", {
  jd <- agg(summarise_case_durations, include_inferred = TRUE)
  x1 <- jd[jd$case_id == "X1", ]
  expect_equal(x1$duration_secs[x1$state == "A"], 7200)
  expect_equal(x1$duration_secs[x1$state == "B"], 10800)
  expect_equal(x1$duration_secs[x1$state == "C"], 14400)
  expect_equal(x1$duration_secs[x1$state == "Discharge"], 0)
  expect_true(x1$terminal[x1$state == "Discharge"])
})

# ── 6a. Per-state statistics ────────────────────────────────────────────────────

test_that("summarise_state_durations computes hand-checked stats and excludes inferred", {
  sd <- agg(summarise_state_durations)

  A <- sd[sd$state == "A", ]
  expect_equal(A$n_cases, 3L)
  expect_equal(A$mean_secs, 6000)          # (7200 + 3600 + 7200) / 3
  expect_equal(A$median_secs, 7200)
  expect_equal(A$p25_secs, 5400)           # type-7 quantile of {3600,7200,7200}
  expect_equal(A$p75_secs, 7200)
  expect_equal(A$n_inferred_excluded, 0L)

  B <- sd[sd$state == "B", ]
  expect_equal(B$mean_secs, 10800)         # (10800 + 7200 + 14400) / 3
  expect_equal(B$p25_secs, 9000)
  expect_equal(B$p75_secs, 12600)

  # C: X1 real (14400) + X2 inferred (excluded). Both cases visited it.
  C <- sd[sd$state == "C", ]
  expect_equal(C$n_cases, 2L)
  expect_equal(C$n_inferred_excluded, 1L)
  expect_equal(C$mean_secs, 14400)         # only the non-inferred stay counts
})

test_that("include_inferred = TRUE folds the imputed stay back into the stats", {
  sd <- agg(summarise_state_durations, include_inferred = TRUE)
  C  <- sd[sd$state == "C", ]
  expect_equal(C$n_inferred_excluded, 0L)
  expect_equal(C$mean_secs, 9000)          # (14400 + 3600) / 2
})

# ── 6b. Breach rate — whole-case scope ──────────────────────────────────────────

test_that("case-scope breach uses first-move-to-last-event and flags nothing inferred", {
  br <- agg(summarise_breach_rate, target_hours = 5, scope = "case")
  expect_setequal(names(br), c("case_id", "elapsed_hours", "breached", "end_inferred"))
  expect_false(any(br$end_inferred))
  expect_equal(br$elapsed_hours[br$case_id == "X1"], 9)   # Discharge @ 9h
  expect_equal(br$elapsed_hours[br$case_id == "X2"], 4)   # obs @ 4h
  expect_equal(br$elapsed_hours[br$case_id == "X3"], 6)   # Discharge @ 6h
  expect_equal(br$breached, c(TRUE, FALSE, TRUE))         # X1,X2,X3 vs 5h
  expect_equal(attr(br, "breach_rate"), 2 / 3)
  expect_equal(attr(br, "n_inferred_excluded"), 0L)
})

# ── 6b. Breach rate — per-state scope ───────────────────────────────────────────

test_that("state-scope breach excludes inferred dwells by default", {
  br <- agg(summarise_breach_rate, target_hours = 1.5, scope = "C")
  # Only X1 has a real C dwell (4h); X2's C is inferred -> excluded.
  expect_equal(nrow(br), 1L)
  expect_equal(br$case_id, "X1")
  expect_equal(br$elapsed_hours, 4)
  expect_true(br$breached)
  expect_equal(attr(br, "breach_rate"), 1)
  expect_equal(attr(br, "n_inferred_excluded"), 1L)
})

test_that("state-scope breach with include_inferred keeps the imputed dwell", {
  br <- agg(summarise_breach_rate, target_hours = 1.5, scope = "C",
            include_inferred = TRUE)
  expect_equal(nrow(br), 2L)
  expect_equal(br$elapsed_hours[br$case_id == "X2"], 1)  # inferred 1h
  expect_false(br$breached[br$case_id == "X2"])          # 1h < 1.5h
  expect_equal(attr(br, "breach_rate"), 0.5)
})

test_that("an unknown scope name aborts with a suggestion", {
  expect_error(
    agg(summarise_breach_rate, target_hours = 1, scope = "Discharg"),  # near-miss
    regexp = "scope"
  )
})

# ── 6c. Transition summary ──────────────────────────────────────────────────────

test_that("summarise_transitions returns exact counts and dwell means", {
  tr <- agg(summarise_transitions)

  ab <- tr[tr$from_state == "A" & tr$to_state == "B", ]
  expect_equal(ab$n, 3L)
  expect_equal(ab$mean_dwell_secs, 6000)      # (7200 + 3600 + 7200) / 3
  expect_equal(ab$median_dwell_secs, 7200)

  bc <- tr[tr$from_state == "B" & tr$to_state == "C", ]
  expect_equal(bc$n, 2L)
  expect_equal(bc$mean_dwell_secs, 9000)      # (10800 + 7200) / 2

  # The final (inferred) C box of X2 has no outgoing transition; only X1's C
  # closes into Discharge.
  cd <- tr[tr$from_state == "C" & tr$to_state == "Discharge", ]
  expect_equal(cd$n, 1L)
  expect_equal(cd$mean_dwell_secs, 14400)

  bd <- tr[tr$from_state == "B" & tr$to_state == "Discharge", ]
  expect_equal(bd$n, 1L)

  # Sorted by descending n: A->B first.
  expect_equal(tr$from_state[1], "A")
})

# ── 6c. Flow diagram render gate (multi-path cohort) ─────────────────────────────

multipath_cohort <- function() {
  mk <- function(id, states, offs) tibble::tibble(
    case_id = id, timestamp = hrs(offs), act_type = "location_move", activity = states
  )
  dplyr::bind_rows(
    mk("P1", c("Triage", "Assessment", "Ward", "Discharge"),          c(0, 2, 5, 30)),
    mk("P2", c("Triage", "Ward", "Assessment", "Ward", "Discharge"),  c(0, 1, 4, 6, 20)),
    mk("P3", c("Triage", "Assessment", "Discharge"),                  c(0, 3, 12)),
    mk("P4", c("Assessment", "Triage", "Ward", "Discharge"),          c(0, 1, 3, 25))
  )
}

test_that("plot_transition_summary renders cleanly on a multi-path cohort", {
  p <- suppressMessages(plot_transition_summary(
    multipath_cohort(),
    state_events = LOC, case_col = "case_id",
    terminal_activities = "Discharge"
  ))
  expect_s3_class(p, "ggplot")
  expect_no_warning(ggplot2::ggplot_build(p))
})

test_that("plot_transition_summary return_data exposes nodes and edges", {
  res <- suppressMessages(plot_transition_summary(
    multipath_cohort(),
    state_events = LOC, case_col = "case_id",
    terminal_activities = "Discharge", return_data = TRUE
  ))
  expect_setequal(names(res), c("plot", "nodes", "edges", "transitions"))
  # Node x-order places the common forward spine left-to-right.
  expect_equal(res$nodes$state[which.min(res$nodes$x)], "Triage")
  expect_equal(res$nodes$state[which.max(res$nodes$x)], "Discharge")
  # Backward transitions (Assessment -> Triage, Ward -> Assessment) are marked.
  expect_true(any(!res$edges$forward))
})

# ── 6d. return_data summary element ──────────────────────────────────────────────

test_that("plot_case_timeline(return_data = TRUE) carries a per-stay summary", {
  res <- suppressMessages(plot_case_timeline(
    fixture(), case_id = "X1",
    state_events = LOC, case_col = "case_id",
    terminal_activities = "Discharge", return_data = TRUE
  ))
  expect_setequal(names(res), c("plot", "boxes", "events", "summary"))
  expect_s3_class(res$summary, "tbl_df")
  expect_equal(nrow(res$summary), 4L)            # A, B, C, Discharge
  expect_true(all(res$summary$case_id == "X1"))
  # Agrees with the standalone cohort summary for the same case.
  expect_equal(res$summary$duration_secs[res$summary$state == "B"], 10800)
})

# ── 6e. Combined timeline + summary (patchwork stretch) ──────────────────────────

test_that("plot_case_timeline_with_summary assembles a patchwork that builds", {
  skip_if_not_installed("patchwork")
  pj <- suppressMessages(plot_case_timeline_with_summary(
    fixture(), case_id = "X1",
    state_events = LOC, case_col = "case_id",
    terminal_activities = "Discharge"
  ))
  expect_s3_class(pj, "patchwork")
  expect_no_error(patchwork::patchworkGrob(pj))
})

# ── Regression: summary bars reuse the timeline's exact fill palette ─────────────

test_that("summary bar colours match the timeline's fills even with a before-first-state box", {
  skip_if_not_installed("patchwork")
  # The before-first-state event gives the timeline a "(before first state)"
  # fill level the summary drops, which used to shift every bar hue by one
  # position.
  log <- tibble::tibble(
    case_id   = "S1",
    timestamp = hrs(c(-1, 0, 1, 2, 3)),
    act_type  = c("obs", "location_move", "obs", "location_move", "obs"),
    activity  = c("pre call", "A", "mid", "B", "post")
  )
  pw <- suppressMessages(plot_case_timeline_with_summary(
    log, case_id = "S1", state_events = "location_move",
    case_col = "case_id"
  ))
  timeline <- pw[[1]]
  bars     <- pw[[2]]

  tld <- timeline$layers[[1]]$data                       # includes (before first state)
  tlb <- ggplot2::ggplot_build(timeline)$data[[1]]
  tl_fill <- stats::setNames(
    tlb$fill[match(as.numeric(tld$xmin_render), tlb$xmin)],
    tld$state
  )

  bar_built <- ggplot2::ggplot_build(bars)$data[[1]]
  bar_states <- levels(bars$data$state)
  bar_fill  <- stats::setNames(bar_built$fill[order(bar_built$x)], bar_states)

  shared <- intersect(names(tl_fill), names(bar_fill))
  expect_setequal(shared, c("A", "B"))
  for (st in shared) {
    expect_equal(unname(bar_fill[[st]]), unname(tl_fill[[st]]))
  }
})
