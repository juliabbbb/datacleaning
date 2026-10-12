# =============================================================================
# src/parity.jl — SECOND CLEANING PROFILE: :paper_parity
#
# The strict pipeline (Stages 1-12) stays the primary, unchanged profile. This
# file adds an alternative, non-destructive profile that reproduces the paper's
# method (Centeno et al., 2023, Cosmos J. Mgmt):
#
#   * imputation to FULL completeness with the median (median rounded to 2 dp,
#     ties away from zero; the Mode for Color TCU) instead of the strict,
#     coverage-guarded station-year median;
#   * every synthesised cell is flagged in a per-parameter '<key>_imputed'
#     column (1 = filled, 0 = observed) and observed values are NEVER altered;
#   * verification artifacts against the paper's Tables 1 and 2
#     (results/paper_vs_ours.csv) and a before/after table for the other two
#     water bodies (results/parity_other_bodies.csv), for which the paper
#     reports no numbers;
#   * a strict-run regression check (results/strict_regression.csv) guaranteeing
#     the primary profile still reconciles 1147 -> 941 with byte-stable outputs.
#
# Included by src/preprocess.jl (after the globals it needs are defined); also
# usable standalone from scripts/paper_parity.jl, so all paths are arguments.
# =============================================================================

const PARITY_KEYS = ["dissolved_oxygen_mg_l", "ph", "temperature_c", "bod_mg_l",
                     "tss_mg_l", "color_tcu", "fecal_coliform_mpn",
                     "total_coliform_mpn", "ammonia_mg_l", "nitrates_mg_l",
                     "phosphates_mg_l", "chlorides_mg_l"]

const N_PAPER = 385

# paper Table 1: min, max, mean, median, mode, blank cells (denominator 385)
const PAPER_P1 = Dict(
 "dissolved_oxygen_mg_l"=> (0.03,7.48,1.996157182,1.8,3.2,16),
 "ph"                   => (6.01,8.86,7.582129032,7.685,8.01,75),
 "temperature_c"        => (25.95,35,29.96693333,29.53,31.5,310),
 "bod_mg_l"             => (2,289,34.61643836,24,23,20),
 "tss_mg_l"             => (3,330,23.6407767,17,12,76),
 "color_tcu"            => (10,250,58.35714286,40,40,315),
 "fecal_coliform_mpn"   => (54000,160000000,8905305.263,2800000,3500000,290),
 "total_coliform_mpn"   => (120,700000000,16269270.33,3500000,3500000,170),
 "ammonia_mg_l"         => (1.319,124,19.97677727,18.784,3.079,165),
 "nitrates_mg_l"        => (0.005,2.037,0.441890323,0.328,0.48,75),
 "phosphates_mg_l"      => (0.113,30.894,2.804983871,2.5415,0.573,75),
 "chlorides_mg_l"       => (1.073,1152,190.2607,60.5,30,295))

# paper Table 2: imputed value (median rounded 2 dp; Mode for Color) and mean
const PAPER_P2_IMPUTED = Dict(
 "dissolved_oxygen_mg_l"=>1.8, "ph"=>7.69, "temperature_c"=>29.53,
 "bod_mg_l"=>24.0, "tss_mg_l"=>17.0, "color_tcu"=>40.0,
 "fecal_coliform_mpn"=>2800000.0, "total_coliform_mpn"=>3500000.0,
 "ammonia_mg_l"=>18.78, "nitrates_mg_l"=>0.33, "phosphates_mg_l"=>2.54,
 "chlorides_mg_l"=>60.5)
const PAPER_P2_MEAN = Dict(
 "dissolved_oxygen_mg_l"=>1.988005, "ph"=>7.603143, "temperature_c"=>29.61512,
 "bod_mg_l"=>34.06494, "tss_mg_l"=>22.32987, "color_tcu"=>43.33766,
 "fecal_coliform_mpn"=>4306503.896, "total_coliform_mpn"=>10630891.22,
 "ammonia_mg_l"=>19.46387, "nitrates_mg_l"=>0.420094, "phosphates_mg_l"=>2.753364,
 "chlorides_mg_l"=>90.83367)

