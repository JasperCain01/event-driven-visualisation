# What the tests protect

There are 157 `test_that()` blocks in `tests/testthat/`. Run them with `devtools::test()`; CI runs them under `R CMD check`.

## How the suite is organised

There are three kinds of test, and each has a job the others don't do.

**Behaviour tests** use small hand-built fixtures (`hrs(n)` offsets from a fixed start), so every expected box boundary, duration and statistic can be checked by eye. They are most of the suite.

**Render checks** call `expect_no_warning(ggplot2::ggplot_build(p))`. A ggplot warning on build usually means rows were silently dropped (for example, labels pushed outside fixed scale limits). These checks sit inside the behaviour test for the feature concerned; there are deliberately no standalone "it renders" tests. The all-features test in `test-render.R` is the single combined check.

**vdiffr snapshots** (12 SVG baselines in `_snaps/`) catch any visual change. They're pinned to the graphics stack that produced them (R, ggplot2, svglite, fonts), and CI is the canonical environment. If every snapshot fails after an R or CRAN upgrade while everything else passes, the baselines are stale, not the code: regenerate them on CI and review each image. Because the snapshots cover layout, the behaviour tests check *values* (positions, label text, counts) rather than layer counts or geom classes.

The interactive tests need **ggiraph** and skip without it.

Severity describes what goes wrong for a user if the guarded behaviour breaks:

- **Critical**: the main entry points don't work.
- **High**: a plot or summary is silently wrong.
- **Medium**: a feature visibly misbehaves or errors.
- **Low**: wording or cosmetics.

## `test-validate.R`: checking and filtering the input log

| Test | Purpose | Severity |
|---|---|---|
| non-data-frame input aborts with informative message | | Low |
| missing column produces error listing missing and present columns | | Low |
| unknown case_id aborts and shows available IDs | | Low |
| character timestamps that parse cleanly are accepted | Text dates are coerced rather than refused. | Medium |
| unparseable timestamp aborts and names the bad row | A bad date fails loudly instead of becoming NA and vanishing. | High |
| no matching state act_types aborts with near-match suggestion | A typo in `state_events` fails with a hint rather than drawing no boxes. | Medium |
| NA or blank activity on a state event aborts | A state with no name can't be drawn or summarised meaningfully. | Medium |
| the log is sorted ascending by time, stably within duplicate timestamps | Event order drives every box boundary; ties keep their input order. | High |
| valid log returns a tibble for the correct case only | Only the requested case is kept. The fixture's column is literally `case_id`, so this also guards dplyr's data-mask collision with the argument of the same name. | High |
| case_col = NULL keeps the whole data frame as one unnamed series | Single-series mode, at the validation layer. | Medium |
| case_id supplied with case_col = NULL aborts | | Low |
| case_id = NULL with a single distinct case auto-resolves it | With a message saying which case was used. | Medium |
| case_id = NULL with multiple distinct cases aborts naming them | Points the user to `plot_cohort_timeline()`. | Low |
| missing case_col hints at case_col = NULL for a single series | | Low |

## `test-schema.R`: column-name schemas and autodetection

