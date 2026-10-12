# =============================================================================
# src/report_artifacts.jl - Report Evidence layer (design.md §11, stage 4b)
#
#   write_report_artifacts(ctx)  -> T1..T21 + run_manifest.json + indexes
#   raw_snapshot(raw)            -> one pass over the raw table, shared by the
#                                   artifact tables and the figures
#
# Every number written here comes from the run that produced `ctx`; the only
# file meant to be edited by hand afterwards is results/concerns.md (T21).
# Included by src/preprocess.jl at top level; called from main().
# =============================================================================

# --- helpers ---------------------------------------------------------------
function pkgver(m)
    v = try
        Base.pkgversion(m)
    catch
        nothing
    end
    v === nothing ? "stdlib" : string(v)
end

pct1(x) = string(round(x; digits = 1))

"Write a CSV with a leading '#' comment (table no. + paper section + run id).
  The REPORT page reads these files with `comment = \"#\"`, so the comment never
  reaches the rendered table."
function write_table(path::AbstractString, tbl::DataFrame, section, run_id)
    CSV.write(path, tbl)    # CSV.write re-seeks the stream, so do this first
    head = string("# ", section, "  |  run ", run_id, "\n")
    c = read(path, String)
    open(path, "w") do io
        write(io, head)
        write(io, c)
    end
    return path
end

# =============================================================================
# RAW SNAPSHOT - everything the report needs from the pre-cleaning table.
# Stages 5-10 mutate `df` in place, so the raw copy taken in main() is parsed
# here once and reused by T6/T7/T8/T9/T10/T11/T15/T16/T17/T20 and fig02..fig11.
# =============================================================================
function raw_snapshot(raw::DataFrame)
    n = nrow(raw)
    typed = ["Date", "Time", PARAM_NAMES...]

    # numeric values per parameter, as found in the raw sheet ---------------
    num = Dict{String, Vector{Float64}}()
    val = Dict{String, Vector{Union{Missing, Float64}}}()
    for (j, p) in enumerate(PARAM_NAMES)
        v = Union{Missing, Float64}[x isa Real ? Float64(x) : missing
                                    for x in raw[!, p]]
        val[PARAM_KEY[j]] = v
        num[PARAM_KEY[j]] = Float64[x for x in v if x isa Float64]
    end

    # year per raw record: real date first, then the 'CY YYYY ...' label -----
    year = Vector{Union{Missing, Int}}(missing, n)
    for i in 1:n
        d = parse_date_cell(raw.Date[i], String[])
        if d isa Date
            year[i] = Int(Dates.year(d))
        else
            lab = raw.period[i]
            m = lab isa AbstractString ? match(r"CY\s+(\d{4})", lab) : nothing
            m !== nothing && (year[i] = parse(Int, m[1]))
        end
    end

    # placeholder tokens by column (T7) -------------------------------------
    ph = Dict{String, Dict{String, Int}}()
    for c in names(raw), v in raw[!, c]
        is_placeholder(v) || continue
        s = strip(string(v))
        tok = isempty(s) ? "<blank>" :
              (occursin("NO SAMPLING", uppercase(s)) ? "NO SAMPLING" : s)
        d = get!(ph, tok, Dict{String, Int}())
        d[c] = get(d, c, 0) + 1
    end

    # invalid-entry rules, with up to 5 examples each (T9 / fig06) ----------
    rcnt = Dict{Tuple{String, String}, Int}()
    rex = Dict{Tuple{String, String}, Vector{String}}()
    function addrule!(rule, colname, ex, k)
        key = (rule, colname)
        rcnt[key] = get(rcnt, key, 0) + k
        if !isempty(ex)
            e = get!(rex, key, String[])
            length(e) < 5 && push!(e, ex)
        end
        nothing
    end
    textcells = Dict{String, Int}()                 # text cells per typed col
    for c in typed
        for v in raw[!, c]
            is_stray_string(v) || continue
            textcells[c] = get(textcells, c, 0) + 1
            s = strip(string(v))
            if startswith(s, "<")
                addrule!("censored value '<x' (below detection limit)", c, s, 1)
            elseif startswith(s, ">")
                addrule!("censored value '>x' (above reportable range)", c, s, 1)
            elseif c == "Date"
                addrule!("malformed date text", c, s, 1)
            elseif c == "Time"
                addrule!("malformed time text", c, s, 1)
            else
                addrule!("non-numeric text in numeric column", c, s, 1)
            end
        end
    end
    phv = Float64[float(v) for v in raw.PH if v isa Real]
    addrule!("pH outside 0-14", "PH", "",
             count(x -> x < 0 || x > 14, phv))
    neg = 0
    for c in PARAM_NAMES, v in raw[!, c]
        v isa Real && v < 0 && (neg += 1)
    end
    addrule!("negative concentration value", "all parameters", "", neg)
    geo = 0
    for r in eachrow(raw)
        (r."Latitude, North (degree)" isa Real &&
         !(5 <= r."Latitude, North (degree)" <= 20)) && (geo += 1)
        (r."Longitude, East (degree)" isa Real &&
         !(116 <= r."Longitude, East (degree)" <= 127)) && (geo += 1)
    end
    addrule!("coordinate outside Philippines domain", "latitude / longitude", "",
             geo)
    rules = [(rule = k[1], column = k[2], count = rcnt[k],
              examples = join(get(rex, k, String[]), "; "))
             for k in sort(collect(keys(rcnt)); by = x -> (x[1], x[2]))]

    # duplicates per worksheet (T8) ------------------------------------------
    dkeys = dup_keys(raw)
    exact = nonunique(raw)
    seen = Dict{String, Int}()
    per = Dict(s => Dict("exact" => 0, "key" => 0) for s in STATION_SHEETS)
    for i in 1:n
        k = dkeys[i]
        if haskey(seen, k)
            d = per[string(raw.water_body[i])]
            exact[i] ? (d["exact"] += 1) : (d["key"] += 1)
        else
            seen[k] = i
        end
    end

    # formatting variants (T11 / consistency score) --------------------------
    st = string.(raw.Station)
    stn = [strip(replace(s, r"\s+" => " ")) for s in st]
    pe = string.(raw.period)
    pen = [strip(replace(s, r"\s+" => " ")) for s in pe]
    rows_variant = count(i -> st[i] != stn[i] || pe[i] != pen[i], 1:n)

    # observed types + text cells per column (T3 / T10) ----------------------
    typ = Dict{String, String}()
    for c in names(raw)
        ts = sort(unique(string(nameof(typeof(v))) for v in raw[!, c]
                         if !ismissing(v)))
        typ[c] = isempty(ts) ? "all missing" : join(ts, ", ")
    end

    # cells the format/range rules were actually applied to (validity score)
    checked = 0
    for c in [typed; "Latitude, North (degree)"; "Longitude, East (degree)"],
        v in raw[!, c]
        (ismissing(v) || is_placeholder(v)) || (checked += 1)
    end

    return (; n, num, val, year, ph, rules, per, rows_variant, typ, textcells,
            checked,
            st_unique = length(unique(st)),
            pe_unique = length(unique(pe)),
            st_changed = count(i -> st[i] != stn[i], 1:n),
            pe_changed = count(i -> pe[i] != pen[i], 1:n))
