# utils.R — Internal helper functions shared across the pipeline

# ── Box-end inference ──────────────────────────────────────────────────────────

# Infer the xmax for the final location box, which has no successor move event.
# strategy: "last_event" → extend to the last event in the spell (default);
#           falls back to "median" if the last event IS the move itself, then
#           to "fixed" if there's only one box (no median possible).
#   "median" → extend by the median duration of all preceding boxes.
#   "fixed"  → extend by a fixed 30-minute window.
# Trade-off: "last_event" is clinically most accurate but silently clips if
# the data feed ends abruptly; "median" is a reasonable imputation; "fixed"
# is a last-resort visual-only fallback.
infer_box_end <- function(last_xmin, all_timestamps, preceding_durations,
                          strategy = "last_event") {

  # Validate up front — an unrecognised strategy would otherwise fall through
  # every branch and return NULL, producing an obscure downstream error.
  strategy <- match.arg(strategy, c("last_event", "median", "fixed"))

  if (strategy == "last_event") {
    last_ts <- max(all_timestamps, na.rm = TRUE)
    if (last_ts > last_xmin) {
      return(last_ts)
    }
    # Last event IS the move event itself — fall through
    strategy <- "median"
  }

  if (strategy == "median") {
    if (length(preceding_durations) > 0) {
      med_secs <- median(as.numeric(preceding_durations, units = "secs"),
                         na.rm = TRUE)
      return(last_xmin + med_secs)
    }
    # Only one box — no preceding durations to median over
    strategy <- "fixed"
  }

  if (strategy == "fixed") {
    return(last_xmin + 30 * 60)  # 30-minute visual stub
  }
}


# ── Date-break selection ───────────────────────────────────────────────────────

# Pick a sensible scale_x_datetime breaks string from the total span in seconds.
# Trade-off: automated breaks won't always be perfect, but they beat a hardcoded
# default for the wide range of journey lengths (hours to weeks).
choose_date_breaks <- function(span_secs) {
  dplyr::case_when(
    span_secs < 3600 * 3   ~ "30 mins",
    span_secs < 3600 * 12  ~ "1 hour",
    span_secs < 3600 * 36  ~ "3 hours",
    span_secs < 3600 * 96  ~ "6 hours",
    span_secs < 3600 * 240 ~ "1 day",
    TRUE                    ~ "1 week"
  )
}

choose_date_labels <- function(span_secs) {
  dplyr::case_when(
    span_secs < 3600 * 36  ~ "%H:%M",
    span_secs < 3600 * 240 ~ "%d %b %H:%M",
    TRUE                    ~ "%d %b"
  )
}


# ── Near-match suggestions ─────────────────────────────────────────────────────

# Surface helpful "did you mean X?" suggestions when a user-supplied category
# name doesn't match anything in the data. Uses base adist() so no extra deps.
suggest_matches <- function(not_found, available, max_dist = 3) {
  if (length(available) == 0) return(character(0))

  # Compute string edit distances (case-insensitive)
  dists  <- adist(not_found, available, ignore.case = TRUE)
  # One row per element of not_found; take the closest available value
  best_i <- apply(dists, 1, which.min)
  best_d <- apply(dists, 1, min)

  suggestions <- available[best_i[best_d <= max_dist]]
  unique(suggestions)
}


# ── Default colour palette ─────────────────────────────────────────────────────

# Generate a named colour vector for a set of levels, using a qualitative
# palette. Returns a named character vector level → hex colour.
# Trade-off: viridis would be perceptually uniform but is sequential; a
# qualitative palette (Set2/Set3) better distinguishes categoricals like
# location names.
journey_palette <- function(levels, type = c("location", "event")) {
  type  <- match.arg(type)
  n     <- length(levels)

  if (n == 0) return(character(0))

  # Use RColorBrewer if available (likely in any ggplot2 install context),
  # otherwise fall back to hcl.colors which is base R since 4.0
  palette_name <- if (type == "location") "Set2" else "Dark2"
  max_brewer   <- if (palette_name == "Set2") 8L else 8L

  if (requireNamespace("RColorBrewer", quietly = TRUE) && n <= max_brewer) {
    cols <- RColorBrewer::brewer.pal(max(3L, n), palette_name)[seq_len(n)]
  } else {
    cols <- hcl.colors(n, palette = if (type == "location") "Pastel 1" else "Dark 3")
  }

  stats::setNames(cols, levels)
}


# ── Null-coalescing operator ───────────────────────────────────────────────────

`%||%` <- function(x, y) if (!is.null(x)) x else y


# ── reference_lines validation ─────────────────────────────────────────────────

# Validate the shape of the `reference_lines` argument to plot_patient_journey():
# NULL (no reference lines) or a data frame with a numeric `offset_hours`
# column (hours from the spell's first event) and a `label` column.
validate_reference_lines <- function(reference_lines) {
  if (is.null(reference_lines)) return(invisible(NULL))

  if (!is.data.frame(reference_lines)) {
    cli::cli_abort(c(
      "{.arg reference_lines} must be a data frame or {.code NULL}.",
      "x" = "You supplied an object of class {.cls {class(reference_lines)}}."
    ))
  }

  required <- c("offset_hours", "label")
  missing  <- setdiff(required, names(reference_lines))
  if (length(missing) > 0) {
    cli::cli_abort(c(
      "{.arg reference_lines} is missing required column(s): {.val {missing}}.",
      "i" = "Expected columns: {.val {required}}."
    ))
  }

  if (nrow(reference_lines) == 0) {
    cli::cli_abort("{.arg reference_lines} must have at least one row.")
  }

  if (!is.numeric(reference_lines$offset_hours)) {
    cli::cli_abort(c(
      "{.field offset_hours} in {.arg reference_lines} must be numeric.",
      "x" = "You supplied class {.cls {class(reference_lines$offset_hours)}}."
    ))
  }

  invisible(NULL)
}
