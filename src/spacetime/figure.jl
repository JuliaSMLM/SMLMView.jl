# The 3D figure: Axis3 with voxel, track, link and dimer layers, legend, view
# controls, the root event router and the control self-test.

# Link opacity: the mapping of the link weight, clamped to [0, 1]. A non-finite result is
# an ArgumentError naming the weight, as for the width.
function _link_alpha(mapping, weight)
    alpha = Float32(mapping(Float32(weight)))
    isfinite(alpha) || throw(ArgumentError(
        "link_alpha($weight) = $alpha must be finite"))
    clamp(alpha, 0.0f0, 1.0f0)
end

# Width of one link segment. A number is the width itself; a function maps the link
# weight. Either way a negative or non-finite width is an ArgumentError.
function _checked_width(width, weight)
    width = Float32(width)
    isfinite(width) && width >= 0 && return width
    throw(ArgumentError(
        (isnothing(weight) ? "link_width = $width" : "link_width($weight) = $width") *
        " must be finite and >= 0",
    ))
end
_link_width(width::Real, weight) = _checked_width(width, nothing)
_link_width(mapping, weight) = _checked_width(mapping(Float32(weight)), weight)

# The `linewidth` of the links plot: a number, or one value per vertex (two per link).
_link_widths(width::Real, weights) = _link_width(width, nothing)
function _link_widths(mapping, weights)
    Float32[_link_width(mapping, weight) for weight in weights for _ in 1:2]
end

# The argument check of `spacetime`.
_check_link_width(width::Real) = (_link_width(width, nothing); nothing)
function _check_link_width(mapping)
    applicable(mapping, 0.5f0) || throw(ArgumentError(
        "link_width must be a number or a function of the link weight"))
    nothing
end

# Self-test: the drawn line width of the links plot matches the mapping.
function _links_width_ok(width::Real, drawn, weights)
    drawn isa Real && abs(Float32(drawn) - Float32(width)) <= 1.0f-6
end
function _links_width_ok(mapping, drawn, weights)
    length(drawn) == 2 * length(weights) && all(eachindex(weights)) do index
        expected = _link_width(mapping, weights[index])
        abs(Float32(drawn[2index - 1]) - expected) <= 1.0f-6 &&
            abs(Float32(drawn[2index]) - expected) <= 1.0f-6
    end
end

# The dark theme applies to this build only; the session's theme is untouched.
function build_figure(scene; kwargs...)
    with_theme(theme_dark()) do
        _build_figure(scene; kwargs...)
    end
end

