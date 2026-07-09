# Summarise directed location-to-location transitions across a cohort

For each case, consecutive stays (ordered by entry time) form a from -\>
to pair; the dwell of that transition is the time spent in the "from"
state before the move. A "from" state always has a successor, so it is
never the imputed final box — transition dwell is intrinsically real
(\`include_inferred\` is threaded only for API symmetry and never
excludes anything here).

## Usage

``` r
summarise_transitions(
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

A tibble (\`from_location\`, \`to_location\`, \`n\`,
\`mean_dwell_secs\`, \`median_dwell_secs\`), one row per distinct
ordered pair, sorted by descending \`n\`.

## Examples

``` r
summarise_transitions(
  complaint_example, case_col = "complaint_id",
  location_categories = "stage_change", patient_col = NULL
)
#> # A tibble: 5 × 5
#>   from_location   to_location            n mean_dwell_secs median_dwell_secs
#>   <chr>           <chr>              <int>           <dbl>             <dbl>
#> 1 Acknowledgement Triage                 8         108000              86400
#> 2 Assigned        Under review           8          97200              86400
#> 3 Triage          Assigned               8          91800              86400
#> 4 Senior review   Formal letter sent     7         172800             172800
#> 5 Under review    Senior review          7         487543.            259200
```
