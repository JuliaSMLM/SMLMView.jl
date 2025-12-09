# Basic 3D viewer example
# Run this in VSCode with the play button

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

    # Mark top-left corner with bright "L" shape (rows 1-10, cols 1-10)
    for z in 1:nz
        # Vertical bar of L (column 1, rows 1-10)
        for r in 1:10
            vol[r, 1, z] = 3000.0
            vol[r, 2, z] = 3000.0
        end
        # Horizontal bar of L (row 10, cols 1-10)
        for c in 1:10
            vol[10, c, z] = 3000.0
            vol[9, c, z] = 3000.0
        end
        # Extra bright corner at (1,1)
        vol[1, 1, z] = 5000.0
        vol[1, 2, z] = 5000.0
        vol[2, 1, z] = 5000.0
    end

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
println("  - Bright 'L' shape should be at TOP-LEFT")
println("  - Image should be WIDE (256 cols) and SHORT (128 rows)")
println("\nKeyboard shortcuts:")
println("  j/l: Previous/Next z-slice (hold for rapid navigation)")
println("  i/o: Zoom in/out")
println("  e/s/d/f: Pan up/left/down/right")
println("  r: Reset view")
println("\nNote: 128×256×100 = ~25 MB Float64 data")
