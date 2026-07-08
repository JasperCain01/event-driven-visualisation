# eventviz (development version)

## Stage 6 — Cohort aggregate / statistical views

* New `summarise_journey_durations()` returns one row per location stay across a
  cohort (case, location, entry/exit, duration, `end_inferred`, `terminal`), and
  `summarise_stage_durations()` builds per-location statistics on it (case count,
  mean/median/p25/p75 dwell, `n_inferred_excluded`).
* New `summarise_breach_rate(data, target_hours, scope = ...)` reports what
  fraction of cases exceed a target. `scope = "spell"` measures whole-spell
  elapsed time (first move to last event); `scope = "<location>"` measures dwell
  within one stage (e.g. the ED 4-hour standard). An unknown scope name aborts
  with a did-you-mean hint.
* New `summarise_transitions()` reduces the cohort to directed
  location-to-location transitions with counts and mean/median dwell in the
  origin state, and `plot_transition_summary()` draws them as a hand-rolled flow
  diagram (no new dependency): nodes ordered along a left-to-right spine, arrowed
  edges whose width encodes frequency, forward and backward transitions bowed
  opposite ways so re-entries stay legible.
* **Every duration statistic respects `end_inferred`.** The imputed end of a
  non-terminal final stay is a rendering convenience, not data; each summariser
  takes `include_inferred = FALSE` (default), excluding those durations from
  means/medians/quantiles and reporting `n_inferred_excluded`. `TRUE` folds them
  back in, with the `end_inferred` flag travelling in the output.
* `plot_patient_journey(return_data = TRUE)` now also returns a `summary`
  element (`summarise_journey_durations()` for that one case), so the return
  value is `list(plot, boxes, events, summary)`. Additive — existing callers are
  unaffected.
* New `plot_journey_with_summary()` (stretch) stacks a single case's timeline
  above a per-stage dwell bar chart via `patchwork`, guarded with a
  `requireNamespace()` install hint.

## Stage 5b — Linear stage processes (staircase view)

* New `plot_stage_ladder()` renders a strictly linear stage process (a
  complaint, an approval pipeline, a ticket lifecycle) as a Gantt-like
  staircase: stages on the y-axis with the first stage at the top, one
  horizontal segment per stage, thin grey connectors forming the steps, and
  duration labels at each segment midpoint. It reuses `derive_location_boxes()`
  verbatim (stages *are* boxes) — only the rendering differs.
* `plot_stage_ladder()` accepts `stage_order` to pin the vertical ordering
  (default: first appearance) and `stage_targets`, a named `stage -> hours`
  vector rendering a light allowance band per targeted stage with any excess
  dwell drawn in `firebrick`. The terminal stage is drawn as a point marker,
  not a segment.
* `plot_patient_journey()` gains a `state_label` argument (default
  `"Location"`) setting the fill-legend title, so a complaint's boxes read as
  "Stage" and a ticket's as "Status". Default output is unchanged.
* New `complaint_example` dataset: eight complaints moving through
  Acknowledgement -> Triage -> Assigned -> Under review -> Senior review ->
  Formal letter sent, with no patient column (exercising `patient_col = NULL`).
  One complaint stalls ~3 weeks in "Under review" and one is still open,
  exercising the per-stage breach and ongoing-spell paths respectively.

## Stage 5 — Cohort view via faceting

* New `plot_journey_cohort()` lays several spells out as a faceted
  small-multiples grid, one panel per case, for at-a-glance comparison. It
  reuses the single-case `validate_event_log()` + `build_journey_tables()`
  pipeline per case rather than re-deriving anything, and asserts cross-facet
  colour consistency (the same location keeps the same fill in every panel).
* `align_start = TRUE` rebases every case to elapsed hours from its own first
  move and draws them on one shared `+Nh` axis (`scales = "fixed"`) so
  durations line up; the default absolute-time mode gives each panel its own
  datetime range (`scales = "free_x"`). A `max_cases` guard (default 25)
  aborts rather than attempting to facet hundreds of spells.
* Internal: the ggplot renderer was split into `journey_layers()` (geoms only)
  plus scale/theme assembly, and gained an `x_scale` option
  (`"datetime"` / `"elapsed_hours"`) and optional faceting. The single-case
  path is byte-identical — every existing vdiffr baseline is unchanged.

## Stage 4 — Swimlanes (concurrent event tracks within one case)

