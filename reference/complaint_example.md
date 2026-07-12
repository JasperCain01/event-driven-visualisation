# A synthetic complaint-handling event log

A deliberately non-spatial event log (eight complaints, each moving
through the fixed stages Acknowledgement -\> Triage -\> Assigned -\>
Under review -\> Senior review -\> Formal letter sent, recorded as
\`act_type = "stage_change"\`), used to exercise the linear
stage-process features (\[plot_stage_ladder()\]). Sprinkled point events
(\`contact\`, \`escalation\`, \`evidence_received\`) exercise the
instantaneous-event path. Complaint \`"CMP-03"\` stalls about three
weeks in "Under review" (a per-state breach); \`"CMP-04"\` is still open
and never reaches the formal letter, exercising the ongoing-case
indication.

## Usage

``` r
complaint_example
```

## Format

A tibble with columns \`complaint_id\`, \`timestamp\`, \`act_type\`,
\`activity\`.

## Examples

``` r
plot_case_timeline(
  complaint_example, case_id = "CMP-01",
  state_events = "stage_change", case_col = "complaint_id",
  terminal_activities = "Formal letter sent",
  state_label = "Stage"
)

plot_stage_ladder(
  complaint_example, case_id = "CMP-01",
  state_events = "stage_change", case_col = "complaint_id"
)
```
