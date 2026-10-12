# =============================================================================
# src/report_figures.jl — report figures fig01..fig16 (design.md §8)
#
#   make_report_figures(ctx) — builds every figure that has data, writes
#                        results/figures_index.csv (missing data -> status N/A)
#
# Theme, palette and save_fig come from src/ui/theme_makie.jl (single source
# of truth, shared with the Bonito UI). Included by src/preprocess.jl after
# src/ui/tokens.jl + src/ui/theme_makie.jl; called from main().
# =============================================================================

"Short axis label for a column, keyed by both the raw header and the final
 snake_case name."
const SHORT_LABEL = Dict(
    "period" => "Period", "period_label" => "Period",
    "water_body" => "Water body",
    "Station No." => "Station no.", "station_no" => "Station no.",
    "Station" => "Station", "station" => "Station",
    "Latitude, North (degree)" => "Latitude", "latitude" => "Latitude",
    "Longitude, East (degree)" => "Longitude", "longitude" => "Longitude",
    "Date" => "Date", "date" => "Date", "Time" => "Time", "time" => "Time",
    "Dissolved Oxygen, mg/L" => "Diss. oxygen",
    "dissolved_oxygen_mg_l" => "Diss. oxygen",
    "PH" => "pH", "ph" => "pH",
    "Temperature °C*" => "Temperature", "temperature_c" => "Temperature",
    "Biochemical Oxygen Demand, mg/L" => "BOD", "bod_mg_l" => "BOD",
    "Total Suspended Solids, mg/L" => "TSS", "tss_mg_l" => "TSS",
    "Color TCU" => "Color", "color_tcu" => "Color",
    "Fecal Coliform, MPN/100mL" => "Fecal coliform",
    "fecal_coliform_mpn" => "Fecal coliform",
    "Total Coliform, MPN/100mL" => "Total coliform",
    "total_coliform_mpn" => "Total coliform",
    "Ammonia, mg/L" => "Ammonia", "ammonia_mg_l" => "Ammonia",
    "Nitrates as Nitrogen, mg/L" => "Nitrates", "nitrates_mg_l" => "Nitrates",
    "Phosphates as Phosphorous, mg/L" => "Phosphates",
    "phosphates_mg_l" => "Phosphates",
    "Chlorides Cl - (mg/L)" => "Chlorides", "chlorides_mg_l" => "Chlorides",
    "year" => "Year", "month" => "Month", "date_source" => "Date source",
    "below_dl" => "Below DL", "above_range" => "Above range",
    "parse_issues" => "Parse issues", "imputed_params" => "Imputed",
    "outlier_params" => "Outliers")
slab(name) = get(SHORT_LABEL, name, name)

const FINAL_TO_RAW = Dict{String, String}(v => k for (k, v) in RENAME_MAP)

const TYPED_RAW = ["Date", "Time", PARAM_NAMES...]

ftitle(fig, txt) = Label(fig[0, 1], txt; fontsize = 20, font = :bold,
                          color = col(INK), tellwidth = false)

# =============================================================================
# F1 — pipeline workflow (block diagram)
# =============================================================================
function fig01_workflow(fd)
    steps = [
        ("1  RAW DATASET",
         string(fd.n_raw_rows, " records | ", fd.n_raw_cols,
                " variables | 3 worksheets"), AMBER),
        ("2  DATA INSPECTION",
         string(fd.ext.n_period_labels, " period labels | ",
                fd.ext.n_skipped_content, " rows skipped | ",
                fd.ext.n_stray_cells, " stray cells excluded"), BUTTER),
        ("3  QUALITY ASSESSMENT",
         string(pct1miss(fd), " missing | ", fd.n_key, " duplicates | ",
                fd.inv.n_stray, " invalid | ", fd.inv.n_badtypes, "/",
                length(TYPED_RAW), " wrong types"), AMBER),
        ("4  CLEANING",
         string("-", fd.r5.n_dupe, " duplicates | -", fd.r5.n_empty,
                " records without measurements | ", fd.n_filled,
                " cells imputed"), BUTTER),
        ("5  TRANSFORMATION",
         string("19 columns renamed | 3 derived | ", fd.n_std,
                " cells standardized"), AMBER),
        ("6  VALIDATION",
         "all assertions PASS | 0 duplicates | 0 invalid entries", BUTTER),
        ("7  FINAL DATASET",
         string(fd.n_rows, " records x ", fd.n_cols,
                " variables | analysis-ready"), MINT)]
    fig = Figure(size = (1180, 1330))
    ftitle(fig, "FIG. 1. PREPROCESSING WORKFLOW — 7 STAGES")
    ax = Axis(fig[1, 1]; backgroundcolor = col(PAPER))
    hidedecorations!(ax)
    hidespines!(ax)
    for (i, (t, sub, c)) in enumerate(steps)
        y = -(i - 1) * 1.5
        poly!(ax, Rect2f(0.0, y - 1.05, 1.0, 1.05); color = col(c),
              strokecolor = col(INK), strokewidth = 3)
        text!(ax, t; position = (0.035, y - 0.38), fontsize = 21, font = :bold)
        text!(ax, sub; position = (0.035, y - 0.74), fontsize = 15)
        i < length(steps) &&
            arrows!(ax, [0.5], [y - 1.07], [0.0], [-0.36]; color = col(INK),
                    linewidth = 3, arrowsize = 18)
    end
    ax.limits = (-0.02, 1.02, -9.35, 0.18)
    fig
