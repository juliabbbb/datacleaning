# =============================================================================
# src/ui/components.jl — reusable REPORT app atoms (design.md §1-5, §7)
#   panel, chip, banner, metric_block, report_table, figure_card, run_history
# All borders 2px INK, square corners, hard 4px shadow, Courier New.
# =============================================================================

"data: URI for a local file (used so the exported single-file HTML is self-contained)."
function data_uri(file; offline = false)
    ext = lowercase(splitext(file)[2])
    mime = ext == ".png" ? "image/png" :
           ext == ".svg" ? "image/svg+xml" :
           ext == ".csv" ? "text/csv;charset=utf-8" :
           ext == ".md"  ? "text/markdown;charset=utf-8" :
           ext == ".txt" ? "text/plain;charset=utf-8" :
           ext == ".doc" ? "application/msword" :
                           "application/octet-stream"
    bytes = read(file)
    return "data:$mime;base64,$(base64encode(bytes))"
end

"Block panel: square, 2px ink border, hard shadow."
function panel(children...; color = PAPER, border = BORDER_THICK,
               pad = string(3 * SPACE, "px"), style = Styles(),
               shadow = false)
    base = Styles(
        "background-color" => color,
        "border" => string(border, "px solid ", INK),
        "padding" => pad,
        "border-radius" => RADIUS)
    shadow && (base = Styles(base, "box-shadow" => SHADOW))
    return DOM.div(children...; style = Styles(base, style))
end

"Small status chip, square, colored fill, ink text."
function chip(text, color; style = Styles(), bold = true)
    return DOM.span(string(text); style = Styles(
        style, "display" => "inline-block",
        "background-color" => string(color),
        "border" => string(BORDER_THIN, "px solid ", INK),
        "padding" => "2px 8px", "font-size" => "12px",
        "font-weight" => bold ? "bold" : "normal",
        "letter-spacing" => "1px", "color" => INK, "line-height" => "1.4"))
end

"Full-width highway sign strip (drop-shadow standard)."
function banner(text; color = VERMILION, sub = nothing)
    inner = DOM.span(string(text); style = Styles("font-size" => "30px",
                                          "font-weight" => "bold",
                                          "letter-spacing" => "2px",
                                          "line-height" => "1.2"))
    body = isnothing(sub) ? inner :
        DOM.div(inner, DOM.div(string(sub); style = Styles("font-size" => "13px",
                         "letter-spacing" => "1px", "margin-top" => "6px")))
    return panel(body; color = color, border = BORDER_SECTION,
                 pad = string(2 * SPACE, "px "), shadow = true,
                 style = Styles("width" => "100%", "box-sizing" => "border-box",
                                "text-align" => "center"))
end

"Metric block: big number, small label, optional footnote."
function metric_block(label, value; color = PAPER, sub = nothing)
    inner = [DOM.div(string(label); style = Styles("font-size" => "12px",
                    "letter-spacing" => "1px", "opacity" => "0.72")),
             DOM.div(string(value); style = Styles("font-size" => "34px",
                    "font-weight" => "bold", "line-height" => "1.05")),
             isnothing(sub) ? nothing :
                 DOM.div(sub; style = Styles("font-size" => "12px", "line-height" => "1.35"))]
    return DOM.div(inner...; style = Styles(
        "background-color" => string(color),
        "border" => string(BORDER_THICK, "px solid ", INK),
        "padding" => string(2 * SPACE, "px"), "min-height" => "92px"))
end

fmt(v) = ismissing(v) ? "N/A" : string(v)
is_strcol(col) = col isa AbstractVector{<:AbstractString}
fmt_col(col, i) = ismissing(col[i]) ? "N/A" : string(col[i])
cell_style(col) = eltype(col) <: Number ? "num" : ""

"Render a DataFrame with proper th/td, numeric right-aligned, missing -> N/A."
function dom_table(df)
    cols = names(df)
    nrows = min(nrow(df), 100)
    head = DOM.tr(Any[DOM.th(string(c)) for c in cols]...)
    rows = Any[]
    for i in 1:nrows
        tds = Any[]
        for c in cols
            v = df[i, c]
            inner = ismissing(v) ? "N/A" : string(v)
            tds = Any[tds..., DOM.td(inner; class = cell_style(df[!, c]))]
        end
        push!(rows, DOM.tr(tds...))
    end
    return DOM.table(DOM.thead(head), DOM.tbody(rows...))
end

"Cross-link chip from T5 cells to a detail table (design.md §7.1)."
function xlink(text, target_key, sel_table)
    target_key = string(target_key)
    b = Button(text; style = Styles(
        "font-family" => FONT_MONO, "font-size" => "11px",
        "background-color" => CREAM, "border" => string(BORDER_THIN, "px solid ", INK),
        "padding" => "1px 6px", "cursor" => "pointer"))
    on(b.value) do _
        sel_table[] = target_key
    end
    return b
