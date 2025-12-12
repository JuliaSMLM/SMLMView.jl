# 2D Two-Channel Composite Viewer
#
# Tests composite viewer with 2 channels (Cyan + Magenta)
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

    return ch1, ch2
end

println("="^60)
println("2D Two-Channel Composite Viewer")
println("="^60)

ch1, ch2 = make_test_channels()
println("Channel sizes: $(size(ch1)), $(size(ch2))")
v = smlmview((ch1, ch2); title="2-Channel Composite (2D)")
println("Viewer launched!")

println("\nColors: Cyan (ch1) + Magenta (ch2)")
println("Overlaps will show: C+M = Blue")

println("\nKeyboard shortcuts:")
println("  1/2: Toggle channel visibility")
println("  m: Cycle mapping (linear/log)")
println("  g: Toggle global/slice stretch")
println("  i/o: Zoom in/out")
println("  e/s/d/f: Pan")
println("  r: Reset view")
