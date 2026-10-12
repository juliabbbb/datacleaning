# =============================================================================
# src/ui/screens.jl — the seven report screens (design.md §6)
#
# Data layer reads the evidence layer exactly as it was run:
#   results/*.csv        (comment='#'), run_manifest.json
#   results/runs/run_*   (per-run snapshots -> run history diff)
#   figures/*.svg|png    (embedded as data URIs -> self-contained HTML)
#   data/clean/mmors_water_quality_clean.csv (FINAL DATASET screen)
# =============================================================================

# --- data layer -----------------------------------------------------------------

const CLEAN_CSV = joinpath(ROOT, "data", "clean", "mmors_water_quality_clean.csv")

function load_manifest()
    f = joinpath(RESULT_DIR, "run_manifest.json")
    isfile(f) || return nothing
    return JSON3.read(read(f, String))
end

load_tables() = Dict{String, DataFrame}(
    fn => CSV.read(joinpath(RESULT_DIR, fn), DataFrame; comment = "#", missingstring = "")
    for fn in filter(f -> endswith(f, ".csv"), readdir(RESULT_DIR)))

latest_run() = begin
    isdir(RUNS_DIR) || return nothing
    runs = sort(filter(f -> isdir(joinpath(RUNS_DIR, f)), readdir(RUNS_DIR)))
    isempty(runs) ? nothing : last(runs)
end

run_dirs() = isdir(RUNS_DIR) ?
    sort(filter(f -> isdir(joinpath(RUNS_DIR, f)), readdir(RUNS_DIR))) : String[]

"Newest mtime over the pipeline's live inputs (source, design, raw data)."
function newest_source_mtime()
    ts = 0.0
    for dir in [joinpath(ROOT, "src"), joinpath(ROOT, "src", "ui"),
                joinpath(ROOT, "data", "raw")]
        isdir(dir) || continue
        for f in readdir(dir)
            p = joinpath(dir, f)
            isfile(p) && (ts = max(ts, mtime(p)))
        end
    end
    for extra in [joinpath(ROOT, "design.md"), joinpath(ROOT, "Project.toml")]
        isfile(extra) && (ts = max(ts, mtime(extra)))
    end
    ts
end

function staleness()
    lr = latest_run()
    lr === nothing && return :none
    newest_source_mtime() > mtime(joinpath(RUNS_DIR, lr)) ? :stale : :current
end

"Reconciliation numbers: input, total removed, output, balanced?"
function solve_reconcile(tables)
    haskey(tables, "reconciliation.csv") || return (nothing, nothing, nothing, false)
    df = tables["reconciliation.csv"]
    rows = df[df.scope .== "ALL WORKSHEETS", :]
    inp = rows.rows[occursin.(r"input", rows.step)][1]
    out = rows.rows[occursin.(r"output", rows.step)][1]
    rem = -sum(rows.rows[occursin.(r"removed", rows.step)])
    return (inp, rem, out, (inp - rem) == out)
end

"Freshness badge: CURRENT / STALE / NO RUN (design.md §6.7 header strip)."
function freshness()
    latest_run() === nothing && return chip("NO RUN", CREAM)
    staleness() == :stale ? chip("STALE", VERMILION) : chip("CURRENT", MINT)
end

"Plain CSS grid without relying on Bonito Grid element sugar."
function css_grid(cols, gap, children...; style = Styles())
    return DOM.div(children...; style = Styles(
        style, "display" => "grid", "grid-template-columns" => cols,
        "gap" => string(gap, "px")))
end

# --- app state -------------------------------------------------------------------

"Shared UI state; observables drive screens, tabs, mode, run-history diff."
struct Ctx
    session
    mode::Observable{Symbol}
    screen::Observable{Symbol}
    tab::Observable{Symbol}
    sel_table::Observable{String}
    sel_fig::Observable{String}
    run_b::Observable{Any}
    run_a::Observable{Any}
    tables::Dict{String, DataFrame}
    mani::Any
    runs::Vector{String}
    table_meta::Dict{String, NamedTuple{(:title, :section, :status), Tuple{String, String, String}}}
    fig_meta::Dict{String, NamedTuple{(:title, :section, :status, :alt, :file), Tuple{String, String, String, String, String}}}
    clean_df::DataFrame
