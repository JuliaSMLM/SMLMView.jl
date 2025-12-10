module SMLMView

using WGLMakie
import WGLMakie.Bonito
using Observables
using Statistics
using Printf

# Import color accessors from Makie's ColorTypes
using WGLMakie.Makie: red, green, blue

export smlmview
export get_keybindings, set_keybinding!, reset_keybindings!, list_keys, list_actions
export configure_display!
export DEFAULT_CHANNEL_COLORS, CHANNEL_COLOR_PRESETS

# Include files in dependency order
include("types.jl")
include("keybindings.jl")
include("display.jl")
include("tools.jl")
include("viewer.jl")
include("viewer_composite.jl")

function __init__()
    load_keybindings!()
end

end # module
