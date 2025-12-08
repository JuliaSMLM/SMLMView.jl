# Test WGLMakie in browser (not plot pane)
# After running, open http://localhost:9385 in your browser

using Pkg
Pkg.activate(dirname(@__DIR__))

using WGLMakie
import WGLMakie.Bonito

port = 9385
Bonito.configure_server!(listen_port=port, listen_url="127.0.0.1")

# Create figure but DON'T call display - we'll serve it
fig = Figure(size=(600, 500))
ax = Axis(fig[1,1], title="Browser Test")
heatmap!(ax, rand(100, 100), colormap=:viridis)

# Serve directly via Bonito App
app = Bonito.App() do
    return fig
end

# Start server and print URL
server = Bonito.Server(app, "127.0.0.1", port)
url = "http://127.0.0.1:$port"
println("\n" * "="^50)
println("Server running at: $url")
println("Open this URL in your browser")
println("(Make sure port $port is forwarded in VSCode)")
println("="^50 * "\n")

# Keep alive
println("Press Ctrl+C to stop...")
wait()
