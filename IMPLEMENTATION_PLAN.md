# Implementation Plan — `eventviz` (working name)

This plan turns the current single-file-sourced set of R scripts into a proper,
general-purpose event-log visualisation package. It assumes every improvement
discussed in review is implemented, plus one addition: a wide→long pivot
helper (Stage 2) for datasets that arrive as one row per case with a column
per milestone timestamp.

Package name `eventviz` is a placeholder — rename freely in Stage 0, everything
downstream is name-agnostic.

## How to read this plan

Each stage has:
- **Depends on** — stages that must land first
- **Model tag** — who should drive it (see legend)
- **Files** — created/touched
- **Steps** — specific enough to implement without further design decisions
- **Tests** — what must exist before the stage is "done"
- **Definition of done**

### Model tag legend

| Tag | Meaning |
|---|---|
| 🟢 LOCAL-OK | Spec below is complete and unambiguous. A small/quantised local model should implement directly from the steps given. |
| 🟡 FRONTIER-DESIGN-THEN-LOCAL | A design decision is required first. This plan already makes that call where possible — where it says "frontier should confirm," a quick review is enough; implementation afterward is 🟢. |
| 🔴 FRONTIER-REQUIRED | Needs ongoing judgment (visual QA, statistical/visual-encoding design, architecture with real regression risk). Should be driven or closely reviewed by a frontier model throughout, not just checked at the end. |

### Design decisions locked in (so no stage re-litigates them)

1. **Swimlanes ≠ multi-case.** Concurrent event tracks *within one case* (Stage 4)
   and *comparing across cases* (Stage 5) are different axes and use different
   mechanisms: swimlanes generalise the existing `assign_y_bands`/`band_index`
   machinery; cohort comparison uses `ggplot2::facet_wrap()`. Conflating them
   into one y-stacking system was rejected as higher-risk for no benefit.
2. **Cohort view is a new function**, `plot_journey_cohort()`, not an overload
   of `case_id` inside `plot_patient_journey()`. Keeps the existing, well-tested
   single-case path completely untouched.
3. **Interactive renderer uses `ggiraph`, not `plotly`.** `ggiraph` decorates
   existing ggplot2 geoms (`geom_rect_interactive`, `geom_point_interactive`)
   rather than translating the whole plot through a converter, so it survives
   `ggrepel`/custom themes without surprises.
4. **No new heavy dependencies for v1 of the transition diagram** — hand-rolled
   with `geom_segment`, not `ggalluvial`/`networkD3`. Flagged as a v2 stretch
   goal if the simple version isn't expressive enough once real data is tried.
5. **Backward compatibility is non-negotiable.** Every new feature is opt-in
   via a new parameter with a default that reproduces current behaviour
   exactly, or lives in a new function. Existing tests must keep passing
   unmodified through every stage.
6. License placeholder: MIT. Change in Stage 0 if the user wants otherwise.

### Stage order and dependency graph

```
Stage 0  (package scaffolding)
   |
   +--> Stage 1 (visual quick wins)   -----+
   +--> Stage 2 (pivot wrapper)             \
   +--> Stage 3 (schema/autodetect)          >-- can run in parallel, all depend only on Stage 0
                                             /
   Stage 3 --> Stage 4 (swimlanes)  <-------+
   Stage 4 --> Stage 5 (cohort facets)
   Stage 5 --> Stage 6 (aggregate/statistical views)
   Stage 1,4 --> Stage 7 (interactive renderer)
   Stage 5,8 --> Stage 8 (generalisation polish)
   all      --> Stage 9 (test hardening / visual regression)
   all      --> Stage 10 (docs / pkgdown)
```

If parallelising across multiple model instances, Stages 1, 2 and 3 are safe
to run concurrently (independent files, independent tests). Everything from
Stage 4 onward should be sequential — each stage edits `render.R` and/or
`plot_patient_journey.R`, so parallel edits there will conflict.

---

## Stage 0 — Package scaffolding

**Depends on:** nothing
**Model tag:** 🟢 LOCAL-OK

**Files:** `DESCRIPTION`, `NAMESPACE`, `.Rbuildignore`, `LICENSE`, `LICENSE.md`,
`tests/testthat.R`, `.github/workflows/R-CMD-check.yaml`, roxygen comments
added to existing `R/*.R` files.

**Steps**

1. Create `DESCRIPTION`:
   - `Package: eventviz`, `Version: 0.1.0`, `Title`, `Description`, `License: MIT + file LICENSE`
   - `Imports: dplyr, tibble, ggplot2, ggrepel, cli, lubridate, rlang, stats, utils`
   - `Suggests: testthat (>= 3.0.0), RColorBrewer, tidyr, ggiraph, patchwork, vdiffr, knitr, rmarkdown`
   - `Config/testthat/edition: 3`
2. Add roxygen2 `#'` blocks above every currently-exported-worthy function
   (`plot_patient_journey`, and `example_journey` as package data) with
   `@param`, `@return`, `@export`, one `@examples` block each. Internal helpers
   (`derive_location_boxes`, `journey_palette`, etc.) get `@keywords internal`
   or `@noRd`, not `@export`.
3. Run `roxygen2::roxygenise()` to generate `NAMESPACE` and `man/*.Rd`. Do not
   hand-write `NAMESPACE`.
4. Move `example_journey` into proper package data: create `data-raw/example_journey.R`
   containing the existing `make_example_journey()` body, call
   `usethis::use_data(example_journey, overwrite = TRUE)`, delete the old
   `R/example_data.R` `source()`-based version once `data/example_journey.rda`
   exists and is documented via a `R/data.R` file with a `#'` roxygen block.
