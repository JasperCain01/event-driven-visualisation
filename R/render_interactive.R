# render_interactive.R — Interactive renderer (Stage 7)
#
# render_journey_plot_interactive() mirrors render_journey_plot() exactly — it
# calls it directly, with opts$interactive = TRUE — and wraps the result in
# ggiraph::girafe(). No layer-building code is duplicated here: journey_layers()
# (consumed by render_journey_plot()) already knows how to emit ggiraph's
# tooltip-bearing geoms in place of their static equivalents when
# opts$interactive is TRUE. This keeps the static output path (opts$interactive
# unset/FALSE) byte-identical to the pre-Stage-7 baselines.
#
# ggiraph is a Suggests-only dependency; plot_patient_journey() guards with
# requireNamespace() before calling this function, mirroring the
# patchwork/RColorBrewer idiom used elsewhere in the package.


# ── render_journey_plot_interactive ────────────────────────────────────────────
#
# Assemble the interactive (girafe) journey plot. Takes the same boxes/events/
# opts as render_journey_plot() — opts$interactive is forced TRUE here so
# callers don't need to remember to set it themselves.
render_journey_plot_interactive <- function(boxes, events, opts) {
  opts$interactive <- TRUE

  p <- render_journey_plot(boxes, events, opts)

  ggiraph::girafe(
    ggobj  = p,
    width_svg  = 10,
    height_svg = 6,
    options = list(
      ggiraph::opts_tooltip(opacity = 0.9, use_fill = TRUE),
      ggiraph::opts_hover(css = "stroke:black;stroke-width:1.5px;"),
      ggiraph::opts_toolbar(saveaspng = FALSE)
    )
  )
}
