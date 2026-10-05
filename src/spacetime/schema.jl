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

# Canonical types and ranges. One table per group of keys lists every key the builder
# reads: its canonical type (what the builder converts it to or uses), whether it is
# required (a Bool, or a function of the dict being read), and the range of every element.
# Floating-point values must be finite. `validate_scene` converts each present key to its
# canonical type, reports every conversion or range failure, and returns the converted
# scene, so the builder only ever sees canonical values.
struct KeySpec
    key::String
    type::Type
    required::Any
    lo::Float64
    hi::Float64
    positive::Bool
end

function KeySpec(key, type; required=false, lo=-Inf, hi=Inf, positive=false)
    KeySpec(key, type, required, lo, hi, positive)
end

# Words for messages and docs: the canonical type and range of a key.
function _describe(spec::KeySpec)
    text = "a " * string(spec.type)
    floats = Union{AbstractFloat,AbstractArray{<:AbstractFloat},
                   AbstractArray{<:AbstractArray{<:AbstractFloat}}}
    spec.type <: floats && (text *= " with finite values")
    spec.type <: Union{String,Vector{String}} && (text *= " (valid UTF-8)")
    spec.positive && (text *= " > 0")
    isfinite(spec.lo) && isfinite(spec.hi) && (text *= " in [$(spec.lo), $(spec.hi)]")
    isfinite(spec.lo) && !isfinite(spec.hi) && (text *= " >= $(spec.lo)")
    text
end

_all_modes(dict) = get(dict, "raw_render_mode", "thresholded") == "all_voxels"
_thresholded(dict) = !_all_modes(dict)
_has_matches(dict) = haskey(dict, "trajectory_color_matches")

const SCENE_SPECS = KeySpec[
    KeySpec("nx", Int; required=true, lo=1),
    KeySpec("ny", Int; required=true, lo=1),
    KeySpec("pixel_size", Float64; required=true, lo=1e-4, hi=1e3),
    KeySpec("sub_steps", Int; required=true, lo=1),
    KeySpec("source_frames", Vector{Int}; required=true),
    KeySpec("state_source", String; required=true),
    KeySpec("title", String),
    KeySpec("raw_intensity_unit", String),
    KeySpec("raw_render_mode", String),
    KeySpec("raw_normalization_quantile", Float64; required=_all_modes, lo=0, hi=1),
    KeySpec("raw_normalization_high", Float64; required=_all_modes),
    KeySpec("raw_threshold", Float64; required=_thresholded),
    KeySpec("raw_quantile", Float64; required=_thresholded, lo=0, hi=1),
    KeySpec("raw_alpha_min", Float32; lo=0, hi=1),
    KeySpec("raw_alpha_max", Float32; lo=0, hi=1),
    KeySpec("raw_alpha_gamma", Float32; positive=true),
    KeySpec("raw_xyz", Matrix{Float32}; required=true),
    KeySpec("raw_scaled_intensity", Vector{Float32}; required=true, lo=0, hi=1),
    KeySpec("trajectory_color_match_gate", Float64; required=_has_matches),
]

const TRACK_SPECS = KeySpec[
    KeySpec("track_x", Vector{Vector{Float32}}; required=true),
    KeySpec("track_y", Vector{Vector{Float32}}; required=true),
    KeySpec("track_z", Vector{Vector{Float32}}; required=true),
    KeySpec("track_fine_frames", Vector{Vector{Int}}; required=true),
    KeySpec("track_colors", Matrix{Float32}; required=true, lo=0, hi=1),
    KeySpec("track_ids", Vector{Int}),
    KeySpec("track_labels", Vector{String}),
    KeySpec("matched_other_ids", Vector{Int}),
    KeySpec("track_label_prefix", String),
    KeySpec("track_id_description", String),
    KeySpec("display_name", String),
]