end

pct1miss(fd) = string(sum(fd.miss_before.total_missing), " cells")

# =============================================================================
# F2 — missing values per column, raw
# =============================================================================
function fig02_missing_raw(fd)
    mb = filter(r -> r.total_missing > 0, fd.miss_before)
    isempty(mb) && error("no missing values to plot")
    sort!(mb, :total_missing; rev = true)
    n = nrow(mb)
    fig = Figure(size = (1020, 110 + 33n))
    ftitle(fig, "FIG. 2. MISSING VALUES PER COLUMN — RAW TABLE")
    ax = Axis(fig[1, 1]; xlabel = "% of records missing or placeholder text",
              yticks = (1:n, [slab(c) for c in mb.column]), yreversed = true)
    barplot!(ax, collect(1:n), mb.pct; direction = :x, color = col(BUTTER),
             strokewidth = 2, strokecolor = col(INK))
    for (i, v) in enumerate(mb.pct)
        text!(ax, pct1(v) * "%";
              position = (Float64(v), Float64(i)),
              align = (:left, :center), offset = (8, 0), fontsize = 13,
              font = :bold)
    end
    ax.limits = (0, maximum(mb.pct) * 1.18, 0.5, Float64(n) + 0.5)
    fig
end

# =============================================================================
# F3 — missing values per column, before vs after
# =============================================================================
function fig03_missing_before_after(fd)
    rows = NamedTuple[]
    for c in fd.ancols
        rawn = get(FINAL_TO_RAW, c, c)
        b = haskey(fd.bmiss, rawn) ? Float64(fd.bmiss[rawn].pct) : 0.0
        a = 100 * fd.amiss[c] / fd.n_rows
        (b > 0 || a > 0) && push!(rows, (column = c, b = b, a = a))
    end
    isempty(rows) && error("no missing values to plot")
    sort!(rows, by = r -> -r.b)
    n = length(rows)
    fig = Figure(size = (1080, 120 + 34n))
    ftitle(fig, "FIG. 3. MISSING VALUES PER COLUMN — BEFORE vs AFTER")
    ax = Axis(fig[1, 1]; xlabel = "% of records with no value",
              yticks = (1:n, [slab(r.column) for r in rows]),
              yreversed = true)
    barplot!(ax, collect(1:n) .- 0.20, [r.b for r in rows]; direction = :x,
             color = col(AMBER), strokewidth = 2, strokecolor = col(INK),
             label = "before")
    barplot!(ax, collect(1:n) .+ 0.20, [r.a for r in rows]; direction = :x,
             color = col(MINT), strokewidth = 2, strokecolor = col(INK),
             label = "after")
    axislegend(ax; position = :rt)
    ax.limits = (0, maximum(max(r.b, r.a) for r in rows) * 1.15,
                 0.5, Float64(n) + 0.5)
    fig
end

# =============================================================================
# F4 — missingness pattern (rows binned x columns)
# =============================================================================
function fig04_missingness(fd)
    raw = fd.raw
    cols = names(raw)
    nr = nrow(raw)
    nb = 40
    M = zeros(length(cols), nb)
    for (j, c) in enumerate(cols)
        v = raw[!, c]
        cnt = zeros(nb)
        mis = zeros(nb)
        for i in 1:nr
            b = clamp(ceil(Int, i * nb / nr), 1, nb)
            cnt[b] += 1
            (ismissing(v[i]) || is_placeholder(v[i])) && (mis[b] += 1)
        end
        for b in 1:nb
            M[j, b] = cnt[b] > 0 ? mis[b] / cnt[b] : 0.0
        end
    end
    fig = Figure(size = (1240, 720))
    ftitle(fig, "FIG. 4. MISSINGNESS PATTERN — RAW TABLE")
    ax = Axis(fig[1, 1];
              xlabel = "row block (1 = first records, 40 = last)",
              yticks = (1:length(cols), [slab(c) for c in cols]),
              yreversed = true, xticks = (5:5:nb, string.(5:5:nb)))
    hp = heatmap!(ax, M; colorrange = (0, 1), interpolate = false,
                  colormap = cgrad([col(PAPER), col(BUTTER)]))
    Colorbar(fig[1, 2], hp; width = 16, label = "share missing (0 = complete)")
    ax.limits = (0.5, Float64(nb) + 0.5, 0.5, Float64(length(cols)) + 0.5)
    fig
