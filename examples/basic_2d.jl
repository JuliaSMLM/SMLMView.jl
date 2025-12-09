# Basic 2D viewer example
# Run this in VSCode with the play button

using Pkg
Pkg.activate(dirname(@__DIR__))

using SMLMView
# Note: SMLMView auto-configures Bonito on first smlmview() call

# Create a 128×256 rectangular test image (128 rows, 256 columns)
# Display should be: width=256 (columns), height=128 (rows)
# Top-left pixel (1,1) should be bright to verify orientation
function make_test_image()
    nrows, ncols = 128, 256
    img = zeros(Float64, nrows, ncols)

    # Mark (1,1) pixel distinctly - top-left should be bright
    img[1, 1] = 10000.0

    # Add a row gradient: row 1 brighter than row 128
    for r in 1:nrows
        img[r, :] .+= 100.0 * (nrows - r + 1) / nrows
    end

    # Add a column gradient: col 1 brighter than col 256
    for c in 1:ncols
        img[:, c] .+= 50.0 * (ncols - c + 1) / ncols
    end

    # Add some Gaussian spots
    for _ in 1:30
        r0, c0 = rand(10:nrows-10), rand(10:ncols-10)
        sigma = 1.5 + rand()
        amplitude = 500 + 1000 * rand()

        for r in max(1, r0-8):min(nrows, r0+8)
            for c in max(1, c0-8):min(ncols, c0+8)
                d2 = (r - r0)^2 + (c - c0)^2
                img[r, c] += amplitude * exp(-d2 / (2 * sigma^2))
            end
        end
    end

    return img
end

data = make_test_image()
println("Created $(size(data)) test image ($(size(data,1)) rows × $(size(data,2)) cols)")
println("Pixel (1,1) = $(data[1,1]) - should be bright at TOP-LEFT")

v = smlmview(data; title="Orientation Test", colormap=:inferno)

println("\nViewer launched - check VSCode plot pane")
println("Verify: TOP-LEFT should be BRIGHT (pixel 1,1)")
println("Verify: Image is WIDE (256) and SHORT (128)")
println("Hover to confirm coordinates match expectations")
