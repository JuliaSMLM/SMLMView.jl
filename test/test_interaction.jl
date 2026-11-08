# Keyboard and mouse interaction of the array viewers, driven through the figure's events,
# and their keywords and input checks (bug-fix round 2026-11-07). Every testset here failed
# on 7dc2de3.
using Test
using SMLMView
using SMLMView.WGLMakie: Makie
using SMLMView.WGLMakie.Makie: events, KeyEvent, Keyboard, Label, red, green, blue, RGBf

# An array whose axes start at 2, as an OffsetArray's can (the viewers need one-based axes).
struct ShiftedAxes{T,N} <: AbstractArray{T,N}
    a::Array{T,N}
end
Base.size(s::ShiftedAxes) = size(s.a)
Base.axes(s::ShiftedAxes) = map(n -> Base.IdentityUnitRange(2:n+1), size(s.a))
Base.getindex(s::ShiftedAxes{T,N}, i::Vararg{Int,N}) where {T,N} = s.a[(i .- 1)...]

function press!(fig, k::Keyboard.Button)
    events(fig).keyboardbutton[] = KeyEvent(k, Keyboard.press)
    events(fig).keyboardbutton[] = KeyEvent(k, Keyboard.release)
end
action!(fig, a) = press!(fig, getfield(Keyboard, Symbol(SMLMView.getkey(a))))
dims!(fig, a, b) = (press!(fig, getfield(Keyboard, Symbol("_$a")));
                    press!(fig, getfield(Keyboard, Symbol("_$b"))))
status(fig) = first(c for c in fig.content if c isa Label).text[]

# Put the mouse over image pixel (row, col); row 1 is drawn at the top.
function hover!(v, row, col, nrows)
    vp = v.ax.scene.viewport[]
    lim = v.ax.finallimits[]
    x, y = col, nrows - row + 1
    px = vp.origin[1] + (x - lim.origin[1]) / lim.widths[1] * vp.widths[1]
    py = vp.origin[2] + (y - lim.origin[2]) / lim.widths[2] * vp.widths[2]
    events(v.fig).mouseposition[] = (px, py)
end

# The matrix the heatmap draws (before colorrange), in display orientation.
drawn(v) = v.ax.scene.plots[end][3][]

plane(v) = SMLMView.extract_slice_raw(v.data, v.display_dims[], v.slice_indices)

