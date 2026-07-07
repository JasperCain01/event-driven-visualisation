# schema.R — Column-name schema object and autodetection
#
# event_log_schema() is a lightweight classed list describing how an event
# log's columns map onto the roles plot_patient_journey() needs (time, case,
# act_type, activity, patient — plus location_categories). autodetect_schema()
# builds one automatically from column names, using ordered, mutually
# exclusive resolution so a single ambiguous column is never silently claimed
# by two roles.
#
# Source order: after utils.R (uses none of its helpers directly, but sits
# alongside validate.R/transform.R in the pipeline).


# ── Constructor ──────────────────────────────────────────────────────────────

# Every field defaults to NULL ("not part of this schema"). When wired into
# plot_patient_journey() via its `schema` argument, a NULL field simply falls
# through to that function's own hardcoded default — and an explicitly
# supplied individual argument always wins over the schema regardless.
event_log_schema <- function(time_col = NULL, act_type_col = NULL,
                             activity_col = NULL, case_col = NULL,
                             patient_col = NULL, location_categories = NULL) {
  structure(
    list(
      time_col            = time_col,
      act_type_col        = act_type_col,
      activity_col        = activity_col,
      case_col            = case_col,
      patient_col         = patient_col,
      location_categories = location_categories
    ),
    class = "event_log_schema"
  )
}

print.event_log_schema <- function(x, ...) {
  field_line <- function(label, value) {
    shown <- if (is.null(value)) "<not set>" else paste(value, collapse = ", ")
    cli::cli_text("{.strong {label}}: {shown}")
  }
  cli::cli_h3("<event_log_schema>")
  field_line("time_col", x$time_col)
  field_line("act_type_col", x$act_type_col)
  field_line("activity_col", x$activity_col)
  field_line("case_col", x$case_col)
  field_line("patient_col", x$patient_col)
  field_line("location_categories", x$location_categories)
  invisible(x)
}


# ── Candidate name lists (case-insensitive) ──────────────────────────────────

.schema_candidates <- list(
  time_col     = c("timestamp", "time", "ts", "datetime", "date_time",
                   "event_time", "event_time_stamp"),
  case_col     = c("case_id", "caseid", "case", "spell_id", "episode_id",
                   "encounter_id", "complaint_id", "ticket_id"),
  act_type_col = c("act_type", "event_type", "category", "type",
                   "event_category"),
  activity_col = c("activity", "label", "description", "event_name", "name"),
  patient_col  = c("patient_id", "patient", "k_number", "mrn", "person_id")
)

# Fixed resolution order: required roles first (time -> case -> act_type ->
# activity), patient last since it's the one optional role.
.schema_role_order <- c("time_col", "case_col", "act_type_col",
                        "activity_col", "patient_col")


# ── Per-role resolution ───────────────────────────────────────────────────────

# Resolve one role against the still-unclaimed columns. Exact case-insensitive
# matches are tried first; only if none exist does a fuzzy (adist <= 2) pass
# run. Returns a list with exactly one of:
#   $column, $method  — the single resolved column name ("exact" or "fuzzy")
#   $tie              — >= 2 columns that tied for this role at the same tier
#   NULL              — no candidate found at all
.resolve_schema_role <- function(candidates, unclaimed) {
  if (length(unclaimed) == 0) return(NULL)

  exact_hits <- unclaimed[tolower(unclaimed) %in% tolower(candidates)]
  if (length(exact_hits) == 1) return(list(column = exact_hits, method = "exact"))
  if (length(exact_hits) > 1)  return(list(tie = exact_hits))

  dists    <- adist(unclaimed, candidates, ignore.case = TRUE)
  best     <- apply(dists, 1, min)
  eligible <- best <= 2
  if (!any(eligible)) return(NULL)

  min_dist <- min(best[eligible])
  winners  <- unclaimed[eligible & best == min_dist]

  if (length(winners) == 1) return(list(column = winners, method = "fuzzy"))
  list(tie = winners)
}


# ── autodetect_schema ─────────────────────────────────────────────────────────

# Build an event_log_schema by matching data's column names against the
# per-role candidate lists above. Roles are resolved in a fixed order and
# each data column may be claimed by at most one role — once claimed, it is
# removed from consideration for every later role.
#
# location_categories is a pure passthrough into the returned schema: this
# function detects *columns*, not the act_type values within them.
autodetect_schema <- function(data, location_categories = NULL) {
  if (!is.data.frame(data)) {
    cli::cli_abort(c(
      "{.arg data} must be a data frame or tibble.",
      "x" = "You supplied an object of class {.cls {class(data)}}."
    ))
  }

  unclaimed <- names(data)
  resolved  <- list()
  methods   <- list()

  for (role in .schema_role_order) {
    hit <- .resolve_schema_role(.schema_candidates[[role]], unclaimed)

    if (!is.null(hit$tie)) {
      cli::cli_abort(c(
        "Column autodetection is ambiguous for {.field {role}}.",
        "x" = "{.val {hit$tie}} are equally good matches.",
        "i" = "Supply an explicit {.fn event_log_schema} instead of relying
               on autodetection."
      ))
    }

    if (!is.null(hit)) {
      resolved[[role]] <- hit$column
      methods[[role]]  <- hit$method
      unclaimed        <- setdiff(unclaimed, hit$column)
    }
  }

  required      <- setdiff(.schema_role_order, "patient_col")
  missing_roles <- required[!vapply(required, function(r) !is.null(resolved[[r]]), logical(1))]

  if (length(missing_roles) > 0) {
    cli::cli_abort(c(
      "Could not autodetect column(s) for: {.field {missing_roles}}.",
      "x" = "Columns available to match against: {.val {names(data)}}",
      "i" = "Supply an explicit {.fn event_log_schema} for the field(s)
             autodetection could not resolve."
    ))
  }

  for (role in .schema_role_order) {
    if (!is.null(resolved[[role]])) {
      cli::cli_inform(c(
        "i" = "Autodetected {.field {role}} = {.val {resolved[[role]]}} ({methods[[role]]} match)."
      ))
    }
  }

  event_log_schema(
    time_col            = resolved$time_col,
    act_type_col        = resolved$act_type_col,
    activity_col        = resolved$activity_col,
    case_col            = resolved$case_col,
    patient_col         = resolved$patient_col,
    location_categories = location_categories
  )
}
