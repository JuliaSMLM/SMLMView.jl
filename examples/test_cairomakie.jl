# Fallback: Use CairoMakie for static display (no Bonito needed)
using Pkg
Pkg.activate(dirname(@__DIR__))

using CairoMakie
CairoMakie.activate!()

# This should work - no WebSocket/Bonito involved
fig = Figure()
ax = Axis(fig[1,1], title="CairoMakie Test")
heatmap!(ax, rand(100, 100), colormap=:viridis)
fig
