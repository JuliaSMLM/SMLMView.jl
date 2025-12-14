using Test
using SMLMView

# Note: These tests use show=false to avoid display issues in CI/headless environments
# WGLMakie figure creation still works, we just don't try to display

@testset "Viewer" begin
    @testset "configure_display!" begin
        # Should not error on repeated calls
        configure_display!()
        configure_display!()  # Second call should be no-op
    end

    @testset "smlmview 2D" begin
        data = rand(64, 64)
        v = smlmview(data; show=false)

        @test v isa NamedTuple
        @test haskey(v, :fig)
        @test haskey(v, :ax)
        @test haskey(v, :data)
        @test haskey(v, :display_dims)
        @test haskey(v, :slice_indices)
        @test haskey(v, :colorrange)
        @test haskey(v, :colormap)
        @test haskey(v, :cursor_pos)
        @test haskey(v, :pixel_value)

        # Data reference should be same object (no copy)
        @test v.data === data

        # Default display dims
        @test v.display_dims[] == (1, 2)

        # Slice indices for 2D should have 2 elements
        @test length(v.slice_indices) == 2
    end

    @testset "smlmview 3D" begin
        data = rand(32, 32, 10)
        v = smlmview(data; show=false)

        @test v.data === data
        @test v.display_dims[] == (1, 2)
        @test length(v.slice_indices) == 3

        # Third dimension slice index should be observable
        @test v.slice_indices[3][] == 1

        # Can change slice
        v.slice_indices[3][] = 5
        @test v.slice_indices[3][] == 5
    end

    @testset "smlmview 4D" begin
        data = rand(16, 16, 5, 8)
        v = smlmview(data; display_dims=(1, 3), show=false)

        @test v.display_dims[] == (1, 3)
        @test length(v.slice_indices) == 4
    end

    @testset "smlmview kwargs" begin
        data = rand(32, 32)

        # Custom colormap
        v = smlmview(data; colormap=:viridis, show=false)
        @test v.colormap[] == :viridis

        # Custom clip (should affect colorrange)
        v = smlmview(data; clip=(0.1, 0.9), show=false)
        @test v.colorrange[] isa Tuple{Float64, Float64}
    end

    @testset "smlmview validation" begin
        # 1D data should error
        @test_throws ArgumentError smlmview(rand(10); show=false)

        # Same display dims should error
        @test_throws ArgumentError smlmview(rand(10, 10); display_dims=(1, 1), show=false)

        # Out of range display dims should error
        @test_throws ArgumentError smlmview(rand(10, 10); display_dims=(1, 3), show=false)
    end

    @testset "smlmview composite 2-channel" begin
        ch1 = rand(32, 32)
        ch2 = rand(32, 32)

        v = smlmview((ch1, ch2); show=false)

        @test v isa NamedTuple
        @test haskey(v, :channels)
        @test haskey(v, :colors)
        @test haskey(v, :channel_visible)
        @test haskey(v, :rgb)

        @test v.channels === (ch1, ch2)
        @test length(v.channel_visible) == 2
        @test all(vis[] for vis in v.channel_visible)  # All visible by default
    end

    @testset "smlmview composite 3-channel" begin
        ch1 = rand(32, 32, 5)
        ch2 = rand(32, 32, 5)
        ch3 = rand(32, 32, 5)

        v = smlmview((ch1, ch2, ch3); names=("A", "B", "C"), show=false)

        @test length(v.channels) == 3
        @test length(v.channel_visible) == 3
        @test length(v.colors) == 3

        # Toggle channel visibility
        v.channel_visible[1][] = false
        @test v.channel_visible[1][] == false
    end

    @testset "smlmview composite custom colors" begin
        ch1 = rand(32, 32)
        ch2 = rand(32, 32)
        ch3 = rand(32, 32)

        colors = CHANNEL_COLOR_PRESETS[:rgb]
        v = smlmview((ch1, ch2, ch3); colors=colors, show=false)

        @test v.colors == colors
    end

    @testset "smlmview composite validation" begin
        # Need at least 2 channels
        @test_throws ArgumentError smlmview((rand(10, 10),); show=false)

        # Max 3 channels - throws BoundsError from color lookup before validation
        @test_throws BoundsError smlmview((rand(10,10), rand(10,10), rand(10,10), rand(10,10)); show=false)

        # Size mismatch should error
        @test_throws ArgumentError smlmview((rand(10, 10), rand(20, 20)); show=false)
    end
end
