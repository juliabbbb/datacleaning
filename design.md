# design.md — Brutalism: MMORS Preprocessing System

> **Scope:** this document covers the *visual design system and the implementation
> architecture* (styling, tokens, components, screens, chart/figure rules, and the
> Julia-only stack). It intentionally contains **no pipeline findings** — every
> number shown in the product comes from `results/` / `figures/` (see
> `results/decision_log.csv` and report §3.3). That is the evidence contract of this
> design.

```yaml
version: "alpha"
name: "Brutalism: MMORS Preprocessing System"
description: "Brutalist interface for a Julia data-preprocessing pipeline on the MMORS Water Quality Results (2012-2018). Implemented entirely in Julia (Bonito.jl + Makie): flat warm-palette blocks, hard borders, visible grid, evidence-first layouts."
```

## 1. Design tokens (single source of truth — `src/ui/tokens.jl`)

| Token | Hex | Role |
|---|---|---|
| ink | `#1A1A1A` | text, borders, code background, secondary buttons |
| paper | `#FFFFFF` | page background |
| cream | `#FFF6D6` | table zebra rows, disabled states, quiet panels, empty cells (`N/A`) |
| primary / terracotta | `#DC8A5A` | primary action, active stage, header CTA |
| amber | `#E8AE68` | large panels (dataset overview, metric blocks) — **before** state |
| butter | `#F6E98C` | large panels (alternating with amber); **missing** values |
| lavender | `#D3A5F2` | **outliers** |
| sky | `#7FD0E6` | **duplicate** records |
| blush | `#F0A8A0` | secondary highlights, selected-row emphasis, diff cells |
| vermilion | `#E8562E` | **invalid** entries, errors, destructive actions |
| mint | `#9ADFA6` | **valid / pass / cleaned** — the **after** state (the one color added beyond the reference, because the pipeline needs a clear pass state) |

Status map (used consistently in chips, tables, charts): `missing = butter`,
`duplicate = sky`, `invalid = vermilion`, `outlier = lavender`, `valid = mint`,
`before = amber`, `after = mint`.

### Color rules
- **Panels:** full-color fills with a 2px ink border, alternating amber and butter.
- **Text:** ink on every fill. White only on ink backgrounds. Never white on
  terracotta/amber/pastels (terracotta ≈ 2.7:1 with white — fails).
- **Statuses:** fill **plus** a text label (`MISSING`, `DUPLICATE`, `INVALID`,
  `OUTLIER`, `VALID`); don't place a status color on a terracotta/amber panel without
  its border + label.
- **Contrast:** ink on every fill ≥ 4.7:1 (vermilion is the tightest).
- **Dark mode:** page → ink, text → paper, borders → paper. Panels/statuses keep their
  fills and ink text. Focus ring → butter. No CSS media queries; a `mode` Observable
  swaps the token set.

## 2. Typography

- **Headings & labels:** `ui-monospace, "Courier New", monospace`, 700, uppercase for h1 and labels.
- **Body:** `system-ui, sans-serif`, 400, 16px / 1.6, max 72ch.
- **Data** (tables, counts, code, logs): monospace with `tabular-nums`; numbers right-aligned, text left-aligned.
- **System fonts only.** No web fonts → works offline during the demo.
- **Links:** ink, underlined. No blue anywhere.

Scale:
- Hero metric: `clamp(2.5rem, 6vw, 4.5rem)` 700 monospace
- H1 `2.25rem` · H2 `1.5rem` · Body `1rem/1.6` · data/small `0.875rem` · label-caps `0.75rem` 600 `0.08em` letterspacing uppercase

## 3. Layout

- **Grid:** CSS Grid, 12 columns, max-width 1280px, 1.5rem side padding, **grid lines visible** (2px ink borders between regions).
- **Shell:** asymmetric — left rail (3 cols) = pipeline stepper (7 steps: Raw Dataset → Data Inspection → Quality Assessment → Cleaning → Transformation → Validation → Final Dataset); main area (9 cols) = active stage.
- **Before/After:** split panel **7/5**, raw left (wider — it carries the problems), cleaned right. Never 50/50, never three equal columns.
- **Metric rows:** varied block sizes — headline metric large, supporting metrics small.
- **Spacing:** 8px base unit; section gaps `clamp(2rem, 5vw, 4rem)`.
- **Mobile (<768px):** everything collapses to one column; tables scroll inside their own container (`overflow-x: auto`); the page never scrolls sideways.
- **z-index contract:** base 0 / sticky-header 100 / overlay 200 / modal 300 / toast 500.

