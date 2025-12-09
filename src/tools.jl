#=============================================================================
# Helper functions for viewer
=============================================================================#

"""
Convert keyboard key to number (1-9), or nothing.
"""
function key_to_number(key)
    key == Makie.Keyboard._1 && return 1
    key == Makie.Keyboard._2 && return 2
    key == Makie.Keyboard._3 && return 3
    key == Makie.Keyboard._4 && return 4
    key == Makie.Keyboard._5 && return 5
    key == Makie.Keyboard._6 && return 6
    key == Makie.Keyboard._7 && return 7
    key == Makie.Keyboard._8 && return 8
    key == Makie.Keyboard._9 && return 9
    return nothing
end

"""
Format dimension label for slider.
"""
function format_dim_label(dim::Int, dim_names::Nothing)
    "dim $dim:"
end

function format_dim_label(dim::Int, dim_names::NTuple{N,String}) where N
    dim <= N ? "$(dim_names[dim]):" : "dim $dim:"
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
Prepare a 2D slice from ND data for display.
display_dims = (row_dim, col_dim)
"""
function prepare_slice_nd(data::AbstractArray{T,N},
                          display_dims::Tuple{Int,Int},
                          slice_indices::Vector{Observable{Int}}) where {T,N}
    # Build index tuple
    idx = ntuple(N) do i
        if i == display_dims[1] || i == display_dims[2]
            Colon()
        else
            slice_indices[i][]
        end
    end

    # Get 2D slice (this is a view, then we collect)
    slice_raw = data[idx...]

    # The slice has shape corresponding to the two Colon() dims
    # We need to orient it: display_dims[1] → rows (vertical), display_dims[2] → cols (horizontal)
    # After indexing, if display_dims[1] < display_dims[2], the result is naturally (dim1, dim2)
    # If display_dims[1] > display_dims[2], the result is (dim2, dim1), need transpose
    if display_dims[1] > display_dims[2]
        slice_2d = permutedims(slice_raw, (2, 1))
    else
        slice_2d = slice_raw
    end

    # Flip rows so row 1 is at top, then transpose for heatmap (cols→X, rows→Y)
    return collect(reverse(slice_2d, dims=1)')
end

"""
Update cursor position and pixel value from mouse position for ND data.
"""
function update_cursor_nd!(ax, data::AbstractArray{T,N},
                           obs_display_dims, slice_indices,
                           obs_pos, obs_val, obs_in_bounds) where {T,N}
    try
        mpos = mouseposition(ax.scene)
        if !isnothing(mpos)
            dd = obs_display_dims[]
            nrows = size(data, dd[1])
            ncols = size(data, dd[2])

            col = round(Int, mpos[1])
            screen_y = round(Int, mpos[2])

            # Convert screen y to original row (flipped display)
            row = nrows - screen_y + 1

            if 1 <= row <= nrows && 1 <= col <= ncols
                obs_pos[] = (row, col)

                # Build full index for value lookup
                idx = ntuple(N) do i
                    if i == dd[1]
                        row
                    elseif i == dd[2]
                        col
                    else
                        slice_indices[i][]
                    end
                end

                obs_val[] = Float64(real(data[idx...]))
                obs_in_bounds[] = true
            else
                obs_in_bounds[] = false
            end
        end
    catch
        obs_in_bounds[] = false
    end
    return nothing
end

"""
Compute colorrange by sampling (no full copy).
"""
function compute_colorrange_sampled(data::AbstractArray{<:Number}, clip::Tuple{Real,Real};
                                     max_samples::Int=1_000_000)
    npixels = length(data)

    if npixels <= max_samples
        # Small enough to scan all
        lo, hi = typemax(Float64), typemin(Float64)
        for val in data
            v = Float64(real(val))
            if isfinite(v)
                lo = min(lo, v)
                hi = max(hi, v)
            end
        end

        if clip != (0.0, 1.0) && npixels > 0
            # Need quantiles, collect samples
            samples = Float64[]
            for val in data
                v = Float64(real(val))
                isfinite(v) && push!(samples, v)
            end
            if !isempty(samples)
                lo, hi = quantile(samples, (clip[1], clip[2]))
            end
        end
    else
        # Sample uniformly
        step = max(1, npixels ÷ max_samples)
        samples = Float64[]
        sizehint!(samples, max_samples)

        idx = 0
        for val in data
            idx += 1
            if idx % step == 0
                v = Float64(real(val))
                isfinite(v) && push!(samples, v)
            end
        end

        if isempty(samples)
            return (0.0, 1.0)
        end

        if clip == (0.0, 1.0)
            lo, hi = extrema(samples)
        else
            lo, hi = quantile(samples, (clip[1], clip[2]))
        end
    end

    # Ensure valid range
    if lo >= hi
        hi = lo + oneunit(lo)
    end

    return (Float64(lo), Float64(hi))
end