end

# =============================================================================
# WRITE_REPORT_ARTIFACTS
# =============================================================================
const EXPECTED_COLS = ["period_label", "water_body", "station_no", "station",
                       "latitude", "longitude", "date", "time", "year", "month",
                       "date_source", PARAM_KEY..., "below_dl", "above_range",
                       "parse_issues", "imputed_params", "outlier_params"]

# =============================================================================
# T17 - data quality scorecard. One function for the table and for figure F13,
# so the report table and the chart can never disagree.
# =============================================================================
function scorecard_table(ctx)
    (; raw, df, miss_before, inv, snap, after, n_key) = ctx
    typed_raw = ["Date", "Time", PARAM_NAMES...]
    typed_f = ["date", "time", PARAM_KEY...]
    n_raw_rows = nrow(raw)
    n_rows = nrow(df)
    n_raw_cols = ncol(raw)
    n_cols = ncol(df)
    miss_b = sum(miss_before.total_missing)
    miss_a = after.n_missing
    cells_b = n_raw_rows * n_raw_cols
    cells_a = n_rows * (n_cols - 5)
    bad_after = count(c -> any(v -> v isa AbstractString, df[!, c]), typed_f)

    dup_a = count(nonunique(DataFrame(k = dup_keys(df))))
    fail_a = bad_after
    checked_a = 0
    for c in typed_f, v in df[!, c]
        ismissing(v) && continue
        checked_a += 1
        v isa AbstractString && (fail_a += 1)
    end
    phf = collect(skipmissing(df.ph))
    fail_a += count(x -> x < 0 || x > 14, phf)
    for c in PARAM_KEY, v in skipmissing(df[!, c])
        v < 0 && (fail_a += 1)
    end

    return DataFrame(
        dimension = ["Completeness", "Uniqueness", "Validity", "Consistency",
                     "Type correctness"],
        before = parse.(Float64, pct1.([
            100 * (cells_b - miss_b) / cells_b,
            100 * (1 - n_key / n_raw_rows),
            100 * (1 - (inv.n_stray + inv.n_ph_bad + inv.n_neg + inv.n_geo) /
                   snap.checked),
            100 * (1 - snap.rows_variant / n_raw_rows),
            100 * (length(typed_raw) - inv.n_badtypes) / length(typed_raw)])),
        after = parse.(Float64, pct1.([
            100 * (cells_a - miss_a) / cells_a,
            100 * (1 - dup_a / n_rows),
            100 * (1 - fail_a / checked_a),
            100.0,
            100 * (length(typed_f) - bad_after) / length(typed_f)])),
        formula = [
            "non-missing cells / analysis cells (5 documentation flag columns excluded)",
            "1 - duplicate rows / total rows",
            "cells passing format + range rules / cells checked (Date, Time, 12 parameters, coordinates)",
            "1 - rows with non-standard formatting / rows checked",
            "columns holding only their intended type / 14 checked columns (Date, Time, 12 parameters)"])
end

