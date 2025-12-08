# Test with port 8080 - WebSocket-supported port in VSCode Dev Tunnels
# Dev Tunnels only supports WebSocket on specific ports:
# 443, 1027, 1111, 1234, 1313, 3000, 3001, 4000, 4200, 5000, 5001,
# 5173, 5174, 5500, 5555, 6006, 7016, 7027, 7038, 7092, 7110, 7137,
# 7233, 7258, 7777, 7860, 8000, 8050, 8080, 8081, 8089, 8888, 9291

using Pkg
Pkg.activate(dirname(@__DIR__))

using WGLMakie
import WGLMakie.Bonito

# Use port 8080 - supported for WebSocket forwarding
port = 8080
Bonito.configure_server!(listen_port=port, listen_url="127.0.0.1")

# Simple test
fig = Figure()
ax = Axis(fig[1,1], title="Port 8080 Test")
heatmap!(ax, rand(100, 100), colormap=:viridis)

display(fig)

println("\nServer on port $port (WebSocket-supported)")
println("Make sure port $port is forwarded in VSCode")