5. Update `tests/testthat/test-*.R`: remove all `source("../../R/....R")` lines
   at the top of each test file — a real package's tests run against the
   loaded namespace, not manual sourcing. Add `tests/testthat.R`:
   ```r
   library(testthat)
   library(eventviz)
   test_check("eventviz")
   ```
6. Add `.Rbuildignore` entries for `IMPLEMENTATION_PLAN.md`, `data-raw/`,
   `.github/`.
7. Add `.github/workflows/R-CMD-check.yaml` using the standard
   `usethis::use_github_action("check-standard")` template.
8. Add `LICENSE`/`LICENSE.md` (MIT, `usethis::use_mit_license()` template).

**Tests:** none new — the point of this stage is that the *existing* test
suite passes unchanged under `devtools::test()`, and `devtools::check()` runs
clean (0 errors, 0 warnings; NOTEs acceptable at this point).

**Definition of done**
- [ ] `devtools::load_all()` succeeds
- [ ] `devtools::test()` — all pre-existing tests pass, none skipped
- [ ] `devtools::check()` — 0 errors, 0 warnings
- [ ] `example_journey` accessible as `eventviz::example_journey` without sourcing

---

## Stage 1 — Visual quick wins (no architecture change)

**Depends on:** Stage 0
**Model tag:** 🟢 LOCAL-OK for 1a–1f individually; 🔴 FRONTIER-REQUIRED for a
final combined visual QA pass (render one plot with everything switched on at
once and eyeball it for layer collisions).

**Files:** `R/render.R`, `R/transform.R`, `R/utils.R`, `R/plot_patient_journey.R`,
new `tests/testthat/test-render.R` (first-ever tests for `render.R`).

### 1a. Duration labels on boxes

- Add `format_duration(secs)` to `utils.R`: numeric seconds → compact string.
  - `< 60` → `"Ns"`; `< 3600` → `"Nm"`; `< 86400` → `"Hh Mm"` (drop the minutes
    part if zero, e.g. `"4h"` not `"4h 0m"`); `>= 86400` → `"Dd Hh"`.
- Add `show_duration = FALSE` to `plot_patient_journey()` and thread through
  `opts`.
- In `render_journey_plot()`, when `show_duration` is `TRUE`, add
  `ggplot2::geom_text()` using `boxes` data: `x = xmin + (xmax_render - xmin)/2`,
  `y = ymax + 0.03`, `label = format_duration(as.numeric(duration, units = "secs"))`,
  `size = 2.6`, `colour = "grey30"`.

### 1b. Reference-line / target-threshold layer

