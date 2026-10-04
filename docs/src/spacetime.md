```@meta
CurrentModule = SMLMView
```

# Space-time viewer

[`spacetime`](@ref) shows a single-molecule tracking result as one interactive WGLMakie
scene: the raw movie as translucent gray voxels in a 3D box (x, y, frame), the
trajectories drawn through it, and a linked 2D frame inspector. It is the viewer behind
RJTrack and SoftLinkTrack results.

- 3D view with rotate, zoom and pan, plus `Top view`, `Reset` and `Links` buttons.
- Frame slider (or `Up` / `Down`): the selected raw frame is highlighted in 3D.
- Zooming the 2D frame crops the 3D scene to the same x-y region (the ROI).
- Click a point in the 2D frame to select its track and redraw it thickly in 3D.
- `2D track IDs` toggles track labels in the frame.
- With `ground_truth_tracks` in the scene, a `FOUND` / `GT` switch swaps the displayed
  track set.
- With `links` in the scene, the alternative links are drawn with opacity set by their
  weight.

The input is a plain `Dict{String,Any}` of arrays and scalars, the *scene*. Nothing in the
viewer depends on the tracker that produced it; an exporter in the tracking package writes
the scene (for example with `jldsave(path; scene)`), and the caller loads it and passes the
Dict. `spacetime` takes the Dict, not a path, so SMLMView carries no file-format dependency.

```julia
using SMLMView, JLD2
scene = load("scene.jld2", "scene")
view = spacetime(scene)                # served in a Ship of Tools REPL, else standalone HTML
view = spacetime(scene; output=:html, html="scene.html")
```

A small hand-written scene in the schema ships with the package, for trying the viewer and
as the reference example of every key:

```@example spacetime
using SMLMView
scene = SMLMView.Spacetime.example_scene(; truth=true, links=true, dimers=true)
sort(collect(keys(scene)))
```

```julia
view = spacetime(SMLMView.Spacetime.example_scene(); output=:html)
```

## Scene schema `"spacetime/1"`

### Required keys

| key | type | meaning |
|---|---|---|
| `nx`, `ny` | `Int` | camera size in pixels |
| `pixel_size` | `Float64` | pixel size in μm, `> 0` |
| `sub_steps` | `Int` | model steps per source frame; `1` when `z` is the frame |
| `source_frames` | `Vector{Int}` | the source frame numbers, non-empty, for example `collect(1:T)` |
| `state_source` | `String` | what the shown tracks are, for example `"map"` (shown in the legend) |
| `raw_xyz` | `Matrix{Float32}`, `(nx*ny*T, 3)` | voxel centers (x, y, frame), see the conventions |
| `raw_scaled_intensity` | `Vector{Float32}`, length `nx*ny*T` | voxel intensity scaled to `[0, 1]` (finite), same order as `raw_xyz` |
| `track_x`, `track_y`, `track_z` | `Vector{Vector{Float32}}` | one vector per track: position in μm and z in frames |
| `track_fine_frames` | `Vector{Vector{Int}}` | the (fine) frame of each track point; a jump `> 1` is drawn as a dashed gap segment |
| `track_colors` | `Matrix{Float32}`, `(n_tracks, 3)` | RGB, every value in `[0, 1]` |

`T = length(source_frames)`. How the raw voxels are described in the legend depends on the
optional `raw_render_mode`:

- `"all_voxels"` needs `raw_normalization_quantile` (`Float64`, for example `0.999`) and
  `raw_normalization_high` (`Float64`, the intensity at that quantile);
- anything else, and the default `"thresholded"`, needs `raw_threshold` and `raw_quantile`.

### Optional keys

