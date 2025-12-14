using Test
using SMLMView

@testset "SMLMView.jl" begin
    include("test_constants.jl")
    include("test_keybindings.jl")
    include("test_viewer.jl")
end
