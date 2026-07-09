# Changelog

## eventviz 0.1.0

Initial release. Turns the original single-file patient-journey timeline
script into a general-purpose event-log visualisation package:
location-band timelines, staircase stage diagrams for location-less
linear processes, cohort facets, aggregate/statistical summaries, an
interactive renderer, and three example datasets spanning healthcare,
complaints, and support tickets.

### Post-implementation review fixes

Four defects found in an executed review of the completed stages, plus
packaging-layout corrections:

- [`plot_journey_cohort()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_journey_cohort.md)
  (absolute-time mode) now sizes the cosmetic inter-box gap — and each
  box’s minimum render width — against each facet panel’s own time span
  instead of the whole cohort’s calendar span. Previously, a cohort
  whose cases were months apart rendered every box at many times its
  true width. Axis-break selection likewise now sees the widest single
  panel, giving per-panel time labels instead of one break sized for the
  whole calendar range. The `cohort-absolute` vdiffr baseline was
  re-rendered and visually re-approved for this change.
- [`plot_journey_cohort()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_journey_cohort.md)
  with `event_type_top_n`: the `"Other"` bucket now receives a colour
  from the event palette. Previously the cohort palette was built over
  the raw (unbucketed) event types, so `"Other"` silently fell back to
  the grey `na.value`.
- [`plot_journey_with_summary()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_journey_with_summary.md)
  now derives the bar-chart colours from the exact fill levels the
  timeline used (including any synthetic `"(pre-admission)"` box) and
  honours `palette_style`/`location_palette` passed through `...`.
  Previously the bars rebuilt their palette over a different level set,
  shifting every hue by one position whenever the two differed.
- [`plot_stage_ladder()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_stage_ladder.md)
  `stage_targets` now bands **every** visit to a stage a case re-enters,
  and draws the firebrick breach excess per visit. Previously only the
  first visit was banded and checked.