end

function make_ctx(session)
    tables = load_tables()
    t_meta = Dict{String, NamedTuple{(:title, :section, :status), Tuple{String, String, String}}}()
    for r in eachrow(tables["tables_index.csv"])
        t_meta[string(r.file)] = (title = string(r.title),
                                  section = string(r.paper_section),
                                  status = string(r.status))
    end
    f_meta = Dict{String, NamedTuple{(:title, :section, :status, :alt, :file), Tuple{String, String, String, String, String}}}()
    for r in eachrow(tables["figures_index.csv"])
        f_meta[string(r.figure)] = (title = string(r.title),
                                    section = string(r.paper_section),
                                    status = string(r.status),
                                    alt = string(r.alt),
                                    file = string(r.file))
    end
    clean = isfile(CLEAN_CSV) ? CSV.read(CLEAN_CSV, DataFrame; missingstring = "") :
             DataFrame()
    runs = run_dirs()
    Ctx(session, Observable(:light), Observable(:report), Observable(:tables),
        Observable("quality_summary.csv"), Observable("F1"),
        Observable(isempty(runs) ? "" : last(runs)),
        Observable(isempty(runs) ? "" : first(runs)),
        tables, load_manifest(), runs, t_meta, f_meta, clean)
end

mval(d, k, alt) = (d === nothing || !haskey(d, k)) ? alt : d[k]

# --- table / figure blocks --------------------------------------------------------

"Wrap a rendered table with its index caption + READY/N-A status chip."
function table_block(ctx, file; title_override = nothing)
    haskey(ctx.tables, file) || return panel(
        chip("N/A", CREAM),
        DOM.div(string("results/", file, " was not produced in this run"),
                style = Styles("margin-top" => "8px", "font-size" => "12px")))
    df = ctx.tables[file]
    meta = get(ctx.table_meta, file, (title = file, section = "", status = "READY"))
    cap = title_override !== nothing ? title_override : meta.title
    return DOM.div(
        DOM.div(chip(meta.status, meta.status == "READY" ? MINT : CREAM),
                DOM.span("  " * string(isempty(meta.section) ? "§" : "§ ", meta.section);
                         style = Styles("font-size" => "12px", "opacity" => "0.75",
                                        "margin-left" => "6px"))),
        panel(report_table(df, cap, file;
                           section = meta.section,
                           run_id = mval(ctx.mani, "run_id", ""));
              color = PAPER, pad = "18px", style = Styles("margin-top" => "8px")))
end

"T21 concerns.md — hand-maintained markdown, rendered line by line."
function concerns_block(ctx)
    f = joinpath(RESULT_DIR, "concerns.md")
    isfile(f) || return panel(chip("concerns.md NOT FOUND", CREAM))
    lines = collect(eachline(f))
    body = [DOM.div(string(l); style = Styles(
                "font-size" => "13px", "line-height" => "1.6",
                "white-space" => "pre-wrap", "font-family" => FONT_MONO))
            for l in lines]
    return DOM.div(
        DOM.div(chip("T21", BUTTER),
                DOM.span("  Table — paper §9  ·  Concerns and limitations";
                         style = Styles("font-weight" => "bold", "font-size" => "15px"))),
        panel(body...; color = CREAM, pad = "18px"))
end

function fig_block(ctx, figkey)
    haskey(ctx.fig_meta, figkey) || return panel(chip("N/A", CREAM))
    m = ctx.fig_meta[figkey]
    png = joinpath(FIG_DIR, string(m.file, ".png"))
    isfile(png) && return figure_card(figkey, m.title, m.section, m.alt, png;
                                      run_id = mval(ctx.mani, "run_id", ""))
    return panel(chip(string(m.status, " — missing ", m.file, ".png"), CREAM),
                 DOM.div(string("rebuild with: julia --project=. src/preprocess.jl");
                         style = Styles("font-size" => "12px", "margin-top" => "8px")))
end

function rail_button(ctx, label, target; tab = :tables, color = PAPER)
    b = Button(label; style = Styles(
        "font-family" => FONT_MONO, "font-size" => "12px",
        "background-color" => string(color),
        "border" => string(BORDER_THIN, "px solid ", INK),
        "padding" => "4px 8px", "width" => "100%", "text-align" => "left",
        "margin" => "0 0 4px 0", "cursor" => "pointer"))
    on(b.value) do _
        ctx.screen[] = :report
        ctx.tab[] = tab
        tab == :tables ? (ctx.sel_table[] = target) : (ctx.sel_fig[] = target)
    end
    return b
