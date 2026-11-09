# Simulated SMLM movie viewer example
#
# A raw camera movie of blinking DNA-ruler-like patterns (three marks 40 nm apart),
# simulated with SMLMSim: pattern, labeling, blinking kinetics and Poisson-noise
# camera frames. The frames are stored as UInt16 counts, as a camera writes them.
# Raise nframes for a memory and speed check on a long movie.

using Pkg
Pkg.activate(@__DIR__)

using Revise
using SMLMView
using SMLMSim
using MicroscopePSFs

nframes = 2000
camera = IdealCamera(128, 128, 0.1)  # 128×128 pixels, 100 nm pixels
params = StaticSMLMConfig(density=1.0, σ_psf=0.13, nframes=nframes, ndatasets=1)
fluor = GenericFluor(; photons=1e5, k_off=10.0, k_on=0.1)  # photons/s; on ~0.1 s, back on every ~10 s
smld, _ = simulate(params; pattern=Nanoruler2D(n=3, spacing=0.04), molecule=fluor, camera=camera)

println("Rendering $nframes camera frames...")
images, _ = gen_images(smld, GaussianPSF(0.13); support=0.5, bg=10.0, poisson_noise=true)
movie = round.(UInt16, images)
println("Movie: $(size(movie)) $(eltype(movie)), $(Base.summarysize(movie) ÷ 1024^2) MB")

# View the movie
v = smlmview(movie; title="Simulated DNA rulers ($nframes frames)", colormap=:inferno)

println("\nControls:")
println("  j/l: Previous/Next frame")
println("  i/o: Zoom in/out")
println("  e/s/d/f: Pan")
println("  r: Reset view")
println("  Slider: Navigate frames")
