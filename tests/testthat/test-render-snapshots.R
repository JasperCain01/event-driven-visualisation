# test-render-snapshots.R — Stage 1.5 visual regression baselines (vdiffr).
#
# These snapshots freeze the *post-Stage-1* rendered output so the
# refactor-heavy stages that follow (swimlanes, cohort facets, the renderer
# split, the interactive path, theme extraction) can prove they leave the
# static output byte-identical rather than relying on eyeballs.
#
# Each baseline was rendered and visually approved once before committing.
# The baselines are pixel-exact SVGs, so they are PINNED to the graphics
# stack that produced them (R version + ggplot2/svglite/fonts): CI is the
# canonical environment. When CI upgrades R/CRAN and every doppelganger
# fails with "Snapshot of `testcase` has changed" while the functional
# tests still pass, the baselines are stale, not the code — run the
# update-snapshots workflow on a branch to regenerate them on the CI
# runner, then visually review every image before merging. On machines
# without vdiffr (or with NOT_CRAN unset) these tests skip.
#
# Run with: testthat::test_file("tests/testthat/test-render-snapshots.R")

library(testthat)
library(dplyr)
library(ggplot2)

# ── 1. Default plot ─────────────────────────────────────────────────────────────

test_that("default journey plot matches its baseline", {
  skip_if_not_installed("vdiffr")
  p <- plot_patient_journey(example_journey, case_id = "SP-001")
  vdiffr::expect_doppelganger("journey-default", p)
})

# ── 2. show_labels (thinned for legibility) ─────────────────────────────────────

test_that("show_labels journey plot matches its baseline", {
  skip_if_not_installed("vdiffr")
  p <- plot_patient_journey(
    example_journey, case_id = "SP-001",
    show_labels        = TRUE,
    exclude_categories = c("obs", "test_ordered")
  )
  vdiffr::expect_doppelganger("journey-show-labels", p)
})

# ── 3. show_duration ────────────────────────────────────────────────────────────

test_that("show_duration journey plot matches its baseline", {
  skip_if_not_installed("vdiffr")
  p <- plot_patient_journey(example_journey, case_id = "SP-001",
                            show_duration = TRUE)
  vdiffr::expect_doppelganger("journey-show-duration", p)
})

# ── 4. label_boxes ──────────────────────────────────────────────────────────────

test_that("label_boxes journey plot matches its baseline", {
  skip_if_not_installed("vdiffr")
  p <- plot_patient_journey(example_journey, case_id = "SP-001",
                            label_boxes = TRUE)
  vdiffr::expect_doppelganger("journey-label-boxes", p)
})

# ── 5. terminal_activities ──────────────────────────────────────────────────────

test_that("terminal_activities journey plot matches its baseline", {
  skip_if_not_installed("vdiffr")
  p <- plot_patient_journey(example_journey, case_id = "SP-001",
                            terminal_activities = "Discharged")
  vdiffr::expect_doppelganger("journey-terminal-activities", p)
})

# ── 6. reference_lines (single 4-hour target) ───────────────────────────────────

test_that("reference_lines journey plot matches its baseline", {
  skip_if_not_installed("vdiffr")
  p <- plot_patient_journey(
    example_journey, case_id = "SP-001",
    reference_lines = data.frame(offset_hours = 4, label = "4h target")
  )
  vdiffr::expect_doppelganger("journey-reference-line-4h", p)
})

# ── 7. Everything on at once ────────────────────────────────────────────────────
# The combined-features baseline the later stages must re-approve when they add
# their own layers on top (swimlanes re-snapshot this as combined view 8).

test_that("all-Stage-1-features journey plot matches its baseline", {
  skip_if_not_installed("vdiffr")
  p <- suppressMessages(
    plot_patient_journey(
      example_journey, case_id = "SP-001",
      terminal_activities = "Discharged",
      show_duration       = TRUE,
      label_boxes         = TRUE,
      reference_lines     = data.frame(offset_hours = 4, label = "4h target"),
      event_type_top_n    = 3
    )
  )
  vdiffr::expect_doppelganger("journey-all-features", p)
})

# ── 8. Swimlanes (Stage 4 combined view) ────────────────────────────────────────
# The combined-features view re-approved with lanes switched on. Point events
# are split into clinical tracks above the location band; duration labels and
# the reference line sit below the lane floor by construction.

example_journey_laned <- dplyr::mutate(
  example_journey,
  lane = dplyr::case_when(
    act_type == "obs"          ~ "Nursing",
    act_type == "test_ordered" ~ "Diagnostics",
    TRUE                        ~ "Medical"
  )
)

test_that("swimlane journey plot matches its baseline", {
  skip_if_not_installed("vdiffr")
  p <- suppressMessages(
    plot_patient_journey(
      example_journey_laned, case_id = "SP-001",
      lane_col        = "lane",
      show_duration   = TRUE,
      reference_lines = data.frame(offset_hours = 4, label = "4h target")
    )
  )
  vdiffr::expect_doppelganger("journey-swimlanes", p)
})
