# Big 3D viewer stress test
#
# Tests viewer responsiveness with large 2k×2k×100 dataset
# Run this in VSCode with the Julia extension's play button

using Pkg
Pkg.activate(@__DIR__)

using Revise
using SMLMView

# Create a 2000×2000×100 3D test volume for stress testing
function make_big_volume(; nrows=2000, ncols=2000, nz=100)
    println("Generating $(nrows)×$(ncols)×$(nz) test volume...")
    println("This will be $(nrows * ncols * nz * 8 ÷ 1024^3) GB of Float64 data")

    vol = zeros(Float64, nrows, ncols, nz)

    # Base gradient: each slice has different intensity
    for z in 1:nz
        vol[:, :, z] .= 50.0 + 5.0 * z
    end

    # Mark top-left corner (1,1,1) for orientation check
    vol[1, 1, 1] = 10000.0

    # Add z-dependent moving spot (traces diagonal path)
    for z in 1:nz
        r0 = mod1(500 + z * 10, nrows - 100)
        c0 = mod1(500 + z * 10, ncols - 100)
        sigma = 20.0
        amplitude = 2000.0

        for r in max(1, r0-60):min(nrows, r0+60)
            for c in max(1, c0-60):min(ncols, c0+60)
                d2 = (r - r0)^2 + (c - c0)^2
                vol[r, c, z] += amplitude * exp(-d2 / (2 * sigma^2))
            end
        end
    end

    # Add static random spots (visible in all frames)
    for _ in 1:100
        r0, c0 = rand(100:nrows-100), rand(100:ncols-100)
        sigma = 15.0
        amplitude = 800.0

        for z in 1:nz
            for r in max(1, r0-50):min(nrows, r0+50)
                for c in max(1, c0-50):min(ncols, c0+50)
                    d2 = (r - r0)^2 + (c - c0)^2
                    vol[r, c, z] += amplitude * exp(-d2 / (2 * sigma^2))
                end
            end
        end
    end

    println("Volume generated: $(Base.summarysize(vol) ÷ 1024^3) GB")
    return vol
end

@time data = make_big_volume()
nrows, ncols, nz = size(data)
println("Created $(size(data)) test volume")
println("Memory: $(Base.summarysize(data) ÷ 1024^2) MB")

println("\nLaunching viewer...")
@time v = smlmview(data; title="Stress Test: $(nrows)×$(ncols)×$(nz)", colormap=:inferno)

println("\nViewer launched - test responsiveness!")
println("Hold 'l' to rapidly advance through slices")
println("Hold 'j' to go backwards")
println("\nKeyboard shortcuts:")
println("  j/l: Previous/Next z-slice")
println("  g: Toggle global/slice stretch")
println("  c: Cycle colormap")
println("  m: Cycle mapping")
println("  i/o: Zoom in/out")
println("  e/s/d/f: Pan")
println("  r: Reset view")
