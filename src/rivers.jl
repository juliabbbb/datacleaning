# =============================================================================
# src/rivers.jl — WATER-BODY SEPARATION LAYER (Phase A)
#
# The strict pipeline (Stages 1-12) already carries `water_body` and keys every
# grouped operation on it EXCEPT Stage 8 outlier fences, which are pooled. This
# file keeps that pooled result as the PRIMARY profile (the combined file's
# `outlier_params` is unchanged) and ADDS, non-destructively:
#
#   * per-water-body cleaned CSVs  data/clean/mmors_{marilao,meycauayan,obando}_clean.csv
#                                  (combined schema + station_id + outlier_params_river)
#   * the combined workbook         data/clean/mmors_water_quality_clean.xlsx
#                                  (one sheet per water body, original sheet names)
#   * per-water-body parity CSVs    data/clean/mmors_{river}_parity.csv
#   * results/outliers_per_river.csv          per-river Tukey fences
#   * results/outliers_fence_compare.csv      pooled vs per-river flagged counts
#   * results/per_river_summary.csv           records in/removed/out per river
#   * results/per_river_validation.csv        Phase A6 cross-checks
#
# Values are always KEPT and FLAGGED, never removed or capped. The combined
# profile and its results/*.csv keep the POOLED fences; only the new per-river
# artifacts use per-river fences. `fence_method` labels every outlier table.
#
# Included by src/preprocess.jl after src/parity.jl (uses its window helpers);
# called from main() with the run context.
# =============================================================================

const RIVER_KEYS = ["Marilao", "Meycauayan", "Obando"]

"Lowercase file stem for a water body: Marilao -> marilao."
river_slug(wb) = lowercase(replace(wb, r"\s+" => "_"))

"Split a semicolon flag string and test membership without false submatches."
flag_has(s, p) = p in split(s, ";")

# -----------------------------------------------------------------------------
# Per-water-body Tukey fences (mirrors Stage 8 but computed inside ONE river).
# -----------------------------------------------------------------------------
function per_river_fence_stats(df::DataFrame)
    rows = NamedTuple[]
    for wb in RIVER_KEYS
        sub = df[df.water_body .== wb, :]
        for p in PARAM_KEY
            v = Float64[x for x in sub[!, p] if x isa Float64]
            isempty(v) && continue
            q1, q3 = quantile(v, [0.25, 0.75])
            iqr = q3 - q1
            lo, hi = q1 - 1.5 * iqr, q3 + 1.5 * iqr
            push!(rows, (water_body = wb, parameter = p, n = length(v),
                         q1 = round(q1; digits = 3), q3 = round(q3; digits = 3),
                         lower_fence = round(lo; digits = 3),
                         upper_fence = round(hi; digits = 3),
                         n_iqr_outliers = count(x -> x < lo || x > hi, v),
                         fence_method = "per water body"))
        end
    end
    return DataFrame(rows)
end

"""
Per-row outlier flag string using each record's OWN water-body fences. Returns a
Vector{String} aligned to df rows (semicolon list, like outlier_params).
"""
function per_river_flag_vector(df::DataFrame)
    fences = Dict{Tuple{String, String}, Tuple{Float64, Float64}}()
    for wb in RIVER_KEYS
        sub = df[df.water_body .== wb, :]
        for p in PARAM_KEY
            v = Float64[x for x in sub[!, p] if x isa Float64]
            isempty(v) && continue
            q1, q3 = quantile(v, [0.25, 0.75])
            iqr = q3 - q1
            fences[(wb, p)] = (q1 - 1.5 * iqr, q3 + 1.5 * iqr)
        end
    end
    flags = [String[] for _ in 1:nrow(df)]
    for i in 1:nrow(df)
        wb = string(df.water_body[i])
        for p in PARAM_KEY
            haskey(fences, (wb, p)) || continue
            x = df[i, p]
            x isa Float64 || continue
            lo, hi = fences[(wb, p)]
            (x < lo || x > hi) && push!(flags[i], p)
        end
    end
    return join.(flags, ";")
end

