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
# Despite the name (kept for backward compatibility — see locked decision 5),
# this renders any event log built from exclusive states over time, not just
# clinical spells: a "location" is any state a case occupies exclusively for
# an interval — a ward, a complaint stage, a ticket status, a pipeline step —
# and location_categories/state_label exist precisely so callers can point
# this at complaint_example or support_ticket_example as readily as a
# patient spell.
#
# Source all files in R/ to use:
#   source("R/utils.R"); source("R/validate.R"); source("R/schema.R")
#   source("R/transform.R"); source("R/render.R"); source("R/render_interactive.R")
#   source("R/plot_patient_journey.R")


plot_patient_journey <- function(
    data,

    # Which spell to visualise
    case_id,

    # Which act_type values represent a move to a new exclusive state (create
    # boxes) — a physical location for a patient spell, but equally a stage
    # move for a complaint or a status change for a support ticket.
    location_categories = c("location_move", "ed_location_move"),

    # Column name mappings — change these if your data uses different names.
    # patient_col may be NULL for event logs with no secondary identifier.
    time_col        = "timestamp",
    act_type_col    = "act_type",
    activity_col    = "activity",
    case_col        = "caseID",
    patient_col     = "K_Number",

    # Schema object (event_log_schema()) bundling the column-mapping args
    # above. NULL = ignored. The literal string "auto" triggers
    # autodetect_schema(data, location_categories) — autodetection never runs
    # silently for any other value. Per-field precedence, highest wins:
    # an explicitly supplied individual argument (time_col, case_col, ...)
    # > the matching schema field > this function's own hardcoded default.
    schema = NULL,

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

    # Show a formatted duration label above each non-terminal box
    # (end_inferred boxes get a "+" suffix, since the end time is imputed)
    show_duration = FALSE,

    # Label each box directly with its location name, at box centre
    label_boxes = FALSE,

    # Reference / target-threshold lines. Data frame with `offset_hours`
    # (numeric, hours from the spell's first event) and `label`, or NULL.
    reference_lines = NULL,

    # When the distinct act_type count exceeds this, keep the top-N most
    # frequent event types and recode the rest to "Other" before colour/shape
    # scales are built. NULL = no bucketing.
    event_type_top_n = NULL,

    # Swimlanes: stack concurrent point-event tracks into horizontal lanes.
    # `lane_col` names a column in `data` whose distinct values become lanes
    # drawn above the location band; it affects point events only (the location
    # boxes stay the spine). Lane order is factor levels if the column is a
    # factor, else first appearance. NULL (default) → single midline, output
    # byte-identical to the pre-Stage-4 baseline. `lane_height`/`lane_gap` tune
    # lane geometry and default (NULL) to `box_height` and `0.05 * box_height`.
    # Note: many lanes make a tall plot — there is no automatic lane cap.
    lane_col    = NULL,
    lane_height = NULL,
    lane_gap    = NULL,

    # Fill-legend title. A journey's boxes are "Location" by default, but for a
    # linear stage process (complaint, ticket, approval pipeline) the exclusive
    # states are stages/statuses, not places — pass e.g. "Stage" or "Status".
    # Threaded through opts to scale_fill_manual(name = state_label). The
    # default reproduces prior output exactly.
    state_label = "Location",

    # Colour overrides — named character vectors (level → hex colour), or NULL = auto
    location_palette = NULL,
    event_palette    = NULL,

    # Auto-palette style used when location_palette/event_palette are NULL.
    # "okabe" (default): colourblind-safe Okabe-Ito based palette. "brewer":
    # the original Set2/Dark2 palette, for callers pinning old colours.
    palette_style = c("okabe", "brewer"),

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

    # Render as an interactive ggiraph girafe widget instead of a static
    # ggplot. Box, terminal-marker, and event-point layers gain tooltips
    # (location/duration/entry-exit for boxes, with an "(end inferred)" flag
    # so a tooltip never overclaims an imputed end). Requires the ggiraph
    # package (Suggests only).
    interactive = FALSE,

    # Set TRUE to return list(plot, boxes, events) for debugging or extension
    return_data = FALSE
) {

  if (interactive && !requireNamespace("ggiraph", quietly = TRUE)) {
    cli::cli_abort(c(
      "{.pkg ggiraph} is required for {.arg interactive = TRUE}.",
      "i" = "Install it with {.code install.packages(\"ggiraph\")}."
    ))
  }

  # ── Resolve schema, if any, before touching the column-mapping args ───────
  # missing(x) reflects whether the *caller* supplied x, independent of x's
  # bound default value — this is what lets an explicit argument beat the
  # schema while an omitted argument still falls through to it.
  if (identical(schema, "auto")) {
    schema <- autodetect_schema(
      data,
      location_categories = if (missing(location_categories)) NULL else location_categories
    )
  }

  if (!is.null(schema) && !inherits(schema, "event_log_schema")) {
    cli::cli_abort(c(
      "{.arg schema} must be an {.cls event_log_schema} object, the string
       {.val auto}, or {.code NULL}.",
      "x" = "You supplied an object of class {.cls {class(schema)}}."
    ))
  }

  if (!is.null(schema)) {
    if (missing(time_col)            && !is.null(schema$time_col))            time_col            <- schema$time_col
    if (missing(case_col)            && !is.null(schema$case_col))            case_col            <- schema$case_col
    if (missing(act_type_col)        && !is.null(schema$act_type_col))        act_type_col        <- schema$act_type_col
    if (missing(activity_col)        && !is.null(schema$activity_col))        activity_col        <- schema$activity_col
    if (missing(patient_col)         && !is.null(schema$patient_col))         patient_col         <- schema$patient_col
    if (missing(location_categories) && !is.null(schema$location_categories)) location_categories <- schema$location_categories
  }

  # ── Resolve swimlane geometry (relative to box_height) and validate lane_col ─
  # Defaults are expressed relative to box_height rather than baked into the
  # signature so they track a caller-supplied box_height.
  if (is.null(lane_height)) lane_height <- box_height
  if (is.null(lane_gap))    lane_gap    <- 0.05 * box_height

  if (!is.null(lane_col)) {
    if (!is.character(lane_col) || length(lane_col) != 1L) {
      cli::cli_abort(c(
        "{.arg lane_col} must be a single column name or {.code NULL}.",
        "x" = "You supplied an object of class {.cls {class(lane_col)}}."
      ))
    }
    if (!lane_col %in% names(data)) {
      suggestions <- suggest_matches(lane_col, names(data))
      hint <- if (length(suggestions) > 0) {
        cli::format_inline("Did you mean {.val {suggestions}}?")
      } else {
        cli::format_inline("Columns present in {.arg data}: {.val {names(data)}}")
      }
      cli::cli_abort(c(
        "{.arg lane_col} {.val {lane_col}} was not found in {.arg data}.",
        "i" = hint
      ))
    }
  }

  # ── Resolve column names into a single named list ─────────────────────────
  # All downstream functions use this list rather than the raw arg names, so
  # renaming an argument never requires touching the internals. `lane` is NULL
  # unless swimlanes were requested (validate/transform treat NULL as absent).
  cols <- list(
    time     = time_col,
    act_type = act_type_col,
    activity = activity_col,
    case     = case_col,
    patient  = patient_col,
    lane     = lane_col
  )

  # ── Validate inputs and get a cleaned single-spell tibble ─────────────────
  spell <- validate_event_log(data, cols, case_id, location_categories, tz = tz)
  validate_reference_lines(reference_lines)

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
                                 terminal_activities = terminal_activities,
                                 lane_height         = lane_height,
                                 lane_gap            = lane_gap)

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
    show_duration    = show_duration,
    label_boxes      = label_boxes,
    reference_lines  = reference_lines,
    event_type_top_n = event_type_top_n,
    location_palette = location_palette,
    event_palette    = event_palette,
    palette_style    = palette_style,
    box_height       = box_height,
    box_gap_prop     = box_gap_prop,
    title            = title,
    state_label      = state_label,
    x_scale          = "datetime",
    facet_by         = NULL,
    spell_open       = attr(boxes, "spell_open") %||% FALSE,
    lanes_active     = !is.null(lane_col),
    interactive      = interactive
  )

  # ── Render ────────────────────────────────────────────────────────────────
  p <- if (interactive) {
    render_journey_plot_interactive(boxes, events, opts)
  } else {
    render_journey_plot(boxes, events, opts)
  }

  # ── Return ────────────────────────────────────────────────────────────────
  # return_data additionally carries a per-stay duration summary (Stage 6d),
  # built from the boxes just derived so it agrees exactly with the cohort-level
  # summarise_journey_durations() for this case.
  if (return_data) {
    summary <- .stays_from_boxes(boxes, case_id)
    list(plot = p, boxes = boxes, events = events, summary = summary)
  } else {
    p
  }
}
