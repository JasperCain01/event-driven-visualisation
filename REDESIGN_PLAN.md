# Redesign Plan — eventviz 0.2.0: generic core (`plot_case_timeline` / `state_events`)

**Status: approved by the maintainer, not yet implemented.**
Written 2026-07-11 by the review session that fixed the four post-implementation
defects (see NEWS 0.1.0 "Post-implementation review fixes"). Intended executor:
a Sonnet-class session working alone from this document. Intended final
reviewer: an Opus/Fable-class session using §10.

Base the implementation branch on `claude/review-implementation-plan-urlsg7`
(commit `393f6ee` or later — it carries the fixed, dispatch-only
`update-snapshots` workflow this plan's final step depends on). Merge target:
`main`. `dev_stages` is historical; do not target it.

---

## 1. Motivation — what this redesign is FOR (read this before judging anything)

eventviz began as a single R script for visualising one hospital patient's
event log. Stages 0–10 of IMPLEMENTATION_PLAN.md turned it into a proper
package whose *architecture* is fully generic — every function takes
column-name mappings, the box-derivation pipeline doesn't care what a "state"
is, and two non-clinical example datasets ship in the box. But the package's
*surface* is still moulded around the original dataset:

- The defaults are that dataset's column names and values
  (`case_col = "caseID"`, `patient_col = "K_Number"`,
  `location_categories = c("location_move", "ed_location_move")`).
- The main entry point is called `plot_patient_journey()` and its own docs
  have to open with "despite the name…".
- Rendered output and messages say "Patient K12345 — Spell SP-001",
  "(pre-admission)", "Expected one patient per spell", legend title
  "Location".

The measured consequence (reproduced during review): a user pointing the
package at a minimal generic event log (`case_id`/`timestamp`/`act_type`/
`activity`) hits **three consecutive errors** before their first plot —
missing `caseID`, missing `K_Number`, then no rows matching
`location_categories` — and the designed escape hatch (`schema = "auto"`)
only fixes the first two, because autodetection matches column *names*,
never which `act_type` *values* open a state.

### The objective

> **A first-time user with any timestamped event log gets a correct plot in
> one call, with exactly one explicit declaration — which event types open a
> state (`state_events`) — and never encounters healthcare vocabulary unless
> they are looking at the clinical example dataset.**

Acceptance snippet — this must work, verbatim, on the finished branch:

```r
library(eventviz)

orders <- data.frame(
  case_id   = c("A-1", "A-1", "A-1", "A-2", "A-2"),
  timestamp = as.POSIXct("2026-01-01") + c(0, 3600, 7200, 0, 5400),
  act_type  = c("status", "note", "status", "status", "status"),
  activity  = c("Raised", "Chased supplier", "Approved", "Raised", "Approved")
)

plot_case_timeline(orders, state_events = "status", case_id = "A-1")

# and, because the bundled example now matches the defaults and is
# single-case, the README quick start is ONE call with ONE declaration:
plot_case_timeline(example_journey,
                   state_events = c("location_move", "ed_location_move"))
```

### Maintainer decisions that license the approach (2026-07-11)

1. **The package has no users yet — breaking changes are free.** No
   deprecation shims, no compatibility aliases. Clean break, version 0.2.0.
2. **Explicit beats guessed:** the user *should* have to declare which event
   types are long-running states vs. point-in-time events. So the
   state-opening categories become a **required argument with no default**,
   and the "how do I discover the right value?" problem is solved by the
   error message listing what's in the data — not by heuristics.
3. **The secondary-identifier (`K_Number`/"patient") concept is deleted
   entirely.** The only identifier that matters is the unique id of the
   subject of the event series — and even that is only needed *"assuming
   there is more than one subject in the dataset"*, which licenses the
   single-subject ergonomics in §4.3.
4. Names approved by the maintainer: **`plot_case_timeline`** and
   **`state_events`**. All other renames in this plan follow from those two
   by the consistency rule below.

### The consistency rule (the reviewer should hold the work to this)

**One concept, one name, everywhere.** The concept formerly called
"location" / "location move" / "stage" (in the ladder) / "status" (in
prose) is now the **state**: an exclusive condition the case occupies for an
interval, opened by an event whose `act_type` is listed in `state_events`
and closed by the next such event. Every exported name, argument, legend,
message, and doc must use *state* vocabulary for it. "Case" is the subject
of one event series. Point events (everything not in `state_events`) stay
"events".

**Semantics note (must be documented prominently in `plot_case_timeline()`'s
roxygen `@details`):** states are *exclusive and contiguous* — a case is in
exactly one state at a time, and each state ends when the next begins (or is
inferred/terminal at the end of the series). Overlapping long-running
processes are not representable as states; concurrent point-event tracks are
what swimlanes (`lane_col`) are for. The maintainer's original working name
for the argument was `continuous_events`; `state_events` was chosen
precisely because it signals this exclusivity.

---

## 2. Renames — the complete table

Anything not listed here keeps its name. NO other exported name may change.

| Old | New | Notes |
|---|---|---|
| `plot_patient_journey()` | `plot_case_timeline()` | file `R/plot_patient_journey.R` → `R/plot_case_timeline.R` |
| `plot_journey_cohort()` | `plot_cohort_timeline()` | file `R/cohort.R` keeps its name |
| `plot_stage_ladder()` | *(unchanged)* | already generic |
| `summarise_journey_durations()` | `summarise_case_durations()` | |
| `summarise_stage_durations()` | `summarise_state_durations()` | output column `location` → `state` (see §4.6) |
| `summarise_breach_rate()` | *(unchanged)* | |
| `summarise_transitions()` | *(unchanged)* | output columns `from_location`/`to_location` → `from_state`/`to_state` |
| `plot_transition_summary()` | *(unchanged)* | |
| `plot_journey_with_summary()` | `plot_case_timeline_with_summary()` | |
| `theme_journey()` | `theme_timeline()` | |
| argument `location_categories` | `state_events` | every function; **required, no default** (§4.2) |
| argument `stage_categories` (ladder) | `state_events` | one concept, one name |
| argument `patient_col` | **deleted** | every function |
| argument `location_palette` | `state_palette` | every plotting function |
| argument default `state_label = "Location"` | `state_label = "State"` | |
| argument default `case_col = "caseID"` | `case_col = "case_id"` | every function |
| pivot argument `location_cols` | `state_cols` | `pivot_events_longer()` |
| pivot emitted `act_type` value `"location_move"` | `"state_change"` | §4.7 |
| schema field `location_categories` | `state_events` | §4.5 |
| schema field/role `patient_col` | **deleted** | §4.5 |
| internal `derive_location_boxes()` | `derive_state_boxes()` | internal, but rename for greppability |
| internal boxes column `location` | `state` | flows through `return_data`, summaries, ladder (which already renamed it), tooltips |
| dataset column `example_journey$caseID` | `case_id` | §5 |
| dataset column `example_journey$K_Number` | **dropped from the dataset** | §5 |
| datasets `example_journey`, `complaint_example`, `support_ticket_example` | *(names unchanged)* | "journey" as a dataset flavour is fine; the API is what must be neutral |
| vdiffr snapshot names (`journey-default`, …) | *(unchanged)* | churn without benefit |

## 3. Vocabulary — user-visible strings

| Where | Old | New |
|---|---|---|
| auto title (timeline + ladder) | `"Patient {p} — Spell {id}"` / `"Case {id}"` | always `"Case {id}"`; when `case_col = NULL` (§4.3) no auto title (`title = NULL`) |
| synthetic leading box label | `"(pre-admission)"` | `"(before first state)"` |
| its cli message | "…A synthetic "(pre-admission)" box will be prepended." | "…events before the first state event are shown in a synthetic "(before first state)" box." |
| validation warning | "Case X maps to N distinct values of {patient}… Expected one patient per spell." | **deleted** (concept gone) |
| fill legend | `name = state_label` (default "Location") | default `"State"` |
| point legend | `"Event type"` | *(unchanged — already neutral)* |
| DESCRIPTION `Description:` | "Originally built for patient journeys…" sentence order | lead fully generic; clinical origin may be mentioned last in one clause |

**Grep gate** (verification, §7): after the work,
`grep -rniE "patient|spell|k_number|admission|clinical|ward|hospital" R/ README.Rmd vignettes/ NEWS.md`
may match ONLY: (a) `R/data.R` + `data-raw/` + anything describing the
*content* of `example_journey` (it is clinical data — that's allowed and
good), (b) `vignettes/getting-started.Rmd`'s clinical walkthrough prose,
(c) NEWS history entries, (d) IMPLEMENTATION_PLAN.md / REDESIGN_PLAN.md.
Any other hit is a defect.

---

## 4. Code changes, file by file

### 4.1 `R/plot_case_timeline.R` (renamed from `R/plot_patient_journey.R`)

New signature — copy exactly:

```r
plot_case_timeline <- function(
    data,
    state_events,                 # REQUIRED: act_type values that open a state
    case_id      = NULL,          # NULL = resolve per §4.3
    time_col     = "timestamp",
    act_type_col = "act_type",
    activity_col = "activity",
    case_col     = "case_id",     # may be NULL: single unnamed series (§4.3)
    schema       = NULL,
    tz           = "UTC",
    terminal_activities = NULL,
    exclude_categories  = NULL,
    show_labels   = FALSE,
    label_max     = 30L,
    show_duration = FALSE,
    label_boxes   = FALSE,
    reference_lines  = NULL,
    event_type_top_n = NULL,
    lane_col    = NULL,
    lane_height = NULL,
    lane_gap    = NULL,
    state_label   = "State",
    state_palette = NULL,
    event_palette = NULL,
    palette_style = c("okabe", "brewer"),
    box_height    = 0.25,
    box_gap_prop  = 0.003,
    title         = NULL,
    tail_strategy = "last_event",
    interactive   = FALSE,
    return_data   = FALSE
) { ... }
```

Body: same orchestration as today with (a) `cols` list loses `patient`,
(b) schema resolution keeps the `missing()`-based precedence pattern
(explicit arg > schema field > default) now covering `state_events` too,
(c) title logic per §3, (d) the `return_data` list unchanged in shape except
`boxes$location` → `boxes$state` and `summary$location` → `summary$state`.

### 4.2 Required `state_events` and the discovery error (`R/validate.R`)

`state_events` has **no default anywhere**. Two distinct failure modes, both
handled in `validate_event_log()` (called by every entry point, so implement
once):

1. **Argument missing.** Entry points pass `state_events` through; use
   `rlang::check_required(state_events)`-style handling *at the entry point*
   (a plain `missing()` check with `cli_abort` is fine) with this message
   shape:

   ```
   `state_events` is required: name the `act_type` value(s) that open a
   state (a long-running condition), as opposed to point-in-time events.
   i  Distinct act_type values in `data`: "status" (3 rows), "note" (1 row), ...
   i  Example: state_events = "status"
   ```

   List at most 10 values, ordered by frequency, with row counts. This
   listing IS the discovery mechanism (maintainer decision 2) — implement it
   as an internal helper `describe_act_types(data, act_type_col)` returning
   the formatted bullet, so the "no rows match" error below reuses it.

2. **Supplied but matches nothing.** Keep today's error (with
   `suggest_matches()` hint), rewording "location" → "state".

