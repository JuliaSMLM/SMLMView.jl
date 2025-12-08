module SMLMView

using WGLMakie
import WGLMakie.Bonito
using Observables
using Statistics
using Printf

export smlmview

#=============================================================================
# Constants
=============================================================================#

const ZOOM_LEVELS = (0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0)
const DEFAULT_ZOOM_IDX = 3  # 1.0x (index into ZOOM_LEVELS)

#=============================================================================
# Main viewer function
=============================================================================#

"""
    smlmview(data::AbstractMatrix; kwargs...) -> NamedTuple

Launch an interactive viewer for 2D array data.

# Arguments
- `data`: 2D numeric array to display

# Keyword Arguments
- `clip::Tuple{Real,Real}=(0.001, 0.999)`: Percentile clipping for intensity stretch
- `title::String=""`: Window/axis title
- `colormap::Symbol=:grays`: Colormap for display
- `figsize::Tuple{Int,Int}=(800, 700)`: Figure size in pixels
- `show::Bool=true`: Whether to display the figure immediately

# Returns
NamedTuple with:
- `fig`: The Makie Figure
- `ax`: The image Axis
- `data`: The processed display data (Float64 matrix)
- `colorrange`: Observable for intensity range
- `cursor_pos`: Observable for cursor (row, col) position
- `pixel_value`: Observable for value under cursor

# Example
```julia
using WGLMakie
import WGLMakie.Bonito
Bonito.configure_server!(listen_port=9384, listen_url="127.0.0.1")
Bonito.Server(listen_url="127.0.0.1", listen_port=9384)  # Start server

using SMLMView

data = rand(256, 256) .* 1000
v = smlmview(data)

# Programmatic control:
v.colorrange[] = (0.0, 500.0)  # Adjust intensity range
```

# Keyboard Shortcuts
- `i`: Zoom in (see fewer pixels, each larger)
- `o`: Zoom out (see more pixels, each smaller)
- `r`: Reset view (fit entire image)
- `e/s/d/f`: Pan up/left/down/right (ESDF layout)

# Notes
- Data is displayed with standard image orientation: row 1 at top, col 1 at left
- Status bar shows (row, col) = value format matching Julia array indexing
- Mouse hover continuously updates cursor position and value
- Zoom levels: 1/4x, 1/2x, 1x, 2x, 4x, 8x, 16x (pixel magnification)
"""
function smlmview(data::AbstractMatrix{T};
                  clip::Tuple{Real,Real}=(0.001, 0.999),
                  title::String="",
                  colormap::Symbol=:grays,
                  figsize::Tuple{Int,Int}=(800, 700),
                  show::Bool=true) where T<:Number
    # Note: Bonito server must be configured BEFORE calling this function
    # Use: Bonito.configure_server!(listen_port=9384, listen_url="127.0.0.1")

    # Process data: convert to Float64, handle complex/NaN/Inf
    display_data = sanitize_data(data)
    nrows, ncols = size(display_data)

    # Compute intensity range with percentile clipping
    crange = compute_colorrange(display_data, clip)

    # Create observables for reactive UI
    obs_colorrange = Observable(crange)
    obs_cursor_pos = Observable((1, 1))
    obs_pixel_value = Observable(display_data[1, 1])
    obs_in_bounds = Observable(false)

    # Zoom state
    obs_view_zoom_idx = Observable(DEFAULT_ZOOM_IDX)  # View zoom (i/o)
    obs_view_center = Observable((nrows / 2.0, ncols / 2.0))  # (row, col)

    # Calculate figure size based on image aspect ratio
    # Scale so largest dimension fits in figsize, maintaining aspect
    img_aspect = ncols / nrows  # width/height
    max_w, max_h = figsize
    if img_aspect > max_w / max_h
        # Image is wider than figure - constrain by width
        fig_w = max_w
        fig_h = round(Int, max_w / img_aspect) + 30  # +30 for status bar
    else
        # Image is taller than figure - constrain by height
        fig_h = max_h
        fig_w = round(Int, (max_h - 30) * img_aspect)  # -30 for status bar
    end
    actual_fig_size = (fig_w, fig_h)

    # Build figure sized to image aspect ratio
    fig = Figure(size=actual_fig_size)

    # Image axis - clean display, no decorations (like dipshow)
    ax = Axis(fig[2, 1];
              aspect=DataAspect(),
              yreversed=true)

    # Hide everything - just show the image
    hidedecorations!(ax)
    hidespines!(ax)

    # Display image as heatmap
    # Note: heatmap expects data as (x, y) but Julia arrays are (row, col)
    # So we transpose: display_data' maps data[row,col] to screen position (x=col, y=row)
    heatmap!(ax, display_data';
             colorrange=obs_colorrange,
             colormap=colormap,
             interpolate=false)

    # Function to update view limits based on zoom and center
    function update_view_limits!()
        view_zoom = ZOOM_LEVELS[obs_view_zoom_idx[]]
        center_row, center_col = obs_view_center[]

        # Visible region at current zoom (maintains image aspect ratio)
        visible_cols = ncols / view_zoom
        visible_rows = nrows / view_zoom

        half_w = visible_cols / 2
        half_h = visible_rows / 2

        # Clamp center so limits stay within image bounds [0.5, size+0.5]
        # This prevents the axis from repositioning due to out-of-bounds limits
        if visible_cols < ncols
            center_col = clamp(center_col, 0.5 + half_w, ncols + 0.5 - half_w)
        else
            center_col = (ncols + 1) / 2  # center when fully zoomed out
        end

        if visible_rows < nrows
            center_row = clamp(center_row, 0.5 + half_h, nrows + 0.5 - half_h)
        else
            center_row = (nrows + 1) / 2  # center when fully zoomed out
        end

        # Update observable with clamped center
        obs_view_center[] = (center_row, center_col)

        # Calculate clamped limits
        x_lo = center_col - half_w
        x_hi = center_col + half_w
        y_lo = center_row - half_h
        y_hi = center_row + half_h

        limits!(ax, x_lo, x_hi, y_lo, y_hi)
    end

    # Function to reset view (fit entire image)
    function reset_view!()
        obs_view_center[] = (nrows / 2.0, ncols / 2.0)
        obs_view_zoom_idx[] = DEFAULT_ZOOM_IDX  # 1x = full image
        limits!(ax, 0.5, ncols + 0.5, 0.5, nrows + 0.5)
    end

    # Pan function: move view by (dcol, drow) in units of jump size
    function pan!(dcol, drow)
        view_zoom = ZOOM_LEVELS[obs_view_zoom_idx[]]
        visible_cols = ncols / view_zoom
        visible_rows = nrows / view_zoom

        # Jump = 1/4 of minimum visible dimension
        jump = min(visible_cols, visible_rows) / 4

        center_row, center_col = obs_view_center[]
        new_col = center_col + dcol * jump
        new_row = center_row + drow * jump

        obs_view_center[] = (new_row, new_col)
        update_view_limits!()
    end

    # Initial view: show full image
    reset_view!()

    # Keyboard event handlers (WGLMakie compatible)
    on(events(fig).keyboardbutton) do event
        # WGLMakie KeyEvent: check key and action fields
        try
            if event.action in (Makie.Keyboard.press, Makie.Keyboard.repeat)
                if event.key == Makie.Keyboard.r
                    reset_view!()
                elseif event.key == Makie.Keyboard.i
                    if obs_view_zoom_idx[] < length(ZOOM_LEVELS)
                        obs_view_zoom_idx[] += 1
                        update_view_limits!()
                    end
                elseif event.key == Makie.Keyboard.o
                    if obs_view_zoom_idx[] > 1
                        obs_view_zoom_idx[] -= 1
                        update_view_limits!()
                    end
                # Pan with ESDF keys
                elseif event.key == Makie.Keyboard.e
                    pan!(0, -1)  # up (toward row 1)
                elseif event.key == Makie.Keyboard.d
                    pan!(0, 1)   # down (toward higher rows)
                elseif event.key == Makie.Keyboard.s
                    pan!(-1, 0)  # left (toward col 1)
                elseif event.key == Makie.Keyboard.f
                    pan!(1, 0)   # right (toward higher cols)
                end
            end
        catch e
            @warn "Keyboard event error" exception=e
        end
        return Consume(false)
    end

    # Status bar with cursor info and zoom
    status_text = @lift begin
        pos = $(obs_cursor_pos)
        val = $(obs_pixel_value)
        in_bounds = $(obs_in_bounds)
        view_zoom = ZOOM_LEVELS[$(obs_view_zoom_idx)]

        pos_str = in_bounds ? "($(pos[1]), $(pos[2])) = $(format_value(val))" : "---"
        zoom_str = format_zoom(view_zoom)
        "$(pos_str) | Zoom: $(zoom_str) | $(nrows)×$(ncols) $(T)"
    end

    Label(fig[1, :], status_text;
          fontsize=12,
          halign=:left,
          tellwidth=false)

    # Mouse hover tracking
    on(events(ax.scene).mouseposition) do _
        update_cursor!(ax, display_data, obs_cursor_pos, obs_pixel_value, obs_in_bounds)
    end

    # Display the figure if requested
    if show
        display(fig)
    end

    # Return handle for programmatic control
    return (;
        fig,
        ax,
        data=display_data,
        colorrange=obs_colorrange,
        cursor_pos=obs_cursor_pos,
        pixel_value=obs_pixel_value,
        view_zoom_idx=obs_view_zoom_idx,
        view_center=obs_view_center
    )
