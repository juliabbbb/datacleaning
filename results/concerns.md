# Remaining concerns and limitations (T21)

> Regenerated on every run; this is the only file under `results/` intended for hand editing.

## Structural gaps stay missing

- 4519 parameter cells are still missing after cleaning. They are era-blocked (e.g. pH was never measured in 2012) or campaign-only, so Decision B leaves them empty instead of inventing measurements.

## Imputed cells are estimates

- 116 cells were filled with the station-year median and are listed per row in `imputed_params`; they are not observations and should be excluded from any measurement of extremes.

## Outliers are flagged, not judged

- 357 cells (293 rows) fall outside Tukey fences and are listed in `outlier_params`. Extreme ambient values (anoxic DO, estuarine chlorides) are frequently real events; no domain-specific water-quality threshold was applied.

## Outlier fences are pooled in the primary profile

- The combined file's `outlier_params` uses IQR fences pooled across all three water bodies (primary profile). Per-water-body fences are provided additively in `outliers_per_river.csv` and the `outlier_params_river` column of each per-river CSV; `outliers_fence_compare.csv` lists the flagged-cell difference per parameter. Values are kept in both, and `fence_method` labels every outlier table.

## Paper retained its outliers

- The reference paper does NOT remove or cap its outliers, and neither do we (IQR flagging only, values kept). Report this as retained, never as removed.

## Paper-parity check: censored cells differ

- The paper's nitrate statistics are only reproducible if its sheet held '0.48*' where ours holds '<0.048*' (60 cells), and its total-coliform mean only if it held '>1600000' where ours holds '>16000000' (1 cell); 0.48 is 10x our detection limit and both workbooks agree otherwise. We keep our values. Confirm with the adviser which workbook was used (see `paper_vs_ours.csv`, metric `censored_reconciliation`).

## Dates are partly unknown

- 156 records (2012) have no sampling date: year and month come from the 'CY ...' period label and the exact day is unknown. Anything daily or event-based cannot be computed for those records.

## Duplicates are resolved by rule, not by review

- 30 exact and 1 same-date/time duplicates were dropped keep-first. 0 period-keyed conflicts had no date to verify and were kept as-is.

## Formatting fixes are mechanical

- 1147 rows had irregular whitespace in station or period text and were normalized; no spelling, renaming or geocoding of stations was attempted.

## Excluded content is not analyzed

- 30 cells outside the 18-column schema, 37 non-record rows and 1 stub worksheet were excluded at load time (they duplicate or contradict the main table).

## Coverage is uneven

- Records per year and per worksheet are not balanced (see `coverage.csv`); trends computed across years should be read with the sample counts in view.