end

"Report table block: caption row, table, source tag, export buttons (§7)."
function report_table(df, caption, source;
                      section = "", run_id = "", footer_shim = true)
    actions = DOM.div(
        download_link("COPY (WORD)", "T.doc", "doc",
                      markdown_table(df, caption, run_id), "application/msword"),
        download_link("CSV", "T.csv", "csv", csv_string(df), "text/csv"),
        download_link("MARKDOWN", "T.md", "md",
                      markdown_table(df, caption, run_id), "text/markdown"),
        download_link("HTML", "T.html", "html", html_table(df, caption, run_id),
                      "text/html");
        style = Styles("margin-top" => string(SPACE, "px"),
                       "font-size" => "12px"))
    head = DOM.div(
        DOM.span(caption; style = Styles("font-weight" => "bold",
                                         "font-size" => "15px")),
        DOM.span(isempty(section) ? "" : "   — § " * section;
                 style = Styles("font-size" => "12px", "opacity" => "0.7")));
        style = Styles("margin-bottom" => string(SPACE, "px"),
                       "border-bottom" => string(BORDER_THIN, "px solid ", INK),
                       "padding-bottom" => "6px")
    src = DOM.div("SOURCE: results/" * source * (isempty(run_id) ? "" : "  |  run " * run_id);
                  style = Styles("margin-top" => string(SPACE, "px"),
                                 "font-size" => "12px", "opacity" => "0.7"))
    return DOM.div(head, dom_table(df), actions, src)
end

"Figure card: caption, image, tags, download links (§7.2)."
function figure_card(figkey, title, section, alt, png_path; run_id = "")
    png_uri = data_uri(png_path)
    svg_path = replace(png_path, ".png" => ".svg")
    fig = DOM.img(; src = png_uri, alt = alt,
                  style = Styles("width" => "100%", "height" => "auto",
                                 "border" => string(BORDER_THICK, "px solid ", INK),
                                 "background-color" => PAPER))
    go_actions = DOM.div(
        isfile(svg_path) ? download_link("SVG", string(basename(png_path)[1:end-4], ".svg"),
                                         "svg", nothing, "image/svg+xml",
                                         file = svg_path) : DOM.span(""),
        DOM.span(string("   alt: ", alt); style = Styles("opacity" => "0.75",
                                                         "font-size" => "12px"));
        style = Styles("margin-top" => string(SPACE, "px"), "font-size" => "12px"))
    return DOM.div(
        DOM.div(string("FIG ", figkey, ". ", title, "  \u2014 \u00a7 ", section,
                       "  |  run ", run_id);
                style = Styles("font-weight" => "bold", "font-size" => "15px",
                               "margin-bottom" => string(SPACE, "px"),
                               "border-bottom" => string(BORDER_THIN, "px solid ", INK),
                               "padding-bottom" => "6px")),
        panel(fig, go_actions; color = CREAM, pad = "12px"))
end

"Download-style link (data URI or raw file), opens a save dialog."
function download_link(label, filename, ext, content, mime; file = nothing)
    uri = isnothing(file) ? "data:$mime;base64,$(base64encode(string(content)))" : data_uri(file)
    return DOM.a(label; href = uri, download = filename)
end

"-- Word-compatible HTML table -------------------------------------------------"
function html_table(df, caption, run_id)
    head = "<meta charset=\"utf-8\"><style>table{border-collapse:collapse;font-family:Courier New}" *
           "td,th{border:1px solid #1A1A1A;padding:4px 8px;text-align:left}</style>"
    hdr = join(["<th>" * html_esc(c) * "</th>" for c in names(df)], "")
    bds = join(["<tr>" * join(["<td>" * html_esc(fmt(df[i, c])) * "</td>"
                               for c in names(df)], "") * "</tr>"
                for i in axes(df, 1)], "")
    return "<html><head>$head</head><body><h2>$(html_esc(caption))</h2>" *
           "<h4>run $(html_esc(run_id))</h4><table><tr>$hdr</tr>$bds</table></body></html>"
end
html_esc(s) = replace(string(s), "&" => "&amp;", "<" => "&lt;", ">" => "&gt;")

"-- Markdown table --------------------------------------------------------------"
function markdown_table(df, caption, run_id)
    cols = names(df)
    rows = [join(string.(fmt.(collect(df[i, cols]))), " | ") for i in axes(df, 1)]
    sep = join(["---" for _ in cols], " | ")
    return string("# ", caption, "\n\nrun ", run_id, "\n\n| ",
                  join(cols, " | "), " |\n| ", sep, " |\n",
                  join(["| " * r * " |" for r in rows], "\n"), "\n")
end

"-- CSV string (raw bytes, no added quoting) -------------------------------------"
function csv_string(df)
    io = IOBuffer()
    CSV.write(io, df)
    return String(take!(io))
end