| key | type | meaning |
|---|---|---|
| `schema` | `String` | `"spacetime/1"`, see the declaration rule |
| `title` | `String` | 3D axis title (default `"Raw intensity and trajectories"`) |
| `track_ids` | `Vector{Int}` | id of each track, one per track (default `1:n_tracks`; the default is used everywhere, including `trajectory_color_matches`) |
| `track_labels` | `Vector{String}` | label of each track (default prefix + index) |
| `track_label_prefix` | `String` | label prefix, default `"T"` |
| `track_id_description` | `String` | what `track_ids` are, default `"trajectory id"` |
| `display_name` | `String` | name of this track set in titles and the legend (default `"found"`, `"ground truth"`) |
| `matched_other_ids` | `Vector{Int}`, one per track | per track, the id of its match in the other set, `0` for none |
| `raw_intensity_unit` | `String` | unit in the legend, default `"photons"` |
| `raw_alpha_min`, `raw_alpha_max`, `raw_alpha_gamma` | `Float` | voxel opacity range, each in `[0, 1]`, and gamma `> 0` (defaults `0.0005`, `0.06`, `1.15`) |
| `ground_truth_tracks` | `Dict` | a second track set, see below |
| `trajectory_color_matches`, `trajectory_color_match_gate` | see below | shared colors for matched tracks |
| `links` | `Dict` | link probabilities, see below |
| `dimer_*` | see below | dimer episodes |

### Coordinate conventions

Every number the viewer reads must be finite, and the ranges above are enforced. All
positions are in μm; `z` is the frame (with `sub_steps = k`, the fine frame is the model
step, `track_fine_frames` holds it and `z = (step - 0.5)/k + 0.5`).

- A voxel at image row `r`, column `c` and frame `f` is at
  `x = (c - 0.5) * pixel_size`, `y = (ny - r + 0.5) * pixel_size`, `z = f`: image row 1 is at
  the top, the MATLAB / image convention.
- `raw_scaled_intensity` is in the order of `CartesianIndices` of `images[row, col, frame]`
  (row fastest), the same order as the rows of `raw_xyz`.
- Track `y` is flipped the same way: `track_y = ny * pixel_size - y`, where `y` is measured
  with image row 1 covering `[0, pixel_size]`. A track point at `x`, `y` lies over the voxels
  of the pixel that contains it.

### Traps

- **Orientation.** The voxel `y` formula assumes the image row index increases with `y`
  (row 1 covers `y in [0, pixel_size]`). Check your simulator's or tracker's image
  orientation against a track's `y` before trusting the overlay: a single transposition makes
  the tracks miss the blobs.
- **Positions outside the field.** Drop them in the exporter, or accept that the viewer clips
  segments at the box edge.
- **Colors.** With `trajectory_color_matches`, every matched found row must have exactly the
  color of its truth row, and found colors must be unique. The control self-test checks this,
  and `spacetime` throws before serving or exporting if it fails.
- **Size.** The standalone HTML grows with the voxel count: about 27 MB for 64x64x100 and
  63 MB for 96x96x120. The browser draws every voxel as a translucent cube.
- **One client.** Two browser clients on one live figure corrupt Makie's shared layout; see
  the output routes.

### Ground-truth tracks

`ground_truth_tracks` is a Dict with the same track keys (`track_x`, `track_y`, `track_z`,
`track_fine_frames`, `track_colors`, and the optional `track_ids`, `track_labels`,
`track_label_prefix`, `display_name`, `matched_other_ids`). It turns on the `FOUND` / `GT`
switch. The scene itself is the found set.

### Color matches

`trajectory_color_matches` is a vector of named tuples with at least `truth_id` and
`estimate_id`, together with `trajectory_color_match_gate` (the matching gate in μm, shown in
the label). It requires `ground_truth_tracks`; `truth_id` is a `ground_truth_tracks` track id
and `estimate_id` a found track id. Matched tracks must carry the same color in both sets.

### Links

`links` is a Dict of equal-length vectors of alternative linkings, in the same coordinates
as the tracks:

```
"links" => Dict(
    "x0", "y0", "z0", "x1", "y1", "z1" => Vector{Float32},  # segment ends (y flipped like tracks)
    "w"      => Vector{Float32},                            # link probability
    "on_map" => Vector{Bool})                               # link used by the MAP readout
```

One amber segment is drawn per link with `on_map = false` (MAP links lie on the track
segments, which are already drawn), for the found set only, clipped to the ROI, with a
`Links` button to hide them.

