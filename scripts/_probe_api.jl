using XLSX
println("readdata methods:")
for m in methods(XLSX.readdata); println("  ", m); end
println("\nreadtable methods:")
for m in methods(XLSX.readtable); println("  ", m); end
println("\nexports with row/data/get:")
println(filter(n -> occursin(r"row|data|get", n), String.(names(XLSX))))
