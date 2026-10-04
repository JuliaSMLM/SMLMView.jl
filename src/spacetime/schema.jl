# The scene schema: version declaration, validation and a small example scene.

# Schema version this viewer reads and writes.
const SCHEMA = "spacetime/1"
const SUPPORTED_SCHEMAS = (SCHEMA,)

# One `@info` per session for a scene without the `"schema"` key.
const UNDECLARED_NOTED = Ref(false)

"""
    scene_schema(scene) -> String

The schema version a scene declares with its `"schema"` key. A scene without the
key is read as `"spacetime/1"` (one `@info` per session suggests the exporter add
the key). Any other declared value throws an `ArgumentError` naming the supported
versions.
"""
function scene_schema(scene::AbstractDict)
    declared = get(scene, "schema", nothing)
    if isnothing(declared)
        if !UNDECLARED_NOTED[]
            UNDECLARED_NOTED[] = true
            @info "spacetime scene declares no \"schema\" key; reading it as " *
                  "\"$SCHEMA\". Add \"schema\" => \"$SCHEMA\" to the exporter."
        end
        return SCHEMA
    end
    declared = string(declared)
    declared in SUPPORTED_SCHEMAS || throw(ArgumentError(
        "unsupported spacetime schema \"$declared\"; supported: " *
        join(("\"$version\"" for version in SUPPORTED_SCHEMAS), ", "),
    ))
    declared
end

# Collects problems instead of throwing, so one report lists every one of them.
function _check_scene!(problems, scene)
    need(dict, key, what, ok; prefix="") = begin
        if !haskey(dict, key)
            push!(problems, "missing key $prefix$key ($what)")
            nothing
        elseif !ok(dict[key])
            push!(problems, "$prefix$key must be $what")
            nothing
        else
            dict[key]
        end
    end
    count_ok(value) = value isa Integer && value > 0
    real_vector(value) = value isa AbstractVector{<:Real}
    int_vector(value) = value isa AbstractVector{<:Integer}
    has_match_ids(match) = hasproperty(match, :truth_id) && hasproperty(match, :estimate_id)

    nx = need(scene, "nx", "a positive Integer", count_ok)
    ny = need(scene, "ny", "a positive Integer", count_ok)
    need(scene, "pixel_size", "a positive finite Real",
        value -> value isa Real && isfinite(value) && value > 0)
    need(scene, "sub_steps", "a positive Integer", count_ok)
    source_frames = need(scene, "source_frames", "a non-empty Vector{Int}",
        value -> int_vector(value) && !isempty(value))
    need(scene, "state_source", "a String", value -> value isa AbstractString)

    if get(scene, "raw_render_mode", "thresholded") == "all_voxels"
        for key in ("raw_normalization_quantile", "raw_normalization_high")
            need(scene, key, "a Real (raw_render_mode is \"all_voxels\")",
                value -> value isa Real)
        end
    else
        for key in ("raw_threshold", "raw_quantile")
            need(scene, key, "a Real (raw_render_mode is not \"all_voxels\")",
                value -> value isa Real)
        end
    end

    n_frames = isnothing(source_frames) ? nothing : length(source_frames)
    n_voxels = isnothing(nx) || isnothing(ny) || isnothing(n_frames) ? nothing :
        nx * ny * n_frames
    raw_xyz = need(scene, "raw_xyz", "a Matrix with 3 columns",
        value -> value isa AbstractMatrix{<:Real} && Base.size(value, 2) == 3)
    if !isnothing(raw_xyz) && !isnothing(n_voxels) && Base.size(raw_xyz, 1) != n_voxels
        push!(problems, "raw_xyz has $(Base.size(raw_xyz, 1)) rows; " *
                        "nx*ny*length(source_frames) = $n_voxels")
    end
    intensity = need(scene, "raw_scaled_intensity", "a Vector{<:Real}", real_vector)
    if !isnothing(intensity)
        expected = isnothing(raw_xyz) ? n_voxels : Base.size(raw_xyz, 1)
        isnothing(expected) || length(intensity) == expected || push!(problems,
            "raw_scaled_intensity has length $(length(intensity)); expected $expected " *
            "(one value per raw_xyz row)")
    end

    n_found = _check_track_set!(problems, scene, "")
    found_ids = isnothing(n_found) ? nothing :
        haskey(scene, "track_ids") && int_vector(scene["track_ids"]) ?
        scene["track_ids"] : collect(1:n_found)
    truth_ids = nothing
    if haskey(scene, "ground_truth_tracks")
        truth = scene["ground_truth_tracks"]
        if truth isa AbstractDict
            n_truth = _check_track_set!(problems, truth, "ground_truth_tracks: ")
            truth_ids = isnothing(n_truth) ? nothing :
                haskey(truth, "track_ids") && int_vector(truth["track_ids"]) ?
                truth["track_ids"] : collect(1:n_truth)
        else
            push!(problems, "ground_truth_tracks must be a Dict with the track keys")
        end
    end

    if haskey(scene, "trajectory_color_matches")
        haskey(scene, "ground_truth_tracks") || push!(problems,
            "trajectory_color_matches needs ground_truth_tracks")
        need(scene, "trajectory_color_match_gate", "a Real " *
            "(required with trajectory_color_matches)", value -> value isa Real)
        matches = scene["trajectory_color_matches"]
        if !(matches isa AbstractVector && all(has_match_ids, matches))
            push!(problems, "trajectory_color_matches must be a vector of named " *
                            "tuples with truth_id and estimate_id")
        else
            for match in matches
                isnothing(truth_ids) || match.truth_id in truth_ids || push!(problems,
                    "trajectory_color_matches: truth_id $(match.truth_id) is not a " *
                    "ground_truth_tracks track id")
                isnothing(found_ids) || match.estimate_id in found_ids || push!(problems,
                    "trajectory_color_matches: estimate_id $(match.estimate_id) is " *
                    "not a track id")
            end
        end
    end

    if haskey(scene, "links")
        links = scene["links"]
        if !(links isa AbstractDict)
            push!(problems, "links must be a Dict (x0 y0 z0 x1 y1 z1 w on_map)")
        else
            lengths = Int[]
            for key in ("x0", "y0", "z0", "x1", "y1", "z1", "w")
                value = need(links, key, "a Vector{<:Real}", real_vector; prefix="links: ")
                isnothing(value) || push!(lengths, length(value))
            end
            on_map = need(links, "on_map", "a Vector{Bool}",
                value -> value isa AbstractVector{Bool}; prefix="links: ")
            isnothing(on_map) || push!(lengths, length(on_map))
            length(unique(lengths)) <= 1 || push!(problems,
                "links: arrays x0 y0 z0 x1 y1 z1 w on_map must have the same length")
        end
    end
    problems
