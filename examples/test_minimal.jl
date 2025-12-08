# Minimal WGLMakie test - no manual Bonito configuration
# Let WGLMakie auto-configure everything

using Pkg
Pkg.activate(dirname(@__DIR__))

using WGLMakie
WGLMakie.activate!()

# Simple test
fig = Figure()
ax = Axis(fig[1,1], title="Minimal Test")
heatmap!(ax, rand(50, 50))

# Just return the figure - let REPL/VSCode handle display
fig
