# transform.R — Data transformation pipeline
#
# Reshapes a validated single-spell event log into two tidy tables:
#   boxes  — one row per location stay, with xmin/xmax/ymin/ymax for geom_rect
#   events — one row per instantaneous event, with x/y for geom_point
#
# Public entry point: build_journey_tables()
# Internal helpers:   derive_location_boxes(), derive_point_events(),
#                     assign_y_bands()


# ── assign_y_bands ─────────────────────────────────────────────────────────────
#
# Set ymin/ymax on a box tibble for a given band index (0-based).
# A single-spell plot uses index 0. Future multi-spell stacking increments this.
# Keeping this as a named helper means the multi-spell extension only needs to
# change the index, not touch box derivation logic.
assign_y_bands <- function(boxes, box_height = 1, band_index = 0L, band_gap = 0.2) {
  y_bottom <- band_index * (box_height + band_gap)
  boxes |>
    dplyr::mutate(
      ymin = y_bottom,
      ymax = y_bottom + box_height
    )
}


# ── derive_location_boxes ──────────────────────────────────────────────────────
#
# From a sorted, single-spell event log, extract one row per location move and
# calculate the time interval [xmin, xmax) each location was occupied.
derive_location_boxes <- function(data, cols, location_categories,
                                  box_height = 1,
                                  tail_strategy = "last_event",
                                  min_box_width_secs = 60,
                                  terminal_activities = NULL) {

  # Filter to move events only — activity is the destination location name
  move_events <- data |>
    dplyr::filter(.data[[cols$act_type]] %in% location_categories) |>
    dplyr::select(
      location  = dplyr::all_of(cols$activity),
      xmin      = dplyr::all_of(cols$time)
    ) |>
    dplyr::mutate(box_id = dplyr::row_number())

  n_boxes <- nrow(move_events)

  if (n_boxes == 0) {
    cli::cli_abort(c(
      "No location events found when deriving boxes.",
      "i" = "This should have been caught by validation \u2014 check that
             {.arg exclude_categories} did not remove all location events."
    ))
  }

  # xmax of each box = xmin of the next move event (half-open intervals)
  move_events <- move_events |>
    dplyr::mutate(xmax = dplyr::lead(xmin))

  # Is the final move a terminal state (e.g. "Discharged", "Closed")?
  # A terminal state is an instant, not a stay: it gets zero duration and is
  # rendered as a marker, never extended by tail inference — otherwise the
  # plot invents hours the case spent "Discharged".
  is_terminal <- !is.null(terminal_activities) &&
    move_events$location[n_boxes] %in% terminal_activities

  # Converse of is_terminal: the caller told us what "done" looks like
  # (terminal_activities), but this case's last recorded move isn't one of
  # them — the data feed stopped before the spell reached a terminal state.
  # terminal_activities = NULL means the caller made no such claim, so there
  # is nothing to be "open" relative to: attribute stays FALSE, no visual change.
  spell_open <- !is.null(terminal_activities) && !is_terminal

  if (is_terminal) {
    move_events$xmax[n_boxes] <- move_events$xmin[n_boxes]
  } else {
    # Resolve the final box's xmax — it has no successor move event
    all_timestamps      <- data[[cols$time]]
    preceding_durations <- diff(move_events$xmin)  # difftime vector, length n-1

    move_events$xmax[n_boxes] <- infer_box_end(
      last_xmin            = move_events$xmin[n_boxes],
      all_timestamps       = all_timestamps,
      preceding_durations  = preceding_durations,
      strategy             = tail_strategy
    )
  }

  # Flag which box ends are data vs inference: every non-terminal final box
  # end is inferred (the data never records leaving it), and downstream
  # duration statistics must be able to exclude or caveat it.
  move_events$terminal     <- c(rep(FALSE, n_boxes - 1), is_terminal)
  move_events$end_inferred <- c(rep(FALSE, n_boxes - 1), !is_terminal)

  # True duration, computed BEFORE any visual nudging so a zero-width stay
  # stores 0, not the nudge amount.
  move_events <- move_events |>
    dplyr::mutate(duration = xmax - xmin)

  # Guard: zero-width or negative non-terminal boxes get a minimum visual
  # width. Trade-off: we nudge rather than abort because same-timestamp moves
  # are a real data artefact (e.g. ED arrival + immediate triage move).
  zero_width <- move_events$xmax <= move_events$xmin & !move_events$terminal
  if (any(zero_width)) {
    cli::cli_inform(c(
      "i" = "{sum(zero_width)} box(es) had zero or negative width and were nudged
             by {min_box_width_secs}s for display. Stored {.field duration} keeps
             the true value."
    ))
    move_events$xmax[zero_width] <-
      move_events$xmin[zero_width] + min_box_width_secs
  }

  # Render-space start positions: a nudged box's widened xmax can overlap the
  # next box's true xmin (they shared a timestamp), which would hide the
  # nudged box entirely behind its successor. Stagger starts in render space
  # only — true xmin is untouched and still drives event assignment.
  move_events$xmin_render <- move_events$xmin
  if (n_boxes > 1) {
    for (i in 2:n_boxes) {
      if (move_events$xmin_render[i] < move_events$xmax[i - 1]) {
        move_events$xmin_render[i] <- move_events$xmax[i - 1]
      }
    }
  }

  # Apply y-band geometry (single spell → band_index = 0)
  move_events <- assign_y_bands(move_events, box_height = box_height)

  # Set after assign_y_bands (a dplyr::mutate() call) so the attribute isn't
  # attached before a transformation that could plausibly drop it.
  attr(move_events, "spell_open") <- spell_open

  move_events
}


