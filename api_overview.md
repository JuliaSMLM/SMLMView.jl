# SMLMView.jl API Reference

WGLMakie-based interactive array viewer for N-dimensional data, inspired by DIPimage's `dipshow`.

## Exports Summary

- **Types:** 0
- **Functions:** 7
- **Constants:** 2

## Key Concepts

SMLMView provides a single entry point (`smlmview`) that dispatches on input type: single arrays become grayscale ND viewers, tuples of arrays become multi-channel RGB composites. All state is managed via Observables for reactive updates. The viewer returns a NamedTuple of Observables and figure references for programmatic control.

## Functions

### smlmview (Single Array)

```julia
smlmview(data::AbstractArray{T,N}; kwargs...) -> NamedTuple
```

Launch an interactive viewer for N-dimensional array data (N >= 2).

**Arguments:**
- `data::AbstractArray{T,N}`: N-dimensional numeric array to display

**Keywords:**
- `display_dims::Tuple{Int,Int}=(1,2)`: Which dims to display as (rows, cols)
- `dim_names::Union{Nothing,NTuple{N,String}}=nothing`: Labels for each dimension
- `clip::Tuple{Real,Real}=(0.0,1.0)`: Percentile clipping for intensity stretch
- `title::String=""`: Window/axis title
- `colormap::Symbol=:grays`: Initial colormap
- `figsize::Tuple{Int,Int}=(800,700)`: Maximum figure size in pixels
- `show::Bool=true`: Display figure immediately

**Returns:** NamedTuple with:
- `fig`: Makie Figure
- `ax`: Image Axis
- `data`: Reference to original array (no copy)
- `display_dims`: Observable for current display dimensions
- `slice_indices`: Vector of Observables for slice positions
- `colorrange`: Observable for intensity range
- `colormap`: Observable for current colormap
- `mapping`: Observable for current intensity mapping
- `stretch`: Observable for stretch mode (:global/:slice)
- `cursor_pos`: Observable for cursor (row, col)
- `pixel_value`: Observable for value under cursor

**Example:**
```julia
using SMLMView
data = rand(256, 256, 10)
v = smlmview(data)
v = smlmview(data; display_dims=(1,3), colormap=:viridis)
```

### smlmview (Multi-Channel Composite)

```julia
smlmview(channels::NTuple{C,AbstractArray{T,N}}; kwargs...) -> NamedTuple
```

Launch viewer for multi-channel RGB composite (2-3 channels).

**Arguments:**
- `channels::NTuple{C,AbstractArray{T,N}}`: Tuple of 2-3 arrays with matching spatial dimensions

**Keywords:**
- `colors::Union{Nothing,NTuple{C,RGB{Float64}}}=nothing`: Channel colors (default: CMY)
- `names::Union{Nothing,NTuple{C,String}}=nothing`: Channel names for display
- `display_dims::Tuple{Int,Int}=(1,2)`: Which dims are (rows, cols)
- `clip::Tuple{Real,Real}=(0.0,1.0)`: Percentile clipping
- `figsize::Tuple{Int,Int}=(800,700)`: Max figure size
- `show::Bool=true`: Display immediately

**Returns:** NamedTuple with:
- `fig`, `ax`: Figure and Axis
- `channels`: Reference to input channels
- `colors`: Actual channel colors used
- `channel_visible`: Vector of Observables for channel visibility
- `channel_ranges`: Vector of Observables for per-channel colorranges
- `rgb`: Observable for composite RGB matrix
- Plus: `display_dims`, `slice_indices`, `mapping`, `stretch`, `cursor_pos`, `pixel_values`

**Example:**
```julia
using SMLMView
ch1, ch2, ch3 = rand(256,256,10), rand(256,256,10), rand(256,256,10)
v = smlmview((ch1, ch2, ch3); names=("DAPI", "GFP", "A647"))
```

### configure_display!

```julia
configure_display!(; port::Int=8080) -> Nothing
```

Configure WGLMakie and Bonito server. Called automatically on first `smlmview()`.

**Keywords:**
- `port::Int=8080`: Server port (8080 is VSCode WebSocket-compatible)

**Example:**
```julia
configure_display!(port=9000)
```

### get_keybindings

```julia
get_keybindings() -> Dict{String,String}
```

Return current keybindings as action => key string pairs.

**Returns:** Dict mapping action names to key strings

**Example:**
```julia
bindings = get_keybindings()
# Dict("zoom_in" => "i", "zoom_out" => "o", ...)
```

### set_keybinding!

```julia
set_keybinding!(action::String, key::String) -> Nothing
set_keybinding!(action::Symbol, key::String) -> Nothing
```

