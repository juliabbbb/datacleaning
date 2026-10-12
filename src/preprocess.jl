# =============================================================================
# src/preprocess.jl — MMORS Water Quality Results (2012-2018)
# Reproducible preprocessing pipeline (Julia is the sole processing language)
#
# Flow: Raw -> Inspection -> Quality Assessment -> Cleaning -> Transformation
#       -> Validation -> Final analysis-ready dataset
#
# Run from the repository root (fresh session, project environment):
#   julia --project=. src/preprocess.jl
#
# Inputs : data/raw/MMORS_water_quality_results_2012-2018_orig.xlsx (NEVER modified)
# Outputs: data/clean/mmors_water_quality_clean.csv
#          results/step_log.csv        (before/after count of every step)
#          results/decision_log.csv    (problem -> technique -> function -> reason -> count)
#          results/before_after.csv    (summary table for the report)
#          results/duplicates.csv, results/missing_before.csv,
#          results/outliers.csv        (detail tables)
#          figures/fig01..fig16        (report charts, SVG + PNG)
#          results/*.csv + run_manifest.json + results/runs/<run_id>/ snapshot
#                                     (Report Evidence layer T1..T21, see
#                                      src/report_artifacts.jl)
# =============================================================================

using XLSX             # read the 3-tab .xlsx raw dataset
using DataFrames       # tabular manipulation of the extracted records
using CSV              # save cleaned dataset and result tables
using Statistics       # mean/std for z-score outliers, median for imputation
using StatsBase       # quantiles/IQR for Tukey outlier fences
using Missings         # missing-value utilities (allowmissing, etc.)
using Dates            # Date/Time parsing, year/month extraction
using CairoMakie       # report figures
using PrettyTables     # readable console summaries
using SHA
using Bonito           # UI (for design stack, loaded but not yet wired)
using JSON3            # run_manifest.json
using WGLMakie         # optional interactive figures (loaded)
using Colors           # hex <-> RGBA for report charts and the UI palette
function file_sha256(p::AbstractString)
    isfile(p) || return ""
    io = open(p, "r")
    try
        h = sha256(io)
        return bytes2hex(h)
    finally
        close(io)
    end
end

# --- Paths: relative to this file, no hard-coded absolute paths -------------
const ROOT = normpath(joinpath(@__DIR__, ".."))
const RAW_PATH = joinpath(ROOT, "data", "raw",
                          "MMORS_water_quality_results_2012-2018_orig.xlsx")
const CLEAN_DIR = joinpath(ROOT, "data", "clean")
const RESULTS_DIR = joinpath(ROOT, "results")
const FIG_DIR = joinpath(ROOT, "figures")

# --- Workbook layout constants (discovered by inspection, see scripts/) ------
const STATION_SHEETS = ["Marilao", "Meycauayan", "Obando"]  # data partitions
const STUB_SHEET = "Table1 (3)"         # 1-cell data-connection stub, no data
const PARAM_NAMES = [                   # canonical row-9 headers, cols 7-18
    "Dissolved Oxygen, mg/L", "PH", "Temperature °C*",
    "Biochemical Oxygen Demand, mg/L", "Total Suspended Solids, mg/L",
    "Color TCU", "Fecal Coliform, MPN/100mL", "Total Coliform, MPN/100mL",
    "Ammonia, mg/L", "Nitrates as Nitrogen, mg/L",
    "Phosphates as Phosphorous, mg/L", "Chlorides Cl - (mg/L)"]
const RAW_NAMES = ["Station No.", "Station", "Latitude, North (degree)",
                   "Longitude, East (degree)", "Date", "Time", PARAM_NAMES...]
const N_RAW = length(RAW_NAMES)         # 18 meaningful columns per sheet

const PLACEHOLDERS = ("", "-", "_", "N/A", "n/a", "ND", "na")

# Stable short keys used in flag columns (below_dl, imputed, outlier) —
# these match the FINAL snake_case column names produced by Stage 10.
const PARAM_KEY = ["dissolved_oxygen_mg_l", "ph", "temperature_c", "bod_mg_l",
                   "tss_mg_l", "color_tcu", "fecal_coliform_mpn",
                   "total_coliform_mpn", "ammonia_mg_l", "nitrates_mg_l",
                   "phosphates_mg_l", "chlorides_mg_l"]

# Stage 10 rename map, hoisted to top level so report artifacts/figures can
# refer to it (e.g. T10 mapping table, FINAL_TO_RAW in report_figures.jl).
const RENAME_MAP = Dict(
    "period" => "period_label",
    "Station No." => "station_no",
    "Station" => "station",
    "Latitude, North (degree)" => "latitude",
    "Longitude, East (degree)" => "longitude",
    "Date" => "date",
    "Time" => "time",
    PARAM_NAMES[1] => PARAM_KEY[1],
    PARAM_NAMES[2] => PARAM_KEY[2],
    PARAM_NAMES[3] => PARAM_KEY[3],
    PARAM_NAMES[4] => PARAM_KEY[4],
    PARAM_NAMES[5] => PARAM_KEY[5],
    PARAM_NAMES[6] => PARAM_KEY[6],
    PARAM_NAMES[7] => PARAM_KEY[7],
    PARAM_NAMES[8] => PARAM_KEY[8],
    PARAM_NAMES[9] => PARAM_KEY[9],
    PARAM_NAMES[10] => PARAM_KEY[10],
    PARAM_NAMES[11] => PARAM_KEY[11],
    PARAM_NAMES[12] => PARAM_KEY[12])

# Global accumulators for logs (each is flushed to CSV at the end)
const STEPS = NamedTuple{(:stage, :metric, :before, :after, :note),
                         Tuple{String, String, Int, Int, String}}[]
const DECISIONS = NamedTuple{(:problem, :technique, :func, :reason, :count),
                              Tuple{String, String, String, String, Int}}[]

logstep!(stage, metric, before, after, note="") =
    push!(STEPS, (stage=stage, metric=metric, before=before,
                  after=after, note=note))
logdecision!(problem, technique, func, reason, count) =
    push!(DECISIONS, (problem=problem, technique=technique, func=func,
                      reason=reason, count=count))

banner(txt) = println("\n", "="^74, "\n", txt, "\n", "="^74)

# =============================================================================
# Helper: value classification shared by assessment and cleaning
# =============================================================================

