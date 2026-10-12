# READ-ONLY Phase 1b probe: inspect the DATA region (rows 11+) of the
# three station sheets. Finds real record counts, placeholder strings,
# numeric ranges, date ranges, and stray cells in unheadered columns.
using XLSX, Dates

const RAW = joinpath(@__DIR__, "..", "data", "raw",
                     "MMORS_water_quality_results_2012-2018_orig.xlsx")
const HEADER_ROW = 9        # actual column names (row 8 = grouped headers)
const GUIDELINE_ROW = 10    # WQG metadata row (not a record)
const DATA_START = 11       # first data row

xf = XLSX.openxlsx(RAW)
sheets = filter(s -> s != "Table1 (3)", XLSX.sheetnames(xf))

for name in sheets
    sheet = xf[name]
    dim = string(sheet.dimension)
    data = XLSX.readdata(RAW, name, dim)
    nr, nc = size(data)
    println("\n", "="^70)
    println("SHEET $name | raw size: $nr x $nc")

    headers = [ismissing(data[HEADER_ROW, c]) ? "col$c" : string(data[HEADER_ROW, c])
               for c in 1:nc]
    println("headers: ", headers)

    # Guideline row content (metadata living inside the sheet)
    println("guideline row $GUIDELINE_ROW: ", repr(data[GUIDELINE_ROW, :]))

    # Rows 8/9 for columns beyond the named ones (Marilao has extra cols)
    extra = findall(c -> !ismissing(data[9, c]) || !ismissing(data[8, c]), 1:nc)
    println("cols with header text in row 8/9: ", extra)

    # Actual data rows: drop fully-missing rows (Excel padding)
    datarows = DATA_START:nr
    nonempty = [r for r in datarows if any(!ismissing, data[r, :])]
    println("data region rows $DATA_START:$nr -> non-empty records: ",
            length(nonempty), " (padding dropped: ",
            length(datarows) - length(nonempty), ")")
    if isempty(nonempty)
        continue
    end

    # Per-column profile over the actual records
    for c in 1:nc
        vals = [data[r, c] for r in nonempty]
        present = filter(!ismissing, vals)
        isempty(present) && begin
            println("  col$c $(headers[c]): ALL MISSING"); continue
        end
        ttypes = sort(unique(string(typeof(v)) for v in present))
        # string values reveal placeholders like "ND", "<0.5", "n/a"
        svals = sort(unique(string(v) for v in present if v isa AbstractString))
        msg = "  col$c $(repr(headers[c])): n=$(length(present)) types=$ttypes"
        if !isempty(svals)
            msg *= " strings=" * string(first(svals, 15))
        end
        nums = [float(v) for v in present if v isa Real]
        if length(nums) == length(present)
            msg *= " min=$(minimum(nums)) max=$(maximum(nums))"
        end
        if any(v -> v isa Date, present)
            ds = [v for v in present if v isa Date]
            msg *= " dates=$(minimum(ds))..$(maximum(ds))"
        end
        println(msg)
    end

    # Stray cells in columns without headers (Marilao cols 19+)
    straycols = [c for c in 1:nc if headers[c] == "col$c"]
    for c in straycols
        cells = [(r, data[r, c]) for r in 1:nr if !ismissing(data[r, c])]
        println("  STRAY col$c: ", length(cells), " cells; first 8: ",
                first(cells, 8))
    end

    # First 3 and last 3 actual records
    for r in first(nonempty, 3)
        println("  row$r: ", repr(data[r, :]))
    end
    println("  ...")
    for r in last(nonempty, 3)
        println("  row$r: ", repr(data[r, :]))
    end
end
