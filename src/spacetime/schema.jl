# The scene schema: version declaration, validation and a small example scene.

# Schema version this viewer reads and writes.
const SCHEMA = "spacetime/1"
const SUPPORTED_SCHEMAS = (SCHEMA,)

"""
    scene_schema(scene) -> String

The schema version a scene declares with its `"schema"` key. A scene without the
key is read as `"spacetime/1"` (one `@info` per session suggests the exporter add
the key). A key that is present must be a string equal to a supported version;
anything else, including `nothing`, throws an `ArgumentError` naming the supported
versions.
"""
function scene_schema(scene::AbstractDict)
    if !haskey(scene, "schema")
        @info "spacetime scene declares no \"schema\" key; reading it as " *
              "\"$SCHEMA\". Add \"schema\" => \"$SCHEMA\" to the exporter." maxlog=1
        return SCHEMA
    end
    declared = scene["schema"]
    declared isa AbstractString && declared in SUPPORTED_SCHEMAS || throw(ArgumentError(
        "unsupported spacetime schema $(repr(declared)); supported: " *
        join(("\"$version\"" for version in SUPPORTED_SCHEMAS), ", "),
    ))
    String(declared)
end

# Value predicates of the schema. Everything the builder reads has one.
_is_count(value) = value isa Integer && value > 0
_is_text(value) = value isa AbstractString
_is_finite_real(value) = value isa Real && isfinite(value)
_is_reals(value) = value isa AbstractVector{<:Real} && all(isfinite, value)
_is_ints(value) = value isa AbstractVector{<:Integer}
_is_unit_reals(value) = _is_reals(value) && all(x -> 0 <= x <= 1, value)
_is_unit_matrix(value) = value isa AbstractMatrix{<:Real} && all(x -> 0 <= x <= 1, value)
function _is_int_field(match, name)
    hasproperty(match, name) && getproperty(match, name) isa Integer
end
function _has_match_ids(match)
    _is_int_field(match, :truth_id) && _is_int_field(match, :estimate_id)
end
_paths_of(element) = value -> value isa AbstractVector &&
    all(path -> path isa AbstractVector{<:element} &&
        (element === Integer || all(isfinite, path)), value)

# Looks up `key` in `dict`, pushing a problem when it is missing (if required) or fails
# `ok`; returns the value when it is there and valid, else nothing.
function _need!(problems, dict, key, what, ok; prefix="", required=true)
    if !haskey(dict, key)
        required && push!(problems, "missing key $prefix$key ($what)")
        return nothing
    end
    value = dict[key]
    ok(value) && return value
    push!(problems, "$prefix$key must be $what")
    nothing
end

# Checks one track set (the scene itself, or ground_truth_tracks); returns its number of
# tracks, or nothing when the arrays are not usable.
function _check_track_set!(problems, track_scene, prefix)
    need(key, what, ok; required=true) =
        _need!(problems, track_scene, key, what, ok; prefix, required)
    paths = Dict{String,Any}()
    for key in ("track_x", "track_y", "track_z")
        what = "a Vector of per-track Vector{<:Real} with finite values"
        value = need(key, what, _paths_of(Real))
        isnothing(value) || (paths[key] = value)
    end
    value = need("track_fine_frames", "a Vector of per-track Vector{<:Integer}",
        _paths_of(Integer))
    isnothing(value) || (paths["track_fine_frames"] = value)

    n_tracks = nothing
    if length(paths) == 4
        counts = unique(length.(values(paths)))
        if length(counts) == 1
            n_tracks = only(counts)
            misaligned = [
                index for index in 1:n_tracks if
                length(unique(length(paths[key][index]) for key in keys(paths))) > 1
            ]
            isempty(misaligned) || push!(problems, prefix *
                "track_x, track_y, track_z and track_fine_frames lengths differ " *
                "for track $(join(first(misaligned, 5), ", "))" *
                (length(misaligned) > 5 ? " and $(length(misaligned) - 5) more" : ""))
        else
            push!(problems, prefix * "track_x, track_y, track_z and " *
                "track_fine_frames must have one entry per track (lengths " *
                join(counts, ", ") * ")")
        end
    end
    colors = need("track_colors", "an n_tracks x 3 Matrix{<:Real} with values in [0, 1]",
        _is_unit_matrix)
    if !isnothing(colors) && !isnothing(n_tracks) && size(colors) != (n_tracks, 3)
        push!(problems, prefix * "track_colors must be $n_tracks x 3, got " *
                        join(size(colors), " x "))
    end
    per_track = (
        ("track_ids", "a Vector{<:Integer}", _is_ints),
        ("track_labels", "a Vector of Strings",
            value -> value isa AbstractVector && all(_is_text, value)),
        ("matched_other_ids", "a Vector{<:Integer} (0 = no match)", _is_ints),
    )
    for (key, what, ok) in per_track
        value = need(key, what, ok; required=false)
        isnothing(value) || isnothing(n_tracks) || length(value) == n_tracks ||
            push!(problems, prefix * "$key has length $(length(value)); " *
                            "expected $n_tracks (one per track)")
    end
    for key in ("track_label_prefix", "track_id_description", "display_name")
        need(key, "a String", _is_text; required=false)
    end
    _check_dimers!(problems, track_scene, prefix)
    n_tracks
