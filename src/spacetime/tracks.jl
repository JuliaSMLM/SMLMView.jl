# Track sets (found / ground truth): render data for the 3D layers, per-frame
# data for the 2D inspector, and dimer episodes.

function _dimer_data(scene)
    xs = get(scene, "dimer_x", Vector{Vector{Float32}}())
    ys = get(scene, "dimer_y", Vector{Vector{Float32}}())
    zs = get(scene, "dimer_z", Vector{Vector{Float32}}())
    fine_frames = get(
        scene,
        "dimer_fine_frames",
        Vector{Vector{Int}}(),
    )
    labels = String.(get(scene, "dimer_labels", String[]))
    track_indices = Int.(get(scene, "dimer_track_indices", zeros(Int, 0, 2)))
    track_ids = Int.(get(scene, "dimer_track_ids", zeros(Int, 0, 2)))
    n_episodes = length(xs)
    length(ys) == n_episodes || error("Cell9 dimer x/y paths must align")
    length(zs) == n_episodes || error("Cell9 dimer x/z paths must align")
    length(fine_frames) == n_episodes ||
        error("Cell9 dimer paths/fine frames must align")
    length(labels) == n_episodes ||
        error("Cell9 dimer paths/labels must align")
    size(track_indices) == (n_episodes, 2) ||
        error("Cell9 dimer track-index pairs must be n×2")
    size(track_ids) == (n_episodes, 2) ||
        error("Cell9 dimer track-id pairs must be n×2")
    for episode_index in 1:n_episodes
        n_points = length(xs[episode_index])
        n_points > 0 || error("Cell9 dimer episodes cannot be empty")
        length(ys[episode_index]) == n_points ||
            error("Cell9 dimer episode x/y lengths must align")
        length(zs[episode_index]) == n_points ||
            error("Cell9 dimer episode x/z lengths must align")
        length(fine_frames[episode_index]) == n_points ||
            error("Cell9 dimer episode positions/frames must align")
    end
    (;
        xs,
        ys,
        zs,
        fine_frames,
        labels,
        track_indices,
        track_ids,
        n_episodes,
    )
end

function _track_sets(scene)
    sets = Dict{Symbol,Any}(:found => scene)
    if haskey(scene, "ground_truth_tracks")
        sets[:ground_truth] = scene["ground_truth_tracks"]
    end
    sets
end