### 4.3 Case resolution (`R/validate.R`)

New rules, replacing the current "case_id is required" model:

- `case_col = NULL` → the whole `data` is one unnamed series. `case_id`
  must also be NULL (abort otherwise: "`case_id` was supplied but
  `case_col = NULL` says the data has no case column."). Skip the
  case-filtering step; no auto title. Supported by `plot_case_timeline()`
  and `plot_stage_ladder()` only; `plot_cohort_timeline()` and all
  summarisers abort on `case_col = NULL` ("a cohort needs a case column").
- `case_col` names a column (default `"case_id"`), column missing → current
  missing-column error, plus a new hint: "if the data is a single series
  with no id column, pass `case_col = NULL`."
- `case_id = NULL` and the column has **exactly one** distinct value → use
  it, with `cli_inform` once: "`case_id` not supplied; using the only case
  {.val {id}}."
- `case_id = NULL` and **more than one** distinct value → abort listing the
  first 10 ids: "…pass `case_id`, or compare cases with
  `plot_cohort_timeline()`."
- `case_id` supplied → exactly today's behaviour.

Drop validation step 5 (the multi-patient warning) and every `cols$patient`
reference.

### 4.4 `R/cohort.R`, `R/stage_ladder.R`, `R/aggregate.R`

Apply §2/§3 mechanically: renames, `state_events` required-and-threaded,
`patient_col` gone, `case_col = "case_id"` default, `schema` argument added
to every one of these functions with the same precedence pattern (this
closes a 0.1.0 gap where only the main function accepted a schema).
`plot_cohort_timeline()` keeps `case_ids = NULL` = all cases (that is its
"which subjects" control; §4.3's single-case auto-pick does not apply to
it). `plot_stage_ladder()`'s `stage_order` argument keeps its name (it
orders the y-axis; "stage" here reads naturally as "rung", and the ladder's
docs already describe states).

