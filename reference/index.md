# Package index

## Plot a single case

Visualise one case’s event log as a location-band timeline or, for a
strictly linear process, a staircase diagram.

- [`plot_patient_journey()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_patient_journey.md)
  : Visualise an event log as a location-band timeline
- [`plot_stage_ladder()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_stage_ladder.md)
  : Visualise a linear stage process as a staircase
- [`plot_journey_with_summary()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_journey_with_summary.md)
  : Plot a single case's timeline stacked above its per-stage duration
  summary

## Compare a cohort

Facet several cases at once, or reduce a cohort to statistics.

- [`plot_journey_cohort()`](https://jaspercain01.github.io/event-driven-visualisation/reference/plot_journey_cohort.md)
  : Visualise several cases as a faceted small-multiples grid
- [`summarise_journey_durations()`](https://jaspercain01.github.io/event-driven-visualisation/reference/summarise_journey_durations.md)
  : Summarise per-stay durations across a cohort
- [`summarise_stage_durations()`](https://jaspercain01.github.io/event-driven-visualisation/reference/summarise_stage_durations.md)
  : Summarise per-location duration statistics across a cohort
- [`summarise_breach_rate()`](https://jaspercain01.github.io/event-driven-visualisation/reference/summarise_breach_rate.md)
  : Summarise breach rate against a target duration
- [`summarise_transitions()`](https://jaspercain01.github.io/event-driven-visualisation/reference/summarise_transitions.md)
  : Summarise directed location-to-location transitions across a cohort
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

- [`theme_journey()`](https://jaspercain01.github.io/event-driven-visualisation/reference/theme_journey.md)
  : Shared base ggplot2 theme for eventviz renderers

## Example datasets

- [`example_journey`](https://jaspercain01.github.io/event-driven-visualisation/reference/example_journey.md)
  : A synthetic patient journey event log
- [`complaint_example`](https://jaspercain01.github.io/event-driven-visualisation/reference/complaint_example.md)
  : A synthetic complaint-handling event log
- [`support_ticket_example`](https://jaspercain01.github.io/event-driven-visualisation/reference/support_ticket_example.md)
  : A synthetic support-ticket event log