- New param `reference_lines = NULL` on `plot_patient_journey()`: a tibble/
  data frame with columns `offset_hours` (numeric, relative to the first
  event's timestamp) and `label` (character). Validate: if supplied and not a
  data frame with both columns, `cli::cli_abort()`.
- In `render_journey_plot()`, when non-NULL: compute
  `x = min(boxes$xmin) + offset_hours * 3600`, add
  `ggplot2::geom_vline(xintercept = x, linetype = "dashed", colour = "firebrick", linewidth = 0.5)`
  and `ggplot2::annotate("text", x = x, y = box_height * 1.1, label = label, colour = "firebrick", size = 2.8, angle = 90, hjust = 0)`.

### 1c. Visual distinction for an open/ongoing final box

- New param `end_categories = NULL` (character vector of `activity` values
  that count as a true terminal state, e.g. `c("Discharged", "Deceased")`).
- In `derive_location_boxes()` (or a thin wrapper called right after), compute
  `spell_open <- !is.null(end_categories) && !(location[n] %in% end_categories)`.
  Attach as `attr(boxes, "spell_open")`.
  Default (`end_categories = NULL`) → `spell_open` always `FALSE`, i.e. current
  behaviour is unchanged.
- In `render_journey_plot()`: if `attr(boxes, "spell_open")` is `TRUE`, draw
  the final box's right edge as a dashed `geom_segment` at its true `xmax`
  (not `xmax_render`) and add a small `"(ongoing)"` text annotation just past
  it.

### 1d. Direct box labelling

- New param `label_boxes = FALSE`.
- When `TRUE`, add `ggplot2::geom_text(data = boxes, aes(x = xmin + (xmax_render - xmin)/2, y = box_height/2, label = location), size = 2.6, colour = "grey15", check_overlap = TRUE)`.
  `check_overlap = TRUE` is a cheap built-in way to silently drop labels that
  would collide — no new dependency needed.

### 1e. High-cardinality event-type bucketing

- New param `event_type_top_n = NULL` (integer). When set and the number of
  distinct `act_type` values in `events` exceeds it, keep the top N most
  frequent as-is and recode the rest to `"Other"` before the colour/shape
  scales are built in `render_journey_plot()`. Emit `cli::cli_inform()` stating
  how many event types were collapsed and their names.

### 1f. Colourblind-safe default palette

- In `journey_palette()` (`utils.R`), add `palette_style = c("colourblind", "brewer")` param, default `"colourblind"`.
  - `"colourblind"`: use the 8-colour Okabe-Ito set (hardcode the hex values,
    no new dependency), recycled via `grDevices::colorRampPalette()` if `n > 8`.
  - `"brewer"`: existing Set2/Dark2 behaviour, kept for backward compatibility
    (some users may already depend on the exact old colours).
- Thread `palette_style` through as an optional `plot_patient_journey()` param
  defaulting to `"colourblind"` — note in the roxygen docs that this changes
  default colours versus any prior 0.0.x usage (acceptable since this is a
  0.1.0 packaging milestone).

**Tests (`tests/testthat/test-render.R`, new file):**
- `format_duration()` exact-string tests for boundary values: 0s, 59s, 60s,
  3599s, 3600s, 3660s, 86399s, 86400s, 90000s.
- Use `ggplot2::ggplot_build(p)` to assert layer *count* and *presence* rather
  than pixel comparison: e.g. `show_duration = TRUE` adds exactly one more
  `GeomText` layer than `show_duration = FALSE`; `reference_lines` adds a
  `GeomVline` layer only when supplied; `end_categories` triggers the dashed
  segment only when the last location isn't in the set; `label_boxes` adds a
  `GeomText` layer; `event_type_top_n` collapses distinct colour levels to
  `top_n + 1` (the `+1` is `"Other"`).
- `journey_palette(letters[1:3], "location", palette_style = "colourblind")`
  returns 3 unique hex colours; `palette_style = "brewer"` reproduces prior
  Set2 output exactly (regression-protects existing behaviour for anyone
  pinning it).

**Definition of done**
- [ ] All six sub-features implemented behind opt-in params, defaults preserve
      current plot output exactly (verify: `render_journey_plot()` called with
      no new params on `example_journey` produces the same `ggplot_build()`
      layer list as before this stage)
- [ ] `test-render.R` passing
- [ ] One manual `ggplot2::ggsave()` of a plot with every new feature enabled
      at once, reviewed by a frontier pass for layer collisions/illegible text

---

## Stage 2 — Wide-to-long pivot wrapper

**Depends on:** Stage 0 (needs the package structure; otherwise fully
independent of Stages 1/3)
**Model tag:** 🟢 LOCAL-OK (signature is fully specified below; a frontier
pass already made the API calls so there's nothing left to design)

**Files:** new `R/pivot_wide.R`, new `tests/testthat/test-pivot.R`, small
refactor extracting a shared helper from `validate.R` into `utils.R`.

**Prerequisite micro-refactor:** extract the timestamp-coercion block from
`validate_event_log()` (the `lubridate::as_datetime()` + NA-detection logic,
`validate.R` lines ~62–78) into a shared helper in `utils.R`:

```r
coerce_datetime_column(x, col_label) {
  # returns coerced POSIXct vector, or cli_abort()s naming which values failed
}
```

Update `validate_event_log()` to call it. This is a pure refactor — behaviour
and all existing `test-validate.R` cases must be unchanged.

**New function signature:**

```r
pivot_events_longer(
  data,
  case_col,
  time_cols,                 # character vector of wide column names to pivot
  patient_col     = NULL,
  location_cols   = NULL,    # subset of time_cols; these become act_type "location_move"
  act_type_map    = NULL,    # named character vector: names = time_cols entries, values = act_type
  activity_map    = NULL,    # named character vector: names = time_cols entries, values = display label
  drop_na         = TRUE,
  time_col_out     = "timestamp",
  act_type_col_out = "act_type",
  activity_col_out = "activity"
)
```

**Behaviour spec:**

1. Validate `case_col` and every entry of `time_cols` exist in `data`; if not,
   `cli::cli_abort()` listing missing names and the columns actually present
   (mirror the exact message style already used in `validate.R`'s missing-column
   check).
2. If `location_cols` supplied, validate it's a subset of `time_cols` — abort
   with the offending names otherwise.
3. Coerce every column in `time_cols` to `POSIXct` using the new
   `coerce_datetime_column()` helper (one call per column, reusing the same
   error message format, naming which wide column and which row failed).
4. `tidyr::pivot_longer(data, cols = dplyr::all_of(time_cols), names_to = ".milestone", values_to = time_col_out)`.
   All columns not in `time_cols` (including `case_col`, `patient_col`, and any
   other metadata columns like diagnosis/ward) are kept automatically as id
   columns — this is default `pivot_longer` behaviour, don't hand-roll it.
5. If `drop_na = TRUE`, drop rows where `.data[[time_col_out]]` is `NA`, and
   `cli::cli_inform()` a per-milestone count of how many rows were dropped
   (a milestone being NA for a case means "didn't happen for this case" —
   this is expected, not an error).
6. Compute `act_type_col_out`:
   - if `.milestone %in% location_cols` → `"location_move"`
   - else if `.milestone` has an entry in `act_type_map` → that value
   - else → the raw `.milestone` string itself (fallback, always defined,
     never NA)
7. Compute `activity_col_out`:
   - if `.milestone` has an entry in `activity_map` → that value
   - else → prettified `.milestone` (replace `_`/`.` with a space, then
     `tools::toTitleCase()`)
8. Drop the internal `.milestone` column from the output. Return a tibble
   with columns in this order: `case_col`, `patient_col` (if given),
   `time_col_out`, `act_type_col_out`, `activity_col_out`, then any remaining
   passthrough columns.
9. The returned tibble must be directly usable as the `data` argument to
   `plot_patient_journey()` with matching `time_col`/`act_type_col`/
   `activity_col`/`case_col`/`patient_col` arguments — no further reshaping.

**Tests (`tests/testthat/test-pivot.R`):**
- Fixture: a wide tibble, 3 cases, columns `case_id`, `patient_id`,
  `arrival_time`, `triage_time`, `ward_time`, `discharge_time`, plus one
  non-time metadata column (`diagnosis`).
- Basic pivot with `location_cols = c("arrival_time","ward_time","discharge_time")`
  and `act_type_map = c(triage_time = "triage")`: assert row count
  (3 cases × 4 milestones, minus any NA), assert `act_type` values are
  `"location_move"` for the three location columns and `"triage"` for
  `triage_time`.
- Missing `case_col` → `expect_error(..., regexp = "case_col")` style, mirroring
  `validate.R`'s message shape.
- `location_cols` not a subset of `time_cols` → aborts naming the offending
  column.
- A row with `NA` in one milestone column for one case → dropped, and
  `expect_message(..., regexp = "dropped")` (or whatever wording is used —
  keep it consistent).
- End-to-end integration: pivot the fixture, then call
  `plot_patient_journey(pivoted, case_id = "<id>", location_categories = "location_move", time_col = "timestamp", act_type_col = "act_type", activity_col = "activity", case_col = "case_id", patient_col = "patient_id")`
  and `expect_s3_class(result, "ggplot")` — proves the two functions actually
  compose, not just that each works in isolation.
- `metadata` passthrough column (`diagnosis`) still present and correct in
  output.

**Definition of done**
- [ ] `pivot_events_longer()` implemented exactly to spec above
- [ ] `coerce_datetime_column()` extracted, `test-validate.R` still passes
      unchanged
- [ ] `test-pivot.R` passing, including the end-to-end integration test
- [ ] Add `tidyr` to `DESCRIPTION` `Imports`

---

## Stage 3 — Schema object + column/category auto-detection

**Depends on:** Stage 0
**Model tag:** 🟡 FRONTIER-DESIGN-THEN-LOCAL — the precedence rule and
candidate-name lists are specified below, so implementation is 🟢 once read
carefully; a frontier pass should just confirm the precedence order doesn't
silently break Stage 0/1/2 behaviour before merging.

**Files:** new `R/schema.R`, new `tests/testthat/test-schema.R`, edit
`R/plot_patient_journey.R`.

**`event_log_schema()` constructor:**

```r
event_log_schema(
  time_col = NULL, act_type_col = NULL, activity_col = NULL,
  case_col = NULL, patient_col = NULL,
  location_categories = NULL
) 
# returns list(...) with class "event_log_schema"
```

Add a `print.event_log_schema()` S3 method printing each field on its own line.

**`autodetect_schema(data, location_categories = NULL)`:**

For each role, try in order:
1. Exact case-insensitive match of a column name against the candidate list
   below.
2. If no exact match, use `adist()` (already used for `suggest_matches()` in
   `utils.R` — reuse that function, don't reimplement) between column names
   and the candidate list, accept if distance ≤ 2.
3. If still nothing, that field stays `NULL` in the returned schema and its
   name is collected into a `missing` vector.

Candidate lists (case-insensitive):
- `time_col`: `c("timestamp","time","ts","datetime","date_time","event_time","event_time_stamp")`
- `act_type_col`: `c("act_type","event_type","category","type","event_category")`
- `activity_col`: `c("activity","label","description","event","event_name","name")`
- `case_col`: `c("case_id","caseid","case","spell_id","episode_id","id","encounter_id")`
- `patient_col`: `c("patient_id","patient","k_number","mrn","person_id")`

If any of `time_col`/`act_type_col`/`activity_col`/`case_col` remain
undetected, `cli::cli_abort()` naming which roles couldn't be inferred, the
column names that *were* tried, and instructing the user to pass an explicit
`event_log_schema()`. (`patient_col` is optional — don't abort if only that
one is missing.)

On success, `cli::cli_inform()` one line per detected field: e.g.
`"Detected time column: 'ts' (fuzzy match)"` vs `"(exact match)"` — this
transparency matters more than saving a line of output.

**Wiring into `plot_patient_journey()`:**

Add `schema = NULL` param. Precedence, highest wins:
1. Explicit individual arguments (`time_col = "foo"`, etc.) — if a caller
   passes both `schema` and an individual column argument, the individual
   argument wins for that field only (not all-or-nothing).
2. Fields present in `schema` (if `schema` supplied and a given field isn't
   overridden by (1)).
3. If neither (1) nor (2) supplies a required field, and `schema` was not
   supplied at all, fall back to the current hardcoded defaults
   (`time_col = "timestamp"`, etc.) — this exact fallback is what makes Stage
   3 100% backward compatible with every existing call site and test.
4. Only call `autodetect_schema()` if the caller explicitly asks for it via a
   new `schema = "auto"` sentinel value (a string, not an `event_log_schema`
   object) — auto-detection must never fire silently on a normal call; it's
   opt-in.

**Tests (`tests/testthat/test-schema.R`):**
- `event_log_schema()` construction + print method.
- `autodetect_schema()` on a renamed copy of `example_journey`
  (`timestamp`→`ts`, `act_type`→`category`, `activity`→`label`,
  `caseID`→`case_id`, `K_Number`→`mrn`) recovers the correct mapping via fuzzy
  match, with `cli::cli_inform()` messages captured via `expect_message()`.
- Undetectable schema (all columns renamed to nonsense like `col1`, `col2`)
  aborts naming the missing roles.
- `plot_patient_journey(data, schema = event_log_schema(time_col = "ts"), act_type_col = "category")`
  — explicit `act_type_col` wins over anything schema would have set for that
  field; `time_col` comes from schema.
- Existing `test-validate.R`/`test-transform.R` calls (no `schema` argument at
  all) still pass unchanged — this is the regression check that matters most
  for this stage.

**Definition of done**
- [ ] Precedence rule implemented exactly as specified (explicit arg > schema
      field > hardcoded default; autodetect only on explicit `"auto"`)
- [ ] All prior tests (Stages 0–2) still pass unmodified
- [ ] `test-schema.R` passing

---

## Stage 4 — Swimlanes (concurrent event tracks within one case)

**Depends on:** Stage 3 (uses schema for the new `lane_col` field cleanly, though not strictly required)
**Model tag:** 🔴 FRONTIER-REQUIRED for the core y-band generalisation and the
conditional axis-visibility logic; 🟢 LOCAL-OK for wiring new params through
`plot_patient_journey.R` once `transform.R`/`render.R` changes land.

**Why this is the highest-risk stage:** it changes the meaning of the y-axis
(currently always blank/meaningless) conditionally, and it must not alter
`render_journey_plot()`'s output at all when lanes aren't used — the existing
Stage 1 layer-count tests must keep passing.

**Files:** `R/transform.R`, `R/render.R`, `R/plot_patient_journey.R`, new
`tests/testthat/test-transform-lanes.R`.

**Design:**
- Location boxes remain the "spine": always occupy `y ∈ [0, box_height]`,
  unaffected by lanes.
- New param `lane_col = NULL` on `plot_patient_journey()` — the name of a
  column in `data` whose distinct values define separate horizontal tracks
  for **point events only** (never for location boxes).
- When `lane_col` is `NULL` (default): identical behaviour to today — all
  events at `y = box_height / 2`. This must be verified with a regression
  test, not assumed.
- When `lane_col` is supplied:
  - Determine lane order: if the column is a factor, use its level order;
    otherwise use first-appearance order in the sorted spell (mirrors the
    existing `loc_levels <- unique(boxes$location)` idiom already in
    `render.R` — copy that pattern, don't invent a new one).
  - Each lane gets a vertical slot **above** the location spine:
    lane *i* (1-indexed) occupies
    `y ∈ [box_height + i * lane_gap + (i-1) * lane_height, box_height + i * lane_gap + i * lane_height]`,
    with new params `lane_height` (default = `box_height`) and `lane_gap`
    (default = `0.05`).
  - `derive_point_events()` gains a `lane_col = NULL` param; when set, after
    computing `box_id` as today, also compute each event's lane index from
    the ordering above and set `y` accordingly (instead of the constant
    `box_height / 2`).
- **Axis visibility:** in `render_journey_plot()`, only make `axis.text.y`
  visible (showing lane names) when lanes are active; keep it blank in the
  default path. Implementation: pass a `lanes_active` boolean through `opts`
  computed in `plot_patient_journey()` as `!is.null(lane_col)`, and branch the
  existing `ggplot2::theme()` block on it — do not restructure the whole
  theme block, just make the two `axis.text.y`/`axis.ticks.y` lines
  conditional.
- Document as a known limitation (in roxygen `@details`, not code): many
  distinct `lane_col` values produce a very tall plot; no automatic capping is
  implemented.

**Tests (`tests/testthat/test-transform-lanes.R`):**
- Synthetic log with a `domain` column (`"obs"`, `"meds"`, `"labs"`) and 2
  events per domain. Assert 3 distinct `y` values in the output, each
  spanning the expected `[lane_gap/height]` arithmetic given known
  `box_height`/`lane_height`/`lane_gap` inputs.
- `lane_col = NULL` produces byte-identical `y` values to pre-Stage-4 behaviour
  (regression test against a fixture captured from the Stage-1 test suite).
- `render_journey_plot()`: `axis.text.y` is a blank element when no lanes are
  used, and a non-blank element (default/inherited) when lanes are active —
  assert via inspecting the built theme object, e.g.
  `inherits(p$theme$axis.text.y, "element_blank")`.

**Definition of done**
- [ ] `lane_col = NULL` path is byte-identical to pre-Stage-4 output (explicit
      regression test, not just "looks the same")
  - [ ] Lane y-position arithmetic verified with a hand-computed fixture
- [ ] Axis label visibility toggles correctly and only when lanes are active

---

## Stage 5 — Cohort view via faceting

**Depends on:** Stage 4 (shares the per-case derive/loop pattern; not
strictly blocked by it, but should land after so lanes + facets can be tested
together)
**Model tag:** 🟡 FRONTIER-DESIGN-THEN-LOCAL — the facet/scale/align-start
decisions are made below; implementation from that spec is 🟢.

**Files:** new `R/cohort.R`, new `tests/testthat/test-cohort.R`.

**New function (not an overload of `plot_patient_journey`):**

```r
plot_journey_cohort(
  data,
  case_ids            = NULL,   # NULL = every distinct case in data
  location_categories  = c("location_move", "ed_location_move"),
  time_col = "timestamp", act_type_col = "act_type", activity_col = "activity",
  case_col = "caseID", patient_col = "K_Number",
  align_start          = FALSE, # TRUE = rebase each case to "hours since first location move"
  ncol                 = NULL,  # passed to facet_wrap
  ...                          # forwarded to derive_location_boxes/derive_point_events
)
```

**Behaviour:**
1. Resolve `case_ids`: if `NULL`, `unique(data[[case_col]])`.
2. For each case id, run `validate_event_log()` + `build_journey_tables()`
   exactly as `plot_patient_journey()` does today (call the same internal
   functions — do not duplicate logic), tag the resulting `boxes`/`events`
   tibbles with a `case_id` column, and `dplyr::bind_rows()` everything.
3. If `align_start = TRUE`: for each case, subtract that case's own
   `min(boxes$xmin)` from every `xmin`/`xmax` in its boxes and every `x` in
   its events, then express the result as a numeric "hours since start" axis
   instead of `POSIXct` (needed since `scale_x_datetime` can't represent a
   relative duration meaningfully) — use `scale_x_continuous` with a
   `"+Nh"`-style label formatter in this mode instead of
   `choose_date_breaks()`/`choose_date_labels()`.
4. If `align_start = FALSE` (default): keep real timestamps, use
   `ggplot2::facet_wrap(~ case_id, scales = "free_x", ncol = ncol)` — `free_x`
   is required since unrelated cases have unrelated absolute start times;
   don't default to a shared x-axis.
5. Colour scales: rely on the fact that `facet_wrap()` on one combined data
   frame naturally produces one shared discrete scale across all panels — do
   **not** build a separate colour scale per facet. Confirm this explicitly in
   a test rather than assuming it.

**Tests (`tests/testthat/test-cohort.R`):**
- 3-case synthetic fixture (reuse the `standard_log()`-style pattern from
  `test-transform.R`, tripled with different `caseID`s and different start
  times/durations).
- `plot_journey_cohort(data)` with no `case_ids` → 3 facet panels.
- `plot_journey_cohort(data, case_ids = c("A","B"))` → 2 panels only.
- `align_start = TRUE`: assert every case's earliest box `xmin` is `0` after
  transformation.
- Colour consistency: same `location` value maps to the same hex colour
  across all 3 cases — extract via `ggplot2::ggplot_build(p)$data` and compare
  fill values for matching `location` labels across facets.

**Definition of done**
- [ ] `plot_journey_cohort()` implemented, reusing (not duplicating)
      `validate_event_log()`/`build_journey_tables()`
- [ ] Both `align_start` modes tested
- [ ] Colour-consistency-across-facets explicitly tested, not assumed

---

## Stage 6 — Cohort aggregate / statistical views

**Depends on:** Stage 5 (reuses its per-case loop)
**Model tag:** 🔴 FRONTIER-REQUIRED for 6c (visual encoding of the transition
diagram — get this wrong and it's actively misleading); 🟢 LOCAL-OK for
6a/6b/6d/6e once the shapes below are followed exactly.

**Files:** new `R/aggregate.R`, new `tests/testthat/test-aggregate.R`.

### 6a. Per-case and cross-case duration summaries

```r
summarise_journey_durations(data, case_ids = NULL, ...) 
# -> tibble: case_id, location, xmin, xmax, duration_secs   (one row per stay)

summarise_stage_durations(data, case_ids = NULL, ...)
# -> tibble: location, n_cases, mean_secs, median_secs, p25_secs, p75_secs
```

`summarise_stage_durations()` is built by calling
`summarise_journey_durations()` then `dplyr::group_by(location) |> dplyr::summarise(...)`.

### 6b. Breach-rate summary

```r
summarise_breach_rate(data, case_ids = NULL, target_hours, ...)
# -> tibble: case_id, elapsed_hours, breached (logical)
# elapsed_hours = (last event timestamp - first location-move timestamp) in hours,
# for that case. Document this definition explicitly in roxygen @details —
# it is a deliberate choice (admission-to-last-known-event), not "total row span".
```

### 6c. Transition summary / flow diagram

```r
summarise_transitions(data, case_ids = NULL, ...)
# -> tibble: from_location, to_location, n, mean_dwell_secs (dwell time in from_location)

plot_transition_summary(data, case_ids = NULL, ...)
# -> ggplot: x = sequence step (1, 2, 3, ...), y = location (factor, ordered by
#    first appearance across the cohort), geom_segment connecting step i to
#    step i+1 with linewidth scaled to `n` (num cases making that transition),
#    geom_label at each node showing location name + n cases currently there,
#    geom_text at each segment midpoint showing mean dwell time.
```
`summarise_transitions()`: for each case, take its `boxes` (from Stage 5's
per-case loop), compute `dplyr::lag(location)`/`dplyr::lead(location)` pairs
within the case, then aggregate counts and mean dwell time across all cases
with `dplyr::count()`/`dplyr::summarise()`. **Frontier review point:** verify
the resulting diagram is legible and not misleading on a real (not
single-path) cohort where cases visit locations in different orders — this
is exactly the failure mode a mechanical implementation is most likely to
produce without noticing.

### 6d. Summary table in `plot_patient_journey()`'s `return_data`

- Extend the existing `return_data = TRUE` path in `plot_patient_journey()`
  (`R/plot_patient_journey.R`) to also include
  `summary = summarise_journey_durations(data filtered to this one case_id)`,
  so `return_data = TRUE` yields `list(plot, boxes, events, summary)`. Purely
  additive — existing consumers pulling `$plot`/`$boxes`/`$events` are
  unaffected.

### 6e. (Optional/stretch) Combined stats + timeline panel

- Add `Suggests: patchwork`. New function
  `plot_journey_with_summary(...)` (forwards args to `plot_patient_journey()`)
  that stacks the timeline plot above a small `ggplot2::geom_col()` chart of
  per-location duration, joined with `patchwork::plot_layout(ncol = 1, heights = c(3, 1))`.
  Guard with `requireNamespace("patchwork", quietly = TRUE)`, `cli::cli_abort()`
  with an install hint if missing — same idiom as the existing
  `RColorBrewer` optional-dependency check in `utils.R`.

**Tests (`tests/testthat/test-aggregate.R`):**
- 3-case fixture with hand-computed expected means/medians for
  `summarise_stage_durations()`.
- `summarise_breach_rate()` with a known `target_hours` — assert the boolean
  breach flag matches hand-calculated elapsed times.
- `summarise_transitions()` on a fixture with a known, small set of
  transitions — assert exact `n`/`mean_dwell_secs` values.
- `return_data = TRUE` includes a `summary` element with the right columns.

**Definition of done**
- [ ] 6a/6b/6d implemented and unit-tested against hand-computed fixtures
- [ ] 6c implemented, and reviewed (not just tested) on a synthetic
      non-trivial cohort (cases visiting locations in different orders/counts)
- [ ] 6e implemented behind the optional-dependency guard, if attempted

---

## Stage 7 — Interactive renderer

**Depends on:** Stage 1 (opts shape must be stable), Stage 4 (lanes should be
representable in the interactive path too)
**Model tag:** 🟢 LOCAL-OK (library choice and pattern already fixed above)

**Files:** new `R/render_interactive.R`, edit `R/plot_patient_journey.R`,
new `tests/testthat/test-render-interactive.R`.

**Steps:**
1. Add `ggiraph` to `Suggests`.
2. `render_journey_plot_interactive(boxes, events, opts)` — a near-mirror of
   `render_journey_plot()`:
   - `ggplot2::geom_rect()` → `ggiraph::geom_rect_interactive()`, adding
     `tooltip = paste0(location, "<br>", format_duration(as.numeric(duration, units = "secs")))`,
     `data_id = box_id`.
   - `ggplot2::geom_point()` → `ggiraph::geom_point_interactive()`, adding
     `tooltip = activity`, `data_id = dplyr::row_number()`.
   - Everything else (scales, theme) identical — factor the shared
     scale/theme-building code out of `render_journey_plot()` into a small
     internal helper both renderers call, rather than copy-pasting the whole
     function. (This is a light refactor of Stage-1-era `render.R`; keep the
     public `render_journey_plot()` behaviour byte-identical.)
   - Wrap final plot: `ggiraph::girafe(ggobj = p, options = list(ggiraph::opts_hover(css = "fill:#333;"), ggiraph::opts_sizing(rescale = TRUE)))`.
3. Add `interactive = FALSE` param to `plot_patient_journey()`. When `TRUE`:
   - `if (!requireNamespace("ggiraph", quietly = TRUE)) cli::cli_abort(c("The {.pkg ggiraph} package is required for interactive = TRUE.", "i" = "Install it with {.code install.packages('ggiraph')}"))` — mirror the existing `RColorBrewer` guard pattern in `utils.R`.
   - Dispatch to `render_journey_plot_interactive()` instead of
     `render_journey_plot()`. Document clearly in roxygen that the return
     type changes from `ggplot` to a `girafe`/htmlwidget object when
     `interactive = TRUE`.

**Tests:**
- `testthat::skip_if_not_installed("ggiraph")` guard at the top of
  `test-render-interactive.R`.
- `plot_patient_journey(example_journey, case_id = "SP-001", interactive = TRUE)`
  returns a non-NULL object of class including `"girafe"`.
- Missing-package path: temporarily can't easily unit-test `requireNamespace`
  returning FALSE without mocking — acceptable to skip this specific branch
  from automated tests and note it as manually verified.

**Definition of done**
- [ ] Shared scale/theme code factored out without changing
      `render_journey_plot()`'s output (regression-tested)
- [ ] `interactive = TRUE` produces a working `girafe` widget on the example
      dataset (manually opened once and inspected — tooltips must actually
      show sensible text, not just "no error thrown")

---

## Stage 8 — Generalisation polish

**Depends on:** Stage 5 (cohort view is worth demonstrating on the new
dataset too)
**Model tag:** 🟢 LOCAL-OK, except picking the non-clinical example domain
(🟡 FRONTIER-DESIGN — recommendation given below, confirm and proceed)

**Files:** `data-raw/support_ticket_example.R`, `R/data.R` (add
documentation block), `R/theme.R` (new, extracted from `render.R`), roxygen
edits across `R/*.R` for terminology.

**Steps:**
1. **Second example dataset.** Recommendation: a support-ticket lifecycle
   log — `case_id` = ticket id, locations =
   `"Open" → "Assigned" → "In Progress" → "Waiting on Customer" → "Resolved" → "Closed"`,
   events = `"comment_added"`, `"priority_changed"`, `"reassigned"`,
   `"sla_warning"`. Build it the same way `example_journey` was built
   (`tibble::tribble()`), save via `usethis::use_data(support_ticket_example)`,
   document in `R/data.R`.
2. **Extract `theme_journey()`.** Move the `ggplot2::theme(...)` block
   currently inline in `render_journey_plot()` into an exported function
   `theme_journey(base_size = 11)` in a new `R/theme.R`. `render_journey_plot()`
   and `render_journey_plot_interactive()` both call
   `theme_journey(base_size = 11)` instead of inlining it. Purely a
   refactor — output must be byte-identical (test with `ggplot_build()`
   comparison before/after).
3. **Terminology pass (documentation only, not code):** in roxygen `@param`
   text for `location_categories`, `location_palette`, etc., describe the
   concept generically ("the categorical attribute defining boxes on the
   timeline — e.g. physical location, but equally an order status, ticket
   state, or pipeline stage") rather than hospital-specific language.
   **Do not rename the parameters themselves** — that would break every
   earlier stage's tests and the public API for no functional gain.

**Tests:**
- `plot_patient_journey(support_ticket_example, case_id = "<some id>", location_categories = "location_move", ...)` runs end-to-end without error and returns a `ggplot` — this is the test that actually proves genericity, not just a claim in the README.
- `plot_journey_cohort(support_ticket_example)` likewise runs end-to-end.
- `theme_journey()` extraction regression test: `ggplot_build()` output
  identical before/after the refactor on a fixed example.

**Definition of done**
- [ ] Second, non-clinical dataset ships and is exercised by an end-to-end
      test through both `plot_patient_journey()` and `plot_journey_cohort()`
- [ ] `theme_journey()` exported and reused by both renderers
- [ ] Roxygen docs describe concepts generically

---

## Stage 9 — Test hardening / visual regression

**Depends on:** everything above (this is the closing-the-gaps pass)
**Model tag:** 🔴 FRONTIER-REQUIRED to generate and *look at* the initial
`vdiffr` baseline images before committing them (a baseline nobody has looked
at is worthless); 🟢 LOCAL-OK to write the surrounding integration tests once
the visual cases are chosen.

**Files:** new `tests/testthat/test-render-snapshots.R`,
new `tests/testthat/test-plot-patient-journey.R` (closes the pre-existing gap
— this top-level orchestrator has never had direct tests).

**Steps:**
1. Add `vdiffr` to `Suggests`. Create `vdiffr::expect_doppelganger()` snapshots
   for these specific cases on `example_journey`, each named descriptively:
   - default plot (no optional params)
   - `show_labels = TRUE`
   - `show_duration = TRUE`
   - `label_boxes = TRUE`
   - `lane_col` set (from Stage 4)
   - `reference_lines` set (from Stage 1b)
   A frontier pass must render each of these once locally
   (`vdiffr::manage_cases()` or equivalent), visually confirm they look
   correct, and only then commit the SVG baselines.
2. Add direct tests for `plot_patient_journey()` itself (never tested at this
   level before): `expect_s3_class(result, "ggplot")`; title
   auto-generation format when `title = NULL`; `return_data = TRUE` shape
   (`list` with `plot`/`boxes`/`events`/`summary` per Stage 6d);
   `exclude_categories` actually drops the right rows (row-count assertion
   before/after).
3. Wire `covr`/Codecov into the CI workflow from Stage 0 (optional but cheap).

**Definition of done**
- [ ] vdiffr baselines exist for all six cases above, each visually confirmed
      once by a frontier pass
- [ ] `plot_patient_journey()` has direct tests for its own orchestration
      logic (title generation, `exclude_categories`, `return_data` shape) —
      previously only its dependencies (`validate.R`/`transform.R`) were
      tested
- [ ] Full suite (`devtools::test()`) green, `devtools::check()` clean

---

## Stage 10 — Documentation & packaging polish

**Depends on:** everything above
**Model tag:** 🟢 LOCAL-OK — outline given below, purely mechanical to fill in

**Files:** `README.Rmd` → `README.md`, `vignettes/*.Rmd`, `_pkgdown.yml`,
`NEWS.md`, `.github/workflows/pkgdown.yaml`.

**Steps:**
1. `README.Rmd`: open with the generic framing ("visualise any timestamped
   event log as a readable timeline"), a quick-start using
   `example_journey`, then a section titled "Not just healthcare" rendering
   `support_ticket_example`. Knit via `devtools::build_readme()`.
2. Three vignettes:
   - `vignettes/getting-started.Rmd` — the clinical walkthrough (today's
     `example_data.R` header comment is already most of this content).
   - `vignettes/adapting-your-data.Rmd` — covers `event_log_schema()`/
     `autodetect_schema()` (Stage 3) and `pivot_events_longer()` (Stage 2)
     together, since both exist to solve "my data doesn't look like the
     example" — this is the single most important vignette for adoption.
   - `vignettes/cohort-analysis.Rmd` — `plot_journey_cohort()` (Stage 5) and
     the `summarise_*()`/`plot_transition_summary()` functions (Stage 6).
3. `_pkgdown.yml` + `.github/workflows/pkgdown.yaml`
   (`usethis::use_pkgdown_github_pages()` template).
4. `NEWS.md`: one `## eventviz 0.1.0` entry summarising all stages as bullet
   points — this doubles as a human-readable changelog of this entire plan.

**Definition of done**
- [ ] README renders cleanly and shows both example datasets
- [ ] All three vignettes build without error (`devtools::build_vignettes()`)
- [ ] pkgdown site builds locally (`pkgdown::build_site()`) without error
- [ ] `NEWS.md` present

---

## Explicitly out of scope for this plan

Raised during review as ideas but deliberately deferred — add as new stages
later if wanted, not silently folded in here:
- Full alluvial/Sankey diagrams via `ggalluvial`/`networkD3` (v2 of Stage 6c
  if the hand-rolled version proves insufficient)
- Shiny app / interactive dashboard wrapper
- Hierarchical/nested location support (e.g. Ward > Bay > Bed)
- A Python or JS port / htmlwidget beyond the `ggiraph` interactive mode
- CRAN submission (Stage 0–10 gets the package to CRAN-shaped, not
  CRAN-submitted)
