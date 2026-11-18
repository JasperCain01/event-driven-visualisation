# test-transform.R — Tests for derive_state_boxes(), derive_point_events(),
#                    assign_y_bands(), and build_journey_tables()
#
# Run with: testthat::test_file("tests/testthat/test-transform.R")

library(testthat)
library(dplyr)

# ── Shared helpers ─────────────────────────────────────────────────────────────

t0 <- as.POSIXct("2024-01-01 08:00:00", tz = "UTC")
hrs <- function(h) t0 + h * 3600

state_evts <- c("ed_location_move", "location_move")

cols <- list(
  time     = "timestamp",
  act_type = "act_type",
  activity = "activity",
  case     = "case_id"
)

# A tidy 3-state case: ED → Ward → Discharge Lounge
# with events in each state and one trailing event in the final box
standard_log <- function() {
  tibble::tibble(
    case_id   = "SP-001",
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

# ── derive_state_boxes ──────────────────────────────────────────────────────────

test_that("a standard log produces one box per state, each ending where the next begins", {
  # One comparison covers the box count, the state names (from the activity
  # column), every start, every non-final end (= the next start), and the
  # final end (= the last event, under tail_strategy = "last_event").
  boxes <- derive_state_boxes(standard_log(), cols, state_evts,
                              tail_strategy = "last_event")
  expect_equal(
    boxes[c("state", "xmin", "xmax")],
    tibble::tibble(state = c("ED", "Ward", "Discharge Lounge"),
                   xmin  = c(hrs(0), hrs(4), hrs(10)),
                   xmax  = c(hrs(4), hrs(10), hrs(12))),
    ignore_attr = TRUE
  )
  # Only the final box's end is inferred: no later state event closes it.
  expect_equal(boxes$end_inferred, c(FALSE, FALSE, TRUE))
})

test_that("final box uses median duration when last event IS the state event itself", {
  # Case ends with the state event — nothing after it
  log <- standard_log() |>
    dplyr::filter(timestamp <= hrs(10))  # remove hrs(11) and hrs(12)
  boxes <- derive_state_boxes(log, cols, state_evts,
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
    boxes <- derive_state_boxes(log, cols, state_evts),
    regexp = "zero or negative width"
  )
  # The nudged box must have positive width
  expect_true(all(boxes$xmax > boxes$xmin))
})

test_that("assign_y_bands stacks bands box_height + band_gap apart", {
  boxes <- derive_state_boxes(standard_log(), cols, state_evts, box_height = 1)
  expect_true(all(boxes$ymin == 0))
  expect_true(all(boxes$ymax == 1))

  shifted <- assign_y_bands(boxes, box_height = 1, band_index = 1, band_gap = 0.2)
  expect_equal(shifted$ymin[1], 1.2)
  expect_equal(shifted$ymax[1], 2.2)
})

# ── derive_point_events ────────────────────────────────────────────────────────

test_that("every non-state row becomes a point event in the box that contains it", {
  log   <- standard_log()
  boxes <- derive_state_boxes(log, cols, state_evts)
  evts  <- derive_point_events(log, boxes, cols, state_evts)$events

  # hrs(1), hrs(2) -> ED; hrs(5), hrs(6) -> Ward; hrs(11), hrs(12) -> Discharge Lounge.
  expect_equal(evts$box_id, c(1L, 1L, 2L, 2L, 3L, 3L))
})

test_that("event exactly at a box boundary belongs to the next box", {
  # Event at exactly hrs(4) should go into the Ward box (box 2), not ED (box 1)
  log <- standard_log()
  log <- log |>
    dplyr::add_row(
      case_id = "SP-001", .orig_row = 99L,
      timestamp = hrs(4),
      act_type  = "obs",
      activity  = "Boundary event"
    ) |>
    dplyr::arrange(timestamp)

  boxes <- derive_state_boxes(log, cols, state_evts)
  evts  <- derive_point_events(log, boxes, cols, state_evts)$events

  boundary_evt <- evts |> dplyr::filter(activity == "Boundary event")
  expect_equal(boundary_evt$box_id, 2L)
})

test_that("returns empty tibble with correct columns when no point events exist", {
  # Log with only state events
  log <- standard_log() |>
    dplyr::filter(act_type %in% state_evts) |>
    dplyr::mutate(.orig_row = dplyr::row_number())

  boxes <- derive_state_boxes(log, cols, state_evts)
  evts  <- derive_point_events(log, boxes, cols, state_evts)$events

  expect_equal(nrow(evts), 0L)
  expect_true("act_type" %in% names(evts))
  expect_true("box_id"   %in% names(evts))
})

# ── build_journey_tables ───────────────────────────────────────────────────────

test_that("events before the first state get a prepended before-first-state box", {
  log <- standard_log() |>
    dplyr::add_row(
      case_id = "SP-001", .orig_row = 0L,
      timestamp = hrs(-1),
      act_type  = "obs",
      activity  = "Pre-call obs"
    ) |>
    dplyr::arrange(timestamp)

  expect_message(
    tables <- build_journey_tables(log, cols, state_evts),
    regexp = "before first state"
  )

  # 4 boxes: (before first state) + the 3 state boxes; the early event sits in box 0.
  expect_equal(nrow(tables$boxes), 4L)
  expect_equal(tables$boxes$state[1], "(before first state)")
  expect_equal(tables$events$activity[tables$events$box_id == 0L], "Pre-call obs")
})

test_that("single state event produces one box", {
  log <- tibble::tibble(
    case_id = "SP-001", .orig_row = 1:2,
    timestamp = c(hrs(0), hrs(2)),
    act_type  = c("ed_location_move", "obs"),
    activity  = c("ED", "Quick obs")
  )
  tables <- build_journey_tables(log, cols, state_evts)
  expect_equal(nrow(tables$boxes), 1L)
  expect_equal(nrow(tables$events), 1L)
})