const PARITY_PLACEHOLDERS = ("", "-", "_", "N/A", "n/a", "ND", "na")
parity_is_ph(v) = v isa AbstractString &&
    (strip(v) in PARITY_PLACEHOLDERS || isempty(strip(v)) ||
     occursin("NO SAMPLING", uppercase(v)))

"Censored-cell parser: strip <,>,* and spaces, keep the digits exactly."
function parity_num(v)
    v isa Real && return Float64(v)
    parity_is_ph(v) && return missing
    v isa AbstractString || return missing
    s = replace(strip(v), r"\s+" => "")
    s = replace(s, r"^[<>]" => "")
    s = replace(s, r"\*" => "")
    try parse(Float64, s) catch; missing end
end

"median rounded to 2 dp, ties away from zero (the paper's imputation rule)."
round2(x) = round(x, RoundNearestTiesAway; digits = 2)

"Excel MODE: the most frequent value; ties broken by FIRST occurrence."
function mode_firstocc(v::AbstractVector{Float64})
    first = Dict{Float64, Int}(); cnt = Dict{Float64, Int}()
    for (i, x) in enumerate(v)
        haskey(first, x) || (first[x] = i)
        cnt[x] = get(cnt, x, 0) + 1
    end
    maxc = maximum(values(cnt))
    sort([x for (x, c) in cnt if c == maxc]; by = x -> first[x])[1]
end

# --- raw-sheet reader (banner blocks) ----------------------------------------
function load_parity_sheet(raw_path, sheet)
    xf = XLSX.openxlsx(raw_path)
    d = XLSX.readdata(raw_path, sheet, string(xf[sheet].dimension))
    nr = size(d, 1)
    blocks = Vector{Vector{Int}}(); labels = String[]; cur = Int[]
    for r in 1:nr
        v1 = d[r, 1]
        if v1 isa AbstractString && startswith(v1, "CY ")
            isempty(cur) || push!(blocks, cur); push!(labels, strip(v1)); cur = Int[]
        elseif v1 isa Integer
            push!(cur, r)
        end
    end
    isempty(cur) || push!(blocks, cur)
    return d, blocks, labels
end

parity_hasdata(d, r) = any(!ismissing(d[r, i]) && !parity_is_ph(d[r, i]) for i in 5:18)
parity_colof(k) = 6 + findfirst(==(k), PARITY_KEYS)

"""
Row set (locked rule 1): the banner range 'CY 2012 JANUARY'..'CY 2018 MAY' if it
yields 385 rows, else the contiguous data window of whole 5-station blocks.
Returns (d, win_blocks, win_rows, diagnostic::String).
"""
function parity_window(raw_path, sheet)
    d, blocks, labels = load_parity_sheet(raw_path, sheet)
    n_data = [count(r -> parity_hasdata(d, r), b) for b in blocks]
    bs = findfirst(==("CY 2012 JANUARY"), labels)
    be = findfirst(==("CY 2018 MAY"), labels)
    banner_blocks = (bs === nothing || be === nothing) ? 0 : be - bs + 1
    if banner_blocks * 5 == N_PAPER
        diag = "banner range CY 2012 JANUARY..CY 2018 MAY = 385 rows (used)"
        return d, collect(bs:be), reduce(vcat, blocks[bs:be]), diag
    end
    firstd = findfirst(>(0), n_data); lastd = findlast(>(0), n_data)
    win = collect(firstd:lastd)
    diag = string("banner range CY 2012 JANUARY..CY 2018 MAY = ",
                  banner_blocks, " blocks / ", banner_blocks * 5,
                  " rows (NOT 385); fell back to the data window blocks ",
                  firstd, "..", lastd, " = ", length(win), " blocks / ",
                  length(reduce(vcat, blocks[win])), " rows; dropped blocks ",
                  lastd + 1, "..", length(blocks), " are all zero-data (EDGE drop)")
    return d, win, reduce(vcat, blocks[win]), diag
end

