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
