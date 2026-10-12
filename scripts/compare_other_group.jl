# Compare "the other group's" reported numbers against OUR extraction.
# Loads preprocess.jl WITHOUT running the pipeline (strips trailing main()).
using XLSX, DataFrames, CSV, Statistics, StatsBase

cd(joinpath(@__DIR__, "..", "src"))   # include_string resolves @__DIR__ to pwd
code = read("preprocess.jl", String)
# Keep everything before the UI/theme/report-artifact includes (which also
# guard the trailing main()). We only need extraction + pipeline functions.
idx = findfirst("include(joinpath(@__DIR__, \"ui\", \"tokens.jl\"))", code)
idx !== nothing && (code = code[1:(idx.start - 1)])
include_string(Main, code)

raw, ext = extract_records()
n0 = nrow(raw)
println("== extracted records: ", n0, " (ours) ==")

st, dt, tm, pe = "Station", "Date", "Time", "period"

dkey(r) = begin
    dcell = r[dt]
    if dcell isa Date
        "D:" * string(dcell)
    elseif dcell isa AbstractString && !is_placeholder(dcell)
        "D:" * norm_key(replace(strip(dcell), r"//+" => "/"))
    else
        "P:" * string(r[pe])
    end
end

# --- duplicates ------------------------------------------------------------
keys_ours   = dup_keys(raw)                                   # water|station|date|time
keys_theirs = [string(r.water_body, "||", norm_key(string(r[st])), "||", dkey(r))
               for r in eachrow(raw)]                         # water|station|date (no time)

n_exact = count(nonunique(raw))
n_dup_ours   = count(nonunique(DataFrame(k = keys_ours)))
n_dup_theirs = count(nonunique(DataFrame(k = keys_theirs)))
println("exact full-row dups: ", n_exact)
println("dup rows (our key, incl time): ", n_dup_ours)
println("dup rows (their key, no time): ", n_dup_theirs)

keepfirst(keys) = begin
    seen = Set{String}(); rm = 0
    for k in keys
        k in seen ? (rm += 1) : push!(seen, k)
    end
    rm
end
rm_ours   = keepfirst(keys_ours)
rm_theirs = keepfirst(keys_theirs)
println("removed keep-first (our key): ", rm_ours, "  (their key): ", rm_theirs)

# rows removed by THEIR key but kept by OURS -> risk of dropping distinct measurements
seen_o = Set{String}(); keep_o = Bool[]
for k in keys_ours; push!(keep_o, !(k in seen_o)); push!(seen_o, k); end
seen_t = Set{String}(); keep_t = Bool[]
for k in keys_theirs; push!(keep_t, !(k in seen_t)); push!(seen_t, k); end
extra = findall(.!keep_t .& keep_o)
withtime = (r -> !ismissing(r[tm])) .| [raw[i, tm] for i in extra]  # placeholder for filter
extra_with_time = count(i -> !ismissing(raw[i, tm]), extra)
extra_nonempty  = count(i -> any(p -> !ismissing(raw[i, p]), PARAM_NAMES), extra)
println("rows removed by their key but kept by ours (risk group): ", length(extra),
        " | with a Time: ", extra_with_time, " | with >=1 measured param: ", extra_nonempty)
for i in extra[1:min(6, length(extra))]
    println("   example: ", raw[i, "water_body"], " | ", raw[i, st], " | ",
            raw[i, dt], " | ", raw[i, tm], " | DO=", raw[i, PARAM_NAMES[1]])
end

# --- zero-measurement vs non-data ------------------------------------------
empty(r) = all(p -> ismissing(r[p]) || is_placeholder(r[p]), PARAM_NAMES)
smissing(r) = ismissing(r[st]) || is_placeholder(r[st])
n_empty       = count(empty, eachrow(raw))
n_emptystat   = count(r -> empty(r) && !smissing(r), eachrow(raw))
n_station_miss = count(smissing, eachrow(raw))
n_empty_nostat = count(r -> empty(r) && smissing(r), eachrow(raw))
println("\n== zero-measurement ==")
println("all-12-params missing (OUR 175 on post-dedup; raw here): ", n_empty)
println("  of which station PRESENT (real rows, no observations): ", n_emptystat)
println("  of which station MISSING (their 'non-data' flavor):    ", n_empty_nostat)
println("rows with station missing overall: ", n_station_miss)

# after THEIR coarse dedup, how many empties remain?
idx_t = Bool[]
stt = Set{String}()
for k in keys_theirs
    push!(idx_t, !(k in stt)); push!(stt, k)
end
after_dup = raw[idx_t, :]
println("after their-key dedup: ", nrow(after_dup),
        " rows; all-params-missing among them: ", count(empty, eachrow(after_dup)))

# --- symbols / invalid -----------------------------------------------------
strays = Pair{String, String}[]
for c in vcat(["Date", "Time"], PARAM_NAMES)
    for v in raw[!, c]
        (v isa AbstractString && !is_placeholder(v)) && push!(strays, c => String(v))
    end
end
n_stray = length(strays)
n_cens  = count(p -> startswith(strip(p.second), "<") || startswith(strip(p.second), ">"), strays)
n_dash  = count(p -> !(startswith(strip(p.second), "<") || startswith(strip(p.second), ">")) && occursin("-", strip(p.second)), strays)
n_mspace = count(p -> occursin(r"\s{2,}|\s\d\.", p.second), strays)
others = [p for p in strays if !(startswith(strip(p.second), "<") || startswith(strip(p.second), ">"))]
println("\n== invalid / symbols ==")
println("stray strings (our invalid=231 basis): ", n_stray)
println("  censored < / > prefix (OUR 214): ", n_cens)
println("  dash-containing (non-censored): ", n_dash)
println("  multi-space / spaced-number: ", n_mspace)
println("  OTHER (the 17): ", length(others))
for p in others
    println("    [", p.first, "] ", repr(p.second))
end

# --- negatives / impossible values -----------------------------------------
neg = 0
for c in PARAM_NAMES, v in raw[!, c]
    (v isa Real && v < 0) && (neg += 1)
end
println("\n== impossible values ==")
println("negative REAL values in params (OUR count): ", neg)

# --- data types: text cells per typed column -------------------------------
println("\n== data types in raw (text cells per typed column) ==")
for c in vcat(["Date", "Time"], PARAM_NAMES)
    txt = count(v -> v isa AbstractString && !is_placeholder(v), raw[!, c])
    ph  = count(v -> v isa AbstractString && is_placeholder(v), raw[!, c])
    num = count(v -> v isa Real, raw[!, c])
    println(rpad(c, 34), " text=", txt, " placeholders=", ph, " numeric=", num)
end