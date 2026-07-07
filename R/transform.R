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
      "i" = "This should have been caught by validation — check that
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

  move_events
}


# ── derive_point_events ────────────────────────────────────────────────────────
#
# Assigns every non-location event to its enclosing location box using a
# half-open interval rule: event belongs to the box where xmin <= t < xmax.
# Uses findInterval() on the sorted xmin vector — O(n log n), no extra deps.
derive_point_events <- function(data, boxes, cols, location_categories,
                                box_height = 1) {

  # All rows that are NOT location moves
  point_data <- data |>
    dplyr::filter(!(.data[[cols$act_type]] %in% location_categories)) |>
    dplyr::select(
      act_type    = dplyr::all_of(cols$act_type),
      activity    = dplyr::all_of(cols$activity),
      timestamp   = dplyr::all_of(cols$time)
    )

  if (nrow(point_data) == 0) {
    return(
      dplyr::tibble(
        act_type  = character(),
        activity  = character(),
        timestamp = as.POSIXct(character()),
        x         = as.POSIXct(character()),
        y         = numeric(),
        box_id    = integer()
      )
    )
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

    # Prepend to boxes in the calling environment — returned via attribute so
    # build_journey_tables() can capture it without mutating boxes in place
    attr(point_data, "pre_box") <- pre_box

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

  point_data <- point_data |>
    dplyr::mutate(
      box_id = box_ids,
      x      = timestamp,
      # y midline — same band for all events in a single-spell plot
      y      = box_height / 2
    )

  point_data
}


# ── build_journey_tables ───────────────────────────────────────────────────────
#
# Orchestrates the full transformation for one spell.
# Returns list(boxes = <tibble>, events = <tibble>).
# If a pre-admission box was created, it is prepended to boxes here.
build_journey_tables <- function(data, cols, location_categories,
                                 box_height          = 1,
                                 tail_strategy       = "last_event",
                                 terminal_activities = NULL) {

  # Derive location boxes
  boxes  <- derive_location_boxes(
    data, cols, location_categories,
    box_height          = box_height,
    tail_strategy       = tail_strategy,
    terminal_activities = terminal_activities
  )

  # Derive instantaneous events, passing boxes so interval join can run
  events <- derive_point_events(data, boxes, cols, location_categories,
                                box_height = box_height)

  # If pre-location events were found, derive_point_events attaches a pre_box
  pre_box <- attr(events, "pre_box")
  if (!is.null(pre_box)) {
    # Renumber: pre_box gets box_id 0, existing boxes keep their IDs
    boxes <- dplyr::bind_rows(pre_box, boxes) |>
      dplyr::arrange(xmin)
  }

  list(boxes = boxes, events = events)
}
