#=============================================================================
# Multi-channel composite viewer
=============================================================================#

"""
    smlmview(channels::Tuple{Vararg{AbstractArray}}; kwargs...) -> NamedTuple

Launch an interactive viewer for multi-channel composite display.

# Arguments
- `channels`: Tuple of 2-3 arrays with matching spatial dimensions

# Keyword Arguments
- `colors`: Channel colors, default CMY (cyan, magenta, yellow)
- `names`: Channel names for display
- `display_dims::Tuple{Int,Int}=(1,2)`: Which dims are (rows, cols)
- `clip::Tuple{Real,Real}=(0.001, 0.999)`: Percentile clipping
- `figsize::Tuple{Int,Int}=(800, 700)`: Max figure size
- `show::Bool=true`: Whether to display immediately

# Keyboard Shortcuts
- `1/2/3`: Toggle channel visibility
- `m`: Cycle mapping (linear, log, percentile)
- `g`: Cycle stretch mode (global, slice)
- `j/l`: Previous/next slice
- `i/o`: Zoom in/out
- `r`: Reset view

# Example
```julia
ch1 = rand(256, 256, 10)  # "DAPI"
ch2 = rand(256, 256, 10)  # "GFP"
ch3 = rand(256, 256, 10)  # "Alexa647"
v = smlmview((ch1, ch2, ch3); names=("DAPI", "GFP", "A647"))
```
"""
function smlmview(channels::NTuple{C, <:AbstractArray{T,N}};
                  colors::Union{Nothing, NTuple{C, RGB{Float64}}}=nothing,
                  names::Union{Nothing, NTuple{C, String}}=nothing,
                  display_dims::Tuple{Int,Int}=(1, 2),
                  clip::Tuple{Real,Real}=(0.001, 0.999),
                  title::String="",
                  figsize::Tuple{Int,Int}=(800, 700),
                  show::Bool=true) where {T<:Real, N, C}

    # Default colors: take first C from DEFAULT_CHANNEL_COLORS
    actual_colors = if colors === nothing
        ntuple(i -> DEFAULT_CHANNEL_COLORS[i], C)
    else
        colors
    end

    # Validate
    C >= 2 || throw(ArgumentError("Need at least 2 channels"))
    C <= 3 || throw(ArgumentError("Maximum 3 channels supported"))
    N >= 2 || throw(ArgumentError("Data must have at least 2 dimensions"))

    # Check all channels have same size
    ref_size = size(channels[1])
    for (i, ch) in enumerate(channels)
        size(ch) == ref_size || throw(ArgumentError("Channel $i size mismatch: $(size(ch)) vs $ref_size"))
    end

    # Auto-configure Bonito
    ensure_display_configured!()

    data_size = ref_size
    n_sliders = N - 2

    # Observables for each channel's colorrange (computed from data)
    channel_ranges = [Observable(compute_colorrange_sampled(ch, clip)) for ch in channels]

    # Channel visibility
    channel_visible = [Observable(true) for _ in 1:C]

    # Shared state
    obs_display_dims = Observable(display_dims)
    obs_cursor_pos = Observable((1, 1))
    obs_pixel_values = Observable(ntuple(i -> 0.0, C))  # Per-channel values
    obs_in_bounds = Observable(false)

    # Slice indices for all dims
    slice_indices = [Observable(1) for _ in 1:N]
    obs_slider_to_dim = Observable(sort(collect(setdiff(1:N, display_dims))))

    # Mapping state (global for all channels)
    obs_mapping_idx = Observable(1)
    obs_mapping = @lift MAPPINGS[$(obs_mapping_idx)]

    # Stretch mode (global for all channels)
    obs_stretch_idx = Observable(1)
    obs_stretch = @lift STRETCH_MODES[$(obs_stretch_idx)]

    # Zoom state
    obs_view_zoom_idx = Observable(DEFAULT_ZOOM_IDX)
    obs_view_center = Observable((0.0, 0.0))

    # Coordinate observables - use tuples (start, stop) for image! API
    initial_nrows = data_size[display_dims[1]]
    initial_ncols = data_size[display_dims[2]]
    obs_xs = Observable((0.5, initial_ncols + 0.5))
    obs_ys = Observable((0.5, initial_nrows + 0.5))

    # Get current display sizes
    function get_display_sizes()
        dd = obs_display_dims[]
        nrows = data_size[dd[1]]
        ncols = data_size[dd[2]]
        return (nrows, ncols)
    end

    # Apply transform to a slice
    function apply_transform(slice::AbstractMatrix, transform::Symbol)
        if transform == :log
            min_val = minimum(slice)
            shifted = slice .- min_val .+ 1.0
            return log10.(shifted)
        else
            return slice
        end
    end

    # Normalize a slice to 0-1 given colorrange
    function normalize_slice(slice::AbstractMatrix, crange::Tuple{Float64, Float64})
        lo, hi = crange
        return clamp.((slice .- lo) ./ (hi - lo), 0.0, 1.0)
    end

    # Composite channels into RGB matrix
    function composite_rgb()
        dd = obs_display_dims[]
        mapping = obs_mapping[]
        stretch = obs_stretch[]
        nrows = data_size[dd[1]]
        ncols = data_size[dd[2]]

        # Initialize RGB accumulator (note: after prepare_slice_nd, dims are (ncols, nrows) for heatmap)
        rgb_r = zeros(Float64, ncols, nrows)
        rgb_g = zeros(Float64, ncols, nrows)
        rgb_b = zeros(Float64, ncols, nrows)

        for i in 1:C
            channel_visible[i][] || continue

            # Get slice for this channel
            raw_slice = prepare_slice_nd(channels[i], dd, slice_indices)
            transformed = apply_transform(raw_slice, mapping.transform)

            # Compute colorrange based on stretch mode
            if stretch == :slice
                crange = compute_colorrange_sampled(transformed, mapping.clip)
            else
                # Use precomputed global range, transform if needed
                base_range = channel_ranges[i][]
                if mapping.transform == :log
                    min_ch = minimum(channels[i])
                    lo_shifted = base_range[1] - min_ch + 1.0
                    hi_shifted = base_range[2] - min_ch + 1.0
                    crange = (log10(max(lo_shifted, 1.0)), log10(max(hi_shifted, 1.0)))
                else
                    crange = base_range
                end
            end

            # Normalize and blend with channel color
            normalized = normalize_slice(transformed, crange)
            color = actual_colors[i]
            rgb_r .+= normalized .* red(color)
            rgb_g .+= normalized .* green(color)
            rgb_b .+= normalized .* blue(color)
        end

        # Clamp and convert to RGB matrix
        rgb_matrix = Matrix{RGB{Float64}}(undef, ncols, nrows)
        for j in 1:nrows, i in 1:ncols
            rgb_matrix[i, j] = RGB{Float64}(
                clamp(rgb_r[i, j], 0.0, 1.0),
                clamp(rgb_g[i, j], 0.0, 1.0),
                clamp(rgb_b[i, j], 0.0, 1.0)
            )
        end
        return rgb_matrix
    end

    # Observable for composite image
    obs_rgb = Observable(composite_rgb())

    # Update composite when anything changes
    function update_composite!()
        dd = obs_display_dims[]
        ncols = data_size[dd[2]]
        nrows = data_size[dd[1]]
        obs_xs[] = (0.5, ncols + 0.5)
        obs_ys[] = (0.5, nrows + 0.5)
        obs_rgb[] = composite_rgb()
    end

    # Connect updates
    on(obs_display_dims) do _
        update_composite!()
    end

    for idx_obs in slice_indices
        on(idx_obs) do _
            update_composite!()
        end
    end

    on(obs_mapping_idx) do _
        update_composite!()
    end

    on(obs_stretch_idx) do _
        update_composite!()
    end

    for vis in channel_visible
        on(vis) do _
            update_composite!()
        end
    end

    # UI height
    ui_height = 30 + 25 * max(0, n_sliders)

    # Figure size calculation
    function calculate_figure_size()
        nrows, ncols = get_display_sizes()
        img_aspect = ncols / nrows
        max_w, max_h = figsize
        if img_aspect > max_w / max_h
            fig_w = max_w
            fig_h = round(Int, max_w / img_aspect) + ui_height
        else
            fig_h = max_h
            fig_w = round(Int, (max_h - ui_height) * img_aspect)
        end
        return (fig_w, fig_h)
    end

    actual_fig_size = calculate_figure_size()
    fig = Figure(size=actual_fig_size)

    # Axis
    ax = Axis(fig[2, 1]; aspect=DataAspect())
    hidedecorations!(ax)
    hidespines!(ax)

    # Display using image! for RGB
    img_ref = Ref{Any}(nothing)

    function create_image!()
        img_ref[] = image!(ax, obs_xs, obs_ys, obs_rgb; interpolate=false)
    end

    create_image!()

    # View limits functions (same as grayscale viewer)
    function update_view_limits!()
        nrows, ncols = get_display_sizes()
        view_zoom = ZOOM_LEVELS[obs_view_zoom_idx[]]
        center_row, center_col = obs_view_center[]

        visible_cols = ncols / view_zoom
        visible_rows = nrows / view_zoom

        half_w = visible_cols / 2
        half_h = visible_rows / 2

        if visible_cols < ncols
            center_col = clamp(center_col, 0.5 + half_w, ncols + 0.5 - half_w)
        else
            center_col = (ncols + 1) / 2
        end

        if visible_rows < nrows
            center_row = clamp(center_row, 0.5 + half_h, nrows + 0.5 - half_h)
        else
            center_row = (nrows + 1) / 2
        end

        obs_view_center[] = (center_row, center_col)
        limits!(ax, center_col - half_w, center_col + half_w, center_row - half_h, center_row + half_h)
    end

    function reset_view!()
        nrows, ncols = get_display_sizes()
        obs_view_center[] = (nrows / 2.0, ncols / 2.0)
        obs_view_zoom_idx[] = DEFAULT_ZOOM_IDX
        limits!(ax, 0.5, ncols + 0.5, 0.5, nrows + 0.5)
    end

    function pan!(dcol, drow)
        nrows, ncols = get_display_sizes()
        view_zoom = ZOOM_LEVELS[obs_view_zoom_idx[]]
        visible_cols = ncols / view_zoom
        visible_rows = nrows / view_zoom
        jump = min(visible_cols, visible_rows) / 4

        center_row, center_col = obs_view_center[]
        obs_view_center[] = (center_row + drow * jump, center_col + dcol * jump)
        update_view_limits!()
    end

    reset_view!()

    # Keyboard handler
    on(events(fig).keyboardbutton) do event
        try
            if event.action in (Makie.Keyboard.press, Makie.Keyboard.repeat)
                key = event.key

                # Channel toggles (1, 2, 3)
                num = key_to_number(key)
                if num !== nothing && num <= C
                    channel_visible[num][] = !channel_visible[num][]
                    return Consume(false)
                end

                if key == getkey("reset")
                    reset_view!()
                elseif key == getkey("zoom_in")
                    if obs_view_zoom_idx[] < length(ZOOM_LEVELS)
                        obs_view_zoom_idx[] += 1
                        update_view_limits!()
                    end
                elseif key == getkey("zoom_out")
                    if obs_view_zoom_idx[] > 1
                        obs_view_zoom_idx[] -= 1
                        update_view_limits!()
                    end
                elseif key == getkey("pan_up")
                    pan!(0, 1)
                elseif key == getkey("pan_down")
                    pan!(0, -1)
                elseif key == getkey("pan_left")
                    pan!(-1, 0)
                elseif key == getkey("pan_right")
                    pan!(1, 0)
                elseif key == getkey("slice_prev")
                    slider_dims = obs_slider_to_dim[]
                    if !isempty(slider_dims)
                        dim = slider_dims[1]
                        if slice_indices[dim][] > 1
                            slice_indices[dim][] -= 1
                        end
                    end
                elseif key == getkey("slice_next")
                    slider_dims = obs_slider_to_dim[]
                    if !isempty(slider_dims)
                        dim = slider_dims[1]
                        if slice_indices[dim][] < data_size[dim]
                            slice_indices[dim][] += 1
                        end
                    end
                elseif key == getkey("mapping_cycle")
                    obs_mapping_idx[] = mod1(obs_mapping_idx[] + 1, length(MAPPINGS))
                elseif key == getkey("stretch_cycle")
                    obs_stretch_idx[] = mod1(obs_stretch_idx[] + 1, length(STRETCH_MODES))
                end
            end
        catch e
            @warn "Keyboard event error" exception=e
        end
        return Consume(false)
    end

    # Status bar
    status_text = @lift begin
        pos = $(obs_cursor_pos)
        vals = $(obs_pixel_values)
        in_bounds = $(obs_in_bounds)
        view_zoom = ZOOM_LEVELS[$(obs_view_zoom_idx)]
        mapping = $(obs_mapping)
        stretch = $(obs_stretch)
        slider_dims = $(obs_slider_to_dim)

        # Channel visibility indicators
        vis_str = join([channel_visible[i][] ? string(i) : "-" for i in 1:C], "")

        # Position and values
        if in_bounds
            val_strs = [format_value(vals[i]) for i in 1:C]
            pos_str = "($(pos[1]),$(pos[2])) = [$(join(val_strs, ", "))]"
        else
            pos_str = "---"
        end

        zoom_str = format_zoom(view_zoom)

        # Slider states
        slider_strs = String[]
        for dim in slider_dims
            push!(slider_strs, "$(dim):$(slice_indices[dim][])/$( data_size[dim])")
        end
        slider_str = isempty(slider_strs) ? "" : " | " * join(slider_strs, " ")

        size_str = join(data_size, "x")

        "$(pos_str) | ch:$(vis_str)$(slider_str) | $(zoom_str) | $(mapping.name) | $(stretch) | $(size_str)"
    end

    Label(fig[1, :], status_text; fontsize=12, halign=:left, tellwidth=false)

    # Sliders for non-display dims
    sliders = []
    slider_labels_obs = Observable{String}[]
    slider_ranges_obs = Observable{UnitRange{Int}}[]

    for i in 1:n_sliders
        initial_dim = obs_slider_to_dim[][i]
        push!(slider_labels_obs, Observable("dim $initial_dim:"))
        push!(slider_ranges_obs, Observable(1:data_size[initial_dim]))
    end

    for i in 1:n_sliders
        sl_grid = fig[2 + i, 1] = GridLayout()
        Label(sl_grid[1, 1], slider_labels_obs[i]; fontsize=11, halign=:right, width=50)
        sl = Makie.Slider(sl_grid[1, 2], range=slider_ranges_obs[i], startvalue=1)
        push!(sliders, sl)

        let i = i
            on(sl.value) do v
                dim = obs_slider_to_dim[][i]
                if slice_indices[dim][] != v
                    slice_indices[dim][] = v
                end
            end
        end
    end

    # Sync slice_index -> slider
    for dim in 1:N
        let dim = dim
            on(slice_indices[dim]) do v
                idx = findfirst(==(dim), obs_slider_to_dim[])
                if idx !== nothing && idx <= length(sliders)
                    if sliders[idx].value[] != v
                        set_close_to!(sliders[idx], v)
                    end
                end
            end
        end
    end

    # Mouse hover - update pixel values for all channels
    on(events(ax.scene).mouseposition) do _
        try
            mpos = mouseposition(ax.scene)
            if !isnothing(mpos)
                dd = obs_display_dims[]
                nrows = data_size[dd[1]]
                ncols = data_size[dd[2]]

                col = round(Int, mpos[1])
                screen_y = round(Int, mpos[2])
                row = nrows - screen_y + 1

                if 1 <= row <= nrows && 1 <= col <= ncols
                    obs_cursor_pos[] = (row, col)

                    # Get value from each channel
                    vals = ntuple(C) do i
                        idx = ntuple(N) do d
                            if d == dd[1]
                                row
                            elseif d == dd[2]
                                col
                            else
                                slice_indices[d][]
                            end
                        end
                        Float64(real(channels[i][idx...]))
                    end
                    obs_pixel_values[] = vals
                    obs_in_bounds[] = true
                else
                    obs_in_bounds[] = false
                end
            end
        catch
            obs_in_bounds[] = false
        end
    end

    if show
        try
            display(fig)
        catch e
            @warn "display(fig) failed" exception=e
        end
    end

    return (;
        fig,
        ax,
        channels=channels,
        colors=actual_colors,
        display_dims=obs_display_dims,
        slice_indices=slice_indices,
        channel_visible=channel_visible,
        channel_ranges=channel_ranges,
        mapping=obs_mapping,
        mapping_idx=obs_mapping_idx,
        stretch=obs_stretch,
        stretch_idx=obs_stretch_idx,
        cursor_pos=obs_cursor_pos,
        pixel_values=obs_pixel_values,
        view_zoom_idx=obs_view_zoom_idx,
        view_center=obs_view_center,
        rgb=obs_rgb
    )
end

