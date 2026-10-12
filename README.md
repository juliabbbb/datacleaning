# MMORS Water Quality 2012–2018 — Data Cleaning Pipeline

Reproducible, Julia-only preprocessing of the Marilao–Meycauayan–Obando
River System (MMORS) water-quality monitoring results (2012–2018).

All cleaning, transformation, validation, logging and figure generation is
done with Julia (`XLSX`, `DataFrames`, `CSV`, `Statistics`, `StatsBase`,
`Missings`, `Dates`, `CairoMakie`, `PrettyTables`). No other tool touches the
data. The raw workbook is never modified.

## Run

```julia
julia --project=. src/preprocess.jl
```

Run from the repository root. Outputs are written relative to it, so the
script is portable.

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
scripts/         inspection probes & environment setup
results/         logs, summaries, detail tables
figures/         report charts
```

## Report app

`src/ui/` is a Bonito 5 app that re-reads the evidence layer
(`results/`, `figures/`, `results/runs/`) into seven screens — DATASET,
QUALITY, CLEANING, BEFORE/AFTER, VALIDATION, FINAL, REPORT — with a
run-history diff drawer and a freshness badge (`CURRENT`/`STALE`/`NO RUN`).

- Live server: `julia --project=. -e 'include("src/ui/BrutalUI.jl"); BrutalUI.run_server()'` → http://127.0.0.1:8080
- Offline single-file export (self-contained; figures embedded as data URIs):

```julia
julia --project=. -e 'include("src/ui/BrutalUI.jl"); BrutalUI.export_report()'
```

- Staleness: any edit to `src/`, `design.md`, `Project.toml` or `data/raw/*`
  newer than the newest `results/runs/` snapshot flips the badge to `STALE`;
  rerun the pipeline to flip it back to `CURRENT`.

## Reproduce the environment

From a fresh machine:

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
```