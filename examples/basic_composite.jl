# Multi-channel composite viewer test
#
# Tests the multi-channel composite viewer with 2-3 channels
# Run this in VSCode with the Julia extension's play button

using Pkg
Pkg.activate(@__DIR__)

using Revise
using SMLMView

# Create test channels with different features
function make_test_channels(; nrows=256, ncols=256)
    # Channel 1: Spots in upper-left quadrant (Cyan)
    ch1 = zeros(Float64, nrows, ncols)
    for _ in 1:20
        r0, c0 = rand(20:nrows÷2-20), rand(20:ncols÷2-20)
        sigma = 8.0
        for r in max(1, r0-30):min(nrows, r0+30)
            for c in max(1, c0-30):min(ncols, c0+30)
                d2 = (r - r0)^2 + (c - c0)^2
                ch1[r, c] += 1000.0 * exp(-d2 / (2 * sigma^2))
            end
        end
    end

    # Channel 2: Spots in lower-right quadrant (Magenta)
    ch2 = zeros(Float64, nrows, ncols)
    for _ in 1:20
        r0, c0 = rand(nrows÷2+20:nrows-20), rand(ncols÷2+20:ncols-20)
        sigma = 8.0
        for r in max(1, r0-30):min(nrows, r0+30)
            for c in max(1, c0-30):min(ncols, c0+30)
                d2 = (r - r0)^2 + (c - c0)^2
                ch2[r, c] += 1000.0 * exp(-d2 / (2 * sigma^2))
            end
        end
    end

    # Channel 3: Spots in center (overlapping region) (Yellow)
    ch3 = zeros(Float64, nrows, ncols)
    for _ in 1:15
        r0, c0 = rand(nrows÷4:3*nrows÷4), rand(ncols÷4:3*ncols÷4)
        sigma = 10.0
        for r in max(1, r0-30):min(nrows, r0+30)
            for c in max(1, c0-30):min(ncols, c0+30)
                d2 = (r - r0)^2 + (c - c0)^2
                ch3[r, c] += 800.0 * exp(-d2 / (2 * sigma^2))
            end
        end
    end

    return ch1, ch2, ch3
end

# Create 3D test channels (with z variation)
function make_test_channels_3d(; nrows=128, ncols=128, nz=20)
    ch1 = zeros(Float64, nrows, ncols, nz)
    ch2 = zeros(Float64, nrows, ncols, nz)
    ch3 = zeros(Float64, nrows, ncols, nz)

    # Channel 1: Moving spot (Cyan)
    for z in 1:nz
        r0 = nrows÷4 + z * 2
        c0 = ncols÷4 + z * 2
        sigma = 6.0
        for r in max(1, r0-25):min(nrows, r0+25)
            for c in max(1, c0-25):min(ncols, c0+25)
                d2 = (r - r0)^2 + (c - c0)^2
                ch1[r, c, z] = 1000.0 * exp(-d2 / (2 * sigma^2))
            end
        end
    end

    # Channel 2: Static spot (Magenta)
    r0, c0 = 3*nrows÷4, 3*ncols÷4
    sigma = 8.0
    for z in 1:nz
        for r in max(1, r0-30):min(nrows, r0+30)
            for c in max(1, c0-30):min(ncols, c0+30)
                d2 = (r - r0)^2 + (c - c0)^2
                ch2[r, c, z] = 800.0 * exp(-d2 / (2 * sigma^2))
            end
        end
    end

    # Channel 3: Appears in middle z slices only (Yellow)
    for z in nz÷3:2*nz÷3
        r0, c0 = nrows÷2, ncols÷2
        sigma = 12.0
        intensity = 600.0 * sin(π * (z - nz÷3) / (nz÷3))
        for r in max(1, r0-35):min(nrows, r0+35)
            for c in max(1, c0-35):min(ncols, c0+35)
                d2 = (r - r0)^2 + (c - c0)^2
                ch3[r, c, z] = intensity * exp(-d2 / (2 * sigma^2))
            end
        end
    end

    return ch1, ch2, ch3
end

println("="^60)
println("Multi-channel Composite Viewer Test")
println("="^60)

# Test 1: 2D two-channel
println("\n--- Test 1: 2D Two-Channel ---")
ch1, ch2, _ = make_test_channels()
println("Channel sizes: $(size(ch1)), $(size(ch2))")
v1 = smlmview((ch1, ch2); title="2-Channel Composite (2D)")
println("Viewer launched!")

println("\nKeyboard shortcuts:")
println("  1/2/3: Toggle channel visibility")
println("  m: Cycle mapping (linear/log)")
println("  g: Toggle global/slice stretch")
println("  i/o: Zoom in/out")
println("  e/s/d/f: Pan")
println("  r: Reset view")

println("\n--- Press Enter to continue to 3-channel test ---")
readline()

# Test 2: 2D three-channel
println("\n--- Test 2: 2D Three-Channel ---")
ch1, ch2, ch3 = make_test_channels()
println("Channel sizes: $(size(ch1)), $(size(ch2)), $(size(ch3))")
v2 = smlmview((ch1, ch2, ch3); title="3-Channel Composite (2D)")
println("Viewer launched!")

println("\nColors: Cyan (ch1) + Magenta (ch2) + Yellow (ch3)")
println("Overlaps will show: C+M=Blue, C+Y=Green, M+Y=Red, C+M+Y=White")

println("\n--- Press Enter to continue to 3D test ---")
readline()

# Test 3: 3D three-channel
println("\n--- Test 3: 3D Three-Channel ---")
ch1_3d, ch2_3d, ch3_3d = make_test_channels_3d()
println("Channel sizes: $(size(ch1_3d)), $(size(ch2_3d)), $(size(ch3_3d))")
v3 = smlmview((ch1_3d, ch2_3d, ch3_3d); title="3-Channel Composite (3D)")
println("Viewer launched!")

println("\nAdditional shortcuts for 3D:")
println("  j/l: Previous/Next z-slice")
println("\nNote: Channel 1 (cyan) moves diagonally across z")
println("      Channel 2 (magenta) is static")
println("      Channel 3 (yellow) appears only in middle z slices")

println("\n--- All tests complete ---")
