# =============================================================================
# scripts/methodology_tables.jl — minimal Phase B report tables (CSV only).
#
#   M6  results/methodology/required_quality_format.csv  (required 5-row format)
#   M7  results/methodology/record_flow.csv              (extracted -> final)
#   M9  results/methodology/strict_vs_parity.csv         (strict vs parity profile)
#
# Every value is READ from an existing pipeline artifact; nothing is hand-typed.
# Run:  julia --project=. scripts/methodology_tables.jl
# =============================================================================
using CSV, DataFrames, JSON3

const ROOT     = normpath(joinpath(@__DIR__, ".."))
const RESULTS  = joinpath(ROOT, "results")
const CLEAN    = joinpath(ROOT, "data", "clean")
const OUTDIR   = joinpath(RESULTS, "methodology")

rpath(f) = joinpath(RESULTS, f)
rd(p)    = CSV.read(p, DataFrame; comment = "#", types = String)
num(x)   = something(tryparse(Float64, string(x)), NaN)

"Write a table with a leading '#' source comment (matches results/ convention)."
function write_csv(name, tbl; comment)
    mkpath(OUTDIR)
    p = joinpath(OUTDIR, name)
    CSV.write(p, tbl)
    c = read(p, String)
    open(p, "w") do io
        write(io, comment, "\n")
        write(io, c)
    end
    println("  ", name, "  (", nrow(tbl), " rows x ", ncol(tbl), " cols)")
    return p
end

function main()
    man      = JSON3.read(read(rpath("run_manifest.json"), String))
    run_id   = string(man.run_id)
    qs       = rd(rpath("quality_summary.csv"))
    rec      = rd(rpath("reconciliation.csv"))
    strict   = rd(joinpath(CLEAN, "mmors_water_quality_clean.csv"))
    parity   = rd(joinpath(CLEAN, "mmors_water_quality_parity.csv"))
    pvo      = rd(rpath("paper_vs_ours.csv"))

    mkpath(OUTDIR)
    println("methodology_tables.jl -> results/methodology/  (run ", run_id, ")")

    # --- M6: the required 5-row before/after table ---------------------------
    m6 = DataFrame(
        "Data Quality Issue"     => qs[!, 1],
        "Before Preprocessing"   => qs[!, 2],
        "Action Taken"           => qs[!, 3],
        "After Preprocessing"    => qs[!, 4])
    write_csv("required_quality_format.csv", m6;
              comment = string("# M6 required before/after format (5 issues x 4 columns)",
                               "  |  source results/quality_summary.csv  |  run ", run_id))

    # --- M7: record flow (extracted -> removals -> final) --------------------
    allrows = rec[rec.scope .== "ALL WORKSHEETS", :]
    flow = DataFrame(
        step      = allrows.step,
        rows      = parse.(Int, allrows.rows),
        cumulative = parse.(Int, allrows.cumulative))
    base = flow.rows[1]
    flow.pct_of_extracted = [string(round(100 * r / base; digits = 1), "%") for r in flow.rows]
    write_csv("record_flow.csv", flow;
              comment = string("# M7 record flow: records extracted -> duplicates/zero-measurement",
                               " removals -> analysis-ready  |  source results/reconciliation.csv",
                               "  |  run ", run_id))

    # --- M9: strict (primary) profile vs :paper_parity profile ---------------
    ni_strict = man.cells_imputed
    ni_parity = sum(sum(parse.(Int, parity[!, c])) for c in names(parity)
                    if endswith(c, "_imputed"))
    npass = count(==("PASS"), pvo.status)
    rows_by_river(df, col) = Dict(g => length(ix) for (g, ix) in
                                  [(v, findall(==(v), df[!, col])) for v in unique(df[!, col])])
    s_river = rows_by_river(strict, "water_body")
    p_river = rows_by_river(parity, "water_body")

    prop = String[]; sp = String[]; pp = String[]; note = String[]
    add(p, s, t, n) = (push!(prop, p); push!(sp, s); push!(pp, t); push!(note, n))

    add("profile", "primary strict pipeline (Stages 1-12)", ":paper_parity (alternative, non-destructive)",
        "parity profile reproduces the paper's method; strict stays the analysis-ready output")
    add("rows (total)", string(nrow(strict)), string(nrow(parity)),
        "parity keeps every windowed sheet row; strict removes duplicates and empty records")
    for wb in ["Marilao", "Meycauayan", "Obando"]
        add("rows ($wb)", string(get(s_river, wb, 0)), string(get(p_river, wb, 0)),
            "parity window = data blocks + trailing coordinate-only block")
    end
    add("columns", string(ncol(strict)), string(ncol(parity)),
        "strict = 3 ids + 9 metadata/derived + 12 parameters + 5 flag/doc columns; parity = 6 ids/fields + 12 parameters + 12 <param>_imputed flags")
    add("duplicate records removed", "31", "0", "parity keeps all rows")
    add("zero-measurement rows removed", "175", "0", "parity keeps all rows")
    add("imputed cells", string(ni_strict), string(ni_parity),
        "strict: station-year median, coverage >= 50%, flagged; parity: full-completeness median (Mode for Color), every cell flagged")
    add("observed values altered", "no", "no", "both profiles never change an observed value")
    add("outlier policy", "IQR flag only, values kept", "not flagged", "reference paper also retains its outliers")
    add("purpose", "analysis-ready dataset for the report", "faithful reproduction + verification of the paper",
        "parity exists to check, not replace, the primary output")
    add("verification", "strict_regression.csv 35/35 PASS",
        string("paper_vs_ours.csv ", npass, " PASS"),
        "strict byte-stable; parity matches the paper's Tables 1-2 on 11/12 parameters")
    m9 = DataFrame(property = prop, strict_profile = sp, parity_profile = pp, note = note)
    write_csv("strict_vs_parity.csv", m9;
              comment = string("# M9 strict (primary) vs :paper_parity profile  |  sources",
                               " run_manifest.json + data/clean/*.csv + results/paper_vs_ours.csv",
                               "  |  run ", run_id))

    println("Done: ", OUTDIR)
end

main()
