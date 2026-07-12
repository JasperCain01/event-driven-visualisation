# Plot a single case's timeline stacked above its per-state duration summary

\`patchwork\`-stacks a single case's timeline (\[plot_case_timeline()\])
above a bar chart of that case's per-state dwell. Requires the
\`patchwork\` package (Suggests only).

## Usage

``` r
plot_case_timeline_with_summary(
  data,
  case_id = NULL,
  state_events,
  heights = c(2, 1),
  ...
)
```

## Arguments

- data:

  A data frame or tibble containing the event log.

- case_id:

  The single case identifier to visualise, or \`NULL\` — see
  \[plot_case_timeline()\] for the resolution rules.

- state_events:

  Character vector of \`act_type\` values that open a state. Required —
  no default; see \[plot_case_timeline()\] for the discovery-error
  behaviour when omitted.

- heights:

  Relative heights \`c(timeline, bars)\` passed to
  \`patchwork::wrap_plots()\`.

- ...:

  Additional arguments forwarded to \[plot_case_timeline()\].

## Value

A \`patchwork\` object.

## Examples

``` r
# \donttest{
if (requireNamespace("patchwork", quietly = TRUE)) {
  plot_case_timeline_with_summary(
    example_journey,
    state_events = c("location_move", "ed_location_move")
  )
}
#> ℹ `case_id` not supplied; using the only case "SP-001".

# }
```