end

# Checks one track set (the scene itself, or ground_truth_tracks); returns its
# number of tracks, or nothing when the arrays are not usable.
function _check_track_set!(problems, track_scene, prefix)
    problem(text) = push!(problems, prefix * text)
    paths = Dict{String,Any}()
    for key in ("track_x", "track_y", "track_z", "track_fine_frames")
        if !haskey(track_scene, key)
            problem("missing key $key (a Vector of per-track Vectors)")
            continue
        end
        value = track_scene[key]
        element = key == "track_fine_frames" ? Integer : Real
        if value isa AbstractVector && all(path -> path isa AbstractVector{<:element}, value)
            paths[key] = value
        else
            problem("$key must be a Vector of per-track Vector{<:$element}")
        end
    end
    n_tracks = nothing
    if length(paths) == 4
        counts = unique(length.(values(paths)))
        if length(counts) == 1
            n_tracks = only(counts)
            misaligned = [
                index for index in 1:n_tracks if
                length(unique(length(paths[key][index]) for key in keys(paths))) > 1
            ]
            isempty(misaligned) || problem(
                "track_x, track_y, track_z and track_fine_frames lengths differ " *
                "for track $(join(first(misaligned, 5), ", "))" *
                (length(misaligned) > 5 ? " and $(length(misaligned) - 5) more" : ""),
            )
        else
            problem("track_x, track_y, track_z and track_fine_frames must have " *
                    "one entry per track (lengths $(join(counts, ", ")))")
        end
    end
    if !haskey(track_scene, "track_colors")
        problem("missing key track_colors (an n_tracks x 3 Matrix)")
    elseif !(track_scene["track_colors"] isa AbstractMatrix{<:Real})
        problem("track_colors must be an n_tracks x 3 Matrix{<:Real}")
    elseif !isnothing(n_tracks) && Base.size(track_scene["track_colors"]) != (n_tracks, 3)
        problem("track_colors must be $n_tracks x 3, got " *
                join(Base.size(track_scene["track_colors"]), " x "))
    end
    for key in ("track_ids", "track_labels")
        haskey(track_scene, key) && !isnothing(n_tracks) &&
            length(track_scene[key]) != n_tracks &&
            problem("$key has length $(length(track_scene[key])); expected $n_tracks")
    end
    try
        _dimer_data(track_scene)
    catch error
        error isa ArgumentError || rethrow()
        problem(error.msg)
    end
    n_tracks
end

"""
    validate_scene(scene::AbstractDict) -> nothing

Check a scene against the `"spacetime/1"` schema before the build: the declared
schema version, the required keys and their types and shapes (`nx`, `ny`,
`pixel_size > 0`, `sub_steps`, non-empty `source_frames`, `raw_xyz` rows equal to
`nx*ny*T`, `raw_scaled_intensity` length, aligned track arrays, `track_colors`
n x 3), and the optional parts present (`ground_truth_tracks`,
`trajectory_color_matches` with `ground_truth_tracks` and the gate, `links`,
`dimer_*`). Throws one `ArgumentError` listing every problem; returns `nothing`
when the scene is valid.
"""
function validate_scene(scene::AbstractDict)
    scene_schema(scene)
    problems = _check_scene!(String[], scene)
    isempty(problems) || throw(ArgumentError(
        "invalid spacetime scene ($(length(problems)) problem" *
        (length(problems) == 1 ? "" : "s") * "):\n  " * join(problems, "\n  "),
    ))
    nothing