end

# =============================================================================
# F5 — record flow: raw -> final (waterfall)
# =============================================================================
function fig05_waterfall(fd)
    raw = fd.n_raw_rows
    d_rm = fd.r5.n_dupe
    e_rm = fd.r5.n_empty
    lvl1 = raw - d_rm
    lvl2 = lvl1 - e_rm
    steps = [("RAW RECORDS", 0.0, Float64(raw), AMBER, string(raw)),
             (string("-", d_rm, " DUPLICATES"), Float64(lvl1), Float64(raw),
              SKY, string("-", d_rm)),
             (string("-", e_rm, " NO MEASUREMENTS"), Float64(lvl2),
              Float64(lvl1), BUTTER, string("-", e_rm)),
             ("ANALYSIS-READY", 0.0, Float64(fd.n_rows), MINT,
              string(fd.n_rows))]
    fig = Figure(size = (1040, 700))
    ftitle(fig, "FIG. 5. RECORD FLOW — RAW TO FINAL DATASET")
    ax = Axis(fig[1, 1]; ylabel = "records",
              xticks = (1:4, [s[1] for s in steps]))
    levels = [raw, lvl1, lvl2]                  # dashed connectors
    for (i, (lab, lo, hi, c, vlab)) in enumerate(steps)
        poly!(ax, Rect2f(i - 0.32, lo, 0.64, max(hi - lo, 0.001));
              color = col(c), strokecolor = col(INK), strokewidth = 2)
        text!(ax, vlab; position = (i, hi + raw * 0.02),
              align = (:center, :bottom), fontsize = 17, font = :bold)
        if i < 4
            yl = levels[i]
            lines!(ax, [i + 0.32, i + 1 - 0.32], [yl, yl]; color = col(INK),
                   linewidth = 1, linestyle = :dot)
        end
    end
    text!(ax, string("invalid entries: ", fd.inv.n_stray,
                     " repaired in place, 0 records removed");
          position = (0.62, 0.02), space = :relative, align = (:left, :bottom),
          fontsize = 13)
    ax.limits = (0.5, 4.5, 0, raw * 1.16)
    fig
end

# =============================================================================
# F6 — invalid entries by rule
# =============================================================================
const RULE_LABEL = Dict(
    "censored value '<x' (below detection limit)" => "'<x'  below detection limit",
    "censored value '>x' (above reportable range)" => "'>x'  above reportable range",
    "malformed date text" => "malformed date text",
    "malformed time text" => "malformed time text",
    "non-numeric text in numeric column" => "non-numeric text",
    "pH outside 0-14" => "pH outside 0-14",
    "negative concentration value" => "negative concentration",
    "coordinate outside Philippines domain" => "coordinate outside PH domain")

function fig06_invalid_by_rule(fd)
    agg = Dict{String, Int}()
    for r in fd.snap.rules
        agg[r.rule] = get(agg, r.rule, 0) + r.count
    end
    rows = sort(collect(agg); by = last, rev = true)
    filter!(p -> last(p) > 0, rows)
    isempty(rows) && error("no invalid entries found")
    n = length(rows)
    fig = Figure(size = (1140, 150 + 52n))
    ftitle(fig, "FIG. 6. INVALID ENTRIES BY RULE — RAW TABLE")
    ax = Axis(fig[1, 1]; xlabel = "cells flagged",
              yticks = (1:n, [get(RULE_LABEL, first(r), first(r)) for r in rows]),
              yreversed = true)
    barplot!(ax, collect(1:n), [Float64(last(r)) for r in rows];
             direction = :x, color = col(VERMILION), strokewidth = 2,
             strokecolor = col(INK))
    for (i, r) in enumerate(rows)
        text!(ax, string(last(r));
              position = (Float64(last(r)), Float64(i)),
              align = (:left, :center), offset = (8, 0), fontsize = 14,
              font = :bold)
    end
    ax.limits = (0, maximum(last(r) for r in rows) * 1.15, 0.5, Float64(n) + 0.5)
    fig
end

