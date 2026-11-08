#=============================================================================
# Helper functions for viewer
=============================================================================#

"""
    extract_slice_raw(data, display_dims, slice_indices) -> AbstractArray

Extract raw 2D slice WITHOUT display transformations (no flip/transpose).
Used for statistics calculation where we need actual values, not display-oriented data.
"""
function extract_slice_raw(data::AbstractArray{T,N},
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
    # Return view (no copy, no transformations)
    return @view data[idx...]
end

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
Format a numeric value for display in status bar. Zero and whole numbers (below 1e15) print
as integers; other values below 1e-3 or from 1e5 up in scientific notation.
"""
function format_value(val::Real)
    if isinteger(val) && abs(val) < 1e15
        string(round(Int64, val))
    elseif abs(val) < 1e-3 || abs(val) >= 1e5
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
    # Use permutedims instead of ' to avoid Adjoint wrapper issues with SubArrays
    flipped = reverse(slice_2d, dims=1)
    return collect(permutedims(flipped, (2, 1)))
end

"""
    mouse_data_position(ax) -> (x, y) or nothing

The mouse position in the axis's data coordinates, from the mouse pixel, the axis viewport,
its current limits, scales and reversal; `nothing` when the mouse is outside the viewport
(or the viewport has no size yet). Unlike `mouseposition(ax.scene)`, which reads the scene
camera, it is already right inside a listener on `ax.finallimits` (the camera can lag the
limits there).
"""
function mouse_data_position(ax)
    mp = events(ax.scene).mouseposition[]
    vp = ax.scene.viewport[]
    all(>(0), vp.widths) || return nothing
    fx = (mp[1] - vp.origin[1]) / vp.widths[1]
    fy = (mp[2] - vp.origin[2]) / vp.widths[2]
    (0 <= fx <= 1 && 0 <= fy <= 1) || return nothing
    lim = ax.finallimits[]
    return (axis_coordinate(fx, lim.origin[1], lim.widths[1], ax.xscale[], ax.xreversed[]),
            axis_coordinate(fy, lim.origin[2], lim.widths[2], ax.yscale[], ax.yreversed[]))
end

# The data coordinate at fraction `frac` across an axis from `lo` to `lo + w`, drawn through
# `scale` (identity, log10, ...) and possibly reversed.
function axis_coordinate(frac, lo, w, scale, reversed::Bool)
    reversed && (frac = 1 - frac)
    scale === identity && return lo + frac * w
    a, b = scale(lo), scale(lo + w)
    return Makie.inverse_transform(scale)(a + frac * (b - a))
end

"""
    normalize_to_range(values, (lo, hi)) -> Array{Float64}

`(values - lo) / (hi - lo)`, clamped to [-1, 2]: the colorrange becomes (0, 1) and every
value stays finite in Float32 (Makie draws in Float32), whatever the magnitude or width of
the range; a value beyond the range stays beyond it. NaN stays NaN.
"""
function normalize_to_range(values::AbstractArray, crange::Tuple{Real,Real})
    lo, hi = widen_range(Float64(crange[1]), Float64(crange[2]))  # never a zero span
    span = hi - lo
    if isfinite(span)
        return clamp.((values .- lo) ./ span, -1.0, 2.0)
    end
    # a span beyond Float64 (lo near -floatmax, hi near floatmax): halve everything first
    return clamp.((values ./ 2 .- lo / 2) ./ (hi / 2 - lo / 2), -1.0, 2.0)
end

"""
Update cursor position and pixel value from mouse position for ND data.
"""
function update_cursor_nd!(ax, data::AbstractArray{T,N},
                           obs_display_dims, slice_indices,
                           obs_pos, obs_val, obs_in_bounds) where {T,N}
    try
        mpos = mouse_data_position(ax)
        if isnothing(mpos)
            obs_in_bounds[] = false
        else
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
    finite_minimum(data) -> Float64

Minimum over the finite values of `data` (as `compute_colorrange_sampled` skips
non-finite ones); 0.0 when there are none. The log mapping's offset.
"""
function finite_minimum(data::AbstractArray{<:Number})
    m = Inf
    for val in data
        v = Float64(real(val))
        isfinite(v) && v < m && (m = v)
    end
    return isfinite(m) ? m : 0.0
end

"""
    log_value(x, offset) -> Float64

The log mapping of one value, `log10(x - offset + 1)`, in Float64 (an integer difference
could wrap) and without losing what Float64 holds: `log1p` keeps a difference far below 1
(`log10(1 + 1e-50)` would be 0), and a difference beyond Float64 (`x - offset` from
`-floatmax` to `floatmax`) is halved first. A value below `offset` (a -Inf pixel, or data
changed in place below a cached minimum) maps to 0, the bottom of the range; NaN stays NaN
and +Inf gives Inf.
"""
function log_value(x::Real, offset::Float64)
    v = Float64(x)
    d = v - offset
    isfinite(d) && return log1p(max(d, 0.0)) / log(10.0)
    isnan(d) && return NaN
    d < 0 && return 0.0
    isfinite(v) || return Inf
    # 1 + d = 2 (d/2 + 1/2), with d/2 = v/2 - offset/2 finite
    return log10(2.0) + log10(v / 2 - offset / 2 + 0.5)
end

"""
    log_values(slice, offset) -> Array{Float64}

The log mapping's drawn values, `log_value` of each value of `slice`.
"""
log_values(slice::AbstractArray, offset::Real) = log_value.(slice, Float64(offset))

"""
    log_range((lo, hi), offset) -> (Float64, Float64)

The colorrange `(lo, hi)` on the same log scale as `log_values(slice, offset)`, through the
same `log_value`. A range that still collapses (a constant) is widened as
`compute_colorrange_sampled` widens one.
"""
log_range(crange::Tuple{Real,Real}, offset::Real) =
    widen_range(log_value(crange[1], Float64(offset)), log_value(crange[2], Float64(offset)))

"""
    widen_range(lo, hi) -> (lo, hi)

`(lo, hi)` unchanged when `lo < hi`; otherwise `(lo, lo + w)` with `w = max(1, 1e-6|lo|)`,
or `(lo - w, lo)` where `lo + w` overflows.
"""
function widen_range(lo::Float64, hi::Float64)
    lo < hi && return (lo, hi)
    w = max(1.0, 1e-6 * abs(lo))
    return isfinite(lo + w) ? (lo, lo + w) : (lo - w, lo)
end

"""
    check_viewable(data, what="data")

Throw an `ArgumentError` unless `data` holds real values on one-based axes.
"""
function check_viewable(data::AbstractArray, what::AbstractString="data")
    eltype(data) <: Real || throw(ArgumentError(
        "$what has element type $(eltype(data)); smlmview shows real values, so pass " *
        "abs.(x), real.(x) or angle.(x) for complex data"))
    Base.has_offset_axes(data) && throw(ArgumentError(
        "$what has axes $(axes(data)); smlmview needs one-based axes " *
        "(for an OffsetArray, pass parent(x))"))
    return nothing
end

"""
    viewer_mappings(clip) -> Tuple

The mapping cycle of one viewer: `MAPPINGS` with the `clip` keyword as the `:linear`
entry's clip, so that keyword holds whenever the cycle returns to `:linear`.
"""
function viewer_mappings(clip::Tuple{Real,Real})
    0 <= clip[1] < clip[2] <= 1 ||
        throw(ArgumentError("clip $clip: need 0 <= clip[1] < clip[2] <= 1"))
    linear = merge(MAPPINGS[1], (; clip=(Float64(clip[1]), Float64(clip[2]))))
    return (linear, Base.tail(MAPPINGS)...)
end

"""
Mapping name for the status bar; `:linear` with a clip shows it, e.g. `linear 5-95%`.
"""
format_mapping(m) = m.name == :linear && m.clip != (0.0, 1.0) ?
    @sprintf("linear %g-%g%%", 100 * m.clip[1], 100 * m.clip[2]) : string(m.name)

"""
    check_display_dims(N, dd)

Throw an `ArgumentError` unless `dd` names two different dims of `1:N`.
"""
function check_display_dims(N::Int, dd::Tuple{Int,Int})
    all(d -> 1 <= d <= N, dd) ||
        throw(ArgumentError("display_dims $dd: each dim must be in 1:$N"))
    dd[1] != dd[2] || throw(ArgumentError("display_dims $dd: the two dims must differ"))
    return nothing
end

"""
    compute_colorrange_sampled(data, clip; max_samples=1_000_000) -> (lo, hi)

Intensity range over the finite values of `data`. With `clip == (0, 1)` it is the exact
minimum and maximum. Otherwise it is the `clip` quantiles, taken from every value when
`data` has at most `max_samples` of them, and from every `step`-th value
(`step = length(data) ÷ max_samples`) when it has more; if none of those samples is finite,
it is the exact minimum and maximum. Data with no finite value gives `(0.0, 1.0)`; a
constant `c` gives `(c, c + w)` with `w = max(1, 1e-6|c|)` (`(c - w, c)` where `c + w`
overflows). Both viewers draw values normalized to this range (`normalize_to_range`), so any
range stays drawable in Makie's Float32.
"""
function compute_colorrange_sampled(data::AbstractArray{<:Number}, clip::Tuple{Real,Real};
                                     max_samples::Int=1_000_000)
    npixels = length(data)
    full = clip[1] <= 0.0 && clip[2] >= 1.0
    step = npixels <= max_samples ? 1 : npixels ÷ max_samples

    # One pass: exact extrema of the finite values, and the samples for the quantiles
    lo, hi = Inf, -Inf
    samples = Float64[]
    full || sizehint!(samples, min(npixels, max_samples + 1))
    idx = 0
    for val in data
        idx += 1
        v = Float64(real(val))
        isfinite(v) || continue
        v < lo && (lo = v)
        v > hi && (hi = v)
        !full && idx % step == 0 && push!(samples, v)
    end
    isfinite(lo) || return (0.0, 1.0)
    if !full && !isempty(samples)
        lo, hi = quantile(samples, (clip[1], clip[2]))
    end

    # hi above lo, also where lo + 1 == lo (|lo| > 2^53); near floatmax, widen downward
    return widen_range(Float64(lo), Float64(hi))
end
