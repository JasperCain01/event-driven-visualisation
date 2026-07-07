# eventviz (development version)

## Stage 1 — Visual quick wins

New opt-in features on `plot_patient_journey()`, each defaulting to prior
behaviour:

* `show_duration` — formatted duration label above each non-terminal box;
  boxes with an inferred end get a `"+"` suffix (1a).
* `reference_lines` — target/threshold vertical lines from a data frame of
  `offset_hours` + `label` (1b).
* Ongoing-spell indication — when `terminal_activities` is supplied but the
  case never reaches one, the final box's right edge is drawn open with an
  `"(ongoing)"` marker (1c).
* `label_boxes` — direct location labels at box centres (1d).
* `event_type_top_n` — collapse a high-cardinality `act_type` tail into
  `"Other"` before the colour/shape scales are built (1e).

### Default-output change (sanctioned)

* **New default palette (1f).** `journey_palette()` gains
  `palette_style = c("okabe", "brewer")`, defaulting to `"okabe"`: a
  colourblind-safe Okabe-Ito palette (locations lightened, events offset by
  four hues so co-indexed location/event pairs never share a colour). Pass
  `palette_style = "brewer"` to restore the previous Set2/Dark2 colours.
  This is one of the two intentional default-output changes for 0.1.0 (the
  other being the Stage 0.5 defect fixes).
