# READ-ONLY Phase 1e: missingness CONDITIONED on records that have at
# least one parameter measured. Separates whole-row gaps (no sampling)
# from scattered per-column gaps (the only place imputation could apply).
using XLSX

const RAW = joinpath(@__DIR__, "..", "data", "raw",
                     "MMORS_water_quality_results_2012-2018_orig.xlsx")
const PARAMS = ["dissolved_oxygen", "ph", "temperature", "bod", "tss",
                "color", "fecal_coliform", "total_coliform", "ammonia",
                "nitrates", "phosphates", "chlorides"]

ismisslike(v) = ismissing(v) ||
    (v isa AbstractString &&
     (strip(v) in ("-", "_", "", "n/a", "N/A", "ND") ||
      occursin("NO SAMPLING", uppercase(v))))

function main()
    xf = XLSX.openxlsx(RAW)
    rows_any = 0
    rows_none = 0
    miss = zeros(Int, 12)      # missing among rows_any
    nrows_with_gap = 0
    gapsize = Int[]            # how many params missing per gapped row
    for name in ["Marilao", "Meycauayan", "Obando"]
        data = XLSX.readdata(RAW, name, string(xf[name].dimension))
        for r in 1:size(data, 1)
            data[r, 1] isa Integer || continue
            vals = [data[r, c] for c in 7:18]
            present = count(v -> !ismisslike(v), vals)
            if present == 0
                rows_none += 1
                continue
            end
            rows_any += 1
            g = 0
            for (i, v) in enumerate(vals)
                if ismisslike(v)
                    miss[i] += 1
                    g += 1
                end
            end
            if g > 0
                nrows_with_gap += 1
                push!(gapsize, g)
            end
        end
    end
    println("records with >=1 measurement: ", rows_any)
    println("records with 0 measurements:  ", rows_none)
    println("records with SOME params missing (partial gaps): ", nrows_with_gap)
    if !isempty(gapsize)
        println("gap sizes (n params missing in those rows): ",
                "min=", minimum(gapsize), " max=", maximum(gapsize),
                " mean=", round(sum(gapsize) / length(gapsize); digits = 1))
    end
    println("\nparam                 missing(within $rows_any)   %")
    for (i, p) in enumerate(PARAMS)
        println(rpad(p, 21), " ", lpad(miss[i], 6), "   ",
                round(100 * miss[i] / rows_any; digits = 1), "%")
    end
end

main()