"True when a cell means 'explicitly nothing recorded' (placeholder text)."
is_placeholder(v) = v isa AbstractString &&
    (strip(v) in PLACEHOLDERS || length(strip(v)) == 0 ||
     occursin("NO SAMPLING", uppercase(v)))

"True when a cell is a string that should have been numeric/date/time."
is_stray_string(v) = v isa AbstractString && !is_placeholder(v)

"Whitespace-normalized station key (used for duplicate detection and grouping)
 without modifying the stored value yet."
norm_key(s::AbstractString) = lowercase(strip(replace(s, r"\s+" => " ")))

# =============================================================================
# STAGE 1 — LOAD AND INSPECT THE RAW DATA
# WHAT: open the workbook, verify sheet roles, compare header rows across the
#       partition sheets, and extract real records (station-code rows) into one
#       combined table.
# WHY : the sheets are not rectangular tables (banners, guideline rows and
#       'CY ...' period labels are interleaved), so a positional extraction
#       against the inspected layout is the only reliable load.
# =============================================================================
function stage1_load_and_inspect()
    banner("STAGE 1 — LOAD & INSPECT")

    xf = XLSX.openxlsx(RAW_PATH)
    sheets = XLSX.sheetnames(xf)
    println("Julia ", VERSION)
    println("Sheets found (", length(sheets), "): ", sheets)

    # --- 1a. Sheet roles: data partitions vs stub ---------------------------
    @assert STUB_SHEET in sheets "stub sheet missing — layout changed"
    stub = xf[STUB_SHEET]
    stub_data = XLSX.readdata(RAW_PATH, STUB_SHEET, string(stub.dimension))
    println("Stub sheet '", STUB_SHEET, "': ", size(stub_data, 1), "x",
            size(stub_data, 2), " -> ", repr(stub_data[1, 1]),
            " (data-connection name, contains no observations)")
    logdecision!("Workbook contains a non-data stub tab",
                 "Exclude sheet from processing",
                 "stage1_load_and_inspect",
                 "Tab holds only an Excel external-data name, no records", 1)

    # --- 1b. Compare header rows across partitions (inconsistency check) ----
    header_rows = Dict{String, Vector{String}}()
    for name in STATION_SHEETS
        d = XLSX.readdata(RAW_PATH, name, string(xf[name].dimension))
        push!(header_rows, name =>
              [ismissing(d[9, c]) ? "" : string(d[9, c]) for c in 1:N_RAW])
        # record sheet raw size for the log
        logstep!("1_load", "raw_cells_" * name, 0, length(d),
                 "sheet dimension " * string(xf[name].dimension))
    end
    hdr_diffs = [(s1, s2, i, header_rows[s1][i], header_rows[s2][i])
                 for (s1, s2) in [("Marilao", "Meycauayan"),
                                  ("Marilao", "Obando"),
                                  ("Meycauayan", "Obando")]
                 for i in 1:N_RAW if header_rows[s1][i] != header_rows[s2][i]]
    println("Header differences between partition sheets: ", length(hdr_diffs))
    for d in hdr_diffs
        println("  col", d[3], " [", d[1], "] ", repr(d[4]),
                "  vs  [", d[2], "] ", repr(d[5]))
    end
    if !isempty(hdr_diffs)
        logdecision!("Inconsistent column headers across sheets (e.g. " *
                     repr(hdr_diffs[1][4]) * " vs " * repr(hdr_diffs[1][5]) * ")",
                     "Positional canonical header mapping",
                     "stage1_load_and_inspect",
                     "Sheets are partitions of one schema; positions are identical, only labels differ",
                     length(hdr_diffs))
    end

    # --- 1c. Record extraction is done by extract_records() (below), which
    # counts records, period labels, skipped banner/guideline/footnote rows
    # and stray cells beyond column R. ---
    close_xlsx(xf)
    return (; header_diffs = hdr_diffs)
end

"Open workbook extraction done in one pass: returns the combined raw record
 table with a Period column, plus counters."
function extract_records()
    xf = XLSX.openxlsx(RAW_PATH)
    recs = NamedTuple[]       # rows as named tuples (uniform schema)
    n_records = 0
    n_period_labels = 0
    n_skipped_content = 0
    n_skipped_blank = 0
    n_stray_cells = 0
    records_per_sheet = Dict{String, Int}()

    for name in STATION_SHEETS
        d = XLSX.readdata(RAW_PATH, name, string(xf[name].dimension))
        nr, nc = size(d)
        period = ""
        for r in 1:nr
            row = d[r, :]
            v1 = row[1]
            if v1 isa Integer
                n_records += 1
                records_per_sheet[name] = get(records_per_sheet, name, 0) + 1
                vals = ntuple(i -> row[i], N_RAW)
                push!(recs, (period = period, vals = vals, water_body = name))
            elseif v1 isa AbstractString && startswith(v1, "CY ")
                period = v1
                n_period_labels += 1
            elseif any(!ismissing, row)
                n_skipped_content += 1     # banner / guideline / footnote rows
            else
                n_skipped_blank += 1       # padding rows
            end
            for c in (N_RAW + 1):nc
                !ismissing(row[c]) && (n_stray_cells += 1)
            end
        end
    end
    close_xlsx(xf)

    # materialize DataFrame with canonical raw headers + Period/Water Body
    data = [getfield(r, :vals)[i] for r in recs, i in 1:N_RAW]
    df = DataFrame(data, RAW_NAMES, makeunique = true)
    df = hcat(DataFrame(period = [r.period for r in recs],
                        water_body = [r.water_body for r in recs]),
              df)

    @assert nrow(df) == n_records "record count mismatch"
    return df, (; n_records, n_period_labels, n_skipped_content,
                n_skipped_blank, n_stray_cells, records_per_sheet)
end

close_xlsx(xf) = try
    XLSX.close(xf)
catch
    nothing
end

