# Product Requirements Document: SMLMView.jl

## Overview

SMLMView is an interactive array/image viewer for Julia, inspired by DIPimage's `dipshow`. It provides a minimalist, low-latency viewer optimized for web deployment via WGLMakie, with efficient navigation of multidimensional data (1D-4D+).

**Design Philosophy:**
- WGLMakie-first: Optimized for web/remote viewing with server deployment
- Low latency over features: Display only the current 2D slice for responsive navigation
- Minimalist UI: Clean dropdown menus, no clutter
- Keyboard-centric: Power users navigate without touching menus

## Target Use Cases

1. **Quick array inspection**: View any Julia array interactively during development
2. **Remote visualization**: Server-deployed viewer accessible from browser
3. **SMLM data exploration**: Navigate Z-stacks, time series, multi-channel data
4. **Teaching/presentations**: Clean, professional display of scientific images

## Core Requirements

### 1. Input Data Support

**Supported Dimensionalities:**
- 1D: Line plot visualization
- 2D: Single image display
- 3D: Stack with slice navigation (dimension selector for which axis to slice)
- 4D: Stack with dual navigation sliders
- 5D+: Multiple navigation sliders, always display 2D slice

**Data Types:**
- Any numeric array: `Int`, `Float16/32/64`, `UInt8/16/32`, etc.
- Complex arrays: Display magnitude, phase, real, or imaginary
- Image types: `Gray`, `RGB` from Images.jl
- SMLMData types: Direct integration with `SMLD` containers

**Internal Processing:**
- Convert to appropriate display format on-the-fly
- Only process current 2D slice (lazy evaluation for large stacks)
- Cache recent slices for smooth back/forth navigation

### 2. Backend Architecture

**Primary Backend: WGLMakie**
- Web-based rendering via WebGL
- Server deployment with `Bonito.configure_server!()`
- Low-latency slice updates (<50ms target)

**Optional Backend: GLMakie**
- Native OpenGL for local desktop use
- Enabled via keyword argument when display available

**Backend Selection:**
```julia
smlmview(data)                      # Auto-detect (prefer WGLMakie)
smlmview(data; backend=:WGLMakie)   # Force web backend
smlmview(data; backend=:GLMakie)    # Force native backend
```

### 3. Display Controls

#### Zoom System (Two Types)

**Display Zoom (Ctrl +/-):** Pixel magnification
- Levels: 1/4x, 1/2x, 1x, 2x, 4x, 8x, 16x (factor-of-2 steps)
- 1x = 1 data pixel : 1 screen pixel (native resolution)
- `Ctrl +` = next larger zoom, `Ctrl -` = next smaller zoom
- Display zoom level shown in status bar

**View Zoom (i/o):** Region of interest within image
- `i` = zoom in (show smaller region, more detail)
- `o` = zoom out (show larger region, more context)
- `r` = reset to full image
- Pan with click-drag when zoomed in
- Mouse scroll = zoom in/out centered on cursor

#### Intensity Mapping (Dropdown Menu)

**Stretch Mode:**
| Option | Description |
|--------|-------------|
| Global | Min/max computed across entire stack (default) |
| Frame | Min/max computed per-slice |
| None | Raw values, no stretching (0-1 for float, 0-255 for UInt8) |
| Manual | User-specified min/max values |

**Mapping Function:**
| Option | Description |
|--------|-------------|
| Linear | Direct linear mapping (default) |
| Log | Logarithmic (good for high dynamic range) |
| Sqrt | Square root (mild compression) |
| Gamma | Adjustable gamma curve |

**Percentile Clipping:**
| Option | Description |
|--------|-------------|
| None | Use actual min/max |
| 0.1-99.9% | Remove extreme outliers (default) |
| 1-99% | Moderate clipping |
| 5-95% | Aggressive clipping |

#### Complex Number Display (for complex arrays)
- Magnitude (default)
- Phase
- Real part
- Imaginary part

### 4. Navigation Controls

#### Slice Navigation (3D+)

**Slider(s):**
- One slider per dimension beyond 2D
- Labeled with dimension index and current position
- Smooth dragging with immediate visual feedback

**Keyboard Shortcuts:**
| Key | Action |
|-----|--------|
| `n` / `p` | Next / previous slice (primary dimension) |
| `f` / `b` | Forward / backward (secondary dimension, 4D+) |
| `←` / `→` | Alternative next/prev |
| `↑` / `↓` | Alternative forward/back |
| `Home` / `End` | First / last slice |
| `PgUp` / `PgDn` | Jump 10 slices |