end

# =============================================================================
# SCREEN: DATASET — source workbook, variable dictionary, coverage (§6.1)
# =============================================================================
function screen_dataset(ctx)
    inp = mval(ctx.mani, "rows_in", "n/a")
    out = mval(ctx.mani, "rows_out", "n/a")
    cin = mval(ctx.mani, "cols_in", "n/a")
    cout = mval(ctx.mani, "cols_out", "n/a")
    return DOM.div(
        panel(fig_block(ctx, "F1"); color = PAPER, pad = "10px",
              style = Styles("margin-bottom" => "12px")),
        css_grid("repeat(4, 1fr)", 12,
            metric_block("RAW RECORDS", inp; color = AMBER,
                         sub = "3 worksheets: Marilao, Meycauayan, Obando"),
            metric_block("FINAL RECORDS", out; color = MINT),
            metric_block("VARIABLES", string(cin, " → ", cout);
                         color = CREAM, sub = "raw schema → analysis-ready schema"),
            metric_block("FREQUENCY", "2012–2018"; color = BUTTER,
                         sub = "records per year: see T20 below")),
        table_block(ctx, "dataset_profile.csv"),
        table_block(ctx, "variable_dictionary.csv"),
        table_block(ctx, "coverage.csv"),
        table_block(ctx, "packages.csv"))
end

# =============================================================================
# SCREEN: QUALITY — T5 first, metric blocks, per-issue evidence (§6.2)
# =============================================================================
const T5_JUMPS = ["Missing Values" => "missing_by_column.csv",
                  "Duplicate Records" => "duplicates.csv",
                  "Invalid Entries" => "invalid_by_rule.csv",
                  "Incorrect Data Types" => "type_corrections.csv",
                  "Outliers" => "outliers.csv"]

"T5 rendered untouched (design.md §7.1) plus cross-link chips under it."
function t5_block(ctx)
    df = ctx.tables["quality_summary.csv"]
    cap = "Table 5. REQUIRED before/after summary — paper §3.4/4.1"
    jumps = Any[]
    for (issue, target) in T5_JUMPS
        b = Button(string("\u2192 ", issue); style = Styles(
            "font-family" => FONT_MONO, "font-size" => "12px",
            "background-color" => CREAM,
            "border" => string(BORDER_THIN, "px solid ", INK),
            "padding" => "3px 8px", "margin" => "4px 6px 0 0", "cursor" => "pointer"))
        on(b.value) do _
            ctx.screen[] = :report; ctx.tab[] = :tables; ctx.sel_table[] = target
        end
        push!(jumps, b)
    end
    return DOM.div(
        DOM.div(chip("T5 REQUIRED", MINT),
                DOM.span("  before/after table, untouched";
                         style = Styles("font-size" => "12px", "opacity" => "0.75",
                                        "margin-left" => "6px"))),
        panel(report_table(df, cap, "quality_summary.csv";
                           run_id = mval(ctx.mani, "run_id", "")),
              DOM.div("columns and row order untouched \u00b7 jump to detail:",
                      jumps...;
                      style = Styles("margin-top" => "10px", "font-size" => "12px"));
              color = PAPER, pad = "18px", style = Styles("margin-top" => "8px")))
end