- [`plot_stage_ladder()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_stage_ladder.md)
  `stage_targets` now draws the breach excess for an *open*
  (end-inferred) stage too, whenever the dwell observed up to the last
  recorded event already exceeds the target — elapsed time is a lower
  bound, so a visible breach is proven. The excess is capped at the last
  observed instant, so a median/fixed-imputed end never inflates it.
  Previously an open stage never showed a breach at all.
- [`plot_journey_cohort()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_journey_cohort.md)
  now draws the `(ongoing)` open-spell marker in the panel of every case
  that never reaches a `terminal_activities` state (previously
  deferred), and gains a `tail_strategy` argument forwarded per case,
  for parity with
  [`plot_patient_journey()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_patient_journey.md).
- Packaging: the three example datasets moved to `data/` as lazy-loaded
  `.rda` files built by `data-raw/` scripts (documented in `R/data.R`),
  as the implementation plan’s Stage 0 specified; `LICENSE` now uses
  CRAN’s two-line form with the full text in `LICENSE.md`;
  `.Rbuildignore` patterns are anchored; `DESCRIPTION` declares
  `ggplot2 (>= 3.4.0)` (needed for `scale_linewidth_continuous()`) and
  `R (>= 3.5)`.

### Stage 10 — Documentation & packaging polish

- Added a `pkgdown` site (`_pkgdown.yml` + a `pkgdown.yaml` GitHub
  Actions workflow deploying to GitHub Pages) and four vignettes:
  `getting-started` (the clinical walkthrough), `adapting-your-data`
  (schema autodetection + the wide-to-long pivot wrapper together, for
  bringing your own data), `linear-processes` (band vs. staircase for
  complaints/tickets, and `stage_targets`), and `cohort-analysis`
  (facets + aggregate/breach/transition summaries).
- Rewrote `README.Rmd` to lead with the general framing (“visualise any
  timestamped event log”), a quick-start on `example_journey`, then a
  “Not just healthcare” section showing `complaint_example` (staircase)
  and `support_ticket_example` (band + cohort).

### Stage 9 — Test gap-closing & internal cleanup

- Added direct tests for
  [`plot_patient_journey()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_patient_journey.md)’s
  own orchestration logic that nothing else exercised: auto-generated
  title format (with and without `patient_col`, and explicit-title
  override), `exclude_categories` row-count accounting (the drop
  message, the no-op case, and the abort when every location event is
  removed), and the full `return_data = TRUE` shape
  (`list(plot, boxes, events, summary)`, checked against
  [`summarise_journey_durations()`](https://jaspercain01.github.io/event-driven-visualisation/reference/summarise_journey_durations.md)
  for the same case).
- Added the vdiffr baseline `support_ticket_example` was still missing
  (lanes/cohort/ladder already had one from their own stages).
- Internal: `derive_point_events()` now returns `list(events, pre_box)`
  instead of attaching the synthetic pre-admission box as an
  `attr(events, "pre_box")` attribute that happened to survive only
  because dplyr preserves unknown attributes through `mutate()`.
  Behaviour unchanged.
- Wired `covr`/Codecov into CI (`test-coverage.yaml`), targeting 85%
  project coverage.
- Fixed several packaging defects uncovered while doing the above, which
  had been silently blocking Stage 10 and CI from ever running
  correctly: `DESCRIPTION` was missing `Encoding: UTF-8`, which
  corrupted the em-dash characters in titles/labels at parse time — this
  had already corrupted the Stage 1.5 vdiffr baselines captured in an
  earlier session, now regenerated correctly; the CI workflow lived in a
  directory literally named `\.github` (a stray backslash) and had
  therefore never run; the hand-written `NAMESPACE` exported only 2 of
  the ~19 public functions; and no R file had any roxygen2
  documentation. Every exported function and dataset now has full
  documentation, and `NAMESPACE`/`man/` are generated from it rather
  than maintained by hand.

### Stage 8 — Generalisation polish

- New `support_ticket_example` dataset: six support tickets moving
  through Open -\> Assigned -\> In Progress -\> Waiting on Customer -\>
  Resolved -\> Closed, with point events (`comment_added`,
  `priority_changed`, `reassigned`, `sla_warning`), no patient column,
  one ticket stalled for days in “Waiting on Customer”, and one still
  open. Deliberately non-healthcare, proving the package leaves the NHS
  sector entirely (`complaint_example` from Stage 5b is still
  NHS-adjacent). Exercised end-to-end through
  [`plot_patient_journey()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_patient_journey.md)
  (`state_label = "Status"`),
  [`plot_stage_ladder()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_stage_ladder.md),
  and
  [`plot_journey_cohort()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_journey_cohort.md).
- New `theme_journey(base_size = 11)` in `R/theme.R` factors out the
  `theme_minimal()` call plus the grid-line and title styling shared by
  `render_journey_plot()` and
  [`plot_stage_ladder()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_stage_ladder.md);
  each renderer layers its own legend/axis/margin customisations on top.
  Output is unchanged — verified by comparing the two renderers’
  computed themes before and after the extraction, in addition to the
  existing vdiffr baselines.
- Light terminology pass:
  [`plot_patient_journey()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_patient_journey.md)’s
  header comment and the `location_categories` parameter comment now
  describe “location” generically (any exclusive state — a ward, a
  complaint stage, a ticket status, a pipeline step). No parameter names
  changed.

### Stage 7 — Interactive renderer

- [`plot_patient_journey()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_patient_journey.md)
  gains `interactive = FALSE`. When `TRUE`, it returns a
  [`ggiraph::girafe()`](https://davidgohel.github.io/ggiraph/reference/girafe.html)
  widget instead of a static `ggplot`: location boxes, terminal-state
  markers, and event points all gain hover tooltips. Box tooltips show
  the location, `format_duration()`-formatted duration, and entry/exit
  times, with an explicit `"(end inferred)"` / `"(inferred)"` caveat
  when the box’s end is imputed — a tooltip must never overclaim an end
  any more than the `show_duration` label may. Requires the `ggiraph`
  package (Suggests only); a
  [`requireNamespace()`](https://rdrr.io/r/base/ns-load.html) guard
  aborts with an install hint if it’s missing.
- Internal: `journey_layers()` gains an `opts$interactive` switch that
  emits ggiraph’s tooltip-bearing geoms (`geom_rect_interactive()`,
  `geom_segment_interactive()`, `geom_text_interactive()`,
  `geom_point_interactive()`) in place of their static equivalents for
  exactly the box/terminal-marker/point-event layers; every other layer
  (duration labels, reference lines, ggrepel event labels) is
  unaffected. New `render_journey_plot_interactive()`
  (`R/render_interactive.R`) calls `render_journey_plot()` with
  `opts$interactive = TRUE` and wraps the result in `girafe()` — no
  layer-building logic is duplicated.
- `interactive = FALSE` (the default) is untouched: the static layers
  stay the exact pre-Stage-7 `ggplot2::geom_*` classes, so every
  existing vdiffr baseline still applies unchanged.

### Stage 6 — Cohort aggregate / statistical views

- New
  [`summarise_journey_durations()`](https://jaspercain01.github.io/event-driven-visualisation/reference/summarise_journey_durations.md)
  returns one row per location stay across a cohort (case, location,
  entry/exit, duration, `end_inferred`, `terminal`), and
  [`summarise_stage_durations()`](https://jaspercain01.github.io/event-driven-visualisation/reference/summarise_stage_durations.md)
  builds per-location statistics on it (case count, mean/median/p25/p75
  dwell, `n_inferred_excluded`).
- New `summarise_breach_rate(data, target_hours, scope = ...)` reports
  what fraction of cases exceed a target. `scope = "spell"` measures
  whole-spell elapsed time (first move to last event);
  `scope = "<location>"` measures dwell within one stage (e.g. the ED
  4-hour standard). An unknown scope name aborts with a did-you-mean
  hint.
- New
  [`summarise_transitions()`](https://jaspercain01.github.io/event-driven-visualisation/reference/summarise_transitions.md)
  reduces the cohort to directed location-to-location transitions with
  counts and mean/median dwell in the origin state, and
  [`plot_transition_summary()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_transition_summary.md)
  draws them as a hand-rolled flow diagram (no new dependency): nodes
  ordered along a left-to-right spine, arrowed edges whose width encodes
  frequency, forward and backward transitions bowed opposite ways so
  re-entries stay legible.
- **Every duration statistic respects `end_inferred`.** The imputed end
  of a non-terminal final stay is a rendering convenience, not data;
  each summariser takes `include_inferred = FALSE` (default), excluding
  those durations from means/medians/quantiles and reporting
  `n_inferred_excluded`. `TRUE` folds them back in, with the
  `end_inferred` flag travelling in the output.
- `plot_patient_journey(return_data = TRUE)` now also returns a
  `summary` element
  ([`summarise_journey_durations()`](https://jaspercain01.github.io/event-driven-visualisation/reference/summarise_journey_durations.md)
  for that one case), so the return value is
  `list(plot, boxes, events, summary)`. Additive — existing callers are
  unaffected.
- New
  [`plot_journey_with_summary()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_journey_with_summary.md)
  (stretch) stacks a single case’s timeline above a per-stage dwell bar
  chart via `patchwork`, guarded with a
  [`requireNamespace()`](https://rdrr.io/r/base/ns-load.html) install
  hint.

### Stage 5b — Linear stage processes (staircase view)

- New
  [`plot_stage_ladder()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_stage_ladder.md)
  renders a strictly linear stage process (a complaint, an approval
  pipeline, a ticket lifecycle) as a Gantt-like staircase: stages on the
  y-axis with the first stage at the top, one horizontal segment per
  stage, thin grey connectors forming the steps, and duration labels at
  each segment midpoint. It reuses `derive_location_boxes()` verbatim
  (stages *are* boxes) — only the rendering differs.
- [`plot_stage_ladder()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_stage_ladder.md)
  accepts `stage_order` to pin the vertical ordering (default: first
  appearance) and `stage_targets`, a named `stage -> hours` vector
  rendering a light allowance band per targeted stage with any excess
  dwell drawn in `firebrick`. The terminal stage is drawn as a point
  marker, not a segment.
- [`plot_patient_journey()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_patient_journey.md)
  gains a `state_label` argument (default `"Location"`) setting the
  fill-legend title, so a complaint’s boxes read as “Stage” and a
  ticket’s as “Status”. Default output is unchanged.
- New `complaint_example` dataset: eight complaints moving through
  Acknowledgement -\> Triage -\> Assigned -\> Under review -\> Senior
  review -\> Formal letter sent, with no patient column (exercising
  `patient_col = NULL`). One complaint stalls ~3 weeks in “Under review”
  and one is still open, exercising the per-stage breach and
  ongoing-spell paths respectively.

### Stage 5 — Cohort view via faceting

- New
  [`plot_journey_cohort()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_journey_cohort.md)
  lays several spells out as a faceted small-multiples grid, one panel
  per case, for at-a-glance comparison. It reuses the single-case
  `validate_event_log()` + `build_journey_tables()` pipeline per case
  rather than re-deriving anything, and asserts cross-facet colour
  consistency (the same location keeps the same fill in every panel).
- `align_start = TRUE` rebases every case to elapsed hours from its own
  first move and draws them on one shared `+Nh` axis
  (`scales = "fixed"`) so durations line up; the default absolute-time
  mode gives each panel its own datetime range (`scales = "free_x"`). A
  `max_cases` guard (default 25) aborts rather than attempting to facet
  hundreds of spells.
- Internal: the ggplot renderer was split into `journey_layers()` (geoms
  only) plus scale/theme assembly, and gained an `x_scale` option
  (`"datetime"` / `"elapsed_hours"`) and optional faceting. The
  single-case path is byte-identical — every existing vdiffr baseline is
  unchanged.

### Stage 4 — Swimlanes (concurrent event tracks within one case)

- [`plot_patient_journey()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_patient_journey.md)
  gains a `lane_col` argument. When supplied, its distinct values become
  horizontal lanes and point events are stacked into them above the
  location band, so concurrent tracks within a single case (e.g. nursing
  / medical / diagnostics activity) no longer collide on one midline.
  Lanes affect point events only — the location boxes stay the spine.
  Lane order follows factor levels when the column is a factor, else
  first appearance.
- New `lane_height` / `lane_gap` arguments tune lane geometry; they
  default (`NULL`) to `box_height` and `0.05 * box_height`. Lanes stack
  upward from the reserved swimlane floor at `box_height * 1.3`, above
  the duration- and reference-label rows.
- The y-axis now labels each lane when swimlanes are active and stays
  blank otherwise. Many lanes make a tall plot — there is no automatic
  lane cap.
- `lane_col = NULL` (the default) reproduces the pre-Stage-4
  single-midline output byte-for-byte; the existing vdiffr baselines are
  unchanged.

### Stage 3 — Schema object + column autodetection

- New
  [`event_log_schema()`](https://jaspercain01.github.io/event-driven-visualisation/reference/event_log_schema.md)
  constructor: a classed list bundling
  `time_col`/`act_type_col`/`activity_col`/`case_col`/`patient_col`/
  `location_categories`, with a
  [`print()`](https://rdrr.io/r/base/print.html) method. Every field
  defaults to `NULL` (“not part of this schema”).
- New `autodetect_schema(data, location_categories = NULL)` matches
  column names against per-role candidate lists (case-insensitive exact
  match first, then `adist() <= 2` fuzzy match), resolving roles in a
  fixed order (time -\> case -\> act_type -\> activity -\> patient) so a
  column claimed by one role is never reconsidered for another. Two
  equally-good matches for one role, or an unresolved required role,
  abort naming the problem rather than guessing.
- [`plot_patient_journey()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_patient_journey.md)
  gains a `schema` argument. Precedence per field, highest wins: an
  explicit individual argument (`time_col`, `case_col`, …) \> the
  matching schema field \> the function’s existing hardcoded default.
  Autodetection only ever runs when `schema = "auto"` is passed
  literally — passing an
  [`event_log_schema()`](https://jaspercain01.github.io/event-driven-visualisation/reference/event_log_schema.md)
  object never triggers it. Default behaviour (no `schema` argument) is
  unchanged.

### Stage 2 — Wide-to-long pivot wrapper

- New
  [`pivot_events_longer()`](https://jaspercain01.github.io/event-driven-visualisation/reference/pivot_events_longer.md)
  reshapes wide, one-row-per-case milestone data (e.g. `arrival_time`,
  `triage_time`, `discharge_time` columns) into the long,
  one-row-per-event form
  [`plot_patient_journey()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_patient_journey.md)
  expects. Handles location vs. non-location milestones
  (`location_cols`), custom `act_type_map`/`activity_map` overrides,
  NA-milestone dropping, and suffix-stripped auto-labelling
  (`"arrival_time"` -\> `"Arrival"`).
- `tidyr` moved from Suggests to Imports (used by
  [`pivot_events_longer()`](https://jaspercain01.github.io/event-driven-visualisation/reference/pivot_events_longer.md)).
- Internal: timestamp coercion extracted from `validate_event_log()`
  into a shared `coerce_datetime_column()` helper, reused by the new
  pivot function.
- Fixed a pre-existing bug in `validate_event_log()`: filtering to a
  single case used a bare `case_id` inside
  [`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html),
  which dplyr’s data mask would resolve against a data column named
  `case_id` instead of the function argument whenever the case column
  happened to be named exactly `case_id` (a natural, common choice — and
  the one used throughout the new pivot wrapper’s own examples). Fixed
  by forcing environment lookup (`.env$case_id`). No change to
  previously-passing behaviour.

### Stage 0.5 — Defect fixes (sanctioned default-output change)

Nine defects found in an executed review, fixed ahead of the package
scaffolding since later stages build on the corrected semantics. This is
the first of the two intentional default-output changes for 0.1.0 (the
other being the Stage 1f palette): broken behaviour is not API surface.

- `show_labels = TRUE` silently dropped every label (labels nudged below
  a hard `scale_y_continuous(limits = ...)` were censored to `NA`).
  Fixed by expanding the lower y-range only when labels will actually
  render.
- Terminal states (e.g. “Discharged”) were extended into a fake
  multi-hour stay by the median tail-inference fallback. New opt-in
  `terminal_activities` parameter: a terminal final move gets zero
  duration and renders as a vertical marker with an italic direct label.
- The zero-width-nudge message claimed “stored duration is unaffected”
  while duration was actually computed *after* the nudge. `duration` is
  now computed before nudging, so a same-timestamp stay correctly stores
  0.
- A nudged box could render hidden behind its successor (same-timestamp
  moves). A render-only `xmin_render` stagger fixes the overlap without
  touching the true `xmin` that event assignment depends on.
- Three cryptic crash paths now abort with actionable messages: a
  mistyped `tail_strategy`, `exclude_categories` removing every location
  event, and a vector/`NA` `case_id`.
- Character timestamps were silently parsed as UTC regardless of the
  data’s actual timezone. New `tz` parameter threaded through to
  [`lubridate::as_datetime()`](https://lubridate.tidyverse.org/reference/as_date.html);
  `POSIXct` input keeps its own `tzone`.
- `patient_col` was mandatory. `patient_col = NULL` is now supported for
  event logs with no secondary identifier.
- Two side-by-side legends could overflow the plot width. Legends now
  stack vertically.
- `exclude_categories` crashed on every use that actually dropped rows
  (a malformed
  [`cli::cli_inform()`](https://cli.r-lib.org/reference/cli_abort.html)
  call with no `message` argument).

### Stage 1 — Visual quick wins

New opt-in features on
[`plot_patient_journey()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_patient_journey.md),
each defaulting to prior behaviour:

- `show_duration` — formatted duration label above each non-terminal
  box; boxes with an inferred end get a `"+"` suffix (1a).
- `reference_lines` — target/threshold vertical lines from a data frame
  of `offset_hours` + `label` (1b).
- Ongoing-spell indication — when `terminal_activities` is supplied but
  the case never reaches one, the final box’s right edge is drawn open
  with an `"(ongoing)"` marker (1c).
- `label_boxes` — direct location labels at box centres (1d).
- `event_type_top_n` — collapse a high-cardinality `act_type` tail into
  `"Other"` before the colour/shape scales are built (1e).

#### Default-output change (sanctioned)

- **New default palette (1f).** `journey_palette()` gains
  `palette_style = c("okabe", "brewer")`, defaulting to `"okabe"`: a
  colourblind-safe Okabe-Ito palette (locations lightened, events offset
  by four hues so co-indexed location/event pairs never share a colour).
  Pass `palette_style = "brewer"` to restore the previous Set2/Dark2
  colours. This is one of the two intentional default-output changes for
  0.1.0 (the other being the Stage 0.5 defect fixes).