# The five dimer path keys come together; the two pair matrices are required once there
# is an episode (checked after conversion).
const DIMER_SPECS = KeySpec[
    KeySpec("dimer_x", Vector{Vector{Float32}}; required=true),
    KeySpec("dimer_y", Vector{Vector{Float32}}; required=true),
    KeySpec("dimer_z", Vector{Vector{Float32}}; required=true),
    KeySpec("dimer_fine_frames", Vector{Vector{Int}}; required=true),
    KeySpec("dimer_labels", Vector{String}; required=true),
    KeySpec("dimer_track_indices", Matrix{Int}),
    KeySpec("dimer_track_ids", Matrix{Int}),
]

const LINK_SPECS = KeySpec[
    KeySpec("x0", Vector{Float32}; required=true),
    KeySpec("y0", Vector{Float32}; required=true),
    KeySpec("z0", Vector{Float32}; required=true),
    KeySpec("x1", Vector{Float32}; required=true),
    KeySpec("y1", Vector{Float32}; required=true),
    KeySpec("z1", Vector{Float32}; required=true),
    KeySpec("w", Vector{Float32}; required=true, lo=0, hi=1),
    KeySpec("on_map", Vector{Bool}; required=true),
]

# Conversion to the canonical type: scalars are Reals (or Strings, or Bools) converted with
# the type's constructor, arrays are converted element by element into a one-based
# `Array` of exactly the canonical type (never an OffsetArray, view or range). An array
# that already has exactly the canonical type is reused, not copied. Anything else throws.
function _convert(::Type{T}, x) where {T<:Union{Int,Float32,Float64}}
    x isa Real || throw(ArgumentError("expected a number, got $(typeof(x))"))
    T(x)
end
function _convert(::Type{String}, x)
    x isa AbstractString || throw(ArgumentError("expected a string, got $(typeof(x))"))
    String(x)
end
function _convert(::Type{Bool}, x)
    x isa Bool || throw(ArgumentError("expected a Bool, got $(typeof(x))"))
    x
end
function _convert(::Type{Vector{T}}, x) where {T}
    x isa Vector{T} && return x
    x isa AbstractVector || throw(ArgumentError("expected a vector, got $(typeof(x))"))
    _materialize(T, x)
end
function _convert(::Type{Matrix{T}}, x) where {T}
    x isa Matrix{T} && return x
    x isa AbstractMatrix || throw(ArgumentError("expected a matrix, got $(typeof(x))"))
    _materialize(T, x)
end

# A new one-based `Array{T,N}` holding the converted elements of `x`, in iteration order.
# `T.(x)` and comprehensions keep the axes of an OffsetArray, so the copy is explicit.
function _materialize(::Type{T}, x::AbstractArray{<:Any,N}) where {T,N}
    out = Array{T,N}(undef, size(x))
    for (index, element) in enumerate(x)
        out[index] = _convert(T, element)
    end
    out
end

# Every element of a (possibly nested) array, or the scalar itself, satisfies `test`.
_all_elements(test, value) = test(value)
function _all_elements(test, value::AbstractArray)
    all(element -> _all_elements(test, element), value)
end
_all_elements(test, value::AbstractArray{<:Union{Real,String}}) = all(test, value)

# Reads one key into `out`: converts it, then checks finiteness and range of the
# converted value. Pushes one problem naming the key when anything fails; returns the
# value or nothing.
function _read!(problems, out, dict, spec::KeySpec, prefix)
    key = spec.key
    required = spec.required isa Function ? spec.required(dict) : spec.required
    if !haskey(dict, key)
        required && push!(problems, "missing key $prefix$key ($(_describe(spec)))")
        return nothing
    end
    value = try
        _convert(spec.type, dict[key])
    catch error
        error isa InterruptException && rethrow()
        push!(problems, "$prefix$key must be $(_describe(spec))")
        return nothing
    end
    function in_range(x)
        x isa AbstractString && return isvalid(x)
        x isa AbstractFloat && !isfinite(x) && return false
        x isa Real || return true
        spec.lo <= x <= spec.hi && (!spec.positive || x > 0)
    end
    if !_all_elements(in_range, value)
        push!(problems, "$prefix$key must be $(_describe(spec))")
        return nothing
    end
    out[key] = value
end

# Keys of `dict` the table does not know are passed through to the canonical copy.
function _pass_through!(out, dict, specs, known)
    names = Set(spec.key for spec in specs)
    for (key, value) in dict
        key in names || key in known || haskey(out, key) || (out[key] = value)
    end
    out
