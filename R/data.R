# data.R — Documentation for the package's example datasets.
#
# The datasets themselves live in data/ as lazy-loaded .rda files; they are
# built by the scripts in data-raw/ (one per dataset — rerun those to
# regenerate after an edit). This file holds only their roxygen docs.

#' A synthetic patient journey event log
#'
#' A representative event log for a single patient spell, following
#' Ambulance arrival -> ED -> Acute Medical Unit -> Discharge Lounge ->
#' Discharged. Mixed in are clinical point events (`obs`, assessments,
#' tests, doctor reviews) to exercise the instantaneous-event rendering.
#'
#' @format A tibble with columns `caseID`, `K_Number`, `timestamp`,
#'   `act_type`, `activity`.
#'
#' @examples
#' plot_patient_journey(example_journey, case_id = "SP-001")
#'
"example_journey"

#' A synthetic complaint-handling event log
#'
#' A deliberately non-spatial event log (eight complaints, each moving
#' through the fixed stages Acknowledgement -> Triage -> Assigned -> Under
#' review -> Senior review -> Formal letter sent, recorded as
#' `act_type = "stage_change"`), used to exercise the linear stage-process
#' features (`patient_col = NULL`, [plot_stage_ladder()]). Sprinkled point
#' events (`contact`, `escalation`, `evidence_received`) exercise the
#' instantaneous-event path. Complaint `"CMP-03"` stalls about three weeks in
#' "Under review" (a per-stage breach); `"CMP-04"` is still open and never
#' reaches the formal letter, exercising the ongoing-spell indication.
#'
#' @format A tibble with columns `complaint_id`, `timestamp`, `act_type`,
#'   `activity`.
#'
#' @examples
#' plot_patient_journey(
#'   complaint_example, case_id = "CMP-01",
#'   location_categories = "stage_change", case_col = "complaint_id",
#'   patient_col = NULL, terminal_activities = "Formal letter sent",
#'   state_label = "Stage"
#' )
#' plot_stage_ladder(
#'   complaint_example, case_id = "CMP-01",
#'   stage_categories = "stage_change", case_col = "complaint_id"
#' )
"complaint_example"

#' A synthetic support-ticket event log
#'
#' Stage 8's third example dataset: it proves the package leaves the
#' healthcare/NHS sector entirely (`complaint_example` is still
#' NHS-adjacent). Six support tickets moving through the fixed statuses
#' Open -> Assigned -> In Progress -> Waiting on Customer -> Resolved ->
#' Closed, recorded as `act_type = "status_change"`. Sprinkled point events
#' (`comment_added`, `priority_changed`, `reassigned`, `sla_warning`)
#' exercise the instantaneous-event path. There is deliberately no patient
#' column, mirroring `complaint_example`. `"TCK-03"` stalls for days in
#' "Waiting on Customer" (a per-stage breach) and `"TCK-04"` is still open,
#' exercising the ongoing-spell indication.
#'
#' @format A tibble with columns `ticket_id`, `timestamp`, `act_type`,
#'   `activity`.
#'
#' @examples
#' plot_patient_journey(
#'   support_ticket_example, case_id = "TCK-01",
#'   location_categories = "status_change", case_col = "ticket_id",
#'   patient_col = NULL, terminal_activities = "Closed",
#'   state_label = "Status"
#' )
#'
"support_ticket_example"
