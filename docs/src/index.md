```@meta
CurrentModule = SMLMView
```

# SMLMView.jl

WGLMakie-based interactive array viewer for N-dimensional microscopy data, inspired by DIPimage's `dipshow`.

## Features

- N-dimensional array viewing with slice navigation
- Multi-channel RGB composite display (2-3 channels)
- Intensity mapping: linear, log, percentile clipping
- Global or per-slice contrast stretch
- Configurable keybindings via Preferences.jl
- Web-deployable via WGLMakie/Bonito

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

# Multi-channel composite
ch1, ch2, ch3 = rand(256,256,10), rand(256,256,10), rand(256,256,10)
smlmview((ch1, ch2, ch3); names=("DAPI", "GFP", "A647"))
```

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `j` / `l` | Previous / next slice |
| `i` / `o` | Zoom in / out |
| `c` | Cycle colormap |
| `m` | Cycle intensity mapping |
| `g` | Toggle global/slice stretch |
| `r` | Reset view |
| `1-9` + `1-9` | Change display dimensions |
| `1` / `2` / `3` | Toggle channel visibility (composite) |

## Documentation

- [Examples](@ref) - Usage examples and workflows
- [API Reference](@ref) - Complete function documentation