## 4. Elevation & depth

- **Radius:** `0px` everywhere (inputs, chips, charts, focus rings).
- **Shadow:** `4px 4px 0 #1A1A1A`, no blur — cards and primary buttons only.
- **Borders:** 1px (table cells), 2px (components/panels), 4px (section dividers, active stage).
- **Transitions:** none — every state change is instant.
- **Pressed state:** button translates `(4px,4px)`, its shadow becomes 0 (stamped down).
- **Loading:** block progress bar of ink squares + text counter (`STEP 3/7`). No spinners, no shimmer.
- **Reduced motion:** nothing to disable — nothing animates.

## 5. Core components

- **Pipeline Stepper (left rail):** 7 bordered rows — number + caps name + status word
  (`PENDING` / `RUNNING` / `DONE`). Active = terracotta fill; done = mint; pending = paper.
- **Panel:** full-color fill (amber/butter alternating), 2px ink border, 24px padding, hard shadow.
- **Button Primary:** terracotta fill, ink text, 2px border, hard shadow, caps label (`RUN PIPELINE`).
- **Button Secondary:** ink fill, paper text, 2px border, caps label (`EXPORT LOG`).
- **Button Destructive:** vermilion fill, ink text; requires a confirm step.
- **Status Chip:** 2px border, ink text, status fill, always a word (`MISSING`…`VALID`), optionally a text glyph (`! = X ^ OK`) for grayscale.
- **Data Table:** 1px ink cell borders, 2px ink header (caps), sticky header, cream zebra, monospace values; flagged cells take the status fill; selected row = blush; `showing N of M` line above.
- **Metric Block:** large monospace number + caps label; before/after shows both (`BEFORE → AFTER`), the improved after value sits on mint.
- **Code Block (Julia):** ink background, paper text, line numbers, horizontal scroll; one-line caps caption stating WHAT and WHY.
- **Log Console:** code-block style, timestamped, append-only, exportable as text.
- **Validation Checklist:** assertions with `PASS` (mint) / `FAIL` (vermilion) chips.
- **Alert:** full-width bordered bar, status-colored 16px left block + caps label.
- **Inputs / File Picker:** label above, 2px border, paper fill, no floating labels; focus ring 3px ink outline offset 2px (butter in dark mode).
- **Tabs:** square, active tab ink fill + paper text, instant switching.
- **Empty State:** bordered cream box + plain text + one action (`NO FILE LOADED. LOAD data/raw/ FILE.`).

## 6. Screens

Mapped to the paper's sections and the video's BEFORE → DURING → AFTER order:

1. **Dataset** — record/variable counts, variable list with detected types, time coverage (paper 3.1)
2. **Quality Assessment** — metric blocks + tables (missing, duplicate, invalid, type, outlier, format) (paper 3.4/4.1)
3. **Cleaning Log** — stepper RUNNING, current Julia code block, live log console (video "during")
4. **Before / After** — 7/5 split comparison table + charts (paper 4.3)
5. **Validation** — assertion checklist (paper 3.3, step 9)
6. **Final Dataset** — cleaned table preview, `DOWNLOAD CSV`, file details
7. **Report Evidence** (nav: `REPORT`) — every table & figure the paper/video needs, re-rendered automatically from `results/` + `figures/`. Never contains hand-typed numbers.

### Report Evidence layout
- Header strip (4px bottom border): run ID, timestamp, Julia version, raw file name+size, records in → out, freshness badge `CURRENT` (mint) / `STALE` (vermilion) / `NO RUN` (cream).
- Tabs: `TABLES` | `FIGURES` | `RECONCILIATION` | `EXPORT`.
- Left rail (3 cols): table/figure index grouped by paper section, `READY` / `N/A` / `STALE` status per entry.
- Main (9 cols): selected table (Report Table) or figure (Figure Card).
- Run history drawer: pick two runs → diff (changed cells get blush + a `was X` line).
- **Reconciliation Banner:** full-width bar — mint `RECONCILED: {IN} − {REMOVED} = {OUT}` or vermilion `MISMATCH` (shows real numbers, format template above).
- Cross-links: T5 cells link to detail tables (Missing → T6/T7, Duplicates → T8, Invalid → T9, Types → T10, Outliers → T12).

## 7. Report tables

### 7.1 Required table T5 — must match the assignment exactly (4 columns, 5 rows, this order, no renames)

