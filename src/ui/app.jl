# =============================================================================
# src/ui/app.jl — App factory, live server, static export (design.md §10)
# =============================================================================

"Build the REPORT Bonito app (fresh data read on every construction)."
function build_app()
    return App() do session
        if Bonito.isroot(session)
            push!(session.global_stylesheets, brutal_css())
        end
        ctx = make_ctx(session)
        return root_view(ctx)
    end
end

"Live server: http://127.0.0.1:<port>"
function run_server(port::Integer = 8080)
    server = Server(build_app(), "127.0.0.1", port)
    @info "REPORT app running at http://127.0.0.1:$(port)"
    return server
end

"Single self-contained HTML (images + evidence embedded as data URIs)."
function export_report(path::AbstractString = joinpath(ROOT, "report", "index.html"))
    mkpath(dirname(path))
    export_static(path, build_app())
    @info "Report written" path bytes = filesize(path)
    return path
end