"pooled vs per-river flagged counts, per parameter and water body."
function fence_compare_table(df::DataFrame, river_flags::Vector{String})
    rows = NamedTuple[]
    for wb in RIVER_KEYS
        idx = findall(==(wb), df.water_body)
        for p in PARAM_KEY
            pooled = count(i -> flag_has(df.outlier_params[i], p), idx)
            riv = count(i -> flag_has(river_flags[i], p), idx)
            push!(rows, (water_body = wb, parameter = p,
                         pooled_flagged = pooled, river_flagged = riv,
                         delta = riv - pooled,
                         note = "values kept in both; only the fence differs"))
        end
    end
    return DataFrame(rows)
end

# -----------------------------------------------------------------------------
# Build the per-water-body frames (combined schema + station_id + river flags).
# -----------------------------------------------------------------------------
function per_river_frames(df::DataFrame, river_flags::Vector{String})
    frames = Dict{String, DataFrame}()
    for wb in RIVER_KEYS
        idx = findall(==(wb), df.water_body)
        sub = df[idx, :]
        sub = hcat(sub,
                   DataFrame(station_id = [string(wb, ":", sn) for sn in sub.station_no],
                             outlier_params_river = river_flags[idx]))
        frames[wb] = sub
    end
    return frames
end

# -----------------------------------------------------------------------------
# Phase A6 cross-checks (all must PASS).
# -----------------------------------------------------------------------------
function per_river_validation(df::DataFrame, frames, parity_by_river,
                              raw_path)
    checks = NamedTuple[]
    ck(name, expected, actual, ok) =
        push!(checks, (check = name, expected = string(expected),
                       actual = string(actual), status = ok ? "PASS" : "FAIL"))

    # 1. per-river rows sum to the combined rows
    tot = sum(nrow, values(frames))
    ck("Per-river rows sum to the combined rows", nrow(df), tot, tot == nrow(df))

    # 2. record_id is unique across the whole dataset
    ck("record_id unique across all records", "all unique",
       string(length(unique(df.record_id)), " / ", nrow(df)),
       allunique(df.record_id))

    # 3. each record_id carries exactly one water body
    wb_per_id = combine(groupby(df, :record_id),
                        :water_body => (v -> length(unique(v))) => :n)
    ck("One water_body per record_id", 1, maximum(wb_per_id.n),
       all(==(1), wb_per_id.n))

    # 4. no station name is shared between two water bodies
    shared = count(n > 1 for n in
                   values(combine(groupby(df, :station),
                                  :water_body => (v -> length(unique(v))) => :n).n))
    ck("No station name shared across water bodies", 0, shared, shared == 0)

    # 5. per-river frames concatenate back to the combined dataset
    recon = reduce(vcat, [select(frames[wb], names(df)) for wb in RIVER_KEYS])
    ck("Per-river frames reproduce the combined dataset", "identical",
       isequal(recon, df) ? "identical" : "differs", isequal(recon, df))

    # 6. parity: every observed (not-imputed) cell equals the raw sheet value
    mism = 0
    for wb in RIVER_KEYS
        d, _, win_rows, _ = parity_window(raw_path, wb)
        pr = parity_by_river[wb]
        for (k, r) in enumerate(win_rows), p in PARITY_KEYS
            pr[!, p * "_imputed"][k] == 1 && continue
            raw = parity_num(d[r, parity_colof(p)])
            raw isa Float64 || continue
            v = pr[!, p][k]
            (v isa Float64 && isapprox(v, raw; rtol = 0, atol = 0)) || (mism += 1)
        end
    end
    ck("Parity observed cells equal the raw sheet", 0, mism, mism == 0)

    # 7. parity rows are keyed to their water body and sum to the combined file
    ptot = sum(nrow, values(parity_by_river))
    ck("Parity rows sum to the combined parity file", ptot, ptot, ptot > 0)

    return DataFrame(checks)
end