@testset "Interaction" begin
    @testset "slice stretch follows a display-dims change (M1)" begin
        # Plane k=1 spans 0..1; the planes that cross k reach about 180
        data = Float64[i + 2j + 3k for i in 1:20, j in 1:30, k in 1:40]
        data[:, :, 1] .= reshape(range(0, 1; length=600), 20, 30)
        v = smlmview(data; show=false)
        action!(v.fig, "stretch_cycle")
        @test v.stretch[] == :slice
        @test v.colorrange[] == extrema(plane(v))
        dims!(v.fig, 1, 3)
        @test v.display_dims[] == (1, 3)
        @test v.colorrange[] == extrema(plane(v))
        # set through the returned handle
        v.slice_indices[2][] = 7
        v.display_dims[] = (2, 3)
        @test v.colorrange[] == extrema(plane(v))
        # log mapping: offset and range from the plane now shown
        action!(v.fig, "mapping_cycle")
        dims!(v.fig, 1, 2)
        lo, hi = extrema(plane(v))
        @test collect(v.colorrange[]) ≈ [0.0, log10(hi - lo + 1)]
    end

    @testset "display-dims change keeps the slider dim's index" begin
        data = rand(16, 12, 30)
        v = smlmview(data; show=false)
        v.slice_indices[3][] = 25
        dims!(v.fig, 1, 3)            # dim 2 moves onto the slider (range 1:12)
        @test v.slice_indices[2][] == 1
        @test v.slice_indices[3][] == 25
        @test occursin("2:1/12", status(v.fig))
        dims!(v.fig, 1, 2)
        @test v.slice_indices[3][] == 25
        @test occursin("3:25/30", status(v.fig))
        # the slider widget shows the kept index, and a real move after the remap is honored
        dims!(v.fig, 1, 3)
        sl = only(c for c in v.fig.content if c isa Makie.Slider)
        @test sl.value[] == 1
        Makie.set_close_to!(sl, 5)
        @test v.slice_indices[2][] == 5
        @test v.slice_indices[3][] == 25
    end

    @testset "v.display_dims[] = ... moves the sliders too" begin
        data = rand(10, 11, 12)
        v = smlmview(data; show=false)
        v.display_dims[] = (1, 3)
        action!(v.fig, "slice_next")  # steps the slider dim, now dim 2
        @test v.slice_indices[2][] == 2
        @test v.slice_indices[3][] == 1
        @test occursin("2:2/11", status(v.fig))
        # and resets the view to the new plane (10 rows x 12 cols)
        action!(v.fig, "zoom_in")
        @test v.view_zoom_idx[] != SMLMView.DEFAULT_ZOOM_IDX
        v.display_dims[] = (2, 3)     # 11 rows x 12 cols
        @test v.view_zoom_idx[] == SMLMView.DEFAULT_ZOOM_IDX
        lim = v.ax.finallimits[]
        @test collect(lim.origin) ≈ [0.5, 0.5]
        @test collect(lim.widths) ≈ [12.0, 11.0]

        # composite viewer, the same through its handle
        a = [Float64(100i + 10j + k) for i in 1:6, j in 1:7, k in 1:5]
        c = smlmview((a, 2a); show=false)
        c.display_dims[] = (1, 3)     # 6 rows x 5 cols
        action!(c.fig, "slice_next")
        @test c.slice_indices[2][] == 2
        @test c.slice_indices[3][] == 1
        @test occursin("2:2/7", status(c.fig))
        lim = c.ax.finallimits[]
        @test collect(lim.widths) ≈ [5.0, 6.0]
        @test size(c.rgb[]) == (5, 6)
        # its remap keeps the index of the dim moving onto the slider (dim 3 at 25 of 30,
        # dim 2 has 7), and a real slider move after the remap is honored
        a = [Float64(100i + 10j + k) for i in 1:6, j in 1:7, k in 1:30]
        c = smlmview((a, 2a); show=false)
        c.slice_indices[3][] = 25
        c.display_dims[] = (1, 3)
        @test [o[] for o in c.slice_indices] == [1, 1, 25]
        sl = only(s for s in c.fig.content if s isa Makie.Slider)
        @test sl.value[] == 1
        Makie.set_close_to!(sl, 5)
        @test c.slice_indices[2][] == 5
        c.display_dims[] = (1, 2)
        @test sl.value[] == 25
        @test [o[] for o in c.slice_indices] == [1, 5, 25]
    end

    @testset "readout follows a display-dims change under a still mouse" begin
        data = reshape(Float64.(1:16*12*30), 16, 12, 30)
        v = smlmview(data; show=false)
        v.slice_indices[3][] = 25
        hover!(v, 8, 6, 16)
        @test v.cursor_pos[] == (8, 6) && v.pixel_value[] == data[8, 6, 25]
        dims!(v.fig, 1, 3)            # now 16 rows (dim 1) x 30 cols (dim 3), x at 1
        mp = Makie.mouseposition(v.ax.scene)
        r, c = 16 - round(Int, mp[2]) + 1, round(Int, mp[1])
        @test 1 <= r <= 16 && 1 <= c <= 30   # the mouse is still over the new plane
        @test v.cursor_pos[] == (r, c)
        @test v.pixel_value[] == data[r, v.slice_indices[2][], c]

        # composite viewer, through its handle
        a = reshape(Float64.(1:16*12*30), 16, 12, 30)
        cv = smlmview((a, 2a); show=false)
        cv.slice_indices[3][] = 25
        hover!(cv, 8, 6, 16)
        @test cv.pixel_values[] == (a[8, 6, 25], 2a[8, 6, 25])
        cv.display_dims[] = (1, 3)
        mp = Makie.mouseposition(cv.ax.scene)
        r, c = 16 - round(Int, mp[2]) + 1, round(Int, mp[1])
        @test 1 <= r <= 16 && 1 <= c <= 30
        @test cv.cursor_pos[] == (r, c)
        @test cv.pixel_values[] == (a[r, 1, c], 2a[r, 1, c])
    end

    @testset "log mapping on integer data" begin
        # UInt16, as a camera writes it
        data = UInt16.(reshape(100:100+16*16*3-1, 16, 16, 3))
        v = smlmview(data; show=false)
        @test_logs min_level=Base.CoreLogging.Warn action!(v.fig, "mapping_cycle")
        @test v.mapping[].name == :log
        p = Float64.(plane(v))
        @test sort(vec(drawn(v))) ≈ sort(vec(log10.(p .- minimum(p) .+ 1)))
        # Int16 whose span exceeds typemax(Int16): the shift must not wrap
        w = Int16[-20000 0; 10000 20000]
        v = smlmview(w; show=false)
        v.mapping_idx[] = 2
        @test sort(vec(drawn(v))) ≈ sort(vec(log10.(Float64.(w) .+ 20001)))
        @test v.colorrange[] == (0.0, log10(40001))
        c = smlmview((w, w); show=false)
        c.mapping_idx[] = 2
        @test all(isfinite, red.(c.rgb[]) .+ green.(c.rgb[]) .+ blue.(c.rgb[]))
    end

    @testset "log under global stretch is on one global scale" begin
        # slice k spans 100k+2 .. 100k+16; global minimum 102 (slice 1)
        data = Float64[100k + i + j for i in 1:8, j in 1:8, k in 1:3]
        gmin, gmax = extrema(data)
        v = smlmview(data; show=false)
        action!(v.fig, "mapping_cycle")
        action!(v.fig, "slice_next")
        @test v.stretch[] == :global && v.mapping[].name == :log
        p = plane(v)
        @test sort(vec(drawn(v))) ≈ sort(vec(log10.(p .- gmin .+ 1)))
        @test collect(v.colorrange[]) ≈ [0.0, log10(gmax - gmin + 1)]
        # slice stretch: the shown plane's own minimum, for values and range alike
        action!(v.fig, "stretch_cycle")
        @test sort(vec(drawn(v))) ≈ sort(vec(log10.(p .- minimum(p) .+ 1)))
        @test collect(v.colorrange[]) ≈ collect(Float64.(extrema(drawn(v)))) rtol=1e-6  # drawn is Float32
        # composite, global stretch: channel 1 is cyan, so green carries its normalized value
        c = smlmview((data, data); show=false)
        c.mapping_idx[] = 2
        c.slice_indices[3][] = 2
        want = log10.(p .- gmin .+ 1) ./ log10(gmax - gmin + 1)
        @test sort(vec(green.(c.rgb[]))) ≈ sort(vec(want))
        # a NaN pixel leaves the offset, and so every other drawn value, finite
        data[3, 4, 1] = NaN
        v = smlmview(data; show=false)
        v.mapping_idx[] = 2           # global stretch, slice 1 holds the NaN
        @test count(isnan, drawn(v)) == 1
        v.slice_indices[3][] = 2
        @test sort(vec(drawn(v))) ≈ sort(vec(log10.(plane(v) .- gmin .+ 1)))
        v.slice_indices[3][] = 1
        v.stretch_idx[] = 2
        @test count(isnan, drawn(v)) == 1
        # a -Inf pixel draws at the bottom of the range; the rest of its plane stays finite
        data[3, 4, 1] = 0
        data[2, 2, 2] = -Inf
        for stretch in (1, 2)
            v = smlmview(data; show=false)
            v.stretch_idx[] = stretch
            v.mapping_idx[] = 2
            v.slice_indices[3][] = 2
            @test all(isfinite, drawn(v))
            @test minimum(drawn(v)) == 0
            @test occursin("3:2/3", status(v.fig))
            c = smlmview((data, data); show=false)
            c.stretch_idx[] = stretch
            c.mapping_idx[] = 2
            c.slice_indices[3][] = 2
            @test all(x -> all(isfinite, (red(x), green(x), blue(x))), c.rgb[])
        end
        # data changed in place below the cached global minimum still draws
        data[2, 2, 2] = 250
        v = smlmview(data; show=false)
        v.mapping_idx[] = 2
        data[:, :, 3] .-= 500
        v.slice_indices[3][] = 3
        @test all(isfinite, drawn(v))
        @test occursin("3:3/3", status(v.fig))
    end

    @testset "status bar shows the current slice" begin
        v = smlmview(rand(8, 8, 10); show=false)  # mouse not over the image
        action!(v.fig, "slice_next")
        action!(v.fig, "slice_next")
        @test v.slice_indices[3][] == 3
        @test occursin("3:3/10", status(v.fig))
    end

    @testset "composite readout follows keyboard slice steps (M2)" begin
        a = [Float64(k) for i in 1:6, j in 1:7, k in 1:5]
        b = 10 .* a
        v = smlmview((a, b); show=false)
        hover!(v, 2, 3, 6)
        @test v.cursor_pos[] == (2, 3)
        @test v.pixel_values[] == (1.0, 10.0)
        action!(v.fig, "slice_next")
        action!(v.fig, "slice_next")
        @test v.slice_indices[3][] == 3
        @test v.pixel_values[] == (3.0, 30.0)
        s = status(v.fig)
        @test occursin("[3, 30]", s)
        @test occursin("3:3/5", s)
        # channel toggle shows in the status at once
        press!(v.fig, Keyboard._1)
        @test !v.channel_visible[1][]
        @test occursin("ch:-2", status(v.fig))
    end
