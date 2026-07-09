# Shared base ggplot2 theme for eventviz renderers

Factors out the \[ggplot2::theme_minimal()\] call plus the grid-line and
title styling common to every renderer in this package (the band layout
and the staircase). Each renderer layers its own additional
\[ggplot2::theme()\] customisations on top.

## Usage

``` r
theme_journey(base_size = 11)
```

## Arguments

- base_size:

  Base font size, in points, passed to \[ggplot2::theme_minimal()\].

## Value

A ggplot2 \`theme\` object.

## Examples

``` r
th <- theme_journey(base_size = 11)
```
