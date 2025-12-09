# Basic 3D viewer example
#
# Run this in VSCode with the Julia extension's play button
# The figure will appear in the plot pane
# (Running from command line won't show the figure)

using Pkg
Pkg.activate(@__DIR__)

using Revise
using SMLMView
# Note: SMLMView auto-configures Bonito on first smlmview() call

# Create a 128×256×100 3D test volume for performance testing
# Each slice has distinct features - spots move across z
function make_test_volume(; nrows=128, ncols=256, nz=100)
    println("Generating $(nrows)×$(ncols)×$(nz) test volume...")
    vol = zeros(Float64, nrows, ncols, nz)

    # Base gradient: each slice has different intensity
    for z in 1:nz
        vol[:, :, z] .= 50.0 + 5.0 * z  # gradual increase
    end

    # Mark ONLY top-left corner (1,1,1) for orientation check
    # This single bright pixel verifies (1,1,...) appears at screen top-left
    vol[1, 1, 1] = 10000.0

    # Add z-dependent moving spot (traces diagonal path)
    for z in 1:nz
        # Spot position varies with z (wraps around)
        r0 = mod1(50 + z * 2, nrows - 20)
        c0 = mod1(50 + z * 2, ncols - 20)
        sigma = 3.0
        amplitude = 2000.0

        for r in max(1, r0-15):min(nrows, r0+15)
            for c in max(1, c0-15):min(ncols, c0+15)
                d2 = (r - r0)^2 + (c - c0)^2
                vol[r, c, z] += amplitude * exp(-d2 / (2 * sigma^2))
            end
        end
    end

    # Add static random spots (visible in all frames)
    for _ in 1:50
        r0, c0 = rand(15:nrows-15), rand(15:ncols-15)
        sigma = 2.0
        amplitude = 800.0

        for z in 1:nz
            for r in max(1, r0-10):min(nrows, r0+10)
                for c in max(1, c0-10):min(ncols, c0+10)
                    d2 = (r - r0)^2 + (c - c0)^2
                    vol[r, c, z] += amplitude * exp(-d2 / (2 * sigma^2))
                end
            end
        end
    end

    println("Volume generated: $(Base.summarysize(vol) ÷ 1024^2) MB")
    return vol
end

data = make_test_volume()
nrows, ncols, nz = size(data)
println("Created $(size(data)) test volume ($(nrows) rows × $(ncols) cols × $(nz) slices)")
println("Pixel (1,1,1) = $(data[1,1,1]) - should be visible at TOP-LEFT")

println("\nLaunching viewer...")
v = smlmview(data; title="Performance Test: $(nz) frames", colormap=:inferno)

println("\nViewer launched - test slice navigation speed!")
println("Hold 'l' to rapidly advance through slices")
println("Hold 'j' to go backwards")
println("\nOrientation check:")
println("  - Single bright pixel at (1,1,1) should be at TOP-LEFT (only visible on slice 1)")
println("  - Image should be WIDE (256 cols) and SHORT (128 rows)")
println("\nKeyboard shortcuts:")
println("  j/l: Previous/Next z-slice (hold for rapid navigation)")
println("  1-3 + 1-3: Set display dims (e.g., '1' '3' for YZ view)")
println("  v: Cycle through all dim combinations")
println("  t: Transpose display dims")
println("  i/o: Zoom in/out")
println("  e/s/d/f: Pan up/left/down/right")
println("  r: Reset view")
println("\nNote: 128×256×100 = ~25 MB Float64 data")