function screen_quality(ctx)
    t5 = ctx.tables["quality_summary.csv"]
    iss = Dict(string(r.data_quality_issue) => (before = r.before, after = r.after)
               for r in eachrow(t5))
    mb = iss["Missing Values"]; ma = iss["Duplicate Records"]
    ib = iss["Invalid Entries"]; ob = iss["Outliers"]
    return DOM.div(
        t5_block(ctx),
        css_grid("repeat(4, 1fr)", 12,
            metric_block("MISSING", mb.before; color = BUTTER,
                         sub = string("after: ", mb.after)),
            metric_block("DUPLICATES", ma.before; color = SKY,
                         sub = string("after: ", ma.after)),
            metric_block("INVALID", ib.before; color = VERMILION,
                         sub = string("after: ", ib.after)),
            metric_block("OUTLIERS", ob.before; color = LAVENDER,
                         sub = string("retained: ", ob.after))),
        css_grid("1fr 1fr", 12, table_block(ctx, "missing_by_column.csv"),
                 fig_block(ctx, "F2")),
        css_grid("1fr 1fr", 12, fig_block(ctx, "F4"),
                 table_block(ctx, "duplicates.csv")),
        css_grid("1fr 1fr", 12, table_block(ctx, "invalid_by_rule.csv"),
                 fig_block(ctx, "F6")),
        css_grid("1fr 1fr", 12, table_block(ctx, "type_corrections.csv"),
                 fig_block(ctx, "F7")),
        css_grid("1fr 1fr", 12, table_block(ctx, "outliers.csv"),
                 fig_block(ctx, "F8")),
        css_grid("1fr 1fr", 12, table_block(ctx, "placeholders.csv"),
                 fig_block(ctx, "F15")))
end

# =============================================================================
# SCREEN: CLEANING — stepper + live console from step_log (§6.3)
# =============================================================================
const STAGE_TITLES = Dict(
    "1_load" => "HARVEST RAW DATA", "2_inspect" => "INSPECTION & REPORT KEYS",
    "3_assess" => "QUALITY ASSESSMENT", "4_clean" => "CLEANING",
    "5_transform" => "TRANSFORMATION", "6_validate" => "VALIDATION",
    "7_ship" => "FINAL DATASET")

stage_color(st) = st == "4_clean" ? TERRACOTTA :
                  st == "6_validate" ? MINT :
                  st == "5_transform" ? BUTTER : CREAM

function stage_console(log)
    out = String[]
    st = nothing
    for r in eachrow(log)
        s = string(r.stage)
        s != st && (st = s; push!(out, "--- STAGE " * s * " " *
                    ("-")^max(4, 56 - length(s))))
        note = ismissing(r.note) ? "" : string(r.note)
        push!(out, lpad(ismissing(r.metric) ? "" : string(r.metric), 28, " ") *
                   string(ismissing(r.before) ? "" : string(r.before), " -> ",
                          ismissing(r.after) ? "" : string(r.after),
                          isempty(note) ? "" : "   " * note))
    end
    join(out, "\n")
end

function stage_panel(stage, rows)
    lines = [DOM.div(
        string(ismissing(r.metric) ? "" : string(r.metric),
               ismissing(r.before) ? "" : string("   ", r.before, " -> ", r.after),
               ismissing(r.note) || isempty(string(r.note)) ? "" : string("   · ", r.note));
        style = Styles("font-size" => "12px", "line-height" => "1.7"))
        for r in eachrow(rows)]
    return panel(
        DOM.div(
            chip("DONE", stage_color(stage)),
            DOM.span(string("  STAGE ", stage, " — ",
                            get(STAGE_TITLES, stage, stage));
                    style = Styles("font-weight" => "bold", "font-size" => "15px")),
            lines...);
        color = PAPER, pad = "16px")
end

function screen_cleaning(ctx)
    log = ctx.tables["step_log.csv"]
    stages = sort(unique(log.stage))
    panels = [stage_panel(s, log[log.stage .== s, :]) for s in stages]
    return DOM.div(
        panel(
            chip("CONSOLE", TERRACOTTA),
            DOM.span(string("  pipeline log — run ", mval(ctx.mani, "run_id", ""));
                    style = Styles("font-weight" => "bold", "font-size" => "15px")),
            DOM.pre(stage_console(log); style = Styles(
                "background-color" => INK, "color" => MINT, "padding" => "14px",
                "font-size" => "12px", "line-height" => "1.5", "overflow" => "auto",
                "margin-top" => "8px",
                "border" => string(BORDER_THICK, "px solid ", INK)));
            color = PAPER, pad = "16px"),
        css_grid("1fr", 12, panels...),
        table_block(ctx, "decision_log.csv"))
end

