# plot_patient_journey.R — Public orchestrator
#
# This is the single function users call. It:
#   1. Resolves column name arguments
#   2. Delegates to validate_event_log()
#   3. Delegates to build_journey_tables()
#   4. Constructs the opts list consumed by render_journey_plot()
#   5. Delegates to render_journey_plot()
#   6. Returns the ggplot object (or list when return_data = TRUE)
#
# Source all files in R/ to use:
#   source("R/utils.R"); source("R/validate.R")
#   source("R/transform.R"); source("R/render.R")
#   source("R/plot_patient_journey.R")


plot_patient_journey <- function(
    data,

    # Which spell to visualise
    case_id,

    # Which act_type values represent physical location moves (create boxes)
    location_categories = c("location_move", "ed_location_move"),

    # Column name mappings — change these if your data uses different names.
    # patient_col may be NULL for event logs with no secondary identifier.
    time_col        = "timestamp",
    act_type_col    = "act_type",
    activity_col    = "activity",
    case_col        = "caseID",
    patient_col     = "K_Number",

    # Timezone used when parsing character timestamps (POSIXct input keeps
    # its own tzone). Wall-clock exports from UK systems should pass
    # "Europe/London" or times shift by an hour across BST.
    tz = "UTC",

    # Activity values that are terminal states (e.g. "Discharged", "Closed").
    # A terminal final move renders as a zero-duration marker instead of a
    # box with an invented duration.
    terminal_activities = NULL,

    # Pre-filter: drop these act_types entirely before plotting (e.g. admin noise)
    exclude_categories = NULL,

    # Label options
    show_labels = FALSE,
    label_max   = 30L,

    # Label each box directly with its location name, at box centre
    label_boxes = FALSE,

    # Colour overrides — named character vectors (level → hex colour), or NULL = auto
    location_palette = NULL,
    event_palette    = NULL,

    # Visual geometry
    box_height    = 0.25,
    # Proportion of each box's width trimmed from its right edge to create a
    # thin visual gap between adjacent locations. Purely cosmetic.
    box_gap_prop  = 0.003,

    # Plot title — NULL auto-generates from case_id / K_Number
    title = NULL,

    # Strategy for inferring the final box's end time
    # "last_event" → extend to last event; falls back to "median" then "fixed"
    tail_strategy = "last_event",

    # Set TRUE to return list(plot, boxes, events) for debugging or extension
    return_data = FALSE
) {

  # ── Resolve column names into a single named list ─────────────────────────
  # All downstream functions use this list rather than the raw arg names, so
  # renaming an argument never requires touching the internals.
  cols <- list(
    time     = time_col,
    act_type = act_type_col,
    activity = activity_col,
    case     = case_col,
    patient  = patient_col
  )

  # ── Validate inputs and get a cleaned single-spell tibble ─────────────────
  spell <- validate_event_log(data, cols, case_id, location_categories, tz = tz)

  # ── Drop excluded categories now that validation has passed ───────────────
  if (!is.null(exclude_categories)) {
    n_before <- nrow(spell)
    spell    <- dplyr::filter(spell, !(.data[[cols$act_type]] %in% exclude_categories))
    n_after  <- nrow(spell)
    if (n_before != n_after) {
      cli::cli_inform(c(
        "i" = "Dropped {n_before - n_after} row(s) matching {.arg exclude_categories}."
      ))
    }

    # Exclusion runs after validation, so re-check the guarantee validation
    # gave us: at least one location event must survive, or box derivation
    # crashes with an unintelligible error.
    if (!any(spell[[cols$act_type]] %in% location_categories)) {
      cli::cli_abort(c(
        "No location events remain after applying {.arg exclude_categories}.",
        "x" = "{.arg exclude_categories} removed every row matching
               {.arg location_categories} ({.val {location_categories}}).",
        "i" = "Remove {.val {intersect(exclude_categories, location_categories)}}
               from {.arg exclude_categories}."
      ))
    }
  }

  # ── Build the two derived tables ──────────────────────────────────────────
  tables <- build_journey_tables(spell, cols, location_categories,
                                 box_height          = box_height,
                                 tail_strategy       = tail_strategy,
                                 terminal_activities = terminal_activities)

  boxes  <- tables$boxes
  events <- tables$events

  # ── Auto-generate title if none supplied ──────────────────────────────────
  if (is.null(title)) {
    title <- if (is.null(cols$patient)) {
      paste0("Case ", case_id)
    } else {
      paste0("Patient ", spell[[cols$patient]][1], " — Spell ", case_id)
    }
  }

  # ── Assemble opts list consumed by render_journey_plot() ─────────────────
  opts <- list(
    show_labels      = show_labels,
    label_max        = label_max,
    label_boxes      = label_boxes,
    location_palette = location_palette,
    event_palette    = event_palette,
    box_height       = box_height,
    box_gap_prop     = box_gap_prop,
    title            = title
  )

  # ── Render ────────────────────────────────────────────────────────────────
  p <- render_journey_plot(boxes, events, opts)

  # ── Return ────────────────────────────────────────────────────────────────
  if (return_data) {
    list(plot = p, boxes = boxes, events = events)
  } else {
    p
  }
}
