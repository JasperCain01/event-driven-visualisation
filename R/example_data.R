# example_data.R — Synthetic patient journey dataset
#
# Creates `example_journey`, a representative event log for a single patient
# spell. The journey follows: Ambulance arrival → ED → Ward → Discharge Lounge
# → Discharge. Mixed in are clinical events (obs, assessments, tests, dr visits)
# to exercise the instantaneous-event rendering.
#
# Usage:
#   source("R/example_data.R")
#   plot_patient_journey(example_journey, case_id = "SP-001")

make_example_journey <- function() {

  base_time <- as.POSIXct("2024-03-15 08:30:00", tz = "Europe/London")

  # Helper: offset from base in hours (fractional ok)
  t <- function(hours) base_time + hours * 3600

  tibble::tribble(
    ~caseID,   ~timestamp,    ~act_type,           ~activity,
    # ── Arrival ───────────────────────────────────────────────────────────────
    "SP-001",  t(0.00),  "ed_location_move",  "Emergency Department",
    "SP-001",  t(0.10),  "clerk_review",       "Ambulance handover documented",
    "SP-001",  t(0.25),  "triage",             "Triage complete - Category 2",

    # ── ED assessments ───────────────────────────────────────────────────────
    "SP-001",  t(0.75),  "obs",                "BP 145/90, HR 88, SpO2 97%",
    "SP-001",  t(1.00),  "clerk_review",       "Initial nursing assessment",
    "SP-001",  t(1.25),  "test_ordered",       "FBC, U&E, CRP, Troponin",
    "SP-001",  t(1.50),  "test_ordered",       "ECG",
    "SP-001",  t(1.75),  "obs",                "ECG completed",
    "SP-001",  t(2.25),  "clerk_review",       "Dr review — query ACS",
    "SP-001",  t(2.50),  "test_ordered",       "Chest X-Ray",
    "SP-001",  t(3.00),  "obs",                "Repeat troponin",
    "SP-001",  t(3.50),  "clerk_review",       "Cardiology consult requested",
    "SP-001",  t(4.00),  "home_today_change",  "No",
    "SP-001",  t(4.25),  "clerk_review",       "Decision to admit — AMU",

    # ── Transfer to ward ─────────────────────────────────────────────────────
    "SP-001",  t(4.75),  "location_move",      "Acute Medical Unit",
    "SP-001",  t(5.00),  "obs",                "Ward admission obs",
    "SP-001",  t(5.50),  "clerk_review",       "Admitting doctor review",
    "SP-001",  t(6.00),  "test_ordered",       "Echo booked",

    # ── Overnight ward ───────────────────────────────────────────────────────
    "SP-001",  t(10.0),  "obs",                "Evening obs — stable",
    "SP-001",  t(14.0),  "obs",                "Night obs — stable",
    "SP-001",  t(18.0),  "obs",                "Early morning obs",
    "SP-001",  t(20.0),  "clerk_review",       "Cardiology review",
    "SP-001",  t(21.0),  "test_ordered",       "Echo completed",
    "SP-001",  t(22.0),  "clerk_review",       "Echo reviewed — mild LV impairment",
    "SP-001",  t(24.0),  "obs",                "Midday obs — improving",
    "SP-001",  t(25.0),  "clerk_review",       "Consultant ward round",
    "SP-001",  t(26.0),  "home_today_change",  "Yes",

    # ── Discharge lounge ─────────────────────────────────────────────────────
    "SP-001",  t(27.0),  "location_move",      "Discharge Lounge",
    "SP-001",  t(27.5),  "clerk_review",       "TTOs sent to pharmacy",
    "SP-001",  t(28.5),  "clerk_review",       "Discharge letter dictated",
    "SP-001",  t(29.0),  "obs",                "Final obs pre-discharge",
    "SP-001",  t(30.0),  "clerk_review",       "Pharmacy — drugs dispensed",

    # ── Discharge ────────────────────────────────────────────────────────────
    "SP-001",  t(30.5),  "location_move",      "Discharged"
  ) |>
    dplyr::mutate(K_Number = "K12345", .after = caseID)
}

example_journey <- make_example_journey()


# ── complaint_example — a location-less linear stage process ────────────────────
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
# Usage (band layout):
#   plot_patient_journey(
#     complaint_example, case_id = "CMP-01",
#     location_categories = "stage_change", case_col = "complaint_id",
#     patient_col = NULL, terminal_activities = "Formal letter sent",
#     state_label = "Stage"
#   )
# Usage (staircase layout):
#   plot_stage_ladder(
#     complaint_example, case_id = "CMP-01",
#     stage_categories = "stage_change", case_col = "complaint_id"
#   )
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