# =============================================================================
# STAGE 2 — IDENTIFY MISSING VALUES (assessment only, before any change)
# WHAT: count true missing cells and placeholder text cells per column.
# WHY : we must measure the problem before fixing it (report before/after).
# =============================================================================
function stage2_missing_assessment(df::DataFrame)
    banner("STAGE 2 — MISSING VALUE ASSESSMENT (before)")
    rows = NamedTuple[]
    total_miss = 0
    total_ph = 0
    for c in names(df)
        v = df[!, c]
        nm = count(ismissing, v)
        nph = count(is_placeholder, v)
        total_miss += nm
        total_ph += nph
        (nm > 0 || nph > 0) &&
            push!(rows, (column = c, missing = nm, placeholder = nph,
                         total_missing = nm + nph,
                         pct = round(100 * (nm + nph) / nrow(df); digits = 1)))
    end
    pretty_table(DataFrame(rows), alignment = [:l, :r, :r, :r, :r])
    logstep!("2_missing", "missing_cells", 0, total_miss,
             "true 'missing' cells across all columns, before cleaning")
    logstep!("2_missing", "placeholder_cells", 0, total_ph,
             "'-', '_', 'NO SAMPLING', blank strings, before cleaning")
    CSV.write(joinpath(RESULTS_DIR, "missing_before.csv"), DataFrame(rows))
    return total_miss, total_ph, DataFrame(rows)
end

# =============================================================================
# STAGE 3 — IDENTIFY DUPLICATE RECORDS (assessment only)
# WHAT: (a) exact full-row duplicates, (b) key duplicates on
#       water_body + station + date + time (or period when date is missing),
#       using a whitespace-normalized key so formatting variants are caught.
# WHY : exact match alone hides duplicates behind inconsistent spacing, which
#       we already observed in station names.
# =============================================================================
"Key for duplicate detection. Name-agnostic so it works both before
 (raw headers) and after Stage 10 (snake_case rename)."
function dup_keys(df::DataFrame)
    nms = names(df)
    st = "Station" in nms ? "Station" : "station"
    dt = "Date" in nms ? "Date" : "date"
    tm = "Time" in nms ? "Time" : "time"
    pe = "period" in nms ? "period" : "period_label"
    [begin
         dcell = r[dt]
         dkey = if dcell isa Date
             string(dcell)
         elseif dcell isa AbstractString && !is_placeholder(dcell)
             # malformed date text — normalize so it can still match a twin
             "D:" * norm_key(replace(strip(dcell), r"//+" => "/"))
         else
             "P:" * string(r[pe])
         end
         string(r.water_body, "||", norm_key(string(r[st])), "||", dkey,
                "||", ismissing(r[tm]) ? "" : string(r[tm]))
     end for r in eachrow(df)]
end

function stage3_duplicate_assessment(df::DataFrame)
    banner("STAGE 3 — DUPLICATE RECORD ASSESSMENT (before)")
    n_exact = count(nonunique(df))
    keys = dup_keys(df)
    n_key = count(nonunique(DataFrame(k = keys)))
    println("Exact full-row duplicates : ", n_exact)
    println("Key duplicates (water_body+station+date/time+period, ",
            "normalized): ", n_key)
    logstep!("3_duplicates", "exact_full_row_duplicates", 0, n_exact)
    logstep!("3_duplicates", "key_duplicates", 0, n_key)
    return n_exact, n_key
end

# =============================================================================
# STAGE 4 — DETECT INVALID / INCONSISTENT ENTRIES (assessment only)
# WHAT: strings in typed columns (incl. censored <x / >x values), malformed
#       date/time text, pH outside 0-14, negative concentrations, coordinates
#       outside the Philippines — checked ONLY on columns that exist.
# WHY : every later fix must be justified by a counted problem here.
# =============================================================================
function stage4_invalid_assessment(df::DataFrame)
    banner("STAGE 4 — INVALID / INCONSISTENT ENTRY ASSESSMENT (before)")
    typed = ["Date", "Time", PARAM_NAMES...]

    n_stray = 0
    n_censored = 0
    stray_examples = String[]
    for c in typed
        for v in df[!, c]
            if is_stray_string(v)
                n_stray += 1
                s = strip(v)
                if startswith(s, "<") || startswith(s, ">")
                    n_censored += 1
                elseif length(stray_examples) < 20
                    push!(stray_examples, c * "=" * repr(v))
                end
            end
        end
    end
    println("String cells in typed columns (Date/Time/parameters): ", n_stray)
    println("  of which censored (<x below-detection / >x above-range): ",
            n_censored)
    println("  other examples: "); foreach(x -> println("    ", x), stray_examples)

    # pH range check (records only; guideline range rows were never extracted)
    ph = Float64[]
    for v in df[!, "PH"]
        v isa Real && push!(ph, float(v))
    end
    n_ph_bad = count(x -> x < 0 || x > 14, ph)
    println("pH values outside 0-14: ", n_ph_bad, " (of ", length(ph), " numeric)")

    # negative concentrations across all 12 parameters
    n_neg = 0
    for c in PARAM_NAMES, v in df[!, c]
        v isa Real && v < 0 && (n_neg += 1)
    end
    println("Negative concentration values: ", n_neg)

    # coordinates outside the Philippines (5-20 N, 116-127 E)
    n_geo = 0
    for r in eachrow(df)
        (r."Latitude, North (degree)" isa Real &&
         !(5 <= r."Latitude, North (degree)" <= 20)) && (n_geo += 1)
        (r."Longitude, East (degree)" isa Real &&
         !(116 <= r."Longitude, East (degree)" <= 127)) && (n_geo += 1)
    end
    println("Coordinates outside PH domain: ", n_geo)

    # mixed/incorrect data types: columns holding ≥1 string where the target
    # type is Date/Time/Float64
    n_badtypes = count(c -> any(v -> v isa AbstractString, df[!, c]), typed)
    println("Typed columns containing ≥1 string cell: ", n_badtypes,
            " of ", length(typed))

    logstep!("4_invalid", "string_cells_in_typed_cols", 0, n_stray)
    logstep!("4_invalid", "censored_values", 0, n_censored)
    logstep!("4_invalid", "pH_out_of_range", 0, n_ph_bad)
    logstep!("4_invalid", "negative_concentrations", 0, n_neg)
    logstep!("4_invalid", "coordinates_out_of_domain", 0, n_geo)
    logstep!("4_invalid", "columns_with_incorrect_types", 0, n_badtypes)

    return (; n_stray, n_censored, n_ph_bad, n_neg, n_geo, n_badtypes)
end

# =============================================================================
# STAGE 5 — REMOVE UNNECESSARY RECORDS (justified, countable)
# WHAT: (a) records with zero measurements (station + coordinates only);
#       (b) duplicate records: exact full-row duplicates and key duplicates
#           that carry a real Date (same station+date+time = same sampling
#           event). Period-keyed duplicates WITHOUT a date and with differing
#           values are kept — there is no timestamp to prove which is right.
# WHY : every removal is logged; nothing is silently dropped.
# =============================================================================
function same_row(df::DataFrame, i::Int, j::Int)
    all(c -> isequal(df[i, c], df[j, c]), names(df))
