# READ-ONLY Phase 1d: missingness profile over candidate record rows
# (rows where col1 is a station code). Counts true missing, placeholder
# strings, and present values per column, aggregated across the 3 sheets.
using XLSX

const RAW = joinpath(@__DIR__, "..", "data", "raw",
                     "MMORS_water_quality_results_2012-2018_orig.xlsx")
const PARAMS = ["period", "station_name", "latitude", "longitude",
                "date", "time", "dissolved_oxygen", "ph", "temperature",
                "bod", "tss", "color", "fecal_coliform", "total_coliform",
                "ammonia", "nitrates", "phosphates", "chlorides"]

# values that mean "explicitly no measurement recorded here"
isplaceholder(v) = v isa AbstractString &&
    (strip(v) in ("-", "_", "", "n/a", "N/A", "ND") ||
     occursin("NO SAMPLING", uppercase(v)))

function main()
    nrec = 0
    counters = [Dict("present" => 0, "missing" => 0, "placeholder" => 0,
                     "invalid" => 0) for _ in 1:18]
    station_nosampling = 0

    xf = XLSX.openxlsx(RAW)
    for name in ["Marilao", "Meycauayan", "Obando"]
        data = XLSX.readdata(RAW, name, string(xf[name].dimension))
        for r in 1:size(data, 1)
            data[r, 1] isa Integer || continue
            nrec += 1
            allph = true
            for (i, c) in enumerate(1:18)
                v = data[r, c]
                if v isa AbstractString && occursin("NO SAMPLING", uppercase(v))
                    counters[i]["placeholder"] += 1
                elseif v isa AbstractString && (strip(v) in ("-", "_", "", "n/a", "N/A", "ND")
                                                || length(strip(v)) == 0)
                    counters[i]["placeholder"] += 1
                elseif ismissing(v)
                    counters[i]["missing"] += 1
                elseif v isa AbstractString && i >= 3
                    # string in a numeric/date/time column -> invalid entry
                    counters[i]["invalid"] += 1
                else
                    counters[i]["present"] += 1
                    i >= 7 && (allph = false)
                end
            end
            allph && (station_nosampling += 1)
        end
    end

    println("candidate records: ", nrec)
    println("records with ALL 12 parameters empty/placeholder: ", station_nosampling)
    println("\nparam                 present   missing   phMissing  invalid  missing%")
    for (i, p) in enumerate(PARAMS)
        c = counters[i]
        tot = c["present"] + c["missing"] + c["placeholder"] + c["invalid"]
        miss = c["missing"] + c["placeholder"]
        println(rpad(p, 21), " ", lpad(c["present"], 7), " ", lpad(c["missing"], 9),
                " ", lpad(c["placeholder"], 10), " ", lpad(c["invalid"], 8), "   ",
                round(100 * miss / tot; digits = 1), "%")
    end
end

main()
