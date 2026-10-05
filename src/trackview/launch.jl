# The public entry point: build, self-test, then serve or export.

"""
    TrackView

The result of [`trackview`](@ref).

Stable fields: `figure` and `axis` (the Makie `Figure` and `Axis3`), `health`
(`(; passed, checks, failures)` of the control self-test), `schema` (the scene's
schema version), `url` (where it is served, or `nothing`), `html` (the exported
file, or `nothing`), `versions` (Julia, WGLMakie and Bonito versions) and `server`
(the Ship of Tools `BrowserView` or the Bonito server behind `url`, or `nothing`).

`controls` is the builder's internal state (inspector, ROI, `self_test`, ...) and
may change in any release; do not rely on it. `trackview(scene; output=:none).health`
is the supported way to run the control self-test without serving.

`wait(view)` blocks while a `:server` view is served; `close(view)` stops it.
"""
struct TrackView
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

function Base.show(io::IO, ::MIME"text/plain", view::TrackView)
    checks = view.health.checks
    println(io, "TrackView (", view.schema, ")")
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

Base.show(io::IO, view::TrackView) =
    print(io, "TrackView(", view.schema, ", ", length(view.health.checks), " checks)")

Base.wait(view::TrackView) = view.server isa Bonito.Server ? wait(view.server) : nothing

function Base.close(view::TrackView)
    view.server isa Bonito.Server && close(view.server)
    nothing
end

# The Ship of Tools REPL module, or nothing.
function _repl_module()
    isdefined(Main, :ShipToolsRepl) ? getfield(Main, :ShipToolsRepl) : nothing
end

function _serve_repl(repl, figure, open)
    # Fresh figure on every launch: a re-served WGL figure keeps its browser
    # event route attached to the previous Bonito session. Serve-only is the
    # default because two browser clients resizing one Bonito Figure corrupt
    # Makie's shared layout and move painted controls away from their hitboxes.
    if open
        Base.invokelatest(repl.wglshow, figure)
    elseif hasmethod(repl.wglshow, Tuple{Any}, (:open,))
        Base.invokelatest(repl.wglshow, figure; open=false)
    else
        throw(ArgumentError(
            "trackview(; output=:serve) needs Ship of Tools with " *
            "`wglshow(...; open=false)` (PR #103). Restart after updating Ship of " *
            "Tools, or pass open=true only when exactly one frontend is attached.",
        ))
    end
end

"""
    trackview(scene::AbstractDict; output=:auto, open=false, html=nothing,
              port=9384, link_alpha=identity, link_width=2.0,
              size=(1640, 920), frame_inspector=true,
              azimuth=1.22, elevation=0.34) -> TrackView

Build the interactive space-time view of a scene (a `Dict{String,Any}` in the
`"trackview/1"` schema, see the Track viewer page and
[`SMLMView.TrackViewer.validate_scene`](@ref)), run its control self-test, then
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
  - `:html`: a standalone HTML file at `html`; the path is printed. With
    `html=nothing` the file is `trackview.html` in a fresh folder under the system
    temp directory, which is not deleted when Julia exits. The file grows with the
    voxel count (about 27 MB for 64x64x100).
  - `:none`: build and self-test only; returns the view without raising, even when
    the self-test fails, for tests and callers that serve the figure themselves.
- `open`: open a browser tab from `:serve` (default `false`).
- `link_alpha`: function of a link weight `w` giving its opacity (clamped to
  [0, 1]; a non-finite result throws an `ArgumentError` naming the weight); default
  `identity`, so opacity is exactly `w`. A floor is
  `w -> max(w, 0.15)`; others are `sqrt` or `_ -> 1`.
- `link_width`: a line width, or a function of `w` giving a per-segment width,
  for example `w -> 0.5 + 3w`. A negative or non-finite width, scalar or from the
  function, throws an `ArgumentError` (naming the weight for the function form).
- `port`: first port tried by `:server`; an integer in 1:65535.
- `size`: figure size in pixels.
- `frame_inspector`: add the 2D frame inspector (frame slider, ROI, track pick).
- `azimuth`, `elevation`: initial 3D view angles.

Validation (`validate_scene`) runs first: it converts the scene to its canonical
types and ranges (for example Float64 positions to Float32), hands that canonical
scene to the builder, and throws one `ArgumentError` listing every offending key.
A failing self-test throws before anything is served or written, naming the failed
checks (except for `output=:none`).
"""
function trackview(scene::AbstractDict; kwargs...)
    _trackview(scene, _repl_module(); kwargs...)
end

# `repl` is the Ship of Tools REPL module (or nothing); tests pass a stand-in.
function _trackview(
    scene::AbstractDict,
    repl;
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
    _check_link_width(link_width)
    1 <= port <= 65535 || throw(ArgumentError(
        "port must be in 1:65535, got $port"))
    output === :auto && (output = isnothing(repl) ? :html : :serve)
    output === :serve && isnothing(repl) && throw(ArgumentError(
        "output=:serve needs Main.ShipToolsRepl (a Ship of Tools REPL); " *
        "use :html or :server elsewhere"))

    canonical = validate_scene(scene)
    schema = canonical["schema"]
    figure, axis, controls = build_figure(
        canonical;
        resolution=size,
        azimuth,
        elevation,
        frame_inspector,
        link_alpha,
        link_width,
    )
    health = controls.self_test()
    health.passed || output === :none || error(
        "trackview control self-test failed before $output: " *
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
        @info "trackview served at $url"
    elseif output === :server
        app = Bonito.App(() -> figure)
        server = Bonito.Server(app, "127.0.0.1", Int(port))
        # Bonito moves to the next free port when `port` is taken.
        url = "http://127.0.0.1:$(server.port)/"
        @info "trackview serving at $url\n  target a frontend: " *
              "sot-fe open-url $url --fe <handle>"
    elseif output === :html
        html_path = html === nothing ?
            joinpath(mktempdir(; prefix="trackview_", cleanup=false), "trackview.html") :
            String(html)
        mkpath(dirname(abspath(html_path)))
        Bonito.export_static(html_path, Bonito.App(() -> figure))
        @info "trackview saved $html_path"
    end
    TrackView(figure, axis, controls, health, schema, url, html_path, versions, server)
end

function trackview(path::AbstractString; kwargs...)
    throw(ArgumentError(
        "trackview takes the scene Dict, not a path; load it first, " *
        "for example `trackview(JLD2.load(\"$path\", \"scene\"))`",
    ))
end
