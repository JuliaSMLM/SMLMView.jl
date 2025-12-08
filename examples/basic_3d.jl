# Basic 3D viewer example
# Run this in VSCode with the play button

using Pkg
Pkg.activate(dirname(@__DIR__))

using WGLMakie
import WGLMakie.Bonito

# Configure Bonito BEFORE creating any figures
# Port 8080 is in VSCode's WebSocket-supported port list
port = 8080
Bonito.configure_server!(listen_port=port, listen_url="127.0.0.1")
println("Bonito configured on port $port")

using SMLMView

# Create a 64×128×256 3D test volume (64 rows, 128 cols, 10 z-slices)
# Each slice has distinct features for easy verification
function make_test_volume()
    nrows, ncols, nz = 64, 128, 10
    vol = zeros(Float64, nrows, ncols, nz)

    # Base gradient: each slice has different intensity
    for z in 1:nz
        vol[:, :, z] .= 100.0 * z  # slice 1 is dimmer, slice 10 is brighter
    end

    # Mark (1,1) corner in all slices - top-left should be visible
    for z in 1:nz
        vol[1, 1, z] += 500.0
    end

    # Add z-dependent spots: spot moves across slices
    for z in 1:nz
        # Spot position varies with z
        r0 = 20 + z * 3
        c0 = 30 + z * 8
        sigma = 2.0
        amplitude = 1000.0

        for r in max(1, r0-10):min(nrows, r0+10)
            for c in max(1, c0-10):min(ncols, c0+10)
                d2 = (r - r0)^2 + (c - c0)^2
                vol[r, c, z] += amplitude * exp(-d2 / (2 * sigma^2))
            end
        end
    end

    # Add some static spots that appear in all slices
    for _ in 1:10
        r0, c0 = rand(10:nrows-10), rand(10:ncols-10)
        sigma = 1.5
        amplitude = 500.0

        for z in 1:nz
            for r in max(1, r0-8):min(nrows, r0+8)
                for c in max(1, c0-8):min(ncols, c0+8)
                    d2 = (r - r0)^2 + (c - c0)^2
                    vol[r, c, z] += amplitude * exp(-d2 / (2 * sigma^2))
                end
            end
        end
    end

    return vol
end

data = make_test_volume()
nrows, ncols, nz = size(data)
println("Created $(size(data)) test volume ($(nrows) rows × $(ncols) cols × $(nz) slices)")
println("Pixel (1,1,1) = $(data[1,1,1]) - should be visible at TOP-LEFT")

v = smlmview(data; title="3D Test Volume", colormap=:inferno)

println("\nViewer launched - check VSCode plot pane")
println("Verify: TOP-LEFT should have bright corner (pixel 1,1)")
println("Verify: Image is WIDE (128 cols) and SHORT (64 rows)")
println("\nKeyboard shortcuts:")
println("  j/l: Previous/Next z-slice")
println("  i/o: Zoom in/out")
println("  e/s/d/f: Pan up/left/down/right")
println("  r: Reset view")
