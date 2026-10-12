# READ-ONLY Phase 1f: WHERE do the partial gaps live? For each column
# with ~160 missing within measurement-bearing records, prints the
# years/months of the gaps -> scattered (imputable) vs blocked (structural).
using XLSX, Dates

const RAW = joinpath(@__DIR__, "..", "data", "raw",
                     "MMORS_water_quality_results_2012-2018_orig.xlsx")
# col index within data matrix for each target parameter
const TARGETS = Dict("ph" => 8, "tss" => 11, "nitrates" => 16,
                     "phosphates" => 17, "ammonia" => 15,
                     "total_coliform" => 14)

ismisslike(v) = ismissing(v) ||
    (v isa AbstractString &&
     (strip(v) in ("-", "_", "", "n/a", "N/A", "ND") ||
      occursin("NO SAMPLING", uppercase(v))))

function main()
    xf = XLSX.openxlsx(RAW)
    # gather (year,label) for each missing cell of each target
    gaps = Dict(p => String[] for p in keys(TARGETS))
    anypresent = Dict(p => String[] for p in keys(TARGETS))
    curperiod = missing
    for name in ["Marilao", "Meycauayan", "Obando"]
        data = XLSX.readdata(RAW, name, string(xf[name].dimension))
        for r in 1:size(data, 1)
            v1 = data[r, 1]
            if v1 isa AbstractString && startswith(v1, "CY ")
                curperiod = v1
            end
            v1 isa Integer || continue
            vals = [data[r, c] for c in 7:18]
            count(x -> !ismisslike(x), vals) == 0 && continue
            # derive a period tag: real date if present, else the CY label
            tag = data[r, 5] isa Date ? string(year(data[r, 5])) :
                  (curperiod isa String ? first(curperiod, 9) : "unknown")
            for (p, c) in TARGETS
                if ismisslike(data[r, c])
                    push!(gaps[p], tag)
                else
                    push!(anypresent[p], tag)
            end
            end
        end
    end
    for p in sort(collect(keys(TARGETS)))
        g = gaps[p]
        a = anypresent[p]
        gc = Dict(k => count(==(k), g) for k in unique(g))
        println("\n", p, ": ", length(g), " gaps | years of gaps: ",
                sort(collect(gc)))
        println("   years WITH data: ",
                sort(collect(Dict(k => count(==(k), a) for k in unique(a)))))
    end
end

main()
