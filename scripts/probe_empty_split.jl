using XLSX, DataFrames
cd(joinpath(@__DIR__, "..", "src"))
code = read("preprocess.jl", String)
idx = findfirst("include(joinpath(@__DIR__, \"ui\", \"tokens.jl\"))", code)
code = code[1:(idx.start - 1)]
include_string(Main, code)

raw, ext = extract_records()
empty(r) = all(p -> ismissing(r[p]) || is_placeholder(r[p]), PARAM_NAMES)

# replicate OUR dedup keep-first mask on our key
keys = dup_keys(raw)
seen = Set{String}(); keep = Bool[]
for k in keys; push!(keep, !(k in seen)); push!(seen, k); end
df = raw[keep, :]
n0 = nrow(df)
hasdate = [!ismissing(r.Date) for r in eachrow(df)]
empt = [empty(r) for r in eachrow(df)]

println("post-dedup rows (ours, 1147-31): ", n0)
println("empty(all-params-missing, OUR 175): ", sum(empt))
println("  empty WITH date present: ", count(i -> empt[i] && hasdate[i], 1:n0))
println("  empty WITHOUT date     : ", count(i -> empt[i] && !hasdate[i], 1:n0))
println("rows with NO date at all : ", count(i -> !hasdate[i], 1:n0))
println("dup rows kept-first that were empty (removed in dup pass): ", 1147 - n0)
println()
for wb in ["Marilao", "Meycauayan", "Obando"]
    m = df.water_body .== wb
    em = empt .& m
    d  = hasdate .& m
    println(wb, ": empties=", sum(em), "  empties-with-date=",
            count(i -> em[i] && hasdate[i], 1:n0), "  no-date-rows=",
            count(i -> !hasdate[i] && m[i], 1:n0))
end
println()
println("date present but all params missing => they kept (?) ", 
        count(i -> empt[i] && hasdate[i], 1:n0))
println("no date + all params missing => the 'junk' subset         ", 
        count(i -> empt[i] && !hasdate[i], 1:n0))