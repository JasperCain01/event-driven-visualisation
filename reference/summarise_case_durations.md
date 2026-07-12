# Summarise per-stay durations across a cohort

One row per state stay across the cohort — the detail table the other
aggregate functions build on. Every duration statistic in this package
respects \`end_inferred\`: the final box of a non-terminal case has an
\*imputed\* end time, and including it in a mean duration would silently
contaminate it with a rendering convenience.

## Usage

``` r
summarise_case_durations(
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

A tibble with one row per stay (\`case_id\`, \`state\`, \`xmin\`,
\`xmax\`, \`duration_secs\`, \`end_inferred\`, \`terminal\`), carrying
\`attr(., "n_inferred_excluded")\`.

## Examples

``` r
summarise_case_durations(
  complaint_example, case_col = "complaint_id",
  state_events = "stage_change"
)
#> # A tibble: 38 × 7
#>    case_id state           xmin                xmax                duration_secs
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
