# test-render.R — Tests for Stage 1 visual quick-win features.
# Covers Stage 1a (duration labels), 1b (reference lines), 1c (ongoing-spell
# indication), 1d (direct box labelling), 1e (high-cardinality bucketing) and
# 1f (colourblind-safe default palette), plus a combined all-features-on
# render gate.
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

# ── 1b. reference_lines validation ─────────────────────────────────────────────

test_that("reference_lines = NULL (default) is accepted and adds no layer", {
  expect_no_error(validate_reference_lines(NULL))

  p_off <- plot_patient_journey(small_log(), case_id = "SP-001")
  expect_no_warning(ggplot2::ggplot_build(p_off))
})

test_that("non-data-frame reference_lines aborts", {
  expect_error(
    plot_patient_journey(small_log(), case_id = "SP-001",
                         reference_lines = c(4)),
    regexp = "data frame"
  )
})

test_that("reference_lines missing required columns aborts naming them", {
  expect_error(
    plot_patient_journey(small_log(), case_id = "SP-001",
                         reference_lines = data.frame(hours = 4, lbl = "x")),
    regexp = "offset_hours"
  )
})

test_that("reference_lines with non-numeric offset_hours aborts", {
  expect_error(
    plot_patient_journey(
      small_log(), case_id = "SP-001",
      reference_lines = data.frame(offset_hours = "4", label = "4h target")
    ),
    regexp = "numeric"
  )
})

test_that("empty reference_lines data frame aborts", {
  expect_error(
    plot_patient_journey(
      small_log(), case_id = "SP-001",
      reference_lines = data.frame(offset_hours = numeric(0), label = character(0))
    ),
    regexp = "at least one row"
  )
})

# ── 1b. reference_lines rendering ──────────────────────────────────────────────

test_that("reference_lines adds a vline + text layer, positioned from the first event", {
  ref <- data.frame(offset_hours = 4, label = "4h target")

  p_off <- plot_patient_journey(small_log(), case_id = "SP-001")
  p_on  <- plot_patient_journey(small_log(), case_id = "SP-001", reference_lines = ref)

  expect_equal(length(p_off$layers) + 2L, length(p_on$layers))

  layer_classes <- vapply(p_on$layers, function(l) class(l$geom)[1], character(1))
  expect_true("GeomVline" %in% layer_classes)

  vline_idx <- which(layer_classes == "GeomVline")[1]
  built <- ggplot2::ggplot_build(p_on)
  expected_x <- as.numeric(hrs(0)) + 4 * 3600  # first event is at hrs(0)
  expect_equal(as.numeric(built$data[[vline_idx]]$xintercept[1]), expected_x)
})

test_that("multiple reference_lines each render their own vline + label", {
  ref <- data.frame(offset_hours = c(2, 4), label = c("2h", "4h"))
  p <- plot_patient_journey(small_log(), case_id = "SP-001", reference_lines = ref)

  layer_classes <- vapply(p$layers, function(l) class(l$geom)[1], character(1))
  vline_idx <- which(layer_classes == "GeomVline")[1]
  built <- ggplot2::ggplot_build(p)
  expect_equal(nrow(built$data[[vline_idx]]), 2L)
})

test_that("universal render gate: reference_lines builds without warning", {
  ref <- data.frame(offset_hours = 4, label = "4h target")
  p <- plot_patient_journey(small_log(), case_id = "SP-001", reference_lines = ref)
  expect_no_warning(ggplot2::ggplot_build(p))
})

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

# ── 1d. label_boxes layer toggling ─────────────────────────────────────────────

test_that("label_boxes = FALSE (default) adds no box-label layer", {
  p_off <- plot_patient_journey(small_log(), case_id = "SP-001")
  p_on  <- plot_patient_journey(small_log(), case_id = "SP-001", label_boxes = TRUE)

  expect_equal(length(p_off$layers) + 1L, length(p_on$layers))
  expect_no_warning(ggplot2::ggplot_build(p_off))
})

test_that("label_boxes = TRUE labels every non-terminal box with its location", {
  r <- plot_patient_journey(small_log(), case_id = "SP-001",
                            label_boxes = TRUE, return_data = TRUE)

  layer_classes <- vapply(r$plot$layers, function(l) class(l$geom)[1], character(1))
  label_layer_idx <- which(layer_classes == "GeomText")[1]

  expect_false(is.na(label_layer_idx))
  built <- ggplot2::ggplot_build(r$plot)
  expect_equal(nrow(built$data[[label_layer_idx]]), nrow(r$boxes))
})