# =============================================================================
# F7 — data types before vs after (stacked)
# =============================================================================
function fig07_types(fd)
    nchk = length(TYPED_RAW)
    data = [("BEFORE", nchk - fd.inv.n_badtypes, fd.inv.n_badtypes),
            ("AFTER", nchk - fd.bad_after, fd.bad_after)]
    fig = Figure(size = (760, 640))
    ftitle(fig, "FIG. 7. DATA TYPES BEFORE vs AFTER")
    ax = Axis(fig[1, 1]; ylabel = "checked columns",
              xticks = (1:2, [d[1] for d in data]), yticks = 0:2:14)
    for (i, (lab, ok, bad)) in enumerate(data)
        poly!(ax, Rect2f(i - 0.28, 0, 0.56, Float64(ok)); color = col(MINT),
              strokecolor = col(INK), strokewidth = 2)
        bad > 0 &&
            poly!(ax, Rect2f(i - 0.28, Float64(ok), 0.56, Float64(bad));
                  color = col(VERMILION), strokecolor = col(INK),
                  strokewidth = 2)
        text!(ax, string(ok, " correct"); position = (i, Float64(ok) / 2),
              align = (:center, :center), fontsize = 15, font = :bold)
        bad > 0 &&
            text!(ax, string(bad, " incorrect");
                  position = (i, Float64(ok) + Float64(bad) / 2),
                  align = (:center, :center), fontsize = 15, font = :bold)
        text!(ax, string(nchk, " checked"); position = (i, Float64(nchk)),
              align = (:center, :bottom), fontsize = 14, offset = (0, 8))
    end
    text!(ax, "MINT = intended type   VERMILION = text in a typed column";
          position = (0.5, 1.0), space = :relative, align = (:left, :top),
          fontsize = 13)
    ax.limits = (0.5, 2.5, 0, nchk * 1.18)
    fig
end

# =============================================================================
# F8 — outliers per key parameter (boxplots, robust scale)
# =============================================================================
const BOX8 = [("dissolved_oxygen_mg_l", "DO"), ("ph", "pH"),
              ("temperature_c", "Temp"), ("bod_mg_l", "BOD"),
              ("tss_mg_l", "TSS"), ("ammonia_mg_l", "NH3"),
              ("nitrates_mg_l", "NO3"), ("chlorides_mg_l", "Cl")]

function fig08_boxplots(fd)
    df = fd.df
    xs = Int[]
    ys = Float64[]
    fx = Int[]
    fy = Float64[]
    for (j, (p, _)) in enumerate(BOX8)
        v = collect(skipmissing(df[!, p]))
        isempty(v) && continue
        q1, q3 = quantile(v, [0.25, 0.75])
        iqr = q3 - q1
        sc = iqr > 0 ? iqr : (std(v) > 0 ? std(v) : 1.0)
        med = median(v)
        for x in v
            z = (x - med) / sc
            push!(xs, j)
            push!(ys, z)
            if x < q1 - 1.5 * iqr || x > q3 + 1.5 * iqr
                push!(fx, j)
                push!(fy, z)
            end
        end
    end
    fig = Figure(size = (1240, 720))
    ftitle(fig, "FIG. 8. OUTLIERS PER KEY PARAMETER — FLAGGED, NOT REMOVED")
    ax = Axis(fig[1, 1];
              xlabel = "parameter (robust scale: (value - median) / IQR)",
              ylabel = "robust value",
              xticks = (1:length(BOX8), [l for (_, l) in BOX8]))
    boxplot!(ax, xs, ys; width = 0.55, color = col(MINT), strokewidth = 2,
             strokecolor = col(INK), whiskerwidth = 0.6)
    scatter!(ax, fx, fy; color = col(LAVENDER), strokewidth = 1.5,
             strokecolor = col(INK), markersize = 11)
    text!(ax, string(length(fx), " IQR-flagged values (lavender), all kept");
          position = (0.01, 0.99), space = :relative, align = (:left, :top),
          fontsize = 14, font = :bold)
    fig
end

# =============================================================================
# F9 — distributions before vs after (paired histograms)
# =============================================================================
function fig09_distributions(fd)
    df = fd.df
    fig = Figure(size = (1520, 880))
    ftitle(fig, "FIG. 9. DISTRIBUTIONS BEFORE vs AFTER  |  amber = raw, mint = cleaned")
    for (k, (p, lab)) in enumerate(BOX8)
        ax = Axis(fig[cld(k, 4), mod1(k, 4)];
                  xlabel = lab, ylabel = "records")
        b = fd.snap.num[p]
        a = collect(skipmissing(df[!, p]))
        (isempty(b) || isempty(a)) && continue
        allv = vcat(b, a)
        med = median(allv)
        use_log = minimum(allv) > 0 && med > 0 && maximum(allv) / med > 50
        tr = use_log ? log10 : identity
        bb = tr.(b)
        aa = tr.(a)
        lo = min(minimum(bb), minimum(aa))
        hi = max(maximum(bb), maximum(aa))
        edges = hi > lo ? range(lo, hi; length = 31) : [lo, hi]
        hist!(ax, bb; bins = edges, color = col(AMBER, 0.70),
              strokewidth = 1, strokecolor = col(INK))
        hist!(ax, aa; bins = edges, color = col(MINT, 0.70),
              strokewidth = 1, strokecolor = col(INK))
        ax.title = use_log ? string(lab, "  [log10]") : lab
    end
    fig