### Dimers

Optional dimer episodes, drawn as a gold path with a label. A set that has any `dimer_*` key
needs `dimer_x`, `dimer_y`, `dimer_z` (`Vector{Vector{Float32}}`, one non-empty vector per
episode, same convention as tracks), `dimer_fine_frames` (`Vector{Vector{Int}}`) and
`dimer_labels` (`Vector{String}`), aligned per episode. When there is at least one episode,
`dimer_track_indices` and `dimer_track_ids` (`n_episodes x 2` integer matrices) are required
too. Dimers may be given for the found set and inside `ground_truth_tracks`. The legend names
dimers only when the scene has `dimer_*` keys.

### The declaration rule

A scene declares its schema with `"schema" => "spacetime/1"`. A scene without the key is read
as `"spacetime/1"`, with one `@info` per session suggesting the exporter add the key. The
absence of the key is the only fallback: a key that is present must be a string equal to a
supported version, so `nothing`, a `Symbol` or another version throws an `ArgumentError`
naming the supported versions. A new version of the schema will get a new number;
`"spacetime/1"` scenes keep working.

[`SMLMView.Spacetime.validate_scene`](@ref) checks the declaration, every key the viewer
reads with its type, shape and range, and the optional parts before anything is built, and
throws one `ArgumentError` listing every problem. A scene it accepts builds and runs the
control self-test without throwing. `spacetime` calls it first.

The public, non-exported names of the `SMLMView.Spacetime` module are `example_scene`,
`validate_scene` and `scene_schema`; they are declared `public` on Julia 1.11 and later.

## Link opacity and width

The default mapping is amber with opacity equal to the link weight `w` and width 2. Both are
call-site choices, with no release needed:

```julia
spacetime(scene)                                            # alpha = w
spacetime(scene; link_alpha = w -> max(w, 0.15))            # a floor
spacetime(scene; link_alpha = sqrt)
spacetime(scene; link_alpha = _ -> 1, link_width = w -> 0.5 + 3w)   # width carries w
```

`link_alpha` is a function of `w`, its result clamped to `[0, 1]`. `link_width` is a number or
a function of `w` giving a per-segment width; a negative or non-finite width throws an
`ArgumentError` (for the function form it names the weight). The control self-test checks the
drawn colors (`links_alpha`) and widths (`links_width`) against the chosen mapping.

## Output routes

`output` selects where the view goes; the figure is always built fresh and its control
self-test runs first (a failed check throws before anything is served or written, except for
`output=:none`).

| `output` | result |
|---|---|
| `:auto` | `:serve` when `Main.ShipToolsRepl` is defined, else `:html` |
| `:serve` | `Main.ShipToolsRepl.wglshow(figure; open)`; `open=false` by default, then target one frontend with `sot-fe open-url <url> --fe <handle>` |
| `:server` | a Bonito server on `127.0.0.1:port` (`port` in 1:65535; the next free port when it is taken, and `view.url` names the port used), for a standalone script; prints the URL; `wait(view)` keeps the process serving, `close(view)` stops it |
| `:html` | standalone HTML at `html`; by default `spacetime.html` in a fresh `spacetime_*` folder under the temp directory, which persists after Julia exits |
| `:none` | build and self-test only; the returned `SpacetimeView` carries `health` |

```julia
view = spacetime(scene; output=:server, port=9384)   # in a script
wait(view)
```

The result is a [`SpacetimeView`](@ref). Its stable fields are `figure`, `axis`, `health` (the
control self-test result), `schema`, `url`, `html`, `versions` and `server`; `controls` is
internal state that may change in any release. `spacetime(scene; output=:none).health` is the
supported way to run the control self-test without serving. The figure is built inside
`with_theme(theme_dark())`, so the session's theme is not changed.

## Reference

[`spacetime`](@ref) and [`SpacetimeView`](@ref) are in the [API Reference](api.md).

```@docs
SMLMView.Spacetime.validate_scene
SMLMView.Spacetime.scene_schema
SMLMView.Spacetime.example_scene
```
