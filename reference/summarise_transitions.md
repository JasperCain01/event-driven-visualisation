# Summarise directed state-to-state transitions across a cohort

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

A tibble (\`from_state\`, \`to_state\`, \`n\`, \`mean_dwell_secs\`,
\`median_dwell_secs\`), one row per distinct ordered pair, sorted by
descending \`n\`.

## Examples

``` r
summarise_transitions(
  complaint_example, case_col = "complaint_id",
  state_events = "stage_change"
)
#> # A tibble: 5 × 5
#>   from_state      to_state               n mean_dwell_secs median_dwell_secs
#>   <chr>           <chr>              <int>           <dbl>             <dbl>
#> 1 Acknowledgement Triage                 8         108000              86400
#> 2 Assigned        Under review           8          97200              86400
#> 3 Triage          Assigned               8          91800              86400
#> 4 Senior review   Formal letter sent     7         172800             172800
#> 5 Under review    Senior review          7         487543.            259200
```
