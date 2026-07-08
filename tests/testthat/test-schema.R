# test-schema.R — Tests for event_log_schema() / autodetect_schema() and
# their wiring into plot_patient_journey().
#
# Run with: testthat::test_file("tests/testthat/test-schema.R")

library(testthat)
library(dplyr)
library(ggplot2)

# ── Construction / print ─────────────────────────────────────────────────────

test_that("event_log_schema() constructs a classed list with the given fields", {
  s <- event_log_schema(time_col = "ts", case_col = "case_id")
  expect_s3_class(s, "event_log_schema")
  expect_equal(s$time_col, "ts")
  expect_equal(s$case_col, "case_id")
  expect_null(s$act_type_col)
  expect_null(s$patient_col)
})

test_that("print.event_log_schema() reports every field", {
  s <- event_log_schema(time_col = "ts", location_categories = c("move"))
  # cli writes straight to the console rather than through a connection
  # capture.output() can intercept; cli_fmt() is the documented way to
  # capture cli-rendered text programmatically.
  txt <- paste(cli::cli_fmt(print(s)), collapse = "\n")
  expect_match(txt, "time_col")
  expect_match(txt, "ts")
  expect_match(txt, "location_categories")
  expect_match(txt, "<not set>")   # act_type_col etc. are unset
})

# ── autodetect_schema(): exact + fuzzy recovery ──────────────────────────────

test_that("autodetect_schema() resolves exact-match columns", {
  s <- suppressMessages(autodetect_schema(example_journey))
  expect_equal(s$time_col, "timestamp")
  expect_equal(s$act_type_col, "act_type")
  expect_equal(s$activity_col, "activity")
  expect_equal(tolower(s$case_col), "caseid")
  expect_equal(tolower(s$patient_col), "k_number")
})

test_that("autodetect_schema() recovers renamed (typo'd) columns via fuzzy match", {
  renamed <- example_journey |>
    dplyr::rename(case_idx = caseID, act_typ = act_type, activty = activity,
                  K_Numbr = K_Number)

  msgs <- capture_messages(s <- autodetect_schema(renamed))

  expect_equal(s$time_col, "timestamp")     # still exact
  expect_equal(s$case_col, "case_idx")      # fuzzy: adist("case_idx","case_id") == 1
  expect_equal(s$act_type_col, "act_typ")   # fuzzy: adist("act_typ","act_type") == 1
  expect_equal(s$activity_col, "activty")   # fuzzy: adist("activty","activity") == 1
  expect_equal(s$patient_col, "K_Numbr")    # fuzzy: adist("K_Numbr","k_number") == 1

  expect_true(any(grepl("fuzzy match", msgs)))
  expect_true(any(grepl("exact match", msgs)))
})

test_that("location_categories is a pure passthrough", {
  s <- suppressMessages(autodetect_schema(example_journey, location_categories = c("a", "b")))
  expect_equal(s$location_categories, c("a", "b"))
})

# ── autodetect_schema(): ties abort ──────────────────────────────────────────

test_that("two equally-good exact matches for one role abort naming both", {
  data <- tibble::tibble(
    time      = as.POSIXct("2024-01-01", tz = "UTC"),
    timestamp = as.POSIXct("2024-01-01", tz = "UTC"),
    case_id   = "C1",
    act_type  = "location_move",
    activity  = "A"
  )
  err <- expect_error(autodetect_schema(data))
  expect_match(conditionMessage(err), "time")
  expect_match(conditionMessage(err), "ambiguous")
})

# ── autodetect_schema(): nonsense columns abort naming the role ─────────────

test_that("columns with no plausible match abort, naming the unresolved role(s)", {
  data <- tibble::tibble(
    zzz1 = "C1",
    zzz2 = as.POSIXct("2024-01-01", tz = "UTC"),
    zzz3 = "loc",
    zzz4 = "x"
  )
  err <- expect_error(autodetect_schema(data))
  msg <- conditionMessage(err)
  expect_match(msg, "event_log_schema")
})

# ── Claimed-column exclusivity ───────────────────────────────────────────────

