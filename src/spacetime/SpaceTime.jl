# Space-time viewer: a 3D (x, y, frame) WGLMakie scene of raw voxels and tracks
# with a linked 2D frame inspector. An internal submodule so its helpers stay
# out of SMLMView's namespace; `SMLMView.spacetime` is the entry point.
module SpaceTime

using WGLMakie
import WGLMakie.Makie
import WGLMakie.Bonito

include("schema.jl")
include("geometry.jl")
include("tracks.jl")
include("inspector.jl")
include("figure.jl")
include("launch.jl")

end # module
