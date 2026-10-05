using Test
using SMLMView
using SMLMView: Spacetime, SpacetimeView
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

example(; kwargs...) = Spacetime.example_scene(; kwargs...)
include("long/utils/mutations.jl")      # shared with the Long group
build(scene; kwargs...) = spacetime(scene; output=:none, kwargs...)
# The launcher with a stand-in Ship of Tools REPL module (or nothing).
launch(scene, repl; kwargs...) = Spacetime._spacetime(scene, repl; kwargs...)
luminance(color) = Makie.Colors.Gray(Makie.to_color(color)).val
const OffsetArrays = Makie.OffsetArrays
problems(scene) = try
    Spacetime.validate_scene(scene); ""
catch e
    e isa ArgumentError ? e.msg : rethrow()
end

# One built view of the default scene, shared by the tests that only read it.
const VIEW0 = build(example())

@testset "Spacetime" begin
    @testset "truth, colour matches and links" begin
        view = VIEW0
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
        @test !any(startswith("trajectory_source")(string(k))
                   for k in keys(view.health.checks))
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
        @test isempty(VIEW0.controls.dimer_plots)
        @test !occursin("dimer", VIEW0.controls.legend_text[])
        bare = build(example(; dimers=true); frame_inspector=false)
        @test bare.health.passed
        @test isnothing(bare.controls.inspector)
        @test Set(keys(bare.health.checks)) ==
              Set([:reset_camera, :top_view, :links_count_in_bounds, :links_alpha,
                   :links_width, :links_toggle, :matched_trajectory_colors,
                   :found_trajectory_colors_unique])
    end

    @testset "labels" begin
        @test VIEW0.axis.title[] == "example scene"
        @test occursin("photons", VIEW0.controls.legend_text[])
        scene = example()
        delete!(scene, "title")
        scene["raw_intensity_unit"] = "counts"
        view = build(scene)
        @test view.axis.title[] == "Raw intensity and trajectories"
        inspector = view.controls.inspector
        legend = view.controls.legend_text[]
        @test occursin("3 trajectories, example found (example)", legend)
        @test occursin("counts", legend) && !occursin("photons", legend)
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
    end

    @testset "schema declaration" begin
        scene = example()
        @test Spacetime.scene_schema(scene) == "spacetime/1"
        delete!(scene, "schema")
        @test_logs (:info, r"schema") Spacetime.scene_schema(scene)
        @test Spacetime.validate_scene(scene)["schema"] == "spacetime/1"
        for declared in ("spacetime/2", nothing, Symbol("spacetime/1"), 1, "")
            scene["schema"] = declared
            err = try; build(scene); nothing; catch e; e; end
            @test err isa ArgumentError
            @test occursin("unsupported spacetime schema", err.msg)
            @test occursin("spacetime/1", err.msg)
        end
        @test Spacetime.validate_scene(example())["schema"] == "spacetime/1"
        undeclared = example(); delete!(undeclared, "schema")
        @test Spacetime.validate_scene(undeclared)["schema"] == "spacetime/1"
    end

    @testset "validation" begin
        for kw in ((;), (; truth=false), (; links=false), (; dimers=true))
            @test Spacetime.validate_scene(example(; kw...)) isa Dict{String,Any}
        end
        # the canonical scene is new, canonical-typed arrays are reused, the input is kept
        scene = example()
        scene["pixel_size"] = 0.1f0
        scene["raw_xyz"] = Float64.(scene["raw_xyz"])
        scene["track_x"] = [Float64.(path) for path in scene["track_x"]]
        before = deepcopy(scene)
        canonical = Spacetime.validate_scene(scene)
        @test scene == before
        @test canonical !== scene
        @test canonical["pixel_size"] isa Float64
        @test canonical["raw_xyz"] isa Matrix{Float32}
        @test canonical["track_x"] isa Vector{Vector{Float32}}
        @test canonical["raw_scaled_intensity"] === scene["raw_scaled_intensity"]
        @test canonical["links"] !== scene["links"]
        @test canonical["links"]["w"] === scene["links"]["w"]
        @test canonical["trajectory_color_matches"] isa
              Vector{@NamedTuple{truth_id::Int, estimate_id::Int}}
        @test build(scene).health.passed

        scene = example(); delete!(scene, "nx")
        err = try; build(scene); nothing; catch e; e; end
        @test err isa ArgumentError && occursin("missing key nx", err.msg)

        scene = example()
        scene["raw_scaled_intensity"] = scene["raw_scaled_intensity"][1:end-1]
        scene["track_y"][1] = scene["track_y"][1][1:end-1]
        scene["track_colors"] = scene["track_colors"][1:2, :]
        scene["pixel_size"] = -1.0
        scene["links"]["w"] = scene["links"]["w"][1:2]
        truth = scene["ground_truth_tracks"]
        truth["track_x"] = truth["track_x"][1:2]
        message = problems(scene)
        for text in ("raw_scaled_intensity", "track_x, track_y, track_z", "track_colors",
                     "pixel_size", "links: arrays", "ground_truth_tracks: track_x")
            @test occursin(text, message)
        end

        scene = example(; truth=false)
        scene["trajectory_color_matches"] = [(; truth_id=1, estimate_id=1)]
        message = problems(scene)
        @test occursin("trajectory_color_matches needs ground_truth_tracks", message)
        @test occursin("trajectory_color_match_gate", message)

        scene = example(; dimers=true)
        scene["dimer_labels"] = String[]
        @test occursin("dimer", problems(scene))
        scene = example(; dimers=true)
        scene["dimer_track_indices"] = [1.5 2.0]           # was an InexactError
        @test occursin("dimer_track_indices", problems(scene))
        scene = example(; dimers=true)
        delete!(scene, "dimer_track_ids")                   # required with an episode
        @test occursin("required when the set has dimer episodes", problems(scene))
        scene = example(; dimers=true)
        scene["dimer_x"][1] = scene["dimer_x"][1][1:2]
        @test occursin("dimer episode 1", problems(scene))

        # values the builder exponentiates or divides by
        scene = example(); scene["raw_scaled_intensity"][1] = -0.1f0
        @test occursin("raw_scaled_intensity", problems(scene))
        scene = example(); scene["raw_scaled_intensity"][1] = NaN32
        @test occursin("raw_scaled_intensity", problems(scene))
        scene = example(); scene["track_colors"][1, 1] = 2f0
        @test occursin("track_colors", problems(scene))
        scene = example(); scene["raw_alpha_gamma"] = 0
        @test occursin("raw_alpha_gamma", problems(scene))

        # integers the builder cannot hold as Int, derived extents, link weights
        for key in ("track_ids", "matched_other_ids")
            for bad in (typemax(UInt64), big(2)^100)
                scene = example(; truth=false)
                scene[key] = [bad, 2, 3]
                @test occursin(key, problems(scene))
            end
        end
        scene = example(; dimers=true)
        scene["dimer_track_ids"] = reshape([typemax(UInt64), 2], 1, 2)
        @test occursin("dimer_track_ids", problems(scene))
        for size in (1e-100, 1e100)
            scene = example(); scene["pixel_size"] = size
            @test occursin("pixel_size", problems(scene))
        end
        scene = example(); scene["links"]["w"][2] = -0.3f0
        @test occursin("links: w", problems(scene))
        @test_throws ArgumentError build(scene; link_alpha=sqrt)
        scene = example(); scene["raw_quantile"] = 2
        scene["raw_normalization_quantile"] = 2
        @test occursin("raw_normalization_quantile", problems(scene))
        scene = example(); scene["track_ids"] = [1, 1, 2]
        @test occursin("track_ids must be unique", problems(scene))

        @test_throws ArgumentError spacetime("scene.jld2")
        @test_throws ArgumentError spacetime(example(); output=:bogus)
        @test_throws ArgumentError spacetime(example(); output=:none, link_alpha=3)
        @test_throws ArgumentError spacetime(example(); output=:none, link_width=-1)
        @test_throws ArgumentError spacetime(example(); output=:none, link_width="wide")
    end

    @testset "track metadata" begin
        for (key, bad) in (("matched_other_ids", ["a", "b", "c"]),
                           ("matched_other_ids", [1, 2]),
                           ("track_ids", ["a", "b", "c"]),
                           ("track_labels", [1, 2, 3]),
                           ("track_labels", ["a"]))
            for set in (:found, :truth)
                scene = example()
                target = set === :found ? scene : scene["ground_truth_tracks"]
                target[key] = bad
                @test occursin(key, problems(scene))
            end
        end
        # a valid scene: selecting every track in both sets cannot throw
        inspector = VIEW0.controls.inspector
        for source in (:found, :ground_truth)
            inspector.trajectory_source[] === source || inspector.toggle_trajectory_source()
            for track in 0:3
                inspector.selected_track[] = track
                @test inspector.selected_track_text[] isa String
            end
        end
        inspector.toggle_trajectory_source()        # back to found, nothing selected
        inspector.selected_track[] = 0
    end

    @testset "default track ids" begin
        # no track_ids in either set: ids are 1:n_tracks, so the matches are 1 and 2
        scene = example()
        delete!(scene, "track_ids")
        delete!(scene["ground_truth_tracks"], "track_ids")
        scene["trajectory_color_matches"] = [(; truth_id=1, estimate_id=1),
                                             (; truth_id=2, estimate_id=2)]
        view = build(scene)
        @test view.health.passed
        @test view.health.checks[:matched_trajectory_colors]
        # ids in the truth set only
        scene = example()
        delete!(scene, "track_ids")
        scene["trajectory_color_matches"] = [(; truth_id=101, estimate_id=1)]
        @test build(scene).health.passed
        # an id the set does not have is rejected before the build
        scene["trajectory_color_matches"] = [(; truth_id=101, estimate_id=7)]
        @test_throws ArgumentError build(scene)
    end

    @testset "raw render modes and sub-steps" begin
        scene = example()                                         # default "thresholded"
        for key in ("raw_render_mode", "raw_normalization_quantile",
                    "raw_normalization_high")
            delete!(scene, key)
        end
        message = try; Spacetime.validate_scene(scene); ""; catch e; e.msg; end
        @test occursin("raw_threshold", message) && occursin("raw_quantile", message)
        scene["raw_threshold"] = 12.3
        scene["raw_quantile"] = 0.98
        view = build(scene)
        @test view.health.passed
        @test occursin("brightest 2.0%", view.controls.legend_text[])
        @test occursin("Threshold 12.3 photons", view.controls.legend_text[])

        # sub_steps = 2: every frame has two model steps, z = (step - 0.5)/2 + 0.5
        base = example()
        scene = example()
        scene["sub_steps"] = 2
        for set in (scene, scene["ground_truth_tracks"])
            fine = [repeat(frames, inner=2) .* 2 .- repeat([1, 0], length(frames))
                    for frames in set["track_fine_frames"]]
            set["track_fine_frames"] = fine
            set["track_z"] = [Float32.((steps .- 0.5) ./ 2 .+ 0.5) for steps in fine]
            for key in ("track_x", "track_y")
                set[key] = [repeat(path, inner=2) for path in set[key]]
            end
        end
        scene["links"] = base["links"]
        view = build(scene)
        @test view.health.passed
        frame_points = view.controls.inspector.frame_track_sets[:found].frame_points
        base_points = VIEW0.controls.inspector.frame_track_sets[:found].frame_points
        @test length.(frame_points) == 2 .* length.(base_points)
        @test extrema(scene["track_z"][1]) == (0.75f0, 10.25f0)
        # the gap between frames 3 and 6 is a gap in steps too (dashed segment)
        @test !isempty(view.controls.track_render_sets[:found].gap_points)
    end

    @testset "failed self-test blocks the output" begin
        scene = example()
        scene["track_colors"][1, :] = Float32[0.5, 0.5, 0.5]    # no longer its truth colour
        view = build(scene)
        @test !view.health.passed
        @test :matched_trajectory_colors in Symbol.(view.health.failures)
        @test occursin("FAILED", sprint(show, MIME("text/plain"), view))
        path = joinpath(mktempdir(), "never.html")
        err = try
            spacetime(scene; output=:html, html=path, frame_inspector=false); nothing
        catch e
            e
        end
        @test err isa ErrorException
        @test occursin("matched_trajectory_colors", err.msg)
        @test !isfile(path)
    end

    @testset "links mapping" begin
        links_of(view) = view.controls.links_plot
        drawn_w = Float32[0.3, 0.5]                     # the on_map = false links
        alphas(view) = [c.alpha for c in links_of(view).color[]][1:2:end]
        plot = links_of(VIEW0)
        @test alphas(VIEW0) ≈ drawn_w
        @test plot.linewidth[] == 2.0
        # sqrt opacity and a per-segment width in one build
        view = build(example(); link_alpha=sqrt, link_width=w -> 0.5 + 3w)
        @test view.health.passed
        @test alphas(view) ≈ sqrt.(drawn_w)
        expected = Float32[0.5 + 3 * 0.3, 0.5 + 3 * 0.3, 0.5 + 3 * 0.5, 0.5 + 3 * 0.5]
        @test links_of(view).linewidth[] ≈ expected
        floor_view = build(example(); link_alpha=w -> max(w, 0.4), link_width=3)
        @test floor_view.health.passed
        @test alphas(floor_view) ≈ Float32[0.4, 0.5]
        @test links_of(floor_view).linewidth[] == 3
        # the opacity is clamped to [0, 1]
        @test Spacetime._link_alpha(w -> 5w, 0.5) == 1
        @test Spacetime._link_alpha(w -> -w, 0.5) == 0
        # a negative or non-finite width is an ArgumentError: scalar, or function result
        # naming the weight (end to end once, the rest on the helper)
        @test_throws ArgumentError build(example(); link_width=-0.5)
        err = try; Spacetime._link_width(w -> 1 - 4w, 0.3f0); nothing; catch e; e; end
        @test err isa ArgumentError && occursin("link_width(0.3)", err.msg)
        @test_throws ArgumentError Spacetime._link_width(w -> NaN, 0.3f0)
        @test_throws ArgumentError Spacetime._link_width(Inf, 0.3f0)
        # no links: no layer, no link checks
        view = build(example(; links=false))
        @test isnothing(view.controls.links_plot)
        @test !haskey(view.health.checks, :links_width)
    end

    @testset "output routes" begin
        scene = example()
        light(; kwargs...) = (; frame_inspector=false, kwargs...)
        mktempdir() do dir
            path = joinpath(dir, "sub", "scene.html")
            view = spacetime(scene; output=:html, html=path, light()...)
            @test view.html == path && isfile(path) && filesize(path) > 10_000
            @test occursin("<html", lowercase(first(read(path, String), 2000)))
            @test isnothing(view.url)
        end
        # html=nothing: a fresh folder that is not deleted at exit
        view = spacetime(scene; output=:html, light()...)
        @test isfile(view.html) && endswith(view.html, ".html")
        @test startswith(basename(dirname(view.html)), "spacetime_")

        # ports outside 1:65535 are rejected; any Integer type in range serves
        for port in (0, -1, 65536)
            @test_throws ArgumentError spacetime(scene; output=:server, port, light()...)
        end
        for T in (Int32, UInt16)
            view = spacetime(scene; output=:server, port=T(rand(30000:45000)), light()...)
            try
                @test startswith(view.url, "http://127.0.0.1:")
            finally
                close(view)
            end
        end

        # :server answers GET / with 200; Bonito moves on when the port is taken
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
        first_view = spacetime(scene; output=:server, port=rand(30000:45000), light()...)
        try
            @test first_view.url == "http://127.0.0.1:$(first_view.server.port)/"
            @test get_status(first_view.url) == 200
            taken = first_view.server.port
            second = spacetime(scene; output=:server, port=taken, light()...)
            try
                @test second.server.port != taken
                @test second.url == "http://127.0.0.1:$(second.server.port)/"
                @test get_status(second.url) == 200
            finally
                close(second)
            end
        finally
            close(first_view)
        end
    end

    @testset "serve through Ship of Tools" begin
        scene = example()
        light = (; frame_inspector=false)
        view = launch(scene, StubRepl; light...)                  # :auto picks :serve
        @test view.url == "http://stub.invalid:1/"
        @test view.server isa StubRepl.BrowserView && !view.server.open
        @test isnothing(view.html)
        @test launch(scene, StubRepl; output=:serve, open=true, light...).server.open
        # a REPL whose wglshow has no `open` keyword
        err = try; launch(scene, StubReplOld; light...); nothing; catch e; e; end
        @test err isa ArgumentError && occursin("open=false", err.msg)
        old = launch(scene, StubReplOld; open=true, light...)
        @test old.url == "http://stub.invalid:2/"
        # a failing self-test never reaches wglshow
        bad = example(); bad["track_colors"][1, :] = Float32[0.5, 0.5, 0.5]
        @test_throws ErrorException launch(bad, StubRepl; output=:serve, light...)
        # no REPL: :auto picks :html, :serve is an error
        view = launch(scene, nothing; light...)
        @test !isnothing(view.html) && isnothing(view.url)
        @test_throws ArgumentError launch(scene, nothing; output=:serve, light...)
    end

    @testset "global theme and dark figure" begin
        before = Makie.current_default_theme()[:backgroundcolor][]
        view = VIEW0
        @test Makie.current_default_theme()[:backgroundcolor][] == before
        @test luminance(before) > 0.5                  # the session default stays light
        @test luminance(view.axis.titlecolor[]) > 0.3  # the figure is dark: light text
        @test luminance(view.figure.scene.backgroundcolor[]) < 0.2
    end

    @testset "schema problems are collected with the others" begin
        scene = example()
        scene["schema"] = "spacetime/2"
        scene["nx"] = 0
        scene["links"]["w"][2] = -0.5f0
        message = problems(scene)
        @test occursin("unsupported spacetime schema", message)
        @test occursin("nx must be", message)
        @test occursin("links: w must be", message)
        @test occursin("3 problems", message)
        err = try; build(scene); nothing; catch e; e; end
        @test err isa ArgumentError && err.msg == message
    end

    @testset "canonical containers" begin
        # every value of the canonical scene has exactly its table type, on all fixtures
        for scene in (example(), example(; truth=false), example(; links=false),
                      example(; dimers=true), comprehensive_scene())
            @test isempty(canonical_type_violations(Spacetime.validate_scene(scene)))
        end

        # OffsetArrays, views and ranges are copied into one-based arrays, then build
        scene = example()
        original = deepcopy(scene)
        scene["raw_xyz"] = OffsetArrays.OffsetArray(scene["raw_xyz"], 5, 3)
        scene["source_frames"] = OffsetArrays.OffsetVector(scene["source_frames"], -4)
        scene["track_ids"] = OffsetArrays.OffsetVector(scene["track_ids"], 7)
        scene["matched_other_ids"] =
            OffsetArrays.OffsetVector(scene["matched_other_ids"], 2)
        paths = Vector{Any}(scene["track_x"])
        paths[1] = OffsetArrays.OffsetVector(scene["track_x"][1], 3)
        scene["track_x"] = paths
        scene["track_colors"] = Base.view(scene["track_colors"], :, :)
        canonical = Spacetime.validate_scene(scene)
        @test isempty(canonical_type_violations(canonical))
        for key in ("raw_xyz", "source_frames", "track_ids", "matched_other_ids",
                    "track_colors")
            @test canonical[key] == original[key]
            @test axes(canonical[key]) == axes(original[key])
        end
        @test canonical["track_x"][1] == original["track_x"][1]
        @test axes(canonical["track_x"][1]) == axes(original["track_x"][1])
        view = build(scene)
        @test view.health.passed
        @test isempty(pick_every_track(view, "offset arrays"))
        # a range is a Vector{Int} too
        scene = example()
        scene["source_frames"] = 1:10
        @test Spacetime.validate_scene(scene)["source_frames"] isa Vector{Int}
    end

    @testset "the fixtures cover every key of the tables" begin
        fixtures = sweep_fixtures()
        covered = Set(path for fixture in fixtures for path in key_paths(fixture))
        @test isempty(setdiff(table_key_paths(), covered))
        # the comprehensive scene builds with every optional part switched on
        view = build(comprehensive_scene())
        @test view.health.passed
        @test isempty(pick_every_track(view, "comprehensive"))
    end

    @testset "validated scenes build (mutation sweep)" begin
        # Every mutation of every key of both fixtures: validate_scene throws an
        # ArgumentError, or else returns a canonical scene (each value exactly its table
        # type). The Long group builds every accepted mutation and runs its self-test.
        violations = String[]
        accepted = 0
        rejected = 0
        for base in sweep_fixtures()
            for (name, scene) in mutated_scenes(base)
                verdict = validation_outcome(scene)
                if verdict === :rejected
                    rejected += 1
                elseif verdict === :accepted
                    accepted += 1
                else
                    push!(violations, "$name: $verdict")
                end
            end
        end
        isempty(violations) || foreach(println, violations)
        @test isempty(violations)
        @test rejected > 900
        @test accepted > 100
    end
end