end

# =============================================================================
# F10 — central tendency by year with spread (median + IQR band)
# =============================================================================
function fig10_yearly_trend(fd)
    df = fd.df
    p = "dissolved_oxygen_mg_l"
    yrs = sort(unique(vcat(collect(skipmissing(fd.snap.year)),
                           collect(skipmissing(df.year)))))
    bb = NamedTuple[]
    aa = NamedTuple[]
    for y in yrs
        bv = Float64[fd.snap.val[p][i] for i in 1:length(fd.snap.val[p])
                     if fd.snap.year[i] == y &&
                        fd.snap.val[p][i] isa Float64]
        av = Float64[df[!, p][i] for i in 1:nrow(df)
                     if df.year[i] isa Int && df.year[i] == y &&
                        df[!, p][i] isa Float64]
        length(bv) >= 3 && push!(bb, (y = y, med = median(bv),
                                      q1 = quantile(bv, 0.25),
                                      q3 = quantile(bv, 0.75)))
        length(av) >= 3 && push!(aa, (y = y, med = median(av),
                                      q1 = quantile(av, 0.25),
                                      q3 = quantile(av, 0.75)))
    end
    (isempty(bb) || isempty(aa)) && error("not enough yearly data")
    fig = Figure(size = (1080, 660))
    ftitle(fig, "FIG. 10. DISSOLVED OXYGEN BY YEAR — MEDIAN AND IQR")
    ax = Axis(fig[1, 1]; xlabel = "year", ylabel = "dissolved oxygen (mg/L)",
              xticks = yrs)
    band!(ax, [r.y for r in bb], [r.q1 for r in bb], [r.q3 for r in bb];
          color = col(AMBER, 0.35))
    lines!(ax, [r.y for r in bb], [r.med for r in bb]; color = col(AMBER),
           linewidth = 3)
    scatter!(ax, [r.y for r in bb], [r.med for r in bb]; color = col(AMBER),
             strokewidth = 2, strokecolor = col(INK), markersize = 12)
    band!(ax, [r.y for r in aa], [r.q1 for r in aa], [r.q3 for r in aa];
          color = col(MINT, 0.35))
    lines!(ax, [r.y for r in aa], [r.med for r in aa]; color = col(MINT),
           linewidth = 3, linestyle = :dash)
    scatter!(ax, [r.y for r in aa], [r.med for r in aa]; color = col(MINT),
             strokewidth = 2, strokecolor = col(INK), markersize = 12)
    text!(ax, "amber = raw records   mint = cleaned records";
          position = (0.01, 0.99), space = :relative, align = (:left, :top),
          fontsize = 14, font = :bold)
    ax.limits = (minimum(yrs) - 0.15, maximum(yrs) + 0.15, nothing, nothing)
    fig
end

# =============================================================================
# F11 — records by year, before vs after
# =============================================================================
function fig11_records_by_year(fd)
    df = fd.df
    yrs = sort(unique(vcat(collect(skipmissing(fd.snap.year)),
                           collect(skipmissing(df.year)))))
    b = [count(==(y), skipmissing(fd.snap.year)) for y in yrs]
    a = [count(==(y), skipmissing(df.year)) for y in yrs]
    fig = Figure(size = (1040, 640))
    ftitle(fig, "FIG. 11. RECORDS BY YEAR — RAW vs CLEANED")
    ax = Axis(fig[1, 1]; ylabel = "records", xticks = (yrs, string.(yrs)),
              xlabel = "year")
    barplot!(ax, Float64.(yrs) .- 0.20, Float64.(b); color = col(AMBER),
             strokewidth = 2, strokecolor = col(INK), label = "raw")
    barplot!(ax, Float64.(yrs) .+ 0.20, Float64.(a); color = col(MINT),
             strokewidth = 2, strokecolor = col(INK), label = "cleaned")
    for (i, y) in enumerate(yrs)
        text!(ax, string(b[i]); position = (Float64(y) - 0.20, Float64(b[i])),
              align = (:center, :bottom), fontsize = 12, offset = (0, 4))
        text!(ax, string(a[i]); position = (Float64(y) + 0.20, Float64(a[i])),
              align = (:center, :bottom), fontsize = 12, offset = (0, 4))
    end
    axislegend(ax; position = :rt)
    ax.limits = (nothing, nothing, 0, maximum(vcat(b, a)) * 1.15)
    fig
