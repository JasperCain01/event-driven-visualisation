# Construct an event log column-name schema

A lightweight classed list describing how an event log's columns map
onto the roles \[plot_case_timeline()\] needs. Every field defaults to
\`NULL\` ("not part of this schema"). When wired into
\[plot_case_timeline()\] via its \`schema\` argument, a \`NULL\` field
falls through to that function's own hardcoded default — and an
explicitly supplied individual argument always wins over the schema
regardless.

## Usage

``` r
event_log_schema(
  time_col = NULL,
  act_type_col = NULL,
  activity_col = NULL,
  case_col = NULL,
  state_events = NULL
)
```

## Arguments

- time_col, act_type_col, activity_col, case_col:

  Column names in the target event log, or \`NULL\`.

- state_events:

  Character vector of \`act_type\` values that open a state, or
  \`NULL\`.

## Value

An object of class \`event_log_schema\`.

## Examples

``` r
event_log_schema(time_col = "ts", case_col = "record_id")
#> 
#> ── <event_log_schema> 
#> time_col: ts
#> act_type_col: <not set>
#> activity_col: <not set>
#> case_col: record_id
#> state_events: <not set>
```