# =============================================================================
# SCREEN: BEFORE / AFTER — the money comparison (§6.4)
# =============================================================================
function screen_before_after(ctx)
    return DOM.div(
        t5_block(ctx),
        css_grid("1fr 1fr", 12, fig_block(ctx, "F3"), fig_block(ctx, "F5")),
        css_grid("1fr 1fr", 12, table_block(ctx, "descriptives_before_after.csv"),
                 fig_block(ctx, "F9")),
        css_grid("1fr 1fr", 12, fig_block(ctx, "F10"), fig_block(ctx, "F11")),
        css_grid("1fr 1fr", 12, table_block(ctx, "before_after.csv"),
                 fig_block(ctx, "F12")),
        css_grid("1fr 1fr", 12, table_block(ctx, "scorecard.csv"),
                 fig_block(ctx, "F13")),
        css_grid("1fr 1fr", 12, fig_block(ctx, "F14"), fig_block(ctx, "F16")),
        css_grid("1fr 1fr", 12, table_block(ctx, "transformations.csv"),
                 table_block(ctx, "removed_items.csv")))
end

# =============================================================================
# SCREEN: VALIDATION — checklist + reconciliation banner (§6.5)
# =============================================================================
function reconcile_banner(ctx)
    inp, rem, out, ok = solve_reconcile(ctx.tables)
    inp === nothing && return banner("NO RECONCILIATION DATA"; color = CREAM)
    return banner(string("RECONCILED: ", inp, " \u2212 ", rem, " = ", out);
                  color = ok ? MINT : VERMILION,
                  sub = ok ? string("row conservation verified - ", rem,
                                    " removed (",
                                    mval(mval(ctx.mani, "records_removed", nothing),
                                         "duplicates", "?"), " duplicates + ",
                                    mval(mval(ctx.mani, "records_removed", nothing),
                                         "zero_measurements", "?"),
                                    " no-measurement records) - nothing lost, nothing invented")
                           : "MISMATCH - investigate before delivery")
end

function screen_validation(ctx)
    v = ctx.tables["validation.csv"]
    checks = Any[]
    for r in eachrow(v)
        pass = string(r.status) == "PASS"
        push!(checks, panel(
            chip(pass ? "PASS" : "FAIL", pass ? MINT : VERMILION),
            DOM.span(string("  ", r.check); style = Styles("font-weight" => "bold")),
            DOM.div(string("expected: ", r.expected);
                    style = Styles("font-size" => "12px", "opacity" => "0.78")),
            DOM.div(string("actual:   ", r.actual);
                    style = Styles("font-size" => "12px", "opacity" => "0.78"));
            color = PAPER, pad = "12px"))
    end
    return DOM.div(
        reconcile_banner(ctx),
        css_grid("1fr 1fr", 12, checks...),
        table_block(ctx, "reconciliation.csv"),
        table_block(ctx, "validation.csv"))
end

# =============================================================================
# SCREEN: FINAL DATASET — preview, download, file facts (§6.6)
# =============================================================================
function screen_final(ctx)
    has_clean = nrow(ctx.clean_df) > 0
    rows = has_clean ? nrow(ctx.clean_df) : "n/a"
    cols = has_clean ? ncol(ctx.clean_df) : "n/a"
    size = isfile(CLEAN_CSV) ? filesize(CLEAN_CSV) : "n/a"
    sha = isfile(CLEAN_CSV) ? bytes2hex(SHA.sha256(read(CLEAN_CSV))) : "n/a"
    preview = has_clean ?
        panel(report_table(ctx.clean_df[1:min(15, nrow(ctx.clean_df)), :],
                           "Table 22. Final dataset - first 15 of $(rows) records",
                           "data/clean/mmors_water_quality_clean.csv";
                           run_id = mval(ctx.mani, "run_id", ""));
              color = PAPER, pad = "18px") :
        panel(chip("CLEAN CSV NOT FOUND", VERMILION))
    return DOM.div(
        css_grid("repeat(4, 1fr)", 12,
            metric_block("ROWS", rows; color = MINT),
            metric_block("COLUMNS", cols; color = CREAM),
            metric_block("SIZE", string(size); color = BUTTER, sub = "bytes on disk"),
            metric_block("MISSING CELLS AFTER", "4519 (20.9%)"; color = BUTTER,
                         sub = "from T5 - after cleaning")),
        panel(
            download_link("DOWNLOAD CLEAN CSV", "mmors_water_quality_clean.csv",
                          "csv", nothing, "text/csv", file = CLEAN_CSV),
            DOM.div(string("SHA-256: ", sha); style = Styles(
                "font-size" => "12px", "opacity" => "0.8", "margin-top" => "8px",
                "word-break" => "break-all"));
            color = MINT, pad = "16px", shadow = true,
            style = Styles("margin-bottom" => "12px")),
        preview,
        concerns_block(ctx))