end

# Dimer episodes of a track set: all five path keys together, aligned per episode; the
# two track pair matrices are required once there is an episode.
function _check_dimers!(problems, track_scene, prefix)
    any(startswith("dimer_"), keys(track_scene)) || return nothing
    need(key, what, ok; required=true) =
        _need!(problems, track_scene, key, what, ok; prefix, required)
    xs = need("dimer_x", "a Vector of per-episode Vector{<:Real} with finite values",
        _paths_of(Real))
    ys = need("dimer_y", "a Vector of per-episode Vector{<:Real} with finite values",
        _paths_of(Real))
    zs = need("dimer_z", "a Vector of per-episode Vector{<:Real} with finite values",
        _paths_of(Real))
    frames = need("dimer_fine_frames", "a Vector of per-episode Vector{<:Integer}",
        _paths_of(Integer))
    labels = need("dimer_labels", "a Vector of Strings",
        value -> value isa AbstractVector && all(_is_text, value))
    arrays = (xs, ys, zs, frames, labels)
    any(isnothing, arrays) && return nothing
    n_episodes = length(xs)
    if any(array -> length(array) != n_episodes, arrays)
        push!(problems, prefix * "dimer_x, dimer_y, dimer_z, dimer_fine_frames and " *
                        "dimer_labels must have one entry per episode")
        return nothing
    end
    bad = [
        episode for episode in 1:n_episodes if
        isempty(xs[episode]) ||
        any(array -> length(array[episode]) != length(xs[episode]), (ys, zs, frames))
    ]
    isempty(bad) || push!(problems, prefix * "dimer episode $(first(bad)) is empty or " *
        "its dimer_x, dimer_y, dimer_z and dimer_fine_frames lengths differ")
    for key in ("dimer_track_indices", "dimer_track_ids")
        what = "an n_episodes x 2 Matrix{<:Integer}"
        value = need(key, what * " (required when the set has dimer episodes)",
            value -> value isa AbstractMatrix{<:Integer}; required=n_episodes > 0)
        isnothing(value) || size(value) == (n_episodes, 2) || push!(problems,
            prefix * "$key must be $n_episodes x 2, got " * join(size(value), " x "))
    end
    nothing
end