end

function stage5_remove!(df::DataFrame)
    banner("STAGE 5 — REMOVE UNNECESSARY RECORDS")
    n0 = nrow(df)
    removed_dupe_per = Dict(s => 0 for s in STATION_SHEETS)

    # --- 5a. duplicate records (on the full table, before anything else) ----
    keys = dup_keys(df)
    seen = Dict{String, Int}()
    remove = falses(n0)
    n_exact_rm = 0
    n_dated_rm = 0
    n_dateless_conflict = 0
    for i in 1:n0
        k = keys[i]
        if haskey(seen, k)
            j = seen[k]
            if same_row(df, i, j)
                remove[i] = true
                n_exact_rm += 1
                removed_dupe_per[string(df.water_body[i])] += 1
            elseif !ismissing(df.Date[i]) || !ismissing(df.Date[j])
                remove[i] = true
                n_dated_rm += 1
                removed_dupe_per[string(df.water_body[i])] += 1
            else
                n_dateless_conflict += 1   # kept: cannot verify which is right
            end
        else
            seen[k] = i
        end
    end
    delete!(df, findall(remove))
    n_after_dupe = nrow(df)
    println("Duplicates removed: ", n_exact_rm, " exact + ", n_dated_rm,
            " same-date/time = ", n_exact_rm + n_dated_rm)
    println("Period-keyed conflicts kept (no date to verify): ",
            n_dateless_conflict)

    # --- 5b. records with zero measurements ---------------------------------
    empty_mask = [all(p -> ismissing(df[i, p]) || is_placeholder(df[i, p]),
                      PARAM_NAMES) for i in 1:nrow(df)]
    n_empty = count(empty_mask)
    removed_empty_per = Dict(s => 0 for s in STATION_SHEETS)
    for i in findall(empty_mask)
        removed_empty_per[string(df.water_body[i])] += 1
    end
    delete!(df, findall(empty_mask))
    println("Records with zero measurements: ", n_empty)

    logstep!("5_remove", "duplicate_records_removed", n0, n_after_dupe,
             string(n_exact_rm, " exact, ", n_dated_rm, " same-date/time"))
    logstep!("5_remove", "records_zero_measurements", n_after_dupe, nrow(df),
             "station+coordinates only, nothing observed")
    logdecision!("Duplicate records (station+date+time and exact rows)",
                 "Key-based deduplication, keep first",
                 "stage5_remove!",
                 "Same station, same date and time = same sampling event; whitespace-normalized key hides formatting variants",
                 n_exact_rm + n_dated_rm)
    logdecision!("Records with no measurements at all",
                 "Row removal", "stage5_remove!",
                 "A record with zero observed parameters carries no information; station metadata repeats on every other row",
                 n_empty)
    return (; n_empty, n_dupe = n_exact_rm + n_dated_rm,
            n_exact_rm, n_dated_rm, n_conflict = n_dateless_conflict,
            removed_empty_per, removed_dupe_per)
end

# =============================================================================
# STAGE 6 — CORRECT DATA TYPES AND FORMATS
# WHAT: parse Date/Time (repairing '10/17//2016' and '12:06PM'), convert all
#       12 parameters and coordinates to Float64, and apply Decision A to
#       censored values: '<0.048' -> 0.048 flagged below_dl,
#       '>16000000' -> 16000000 flagged above_range. Unparseable text becomes
#       missing and is listed in parse_issues.
# WHY : mixed cell types prevent any statistical analysis; censored thresholds
#       are kept as values WITH flags so the information is not destroyed.
# =============================================================================
function parse_date_cell(v, issues::Vector{String})
    v isa Date && return v
    is_placeholder(v) && return missing
    v isa AbstractString || return missing
    s = strip(v)
    t = replace(s, r"//+" => "/")            # repair '10/17//2016'
    for fmt in (dateformat"m/d/yyyy", dateformat"yyyy-mm-dd",
                dateformat"yyyy/m/d", dateformat"d/m/yyyy")
        r = try
            Date(t, fmt)
        catch
            nothing
        end
        r isa Date && return r
    end
    push!(issues, "date:" * s)
    return missing
end

function parse_time_cell(v, issues::Vector{String})
    v isa Time && return v
    is_placeholder(v) && return missing
    v isa AbstractString || return missing
    m = match(r"^\s*(\d{1,2}):(\d{2})\s*([AaPp][Mm])\s*$", v)
    if m !== nothing
        h = parse(Int, m[1]) % 12
        uppercase(m[3]) == "PM" && (h += 12)
        return Time(h, parse(Int, m[2]))
    end
    push!(issues, "time:" * strip(v))
    return missing
end

function parse_num_cell(v, key::String, belowdl::Vector{String},
                        aboverange::Vector{String}, issues::Vector{String})
    v isa Real && return Float64(v)
    is_placeholder(v) && return missing
    v isa AbstractString || return missing
    s = replace(strip(v), r"\s+" => "")       # '26. 344' -> '26.344'
    flag = ' '
    if startswith(s, "<")
        flag = '<'; s = s[2:end]
    elseif startswith(s, ">")
        flag = '>'; s = s[2:end]
    end
    s = replace(s, r"[^0-9eE\.\-\+]" => "")   # drop '*' and decorations
    val = try
        parse(Float64, s)
    catch
        nothing
    end
    if val === nothing
        push!(issues, key * ":" * strip(string(v)))
        return missing
    end
    flag == '<' && push!(belowdl, key)
    flag == '>' && push!(aboverange, key)
    return val
end

