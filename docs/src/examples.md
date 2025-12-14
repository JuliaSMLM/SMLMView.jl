# Examples

```@meta
CurrentModule = SMLMView
```

## Basic 2D/3D Viewing

View grayscale arrays with automatic display configuration:

```julia
using SMLMView

# 2D image
img = rand(512, 512)
smlmview(img)

# 3D stack - navigate with j/l keys
stack = rand(256, 256, 50)
v = smlmview(stack)

# Programmatic slice control
v.slice_indices[3][] = 25  # Jump to slice 25
```

## Multi-Channel Composite

Display 2-3 channel data as RGB composite with additive blending:

```julia
using SMLMView

# Simulate 3-channel microscopy data
dapi = rand(512, 512, 20)   # Nuclear stain
gfp = rand(512, 512, 20)    # Green fluorescent protein
alexa = rand(512, 512, 20)  # Far-red label

# View as composite (default CMY colors)
v = smlmview((dapi, gfp, alexa); names=("DAPI", "GFP", "Alexa647"))

# Toggle channels with 1/2/3 keys or programmatically
v.channel_visible[1][] = false  # Hide DAPI channel
```

## Custom Channel Colors

Use preset color schemes or define custom colors:

```julia
using SMLMView

ch1 = rand(256, 256)
ch2 = rand(256, 256)
ch3 = rand(256, 256)

# Use RGB preset instead of default CMY
colors = CHANNEL_COLOR_PRESETS[:rgb]
smlmview((ch1, ch2, ch3); colors=colors)

# Or define custom colors
using WGLMakie: RGB
custom = (RGB(1.0, 0.0, 0.0), RGB(0.0, 1.0, 0.0), RGB(0.0, 0.0, 1.0))
smlmview((ch1, ch2, ch3); colors=custom)
```

## 4D+ Data Navigation

Handle higher-dimensional data with dimension selection:

```julia
using SMLMView

# 4D data: (Y, X, Z, T)
data4d = rand(128, 128, 20, 100)
v = smlmview(data4d; dim_names=("Y", "X", "Z", "T"))

# Press 1,3 to view Y-Z plane (sagittal view)
# Or change programmatically:
v.display_dims[] = (1, 3)

# Navigate T dimension via slider or:
v.slice_indices[4][] = 50  # Jump to frame 50
```

## Intensity Mapping

Control how intensity values map to display:

```julia
using SMLMView

# High dynamic range data
data = exp.(randn(256, 256) .* 2)
v = smlmview(data)

# Press 'm' to cycle through:
# - linear: Full min-max range
# - log: Logarithmic scaling
# - p1_99: 1%-99% percentile clip
# - p5_95: 5%-95% percentile clip

# Press 'g' to toggle:
# - global: Colorrange from entire dataset
# - slice: Colorrange from current slice only
```

## Custom Keybindings

Configure keyboard shortcuts to your preference:

```julia
using SMLMView

# WASD-style navigation
set_keybinding!(:pan_up, "w")
set_keybinding!(:pan_left, "a")
set_keybinding!(:pan_down, "s")
set_keybinding!(:pan_right, "d")

# View current bindings
get_keybindings()

# Reset to defaults
reset_keybindings()

# See available keys and actions
list_keys()
list_actions()
```

## Programmatic Control

Access viewer state via returned Observables:

```julia
using SMLMView

data = rand(256, 256, 10)
v = smlmview(data)

# Read current state
v.colorrange[]        # Current intensity range
v.colormap[]          # Current colormap symbol
v.cursor_pos[]        # Current cursor position
v.pixel_value[]       # Value under cursor

# Modify state
v.colormap_idx[] = 2  # Switch to inferno
v.stretch_idx[] = 2   # Switch to per-slice stretch
```