function _track_render_data(track_scene)
    n_tracks = length(track_scene["track_x"])
    track_colors = track_scene["track_colors"]
    size(track_colors) == (n_tracks, 3) ||
        error("Cell9 track colors must be n_tracks×3")
    continuous_points = Point3f[]
    continuous_halo_colors = RGBAf[]
    continuous_mid_colors = RGBAf[]
    continuous_core_colors = RGBf[]
    gap_points = Point3f[]
    gap_halo_colors = RGBAf[]
    gap_core_colors = RGBAf[]
    singleton_points = Point3f[]
    singleton_halo_colors = RGBAf[]
    singleton_core_colors = RGBf[]
    separator = Point3f(NaN32, NaN32, NaN32)

    for track_index in 1:n_tracks
        xs = track_scene["track_x"][track_index]
        ys = track_scene["track_y"][track_index]
        zs = track_scene["track_z"][track_index]
        fine_frames = track_scene["track_fine_frames"][track_index]
        length(ys) == length(xs) == length(zs) == length(fine_frames) ||
            error("Cell9 trajectory positions and fine frames must align")
        isempty(xs) && continue

        color = RGBf(
            track_colors[track_index, 1],
            track_colors[track_index, 2],
            track_colors[track_index, 3],
        )
        core_color = RGBf(
            0.18f0 + 0.82f0 * color.r,
            0.18f0 + 0.82f0 * color.g,
            0.18f0 + 0.82f0 * color.b,
        )
        if length(xs) == 1
            push!(singleton_points, Point3f(xs[1], ys[1], zs[1]))
            push!(
                singleton_halo_colors,
                RGBAf(color.r, color.g, color.b, 0.34f0),
            )
            push!(singleton_core_colors, core_color)
        end
        continuous, gaps = _spacetime_paths(xs, ys, zs, fine_frames)
        append!(continuous_points, continuous)
        append!(
            continuous_halo_colors,
            fill(RGBAf(color.r, color.g, color.b, 0.12f0), length(continuous)),
        )
        append!(
            continuous_mid_colors,
            fill(RGBAf(color.r, color.g, color.b, 0.34f0), length(continuous)),
        )
        append!(continuous_core_colors, fill(core_color, length(continuous)))
        push!(continuous_points, separator)
        push!(continuous_halo_colors, RGBAf(color.r, color.g, color.b, 0.12f0))
        push!(continuous_mid_colors, RGBAf(color.r, color.g, color.b, 0.34f0))
        push!(continuous_core_colors, core_color)

        if !isempty(gaps)
            append!(gap_points, gaps)
            append!(
                gap_halo_colors,
                fill(RGBAf(color.r, color.g, color.b, 0.16f0), length(gaps)),
            )
            append!(
                gap_core_colors,
                fill(
                    RGBAf(core_color.r, core_color.g, core_color.b, 0.78f0),
                    length(gaps),
                ),
            )
        end
    end

    dimers = _dimer_data(track_scene)
    dimer_points = Point3f[]
    dimer_onset_points = Point3f[]
    dimer_label_points = Point3f[]
    dimer_labels = String[]
    for episode_index in 1:dimers.n_episodes
        episode_points = Point3f[
            Point3f(x, y, z)
            for (x, y, z) in zip(
                dimers.xs[episode_index],
                dimers.ys[episode_index],
                dimers.zs[episode_index],
            )
        ]
        append!(dimer_points, episode_points)
        push!(dimer_points, separator)
        push!(dimer_onset_points, first(episode_points))
        push!(dimer_label_points, episode_points[cld(length(episode_points), 2)])
        push!(dimer_labels, dimers.labels[episode_index])
    end

    (;
        track_scene,
        n_tracks,
        n_emitters=sum(length, track_scene["track_x"]; init=0),
        dimers,
        continuous_points,
        continuous_halo_colors,
        continuous_mid_colors,
        continuous_core_colors,
        gap_points,
        gap_halo_colors,
        gap_core_colors,
        singleton_points,
        singleton_halo_colors,
        singleton_core_colors,
        dimer_points,
        dimer_onset_points,
        dimer_label_points,
        dimer_labels,
    )
end

