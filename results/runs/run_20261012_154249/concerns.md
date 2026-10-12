# Remaining concerns and limitations (T21)

> Regenerated on every run; this is the only file under `results/` intended for hand editing.

## Structural gaps stay missing

- 4519 parameter cells are still missing after cleaning. They are era-blocked (e.g. pH was never measured in 2012) or campaign-only, so Decision B leaves them empty instead of inventing measurements.

## Imputed cells are estimates

- 116 cells were filled with the station-year median and are listed per row in `imputed_params`; they are not observations and should be excluded from any measurement of extremes.

## Outliers are flagged, not judged

- 357 cells (293 rows) fall outside Tukey fences and are listed in `outlier_params`. Extreme ambient values (anoxic DO, estuarine chlorides) are frequently real events; no domain-specific water-quality threshold was applied.

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
