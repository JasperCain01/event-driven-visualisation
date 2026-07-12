# Implementation Plan — eventviz (working name)

This plan turns the current single-file-sourced set of R scripts into a
proper, general-purpose event-log visualisation package.

**Revision 2 (2026-07-04).** Amended after an executed review (R 4.3.3,
full test suite + rendered-output inspection) found eight defects the
original read-only review missed, plus internal contradictions in
revision 1 of this plan. Changes in this revision:

- **Stage 0.5 (defect fixes) added — and already IMPLEMENTED** in the
  same commit as this revision. Nine defects fixed with 21 regression
  tests.
- **Stage 1.5 (visual baselines) added**: vdiffr snapshots are captured
  right after the visual quick wins, *before* the refactor-heavy stages
  they exist to protect — not at the end (revision 1 would have
  snapshotted broken behaviour as the baseline).
- **Stage 5b (linear stage processes) added**: first-class support for
  location-less linear journeys (complaints, approvals, ticket
  pipelines), including a staircase layout and a complaint example
  dataset.
- Stage 1f palette spec corrected (revision 1 gave locations and events
  identical colours); backward-compatibility decision de-contradicted;
  vertical layout budget added; Stage 3 autodetect made unambiguous;
  Stage 5’s renderer refactor made explicit; Stage 6 statistics now
  respect the `end_inferred` flag and support per-stage breach targets;
  machine-checkable render gates added to every render-touching stage.

Package name `eventviz` is a placeholder — rename freely in Stage 0.

## How to read this plan

Each stage has: - **Depends on** — stages that must land first - **Model
tag** — who should drive it (see legend) - **Files** — created/touched -
**Steps** — specific enough to implement without further design
decisions - **Tests** — what must exist before the stage is “done” -
**Definition of done**

### Model tag legend

| Tag | Meaning |
|----|----|
| 🟢 LOCAL-OK | Spec below is complete and unambiguous. A small/quantised local model should implement directly from the steps given. |
| 🟡 FRONTIER-DESIGN-THEN-LOCAL | A design decision is required first. This plan already makes that call where possible — where it says “frontier should confirm,” a quick review is enough; implementation afterward is 🟢. |
| 🔴 FRONTIER-REQUIRED | Needs ongoing judgment (visual QA, statistical/visual-encoding design, architecture with real regression risk). Should be driven or closely reviewed by a frontier model throughout, not just checked at the end. |

### Universal acceptance gate (applies to EVERY render-touching stage)

The original `show_labels` bug shipped because the code ran without
error while silently dropping every label. To make that class of failure
machine-detectable — essential when delegating to local models — **every
stage that adds or changes a render path must include this assertion in
its tests**:

``` r

expect_no_warning(ggplot2::ggplot_build(p))
```

A ggplot warning at build time (“Removed N rows…”, scale clashes, etc.)
is a test failure, full stop. `tests/testthat/test-fixes.R` shows the
pattern.

### Design decisions locked in (so no stage re-litigates them)

1.  **Swimlanes ≠ multi-case.** Concurrent event tracks *within one
    case* (Stage 4) and *comparing across cases* (Stage 5) are different
    axes: swimlanes generalise the existing `assign_y_bands` machinery;
    cohort comparison uses
    [`ggplot2::facet_wrap()`](https://ggplot2.tidyverse.org/reference/facet_wrap.html).

2.  **Cohort view is a new function**, `plot_journey_cohort()`, not an
    overload of `case_id` inside `plot_patient_journey()`.

3.  **Interactive renderer uses `ggiraph`, not `plotly`** — it decorates
    existing ggplot2 geoms rather than translating the whole plot.

4.  **No new heavy dependencies for v1 of the transition diagram** —
    hand-rolled with `geom_segment`; `ggalluvial` is a v2 stretch goal.

5.  **Backward compatibility, amended.** Every new feature is opt-in
    with a default reproducing current behaviour, *with exactly two
    sanctioned exceptions*, both landing in the 0.1.0 packaging
    milestone and called out in NEWS.md: (a) the Stage 0.5 defect fixes
    (broken behaviour is not API surface — e.g. labels now render,
    `duration` now stores the true value); (b) the Stage 1f default
    palette change. Nothing else may alter default output; existing
    tests keep passing unmodified through every stage.

6.  **Vertical layout budget.** Three features want space above the
    location band. They MUST use these reserved y-ranges (in units of
    `box_height` = h, band occupying `[0, h]`) and nothing else:

    | y-range | Reserved for | Stage |
    |----|----|----|
    | `[0, h]` | Location boxes + event midline | existing |
    | `< 0` (lower expansion) | ggrepel event labels | existing (fixed in 0.5) |
    | `[h, 1.12h]` | Duration labels (`y = 1.04h`, vjust 0) + terminal-marker labels | 1a / 0.5 |
    | `[1.12h, 1.3h]` | Reference-line labels (`y = 1.14h`, vjust 0) | 1b |
    | `[1.3h + lane_gap, …]` | Swimlanes stack upward from `1.3h` | 4 |

    Any stage needing new vertical space amends this table first, in its
    own PR, so collisions are caught at review time rather than render
    time.

7.  License placeholder: MIT. Change in Stage 0 if the user wants
    otherwise.

### Stage order and dependency graph

    Stage 0    (package scaffolding)
    Stage 0.5  (defect fixes)  ✅ DONE — implemented pre-scaffolding with tests
       |
       +--> Stage 1  (visual quick wins) --> Stage 1.5 (vdiffr baselines)
       +--> Stage 2  (pivot wrapper)          } 1, 2, 3 parallel-safe after 0
       +--> Stage 3  (schema/autodetect)      }

       Stage 1.5 + 3 --> Stage 4  (swimlanes)
       Stage 4       --> Stage 5  (cohort facets)
       Stage 5       --> Stage 5b (linear stage processes / staircase)
       Stage 5b      --> Stage 6  (aggregate/statistical views)
       Stage 1.5 + 4 --> Stage 7  (interactive renderer)
       Stage 5b      --> Stage 8  (generalisation polish)
       all           --> Stage 9  (test gap-closing)
       all           --> Stage 10 (docs / pkgdown)

