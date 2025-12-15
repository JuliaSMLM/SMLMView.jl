#=============================================================================
# Constants and type definitions
=============================================================================#

const ZOOM_LEVELS = (0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0)
const DEFAULT_ZOOM_IDX = 3  # 1.0x (index into ZOOM_LEVELS)
const DIM_KEY_TIMEOUT = 0.5  # seconds for two-number dim selection
const DEFAULT_PORT = 8080  # Default port for Bonito server (VSCode WebSocket-compatible)

# Available colormaps for cycling with 'c' key
const COLORMAPS = (:grays, :inferno, :viridis, :turbo, :plasma, :twilight)

# Intensity mapping modes for cycling with 'm' key
# Each is (name, clip, transform)
# clip=(0.0, 1.0) means full min-max range (no percentile clipping)
const MAPPINGS = (
    (name=:linear,  clip=(0.0, 1.0),   transform=:linear),  # Full min-max range
    (name=:log,     clip=(0.0, 1.0),   transform=:log),     # Log with full range
    (name=:p1_99,   clip=(0.01, 0.99), transform=:linear),  # 1%-99% percentile
    (name=:p5_95,   clip=(0.05, 0.95), transform=:linear),  # 5%-95% percentile
)

# Stretch modes for cycling with 'g' key
# :global = colorrange from entire dataset, :slice = colorrange from current slice
const STRETCH_MODES = (:global, :slice)

# RGB type from Makie/ColorTypes (re-exported by WGLMakie)
const RGB = WGLMakie.Makie.RGB
const Colorant = WGLMakie.Makie.Colorant

"""
    DEFAULT_CHANNEL_COLORS

Default channel colors for multi-channel composite viewing (Cyan, Magenta, Yellow).
CMY additive blending: C+M=Blue, C+Y=Green, M+Y=Red, C+M+Y=White.
"""
const DEFAULT_CHANNEL_COLORS = (
    RGB{Float64}(0.0, 1.0, 1.0),  # Cyan
    RGB{Float64}(1.0, 0.0, 1.0),  # Magenta
    RGB{Float64}(1.0, 1.0, 0.0),  # Yellow
)

"""
    CHANNEL_COLOR_PRESETS

Named color presets for multi-channel composite viewing.
Available presets: `:cmy` (default), `:rgb`, `:mgc` (Magenta-Green-Cyan).
"""
const CHANNEL_COLOR_PRESETS = Dict{Symbol, NTuple{3, RGB{Float64}}}(
    :cmy => (RGB{Float64}(0.0, 1.0, 1.0), RGB{Float64}(1.0, 0.0, 1.0), RGB{Float64}(1.0, 1.0, 0.0)),
    :rgb => (RGB{Float64}(1.0, 0.0, 0.0), RGB{Float64}(0.0, 1.0, 0.0), RGB{Float64}(0.0, 0.0, 1.0)),
    :mgc => (RGB{Float64}(1.0, 0.0, 1.0), RGB{Float64}(0.0, 1.0, 0.0), RGB{Float64}(0.0, 1.0, 1.0)),
)