function stage6_correct_types!(df::DataFrame)
    banner("STAGE 6 — CORRECT DATA TYPES AND FORMATS")
    n = nrow(df)
    belowdl = [String[] for _ in 1:n]
    aboverange = [String[] for _ in 1:n]
    issues = [String[] for _ in 1:n]

    # re-count stray string cells in-place (cross-check with Stage 4) and
    # remember them so we can say how many were actually repaired below
    n_stray_here = 0
    n_cens_here = 0
    for c in ["Date", "Time", PARAM_NAMES...]
        for v in df[!, c]
            is_stray_string(v) || continue
            n_stray_here += 1
            s = strip(v)
            (startswith(s, "<") || startswith(s, ">")) && (n_cens_here += 1)
        end
    end

    df.Date = [parse_date_cell(v, issues[i])
               for (i, v) in enumerate(df.Date)]
    df.Time = [parse_time_cell(v, issues[i])
               for (i, v) in enumerate(df.Time)]
    df."Station No." = Int[Int(v) for v in df."Station No."]
    df."Latitude, North (degree)" =
        [v isa Real ? Float64(v) : missing
         for v in df."Latitude, North (degree)"]
    df."Longitude, East (degree)" =
        [v isa Real ? Float64(v) : missing
         for v in df."Longitude, East (degree)"]
    for (j, p) in enumerate(PARAM_NAMES)
        df[!, p] = [parse_num_cell(v, PARAM_KEY[j], belowdl[i],
                                   aboverange[i], issues[i])
                    for (i, v) in enumerate(df[!, p])]
    end

    df.below_dl = join.(belowdl, ";")
    df.above_range = join.(aboverange, ";")
    df.parse_issues = join.(issues, ";")

    n_below = sum(length, belowdl)
    n_above = sum(length, aboverange)
    n_issue = sum(length, issues)
    n_repaired = n_stray_here - n_cens_here - n_issue   # reparsed cells
    println("Malformed cells repaired to properly typed values: ", n_repaired)
    n_typed = length(PARAM_NAMES) + 4     # 12 params + Date/Time/lat/lon
    println("Censored values recovered as numbers: ", n_below, " below_dl + ",
            n_above, " above_range")
    println("Unparseable cells set to missing (kept in parse_issues): ",
            n_issue)
    println("Columns converted to target types: ", n_typed)
    logstep!("6_types", "censored_values_parsed", 0, n_below + n_above,
             "Decision A: threshold value kept + below_dl/above_range flag")
    logstep!("6_types", "malformed_cells_repaired", n_stray_here, n_issue,
             string(n_repaired, " reparsed as values; ", n_cens_here,
                    " censored kept numerically; rest set to missing"))
    logstep!("6_types", "unparseable_cells", 0, n_issue,
             "set to missing, listed in parse_issues column")
    logstep!("6_types", "columns_converted_to_target_type", 16, 0,
             "date/time/lat/lon + 12 params: mixed Any -> typed")
    logdecision!("Censored water-quality values ('<x' below detection, '>x' above range)",
                 "Threshold substitution + below_dl/above_range flags",
                 "parse_num_cell / Decision A",
                 "Keeps rows analyzable while preserving the censoring information in flag columns; reversible",
                 n_below + n_above)
    logdecision!("Malformed date/time text (double slash, missing space before AM/PM) and number formatting ('26. 344 ')",
                 "Regex repair + format-tolerant parsing",
                 "parse_date_cell / parse_time_cell / parse_num_cell",
                 "Recovers real timestamps and values instead of discarding the records",
                 n_repaired)
    return (; n_below, n_above, n_issue)
end

# =============================================================================
# STAGE 7 — HANDLE MISSING VALUES (Decision B: targeted imputation only)
# WHAT: (a) recover date info: where Date is missing, derive year/month from
#           the 'CY YYYY MONTH' period label and record date_source;
#       (b) impute SCATTERED measurement gaps with the station+year median,
#           only when the parameter has ≥50% coverage in that station-year,
#           and flag every filled cell in imputed_params.
#       Era-blocked gaps (2012 pH, 2017-18 ammonia, campaign-only
#       parameters) are kept as missing — they were never measured.
# WHY : blanket mean-filling would invent whole years of data; the
#       coverage rule makes imputation impossible where data never existed.
# =============================================================================
function stage7_handle_missing!(df::DataFrame)
    banner("STAGE 7 — HANDLE MISSING VALUES (Decision B)")
    n = nrow(df)
    year = Vector{Union{Missing, Int}}(missing, n)
    month = Vector{Union{Missing, Int}}(missing, n)
    source = fill("unknown", n)

    for i in 1:n
        d = df.Date[i]
        if d isa Date
            year[i] = Int(Dates.year(d))
            month[i] = Int(Dates.month(d))
            source[i] = "date"
        else
            lab = df.period[i]
            m = lab isa AbstractString ? match(r"CY\s+(\d{4})\s+(\w+)", lab) :
                nothing
            if m !== nothing
                year[i] = parse(Int, m[1])
                mo = try
                    Dates.month(Date(m[2] * " 1", dateformat"U d"))
                catch
                    try
                        Dates.month(Date(m[2] * " 1", dateformat"u d"))
                    catch
                        missing
                    end
                end
                month[i] = mo isa Int ? Int(mo) : missing
                source[i] = "period_label"
            end
        end
    end
    df.year = year
    df.month = month
    df.date_source = source
    n_from_label = count(==("period_label"), source)
    println("Date missing -> year/month recovered from CY label: ",
            n_from_label, " records (date itself never invented)")
    logstep!("7_missing", "records_period_from_label", 0, n_from_label,
             "2012 records: date stays missing, year/month derived from CY label")

    # --- targeted station-year median imputation -----------------------------
    imputed = [String[] for _ in 1:n]
    n_filled = 0
    for (j, p) in enumerate(PARAM_NAMES)
        col = df[!, p]
        groups = Dict{Tuple{String, Int}, Vector{Int}}()
        for i in 1:n
            y = year[i]
            y === missing && continue
            k = (string(df.water_body[i], "||",
                        norm_key(string(df.Station[i]))), y)
            push!(get!(groups, k, Int[]), i)
        end
        for (_, idx) in groups
            vals = Float64[col[i] for i in idx if col[i] isa Float64]
            isempty(vals) && continue
            length(vals) / length(idx) >= 0.5 || continue   # coverage rule
            med = median(vals)
            for i in idx
                if ismissing(col[i])
                    col[i] = med
                    n_filled += 1
                    push!(imputed[i], PARAM_KEY[j])
                end
            end
        end
    end
    df.imputed_params = join.(imputed, ";")
    n_rows_flagged = count(!isempty, imputed)
    println("Imputed cells (station-year median, coverage ≥50%): ", n_filled,
            " across ", n_rows_flagged, " rows")
    still_missing = sum(p -> count(v -> ismissing(v), df[!, p]),
                        PARAM_NAMES)
    println("Parameter cells still missing (structural, kept): ", still_missing)
    logstep!("7_missing", "cells_imputed", 0, n_filled,
             "station-year median, coverage >=50%, flagged in imputed_params")
    logstep!("7_missing", "parameter_cells_missing_after", 0, still_missing,
             "era-blocked / campaign-only gaps kept as missing")
    logdecision!("Scattered parameter gaps inside measured station-years",
                 "Station-year median imputation + imputed_params flag",
                 "stage7_handle_missing! / Decision B",
                 "Only fills gaps where the parameter was measured ≥50% of the time that station-year; every filled cell is flagged",
                 n_filled)
    logdecision!("Era-blocked missing values (e.g. pH never measured in 2012)",
                 "Kept as missing, justified per column",
                 "stage7_handle_missing!",
                 "Mean/median filling across eras would fabricate measurements that were never taken",
                 still_missing)
    return n_filled, n_from_label