Stages 1, 2, 3 may run concurrently (independent files). Everything from
Stage 4 onward is sequential — each edits `render.R` and/or
`plot_patient_journey.R`.

------------------------------------------------------------------------

## Stage 0 — Package scaffolding

**Depends on:** nothing **Model tag:** 🟢 LOCAL-OK

**Files:** `DESCRIPTION`, `NAMESPACE`, `.Rbuildignore`, `LICENSE`,
`LICENSE.md`, `tests/testthat.R`, `.github/workflows/R-CMD-check.yaml`,
roxygen comments added to existing `R/*.R` files.

**Steps**

1.  Create `DESCRIPTION`:
    - `Package: eventviz`, `Version: 0.1.0`, `Title`, `Description`,
      `License: MIT + file LICENSE`
    - `Imports: dplyr, tibble, ggplot2, ggrepel, cli, lubridate, rlang, stats, utils`
    - `Suggests: testthat (>= 3.0.0), RColorBrewer, tidyr, ggiraph, patchwork, vdiffr, knitr, rmarkdown`
    - `Config/testthat/edition: 3`
2.  Add roxygen2 `#'` blocks above every exported function
    (`plot_patient_journey`, `example_journey` as data) with `@param`,
    `@return`, `@export`, one `@examples` block each. Documentation must
    cover the Stage 0.5 additions: `tz`, `terminal_activities`,
    `patient_col = NULL` support, and the
    `terminal`/`end_inferred`/`xmin_render` columns of the `boxes` table
    returned by `return_data = TRUE`. Internal helpers get
    `@keywords internal` or `@noRd`.
3.  Run `roxygen2::roxygenise()` to generate `NAMESPACE` and `man/*.Rd`.
    Never hand-write `NAMESPACE`.