# Collects problems instead of throwing, so one report lists every one of them.
function _check_scene!(problems, scene)
    need(key, what, ok; required=true) = _need!(problems, scene, key, what, ok; required)
    nx = need("nx", "a positive Integer", _is_count)
    ny = need("ny", "a positive Integer", _is_count)
    need("pixel_size", "a positive finite Real",
        value -> _is_finite_real(value) && value > 0)
    need("sub_steps", "a positive Integer", _is_count)
    source_frames = need("source_frames", "a non-empty Vector{<:Integer}",
        value -> _is_ints(value) && !isempty(value))
    need("state_source", "a String", _is_text)
    need("title", "a String", _is_text; required=false)
    need("raw_intensity_unit", "a String", _is_text; required=false)
    need("raw_render_mode", "a String", _is_text; required=false)

    if get(scene, "raw_render_mode", "thresholded") == "all_voxels"
        for key in ("raw_normalization_quantile", "raw_normalization_high")
            need(key, "a finite Real (raw_render_mode is \"all_voxels\")",
                _is_finite_real)
        end
    else
        for key in ("raw_threshold", "raw_quantile")
            need(key, "a finite Real (raw_render_mode is not \"all_voxels\")",
                _is_finite_real)
        end
    end
    for key in ("raw_alpha_min", "raw_alpha_max")
        need(key, "a Real in [0, 1]", value -> _is_finite_real(value) && 0 <= value <= 1;
            required=false)
    end
    need("raw_alpha_gamma", "a positive finite Real",
        value -> _is_finite_real(value) && value > 0; required=false)

    n_frames = isnothing(source_frames) ? nothing : length(source_frames)
    n_voxels = isnothing(nx) || isnothing(ny) || isnothing(n_frames) ? nothing :
        nx * ny * n_frames
    raw_xyz = need("raw_xyz", "a Matrix with 3 columns and finite values",
        value -> value isa AbstractMatrix{<:Real} && size(value, 2) == 3 &&
            all(isfinite, value))
    if !isnothing(raw_xyz) && !isnothing(n_voxels) && size(raw_xyz, 1) != n_voxels
        push!(problems, "raw_xyz has $(size(raw_xyz, 1)) rows; " *
                        "nx*ny*length(source_frames) = $n_voxels")
    end
    intensity = need("raw_scaled_intensity",
        "a Vector{<:Real} with finite values in [0, 1]", _is_unit_reals)
    if !isnothing(intensity)
        expected = isnothing(raw_xyz) ? n_voxels : size(raw_xyz, 1)
        isnothing(expected) || length(intensity) == expected || push!(problems,
            "raw_scaled_intensity has length $(length(intensity)); expected $expected " *
            "(one value per raw_xyz row)")
    end

    found_ids = _checked_ids(_check_track_set!(problems, scene, ""), scene)
    truth_ids = nothing
    if haskey(scene, "ground_truth_tracks")
        truth = scene["ground_truth_tracks"]
        if truth isa AbstractDict
            n_truth = _check_track_set!(problems, truth, "ground_truth_tracks: ")
            truth_ids = _checked_ids(n_truth, truth)
        else
            push!(problems, "ground_truth_tracks must be a Dict with the track keys")
        end
    end

    if haskey(scene, "trajectory_color_matches")
        haskey(scene, "ground_truth_tracks") || push!(problems,
            "trajectory_color_matches needs ground_truth_tracks")
        need("trajectory_color_match_gate", "a finite Real " *
            "(required with trajectory_color_matches)", _is_finite_real)
        matches = scene["trajectory_color_matches"]
        if !(matches isa AbstractVector && all(_has_match_ids, matches))
            push!(problems, "trajectory_color_matches must be a vector of named " *
                            "tuples with Integer truth_id and estimate_id")
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
                value = _need!(problems, links, key,
                    "a Vector{<:Real} with finite values", _is_reals; prefix="links: ")
                isnothing(value) || push!(lengths, length(value))
            end
            on_map = _need!(problems, links, "on_map", "a Vector{Bool}",
                value -> value isa AbstractVector{Bool}; prefix="links: ")
            isnothing(on_map) || push!(lengths, length(on_map))
            length(unique(lengths)) <= 1 || push!(problems,
                "links: arrays x0 y0 z0 x1 y1 z1 w on_map must have the same length")
        end
    end
    problems
end

