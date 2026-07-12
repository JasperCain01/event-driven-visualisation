# Summarise breach rate against a target duration

What fraction of cases exceed \`target_hours\`?

## Usage

``` r
summarise_breach_rate(
  data,
  target_hours,
  scope = "case",
  case_ids = NULL,
  state_events,
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

- target_hours:

  Single numeric target, in hours.

- scope:

  Either \`"case"\` (whole-case elapsed time: first state event to last
  recorded event — both endpoints are real timestamps, so
  \`include_inferred\` is a no-op) or the name of a state present in the
  cohort (dwell within that one state, e.g. a 4-hour standard). A case
  that never visited the state contributes no row. An unknown scope name
  aborts with a did-you-mean hint.

- case_ids:

  Character vector of cases to include, or \`NULL\` (default) for every
  case in \`data\`.

- state_events:

  Character vector of \`act_type\` values that open a state. Required —
  no default; see \[plot_case_timeline()\] for the discovery-error
  behaviour when omitted.

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

  Logical; see \[summarise_case_durations()\]. When \`scope\` is a state
  whose final stay is the imputed final box, \`FALSE\` (default) drops
  those cases and reports the count.

## Value

A tibble (\`case_id\`, \`elapsed_hours\`, \`breached\`,
\`end_inferred\`) with the cohort breach fraction in \`attr(.,
"breach_rate")\` and the excluded count in \`attr(.,
"n_inferred_excluded")\`.

## Examples

``` r
summarise_breach_rate(
  complaint_example, target_hours = 24 * 7, scope = "case",
  case_col = "complaint_id", state_events = "stage_change"
)
#> # A tibble: 8 × 4
#>   case_id elapsed_hours breached end_inferred
#>   <chr>           <dbl> <lgl>    <lgl>       
#> 1 CMP-01            192 TRUE     FALSE       
#> 2 CMP-02             96 FALSE    FALSE       
#> 3 CMP-03            624 TRUE     FALSE       
#> 4 CMP-04             96 FALSE    FALSE       
#> 5 CMP-05            216 TRUE     FALSE       
#> 6 CMP-06            144 FALSE    FALSE       
#> 7 CMP-07            240 TRUE     FALSE       
#> 8 CMP-08            336 TRUE     FALSE       
```
