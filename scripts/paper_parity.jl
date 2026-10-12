# =============================================================================
# scripts/paper_parity.jl
# Standalone runner for the :paper_parity verification (implementation lives in
# src/parity.jl, shared with the pipeline). Writes:
#   results/paper_vs_ours.csv        (Marilao, paper Tables 1 & 2 vs ours)
#   results/parity_other_bodies.csv  (Meycauayan/Obando before-after)
#
# Run:  julia --project=. scripts/paper_parity.jl
# =============================================================================
using XLSX, DataFrames, CSV, Statistics, StatsBase, Dates, SHA

const ROOT = normpath(joinpath(@__DIR__, ".."))
include(joinpath(ROOT, "src", "parity.jl"))

const RAW = joinpath(ROOT, "data", "raw",
                     "MMORS_water_quality_results_2012-2018_orig.xlsx")
const RESULTS = joinpath(ROOT, "results")
mkpath(RESULTS)

pt = paper_parity_table(RAW)
CSV.write(joinpath(RESULTS, "paper_vs_ours.csv"), pt)
np = count(==("PASS"), pt.status); nf = count(==("FAIL"), pt.status)
ni = count(==("INFO"), pt.status)
println("paper_vs_ours.csv: ", nrow(pt), " checks (", np, " PASS, ", nf,
        " FAIL, ", ni, " INFO)")
for r in eachrow(pt)
    r.status == "FAIL" && println("   FAIL  ", rpad(r.parameter, 20), r.metric,
                                  "  ours=", r.our_value, "  paper=", r.paper_value)
end

ot = parity_other_table(RAW)
CSV.write(joinpath(RESULTS, "parity_other_bodies.csv"), ot)
println("parity_other_bodies.csv: ", nrow(ot), " rows")
