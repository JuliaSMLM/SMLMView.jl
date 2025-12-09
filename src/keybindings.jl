#=============================================================================
# Keybindings configuration using Preferences.jl
=============================================================================#

using Preferences

# Keyboard comes from WGLMakie.Makie (already loaded by parent module)
const Keyboard = WGLMakie.Makie.Keyboard

# Default keybindings (action => key string)
const DEFAULT_KEYBINDINGS = Dict{String,String}(
    "zoom_in"       => "i",
    "zoom_out"      => "o",
    "reset"         => "r",
    "pan_up"        => "e",
    "pan_down"      => "d",
    "pan_left"      => "s",
    "pan_right"     => "f",
    "slice_prev"    => "j",
    "slice_next"    => "l",
    "colormap_cycle"=> "c",
    "mapping_cycle" => "m",
)

# Runtime keybindings storage (action => Keyboard.Button)
const KEYBINDINGS = Dict{String,Keyboard.Button}()

# Map string to Makie Keyboard.Button
const KEY_MAP = Dict{String,Keyboard.Button}(
    "a" => Keyboard.a, "b" => Keyboard.b, "c" => Keyboard.c,
    "d" => Keyboard.d, "e" => Keyboard.e, "f" => Keyboard.f,
    "g" => Keyboard.g, "h" => Keyboard.h, "i" => Keyboard.i,
    "j" => Keyboard.j, "k" => Keyboard.k, "l" => Keyboard.l,
    "m" => Keyboard.m, "n" => Keyboard.n, "o" => Keyboard.o,
    "p" => Keyboard.p, "q" => Keyboard.q, "r" => Keyboard.r,
    "s" => Keyboard.s, "t" => Keyboard.t, "u" => Keyboard.u,
    "v" => Keyboard.v, "w" => Keyboard.w, "x" => Keyboard.x,
    "y" => Keyboard.y, "z" => Keyboard.z,
    "0" => Keyboard._0, "1" => Keyboard._1, "2" => Keyboard._2,
    "3" => Keyboard._3, "4" => Keyboard._4, "5" => Keyboard._5,
    "6" => Keyboard._6, "7" => Keyboard._7, "8" => Keyboard._8,
    "9" => Keyboard._9,
    "up" => Keyboard.up, "down" => Keyboard.down,
    "left" => Keyboard.left, "right" => Keyboard.right,
    "space" => Keyboard.space, "enter" => Keyboard.enter,
    "tab" => Keyboard.tab, "escape" => Keyboard.escape,
    "backspace" => Keyboard.backspace,
    "minus" => Keyboard.minus, "equal" => Keyboard.equal,
    "left_bracket" => Keyboard.left_bracket,
    "right_bracket" => Keyboard.right_bracket,
)

# Reverse map for display
const KEY_NAMES = Dict{Keyboard.Button,String}(v => k for (k, v) in KEY_MAP)

"""
Convert key string to Keyboard.Button.
"""
function string_to_key(s::String)
    key = get(KEY_MAP, lowercase(s), nothing)
    if isnothing(key)
        @warn "Unknown key '$s', using default"
        return Keyboard.unknown
    end
    return key
end

"""
Convert Keyboard.Button to display string.
"""
function key_to_string(k::Keyboard.Button)
    return get(KEY_NAMES, k, "unknown")
end

"""
Load keybindings from Preferences, falling back to defaults.
Called during module initialization.
"""
function load_keybindings!()
    empty!(KEYBINDINGS)
    for (action, default_key) in DEFAULT_KEYBINDINGS
        key_str = @load_preference(action, default_key)
        KEYBINDINGS[action] = string_to_key(key_str)
    end
    return nothing
end

"""
    get_keybindings() -> Dict{String,String}

Return current keybindings as action => key string pairs.
"""
function get_keybindings()
    result = Dict{String,String}()
    for (action, button) in KEYBINDINGS
        result[action] = key_to_string(button)
    end
    return result
end

"""
    set_keybinding!(action::String, key::String)
    set_keybinding!(action::Symbol, key::String)

Set a keybinding for an action. Persists to LocalPreferences.toml.

# Example
```julia
SMLMView.set_keybinding!(:zoom_in, "k")
SMLMView.set_keybinding!("pan_up", "w")
```
"""
function set_keybinding!(action::String, key::String)
    if !haskey(DEFAULT_KEYBINDINGS, action)
        error("Unknown action '$action'. Valid actions: $(join(keys(DEFAULT_KEYBINDINGS), ", "))")
    end

    button = string_to_key(key)
    if button == Keyboard.unknown
        error("Unknown key '$key'. See SMLMView.list_keys() for valid keys.")
    end

    @set_preferences!(action => key)
    KEYBINDINGS[action] = button
    @info "Set $action => $key (restart Julia for full effect)"
    return nothing
end

set_keybinding!(action::Symbol, key::String) = set_keybinding!(String(action), key)

"""
    reset_keybindings!()

Reset all keybindings to defaults. Clears preferences.
"""
function reset_keybindings!()
    for action in keys(DEFAULT_KEYBINDINGS)
        @delete_preferences!(action)
    end
    load_keybindings!()
    @info "Keybindings reset to defaults"
    return nothing
end

"""
    list_keys() -> Vector{String}

List all valid key names for keybindings.
"""
function list_keys()
    return sort(collect(keys(KEY_MAP)))
end

"""
    list_actions() -> Vector{String}

List all configurable actions.
"""
function list_actions()
    return sort(collect(keys(DEFAULT_KEYBINDINGS)))
end

"""
Get the Keyboard.Button for an action.
"""
function getkey(action::String)
    return get(KEYBINDINGS, action, Keyboard.unknown)
end
