# Summarise per-state duration statistics across a cohort

Built on \[summarise_case_durations()\]: one row per distinct state with
the case count, mean/median/p25/p75 dwell in seconds, and the number of
imputed final stays excluded from those statistics.

## Usage

``` r
summarise_state_durations(
  data,
  state_events,
  case_ids = NULL,
  time_col = "timestamp",
  act_type_col = "act_type",
  activity_col = "activity",
  case_col = "case_id",
  schema = NULL,
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

- state_events:

  Character vector of \`act_type\` values that open a state. Required —
  no default; see \[plot_case_timeline()\] for the discovery-error
  behaviour when omitted.

- case_ids:

  Character vector of cases to include, or \`NULL\` (default) for every
  case in \`data\`.

- time_col, act_type_col, activity_col, case_col:

  Column-name mappings, as in \[plot_case_timeline()\]. \`case_col\` is
  required (it cannot be \`NULL\` — a cohort needs a case column).

- schema:

  An \[event_log_schema()\] object, the literal string \`"auto"\`, or
  \`NULL\` — see \[plot_case_timeline()\].

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

A tibble with one row per state (\`state\`, \`n_cases\`, \`mean_secs\`,
\`median_secs\`, \`p25_secs\`, \`p75_secs\`, \`n_inferred_excluded\`).
\`n_cases\` counts every case that visited the state; the statistics are
computed only over the \*included\* stays, so a state seen only as an
imputed final stay reports \`NA\` statistics when \`include_inferred =
FALSE\`.

## Examples

``` r
summarise_state_durations(
  complaint_example, case_col = "complaint_id",
  state_events = "stage_change"
)
#> # A tibble: 6 × 7
#>   state      n_cases mean_secs median_secs p25_secs p75_secs n_inferred_excluded
#>   <chr>        <int>     <dbl>       <dbl>    <dbl>    <dbl>               <int>
#> 1 Acknowled…       8   108000        86400    86400   140400                   0
#> 2 Assigned         8    97200        86400    86400    97200                   0
#> 3 Formal le…       7       NA           NA       NA       NA                   7
#> 4 Senior re…       7   172800       172800   129600   216000                   0
#> 5 Triage           8    91800        86400    86400    86400                   0
#> 6 Under rev…       8   487543.      259200   216000   388800                   1
```
