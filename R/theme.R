# theme.R — Shared base theme (Stage 8)
#
# theme_journey() factors out the ggplot2::theme_minimal() call plus the grid-
# line and title styling common to every renderer in this package: the band
# layout (render_journey_plot()) and the staircase (plot_stage_ladder()).
# Each caller layers its own additional theme() customisations on top (legend
# styling and the lane-conditional axis for the band layout; the fixed stage-
# name axis and no-legend styling for the staircase) — those differ by design,
# so only the genuinely shared subset lives here. Because ggplot2 theme()
# calls compose additively, splitting the theme across two calls like this
# produces the exact same final theme as one call would — extracting this
# is purely DRY, not a behaviour change.

#' Shared base ggplot2 theme for eventviz renderers
#'
#' Factors out the [ggplot2::theme_minimal()] call plus the grid-line and
#' title styling common to every renderer in this package (the band layout
#' and the staircase). Each renderer layers its own additional
#' [ggplot2::theme()] customisations on top.
#'
#' @param base_size Base font size, in points, passed to
#'   [ggplot2::theme_minimal()].
#'
#' @return A ggplot2 `theme` object.
#'
#' @examples
#' th <- theme_journey(base_size = 11)
#'
#' @export
theme_journey <- function(base_size = 11) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      panel.grid.major.y = ggplot2::element_blank(),
      panel.grid.minor.y = ggplot2::element_blank(),
      panel.grid.minor.x = ggplot2::element_blank(),
      panel.grid.major.x = ggplot2::element_line(colour = "grey88", linewidth = 0.4),
      plot.title          = ggplot2::element_text(size = 12, face = "bold", hjust = 0)
    )
}