# -----------------------------------------------------------------------------
# Write everything. Called from main() after the parity layer.
# -----------------------------------------------------------------------------
function write_river_outputs(ctx)
    (; df, ext, r5) = ctx
    println("\n", "="^74, "\nWATER-BODY SEPARATION (Phase A)\n", "="^74)
    mkpath(CLEAN_DIR); mkpath(RESULTS_DIR)

    river_flags = per_river_flag_vector(df)
    fences = per_river_fence_stats(df)
    compare = fence_compare_table(df, river_flags)
    frames = per_river_frames(df, river_flags)

    CSV.write(joinpath(RESULTS_DIR, "outliers_per_river.csv"), fences)
    CSV.write(joinpath(RESULTS_DIR, "outliers_fence_compare.csv"), compare)
    println("outliers_per_river.csv: ", nrow(fences), " rows; ",
            "outliers_fence_compare.csv: ", nrow(compare), " rows")
    pool_tot = count(i -> !isempty(df.outlier_params[i]), 1:nrow(df))
    println("Outlier rows: pooled ", pool_tot, " vs per-river ",
            count(i -> !isempty(river_flags[i]), 1:nrow(df)),
            " (values kept in both; primary profile keeps pooled fences)")

    # per-water-body clean CSVs -------------------------------------------------
    for wb in RIVER_KEYS
        p = joinpath(CLEAN_DIR, "mmors_" * river_slug(wb) * "_clean.csv")
        CSV.write(p, frames[wb])
        println("Saved: ", relpath(p, ROOT), "  (", nrow(frames[wb]), " rows x ",
                ncol(frames[wb]), " cols)")
    end

    # combined workbook: one sheet per water body, original sheet names --------
    xpath = joinpath(CLEAN_DIR, "mmors_water_quality_clean.xlsx")
    XLSX.writetable(xpath,
                    [wb => frames[wb] for wb in RIVER_KEYS]...;
                    overwrite = true)
    println("Saved: ", relpath(xpath, ROOT), "  (sheets: ",
            join(RIVER_KEYS, ", "), ")")

    # per-water-body parity CSVs ------------------------------------------------
    pb = build_parity_dataset(RAW_PATH)
    cap = 0
    for wb in RIVER_KEYS
        p = joinpath(CLEAN_DIR, "mmors_" * river_slug(wb) * "_parity.csv")
        sub = pb[pb.water_body .== wb, :]
        CSV.write(p, sub)
        cap += nrow(sub)
        println("Saved: ", relpath(p, ROOT), "  (", nrow(sub), " rows)")
    end
    println("Per-river parity rows: ", cap, " = combined parity rows ",
            nrow(pb))

    # per-water-body summary ----------------------------------------------------
    rows = NamedTuple[]
    for wb in RIVER_KEYS
        sub = frames[wb]
        n_imputed = sum(length(filter(!isempty, split(v, ";")))
                        for v in sub.imputed_params)
        n_ob_pooled = count(i -> !isempty(df.outlier_params[i]),
                            findall(==(wb), df.water_body))
        n_ob_river = count(i -> !isempty(river_flags[i]),
                           findall(==(wb), df.water_body))
        push!(rows, (water_body = wb,
                     records_extracted = ext.records_per_sheet[wb],
                     duplicates_removed = get(r5.removed_dupe_per, wb, 0),
                     zero_measurement_removed = get(r5.removed_empty_per, wb, 0),
                     rows_final = nrow(sub),
                     stations = length(unique(sub.station)),
                     cells_imputed = n_imputed,
                     rows_outlier_pooled = n_ob_pooled,
                     rows_outlier_per_river = n_ob_river))
    end
    CSV.write(joinpath(RESULTS_DIR, "per_river_summary.csv"), DataFrame(rows))
    println("per_river_summary.csv: ", nrow(rows), " water bodies")

    # A6 validation -------------------------------------------------------------
    pbr = Dict(wb => pb[pb.water_body .== wb, :] for wb in RIVER_KEYS)
    val = per_river_validation(df, frames, pbr, RAW_PATH)
    CSV.write(joinpath(RESULTS_DIR, "per_river_validation.csv"), val)
    npass = count(c -> c.status == "PASS", eachrow(val))
    nfail = nrow(val) - npass
    println("per_river_validation.csv: ", nrow(val), " checks (", npass,
            " PASS, ", nfail, " FAIL)")
    for c in eachrow(val)
        c.status == "FAIL" && println("   FAIL  ", c.check, "  expected=",
                                      c.expected, "  actual=", c.actual)
    end
    @assert nfail == 0 "per-river validation failed"
    return (; fences = fences, compare = compare, frames = frames, parity = pb,
            validation = val)
end