| Data Quality Issue | Before Preprocessing | Action Taken | After Preprocessing |
|---|---|---|---|
| Missing Values | count (%) | technique, e.g. "median imputation (n cols); N rows dropped" | count (%) |
| Duplicate Records | count | "removed N full-row, N key-column" | count |
| Invalid Entries | count | "set to missing / corrected / removed (by rule)" | count |
| Incorrect Data Types | N columns | "converted col: from → to" | N columns |
| Outliers | N values flagged | "flagged, retained / capped" | N flagged, N still present |

**Rule:** additional issues (formatting inconsistencies, unnecessary variables) go in a
**separate** table directly below, labeled `ADDITIONAL ISSUES`, so the required table is
never altered. Every T5 cell links to its detail table.

### 7.2 Table inventory (T1–T21) — all generated from `results/`

| No. | Table | Paper section | Source file |
|---|---|---|---|
| T1 | Packages and purposes | 3.2 | `packages.csv` |
| T2 | Dataset description | 3.1 | `dataset_profile.csv` |
| T3 | Variable dictionary (name, unit, type before→after, missing before/after, kept/removed, description) | 3.1, 4.2 | `variable_dictionary.csv` |
| T4 | Preprocessing procedure summary (problem, technique, function, reason, rows/cells affected) | 3.3 | `decision_log.csv` |
| T5 | **Required** before/after table (above) | 3.4, 4.1 | `quality_summary.csv` |
| T5b | Additional issues | 4.1 | `quality_summary_extra.csv` |
| T6 | Missing values per column, before/after + treatment | 4.2 | `missing_by_column.csv` |
| T7 | Placeholder tokens (token, column, count, mapped to) | 3.4, 4.2 | `placeholders.csv` |
| T8 | Duplicates (per tab & combined; full-row vs key-column; removed) | 4.2 | `duplicates.csv` |
| T9 | Invalid entries by rule (rule, column, flagged, action, 5 examples) | 4.2 | `invalid_by_rule.csv` |
| T10 | Data type corrections (column, from, to, parse failures) | 4.2 | `type_corrections.csv` |
| T11 | Standardization map (column, variants, standard, rows changed) | 4.2 | `standardization_map.csv` |
| T12 | Outlier summary per parameter (Q1, Q3, IQR bounds, n IQR, n z, n retained, decision) | 4.2 | `outliers.csv` |
| T13 | Columns and records removed (item, reason, count) | 4.2 | `removed_items.csv` |
| T14 | Transformations (new/renamed variables, formula/rule) | 4.2 | `transformations.csv` |
| T15 | Descriptive stats before vs after per key parameter (n, mean, median, SD, min, max) | 4.3 | `descriptives_before_after.csv` |
| T16 | Before-and-after comparison (records, variables, completeness %, duplicates, correct types, consistency) | 4.3 | `before_after.csv` |
| T17 | Data quality scorecard (completeness, uniqueness, validity, consistency, type correctness; before % and after %) | 4.3 | `scorecard.csv` |
| T18 | Row-count reconciliation (input − each logged removal = output) | 3.3/9, 4.3 | `reconciliation.csv` |
| T19 | Validation checks (assertion, status, detail) | 3.3/9 | `validation.csv` |
| T20 | Coverage (records per year, before/after) | 4.3 | `coverage.csv` |
| T21 | Remaining concerns & limitations (**only manually edited file**) | 4.3, 4.4 | `concerns.md` |

### 7.3 Report Table component
Caption above (`TABLE N. title`), source tag below (`SOURCE: results/file.csv, run ID, timestamp`), buttons `COPY (WORD)` / `CSV` / `MARKDOWN`. Numbers right-aligned, % one decimal, empty cells `N/A` on cream (never 0).

## 8. Figures (F1–F16, generated by Julia → `figures/fig01..fig16`, SVG + 300 dpi PNG)

| No. | Figure | Type | Paper section |
|---|---|---|---|
| F1 | Pipeline workflow (the 7 stages) | block diagram (stepper, exported) | 3.3 |
| F2 | Missing values per column, raw | horizontal bars, sorted, % labels | 4.1 |
| F3 | Missing values per column, before vs after | grouped horizontal bars | 4.2 |
| F4 | Missingness pattern | matrix heatmap (rows binned × columns) | 4.1 |
| F5 | Record flow raw → final | waterfall (raw, −duplicates, −invalid, −other, final) | 4.2 |
| F6 | Invalid entries by rule | horizontal bars | 4.1 |
| F7 | Data types before vs after | stacked bars (correct/incorrect per type) | 4.2 |
| F8 | Outliers per key parameter | boxplots, outliers in lavender | 4.1 |
| F9 | Distributions before vs after, key parameters | paired histograms (log x if skewed) | 4.3 |
| F10 | Central tendency by year with spread | yearly median line + IQR band, before & after | 4.3 |
| F11 | Records by year (& station) | bars / heatmap | 4.3 |
| F12 | Completeness by column | dumbbell (before dot → after dot) | 4.3 |
| F13 | Data quality scorecard | paired horizontal bars (5 dims, 0–100%) | 4.3 |
| F14 | Standardization effect | variant counts collapsing to one standard | 4.2 |
| F15 | Share of below-detection-limit (`<x`) values per parameter | horizontal bars | 4.1 |
| F16 | Correlation among numeric parameters, after cleaning | heatmap (optional) | 4.4 |

