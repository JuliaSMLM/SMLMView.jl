# Geometry helpers: track paths, segment clipping, fixed-length padded buffers,
# frame-slab edges, layout hit tests and ROI bounds.

function _spacetime_paths(xs, ys, zs, fine_frames)
    continuous = Point3f[]
    gaps = Point3f[]
    separator = Point3f(NaN32, NaN32, NaN32)

    for index in eachindex(xs)
        point = Point3f(xs[index], ys[index], zs[index])
        if index > firstindex(xs) && fine_frames[index] - fine_frames[index - 1] > 1
            previous = Point3f(
                xs[index - 1],
                ys[index - 1],
                zs[index - 1],
            )
            push!(continuous, separator)
            append!(gaps, (previous, point, separator))
        end
        push!(continuous, point)
    end

    continuous, gaps
end

function _clip_spacetime_segment(first_point, second_point, bounds)
    all(isfinite, first_point) && all(isfinite, second_point) || return nothing

    x_lower, x_upper, y_lower, y_upper = bounds
    delta_x = second_point[1] - first_point[1]
    delta_y = second_point[2] - first_point[2]
    lower_fraction = 0.0f0
    upper_fraction = 1.0f0

    for (direction, distance) in (
        (-delta_x, first_point[1] - x_lower),
        (delta_x, x_upper - first_point[1]),
        (-delta_y, first_point[2] - y_lower),
        (delta_y, y_upper - first_point[2]),
    )
        if iszero(direction)
            distance >= 0 || return nothing
            continue
        end
        fraction = distance / direction
        if direction < 0
            lower_fraction = max(lower_fraction, fraction)
        else
            upper_fraction = min(upper_fraction, fraction)
        end
        lower_fraction <= upper_fraction || return nothing
    end

    delta_z = second_point[3] - first_point[3]
    (
        Point3f(
            first_point[1] + lower_fraction * delta_x,
            first_point[2] + lower_fraction * delta_y,
            first_point[3] + lower_fraction * delta_z,
        ),
        Point3f(
            first_point[1] + upper_fraction * delta_x,
            first_point[2] + upper_fraction * delta_y,
            first_point[3] + upper_fraction * delta_z,
        ),
    )
end

function _spacetime_line_segments(points, bounds=nothing)
    # WGLMakie may compact NaN vertices while leaving a separately uploaded
    # per-vertex color buffer unchanged. A finite, degenerate off-screen pair
    # keeps geometry and colors index-aligned through ROI updates.
    hidden = Point3f(-1.0f6, -1.0f6, -1.0f6)
    output = fill(hidden, 2 * max(length(points) - 1, 0))
    for second_index in 2:length(points)
        first_point = points[second_index - 1]
        second_point = points[second_index]
        clipped = if isnothing(bounds)
            all(isfinite, first_point) && all(isfinite, second_point) ?
                (first_point, second_point) : nothing
        else
            _clip_spacetime_segment(first_point, second_point, bounds)
        end
        isnothing(clipped) && continue
        output_index = 2 * (second_index - 2) + 1
        output[output_index] = clipped[1]
        output[output_index + 1] = clipped[2]
    end
    output
end

function _spacetime_segment_colors(colors)
    output = Vector{eltype(colors)}(undef, 2 * max(length(colors) - 1, 0))
    for second_index in 2:length(colors)
        output_index = 2 * (second_index - 2) + 1
        output[output_index] = colors[second_index - 1]
        output[output_index + 1] = colors[second_index]
    end
    output
end

function _spacetime_clipped_points(points, bounds)
    hidden = Point3f(-1.0f6, -1.0f6, -1.0f6)
    x_lower, x_upper, y_lower, y_upper = bounds
    [
        all(isfinite, point) &&
        x_lower <= point[1] <= x_upper &&
        y_lower <= point[2] <= y_upper ? point : hidden
        for point in points
    ]
end

function _padded(values, capacity, filler)
    output = fill(filler, capacity)
    copyto!(output, 1, values, 1, min(length(values), capacity))
    output
end

function _frame_slab_edges(
    frame_index,
    x_lower,
    x_upper,
    y_lower,
    y_upper,
)
    lower = Float32(frame_index) - 0.46f0
    upper = Float32(frame_index) + 0.46f0
    corners = (
        Point3f(x_lower, y_lower, lower),
        Point3f(x_upper, y_lower, lower),
        Point3f(x_upper, y_upper, lower),
        Point3f(x_lower, y_upper, lower),
        Point3f(x_lower, y_lower, upper),
        Point3f(x_upper, y_lower, upper),
        Point3f(x_upper, y_upper, upper),
        Point3f(x_lower, y_upper, upper),
    )
    edge_indices = (
        (1, 2), (2, 3), (3, 4), (4, 1),
        (5, 6), (6, 7), (7, 8), (8, 5),
        (1, 5), (2, 6), (3, 7), (4, 8),
    )
    reduce(vcat, ([corners[first(edge)], corners[last(edge)]]
                  for edge in edge_indices))
end

function _inside_layout(position, layout_object)
    bbox = layout_object.layoutobservables.computedbbox[]
    extent = widths(bbox)
    bbox.origin[1] <= position[1] <= bbox.origin[1] + extent[1] &&
        bbox.origin[2] <= position[2] <= bbox.origin[2] + extent[2]
end

function _xy_bounds(limits, x_extent, y_extent)
    lower = minimum(limits)
    upper = maximum(limits)
    x_lower = clamp(lower[1], 0, x_extent)
    x_upper = clamp(upper[1], 0, x_extent)
    y_lower = clamp(lower[2], 0, y_extent)
    y_upper = clamp(upper[2], 0, y_extent)
    x_lower < x_upper && y_lower < y_upper || return nothing
    Float32.((x_lower, x_upper, y_lower, y_upper))
end
