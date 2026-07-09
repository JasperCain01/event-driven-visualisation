# Visualise an event log as a location-band timeline

Renders one case's event log as a horizontal timeline: coloured boxes
for each exclusive state the case occupies over time (a ward, a
complaint stage, a ticket status — anything \`location_categories\`
marks as a move), with instantaneous events plotted as points on the
midline. Despite the name (kept for backward compatibility), this works
for any event log built from exclusive states over time, not just
clinical spells.

## Usage

``` r
plot_patient_journey(
  data,
  case_id,
  location_categories = c("location_move", "ed_location_move"),
  time_col = "timestamp",
  act_type_col = "act_type",
  activity_col = "activity",
  case_col = "caseID",
  patient_col = "K_Number",
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
  state_label = "Location",
  location_palette = NULL,
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

- case_id:

  The single case identifier to visualise (must be present in
  \`data\[\[case_col\]\]\`).

- location_categories:

  Character vector of \`act_type\` values that mark a move to a new
  exclusive state (these events create boxes).

- time_col, act_type_col, activity_col, case_col, patient_col:

  Column-name mappings. \`patient_col\` may be \`NULL\` for event logs
  with no secondary identifier.

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
  \`"Discharged"\`, \`"Closed"\`). A terminal final move renders as a
  zero-duration marker instead of a box with an invented duration.

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

  Logical; label each box directly with its location name, at box
  centre.

- reference_lines:

  Data frame with \`offset_hours\` (numeric, hours from the spell's
  first event) and \`label\`, drawn as dashed target-threshold lines, or
  \`NULL\`.

- event_type_top_n:

  When the distinct \`act_type\` count exceeds this, keep the top-N most
  frequent event types and recode the rest to \`"Other"\`. \`NULL\` = no
  bucketing.

- lane_col:

  Column in \`data\` whose distinct values become swimlanes for point
  events, drawn above the location band. \`NULL\` (default) keeps a
  single midline.

- lane_height, lane_gap:

  Swimlane geometry, in \`box_height\` units. \`NULL\` defaults to
  \`box_height\` and \`0.05 \* box_height\` respectively.

- state_label:

  Fill-legend title. A journey's boxes are \`"Location"\` by default;
  pass e.g. \`"Stage"\` or \`"Status"\` for a linear stage process.

- location_palette, event_palette:

  Named character vectors (level -\> hex colour) overriding the
  automatic palettes, or \`NULL\`.

- palette_style:

  Auto-palette style used when \`location_palette\`/ \`event_palette\`
  are \`NULL\`: \`"okabe"\` (default, colourblind-safe) or \`"brewer"\`
  (the original Set2/Dark2 palette).

- box_height:

  Height of the location band, in plot y-units.

- box_gap_prop:

  Proportion of each box's width trimmed from its right edge to create a
  thin visual gap between adjacent locations.

- title:

  Plot title; \`NULL\` auto-generates one from \`case_id\` /
  \`patient_col\`.

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

## Examples

``` r
plot_patient_journey(example_journey, case_id = "SP-001")

```