### 4.5 `R/schema.R`

- `event_log_schema(time_col, act_type_col, activity_col, case_col,
  state_events)` — `patient_col` gone, `location_categories` renamed.
- `.schema_candidates`: drop the `patient_col` entry (with its `k_number`,
  `mrn` list). Keep the other candidate lists as they are.
- `.schema_role_order`: `time_col, case_col, act_type_col, activity_col`.
- `autodetect_schema(data, state_events = NULL)` passthrough renamed.
- Resolution algorithm, tie-abort behaviour, and messages: **unchanged**
  (maintainer decision, 2026-07-11: strict abort stays).

### 4.6 `R/transform.R`, `R/render.R`, `R/render_interactive.R`, `R/theme.R`, `R/utils.R`

- `derive_location_boxes()` → `derive_state_boxes()`; boxes column
  `location` → `state` and thread it through `journey_layers()` (fill aes,
  tooltips, terminal labels, `label_boxes` text), `.stays_from_boxes()`
  (output column `state`), the ladder (delete its now-redundant
  `rename(stage = location)` — use `state` and keep its `stage_rank`
  internals), and the aggregate outputs (`summarise_state_durations()$state`,
  `summarise_transitions()$from_state/$to_state`,
  `summarise_breach_rate()`'s `scope` doc text "a state name").
- "(before first state)" per §3.
- `theme_journey()` → `theme_timeline()` (pure rename, byte-identical theme).
- `journey_layers()`/`render_journey_plot()` may keep their internal names
  (not exported; renaming them is allowed but not required).

### 4.7 `R/pivot_wide.R`

`location_cols` → `state_cols`; rows from those columns get
`act_type = "state_change"` (was `"location_move"`). Docs updated to show
the pivot output feeding `plot_case_timeline(..., state_events =
"state_change")` — the pivot and the plot must agree out of the box.

---

## 5. Datasets (`data-raw/`, `data/`, `R/data.R`)

- `example_journey`: rename column `caseID` → `case_id`; **drop the
  `K_Number` column**. Content otherwise unchanged (it stays a clinical
  dataset — that is allowed; it is *data*, not API). Regenerate the `.rda`
  by editing and re-running `data-raw/example_journey.R` (keep the `—`
  escapes so strings stay marked UTF-8).
- `complaint_example` (`complaint_id`) and `support_ticket_example`
  (`ticket_id`): **unchanged** — they deliberately exercise `case_col`
  mapping and every doc example that uses them must pass
  `case_col = "complaint_id"` / `"ticket_id"`.
- `R/data.R` docs updated to the new formats and to `state_events`-style
  example calls.
- Extra-column tolerance (the role K_Number incidentally played) moves to a
  test (§6): a fixture with an unused extra column must pass through
  untouched.

## 6. Tests

Mechanical pass over all 14 files: renames per §2, fixtures' `caseID` →
`case_id`, delete `K_Number` from fixtures (keep ONE fixture with an inert
extra column, asserting it is tolerated), delete the multi-patient-warning
test, replace patient-title assertions with `"Case <id>"` assertions,
`location` → `state` in returned-table assertions. Snapshot names unchanged.
Every call site now passes `state_events = ...` explicitly.

New file `test-generic-path.R`, covering the objective directly:

1. The §1 acceptance snippet, verbatim, under the universal render gate
   (`expect_no_warning(ggplot_build(p))`).
2. Missing `state_events` aborts listing the distinct `act_type` values
   with counts (match on a value name and "state").
3. `case_id = NULL` + single case → plot + the "using the only case"
   message; + multi-case → abort naming ids and `plot_cohort_timeline`.
4. `case_col = NULL` single-series plot builds; with `case_id` supplied →
   abort; cohort/summarisers with `case_col = NULL` → abort.
5. A schema built once drives `plot_case_timeline`, `plot_cohort_timeline`,
   `plot_stage_ladder`, and `summarise_case_durations` (schema-everywhere).
6. Extra unused columns are tolerated end-to-end.
7. Grep gate as a test: `expect_false(any(grepl("(pre-admission)|Patient ",
   <rendered layer labels and titles>)))` on a generic-data plot.

## 7. Documentation & packaging

- **roxygen:** regenerate `NAMESPACE` and `man/` with `roxygen2::roxygenise()`
  (install `r-cran-roxygen2` via apt if needed; accept the `RoxygenNote`
  field changing). At this scale, do NOT hand-edit `man/`. Delete stale
  `.Rd` files for renamed topics.
- **README.Rmd:** restructure — (1) one-paragraph generic pitch (keep), (2)
  quick start = the ONE-call `example_journey` snippet from §1 plus the
  feature-flags variant, (3) "Same API, any domain": ticket + complaint
  examples (band, ladder, cohort), (4) "Bring your own data": schema +
  pivot pointers, (5) vignette index. Re-knit README.md (install pandoc +
  r-cran-knitr/rmarkdown/... via apt) so the committed README.md and figures
  match the new API. Note in the PR body that the GitHub repo *description*
  ("R function for visualising patient hospital journey event logs…") needs
  manual updating by the maintainer — it is a repo setting, not a file.
- **Vignettes:** update all four to the new API. `getting-started.Rmd`
  remains the clinical walkthrough by design; the other three must read
  domain-neutral. `adapting-your-data.Rmd` gains the §4.2 error-driven
  `state_events` discovery flow as its opening example.
- **_pkgdown.yml:** update `reference:` lists to the new names.
- **DESCRIPTION:** `Version: 0.2.0`; Description text per §3.
- **NEWS.md:** new `# eventviz 0.2.0` section: the objective (one paragraph
  of §1), the rename table (condensed), the new case-resolution rules, and
  "no deprecation shims — pre-release clean break".
- **.Rbuildignore:** add `^REDESIGN_PLAN\.md$`.

## 8. Verification gates (all must pass before the PR is opened)

Run in the implementation container (apt R 4.3.3 stack is fine):

1. `R CMD INSTALL .` clean.
2. Full suite **without** `NOT_CRAN` (vdiffr skips): **0 failures**, and the
   functional count must not drop below 0.1.0's (≈441 + the new
   `test-generic-path.R` assertions).
