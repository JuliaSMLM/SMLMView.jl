# Test Bonito alone (no WGLMakie)
using Pkg
Pkg.activate(dirname(@__DIR__))

# Load Bonito directly from WGLMakie's dependency
using WGLMakie
import WGLMakie.Bonito

println("Bonito version check...")
println("Bonito loaded: ", isdefined(Bonito, :App))

# Simple HTML app - no WebGL
app = Bonito.App() do
    return Bonito.DOM.div(
        Bonito.DOM.h1("Bonito Test"),
        Bonito.DOM.p("If you see this, Bonito HTTP serving works!"),
        style="font-family: sans-serif; padding: 20px;"
    )
end

port = 9385
println("\nStarting server on port $port...")
server = Bonito.Server(app, "127.0.0.1", port)
println("Server started!")
println("Open http://localhost:$port in browser")
println("Press Ctrl+C to stop")

wait()
