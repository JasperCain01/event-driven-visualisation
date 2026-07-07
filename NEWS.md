# eventviz (development version)

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