3. `_R_CHECK_FORCE_SUGGESTS_=false R CMD check --no-manual --no-vignettes
   --no-build-vignettes` on the built tarball: no ERROR; no WARNING/NOTE
   beyond the known environment set (locale warning, vignette-not-built
   warnings when knitr absent, offline-CRAN note, marked-UTF-8 data note).
4. The §3 grep gate.
5. The §1 acceptance snippet, run by hand, eyeballed once via `ggsave()`.
6. Local vdiffr baselines are now stale BY DESIGN (titles/legends changed).
   Do not hand-edit them and do not commit locally-rendered replacements.

## 9. Final step: regenerate baselines on CI

The 12 vdiffr baselines are regenerated ON the CI runner (the canonical
graphics stack) by the `update-snapshots` workflow already on this branch's
history (fixed in commit `393f6ee`: attaches the package, lifts the
max-failure cap, dispatch-only).

Because `workflow_dispatch` is only available for workflows that exist on
the default branch, and this workflow does not yet, use the bootstrap
pattern (it worked on 2026-07-11): temporarily add to the workflow's `on:`
block —

```yaml
  push:
    branches: [ '<implementation-branch-name>' ]
```

— push, let the run commit the regenerated SVGs to the branch, then REMOVE
the temporary trigger in a follow-up commit (removing it in the pushed
commit itself prevents re-triggering). The implementing session must NOT
attempt to visually approve the images — that is the reviewer's job (§10.4).
Open the PR to `main` after the snapshots commit lands; the PR's own
R-CMD-check / test-coverage / pkgdown runs should then be green (if
test-coverage fails only at the Codecov *upload* step, that is the missing
`CODECOV_TOKEN` repo secret — a pre-existing, out-of-scope repo-settings
issue; say so in the PR rather than "fixing" it by weakening the workflow).