# --- comparison tables ------------------------------------------------------
"Marilao: paper Tables 1 & 2 vs ours -> long PASS/FAIL/INFO table."
function paper_parity_table(raw_path)
    d, win_blocks, win_rows, diag = parity_window(raw_path, "Marilao")
    rows = NamedTuple[]
    delta_of(p, o) = (p isa Real && o isa Real) ? round(o - p; digits = 6) : missing
    addrow(param, metric, paper, ours, status, note="") =
        push!(rows, (parameter = param, metric = metric,
                     paper_value = string(paper), our_value = string(ours),
                     delta = delta_of(paper, ours), status = status, note = note))
    approx(a, b) = isapprox(a, b; rtol = 1e-5, atol = 1e-6)
    obs(k) = [x for x in (parity_num(d[r, parity_colof(k)]) for r in win_rows)
              if x isa Float64]

    addrow("_row_set", "blocks_in_window", 77, length(win_blocks),
           length(win_blocks) == 77 ? "PASS" : "INFO", diag)

    for k in PARITY_KEYS
        v = obs(k)
        pmin, pmax, pmean, pmed, pmode, pblank = PAPER_P1[k]
        pn = N_PAPER - pblank
        m = mode_firstocc(v)
        addrow(k, "n_nonblank", pn, length(v), length(v) == pn ? "PASS" : "FAIL")
        addrow(k, "min", pmin, minimum(v), approx(minimum(v), pmin) ? "PASS" : "FAIL")
        addrow(k, "max", pmax, maximum(v), approx(maximum(v), pmax) ? "PASS" : "FAIL")
        addrow(k, "mean", pmean, mean(v), approx(mean(v), pmean) ? "PASS" : "FAIL",
               approx(mean(v), pmean) ? "" : "mean mismatch")
        addrow(k, "median", pmed, median(v),
               approx(median(v), pmed) ? "PASS" : "FAIL",
               approx(median(v), pmed) ? "" : "median mismatch")
        addrow(k, "mode", pmode, m, m == pmode ? "PASS" : "FAIL",
               m == pmode ? "first-occurrence tie-break (Excel MODE)" :
                            "paper mode not reproduced")
        fillv = k == "color_tcu" ? mode_firstocc(v) : round2(median(v))
        m385 = (length(v) * mean(v) + (N_PAPER - length(v)) * fillv) / N_PAPER
        addrow(k, "imputed_value", PAPER_P2_IMPUTED[k], fillv,
               approx(fillv, PAPER_P2_IMPUTED[k]) ? "PASS" : "FAIL",
               k == "color_tcu" ? "color = mode" : "median rounded to 2 dp")
        addrow(k, "mean_after", PAPER_P2_MEAN[k], m385,
               approx(m385, PAPER_P2_MEAN[k]) ? "PASS" : "FAIL",
               approx(m385, PAPER_P2_MEAN[k]) ?
                   "paper closed form (n*mean+(385-n)*imputed)/385" :
                   "diverges from the paper (see Table 1 / imputed_value)")
    end

    # censored cells (rule 4): keep the digits; documented as FAIL
    for k in ("nitrates_mg_l", "total_coliform_mpn")
        ci = parity_colof(k)
        n = count(r -> d[r, ci] isa AbstractString && !parity_is_ph(d[r, ci]) &&
                       (startswith(strip(d[r, ci]), "<") ||
                        startswith(strip(d[r, ci]), ">")), win_rows)
        note = k == "nitrates_mg_l" ?
            "paper's nitrates are consistent with 0.48 (10x our 0.048, 60 cells); likely retyping in the adviser's sheet, to be confirmed with the adviser." :
            "paper's total coliform is consistent with 1,600,000 (10x our 16,000,000, 1 cell); likely retyping in the adviser's sheet, to be confirmed with the adviser."
        addrow(k, "censored_cells", missing, n, "FAIL", note)
    end

    # Date / Time count gaps -> INFO (documented, not chased)
    nd = count(r -> !ismissing(d[r, 5]) && !parity_is_ph(d[r, 5]), win_rows)
    nt = count(r -> !ismissing(d[r, 6]) && !parity_is_ph(d[r, 6]), win_rows)
    addrow("date", "n_nonblank", 370, nd, "INFO",
           "paper derives dates from the CY banner; our window keeps 10 date/time-only rows")
    addrow("time", "n_nonblank", 310, nt, "INFO",
           "10 date/time-only rows carry a time but no parameter")
    return DataFrame(rows)
