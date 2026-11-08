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
    "stretch_cycle" => "g",
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
    return get(KEY_MAP, lowercase(s), Keyboard.unknown)
end

# Digit keys 1-9 pick the display dims (array viewer) and toggle channels (composite); the
# viewers read them before any action, so an action bound to one could never fire.
const RESERVED_KEYS = (Keyboard._1, Keyboard._2, Keyboard._3, Keyboard._4, Keyboard._5,
                       Keyboard._6, Keyboard._7, Keyboard._8, Keyboard._9)

"""
    resolve_keybinding(action, key_str, default_key) -> Keyboard.Button

The key bound to `action`: `key_str` (a saved preference) when it names a key that is not a
reserved digit, otherwise the default, with a warning.
"""
function resolve_keybinding(action::String, key_str::String, default_key::String)
    button = string_to_key(key_str)
    if button == Keyboard.unknown
        @warn "Unknown key '$key_str' saved for '$action', using the default '$default_key'"
        button = string_to_key(default_key)
    elseif button in RESERVED_KEYS
        @warn "Key '$key_str' saved for '$action' is a digit, which picks display dims " *
              "and toggles channels; using the default '$default_key'"
        button = string_to_key(default_key)
    end
    return button
end

"""
    separate_keybindings!(bindings) -> bindings

Where two actions share a key, only one of them could ever fire. Put a saved binding that
shares a key back to its default (no two defaults share one) until every key is distinct.
"""
function separate_keybindings!(bindings::Dict{String,Keyboard.Button})
    isdefault(a) = bindings[a] == string_to_key(DEFAULT_KEYBINDINGS[a])
    while true
        owner = Dict{Keyboard.Button,String}()
        clash = nothing
        for action in sort(collect(keys(bindings)))
            other = get(owner, bindings[action], nothing)
            other === nothing || (clash = (other, action); break)
            owner[bindings[action]] = action
        end
        clash === nothing && return bindings
        other, action = clash
        moved = isdefault(action) ? other : action
        @warn "Key '$(key_to_string(bindings[moved]))' is saved for both '$other' and " *
              "'$action'; '$moved' goes back to its default '$(DEFAULT_KEYBINDINGS[moved])'"
        bindings[moved] = string_to_key(DEFAULT_KEYBINDINGS[moved])
    end
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
        KEYBINDINGS[action] = resolve_keybinding(action, key_str, default_key)
    end
    separate_keybindings!(KEYBINDINGS)
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

Set a keybinding for an action. It takes effect at once, in open viewers too, and persists to
LocalPreferences.toml.

Throws an `ArgumentError` for an unknown action or key, for a digit `1`-`9` (they pick display
dims and toggle channels), and for a key already bound to another action (rebind that one
first).

# Example
```julia
SMLMView.set_keybinding!(:zoom_in, "k")
SMLMView.set_keybinding!("pan_up", "w")
```
"""
function set_keybinding!(action::String, key::String)
    haskey(DEFAULT_KEYBINDINGS, action) || throw(ArgumentError(
        "Unknown action '$action'. Valid actions: $(join(list_actions(), ", "))"))

    button = string_to_key(key)
    button == Keyboard.unknown && throw(ArgumentError(
        "Unknown key '$key'. See SMLMView.list_keys() for valid keys."))
    button in RESERVED_KEYS && throw(ArgumentError(
        "Key '$key' is a digit; digits 1-9 pick display dims and toggle channels"))
    for (other, b) in KEYBINDINGS
        other != action && b == button && throw(ArgumentError(
            "Key '$key' is already bound to '$other'; rebind '$other' first"))
    end

    KEYBINDINGS[action] = button
    save_keybindings!()
    @info "Set $action => $key"
    return nothing
end

"""
    save_keybindings!()

Make the saved preferences the bindings in effect: an action on its default key has no saved
preference, every other action has its key saved. So a saved binding that loading put back
to its default (a digit, a collision, an unknown name) never returns at the next load.
"""
function save_keybindings!()
    for (action, default_key) in DEFAULT_KEYBINDINGS
        button = KEYBINDINGS[action]
        if button == string_to_key(default_key)
            @delete_preferences!(action)
        else
            @set_preferences!(action => key_to_string(button))
        end
    end
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

List all key names an action can be bound to (every known key but the digits 1-9, which pick
display dims and toggle channels).
"""
function list_keys()
    return sort([k for (k, b) in KEY_MAP if !(b in RESERVED_KEYS)])
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
