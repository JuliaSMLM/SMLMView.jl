# GATTA DNA Ruler viewer example
# Loads real SMLM data from SMLMAnalysis/data

using Pkg
Pkg.activate(@__DIR__)

using Revise
using SMLMView
using HDF5

# Data path (via symlink in SMLMAnalysis/data)
datapath = joinpath(dirname(@__DIR__), "..", "SMLMAnalysis", "data", "gatta_ruler",
    "2025-10-23", "20R-ruler-0.1exp-TIRF-onlyZFocusLockDT1-1ch--2025-10-23_11-29-25.h5")

# Load subset of frames for memory testing
nframes_to_load = 5000
println("Loading $nframes_to_load frames from H5 file...")

data = h5open(datapath, "r") do f
    dset = f["Main/data"]
    fullsize = size(dset)
    println("Full dataset: $(fullsize) $(eltype(dset))")
    dset[:, :, 1:nframes_to_load]
end

println("Loaded: $(size(data)) $(eltype(data))")
raw_mb = Base.summarysize(data) ÷ 1024^2
println("Raw data memory: $raw_mb MB")
println("Expected Float64 memory: $(raw_mb * 4) MB (sanitize_data_3d converts to Float64)")

GC.gc()
println("Memory before viewer: $(Sys.free_memory() ÷ 1024^2) MB free")

# View the data
nframes = size(data, 3)
println("\nLaunching viewer...")
v = smlmview(data; title="GATTA DNA Ruler ($nframes frames)", colormap=:inferno)

println("\nControls:")
println("  j/l: Previous/Next frame")
println("  i/o: Zoom in/out")
println("  e/s/d/f: Pan")
println("  r: Reset view")
println("  Slider: Navigate frames")