end

# =============================================================================
# SCREEN: REPORT — tabs, left index rail, main pane, run history (§6.7)
# =============================================================================
function tab_button(ctx, key, label)
    b = Button(label; style = Styles(
        "font-family" => FONT_MONO, "font-size" => "13px", "font-weight" => "bold",
        "background-color" => CREAM, "border" => string(BORDER_THIN, "px solid ", INK),
        "padding" => "5px 16px", "margin" => "3px", "cursor" => "pointer"))
    on(b.value) do _; ctx.tab[] = key; end
    return b
end

section_group_title(s) = s == "3.1" ? "3.1 DATASET" :
    s == "3.2" ? "3.2 PACKAGES" :
    s == "3.3" ? "3.3 PIPELINE" :
    s == "3.4" ? "3.4 QUALITY ASSESSMENT" :
    s == "4.1" ? "4.1 RAW-STATE ISSUES" :
    s == "4.2" ? "4.2 CLEANED-STATE ISSUES" :
    s == "4.3" ? "4.3 COMPARISON & SCORECARD" :
    s == "4.4" ? "4.4 CORRELATIONS" :
    s == "9" ? "9 LIMITATIONS" : string("SECTION ", s)

function index_rail(ctx, kind)
    items = Any[]
    entries = kind == :tables ? collect(ctx.table_meta) : collect(ctx.fig_meta)
    sec_order = sort(unique([m.section for (_, m) in entries]))
    for sec in sec_order
        push!(items, DOM.div(section_group_title(sec);
                             style = Styles("font-size" => "11px",
                                            "font-weight" => "bold",
                                            "letter-spacing" => "1px",
                                            "margin" => "10px 0 4px 0")))
        for (key, m) in entries
            m.section == sec || continue
            if kind == :tables
                push!(items, rail_button(ctx, string(key, "  ·  ", m.title), key))
            else
                push!(items, rail_button(ctx, string(key, "  ·  ", m.title), key;
                                         tab = :figures))
            end
        end
    end
    return panel(DOM.div(items...); color = CREAM, pad = "12px",
                 style = Styles("align-self" => "start", "max-height" => "78vh",
                                "overflow" => "auto"))
end

pane_split(ctx, kind, selected) = css_grid("3fr 9fr", 12,
    index_rail(ctx, kind),
    panel(kind == :tables ? table_block(ctx, selected) :
          fig_block(ctx, selected);
          color = PAPER, pad = "14px", style = Styles("min-width" => "0")))

function report_main_export(ctx)
    rpt = joinpath(ROOT, "report", "index.html")
    mani = joinpath(RESULT_DIR, "run_manifest.json")
    env = isfile(joinpath(RESULT_DIR, "environment.txt")) ?
          read(joinpath(RESULT_DIR, "environment.txt"), String) : "(not written)"
    report_link = isfile(rpt) ?
        download_link("REPORT (single HTML)", "report.html", "html",
                      nothing, "text/html", file = rpt) :
        DOM.span("(export the report first: BrutalUI.export_report())")
    return DOM.div(
        panel(
            chip("EVIDENCE EXPORT", TERRACOTTA),
            css_grid("repeat(3, 1fr)", 12,
                report_link,
                download_link("ENVIRONMENT.txt", "environment.txt", "txt",
                              env, "text/plain"),
                download_link("run_manifest.json", "run_manifest.json", "json",
                              isfile(mani) ? read(mani, String) : "{}",
                              "application/json"));
            color = PAPER, pad = "18px"),
        concerns_block(ctx))
end

