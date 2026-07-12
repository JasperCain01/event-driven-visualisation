# plot_case_timeline.R — Public orchestrator
#
# This is the single function users call. It:
#   1. Resolves column name arguments and state_events (schema, then a
#      discovery error if still unset)
#   2. Delegates to validate_event_log()
#   3. Delegates to build_journey_tables()
#   4. Constructs the opts list consumed by render_journey_plot()
#   5. Delegates to render_journey_plot()
#   6. Returns the ggplot object (or list when return_data = TRUE)
#
# Renders any event log built from exclusive states over time: a "state" is
# any condition a case occupies exclusively for an interval — a complaint
# stage, a ticket status, a pipeline step, a warehouse bay — opened by an
# event whose act_type is listed in state_events and closed by the next
# such event.

#' Visualise an event log as a state-band timeline
#'
#' Renders one case's event log as a horizontal timeline: coloured boxes for
#' each exclusive state the case occupies over time (opened by an event whose
#' `act_type` is listed in `state_events`), with instantaneous events plotted
#' as points on the midline.
#'
#' @details
#' States are *exclusive and contiguous*: a case is in exactly one state at a
#' time, and each state ends when the next begins (or is inferred/terminal at
#' the end of the series). Overlapping long-running processes are not
#' representable as states — concurrent point-event tracks are what
#' `lane_col` (swimlanes) are for.
#'
#' @param data A data frame or tibble containing the event log.
#' @param state_events Character vector of `act_type` values that open a
#'   state (these events create boxes). Required — no default. If omitted
#'   (and not supplied via `schema`), the error lists the distinct
#'   `act_type` values present in `data` with row counts, so you can see
#'   what to pass.
#' @param case_id The single case identifier to visualise, or `NULL`
#'   (default). When `case_col` names a column with exactly one distinct
#'   value, `NULL` resolves to that value automatically; with more than one,
#'   `NULL` aborts naming the first 10 and pointing at
#'   [plot_cohort_timeline()]. Must stay `NULL` when `case_col = NULL`.
#' @param time_col,act_type_col,activity_col,case_col Column-name mappings.
#'   `case_col` may be `NULL` for event logs with no case column at all — a
#'   single unnamed series (`case_id` must then also be `NULL`).
#' @param schema An [event_log_schema()] object bundling the column-mapping
#'   arguments, or the literal string `"auto"` to run [autodetect_schema()],
#'   or `NULL` (default) to ignore. Per-field precedence, highest wins: an
#'   explicitly supplied individual argument (`time_col`, `case_col`, ...) >
#'   the matching schema field > this function's own hardcoded default.
#' @param tz Timezone used when parsing character timestamps (`POSIXct`
#'   input keeps its own `tzone`).
#' @param terminal_activities Character vector of `activity` values that are
#'   terminal states (e.g. `"Discharged"`, `"Closed"`). A terminal final
#'   state event renders as a zero-duration marker instead of a box with an
#'   invented duration.
#' @param exclude_categories Character vector of `act_type` values to drop
#'   entirely before plotting, or `NULL`.
#' @param show_labels Logical; show `ggrepel` labels for point events.
#' @param label_max Maximum label character length before truncation.
#' @param show_duration Logical; show a formatted duration label above each
#'   non-terminal box (`end_inferred` boxes get a `"+"` suffix).
#' @param label_boxes Logical; label each box directly with its state name,
#'   at box centre.
#' @param reference_lines Data frame with `offset_hours` (numeric, hours from
#'   the case's first event) and `label`, drawn as dashed target-threshold
#'   lines, or `NULL`.
#' @param event_type_top_n When the distinct `act_type` count exceeds this,
#'   keep the top-N most frequent event types and recode the rest to
#'   `"Other"`. `NULL` = no bucketing.
#' @param lane_col Column in `data` whose distinct values become swimlanes
#'   for point events, drawn above the state band. `NULL` (default) keeps
#'   a single midline.
#' @param lane_height,lane_gap Swimlane geometry, in `box_height` units.
#'   `NULL` defaults to `box_height` and `0.05 * box_height` respectively.
#' @param state_label Fill-legend title. `"State"` by default; pass e.g.
#'   `"Stage"` or `"Status"` for a linear stage process.
#' @param state_palette,event_palette Named character vectors (level ->
#'   hex colour) overriding the automatic palettes, or `NULL`.
#' @param palette_style Auto-palette style used when `state_palette`/
#'   `event_palette` are `NULL`: `"okabe"` (default, colourblind-safe) or
#'   `"brewer"` (the original Set2/Dark2 palette).
#' @param box_height Height of the state band, in plot y-units.
#' @param box_gap_prop Proportion of each box's width trimmed from its right
#'   edge to create a thin visual gap between adjacent states.
#' @param title Plot title; `NULL` auto-generates `"Case <case_id>"` unless
#'   `case_col = NULL`, in which case there is no case to name and the title
#'   stays `NULL`.
#' @param tail_strategy Strategy for inferring the final box's end time:
#'   `"last_event"` extends to the last event, falling back to `"median"`
#'   then `"fixed"`.
#' @param interactive Logical; render as an interactive `ggiraph` `girafe`
#'   widget instead of a static ggplot. Requires the `ggiraph` package.
#' @param return_data Logical; if `TRUE`, return
#'   `list(plot, boxes, events, summary)` instead of just the plot.
#'
#' @return A `ggplot` object (or a `girafe` widget when `interactive = TRUE`),
#'   or a list when `return_data = TRUE`.
#'
#' @examples
#' plot_case_timeline(example_journey, state_events = c("location_move", "ed_location_move"))
#'
#' @export
plot_case_timeline <- function(
    data,

    # Which act_type values open a state (create boxes). Required — no
    # default (see @details / the "no state_events" error).
    state_events,

    # Which case to visualise
    case_id = NULL,

    # Column name mappings — change these if your data uses different names.
    # case_col may be NULL for a single unnamed series (no case column at all).
    time_col        = "timestamp",
    act_type_col    = "act_type",
    activity_col    = "activity",
    case_col        = "case_id",

    # Schema object (event_log_schema()) bundling the column-mapping args
    # above. NULL = ignored. The literal string "auto" triggers
    # autodetect_schema(data, state_events) — autodetection never runs
    # silently for any other value. Per-field precedence, highest wins:
    # an explicitly supplied individual argument (time_col, case_col, ...)
    # > the matching schema field > this function's own hardcoded default.
    schema = NULL,

    # Timezone used when parsing character timestamps (POSIXct input keeps
    # its own tzone). Wall-clock exports from UK systems should pass
    # "Europe/London" or times shift by an hour across BST.
    tz = "UTC",

    # Activity values that are terminal states (e.g. "Discharged", "Closed").
    # A terminal final state event renders as a zero-duration marker instead
    # of a box with an invented duration.
    terminal_activities = NULL,

    # Pre-filter: drop these act_types entirely before plotting (e.g. admin noise)
    exclude_categories = NULL,

    # Label options
    show_labels = FALSE,
    label_max   = 30L,

    # Show a formatted duration label above each non-terminal box
    # (end_inferred boxes get a "+" suffix, since the end time is imputed)
    show_duration = FALSE,

    # Label each box directly with its state name, at box centre
    label_boxes = FALSE,

    # Reference / target-threshold lines. Data frame with `offset_hours`
    # (numeric, hours from the case's first event) and `label`, or NULL.
    reference_lines = NULL,

    # When the distinct act_type count exceeds this, keep the top-N most
    # frequent event types and recode the rest to "Other" before colour/shape
    # scales are built. NULL = no bucketing.
    event_type_top_n = NULL,

    # Swimlanes: stack concurrent point-event tracks into horizontal lanes.
    # `lane_col` names a column in `data` whose distinct values become lanes
    # drawn above the state band; it affects point events only (the state
    # boxes stay the spine). Lane order is factor levels if the column is a
    # factor, else first appearance. NULL (default) → single midline, output
    # byte-identical to the pre-Stage-4 baseline. `lane_height`/`lane_gap` tune
    # lane geometry and default (NULL) to `box_height` and `0.05 * box_height`.
    # Note: many lanes make a tall plot — there is no automatic lane cap.
    lane_col    = NULL,
    lane_height = NULL,
    lane_gap    = NULL,

    # Fill-legend title. Defaults to "State"; for a linear stage process
    # (complaint, ticket, approval pipeline) pass e.g. "Stage" or "Status".
    # Threaded through opts to scale_fill_manual(name = state_label).
    state_label = "State",

    # Colour overrides — named character vectors (level → hex colour), or NULL = auto
    state_palette = NULL,
    event_palette = NULL,

    # Auto-palette style used when state_palette/event_palette are NULL.
    # "okabe" (default): colourblind-safe Okabe-Ito based palette. "brewer":
    # the original Set2/Dark2 palette, for callers pinning old colours.
    palette_style = c("okabe", "brewer"),

    # Visual geometry
    box_height    = 0.25,
    # Proportion of each box's width trimmed from its right edge to create a
    # thin visual gap between adjacent states. Purely cosmetic.
    box_gap_prop  = 0.003,

    # Plot title — NULL auto-generates "Case <case_id>", or stays NULL when
    # case_col = NULL (there is no case to name).
    title = NULL,

    # Strategy for inferring the final box's end time
    # "last_event" → extend to last event; falls back to "median" then "fixed"
    tail_strategy = "last_event",

    # Render as an interactive ggiraph girafe widget instead of a static
    # ggplot. Box, terminal-marker, and event-point layers gain tooltips
    # (state/duration/entry-exit for boxes, with an "(end inferred)" flag
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
  resolved <- resolve_entry_args(
    data, schema,
    state_events, missing(state_events),
    time_col,     missing(time_col),
    case_col,     missing(case_col),
    act_type_col, missing(act_type_col),
    activity_col, missing(activity_col)
  )
  state_events <- resolved$state_events
  time_col     <- resolved$time_col
  case_col     <- resolved$case_col
  act_type_col <- resolved$act_type_col
  activity_col <- resolved$activity_col

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
    lane     = lane_col
  )

  # ── Validate inputs and get a cleaned single-case tibble ──────────────────
  case_data <- validate_event_log(data, cols, case_id, state_events, tz = tz)
  case_id   <- attr(case_data, "case_id")
  validate_reference_lines(reference_lines)

  # ── Drop excluded categories now that validation has passed ───────────────
  if (!is.null(exclude_categories)) {
    n_before  <- nrow(case_data)
    case_data <- dplyr::filter(case_data, !(.data[[cols$act_type]] %in% exclude_categories))
    n_after   <- nrow(case_data)
    if (n_before != n_after) {
      cli::cli_inform(c(
        "i" = "Dropped {n_before - n_after} row(s) matching {.arg exclude_categories}."
      ))
    }

    # Exclusion runs after validation, so re-check the guarantee validation
    # gave us: at least one state event must survive, or box derivation
    # crashes with an unintelligible error.
    if (!any(case_data[[cols$act_type]] %in% state_events)) {
      cli::cli_abort(c(
        "No state events remain after applying {.arg exclude_categories}.",
        "x" = "{.arg exclude_categories} removed every row matching
               {.arg state_events} ({.val {state_events}}).",
        "i" = "Remove {.val {intersect(exclude_categories, state_events)}}
               from {.arg exclude_categories}."
      ))
    }
  }

  # ── Build the two derived tables ──────────────────────────────────────────
  tables <- build_journey_tables(case_data, cols, state_events,
                                 box_height          = box_height,
                                 tail_strategy       = tail_strategy,
                                 terminal_activities = terminal_activities,
                                 lane_height         = lane_height,
                                 lane_gap            = lane_gap)

  boxes  <- tables$boxes
  events <- tables$events

  # ── Auto-generate title if none supplied ──────────────────────────────────
  # No case column at all → nothing to name; leave the title NULL.
  if (is.null(title) && !is.null(cols$case)) {
    title <- paste0("Case ", case_id)
  }

  # ── Assemble opts list consumed by render_journey_plot() ─────────────────
  opts <- list(
    show_labels      = show_labels,
    label_max        = label_max,
    show_duration    = show_duration,
    label_boxes      = label_boxes,
    reference_lines  = reference_lines,
    event_type_top_n = event_type_top_n,
    state_palette    = state_palette,
    event_palette    = event_palette,
    palette_style    = palette_style,
    box_height       = box_height,
    box_gap_prop     = box_gap_prop,
    title            = title,
    state_label      = state_label,
    x_scale          = "datetime",
    facet_by         = NULL,
    case_open        = attr(boxes, "case_open") %||% FALSE,
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
  # summarise_case_durations() for this case.
  if (return_data) {
    summary <- .stays_from_boxes(boxes, case_id)
    list(plot = p, boxes = boxes, events = events, summary = summary)
  } else {
    p
  }
}
