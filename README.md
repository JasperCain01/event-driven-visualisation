
<!-- README.md is generated from README.Rmd. Please edit that file -->

# eventviz

<!-- badges: start -->

[![R-CMD-check](https://github.com/JasperCain01/event-driven-visualisation/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/JasperCain01/event-driven-visualisation/actions/workflows/R-CMD-check.yaml)
[![test-coverage](https://github.com/JasperCain01/event-driven-visualisation/actions/workflows/test-coverage.yaml/badge.svg)](https://github.com/JasperCain01/event-driven-visualisation/actions/workflows/test-coverage.yaml)
<!-- badges: end -->

eventviz visualises any timestamped event log — not just clinical data.
If your data has a case, a timestamp, and a state that case occupies
exclusively over time (a hospital ward, a complaint stage, a
support-ticket status, a pipeline step), eventviz turns it into a
timeline, a staircase diagram, a faceted cohort comparison, or an
aggregate statistical summary, with a colourblind-safe default palette
and an interactive tooltip renderer available on request.

## Installation

eventviz isn’t on CRAN. Install the development version from GitHub:

``` r
# install.packages("pak")
pak::pak("JasperCain01/event-driven-visualisation")
```

## Quick start

The package ships `example_journey`, a synthetic patient spell:
Ambulance arrival -\> Emergency Department -\> Acute Medical Unit -\>
Discharge Lounge -\> Discharged, with clinical point events
(observations, tests, doctor reviews) sprinkled throughout.

``` r
library(eventviz)

plot_patient_journey(example_journey, case_id = "SP-001")
```

<img src="man/figures/README-quick-start-1.png" width="100%" />

Turn on a few opt-in features — duration labels, a target-threshold
line, and terminal-state handling so “Discharged” renders as a marker
rather than an invented multi-hour stay:

``` r
plot_patient_journey(
  example_journey, case_id = "SP-001",
  show_duration        = TRUE,
  terminal_activities  = "Discharged",
  reference_lines      = data.frame(offset_hours = 4, label = "4h target")
)
```

<img src="man/figures/README-quick-start-features-1.png" width="100%" />

## Not just healthcare

Two more example datasets prove the package generalises past clinical
spells: `complaint_example` (an NHS complaint moving through fixed
stages, with no patient column at all) and `support_ticket_example` (a
software support ticket lifecycle — deliberately outside the healthcare
sector entirely).

For a strictly linear process like these, `plot_stage_ladder()` answers
“where does the time go” by putting the stage on the y-axis instead of
x, so the case walks down-and-right like a Gantt chart:

``` r
plot_stage_ladder(
  complaint_example, case_id = "CMP-03",
  stage_categories = "stage_change", case_col = "complaint_id",
  stage_targets    = c("Under review" = 24 * 7)   # a one-week target
)
```

<img src="man/figures/README-staircase-1.png" width="100%" />

`plot_journey_cohort()` compares several cases at once as small
multiples, and `state_label` relabels the fill legend for a non-spatial
process:

``` r
plot_journey_cohort(
  support_ticket_example,
  location_categories = "status_change", case_col = "ticket_id",
  patient_col = NULL, terminal_activities = "Closed", state_label = "Status",
  case_ids = c("TCK-02", "TCK-05", "TCK-06")
)
```

<img src="man/figures/README-cohort-1.png" width="100%" />

## Learn more

- `vignette("getting-started")` — the full clinical walkthrough
- `vignette("adapting-your-data")` — schema autodetection and the
  wide-to-long pivot wrapper, for bringing your own data
- `vignette("linear-processes")` — band vs. staircase for complaints and
  tickets, and per-stage targets
- `vignette("cohort-analysis")` — facets plus
  aggregate/breach/transition summaries across a cohort
