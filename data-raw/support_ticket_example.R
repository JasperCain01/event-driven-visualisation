# data-raw/support_ticket_example.R — builds the `support_ticket_example`
# dataset.
#
# Stage 8's third dataset: it proves the package leaves the healthcare/NHS
# sector entirely (complaint_example is still NHS-adjacent). Six support
# tickets moving through the fixed statuses
#   Open -> Assigned -> In Progress -> Waiting on Customer -> Resolved -> Closed
# recorded as `act_type = "status_change"` (the activity holds the status
# name). Sprinkled point events (`comment_added`, `priority_changed`,
# `reassigned`, `sla_warning`) exercise the instantaneous-event path. There is
# deliberately NO patient column, mirroring `complaint_example`.
#
# TCK-03 stalls for days in "Waiting on Customer" (a per-stage breach) and
# TCK-04 is still open — it never reaches "Closed", exercising the
# ongoing-spell (Stage 1c) indication.
#
# Regenerate with: source("data-raw/support_ticket_example.R")

make_support_ticket_example <- function() {

  base_time <- as.POSIXct("2025-02-03 09:00:00", tz = "Europe/London")
  h <- function(hours) base_time + hours * 3600   # offset in hours (fractional ok)

  # ticket_id, hour-offset, act_type, activity
  raw <- tibble::tribble(
    ~ticket_id, ~hour, ~act_type,          ~activity,
    # ── TCK-01 — standard full lifecycle ────────────────────────────────────────
    "TCK-01", 0.0,   "status_change",  "Open",
    "TCK-01", 0.5,   "comment_added",  "Customer added reproduction steps",
    "TCK-01", 2.0,   "status_change",  "Assigned",
    "TCK-01", 3.0,   "status_change",  "In Progress",
    "TCK-01", 6.0,   "comment_added",  "Engineer requests logs",
    "TCK-01", 8.0,   "status_change",  "Waiting on Customer",
    "TCK-01", 30.0,  "comment_added",  "Customer supplies logs",
    "TCK-01", 31.0,  "status_change",  "In Progress",
    "TCK-01", 40.0,  "status_change",  "Resolved",
    "TCK-01", 48.0,  "status_change",  "Closed",

    # ── TCK-02 — fast turnaround ─────────────────────────────────────────────────
    "TCK-02", 0.0,  "status_change",  "Open",
    "TCK-02", 1.0,  "status_change",  "Assigned",
    "TCK-02", 1.5,  "status_change",  "In Progress",
    "TCK-02", 4.0,  "status_change",  "Resolved",
    "TCK-02", 6.0,  "status_change",  "Closed",

    # ── TCK-03 — stalls days in Waiting on Customer ─────────────────────────────
    "TCK-03", 0.0,   "status_change",   "Open",
    "TCK-03", 1.0,   "status_change",   "Assigned",
    "TCK-03", 2.0,   "status_change",   "In Progress",
    "TCK-03", 5.0,   "priority_changed", "Priority raised to High",
    "TCK-03", 6.0,   "status_change",   "Waiting on Customer",
    "TCK-03", 150.0, "status_change",   "In Progress",
    "TCK-03", 152.0, "status_change",   "Resolved",
    "TCK-03", 154.0, "status_change",   "Closed",

    # ── TCK-04 — still open (never reaches Closed) ──────────────────────────────
    "TCK-04", 0.0,  "status_change",  "Open",
    "TCK-04", 0.5,  "sla_warning",    "First-response SLA at risk",
    "TCK-04", 2.0,  "status_change",  "Assigned",
    "TCK-04", 3.0,  "status_change",  "In Progress",
    "TCK-04", 5.0,  "comment_added",  "Engineer investigating",

    # ── TCK-05 — reassigned mid-flight, SLA warning ──────────────────────────────
    "TCK-05", 0.0,  "status_change",   "Open",
    "TCK-05", 1.0,  "status_change",   "Assigned",
    "TCK-05", 2.0,  "status_change",   "In Progress",
    "TCK-05", 5.0,  "reassigned",      "Reassigned to platform team",
    "TCK-05", 6.0,  "sla_warning",     "Resolution SLA at risk",
    "TCK-05", 10.0, "status_change",   "Waiting on Customer",
    "TCK-05", 20.0, "status_change",   "In Progress",
    "TCK-05", 24.0, "status_change",   "Resolved",
    "TCK-05", 28.0, "status_change",   "Closed",

    # ── TCK-06 — quick close ──────────────────────────────────────────────────────
    "TCK-06", 0.0,  "status_change",  "Open",
    "TCK-06", 1.0,  "status_change",  "Assigned",
    "TCK-06", 2.0,  "status_change",  "In Progress",
    "TCK-06", 3.0,  "status_change",  "Resolved",
    "TCK-06", 4.0,  "status_change",  "Closed"
  )

  raw |>
    dplyr::mutate(timestamp = h(hour)) |>
    dplyr::select(ticket_id, timestamp, act_type, activity)
}

support_ticket_example <- make_support_ticket_example()

usethis::use_data(support_ticket_example, overwrite = TRUE)
