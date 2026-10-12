# READ-ONLY Phase 1 probe: inspect the raw workbook structure.
# Nothing is modified here; output feeds the data-quality assessment.
using XLSX

const RAW = joinpath(@__DIR__, "..", "data", "raw",
                     "MMORS_water_quality_results_2012-2018_orig.xlsx")

println("Julia ", VERSION)
println("File exists: ", isfile(RAW))

xf = XLSX.openxlsx(RAW)
sheets = XLSX.sheetnames(xf)
println("SHEETS (", length(sheets), "): ", sheets)

for name in sheets
    sheet = xf[name]
    println("\n", "="^70)
    println("SHEET: ", repr(name))
    dim = try
        sheet.dimension
    catch e
        "n/a (" * sprint(showerror, e) * ")"
    end
    println("dimension field: ", repr(dim))

    # Merged cells (a common Excel quirk that breaks header detection)
    try
        mc = XLSX.getMergedCells(sheet)
        println("merged cells: ", length(mc), " -> ", first(mc, 10))
    catch e
        println("merged cells unavailable: ", sprint(showerror, e))
    end

    # Read whole sheet as raw values, no header/type assumptions
    data = try
        XLSX.readdata(RAW, name, string(dim))
    catch e
        println("readdata with dimension failed: ", sprint(showerror, e))
        nothing
    end
    if data !== nothing
        println("typeof(data): ", typeof(data), " size: ", size(data))
        nrows = min(10, size(data, 1))
        for r in 1:nrows
            println("  row", r, ": ", repr(data[r, :]))
        end
        # Per-column type inventory (detects mixed-type columns)
        types = [sort(unique(string(typeof(data[r, c]))
                               for r in 1:size(data, 1)))
                 for c in 1:size(data, 2)]
        for c in 1:size(data, 2)
            println("  col", c, " types: ", types[c])
        end
    end
end