end

"Meycauayan + Obando before/after under the parity profile (no paper numbers)."
function parity_other_table(raw_path)
    other = NamedTuple[]
    for sheet in ("Meycauayan", "Obando")
        d, win_blocks, win_rows, _ = parity_window(raw_path, sheet)
        for k in PARITY_KEYS
            ci = parity_colof(k)
            o = Float64[x for x in (parity_num(d[r, ci]) for r in win_rows)
                        if x isa Float64]
            isempty(o) && continue
            fillv = k == "color_tcu" ? mode_firstocc(o) : round2(median(o))
            m_after = (length(o) * mean(o) +
                       (length(win_rows) - length(o)) * fillv) / length(win_rows)
            push!(other, (water_body = sheet, parameter = k,
                          n_before = length(o),
                          mean_before = round(mean(o); digits = 4),
                          median_before = median(o),
                          mode_before = mode_firstocc(o),
                          imputed_value = fillv,
                          n_after = length(win_rows),
                          mean_after = round(m_after; digits = 4),
                          median_after = fillv))
        end
    end
    return DataFrame(other)
end

# --- the parity profile applied to the cleaned dataset ----------------------
"""
Non-destructive, full-completeness imputation: fill every missing parameter
cell with the median (median rounded 2 dp; Mode for Color TCU) and flag it in a
'<key>_imputed' column. Observed values are never modified.
"""
function parity_impute(df::DataFrame)
    out = copy(df)
    for k in PARITY_KEYS
        col = out[!, k]
        o = Float64[x for x in col if x isa Float64]
        if isempty(o)
            out[!, k * "_imputed"] = zeros(Int, nrow(out))
            continue
        end
        fillv = k == "color_tcu" ? mode_firstocc(o) : round2(median(o))
        out[!, k] = Union{Missing, Float64}[x isa Float64 ? x : fillv for x in col]
        out[!, k * "_imputed"] = Int[ismissing(x) ? 1 : 0 for x in col]
    end
    return out
end

"""
Write the parity artifacts and print a summary. Called from main() after the
strict report layer; also callable standalone.
"""
function write_parity_artifacts(raw_path, results_dir, clean_dir, df::DataFrame)
    mkpath(results_dir); mkpath(clean_dir)
    println("\n", "="^74, "\nPARITY PROFILE (:paper_parity)\n", "="^74)

    pt = paper_parity_table(raw_path)
    CSV.write(joinpath(results_dir, "paper_vs_ours.csv"), pt)
    np = count(==("PASS"), pt.status); nf = count(==("FAIL"), pt.status)
    ni = count(==("INFO"), pt.status)
    println("paper_vs_ours.csv: ", nrow(pt), " checks (", np, " PASS, ", nf,
            " FAIL, ", ni, " INFO)")
    for r in eachrow(pt)
        r.status == "FAIL" && println("   FAIL  ", rpad(r.parameter, 20),
                                      r.metric, "  ours=", r.our_value,
                                      "  paper=", r.paper_value)
    end

    ot = parity_other_table(raw_path)
    CSV.write(joinpath(results_dir, "parity_other_bodies.csv"), ot)
    println("parity_other_bodies.csv: ", nrow(ot), " rows")

    imp = parity_impute(df)
    path = joinpath(clean_dir, "mmors_water_quality_parity.csv")
    CSV.write(path, imp)
    nfill = sum(sum(imp[!, k * "_imputed"]) for k in PARITY_KEYS)
    println("mmors_water_quality_parity.csv: ", nrow(imp), " x ", ncol(imp),
            " (", nfill, " cells imputed; observed values unchanged, every fill ",
            "flagged in <param>_imputed)")

    if isdefined(@__MODULE__, :logstep!)
        logstep!("parity", "paper_checks", 0, nrow(pt),
                 string(np, " PASS, ", nf, " FAIL, ", ni, " INFO"))
        logstep!("parity", "cells_imputed_full_completeness", 0, nfill,
                 "median (Mode for Color); flagged in <param>_imputed")
    end
    return (; paper = pt, other = ot, parity = imp)
end

