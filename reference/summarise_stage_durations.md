# Summarise per-location duration statistics across a cohort

Built on \[summarise_journey_durations()\]: one row per distinct
location with the case count, mean/median/p25/p75 dwell in seconds, and
the number of imputed final stays excluded from those statistics.

## Usage

``` r
summarise_stage_durations(
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

A tibble with one row per location (\`location\`, \`n_cases\`,
\`mean_secs\`, \`median_secs\`, \`p25_secs\`, \`p75_secs\`,
\`n_inferred_excluded\`). \`n_cases\` counts every case that visited the
location; the statistics are computed only over the \*included\* stays,
so a location seen only as an imputed final stay reports \`NA\`
statistics when \`include_inferred = FALSE\`.

## Examples

``` r
summarise_stage_durations(
  complaint_example, case_col = "complaint_id",
  location_categories = "stage_change", patient_col = NULL
)
#> # A tibble: 6 × 7
#>   location   n_cases mean_secs median_secs p25_secs p75_secs n_inferred_excluded
#>   <chr>        <int>     <dbl>       <dbl>    <dbl>    <dbl>               <int>
#> 1 Acknowled…       8   108000        86400    86400   140400                   0
#> 2 Assigned         8    97200        86400    86400    97200                   0
#> 3 Formal le…       7       NA           NA       NA       NA                   7
#> 4 Senior re…       7   172800       172800   129600   216000                   0
#> 5 Triage           8    91800        86400    86400    86400                   0
#> 6 Under rev…       8   487543.      259200   216000   388800                   1
```
