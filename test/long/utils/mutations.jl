# Mutation helpers shared by test/test_spacetime.jl (Core: validation sweep) and
# test/long/mutation_builds.jl (Long: builds every accepted mutation). The including file
# has `Spacetime` (SMLMView.Spacetime) and `spacetime` in scope.
#
# The requirement under test: for every mutation of every key of a scene, validate_scene
# throws an ArgumentError, or else it returns a canonical scene that builds without
# throwing and whose self-test failures are only names of checks that returned false (a
# failure that is an exception message means the builder threw inside the self-test).

const SCALAR_MUTATIONS = (
    "nan" => NaN, "inf" => Inf, "negative" => -1, "zero" => 0, "big" => 7,
    "tiny" => 1e-100, "huge" => 1e100, "floatmax" => floatmax(Float64),
    "uint64-max" => typemax(UInt64), "2^100" => big(2)^100,
    "int-min" => typemin(Int), "int-max" => typemax(Int),
)

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
        for (label, x) in (SCALAR_MUTATIONS..., "nothing" => nothing, "string" => "x")
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

# :rejected, :accepted, or a violation string; validation only.
function validation_outcome(scene)
    try
        Spacetime.validate_scene(scene)
        :accepted
    catch error
        error isa ArgumentError ? :rejected : "validate threw " * short_error(error)
    end
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
    names = Set(string.(keys(view.health.checks)))
    raised = [failure for failure in view.health.failures if !(failure in names)]
    isempty(raised) || return "self-test raised: " * first(join(raised, "; "), 140)
    (:accepted, view)
end
