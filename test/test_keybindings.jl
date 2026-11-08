using Test
using SMLMView

@testset "Keybindings" begin
    @testset "list_keys" begin
        keys = list_keys()
        @test keys isa Vector{String}
        @test !isempty(keys)
        @test issorted(keys)

        # Check common keys exist
        @test "a" in keys
        @test "z" in keys
        @test "0" in keys
        @test !("9" in keys)  # digits 1-9 pick display dims and toggle channels
        @test "space" in keys
        @test "enter" in keys
    end

    @testset "list_actions" begin
        actions = list_actions()
        @test actions isa Vector{String}
        @test !isempty(actions)
        @test issorted(actions)

        # Check expected actions exist
        @test "zoom_in" in actions
        @test "zoom_out" in actions
        @test "reset" in actions
        @test "pan_up" in actions
        @test "pan_down" in actions
        @test "pan_left" in actions
        @test "pan_right" in actions
        @test "slice_prev" in actions
        @test "slice_next" in actions
        @test "colormap_cycle" in actions
        @test "mapping_cycle" in actions
        @test "stretch_cycle" in actions
    end

    @testset "get_keybindings" begin
        bindings = get_keybindings()
        @test bindings isa Dict{String, String}
        @test !isempty(bindings)

        # All actions should have bindings
        actions = list_actions()
        for action in actions
            @test haskey(bindings, action)
            @test bindings[action] isa String
            @test !isempty(bindings[action])
        end

        # Check default bindings
        @test bindings["zoom_in"] == "i"
        @test bindings["zoom_out"] == "o"
        @test bindings["reset"] == "r"
    end

    @testset "set_keybinding!" begin
        # Save original binding
        original = get_keybindings()["zoom_in"]

        # Set new binding
        set_keybinding!(:zoom_in, "k")
        @test get_keybindings()["zoom_in"] == "k"

        # Also works with String action
        set_keybinding!("zoom_in", "p")
        @test get_keybindings()["zoom_in"] == "p"

        # Restore original
        set_keybinding!(:zoom_in, original)
        @test get_keybindings()["zoom_in"] == original
    end

    @testset "set_keybinding! errors" begin
        # Invalid action or key
        @test_throws ArgumentError set_keybinding!("invalid_action", "a")
        @test_throws ArgumentError set_keybinding!("zoom_in", "invalid_key")
        # A digit (it picks display dims and toggles channels) or another action's key
        # could never fire; neither is accepted nor saved
        @test_throws ArgumentError set_keybinding!(:zoom_in, "1")
        @test_throws ArgumentError set_keybinding!(:zoom_in, "r")
        @test get_keybindings()["zoom_in"] == "i"
        @test SMLMView.Preferences.load_preference(SMLMView, "zoom_in") in (nothing, "i")
    end

    # Run f with these saved preferences, then put the active project's LocalPreferences.toml
    # back exactly as it was (f may save others through set_keybinding!).
    function with_saved(f, prefs::Pair...)
        path = joinpath(dirname(Base.active_project()), "LocalPreferences.toml")
        before = isfile(path) ? read(path, String) : nothing
        isempty(prefs) || SMLMView.Preferences.set_preferences!(SMLMView, prefs...; force=true)
        try
            f()
        finally
            before === nothing ? rm(path; force=true) : write(path, before)
            SMLMView.load_keybindings!()
        end
    end

    @testset "an invalid saved key falls back to the default" begin
        with_saved("zoom_in" => "notakey") do
            @test_logs (:warn, r"'notakey'.*'i'") SMLMView.load_keybindings!()
            @test get_keybindings()["zoom_in"] == "i"
        end
        with_saved("zoom_in" => "1") do
            @test_logs (:warn, r"'1'.*digit.*'i'") SMLMView.load_keybindings!()
            @test get_keybindings()["zoom_in"] == "i"
        end
    end

    @testset "saved keys that collide go back to their defaults" begin
        # zoom_in on reset's key: zoom_in goes back to i, so reset keeps r
        with_saved("zoom_in" => "r") do
            @test_logs (:warn, r"'r'.*'reset'.*'zoom_in'") SMLMView.load_keybindings!()
            b = get_keybindings()
            @test b["zoom_in"] == "i" && b["reset"] == "r"
        end
        # a chain: zoom_in back to i then collides with pan_up's saved i, which goes back to e
        with_saved("zoom_in" => "r", "pan_up" => "i") do
            SMLMView.load_keybindings!()
            b = get_keybindings()
            @test length(unique(values(b))) == length(b)
            @test b["zoom_in"] == "i" && b["pan_up"] == "e" && b["reset"] == "r"
        end
    end

    @testset "the saved bindings are the ones in effect after a change" begin
        # a collision saved before set_keybinding! refused them: reset on zoom_in's key
        with_saved("reset" => "i") do
            @test_logs (:warn, r"'reset'") SMLMView.load_keybindings!()
            @test get_keybindings()["reset"] == "r"
            set_keybinding!(:zoom_in, "k")
            set_keybinding!(:zoom_out, "i")
            P = SMLMView.Preferences
            @test P.load_preference(SMLMView, "reset") === nothing  # the repaired one is gone
            @test P.load_preference(SMLMView, "zoom_out") == "i"
            SMLMView.load_keybindings!()  # as at the next start
            b = get_keybindings()
            @test (b["reset"], b["zoom_in"], b["zoom_out"]) == ("r", "k", "i")
        end
    end

    @testset "a default saved or reset holds over an inherited preference" begin
        # Another environment on the load path saves zoom_in = "k" (an inherited preference)
        parent = mktempdir()
        write(joinpath(parent, "Project.toml"),
              "[deps]\nSMLMView = \"$(Base.PkgId(SMLMView).uuid)\"\n")
        write(joinpath(parent, "LocalPreferences.toml"), "[SMLMView]\nzoom_in = \"k\"\n")
        push!(LOAD_PATH, parent)
        try
            # `missing` lifts any local setting or block of zoom_in left by earlier tests
            with_saved("zoom_in" => missing) do
                SMLMView.load_keybindings!()
                @test get_keybindings()["zoom_in"] == "k"  # inherited
                set_keybinding!(:zoom_in, "i")              # back to the default
                SMLMView.load_keybindings!()                # as at the next start
                @test get_keybindings()["zoom_in"] == "i"
            end
            with_saved("zoom_in" => missing) do
                SMLMView.load_keybindings!()
                @test get_keybindings()["zoom_in"] == "k"
                reset_keybindings!()
                @test get_keybindings()["zoom_in"] == "i"
                SMLMView.load_keybindings!()
                @test get_keybindings()["zoom_in"] == "i"
            end
        finally
            pop!(LOAD_PATH)
            rm(parent; recursive=true, force=true)
            SMLMView.load_keybindings!()
        end
    end

    @testset "a rebound key works in a viewer" begin
        K = SMLMView.Keyboard
        v = smlmview(rand(8, 8); show=false)
        set_keybinding!(:zoom_in, "k")
        try
            key = SMLMView.WGLMakie.Makie.KeyEvent
            events = SMLMView.WGLMakie.Makie.events
            events(v.fig).keyboardbutton[] = key(K.k, K.press)
            @test v.view_zoom_idx[] == SMLMView.DEFAULT_ZOOM_IDX + 1
            events(v.fig).keyboardbutton[] = key(K.i, K.press)
            @test v.view_zoom_idx[] == SMLMView.DEFAULT_ZOOM_IDX + 1
        finally
            set_keybinding!(:zoom_in, "i")
        end
    end

    @testset "reset_keybindings!" begin
        # Change a binding
        set_keybinding!(:zoom_in, "k")
        @test get_keybindings()["zoom_in"] == "k"

        # Reset
        reset_keybindings!()

        # Should be back to default
        @test get_keybindings()["zoom_in"] == "i"
        @test get_keybindings()["zoom_out"] == "o"
        @test get_keybindings()["reset"] == "r"
    end
end