| Test | Purpose | Severity |
|---|---|---|
| event_log_schema() constructs a classed list with the given fields | | Medium |
| print.event_log_schema() reports every field | | Low |
| autodetect_schema() resolves exact-match columns | | Medium |
| autodetect_schema() recovers renamed (typo'd) columns via fuzzy match | And says which matches were fuzzy. | Medium |
| state_events is a pure passthrough | | Low |
| two equally-good exact matches for one role abort naming both | Ambiguity is never resolved by guessing. | High |
| columns with no plausible match abort, naming the unresolved role(s) | | Low |
| a column claimed by an earlier role is not reconsidered by a later role | One column can't silently serve as both time and activity. | High |
| schema = "auto" autodetects and renders successfully | End-to-end check of the `"auto"` sentinel. | Medium |
| an explicit individual argument beats the schema | Precedence: argument > schema > default. | High |
| an omitted argument falls through to the schema field | Also proves a schema *object* is never autodetected: autodetection would have picked `ts`, not the schema's `mytime`. | High |
| state_events omitted falls through to the schema field | | Medium |

## `test-transform.R`: deriving state boxes and point events

| Test | Purpose | Severity |
|---|---|---|
| a standard log produces one box per state, each ending where the next begins | Box count, state names, every start and end, and which end is inferred, in one comparison. Everything else is drawn from these boxes. | High |
| final box uses median duration when last event IS the state event itself | The `last_event` tail strategy's fallback when there's nothing after the final move. | High |
| zero-width box is nudged and a message is emitted | Two moves at the same instant still produce a visible box, and the user is told. | Medium |
| assign_y_bands stacks bands box_height + band_gap apart | Band 0 sits at 0–1; band 1 is offset by height plus gap. | Medium |
| every non-state row becomes a point event in the box that contains it | | High |
| event exactly at a box boundary belongs to the next box | The half-open interval rule at boundaries. | High |
| returns empty tibble with correct columns when no point events exist | | Medium |
| events before the first state get a prepended before-first-state box | Early events are kept and drawn rather than dropped, with a message. | High |
| single state event produces one box | | Medium |

## `test-transform-lanes.R`: swimlanes

| Test | Purpose | Severity |
|---|---|---|
| lane y positions match the hand-computed band centres | Lane arithmetic, and lanes stored as a factor in first-appearance order. | Medium |
| a factor lane column pins an explicit lane ordering | | Medium |
| lane_gap and lane_height feed straight into the arithmetic | | Medium |
| lane_col = NULL keeps every event on the box midline | The no-lanes path is unchanged. | Medium |
| empty point-event set still returns a lane column when lanes active | | Medium |
| y-axis text/ticks are blank without lanes and visible with them | | Low |
| lanes + duration labels + reference lines render together (gate) | The layers that share vertical space don't collide or drop rows. | Medium |
| an unknown lane_col aborts with a helpful message | | Low |

## `test-generic-path.R`: the package works for any event log

| Test | Purpose | Severity |
|---|---|---|
| the §1 acceptance snippet renders in one call with one declaration | The headline promise: a first-time user's order log plots with only `state_events` declared. | Critical |
| missing state_events aborts listing act_type values with counts and 'state' | The error the first-time user sees tells them what to declare. | Medium |
| case_col = NULL builds a single-series plot with no case_id | Single-series mode end to end, with no title. | Medium |
| summarisers with case_col = NULL abort | | Low |
| one schema drives plot_case_timeline, plot_cohort_timeline, plot_stage_ladder, and summarise_case_durations | The only test that the schema reaches every entry point. | High |
| a generic-data plot carries no clinical vocabulary in labels or titles | No healthcare wording leaks into non-clinical plots. | Low |

## `test-fixes.R`: regressions for named defects

Each test names the defect it guards in a comment.

| Test | Purpose | Severity |
|---|---|---|
| show_labels = TRUE renders without dropping label rows | Labels were once censored to NA by scale limits. | Medium |
| terminal_activities gives the final move zero duration, not a median box | A discharge isn't a stay. | High |
| without terminal_activities the final box end is flagged as inferred | Only the final box. | High |
| zero-width box stores true duration 0, and the message says so | The cosmetic nudge never falsifies the stored duration. | High |
| render-space stagger prevents the nudged box being overlapped | The nudged box stays visible while its true start is untouched. | Medium |
| invalid tail_strategy aborts with a clear match.arg error | | Low |
| exclude_categories removing all state events aborts cleanly | | Low |
| a vector or NA case_id aborts with a clear message | | Low |
| tz argument controls parsing of character timestamps | | High |
| POSIXct input keeps its own tzone regardless of tz argument | `tz` never shifts already-typed times. | High |

## `test-orchestration.R`: `plot_case_timeline()`'s own logic

| Test | Purpose | Severity |
|---|---|---|
| auto title is 'Case <case_id>' | | Low |
| an explicit title overrides auto-generation | | Low |
| exclude_categories drops exactly the matching rows and informs the count | | Medium |
| exclude_categories with no matching rows plots silently (no drop message) | | Low |
| return_data = TRUE returns the plot, boxes, events and a one-row-per-box summary | The documented return shape. | Medium |
| return_data summary agrees with summarise_case_durations() for the same case | Two code paths that compute the same durations must agree. | High |

## `test-render.R`: visual features of the single-case plot

| Test | Purpose | Severity |
|---|---|---|
| format_duration() gives exact strings at each bucket boundary | `59s`, `1m`, `59m`, `1h`, `23h 59m`, `1d 0h`… | Medium |
| format_duration() is vectorised and NA-safe | | Medium |
| show_duration labels each box with its rendered duration, '+' marking an inferred end | Reads the label text from the built plot: `4h` and `4h+`. Terminal boxes get no label. A wrong duration label misleads the reader. | High |
| malformed reference_lines abort with a message naming the problem | Four malformed inputs. | Low |
| each reference line is drawn at its offset from the first event | A target drawn in the wrong place is misleading. | High |
| case_open is TRUE only when terminal_activities is given and not reached | The open/closed truth table. | High |
| an open case gets a dashed '(ongoing)' marker at its last box's end; a closed one does not | | Medium |
| label_boxes writes each non-terminal box's state name on it | Terminal boxes keep their own label. | Medium |
| bucket_top_n() leaves x unchanged when distinct count <= top_n | | Medium |
| bucket_top_n() keeps the most frequent values and collapses the rest | | Medium |
| event_type_top_n collapses the long tail into 'Other' | Visible as four colour groups. | Medium |
| event_type_top_n is a no-op when under the threshold | And the returned events table is never altered. | Medium |
| okabe states and events never share a hex for co-indexed levels | States and events stay distinguishable. | Medium |
| okabe palette recycles past 8 distinct levels without erroring | | Medium |
| journey_palette() defaults to palette_style = 'okabe' | | Low |
| brewer style reproduces the prior Set2/Dark2 output exactly | Backward compatibility for the opt-out style. | Low |
| invalid palette_style aborts with a clear match.arg error | | Low |
| palette_style = 'brewer' render builds without warning | The only plot-level check of the non-default palette. | Medium |
| universal render gate: ALL Stage 1 features on at once builds cleanly | Every Stage 1 layer at once, with no collision or dropped rows. | Medium |

## `test-render-interactive.R`: the ggiraph renderer (skipped without ggiraph)

The tooltip tests build the interactive ggplot through `.interactive_plot()`, which calls the internal pipeline with a hand-written `opts` list. If `plot_case_timeline()` gains or renames an option, update that list too; otherwise these tests keep checking a configuration the real entry point no longer produces.

| Test | Purpose | Severity |
|---|---|---|
| interactive = TRUE returns a girafe htmlwidget | | Medium |
| the interactive ggplot builds cleanly (universal gate) | | Medium |
| box tooltips carry state, duration, entry/exit, no inferred caveat for a real end | | Medium |
| an end_inferred box's tooltip carries the inferred caveat | An imputed end is never shown as fact. | High |
| terminal-marker tooltips carry the state name and its instant | | Medium |
| event-point tooltips carry activity, act_type, and timestamp | | Medium |

## `test-render-snapshots.R` and the other baselines

`journey-default`, `-show-labels`, `-show-duration`, `-label-boxes`, `-terminal-activities`, `-reference-line-4h`, `-all-features` and `-swimlanes` (in `test-render-snapshots.R`), plus `cohort-absolute`, `cohort-aligned`, `stage-ladder-cmp03` and `support-ticket-band` in their own files. Each freezes one approved rendering. The per-feature images duplicate parts of `journey-all-features` on purpose, so a failure shows *which* feature changed. All guard against High-severity silent visual regressions.

## `test-aggregate.R`: cohort statistics

The fixture's three cases have round-number durations computed in the file header, so every figure below can be checked by hand. These are the numbers a user would quote in a report.

| Test | Purpose | Severity |
|---|---|---|
| summarise_case_durations drops inferred stays by default and reports the count | Imputed durations stay out of statistics unless asked for. | High |
| include_inferred = TRUE keeps every stay, at its hand-computed duration | | High |
| summarise_state_durations computes hand-checked stats and excludes inferred | Mean, median, quartiles, n. | High |
| include_inferred = TRUE folds the imputed stay back into the stats | | High |
| case-scope breach uses first-move-to-last-event and flags nothing inferred | | High |
| state-scope breach excludes inferred dwells by default | | High |
| state-scope breach with include_inferred keeps the imputed dwell | | High |
| a case or stay that exactly meets its target is not a breach; one second over is | "Breach" means exceeding the target. A `>=` slip would raise every breach rate with cases on the line, and no other test would notice. | High |
| an unknown scope name aborts with a suggestion | | Low |
| summarise_transitions returns exact counts and dwell means | | High |
| plot_transition_summary renders cleanly on a multi-path cohort | Including backward transitions. | Medium |
| plot_transition_summary return_data exposes nodes and edges | Node order follows the forward spine; backward edges are flagged. | Medium |
| plot_case_timeline_with_summary assembles a patchwork that builds | (Skipped without patchwork.) | Medium |
| summary bar colours match the timeline's fills even with a before-first-state box | A shifted palette made the legend lie. | Medium |

## `test-cohort.R`: faceted cohort view

| Test | Purpose | Severity |
|---|---|---|
| NULL case_ids facets every case in the data, within max_cases | | Medium |
| a case_ids subset facets only the requested cases | | Medium |
| align_start puts every case's first box at elapsed hour 0 | | High |
| align_start does not error when a case has zero point events | Regression: a type mismatch on bind. | Medium |
| absolute mode keeps each case on its own datetime range | | Medium |
| the same state gets the same fill hex in every panel | Cross-panel colour consistency. | High |
| max_cases aborts with advice to pass explicit case_ids | | Low |
| terminal_activities is forwarded per case | | Medium |
| absolute cohort plot matches its baseline / start-aligned cohort plot matches its baseline | vdiffr. | High |
| absolute-mode gaps are sized per panel, not against the cohort calendar span | Regression: 1-hour boxes once drew 11 hours wide. | High |
| the 'Other' bucket is coloured from the palette, not na.value grey | | Medium |
| open cases get a per-panel '(ongoing)' marker; closed cases do not | And none at all without `terminal_activities`. | Medium |
| ongoing markers render in start-aligned mode too (universal gate) | | Medium |
| tail_strategy is forwarded per case | | Medium |
| case_col = NULL aborts: a cohort needs a case column | | Low |

## `test-stage-ladder.R`: staircase view and stage targets

| Test | Purpose | Severity |
|---|---|---|
| the staircase renders cleanly (universal gate) | | Critical (for this view) |
| first stage sits at the top (highest y) by first appearance | | Medium |
| stage_order pins an explicit vertical ordering | | Medium |
| stage_order missing a present stage aborts naming it | | Low |
| duration labels are present at segment midpoints | With no `+` on a closed case. | Medium |
| show_duration = FALSE drops the duration-label layer | | Low |
| stage_targets adds exactly one band layer per targeted stage | | Medium |
| a breached target draws a firebrick excess segment | | High |
| stage_targets naming an unknown stage aborts | | Low |
| the terminal stage renders as a point, not a segment | | Medium |
| complaint_example renders in the band layout, with state_label as the legend title | | Medium |
| stage-ladder plot matches its baseline | vdiffr. | High |
| stage_targets bands and marks every visit to a revisited stage | Regression: only the first visit was marked. | High |
| an open stage draws its proven breach excess, capped at the last observed event | A breach is claimed only as far as the data proves it. | High |
| an open stage whose observed dwell is within target claims no breach | Even if the imputed end would cross the target. | High |

## `test-pivot.R`: wide milestone tables → event log

| Test | Purpose | Severity |
|---|---|---|
| basic pivot produces correct row count and act_type values | Row count, state vs milestone `act_type`s, and suffix-stripped labels (`Triage`, not `Triage Time`). | High |
| act_type_map and activity_map override the defaults | | Medium |
| missing case_col aborts naming missing and present columns | | Low |
| missing time_cols entry aborts naming it | | Low |
| state_cols not a subset of time_cols aborts naming the offender | | Low |
| NA milestone timestamps are dropped with an informative message | | Medium |
| drop_na = FALSE keeps NA-timestamp rows | | Medium |
| equal-timestamp milestones pivot cleanly and render under the universal gate | Pivoted output feeds `plot_case_timeline()` directly, even with tied milestones. | Medium |
| passthrough columns (e.g. diagnosis) survive the pivot untouched | | Medium |

## `test-support-ticket.R`: the non-healthcare example dataset

| Test | Purpose | Severity |
|---|---|---|
| support_ticket_example has the expected shape and no case-secondary column | Protects the bundled data the documentation relies on. | Medium |
| the still-open ticket (TCK-04) triggers the ongoing-case indication | The dataset contains the open case the docs demonstrate. | Low |
| support_ticket_example band layout matches its baseline | vdiffr. | High |
| support_ticket_example renders in the staircase layout | | Medium |
| support_ticket_example renders in the cohort layout | | Medium |