function _build_figure(
    scene;
    resolution=(1100, 900),
    azimuth=1.22,
    elevation=0.34,
    frame_inspector=false,
    link_alpha=identity,
    link_width=2.0,
)
    background = RGBf(0.035, 0.038, 0.045)

    source_frames = scene["source_frames"]
    n_frames = length(source_frames)
    track_sets = _track_sets(scene)
    track_render_sets = Dict(
        source => _track_render_data(track_scene)
        for (source, track_scene) in track_sets
    )
    trajectory_source = Makie.Observable(:found)
    found_render = track_render_sets[:found]
    n_tracks = found_render.n_tracks
    n_emitters = found_render.n_emitters
    dimers = found_render.dimers
    pixel_size = scene["pixel_size"]
    nx = scene["nx"]
    ny = scene["ny"]
    x_extent = Float32(nx * pixel_size)
    y_extent = Float32(ny * pixel_size)
    state_source = scene["state_source"]
    roi_bounds = Makie.Observable((0.0f0, x_extent, 0.0f0, y_extent))

    tick_indices = unique(round.(Int, range(1, n_frames; length=5)))
    zticks = (
        Float64.(tick_indices),
        string.(source_frames[tick_indices]),
    )

    fig = Figure(size=resolution, backgroundcolor=background)
    ax = Axis3(
        fig[1, 1:2];
        title=get(scene, "title", "Raw intensity and trajectories"),
        xlabel="x (μm)",
        ylabel="y (μm, image orientation)",
        zlabel="source camera frame",
        zticks,
        azimuth,
        elevation,
        aspect=(1.0, 1.0, 0.82),
        viewmode=:fitzoom,
        xgridvisible=false,
        ygridvisible=false,
        zgridvisible=false,
    )

    alpha_min = Float32(get(scene, "raw_alpha_min", 0.0005f0))
    alpha_max = Float32(get(scene, "raw_alpha_max", 0.06f0))
    alpha_gamma = Float32(get(scene, "raw_alpha_gamma", 1.15f0))
    raw_xyz = scene["raw_xyz"]
    raw_points = [
        Point3f(raw_xyz[index, 1], raw_xyz[index, 2], raw_xyz[index, 3])
        for index in axes(raw_xyz, 1)
    ]
    raw_colors = [
        let
            gray = 0.10f0 + 0.88f0 * value^0.55f0
            alpha = alpha_min +
                (alpha_max - alpha_min) * value^alpha_gamma
            RGBAf(gray, gray, gray, alpha)
        end
        for value in scene["raw_scaled_intensity"]
    ]
    raw_cube = Rect3f(
        Point3f(-0.5f0, -0.5f0, -0.5f0),
        Vec3f(1.0f0, 1.0f0, 1.0f0),
    )
    raw_plot = meshscatter!(
        ax,
        raw_points;
        marker=raw_cube,
        markersize=Vec3f(
            0.96f0 * pixel_size,
            0.96f0 * pixel_size,
            0.84f0,
        ),
        color=raw_colors,
        shading=NoShading,
        transparency=true,
    )

    # Batch every trajectory layer into one plot.  WGLMakie pays a substantial
    # browser-side setup cost per plot; drawing the glow separately for every
    # track left the canvas blank for a long time on large scenes.  NaN
    # separators preserve independent tracks while per-vertex colors keep their
    # identities.
    continuous_capacity = maximum(
        render -> length(_spacetime_line_segments(render.continuous_points)),
        values(track_render_sets);
        init=0,
    )
    gap_capacity = maximum(
        render -> length(_spacetime_line_segments(render.gap_points)),
        values(track_render_sets);
        init=0,
    )
    singleton_capacity = maximum(
        render -> length(render.singleton_points),
        values(track_render_sets);
        init=0,
    )

    # WGLMakie's dynamic Axis3 clipping can drop batched polylines after the
    # 2D ROI changes. Use fixed-length LineSegments buffers instead: only the
    # point buffer changes, while the equally sized per-track color buffer stays
    # immutable. NaN pairs suppress segments outside the ROI without changing
    # browser buffer lengths or trajectory-color alignment.
    hidden_point = Point3f(-1.0f6, -1.0f6, -1.0f6)
    continuous_plot_points = Makie.lift(
        trajectory_source,
        roi_bounds,
    ) do source, bounds
        render = track_render_sets[source]
        segments = _spacetime_line_segments(
            render.continuous_points,
            frame_inspector ? bounds : nothing,
        )
        _padded(segments, continuous_capacity, hidden_point)
    end
    continuous_plot_halo_colors = Makie.lift(trajectory_source) do source
        colors = _spacetime_segment_colors(
            track_render_sets[source].continuous_halo_colors)
        _padded(colors, continuous_capacity, RGBAf(0, 0, 0, 0))
    end
    continuous_plot_mid_colors = Makie.lift(trajectory_source) do source
        colors = _spacetime_segment_colors(
            track_render_sets[source].continuous_mid_colors)
        _padded(colors, continuous_capacity, RGBAf(0, 0, 0, 0))
    end
    continuous_plot_core_colors = Makie.lift(trajectory_source) do source
        colors = _spacetime_segment_colors(
            track_render_sets[source].continuous_core_colors)
        _padded(colors, continuous_capacity, RGBf(0, 0, 0))
    end
    gap_plot_points = Makie.lift(
        trajectory_source,
        roi_bounds,
    ) do source, bounds
        render = track_render_sets[source]
        segments = _spacetime_line_segments(
            render.gap_points,
            frame_inspector ? bounds : nothing,
        )
        _padded(segments, gap_capacity, hidden_point)
    end
    gap_plot_halo_colors = Makie.lift(trajectory_source) do source
        colors = _spacetime_segment_colors(track_render_sets[source].gap_halo_colors)
        _padded(colors, gap_capacity, RGBAf(0, 0, 0, 0))
    end
    gap_plot_core_colors = Makie.lift(trajectory_source) do source
        colors = _spacetime_segment_colors(track_render_sets[source].gap_core_colors)
        _padded(colors, gap_capacity, RGBAf(0, 0, 0, 0))
    end
    singleton_plot_points = Makie.lift(
        trajectory_source,
        roi_bounds,
    ) do source, bounds
        points = track_render_sets[source].singleton_points
        clipped = frame_inspector ? _spacetime_clipped_points(points, bounds) : points
        _padded(clipped, singleton_capacity, hidden_point)
    end
    singleton_halo_colors = Makie.lift(trajectory_source) do source
        _padded(
            track_render_sets[source].singleton_halo_colors,
            singleton_capacity,
            RGBAf(0, 0, 0, 0),
        )
    end
    singleton_core_colors = Makie.lift(trajectory_source) do source
        _padded(
            track_render_sets[source].singleton_core_colors,
            singleton_capacity,
            RGBf(0, 0, 0),
        )
    end
    no_clip_planes = Plane3f[]
    trajectory_plots = Any[]

    # A thin bright core with two translucent, same-color halos reads as a
    # glow while preserving the small geometric centerline.
    if continuous_capacity > 0
        push!(trajectory_plots, linesegments!(
            ax,
            continuous_plot_points;
            color=continuous_plot_halo_colors,
            linewidth=3.2,
            transparency=true,
            overdraw=true,
            clip_planes=no_clip_planes,
        ))
        push!(trajectory_plots, linesegments!(
            ax,
            continuous_plot_points;
            color=continuous_plot_mid_colors,
            linewidth=1.55,
            transparency=true,
            overdraw=true,
            clip_planes=no_clip_planes,
        ))
        push!(trajectory_plots, linesegments!(
            ax,
            continuous_plot_points;
            color=continuous_plot_core_colors,
            linewidth=0.72,
            overdraw=true,
            clip_planes=no_clip_planes,
        ))
    end
    if gap_capacity > 0
        push!(trajectory_plots, linesegments!(
            ax,
            gap_plot_points;
            color=gap_plot_halo_colors,
            linewidth=1.7,
            linestyle=:dash,
            transparency=true,
            overdraw=true,
            clip_planes=no_clip_planes,
        ))
        push!(trajectory_plots, linesegments!(
            ax,
            gap_plot_points;
            color=gap_plot_core_colors,
            linewidth=0.55,
            linestyle=:dash,
            overdraw=true,
            clip_planes=no_clip_planes,
        ))
    end
    if singleton_capacity > 0
        push!(trajectory_plots, scatter!(
            ax,
            singleton_plot_points;
            color=singleton_halo_colors,
            markersize=8,
            transparency=true,
            overdraw=true,
            clip_planes=no_clip_planes,
        ))
        push!(trajectory_plots, scatter!(
            ax,
            singleton_plot_points;
            color=singleton_core_colors,
            markersize=3.5,
            overdraw=true,
            clip_planes=no_clip_planes,
        ))
    end

    # Optional link-probability layer: one amber segment per alternative
    # (on_map == false) link, alpha = link_alpha(w), width = link_width (a
    # number, or a function of w for a per-segment width). MAP links are not
    # drawn: they lie on the track segments, which already show them. Links
    # belong to the FOUND source. Like the tracks, geometry is a fixed-length
    # buffer clipped to the ROI; hidden links collapse to an off-screen pair so
    # the immutable per-vertex color buffer stays aligned.
    links = get(scene, "links", nothing)
    drawn_link_indices = isnothing(links) ? Int[] :
        [index for index in eachindex(links["w"]) if !links["on_map"][index]]
    link_count = length(drawn_link_indices)
    drawn_weights = isnothing(links) ? Float32[] :
        Float32[links["w"][index] for index in drawn_link_indices]
    links_visible = Makie.Observable(true)
    link_colors = RGBAf[]
    link_endpoints = Point3f[]
    links_plot = nothing
    link_points = nothing
    link_clipped_count = nothing
    if !isnothing(links)
        link_alt_color = RGBf(1.0, 0.62, 0.10)
        for index in drawn_link_indices
            color = RGBAf(
                link_alt_color.r,
                link_alt_color.g,
                link_alt_color.b,
                _link_alpha(link_alpha, links["w"][index]),
            )
            push!(link_colors, color, color)
            push!(
                link_endpoints,
                Point3f(links["x0"][index], links["y0"][index], links["z0"][index]),
                Point3f(links["x1"][index], links["y1"][index], links["z1"][index]),
            )
        end
        # Number of links with any part inside the bounds, in the model of the
        # drawn buffer (used by the self-test as the expected drawn count).
        link_clipped_count = bounds -> count(1:link_count) do index
            clipped = if isnothing(bounds)
                first_point = link_endpoints[2index - 1]
                second_point = link_endpoints[2index]
                all(isfinite, first_point) && all(isfinite, second_point)
            else
                !isnothing(_clip_spacetime_segment(
                    link_endpoints[2index - 1],
                    link_endpoints[2index],
                    bounds,
                ))
            end
            clipped
        end
        link_points = Makie.lift(
            trajectory_source,
            roi_bounds,
            links_visible,
        ) do source, bounds, visible
            output = fill(hidden_point, 2 * link_count)
            if visible && source === :found
                for index in 1:link_count
                    first_point = link_endpoints[2index - 1]
                    second_point = link_endpoints[2index]
                    clipped = if frame_inspector
                        _clip_spacetime_segment(first_point, second_point, bounds)
                    else
                        all(isfinite, first_point) && all(isfinite, second_point) ?
                            (first_point, second_point) : nothing
                    end
                    isnothing(clipped) && continue
                    output[2index - 1] = clipped[1]
                    output[2index] = clipped[2]
                end
            end
            output
        end
        links_plot_visible = Makie.lift(
            trajectory_source,
            links_visible,
        ) do source, visible
            visible && source === :found
        end
        links_plot = linesegments!(
            ax,
            link_points;
            color=link_colors,
            linewidth=_link_widths(link_width, drawn_weights),
            transparency=true,
            overdraw=true,
            visible=links_plot_visible,
            clip_planes=no_clip_planes,
        )
    end

    # A reciprocal dimer is still represented by its two constituent colored
    # trajectories.  Overlay their model center with a gold binding path so
    # association state is visible without drawing a fictitious third emitter.
    dimer_segment_capacity = maximum(
        render -> length(_spacetime_line_segments(render.dimer_points)),
        values(track_render_sets);
        init=0,
    )
    dimer_episode_capacity = maximum(
        render -> length(render.dimer_onset_points),
        values(track_render_sets);
        init=0,
    )
    dimer_plot_points = Makie.lift(
        trajectory_source,
        roi_bounds,
    ) do source, bounds
        render = track_render_sets[source]
        segments = _spacetime_line_segments(
            render.dimer_points,
            frame_inspector ? bounds : nothing,
        )
        _padded(segments, dimer_segment_capacity, hidden_point)
    end
    dimer_onset_plot_points = Makie.lift(
        trajectory_source,
        roi_bounds,
    ) do source, bounds
        points = track_render_sets[source].dimer_onset_points
        clipped = frame_inspector ? _spacetime_clipped_points(points, bounds) : points
        _padded(clipped, dimer_episode_capacity, hidden_point)
    end
    dimer_label_plot_points = Makie.lift(
        trajectory_source,
        roi_bounds,
    ) do source, bounds
        points = track_render_sets[source].dimer_label_points
        clipped = frame_inspector ? _spacetime_clipped_points(points, bounds) : points
        _padded(clipped, dimer_episode_capacity, hidden_point)
    end
    dimer_labels = Makie.lift(trajectory_source) do source
        _padded(
            track_render_sets[source].dimer_labels,
            dimer_episode_capacity,
            "",
        )
    end
    dimer_plots = Any[]
    if dimer_segment_capacity > 0
        push!(dimer_plots, linesegments!(
            ax,
            dimer_plot_points;
            color=RGBAf(1.00, 0.58, 0.02, 0.18),
            linewidth=7.0,
            transparency=true,
            overdraw=true,
            clip_planes=no_clip_planes,
        ))
        push!(dimer_plots, linesegments!(
            ax,
            dimer_plot_points;
            color=RGBAf(1.00, 0.72, 0.06, 0.62),
            linewidth=3.0,
            transparency=true,
            overdraw=true,
            clip_planes=no_clip_planes,
        ))
        push!(dimer_plots, linesegments!(
            ax,
            dimer_plot_points;
            color=RGBf(1.00, 0.90, 0.24),
            linewidth=1.15,
            overdraw=true,
            clip_planes=no_clip_planes,
        ))
        push!(dimer_plots, scatter!(
            ax,
            dimer_onset_plot_points;
            color=RGBf(1.00, 0.86, 0.14),
            marker=:diamond,
            markersize=12,
            strokecolor=RGBAf(0.22, 0.10, 0.00, 0.98),
            strokewidth=1.4,
            overdraw=true,
            clip_planes=no_clip_planes,
        ))
        push!(dimer_plots, text!(
            ax,
            dimer_label_plot_points;
            text=dimer_labels,
            color=RGBf(1.00, 0.86, 0.18),
            fontsize=16,
            offset=(8, 8),
            align=(:left, :bottom),
            strokecolor=RGBAf(0.02, 0.02, 0.03, 0.82),
            strokewidth=1.1,
            overdraw=true,
        ))
    end

    xlims!(ax, 0, x_extent)
    ylims!(ax, 0, y_extent)
    zlims!(ax, 0.5, n_frames + 0.5)

    intensity_unit = String(get(scene, "raw_intensity_unit", "photons"))
    raw_render_mode = get(scene, "raw_render_mode", "thresholded")
    raw_description = if raw_render_mode == "all_voxels"
        normalization_quantile = scene["raw_normalization_quantile"]
        normalization_high = scene["raw_normalization_high"]
        "Gray translucent cubes: all $(length(raw_points)) calibrated raw pixels\n" *
        "Continuous opacity/intensity normalized at " *
        "q=$(round(normalization_quantile, digits=4)) " *
        "($(round(normalization_high, digits=1)) $intensity_unit)"
    else
        threshold = scene["raw_threshold"]
        quantile = scene["raw_quantile"]
        "Gray blocks: brightest $(round(100 * (1 - quantile), digits=2))% " *
        "of calibrated raw pixels\nThreshold " *
        "$(round(threshold, digits=1)) $intensity_unit"
    end
    has_dimers = any(
        render -> any(startswith("dimer_"), keys(render.track_scene)),
        values(track_render_sets),
    )
    legend_text = Makie.lift(trajectory_source) do source
        render = track_render_sets[source]
        source_name = _set_display_name(render, source)
        source_description = source === :found ?
            "$source_name ($state_source)" : source_name
        dimer_description = if !has_dimers
            ""
        elseif render.dimers.n_episodes == 0
            "\nGold: no reciprocal dimer episode in this displayed state"
        else
            "\nGold: $(render.dimers.n_episodes) reciprocal dimer episode" *
            (render.dimers.n_episodes == 1 ? "" : "s") * " (" *
            join(render.dimers.labels, ", ") * ")"
        end
        raw_description * "\n" *
        "Colors: $(render.n_tracks) trajectories, $source_description " *
        "($(render.n_emitters) in-volume positions)  ·  " *
        "Dashed: connection across missing frames" *
        dimer_description
    end
    Label(
        fig[2, 1],
        legend_text;
        color=RGBf(0.82, 0.84, 0.88),
        fontsize=12,
        tellwidth=false,
        halign=:left,
        justification=:left,
        word_wrap=true,
    )

    inspector = frame_inspector ?
        _add_frame_inspector!(
            fig,
            ax,
            scene,
            roi_bounds,
            trajectory_source,
            track_sets,
        ) :
        nothing
    view_controls = Makie.GridLayout(fig[2, 2])
    top_view_box = Box(
        view_controls[1, 1];
        color=RGBf(0.16, 0.18, 0.22),
        strokecolor=RGBf(0.36, 0.39, 0.44),
        strokewidth=1.0,
        cornerradius=6,
        width=104,
        height=38,
        z=-1,
    )
    Label(
        view_controls[1, 1],
        "Top view";
        color=RGBf(0.90, 0.92, 0.95),
        fontsize=16,
        tellwidth=false,
        tellheight=false,
    )

    reset_box = Box(
        view_controls[1, 2];
        color=RGBf(0.16, 0.18, 0.22),
        strokecolor=RGBf(0.36, 0.39, 0.44),
        strokewidth=1.0,
        cornerradius=6,
        width=82,
        height=38,
        z=-1,
    )
    Label(
        view_controls[1, 2],
        "Reset";
        color=RGBf(0.90, 0.92, 0.95),
        fontsize=16,
        tellwidth=false,
        tellheight=false,
    )

    links_box = nothing
    if !isnothing(links)
        links_box_color = Makie.lift(links_visible) do visible
            visible ? RGBf(0.10, 0.36, 0.46) : RGBf(0.16, 0.18, 0.22)
        end
        links_box = Box(
            view_controls[1, 3];
            color=links_box_color,
            strokecolor=RGBf(0.36, 0.39, 0.44),
            strokewidth=1.0,
            cornerradius=6,
            width=82,
            height=38,
            z=-1,
        )
        Label(
            view_controls[1, 3],
            "Links";
            color=RGBf(0.90, 0.92, 0.95),
            fontsize=16,
            tellwidth=false,
            tellheight=false,
        )
    end

    function toggle_links!()
        isnothing(links) && return links_visible[]
        links_visible[] = !links_visible[]
        links_visible[]
    end

    function set_top_view!()
        ax.azimuth[] = -π / 2
        ax.elevation[] = π / 2 - 0.001
        nothing
    end

    function reset_view!()
        ax.azimuth[] = azimuth
        ax.elevation[] = elevation
        if isnothing(inspector)
            xlims!(ax, 0, x_extent)
            ylims!(ax, 0, y_extent)
        else
            inspector.reset_inspector()
        end
        zlims!(ax, 0.5, n_frames + 0.5)
        nothing
    end

    # WGLMakie sends one event stream for the whole canvas. Keep every custom
    # control on that root stream; child-block event handlers can appear to work
    # locally while failing after a Bonito re-serve. WGLMakie 0.13 throttles
    # mouse position by 40 ms and sends button messages without coordinates, so
    # settle a click for 55 ms before hit-testing painted controls. Axis-native
    # pan/zoom/rotate remains untouched and receives the original events.
    root_events = Makie.events(fig.scene)
    pointer_serial = Ref(0)
    settle_task = Ref{Union{Nothing,Task}}(nothing)    # the latest press's settle task
    frame_click_origin = Ref{Union{Nothing,Point2f}}(nothing)
    slider_drag_active = Ref(false)

    function custom_control_at(position)
        _inside_layout(position, top_view_box) && return :top_view
        _inside_layout(position, reset_box) && return :reset
        !isnothing(links_box) &&
            _inside_layout(position, links_box) && return :links
        if !isnothing(inspector)
            _inside_layout(position, inspector.slider_axis) && return :slider
            _inside_layout(position, inspector.highlight_box) &&
                return :highlight
            _inside_layout(position, inspector.id_toggle_box) &&
                return :track_ids
            !isnothing(inspector.source_toggle_box) &&
                _inside_layout(position, inspector.source_toggle_box) &&
                return :trajectory_source
        end
        nothing
    end

    function activate_custom_control!(control, position)
        if control === :top_view
            set_top_view!()
        elseif control === :reset
            reset_view!()
        elseif control === :links
            toggle_links!()
        elseif control === :slider
            inspector.select_frame_at(position)
        elseif control === :highlight
            inspector.toggle_highlight()
        elseif control === :track_ids
            inspector.toggle_track_ids()
        elseif control === :trajectory_source
            inspector.toggle_trajectory_source()
        else
            return false
        end
        isnothing(inspector) || inspector.record_browser_event(string(control))
        true
    end

    mousebutton_observer = Makie.on(
        root_events.mousebutton;
        priority=120,
    ) do event
        if event.button == Makie.Mouse.left && event.action == Makie.Mouse.press
            pointer_serial[] += 1
            serial = pointer_serial[]
            position = root_events.mouseposition[]
            frame_click_origin[] =
                !isnothing(inspector) &&
                _inside_layout(position, inspector.frame_axis) ?
                Point2f(position) : nothing

            # Use the trailing mouse-position update for painted controls. This
            # avoids intermittent misses caused by WGLMakie's 40 ms position
            # throttle without delaying native Axis interactions.
            settle_task[] = @async begin
                sleep(0.055)
                serial == pointer_serial[] || return
                settled_position = root_events.mouseposition[]
                control = custom_control_at(settled_position)
                isnothing(control) ||
                    activate_custom_control!(control, settled_position)
            end
        elseif event.button == Makie.Mouse.left &&
               event.action == Makie.Mouse.release
            position = root_events.mouseposition[]
            origin = frame_click_origin[]
            frame_click_origin[] = nothing
            slider_drag_active[] = false
            if !isnothing(inspector) && origin !== nothing &&
               _inside_layout(position, inspector.frame_axis)
                displacement2 =
                    (position[1] - origin[1])^2 +
                    (position[2] - origin[2])^2
                if displacement2 <= 16.0
                    inspector.select_track_at(Makie.mouseposition(inspector.frame_axis))
                    inspector.record_browser_event("track pick")
                else
                    inspector.record_browser_event("2D ROI drag")
                end
            end
        end
        Makie.Consume(false)
    end

    mouseposition_observer = Makie.on(
        root_events.mouseposition;
        priority=120,
    ) do position
        if !isnothing(inspector) &&
           Makie.ispressed(root_events, Makie.Mouse.left) &&
           _inside_layout(position, inspector.slider_axis)
            inspector.select_frame_at(position)
            if !slider_drag_active[]
                slider_drag_active[] = true
                inspector.record_browser_event("slider drag")
            end
            return Makie.Consume(true)
        end
        Makie.Consume(false)
    end

    keyboard_observer = Makie.on(
        root_events.keyboardbutton;
        priority=120,
    ) do event
        if !isnothing(inspector) &&
           event.action in (Makie.Keyboard.press, Makie.Keyboard.repeat)
            direction = event.key == Makie.Keyboard.up ? 1 :
                event.key == Makie.Keyboard.down ? -1 : 0
            if direction != 0
                inspector.set_frame(inspector.selected_frame[] + direction)
                inspector.record_browser_event(
                    direction > 0 ? "keyboard frame up" : "keyboard frame down")
                return Makie.Consume(true)
            end
        end
        Makie.Consume(false)
    end

    scroll_observer = Makie.on(root_events.scroll; priority=120) do _
        if !isnothing(inspector) &&
           _inside_layout(root_events.mouseposition[], inspector.frame_axis)
            inspector.record_browser_event("2D ROI scroll")
        end
        Makie.Consume(false)
    end

    function reassert_browser_state!()
        isnothing(inspector) && return nothing
        # A Bonito reconnect creates a new browser-side scene. Re-notify the
        # state that users can change so the replacement scene cannot inherit
        # stale defaults while keeping the backend's current view.
        inspector.selected_frame[] = inspector.selected_frame[]
        inspector.selected_track[] = inspector.selected_track[]
        inspector.highlight_active[] = inspector.highlight_active[]
        inspector.track_ids_active[] = inspector.track_ids_active[]
        inspector.trajectory_source[] = inspector.trajectory_source[]
        isnothing(links) || (links_visible[] = links_visible[])
        ax.azimuth[] = ax.azimuth[]
        ax.elevation[] = ax.elevation[]
        inspector.set_roi(roi_bounds[])
        nothing
    end

    window_open_observer = Makie.on(root_events.window_open) do is_open
        if !isnothing(inspector)
            inspector.browser_connection[] = is_open ?
                "browser: connected" : "browser: disconnected"
            if is_open
                @async begin
                    # Let the new WGL scene finish binding its Observables,
                    # then replay the retained backend state once.
                    sleep(0.075)
                    inspector.browser_connection[] == "browser: connected" &&
                        reassert_browser_state!()
                end
            end
        end
        nothing
    end

    control_router = (;
        mousebutton_observer,
        mouseposition_observer,
        keyboard_observer,
        scroll_observer,
        window_open_observer,
    )

    function control_self_test!()
        checks = Dict{Symbol,Bool}()
        failures = String[]
        try
            reset_view!()
            checks[:reset_camera] =
                isapprox(ax.azimuth[], azimuth) &&
                isapprox(ax.elevation[], elevation)

            set_top_view!()
            checks[:top_view] =
                isapprox(ax.azimuth[], -π / 2) &&
                isapprox(ax.elevation[], π / 2 - 0.001)

            if !isnothing(inspector)
                initial_frame = cld(n_frames, 2)
                test_frame = initial_frame == n_frames ? max(1, n_frames - 1) :
                    initial_frame + 1
                inspector.set_frame(test_frame)
                checks[:frame_selection] = inspector.selected_frame[] == test_frame

                original_highlight = inspector.highlight_active[]
                inspector.toggle_highlight()
                checks[:highlight_toggle] =
                    inspector.highlight_active[] != original_highlight

                original_ids = inspector.track_ids_active[]
                inspector.toggle_track_ids()
                checks[:track_id_toggle] = inspector.track_ids_active[] != original_ids

                if inspector.has_ground_truth
                    original_source = inspector.trajectory_source[]
                    inspector.toggle_trajectory_source()
                    checks[:trajectory_source_toggle] =
                        inspector.trajectory_source[] === :ground_truth &&
                        original_source === :found
                    gt_data = inspector.frame_track_sets[:ground_truth]
                    checks[:trajectory_source_2d_sync] =
                        inspector.selected_points[] ==
                        gt_data.frame_points[inspector.selected_frame[]]
                    expected_gt_segments = _padded(
                        _spacetime_line_segments(
                            track_render_sets[:ground_truth].continuous_points,
                            frame_inspector ? roi_bounds[] : nothing,
                        ),
                        continuous_capacity,
                        hidden_point,
                    )
                    checks[:trajectory_source_3d_sync] =
                        continuous_plot_points[] == expected_gt_segments
                    source_bbox = inspector.source_toggle_box.layoutobservables.computedbbox[]
                    source_center = Point2f(
                        source_bbox.origin[1] + 0.5f0 * widths(source_bbox)[1],
                        source_bbox.origin[2] + 0.5f0 * widths(source_bbox)[2],
                    )
                    checks[:trajectory_source_hitbox] =
                        custom_control_at(source_center) === :trajectory_source
                end

                # Exercise the actual root event router, including its WGL
                # pointer-settling path. This is intentionally separate from
                # the direct state-action checks above.
                inspector.reset_inspector()
                toggle_bbox = inspector.highlight_box.layoutobservables.computedbbox[]
                toggle_center = Point2f(
                    toggle_bbox.origin[1] + 0.5f0 * widths(toggle_bbox)[1],
                    toggle_bbox.origin[2] + 0.5f0 * widths(toggle_bbox)[2],
                )
                root_events.mouseposition[] = (
                    Float64(toggle_center[1]),
                    Float64(toggle_center[2]),
                )
                settle_task[] = nothing
                setindex!(
                    root_events.mousebutton,
                    Makie.MouseButtonEvent(Makie.Mouse.left, Makie.Mouse.press),
                )
                # The router must have started its settle task; wait for it.
                task = settle_task[]
                settled = !isnothing(task) &&
                    timedwait(() -> istaskdone(task), 5.0) === :ok
                setindex!(
                    root_events.mousebutton,
                    Makie.MouseButtonEvent(Makie.Mouse.left, Makie.Mouse.release),
                )
                checks[:root_canvas_route] = settled &&
                    inspector.last_browser_action[] == "highlight" &&
                    !inspector.highlight_active[]

                requested = (
                    0.20f0 * x_extent,
                    0.80f0 * x_extent,
                    0.20f0 * y_extent,
                    0.80f0 * y_extent,
                )
                inspector.set_roi(requested)
                visible_bounds = roi_bounds[]
                axis_bounds = _xy_bounds(
                    ax.finallimits[],
                    x_extent,
                    y_extent,
                )
                checks[:roi_changes] = visible_bounds !=
                    (0.0f0, x_extent, 0.0f0, y_extent)
                checks[:roi_3d_sync] = !isnothing(axis_bounds) && all(
                    isapprox.(visible_bounds, axis_bounds; atol=2.0f0 * eps(Float32)),
                )
                expected_frame_points_3d = _spacetime_clipped_points(
                    inspector.frame_track_sets[
                        inspector.trajectory_source[]
                    ].frame_points_3d[inspector.selected_frame[]],
                    visible_bounds,
                )
                checks[:frame_dots_3d_sync] =
                    inspector.current_frame_track_points_3d[] ==
                    expected_frame_points_3d
            end

            if !isnothing(links)
                links_visible[] = true
                trajectory_source[] === :found || (trajectory_source[] = :found)
                link_bounds = frame_inspector ? roi_bounds[] : nothing
                is_drawn(points) = [
                    points[2index - 1] != hidden_point || points[2index] != hidden_point
                    for index in 1:link_count
                ]
                drawn = is_drawn(link_points[])
                checks[:links_count_in_bounds] =
                    count(drawn) == link_clipped_count(link_bounds) &&
                    links_plot.visible[]
                drawn_colors = links_plot.color[]
                checks[:links_alpha] = length(drawn_colors) == 2 * link_count &&
                    all(1:link_count) do index
                        !drawn[index] || begin
                            expected = _link_alpha(
                                link_alpha,
                                links["w"][drawn_link_indices[index]],
                            )
                            abs(Float32(drawn_colors[2index - 1].alpha) - expected) <=
                                1.0f-6 &&
                            abs(Float32(drawn_colors[2index].alpha) - expected) <=
                                1.0f-6
                        end
                    end
                checks[:links_width] =
                    _links_width_ok(link_width, links_plot.linewidth[], drawn_weights)
                toggle_links!()
                hidden_off = !links_visible[] && !links_plot.visible[] &&
                    !any(is_drawn(link_points[]))
                toggle_links!()
                checks[:links_toggle] = hidden_off && links_visible[] &&
                    links_plot.visible[] && count(is_drawn(link_points[])) ==
                    link_clipped_count(link_bounds)
                if !isnothing(inspector) && inspector.has_ground_truth
                    inspector.toggle_trajectory_source()
                    gt_hidden = trajectory_source[] === :ground_truth &&
                        !links_plot.visible[] && !any(is_drawn(link_points[]))
                    inspector.toggle_trajectory_source()
                    checks[:links_found_source_only] = gt_hidden &&
                        trajectory_source[] === :found && links_plot.visible[] &&
                        count(is_drawn(link_points[])) ==
                        link_clipped_count(link_bounds)
                end
            end

            if haskey(scene, "trajectory_color_matches")
                truth_scene = track_sets[:ground_truth]
                truth_index = Dict(
                    id => index
                    for (index, id) in enumerate(_track_ids(truth_scene))
                )
                found_index = Dict(
                    id => index
                    for (index, id) in enumerate(_track_ids(scene))
                )
                checks[:matched_trajectory_colors] = all(
                    scene["trajectory_color_matches"],
                ) do match
                    found_color = @view scene["track_colors"][
                        found_index[match.estimate_id], :]
                    truth_color = @view truth_scene["track_colors"][
                        truth_index[match.truth_id], :]
                    found_color == truth_color
                end
                found_color_rows = [
                    Tuple(@view scene["track_colors"][index, :])
                    for index in axes(scene["track_colors"], 1)
                ]
                checks[:found_trajectory_colors_unique] =
                    allunique(found_color_rows)
            end
        catch error
            push!(failures, sprint(showerror, error))
        finally
            try
                reset_view!()
            catch error
                push!(failures, "reset after self-test: " * sprint(showerror, error))
            end
        end

        for (name, passed) in checks
            passed || push!(failures, string(name))
        end
        passed = isempty(failures) && !isempty(checks) && all(values(checks))
        if !isnothing(inspector)
            inspector.backend_health[] = passed ?
                "backend: PASS" : "backend: FAIL"
            inspector.browser_event_count[] = 0
            inspector.last_browser_action[] = "awaiting first browser event"
        end
        (; passed, checks, failures)
    end

    fig, ax, (;
        inspector,
        roi_bounds,
        trajectory_source,
        legend_text,
        track_sets,
        track_render_sets,
        raw_plot,
        trajectory_plots,
        dimer_plots,
        top_view_box,
        reset_box,
        links_plot,
        links_visible,
        links_box,
        toggle_links=toggle_links!,
        control_router,
        set_top_view=set_top_view!,
        reset_view=reset_view!,
        reassert_browser_state=reassert_browser_state!,
        self_test=control_self_test!,
    )
end
