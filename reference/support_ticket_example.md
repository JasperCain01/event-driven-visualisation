# A synthetic support-ticket event log

A third example dataset that leaves the healthcare sector entirely
(\`complaint_example\` is still NHS-adjacent). Six support tickets
moving through the fixed statuses Open -\> Assigned -\> In Progress -\>
Waiting on Customer -\> Resolved -\> Closed, recorded as \`act_type =
"status_change"\`. Sprinkled point events (\`comment_added\`,
\`priority_changed\`, \`reassigned\`, \`sla_warning\`) exercise the
instantaneous-event path. \`"TCK-03"\` stalls for days in "Waiting on
Customer" (a per-state breach) and \`"TCK-04"\` is still open,
exercising the ongoing-case indication.

## Usage

``` r
support_ticket_example
```

## Format

A tibble with columns \`ticket_id\`, \`timestamp\`, \`act_type\`,
\`activity\`.

## Examples

``` r
plot_case_timeline(
  support_ticket_example, case_id = "TCK-01",
  state_events = "status_change", case_col = "ticket_id",
  terminal_activities = "Closed",
  state_label = "Status"
)

```
