# test-render-interactive.R — Stage 7 interactive renderer tests.
#
# Covers the ggiraph-backed interactive path: requireNamespace guard, the
# universal render gate on the underlying ggplot (before girafe() wraps it),
# tooltip content for boxes (with the end_inferred "(end inferred)"/
# "(inferred)" caveat), terminal markers, and event points, and confirms the
# default (interactive = FALSE) static path is completely unaffected — its
# geoms stay the plain (non-Interactive) classes ggiraph would otherwise swap
# in, so every pre-Stage-7 vdiffr baseline still applies unchanged.
#
# Run with: testthat::test_file("tests/testthat/test-render-interactive.R")

library(testthat)
library(dplyr)
library(ggplot2)

geom_classes <- function(p) vapply(p$layers, function(l) class(l$geom)[1], character(1))

# ── Default (static) path is untouched ──────────────────────────────────────────

test_that("interactive = FALSE (default) keeps plain, non-interactive geoms", {
  p <- suppressMessages(plot_patient_journey(
    example_journey, case_id = "SP-001", terminal_activities = "Discharged"
  ))
  expect_s3_class(p, "ggplot")
  gc <- geom_classes(p)
  expect_false(any(grepl("Interactive", gc)))
  expect_true(all(c("GeomRect", "GeomSegment", "GeomText", "GeomPoint") %in% gc))
})

# ── requireNamespace guard ───────────────────────────────────────────────────────

test_that("interactive = TRUE requires ggiraph to be installed", {
  skip_if(requireNamespace("ggiraph", quietly = TRUE),
          "ggiraph is installed; guard path not exercised")
  expect_error(
    plot_patient_journey(example_journey, case_id = "SP-001", interactive = TRUE),
    regexp = "ggiraph"
  )
})

# ── interactive = TRUE returns a girafe widget ──────────────────────────────────

test_that("interactive = TRUE returns a girafe htmlwidget", {
  skip_if_not_installed("ggiraph")
  p <- suppressMessages(plot_patient_journey(
    example_journey, case_id = "SP-001",
    terminal_activities = "Discharged", interactive = TRUE
  ))
  expect_s3_class(p, "girafe")
  expect_s3_class(p, "htmlwidget")
})

# ── Universal render gate on the underlying ggplot ──────────────────────────────
# render_journey_plot() with opts$interactive = TRUE is the ggplot girafe()
# wraps; ggplot_build() must still succeed cleanly on it.
#
# girafe() serialises straight to HTML/JS/SVG, so it doesn't keep the
# intermediate ggplot around. .interactive_plot() builds that intermediate
# ggplot the same way render_journey_plot_interactive() does internally — via
# render_journey_plot(..., opts$interactive = TRUE) — so both this gate and
# the tooltip-content tests below can inspect layer data pre-girafe().

.interactive_plot <- function(case_id = "SP-001", terminal_activities = NULL) {
  cols <- list(time = "timestamp", act_type = "act_type", activity = "activity",
               case = "caseID", patient = "K_Number", lane = NULL)
  spell <- validate_event_log(example_journey, cols, case_id,
                              c("location_move", "ed_location_move"), tz = "UTC")
  tables <- suppressMessages(build_journey_tables(
    spell, cols, c("location_move", "ed_location_move"),
    box_height = 0.25, terminal_activities = terminal_activities
  ))
  opts <- list(
    box_height = 0.25, box_gap_prop = 0.003, title = "t", state_label = "Location",
    x_scale = "datetime", facet_by = NULL, spell_open = FALSE, lanes_active = FALSE,
    show_labels = FALSE, label_max = 30L, show_duration = FALSE, label_boxes = FALSE,
    reference_lines = NULL, event_type_top_n = NULL, location_palette = NULL,
    event_palette = NULL, palette_style = "okabe", interactive = TRUE
  )
  render_journey_plot(tables$boxes, tables$events, opts)
}

test_that("the interactive ggplot builds cleanly (universal gate)", {
  skip_if_not_installed("ggiraph")
  gp <- .interactive_plot(terminal_activities = "Discharged")
  expect_no_warning(ggplot2::ggplot_build(gp))

  gc <- geom_classes(gp)
  expect_true(all(c("GeomInteractiveRect", "GeomInteractiveSegment",
                    "GeomInteractiveText", "GeomInteractivePoint") %in% gc))
})

# ── Tooltip content ──────────────────────────────────────────────────────────────

test_that("box tooltips carry location, duration, entry/exit, no inferred caveat for a real end", {
  skip_if_not_installed("ggiraph")
  gp <- .interactive_plot(terminal_activities = "Discharged")
  gc <- geom_classes(gp)
  box_data <- gp$layers[[which(gc == "GeomInteractiveRect")[1]]]$data

  ed <- box_data[box_data$location == "Emergency Department", ]
  expect_true(grepl("Emergency Department", ed$tooltip[1]))
  expect_true(grepl("4h 45m", ed$tooltip[1]))
  expect_true(grepl("Entry: 2024-03-15 08:30", ed$tooltip[1]))
  expect_true(grepl("Exit: 2024-03-15 13:15", ed$tooltip[1]))
  expect_false(grepl("inferred", ed$tooltip[1]))
})

test_that("an end_inferred box's tooltip carries the inferred caveat", {
  skip_if_not_installed("ggiraph")
  # No terminal_activities -> the final box's end is inferred (tail_strategy).
  gp <- .interactive_plot(terminal_activities = NULL)
  gc <- geom_classes(gp)
  box_data <- gp$layers[[which(gc == "GeomInteractiveRect")[1]]]$data

  last_box <- box_data[which.max(box_data$xmax), ]
  expect_true(last_box$end_inferred)
  expect_true(grepl("\\(end inferred\\)", last_box$tooltip))
  expect_true(grepl("\\(inferred\\)", last_box$tooltip))
})

test_that("terminal-marker tooltips carry the location name and its instant", {
  skip_if_not_installed("ggiraph")
  gp <- .interactive_plot(terminal_activities = "Discharged")
  gc <- geom_classes(gp)
  term_data <- gp$layers[[which(gc == "GeomInteractiveSegment")[1]]]$data
  expect_true(grepl("Discharged", term_data$tooltip[1]))
  expect_true(grepl("At: 2024-03-16 15:00", term_data$tooltip[1], fixed = TRUE))
})

test_that("event-point tooltips carry activity, act_type, and timestamp", {
  skip_if_not_installed("ggiraph")
  gp <- .interactive_plot(terminal_activities = "Discharged")
  gc <- geom_classes(gp)
  pt_data <- gp$layers[[which(gc == "GeomInteractivePoint")[1]]]$data
  expect_true(all(c("activity", "act_type") %in% names(pt_data)))
  first <- pt_data[1, ]
  expect_true(grepl(first$activity, first$tooltip, fixed = TRUE))
  expect_true(grepl(first$act_type, first$tooltip, fixed = TRUE))
})