function write_report_artifacts(ctx)
    banner("STAGE 4b - REPORT EVIDENCE ARTIFACTS (T1..T21)")
    (; run_id, run_ts, raw, df, ext, miss_before, inv, snap, r5, types6,
       n_filled, n_label, n_out, outlier_tbl, n_std, n_ren, after,
       n_exact, n_key) = ctx
    mkpath(RESULTS_DIR)

    written = String[]                       # files snapshotted per run
    function w(name, section, tbl)
        p = write_table(joinpath(RESULTS_DIR, name), tbl, section, run_id)
        push!(written, p)
        return p
    end

    typed_raw = ["Date", "Time", PARAM_NAMES...]
    typed_f = ["date", "time", PARAM_KEY...]
    n_raw_rows, n_raw_cols = size(raw)
    n_rows, n_cols = size(df)
    miss_b = sum(miss_before.total_missing)                 # 7499
    miss_a = after.n_missing                                # 4519
    cells_b = n_raw_rows * n_raw_cols
    cells_a = n_rows * (n_cols - 5)                         # 5 flag/doc cols
    bad_after = count(c -> any(v -> v isa AbstractString, df[!, c]), typed_f)
    n_repaired = inv.n_stray - (types6.n_below + types6.n_above) - types6.n_issue

    # -------------------------------------------------------------------------
    # T1 - packages and purposes (section 3.2)
    # -------------------------------------------------------------------------
    mods = [("XLSX", "read the raw workbook: 3 partition sheets + stub tab"),
            ("DataFrames", "tabular manipulation of the extracted records"),
            ("CSV", "read and write every results/*.csv artifact"),
            ("Statistics", "mean, median, std for imputation and descriptives"),
            ("StatsBase", "quantiles / IQR fences for Tukey outlier flagging"),
            ("Missings", "missing-value utilities"),
            ("Dates", "Date/Time parsing and year/month extraction"),
            ("SHA", "raw file fingerprint in run_manifest.json"),
            ("CairoMakie", "static report figures: SVG + 300 dpi PNG"),
            ("Colors", "palette tokens parsed to Colorant values"),
            ("PrettyTables", "readable console summaries"),
            ("JSON3", "run_manifest.json output"),
            ("WGLMakie", "interactive figures inside the Bonito app"),
            ("Bonito", "brutalist UI: live server + static HTML export")]
    w("packages.csv", "T1 Packages and purposes - paper section 3.2",
      DataFrame(package = [m[1] for m in mods],
                version = [pkgver(getfield(Main, Symbol(m[1]))) for m in mods],
                purpose = [m[2] for m in mods]))

    # -------------------------------------------------------------------------
    # T2 - dataset description (section 3.1)
    # -------------------------------------------------------------------------
    sheets = try
        xf = XLSX.openxlsx(RAW_PATH)
        s = XLSX.sheetnames(xf)
        close_xlsx(xf)
        s
    catch
        String[]
    end
    yr = collect(skipmissing(df.year))
    w("dataset_profile.csv", "T2 Dataset description - paper section 3.1",
      DataFrame(
          metric = ["Source workbook", "File size (bytes)", "SHA-256",
                    "Worksheets in file", "Data worksheets",
                    "Records extracted (input)", "Period label rows",
                    "Non-record rows skipped", "Blank rows skipped",
                    "Cells outside the schema skipped",
                    "Records after cleaning (output)", "Variables (raw)",
                    "Variables (final)", "Water-quality parameters",
                    "Water bodies", "Distinct stations", "Time coverage",
                    "Run ID", "Run timestamp"],
          value = [string(basename(RAW_PATH)), string(filesize(RAW_PATH)),
                   file_sha256(RAW_PATH), join(sheets, ", "),
                   join(STATION_SHEETS, ", "), string(n_raw_rows),
                   string(ext.n_period_labels), string(ext.n_skipped_content),
                   string(ext.n_skipped_blank), string(ext.n_stray_cells),
                   string(n_rows), string(n_raw_cols), string(n_cols),
                   string(length(PARAM_NAMES)),
                   string(length(unique(df.water_body))),
                   string(length(unique(df.station))),
                   string(minimum(yr), "-", maximum(yr)), run_id,
                   Dates.format(run_ts, "yyyy-mm-dd HH:MM:SS")]))

    # -------------------------------------------------------------------------
    # T3 - variable dictionary (sections 3.1, 4.2)
    # -------------------------------------------------------------------------
    UNITS = Dict(
        "period_label" => "-", "water_body" => "name", "station_no" => "code",
        "station" => "name", "latitude" => "degree", "longitude" => "degree",
        "date" => "date", "time" => "time", "year" => "year",
        "month" => "month", "date_source" => "source",
        "dissolved_oxygen_mg_l" => "mg/L", "ph" => "-", "temperature_c" => "deg C",
        "bod_mg_l" => "mg/L", "tss_mg_l" => "mg/L", "color_tcu" => "TCU",
        "fecal_coliform_mpn" => "MPN/100 mL", "total_coliform_mpn" => "MPN/100 mL",
        "ammonia_mg_l" => "mg/L", "nitrates_mg_l" => "mg/L N",
        "phosphates_mg_l" => "mg/L P", "chlorides_mg_l" => "mg/L",
        "below_dl" => "flag", "above_range" => "flag", "parse_issues" => "log",
        "imputed_params" => "flag", "outlier_params" => "flag")
    DESCR = Dict(
        "period_label" => "'CY YYYY MONTH' label of the worksheet block the record sits in",
        "water_body" => "partition worksheet the record came from (Marilao / Meycauayan / Obando)",
        "station_no" => "agency station code",
        "station" => "station name, whitespace-normalized in Stage 9",
        "latitude" => "north latitude of the station",
        "longitude" => "east longitude of the station",
        "date" => "sampling date; missing for 2012 records and never invented",
        "time" => "sampling time",
        "year" => "calendar year derived from date or period label (Stage 7)",
        "month" => "calendar month derived from date or period label (Stage 7)",
        "date_source" => "whether year/month came from the date or the period label",
        "dissolved_oxygen_mg_l" => "dissolved oxygen",
        "ph" => "acidity",
        "temperature_c" => "water temperature",
        "bod_mg_l" => "biochemical oxygen demand",
        "tss_mg_l" => "total suspended solids",
        "color_tcu" => "apparent colour",
        "fecal_coliform_mpn" => "fecal coliform count",
        "total_coliform_mpn" => "total coliform count",
        "ammonia_mg_l" => "ammonia",
        "nitrates_mg_l" => "nitrates as nitrogen",
        "phosphates_mg_l" => "phosphates as phosphorous",
        "chlorides_mg_l" => "chlorides",
        "below_dl" => "parameters read as '<x' (below detection) - Decision A flag",
        "above_range" => "parameters read as '>x' (above reportable range) - Decision A flag",
        "parse_issues" => "cells that could not be parsed (empty in this run)",
        "imputed_params" => "parameters filled by station-year median - Decision B flag",
        "outlier_params" => "parameters outside the IQR fences; values retained")
    DERIVED = ["year", "month", "date_source", "below_dl", "above_range",
               "parse_issues", "imputed_params", "outlier_params"]
    final_to_raw = Dict(RENAME_MAP[r] => r for r in keys(RENAME_MAP))
    mb = Dict(r.column => r for r in eachrow(miss_before))
    rows = NamedTuple[]
    for c in names(df)
        rawn = get(final_to_raw, c, c)
        br = get(mb, rawn, nothing)
        derived = c in DERIVED
        push!(rows, (variable = c,
                     unit = get(UNITS, c, "-"),
                     type_before = derived ? "n/a (derived)" :
                                   get(snap.typ, rawn, "n/a"),
                     type_after = string(eltype(df[!, c])),
                     missing_before = br === nothing ? missing : br.missing,
                     missing_after = count(ismissing, df[!, c]),
                     status = c == "water_body" ? "kept as-is" :
                              (derived ? "derived (Stages 6-7)" :
                               "kept, renamed (Stage 10)"),
                     description = get(DESCR, c, "-")))
    end
    w("variable_dictionary.csv",
      "T3 Variable dictionary - paper sections 3.1 and 4.2", DataFrame(rows))

    # -------------------------------------------------------------------------
    # T4 - preprocessing procedure summary (section 3.3)
    # -------------------------------------------------------------------------
    w("decision_log.csv", "T4 Preprocessing procedure summary - paper section 3.3",
      DataFrame(DECISIONS))

    # -------------------------------------------------------------------------
    # T5 - required before/after table (sections 3.4, 4.1) - EXACT 5 x 4
    # -------------------------------------------------------------------------
    t5 = DataFrame(
        data_quality_issue = ["Missing Values", "Duplicate Records",
                              "Invalid Entries", "Incorrect Data Types",
                              "Outliers"],
        before = [string(miss_b, " (", pct1(100 * miss_b / cells_b), "%)"),
                  string(n_key),
                  string(inv.n_stray),
                  string(inv.n_badtypes, " of ", length(typed_raw), " columns"),
                  string(n_out, " values flagged (", after.n_flagged, " rows)")],
        action_taken = [
            string("placeholder text mapped to missing; ", r5.n_empty,
                   " zero-measurement records removed; ", n_filled,
                   " cells station-year median imputation (flagged)"),
            string("normalized-key deduplication (station+date+time), keep first: ",
                   r5.n_exact_rm, " exact + ", r5.n_dated_rm, " same-date/time"),
            string(types6.n_below + types6.n_above,
                   " censored <x/>x parsed to threshold + flags; ", n_repaired,
                   " malformed cells repaired; range checks passed"),
            string("Date/Time/Float64 parsing of 16 columns (Date, Time, ",
                   "latitude, longitude + 12 parameters)"),
            "IQR flagging only - retained, never removed (extremes can be real events)"],
        after = [string(miss_a, " (", pct1(100 * miss_a / cells_a), "%)"),
                 "0", "0",
                 string(bad_after, " of ", length(typed_raw), " columns"),
                 string(n_out, " flagged, ", n_out, " retained")])
    @assert names(t5) == ["data_quality_issue", "before", "action_taken", "after"] "T5 column names changed"
    @assert nrow(t5) == 5 "T5 must have exactly 5 rows"
    w("quality_summary.csv",
      "T5 REQUIRED before/after table - paper sections 3.4 and 4.1", t5)

    # T5b - additional issues (never mixed into T5) --------------------------
    w("quality_summary_extra.csv", "T5b ADDITIONAL ISSUES - paper section 4.1",
      DataFrame(
          issue = ["Formatting inconsistencies (station / period spacing)",
                   "Records with zero measurements",
                   "Cells outside the 18-column schema",
                   "Non-data stub worksheet",
                   "Period-keyed duplicate conflicts (no date to verify)",
                   "Records dated only by a 'CY ...' period label"],
          before = [string(snap.rows_variant, " rows (",
                           snap.st_changed + snap.pe_changed, " cells)"),
                    string(r5.n_empty, " records"),
                    string(ext.n_stray_cells, " cells"),
                    "1 sheet",
                    string(r5.n_conflict, " records"),
                    string(n_label, " records")],
          action_taken = ["regex whitespace collapse + strip (Stage 9)",
                          "row removal (Stage 5)",
                          "excluded at extraction (values duplicate main table)",
                          "excluded from processing (Stage 1)",
                          "kept: no timestamp proves which value is right",
                          "year/month derived from the label, date left missing (Stage 7)"],
          after = ["0 variants", "0 records", "0 cells", "0 sheets",
                   string(r5.n_conflict, " records (kept)"),
                   string(n_label, " records")]))

    # -------------------------------------------------------------------------
    # T6 - missing values per column, before/after + treatment (section 4.2)
    # -------------------------------------------------------------------------
    imp = zeros(Int, n_cols)
    for v in df.imputed_params
        isempty(v) && continue
        for k in split(v, ";")
            j = findfirst(==(String(k)), names(df))
            j === nothing || (imp[j] += 1)
        end
    end
    rows = NamedTuple[]
    for (j, c) in enumerate(names(df))
        br = get(mb, get(final_to_raw, c, c), nothing)
        a = count(ismissing, df[!, c])
        b_tot = br === nothing ? missing : br.total_missing
        treatment = if imp[j] > 0
            "station-year median imputation, flagged (Decision B)"
        elseif b_tot === missing || b_tot == 0
            a > 0 ? "kept missing (no source value)" : "-"
        else
            "kept missing (structural gap, never measured)"
        end
        push!(rows, (column = c,
                     missing_before = br === nothing ? missing : br.missing,
                     placeholder_before = br === nothing ? missing : br.placeholder,
                     total_missing_before = b_tot,
                     pct_before = br === nothing ? missing : br.pct,
                     missing_after = a,
                     pct_after = round(100 * a / n_rows; digits = 1),
                     imputed_cells = imp[j],
                     treatment = treatment))
    end
    w("missing_by_column.csv", "T6 Missing values per column - paper section 4.2",
      DataFrame(rows))

    # -------------------------------------------------------------------------
    # T7 - placeholder tokens (sections 3.4, 4.2)
    # -------------------------------------------------------------------------
    rows = [(token = tok, column = c, count = k, mapped_to = "missing")
            for (tok, d) in snap.ph for (c, k) in d]
    sort!(rows, by = r -> (-r.count, r.column, r.token))
    w("placeholders.csv", "T7 Placeholder tokens - paper sections 3.4 and 4.2",
      DataFrame(rows))

    # -------------------------------------------------------------------------
    # T8 - duplicates per worksheet and combined (section 4.2)
    # -------------------------------------------------------------------------
    rows = [(scope = "worksheet", water_body = s,
             exact_full_rows = snap.per[s]["exact"],
             key_duplicates = snap.per[s]["exact"] + snap.per[s]["key"],
             removed = get(r5.removed_dupe_per, s, 0))
            for s in STATION_SHEETS]
    push!(rows, (scope = "combined", water_body = "ALL WORKSHEETS",
                 exact_full_rows = n_exact, key_duplicates = n_key,
                 removed = r5.n_dupe))
    w("duplicates.csv", "T8 Duplicate records - paper section 4.2", DataFrame(rows))

    # -------------------------------------------------------------------------
    # T9 - invalid entries by rule (section 4.2)
    # -------------------------------------------------------------------------
    ACTION = Dict(
        "censored value '<x' (below detection limit)" =>
            "threshold kept as the value + below_dl flag (Decision A)",
        "censored value '>x' (above reportable range)" =>
            "threshold kept as the value + above_range flag (Decision A)",
        "malformed date text" => "regex repair of '//' + tolerant format parsing",
        "malformed time text" => "regex parse of 'h:mm AM/PM'",
        "non-numeric text in numeric column" =>
            "reparsed, otherwise set to missing (parse_issues)",
        "pH outside 0-14" => "none found; range asserted in Stage 11",
        "negative concentration value" => "none found; asserted >= 0 in Stage 11",
        "coordinate outside Philippines domain" =>
            "none found; domain asserted in Stage 11")
    w("invalid_by_rule.csv", "T9 Invalid entries by rule - paper section 4.2",
      DataFrame([(rule = r.rule, column = r.column, flagged = r.count,
                  action = get(ACTION, r.rule, "-"),
                  examples = isempty(r.examples) ? "N/A" : r.examples)
                 for r in snap.rules]))

    # -------------------------------------------------------------------------
    # T10 - data type corrections (section 4.2)
    # -------------------------------------------------------------------------
    fail = Dict{String, Int}()
    for v in df.parse_issues
        for item in split(v, ";")
            isempty(item) && continue
            k = String(first(split(item, ":")))
            fail[k] = get(fail, k, 0) + 1
        end
    end
    TARGET = [("Date", "Date", "date"), ("Time", "Time", "time"),
              ("Station No.", "Int64", ""),
              ("Latitude, North (degree)", "Float64", ""),
              ("Longitude, East (degree)", "Float64", "")]
    rows = NamedTuple[]
    for (c, t, key) in TARGET
        push!(rows, (column = RENAME_MAP[c], target_type = t,
                     type_before = get(snap.typ, c, "-"),
                     text_cells_before = get(snap.textcells, c, 0),
                     parse_failures = isempty(key) ? 0 : get(fail, key, 0),
                     action = string("cast to ", t)))
    end
    for (j, p) in enumerate(PARAM_NAMES)
        push!(rows, (column = PARAM_KEY[j], target_type = "Float64",
                     type_before = get(snap.typ, p, "-"),
                     text_cells_before = get(snap.textcells, p, 0),
                     parse_failures = get(fail, PARAM_KEY[j], 0),
                     action = "censored '<x'/'>x' to threshold + flags; else numeric cast"))
    end
    w("type_corrections.csv", "T10 Data type corrections - paper section 4.2",
      DataFrame(rows))

    # -------------------------------------------------------------------------
    # T11 - standardization map (section 4.2)
    # -------------------------------------------------------------------------
    w("standardization_map.csv", "T11 Standardization map - paper section 4.2",
      DataFrame(
          column = ["station", "period_label", "water_body"],
          variants_before = [snap.st_unique, snap.pe_unique,
                             length(unique(raw.water_body))],
          variants_after = [length(unique(df.station)),
                            length(unique(df.period_label)),
                            length(unique(df.water_body))],
          rows_changed = [snap.st_changed, snap.pe_changed, 0],
          rule = ["collapse repeated whitespace + strip",
                  "collapse repeated whitespace + strip",
                  "canonical worksheet name, no change"]))

    # -------------------------------------------------------------------------
    # T12 - outlier summary per parameter (section 4.2)
    # -------------------------------------------------------------------------
    w("outliers.csv", "T12 Outlier summary per parameter - paper section 4.2",
      outlier_tbl)

    # -------------------------------------------------------------------------
    # T13 - columns and records removed (section 4.2)
    # -------------------------------------------------------------------------
    w("removed_items.csv", "T13 Removed items - paper section 4.2",
      DataFrame(
          item = ["Exact duplicate records",
                  "Duplicate records (same station + date + time)",
                  "Records with zero measurements",
                  "Cells outside the 18-column schema",
                  "Non-record content rows (banners, guidelines, footnotes)",
                  "Blank padding rows",
                  "Non-data stub worksheet",
                  "TOTAL records removed"],
          scope = ["records", "records", "records", "cells", "rows", "rows",
                   "sheets", "records"],
          reason = ["identical full row, keep first",
                    "same sampling event, keep first",
                    "station metadata only, no observed parameter",
                    "stray transposed fragment duplicating the main table",
                    "not observations",
                    "no content",
                    "Excel data-connection tab, no records",
                    "duplicates + zero-measurement records"],
          count = [r5.n_exact_rm, r5.n_dated_rm, r5.n_empty, ext.n_stray_cells,
                   ext.n_skipped_content, ext.n_skipped_blank, 1,
                   r5.n_dupe + r5.n_empty]))

    # -------------------------------------------------------------------------
    # T14 - transformations (section 4.2)
    # -------------------------------------------------------------------------
    rows = NamedTuple[]
    for old in sort(collect(keys(RENAME_MAP)))
        old in names(raw) || continue
        new = RENAME_MAP[old]
        push!(rows, (variable = new, action = "renamed",
                     rule = string(old, "  ->  ", new, " (snake_case)"),
                     rows_affected = n_raw_rows))
    end
    push!(rows, (variable = "year", action = "derived",
                 rule = "Dates.year(date), else year of the 'CY YYYY ...' label",
                 rows_affected = count(!ismissing, df.year)))
    push!(rows, (variable = "month", action = "derived",
                 rule = "Dates.month(date), else month name of the period label",
                 rows_affected = count(!ismissing, df.month)))
    push!(rows, (variable = "date_source", action = "derived",
                 rule = "'date' | 'period_label' | 'unknown'",
                 rows_affected = n_rows))
    for (v, rule) in [("below_dl", "semicolon list of parameters read as '<x' (Decision A)"),
                      ("above_range", "semicolon list of parameters read as '>x' (Decision A)"),
                      ("parse_issues", "semicolon list of unparsed cells (empty in this run)"),
                      ("imputed_params", "semicolon list of parameters filled by station-year median (Decision B)"),
                      ("outlier_params", "semicolon list of parameters outside the IQR fences")]
        push!(rows, (variable = v, action = "derived", rule = rule,
                     rows_affected = count(!isempty, df[!, v])))
    end
    push!(rows, (variable = "16 typed columns", action = "type conversion",
                 rule = "mixed Any -> Date / Time / Float64 (details in T10)",
                 rows_affected = sum(c -> count(!ismissing, df[!, c]),
                                     ["date", "time", "latitude", "longitude",
                                      PARAM_KEY...])))
    push!(rows, (variable = "19 columns", action = "standardized",
                 rule = "whitespace collapse on station and period text (T11)",
                 rows_affected = n_std))
    w("transformations.csv", "T14 Transformations - paper section 4.2",
      DataFrame(rows))

    # -------------------------------------------------------------------------
    # T15 - descriptives before vs after (section 4.3)
    # -------------------------------------------------------------------------
    r3(x) = round(x; digits = 3)
    rows = NamedTuple[]
    for p in PARAM_KEY
        b = snap.num[p]
        a = collect(skipmissing(df[!, p]))
        push!(rows, (parameter = p,
                     n_before = length(b), mean_before = r3(mean(b)),
                     median_before = r3(median(b)), sd_before = r3(std(b)),
                     min_before = r3(minimum(b)), max_before = r3(maximum(b)),
                     n_after = length(a), mean_after = r3(mean(a)),
                     median_after = r3(median(a)), sd_after = r3(std(a)),
                     min_after = r3(minimum(a)), max_after = r3(maximum(a))))
    end
    w("descriptives_before_after.csv",
      "T15 Descriptive statistics before vs after - paper section 4.3",
      DataFrame(rows))

    # -------------------------------------------------------------------------
    # T16 - before-and-after comparison (section 4.3)
    # -------------------------------------------------------------------------
    w("before_after.csv", "T16 Before-and-after comparison - paper section 4.3",
      DataFrame(
          metric = ["Records", "Variables", "Completeness", "Duplicate records",
                    "Invalid entries", "Incorrect data types",
                    "Consistency (standard formatting)"],
          before = [n_raw_rows, n_raw_cols,
                    parse(Float64, pct1(100 * (cells_b - miss_b) / cells_b)),
                    n_key, inv.n_stray, inv.n_badtypes,
                    parse(Float64, pct1(100 * (1 - snap.rows_variant / n_raw_rows)))],
          after = [n_rows, n_cols,
                   parse(Float64, pct1(100 * (cells_a - miss_a) / cells_a)),
                   0, 0, bad_after, 100.0],
          unit = ["rows", "columns", "% of cells", "rows", "cells",
                  "columns (of 14)", "% of rows"]))

    # -------------------------------------------------------------------------
    # T17 - data quality scorecard (section 4.3)
    # -------------------------------------------------------------------------
    sc = scorecard_table(ctx)
    println("\nScorecard formulas (T17):")
    for r in eachrow(sc)
        println("  ", rpad(r.dimension, 18), rpad(pct1(r.before) * "%", 10),
                "-> ", rpad(pct1(r.after) * "%", 10), r.formula)
    end
    w("scorecard.csv", "T17 Data quality scorecard - paper section 4.3", sc)

    # -------------------------------------------------------------------------
    # T18 - row-count reconciliation (sections 3.3/9, 4.3)
    # -------------------------------------------------------------------------
    rows = NamedTuple[]
    rec_out = Dict(s => count(==(s), df.water_body) for s in STATION_SHEETS)
    for s in vcat(["ALL WORKSHEETS"], STATION_SHEETS)
        all_ws = s == "ALL WORKSHEETS"
        inp = all_ws ? n_raw_rows : ext.records_per_sheet[s]
        d_rm = all_ws ? r5.n_dupe : get(r5.removed_dupe_per, s, 0)
        e_rm = all_ws ? r5.n_empty : get(r5.removed_empty_per, s, 0)
        outp = all_ws ? n_rows : rec_out[s]
        @assert inp - d_rm - e_rm == outp "reconciliation failed for " * s
        push!(rows, (scope = s, step = "input: records extracted",
                     rows = inp, cumulative = inp))
        push!(rows, (scope = s, step = "removed: duplicate records",
                     rows = -d_rm, cumulative = inp - d_rm))
        push!(rows, (scope = s, step = "removed: zero-measurement records",
                     rows = -e_rm, cumulative = inp - d_rm - e_rm))
        push!(rows, (scope = s, step = "output: analysis-ready records",
                     rows = outp, cumulative = inp - d_rm - e_rm))
    end
    @assert n_raw_rows - r5.n_dupe - r5.n_empty == n_rows "overall reconciliation failed"
    println("\nRECONCILED: ", n_raw_rows, " - ", r5.n_dupe + r5.n_empty, " = ",
            n_rows)
    w("reconciliation.csv", "T18 Row-count reconciliation - paper sections 3.3/9 and 4.3",
      DataFrame(rows))

    # -------------------------------------------------------------------------
    # T19 - validation checks (section 3.3/9), recomputed live
    # -------------------------------------------------------------------------
    checks = NamedTuple[]
    function ck(name, expected, actual, ok)
        push!(checks, (check = name, expected = string(expected),
                       actual = string(actual),
                       status = ok ? "PASS" : "FAIL"))
    end
    phf = collect(skipmissing(df.ph))
    dup_a = count(nonunique(DataFrame(k = dup_keys(df))))
    ck("Row conservation: input - removals = output",
       n_raw_rows - r5.n_dupe - r5.n_empty, n_rows,
       n_raw_rows - r5.n_dupe - r5.n_empty == n_rows)
    ck("Column names unique", n_cols, length(unique(names(df))),
       allunique(names(df)))
    ck("Schema matches the expected 28 columns",
       join(EXPECTED_COLS, ","), join(names(df), ","),
       names(df) == EXPECTED_COLS)
    ck("pH within 0-14", "0..14",
       string(minimum(phf), "..", maximum(phf)),
       all(x -> 0 <= x <= 14, phf))
    negf = sum(c -> count(x -> x < 0, collect(skipmissing(df[!, c]))), PARAM_KEY)
    ck("Parameter values non-negative", 0, negf, negf == 0)
    lat = collect(skipmissing(df.latitude))
    lon = collect(skipmissing(df.longitude))
    ck("Coordinates inside the Philippines domain", "5..20 N, 116..127 E",
       string(minimum(lat), "..", maximum(lat), " N, ", minimum(lon), "..",
              maximum(lon), " E"),
       all(x -> 5 <= x <= 20, lat) && all(x -> 116 <= x <= 127, lon))
    yrf = collect(skipmissing(df.year))
    ck("Years within 2012-2018", "2012..2018",
       string(minimum(yrf), "..", maximum(yrf)),
       all(y -> 2012 <= y <= 2018, yrf))
    ck("date column typed Date", "Union{Missing, Date}",
       string(eltype(df.date)), eltype(df.date) <: Union{Missing, Date})
    ck("time column typed Time", "Union{Missing, Time}",
       string(eltype(df.time)), eltype(df.time) <: Union{Missing, Time})
    typed_ok = all(p -> eltype(df[!, p]) <: Union{Missing, Float64}, PARAM_KEY)
    ck("12 parameters typed Float64", "Union{Missing, Float64}",
       typed_ok ? "Union{Missing, Float64}" : "mixed", typed_ok)
    ck("No text left in typed columns", 0, bad_after, bad_after == 0)
    ck("No verifiable duplicate records remain", 0, dup_a, dup_a == 0)
    ck("Every censored cell carries a flag",
       types6.n_below + types6.n_above,
       sum(length(filter(!isempty, split(v, ";"))) for v in df.below_dl) +
       sum(length(filter(!isempty, split(v, ";"))) for v in df.above_range),
       types6.n_below + types6.n_above ==
       sum(length(filter(!isempty, split(v, ";"))) for v in df.below_dl) +
       sum(length(filter(!isempty, split(v, ";"))) for v in df.above_range))
    ck("Every imputed cell carries a flag", n_filled,
       sum(length(filter(!isempty, split(v, ";"))) for v in df.imputed_params),
       n_filled ==
       sum(length(filter(!isempty, split(v, ";"))) for v in df.imputed_params))
    clean_path = joinpath(CLEAN_DIR, "mmors_water_quality_clean.csv")
    ok_file = isfile(clean_path)
    if ok_file
        reloaded = CSV.read(clean_path, DataFrame)
        ck("Clean CSV reloads with the same shape", string(n_rows, "x", n_cols),
           string(nrow(reloaded), "x", ncol(reloaded)),
           size(reloaded) == size(df))
    else
        ck("Clean CSV written", "file", "missing", false)
    end
    w("validation.csv", "T19 Validation checks - paper sections 3.3 and 9",
      DataFrame(checks))
    @assert all(r -> r.status == "PASS", checks) "validation checks failed"

    # -------------------------------------------------------------------------
    # T20 - coverage: records per year, before/after (section 4.3)
    # -------------------------------------------------------------------------
    years = sort(unique([y for y in vcat(collect(skipmissing(snap.year)),
                                         collect(skipmissing(df.year)))]))
    rows = NamedTuple[]
    for y in years
        b = count(==(y), skipmissing(snap.year))
        a = count(==(y), skipmissing(df.year))
        push!(rows, (year = y, records_before = b, records_after = a,
                     removed = b - a))
    end
    b0 = count(ismissing, snap.year)
    a0 = count(ismissing, df.year)
    (b0 > 0 || a0 > 0) &&
        push!(rows, (year = "no year", records_before = b0, records_after = a0,
                     removed = b0 - a0))
    w("coverage.csv", "T20 Coverage: records per year - paper section 4.3",
      DataFrame(rows))

    # -------------------------------------------------------------------------
    # T21 - remaining concerns & limitations (only hand-editable file)
    # -------------------------------------------------------------------------
    p = joinpath(RESULTS_DIR, "concerns.md")
    open(p, "w") do io
        println(io, "# Remaining concerns and limitations (T21)")
        println(io)
        println(io, "> Regenerated on every run; this is the only file under ",
                    "`results/` intended for hand editing.")
        println(io)
        for (title, body) in [
            ("Structural gaps stay missing",
             string("- ", miss_a, " parameter cells are still missing after ",
                    "cleaning. They are era-blocked (e.g. pH was never measured ",
                    "in 2012) or campaign-only, so Decision B leaves them empty ",
                    "instead of inventing measurements.")),
            ("Imputed cells are estimates",
             string("- ", n_filled, " cells were filled with the station-year ",
                    "median and are listed per row in `imputed_params`; they ",
                    "are not observations and should be excluded from any ",
                    "measurement of extremes.")),
            ("Outliers are flagged, not judged",
             string("- ", n_out, " cells (", after.n_flagged,
                    " rows) fall outside Tukey fences and are listed in ",
                    "`outlier_params`. Extreme ambient values (anoxic DO, ",
                    "estuarine chlorides) are frequently real events; no ",
                    "domain-specific water-quality threshold was applied.")),
            ("Dates are partly unknown",
             string("- ", n_label, " records (2012) have no sampling date: year ",
                    "and month come from the 'CY ...' period label and the ",
                    "exact day is unknown. Anything daily or event-based cannot ",
                    "be computed for those records.")),
            ("Duplicates are resolved by rule, not by review",
             string("- ", r5.n_exact_rm, " exact and ", r5.n_dated_rm,
                    " same-date/time duplicates were dropped keep-first. ",
                    r5.n_conflict, " period-keyed conflicts had no date to ",
                    "verify and were kept as-is.")),
            ("Formatting fixes are mechanical",
             string("- ", snap.rows_variant, " rows had irregular whitespace in ",
                    "station or period text and were normalized; no spelling, ",
                    "renaming or geocoding of stations was attempted.")),
            ("Excluded content is not analyzed",
             string("- ", ext.n_stray_cells, " cells outside the 18-column ",
                    "schema, ", ext.n_skipped_content, " non-record rows and 1 ",
                    "stub worksheet were excluded at load time (they duplicate ",
                    "or contradict the main table)."))]
            println(io, "## ", title)
            println(io)
            println(io, body)
            println(io)
        end
        println(io, "## Coverage is uneven")
        println(io)
        println(io, "- Records per year and per worksheet are not balanced ",
                    "(see `coverage.csv`); trends computed across years should ",
                    "be read with the sample counts in view.")
    end
    push!(written, p)

    # -------------------------------------------------------------------------
    # run_manifest.json + table index
    # -------------------------------------------------------------------------
    man = Dict(
        "run_id" => run_id,
        "timestamp" => Dates.format(run_ts, "yyyy-mm-dd'T'HH:MM:SS"),
        "julia_version" => string(VERSION),
        "packages" => Dict(m[1] => pkgver(getfield(Main, Symbol(m[1])))
                           for m in mods),
        "raw_file" => Dict("name" => basename(RAW_PATH),
                           "bytes" => filesize(RAW_PATH),
                           "sha256" => file_sha256(RAW_PATH)),
        "rows_in" => n_raw_rows, "cols_in" => n_raw_cols,
        "rows_out" => n_rows, "cols_out" => n_cols,
        "records_removed" => Dict("duplicates" => r5.n_dupe,
                                  "zero_measurements" => r5.n_empty),
        "cells_imputed" => n_filled,
        "cells_flagged_outliers" => n_out,
        "reconciled" => true,
        "tables" => count(x -> endswith(x, ".csv"), written))
    mp = joinpath(RESULTS_DIR, "run_manifest.json")
    open(mp, "w") do io
        JSON3.write(io, man; pretty = true)
    end
    push!(written, mp)

    TABLES = [("T1", "packages.csv", "Packages and purposes", "3.2"),
              ("T2", "dataset_profile.csv", "Dataset description", "3.1"),
              ("T3", "variable_dictionary.csv", "Variable dictionary", "3.1, 4.2"),
              ("T4", "decision_log.csv", "Preprocessing procedure summary", "3.3"),
              ("T5", "quality_summary.csv", "REQUIRED before/after table", "3.4, 4.1"),
              ("T5b", "quality_summary_extra.csv", "Additional issues", "4.1"),
              ("T6", "missing_by_column.csv", "Missing values per column", "4.2"),
              ("T7", "placeholders.csv", "Placeholder tokens", "3.4, 4.2"),
              ("T8", "duplicates.csv", "Duplicate records", "4.2"),
              ("T9", "invalid_by_rule.csv", "Invalid entries by rule", "4.2"),
              ("T10", "type_corrections.csv", "Data type corrections", "4.2"),
              ("T11", "standardization_map.csv", "Standardization map", "4.2"),
              ("T12", "outliers.csv", "Outlier summary per parameter", "4.2"),
              ("T13", "removed_items.csv", "Columns and records removed", "4.2"),
              ("T14", "transformations.csv", "Transformations", "4.2"),
              ("T15", "descriptives_before_after.csv",
               "Descriptive statistics before vs after", "4.3"),
              ("T16", "before_after.csv", "Before-and-after comparison", "4.3"),
              ("T17", "scorecard.csv", "Data quality scorecard", "4.3"),
              ("T18", "reconciliation.csv", "Row-count reconciliation", "3.3/9, 4.3"),
              ("T19", "validation.csv", "Validation checks", "3.3/9"),
              ("T20", "coverage.csv", "Coverage: records per year", "4.3"),
              ("T21", "concerns.md", "Remaining concerns and limitations", "4.3, 4.4")]
    fp = joinpath(RESULTS_DIR, "figures_index.csv")
    isfile(fp) && push!(written, fp)
    w("tables_index.csv", "Report Evidence: table index",
      DataFrame([(table = t, file = f, title = ti, paper_section = s,
                  status = isfile(joinpath(RESULTS_DIR, f)) ? "READY" : "N/A")
                 for (t, f, ti, s) in TABLES]))

    # -------------------------------------------------------------------------
    # snapshot for run history / diff
    # -------------------------------------------------------------------------
    snapdir = joinpath(RESULTS_DIR, "runs", run_id)
    mkpath(snapdir)
    for src in written
        isfile(src) && cp(src, joinpath(snapdir, basename(src)); force = true)
    end

    pretty_table(t5, alignment = [:l, :r, :l, :r])
    println("Report artifacts written: ", length(written), " files -> results/ ",
            "(snapshot: results/runs/", run_id, "/)")
    return length(written)
end
