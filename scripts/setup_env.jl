# One-time environment setup: creates Project.toml/Manifest.toml
# and adds the packages required by the assignment.
# Run: julia --project=. scripts/setup_env.jl
using Pkg

Pkg.activate(joinpath(@__DIR__, ".."))
Pkg.add([
    "XLSX",          # read the 3-tab .xlsx raw dataset
    "DataFrames",    # tabular data manipulation
    "CSV",           # export cleaned dataset + before/after tables
    "Statistics",    # mean/std/z-score for outlier detection
    "StatsBase",     # quantiles/IQR for outlier detection
    "Missings",      # missing-value handling utilities
    "Dates",         # date parsing and year/month extraction
    "CairoMakie",    # figures for the report
    "PrettyTables",  # readable console summaries
])

println("JULIA_VERSION=", VERSION)
