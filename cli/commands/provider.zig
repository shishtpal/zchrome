const std = @import("std");
const cdp = @import("cdp");
const config_mod = @import("../config.zig");
const session_mod = @import("../session.zig");
const cloud = @import("../cloud.zig");

const Provider = cdp.Provider;
const SessionInfo = cdp.SessionInfo;

/// Provider management command
/// Usage:
///   zchrome provider                  - Show current provider status
///   zchrome provider list             - List available providers
///   zchrome provider set <name>       - Set default provider for session
///   zchrome provider status           - Show active session details
///   zchrome provider close            - Close active cloud session
pub fn providerCmd(
    session_ctx: *const session_mod.SessionContext,
    positional: []const []const u8,
    environ_map: *std.process.Environ.Map,
) !void {
    const allocator = session_ctx.allocator;

    if (positional.len == 0) {
        // Show current provider status
        try showStatus(session_ctx, environ_map);
        return;
    }

    const subcmd = positional[0];

    if (std.mem.eql(u8, subcmd, "list")) {
        try listProviders(environ_map);
    } else if (std.mem.eql(u8, subcmd, "set")) {
        if (positional.len < 2) {
            std.debug.print("Usage: zchrome provider set <name>\n", .{});
            std.debug.print("Available providers: local, kernel, notte, browserbase, browserless\n", .{});
            return;
        }
        try setProvider(session_ctx, positional[1], allocator);
    } else if (std.mem.eql(u8, subcmd, "status")) {
        try showStatus(session_ctx, environ_map);
    } else if (std.mem.eql(u8, subcmd, "close")) {
        try closeSession(session_ctx, environ_map);
    } else if (std.mem.eql(u8, subcmd, "--help") or std.mem.eql(u8, subcmd, "help")) {
        printHelp();
    } else {
        std.debug.print("Unknown provider subcommand: {s}\n", .{subcmd});
        printHelp();
    }
}

fn listProviders(environ_map: *std.process.Environ.Map) !void {
    const providers = cdp.listProviders();

    std.debug.print("\nAvailable Cloud Browser Providers:\n", .{});
    std.debug.print("{s:-<60}\n", .{""});

    for (providers) |p| {
        const has_key = if (p.api_key_env_var.len > 0)
            environ_map.get(p.api_key_env_var) != null
        else
            true; // Local doesn't need a key

        const status = if (has_key) "[configured]" else "[needs API key]";

        std.debug.print("  {s:<15} {s:<20} {s}\n", .{
            p.name,
            p.display_name,
            status,
        });

        if (p.api_key_env_var.len > 0) {
            std.debug.print("                  env: {s}\n", .{p.api_key_env_var});
        }
    }

    std.debug.print("\nTo set a provider: zchrome provider set <name>\n", .{});
    std.debug.print("To configure: set the environment variable shown above\n\n", .{});
}

fn setProvider(session_ctx: *const session_mod.SessionContext, provider_name: []const u8, allocator: std.mem.Allocator) !void {
    // Validate provider name
    const provider = cdp.getProvider(provider_name) orelse {
        std.debug.print("Error: Unknown provider '{s}'\n", .{provider_name});
        std.debug.print("Available: local, kernel, notte, browserbase, browserless\n", .{});
        return;
    };

    // Load and update config
    var config = session_ctx.loadConfig() orelse config_mod.Config{};
    defer config.deinit(allocator);

    // Update provider
    if (config.provider) |old| allocator.free(old);
    config.provider = allocator.dupe(u8, provider_name) catch null;

    // Clear any existing cloud session when changing providers
    if (config.provider_session_id) |old_sid| {
        allocator.free(old_sid);
        config.provider_session_id = null;
    }

    try session_ctx.saveConfig(config);

    std.debug.print("Provider set to: {s} ({s})\n", .{ provider.name, provider.display_name });

    if (provider.api_key_env_var.len > 0) {
        std.debug.print("API key environment variable: {s}\n", .{provider.api_key_env_var});
    }
}