Supersedes the earlier figure files (`fig_missing_before_after`, `fig_record_counts`,
`fig_outlier_boxplots`, `fig_distributions_before_after`) — their content is folded into
F3, F5, F8, F9. Old names are not produced anymore.

### Chart style rules (all figures)
- Flat fills, no gradients/3D/shadows on marks; 2px ink stroke on bars/boxes; 1px ink gridlines on paper.
- Status colors as in §1; **before = amber, after = mint** across every figure.
- Direct series labels (no separate legend where possible); values printed on bars (monospace).
- Boxplot outliers: lavender points with ink outline.
- Each figure card: `FIG. N. description`, paper-section tag, alt text, `SVG` / `PNG (300 dpi)` / `COPY CAPTION`.
- **Only draw figures for columns/issues that actually exist**; anything absent is `N/A` in the index, never an empty chart.

## 9. Do's and Don'ts

**Do:** keep 0px radius, 2px borders, hard shadow · instant state changes · alternate amber/butter panels · label every status with a word + color · monospace right-aligned numbers · show real values from pipeline output (`N/A` before a run) · keep grid + borders visible.

**Don't:** gradients, blur, soft shadow, rounded corners · emojis (text glyphs / Lucide) · fabricated numbers or sample rows (use real output or `{placeholder}` marks) · status/panel colors as text on paper (text is ink or paper) · white text on terracotta/amber/pastels · three equal columns or `h-screen` (use `min-h-[100dvh]`) · AI copy clichés · external fonts/images/CDNs.

## 10. Implementation stack (Julia only)

Every token, component, screen, and chart lives in `.jl`. Bonito ships its own browser
runtime — no authored JS. CSS is `CSS("property" => "value")` pairs in Julia.

### Packages
```
] add Bonito Observables CairoMakie Colors PrettyTables Tables DataFrames CSV JSON3 WGLMakie
```

| Package | Design role |
|---|---|
| Bonito.jl | App, `DOM`, `Styles`/`CSS`, `Card`, `Grid`/`Row`/`Col`, `Button`, `TextField`, `Dropdown`, `Label`, `export_static` |
| Observables.jl | Reactive state (stage status, refresh tick, light/dark mode) |
| CairoMakie | Themed figures → SVG + PNG into `figures/` |
| WGLMakie | Interactive versions of F8–F10 in the live app |
| Colors.jl | Palette tokens (`parse(Colorant, hex)`) |
| PrettyTables.jl (v3) | `pretty_table(String, df; backend=:markdown/:latex/:html)` for copy/export |
| Tables/DataFrames/CSV | Read `results/*.csv` |
| JSON3.jl | Read `run_manifest.json` |

Stdlib: `Dates`, `FileWatching`, `SHA`, `Printf`.

### File layout
```
src/ui/
  BrutalUI.jl      # module: includes the files below
  tokens.jl        # palette, type, borders, shadows, status map
  styles.jl        # GLOBAL styles
  theme_makie.jl   # brutal_theme() + save_fig()
  components.jl    # panel, status_chip, buttons, metric_block, report_table, figure_card, stage_row
  screens.jl       # dataset, quality, cleaning_log, before_after, validation, final, report
  app.jl           # App, Server, export_static
```

