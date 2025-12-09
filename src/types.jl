#=============================================================================
# Constants and type definitions
=============================================================================#

const ZOOM_LEVELS = (0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0)
const DEFAULT_ZOOM_IDX = 3  # 1.0x (index into ZOOM_LEVELS)
const DIM_KEY_TIMEOUT = 0.5  # seconds for two-number dim selection
const DEFAULT_PORT = 8080  # Default port for Bonito server (VSCode WebSocket-compatible)