**Mouse:**
- Scroll wheel = navigate primary slice dimension

#### Playback (for time series)
| Key | Action |
|-----|--------|
| `Space` | Play/pause auto-advance |
| `[` / `]` | Slower / faster playback |
| `l` | Toggle loop mode |

### 5. User Interface Layout

```
┌─────────────────────────────────────────────────────────────────────┐
│ Stretch: [Global ▾]  Map: [Linear ▾]  Clip: [0.1-99.9% ▾]          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│                                                                     │
│                        ┌──────────────────┐                         │
│                        │                  │                         │
│                        │   Image Display  │                         │
│                        │                  │                         │
│                        └──────────────────┘                         │
│                                                                     │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│ Z: [═══════●═══════════════════════════] 45/100                     │
│ T: [═══●═══════════════════════════════] 3/50     [▶ 10fps] [Loop]  │
├─────────────────────────────────────────────────────────────────────┤
│ (256, 128) = 1247.3  │  Zoom: 2x  │  512×512 Float32              │
└─────────────────────────────────────────────────────────────────────┘
      └─ Cursor pos & value    └─ Display zoom  └─ Image info
```

**Layout Principles:**
- Top bar: Dropdown menus only (no buttons, no panels)
- Center: Image display (maximized)
- Bottom: Navigation sliders (only shown if needed)
- Status bar: Cursor info, zoom level, image metadata

**Responsive Behavior:**
- Image scales to fit container while maintaining aspect ratio
- Sliders hidden for 2D images
- Minimal chrome for maximum image area

### 6. Pixel Inspection

**Mouse Hover:**
- Display cursor position `(x, y)` or `(x, y, z, t)` in status bar
- Display pixel value at cursor position
- For multi-channel: show all channel values
- For complex: show based on current display mode

**No click required** - continuous update as mouse moves over image

### 7. Keyboard Shortcut Summary

| Category | Key | Action |
|----------|-----|--------|
| **Display Zoom** | `Ctrl +` | Increase magnification (1/4x → 16x) |
| | `Ctrl -` | Decrease magnification |
| | `Ctrl 0` | Reset to 1x (native) |
| **View Zoom** | `i` | Zoom into image (show less, more detail) |
| | `o` | Zoom out of image (show more, less detail) |
| | `r` | Reset view (full image, native zoom) |
| **Navigation** | `n` / `p` | Next / previous slice |
| | `f` / `b` | Forward / backward frame |
| | `Home` / `End` | First / last slice |
| | `PgUp` / `PgDn` | Jump ±10 slices |
| **Playback** | `Space` | Play / pause |
| | `[` / `]` | Slower / faster |
| | `l` | Toggle loop |
| **Display** | `c` | Cycle mapping (Linear → Log → Sqrt) |
| | `s` | Cycle stretch (Global → Frame → None) |
| | `h` | Toggle help overlay |
| **General** | `q` | Close viewer |
| | `Esc` | Close help / cancel operation |

### 8. API Design

#### Primary Function

```julia
"""
    smlmview(data::AbstractArray; kwargs...)

Launch an interactive viewer for array data.

# Arguments
- `data`: Any numeric array (1D-ND)

# Keyword Arguments
- `backend::Symbol=:auto`: `:WGLMakie`, `:GLMakie`, or `:auto`
- `stretch::Symbol=:global`: `:global`, `:frame`, `:none`, or `:manual`
- `mapping::Symbol=:linear`: `:linear`, `:log`, `:sqrt`, `:gamma`
- `clip::Tuple=(0.001, 0.999)`: Percentile clipping (min, max)
- `zoom::Real=1.0`: Initial display zoom (1/4, 1/2, 1, 2, 4, 8, 16)
- `slice::Union{Int,Tuple}=1`: Initial slice index(es)
- `title::String=""`: Window title
- `port::Int=9384`: Server port for WGLMakie

# Returns
- `ViewerHandle`: Object for programmatic control

# Examples
```julia
# View a 3D stack
data = rand(512, 512, 100)
smlmview(data)

# High dynamic range with log mapping
smlmview(data; mapping=:log, clip=(0.01, 0.99))

# Force web backend on specific port
smlmview(data; backend=:WGLMakie, port=9000)

# View complex data
fft_data = fft(rand(256, 256))
smlmview(fft_data)  # Shows magnitude by default
```
"""
function smlmview(data::AbstractArray; kwargs...)
end
```

#### Convenience Aliases

```julia
const view = smlmview      # Short alias (if not conflicting)
const dipshow = smlmview   # For dipimage users
```