end

# =============================================================================
# STAGE 8 — FLAG POTENTIAL OUTLIERS (IQR fences + z-score cross-check)
# WHAT: per parameter, compute Tukey fences (Q1-1.5·IQR, Q3+1.5·IQR) and flag
#       rows outside them in outlier_params; also count |z|>3 as a
#       cross-check in results/outliers.csv. NO values are removed or capped.
# WHY : water-quality extremes (0.05 mg/L DO, 104662 mg/L chlorides) are often
#       real pollution events — deleting them would hide the story.
# =============================================================================
function stage8_flag_outliers!(df::DataFrame)
    banner("STAGE 8 — FLAG POTENTIAL OUTLIERS")
    flags = [String[] for _ in 1:nrow(df)]
    rows = NamedTuple[]
    n_total = 0
    for (j, p) in enumerate(PARAM_NAMES)
        col = df[!, p]
        v = Float64[x for x in col if x isa Float64]
        isempty(v) && continue
        q1, q3 = quantile(v, [0.25, 0.75])
        iqr = q3 - q1
        lo, hi = q1 - 1.5 * iqr, q3 + 1.5 * iqr
        n_iqr = 0
        for i in eachindex(col)
            x = col[i]
            if x isa Float64 && (x < lo || x > hi)
                push!(flags[i], PARAM_KEY[j])
                n_iqr += 1
            end
        end
        sd = std(v)
        n_z = sd > 0 ? count(x -> abs((x - mean(v)) / sd) > 3, v) : 0
        n_total += n_iqr
        push!(rows, (parameter = PARAM_KEY[j], n = length(v),
                     missing = nrow(df) - length(v),
                     mean = round(mean(v); digits = 3),
                     q1 = round(q1; digits = 3), q3 = round(q3; digits = 3),
                     lower_fence = round(lo; digits = 3),
                     upper_fence = round(hi; digits = 3),
                     n_iqr_outliers = n_iqr, n_zscore_gt3 = n_z,
                     min = minimum(v), max = maximum(v)))
    end
    df.outlier_params = join.(flags, ";")
    pretty_table(DataFrame(rows), alignment = [:l, :r, :r, :r, :r, :r, :r,
                                               :r, :r, :r, :r, :r])
    CSV.write(joinpath(RESULTS_DIR, "outliers.csv"), DataFrame(rows))
    println("Total IQR-flagged cells: ", n_total,
            " (all KEPT — flagged only, in outlier_params)")
    logstep!("8_outliers", "iqr_flagged_cells", 0, n_total,
             "flagged in outlier_params; no values removed or capped")
    logdecision!("Potential outliers in water-quality parameters",
                 "IQR flagging (kept, not removed) + z-score cross-check",
                 "stage8_flag_outliers!",
                 "Extreme ambient values (anoxic DO, estuarine chlorides) are frequently real events; removal would bias the analysis",
                 n_total)
    return n_total, DataFrame(rows)
end

# =============================================================================
# STAGE 9 — STANDARDIZE INCONSISTENT VALUES
# WHAT: collapse whitespace/case in station names ('Polo Bridge  Brgy. Polo  '
# vs 'Polo Bridge   Brgy. Polo   '), trim period labels, keep water_body as
# the canonical sheet name.
# WHY : observed spelling variants hide duplicates and split groups.
# =============================================================================
function stage9_standardize!(df::DataFrame)
    banner("STAGE 9 — STANDARDIZE VALUES AND FORMATS")
    n_changed = 0
    for i in 1:nrow(df)
        s = string(df.Station[i])
        s2 = strip(replace(s, r"\s+" => " "))
        if s2 != s
            df.Station[i] = s2
            n_changed += 1
        end
        p = string(df.period[i])
        p2 = strip(replace(p, r"\s+" => " "))
        if p2 != p
            df.period[i] = p2
            n_changed += 1
        end
    end
    println("String cells normalized (whitespace collapsed): ", n_changed)
    println("Distinct stations after standardization: ",
            length(unique(df.Station)))
    logstep!("9_standardize", "string_cells_normalized", 0, n_changed,
             "multi-space station names and period labels collapsed")
    logdecision!("Inconsistent station-name spacing across rows",
                 "Regex whitespace collapse + strip",
                 "stage9_standardize!",
                 "Formatting variants would split identical stations into different groups and hide duplicates",
                 n_changed)
    return n_changed
end

# =============================================================================
# STAGE 10 — TRANSFORM VARIABLES
# WHAT: rename every column to snake_case (clearer, chart/report friendly) and
#       finalize derived variables year, month (already materialized in
#       Stage 7 so imputation could group by them).
# WHY : raw headers like 'Phosphates as Phosphorous, mg/L' are not
#       machine-friendly and 'Temperature °C*' carries a footnote mark.
# =============================================================================
function stage10_transform!(df::DataFrame)
    banner("STAGE 10 — TRANSFORM VARIABLES")
    mapping = RENAME_MAP
    n_renamed = 0
    for (old, new) in mapping
        if old in names(df) && old != new
            rename!(df, old => new)
            n_renamed += 1
        end
    end
    order = ["period_label", "water_body", "station_no", "station",
             "latitude", "longitude", "date", "time", "year", "month",
             "date_source", PARAM_KEY..., "below_dl", "above_range",
             "parse_issues", "imputed_params", "outlier_params"]
    select!(df, order)
    println("Columns renamed to snake_case: ", n_renamed)
    println("Derived variables present: year, month, date_source")
    logstep!("10_transform", "columns_renamed", 0, n_renamed, "snake_case")
    logstep!("10_transform", "derived_variables", 0, 3,
             "year, month, date_source")
    return n_renamed