# The ids of a checked track set (its `track_ids`, else 1:n), or nothing when unusable.
function _checked_ids(n_tracks, track_scene)
    isnothing(n_tracks) && return nothing
    ids = get(track_scene, "track_ids", nothing)
    _is_ints(ids) && length(ids) == n_tracks ? ids : collect(1:n_tracks)
end

"""
    validate_scene(scene::AbstractDict) -> String

Check a scene against the `"spacetime/1"` schema before the build: the declared
schema version, every key the viewer reads with its type, shape and range, and the
optional parts present (`ground_truth_tracks`, `trajectory_color_matches` with
`ground_truth_tracks` and the gate, `links`, `dimer_*`). Throws one `ArgumentError`
listing every problem. Returns the schema version (`"spacetime/1"`) when the scene
is valid; a scene it accepts builds and runs the control self-test without throwing.
"""
function validate_scene(scene::AbstractDict)
    schema = scene_schema(scene)
    problems = _check_scene!(String[], scene)
    isempty(problems) || throw(ArgumentError(
        "invalid spacetime scene ($(length(problems)) problem" *
        (length(problems) == 1 ? "" : "s") * "):\n  " * join(problems, "\n  "),
    ))
    schema
end

"""
    example_scene(; truth=true, links=true, dimers=false) -> Dict{String,Any}

A small hand-written scene in the `"spacetime/1"` schema, with no simulation:
three straight found tracks (one with a gap in its frames, one a singleton) over a
bright voxel block. `truth` adds `ground_truth_tracks` with colour matches,
`links` adds alternative links with weights, and `dimers` adds one dimer episode.
The scene declares `"schema" => "spacetime/1"`. It is the example of the docs
page and the test fixture.
"""
function example_scene(; truth=true, links=true, dimers=false)
    nx, ny, px, T = 16, 12, 0.1, 10         # camera size, pixel size (μm), frames
    track_paths = [
        [(0.25 + 0.10f * px * 10, 0.30, f) for f in 1:T],                 # straight
        [(1.20, 0.20 + 0.06f * px * 10, f) for f in (1, 2, 3, 6, 7, 8)],  # gap 3 -> 6
        [(0.80, 0.80, 5)],                                                # singleton
    ]
    function serialize(paths, colors; prefix, name, matched)
        set = Dict{String,Any}(
            "track_x" => [Float32[p[1] for p in path] for path in paths],
            "track_y" => [Float32[ny * px - p[2] for p in path] for path in paths],
            "track_z" => [Float32[p[3] for p in path] for path in paths],
            "track_fine_frames" => [Int[p[3] for p in path] for path in paths],
            "track_colors" => Float32.(colors),
            "track_ids" => collect(1:length(paths)) .+ (prefix == "M" ? 100 : 0),
            "track_label_prefix" => prefix,
            "display_name" => name,
        )
        isnothing(matched) || (set["matched_other_ids"] = matched)
        set
    end
    colors = [1 0 0; 0 1 0; 0 0 1]
    found = serialize(track_paths, colors; prefix="T", name="example found",
        matched=truth ? [101, 102, 0] : nothing)
    raw_xyz = Matrix{Float32}(undef, ny * nx * T, 3)
    raw_i = fill(0.02f0, ny * nx * T)
    for (k, idx) in enumerate(CartesianIndices((ny, nx, T)))
        row, col, f = Tuple(idx)
        raw_xyz[k, :] .= ((col - 0.5f0) * px, (ny - row + 0.5f0) * px, f)
        3 <= col <= 6 && 4 <= row <= 7 && (raw_i[k] = 0.8f0)          # a bright voxel block
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
        middle(first, second) = Float32[
            (first[f] + second[second_index[f]]) / 2 for f in shared
        ]
        scene["dimer_x"] = [middle(first_x, second_x)]
        scene["dimer_y"] = [middle(first_y, second_y)]
        scene["dimer_z"] = [Float32.(shared)]
        scene["dimer_fine_frames"] = [shared]
        scene["dimer_labels"] = ["D1"]
        scene["dimer_track_indices"] = [1 2]
        scene["dimer_track_ids"] = [1 2]
    end
    scene
end