end

# =============================================================================
# F12 — completeness by column (dumbbell)
# =============================================================================
function fig12_completeness(fd)
    rows = NamedTuple[]
    for c in fd.ancols
        rawn = get(FINAL_TO_RAW, c, c)
        b = haskey(fd.bmiss, rawn) ?
            100 * (1 - fd.bmiss[rawn].total_missing / fd.n_raw_rows) : 100.0
        a = 100 * (1 - fd.amiss[c] / fd.n_rows)
        (b < 100 || a < 100) && push!(rows, (column = c, b = b, a = a))
    end
    isempty(rows) && error("no column has any missing values")
    sort!(rows, by = r -> r.b)
    n = length(rows)
    xlo = min(minimum(r.b for r in rows), minimum(r.a for r in rows)) - 3.0
    xlo = max(xlo, 0.0)
    fig = Figure(size = (1080, 130 + 30n))
    ftitle(fig, "FIG. 12. COMPLETENESS BY COLUMN — BEFORE -> AFTER")
    ax = Axis(fig[1, 1]; xlabel = "% of records with a value",
              xticks = (0:20:100, string.(0:20:100)),
              yticks = (1:n, [slab(r.column) for r in rows]),
              yreversed = true, xgridvisible = true)
    for (i, r) in enumerate(rows)
        lines!(ax, [r.b, r.a], [Float64(i), Float64(i)];
               color = r.a >= r.b ? col(MINT) : col(SKY), linewidth = 3)
    end
    scatter!(ax, [r.b for r in rows], Float64.(1:n); color = col(AMBER),
             strokewidth = 2, strokecolor = col(INK), markersize = 13)
    scatter!(ax, [r.a for r in rows], Float64.(1:n); color = col(MINT),
             strokewidth = 2, strokecolor = col(INK), markersize = 13)
    text!(ax, "AMBER = raw   MINT = cleaned";
          position = (0.0, 1.0), space = :relative, align = (:left, :top),
          fontsize = 13, font = :bold)
    ax.limits = (xlo, 100.6, 0.5, Float64(n) + 0.5)
    fig
end

# =============================================================================
# F13 — data quality scorecard
# =============================================================================
function fig13_scorecard(fd)
    sc = scorecard_table(fd.ctx)
    n = nrow(sc)
    fig = Figure(size = (1120, 150 + 76n))
    ftitle(fig, "FIG. 13. DATA QUALITY SCORECARD — BEFORE vs AFTER")
    ax = Axis(fig[1, 1]; xlabel = "score (%)", xticks = (0:20:100, string.(0:20:100)),
              yticks = (1:n, sc.dimension), yreversed = true)
    barplot!(ax, collect(1:n) .- 0.20, sc.before; direction = :x,
             color = col(AMBER), strokewidth = 2, strokecolor = col(INK),
             label = "before")
    barplot!(ax, collect(1:n) .+ 0.20, sc.after; direction = :x,
             color = col(MINT), strokewidth = 2, strokecolor = col(INK),
             label = "after")
    for (i, r) in enumerate(eachrow(sc))
        text!(ax, pct1(r.before) * "%";
              position = (r.before == 0 ? 0.5 : r.before, Float64(i) - 0.20),
              align = (:left, :center), offset = (6, 0), fontsize = 12,
              font = :bold)
        text!(ax, pct1(r.after) * "%";
              position = (r.after, Float64(i) + 0.20),
              align = (:left, :center), offset = (6, 0), fontsize = 12,
              font = :bold)
    end
    axislegend(ax; position = :rt)
    ax.limits = (0, 115, 0.5, Float64(n) + 0.5)
    fig
end

# =============================================================================
# F14 — standardization effect
# =============================================================================
function fig14_standardization(fd)
    cats = ["Station names", "Period labels"]
    b = [Float64(fd.snap.st_unique), Float64(fd.snap.pe_unique)]
    a = [Float64(length(unique(fd.df.station))),
         Float64(length(unique(fd.df.period_label)))]
    ymax = maximum(vcat(b, a))
    fig = Figure(size = (940, 620))
    ftitle(fig, "FIG. 14. STANDARDIZATION EFFECT — TEXT VARIANTS")
    ax = Axis(fig[1, 1]; ylabel = "distinct values", xticks = (1:2, cats),
              yticks = 0:5:ceil(Int, ymax))
    barplot!(ax, [0.80, 1.80], b; color = col(BLUSH), strokewidth = 2,
             strokecolor = col(INK), label = "raw variants")
    barplot!(ax, [1.20, 2.20], a; color = col(MINT), strokewidth = 2,
             strokecolor = col(INK), label = "after Stage 9")
    for (i, x) in enumerate(b)
        text!(ax, string(Int(x)); position = (i - 0.20, x),
              align = (:center, :bottom), fontsize = 14, font = :bold,
              offset = (0, 5))
        text!(ax, string(Int(a[i])); position = (i + 0.20, a[i]),
              align = (:center, :bottom), fontsize = 14, font = :bold,
              offset = (0, 5))
    end
    axislegend(ax; position = :rt)
    ax.limits = (0.5, 2.5, 0, ymax * 1.22)
    fig
