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
        @test "9" in keys
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
        # Invalid action should error
        @test_throws ErrorException set_keybinding!("invalid_action", "a")

        # Invalid key should error
        @test_throws ErrorException set_keybinding!("zoom_in", "invalid_key")
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
