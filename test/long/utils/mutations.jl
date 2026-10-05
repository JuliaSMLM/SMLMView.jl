# Mutation helpers shared by test/test_spacetime.jl (Core: validation sweep) and
# test/long/mutation_builds.jl (Long: builds every accepted mutation). The including file
# has `Spacetime` (SMLMView.Spacetime) and `spacetime` in scope.
#
# The requirement under test: for every mutation of every key of a scene, validate_scene
# throws an ArgumentError, or else it returns a canonical scene that builds and passes its
# control self-test.

const SCALAR_MUTATIONS = (
    "nan" => NaN, "inf" => Inf, "negative" => -1, "zero" => 0, "big" => 7,
    "tiny" => 1e-100, "huge" => 1e100, "floatmax" => floatmax(Float64),
    "uint64-max" => typemax(UInt64), "2^100" => big(2)^100,
    "int-min" => typemin(Int), "int-max" => typemax(Int),
)

# A String that is not valid UTF-8 (Makie's text layout throws on it).
const INVALID_UTF8 = String(UInt8[0xff])

# `value` with its first element replaced by `x`; the element type is widened, never
# turned into floats, so integer arrays keep their integer range cases.
function poke(value, x)
    if value isa AbstractVector && !isempty(value) && first(value) isa AbstractArray
        copy = Vector{Any}(value)
        copy[1] = poke(first(value), x)
        copy
    elseif value isa AbstractArray && !isempty(value)
        copy = Array{Union{eltype(value),typeof(x)}}(value)
        copy[1] = x
        copy
    else
        x
    end
end

# Mutated values of one key's value, as label => new value.
function mutations(value)
    out = Pair{String,Any}["nothing" => nothing, "string" => "bad", "float" => 1.5,
                           "symbol" => :bad]
    if value isa AbstractArray
        push!(out, "short" => collect(selectdim(value, 1, 1:size(value, 1) - 1)))
        for (label, x) in (SCALAR_MUTATIONS..., "nothing" => nothing, "string" => "x",
                           "invalid-utf8" => INVALID_UTF8)
            push!(out, "$label-element" => poke(value, x))
        end
        if length(value) >= 2
            copy = Array{eltype(value)}(value)
            copy[2] = copy[1]
            push!(out, "duplicate" => copy)
        end
        if value isa AbstractVector && !isempty(value) && first(value) isa NamedTuple
            for field in (:truth_id, :estimate_id), (label, x) in SCALAR_MUTATIONS
                copy = Vector{Any}(value)
                copy[1] = merge(copy[1], NamedTuple{(field,)}((x,)))
                push!(out, "$field-$label" => copy)
            end
        end
    elseif value isa AbstractString
        push!(out, "invalid-utf8" => INVALID_UTF8)
    elseif value isa Bool
        push!(out, "int" => 2)
    elseif value isa Real
        append!(out, SCALAR_MUTATIONS)
    end
    out
end

# Key paths of a scene: every top-level key, and every key of a nested Dict.
function key_paths(scene)
    out = Vector{Vector{String}}()
    for (key, value) in scene
        push!(out, [key])
        value isa AbstractDict && foreach(sub -> push!(out, [key, sub]), keys(value))
    end
    out
end

lookup(scene, path) = length(path) == 1 ? scene[path[1]] : scene[path[1]][path[2]]

function assign!(scene, path, value)
    container = length(path) == 1 ? scene : scene[path[1]]
    value === :delete ? delete!(container, path[end]) : (container[path[end]] = value)
    scene
end

# Every mutation of `base`, as "key <- label" => mutated copy (the key deleted included).
function mutated_scenes(base)
    out = Pair{String,Dict{String,Any}}[]
    for path in key_paths(base)
        candidates = Pair{String,Any}["delete" => :delete]
        append!(candidates, mutations(lookup(base, path)))
        for (label, mutated) in candidates
            scene = assign!(deepcopy(base), path, mutated)
            push!(out, join(path, "/") * " <- " * label => scene)
        end
    end
    out
end

short_error(error) = first(sprint(showerror, error), 140)

