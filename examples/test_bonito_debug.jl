# Debug Bonito server with verbose output
using Pkg
Pkg.activate(dirname(@__DIR__))

using WGLMakie
import WGLMakie.Bonito

println("Bonito version: ", pkgversion(Bonito))
println("Julia version: ", VERSION)

# Simple HTML app
app = Bonito.App() do
    return Bonito.DOM.div(
        Bonito.DOM.h1("Debug Test"),
        Bonito.DOM.p("Testing Bonito server"),
        style="padding: 20px;"
    )
end

port = 9385
println("\nStarting server with verbose=1 on port $port...")

# Try with verbose flag to see what's happening
server = Bonito.Server(app, "127.0.0.1", port; verbose=1)

println("Server object created: ", server)
println("Open http://localhost:$port in browser")
println("Watch for debug output above...")
println("Press Ctrl+C to stop")

wait()