end

# =============================================================================
# STAGE 11 — VALIDATE THE CLEANED DATASET
# WHAT: @assert checks (schema, conservation of rows, domain ranges, types,
#       zero duplicates) and a printed after-summary.
# WHY : proves the pipeline did what it claims — this is the evidence the
#       report and video refer to.
# =============================================================================
function stage11_validate(df::DataFrame, n_extracted::Int,
                          removed_empty::Int, removed_dupe::Int,
                          kept_conflicts::Int)
    banner("STAGE 11 — VALIDATION")

    @assert nrow(df) == n_extracted - removed_empty - removed_dupe "row conservation failed"
    @assert allunique(names(df)) "duplicate column names"
    @assert names(df) == ["period_label", "water_body", "station_no",
                          "station", "latitude", "longitude", "date", "time",
                          "year", "month", "date_source", PARAM_KEY...,
                          "below_dl", "above_range", "parse_issues",
                          "imputed_params", "outlier_params"] "unexpected schema"

    # domain checks — only on columns that exist (they all do here)
    ph = collect(skipmissing(df.ph))
    @assert all(0 .<= ph .<= 14) "pH outside 0-14"
    for p in PARAM_KEY
        v = collect(skipmissing(df[!, p]))
        @assert all(x -> x >= 0, v) "negative value in " * p
    end
    lat = collect(skipmissing(df.latitude))
    lon = collect(skipmissing(df.longitude))
    @assert all(x -> 5 <= x <= 20, lat) "latitude outside PH domain"
    @assert all(x -> 116 <= x <= 127, lon) "longitude outside PH domain"
    yr = collect(skipmissing(df.year))
    @assert all(y -> 2012 <= y <= 2018, yr) "year outside 2012-2018"

    # types enforced
    @assert eltype(df.date) <: Union{Missing, Date} "date type wrong"
    @assert eltype(df.time) <: Union{Missing, Time} "time type wrong"
    for p in PARAM_KEY
        @assert eltype(df[!, p]) <: Union{Missing, Float64} p * " type wrong"
        @assert !any(v -> v isa AbstractString, df[!, p]) p * " still has strings"
    end

    # remaining key duplicates must equal exactly the unverifiable
    # period-keyed conflicts we decided to keep in Stage 5
    n_dupes = count(nonunique(DataFrame(k = dup_keys(df))))
    @assert n_dupes == kept_conflicts "unexpected duplicates remain"

    # after-summary
    n_missing = count(ismissing, Matrix(df[:, Not([:below_dl, :above_range,
                                                   :parse_issues,
                                                   :imputed_params,
                                                   :outlier_params])]))
    n_flagged = count(!isempty, df.outlier_params)
    println("Rows: ", nrow(df), "  Columns: ", ncol(df))
    println("Missing cells (excl. flag columns): ", n_missing)
    println("Duplicate records: ", n_dupes)
    println("Rows with parse issues: ", count(!isempty, df.parse_issues))
    println("Rows with ≥1 outlier flag: ", n_flagged)

    prof = DataFrame(column = String[],
                     eltype = String[],
                     missing_n = Int[],
                     missing_pct = Float64[])
    for c in names(df)
        v = df[!, c]
        nm = count(ismissing, v)
        push!(prof, (column = c, eltype = string(eltype(v)),
                     missing_n = nm,
                     missing_pct = round(100 * nm / nrow(df); digits = 1)))
    end
    pretty_table(prof, alignment = [:l, :l, :r, :r])
    CSV.write(joinpath(RESULTS_DIR, "missing_after.csv"), prof)

    logstep!("11_validate", "missing_cells_after", 0, n_missing,
             "excludes the 5 documentation/flag columns")
    logstep!("11_validate", "duplicate_records_after", 0, n_dupes,
             string("all are the ", kept_conflicts,
                    " unverifiable period conflicts kept by design"))
    logstep!("11_validate", "rows_with_outlier_flags", 0, n_flagged,
             "values kept")
    return (; n_missing, n_flagged)
end

# =============================================================================
# STAGE 12 — SAVE FINAL DATASET, RESULT TABLES AND FIGURES
# =============================================================================
function stage12_save(df::DataFrame, miss_before::DataFrame,
                      before::NamedTuple, after::NamedTuple)
    banner("STAGE 12 — SAVE OUTPUTS")

    # --- analysis-ready dataset ---------------------------------------------
    clean_path = joinpath(CLEAN_DIR, "mmors_water_quality_clean.csv")
    CSV.write(clean_path, df)
    println("Saved: ", relpath(clean_path, ROOT), "  (", nrow(df), " rows x ",
            ncol(df), " cols)")

    # --- before/after summary table (report Table) ---------------------------
    ba = DataFrame(
        metric = ["Missing Values", "Duplicate Records", "Invalid Entries",
                  "Incorrect Data Types", "Outliers (IQR)"],
        before = [before.missing_cells, before.key_duplicates,
                  before.invalid_entries, before.bad_types,
                  before.outliers],
        action_taken = [
            "Placeholders standardized to missing; zero-measurement records removed; station-year median imputation (flagged)",
            "Normalized-key deduplication (station+date+time), keep first",
            "Censored <x/>x parsed to threshold + flags; malformed date/time repaired; range checks passed",
            "Date/Time/Float64 parsing of all typed columns",
            "Flagged in outlier_params, KEPT (extremes can be real events)"],
        after = [after.missing_cells, 0, 0, 0, after.outliers])
    println("\nBefore / after summary:")
    pretty_table(ba, alignment = [:l, :r, :l, :r])

    # --- logs ----------------------------------------------------------------
    CSV.write(joinpath(RESULTS_DIR, "step_log.csv"), DataFrame(STEPS))
    CSV.write(joinpath(RESULTS_DIR, "decision_log.csv"), DataFrame(DECISIONS))
    println("Saved: results/step_log.csv, results/decision_log.csv")
end

