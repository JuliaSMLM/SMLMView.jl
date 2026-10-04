using Test
using SMLMView
using SMLMView: SpaceTime, SpacetimeView
using WGLMakie
using Downloads

const Makie = WGLMakie.Makie

# Stand-ins for the Ship of Tools REPL module (never defined in Main of a shared kernel).
module StubRepl
struct BrowserView
    url::String
    open::Bool
end
wglshow(figure; open=true) = BrowserView("http://stub.invalid:1/", open)
end
module StubReplOld
struct BrowserView
    url::String
end
wglshow(figure) = BrowserView("http://stub.invalid:2/")
end

example(; kwargs...) = SpaceTime.example_scene(; kwargs...)
build(scene; kwargs...) = spacetime(scene; output=:none, kwargs...)
luminance(color) = Makie.Colors.Gray(Makie.to_color(color)).val

@testset "SpaceTime" begin
    @testset "truth, colour matches and links" begin
        view = build(example())
        @test view isa SpacetimeView
        @test view.health.passed
        @test isempty(view.health.failures)
        @test all(values(view.health.checks))
        @test Set(keys(view.health.checks)) == Set([
            :reset_camera, :top_view, :frame_selection, :highlight_toggle,
            :track_id_toggle, :trajectory_source_toggle, :trajectory_source_2d_sync,
            :trajectory_source_3d_sync, :trajectory_source_hitbox, :root_canvas_route,
            :roi_changes, :roi_3d_sync, :frame_dots_3d_sync, :links_count_in_bounds,
            :links_alpha, :links_width, :links_toggle, :links_found_source_only,
            :matched_trajectory_colors, :found_trajectory_colors_unique,
        ])
        @test view.schema == "spacetime/1"
        @test isnothing(view.url) && isnothing(view.html)
        @test view.controls.inspector.has_ground_truth
        @test view.versions.julia == VERSION
        @test occursin("20 checks passed", sprint(show, MIME("text/plain"), view))
        @test occursin("SpacetimeView", sprint(show, view))
    end

    @testset "no truth" begin
        view = build(example(; truth=false))
        @test view.health.passed
        @test isnothing(view.controls.inspector.source_toggle_box)
        @test !view.controls.inspector.has_ground_truth
        @test !any(startswith("trajectory_source")(string(k)) for k in keys(view.health.checks))
        @test !haskey(view.health.checks, :matched_trajectory_colors)
        @test all(get(view.health.checks, k, false) for k in
                  (:links_count_in_bounds, :links_alpha, :links_width, :links_toggle))
        @test !haskey(view.health.checks, :links_found_source_only)
    end

    @testset "dimers and frame_inspector=false" begin
        view = build(example(; dimers=true))
        @test view.health.passed
        @test !isempty(view.controls.dimer_plots)
        @test occursin("1 reciprocal dimer episode (D1)", view.controls.legend_text[])
        @test isempty(build(example()).controls.dimer_plots)
        @test !occursin("dimer", build(example()).controls.legend_text[])
        bare = build(example(; dimers=true); frame_inspector=false)
        @test bare.health.passed
        @test isnothing(bare.controls.inspector)
        @test Set(keys(bare.health.checks)) ==
              Set([:reset_camera, :top_view, :links_count_in_bounds, :links_alpha,
                   :links_width, :links_toggle, :matched_trajectory_colors,
                   :found_trajectory_colors_unique])
    end

    @testset "labels" begin
        scene = example()
        view = build(scene)
        @test view.axis.title[] == "example scene"
        delete!(scene, "title")
        view = build(scene)
        @test view.axis.title[] == "Raw intensity and trajectories"
        inspector = view.controls.inspector
        legend = view.controls.legend_text[]
        @test occursin("3 trajectories, example found (example)", legend)
        @test occursin("photons", legend)
        @test !occursin(r"latent|molecul|Cell9"i, legend)
        @test occursin("example found: ", inspector.frame_axis.title[])
        @test !occursin("latent", inspector.frame_axis.title[])
        @test occursin(" points", inspector.frame_axis.title[])
        inspector.selected_track[] = 1
        @test occursin("T1", inspector.selected_track_text[])
        @test occursin("matched GT id 101", inspector.selected_track_text[])
        inspector.selected_track[] = 3
        @test occursin("unmatched", inspector.selected_track_text[])
        inspector.toggle_trajectory_source()
        inspector.selected_track[] = 1
        @test occursin("matched found id 1", inspector.selected_track_text[])
        @test occursin("example truth", inspector.frame_axis.title[])
        scene["raw_intensity_unit"] = "counts"
        legend = build(scene).controls.legend_text[]
        @test occursin("counts", legend) && !occursin("photons", legend)
    end

    @testset "schema declaration and validation" begin
        scene = example()
        @test SpaceTime.scene_schema(scene) == "spacetime/1"
        delete!(scene, "schema")
        SpaceTime.UNDECLARED_NOTED[] = false
        @test_logs (:info, r"schema") SpaceTime.scene_schema(scene)
        @test_logs SpaceTime.scene_schema(scene)         # once per session
        @test build(scene).schema == "spacetime/1"
        scene["schema"] = "spacetime/2"
        err = try; build(scene); nothing; catch e; e; end
        @test err isa ArgumentError
        @test occursin("spacetime/2", err.msg) && occursin("spacetime/1", err.msg)

        for kw in ((;), (; truth=false), (; links=false), (; dimers=true))
            @test SpaceTime.validate_scene(example(; kw...)) === nothing
        end

        scene = example(); delete!(scene, "nx")
        err = try; build(scene); nothing; catch e; e; end
        @test err isa ArgumentError && occursin("missing key nx", err.msg)

        scene = example()
        scene["raw_scaled_intensity"] = scene["raw_scaled_intensity"][1:end-1]
        scene["track_y"][1] = scene["track_y"][1][1:end-1]
        scene["track_colors"] = scene["track_colors"][1:2, :]
        scene["pixel_size"] = -1.0
        scene["links"]["w"] = scene["links"]["w"][1:2]
        scene["ground_truth_tracks"]["track_x"] = scene["ground_truth_tracks"]["track_x"][1:2]
        err = try; SpaceTime.validate_scene(scene); nothing; catch e; e; end
        @test err isa ArgumentError
        for text in ("raw_scaled_intensity", "track_x, track_y, track_z", "track_colors",
                     "pixel_size", "links: arrays", "ground_truth_tracks: track_x")
            @test occursin(text, err.msg)
        end

        scene = example(; truth=false)
        scene["trajectory_color_matches"] = [(; truth_id=1, estimate_id=1)]
        err = try; SpaceTime.validate_scene(scene); nothing; catch e; e; end
        @test err isa ArgumentError
        @test occursin("trajectory_color_matches needs ground_truth_tracks", err.msg)
        @test occursin("trajectory_color_match_gate", err.msg)

        scene = example(; dimers=true)
        scene["dimer_labels"] = String[]
        err = try; SpaceTime.validate_scene(scene); nothing; catch e; e; end
        @test err isa ArgumentError && occursin("dimer", err.msg)

        @test_throws ArgumentError spacetime("scene.jld2")
        @test_throws ArgumentError spacetime(example(); output=:bogus)
        @test_throws ArgumentError spacetime(example(); output=:none, link_alpha=3)
        @test_throws ArgumentError spacetime(example(); output=:none, link_width=-1)
    end

    @testset "failed self-test blocks the output" begin
        scene = example()
        scene["track_colors"][1, :] = Float32[0.5, 0.5, 0.5]    # no longer its truth colour
        view = build(scene)
        @test !view.health.passed
        @test :matched_trajectory_colors in Symbol.(view.health.failures)
        @test occursin("FAILED", sprint(show, MIME("text/plain"), view))
        path = joinpath(mktempdir(), "never.html")
        err = try; spacetime(scene; output=:html, html=path); nothing; catch e; e; end
        @test err isa ErrorException
        @test occursin("matched_trajectory_colors", err.msg)
        @test !isfile(path)
    end

    @testset "links mapping" begin
        links_of(view) = view.controls.links_plot
        drawn_w = Float32[0.3, 0.5]                     # the on_map = false links
        plot = links_of(build(example()))
        @test [c.alpha for c in plot.color[]][1:2:end] ≈ drawn_w
        @test plot.linewidth[] == 2.0
        plot = links_of(build(example(); link_alpha=sqrt))
        @test [c.alpha for c in plot.color[]][1:2:end] ≈ sqrt.(drawn_w)
        floor_view = build(example(); link_alpha=w -> max(w, 0.4))
        @test floor_view.health.passed
        @test [c.alpha for c in links_of(floor_view).color[]][1:2:end] ≈ Float32[0.4, 0.5]
        over = build(example(); link_alpha=w -> 5w)
        @test all(c -> c.alpha == 1, links_of(over).color[])
        view = build(example(); link_alpha=_ -> 1, link_width=w -> 0.5 + 3w)
        @test view.health.passed
        @test all(c -> c.alpha == 1, links_of(view).color[])
        @test links_of(view).linewidth[] ≈ Float32[0.5 + 3 * 0.3, 0.5 + 3 * 0.3,
                                                   0.5 + 3 * 0.5, 0.5 + 3 * 0.5]
        view = build(example(); link_width=3)
        @test view.health.passed && links_of(view).linewidth[] == 3
        # no links: no layer, no link checks
        view = build(example(; links=false))
        @test isnothing(view.controls.links_plot)
        @test !haskey(view.health.checks, :links_width)
    end

    @testset "output routes" begin
        scene = example()
        mktempdir() do dir
            path = joinpath(dir, "sub", "scene.html")
            view = spacetime(scene; output=:html, html=path)
            @test view.html == path && isfile(path) && filesize(path) > 10_000
            @test occursin("<html", lowercase(first(read(path, String), 2000)))
            @test isnothing(view.url)
        end
        view = spacetime(scene; output=:html)           # fresh temporary directory
        @test isfile(view.html) && endswith(view.html, ".html")

        # :server on a free port answers GET / with 200, then closes
        function get_status(url)
            status = 0
            for _ in 1:50
                status = try
                    Downloads.request(url; throw=false, timeout=5).status
                catch
                    0
                end
                status == 200 && break
                sleep(0.1)
            end
            status
        end
        view = nothing
        for attempt in 1:20
            port = rand(30000:45000)
            try
                view = spacetime(scene; output=:server, port)
                break
            catch error
                attempt == 20 && rethrow()
            end
        end
        held = view
        try
            @test view.url == "http://127.0.0.1:$(view.server.port)/"
            @test get_status(view.url) == 200

            # a taken port: Bonito moves on, and the url names the port actually used
            taken = held.server.port
            second = spacetime(scene; output=:server, port=taken)
            try
                @test second.server.port != taken
                @test second.url == "http://127.0.0.1:$(second.server.port)/"
                @test get_status(second.url) == 200
            finally
                close(second)
            end
        finally
            close(held)
        end
    end

    @testset "serve through Ship of Tools" begin
        scene = example()
        try
            SpaceTime.REPL_MODULE[] = StubRepl
            view = spacetime(scene)                                   # :auto picks :serve
            @test view.url == "http://stub.invalid:1/"
            @test view.server isa StubRepl.BrowserView && !view.server.open
            @test isnothing(view.html)
            view = spacetime(scene; output=:serve, open=true)
            @test view.server.open
            SpaceTime.REPL_MODULE[] = StubReplOld                     # no `open` field
            err = try; spacetime(scene); nothing; catch e; e; end
            @test err isa ArgumentError && occursin("open=false", err.msg)
            @test spacetime(scene; open=true).url == "http://stub.invalid:2/"
            # a failing self-test never reaches wglshow
            bad = example(); bad["track_colors"][1, :] = Float32[0.5, 0.5, 0.5]
            @test_throws ErrorException spacetime(bad; output=:serve)
        finally
            SpaceTime.REPL_MODULE[] = nothing
        end
        if !isdefined(Main, :ShipToolsRepl)
            @test_throws ArgumentError spacetime(scene; output=:serve)
            view = spacetime(scene)                                   # :auto picks :html
            @test !isnothing(view.html) && isnothing(view.url)
        end
    end

    @testset "global theme and dark figure" begin
        before = Makie.current_default_theme()[:backgroundcolor][]
        view = build(example())
        @test Makie.current_default_theme()[:backgroundcolor][] == before
        @test luminance(before) > 0.5                  # the session default stays light
        @test luminance(view.axis.titlecolor[]) > 0.3  # the figure is dark: light text
        @test luminance(view.figure.scene.backgroundcolor[]) < 0.2
    end
end
