# MMORS Water Quality 2012–2018 — Data Cleaning Pipeline

Reproducible, Julia-only preprocessing of the Marilao–Meycauayan–Obando
River System (MMORS) water-quality monitoring results (2012–2018).

All cleaning, transformation, validation, logging and figure generation is
done with Julia (`XLSX`, `DataFrames`, `CSV`, `Statistics`, `StatsBase`,
`Missings`, `Dates`, `CairoMakie`, `PrettyTables`). No other tool touches the
data. The raw workbook is never modified.

## Run

Run from the repository root. Outputs are written relative to it, so the
script is portable.

```powershell
julia --project=. src/preprocess.jl
```

If PowerShell says `julia` is not recognized, Julia is installed but not on
`PATH` (this happens with the standalone installer; a juliaup install already
adds `julia` to `PATH`). Pick one of these — both assume Julia is in the default
per-user location `%LOCALAPPDATA%\Programs\Julia-1.13.1\bin` (adjust the version
folder to match yours; find it with
`Get-ChildItem "$env:LOCALAPPDATA\Programs" -Filter "Julia*"`).

**Option 1 — call the executable by full path** (nothing to change):

```powershell
& "$env:LOCALAPPDATA\Programs\Julia-1.13.1\bin\julia.exe" --project=. src/preprocess.jl
```

**Option 2 — add Julia to `PATH` for this terminal only:**

```powershell
$env:Path += ";$env:LOCALAPPDATA\Programs\Julia-1.13.1\bin"
julia --project=. src/preprocess.jl
```

To make plain `julia` work in every future terminal, add that folder to your
user `PATH` permanently, then reopen the terminal:

```powershell
[Environment]::SetEnvironmentVariable("Path",
  ([Environment]::GetEnvironmentVariable("Path","User")).TrimEnd(";") +
  ";$env:LOCALAPPDATA\Programs\Julia-1.13.1\bin", "User")
```

Every `julia ...` command below works with any of the three forms; the
full-path form always works with no setup.

