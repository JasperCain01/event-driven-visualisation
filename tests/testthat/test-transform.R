# test-transform.R — Tests for derive_location_boxes(), derive_point_events(),
#                    assign_y_bands(), and build_journey_tables()
#
# Run with: testthat::test_file("tests/testthat/test-transform.R")

library(testthat)
library(dplyr)

# ── Shared helpers ─────────────────────────────────────────────────────────────

t0 <- as.POSIXct("2024-01-01 08:00:00", tz = "UTC")
hrs <- function(h) t0 + h * 3600

loc_cats <- c("ed_location_move", "location_move")

cols <- list(
  time     = "timestamp",
  act_type = "act_type",
  activity = "activity",
  case     = "caseID",
  patient  = "K_Number"
)

# A tidy 3-location spell: ED → Ward → Discharge Lounge
# with events in each location and one trailing event in the final box
standard_log <- function() {
  tibble::tibble(
    caseID    = "SP-001",
    K_Number  = "K001",
    .orig_row = 1:9,
    timestamp = c(hrs(0), hrs(1), hrs(2), hrs(4), hrs(5), hrs(6), hrs(10), hrs(11), hrs(12)),
    act_type  = c(
      "ed_location_move", "obs", "clerk_review",
      "location_move",    "obs", "clerk_review",
      "location_move",    "obs", "clerk_review"
    ),
    activity  = c(
      "ED",   "Triage obs",    "Initial review",
      "Ward", "Ward obs",      "Dr visit",
      "Discharge Lounge", "Final obs", "TTOs issued"
    )
  )
}

# ── derive_location_boxes ──────────────────────────────────────────────────────

test_that("standard log produces correct number of boxes", {
  boxes <- derive_location_boxes(standard_log(), cols, loc_cats)
  expect_equal(nrow(boxes), 3L)
})

test_that("box xmin values match location move timestamps", {
  boxes <- derive_location_boxes(standard_log(), cols, loc_cats)
  expect_equal(boxes$xmin, c(hrs(0), hrs(4), hrs(10)))
})

test_that("non-final box xmax equals next location's xmin", {
  boxes <- derive_location_boxes(standard_log(), cols, loc_cats)
  expect_equal(boxes$xmax[1], hrs(4))
  expect_equal(boxes$xmax[2], hrs(10))
})

test_that("final box xmax extends to the last event (tail_strategy = 'last_event')", {
  boxes <- derive_location_boxes(standard_log(), cols, loc_cats,
                                 tail_strategy = "last_event")
  # Last event in the spell is at hrs(12)
  expect_equal(boxes$xmax[3], hrs(12))
})

test_that("final box uses median duration when last event IS the move itself", {
  # Spell ends with the move event — nothing after it
  log <- standard_log() |>
    dplyr::filter(timestamp <= hrs(10))  # remove hrs(11) and hrs(12)
  boxes <- derive_location_boxes(log, cols, loc_cats,
                                 tail_strategy = "last_event")
  # Preceding box durations: 4h and 6h → median = 5h = 18000s
  expected_end <- hrs(10) + 5 * 3600
  expect_equal(as.numeric(boxes$xmax[3] - hrs(10), units = "secs"),
               18000, tolerance = 1)
})

test_that("zero-width box is nudged and a message is emitted", {
  # Two moves at the exact same timestamp
  log <- standard_log()
  log$timestamp[4] <- log$timestamp[1]  # Ward move = ED move time
  expect_message(
    boxes <- derive_location_boxes(log, cols, loc_cats),
    regexp = "zero or negative width"
  )
  # The nudged box must have positive width
  expect_true(all(boxes$xmax > boxes$xmin))
})

test_that("location names come from the activity column", {
  boxes <- derive_location_boxes(standard_log(), cols, loc_cats)
  expect_equal(boxes$location, c("ED", "Ward", "Discharge Lounge"))
})

test_that("assign_y_bands sets ymin = 0, ymax = box_height for band_index 0", {
  boxes <- derive_location_boxes(standard_log(), cols, loc_cats, box_height = 1)
  expect_true(all(boxes$ymin == 0))
  expect_true(all(boxes$ymax == 1))
})

test_that("assign_y_bands offsets correctly for band_index = 1", {
  boxes <- derive_location_boxes(standard_log(), cols, loc_cats, box_height = 1)
  shifted <- assign_y_bands(boxes, box_height = 1, band_index = 1, band_gap = 0.2)
  expect_equal(shifted$ymin[1], 1.2)
  expect_equal(shifted$ymax[1], 2.2)
})

# ── derive_point_events ────────────────────────────────────────────────────────

test_that("standard log produces 6 point events (non-location rows)", {
  log   <- standard_log()
  boxes <- derive_location_boxes(log, cols, loc_cats)
  evts  <- derive_point_events(log, boxes, cols, loc_cats)$events
  expect_equal(nrow(evts), 6L)
})

