# CLAUDE.md

## Package Overview

SMLMView is a Julia package providing an interactive array/image viewer inspired by DIPimage's `dipshow`. Primary design goals:

- **WGLMakie-first**: Optimized for web/server deployment
- **Low latency**: <50ms slice navigation, display only current 2D slice
- **Minimalist UI**: Clean dropdowns, no clutter, maximum image area

## Design Reference

See `PRD.md` for complete product requirements. Key points:

### Zoom System
- **View Zoom** (`i/o`): Magnification levels (1/4x, 1/2x, 1x, 2x, 4x, 8x, 16x)
  - At 1x: Full image visible
  - At 2x: See half the pixels, each displayed 2x larger
- **Reset** (`r`): Fit entire image in view
- **Figure size**: Auto-calculated from image aspect ratio (via `figsize` max constraint)

### Key Shortcuts (Implemented)
- `i`: Zoom in (see fewer pixels, each larger)
- `o`: Zoom out (see more pixels, each smaller)
- `r`: Reset view (fit entire image)
- `e/s/d/f`: Pan up/left/down/right (jump = 1/4 of min visible dimension)
- Mouse hover: Shows pixel value continuously

### Key Shortcuts (Implemented - 3D)
- `j/l`: Previous/next z-slice

### Key Shortcuts (Future)
- `f/b`: Forward/back frame (4D)
- `c`: Cycle mapping (linear/log/sqrt)
- `s`: Cycle stretch (global/frame/none)

### UI Layout
```
┌─ Dropdowns: [Stretch ▾] [Mapping ▾] [Clip ▾] ─────────────────────┐
│                        Image Display                              │
├─ Sliders: Z: [═══●═══] T: [═══●═══] ─────────────────────────────┤
│ Status: (x,y) = value │ Zoom: 2x │ 512×512 Float32               │
└───────────────────────────────────────────────────────────────────┘
```

## Technical Architecture

### Backend
- Primary: WGLMakie with Bonito server configuration
- Optional: GLMakie for native desktop (via extension)

### Dependencies
```toml
[deps]
WGLMakie, Observables, Statistics

[weakdeps]
GLMakie, SMLMData, Images
```

### WGLMakie Setup (Auto-Configured)
SMLMView automatically configures Bonito on first `smlmview()` call:
```julia
using SMLMView
smlmview(rand(256, 256))  # Just works!
```

For manual control or custom port:
```julia
using SMLMView
configure_display!(port=8080)  # Optional: call before smlmview()
```

**Critical for VSCode Remote**: The `external_url` parameter is set automatically to enable
WebSocket tunneling through VSCode's port forwarding.

### VSCode Remote WebSocket Ports
VSCode Dev Tunnels/Remote only forward WebSocket on specific ports:
```
443, 3000, 3001, 4000, 4200, 5000, 5001, 5173, 5174,
5500, 5555, 6006, 7777, 7860, 8000, 8050, 8080, 8081,
8089, 8888, 9291
```
Default port 8080 is used. Check VSCode's Ports panel if display issues occur.

## Implementation Notes

### Image Orientation (MATLAB/DIPimage Convention)
- **Top-left = (1,1)**: Row 1 at top, column 1 at left
- **Data mapping**: `heatmap!(ax, reverse(data, dims=1)')` - flip rows then transpose
- **Interpolation**: `interpolate=false` for nearest neighbor (crisp pixels)
- **Coordinates**: Mouse Y maps to `row = nrows - screen_y + 1`, display as `(row, col) = value`
- **Note**: `yreversed=true` doesn't work reliably in WGLMakie, so we flip data instead

### Phase 1 (MVP) - COMPLETE
1. WGLMakie figure with Bonito config (port 8080)
2. 2D image display via `heatmap!` with transpose
3. Linear intensity mapping with percentile clipping
4. Mouse hover → pixel value in status bar
5. Correct orientation: (1,1) at top-left
6. Nearest neighbor interpolation (crisp pixels)
7. Rectangular images display correctly (width=ncols, height=nrows)
8. View zoom (`i/o`) with magnification levels
9. Reset view (`r`) to fit entire image
10. Auto-sized figure based on image aspect ratio
11. Basic status bar with coordinates and zoom

### Performance Priorities
- Only render current 2D slice (lazy for ND)
- Nearest-neighbor interpolation for zoom (fast)
- LRU cache for recent slices
- Debounce rapid slider movements

## Related Packages

- **SMLMVis.jl**: Has existing PRD at `src/interact/PRD.md` with comprehensive dipshow feature list (used as reference)
- **SMLMData.jl**: Core types, integrate via extension
- **DIPlib/dipimage**: Original inspiration ([dipshow.m source](https://github.com/DIPlib/diplib/blob/master/dipimage/dipshow.m))

## Development Commands

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()

using SMLMView

# Quick test - Bonito auto-configured on first call
data = rand(256, 256)
smlmview(data)

# 3D test
data3d = rand(64, 128, 10)
v = smlmview(data3d)  # Use j/l to navigate z-slices
```

### Keybindings API
```julia
get_keybindings()           # Show current bindings
set_keybinding!(:zoom_in, "k")  # Change zoom_in to 'k'
reset_keybindings!()        # Reset to defaults
list_keys()                 # Valid key names
list_actions()              # Configurable actions
```
