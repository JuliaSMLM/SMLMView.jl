# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

```julia
# Setup
using Pkg
Pkg.activate(".")
Pkg.instantiate()

# Run all tests
Pkg.test()

# Run specific test file
include("test/test_keybindings.jl")

# Interactive testing - Bonito auto-configures on first call
using SMLMView
smlmview(rand(256, 256))              # 2D grayscale
smlmview(rand(64, 128, 10))           # 3D stack (j/l to navigate)
smlmview((rand(256,256), rand(256,256)))  # 2-channel composite
```

Example scripts in `examples/` demonstrate various use cases.

## Architecture Overview

SMLMView is a WGLMakie-based interactive array viewer inspired by DIPimage's `dipshow`. Design goals: web deployment via WGLMakie, <50ms slice navigation, minimalist UI.

### Source Files (`src/`)
- **SMLMView.jl**: Module entry point, exports `smlmview`, keybinding APIs, `configure_display!`
- **types.jl**: Constants (zoom levels, colormaps, mappings, stretch modes, channel colors)
- **display.jl**: Bonito server configuration (`configure_display!`, auto-setup on first use)
- **keybindings.jl**: User-configurable keybindings via Preferences.jl, persistent in LocalPreferences.toml
- **tools.jl**: Helper functions - slice extraction, colorrange sampling, cursor updates, formatting
- **viewer.jl**: Main `smlmview(data::AbstractArray)` - single-channel ND viewer with Observables-based reactivity
- **viewer_composite.jl**: `smlmview(channels::Tuple)` - multi-channel RGB composite with additive blending

### Key Design Patterns
- **Observables-based reactivity**: All state (slice indices, zoom, colormap, cursor) stored in Observables; UI updates automatically via `on()` callbacks and `@lift` macros
- **Lazy slice evaluation**: Only current 2D slice rendered; `prepare_slice_nd()` extracts and orients data on-demand
- **WGLMakie texture recreation**: When `display_dims` changes, heatmap must be recreated via `empty!(ax)` + `heatmap!(...)` because texture dimensions are fixed at creation
- **Image orientation**: MATLAB convention (1,1 at top-left) via `reverse(data, dims=1)` then `permutedims`

### Two Viewer Modes
1. **Single-channel viewer** (`viewer.jl`): `smlmview(data::AbstractArray)` - grayscale heatmap with colormaps
2. **Composite viewer** (`viewer_composite.jl`): `smlmview(channels::Tuple)` - RGB additive blending, channel visibility toggles

Both share common tools from `tools.jl` but have separate keyboard handling due to different state requirements.

### Keyboard Shortcuts (Configurable via Preferences.jl)
Keybindings persist in `LocalPreferences.toml`. Use `set_keybinding!(:action, "key")` to customize.

- `i/o`: Zoom in/out
- `r`: Reset view
- `e/s/d/f`: Pan up/left/down/right
- `j/l`: Previous/next slice
- `c`: Cycle colormap (grays, inferno, viridis, turbo, plasma, twilight)
- `m`: Cycle mapping (linear, log, p1_99, p5_95)
- `g`: Cycle stretch (global, slice)
- `1-9` + `1-9`: Two-number sequence changes display_dims (ND viewer)
- `1/2/3`: Toggle channel visibility (composite viewer)

## WGLMakie/VSCode Remote Setup

Display auto-configures on first `smlmview()` call (port 8080). VSCode Remote only forwards WebSocket on specific ports - 8080 is one of them.

**Troubleshooting**: If figure doesn't appear, reset VSCode port forwarding:
1. Ports panel → Stop Forwarding port 8080
2. Re-add port 8080
3. Try `smlmview()` again
