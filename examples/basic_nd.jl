# Basic ND viewer example
# Tests 4D data with display dimension switching
#
# Run this in VSCode with the Julia extension's play button
# The figure will appear in the plot pane
# (Running from command line won't show the figure)

using Pkg
Pkg.activate(@__DIR__)

using Revise
using SMLMView

# Create a 4D test dataset: (Y=64, X=128, Z=10, T=5)
# Each dimension has distinct features to verify orientation
function make_test_4d()
    println("Generating 64×128×10×5 test volume...")
    data = zeros(Float64, 64, 128, 10, 5)

    # Fill with gradients that identify each dimension
    for t in 1:5, z in 1:10, x in 1:128, y in 1:64
        # Base: combination of all indices (for identification)
        data[y, x, z, t] = 100.0 + y + x/2 + z*10 + t*50
    end

    # Mark ONLY top-left corner (1,1,1,1) for orientation check
    # This single bright pixel verifies (1,1,...) appears at screen top-left
    data[1, 1, 1, 1] = 10000.0

    # Add a spot that moves with Z (visible in YZ or XZ views)
    for t in 1:5, z in 1:10
        y0 = 20 + z * 4
        x0 = 64
        if y0 <= 64
            for dy in -3:3, dx in -3:3
                y = clamp(y0 + dy, 1, 64)
                x = clamp(x0 + dx, 1, 128)
                data[y, x, z, t] += 1000.0 * exp(-(dy^2 + dx^2) / 4)
            end
        end
    end

    # Add a spot that moves with T
    for t in 1:5, z in 1:10
        y0 = 32
        x0 = 20 + t * 20
        if x0 <= 128
            for dy in -3:3, dx in -3:3
                y = clamp(y0 + dy, 1, 64)
                x = clamp(x0 + dx, 1, 128)
                data[y, x, z, t] += 800.0 * exp(-(dy^2 + dx^2) / 4)
            end
        end
    end

    println("Volume generated: $(Base.summarysize(data) ÷ 1024) KB")
    return data
end

data = make_test_4d()
println("Created 4D test data: $(size(data))")
println("  dim 1 (Y): 64 pixels")
println("  dim 2 (X): 128 pixels")
println("  dim 3 (Z): 10 slices")
println("  dim 4 (T): 5 frames")

println("\nLaunching viewer...")
v = smlmview(data; colormap=:inferno, dim_names=("Y", "X", "Z", "T"))

println("\nViewer launched!")
println("\nKeyboard shortcuts:")
println("  1-4 + 1-4: Set display dims (e.g., press '1' then '3' for YZ view)")
println("  v: Cycle through all dim combinations")
println("  t: Transpose (swap row/col dims)")
println("  j/l: Navigate first slider dimension")
println("  i/o: Zoom in/out")
println("  e/s/d/f: Pan")
println("  r: Reset view")
println("\nTry these views:")
println("  Press 1, 2 → YX view (default)")
println("  Press 1, 3 → YZ view (spot moves diagonally)")
println("  Press 2, 3 → XZ view")
println("  Press 1, 4 → YT view (spot moves horizontally)")
