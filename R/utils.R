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

# The 8-hue Okabe-Ito colourblind-safe qualitative palette.
.okabe_ito <- c(
  "#E69F00", "#56B4E9", "#009E73", "#F0E442",
  "#0072B2", "#D55E00", "#CC79A7", "#000000"
)

# Generate a named colour vector for a set of levels, using a qualitative
# palette. Returns a named character vector level → hex colour.
#
# palette_style:
#   "okabe"  (default) — colourblind-safe. Locations get the Okabe-Ito hues
#     lightened 40% toward white (so text/points overlaid on a box stay
#     legible); events get the same 8 hues *offset by 4 positions* so a
#     location and event sharing an index never share a hue (event 1 gets
#     colour 5, wrapping). Recycles past 8 distinct values.
#   "brewer" — the original Set2 (location) / Dark2 (event) palette, kept
#     verbatim for callers pinning the pre-1f default output.
journey_palette <- function(levels, type = c("location", "event"),
                            palette_style = c("okabe", "brewer")) {
  type          <- match.arg(type)
  palette_style <- match.arg(palette_style)
  n             <- length(levels)

  if (n == 0) return(character(0))

  if (palette_style == "okabe") {
    offset <- if (type == "event") 4L else 0L
    idx    <- ((seq_len(n) - 1L + offset) %% length(.okabe_ito)) + 1L
    cols   <- .okabe_ito[idx]

    if (type == "location") {
      cols <- if (requireNamespace("colorspace", quietly = TRUE)) {
        colorspace::lighten(cols, amount = 0.4)
      } else {
        vapply(cols, function(col) {
          grDevices::colorRampPalette(c(col, "white"))(5)[3]
        }, character(1), USE.NAMES = FALSE)
      }
    }

    return(stats::setNames(cols, levels))
  }

  # palette_style == "brewer" — original behaviour, kept verbatim.
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


# ── Duration formatting ────────────────────────────────────────────────────────

# Format a duration given in seconds as a short human-readable string:
#   < 60      -> "Ns"
#   < 3600    -> "Nm"
#   < 86400   -> "Hh Mm" (Mm dropped when zero)
#   >= 86400  -> "Dd Hh"
# floor() (not round()) is used throughout the sub-day buckets so a value like
# 3599s renders as "59m", not "60m" via rounding carry-over into the next unit.
format_duration <- function(secs) {
  vapply(as.numeric(secs), function(s) {
    if (is.na(s)) return(NA_character_)
    if (s < 60) {
      paste0(round(s), "s")
    } else if (s < 3600) {
      paste0(floor(s / 60), "m")
    } else if (s < 86400) {
      h <- floor(s / 3600)
      m <- floor((s - h * 3600) / 60)
      if (m == 0) paste0(h, "h") else paste0(h, "h ", m, "m")
    } else {
      d <- floor(s / 86400)
      h <- floor((s - d * 86400) / 3600)
      paste0(d, "d ", h, "h")
    }
  }, character(1))
}


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


# ── Timestamp coercion ──────────────────────────────────────────────────────────

# Coerce a column to POSIXct, aborting with an actionable message naming which
# values failed to parse. POSIXct input is returned untouched (keeping its own
# tzone); tz only applies when parsing character/numeric input, since
# lubridate would otherwise default silently to UTC, shifting wall-clock
# exports (e.g. BST) by an hour. col_label is used only in the error message
# (typically the column name).
coerce_datetime_column <- function(x, col_label, tz = "UTC") {
  if (inherits(x, "POSIXct")) return(x)

  coerced <- suppressWarnings(lubridate::as_datetime(x, tz = tz))
  na_new  <- which(is.na(coerced) & !is.na(x))

  if (length(na_new) > 0) {
    cli::cli_abort(c(
      "Could not parse {length(na_new)} value(s) in {.field {col_label}} as datetime.",
      "x" = "Problematic row(s): {.val {na_new}}",
      "i" = "Example value: {.val {x[na_new[1]]}}"
    ))
  }

  coerced
}


# ── High-cardinality bucketing ─────────────────────────────────────────────────

# Recode all but the `top_n` most frequent values of `x` to "Other", so a
# high-cardinality event_type column doesn't blow out the colour/shape
# legend. Ties at the keep/drop boundary are broken by first appearance, for
# deterministic output. Returns `x` unchanged if it has top_n or fewer
# distinct values.
bucket_top_n <- function(x, top_n) {
  freq <- table(x)
  first_appearance <- match(names(freq), x)
  ord <- order(-as.numeric(freq), first_appearance)
  levels_ordered <- names(freq)[ord]

  if (length(levels_ordered) <= top_n) return(x)

  keep    <- levels_ordered[seq_len(top_n)]
  dropped <- setdiff(levels_ordered, keep)

  cli::cli_inform(c(
    "i" = "{length(dropped)} event type(s) collapsed into {.val Other}
           (kept top {top_n} by frequency): {.val {dropped}}."
  ))

  ifelse(x %in% keep, x, "Other")
}
