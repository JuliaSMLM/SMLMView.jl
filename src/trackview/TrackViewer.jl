# Track viewer: a 3D (x, y, frame) WGLMakie scene of raw voxels and tracks
# with a linked 2D frame inspector. An internal submodule so its helpers stay
# out of SMLMView's namespace; `SMLMView.trackview` is the entry point.
module TrackViewer

using WGLMakie
import WGLMakie.Makie
import Bonito

include("schema.jl")
include("geometry.jl")
include("tracks.jl")
include("inspector.jl")
include("figure.jl")
include("launch.jl")

# Public, not exported. `public` needs Julia 1.11; 1.10 must still parse this file.
@static if VERSION >= v"1.11.0-DEV.469"
    eval(Meta.parse("public example_scene, validate_scene, scene_schema"))
end

end # module