# ── derive_point_events ────────────────────────────────────────────────────────
#
# Assigns every non-location event to its enclosing location box using a
# half-open interval rule: event belongs to the box where xmin <= t < xmax.
# Uses findInterval() on the sorted xmin vector — O(n log n), no extra deps.
#
# Swimlanes (Stage 4): when cols$lane names a data column, point events are
# stacked into horizontal lanes above the location band instead of sharing a
# single midline. Lanes affect point events ONLY — the location boxes stay the
# spine at [0, box_height]. Lane order is factor levels if the lane column is a
# factor, else first-appearance order. Lane i (1-indexed) occupies the y-range
#   [base + i*lane_gap + (i-1)*lane_height, base + i*lane_gap + i*lane_height]
# with base = box_height * 1.3 (the layout-budget swimlane floor, sitting above
# the duration- and reference-label rows). Each event is placed at its lane's
# vertical centre. cols$lane = NULL (default) → every event keeps y = midline,
# output byte-identical to the pre-Stage-4 baseline.
#
# Returns list(events = <tibble>, pre_box = <tibble or NULL>): when events
# precede the first location move, a synthetic "(pre-admission)" box is
# returned alongside the events rather than attached as an attribute, so the
# caller doesn't depend on attributes surviving unrelated transformations.
derive_point_events <- function(data, boxes, cols, location_categories,
                                box_height  = 1,
                                lane_height = box_height,
                                lane_gap    = 0.05 * box_height) {

  lane_col <- cols$lane  # NULL unless swimlanes requested

  # All rows that are NOT location moves
  point_rows <- data |>
    dplyr::filter(!(.data[[cols$act_type]] %in% location_categories))

  point_data <- point_rows |>
    dplyr::select(
      act_type    = dplyr::all_of(cols$act_type),
      activity    = dplyr::all_of(cols$activity),
      timestamp   = dplyr::all_of(cols$time)
    )

  # Carry the raw lane values through untouched — they are resolved to lane
  # indices/positions below, after the empty-input guard.
  if (!is.null(lane_col)) {
    point_data$lane <- point_rows[[lane_col]]
  }

  if (nrow(point_data) == 0) {
    empty <- tibble::tibble(
      act_type  = character(),
      activity  = character(),
      timestamp = as.POSIXct(character()),
      x         = as.POSIXct(character()),
      y         = numeric(),
      box_id    = integer()
    )
    if (!is.null(lane_col)) empty$lane <- character()
    return(list(events = empty, pre_box = NULL))
  }

  # findInterval(t, xmin_vec) returns the index of the largest xmin <= t.
  # Because box boundaries are contiguous (xmax[i] == xmin[i+1]), this
  # naturally implements the half-open [xmin, xmax) rule:
  #   - t exactly equal to xmin[i+1] → returns i+1 (belongs to next box) ✓
  #   - t < xmin[1]                  → returns 0 (pre-location) ✓
  box_starts <- boxes$xmin  # already sorted (derive_location_boxes preserves order)
  raw_idx    <- findInterval(as.numeric(point_data$timestamp),
                              as.numeric(box_starts))

  # Separate pre-location events (idx == 0) from in-location events
  pre_loc_mask <- raw_idx == 0L
  n_pre        <- sum(pre_loc_mask)
  pre_box      <- NULL

  if (n_pre > 0) {
    cli::cli_inform(c(
      "i" = "{n_pre} event(s) occurred before the first location move.",
      "i" = "A synthetic {.val (pre-admission)} box will be prepended."
    ))

    # Create an implicit leading box spanning [first_event, first_move)
    first_event_ts <- min(point_data$timestamp[pre_loc_mask])
    first_move_ts  <- min(boxes$xmin)

    pre_box <- dplyr::tibble(
      box_id       = 0L,
      location     = "(pre-admission)",
      xmin         = first_event_ts,
      xmax         = first_move_ts,
      duration     = first_move_ts - first_event_ts,
      terminal     = FALSE,
      end_inferred = FALSE,
      xmin_render  = first_event_ts
    ) |>
      assign_y_bands(box_height = box_height)

    # Assign pre-location events to box_id 0
    raw_idx[pre_loc_mask] <- 0L
  }

  # Map raw_idx back to box_id: idx 1..n maps to boxes$box_id[1..n],
  # idx 0 stays as 0 (the pre-admission box).
  # Clamp to 1 before indexing — R returns integer(0) for x[0], which breaks
  # vectorised recycling. Pre-location rows are overwritten below.
  safe_idx <- pmax(raw_idx, 1L)
  box_ids  <- boxes$box_id[safe_idx]
  box_ids[raw_idx == 0L] <- 0L

  # ── Vertical position: single midline, or one lane per lane-column value ──
  if (is.null(lane_col)) {
    # No swimlanes — every event shares the box midline (pre-Stage-4 behaviour).
    y_vals <- rep(box_height / 2, nrow(point_data))
  } else {
    # Lane order: factor levels if supplied as a factor (lets callers pin an
    # explicit ordering), else first appearance in the data.
    lane_vals <- point_data$lane
    lane_levels <- if (is.factor(lane_vals)) {
      levels(lane_vals)
    } else {
      unique(as.character(lane_vals))
    }

    lane_idx <- match(as.character(lane_vals), lane_levels)
    base     <- box_height * 1.3
    # Centre of lane i's band [base + i*gap + (i-1)*h, base + i*gap + i*h].
    y_vals   <- base + lane_idx * lane_gap + (lane_idx - 0.5) * lane_height

    # Store lane as a factor carrying the resolved ordering so the renderer's
    # axis breaks (sorted by y) come out in lane order.
    point_data$lane <- factor(as.character(lane_vals), levels = lane_levels)
  }

  point_data <- point_data |>
    dplyr::mutate(
      box_id = box_ids,
      x      = timestamp,
      y      = y_vals
    )

  list(events = point_data, pre_box = pre_box)
}


