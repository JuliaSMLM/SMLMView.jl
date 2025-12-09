#=============================================================================
# Display configuration (Bonito/WGLMakie setup)
=============================================================================#

# Track if we've configured Bonito
const _bonito_configured = Ref(false)

"""
    configure_display!(; port=8080)

Configure Bonito server for WGLMakie display. Call once per Julia session.
Automatically called on first `smlmview()` if not already configured.

For VSCode Remote, this sets up the proxy_url for proper WebSocket tunneling.
"""
function configure_display!(; port::Int=DEFAULT_PORT)
    if _bonito_configured[]
        @info "Bonito already configured, skipping"
        return nothing
    end

    Bonito.configure_server!(
        listen_port=port,
        listen_url="127.0.0.1",
        proxy_url="http://localhost:$(port)"
    )
    _bonito_configured[] = true
    @info "SMLMView display configured on port $port"
    return nothing
end

"""
Ensure Bonito is configured before display.
"""
function ensure_display_configured!()
    if !_bonito_configured[]
        configure_display!()
    end
end