test_that("each event is assigned to the correct box", {
  log   <- standard_log()
  boxes <- derive_location_boxes(log, cols, loc_cats)
  evts  <- derive_point_events(log, boxes, cols, loc_cats)$events

  # hrs(1) and hrs(2) → box 1 (ED: hrs(0)–hrs(4))
  ed_events <- evts |> dplyr::filter(box_id == 1L)
  expect_equal(nrow(ed_events), 2L)

  # hrs(5) and hrs(6) → box 2 (Ward: hrs(4)–hrs(10))
  ward_events <- evts |> dplyr::filter(box_id == 2L)
  expect_equal(nrow(ward_events), 2L)

  # hrs(11) and hrs(12) → box 3 (Discharge Lounge: hrs(10)–hrs(12))
  dl_events <- evts |> dplyr::filter(box_id == 3L)
  expect_equal(nrow(dl_events), 2L)
})

test_that("event exactly at a box boundary belongs to the next box", {
  # Event at exactly hrs(4) should go into the Ward box (box 2), not ED (box 1)
  log <- standard_log()
  log <- log |>
    dplyr::add_row(
      caseID = "SP-001", K_Number = "K001", .orig_row = 99L,
      timestamp = hrs(4),
      act_type  = "obs",
      activity  = "Boundary event"
    ) |>
    dplyr::arrange(timestamp)

  boxes <- derive_location_boxes(log, cols, loc_cats)
  evts  <- derive_point_events(log, boxes, cols, loc_cats)$events

  boundary_evt <- evts |> dplyr::filter(activity == "Boundary event")
  expect_equal(boundary_evt$box_id, 2L)
})

test_that("events before first location move trigger a pre-admission box", {
  # Add an event before the ED arrival
  log <- standard_log() |>
    dplyr::add_row(
      caseID = "SP-001", K_Number = "K001", .orig_row = 0L,
      timestamp = hrs(-1),
      act_type  = "clerk_review",
      activity  = "Pre-triage call"
    ) |>
    dplyr::arrange(timestamp)

  boxes <- derive_location_boxes(log, cols, loc_cats)

  expect_message(
    result <- derive_point_events(log, boxes, cols, loc_cats),
    regexp = "pre-admission"
  )
  evts <- result$events

  # The pre-admission event should have box_id == 0
  pre_evt <- evts |> dplyr::filter(box_id == 0L)
  expect_equal(nrow(pre_evt), 1L)
  expect_equal(pre_evt$activity, "Pre-triage call")

  # A pre_box should be returned alongside the events
  expect_false(is.null(result$pre_box))
})

test_that("returns empty tibble with correct columns when no point events exist", {
  # Log with only location moves
  log <- standard_log() |>
    dplyr::filter(act_type %in% loc_cats) |>
    dplyr::mutate(.orig_row = dplyr::row_number())

  boxes <- derive_location_boxes(log, cols, loc_cats)
  evts  <- derive_point_events(log, boxes, cols, loc_cats)$events

  expect_equal(nrow(evts), 0L)
  expect_true("act_type" %in% names(evts))
  expect_true("box_id"   %in% names(evts))
})

# ── build_journey_tables ───────────────────────────────────────────────────────

test_that("build_journey_tables returns a list with boxes and events", {
  tables <- build_journey_tables(standard_log(), cols, loc_cats)
  expect_named(tables, c("boxes", "events"))
  expect_true(is.data.frame(tables$boxes))
  expect_true(is.data.frame(tables$events))
})

test_that("pre-admission box is prepended to boxes when present", {
  log <- standard_log() |>
    dplyr::add_row(
      caseID = "SP-001", K_Number = "K001", .orig_row = 0L,
      timestamp = hrs(-1),
      act_type  = "obs",
      activity  = "Pre-call obs"
    ) |>
    dplyr::arrange(timestamp)

  suppressMessages(
    tables <- build_journey_tables(log, cols, loc_cats)
  )

  # Should now have 4 boxes (pre-admission + 3 location boxes)
  expect_equal(nrow(tables$boxes), 4L)
  expect_equal(tables$boxes$location[1], "(pre-admission)")
})

test_that("single location move produces one box", {
  log <- tibble::tibble(
    caseID = "SP-001", K_Number = "K001", .orig_row = 1:2,
    timestamp = c(hrs(0), hrs(2)),
    act_type  = c("ed_location_move", "obs"),
    activity  = c("ED", "Quick obs")
  )
  tables <- build_journey_tables(log, cols, loc_cats)
  expect_equal(nrow(tables$boxes), 1L)
  expect_equal(nrow(tables$events), 1L)
})