4.  Move `example_journey` into package data:
    `data-raw/example_journey.R` with the existing
    `make_example_journey()` body,
    `usethis::use_data(example_journey, overwrite = TRUE)`, document in
    `R/data.R`, delete the
    [`source()`](https://rdrr.io/r/base/source.html)-based
    `R/example_data.R`.
5.  Update `tests/testthat/test-*.R`: remove the `source("../../R/…")`
    headers (including from `test-fixes.R`); add `tests/testthat.R` with
    the standard `test_check("eventviz")` body.
6.  `.Rbuildignore`: `IMPLEMENTATION_PLAN.md`, `data-raw/`, `.github/`.
7.  `.github/workflows/R-CMD-check.yaml` from the `check-standard`
    template.
8.  `LICENSE`/`LICENSE.md` (MIT).

**Tests:** none new — the existing suite (including `test-fixes.R`)
passes unchanged under `devtools::test()`; `devtools::check()` runs 0
errors / 0 warnings.

**Definition of done** - \[ \] `devtools::load_all()` succeeds - \[ \]
`devtools::test()` — all pre-existing tests pass, none skipped - \[ \]
`devtools::check()` — 0 errors, 0 warnings - \[ \] `example_journey`
accessible as
[`eventviz::example_journey`](https://jaspercain01.github.io/event-driven-visualisation/reference/example_journey.md)

------------------------------------------------------------------------

## Stage 0.5 — Defect fixes ✅ COMPLETE

**Status: implemented and tested in the same commit as this plan
revision**, ahead of scaffolding, because later stages build on the
corrected semantics and Stage 1.5’s baselines must capture *fixed*
behaviour. 21 regression tests in `tests/testthat/test-fixes.R`; full
suite 72 passing.

What was fixed (defect → fix → where):

1.  **`show_labels = TRUE` silently dropped every label** (labels nudged
    below hard `scale_y_continuous(limits=…)` were censored to NA).
    Fixed by removing the hard limits and expanding the lower y-range
    only when labels will actually render. `R/render.R`.
2.  **Terminal states were extended into fake stays** (example data
    showed a ~4.75 h “Discharged” box invented by the median tail
    fallback). New opt-in `terminal_activities` parameter: a terminal
    final move gets zero duration and renders as a vertical marker with
    an italic direct label, outside the fill legend.
    `R/plot_patient_journey.R`, `R/transform.R`, `R/render.R`.
3.  **The zero-width-nudge message lied** (“Stored duration is
    unaffected” while duration was computed *after* the nudge).
    `duration` is now computed before nudging (a same-timestamp stay
    stores 0) and the message says so. `R/transform.R`.
4.  **A nudged box was hidden behind its successor** (same-timestamp
    moves). New render-only `xmin_render` stagger; true `xmin` untouched
    so event assignment is unaffected. Known limitation: 3+ moves
    sharing one timestamp still compress to sliver widths — acceptable,
    documented. `R/transform.R`, `R/render.R`.
5.  **Three cryptic crash paths** now abort cleanly with actionable
    messages: typo’d `tail_strategy` (`match.arg`, `R/utils.R`);
    `exclude_categories` removing every location event (post-exclusion
    re-check, `R/plot_patient_journey.R`, plus a defensive n_boxes==0
    guard in `R/transform.R`); vector/NA `case_id` (scalar guard,
    `R/validate.R`).
6.  **Character timestamps were silently parsed as UTC.** New `tz`
    parameter threaded through to `lubridate::as_datetime(…, tz = tz)`;
    POSIXct input keeps its own tzone. `R/plot_patient_journey.R`,
    `R/validate.R`.
7.  **`patient_col` was mandatory.** `patient_col = NULL` now supported
    for logs with no secondary identifier; title falls back to
    `"Case <id>"`. `R/validate.R`, `R/plot_patient_journey.R`.
8.  **Legend clipping/truncation** (two side-by-side legends overflowed
    plot width). Legends now stack vertically. `R/render.R`.
9.  **Bonus defect found while fixing 5:** the row-drop notification
    called `cli::cli_inform("i" = …)` with no `message` argument —
    meaning `exclude_categories` crashed on *every* use that dropped
    rows. Wrapped in [`c()`](https://rdrr.io/r/base/c.html).
    `R/plot_patient_journey.R`.

Also added: `end_inferred` flag on every box (TRUE only for a
non-terminal final box) so Stage 6 statistics can exclude imputed ends;
dead `box_id = .orig_row` pseudo-traceability code removed.

Deliberately NOT fixed here: the Set2/Dark2 palette-hue pairing (Stage
1f owns the palette change under locked decision 5’s sanctioned
exception) and the `attr(events, "pre_box")` handoff (works, relies on
dplyr attribute preservation; replace with an explicit list return in
Stage 9 cleanup).

------------------------------------------------------------------------

## Stage 1 — Visual quick wins (no architecture change)

**Depends on:** Stage 0 **Model tag:** 🟢 LOCAL-OK for 1a–1f
individually; 🔴 FRONTIER-REQUIRED for a final combined visual QA pass
(render one plot with everything switched on at once and eyeball it for
layer collisions).

**Files:** `R/render.R`, `R/transform.R`, `R/utils.R`,
`R/plot_patient_journey.R`, `tests/testthat/test-render.R` (new).

### 1a. Duration labels on boxes

- Add `format_duration(secs)` to `utils.R`: `< 60` → `"Ns"`; `< 3600` →
  `"Nm"`; `< 86400` → `"Hh Mm"` (drop zero minutes); `>= 86400` →
  `"Dd Hh"`.
- Add `show_duration = FALSE` to `plot_patient_journey()`, thread
  through `opts`.
- When `TRUE`: `geom_text()` on non-terminal boxes,
  `x = xmin_render + (xmax_render - xmin_render)/2`,
  **`y = box_height * 1.04`, vjust 0** (layout budget row 3 — NOT
  ymax+0.03 as in plan revision 1), `label = format_duration(…)`, size
  2.6, colour grey30. Boxes with `end_inferred` append `"+"` to the
  label (e.g. `"4h 45m+"`) — the end is imputed and the label must not
  overclaim.

### 1b. Reference-line / target-threshold layer

- `reference_lines = NULL`: data frame with `offset_hours` (numeric,
  from first event) and `label`. Validate shape, else `cli_abort`.
- Renders `geom_vline` (dashed, firebrick) plus text at
  **`y = box_height * 1.14`, vjust 0** (layout budget row 4), size 2.8.
  Horizontal text, `hjust = -0.05` (just right of the line) — angled
  text was revision-1 speculation; confirm orientation in the 1-final QA
  pass.

### 1c. Ongoing-spell indication

Builds on Stage 0.5’s `terminal_activities` (which handles the *reached*
terminal state). This sub-feature handles the converse: **the case never
reached a terminal state** — the data feed just stopped. - When
`terminal_activities` is supplied AND the final location is NOT in it,
set `attr(boxes, "spell_open") <- TRUE` in `derive_location_boxes()`. -
Render: final box’s right edge drawn as a dashed vertical `geom_segment`
at `xmax` plus an italic `"(ongoing)"` annotation at
`y = box_height * 1.04` right-aligned to `xmax`. -
`terminal_activities = NULL` (default) → attribute FALSE → no visual
change.

### 1d. Direct box labelling

- `label_boxes = FALSE`. When `TRUE`: `geom_text` at box centres
  (`y = box_height/2 + 0.06`, nudged off the event midline), size 2.6,
  `check_overlap = TRUE` to silently drop colliding labels — no new
  dependency.

### 1e. High-cardinality event-type bucketing

- `event_type_top_n = NULL`. When set and distinct `act_type` count
  exceeds it: keep top-N by frequency, recode the rest to `"Other"`,
  before colour/ shape scales are built. `cli_inform` names the
  collapsed types.

### 1f. Colourblind-safe default palette — CORRECTED SPEC

Revision 1 applied the same Okabe-Ito set to both palettes, which would
give location 1 and event-type 1 *identical* colours — worse than
today’s matched-hue Set2/Dark2 problem. Corrected:

- `journey_palette()` gains `palette_style = c("okabe", "brewer")`,
  default `"okabe"`.
- `"okabe"`, locations (fills): the 8 Okabe-Ito colours **lightened 40%
  toward white** via
  [`colorspace::lighten()`](https://colorspace.R-Forge.R-project.org/reference/lighten.html)
  if available else `grDevices::colorRampPalette(c(col, "white"))(5)[3]`
  per colour (no new hard dependency).
- `"okabe"`, events (points): the saturated Okabe-Ito originals **offset
  by 4 positions** (event 1 gets colour 5, wrapping) so co-indexed
  location/event pairs never share a hue.
- `"brewer"`: existing Set2/Dark2, kept verbatim for anyone pinning old
  colours.
- This is sanctioned exception (b) of locked decision 5: the ONE
  intentional default-output change outside Stage 0.5. NEWS.md entry
  required.

**Tests (`test-render.R`):** - `format_duration()` exact strings at 0,
59, 60, 3599, 3600, 3660, 86399, 86400, 90000 secs. - `ggplot_build()`
layer-count assertions per feature toggle (each feature adds exactly its
expected layer; defaults add none). - Universal render gate on a plot
with ALL Stage 1 features enabled at once. - `"okabe"`: assert
`setdiff(loc_colours, evt_colours)` has no common hex; `"brewer"`
reproduces prior Set2/Dark2 output exactly. - `end_inferred` boxes get
the `"+"` duration suffix; terminal boxes get no duration label.

**Definition of done** - \[ \] All six features opt-in; with defaults,
`ggplot_build()` layer list identical to Stage 0.5 output except palette
hexes (1f) - \[ \] Universal render gate passes with all features on
simultaneously - \[ \] One combined `ggsave()` render visually reviewed
by a frontier pass

------------------------------------------------------------------------

## Stage 1.5 — Visual regression baselines (vdiffr)

**Depends on:** Stage 1 **Model tag:** 🔴 FRONTIER-REQUIRED — a baseline
nobody has looked at is worthless; every snapshot must be rendered and
visually confirmed once before committing.

Moved from the end of the plan (revision 1’s Stage 9) to here: baselines
must exist **before** the refactor-heavy stages (4, 5, 7, 8) they
protect, and must capture post-0.5 *fixed* behaviour.

**Files:** `tests/testthat/test-render-snapshots.R`, `DESCRIPTION`
(vdiffr → Suggests).

**Snapshots on `example_journey`** (each
[`vdiffr::expect_doppelganger()`](https://vdiffr.r-lib.org/reference/expect_doppelganger.html),
descriptively named): 1. default plot 2. `show_labels = TRUE` (with
`exclude_categories = c("obs","test_ordered")` so the snapshot stays
legible) 3. `show_duration = TRUE` 4. `label_boxes = TRUE` 5.
`terminal_activities = "Discharged"` 6. `reference_lines` with one
4-hour target 7. everything on at once

**Definition of done** - \[ \] All seven baselines committed AFTER a
frontier pass has rendered and visually approved each one - \[ \] CI
runs them (vdiffr skips gracefully where unavailable)

------------------------------------------------------------------------

## Stage 2 — Wide-to-long pivot wrapper

**Depends on:** Stage 0 (and benefits from 0.5’s fixes: wide milestone
data routinely contains equal timestamps in adjacent columns, which
lands directly on the nudge/stagger paths fixed there) **Model tag:** 🟢
LOCAL-OK, except the `coerce_datetime_column()` extraction touches
shared validation code — run the full suite after that refactor before
writing any new code.

**Files:** new `R/pivot_wide.R`, new `tests/testthat/test-pivot.R`,
shared helper extracted from `validate.R` into `utils.R`.

**Prerequisite micro-refactor:** extract the timestamp-coercion block
from `validate_event_log()` into `utils.R`:

``` r

coerce_datetime_column(x, col_label, tz = "UTC")
# returns coerced POSIXct, or cli_abort()s naming which values failed
```

`validate_event_log()` calls it (passing its `tz` through). Pure
refactor — `test-validate.R` and `test-fixes.R` must pass unchanged.

**New function:**

``` r

pivot_events_longer(
  data,
  case_col,
  time_cols,                 # character vector of wide column names to pivot
  patient_col     = NULL,
  location_cols   = NULL,    # subset of time_cols; become act_type "location_move"
  act_type_map    = NULL,    # named chr: time_cols entry -> act_type
  activity_map    = NULL,    # named chr: time_cols entry -> display label
  drop_na         = TRUE,
  tz              = "UTC",   # forwarded to coerce_datetime_column()
  time_col_out     = "timestamp",
  act_type_col_out = "act_type",
  activity_col_out = "activity"
)
```

**Behaviour spec:**

1.  Validate `case_col` and every `time_cols` entry exist; abort listing
    missing + present names (mirror `validate.R`’s message style).
2.  `location_cols` must be a subset of `time_cols`; abort naming
    offenders.
3.  Coerce every `time_cols` column via
    `coerce_datetime_column(…, tz = tz)`.
4.  `tidyr::pivot_longer(cols = all_of(time_cols), names_to = ".milestone", values_to = time_col_out)`
    — non-pivoted columns (case, patient, metadata like diagnosis) pass
    through automatically; don’t hand-roll.
5.  `drop_na = TRUE`: drop NA-timestamp rows with a per-milestone
    `cli_inform` count (an NA milestone means “didn’t happen for this
    case” — expected, not an error).
6.  `act_type_col_out`: `location_cols` member → `"location_move"`; else
    `act_type_map` entry; else the raw `.milestone` string (never NA).
7.  `activity_col_out`: `activity_map` entry if present; else prettified
    `.milestone` — **first strip common timestamp suffixes** (`_time`,
    `_at`, `_date`, `_ts`, `_datetime`, case-insensitive, end-anchored
    regex), then replace `_`/`.` with spaces, then
    [`tools::toTitleCase()`](https://rdrr.io/r/tools/toTitleCase.html).
    `"arrival_time"` → `"Arrival"`, not `"Arrival Time"`.
8.  Drop `.milestone`; column order: case, patient (if given), time,
    act_type, activity, then passthrough columns.
9.  Output must feed `plot_patient_journey()` directly with matching col
    args.

**Tests (`test-pivot.R`):** - Fixture: 3 cases, cols `case_id`,
`patient_id`, `arrival_time`, `triage_time`, `ward_time`,
`discharge_time`, `diagnosis`. - Basic pivot: row count, act_type
values, suffix-stripped labels (`"Arrival"` not `"Arrival Time"`). -
Missing `case_col` aborts; `location_cols ⊄ time_cols` aborts naming the
column; NA milestone dropped with message. - **Equal-timestamp
milestones for one case** (arrival == triage): pivots cleanly AND the
end-to-end plot call renders under the universal gate — this exercises
the Stage 0.5 stagger fix from the pivot side. - End-to-end: pivot →
`plot_patient_journey(...)` → `expect_s3_class(p, "ggplot")` +
`expect_no_warning(ggplot_build(p))`. - `diagnosis` passthrough intact.

**Definition of done** - \[ \] Implemented to spec; `tidyr` added to
Imports - \[ \] `coerce_datetime_column()` extracted; validate/fixes
suites unchanged - \[ \] End-to-end + equal-timestamp tests passing

------------------------------------------------------------------------

## Stage 3 — Schema object + column/category auto-detection

**Depends on:** Stage 0 **Model tag:** 🟡 FRONTIER-DESIGN-THEN-LOCAL —
resolution rules now fully specified; frontier confirms precedence
doesn’t break earlier stages, then implementation is 🟢.

**Files:** new `R/schema.R`, new `tests/testthat/test-schema.R`, edit
`R/plot_patient_journey.R`.

**[`event_log_schema()`](https://jaspercain01.github.io/event-driven-visualisation/reference/event_log_schema.md)
constructor:** as revision 1 —
`time_col/act_type_col/activity_col/case_col/patient_col/location_categories`,
returns classed list, [`print()`](https://rdrr.io/r/base/print.html)
method.

**`autodetect_schema(data, location_categories = NULL)` — CORRECTED
SPEC:**

Candidate lists (case-insensitive): - `time_col`:
`timestamp, time, ts, datetime, date_time, event_time, event_time_stamp` -
`case_col`:
`case_id, caseid, case, spell_id, episode_id, encounter_id, complaint_id, ticket_id`
— **`id` removed**: it matches any surrogate/row key and is more likely
wrong than right. - `act_type_col`:
`act_type, event_type, category, type, event_category` - `activity_col`:
`activity, label, description, event_name, name` — bare `event` removed
(fuzzy distance ≤ 2 from `event_type` made one column claimable by two
roles). - `patient_col`: `patient_id, patient, k_number, mrn, person_id`

Resolution algorithm (replaces revision 1’s per-role independent
matching): 1. Roles are resolved **in fixed order** time → case →
act_type → activity → patient. Each data column may be claimed by at
most one role; once claimed it is removed from later roles’
consideration. 2. Per role: exact case-insensitive match first; else
`adist() ≤ 2` fuzzy match (reuse `suggest_matches()`). 3. If two
unclaimed columns tie for one role (equal distance), **abort** naming
both and asking for an explicit
[`event_log_schema()`](https://jaspercain01.github.io/event-driven-visualisation/reference/event_log_schema.md)
— never pick silently. 4. Required roles (all but patient) unresolved →
abort naming them, the columns tried, and the
[`event_log_schema()`](https://jaspercain01.github.io/event-driven-visualisation/reference/event_log_schema.md)
escape hatch. 5. On success, `cli_inform` one line per field, stating
exact vs fuzzy.

**Wiring into `plot_patient_journey()`:** `schema = NULL` param.
Precedence per field, highest wins: explicit individual argument →
schema field → current hardcoded default. Autodetect ONLY on the
explicit sentinel `schema = "auto"` — never silently.

**Tests:** construction/print; fuzzy recovery on a renamed
`example_journey`; tie → abort; nonsense columns → abort naming roles;
per-field precedence (explicit `act_type_col` beats schema, `time_col`
comes from schema); claimed-column exclusivity (a column matching both
time and activity lists is consumed by time only); all earlier suites
pass untouched with no `schema` argument.

**Definition of done** - \[ \] Ordered, exclusive, tie-aborting
resolution implemented as specified - \[ \] All prior tests pass
unmodified - \[ \] `test-schema.R` passing

------------------------------------------------------------------------

## Stage 4 — Swimlanes (concurrent event tracks within one case)

**Depends on:** Stages 1.5, 3 **Model tag:** 🔴 FRONTIER-REQUIRED for
the y-band generalisation and conditional axis visibility; 🟢 LOCAL-OK
for parameter plumbing afterward.

**Files:** `R/transform.R`, `R/render.R`, `R/plot_patient_journey.R`,
new `tests/testthat/test-transform-lanes.R`.

**Design (consumes layout budget row 5):** - Location boxes stay the
spine at `[0, box_height]`; lanes affect **point events only**. -
`lane_col = NULL` (default) → behaviour byte-identical to Stage 1.5
baselines (vdiffr proves it, not eyeballs). - When supplied: lane order
= factor levels if factor, else first-appearance order. Lane *i*
(1-indexed) occupies
`[base + i*lane_gap + (i-1)*lane_height, base + i*lane_gap + i*lane_height]`
where **`base = box_height * 1.3`** (the budget’s swimlane floor — NOT
directly atop the band, which duration/reference labels own). New params
`lane_height = box_height`, `lane_gap = 0.05 * box_height`. -
`derive_point_events()` gains `lane_col`; computes lane index → `y`. -
Axis: `axis.text.y` shows lane names only when lanes active; blank
otherwise. Branch the two theme lines on a `lanes_active` flag in `opts`
— do not restructure the theme block. - Duration labels (1a) and
reference labels (1b) sit below the lane floor by construction; the
combined-features vdiffr snapshot must be re-approved with lanes on (new
snapshot 8, frontier-reviewed). - Document (roxygen `@details`): many
lanes → tall plot; no auto-capping.

**Tests:** hand-computed lane y arithmetic for 3 lanes;
`lane_col = NULL` vdiffr baseline unchanged; axis element
blank/non-blank via `p$theme$axis.text.y` inheritance; universal render
gate with lanes + duration labels + reference lines simultaneously.

**Definition of done** - \[ \] Null path proven identical via existing
vdiffr baselines - \[ \] Lane arithmetic fixture-verified; combined
snapshot 8 approved - \[ \] Axis visibility toggles only with lanes

------------------------------------------------------------------------

## Stage 5 — Cohort view via faceting

**Depends on:** Stage 4 **Model tag:** 🟡 FRONTIER-DESIGN-THEN-LOCAL —
with one 🔴 exception: the renderer x-scale refactor below is the kind
of change that must be frontier-reviewed against the vdiffr baselines.

**Files:** new `R/cohort.R`, edit `R/render.R`, new
`tests/testthat/test-cohort.R`.

**Prerequisite refactor (revision 1 omitted this and a local model would
have hit a wall):** `render_journey_plot()` hardcodes
`scale_x_datetime`, but `align_start = TRUE` needs a numeric
elapsed-hours axis. Refactor FIRST:

- Split `render_journey_plot()` internally into
  `journey_layers(boxes, events, opts)` (geoms only) +
  x-scale/y-scale/theme assembly.
- `opts$x_scale` ∈ `{"datetime", "elapsed_hours"}` (default
  `"datetime"`). `"elapsed_hours"` emits
  `scale_x_continuous(labels = \(x) paste0("+", x, "h"))` and skips
  `choose_date_breaks()`.
- Gate: all vdiffr baselines unchanged after the refactor. Only then
  build the cohort function.

**`plot_journey_cohort()`** as revision 1 (`case_ids = NULL` → all;
per-case `validate_event_log()` + `build_journey_tables()` reuse — never
duplicate; bind with a `case_id` column;
`facet_wrap(~case_id, scales = "free_x", ncol = ncol)` for absolute
time; `align_start = TRUE` rebases each case to its first move and uses
`x_scale = "elapsed_hours"` with `scales = "fixed"` — aligned cases
exist to be compared on one axis). Plus, inherited from later thinking:
`terminal_activities`, `tz`, `patient_col = NULL` all forwarded; a
`max_cases = 25` guard aborting with advice to pass explicit `case_ids`
(faceting hundreds of spells is a hang, not a plot).

**Tests:** 3-case fixture; panel counts for NULL/subset `case_ids`;
`align_start` → every case’s first box at 0; **cross-facet colour
consistency asserted via `ggplot_build()` fill values** (same location,
same hex, every panel); `max_cases` guard; universal render gate both
modes.

**Definition of done** - \[ \] x-scale refactor landed with baselines
unchanged FIRST - \[ \] Cohort function reuses internals, both modes
tested, colour consistency proven

------------------------------------------------------------------------

## Stage 5b — Linear stage processes (no locations at all)

**Depends on:** Stage 5 **Model tag:** 🟡 FRONTIER-DESIGN-THEN-LOCAL —
the staircase encoding below should be frontier-confirmed on the
complaint dataset once, then it’s 🟢.

**Purpose.** Many event logs have no spatial component: a complaint
moves acknowledgement → triage → assignment → review → senior review →
formal letter; a purchase order moves raised → approved → fulfilled.
Stage 0.5 already proved the *band* layout handles this today (stage
transitions as `location_categories`, `patient_col = NULL`,
`terminal_activities` for the closing letter — see the rendered
complaint demo from the review). This stage makes that first-class
rather than incidental.

**Files:** new `R/stage_ladder.R`, `data-raw/complaint_example.R`,
`R/data.R` addition, edits to `R/plot_patient_journey.R` (one param),
new `tests/testthat/test-stage-ladder.R`.

### 5b-1. `complaint_example` dataset

~8 complaints, one `complaint_id` each, stages
`Acknowledgement → Triage → Assigned → Under review → Senior review → Formal letter sent`
as `act_type = "stage_change"`, sprinkled point events (`contact`,
`escalation`, `evidence_received`), varying dwell times including one
complaint that stalls 3 weeks in “Under review” and one still open
(never reaches the letter — exercises Stage 1c). No patient column —
this dataset deliberately exercises `patient_col = NULL`.

### 5b-2. Legend/vocabulary fit

`plot_patient_journey()` gains `state_label = "Location"` — the fill
legend title (a complaint’s stages are not “Locations”). Single string
param, threaded through `opts` to
`scale_fill_manual(name = state_label)`. Default unchanged.

### 5b-3. `plot_stage_ladder()` — the staircase view

The band layout answers “what happened when”; for strictly linear
processes the more compelling question is “**where does the time go**”,
which wants stage on the y-axis:

``` r
plot_stage_ladder(
  data, case_id,
  stage_categories,               # act_types that mark stage entry
  stage_order   = NULL,           # explicit stage ordering; NULL = first appearance
  time_col/act_type_col/activity_col/case_col as elsewhere,
  patient_col   = NULL,
  tz            = "UTC",
  terminal_activities = NULL,
  stage_targets = NULL,           # named numeric: stage -> target dwell hours
  show_duration = TRUE
)
```

- Derivation: reuse `derive_location_boxes()` verbatim (stages ARE
  boxes); the difference is purely rendering.
- Render: y = stage (factor, `stage_order` or first-appearance, first
  stage at the TOP so the case walks down-right like a Gantt); one
  horizontal segment per stage from `xmin` to `xmax` (`linewidth ≈ 4`,
  colour = stage fill); thin grey vertical connectors between
  consecutive stage ends/starts, producing the staircase; duration text
  at each segment’s midpoint (reuses `format_duration()`, `"+"` suffix
  for `end_inferred`); terminal stage drawn as a point marker, not a
  segment.
- `stage_targets`: per-stage allowance rendered as a light band from
  stage entry to entry+target on that stage’s row; dwell beyond it draws
  the excess in `firebrick`. This is the per-stage breach made visual —
  Stage 6b computes the same thing numerically.
- Cohort variant deferred:
  [`plot_stage_ladder()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_stage_ladder.md)
  is single-case in this stage; overlaying many cases (spaghetti) is
  Stage 6/v2 territory — noted in Out of scope.

**Tests:** ladder returns ggplot under the universal gate; stage y-order
respects `stage_order` and errors on unknown stage names; duration
labels present; `stage_targets` adds exactly one band layer per targeted
stage; terminal stage renders as point; end-to-end on
`complaint_example` for BOTH `plot_patient_journey()` (band) and
[`plot_stage_ladder()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_stage_ladder.md)
(staircase); the still-open complaint shows the 1c ongoing treatment.

**Definition of done** - \[ \] `complaint_example` ships and is
exercised end-to-end in both layouts - \[ \] `state_label` param
threaded; default output unchanged - \[ \] Staircase encoding
frontier-approved once on the complaint data; vdiffr snapshot added

------------------------------------------------------------------------

## Stage 6 — Cohort aggregate / statistical views

**Depends on:** Stage 5b **Model tag:** 🔴 FRONTIER-REQUIRED for 6c; 🟢
LOCAL-OK for the rest.

**Files:** new `R/aggregate.R`, new `tests/testthat/test-aggregate.R`.

**Global rule for every function in this stage:** duration statistics
MUST respect `end_inferred`. Default `include_inferred = FALSE` drops
imputed final-stay durations from means/medians/quantiles and reports
`n_inferred_excluded`; `TRUE` includes them but the output carries the
flag column so callers can see what they ingested. Revision 1 omitted
this and would have shipped LOS statistics silently contaminated by the
tail- imputation rendering convenience.

### 6a. Duration summaries

`summarise_journey_durations()` (one row per stay: case_id, location,
xmin, xmax, duration_secs, end_inferred, terminal) and
`summarise_stage_durations()` (per location: n_cases,
mean/median/p25/p75 secs, n_inferred_excluded) built on it.

### 6b. Breach rates — per-stage, not whole-spell

``` r

summarise_breach_rate(data, target_hours, scope = "spell", case_ids = NULL, ...)
```

- `scope = "spell"`: first location move → last event (revision 1’s
  definition, retained as one option).
- `scope = "<location name>"`: dwell within that stage — this is how
  real targets work (ED 4-hour standard = time in the ED box; complaint
  acknowledgement SLA = time in “Acknowledgement”). Returns case_id,
  elapsed_hours, breached, end_inferred. Unknown location name → abort
  with `suggest_matches()` hint.

### 6c. Transition summary / flow diagram

As revision 1
([`summarise_transitions()`](https://jaspercain01.github.io/event-driven-visualisation/reference/summarise_transitions.md)
from per-case lag/lead pairs;
[`plot_transition_summary()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_transition_summary.md)
hand-rolled with `geom_segment`, linewidth ∝ n, mean dwell at segment
midpoints) with the frontier review REQUIRED on a synthetic cohort whose
cases visit stages in different orders and counts — the exact case where
a mechanical implementation produces a legible-looking lie. Dwell means
obey the `include_inferred` rule.

### 6d. `return_data` summary element

`return_data = TRUE` also returns
`summary = summarise_journey_durations()` for the one case →
`list(plot, boxes, events, summary)`. Additive.

### 6e. (Stretch) `plot_journey_with_summary()`

patchwork-stacked timeline + per-stage duration bars; `requireNamespace`
guard with install hint, same idiom as the RColorBrewer check.

**Tests:** hand-computed fixtures for 6a/6b (both scopes) including
inferred-end exclusion counts; exact transition n/dwell values for 6c;
`return_data` shape for 6d.

**Definition of done** - \[ \] All stats respect `end_inferred` with
tested exclusion counts - \[ \] Per-stage breach scope tested against
hand-calculated dwell - \[ \] 6c frontier-reviewed on a non-trivial
multi-path cohort

------------------------------------------------------------------------

## Stage 7 — Interactive renderer

**Depends on:** Stages 1.5, 4 **Model tag:** 🟢 LOCAL-OK

As revision 1 (`ggiraph`; `render_journey_plot_interactive()` mirroring
the static renderer via the shared `journey_layers()` helper that Stage
5’s refactor already created — do NOT re-factor again here;
`interactive = FALSE` param; `requireNamespace` guard; roxygen documents
the changed return type), with these amendments: - Box tooltips:
location, true `format_duration(duration)`, entry/exit times, and
`"(end inferred)"` when flagged — tooltips must not overclaim imputed
ends any more than labels may. - Terminal markers and swimlane points
get tooltips too (`geom_segment_interactive` /
`geom_point_interactive`). - Static output regression: vdiffr baselines
unchanged (the girafe path must not perturb the shared layer code).

**Definition of done** - \[ \] `interactive = TRUE` returns a girafe
widget; opened and tooltip text manually verified once - \[ \] All
vdiffr baselines still pass

------------------------------------------------------------------------

## Stage 8 — Generalisation polish

**Depends on:** Stage 5b **Model tag:** 🟢 LOCAL-OK

**Files:** `data-raw/support_ticket_example.R`, `R/data.R`, `R/theme.R`,
roxygen edits.

1.  **Third dataset, non-healthcare-adjacent:** support-ticket lifecycle
    (Open → Assigned → In Progress → Waiting on Customer → Resolved →
    Closed; events
    comment_added/priority_changed/reassigned/sla_warning). The
    complaint data (5b) is still NHS-adjacent; tickets prove the package
    leaves the sector entirely. Exercised end-to-end through
    `plot_patient_journey()` (with `state_label = "Status"`),
    [`plot_stage_ladder()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_stage_ladder.md),
    and `plot_journey_cohort()`.
2.  **Extract `theme_journey(base_size = 11)`** into `R/theme.R`, used
    by both renderers. Byte-identical output — vdiffr baselines are the
    gate.
3.  **Terminology pass (docs only):** roxygen text describes “location”
    generically (any exclusive state: ward, ticket status, complaint
    stage, pipeline step). **Parameter names do not change** — renaming
    would break every earlier stage for zero functional gain.

**Definition of done** - \[ \] Ticket dataset end-to-end through all
three plotting functions - \[ \] `theme_journey()` extracted, baselines
unchanged - \[ \] Docs de-hospitalised

------------------------------------------------------------------------

## Stage 9 — Test gap-closing & internal cleanup

**Depends on:** everything above **Model tag:** 🟢 LOCAL-OK (the
visual-baseline work that made revision 1’s version of this stage 🔴
moved to Stage 1.5)

1.  Direct tests for `plot_patient_journey()` orchestration not covered
    by `test-fixes.R`: auto-title format, `exclude_categories` row
    counts, `return_data` shape incl. Stage 6d’s `summary`.
2.  vdiffr snapshots for everything built after Stage 1.5 that lacks one
    (lanes, cohort both modes, ladder, tickets) — frontier-approved like
    the originals.
3.  **Replace the `attr(events, "pre_box")` handoff** with an explicit
    `list(events, pre_box)` return from `derive_point_events()` — the
    attribute survives only because dplyr happens to preserve unknown
    attributes through `mutate()`. Update `build_journey_tables()` and
    the two tests that read the attribute. Behaviour identical.
4.  `covr` + Codecov in CI; target ≥ 85% line coverage, no file below
    70%.

**Definition of done** - \[ \] Orchestrator directly tested; pre_box
handoff explicit; coverage wired

------------------------------------------------------------------------

## Stage 10 — Documentation & packaging polish

**Depends on:** everything above **Model tag:** 🟢 LOCAL-OK

1.  `README.Rmd` → generic framing first (“visualise any timestamped
    event log”), quick-start on `example_journey`, then “Not just
    healthcare” showing `complaint_example` (staircase) and
    `support_ticket_example` (band + cohort).
2.  Four vignettes:
    - `getting-started.Rmd` — clinical walkthrough
    - `adapting-your-data.Rmd` — schema/autodetect (3) + pivot
      wrapper (2) together: the single most important vignette for
      adoption
    - `linear-processes.Rmd` — complaints/tickets, band vs staircase,
      when to use which, `stage_targets`
    - `cohort-analysis.Rmd` — cohort facets (5) + aggregates/transitions
      (6)
3.  `_pkgdown.yml` + pkgdown GitHub Pages workflow; `NEWS.md` 0.1.0
    entry including the two sanctioned default-output changes (0.5
    fixes, 1f palette).

**Definition of done** - \[ \] README + four vignettes build; pkgdown
builds; NEWS.md present

------------------------------------------------------------------------

## Explicitly out of scope (deferred, not silently folded in)

- **Segmented / non-linear time axis and per-location zoom facets** —
  the review’s biggest open visualisation idea (long stays compress
  clinically dense periods into slivers). Real design work; a future
  stage of its own.
- Cohort staircase overlay (“spaghetti” of many cases on one ladder).
- Full alluvial/Sankey via `ggalluvial` (v2 of 6c if the hand-rolled
  version proves insufficient).
- Shiny dashboard wrapper; hierarchical locations (Ward \> Bay \> Bed);
  Python/JS ports; CRAN submission (plan gets the package CRAN-shaped,
  not CRAN-submitted).
- Multi-band single-panel stacking via `assign_y_bands(band_index > 0)`
  — superseded by facets (Stage 5); the helper stays but nothing drives
  it.