To browse the results in the browser instead, run the report app — see
[Report app (web UI)](#report-app-web-ui) below.

## Input

`data/raw/MMORS_water_quality_results_2012-2018_orig.xlsx` — 4 sheets:

- `Table1 (3)` … single-cell external-data stub, no observations (excluded)
- `Marilao`, `Meycauayan`, `Obando` … data partitions (same schema)

The sheets are not rectangular: agency banners, WQG guideline rows and
interleaved `CY YYYY MONTH` period labels were interleaved with the station
records. Extraction is positional against the inspected fixed layout.

## Pipeline (12 stages)

| # | Stage | What it does |
|---|-------|--------------|
| 1 | Load & inspect | Verify sheet roles, compare headers across partitions, extract 1147 station rows + 263 period labels, exclude 30 stray cells outside the 18-column schema |
| 2 | Missing assessment | Count true/placeholder missingness per column before cleaning |
| 3 | Duplicate assessment | Exact and normalized-key duplicates before cleaning |
| 4 | Invalid-entry assessment | Strings in typed columns, pH range, negatives, coordinate domain |
| 5 | Remove unnecessary records | Normalized-key deduplication; drop 175 zero-measurement rows |
| 6 | Correct types & formats | Parse Date/Time/Float64; repair malformed cells; censored `<x`/`>x` kept as threshold + flags (Decision A) |
| 7 | Handle missing values | Recover year/month from `CY` labels; station+year median imputation only where coverage ≥50% per station-year, flagged (Decision B); era-blocked gaps kept missing |
| 8 | Flag outliers | IQR fences + z-score cross-check; values kept, flagged in `outlier_params` |
| 9 | Standardize values | Collapse inconsistent whitespace in station names / period labels |
| 10 | Transform variables | Rename to snake_case, add derived `year`/`month`/`date_source` |
| 11 | Validate | `@assert` schema, row conservation, domain ranges, types, duplicate contract |
| 12 | Save outputs | Clean CSV, before/after tables, step & decision logs, figures |

## Outputs

- `data/clean/mmors_water_quality_clean.csv` — analysis-ready dataset
  (941 rows × 29 columns)
- `results/step_log.csv` — before/after count of every cleaning step
- `results/decision_log.csv` — problem → technique → Julia function →
  reason → count (basis for the report's §3.3)
- `results/before_after.csv` — summary table for the report
- `results/missing_before.csv`, `results/missing_after.csv`,
  `results/outliers.csv` — detail tables
- `results/environment.txt` — Julia + package versions (reproducibility)
- `figures/` — missing-values, record-count flow, outlier boxplots,
  and before/after distribution charts

## Key decisions

- **Censored values** (Decision A): `<0.048`, `>16000000` … parsed to the
  threshold number and flagged in `below_dl` / `above_range`. Information is
  preserved, rows stay analyzable.
- **Missing values** (Decision B): only scattered gaps inside measured
  station-years are filled (station-year median, coverage ≥50%) and each fill
  is recorded in `imputed_params`. Era-blocked gaps (2012 pH, campaign-only
  temperature/color, etc.) are kept missing — filling them would fabricate
  measurements that were never taken.
- **Outliers** are flagged, never removed or capped: anoxic DO and estuarine
  chlorides are typically real events.

## Structure

```
data/raw/        raw workbook (read-only)
data/clean/      final dataset
src/preprocess.jl  12-stage pipeline
src/ui/          Bonito report app (7 screens, live server + static export)
scripts/         inspection probes, env setup, serve_report.jl, export_report.jl
results/         logs, summaries, detail tables
figures/         report charts
```

## Report app (web UI)

`src/ui/` is a Bonito 5 app that re-reads the evidence layer
(`results/`, `figures/`, `results/runs/`) into seven screens — DATASET,
QUALITY, CLEANING, BEFORE/AFTER, VALIDATION, FINAL, REPORT — with navigation
buttons, a per-run history diff drawer, table/figure download buttons, a
light/dark `MODE` toggle, and a freshness badge (`CURRENT`/`STALE`/`NO RUN`).

Prerequisite: instantiate the environment once (see below), Julia 1.13.

### 1. Live server — fully interactive (recommended)

Run from the repository root, then open the URL in a browser:

```powershell
julia --project=. scripts/serve_report.jl
```

(If `julia` is not recognized, use Option 1 or Option 2 from [Run](#run).)

Open **http://127.0.0.1:8080**. Everything is interactive here — the seven
screen buttons, REPORT tabs (TABLES / FIGURES / RECONCILIATION / EXPORT), the
left index rail, run-history diff dropdowns, per-figure navigation, file
downloads and the mode toggle — because Bonito keeps the session live on the
Julia process. Pass a different port with `BrutalUI.run_server(9000)`. Press
Ctrl+C in the terminal to stop it.

### 2. Offline single-file snapshot — for sharing / embedding

```powershell
julia --project=. scripts/export_report.jl
```

writes `report/index.html`, a self-contained page you can open directly
(double-click) or commit. It is a **frozen static snapshot of the view rendered
at export time**, not the live app: it has no server behind it, so the buttons
and dropdowns do not do anything, and only the figures visible in the captured
view are embedded as data URIs. Re-run the export after any pipeline run
or figure change so the snapshot is current.

### Freshness

Any edit to `src/`, `design.md`, `Project.toml` or `data/raw/*` newer than the
newest `results/runs/` snapshot flips the header badge to `STALE`; re-run the
pipeline to flip it back to `CURRENT`.

## Setup on a fresh machine (for teammates)

Each teammate runs their own local copy; nothing is hosted centrally, and the
app is served from `127.0.0.1` on each person's machine.

1. **Install Julia 1.13.x.** Recommended: install
   [juliaup](https://github.com/JuliaLang/juliaup) (a version manager), then add
   1.13. On Windows the Microsoft Store build installs both:

   ```powershell
   winget install --name Julia --id 9NJNWW8PVKMN -e -s msstore
   juliaup add 1.13.1
   juliaup default 1.13.1
   ```

   On macOS/Linux:

   ```shell
   curl -fsSL https://install.julialang.org | sh
   juliaup add 1.13.1
   juliaup default 1.13.1
   ```

   Reopen the terminal afterwards, then confirm with `julia --version` — it
   should print `1.13.x`. Prefer **1.13.1**: it is the version this repo's
   `Manifest.toml` was generated with. juliaup puts `julia` on `PATH`
   automatically, so Options 1/2 from [Run](#run) are not needed. (If the Store
   is blocked, download the standalone installer from
   <https://julialang.org/downloads/> — then `julia` is *not* on `PATH` and you
   do need Option 1 or 2.)

2. **Clone the repository:**

   ```powershell
   git clone https://github.com/juliabbbb/datacleaning.git
   cd datacleaning
   ```

3. **Make `julia` usable.** Try `julia --version`. If it is not recognized,
   apply Option 1 (full path) or Option 2 (session `PATH`) from [Run](#run).

4. **Instantiate the environment** (once — downloads and precompiles packages;
   the first time can take several minutes):

   ```powershell
   julia --project=. -e 'using Pkg; Pkg.instantiate()'
   ```

   (That `-e` form is safe in PowerShell; for commands that contain double
   quotes, prefer the `scripts/*.jl` entry points below.)

5. **(Re)generate the evidence layer** so the app has current data:

   ```powershell
   julia --project=. src/preprocess.jl
   ```

6. **Open the app** and browse the results at <http://127.0.0.1:8080>:

   ```powershell
   julia --project=. scripts/serve_report.jl
   ```

   Or build the offline single-file report (`report/index.html`) to share:

   ```powershell
   julia --project=. scripts/export_report.jl
   ```

### What each teammate sees

- The app reads this clone's `results/`, `figures/` and `results/runs/`, so
  everyone sees their own checkout's evidence.
- The header badge is `CURRENT` when the evidence is newer than the source; if
  someone edits `src/` and does not re-run the pipeline, it shows `STALE`.
- Stop the server with `Ctrl+C`; the port (`8080` by default) is per machine,
  so multiple teammates can run it at the same time without clashing.
- To share a static view without a server, send them the generated
  `report/index.html` (open it by double-clicking).