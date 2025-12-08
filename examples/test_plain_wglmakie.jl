# Test plain WGLMakie without SMLMView
using Pkg
Pkg.activate(dirname(@__DIR__))

using WGLMakie
import WGLMakie.Bonito

# Key fix for VSCode remote: use proxy_url="." for relative URLs
port = 9385
Bonito.configure_server!(listen_port=port, listen_url="127.0.0.1", proxy_url=".")

# Simple test - does this display?
fig = Figure()
ax = Axis(fig[1,1], title="Test")
heatmap!(ax, rand(100, 100))
display(fig)

println("Plain WGLMakie test - check if figure appears in plot pane")