Set a keybinding for an action. Persists to LocalPreferences.toml.

**Arguments:**
- `action`: Action name (see `list_actions()`)
- `key`: Key string (see `list_keys()`)

**Example:**
```julia
set_keybinding!(:zoom_in, "k")
set_keybinding!("pan_up", "w")
```

### reset_keybindings!

```julia
reset_keybindings!() -> Nothing
```

Reset all keybindings to defaults. Clears LocalPreferences.toml entries.

**Example:**
```julia
reset_keybindings!()
```

### list_keys

```julia
list_keys() -> Vector{String}
```

List all valid key names for keybindings.

**Returns:** Sorted vector of key name strings

**Example:**
```julia
list_keys()
# ["0", "1", ..., "a", "b", ..., "space", "tab", ...]
```

### list_actions

```julia
list_actions() -> Vector{String}
```

List all configurable actions.

**Returns:** Sorted vector of action names

**Example:**
```julia
list_actions()
# ["colormap_cycle", "mapping_cycle", "pan_down", "pan_left", ...]
```

## Constants

### DEFAULT_CHANNEL_COLORS

```julia
DEFAULT_CHANNEL_COLORS::NTuple{3,RGB{Float64}}
```

Default CMY colors for multi-channel composite:
- Channel 1: Cyan `RGB(0.0, 1.0, 1.0)`
- Channel 2: Magenta `RGB(1.0, 0.0, 1.0)`
- Channel 3: Yellow `RGB(1.0, 1.0, 0.0)`

### CHANNEL_COLOR_PRESETS

```julia
CHANNEL_COLOR_PRESETS::Dict{Symbol,NTuple{3,RGB{Float64}}}
```

Named color presets for multi-channel display:
- `:cmy` - Cyan, Magenta, Yellow (default)
- `:rgb` - Red, Green, Blue
- `:mgc` - Magenta, Green, Cyan

**Example:**
```julia
colors = CHANNEL_COLOR_PRESETS[:rgb]
smlmview((ch1, ch2, ch3); colors=colors)
```

## Keyboard Shortcuts

### Single-Channel Viewer

| Key | Action |
|-----|--------|
| `1-9` + `1-9` | Two-number sequence sets display_dims |
| `c` | Cycle colormap (grays, inferno, viridis, turbo, plasma, twilight) |
| `m` | Cycle mapping (linear, log, p1_99, p5_95) |
| `g` | Cycle stretch mode (global, slice) |
| `r` | Reset view |
| `i` / `o` | Zoom in / out |
| `e` / `s` / `d` / `f` | Pan up / left / down / right |
| `j` / `l` | Previous / next slice |

### Multi-Channel Composite

| Key | Action |
|-----|--------|
| `1` / `2` / `3` | Toggle channel visibility |
| `m` | Cycle mapping |
| `g` | Cycle stretch mode |
| `r` | Reset view |
| `i` / `o` | Zoom in / out |
| `e` / `s` / `d` / `f` | Pan |
| `j` / `l` | Previous / next slice |

## Common Workflows

### Basic 2D/3D Viewing

```julia
using SMLMView

# 2D grayscale
img = rand(256, 256)
smlmview(img)

# 3D stack - use j/l to navigate slices
stack = rand(256, 256, 50)
v = smlmview(stack)

# Change slice programmatically
v.slice_indices[3][] = 25
```

### Multi-Channel Microscopy

```julia
using SMLMView

# Load/simulate 3-channel data
dapi = rand(512, 512, 20)
gfp = rand(512, 512, 20)
alexa = rand(512, 512, 20)

# View as RGB composite
v = smlmview((dapi, gfp, alexa); names=("DAPI", "GFP", "Alexa647"))

# Toggle channels with 1/2/3 keys, or programmatically:
v.channel_visible[1][] = false  # Hide DAPI
```

### 4D+ Data Navigation

```julia
using SMLMView

# 4D: (Y, X, Z, T)
data4d = rand(128, 128, 20, 100)
v = smlmview(data4d; dim_names=("Y", "X", "Z", "T"))

# Press 1,3 to view Y-Z plane instead of Y-X
# Or programmatically:
v.display_dims[] = (1, 3)
```

### Custom Keybindings

```julia
using SMLMView

# WASD navigation
set_keybinding!(:pan_up, "w")
set_keybinding!(:pan_left, "a")
set_keybinding!(:pan_down, "s")
set_keybinding!(:pan_right, "d")

# Check current bindings
get_keybindings()

# Reset to defaults
reset_keybindings!()
```