#### SMLD Integration

```julia
"""
    smlmview(smld::SMLD; render_kwargs...)

View SMLD localization data with on-the-fly rendering.
"""
function smlmview(smld::SMLD; kwargs...)
end
```

#### Programmatic Control

```julia
# Get handle for programmatic control
v = smlmview(data)

# Update display
v.slice = 50           # Jump to slice 50
v.zoom = 4             # Set display zoom to 4x
v.mapping = :log       # Change to log mapping

# Query state
current_slice = v.slice
cursor_pos = v.cursor_position
pixel_val = v.pixel_value
```

### 9. Performance Requirements

**Latency Targets:**
- Slice navigation: <50ms update time
- Zoom change: <100ms
- Hover pixel value: <16ms (60fps)

**Memory Management:**
- Only current slice in GPU memory
- LRU cache for recent slices (configurable, default 10 slices)
- Lazy loading for large stacks (>1GB)

**Optimization Strategies:**
- Pre-compute global statistics on first load (background thread)
- Nearest-neighbor interpolation for display zoom (fast)
- Debounce rapid slider movements

### 10. Implementation Phases

**Phase 1: Core Viewer (MVP)**
- [ ] WGLMakie figure setup with Bonito configuration
- [ ] 2D image display with `heatmap!` or `image!`
- [ ] Basic intensity mapping (linear, global stretch)
- [ ] Mouse hover pixel value display
- [ ] Display zoom (Ctrl +/-, 1/4x to 16x)
- [ ] Status bar with cursor position and value

**Phase 2: Navigation**
- [ ] 3D support with Z-slider
- [ ] Keyboard navigation (n/p, Home/End)
- [ ] Mouse scroll for slice navigation
- [ ] 4D support with second slider
- [ ] View zoom (i/o) and pan

**Phase 3: Display Options**
- [ ] Dropdown menus (Stretch, Mapping, Clip)
- [ ] Log/sqrt mapping functions
- [ ] Per-frame stretching
- [ ] Complex number support
- [ ] Keyboard shortcuts (c, s)

**Phase 4: Playback & Polish**
- [ ] Animation playback (Space, speed control)
- [ ] Loop mode
- [ ] Help overlay (h)
- [ ] GLMakie backend option
- [ ] Performance optimization

**Phase 5: SMLD Integration**
- [ ] Direct SMLD viewing with on-the-fly rendering
- [ ] Color-by options (photons, z, frame)
- [ ] Zoom-dependent rendering resolution

### 11. Technical Dependencies

**Required:**
- WGLMakie.jl: WebGL rendering
- Bonito.jl: Server configuration (comes with WGLMakie)
- Observables.jl: Reactive state management
- Statistics.jl: Min/max/quantile calculations

**Optional (Extensions):**
- GLMakie.jl: Native desktop backend
- SMLMData.jl: SMLD type support
- Images.jl: Image type support

**Project.toml Structure:**
```toml
[deps]
WGLMakie = "..."
Observables = "..."
Statistics = "..."

[weakdeps]
GLMakie = "..."
SMLMData = "..."
Images = "..."

[extensions]
SMLMViewGLMakieExt = "GLMakie"
SMLMViewSMLMDataExt = "SMLMData"
SMLMViewImagesExt = "Images"
```

### 12. Differences from DIPimage dipshow

| Feature | dipshow | SMLMView |
|---------|---------|----------|
| Primary backend | MATLAB figures | WGLMakie (web) |
| Zoom shortcuts | i/o for magnification | Ctrl +/- for magnification, i/o for ROI |
| UI style | Menu bar + dialogs | Minimalist dropdowns |
| 3D display | Orthogonal views option | Single 2D slice only (latency priority) |
| Linked viewers | Built-in | Deferred to v2 |
| Colormaps | Limited | Full ColorSchemes.jl support |

### 13. Success Criteria

1. View any Julia array (1D-5D+) with `smlmview(data)`
2. Slice navigation latency <50ms on typical hardware
3. Works in browser via WGLMakie server deployment
4. Intuitive for dipshow users (similar keyboard shortcuts)
5. Pixel values visible on hover without clicking
6. Clean, professional appearance suitable for presentations

### 14. Deferred Features (v2.0+)

- Orthogonal views (XY/XZ/YZ)
- Maximum intensity projection
- Linked viewers for synchronized navigation
- ROI selection tools
- Measurement tools (distance, profiles)
- Export functionality (save image, movie)
- Histogram display
- Annotation overlays
- Multi-channel blending