* `plot_patient_journey()` gains a `lane_col` argument. When supplied, its
  distinct values become horizontal lanes and point events are stacked into
  them above the location band, so concurrent tracks within a single case
  (e.g. nursing / medical / diagnostics activity) no longer collide on one
  midline. Lanes affect point events only — the location boxes stay the
  spine. Lane order follows factor levels when the column is a factor, else
  first appearance.
* New `lane_height` / `lane_gap` arguments tune lane geometry; they default
  (`NULL`) to `box_height` and `0.05 * box_height`. Lanes stack upward from
  the reserved swimlane floor at `box_height * 1.3`, above the duration- and
  reference-label rows.
* The y-axis now labels each lane when swimlanes are active and stays blank
  otherwise. Many lanes make a tall plot — there is no automatic lane cap.
* `lane_col = NULL` (the default) reproduces the pre-Stage-4 single-midline
  output byte-for-byte; the existing vdiffr baselines are unchanged.

## Stage 3 — Schema object + column autodetection

* New `event_log_schema()` constructor: a classed list bundling
  `time_col`/`act_type_col`/`activity_col`/`case_col`/`patient_col`/
  `location_categories`, with a `print()` method. Every field defaults to
  `NULL` ("not part of this schema").
* New `autodetect_schema(data, location_categories = NULL)` matches column
  names against per-role candidate lists (case-insensitive exact match
  first, then `adist() <= 2` fuzzy match), resolving roles in a fixed order
  (time -> case -> act_type -> activity -> patient) so a column claimed by
  one role is never reconsidered for another. Two equally-good matches for
  one role, or an unresolved required role, abort naming the problem rather
  than guessing.
* `plot_patient_journey()` gains a `schema` argument. Precedence per field,
  highest wins: an explicit individual argument (`time_col`, `case_col`, …)
  > the matching schema field > the function's existing hardcoded default.
  Autodetection only ever runs when `schema = "auto"` is passed literally —
  passing an `event_log_schema()` object never triggers it. Default
  behaviour (no `schema` argument) is unchanged.

## Stage 2 — Wide-to-long pivot wrapper

* New `pivot_events_longer()` reshapes wide, one-row-per-case milestone data
  (e.g. `arrival_time`, `triage_time`, `discharge_time` columns) into the
  long, one-row-per-event form `plot_patient_journey()` expects. Handles
  location vs. non-location milestones (`location_cols`), custom
  `act_type_map`/`activity_map` overrides, NA-milestone dropping, and
  suffix-stripped auto-labelling (`"arrival_time"` -> `"Arrival"`).
* `tidyr` moved from Suggests to Imports (used by `pivot_events_longer()`).
* Internal: timestamp coercion extracted from `validate_event_log()` into a
  shared `coerce_datetime_column()` helper, reused by the new pivot function.
* Fixed a pre-existing bug in `validate_event_log()`: filtering to a single
  case used a bare `case_id` inside `dplyr::filter()`, which dplyr's data
  mask would resolve against a data column named `case_id` instead of the
  function argument whenever the case column happened to be named exactly
  `case_id` (a natural, common choice — and the one used throughout the new
  pivot wrapper's own examples). Fixed by forcing environment lookup
  (`.env$case_id`). No change to previously-passing behaviour.

## Stage 1 — Visual quick wins

New opt-in features on `plot_patient_journey()`, each defaulting to prior
behaviour:

* `show_duration` — formatted duration label above each non-terminal box;
  boxes with an inferred end get a `"+"` suffix (1a).
* `reference_lines` — target/threshold vertical lines from a data frame of
  `offset_hours` + `label` (1b).
* Ongoing-spell indication — when `terminal_activities` is supplied but the
  case never reaches one, the final box's right edge is drawn open with an
  `"(ongoing)"` marker (1c).
* `label_boxes` — direct location labels at box centres (1d).
* `event_type_top_n` — collapse a high-cardinality `act_type` tail into
  `"Other"` before the colour/shape scales are built (1e).

### Default-output change (sanctioned)

* **New default palette (1f).** `journey_palette()` gains
  `palette_style = c("okabe", "brewer")`, defaulting to `"okabe"`: a
  colourblind-safe Okabe-Ito palette (locations lightened, events offset by
  four hues so co-indexed location/event pairs never share a colour). Pass
  `palette_style = "brewer"` to restore the previous Set2/Dark2 colours.
  This is one of the two intentional default-output changes for 0.1.0 (the
  other being the Stage 0.5 defect fixes).