## 10. Review charter — for the final Opus/Fable pass

You are reviewing against the **objective in §1**, not against task
completion. A diff that ticks every box above but still *feels* like a
hospital package wearing a costume is a failed review. Protocol:

1. **Run the first-contact experience yourself.** Fresh R session, the §1
   `orders` frame, nothing but `plot_case_timeline(orders, state_events =
   "status", case_id = "A-1")`. Then deliberately do it wrong: omit
   `state_events`, omit `case_id` with 2 cases, point `case_col` at a
   missing column. Judge whether each error TEACHES the fix in one reading.
   This is the heart of the review.
2. **Hunt for concept leaks**, not just string leaks: an argument still
   named for locations, a doc paragraph that only makes sense clinically, a
   summary column called `location`, an example that silently depends on
   the old defaults. The §3 grep gate catches strings; you are checking
   *framing*.
3. **API coherence:** one concept, one name (§1 rule) across all exported
   signatures, return columns, and docs — including the pivot's emitted
   `"state_change"` value feeding `state_events` without translation.
4. **Visually approve all 12 regenerated baselines** in the PR diff, one by
   one (GitHub renders SVG diffs; check titles now say "Case …", legends say
   "State", nothing overlaps). No baseline merges unreviewed — this rule
   predates this plan and still binds.
5. **Judge the docs as a stranger:** does the README's first screen ever
   mention a hospital before it has shown a generic example? Do the three
   non-clinical vignettes read natively generic?
6. Check NEWS tells a 0.1.0 user (there are none, but the record matters)
   exactly what broke and why.
7. Only then check the mechanical gates (§8) were honestly reported.

## 11. Out of scope (do not fold in)

- Overlapping/parallel states (see §1 semantics note) and any
  `continuous_events`-style non-exclusive interval support.
- Value-level autodetection heuristics for `state_events` (the error
  listing IS the mechanism, by decision).
- Segmented/non-linear time axis; cohort staircase overlay; ggalluvial;
  Shiny; CRAN submission.
- The Codecov token repo setting (§9).
- Renaming the GitHub repository itself.
