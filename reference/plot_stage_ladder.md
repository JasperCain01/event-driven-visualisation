# Visualise a linear stage process as a staircase

For a strictly linear process (a complaint moving through fixed stages,
a purchase order raised then approved then fulfilled), the compelling
question is "where does the time go" — this puts stage on the y-axis
(first stage at the top) and draws one horizontal segment per stage,
with thin grey connectors forming a staircase as the case walks
down-and-right like a Gantt chart. It reuses the same box derivation
\[plot_patient_journey()\] uses; only the rendering differs.

## Usage

``` r
plot_stage_ladder(
  data,
  case_id,
  stage_categories,
  stage_order = NULL,
  time_col = "timestamp",
  act_type_col = "act_type",
  activity_col = "activity",
  case_col = "caseID",
  patient_col = NULL,
  tz = "UTC",
  terminal_activities = NULL,
  stage_targets = NULL,
  show_duration = TRUE,
  palette_style = c("okabe", "brewer"),
  location_palette = NULL,
  tail_strategy = "last_event",
  title = NULL,
  return_data = FALSE
)
```

## Arguments

- data:

  A data frame or tibble containing the event log.

- case_id:

  The single case identifier to visualise.

- stage_categories:

  Character vector of \`act_type\` value(s) marking a stage entry (the
  direct analogue of \`location_categories\`).

- stage_order:

  Character vector pinning the vertical stage order, or \`NULL\`
  (default) to use first-appearance order. Every stage present in the
  data must appear in \`stage_order\` if supplied.

- time_col, act_type_col, activity_col, case_col, patient_col:

  Column-name mappings, as in \[plot_patient_journey()\].

- tz:

  Timezone used when parsing character timestamps.

- terminal_activities:

  Character vector of terminal \`activity\` values.

- stage_targets:

  Named numeric vector mapping a stage name to its allowed dwell in
  hours, rendered as a light band from stage entry to entry + target;
  dwell beyond it is drawn in firebrick. \`NULL\` = no targets shown.

- show_duration:

  Logical; show a formatted duration label at each segment's midpoint.

- palette_style:

  Auto-palette style: \`"okabe"\` (default) or \`"brewer"\`.

- location_palette:

  Named character vector (stage -\> hex colour) overriding the automatic
  palette, or \`NULL\`.

- tail_strategy:

  Strategy for inferring the final stage's end time.

- title:

  Plot title; \`NULL\` auto-generates one from \`case_id\` /
  \`patient_col\`.

- return_data:

  Logical; if \`TRUE\`, return \`list(plot, boxes)\` instead of just the
  plot.

## Value

A \`ggplot\` object, or a list when \`return_data = TRUE\`.

## Examples

``` r
plot_stage_ladder(
  complaint_example, case_id = "CMP-01",
  stage_categories = "stage_change", case_col = "complaint_id"
)

```
