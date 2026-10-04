# The 2D frame inspector: frame axis, slider, toggles, ROI sync, track pick.

function _add_frame_inspector!(
    fig,
    ax,
    scene,
    roi_bounds,
    trajectory_source,
    track_sets,
)
    source_frames = scene["source_frames"]
    n_frames = length(source_frames)
    n_frames > 0 ||
        throw(ArgumentError("frame inspector requires at least one frame"))
    nx = scene["nx"]
    ny = scene["ny"]
    pixel_size = scene["pixel_size"]
    sub_steps = scene["sub_steps"]
    frame_track_sets = Dict(
        source => _frame_track_data(track_scene, n_frames, sub_steps)
        for (source, track_scene) in track_sets
    )
    has_ground_truth = haskey(frame_track_sets, :ground_truth)
    x_extent = Float32(nx * pixel_size)
    y_extent = Float32(ny * pixel_size)
    initial_frame = cld(n_frames, 2)

    selected_frame = Makie.Observable(initial_frame)
    selected_track = Makie.Observable(0)
    track_ids_active = Makie.Observable(false)
    browser_event_count = Makie.Observable(0)
    last_browser_action = Makie.Observable("awaiting first browser event")
    backend_health = Makie.Observable("backend: unchecked")
    browser_connection = Makie.Observable("browser: waiting")

    function record_browser_event!(action)
        browser_event_count[] = browser_event_count[] + 1
        last_browser_action[] = String(action)
        nothing
    end
    selected_core_color = Makie.lift(
        selected_track,
        trajectory_source,
    ) do track_index, source
        data = frame_track_sets[source]
        track_index == 0 || track_index > data.n_tracks ?
            RGBf(0.92, 0.94, 0.98) : data.track_core_colors[track_index]
    end
    selected_halo_color = Makie.lift(selected_core_color) do color
        RGBAf(color.r, color.g, color.b, 0.30f0)
    end
    slider_axis = Axis(
        fig[1, 4];
        limits=(0.0, 1.0, 0.5, n_frames + 0.5),
        width=48,
        backgroundcolor=RGBf(0.025, 0.027, 0.032),
    )
    hidedecorations!(slider_axis)
    hidespines!(slider_axis)
    lines!(
        slider_axis,
        Point2f[(0.5f0, 1.0f0), (0.5f0, Float32(n_frames))];
        color=RGBAf(0.42, 0.45, 0.50, 0.95),
        linewidth=8,
    )
    slider_handle = Makie.lift(selected_frame) do frame_index
        Point2f[Point2f(0.5f0, Float32(frame_index))]
    end
    scatter!(
        slider_axis,
        slider_handle;
        color=RGBf(0.10, 0.90, 1.00),
        markersize=18,
        strokecolor=RGBAf(0.02, 0.08, 0.10, 0.95),
        strokewidth=1.5,
    )

    controls = Makie.GridLayout(fig[2, 3:4])
    Label(
        controls[1, 1],
        "3D frame highlight";
        color=RGBf(0.84, 0.87, 0.91),
        fontsize=13,
        halign=:right,
    )
    highlight_active = Makie.Observable(true)
    toggle_color = Makie.lift(highlight_active) do active
        active ? RGBf(0.06, 0.58, 0.66) : RGBf(0.16, 0.18, 0.22)
    end
    toggle_text = Makie.lift(highlight_active) do active
        active ? "ON" : "OFF"
    end
    highlight_box = Box(
        controls[1, 2];
        color=toggle_color,
        strokecolor=RGBAf(0.10, 0.90, 1.00, 0.72),
        strokewidth=1.0,
        cornerradius=8,
        width=42,
        height=24,
        z=-1,
    )
    Label(
        controls[1, 2],
        toggle_text;
        color=RGBf(0.92, 0.96, 0.98),
        fontsize=11,
        tellwidth=false,
        tellheight=false,
    )
    Label(
        controls[1, 3],
        "Click point: select track  ·  Up / Down: frame  ·  zoom 2D: crop 3D ROI";
        color=RGBf(0.68, 0.72, 0.78),
        fontsize=12,
        halign=:left,
    )
    Label(
        controls[2, 1],
        "2D track IDs";
        color=RGBf(0.84, 0.87, 0.91),
        fontsize=13,
        halign=:right,
    )
    id_toggle_color = Makie.lift(track_ids_active) do active
        active ? RGBf(0.62, 0.10, 0.43) : RGBf(0.16, 0.18, 0.22)
    end
    id_toggle_text = Makie.lift(track_ids_active) do active
        active ? "ON" : "OFF"
    end
    id_toggle_box = Box(
        controls[2, 2];
        color=id_toggle_color,
        strokecolor=RGBAf(1.00, 0.22, 0.70, 0.78),
        strokewidth=1.0,
        cornerradius=8,
        width=42,
        height=24,
        z=-1,
    )
    Label(
        controls[2, 2],
        id_toggle_text;
        color=RGBf(0.96, 0.93, 0.97),
        fontsize=11,
        tellwidth=false,
        tellheight=false,
    )
    selected_track_text = Makie.lift(
        selected_track,
        trajectory_source,
    ) do track_index, source
        data = frame_track_sets[source]
        if track_index == 0 || track_index > data.n_tracks
            "Selected: none"
        else
            track_scene = data.track_scene
            id_description = get(
                track_scene,
                "track_id_description",
                "trajectory id",
            )
            matched_ids = Int.(get(track_scene, "matched_other_ids", Int[]))
            match_suffix = if length(matched_ids) < track_index
                ""
            elseif matched_ids[track_index] == 0
                "  ·  unmatched"
            elseif source === :found
                "  ·  matched GT id $(matched_ids[track_index])"
            else
                "  ·  matched found id $(matched_ids[track_index])"
            end
            "Selected: $(data.track_labels[track_index])  ·  $id_description " *
            "$(data.track_ids[track_index])$match_suffix"
        end
    end
    Label(
        controls[2, 3],
        selected_track_text;
        color=selected_core_color,
        fontsize=15,
        halign=:left,
    )
    source_toggle_box = nothing
    if has_ground_truth
        Label(
            controls[3, 1],
            "Trajectory source";
            color=RGBf(0.84, 0.87, 0.91),
            fontsize=13,
            halign=:right,
        )
        source_toggle_color = Makie.lift(trajectory_source) do source
            source === :ground_truth ? RGBf(0.16, 0.64, 0.28) :
                RGBf(0.20, 0.34, 0.68)
        end
        source_toggle_text = Makie.lift(trajectory_source) do source
            source === :ground_truth ? "GT" : "FOUND"
        end
        source_toggle_box = Box(
            controls[3, 2];
            color=source_toggle_color,
            strokecolor=RGBAf(0.62, 0.94, 0.72, 0.82),
            strokewidth=1.0,
            cornerradius=8,
            width=68,
            height=24,
            z=-1,
        )
        Label(
            controls[3, 2],
            source_toggle_text;
            color=RGBf(0.94, 0.98, 0.95),
            fontsize=11,
            tellwidth=false,
            tellheight=false,
        )
        Label(
            controls[3, 3],
            if haskey(scene, "trajectory_color_matches")
                matches = scene["trajectory_color_matches"]
                gate = scene["trajectory_color_match_gate"]
                "$(length(matches)) shared colors: optimal GT↔FOUND identity " *
                "match ($(round(gate, digits=2)) μm gate); unmatched remain unique"
            else
                "FOUND: $(_set_display_name(frame_track_sets[:found], :found))" *
                "  ·  GT: $(_set_display_name(frame_track_sets[:ground_truth], :ground_truth))"
            end;
            color=RGBf(0.68, 0.72, 0.78),
            fontsize=12,
            halign=:left,
            justification=:left,
            word_wrap=true,
            tellwidth=false,
        )
    end
    control_status_text = Makie.lift(
        backend_health,
        browser_connection,
        browser_event_count,
        last_browser_action,
        roi_bounds,
    ) do health, connection, event_count, action, bounds
        x_lower, x_upper, y_lower, y_upper = bounds
        "$health  ·  $connection  ·  input events: $event_count  ·  $action  ·  " *
        "ROI x=$(round(x_lower, digits=2))–$(round(x_upper, digits=2)), " *
        "y=$(round(y_lower, digits=2))–$(round(y_upper, digits=2)) μm"
    end
    control_status_color = Makie.lift(
        backend_health,
        browser_connection,
    ) do health, connection
        occursin("PASS", health) && connection == "browser: connected" ?
            RGBf(0.42, 0.92, 0.64) : RGBf(1.00, 0.66, 0.24)
    end
    Label(
        controls[has_ground_truth ? 4 : 3, 1:3],
        control_status_text;
        color=control_status_color,
        fontsize=11,
        halign=:right,
        justification=:right,
        word_wrap=true,
        tellwidth=false,
    )

    raw_values = scene["raw_scaled_intensity"]
    raw_stack = reshape(raw_values, ny, nx, n_frames)
    frame_image = Makie.lift(selected_frame) do frame_index
        oriented = reverse(
            permutedims(@view(raw_stack[:, :, frame_index]), (2, 1));
            dims=2,
        )
        oriented .^ 0.55f0
    end

    selected_points = Makie.lift(
        selected_frame,
        trajectory_source,
    ) do frame_index, source
        frame_track_sets[source].frame_points[frame_index]
    end
    selected_point_colors = Makie.lift(
        selected_frame,
        trajectory_source,
    ) do frame_index, source
        frame_track_sets[source].frame_point_colors[frame_index]
    end
    frame_title = Makie.lift(
        selected_frame,
        trajectory_source,
    ) do frame_index, source
        data = frame_track_sets[source]
        n_points = length(data.frame_points[frame_index])
        dimer_suffix = isempty(data.frame_dimer_label_texts[frame_index]) ? "" :
            "  ·  " * join(data.frame_dimer_label_texts[frame_index], ", ")
        source_name = _set_display_name(data, source)
        "Source frame $(source_frames[frame_index])  ·  " *
        "$source_name: $n_points points$dimer_suffix"
    end

    frame_axis = Axis(
        fig[1, 3];
        title=frame_title,
        xlabel="x (μm)",
        ylabel="y (μm, image orientation)",
        aspect=DataAspect(),
        backgroundcolor=RGBf(0.025, 0.027, 0.032),
    )
    image!(
        frame_axis,
        (0.0f0, x_extent),
        (0.0f0, y_extent),
        frame_image;
        colormap=:grays,
        colorrange=(0.0f0, 1.0f0),
        interpolate=false,
    )
    frame_point_plot = scatter!(
        frame_axis,
        selected_points;
        color=selected_point_colors,
        marker=Circle,
        markerspace=:data,
        markersize=0.5f0 * pixel_size,
        strokewidth=0,
    )
    selected_dimer_points = Makie.lift(
        selected_frame,
        trajectory_source,
    ) do frame_index, source
        frame_track_sets[source].frame_dimer_points[frame_index]
    end
    dimer_frame_plot = scatter!(
        frame_axis,
        selected_dimer_points;
        color=RGBAf(0, 0, 0, 0),
        marker=Circle,
        markerspace=:data,
        markersize=1.10f0 * pixel_size,
        strokecolor=RGBf(1.00, 0.82, 0.12),
        strokewidth=2.2,
    )
    selected_dimer_label_positions = Makie.lift(
        selected_frame,
        trajectory_source,
    ) do frame_index, source
        frame_track_sets[source].frame_dimer_label_positions[frame_index]
    end
    selected_dimer_label_texts = Makie.lift(
        selected_frame,
        trajectory_source,
    ) do frame_index, source
        frame_track_sets[source].frame_dimer_label_texts[frame_index]
    end
    dimer_frame_label_plot = text!(
        frame_axis,
        selected_dimer_label_positions;
        text=selected_dimer_label_texts,
        color=RGBf(1.00, 0.84, 0.18),
        fontsize=16,
        offset=(8, 8),
        align=(:left, :bottom),
        strokecolor=RGBAf(0.02, 0.02, 0.03, 0.82),
        strokewidth=1.1,
    )
    selected_frame_track_points = Makie.lift(
        selected_frame,
        selected_track,
        trajectory_source,
    ) do frame_index, track_index, source
        track_index == 0 && return Point2f[]
        data = frame_track_sets[source]
        [
            point
            for (point, point_track_index) in zip(
                data.frame_points[frame_index],
                data.frame_point_track_indices[frame_index],
            )
            if point_track_index == track_index
        ]
    end
    selected_frame_track_plot = scatter!(
        frame_axis,
        selected_frame_track_points;
        color=RGBAf(0, 0, 0, 0),
        marker=Circle,
        markerspace=:data,
        markersize=1.05f0 * pixel_size,
        strokecolor=RGBf(0.98, 0.99, 1.00),
        strokewidth=2.0,
    )
    selected_label_positions = Makie.lift(
        selected_frame,
        trajectory_source,
    ) do frame_index, source
        frame_track_sets[source].frame_label_positions[frame_index]
    end
    selected_label_texts = Makie.lift(
        selected_frame,
        trajectory_source,
    ) do frame_index, source
        frame_track_sets[source].frame_label_texts[frame_index]
    end
    frame_label_plot = text!(
        frame_axis,
        selected_label_positions;
        text=selected_label_texts,
        color=RGBf(1.00, 0.68, 0.86),
        fontsize=17,
        offset=(7, 7),
        align=(:left, :bottom),
        strokecolor=RGBAf(0.02, 0.02, 0.03, 0.95),
        strokewidth=3,
        visible=track_ids_active,
    )
    xlims!(frame_axis, 0, x_extent)
    ylims!(frame_axis, 0, y_extent)

    function apply_visible_roi!(limits)
        bounds = _xy_bounds(limits, x_extent, y_extent)
        isnothing(bounds) && return nothing
        x_lower, x_upper, y_lower, y_upper = bounds
        roi_bounds[] == bounds || (roi_bounds[] = bounds)
        limits!(
            ax,
            x_lower,
            x_upper,
            y_lower,
            y_upper,
            0.5,
            n_frames + 0.5,
        )
        bounds
    end

    # `DataAspect` may expand the requested target limits. The ROI contract is
    # the region actually visible in the 2D axis, so synchronize from
    # `finallimits`, not `targetlimits`.
    Makie.on(frame_axis.finallimits) do limits
        apply_visible_roi!(limits)
        nothing
    end
    apply_visible_roi!(frame_axis.finallimits[])

    function set_roi!(bounds)
        x_lower, x_upper, y_lower, y_upper = bounds
        x_lower = clamp(Float32(x_lower), 0.0f0, x_extent)
        x_upper = clamp(Float32(x_upper), 0.0f0, x_extent)
        y_lower = clamp(Float32(y_lower), 0.0f0, y_extent)
        y_upper = clamp(Float32(y_upper), 0.0f0, y_extent)
        x_lower < x_upper || throw(ArgumentError("ROI x bounds must be ordered"))
        y_lower < y_upper || throw(ArgumentError("ROI y bounds must be ordered"))
        limits!(frame_axis, x_lower, x_upper, y_lower, y_upper)
        apply_visible_roi!(frame_axis.finallimits[])
    end

    pixels_per_frame = nx * ny
    raw_xyz = scene["raw_xyz"]
    selected_raw_points = Makie.lift(selected_frame) do frame_index
        first_index = (frame_index - 1) * pixels_per_frame + 1
        last_index = frame_index * pixels_per_frame
        [Point3f(raw_xyz[index, 1], raw_xyz[index, 2], raw_xyz[index, 3])
         for index in first_index:last_index]
    end
    selected_raw_colors = Makie.lift(selected_frame) do frame_index
        first_index = (frame_index - 1) * pixels_per_frame + 1
        last_index = frame_index * pixels_per_frame
        [let
             gray = 0.20f0 + 0.80f0 * value^0.55f0
             alpha = 0.018f0 + 0.14f0 * value^1.15f0
             RGBAf(gray, gray, gray, alpha)
         end for value in @view(raw_values[first_index:last_index])]
    end
    highlight_cube = Rect3f(
        Point3f(-0.5f0, -0.5f0, -0.5f0),
        Vec3f(1.0f0, 1.0f0, 1.0f0),
    )
    meshscatter!(
        ax,
        selected_raw_points;
        marker=highlight_cube,
        markersize=Vec3f(
            0.97f0 * pixel_size,
            0.97f0 * pixel_size,
            0.88f0,
        ),
        color=selected_raw_colors,
        shading=NoShading,
        transparency=true,
        visible=highlight_active,
    )
    current_frame_track_points_3d = Makie.lift(
        selected_frame,
        roi_bounds,
        trajectory_source,
    ) do frame_index, bounds, source
        # These points use overdraw and deliberately opt out of Axis3 clip
        # planes so their bright cores remain visible. They therefore need the
        # same explicit ROI masking as the trajectory line buffers.
        _spacetime_clipped_points(
            frame_track_sets[source].frame_points_3d[frame_index],
            bounds,
        )
    end
    selected_track_point_colors_3d = Makie.lift(
        selected_frame,
        trajectory_source,
    ) do frame_index, source
        frame_track_sets[source].frame_point_colors[frame_index]
    end
    current_frame_track_plot_3d = scatter!(
        ax,
        current_frame_track_points_3d;
        color=selected_track_point_colors_3d,
        markersize=3.2,
        overdraw=true,
        clip_planes=Plane3f[],
        visible=highlight_active,
    )
    slab_edges = Makie.lift(selected_frame, roi_bounds) do frame_index, bounds
        _frame_slab_edges(frame_index, bounds...)
    end
    linesegments!(
        ax,
        slab_edges;
        color=RGBAf(0.10, 0.90, 1.00, 0.92),
        linewidth=1.8,
        overdraw=true,
        visible=highlight_active,
    )

    # A selected track is redrawn more thickly in its own trajectory color.
    # Keep every observable geometry buffer at a fixed maximum length so
    # WGLMakie can update selections and ROI crops without rebuilding buffers.
    function padded_selected_segments(paths, track_index, bounds, capacity)
        hidden = Point3f(-1.0f6, -1.0f6, -1.0f6)
        output = fill(hidden, capacity)
        (track_index == 0 || track_index > length(paths)) && return output
        segments = _spacetime_line_segments(paths[track_index], bounds)
        copyto!(output, 1, segments, 1, min(length(output), length(segments)))
        output
    end

    function padded_selected_points(paths, track_index, bounds, capacity)
        hidden = Point3f(-1.0f6, -1.0f6, -1.0f6)
        output = fill(hidden, capacity)
        (track_index == 0 || track_index > length(paths)) && return output
        points = _spacetime_clipped_points(paths[track_index], bounds)
        copyto!(output, 1, points, 1, min(length(output), length(points)))
        output
    end

    continuous_capacity = maximum(
        data -> maximum(
            path -> 2 * max(length(path) - 1, 0),
            data.track_continuous_paths;
            init=0,
        ),
        values(frame_track_sets);
        init=0,
    )
    gap_capacity = maximum(
        data -> maximum(
            path -> 2 * max(length(path) - 1, 0),
            data.track_gap_paths;
            init=0,
        ),
        values(frame_track_sets);
        init=0,
    )
    point_capacity = maximum(
        data -> maximum(length, data.track_point_paths; init=0),
        values(frame_track_sets);
        init=0,
    )
    selected_trajectory_plots = Any[]
    no_clip_planes = Plane3f[]
    if continuous_capacity > 0
        selected_continuous_segments = Makie.lift(
            selected_track,
            roi_bounds,
            trajectory_source,
        ) do track_index, bounds, source
            padded_selected_segments(
                frame_track_sets[source].track_continuous_paths,
                track_index,
                bounds,
                continuous_capacity,
            )
        end
        push!(selected_trajectory_plots, linesegments!(
            ax,
            selected_continuous_segments;
            color=selected_halo_color,
            linewidth=6.0,
            transparency=true,
            overdraw=true,
            clip_planes=no_clip_planes,
        ))
        push!(selected_trajectory_plots, linesegments!(
            ax,
            selected_continuous_segments;
            color=selected_core_color,
            linewidth=1.6,
            overdraw=true,
            clip_planes=no_clip_planes,
        ))
    end
    if gap_capacity > 0
        selected_gap_segments = Makie.lift(
            selected_track,
            roi_bounds,
            trajectory_source,
        ) do track_index, bounds, source
            padded_selected_segments(
                frame_track_sets[source].track_gap_paths,
                track_index,
                bounds,
                gap_capacity,
            )
        end
        push!(selected_trajectory_plots, linesegments!(
            ax,
            selected_gap_segments;
            color=selected_core_color,
            linewidth=1.6,
            linestyle=:dash,
            overdraw=true,
            clip_planes=no_clip_planes,
        ))
    end
    if point_capacity > 0
        selected_track_points_3d = Makie.lift(
            selected_track,
            roi_bounds,
            trajectory_source,
        ) do track_index, bounds, source
            padded_selected_points(
                frame_track_sets[source].track_point_paths,
                track_index,
                bounds,
                point_capacity,
            )
        end
        push!(selected_trajectory_plots, scatter!(
            ax,
            selected_track_points_3d;
            color=selected_core_color,
            markersize=3.2,
            overdraw=true,
            clip_planes=no_clip_planes,
        ))
    end

    function select_frame_at!(position)
        bbox = slider_axis.layoutobservables.computedbbox[]
        extent = widths(bbox)
        iszero(extent[2]) && return
        fraction = clamp((position[2] - bbox.origin[2]) / extent[2], 0, 1)
        frame_index = round(Int, 1 + fraction * (n_frames - 1))
        selected_frame[] == frame_index || (selected_frame[] = frame_index)
        nothing
    end

    function select_track_at!(position; radius=1.25f0 * pixel_size)
        data = frame_track_sets[trajectory_source[]]
        points = data.frame_points[selected_frame[]]
        indices = data.frame_point_track_indices[selected_frame[]]
        if isempty(points)
            selected_track[] = 0
            return 0
        end
        nearest_point = argmin(eachindex(points)) do point_index
            point = points[point_index]
            (point[1] - position[1])^2 + (point[2] - position[2])^2
        end
        point = points[nearest_point]
        distance2 =
            (point[1] - position[1])^2 + (point[2] - position[2])^2
        track_index = distance2 <= radius^2 ? indices[nearest_point] : 0
        selected_track[] == track_index || (selected_track[] = track_index)
        track_index
    end

    function set_frame!(frame_index)
        next_frame = clamp(Int(frame_index), 1, n_frames)
        selected_frame[] == next_frame || (selected_frame[] = next_frame)
        next_frame
    end

    function toggle_highlight!()
        highlight_active[] = !highlight_active[]
    end

    function toggle_track_ids!()
        track_ids_active[] = !track_ids_active[]
    end

    function toggle_trajectory_source!()
        has_ground_truth || return trajectory_source[]
        trajectory_source[] = trajectory_source[] === :found ?
            :ground_truth : :found
        selected_track[] == 0 || (selected_track[] = 0)
        trajectory_source[]
    end

    function reset_inspector!()
        selected_frame[] == initial_frame || (selected_frame[] = initial_frame)
        highlight_active[] || (highlight_active[] = true)
        selected_track[] == 0 || (selected_track[] = 0)
        track_ids_active[] && (track_ids_active[] = false)
        trajectory_source[] === :found || (trajectory_source[] = :found)
        full_bounds = (0.0f0, x_extent, 0.0f0, y_extent)
        set_roi!(full_bounds)
        nothing
    end

    (;
        slider_axis,
        highlight_box,
        highlight_active,
        id_toggle_box,
        track_ids_active,
        source_toggle_box,
        trajectory_source,
        has_ground_truth,
        frame_axis,
        frame_point_plot,
        current_frame_track_plot_3d,
        dimer_frame_plot,
        dimer_frame_label_plot,
        selected_frame_track_plot,
        frame_label_plot,
        selected_frame,
        selected_track,
        selected_track_text,
        selected_points,
        frame_track_sets,
        current_frame_track_points_3d,
        selected_trajectory_plots,
        browser_event_count,
        last_browser_action,
        backend_health,
        browser_connection,
        record_browser_event=record_browser_event!,
        set_frame=set_frame!,
        set_roi=set_roi!,
        toggle_highlight=toggle_highlight!,
        toggle_track_ids=toggle_track_ids!,
        toggle_trajectory_source=toggle_trajectory_source!,
        select_frame_at=select_frame_at!,
        select_track_at=select_track_at!,
        reset_inspector=reset_inspector!,
    )
end