# =============================================================================
# STRICT-RUN REGRESSION CHECK
# The primary profile must stay byte-stable. Outputs embed the run id and
# timestamp in comment headers, so hashes are taken on a normalized copy
# (run ids + timestamps masked, comment lines dropped). The intentionally
# changed descriptives_before_after.csv (new mode columns) is excluded from the
# byte comparison and checked structurally instead.
# =============================================================================
const REGRESSION_EXCLUDE = Set(["descriptives_before_after.csv",
                                "paper_vs_ours.csv", "parity_other_bodies.csv",
                                "strict_regression.csv",
                                "baseline_strict_sha256.csv"])

normalize_strict_text(txt::AbstractString) = begin
    t = replace(txt, r"run_\d{8}_\d{6}" => "run_ID")
    t = replace(t, r"\d{4}-\d{2}-\d{2}.{0,4}\d{2}:\d{2}:\d{2}" => "TS")
    join(filter(l -> !startswith(l, "#"), split(t, '\n')), "\n")
end

strict_file_list(dir) = sort([f for f in readdir(dir)
    if isfile(joinpath(dir, f)) &&
       lowercase(splitext(f)[2]) in (".csv", ".md", ".json", ".txt") &&
       !(f in REGRESSION_EXCLUDE)])

strict_file_hash(dir, f) =
    bytes2hex(sha256(normalize_strict_text(read(joinpath(dir, f), String))))

"Capture the current strict outputs as the regression baseline."
function write_strict_baseline(dir, baseline = joinpath(dir, "baseline_strict_sha256.csv"))
    df = DataFrame(file = String[], sha256 = String[])
    for f in strict_file_list(dir)
        push!(df, (file = f, sha256 = strict_file_hash(dir, f)))
    end
    CSV.write(baseline, df)
    println("baseline_strict_sha256.csv: ", nrow(df), " strict files hashed")
    return df
end

"""
Compare the current strict outputs against the baseline and assert the row
conservation invariants (1147 in -> 941 out). Writes results/strict_regression.csv.
"""
function strict_regression(dir; rows_in::Int, rows_out::Int,
                           baseline = joinpath(dir, "baseline_strict_sha256.csv"))
    bl = isfile(baseline) ? CSV.read(baseline, DataFrame) :
         DataFrame(file = String[], sha256 = String[])
    blm = Dict(string(r.file) => string(r.sha256) for r in eachrow(bl))
    checks = NamedTuple[]
    addcheck(name, expected, actual, ok) =
        push!(checks, (check = name, expected = string(expected),
                       actual = string(actual), status = ok ? "PASS" : "FAIL"))

    addcheck("Strict records in == 1147", 1147, rows_in, rows_in == 1147)
    addcheck("Strict records out == 941", 941, rows_out, rows_out == 941)

    desc = joinpath(dir, "descriptives_before_after.csv")
    dn = isfile(desc) ? names(CSV.read(desc, DataFrame; comment = "#")) : String[]
    addcheck("descriptives_before_after.csv has mode_before/mode_after",
             "mode_before,mode_after", join(filter(c -> endswith(c, "mode_before") ||
                 endswith(c, "mode_after"), dn), ","),
             ("mode_before" in dn) && ("mode_after" in dn))

    for f in strict_file_list(dir)
        h = strict_file_hash(dir, f)
        if haskey(blm, f)
            addcheck("strict file unchanged: " * f, blm[f], h, blm[f] == h)
        else
            addcheck("strict file known to baseline: " * f, "in baseline",
                     "NEW", false)
        end
    end
    for f in sort(collect(keys(blm)))
        isfile(joinpath(dir, f)) ||
            addcheck("strict file still present: " * f, "present", "MISSING", false)
    end

    out = joinpath(dir, "strict_regression.csv")
    CSV.write(out, DataFrame(checks))
    npass = count(c -> c.status == "PASS", checks)
    nfail = count(c -> c.status == "FAIL", checks)
    println("strict_regression.csv: ", length(checks), " checks (", npass,
            " PASS, ", nfail, " FAIL)")
    for c in checks
        c.status == "FAIL" && println("   FAIL  ", c.check, "  expected=",
                                      c.expected, "  actual=", c.actual)
    end
    return DataFrame(checks)
end
