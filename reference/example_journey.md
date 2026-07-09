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

A tibble with columns \`caseID\`, \`K_Number\`, \`timestamp\`,
\`act_type\`, \`activity\`.

## Examples

``` r
plot_patient_journey(example_journey, case_id = "SP-001")

```