end

# =============================================================================
# F15 — share of below-detection-limit values per parameter
# =============================================================================
function fig15_below_detection(fd)
    df = fd.df
    cnt = zeros(Int, length(PARAM_KEY))
    for v in df.below_dl
        for k in split(v, ";")
            isempty(k) && continue
            j = findfirst(==(String(k)), PARAM_KEY)
            j === nothing || (cnt[j] += 1)
        end
    end
    rows = [(PARAM_KEY[j], 100 * cnt[j] / max(count(!ismissing, df[!, PARAM_KEY[j]]), 1),
             cnt[j]) for j in eachindex(PARAM_KEY) if cnt[j] > 0]
    isempty(rows) && error("no below-detection values found")
    sort!(rows, by = r -> -r[2])
    n = length(rows)
    fig = Figure(size = (1080, 120 + 46n))
    ftitle(fig, "FIG. 15. BELOW-DETECTION-LIMIT (`<x`) SHARE PER PARAMETER")
    ax = Axis(fig[1, 1]; xlabel = "% of measured values read as '<x'",
              yticks = (1:n, [slab(r[1]) for r in rows]), yreversed = true)
    barplot!(ax, collect(1:n), [r[2] for r in rows]; direction = :x,
             color = col(AMBER), strokewidth = 2, strokecolor = col(INK))
    for (i, r) in enumerate(rows)
        text!(ax, pct1(r[2]) * "%";
              position = (r[2], Float64(i)),
              align = (:left, :center), offset = (8, 0), fontsize = 14,
              font = :bold)
    end
    ax.limits = (0, maximum(r[2] for r in rows) * 1.18, 0.5, Float64(n) + 0.5)
    fig
end

# =============================================================================
# F16 — correlation among numeric parameters, after cleaning
# =============================================================================
function fig16_correlation(fd)
    df = fd.df
    n = length(PARAM_KEY)
    C = fill(NaN, n, n)
    cols = [collect(skipmissing(df[!, p])) for p in PARAM_KEY]
    for i in 1:n, j in i:n
        xi = Float64[]
        xj = Float64[]
        for k in 1:nrow(df)
            a = df[!, PARAM_KEY[i]][k]
            b = df[!, PARAM_KEY[j]][k]
            if a isa Float64 && b isa Float64
                push!(xi, a)
                push!(xj, b)
            end
        end
        if length(xi) >= 10 && std(xi) > 0 && std(xj) > 0
            r = cor(xi, xj)
            C[i, j] = r
            C[j, i] = r
        end
    end
    all(isnan, C) && error("no parameter pair has enough data")
    fig = Figure(size = (980, 880))
    ftitle(fig, "FIG. 16. CORRELATION AMONG PARAMETERS — AFTER CLEANING")
    ax = Axis(fig[1, 1];
              xticks = (1:n, [slab(p) for p in PARAM_KEY]),
              yticks = (1:n, [slab(p) for p in PARAM_KEY]),
              xticklabelrotation = pi / 2, yreversed = true)
    hm = heatmap!(ax, 1:n, 1:n, C; colorrange = (-1, 1),
                  colormap = cgrad([col(VERMILION), col(PAPER), col(SKY)]),
                  nan_color = col(CREAM))
    Colorbar(fig[1, 2], hm; width = 16, label = "Pearson r")
    fig
end