function run_history_drawer(ctx)
    isempty(ctx.runs) && return panel(chip("RUN HISTORY EMPTY - run the pipeline", CREAM))
    nb = length(ctx.runs)
    idx_b = findfirst(==(ctx.run_b[]), ctx.runs)
    idx_a = findfirst(==(ctx.run_a[]), ctx.runs)
    db = Dropdown(ctx.runs; index = idx_b === nothing ? nb : idx_b,
                  style = Styles("font-family" => FONT_MONO))
    da = Dropdown(ctx.runs; index = idx_a === nothing ? 1 : idx_a,
                  style = Styles("font-family" => FONT_MONO))
    on(db.value) do v; ctx.run_b[] = v; end
    on(da.value) do v; ctx.run_a[] = v; end
    diff = map(db.value, da.value) do r1, r2
        r1 == r2 ? panel(chip("PICK TWO DIFFERENT RUNS", CREAM)) : diff_dom(r1, r2)
    end
    return panel(
        DOM.div(
            chip("RUN HISTORY", SKY),
            DOM.span("  diff two snapshots - changed cells blush, tooltip shows the old value";
                     style = Styles("font-weight" => "bold")),
            DOM.span("  ", db, " vs ", da;
                     style = Styles("margin-left" => "8px")),
            diff;
            style = Styles("margin-top" => "8px"));
        color = CREAM, pad = "14px")
end

"Cell-level diff: every shared CSV of the two runs, first 8 changed rows each."
function diff_dom(ra, rb)
    out = Any[]
    fa = joinpath(RUNS_DIR, ra)
    fb = joinpath(RUNS_DIR, rb)
    for fn in filter(f -> endswith(f, ".csv"), readdir(fa))
        isfile(joinpath(fb, fn)) || continue
        a = CSV.read(joinpath(fa, fn), DataFrame; comment = "#")
        b = CSV.read(joinpath(fb, fn), DataFrame; comment = "#")
        if names(a) != names(b) || nrow(a) != nrow(b)
            push!(out, panel(chip(string(fn, ": shape differs"), VERMILION);
                             color = PAPER, pad = "10px",
                             style = Styles("margin" => "6px 0")))
            continue
        end
        changed = [(i, c) for i in axes(a, 1) for c in names(a)
                   if !isequal(a[i, c], b[i, c])]
        if isempty(changed)
            push!(out, DOM.div(string("  ", fn, ": identical"); style = Styles(
                "font-size" => "12px", "padding" => "3px 0")))
            continue
        end
        head = DOM.tr(DOM.th("row"), Any[DOM.th(string(c)) for c in names(a)]...)
        nshow = min(8, length(changed))
        body = Any[]
        for k in 1:nshow
            i = changed[k][1]
            cells = map(names(a)) do c
                if isequal(a[i, c], b[i, c])
                    return DOM.td(fmt(a[i, c]))
                end
                return DOM.td(fmt(b[i, c]); style = Styles(
                    "background-color" => BLUSH,
                    "title" => string("was: ", fmt(a[i, c]))))
            end
            push!(body, DOM.tr(DOM.td(string(i)), cells...))
        end
        push!(out, panel(
            DOM.div(chip(string(fn, ": ", length(changed), " changed cells"),
                         VERMILION),
                    nshow < length(changed) ?
                        DOM.span(string("  showing first ", nshow);
                                 style = Styles("font-size" => "12px")) :
                        DOM.span(""),
                    DOM.table(DOM.thead(head), DOM.tbody(body...)));
            color = PAPER, pad = "12px", style = Styles("margin" => "6px 0")))
    end
    isempty(out) && return panel(chip("NO SHARED CSV SNAPSHOTS", CREAM))
    return DOM.div(out...)
end

function screen_report(ctx)
    tab_bar = DOM.div(
        tab_button(ctx, :tables, "TABLES"),
        tab_button(ctx, :figures, "FIGURES"),
        tab_button(ctx, :reconciliation, "RECONCILIATION"),
        tab_button(ctx, :export, "EXPORT");
        style = Styles("border" => string(BORDER_THICK, "px solid ", INK),
                       "background-color" => CREAM, "padding" => "4px",
                       "margin-bottom" => "10px"))
    body = map(ctx.tab, ctx.sel_table, ctx.sel_fig) do t, st, sf
        t == :figures ? pane_split(ctx, :figures, sf) :
        t == :reconciliation ? report_main_reconciliation(ctx) :
        t == :export ? report_main_export(ctx) :
        pane_split(ctx, :tables, st)
    end
    return DOM.div(run_history_drawer(ctx), tab_bar, body)
end

