# =============================================================================
# src/ui/theme_makie.jl — Makie theme + figure saving (single source of truth)
#
#   col(h)            — hex token -> Colorant (alpha variant: col(h, a))
#   brutal_theme()    — flat fills, 2px ink strokes, Courier New, hard grid
#   save_fig(name, fig) — figures/<name>.svg + figures/<name>.png (300 dpi)
#
# Palette comes from src/ui/tokens.jl. Included by src/report_figures.jl and
# by the Bonito UI, so figures and the app read identical tokens.
# =============================================================================

col(h::AbstractString) = parse(Colorant, h)
function col(h::AbstractString, a::Real)
    c = parse(RGBA{Float64}, h)
    RGBA{Float64}(c.r, c.g, c.b, a)
end

const PALETTE = [col(AMBER), col(MINT), col(SKY), col(LAVENDER), col(BUTTER),
                 col(VERMILION)]

brutal_theme() = Theme(
    fontsize = 15,
    fonts = (regular = "Courier New", bold = "Courier New",
             repl = "Courier New"),
    palette = (color = PALETTE,),
    Axis = (
        backgroundcolor = col(PAPER),
        leftspinevisible = true, rightspinevisible = false,
        topspinevisible = false, bottomspinevisible = true,
        leftspinecolor = col(INK), bottomspinecolor = col(INK),
        spinewidth = 2.0,
        tickcolor = col(INK), mintickspace = 5.0,
        xticklabelcolor = col(INK), yticklabelcolor = col(INK),
        xticklabelfont = "Courier New", yticklabelfont = "Courier New",
        xticklabelsize = 13, yticklabelsize = 13,
        titlefont = "Courier New", titlecolor = col(INK), titlesize = 17,
        xlabelcolor = col(INK), ylabelcolor = col(INK),
        xgridvisible = true, ygridvisible = false,
        xgridcolor = col(INK, 0.30), xgridwidth = 1.0,
        ygridcolor = col(INK, 0.30), ygridwidth = 1.0),
    Text = (color = col(INK), font = "Courier New"))

function save_fig(name::AbstractString, fig)
    mkpath(FIG_DIR)
    save(joinpath(FIG_DIR, name * ".svg"), fig)
    save(joinpath(FIG_DIR, name * ".png"), fig; px_per_unit = 3)
    return name
end