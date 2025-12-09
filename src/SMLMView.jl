module SMLMView

using WGLMakie
import WGLMakie.Bonito
using Observables
using Statistics
using Printf

export smlmview
export get_keybindings, set_keybinding!, reset_keybindings!, list_keys, list_actions
export configure_display!

# Include files in dependency order
include("types.jl")
include("keybindings.jl")
include("display.jl")
include("tools.jl")
include("viewer.jl")

function __init__()
    load_keybindings!()
end

end # module