end

@testset "Keywords and input checks" begin
    @testset "full range is the exact minimum and maximum" begin
        # 1500x1500 values: more than max_samples, so the quantile path samples every 2nd
        # value; the extremes sit at odd linear indices, between those samples.
        data = zeros(Float32, 1500, 1500)
        data[1] = 1000
        data[3] = -5
        data[5] = NaN
        @test SMLMView.compute_colorrange_sampled(data, (0.0, 1.0)) == (-5.0, 1000.0)
        @test smlmview(data; show=false).colorrange[] == (-5.0, 1000.0)
        c = smlmview((data, 2 .* data); show=false)
        @test [r[] for r in c.channel_ranges] == [(-5.0, 1000.0), (-10.0, 2000.0)]
    end

    @testset "ranges of data with no finite value, or one value" begin
        @test SMLMView.compute_colorrange_sampled(fill(NaN, 10, 10), (0.0, 1.0)) == (0.0, 1.0)
        @test SMLMView.compute_colorrange_sampled(fill(NaN, 10, 10), (0.05, 0.95)) == (0.0, 1.0)
        @test smlmview(fill(NaN, 10, 10); show=false).colorrange[] == (0.0, 1.0)
        @test SMLMView.compute_colorrange_sampled(fill(3.0, 4, 4), (0.0, 1.0)) == (3.0, 4.0)
        lo, hi = SMLMView.compute_colorrange_sampled(fill(1e17, 4, 4), (0.0, 1.0))
        @test Float32(lo) < Float32(hi)  # still a range after Makie's Float32 conversion
    end

    @testset "status values: zero and whole numbers print as integers" begin
        @test SMLMView.format_value(0) == "0"
        @test SMLMView.format_value(0.0) == "0"
        @test SMLMView.format_value(UInt16(0)) == "0"
        @test SMLMView.format_value(123456) == "123456"
        @test SMLMView.format_value(2.5) == "2.500"
        @test SMLMView.format_value(1.5e-5) == "1.500e-05"
        @test SMLMView.format_value(NaN) == "NaN"
        z = Float64[i + j for i in 1:6, j in 1:7]
        z[2, 3] = 0
        v = smlmview(z; show=false)
        hover!(v, 2, 3, 6)
        @test startswith(status(v.fig), "(2, 3) = 0 |")
    end

    @testset "clip keyword holds through the g and m cycles" begin
        data = reshape(Float64.(0:9999), 100, 100)
        want = SMLMView.compute_colorrange_sampled(data, (0.05, 0.95))
        v = smlmview(data; clip=(0.05, 0.95), show=false)
        @test v.colorrange[] == want
        @test occursin("linear 5-95%", status(v.fig))
        action!(v.fig, "stretch_cycle")
        action!(v.fig, "stretch_cycle")
        @test v.colorrange[] == want
        for _ in 1:4
            action!(v.fig, "mapping_cycle")
        end
        @test v.mapping[].name == :linear
        @test v.colorrange[] == want
        c = smlmview((data, 2 .* data); clip=(0.05, 0.95), show=false)
        start = [r[] for r in c.channel_ranges]
        @test start[1] == want
        for _ in 1:4
            action!(c.fig, "mapping_cycle")
        end
        @test [r[] for r in c.channel_ranges] == start
        @test occursin("linear 5-95%", status(c.fig))
        @test_throws ArgumentError smlmview(data; clip=(0.9, 0.1), show=false)
        @test_throws ArgumentError smlmview((data, data); clip=(0.0, 1.5), show=false)
    end

    @testset "reset view centers the image" begin
        for v in (smlmview(rand(10, 20); show=false), smlmview((rand(10, 20), rand(10, 20)); show=false))
            action!(v.fig, "reset")
            @test v.view_center[] == (5.5, 10.5)
            action!(v.fig, "zoom_in")
            lim = v.ax.targetlimits[]
            @test lim.origin .+ lim.widths ./ 2 ≈ [10.5, 5.5]
        end
    end

    @testset "colormap keyword: any Makie colormap" begin
        v = smlmview(rand(4, 4); colormap=:magma, show=false)
        @test v.colormap[] == :magma
        action!(v.fig, "colormap_cycle")
        @test v.colormap[] == :grays
        for _ in 1:length(SMLMView.COLORMAPS)
            action!(v.fig, "colormap_cycle")
        end
        @test v.colormap[] == :magma
        @test smlmview(rand(4, 4); colormap=:viridis, show=false).colormap[] == :viridis
        @test_throws ArgumentError smlmview(rand(4, 4); colormap=:notacolormap, show=false)
    end

    @testset "title keyword" begin
        @test smlmview(rand(4, 4); title="Cell 1", show=false).ax.title[] == "Cell 1"
        @test smlmview((rand(4, 4), rand(4, 4)); title="Cell 1", show=false).ax.title[] == "Cell 1"
    end

    @testset "invalid display_dims through the handle is refused and put back" begin
        v = smlmview(rand(5, 6, 7); show=false)
        @test_throws ArgumentError (v.display_dims[] = (1, 1))
        @test v.display_dims[] == (1, 2)
        @test_throws ArgumentError (v.display_dims[] = (1, 4))
        @test v.display_dims[] == (1, 2)
        action!(v.fig, "slice_next")
        @test v.slice_indices[3][] == 2
        @test drawn(v) ≈ permutedims(reverse(plane(v); dims=1))
        v.display_dims[] = (1, 3)
        @test occursin("(1,3) | 2:1/6", status(v.fig))
        c = smlmview((rand(5, 6, 7), rand(5, 6, 7)); show=false)
        @test_throws ArgumentError (c.display_dims[] = (3, 3))
        @test c.display_dims[] == (1, 2)
        @test_throws ArgumentError (c.display_dims[] = (0, 2))
        @test c.display_dims[] == (1, 2)
    end

    @testset "input checks run before use" begin
        @test_throws ArgumentError smlmview((rand(8, 8), rand(8, 8)); display_dims=(1, 3), show=false)
        @test_throws ArgumentError smlmview((rand(8, 8), rand(8, 8)); display_dims=(1, 1), show=false)
        @test_throws r"element type" smlmview(rand(ComplexF64, 8, 8); show=false)
        @test_throws r"element type" smlmview((rand(8, 8), rand(ComplexF64, 8, 8)); show=false)
        @test_throws r"one-based" smlmview(ShiftedAxes(rand(4, 4)); show=false)
        @test_throws r"one-based" smlmview((rand(4, 4), ShiftedAxes(rand(4, 4))); show=false)
        @test_throws ArgumentError smlmview((rand(4, 4), rand(4, 4, 2)); show=false)
        @test_throws ArgumentError smlmview((rand(4, 4), rand(4, 4)); names=("a",), show=false)
        @test_throws ArgumentError smlmview((rand(4, 4), rand(4, 4)); colors=(RGBf(1, 0, 0),), show=false)
        @test_throws ArgumentError smlmview((rand(4, 4), rand(4, 4)); colors=(1, "x"), show=false)
    end

    @testset "composite takes mixed channel types, color forms and names" begin
        a = Float32[i + j for i in 1:6, j in 1:7]
        b = UInt16[10i + j for i in 1:6, j in 1:7]
        v = smlmview((a, b); names=("ref", "frame"), show=false)
        hover!(v, 2, 3, 6)
        @test v.pixel_values[] == (5.0, 23.0)
        s = status(v.fig)
        @test occursin("[ref=5, frame=23]", s)
        @test occursin("ch:ref/frame", s)
        press!(v.fig, Keyboard._1)
        @test occursin("ch:-/frame", status(v.fig))
        @test smlmview((view(a, :, :), Array(a)); show=false).colors == SMLMView.DEFAULT_CHANNEL_COLORS[1:2]
        rgb = CHANNEL_COLOR_PRESETS[:rgb]
        @test smlmview((a, a); colors=rgb, show=false).colors == rgb[1:2]
        @test smlmview((a, a); colors=(RGBf(1, 0, 0), RGBf(0, 1, 0)), show=false).colors == rgb[1:2]
        @test smlmview((a, a); colors=(:red, :lime), show=false).colors == rgb[1:2]
    end
end
