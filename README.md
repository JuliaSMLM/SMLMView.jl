# SMLMView

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://JuliaSMLM.github.io/SMLMView.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://JuliaSMLM.github.io/SMLMView.jl/dev/)
[![Build Status](https://github.com/JuliaSMLM/SMLMView.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/JuliaSMLM/SMLMView.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/JuliaSMLM/SMLMView.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/JuliaSMLM/SMLMView.jl)

WGLMakie-based interactive array viewer for N-dimensional microscopy data, inspired by DIPimage's `dipshow`.

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/JuliaSMLM/SMLMView.jl")
```

## Quick Start

```julia
using SMLMView

# 2D or 3D grayscale
data = rand(256, 256, 10)
smlmview(data)

# Multi-channel composite (2-3 channels)
ch1, ch2, ch3 = rand(256,256,10), rand(256,256,10), rand(256,256,10)
smlmview((ch1, ch2, ch3); names=("DAPI", "GFP", "A647"))
```

## Features

- N-dimensional array viewing with slice navigation (`j`/`l` keys)
- Multi-channel RGB composite with CMY/RGB color presets
- Intensity mapping modes: linear, log, percentile clipping
- Global or per-slice contrast stretch
- Configurable keybindings via Preferences.jl
- Web-deployable via WGLMakie/Bonito

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `j` / `l` | Previous / next slice |
| `i` / `o` | Zoom in / out |
| `c` | Cycle colormap |
| `m` | Cycle intensity mapping |
| `g` | Toggle global/slice stretch |
| `r` | Reset view |
| `1-9` + `1-9` | Change display dimensions (ND viewer) |
| `1` / `2` / `3` | Toggle channel visibility (composite viewer) |

## Documentation

- [API Reference](api_overview.md) - Function signatures and examples
- [Full Documentation](https://JuliaSMLM.github.io/SMLMView.jl/dev/) - Guides and tutorials

## License

MIT License - see [LICENSE](LICENSE) file.
