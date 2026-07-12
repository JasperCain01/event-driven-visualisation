# Visualise an event log as a state-band timeline

Renders one case's event log as a horizontal timeline: coloured boxes
for each exclusive state the case occupies over time (opened by an event
whose \`act_type\` is listed in \`state_events\`), with instantaneous
events plotted as points on the midline.

## Usage

``` r
plot_case_timeline(
  data,
  state_events,
  case_id = NULL,
  time_col = "timestamp",
  act_type_col = "act_type",
  activity_col = "activity",
  case_col = "case_id",
  schema = NULL,
  tz = "UTC",
  terminal_activities = NULL,
  exclude_categories = NULL,
  show_labels = FALSE,
  label_max = 30L,
  show_duration = FALSE,
  label_boxes = FALSE,
  reference_lines = NULL,
  event_type_top_n = NULL,
  lane_col = NULL,
  lane_height = NULL,
  lane_gap = NULL,
  state_label = "State",
  state_palette = NULL,
  event_palette = NULL,
  palette_style = c("okabe", "brewer"),
  box_height = 0.25,
  box_gap_prop = 0.003,
  title = NULL,
  tail_strategy = "last_event",
  interactive = FALSE,
  return_data = FALSE
)
```

## Arguments

- data:

  A data frame or tibble containing the event log.

- state_events:

  Character vector of \`act_type\` values that open a state (these
  events create boxes). Required — no default. If omitted (and not
  supplied via \`schema\`), the error lists the distinct \`act_type\`
  values present in \`data\` with row counts, so you can see what to
  pass.

- case_id:

  The single case identifier to visualise, or \`NULL\` (default). When
  \`case_col\` names a column with exactly one distinct value, \`NULL\`
  resolves to that value automatically; with more than one, \`NULL\`
  aborts naming the first 10 and pointing at \[plot_cohort_timeline()\].
  Must stay \`NULL\` when \`case_col = NULL\`.

- time_col, act_type_col, activity_col, case_col:

  Column-name mappings. \`case_col\` may be \`NULL\` for event logs with
  no case column at all — a single unnamed series (\`case_id\` must then
  also be \`NULL\`).

- schema:

  An \[event_log_schema()\] object bundling the column-mapping
  arguments, or the literal string \`"auto"\` to run
  \[autodetect_schema()\], or \`NULL\` (default) to ignore. Per-field
  precedence, highest wins: an explicitly supplied individual argument
  (\`time_col\`, \`case_col\`, ...) \> the matching schema field \> this
  function's own hardcoded default.

- tz:

  Timezone used when parsing character timestamps (\`POSIXct\` input
  keeps its own \`tzone\`).

- terminal_activities:

  Character vector of \`activity\` values that are terminal states (e.g.
  \`"Discharged"\`, \`"Closed"\`). A terminal final state event renders
  as a zero-duration marker instead of a box with an invented duration.

- exclude_categories:

  Character vector of \`act_type\` values to drop entirely before
  plotting, or \`NULL\`.

- show_labels:

  Logical; show \`ggrepel\` labels for point events.

- label_max:

  Maximum label character length before truncation.

- show_duration:

  Logical; show a formatted duration label above each non-terminal box
  (\`end_inferred\` boxes get a \`"+"\` suffix).

- label_boxes:

  Logical; label each box directly with its state name, at box centre.

- reference_lines:

  Data frame with \`offset_hours\` (numeric, hours from the case's first
  event) and \`label\`, drawn as dashed target-threshold lines, or
  \`NULL\`.

- event_type_top_n:

  When the distinct \`act_type\` count exceeds this, keep the top-N most
  frequent event types and recode the rest to \`"Other"\`. \`NULL\` = no
  bucketing.

- lane_col:

  Column in \`data\` whose distinct values become swimlanes for point
  events, drawn above the state band. \`NULL\` (default) keeps a single
  midline.

- lane_height, lane_gap:

  Swimlane geometry, in \`box_height\` units. \`NULL\` defaults to
  \`box_height\` and \`0.05 \* box_height\` respectively.

- state_label:

  Fill-legend title. \`"State"\` by default; pass e.g. \`"Stage"\` or
  \`"Status"\` for a linear stage process.

- state_palette, event_palette:

  Named character vectors (level -\> hex colour) overriding the
  automatic palettes, or \`NULL\`.

- palette_style:

  Auto-palette style used when \`state_palette\`/ \`event_palette\` are
  \`NULL\`: \`"okabe"\` (default, colourblind-safe) or \`"brewer"\` (the
  original Set2/Dark2 palette).

- box_height:

  Height of the state band, in plot y-units.

- box_gap_prop:

  Proportion of each box's width trimmed from its right edge to create a
  thin visual gap between adjacent states.

- title:

  Plot title; \`NULL\` auto-generates \`"Case \<case_id\>"\` unless
  \`case_col = NULL\`, in which case there is no case to name and the
  title stays \`NULL\`.

- tail_strategy:

  Strategy for inferring the final box's end time: \`"last_event"\`
  extends to the last event, falling back to \`"median"\` then
  \`"fixed"\`.

- interactive:

  Logical; render as an interactive \`ggiraph\` \`girafe\` widget
  instead of a static ggplot. Requires the \`ggiraph\` package.

- return_data:

  Logical; if \`TRUE\`, return \`list(plot, boxes, events, summary)\`
  instead of just the plot.

## Value

A \`ggplot\` object (or a \`girafe\` widget when \`interactive =
TRUE\`), or a list when \`return_data = TRUE\`.

## Details

States are \*exclusive and contiguous\*: a case is in exactly one state
at a time, and each state ends when the next begins (or is
inferred/terminal at the end of the series). Overlapping long-running
processes are not representable as states — concurrent point-event
tracks are what \`lane_col\` (swimlanes) are for.

## Examples

``` r
plot_case_timeline(example_journey, state_events = c("location_move", "ed_location_move"))
#> ℹ `case_id` not supplied; using the only case "SP-001".

```
