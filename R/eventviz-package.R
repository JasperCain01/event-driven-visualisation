#' eventviz: Event Log Visualisation
#'
#' A general-purpose package for visualising timestamped event logs as
#' state-band timelines, staircase stage diagrams, cohort facets, and
#' aggregate/statistical summaries. See [plot_case_timeline()] to get
#' started.
#'
#' @keywords internal
#' @importFrom rlang .data
"_PACKAGE"

# Column names referenced as bare symbols inside dplyr/ggplot2 data-masking
# contexts (aes(), filter(), mutate(), ...) throughout the package. These are
# not undefined globals — they're tidy-eval pronouns resolved against a data
# frame at runtime — but R CMD check's static analysis can't tell the
# difference, so they're declared here to silence the NOTE.
utils::globalVariables(c(
  ".env", ".gap", ".gap_span", ".orig_row", ".use",
  "act_type", "activity", "breached",
  "case_end", "case_id", "case_start", "complaint_id",
  "dur_lab", "dur_label", "duration", "duration_secs",
  "dwell_lab", "dwell_secs", "elapsed_hours", "end_inferred",
  "forward", "from_state", "hours",
  "label", "lane", "state",
  "mean_dwell_secs", "mean_step", "n",
  "stage", "step",
  "terminal", "ticket_id", "timestamp", "to_state", "tooltip",
  "x", "x_mid", "xend", "xmax", "xmax_render", "xmin", "xmin_render",
  "y", "y_mid", "yend", "ymax", "ymin"
))
