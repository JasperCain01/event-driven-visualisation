# Package index

## Plot a single case

Visualise one case’s event log as a state-band timeline or, for a
strictly linear process, a staircase diagram.

- [`plot_case_timeline()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_case_timeline.md)
  : Visualise an event log as a state-band timeline
- [`plot_stage_ladder()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_stage_ladder.md)
  : Visualise a linear stage process as a staircase
- [`plot_case_timeline_with_summary()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_case_timeline_with_summary.md)
  : Plot a single case's timeline stacked above its per-state duration
  summary

## Compare a cohort

Facet several cases at once, or reduce a cohort to statistics.

- [`plot_cohort_timeline()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_cohort_timeline.md)
  : Visualise several cases as a faceted small-multiples grid
- [`summarise_case_durations()`](https://jaspercain01.github.io/event-driven-visualisation/reference/summarise_case_durations.md)
  : Summarise per-stay durations across a cohort
- [`summarise_state_durations()`](https://jaspercain01.github.io/event-driven-visualisation/reference/summarise_state_durations.md)
  : Summarise per-state duration statistics across a cohort
- [`summarise_breach_rate()`](https://jaspercain01.github.io/event-driven-visualisation/reference/summarise_breach_rate.md)
  : Summarise breach rate against a target duration
- [`summarise_transitions()`](https://jaspercain01.github.io/event-driven-visualisation/reference/summarise_transitions.md)
  : Summarise directed state-to-state transitions across a cohort
- [`plot_transition_summary()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_transition_summary.md)
  : Plot a directed transition-flow diagram for a cohort

## Adapt your data

Get your own event log into the shape eventviz expects.

- [`pivot_events_longer()`](https://jaspercain01.github.io/event-driven-visualisation/reference/pivot_events_longer.md)
  : Pivot a wide milestone-timestamp event log into long form
- [`event_log_schema()`](https://jaspercain01.github.io/event-driven-visualisation/reference/event_log_schema.md)
  : Construct an event log column-name schema
- [`autodetect_schema()`](https://jaspercain01.github.io/event-driven-visualisation/reference/autodetect_schema.md)
  : Autodetect an event log's column schema
- [`print(`*`<event_log_schema>`*`)`](https://jaspercain01.github.io/event-driven-visualisation/reference/print.event_log_schema.md)
  : Print an event_log_schema object

## Theming

- [`theme_timeline()`](https://jaspercain01.github.io/event-driven-visualisation/reference/theme_timeline.md)
  : Shared base ggplot2 theme for eventviz renderers

## Example datasets

- [`example_journey`](https://jaspercain01.github.io/event-driven-visualisation/reference/example_journey.md)
  : A synthetic patient journey event log
- [`complaint_example`](https://jaspercain01.github.io/event-driven-visualisation/reference/complaint_example.md)
  : A synthetic complaint-handling event log
- [`support_ticket_example`](https://jaspercain01.github.io/event-driven-visualisation/reference/support_ticket_example.md)
  : A synthetic support-ticket event log
