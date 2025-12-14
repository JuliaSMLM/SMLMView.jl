using Test
using SMLMView
using SMLMView: RGB

@testset "Constants" begin
    @testset "DEFAULT_CHANNEL_COLORS" begin
        @test DEFAULT_CHANNEL_COLORS isa NTuple{3, RGB{Float64}}

        # CMY colors
        cyan, magenta, yellow = DEFAULT_CHANNEL_COLORS
        @test cyan == RGB{Float64}(0.0, 1.0, 1.0)
        @test magenta == RGB{Float64}(1.0, 0.0, 1.0)
        @test yellow == RGB{Float64}(1.0, 1.0, 0.0)
    end

    @testset "CHANNEL_COLOR_PRESETS" begin
        @test CHANNEL_COLOR_PRESETS isa Dict{Symbol, NTuple{3, RGB{Float64}}}

        # Check preset keys exist
        @test haskey(CHANNEL_COLOR_PRESETS, :cmy)
        @test haskey(CHANNEL_COLOR_PRESETS, :rgb)
        @test haskey(CHANNEL_COLOR_PRESETS, :mgc)

        # Verify preset values
        @test CHANNEL_COLOR_PRESETS[:cmy] == DEFAULT_CHANNEL_COLORS

        rgb = CHANNEL_COLOR_PRESETS[:rgb]
        @test rgb[1] == RGB{Float64}(1.0, 0.0, 0.0)  # Red
        @test rgb[2] == RGB{Float64}(0.0, 1.0, 0.0)  # Green
        @test rgb[3] == RGB{Float64}(0.0, 0.0, 1.0)  # Blue
    end
end
