# test-render.R — Tests for Stage 1 visual quick-win features.
# Covers Stage 1a (duration labels), 1b (reference lines), 1c (ongoing-case
# indication), 1d (direct box labelling), 1e (high-cardinality bucketing) and
# 1f (colourblind-safe default palette), plus a combined all-features-on
# render gate.
#
# Run with: testthat::test_file("tests/testthat/test-render.R")

library(testthat)
library(dplyr)
library(ggplot2)

# ── Shared fixtures ────────────────────────────────────────────────────────────

t0 <- as.POSIXct("2024-01-01 08:00:00", tz = "UTC")
hrs <- function(h) t0 + h * 3600

STATE_EVENTS <- c("ed_location_move", "location_move")

small_log <- function() {
  # Final state move is "Ward" — never reaches a terminal state.
  tibble::tibble(
    case_id   = "SP-001",
    timestamp = c(hrs(0), hrs(1), hrs(2), hrs(4), hrs(5), hrs(8)),
    act_type  = c("ed_location_move", "obs", "clerk_review",
                  "location_move", "obs", "clerk_review"),
    activity  = c("ED", "Triage obs", "Initial review",
                  "Ward", "Ward obs", "Dr review")
  )
}

terminal_log <- function() {
  small_log() |>
    dplyr::add_row(case_id = "SP-001",
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
    case_id   = "SP-001",
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

# ── 1a. show_duration labels ──────────────────────────────────────────────────

test_that("show_duration labels each box with its rendered duration, '+' marking an inferred end", {
  # small_log() never reaches a terminal state, so its final box's end is
  # inferred. The label text is read from the built plot, not recomputed here.
  r <- plot_case_timeline(small_log(), case_id = "SP-001", state_events = STATE_EVENTS,
                          show_duration = TRUE, return_data = TRUE)
  built <- ggplot2::ggplot_build(r$plot)
  layer_classes <- vapply(r$plot$layers, function(l) class(l$geom)[1], character(1))
  labels <- built$data[[which(layer_classes == "GeomText")[1]]]$label
  expect_equal(r$boxes$end_inferred, c(FALSE, TRUE))
  expect_equal(labels, c("4h", "4h+"))

  # A terminal box gets no duration label at all.
  rt <- plot_case_timeline(terminal_log(), case_id = "SP-001", state_events = STATE_EVENTS,
                           terminal_activities = "Discharged",
                           show_duration = TRUE, return_data = TRUE)
  built <- ggplot2::ggplot_build(rt$plot)
  layer_classes <- vapply(rt$plot$layers, function(l) class(l$geom)[1], character(1))
  dur_layer <- built$data[[which(layer_classes == "GeomText")[1]]]
  expect_equal(nrow(dur_layer), sum(!rt$boxes$terminal))
  expect_no_warning(ggplot2::ggplot_build(rt$plot))
})

# ── 1b. reference_lines validation ─────────────────────────────────────────────

test_that("malformed reference_lines abort with a message naming the problem", {
  bad <- list(
    "data frame"     = c(4),
    "offset_hours"   = data.frame(hours = 4, lbl = "x"),
    "numeric"        = data.frame(offset_hours = "4", label = "4h target"),
    "at least one row" = data.frame(offset_hours = numeric(0), label = character(0))
  )
  for (msg in names(bad)) {
    expect_error(
      plot_case_timeline(small_log(), case_id = "SP-001", state_events = STATE_EVENTS,
                         reference_lines = bad[[msg]]),
      regexp = msg, info = msg
    )
  }
})

# ── 1b. reference_lines rendering ──────────────────────────────────────────────

test_that("each reference line is drawn at its offset from the first event", {
  ref <- data.frame(offset_hours = c(2, 4), label = c("2h", "4h"))
  p <- plot_case_timeline(small_log(), case_id = "SP-001", state_events = STATE_EVENTS,
                          reference_lines = ref)

  layer_classes <- vapply(p$layers, function(l) class(l$geom)[1], character(1))
  vline_idx <- which(layer_classes == "GeomVline")[1]
  built <- ggplot2::ggplot_build(p)
  # First event is at hrs(0).
  expect_equal(as.numeric(built$data[[vline_idx]]$xintercept),
               as.numeric(hrs(0)) + c(2, 4) * 3600)
  expect_no_warning(ggplot2::ggplot_build(p))
})

# ── 1c. case_open attribute ────────────────────────────────────────────────────

test_that("case_open is TRUE only when terminal_activities is given and not reached", {
  open_flag <- function(log, terminal) {
    attr(plot_case_timeline(log, case_id = "SP-001", state_events = STATE_EVENTS,
                            terminal_activities = terminal, return_data = TRUE)$boxes,
         "case_open")
  }
  expect_false(open_flag(small_log(), NULL))            # no terminal states declared
  expect_true(open_flag(small_log(), "Discharged"))     # declared, not reached
  expect_false(open_flag(terminal_log(), "Discharged")) # declared and reached
})

# ── 1c. ongoing-case rendering ────────────────────────────────────────────────

has_ongoing_annotation <- function(p) {
  built <- ggplot2::ggplot_build(p)
  any(vapply(built$data, function(d) {
    "label" %in% names(d) && any(d$label == "(ongoing)")
  }, logical(1)))
}

test_that("an open case gets a dashed '(ongoing)' marker at its last box's end; a closed one does not", {
  p_default <- plot_case_timeline(small_log(), case_id = "SP-001", state_events = STATE_EVENTS)
  p_reached <- plot_case_timeline(terminal_log(), case_id = "SP-001", state_events = STATE_EVENTS,
                                  terminal_activities = "Discharged")
  expect_false(has_ongoing_annotation(p_default))
  expect_false(has_ongoing_annotation(p_reached))
  expect_no_warning(ggplot2::ggplot_build(p_reached))

  r <- plot_case_timeline(small_log(), case_id = "SP-001", state_events = STATE_EVENTS,
                          terminal_activities = "Discharged", return_data = TRUE)
  expect_true(has_ongoing_annotation(r$plot))
  layer_classes <- vapply(r$plot$layers, function(l) class(l$geom)[1], character(1))
  seg_idx <- which(layer_classes == "GeomSegment")[1]
  built   <- ggplot2::ggplot_build(r$plot)
  expect_equal(as.numeric(built$data[[seg_idx]]$x[1]),
               as.numeric(r$boxes$xmax[nrow(r$boxes)]))
  expect_no_warning(ggplot2::ggplot_build(r$plot))
})

# ── 1d. label_boxes ────────────────────────────────────────────────────────────

test_that("label_boxes writes each non-terminal box's state name on it", {
  r <- plot_case_timeline(small_log(), case_id = "SP-001", state_events = STATE_EVENTS,
                          label_boxes = TRUE, return_data = TRUE)
  layer_classes <- vapply(r$plot$layers, function(l) class(l$geom)[1], character(1))
  built <- ggplot2::ggplot_build(r$plot)
  expect_equal(built$data[[which(layer_classes == "GeomText")[1]]]$label, r$boxes$state)
  expect_no_warning(ggplot2::ggplot_build(r$plot))

  # With a terminal state, two text layers exist: the terminal marker's own
  # label and the box labels. The box-label layer covers only non-terminal boxes.
  rt <- plot_case_timeline(terminal_log(), case_id = "SP-001", state_events = STATE_EVENTS,
                           terminal_activities = "Discharged",
                           label_boxes = TRUE, return_data = TRUE)
  layer_classes <- vapply(rt$plot$layers, function(l) class(l$geom)[1], character(1))
  built <- ggplot2::ggplot_build(rt$plot)
  label_sets <- lapply(which(layer_classes == "GeomText"), function(i) built$data[[i]]$label)
  expect_true(list(rt$boxes$state[!rt$boxes$terminal]) %in% label_sets)
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

test_that("event_type_top_n collapses the long tail into 'Other'", {
  expect_message(
    r <- plot_case_timeline(high_cardinality_log(), case_id = "SP-001", state_events = STATE_EVENTS,
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
  r <- plot_case_timeline(high_cardinality_log(), case_id = "SP-001", state_events = STATE_EVENTS,
                          event_type_top_n = 20, return_data = TRUE)

  built <- ggplot2::ggplot_build(r$plot)
  layer_classes <- vapply(r$plot$layers, function(l) class(l$geom)[1], character(1))
  point_idx <- which(layer_classes == "GeomPoint")[1]

  # 8 distinct event types, none collapsed (canonical returned events table
  # is never mutated by the render-only bucketing either)
  expect_equal(length(unique(built$data[[point_idx]]$colour)), 8L)
  expect_false("Other" %in% r$events$act_type)
})

# ── 1f. journey_palette() — "okabe" style (new default) ────────────────────────

test_that("okabe states and events never share a hex for co-indexed levels", {
  state_cols <- journey_palette(c("A", "B", "C"), "state", "okabe")
  evt_cols   <- journey_palette(c("A", "B", "C"), "event", "okabe")

  expect_length(setdiff(unname(state_cols), unname(evt_cols)), 3L)
})

test_that("okabe palette recycles past 8 distinct levels without erroring", {
  levs <- paste0("L", 1:10)
  expect_no_error(state_cols <- journey_palette(levs, "state", "okabe"))
  expect_no_error(evt_cols <- journey_palette(levs, "event", "okabe"))
  expect_length(state_cols, 10L)
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
  state_cols <- journey_palette(levs, "state", "brewer")
  evt_cols   <- journey_palette(levs, "event", "brewer")

  expect_equal(unname(state_cols), RColorBrewer::brewer.pal(3, "Set2"))
  expect_equal(unname(evt_cols), RColorBrewer::brewer.pal(3, "Dark2"))
})

test_that("invalid palette_style aborts with a clear match.arg error", {
  expect_error(
    journey_palette(c("A", "B"), "state", "viridis"),
    regexp = "should be one of"
  )
})

# ── 1f. end-to-end rendering ────────────────────────────────────────────────────

test_that("palette_style = 'brewer' render builds without warning", {
  p <- plot_case_timeline(small_log(), case_id = "SP-001", state_events = STATE_EVENTS,
                          palette_style = "brewer")
  expect_no_warning(ggplot2::ggplot_build(p))
})

# ── Stage 1 combined — all features enabled at once ────────────────────────────
# The plan's Stage 1 acceptance gate: render one plot with everything switched
# on simultaneously and assert no build-time warning (no layer collisions, no
# dropped rows). This is the machine-checkable half of the combined QA pass.

test_that("universal render gate: ALL Stage 1 features on at once builds cleanly", {
  ref <- data.frame(offset_hours = c(2, 6), label = c("2h target", "6h target"))

  p <- suppressMessages(
    plot_case_timeline(
      high_cardinality_log(), case_id = "SP-001", state_events = STATE_EVENTS,
      terminal_activities = "Discharged",   # final move is "Ward" → case open
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
