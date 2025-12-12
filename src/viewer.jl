#=============================================================================
# Main viewer function - ND implementation
=============================================================================#

"""
    smlmview(data::AbstractArray{T,N}; kwargs...) -> NamedTuple

Launch an interactive viewer for N-dimensional array data (N ≥ 2).

# Arguments
- `data`: N-dimensional numeric array to display

# Keyword Arguments
- `display_dims::Tuple{Int,Int}=(1,2)`: Which dims to display (row_dim, col_dim)
- `dim_names::Union{Nothing,NTuple{N,String}}=nothing`: Optional labels for each dimension
- `clip::Tuple{Real,Real}=(0.0, 1.0)`: Percentile clipping for intensity stretch (0.0, 1.0 = full range)
- `title::String=""`: Window/axis title
- `colormap::Symbol=:grays`: Colormap for display
- `figsize::Tuple{Int,Int}=(800, 700)`: Maximum figure size in pixels
- `show::Bool=true`: Whether to display the figure immediately

# Returns
NamedTuple with:
- `fig`: The Makie Figure
- `ax`: The image Axis
- `data`: Reference to original array (no copy)
- `display_dims`: Observable for current display dimensions
- `slice_indices`: Vector of Observables for each dim's slice index
- `colorrange`: Observable for intensity range
- `cursor_pos`: Observable for cursor (row, col) position
- `pixel_value`: Observable for value under cursor

# Keyboard Shortcuts
- `1`-`9` + `1`-`9`: Two-number sequence sets display_dims (e.g., `21` for transpose)
- `c`: Cycle colormap (grays, inferno, viridis, turbo, plasma, twilight)
- `m`: Cycle mapping (linear, log, p1_99, p5_95)
- `g`: Cycle stretch mode (global, slice)
- `r`: Reset view (fit entire image)
- `i`/`o`: Zoom in/out
- `e`/`s`/`d`/`f`: Pan up/left/down/right
- `j`/`l`: Previous/next slice on first slider dim

# Example
```julia
using SMLMView

# 3D data
data3d = rand(256, 256, 10)
v = smlmview(data3d)

# 4D data with custom display
data4d = rand(64, 64, 10, 5)
v = smlmview(data4d; display_dims=(1, 3), dim_names=("Y", "X", "Z", "T"))

# Change view interactively: press 2 then 3 to show dims (2,3)
```

# Notes
- Data is displayed with standard image orientation: row 1 at top, col 1 at left
- Status bar shows current display dims: (1,2) means dim1→rows, dim2→cols
- For N-dim data, N-2 sliders are created for non-display dimensions
"""
function smlmview(data::AbstractArray{T,N};
                  display_dims::Tuple{Int,Int}=(1, 2),
                  dim_names::Union{Nothing,NTuple{N,String}}=nothing,
                  clip::Tuple{Real,Real}=(0.0, 1.0),
                  title::String="",
                  colormap::Symbol=:grays,
                  figsize::Tuple{Int,Int}=(800, 700),
                  show::Bool=true) where {T<:Number, N}

    # Validate
    N >= 2 || throw(ArgumentError("Data must have at least 2 dimensions"))
    1 <= display_dims[1] <= N || throw(ArgumentError("display_dims[1] out of range"))
    1 <= display_dims[2] <= N || throw(ArgumentError("display_dims[2] out of range"))
    display_dims[1] != display_dims[2] || throw(ArgumentError("display_dims must be different"))

    # Auto-configure Bonito if not already done
    ensure_display_configured!()

    # Keep reference to original data - no copy!
    data_size = size(data)
    n_sliders = N - 2

    # Compute global intensity range by sampling (no full copy)
    crange = compute_colorrange_sampled(data, clip)

    # Create observables
    obs_display_dims = Observable(display_dims)
    obs_colorrange = Observable(crange)
    obs_cursor_pos = Observable((1, 1))
    obs_pixel_value = Observable(Float64(real(data[ones(Int, N)...])))
    obs_in_bounds = Observable(false)

    # Slice indices for ALL dimensions (1-based)
    slice_indices = [Observable(1) for _ in 1:N]

    # Track which dims each slider controls (sorted non-display dims)
    obs_slider_to_dim = Observable(sort(collect(setdiff(1:N, display_dims))))

    # Pending dim key for two-number sequence
    pending_dim_key = Observable{Union{Nothing,Int}}(nothing)
    pending_dim_time = Ref(0.0)

    # Colormap state - find initial index or default to first
    initial_cmap_idx = findfirst(==(colormap), COLORMAPS)
    obs_colormap_idx = Observable(initial_cmap_idx === nothing ? 1 : initial_cmap_idx)
    obs_colormap = @lift COLORMAPS[$(obs_colormap_idx)]

    # Mapping state (intensity transform + clip)
    obs_mapping_idx = Observable(1)  # Default to linear
    obs_mapping = @lift MAPPINGS[$(obs_mapping_idx)]

    # Stretch mode state (global vs per-slice scaling)
    obs_stretch_idx = Observable(1)  # Default to global
    obs_stretch = @lift STRETCH_MODES[$(obs_stretch_idx)]

    # Zoom state
    obs_view_zoom_idx = Observable(DEFAULT_ZOOM_IDX)
    obs_view_center = Observable((0.0, 0.0))  # Will be set by reset_view!

    # Current slice data - reactive to display_dims and slice_indices
    obs_slice_data = Observable(prepare_slice_nd(data, display_dims, slice_indices))

    # Coordinate observables - must update when display_dims changes
    # These ensure heatmap coordinate grid matches data shape
    initial_nrows = data_size[display_dims[1]]
    initial_ncols = data_size[display_dims[2]]
    obs_xs = Observable(1:initial_ncols)
    obs_ys = Observable(1:initial_nrows)

    # Apply intensity transform to slice data
    function apply_transform(slice::AbstractMatrix, transform::Symbol)
        if transform == :log
            # Log transform: shift to positive, take log10
            min_val = minimum(slice)
            shifted = slice .- min_val .+ 1.0  # Ensure all positive
            return log10.(shifted)
        else
            return slice
        end
    end

    # Update colorrange based on current mapping and stretch mode
    function update_colorrange!()
        mapping = obs_mapping[]
        stretch = obs_stretch[]

        # Get source data for colorrange: global dataset or current slice
        # Use extract_slice_raw (not prepare_slice_nd) to get raw values without display transforms
        if stretch == :global
            source_data = data
        else  # :slice
            source_data = extract_slice_raw(data, obs_display_dims[], slice_indices)
        end

        crange = compute_colorrange_sampled(source_data, mapping.clip)
        if mapping.transform == :log
            # Transform the range for log display
            lo, hi = crange
            min_data = minimum(source_data)
            lo_shifted = lo - min_data + 1.0
            hi_shifted = hi - min_data + 1.0
            crange = (log10(max(lo_shifted, 1.0)), log10(max(hi_shifted, 1.0)))
        end
        obs_colorrange[] = crange
    end

    # Update slice AND coordinates when display_dims or any slice_index changes
    function update_slice!()
        dd = obs_display_dims[]
        mapping = obs_mapping[]
        # Update coordinate ranges FIRST to avoid size mismatch during render
        # (If data updates before coords, Makie tiles/stretches to fit old coords)
        obs_xs[] = 1:data_size[dd[2]]  # ncols
        obs_ys[] = 1:data_size[dd[1]]  # nrows
        # Get raw slice, apply transform
        raw_slice = prepare_slice_nd(data, dd, slice_indices)
        obs_slice_data[] = apply_transform(raw_slice, mapping.transform)
    end

    on(obs_display_dims) do _
        update_slice!()
        # Resize figure to match new aspect ratio
        new_size = calculate_figure_size()
        resize!(fig, new_size...)
        # Recreate heatmap to force WGLMakie texture reallocation with new dimensions
        empty!(ax)
        create_heatmap!()
    end

    for idx_obs in slice_indices
        on(idx_obs) do _
            update_slice!()
            # Update colorrange when in slice mode
            if obs_stretch[] == :slice
                update_colorrange!()
            end
        end
    end

    # When mapping changes, update colorrange and slice
    on(obs_mapping_idx) do _
        update_colorrange!()
        update_slice!()
    end

    # When stretch mode changes, update colorrange
    on(obs_stretch_idx) do _
        update_colorrange!()
    end

    # Get current display dimensions' sizes
    function get_display_sizes()
        dd = obs_display_dims[]
        nrows = data_size[dd[1]]
        ncols = data_size[dd[2]]
        return (nrows, ncols)
    end

    # UI height for status bar + sliders
    ui_height = 30 + 25 * max(0, n_sliders)

    # Calculate figure size based on image aspect ratio
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

    # Build figure
    fig = Figure(size=actual_fig_size)

    # Image axis - clean display, no decorations
    ax = Axis(fig[2, 1]; aspect=DataAspect())
    hidedecorations!(ax)
    hidespines!(ax)

    # Display current slice as heatmap with explicit coordinates
    # Store reference for recreation when display_dims changes (WGLMakie texture resize issue)
    hm_ref = Ref{Any}(nothing)

    function create_heatmap!()
        hm_ref[] = heatmap!(ax, obs_xs, obs_ys, obs_slice_data;
                           colorrange=obs_colorrange,
                           colormap=obs_colormap,
                           interpolate=false)
    end

    create_heatmap!()

    # Function to update view limits based on zoom and center
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

        x_lo = center_col - half_w
        x_hi = center_col + half_w
        y_lo = center_row - half_h
        y_hi = center_row + half_h

        limits!(ax, x_lo, x_hi, y_lo, y_hi)
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
        new_col = center_col + dcol * jump
        new_row = center_row + drow * jump

        obs_view_center[] = (new_row, new_col)
        update_view_limits!()
    end

    # Function to change display dims
    function set_display_dims!(new_dims::Tuple{Int,Int})
        if new_dims[1] != new_dims[2] &&
           1 <= new_dims[1] <= N &&
           1 <= new_dims[2] <= N &&
           new_dims != obs_display_dims[]
            obs_display_dims[] = new_dims
            obs_slider_to_dim[] = sort(collect(setdiff(1:N, new_dims)))
            reset_view!()
        end
    end

    # Initial view
    reset_view!()

    # Keyboard event handlers
    on(events(fig).keyboardbutton) do event
        try
            if event.action in (Makie.Keyboard.press, Makie.Keyboard.repeat)
                key = event.key

                # Check for number keys (dim selection)
                num = key_to_number(key)
                if num !== nothing && 1 <= num <= N
                    now = time()
                    if pending_dim_key[] !== nothing &&
                       now - pending_dim_time[] < DIM_KEY_TIMEOUT
                        # Second number within timeout
                        first = pending_dim_key[]
                        if first != num
                            set_display_dims!((first, num))
                        end
                        pending_dim_key[] = nothing
                    else
                        # First number, start sequence
                        pending_dim_key[] = num
                        pending_dim_time[] = now
                    end
                    return Consume(false)
                end

                # Cancel pending dim key on other keys
                pending_dim_key[] = nothing

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
                    # Navigate first slider dim
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
                elseif key == getkey("colormap_cycle")
                    # Cycle colormap
                    obs_colormap_idx[] = mod1(obs_colormap_idx[] + 1, length(COLORMAPS))
                elseif key == getkey("mapping_cycle")
                    # Cycle mapping (intensity transform + clip)
                    obs_mapping_idx[] = mod1(obs_mapping_idx[] + 1, length(MAPPINGS))
                elseif key == getkey("stretch_cycle")
                    # Cycle stretch mode (global vs per-slice)
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
        val = $(obs_pixel_value)
        in_bounds = $(obs_in_bounds)
        view_zoom = ZOOM_LEVELS[$(obs_view_zoom_idx)]
        dd = $(obs_display_dims)
        pending = $(pending_dim_key)
        slider_dims = $(obs_slider_to_dim)
        cmap = $(obs_colormap)
        mapping = $(obs_mapping)
        stretch = $(obs_stretch)

        pos_str = in_bounds ? "($(pos[1]), $(pos[2])) = $(format_value(val))" : "---"
        zoom_str = format_zoom(view_zoom)

        # Display dims indicator
        dims_str = if pending !== nothing
            "($(pending),?)"
        else
            "($(dd[1]),$(dd[2]))"
        end

        # Slider states
        slider_strs = String[]
        for dim in slider_dims
            push!(slider_strs, "$(dim):$(slice_indices[dim][])/$( data_size[dim])")
        end
        slider_str = isempty(slider_strs) ? "" : " | " * join(slider_strs, " ")

        # Size string
        size_str = join(data_size, "×")

        "$(pos_str) | $(dims_str)$(slider_str) | $(zoom_str) | $(cmap) | $(mapping.name) | $(stretch) | $(size_str) $(T)"
    end

    Label(fig[1, :], status_text;
          fontsize=12,
          halign=:left,
          tellwidth=false)

    # Create sliders for non-display dims
    sliders = []
    slider_labels_obs = Observable{String}[]
    slider_ranges_obs = Observable{UnitRange{Int}}[]

    for i in 1:n_sliders
        initial_dim = obs_slider_to_dim[][i]
        push!(slider_labels_obs, Observable(format_dim_label(initial_dim, dim_names)))
        push!(slider_ranges_obs, Observable(1:data_size[initial_dim]))
    end

    for i in 1:n_sliders
        # Layout: label and slider in same row
        sl_grid = fig[2 + i, 1] = GridLayout()
        Label(sl_grid[1, 1], slider_labels_obs[i]; fontsize=11, halign=:right, width=50)
        sl = Makie.Slider(sl_grid[1, 2], range=slider_ranges_obs[i], startvalue=1)
        push!(sliders, sl)

        # Slider → slice_index
        let i = i
            on(sl.value) do v
                dim = obs_slider_to_dim[][i]
                if slice_indices[dim][] != v
                    slice_indices[dim][] = v
                end
            end
        end
    end

    # slice_index → slider (for keyboard navigation)
    for dim in 1:N
        let dim = dim
            on(slice_indices[dim]) do v
                idx = findfirst(==(dim), obs_slider_to_dim[])
                if idx !== nothing && !isempty(sliders) && idx <= length(sliders)
                    if sliders[idx].value[] != v
                        set_close_to!(sliders[idx], v)
                    end
                end
            end
        end
    end

    # Update slider assignments when display_dims changes
    on(obs_slider_to_dim) do new_dims
        for (i, dim) in enumerate(new_dims)
            if i <= length(sliders)
                slider_labels_obs[i][] = format_dim_label(dim, dim_names)
                slider_ranges_obs[i][] = 1:data_size[dim]
                set_close_to!(sliders[i], slice_indices[dim][])
            end
        end
    end

    # Mouse hover tracking
    on(events(ax.scene).mouseposition) do _
        update_cursor_nd!(ax, data, obs_display_dims, slice_indices,
                          obs_cursor_pos, obs_pixel_value, obs_in_bounds)
    end

    # Update pixel value when slice changes (if cursor in bounds)
    for idx_obs in slice_indices
        on(idx_obs) do _
            if obs_in_bounds[]
                update_cursor_nd!(ax, data, obs_display_dims, slice_indices,
                                  obs_cursor_pos, obs_pixel_value, obs_in_bounds)
            end
        end
    end

    if show
        try
            display(fig)
        catch e
            @warn "display(fig) failed, returning figure for manual display" exception=e
        end
    end

    # Return handle
    return (;
        fig,
        ax,
        data=data,
        display_dims=obs_display_dims,
        slice_indices=slice_indices,
        colorrange=obs_colorrange,
        colormap=obs_colormap,
        colormap_idx=obs_colormap_idx,
        mapping=obs_mapping,
        mapping_idx=obs_mapping_idx,
        stretch=obs_stretch,
        stretch_idx=obs_stretch_idx,
        cursor_pos=obs_cursor_pos,
        pixel_value=obs_pixel_value,
        view_zoom_idx=obs_view_zoom_idx,
        view_center=obs_view_center
    )
end
