# A synthetic patient journey event log

A representative event log for a single patient spell, following
Ambulance arrival -\> ED -\> Acute Medical Unit -\> Discharge Lounge -\>
Discharged. Mixed in are clinical point events (\`obs\`, assessments,
tests, doctor reviews) to exercise the instantaneous-event rendering.

## Usage

``` r
example_journey
```

## Format

A tibble with columns \`case_id\`, \`timestamp\`, \`act_type\`,
\`activity\`.

## Examples

``` r
plot_case_timeline(example_journey, state_events = c("location_move", "ed_location_move"))
#> ℹ `case_id` not supplied; using the only case "SP-001".
```
