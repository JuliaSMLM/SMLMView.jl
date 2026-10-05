using Test
using SMLMView
using SMLMView: Spacetime

example(; kwargs...) = Spacetime.example_scene(; kwargs...)
include("utils/mutations.jl")

@testset "every accepted mutation builds" begin
    violations = String[]
    accepted = 0
    rejected = 0
    for base in sweep_fixtures()
        for (name, scene) in mutated_scenes(base)
            outcome = full_outcome(scene)
            if outcome === :rejected
                rejected += 1
            elseif outcome isa Tuple
                accepted += 1
                append!(violations, pick_every_track(outcome[2], name))
            else
                push!(violations, "$name: $outcome")
            end
        end
    end
    println("mutations: $rejected rejected, $accepted accepted and built")
    foreach(println, violations)
    @test isempty(violations)
    @test rejected > 900
    @test accepted > 100
end
