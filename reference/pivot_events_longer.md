# Pivot a wide milestone-timestamp event log into long form

Milestone-style event logs are commonly stored wide: one row per case,
one column per timestamp (\`"arrival_time"\`, \`"triage_time"\`,
\`"discharge_time"\`, ...). \[plot_patient_journey()\] needs the long
form (one row per event); this reshapes the former into the latter.

## Usage

``` r
pivot_events_longer(
  data,
  case_col,
  time_cols,
  patient_col = NULL,
  location_cols = NULL,
  act_type_map = NULL,
  activity_map = NULL,
  drop_na = TRUE,
  tz = "UTC",
  time_col_out = "timestamp",
  act_type_col_out = "act_type",
  activity_col_out = "activity"
)
```

## Arguments

- data:

  Wide data frame, one row per case.

- case_col:

  Column identifying each case.

- time_cols:

  Character vector of wide column names to pivot.

- patient_col:

  Optional secondary identifier column, or \`NULL\`.

- location_cols:

  Subset of \`time_cols\` that mark a physical location move; these get
  \`act_type = "location_move"\`.

- act_type_map:

  Named character vector: \`time_cols\` entry -\> act_type, for
  non-location milestones. \`NULL\` = the milestone name is used as-is.

- activity_map:

  Named character vector: \`time_cols\` entry -\> display label.
  \`NULL\` = derived from the milestone name (see
  \`prettify_milestone()\`): strip a trailing timestamp suffix, replace
  separators with spaces, then title-case.

- drop_na:

  Logical; drop rows whose milestone timestamp is \`NA\` (the milestone
  didn't happen for that case). Default \`TRUE\`.

- tz:

  Timezone forwarded to the internal datetime coercion.

- time_col_out, act_type_col_out, activity_col_out:

  Output column names, matching \[plot_patient_journey()\]'s
  \`time_col\`/\`act_type_col\`/ \`activity_col\` arguments.

## Value

A long tibble: case, patient (if given), time, act_type, activity, then
any passthrough columns from \`data\` untouched — ready to pass straight
into \[plot_patient_journey()\].

## Examples

``` r
wide <- data.frame(
  case_id = c("A", "B"),
  arrival_time = as.POSIXct(c("2024-01-01 08:00", "2024-01-01 09:00")),
  discharge_time = as.POSIXct(c("2024-01-01 12:00", "2024-01-01 14:00"))
)
pivot_events_longer(wide, case_col = "case_id",
                     time_cols = c("arrival_time", "discharge_time"),
                     location_cols = c("arrival_time", "discharge_time"))
#> # A tibble: 4 × 4
#>   case_id timestamp           act_type      activity 
#>   <chr>   <dttm>              <chr>         <chr>    
#> 1 A       2024-01-01 08:00:00 location_move Arrival  
#> 2 A       2024-01-01 12:00:00 location_move Discharge
#> 3 B       2024-01-01 09:00:00 location_move Arrival  
#> 4 B       2024-01-01 14:00:00 location_move Discharge
```
