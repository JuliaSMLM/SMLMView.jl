# 3D Three-Channel Composite Viewer
#
# Tests composite viewer with 3 channels and z-navigation
# Run this in VSCode with the Julia extension's play button

using Pkg
Pkg.activate(@__DIR__)

using Revise
using SMLMView

# Create 3D test channels (with z variation)
function make_test_channels_3d(; nrows=128, ncols=128, nz=20)
    ch1 = zeros(Float64, nrows, ncols, nz)
    ch2 = zeros(Float64, nrows, ncols, nz)
    ch3 = zeros(Float64, nrows, ncols, nz)

    # Channel 1: Moving spot (Cyan) - moves diagonally across z
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

    # Channel 2: Static spot (Magenta) - stays in same position
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
println("3D Three-Channel Composite Viewer")
println("="^60)

ch1, ch2, ch3 = make_test_channels_3d()
println("Channel sizes: $(size(ch1)), $(size(ch2)), $(size(ch3))")
v = smlmview((ch1, ch2, ch3); title="3-Channel Composite (3D)")
println("Viewer launched!")

println("\nColors: Cyan (ch1) + Magenta (ch2) + Yellow (ch3)")
println("Note: Channel 1 (cyan) moves diagonally across z")
println("      Channel 2 (magenta) is static")
println("      Channel 3 (yellow) appears only in middle z slices")

println("\nKeyboard shortcuts:")
println("  1/2/3: Toggle channel visibility")
println("  j/l: Previous/Next z-slice")
println("  m: Cycle mapping (linear/log)")
println("  g: Toggle global/slice stretch")
println("  i/o: Zoom in/out")
println("  e/s/d/f: Pan")
println("  r: Reset view")