test_that("label_boxes = TRUE excludes terminal boxes (they keep their own label)", {
  r <- plot_patient_journey(terminal_log(), case_id = "SP-001",
                            terminal_activities = "Discharged",
                            label_boxes = TRUE, return_data = TRUE)

  layer_classes <- vapply(r$plot$layers, function(l) class(l$geom)[1], character(1))
  # Two GeomText layers exist here: the terminal marker's direct label
  # (Stage 0.5) and this stage's box-centre label. The box-centre layer must
  # only cover the non-terminal boxes.
  label_layer_idxs <- which(layer_classes == "GeomText")
  built <- ggplot2::ggplot_build(r$plot)
  n_non_terminal <- sum(!r$boxes$terminal)

  expect_true(any(vapply(label_layer_idxs, function(i) {
    nrow(built$data[[i]]) == n_non_terminal
  }, logical(1))))
})

test_that("universal render gate: label_boxes = TRUE builds without warning", {
  p <- plot_patient_journey(small_log(), case_id = "SP-001", label_boxes = TRUE)
  expect_no_warning(ggplot2::ggplot_build(p))
})

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

# ── 1f. journey_palette() — "okabe" style (new default) ────────────────────────

test_that("okabe locations and events never share a hex for co-indexed levels", {
  loc_cols <- journey_palette(c("A", "B", "C"), "location", "okabe")
  evt_cols <- journey_palette(c("A", "B", "C"), "event", "okabe")

  expect_length(setdiff(unname(loc_cols), unname(evt_cols)), 3L)
})

test_that("okabe events are the Okabe-Ito hues offset by 4 positions", {
  evt_cols <- journey_palette(c("e1", "e2", "e3"), "event", "okabe")
  # event 1 gets colour index 5 (1-indexed), wrapping past 8
  expect_equal(unname(evt_cols), .okabe_ito[c(5, 6, 7)])
})

test_that("okabe locations are lightened toward white, not the raw saturated hue", {
  loc_cols <- journey_palette(c("l1", "l2"), "location", "okabe")
  expect_false(unname(loc_cols[1]) %in% .okabe_ito)
  expect_true(all(grepl("^#[0-9A-Fa-f]{6,8}$", loc_cols)))
})

test_that("okabe palette recycles past 8 distinct levels without erroring", {
  levs <- paste0("L", 1:10)
  expect_no_error(loc_cols <- journey_palette(levs, "location", "okabe"))
  expect_no_error(evt_cols <- journey_palette(levs, "event", "okabe"))
  expect_length(loc_cols, 10L)
  expect_length(evt_cols, 10L)
})

test_that("journey_palette() defaults to palette_style = 'okabe'", {
  expect_equal(
    journey_palette(c("A", "B"), "event"),
    journey_palette(c("A", "B"), "event", "okabe")
  )
})

# ── 1f. journey_palette() — "brewer" style (opt-out, old default) ──────────────

test_that("brewer style reproduces the prior Set2/Dark2 output exactly", {
  skip_if_not_installed("RColorBrewer")

  levs <- c("A", "B", "C")
  loc_cols <- journey_palette(levs, "location", "brewer")
  evt_cols <- journey_palette(levs, "event", "brewer")

  expect_equal(unname(loc_cols), RColorBrewer::brewer.pal(3, "Set2"))
  expect_equal(unname(evt_cols), RColorBrewer::brewer.pal(3, "Dark2"))
})

test_that("invalid palette_style aborts with a clear match.arg error", {
  expect_error(
    journey_palette(c("A", "B"), "location", "viridis"),
    regexp = "should be one of"
  )
})

# ── 1f. end-to-end rendering ────────────────────────────────────────────────────

test_that("default (okabe) render builds without warning", {
  p <- plot_patient_journey(small_log(), case_id = "SP-001")
  expect_no_warning(ggplot2::ggplot_build(p))
})

test_that("palette_style = 'brewer' render builds without warning", {
  p <- plot_patient_journey(small_log(), case_id = "SP-001", palette_style = "brewer")
  expect_no_warning(ggplot2::ggplot_build(p))
})

# ── Stage 1 combined — all features enabled at once ────────────────────────────
# The plan's Stage 1 acceptance gate: render one plot with everything switched
# on simultaneously and assert no build-time warning (no layer collisions, no
# dropped rows). This is the machine-checkable half of the combined QA pass.

test_that("universal render gate: ALL Stage 1 features on at once builds cleanly", {
  ref <- data.frame(offset_hours = c(2, 6), label = c("2h target", "6h target"))

  p <- suppressMessages(
    plot_patient_journey(
      high_cardinality_log(), case_id = "SP-001",
      terminal_activities = "Discharged",   # final move is "Ward" → spell open
      show_duration       = TRUE,
      label_boxes         = TRUE,
      reference_lines     = ref,
      event_type_top_n    = 3,
      palette_style       = "okabe"
    )
  )

  expect_s3_class(p, "ggplot")
  expect_no_warning(ggplot2::ggplot_build(p))

  # Every Stage 1 layer type is present simultaneously.
  layer_classes <- vapply(p$layers, function(l) class(l$geom)[1], character(1))
  expect_true(all(c("GeomRect", "GeomText", "GeomVline", "GeomSegment",
                    "GeomPoint") %in% layer_classes))
})