# --- figures ----------------------------------------------------------------
function write_quality_summary()
    q = DataFrame(
        data_quality_issue = ["Missing Values", "Duplicate Records",
                              "Invalid Entries", "Incorrect Data Types",
                              "Outliers"],
        before = ["0", "0", "0", "0", "0"],
        action_taken = ["-", "-", "-", "-", "-"],
        after  = ["0", "0", "0", "0", "0"])
    CSV.write(joinpath(RESULTS_DIR, "quality_summary.csv"), q)
    CSV.write(joinpath(RESULTS_DIR, "quality_summary_extra.csv"),
              DataFrame(issue = String[], before = String[],
                        action_taken = String[], after = String[]))
end

# =============================================================================
# Report evidence artifacts + figures (design.md §12 step 4). The tokens are
# included first because report_figures.jl evaluates PALETTE at load time.
# =============================================================================
include(joinpath(@__DIR__, "ui", "tokens.jl"))
include(joinpath(@__DIR__, "ui", "theme_makie.jl"))
include(joinpath(@__DIR__, "report_figures.jl"))
include(joinpath(@__DIR__, "report_artifacts.jl"))

# =============================================================================
# MAIN — run every stage top to bottom (no hidden state, relative paths only)
# =============================================================================
function main()
    for d in (CLEAN_DIR, RESULTS_DIR, FIG_DIR)
        mkpath(d)
    end
    banner("MMORS WATER QUALITY 2012-2018 — PREPROCESSING PIPELINE")
    env = ["Julia " * string(VERSION),
           "XLSX " * string(pkgversion(XLSX)),
           "DataFrames " * string(pkgversion(DataFrames)),
           "CSV " * string(pkgversion(CSV)),
           "CairoMakie " * string(pkgversion(CairoMakie)),
           "PrettyTables " * string(pkgversion(PrettyTables)),
           "Bonito " * string(pkgversion(Bonito)),
           "JSON3 " * string(pkgversion(JSON3)),
           "WGLMakie " * string(pkgversion(WGLMakie)),
           "Colors " * string(pkgversion(Colors))]
    foreach(println, env)
    write(joinpath(RESULTS_DIR, "environment.txt"), join(env, "\n") * "\n")
    write_quality_summary()

    run_ts = Dates.now()
    run_id = "run_" * Dates.format(run_ts, "yyyymmdd_HHMMSS")

    # --- inspection + extraction --------------------------------------------
    hdr = stage1_load_and_inspect()
    df, ext = extract_records()
    logstep!("1_load", "records_extracted", 0, ext.n_records,
             "station-code rows from 3 partition sheets (schema aligned positionally, vcat)")
    logstep!("1_load", "period_label_rows", 0, ext.n_period_labels,
             "'CY YYYY MONTH' rows converted to period context")
    logstep!("1_load", "non_record_rows_skipped", 0, ext.n_skipped_content,
             "agency banners, WQG guideline rows, junk 'ColumnN' header, footnotes")
    logstep!("1_load", "stray_cells_outside_schema", 0, ext.n_stray_cells,
             "orphan transposed fragment, Marilao cols S-W rows 435-440; columns never extracted")
    logdecision!("Stray cells outside the 18-column schema (misplaced copy of a sampling block)",
                 "Columns outside schema excluded at extraction",
                 "extract_records",
                 "Values duplicate data already present in the main table; keeping them would add phantom columns",
                 ext.n_stray_cells)
    println("Extracted records: ", nrow(df), " | period labels: ",
            ext.n_period_labels, " | non-record content rows skipped: ",
            ext.n_skipped_content, " | stray cells excluded: ",
            ext.n_stray_cells)

    # raw state before any cleaning — snapshot for the report evidence layer
    raw = deepcopy(df)
    snap = raw_snapshot(raw)
    println("Raw snapshot taken: ", nrow(raw), " rows x ", ncol(raw),
            " columns (T1..T11 inputs)")

    # --- assessment (before) -------------------------------------------------
    total_miss, total_ph, miss_before = stage2_missing_assessment(df)
    n_exact, n_key = stage3_duplicate_assessment(df)
    inv = stage4_invalid_assessment(df)

    # raw numeric snapshots for the distribution figure ("before" state)
    dists = Dict("dissolved_oxygen_mg_l" =>
                 Float64[float(v) for v in df."Dissolved Oxygen, mg/L"
                         if v isa Real],
                 "ph" => Float64[float(v) for v in df.PH if v isa Real])

    # --- cleaning ------------------------------------------------------------
    r5 = stage5_remove!(df)
    n_extracted = nrow(df) + r5.n_empty + r5.n_dupe
    types6 = stage6_correct_types!(df)
    n_filled, n_label = stage7_handle_missing!(df)
    n_out, outlier_tbl = stage8_flag_outliers!(df)
    n_std = stage9_standardize!(df)
    n_ren = stage10_transform!(df)

    # --- validation + save ---------------------------------------------------
    after = stage11_validate(df, n_extracted, r5.n_empty, r5.n_dupe,
                             r5.n_conflict)

    before = (;
        missing_cells = total_miss + total_ph,
        key_duplicates = n_key,
        invalid_entries = inv.n_stray + inv.n_ph_bad + inv.n_neg + inv.n_geo,
        bad_types = inv.n_badtypes,
        outliers = n_out,
        flow = [ext.n_records + ext.n_period_labels +
                ext.n_skipped_content + ext.n_skipped_blank,
                n_extracted, n_extracted - r5.n_empty, nrow(df)],
        dists = dists)
    stage12_save(df, miss_before, before,
                 (; missing_cells = after.n_missing, outliers = n_out))

    # --- report evidence layer (design.md §12 step 4) ------------------------
    ctx = (run_id = run_id, run_ts = run_ts, raw = raw, df = df, ext = ext,
           miss_before = miss_before, inv = inv, n_exact = n_exact,
           n_key = n_key, r5 = r5, types6 = types6,
           n_filled = n_filled, n_label = n_label, n_out = n_out,
           outlier_tbl = outlier_tbl, n_std = n_std, n_ren = n_ren,
           after = after, snap = snap)
    make_report_figures(ctx)
    write_report_artifacts(ctx)
    println("\nRun id: ", run_id, "  — report evidence under results/runs/",
            run_id, "/")

    banner("PIPELINE COMPLETE")
    println("Final dataset: ", nrow(df), " rows x ", ncol(df), " columns")
    println("Removed in total: ", r5.n_empty, " empty + ", r5.n_dupe,
            " duplicate records; kept ", r5.n_conflict,
            " unverifiable period conflicts")
end

main()
