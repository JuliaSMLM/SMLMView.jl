# The public entry point: build, self-test, then serve or export.

"""
    SpacetimeView

The result of [`spacetime`](@ref).

Fields: `figure` and `axis` (the Makie `Figure` and `Axis3`), `controls` (the
builder's state NamedTuple: `inspector`, `roi_bounds`, `trajectory_source`,
`self_test`, ...), `health` (`(; passed, checks, failures)` of the control
self-test), `schema` (the scene's schema version), `url` (where it is served, or
`nothing`), `html` (the exported file, or `nothing`), `versions` (Julia, WGLMakie
and Bonito versions) and `server` (the Ship of Tools `BrowserView` or the Bonito
server behind `url`, or `nothing`).

`wait(view)` blocks while a `:server` view is served; `close(view)` stops it.
"""
struct SpacetimeView
    figure::Makie.Figure
    axis::Makie.Axis3
    controls::NamedTuple
    health::NamedTuple
    schema::String
    url::Union{Nothing,String}
    html::Union{Nothing,String}
    versions::NamedTuple
    server::Any
end

function Base.show(io::IO, ::MIME"text/plain", view::SpacetimeView)
    checks = view.health.checks
    println(io, "SpacetimeView (", view.schema, ")")
    if view.health.passed
        println(io, "  control self-test: ", length(checks), " checks passed")
    else
        println(io, "  control self-test FAILED: ", join(view.health.failures, ", "))
    end
    isnothing(view.url) || println(io, "  url:  ", view.url)
    isnothing(view.html) || println(io, "  html: ", view.html)
    isnothing(view.url) && isnothing(view.html) && println(io, "  not served or exported")
    print(io, "  julia ", view.versions.julia, ", WGLMakie ", view.versions.wglmakie,
        ", Bonito ", view.versions.bonito)
end

Base.show(io::IO, view::SpacetimeView) =
    print(io, "SpacetimeView(", view.schema, ", ", length(view.health.checks), " checks)")

Base.wait(view::SpacetimeView) = view.server isa Bonito.Server ? wait(view.server) : nothing

function Base.close(view::SpacetimeView)
    view.server isa Bonito.Server && close(view.server)
    nothing
end

# The Ship of Tools REPL module, or nothing. `REPL_MODULE` lets tests stand in a stub.
const REPL_MODULE = Ref{Union{Nothing,Module}}(nothing)

function _repl_module()
    isnothing(REPL_MODULE[]) || return REPL_MODULE[]
    isdefined(Main, :ShipToolsRepl) ? getfield(Main, :ShipToolsRepl) : nothing
end

function _serve_repl(repl, figure, open)
    # Fresh figure on every launch: a re-served WGL figure keeps its browser
    # event route attached to the previous Bonito session. Serve-only is the
    # default because two browser clients resizing one Bonito Figure corrupt
    # Makie's shared layout and move painted controls away from their hitboxes.
    if open
        Base.invokelatest(repl.wglshow, figure)
    elseif :open in fieldnames(repl.BrowserView)
        Base.invokelatest(() -> repl.wglshow(figure; open=false))
    else
        throw(ArgumentError(
            "spacetime(; output=:serve) needs Ship of Tools with " *
            "`wglshow(...; open=false)` (PR #103). Restart after updating Ship of " *
            "Tools, or pass open=true only when exactly one frontend is attached.",
        ))
    end
end