# =============================================================================
# DRIVER
# =============================================================================
function make_report_figures(ctx)
    CairoMakie.activate!()      # SVG/PNG save must go to CairoMakie even with
                                # WGLMakie loaded for the UI later
    banner("REPORT FIGURES — fig01..fig16 (brutal_theme)")
    (; raw, df, ext, miss_before, inv, snap, r5, types6, n_filled, n_out,
       after, n_std, n_exact, n_key) = ctx
    FLAG = ["below_dl", "above_range", "parse_issues", "imputed_params",
            "outlier_params"]
    fd = (ctx = ctx, raw = raw, df = df, ext = ext, miss_before = miss_before,
          inv = inv, snap = snap, r5 = r5, types6 = types6, after = after,
          n_filled = n_filled, n_out = n_out, n_std = n_std,
          n_exact = n_exact, n_key = n_key,
          n_raw_rows = nrow(raw), n_raw_cols = ncol(raw),
          n_rows = nrow(df), n_cols = ncol(df),
          ancols = [c for c in names(df) if !(c in FLAG)],
          bmiss = Dict(r.column => r for r in eachrow(miss_before)),
          amiss = Dict(c => count(ismissing, df[!, c]) for c in names(df)),
          bad_after = count(c -> any(v -> v isa AbstractString, df[!, c]),
                            ["date", "time", PARAM_KEY...]))

    idx = NamedTuple[]
    function build(fig_id, file, title, section, alt, f)
        status = "READY"
        note = ""
        try
            save_fig(file, with_theme(f, brutal_theme()))
            println("  ", fig_id, "  ", file, ".svg/.png  — ", title)
        catch e
            status = "N/A"
            note = sprint(showerror, e)
            @warn "figure skipped" fig = fig_id err = note
        end
        push!(idx, (figure = fig_id, file = file, title = title,
                    paper_section = section, alt = alt, status = status,
                    note = note))
    end

    build("F1", "fig01", "Pipeline workflow (7 stages)", "3.3",
          "Block diagram of the seven preprocessing stages with record counts at each step.",
          () -> fig01_workflow(fd))
    build("F2", "fig02", "Missing values per column, raw", "4.1",
          "Horizontal bars of the share of records missing or placeholder text in each raw column, sorted worst first.",
          () -> fig02_missing_raw(fd))
    build("F3", "fig03", "Missing values per column, before vs after", "4.2",
          "Grouped horizontal bars comparing missing share per column before and after cleaning.",
          () -> fig03_missing_before_after(fd))
    build("F4", "fig04", "Missingness pattern (rows x columns)", "4.1",
          "Heatmap of missing share per row block and column in the raw table; darker cells mark structured gaps.",
          () -> fig04_missingness(fd))
    build("F5", "fig05", "Record flow raw to final", "4.2",
          "Waterfall from extracted records to the analysis-ready dataset, one bar per removal reason.",
          () -> fig05_waterfall(fd))
    build("F6", "fig06", "Invalid entries by rule", "4.1",
          "Horizontal bars counting cells flagged by each validity rule in the raw table.",
          () -> fig06_invalid_by_rule(fd))
    build("F7", "fig07", "Data types before vs after", "4.2",
          "Stacked bars of correct versus incorrect typed columns before and after the type conversion stage.",
          () -> fig07_types(fd))
    build("F8", "fig08", "Outliers per key parameter", "4.1",
          "Boxplots of eight key parameters on a robust scale with IQR outliers drawn as lavender points and kept.",
          () -> fig08_boxplots(fd))
    build("F9", "fig09", "Distributions before vs after", "4.3",
          "Paired histograms of eight key parameters, raw in amber and cleaned in mint, log10 axis when skewed.",
          () -> fig09_distributions(fd))
    build("F10", "fig10", "Central tendency by year with spread", "4.3",
          "Yearly median line with interquartile band for dissolved oxygen, raw records versus cleaned records.",
          () -> fig10_yearly_trend(fd))
    build("F11", "fig11", "Records by year", "4.3",
          "Grouped bars of record counts per year before and after cleaning.",
          () -> fig11_records_by_year(fd))
    build("F12", "fig12", "Completeness by column", "4.3",
          "Dumbbell chart: completeness of each column before cleaning and after cleaning.",
          () -> fig12_completeness(fd))
    build("F13", "fig13", "Data quality scorecard", "4.3",
          "Paired horizontal bars for the five scorecard dimensions, before and after, in percent.",
          () -> fig13_scorecard(fd))
    build("F14", "fig14", "Standardization effect", "4.2",
          "Bars showing distinct station and period text variants before and after whitespace normalization.",
          () -> fig14_standardization(fd))
    build("F15", "fig15", "Below-detection-limit share per parameter", "4.1",
          "Horizontal bars of the share of measured values that were recorded as '<x' and converted to their threshold.",
          () -> fig15_below_detection(fd))
    build("F16", "fig16", "Correlation among parameters, after cleaning", "4.4",
          "Heatmap of pairwise Pearson correlations among the twelve water-quality parameters in the cleaned dataset.",
          () -> fig16_correlation(fd))

    p = joinpath(RESULTS_DIR, "figures_index.csv")
    write_table(p, DataFrame(idx), "Report Evidence: figure index",
                ctx.run_id)
    println("Figures: ",
            count(r -> r.status == "READY", idx), " built, ",
            count(r -> r.status == "N/A", idx), " skipped -> ", relpath(p, ROOT))
    return idx
end
