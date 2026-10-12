# =============================================================================
# src/ui/styles.jl — global CSS for the REPORT app (design.md §1-5)
# Monospace brutal baseline: 2px ink borders everywhere, cream zebra rows,
# hard shadow, square corners. Nothing soft, nothing rounded.
# =============================================================================

function brutal_css()
    return Styles(
        CSS("body", "font-family" => FONT_MONO, "background-color" => PAPER,
            "color" => INK, "margin" => "0px", "padding" => "0px"),
        CSS("table", "border-collapse" => "collapse", "width" => "100%",
            "font-size" => "13px"),
        CSS("th, td", "border" => string(BORDER_THIN, "px solid ", INK),
            "padding" => "6px 10px", "text-align" => "left",
            "vertical-align" => "top"),
        CSS("th", "background-color" => CREAM, "font-weight" => "bold",
            "border-bottom" => string(BORDER_THICK, "px solid ", INK)),
        CSS("tr:nth-child(even) td", "background-color" => CREAM),
        CSS("a", "color" => INK, "text-decoration" => "underline"),
        CSS("code", "font-family" => FONT_MONO, "background-color" => CREAM,
            "padding" => "1px 4px"),
        CSS(".num", "text-align" => "right", "font-variant-numeric" => "tabular-nums"))
end

"Merge a set of property pairs onto a base style dict."
stv(style::Styles, pairs...) = Styles(style, pairs...)