"""
    spacetime(scene::AbstractDict; output=:auto, open=false, html=nothing,
              port=9384, link_alpha=identity, link_width=2.0,
              size=(1640, 920), frame_inspector=true,
              azimuth=1.22, elevation=0.34) -> SpacetimeView

Build the interactive space-time view of a scene (a `Dict{String,Any}` in the
`"spacetime/1"` schema, see the Space-time viewer page and
[`SMLMView.SpaceTime.validate_scene`](@ref)), run its control self-test, then
serve or export it. The scene is a Dict, not a path: load it first, for example
with `JLD2.load(path, "scene")`. A fresh figure is built on every call.

# Keywords
- `output`: where the view goes.
  - `:auto`: `:serve` when `Main.ShipToolsRepl` is defined, else `:html`.
  - `:serve`: `Main.ShipToolsRepl.wglshow(figure; open)`. With `open=false` (the
    default) the figure is served without opening a tab; target one frontend
    afterwards with `sot-fe open-url <url> --fe <handle>`. Two clients on one figure
    corrupt its layout.
  - `:server`: a standalone Bonito server on `127.0.0.1:port` (the next free port
    when `port` is taken; `url` names the port actually used) for a script's own
    process; prints the URL and the `sot-fe open-url` line. `wait(view)` keeps the
    process serving; `close(view)` stops it. Never chosen by `:auto`.
  - `:html`: a standalone HTML file at `html` (a fresh temporary directory when
    `nothing`); the path is printed. The file grows with the voxel count (about
    27 MB for 64x64x100).
  - `:none`: build and self-test only; returns the view without raising, even when
    the self-test fails, for tests and callers that serve the figure themselves.
- `open`: open a browser tab from `:serve` (default `false`).
- `link_alpha`: function of a link weight `w` giving its opacity (clamped to
  [0, 1]); default `identity`, so opacity is exactly `w`. A floor is
  `w -> max(w, 0.15)`; others are `sqrt` or `_ -> 1`.
- `link_width`: a line width, or a function of `w` giving a per-segment width,
  for example `w -> 0.5 + 3w`.
- `size`: figure size in pixels.
- `frame_inspector`: add the 2D frame inspector (frame slider, ROI, track pick).
- `azimuth`, `elevation`: initial 3D view angles.

Validation (`validate_scene`) runs first and throws one `ArgumentError` listing
every problem. A failing self-test throws before anything is served or written,
naming the failed checks (except for `output=:none`).
"""
function spacetime(
    scene::AbstractDict;
    output::Symbol=:auto,
    open::Bool=false,
    html=nothing,
    port::Integer=9384,
    link_alpha=identity,
    link_width=2.0,
    size=(1640, 920),
    frame_inspector::Bool=true,
    azimuth=1.22,
    elevation=0.34,
)
    output in (:auto, :serve, :server, :html, :none) || throw(ArgumentError(
        "output must be :auto, :serve, :server, :html or :none, got :$output"))
    applicable(link_alpha, 0.5f0) || throw(ArgumentError(
        "link_alpha must be a function of the link weight"))
    link_width isa Real ? link_width >= 0 || throw(ArgumentError(
        "link_width must be >= 0")) : applicable(link_width, 0.5f0) ||
        throw(ArgumentError("link_width must be a number or a function of the link weight"))
    repl = _repl_module()
    output === :auto && (output = isnothing(repl) ? :html : :serve)
    output === :serve && isnothing(repl) && throw(ArgumentError(
        "output=:serve needs Main.ShipToolsRepl (a Ship of Tools REPL); " *
        "use :html or :server elsewhere"))

    schema = scene_schema(scene)
    validate_scene(scene)
    figure, axis, controls = build_figure(
        scene;
        resolution=size,
        azimuth,
        elevation,
        frame_inspector,
        link_alpha,
        link_width,
    )
    health = controls.self_test()
    health.passed || output === :none || error(
        "spacetime control self-test failed before $output: " *
        join(sort(health.failures), ", "),
    )
    versions = (;
        julia=VERSION,
        wglmakie=pkgversion(WGLMakie),
        bonito=pkgversion(Bonito),
    )

    url = nothing
    html_path = nothing
    server = nothing
    if output === :serve
        server = _serve_repl(repl, figure, open)
        url = string(server.url)
        println("spacetime served at ", url)
    elseif output === :server
        app = Bonito.App(() -> figure)
        server = Bonito.Server(app, "127.0.0.1", port)
        # Bonito moves to the next free port when `port` is taken.
        url = "http://127.0.0.1:$(server.port)/"
        println("spacetime serving at ", url)
        println("  target a frontend: sot-fe open-url ", url, " --fe <handle>")
    elseif output === :html
        html_path = html === nothing ? joinpath(mktempdir(), "spacetime.html") :
            String(html)
        mkpath(dirname(abspath(html_path)))
        Bonito.export_static(html_path, Bonito.App(() -> figure))
        println("spacetime saved ", html_path)
    end
    SpacetimeView(figure, axis, controls, health, schema, url, html_path, versions, server)
end

function spacetime(path::AbstractString; kwargs...)
    throw(ArgumentError(
        "spacetime takes the scene Dict, not a path; load it first, " *
        "for example `spacetime(JLD2.load(\"$path\", \"scene\"))`",
    ))
end
