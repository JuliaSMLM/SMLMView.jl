using Test
using SMLMView
using SMLMView: Spacetime

example(; kwargs...) = Spacetime.example_scene(; kwargs...)
include("utils/mutations.jl")

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

@testset "every accepted mutation builds" begin
    violations = String[]
    accepted = 0
    rejected = 0
    for base in (example(; dimers=true), example(; truth=false))
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