fn showStatus(session_ctx: *const session_mod.SessionContext, environ_map: *std.process.Environ.Map) !void {
    const allocator = session_ctx.allocator;

    var config = session_ctx.loadConfig() orelse {
        std.debug.print("Session: {s}\n", .{session_ctx.name});
        std.debug.print("Provider: local (default)\n", .{});
        return;
    };
    defer config.deinit(allocator);

    std.debug.print("\nSession: {s}\n", .{session_ctx.name});
    std.debug.print("{s:-<40}\n", .{""});

    const provider_name = config.provider orelse "local";
    const provider = cdp.getProvider(provider_name);

    if (provider) |p| {
        std.debug.print("Provider: {s} ({s})\n", .{ p.name, p.display_name });

        if (p.api_key_env_var.len > 0) {
            const has_key = environ_map.get(p.api_key_env_var) != null;
            if (has_key) {
                std.debug.print("API Key: configured (via {s})\n", .{p.api_key_env_var});
            } else {
                std.debug.print("API Key: NOT SET - set {s}\n", .{p.api_key_env_var});
            }
        }

        std.debug.print("Auto-cleanup: {s}\n", .{@tagName(p.default_cleanup)});
    } else {
        std.debug.print("Provider: {s} (unknown)\n", .{provider_name});
    }

    if (config.provider_session_id) |sid| {
        std.debug.print("\nActive Session ID: {s}\n", .{sid});
    }

    if (config.ws_url) |url| {
        std.debug.print("WebSocket URL: {s}\n", .{url});
    }

    std.debug.print("\n", .{});
}

fn closeSession(session_ctx: *const session_mod.SessionContext, environ_map: *std.process.Environ.Map) !void {
    const allocator = session_ctx.allocator;

    var config = session_ctx.loadConfig() orelse {
        std.debug.print("No active session to close\n", .{});
        return;
    };
    defer config.deinit(allocator);

    const session_id = config.provider_session_id orelse {
        std.debug.print("No active cloud session to close\n", .{});
        return;
    };

    const provider_name = config.provider orelse "local";
    const provider = cdp.getProvider(provider_name) orelse {
        std.debug.print("Unknown provider: {s}\n", .{provider_name});
        return;
    };

    if (std.mem.eql(u8, provider_name, "local")) {
        std.debug.print("Local provider sessions are managed by the browser process\n", .{});
        std.debug.print("Use 'zchrome' commands to interact with the browser directly\n", .{});
        return;
    }

    const api_key = environ_map.get(provider.api_key_env_var) orelse {
        std.debug.print("Error: API key not set. Set {s}\n", .{provider.api_key_env_var});
        return;
    };

    std.debug.print("Closing session {s} on {s}...\n", .{ session_id, provider.display_name });

    var destroy_succeeded = true;

    // Use stop_url if available (some providers like Browserless return it)
    if (config.provider_stop_url) |stop_url| {
        // Try stop_url first, with provider.destroySession as fallback
        destroy_succeeded = cloud.deleteViaStopUrl(
            allocator,
            session_ctx.init,
            stop_url,
            provider,
            api_key,
            session_id,
        );
    } else {
        provider.destroySession(allocator, session_ctx.init, api_key, session_id) catch {
            destroy_succeeded = false;
        };
    }

    // Clear session from config regardless of API result (session may already be gone)
    cloud.clearSession(allocator, &config);

    try session_ctx.saveConfig(config);

    if (destroy_succeeded) {
        std.debug.print("Session closed successfully\n", .{});
    } else {
        std.debug.print("Session cleared from config (was not found on provider)\n", .{});
    }
}

fn printHelp() void {
    std.debug.print(
        \\Cloud Browser Provider Management
        \\
        \\Usage: zchrome provider [subcommand]
        \\
        \\Subcommands:
        \\  list              List available providers and their status
        \\  set <name>        Set the default provider for this session
        \\  status            Show current provider and session details
        \\  close             Close the active cloud browser session
        \\
        \\Providers:
        \\  local             Local Chrome (default)
        \\  kernel            Kernel.sh cloud browsers
        \\  notte             Notte.cc cloud browsers
        \\  browserbase       Browserbase cloud browsers
        \\  browserless       Browserless.io cloud browsers
        \\
        \\Examples:
        \\  zchrome provider set kernel
        \\  zchrome provider list
        \\  zchrome provider status
        \\  zchrome provider close
        \\
        \\Environment Variables:
        \\  ZCHROME_PROVIDER               Default provider
        \\  ZCHROME_KERNEL_API_KEY         Kernel.sh API key
        \\  ZCHROME_NOTTE_API_KEY          Notte.cc API key
        \\  ZCHROME_BROWSERBASE_API_KEY    Browserbase API key
        \\  ZCHROME_BROWSERLESS_API_KEY    Browserless.io API key
        \\  ZCHROME_BROWSERLESS_REGION     Browserless region (sfo|lon|ams)
        \\  ZCHROME_BROWSERLESS_STEALTH    Enable stealth mode (true|false)
        \\
    , .{});
}