end

#=============================================================================
# Helper functions
=============================================================================#

"""
Convert input data to Float64, handling complex numbers and non-finite values.
"""
function sanitize_data(data::AbstractMatrix)
    # Convert to Float64, taking real part of complex
    result = Matrix{Float64}(undef, size(data))
    for i in eachindex(data)
        val = Float64(real(data[i]))
        result[i] = isfinite(val) ? val : zero(Float64)
    end
    return result
end

"""
Compute display colorrange based on percentile clipping.
"""
function compute_colorrange(data::AbstractMatrix, clip::Tuple{Real,Real})
    # Filter to finite values only
    finite_vals = filter(isfinite, vec(data))

    if isempty(finite_vals)
        return (0.0, 1.0)
    end

    # Compute range
    lo, hi = if clip == (0.0, 1.0)
        extrema(finite_vals)
    else
        quantile(finite_vals, (clip[1], clip[2]))
    end

    # Ensure valid range (lo < hi)
    if lo >= hi
        hi = lo + oneunit(lo)
    end

    return (Float64(lo), Float64(hi))
end

"""
Format a numeric value for display in status bar.
"""
function format_value(val::Real)
    if abs(val) < 1e-3 || abs(val) >= 1e5
        @sprintf("%.3e", val)
    elseif val == round(val)
        string(round(Int, val))
    else
        @sprintf("%.3f", val)
    end
end

"""
Format zoom level for display (e.g., "2x", "1/4x").
"""
function format_zoom(z::Real)
    if z >= 1
        "$(Int(z))x"
    else
        "1/$(Int(1/z))x"
    end
end

"""
Update cursor position and pixel value from mouse position.
"""
function update_cursor!(ax, data, obs_pos, obs_val, obs_in_bounds)
    try
        mpos = mouseposition(ax.scene)
        if !isnothing(mpos)
            col = round(Int, mpos[1])
            row = round(Int, mpos[2])
            nrows, ncols = size(data)

            if 1 <= row <= nrows && 1 <= col <= ncols
                obs_pos[] = (row, col)
                obs_val[] = data[row, col]
                obs_in_bounds[] = true
            else
                obs_in_bounds[] = false
            end
        end
    catch
        # Silently handle edge cases (mouse outside scene, etc.)
        obs_in_bounds[] = false
    end
    return nothing
end

end # module
