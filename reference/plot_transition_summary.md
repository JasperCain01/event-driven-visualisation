# Plot a directed transition-flow diagram for a cohort

A hand-rolled flow diagram: nodes are the distinct locations laid out
left-to-right by their average step index across cases, so the common
forward flow reads as a left-to-right spine; directed edges are drawn as
arrowed curves whose width encodes transition frequency, labelled with
the mean dwell in the "from" state. Forward transitions (to a later
node) bow one way, backward transitions the other, so a re-entry loop is
visually separable from the forward flow it mirrors.

## Usage

``` r
plot_transition_summary(
  data,
  case_ids = NULL,
  location_categories = c("location_move", "ed_location_move"),
  time_col = "timestamp",
  act_type_col = "act_type",
  activity_col = "activity",
  case_col = "caseID",
  patient_col = NULL,
  tz = "UTC",
  terminal_activities = NULL,
  exclude_categories = NULL,
  tail_strategy = "last_event",
  min_n = 1L,
  title = NULL,
  return_data = FALSE
)
```

## Arguments

- data:

  A data frame or tibble containing the event log for the whole cohort.

- case_ids:

  Character vector of cases to include, or \`NULL\` (default) for every
  case in \`data\`.

- location_categories:

  Character vector of \`act_type\` values that mark a location/state
  move.

- time_col, act_type_col, activity_col, case_col, patient_col:

  Column-name mappings, as in \[plot_patient_journey()\].

- tz:

  Timezone used when parsing character timestamps.

- terminal_activities:

  Character vector of terminal \`activity\` values.

- exclude_categories:

  Character vector of \`act_type\` values to drop before summarising, or
  \`NULL\`.

- tail_strategy:

  Strategy for inferring the final box's end time.

- min_n:

  Only draw transitions observed at least this many times.

- title:

  Plot title; \`NULL\` auto-generates one from the case count.

- return_data:

  Logical; if \`TRUE\`, return \`list(plot, nodes, edges, transitions)\`
  instead of just the plot.

## Value

A \`ggplot\` object, or a list when \`return_data = TRUE\`.

## Examples

``` r
plot_transition_summary(
  complaint_example, case_col = "complaint_id",
  location_categories = "stage_change", patient_col = NULL
)

```