### Key architecture decisions
- **Tokens in `tokens.jl`** — the single source of truth, imported everywhere including the Makie theme (`col(hex) = parse(Colorant, hex)`).
- **`brutal_theme()`**: 2px spines/ticks, 1px gridlines (40% ink), `strokewidth=2` on BarPlot/BoxPlot, 2px boxed Legend, Courier New for fonts (verify render; else drop), `palette` = [AMBER, MINT, SKY, LAVENDER, BUTTER, VERMILION].
- **`save_fig(name, fig)`** writes `figures/$name.svg` + `figures/$name.png` (`px_per_unit=3`).
- **`Card` breakage guard:** Bonito `Card` defaults are rounded + soft-shadowed — always pass `border_radius="0px"`, `shadow_size="4px 4px 0"`, `shadow_color=INK`, `padding`, `margin=0`.
- **No `.css/.js/.html/.py/.R` authored**: HTML is exported (`export_static("report/index.html", app)`) for the offline demo. Interactions via Observables only — no `js"..."` calls.
- **dark mode:** `mode = Observable(:light)`; a `MODE` button swaps the token set; no media queries.
- **deployment:** `Bonito.Server(app, "127.0.0.1", 8080)` for the live demo + `export_static` single-file page for the video.

## 11. Report Evidence module — artifact contract (Julia, Stage 4b)

Run at the end of the pipeline via `write_report_artifacts(run)`:

1. Writes everything below to `results/` + `figures/` and a snapshot copy to `results/runs/<run_id>/` (run history/diff).
2. `quality_summary.csv` = **T5 exact format**; `quality_summary_extra.csv` = additional issues.
3. One CSV per T1–T20 entry (columns implied by name; header comment states the paper section), plus `run_manifest.json` (run_id, timestamp, Julia version, package versions, raw file name+size+SHA, rows/cols in/out).
4. **Scorecard formulas** (logged in the console):
   - completeness = non-missing cells / total cells
   - uniqueness = 1 − duplicate rows / total rows
   - validity = passing range/format rules / values checked
   - consistency = 1 − non-standard-variant rows / rows checked
   - type correctness = intended-type columns / total columns
   - each reported as % before and after in `scorecard.csv`
5. **Reconciliation:** `reconciliation.csv` lists input rows, every logged removal (reason + count), output rows; `@assert input − sum(removals) == output` (per tab too).
6. Figures F1–F16 per §8; only for existing columns/issues.
7. **UI contract:** REPORT page reads these files only; missing file → `N/A`; `STALE` when raw/script newer than latest run; reconciliation banner; T5↔detail consistency checks; no hand-typed numbers (only `concerns.md` editable).
8. **Reproducibility:** fresh-session re-run produces identical files except timestamp/run_id.

### Acceptance criteria
- [ ] `quality_summary.csv` has exactly the 5 required rows × 4 columns
- [ ] every paper number traces to a file in `results/`
- [ ] fresh re-run reproduces identical files (except timestamp/run_id)
- [ ] reconciliation passes
- [ ] each figure has caption, alt text, paper-section tag
- [ ] table/figure numbering matches the paper

## 12. Delivery order (as scoped)

1. **design.md** ✅ — this document (styling + architecture only).
2. **Packages:** add Bonito, JSON3, WGLMakie to the project. ✅
3. **Artifacts:** `write_report_artifacts(run)` in `src/preprocess.jl` → T1–T20 CSVs, `run_manifest.json`, `quality_summary.csv` (T5), reconciliation, scorecard. ✅
4. **Figures:** replace the 4 legacy figures with `fig01..fig16` under `brutal_theme()`. ✅
5. **UI:** `src/ui/` Bonito app — 7 screens, REPORT page, live server + `export_static`. ✅

### Delivered (step 5) — how to run

- Live server: `julia --project=. -e 'include("src/ui/BrutalUI.jl"); BrutalUI.run_server()'` → http://127.0.0.1:8080
- Static export: `julia --project=. -e 'include("src/ui/BrutalUI.jl"); BrutalUI.export_report()'` → `report/index.html` (single self-contained file; figures + evidence embedded as data URIs)
- Files: `src/ui/BrutalUI.jl` (module), `tokens.jl` (palette), `styles.jl` (global CSS),
  `theme_makie.jl` (brutal_theme/save_fig, shared with the pipeline), `components.jl`
  (panel/chip/metric/report-table/figure-card), `screens.jl` (7 screens + data layer +
  run-history diff), `app.jl` (build_app/run_server/export_report).
- Verified: all 16 figures build, 7 screens render without errors in static export,
  live server serves HTTP 200, freshness badge flips STALE→CURRENT per evidence run.
- Design deltas (bounded scope, recorded): RECONCILIATION is a banner on every screen
  (design §6 shows it on the REPORT page); MODE toggles page chrome only (panels keep
  their fills per §1); T5 cross-links are chips underneath the untouched table (no JS
  authored, so no in-cell links); run history diffs cells with a blush fill + "was X"
  tooltip instead of a side-by-side split.