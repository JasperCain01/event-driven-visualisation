# Autodetect an event log's column schema

Builds an \[event_log_schema()\] by matching \`data\`'s column names
against built-in per-role candidate lists (exact case-insensitive match
first, then fuzzy \`adist() \<= 2\` match). Roles are resolved in a
fixed order (time -\> case -\> act_type -\> activity) and each data
column may be claimed by at most one role — once claimed, it is removed
from consideration for every later role. A tie between two equally-good
candidates for one role aborts rather than picking silently.

## Usage

``` r
autodetect_schema(data, state_events = NULL)
```

## Arguments

- data:

  A data frame or tibble to detect column roles in.

- state_events:

  Character vector of \`act_type\` values that open a state — a pure
  passthrough into the returned schema, since this function detects
  \*columns\*, not values.

## Value

An \[event_log_schema()\] object.

## Examples

``` r
autodetect_schema(example_journey)
#> ℹ Autodetected time_col = "timestamp" (exact match).
#> ℹ Autodetected case_col = "case_id" (exact match).
#> ℹ Autodetected act_type_col = "act_type" (exact match).
#> ℹ Autodetected activity_col = "activity" (exact match).
#> 
#> ── <event_log_schema> 
#> time_col: timestamp
#> act_type_col: act_type
#> activity_col: activity
#> case_col: case_id
#> state_events: <not set>
```