# ── build_journey_tables ───────────────────────────────────────────────────────
#
# Orchestrates the full transformation for one spell.
# Returns list(boxes = <tibble>, events = <tibble>).
# If a pre-admission box was created, it is prepended to boxes here.
build_journey_tables <- function(data, cols, location_categories,
                                 box_height          = 1,
                                 tail_strategy       = "last_event",
                                 terminal_activities = NULL,
                                 lane_height         = box_height,
                                 lane_gap            = 0.05 * box_height) {

  # Derive location boxes
  boxes  <- derive_location_boxes(
    data, cols, location_categories,
    box_height          = box_height,
    tail_strategy       = tail_strategy,
    terminal_activities = terminal_activities
  )

  # Read off spell_open before bind_rows()/arrange() below, which build a new
  # tibble and would otherwise drop it.
  spell_open <- attr(boxes, "spell_open") %||% FALSE

  # Derive instantaneous events, passing boxes so interval join can run.
  # lane geometry is inert unless cols$lane names a column (swimlanes).
  point_result <- derive_point_events(data, boxes, cols, location_categories,
                                      box_height  = box_height,
                                      lane_height = lane_height,
                                      lane_gap    = lane_gap)
  events  <- point_result$events
  pre_box <- point_result$pre_box

  # If pre-location events were found, derive_point_events returned a pre_box
  if (!is.null(pre_box)) {
    # Renumber: pre_box gets box_id 0, existing boxes keep their IDs
    boxes <- dplyr::bind_rows(pre_box, boxes) |>
      dplyr::arrange(xmin)
  }
  attr(boxes, "spell_open") <- spell_open

  list(boxes = boxes, events = events)
}


# ── .stays_from_boxes ───────────────────────────────────────────────────────────
#
# Reshape a derived `boxes` table into a per-stay summary row set: one row per
# location stay with its duration in seconds and the terminal / end_inferred
# flags. Shared by plot_patient_journey()'s return_data path (Stage 6d) and the
# cohort summarisers in aggregate.R, so a single-case summary and the cohort
# summary for that case agree exactly. The synthetic "(pre-admission)" box
# (box_id 0, injected by derive_point_events() for events preceding the first
# move) is dropped: it is a rendering artefact, not a recorded stay.
.stays_from_boxes <- function(boxes, case_id) {
  b <- boxes
  if ("box_id" %in% names(b)) b <- b[b$box_id != 0, , drop = FALSE]

  tibble::tibble(
    case_id       = case_id,
    location      = b$location,
    xmin          = b$xmin,
    xmax          = b$xmax,
    duration_secs = as.numeric(b$duration, units = "secs"),
    end_inferred  = b$end_inferred,
    terminal      = b$terminal
  )
}
