# =============================================================================
# src/ui/BrutalUI.jl — REPORT app module (design.md §10 file layout)
#
#   BrutalUI.build_app()      -> Bonito.App (7 screens, live observables)
#   BrutalUI.run_server(port) -> Bonito.Server at 127.0.0.1:<port>
#   BrutalUI.export_report()  -> report/index.html (single self-contained file)
#
# Run standalone:
#   julia --project=. -e 'include("src/ui/BrutalUI.jl"); BrutalUI.run_server()'
# Theme (theme_makie.jl) is intentionally NOT included here: it pulls
# CairoMakie for figure generation and belongs to the pipeline side.
# =============================================================================

module BrutalUI

using Bonito
using Bonito: DOM, App, Card, Styles, CSS, Observable, on, Button, Dropdown
using DataFrames, CSV, JSON3, Dates, Base64, Printf, SHA

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const RESULT_DIR = joinpath(ROOT, "results")
const FIG_DIR = joinpath(ROOT, "figures")
const RUNS_DIR = joinpath(RESULT_DIR, "runs")

include(joinpath(@__DIR__, "tokens.jl"))
include(joinpath(@__DIR__, "styles.jl"))
include(joinpath(@__DIR__, "components.jl"))
include(joinpath(@__DIR__, "screens.jl"))
include(joinpath(@__DIR__, "app.jl"))

export build_app, run_server, export_report

end