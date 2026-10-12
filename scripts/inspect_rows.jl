# READ-ONLY Phase 1c: understand row semantics inside the data region.
# Prints cols 1-7 (+18) for key row ranges of each station sheet.
using XLSX, Dates

const RAW = joinpath(@__DIR__, "..", "data", "raw",
                     "MMORS_water_quality_results_2012-2018_orig.xlsx")
const COLS = [1, 2, 3, 5, 6, 7, 8, 18]   # code, station, lat, date, time, DO, pH, Cl

xf = XLSX.openxlsx(RAW)

function showrows(data, rows, label)
    println("\n--- ", label, " ---")
    for r in rows
        vals = [data[r, c] for c in COLS]
        # compact: shorten long strings
        s = join([v isa AbstractString ? repr(first(v, 40)) : string(v) for v in vals], " | ")
        println("  r", r, ": ", s)
    end
end

for name in ["Marilao", "Meycauayan", "Obando"]
    sheet = xf[name]
    data = XLSX.readdata(RAW, name, string(sheet.dimension))
    nr, nc = size(data)
    println("\n", "="^70)
    println("SHEET $name ($nr rows)")

    # Where do "CY ..." period labels live in col1?
    lbl = [r for r in 1:nr
           if data[r, 1] isa AbstractString && startswith(data[r, 1], "CY ")]
    println("col1 'CY ...' label rows: n=", length(lbl),
            " first=", first(lbl, 5), " last=", last(lbl, 5))

    # Rows where col1 is an integer (station code?) and col5 has a real Date
    coded = [r for r in 1:nr if data[r, 1] isa Integer]
    dated = [r for r in 1:nr if data[r, 5] isa Date]
    both  = [r for r in 1:nr if data[r, 1] isa Integer && data[r, 5] isa Date]
    println("col1 Integer rows: ", length(coded),
            " | col5 Date rows: ", length(dated),
            " | both: ", length(both))
    # Rows with station name but no date (station-list / label blocks?)
    nodate = [r for r in coded if !(data[r, 5] isa Date)]
    println("col1 Integer but col5 NOT Date: ", length(nodate),
            " e.g. ", first(nodate, 10))
    if !isempty(nodate)
        for r in first(nodate, 4)
            println("   r", r, ": ", repr(data[r, 1:min(nc, 7)]))
        end
    end

    # First 40 rows after the last CY label and around data start
    showrows(data, 13:min(45, nr), "rows 13-45 (region start)")
    # Around the stray fragment in Marilao
    if name == "Marilao"
        showrows(data, 430:445, "rows 430-445 (stray fragment)")
    end
    showrows(data, max(1, nr - 12):nr, "last 13 rows (footer)")
end