end

"""
    example_scene(; truth=true, links=true, dimers=false, nx=16, ny=12,
                  pixel_size=0.1, frames=10) -> Dict{String,Any}

A small hand-written scene in the `"spacetime/1"` schema, with no simulation:
three straight found tracks (one with a gap in its frames, one a singleton) over a
bright voxel block. `truth` adds `ground_truth_tracks` with colour matches,
`links` adds alternative links with weights, and `dimers` adds one dimer episode.
The scene declares `"schema" => "spacetime/1"`. It is the example of the docs
page and the test fixture.
"""
function example_scene(;
    truth=true,
    links=true,
    dimers=false,
    nx=16,
    ny=12,
    pixel_size=0.1,
    frames=10,
)
    px = pixel_size
    T = frames
    track_paths = [
        [(0.25 + 0.10f * px * 10, 0.30, f) for f in 1:T],                 # straight, full length
        [(1.20, 0.20 + 0.06f * px * 10, f) for f in (1, 2, 3, 6, 7, 8)],  # gap 3 -> 6
        [(0.80, 0.80, 5)],                                                # singleton
    ]
    function serialize(paths, colors; prefix, name, matched)
        Dict{String,Any}(
            "track_x" => [Float32[p[1] for p in path] for path in paths],
            "track_y" => [Float32[ny * px - p[2] for p in path] for path in paths],
            "track_z" => [Float32[p[3] for p in path] for path in paths],
            "track_fine_frames" => [Int[p[3] for p in path] for path in paths],
            "track_colors" => Float32.(colors),
            "track_ids" => collect(1:length(paths)) .+ (prefix == "M" ? 100 : 0),
            "track_label_prefix" => prefix,
            "display_name" => name,
            "matched_other_ids" => matched,
        )
    end
    colors = [1 0 0; 0 1 0; 0 0 1]
    found = serialize(track_paths, colors; prefix="T", name="example found",
        matched=truth ? [101, 102, 0] : Int[])
    raw_xyz = Matrix{Float32}(undef, ny * nx * T, 3)
    raw_i = fill(0.02f0, ny * nx * T)
    for (k, idx) in enumerate(CartesianIndices((ny, nx, T)))
        row, col, f = Tuple(idx)
        raw_xyz[k, :] .= ((col - 0.5f0) * px, (ny - row + 0.5f0) * px, f)
        3 <= col <= 6 && 4 <= row <= 7 && (raw_i[k] = 0.8f0)              # a bright voxel block
    end
    scene = Dict{String,Any}(
        "schema" => SCHEMA, "title" => "example scene",
        "nx" => nx, "ny" => ny, "pixel_size" => px, "sub_steps" => 1,
        "source_frames" => collect(1:T),
        "state_source" => "example", "raw_render_mode" => "all_voxels",
        "raw_normalization_quantile" => 0.999, "raw_normalization_high" => 100.0,
        "raw_xyz" => raw_xyz, "raw_scaled_intensity" => raw_i,
    )
    merge!(scene, found)
    if truth
        truth_paths = [track_paths[1], track_paths[2], [(0.40, 0.90, f) for f in 2:4]]
        truth_colors = [1 0 0; 0 1 0; 1 1 0]
        scene["ground_truth_tracks"] =
            serialize(truth_paths, truth_colors; prefix="M", name="example truth",
                matched=[1, 2, 0])
        scene["trajectory_color_matches"] =
            [(; truth_id=101, estimate_id=1), (; truth_id=102, estimate_id=2)]
        scene["trajectory_color_match_gate"] = 0.2
    end
    if links
        scene["links"] = Dict{String,Any}(
            "x0" => Float32[0.35, 1.20, 0.30], "y0" => Float32[0.9, 0.7, 0.2],
            "z0" => Float32[1, 2, 4], "x1" => Float32[0.45, 0.80, 2.5],
            "y1" => Float32[0.9, 0.4, 0.2], "z1" => Float32[2, 3, 5],
            "w" => Float32[0.9, 0.3, 0.5], "on_map" => Bool[true, false, false],
        )
    end
    if dimers
        # One episode: the midpoint of found tracks 1 and 2 over their shared frames.
        shared = [1, 2, 3]
        first_x, second_x = found["track_x"][1], found["track_x"][2]
        first_y, second_y = found["track_y"][1], found["track_y"][2]
        second_index = Dict(f => i for (i, f) in enumerate(found["track_fine_frames"][2]))
        scene["dimer_x"] = [Float32[(first_x[f] + second_x[second_index[f]]) / 2 for f in shared]]
        scene["dimer_y"] = [Float32[(first_y[f] + second_y[second_index[f]]) / 2 for f in shared]]
        scene["dimer_z"] = [Float32.(shared)]
        scene["dimer_fine_frames"] = [shared]
        scene["dimer_labels"] = ["D1"]
        scene["dimer_track_indices"] = [1 2]
        scene["dimer_track_ids"] = [1 2]
    end
    scene
end
