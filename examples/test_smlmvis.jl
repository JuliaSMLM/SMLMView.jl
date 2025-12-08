# Test if SMLMVis works in this environment
# Run this with VSCode play button

using Pkg
Pkg.activate("/home/kalidke/julia_shared_dev/SMLMVis/dev")

using WGLMakie
import WGLMakie.Bonito
Bonito.configure_server!(listen_port=9284, listen_url="127.0.0.1")

using SMLMVis
using SMLMVis.Interact

# Generate test data
data = rand(Float32, 256, 256, 10)
println("Generated test data: $(size(data))")

# Try to display
fig = stack_viewer(data; title="SMLMVis Test")
display(fig)

println("SMLMVis test - check if figure appears")
