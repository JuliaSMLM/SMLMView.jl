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
# Each is (name, clip_lo, clip_hi, transform)
# transform: :linear or :log
const MAPPINGS = (
    (name=:linear,  clip=(0.001, 0.999), transform=:linear),
    (name=:log,     clip=(0.001, 0.999), transform=:log),
    (name=:p1_99,   clip=(0.01, 0.99),   transform=:linear),
    (name=:p5_95,   clip=(0.05, 0.95),   transform=:linear),
)

# Stretch modes for cycling with 'g' key
# :global = colorrange from entire dataset, :slice = colorrange from current slice
const STRETCH_MODES = (:global, :slice)