end

# Position and frame rules. The box is B = [0, X] x [0, Y] x [0.5, T + 0.5], the axis
# limits the builder sets, with X = nx*pixel_size, Y = ny*pixel_size and T the number of
# frames. Every position must lie in B grown by its own size (x in [-X, 2X], y in
# [-Y, 2Y], z in [0.5 - T, 2T + 0.5]); every fine frame in [1 - kT, 2kT] with
# kT = sub_steps*T <= FRAME_LIMIT. Values are checked after conversion, inclusive, with
# the position bounds converted to Float32 like the values, so a position exactly on a
# bound is accepted. `box` is nothing, or (; X, Y, T, frames) with frames nothing when
# sub_steps*T is out of bounds (reported once, in _check_scene!).
const FRAME_LIMIT = 10^6

function _position_bounds(box, axis)
    axis == 1 ? (-box.X, 2box.X) :
    axis == 2 ? (-box.Y, 2box.Y) :
    (0.5 - box.T, 2box.T + 0.5)
end

function _check_positions!(problems, box, prefix, key, value, axis)
    (isnothing(box) || isnothing(value)) && return nothing
    low, high = _position_bounds(box, axis)
    low32, high32 = Float32(low), Float32(high)
    _all_elements(x -> low32 <= x <= high32, value) || push!(problems, prefix *
        "$key must lie within [$low, $high] (the box grown by its own size)")
    nothing
end

function _check_frames!(problems, box, prefix, key, value)
    (isnothing(box) || isnothing(box.frames) || isnothing(value)) && return nothing
    low, high = 1 - box.frames, 2 * box.frames
    _all_elements(x -> low <= x <= high, value) || push!(problems, prefix *
        "$key must lie within [$low, $high] (the fine frames grown by their own size)")
    nothing
end

