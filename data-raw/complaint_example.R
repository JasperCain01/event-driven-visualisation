# data-raw/complaint_example.R — builds the `complaint_example` dataset.
#
# A deliberately non-spatial event log (Stage 5b): eight complaints, each moving
# through the fixed stages
#   Acknowledgement -> Triage -> Assigned -> Under review -> Senior review
#     -> Formal letter sent
# recorded as `act_type = "stage_change"` (the activity holds the stage name).
# Sprinkled point events (`contact`, `escalation`, `evidence_received`) exercise
# the instantaneous-event path. There is deliberately NO patient column — this
# dataset exercises `patient_col = NULL`.
#
# Two cases are intentionally awkward: CMP-03 stalls ~3 weeks in "Under review"
# (a per-stage breach), and CMP-04 is still open — it never reaches the formal
# letter, so with `terminal_activities = "Formal letter sent"` it exercises the
# ongoing-spell (Stage 1c) indication.
#
# Regenerate with: source("data-raw/complaint_example.R")

make_complaint_example <- function() {

  base_time <- as.POSIXct("2025-01-06 09:00:00", tz = "Europe/London")
  d <- function(days) base_time + days * 86400   # offset in days (fractional ok)

  # complaint_id, day-offset, act_type, activity
  raw <- tibble::tribble(
    ~complaint_id, ~day, ~act_type,            ~activity,
    # ── CMP-01 — standard full journey ─────────────────────────────────────────
    "CMP-01", 0.0,  "stage_change",       "Acknowledgement",
    "CMP-01", 0.2,  "contact",            "Phone call to complainant",
    "CMP-01", 1.0,  "stage_change",       "Triage",
    "CMP-01", 2.0,  "stage_change",       "Assigned",
    "CMP-01", 2.5,  "evidence_received",  "Case notes received",
    "CMP-01", 3.0,  "stage_change",       "Under review",
    "CMP-01", 6.0,  "stage_change",       "Senior review",
    "CMP-01", 8.0,  "stage_change",       "Formal letter sent",

    # ── CMP-02 — fast turnaround ────────────────────────────────────────────────
    "CMP-02", 0.0,  "stage_change",       "Acknowledgement",
    "CMP-02", 0.5,  "stage_change",       "Triage",
    "CMP-02", 1.0,  "stage_change",       "Assigned",
    "CMP-02", 1.5,  "stage_change",       "Under review",
    "CMP-02", 3.0,  "stage_change",       "Senior review",
    "CMP-02", 4.0,  "stage_change",       "Formal letter sent",

    # ── CMP-03 — stalls ~3 weeks in Under review ────────────────────────────────
    "CMP-03", 0.0,  "stage_change",       "Acknowledgement",
    "CMP-03", 1.0,  "stage_change",       "Triage",
    "CMP-03", 2.0,  "stage_change",       "Assigned",
    "CMP-03", 2.5,  "escalation",         "Complainant chases for update",
    "CMP-03", 3.0,  "stage_change",       "Under review",
    "CMP-03", 24.0, "stage_change",       "Senior review",
    "CMP-03", 26.0, "stage_change",       "Formal letter sent",

    # ── CMP-04 — still open (never reaches the letter) ──────────────────────────
    "CMP-04", 0.0,  "stage_change",       "Acknowledgement",
    "CMP-04", 1.0,  "stage_change",       "Triage",
    "CMP-04", 2.0,  "stage_change",       "Assigned",
    "CMP-04", 2.5,  "evidence_received",  "Statements collected",
    "CMP-04", 4.0,  "stage_change",       "Under review",

    # ── CMP-05 — escalated mid-review ───────────────────────────────────────────
    "CMP-05", 0.0,  "stage_change",       "Acknowledgement",
    "CMP-05", 0.3,  "contact",            "Acknowledgement email sent",
    "CMP-05", 2.0,  "stage_change",       "Triage",
    "CMP-05", 3.0,  "stage_change",       "Assigned",
    "CMP-05", 4.0,  "stage_change",       "Under review",
    "CMP-05", 5.0,  "escalation",         "Escalated to service lead",
    "CMP-05", 7.0,  "stage_change",       "Senior review",
    "CMP-05", 9.0,  "stage_change",       "Formal letter sent",

    # ── CMP-06 — quick close ────────────────────────────────────────────────────
    "CMP-06", 0.0,  "stage_change",       "Acknowledgement",
    "CMP-06", 1.0,  "stage_change",       "Triage",
    "CMP-06", 2.0,  "stage_change",       "Assigned",
    "CMP-06", 3.0,  "stage_change",       "Under review",
    "CMP-06", 5.0,  "stage_change",       "Senior review",
    "CMP-06", 6.0,  "stage_change",       "Formal letter sent",

    # ── CMP-07 — evidence-heavy ─────────────────────────────────────────────────
    "CMP-07", 0.0,  "stage_change",       "Acknowledgement",
    "CMP-07", 0.5,  "contact",            "Complainant called",
    "CMP-07", 1.5,  "stage_change",       "Triage",
    "CMP-07", 2.5,  "stage_change",       "Assigned",
    "CMP-07", 3.0,  "evidence_received",  "GP records received",
    "CMP-07", 4.0,  "stage_change",       "Under review",
    "CMP-07", 7.0,  "stage_change",       "Senior review",
    "CMP-07", 10.0, "stage_change",       "Formal letter sent",

    # ── CMP-08 — long overall, MP involvement ───────────────────────────────────
    "CMP-08", 0.0,  "stage_change",       "Acknowledgement",
    "CMP-08", 2.0,  "stage_change",       "Triage",
    "CMP-08", 4.0,  "stage_change",       "Assigned",
    "CMP-08", 5.0,  "stage_change",       "Under review",
    "CMP-08", 9.0,  "escalation",         "MP involvement noted",
    "CMP-08", 11.0, "stage_change",       "Senior review",
    "CMP-08", 14.0, "stage_change",       "Formal letter sent"
  )

  raw |>
    dplyr::mutate(timestamp = d(day)) |>
    dplyr::select(complaint_id, timestamp, act_type, activity)
}

complaint_example <- make_complaint_example()

usethis::use_data(complaint_example, overwrite = TRUE)