# A scene with every optional key of the tables: the thresholded raw mode (with the
# all-voxels keys present too), alpha keys, intensity unit, labels, id description,
# matches with their gate, links, and dimer episodes in both track sets.
function comprehensive_scene()
    scene = Spacetime.example_scene(; dimers=true)
    scene["raw_alpha_min"] = 0.001f0
    scene["raw_alpha_max"] = 0.08f0
    scene["raw_alpha_gamma"] = 1.2f0
    scene["raw_render_mode"] = "thresholded"
    scene["raw_threshold"] = 12.5
    scene["raw_quantile"] = 0.98
    scene["raw_intensity_unit"] = "counts"
    truth = scene["ground_truth_tracks"]
    for set in (scene, truth)
        set["track_labels"] = ["L$index" for index in eachindex(set["track_x"])]
        set["track_id_description"] = "run id"
    end
    for (key, value) in scene
        startswith(key, "dimer_") && (truth[key] = deepcopy(value))
    end
    truth["dimer_labels"] = ["G1"]
    truth["dimer_track_ids"] = [101 102]
    scene
end

# The fixtures the sweeps mutate: everything switched on, and no ground truth.
sweep_fixtures() = (comprehensive_scene(), Spacetime.example_scene(; truth=false))

# Key paths the schema tables name: top level, in ground_truth_tracks, in links.
function table_key_paths()
    paths = Set{Vector{String}}()
    for spec in vcat(Spacetime.SCENE_SPECS, Spacetime.TRACK_SPECS, Spacetime.DIMER_SPECS)
        push!(paths, [spec.key])
    end
    for spec in vcat(Spacetime.TRACK_SPECS, Spacetime.DIMER_SPECS)
        push!(paths, ["ground_truth_tracks", spec.key])
    end
    for spec in Spacetime.LINK_SPECS
        push!(paths, ["links", spec.key])
    end
    for key in ("schema", "ground_truth_tracks", "links", "trajectory_color_matches")
        push!(paths, [key])
    end
    paths
end

# Keys of the canonical scene whose value is not exactly its table type.
function canonical_type_violations(canonical)
    violations = String[]
    function check(dict, specs, prefix)
        for spec in specs
            haskey(dict, spec.key) || continue
            value = dict[spec.key]
            typeof(value) === spec.type || push!(violations,
                "$prefix$(spec.key) is a $(typeof(value)), not a $(spec.type)")
        end
    end
    check(canonical, vcat(Spacetime.SCENE_SPECS, Spacetime.TRACK_SPECS,
                          Spacetime.DIMER_SPECS), "")
    haskey(canonical, "ground_truth_tracks") && check(canonical["ground_truth_tracks"],
        vcat(Spacetime.TRACK_SPECS, Spacetime.DIMER_SPECS), "ground_truth_tracks: ")
    haskey(canonical, "links") && check(canonical["links"], Spacetime.LINK_SPECS, "links: ")
    matches = NamedTuple{(:truth_id, :estimate_id),Tuple{Int,Int}}
    if haskey(canonical, "trajectory_color_matches") &&
       typeof(canonical["trajectory_color_matches"]) !== Vector{matches}
        push!(violations, "trajectory_color_matches is not a Vector of matches")
    end
    typeof(get(canonical, "schema", nothing)) === String || push!(violations, "schema")
    violations
end

# :rejected, :accepted (the canonical scene has exactly the table types), or a violation
# string; validation only.
function validation_outcome(scene)
    canonical = try
        Spacetime.validate_scene(scene)
    catch error
        return error isa ArgumentError ? :rejected : "validate threw " * short_error(error)
    end
    violations = canonical_type_violations(canonical)
    isempty(violations) ? :accepted :
        "canonical types: " * first(join(violations, "; "), 140)
end

# Picks every track (and none) in every source of a built view; returns violations.
function pick_every_track(view, name)
    violations = String[]
    inspector = view.controls.inspector
    for source in (:found, :ground_truth)
        haskey(inspector.frame_track_sets, source) || continue
        while inspector.trajectory_source[] !== source
            inspector.toggle_trajectory_source()
        end
        for track in 0:inspector.frame_track_sets[source].n_tracks
            try
                inspector.selected_track[] = track
                inspector.selected_track_text[] isa String ||
                    push!(violations, "$name: selected text is not a string")
            catch error
                push!(violations, "$name: picking $source track $track threw " *
                                  short_error(error))
            end
        end
    end
    violations
end

# The full outcome: :rejected, (:accepted, view), or a violation string.
function full_outcome(scene)
    verdict = validation_outcome(scene)
    verdict === :accepted || return verdict
    view = try
        spacetime(scene; output=:none)
    catch error
        return "built with " * short_error(error)
    end
    view.health.passed ||
        return "self-test failed: " * first(join(view.health.failures, "; "), 140)
    (:accepted, view)
end
