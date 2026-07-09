# Summarise per-stay durations across a cohort

One row per location stay across the cohort — the detail table the other
aggregate functions build on. Every duration statistic in this package
respects \`end_inferred\`: the final box of a non-terminal spell has an
\*imputed\* end time, and including it in a mean length-of-stay would
silently contaminate it with a rendering convenience.

## Usage

``` r
summarise_journey_durations(
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
  include_inferred = FALSE
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

- include_inferred:

  Logical. \`FALSE\` (default) drops the imputed final-stay rows and
  records how many were removed in \`attr(result,
  "n_inferred_excluded")\`; \`TRUE\` keeps every row (the
  \`end_inferred\` column still flags the imputed ones).

## Value

A tibble with one row per stay (\`case_id\`, \`location\`, \`xmin\`,
\`xmax\`, \`duration_secs\`, \`end_inferred\`, \`terminal\`), carrying
\`attr(., "n_inferred_excluded")\`.

## Examples

``` r
summarise_journey_durations(
  complaint_example, case_col = "complaint_id",
  location_categories = "stage_change", patient_col = NULL
)
#> # A tibble: 38 × 7
#>    case_id location        xmin                xmax                duration_secs
#>    <chr>   <chr>           <dttm>              <dttm>                      <dbl>
#>  1 CMP-01  Acknowledgement 2025-01-06 09:00:00 2025-01-07 09:00:00         86400
#>  2 CMP-01  Triage          2025-01-07 09:00:00 2025-01-08 09:00:00         86400
#>  3 CMP-01  Assigned        2025-01-08 09:00:00 2025-01-09 09:00:00         86400
#>  4 CMP-01  Under review    2025-01-09 09:00:00 2025-01-12 09:00:00        259200
#>  5 CMP-01  Senior review   2025-01-12 09:00:00 2025-01-14 09:00:00        172800
#>  6 CMP-02  Acknowledgement 2025-01-06 09:00:00 2025-01-06 21:00:00         43200
#>  7 CMP-02  Triage          2025-01-06 21:00:00 2025-01-07 09:00:00         43200
#>  8 CMP-02  Assigned        2025-01-07 09:00:00 2025-01-07 21:00:00         43200
#>  9 CMP-02  Under review    2025-01-07 21:00:00 2025-01-09 09:00:00        129600
#> 10 CMP-02  Senior review   2025-01-09 09:00:00 2025-01-10 09:00:00         86400
#> # ℹ 28 more rows
#> # ℹ 2 more variables: end_inferred <lgl>, terminal <lgl>
```