# Reads a track set (the scene itself, or ground_truth_tracks) into a canonical copy.
# Returns (canonical, n_tracks), with n_tracks nothing when the arrays are not usable.
function _check_track_set!(problems, track_scene, prefix; passthrough=true, box=nothing)
    out = Dict{String,Any}()
    for spec in TRACK_SPECS
        _read!(problems, out, track_scene, spec, prefix)
    end
    n_tracks = nothing
    paths = [get(out, key, nothing) for key in
             ("track_x", "track_y", "track_z", "track_fine_frames")]
    if !any(isnothing, paths)
        counts = unique(length.(paths))
        if length(counts) == 1
            n_tracks = only(counts)
            misaligned = [
                index for index in 1:n_tracks if
                length(unique(length(path[index]) for path in paths)) > 1
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
    colors = get(out, "track_colors", nothing)
    if !isnothing(colors) && !isnothing(n_tracks) && size(colors) != (n_tracks, 3)
        push!(problems, prefix * "track_colors must be $n_tracks x 3, got " *
                        join(size(colors), " x "))
    end
    for key in ("track_ids", "track_labels", "matched_other_ids")
        value = get(out, key, nothing)
        isnothing(value) || isnothing(n_tracks) || length(value) == n_tracks ||
            push!(problems, prefix * "$key has length $(length(value)); " *
                            "expected $n_tracks (one per track)")
    end
    ids = get(out, "track_ids", nothing)
    isnothing(ids) || allunique(ids) ||
        push!(problems, prefix * "track_ids must be unique within a set")
    for (axis, key) in enumerate(("track_x", "track_y", "track_z"))
        _check_positions!(problems, box, prefix, key, get(out, key, nothing), axis)
    end
    _check_frames!(problems, box, prefix, "track_fine_frames",
        get(out, "track_fine_frames", nothing))
    _check_dimers!(problems, out, track_scene, prefix, box)
    passthrough &&
        _pass_through!(out, track_scene, vcat(TRACK_SPECS, DIMER_SPECS), ())
    (out, n_tracks)
end

# Dimer episodes of a track set: all five path keys together, aligned per episode; the
# two track pair matrices are required once there is an episode. Converted values go
# into `out`.
function _check_dimers!(problems, out, track_scene, prefix, box)
    any(startswith("dimer_"), keys(track_scene)) || return nothing
    for spec in DIMER_SPECS
        _read!(problems, out, track_scene, spec, prefix)
    end
    for (axis, key) in enumerate(("dimer_x", "dimer_y", "dimer_z"))
        _check_positions!(problems, box, prefix, key, get(out, key, nothing), axis)
    end
    _check_frames!(problems, box, prefix, "dimer_fine_frames",
        get(out, "dimer_fine_frames", nothing))
    arrays = [get(out, key, nothing) for key in
              ("dimer_x", "dimer_y", "dimer_z", "dimer_fine_frames", "dimer_labels")]
    any(isnothing, arrays) && return nothing
    n_episodes = length(arrays[1])
    if any(array -> length(array) != n_episodes, arrays)
        push!(problems, prefix * "dimer_x, dimer_y, dimer_z, dimer_fine_frames and " *
                        "dimer_labels must have one entry per episode")
        return nothing
    end
    xs, ys, zs, frames = arrays[1:4]
    bad = [
        episode for episode in 1:n_episodes if
        isempty(xs[episode]) ||
        any(array -> length(array[episode]) != length(xs[episode]), (ys, zs, frames))
    ]
    isempty(bad) || push!(problems, prefix * "dimer episode $(first(bad)) is empty or " *
        "its dimer_x, dimer_y, dimer_z and dimer_fine_frames lengths differ")
    for key in ("dimer_track_indices", "dimer_track_ids")
        if haskey(out, key)
            size(out[key]) == (n_episodes, 2) || push!(problems,
                prefix * "$key must be $n_episodes x 2, got " * join(size(out[key]), " x "))
        elseif n_episodes > 0 && !haskey(track_scene, key)
            push!(problems, prefix * "missing key $key (an n_episodes x 2 Matrix{Int}, " *
                            "required when the set has dimer episodes)")
        end
    end
    nothing
end

# The ids of a canonical track set: its `track_ids`, else the default.
_checked_ids(n_tracks, canonical) = isnothing(n_tracks) ? nothing : _track_ids(canonical)

# Reads the whole scene into its canonical copy, collecting every problem.
function _check_scene!(problems, scene)
    out = Dict{String,Any}("schema" => SCHEMA)
    for spec in SCENE_SPECS
        _read!(problems, out, scene, spec, "")
    end
    source_frames = get(out, "source_frames", nothing)
    isnothing(source_frames) || !isempty(source_frames) ||
        push!(problems, "source_frames must be a non-empty Vector{Int}")
    nx, ny = get(out, "nx", nothing), get(out, "ny", nothing)
    pixel_size = get(out, "pixel_size", nothing)

    n_frames = isnothing(source_frames) ? nothing : length(source_frames)
    n_voxels = try
        isnothing(nx) || isnothing(ny) || isnothing(n_frames) ? nothing :
            Base.checked_mul(Base.checked_mul(nx, ny), n_frames)
    catch error
        error isa OverflowError || rethrow()
        push!(problems, "nx*ny*length(source_frames) overflows")
        nothing
    end
    box = nothing
    if !isnothing(nx) && !isnothing(ny) && !isnothing(pixel_size) && !isnothing(n_frames)
        frames = try
            total = Base.checked_mul(get(out, "sub_steps", 1), n_frames)
            total <= FRAME_LIMIT || push!(problems,
                "sub_steps * length(source_frames) = $total must be at most $FRAME_LIMIT")
            total <= FRAME_LIMIT ? total : nothing
        catch error
            error isa OverflowError || rethrow()
            push!(problems, "sub_steps * length(source_frames) overflows (at most " *
                            "$FRAME_LIMIT)")
            nothing
        end
        box = (; X=nx * pixel_size, Y=ny * pixel_size, T=n_frames, frames)
    end
    raw_xyz = get(out, "raw_xyz", nothing)
    if !isnothing(raw_xyz)
        size(raw_xyz, 2) == 3 || push!(problems,
            "raw_xyz must have 3 columns, got $(size(raw_xyz, 2))")
        if size(raw_xyz, 2) == 3
            for axis in 1:3
                _check_positions!(problems, box, "", "raw_xyz column $axis",
                    view(raw_xyz, :, axis), axis)
            end
        end
        isnothing(n_voxels) || size(raw_xyz, 1) == n_voxels || push!(problems,
            "raw_xyz has $(size(raw_xyz, 1)) rows; " *
            "nx*ny*length(source_frames) = $n_voxels")
    end
    intensity = get(out, "raw_scaled_intensity", nothing)
    if !isnothing(intensity)
        expected = isnothing(raw_xyz) ? n_voxels : size(raw_xyz, 1)
        isnothing(expected) || length(intensity) == expected || push!(problems,
            "raw_scaled_intensity has length $(length(intensity)); expected $expected " *
            "(one value per raw_xyz row)")
    end

    found, n_found = _check_track_set!(problems, scene, ""; passthrough=false, box)
    merge!(out, found)
    found_ids = _checked_ids(n_found, found)
    truth_ids = nothing
    if haskey(scene, "ground_truth_tracks")
        truth = scene["ground_truth_tracks"]
        if truth isa AbstractDict
            canonical, n_truth = _check_track_set!(
                problems, truth, "ground_truth_tracks: "; box)
            out["ground_truth_tracks"] = canonical
            truth_ids = _checked_ids(n_truth, canonical)
        else
            push!(problems, "ground_truth_tracks must be a Dict with the track keys")
        end
    end

    if haskey(scene, "trajectory_color_matches")
        haskey(scene, "ground_truth_tracks") || push!(problems,
            "trajectory_color_matches needs ground_truth_tracks")
        out["trajectory_color_matches"] = _check_matches!(
            problems, scene["trajectory_color_matches"], found_ids, truth_ids)
        truth_set = get(out, "ground_truth_tracks", nothing)
        isnothing(truth_set) || _check_match_colours!(
            problems, out["trajectory_color_matches"], out, found_ids, truth_set,
            truth_ids)
    end

    if haskey(scene, "links")
        links = scene["links"]
        if links isa AbstractDict
            canonical = Dict{String,Any}()
            for spec in LINK_SPECS
                _read!(problems, canonical, links, spec, "links: ")
            end
            for (axis, (first_key, second_key)) in enumerate((("x0", "x1"), ("y0", "y1"),
                                                              ("z0", "z1")))
                for key in (first_key, second_key)
                    _check_positions!(problems, box, "links: ", key,
                        get(canonical, key, nothing), axis)
                end
            end
            lengths = unique(length(value) for (_, value) in canonical)
            length(lengths) <= 1 || push!(problems,
                "links: arrays x0 y0 z0 x1 y1 z1 w on_map must have the same length")
            out["links"] = _pass_through!(canonical, links, LINK_SPECS, ())
        else
            push!(problems, "links must be a Dict (x0 y0 z0 x1 y1 z1 w on_map)")
        end
    end
    known = ("schema", "ground_truth_tracks", "links", "trajectory_color_matches")
    _pass_through!(out, scene, vcat(SCENE_SPECS, TRACK_SPECS, DIMER_SPECS), known)
    out
end

# Colour rules, when matches are present: a matched found track has exactly the colour
# of its ground-truth track, and the found colours are unique.
function _check_match_colours!(problems, matches, found, found_ids, truth, truth_ids)
    colors = get(found, "track_colors", nothing)
    truth_colors = get(truth, "track_colors", nothing)
    (isnothing(colors) || isnothing(truth_colors) || isnothing(found_ids) ||
        isnothing(truth_ids)) && return nothing
    (size(colors, 1) == length(found_ids) && size(truth_colors, 1) == length(truth_ids) &&
        size(colors, 2) == 3 && size(truth_colors, 2) == 3) || return nothing
    differing = String[]
    for match in matches
        found_row = findfirst(==(match.estimate_id), found_ids)
        truth_row = findfirst(==(match.truth_id), truth_ids)
        (isnothing(found_row) || isnothing(truth_row)) && continue
        colors[found_row, :] == truth_colors[truth_row, :] || push!(differing,
            "estimate_id $(match.estimate_id) and truth_id $(match.truth_id)")
    end
    isempty(differing) || push!(problems,
        "trajectory_color_matches: matched tracks must have the same track_colors row " *
        "(differing: " * join(first(differing, 5), "; ") *
        (length(differing) > 5 ? "; and $(length(differing) - 5) more" : "") * ")")
    rows = [Tuple(colors[row, :]) for row in axes(colors, 1)]
    allunique(rows) || push!(problems,
        "track_colors rows must be unique when trajectory_color_matches is present")
    nothing
end

# Colour matches: a vector of objects with Integer `truth_id` and `estimate_id`, converted
# to NamedTuples of Int; every id must belong to its set.
function _check_matches!(problems, matches, found_ids, truth_ids)
    canonical = NamedTuple{(:truth_id, :estimate_id),Tuple{Int,Int}}[]
    if !(matches isa AbstractVector)
        push!(problems, "trajectory_color_matches must be a vector of named tuples " *
                        "with Integer truth_id and estimate_id")
        return canonical
    end
    for match in matches
        ids = try
            (; truth_id=_match_id(match.truth_id),
               estimate_id=_match_id(match.estimate_id))
        catch error
            error isa InterruptException && rethrow()
            push!(problems, "trajectory_color_matches must be a vector of named tuples " *
                            "with Integer truth_id and estimate_id")
            return canonical
        end
        isnothing(truth_ids) || ids.truth_id in truth_ids || push!(problems,
            "trajectory_color_matches: truth_id $(ids.truth_id) is not a " *
            "ground_truth_tracks track id")
        isnothing(found_ids) || ids.estimate_id in found_ids || push!(problems,
            "trajectory_color_matches: estimate_id $(ids.estimate_id) is not a track id")
        push!(canonical, ids)
    end
    canonical
end
function _match_id(value)
    value isa Integer || throw(ArgumentError("match ids are Integers"))
    Int(value)
end

"""
    validate_scene(scene::AbstractDict) -> Dict{String,Any}

Check a scene against the `"spacetime/1"` schema and return its canonical copy.

Every key the viewer reads is converted to its canonical type (for example `Int`,
`Float32`, `Vector{Vector{Float32}}`, `Matrix{Float32}`, `String`) and checked for
finite values, range and alignment: `pixel_size` in [1e-4, 1e3] μm, intensities,
colours, link weights and quantiles in [0, 1], unique `track_ids` per set, track
arrays of equal lengths, every position in the scene's box grown by its own size,
`sub_steps * length(source_frames) <= 10^6` with every fine frame in `[1 - kT, 2kT]`,
matched and unique track colours when `trajectory_color_matches` is present, and the
optional parts present (`ground_truth_tracks`,
`trajectory_color_matches`, `links`, `dimer_*`). Ranges and finiteness apply after
conversion to the canonical type. Throws one `ArgumentError` naming every offending
key, including an unsupported `"schema"` value. The returned `Dict` is new (nested
Dicts too) and carries `"schema" => "spacetime/1"`. Every array in it is exactly its
canonical `Array` type, one-based (an OffsetArray, view or range is copied); arrays
that already have exactly that type are reused, not copied. The caller's scene is
never changed. A scene that matches
the canonical types and ranges builds and runs the control self-test without
throwing; [`spacetime`](@ref) hands the canonical scene to the builder.
"""
function validate_scene(scene::AbstractDict)
    problems = String[]
    try
        scene_schema(scene)
    catch error
        error isa ArgumentError || rethrow()
        push!(problems, error.msg)
    end
    canonical = _check_scene!(problems, scene)
    isempty(problems) || throw(ArgumentError(
        "invalid spacetime scene ($(length(problems)) problem" *
        (length(problems) == 1 ? "" : "s") * "):\n  " * join(problems, "\n  "),
    ))
    canonical
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
        [(0.25 + 0.1 * f, 0.30, f) for f in 1:T],                         # straight
        [(1.20, 0.20 + 0.06 * f, f) for f in (1, 2, 3, 6, 7, 8)],         # gap 3 -> 6
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