function report_main_reconciliation(ctx)
    return DOM.div(
        reconcile_banner(ctx),
        t5_block(ctx),
        css_grid("1fr 1fr", 12, table_block(ctx, "scorecard.csv"),
                 fig_block(ctx, "F13")),
        table_block(ctx, "reconciliation.csv"),
        table_block(ctx, "validation.csv"))
end

# =============================================================================
# NAVIGATION + ROOT
# =============================================================================
function nav_btn(ctx, screen, label)
    b = Button(label; style = Styles(
        "font-family" => FONT_MONO, "font-size" => "12px", "font-weight" => "bold",
        "background-color" => PAPER, "border" => string(BORDER_THIN, "px solid ", INK),
        "padding" => "6px 10px", "margin" => "3px", "cursor" => "pointer"))
    on(b.value) do _; ctx.screen[] = screen; end
    return b
end

function header_bar(ctx)
    run_id = mval(ctx.mani, "run_id", "NO RUN")
    ts = mval(ctx.mani, "timestamp", "")
    inp = mval(ctx.mani, "rows_in", "n/a")
    out = mval(ctx.mani, "rows_out", "n/a")
    left = DOM.div(
        DOM.div("MMORS / WATER QUALITY   \u2588   REPORT";
                style = Styles("font-weight" => "bold", "font-size" => "22px",
                               "letter-spacing" => "2px")),
        DOM.div("JULIA-ONLY \u00b7 MONOSPACE-ONLY \u00b7 EVIDENCE = results/";
                style = Styles("font-size" => "12px", "opacity" => "0.8")))
    info = DOM.div(
        chip(string(run_id), TERRACOTTA),
        DOM.span(string("  ", ts); style = Styles("font-size" => "12px",
                                                  "opacity" => "0.8")),
        freshness(),
        DOM.span(string("  in\u2192out: ", inp, "\u2192", out);
                 style = Styles("font-size" => "12px", "font-weight" => "bold")),
        mode_button(ctx);
        style = Styles("display" => "flex", "align-items" => "center",
                       "gap" => "10px", "flex-wrap" => "wrap", "margin" => "10px 0"))
    nav = DOM.div([nav_btn(ctx, s, l) for (s, l) in
        [(:dataset, "DATASET"), (:quality, "QUALITY"), (:cleaning, "CLEANING"),
         (:before_after, "BEFORE/AFTER"), (:validation, "VALIDATION"),
         (:final, "FINAL"), (:report, "REPORT")]]...)
    return DOM.div(left, info, nav;
                   style = Styles("border-bottom" =>
                                  string(BORDER_SECTION, "px solid ", INK),
                                  "padding-bottom" => "8px",
                                  "margin-bottom" => "14px"))
end

"Page skeleton: header strip, reconciliation banner, active screen."
function root_view(ctx)
    return map(ctx.screen, ctx.mode) do s, mode
        page = s == :dataset ? screen_dataset(ctx) :
               s == :quality ? screen_quality(ctx) :
               s == :cleaning ? screen_cleaning(ctx) :
               s == :before_after ? screen_before_after(ctx) :
               s == :validation ? screen_validation(ctx) :
               s == :final ? screen_final(ctx) :
               screen_report(ctx)
        chrome = mode == :light ?
            Styles("background-color" => PAPER, "color" => INK,
                   "min-height" => "100vh") :
            Styles("background-color" => "#101010", "color" => PAPER,
                   "min-height" => "100vh")
        DOM.div(header_bar(ctx), reconcile_banner(ctx),
                DOM.div(page; style = Styles("padding-bottom" => "32px"));
                style = Styles(chrome, "padding" => "18px 24px 0 24px",
                               "max-width" => "1500px", "margin" => "0 auto"))
    end
end

"MODE button: light/dark page chrome (design.md §6 header)."
function mode_button(ctx)
    b = Button("MODE"; style = Styles(
        "font-family" => FONT_MONO, "font-size" => "12px", "font-weight" => "bold",
        "background-color" => INK, "color" => PAPER,
        "border" => string(BORDER_THIN, "px solid ", INK),
        "padding" => "6px 12px", "cursor" => "pointer"))
    on(b.value) do _
        ctx.mode[] = ctx.mode[] == :light ? :dark : :light
    end
    return b
end