test_that("a column claimed by an earlier role is not reconsidered by a later role", {
  # "event_time" exactly matches the time_col candidate list and is also a
  # near match (adist == 2) for activity_col's "event_name" candidate. With
  # claimed-column exclusivity enforced, it is consumed by time_col only —
  # so activity_col, which has no other candidate here, must fail to
  # resolve rather than silently reusing "event_time".
  data <- tibble::tibble(
    case_id    = c("C1", "C1"),
    event_time = as.POSIXct(c("2024-01-01 08:00", "2024-01-01 09:00"), tz = "UTC"),
    act_type   = c("location_move", "location_move")
  )
  err <- expect_error(autodetect_schema(data))
  expect_match(conditionMessage(err), "activity_col")
})

# ── Wiring into plot_patient_journey(): schema = "auto" ──────────────────────

test_that("schema = \"auto\" autodetects and renders successfully", {
  p <- suppressMessages(plot_patient_journey(example_journey, case_id = "SP-001", schema = "auto"))
  expect_s3_class(p, "ggplot")
  expect_no_warning(ggplot2::ggplot_build(p))
})

test_that("schema is never autodetected unless the literal sentinel \"auto\" is used", {
  # Passing an event_log_schema() object must not trigger autodetection —
  # only unresolved fields are used, and only the ones explicitly present.
  s <- event_log_schema(time_col = "timestamp", act_type_col = "act_type",
                        activity_col = "activity", case_col = "caseID",
                        patient_col = "K_Number")
  expect_no_error(
    suppressMessages(plot_patient_journey(example_journey, case_id = "SP-001", schema = s))
  )
})

# ── Per-field precedence ──────────────────────────────────────────────────────

make_precedence_fixture <- function() {
  ts_val     <- as.POSIXct("2024-01-01 08:00:00", tz = "UTC")
  mytime_val <- as.POSIXct("2024-06-01 08:00:00", tz = "UTC")
  tibble::tibble(
    case_id  = c("C1", "C1"),
    ts       = c(ts_val, ts_val + 3600),
    mytime   = c(mytime_val, mytime_val + 3600),
    act_type = c("location_move", "location_move"),
    activity = c("A", "B")
  )
}

test_that("an explicit individual argument beats the schema", {
  data   <- make_precedence_fixture()
  # Schema deliberately points act_type_col at a non-existent column; if the
  # schema field won instead of the explicit argument, validation would
  # abort on a missing column.
  schema <- event_log_schema(act_type_col = "does_not_exist")

  expect_no_error(
    plot_patient_journey(
      data, case_id = "C1", schema = schema, act_type_col = "act_type",
      case_col = "case_id", time_col = "ts", patient_col = NULL
    )
  )
})

test_that("an omitted argument falls through to the schema field", {
  data   <- make_precedence_fixture()
  schema <- event_log_schema(time_col = "mytime")

  result <- plot_patient_journey(
    data, case_id = "C1", schema = schema,
    case_col = "case_id", act_type_col = "act_type", patient_col = NULL,
    return_data = TRUE
  )
  # time_col was omitted, so the schema's "mytime" column must have been
  # used, not the hardcoded default "timestamp" (which doesn't even exist
  # in this fixture — using it would have aborted) nor the fixture's other
  # candidate time column "ts".
  expect_equal(min(result$boxes$xmin), as.POSIXct("2024-06-01 08:00:00", tz = "UTC"))
})

test_that("patient_col = NULL explicitly requested is honoured even with a schema present", {
  data   <- make_precedence_fixture()
  schema <- event_log_schema(patient_col = "does_not_exist", time_col = "ts")

  expect_no_error(
    plot_patient_journey(
      data, case_id = "C1", schema = schema, patient_col = NULL,
      case_col = "case_id", act_type_col = "act_type"
    )
  )
})

# ── Earlier suites pass untouched with no schema argument ───────────────────

test_that("plot_patient_journey() works exactly as before with no schema argument", {
  p <- plot_patient_journey(example_journey, case_id = "SP-001")
  expect_s3_class(p, "ggplot")
  expect_no_warning(ggplot2::ggplot_build(p))
})