function _frame_track_data(track_scene, n_frames, sub_steps)
    n_tracks = length(track_scene["track_x"])
    track_ids = Int.(get(track_scene, "track_ids", collect(1:n_tracks)))
    length(track_ids) == n_tracks ||
        error("Cell9 track IDs must align with serialized trajectories")
    track_colors = track_scene["track_colors"]
    track_core_colors = RGBf[
        RGBf(
            0.18f0 + 0.82f0 * track_colors[track_index, 1],
            0.18f0 + 0.82f0 * track_colors[track_index, 2],
            0.18f0 + 0.82f0 * track_colors[track_index, 3],
        )
        for track_index in 1:n_tracks
    ]
    frame_points = [Point2f[] for _ in 1:n_frames]
    frame_points_3d = [Point3f[] for _ in 1:n_frames]
    frame_point_colors = [RGBf[] for _ in 1:n_frames]
    frame_point_track_indices = [Int[] for _ in 1:n_frames]
    frame_label_positions = [Point2f[] for _ in 1:n_frames]
    frame_label_texts = [String[] for _ in 1:n_frames]
    frame_dimer_points = [Point2f[] for _ in 1:n_frames]
    frame_dimer_label_positions = [Point2f[] for _ in 1:n_frames]
    frame_dimer_label_texts = [String[] for _ in 1:n_frames]
    label_prefix = String(get(track_scene, "track_label_prefix", "T"))
    track_labels = String.(get(
        track_scene,
        "track_labels",
        ["$label_prefix$index" for index in 1:n_tracks],
    ))
    length(track_labels) == n_tracks ||
        error("Cell9 track labels must align with serialized trajectories")

    for track_index in 1:n_tracks
        track_points_by_frame = Dict{Int,Vector{Point2f}}()
        for point_index in eachindex(track_scene["track_x"][track_index])
            fine_frame = track_scene["track_fine_frames"][track_index][point_index]
            frame_index = fld(fine_frame - 1, sub_steps) + 1
            1 <= frame_index <= n_frames || continue
            point = Point2f(
                track_scene["track_x"][track_index][point_index],
                track_scene["track_y"][track_index][point_index],
            )
            push!(frame_points[frame_index], point)
            push!(frame_points_3d[frame_index], Point3f(
                point[1], point[2], track_scene["track_z"][track_index][point_index],
            ))
            push!(frame_point_colors[frame_index], track_core_colors[track_index])
            push!(frame_point_track_indices[frame_index], track_index)
            push!(get!(track_points_by_frame, frame_index, Point2f[]), point)
        end
        for (frame_index, points) in track_points_by_frame
            inverse_count = inv(length(points))
            push!(frame_label_positions[frame_index], Point2f(
                sum(point[1] for point in points) * inverse_count,
                sum(point[2] for point in points) * inverse_count,
            ))
            push!(frame_label_texts[frame_index], track_labels[track_index])
        end
    end

    dimers = _dimer_data(track_scene)
    for episode_index in 1:dimers.n_episodes
        episode_points = Dict{Int,Vector{Point2f}}()
        for point_index in eachindex(dimers.xs[episode_index])
            fine_frame = dimers.fine_frames[episode_index][point_index]
            frame_index = fld(fine_frame - 1, sub_steps) + 1
            1 <= frame_index <= n_frames || continue
            point = Point2f(
                dimers.xs[episode_index][point_index],
                dimers.ys[episode_index][point_index],
            )
            push!(frame_dimer_points[frame_index], point)
            push!(get!(episode_points, frame_index, Point2f[]), point)
        end
        for (frame_index, points) in episode_points
            inverse_count = inv(length(points))
            push!(frame_dimer_label_positions[frame_index], Point2f(
                sum(point[1] for point in points) * inverse_count,
                sum(point[2] for point in points) * inverse_count,
            ))
            push!(frame_dimer_label_texts[frame_index], dimers.labels[episode_index])
        end
    end

    track_continuous_paths = Vector{Vector{Point3f}}(undef, n_tracks)
    track_gap_paths = Vector{Vector{Point3f}}(undef, n_tracks)
    track_point_paths = Vector{Vector{Point3f}}(undef, n_tracks)
    for track_index in 1:n_tracks
        track_point_paths[track_index] = Point3f[
            Point3f(x, y, z)
            for (x, y, z) in zip(
                track_scene["track_x"][track_index],
                track_scene["track_y"][track_index],
                track_scene["track_z"][track_index],
            )
        ]
        continuous, gaps = _spacetime_paths(
            track_scene["track_x"][track_index],
            track_scene["track_y"][track_index],
            track_scene["track_z"][track_index],
            track_scene["track_fine_frames"][track_index],
        )
        track_continuous_paths[track_index] = continuous
        track_gap_paths[track_index] = gaps
    end

    (;
        track_scene,
        n_tracks,
        track_ids,
        track_labels,
        track_core_colors,
        frame_points,
        frame_points_3d,
        frame_point_colors,
        frame_point_track_indices,
        frame_label_positions,
        frame_label_texts,
        frame_dimer_points,
        frame_dimer_label_positions,
        frame_dimer_label_texts,
        track_continuous_paths,
        track_gap_paths,
        track_point_paths,
    )
end
