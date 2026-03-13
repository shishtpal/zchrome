const std = @import("std");
const cdp = @import("cdp");
const config_mod = @import("config.zig");
const session_mod = @import("session.zig");

const Config = config_mod.Config;

pub const CloudContext = struct {
    allocator: std.mem.Allocator,
    init: std.process.Init,
    session_ctx: *session_mod.SessionContext,
    config: *Config,
    provider: *const cdp.Provider,
    api_key: []const u8,
    verbose: bool = false,
    timeout_ms: u32 = 30000,
    stop_url: ?[]const u8 = null, // Direct URL for session deletion (provider-specific)
};

/// Create a new cloud browser session
pub fn cloudOpen(ctx: CloudContext) !void {
    const allocator = ctx.allocator;
    const config = ctx.config;
    const provider = ctx.provider;

    // Check if we already have a session
    if (config.provider_session_id != null and config.ws_url != null) {
        std.debug.print("Cloud session already exists on {s}\n", .{provider.display_name});
        std.debug.print("Session ID: {s}\n", .{config.provider_session_id.?});
        std.debug.print("WebSocket URL: {s}\n", .{config.ws_url.?});
        std.debug.print("\nTo create a new session, first close the existing one:\n", .{});
        std.debug.print("  zchrome provider close\n", .{});
        return;
    }

    std.debug.print("Creating cloud browser session on {s}...\n", .{provider.display_name});

    var session_info = provider.createSession(.{
        .allocator = allocator,
        .init = ctx.init,
        .api_key = ctx.api_key,
        .timeout_ms = ctx.timeout_ms,
    }) catch |err| {
        std.debug.print("Error creating cloud session: {}\n", .{err});
        std.process.exit(1);
    };
    defer session_info.deinit();

    // Print session info
    std.debug.print("Cloud browser session created!\n", .{});
    std.debug.print("Session ID: {s}\n", .{session_info.session_id});
    std.debug.print("WebSocket URL: {s}\n", .{session_info.cdp_ws_url});
    if (session_info.live_view_url) |lv| {
        std.debug.print("Live view: {s}\n", .{lv});
    }
    if (session_info.stop_url) |stop| {
        if (ctx.verbose) {
            std.debug.print("Stop URL: {s}\n", .{stop});
        }
    }

    // Save to config
    if (config.provider_session_id) |old| allocator.free(old);
    config.provider_session_id = allocator.dupe(u8, session_info.session_id) catch |err| blk: {
        std.debug.print("Warning: Failed to save session_id: {}\n", .{err});
        break :blk null;
    };
    if (config.ws_url) |old| allocator.free(old);
    config.ws_url = allocator.dupe(u8, session_info.cdp_ws_url) catch |err| blk: {
        std.debug.print("Warning: Failed to save ws_url: {}\n", .{err});
        break :blk null;
    };

    // Save stop URL if provided (used for session deletion)
    if (config.provider_stop_url) |old| allocator.free(old);
    config.provider_stop_url = if (session_info.stop_url) |stop|
        allocator.dupe(u8, stop) catch null
    else
        null;

    // Clear any stale target from previous sessions
    if (config.last_target) |old| allocator.free(old);
    config.last_target = null;

    if (ctx.verbose) {
        std.debug.print("Saving config with session_id={s}, ws_url={s}\n", .{
            config.provider_session_id orelse "(null)",
            if (config.ws_url) |u| u[0..@min(50, u.len)] else "(null)",
        });
    }

    ctx.session_ctx.saveConfig(config.*) catch |err| {
        std.debug.print("Warning: Failed to save config: {}\n", .{err});
    };
}

/// Connect to an existing cloud browser session
pub fn cloudConnect(ctx: CloudContext) !void {
    const allocator = ctx.allocator;
    const config = ctx.config;
    const provider = ctx.provider;

    // Check if we have an existing session
    if (config.provider_session_id == null) {
        std.debug.print("No cloud session found.\n", .{});
        std.debug.print("Run 'zchrome open' to create a cloud browser session.\n", .{});
        std.process.exit(1);
    }

    const session_id = config.provider_session_id.?;

    // Verify session is still alive
    if (provider.getSessionInfo(allocator, ctx.init, ctx.api_key, session_id)) |info| {
        std.debug.print("Connected to cloud session on {s}\n", .{provider.display_name});
        std.debug.print("Session ID: {s}\n", .{info.session_id});
        std.debug.print("WebSocket URL: {s}\n", .{info.cdp_ws_url});
        if (info.live_view_url) |lv| {
            std.debug.print("Live view: {s}\n", .{lv});
        }

        // Update ws_url in config (might have changed)
        if (config.ws_url) |old| allocator.free(old);
        config.ws_url = allocator.dupe(u8, info.cdp_ws_url) catch null;
        ctx.session_ctx.saveConfig(config.*) catch {};

        var info_mut = info;
        info_mut.deinit();
    } else {
        std.debug.print("Session expired or invalid.\n", .{});
        std.debug.print("Run 'zchrome open' to create a new cloud browser session.\n", .{});
        // Clear stale session from config
        clearSession(allocator, config);
        ctx.session_ctx.saveConfig(config.*) catch {};
        std.process.exit(1);
    }
}

/// Cleanup cloud session (called when --cleanup flag is set)
pub fn cloudCleanup(ctx: CloudContext) void {
    const allocator = ctx.allocator;
    const config = ctx.config;
    const provider = ctx.provider;

    const session_id = config.provider_session_id orelse return;

    if (ctx.verbose) {
        std.debug.print("Cleaning up cloud session: {s}\n", .{session_id});
    }

    // Use stop_url if provided (some providers like Browserless return it)
    if (ctx.stop_url) |stop_url| {
        if (ctx.verbose) {
            std.debug.print("Using stop URL: {s}\n", .{stop_url});
        }
        // Try stop_url first, with provider.destroySession as fallback
        if (!deleteViaStopUrl(allocator, ctx.init, stop_url, provider, ctx.api_key, session_id)) {
            std.debug.print("Warning: Failed to cleanup session via stop URL\n", .{});
        }
    } else {
        provider.destroySession(allocator, ctx.init, ctx.api_key, session_id) catch |err| {
            std.debug.print("Warning: Failed to cleanup session: {}\n", .{err});
        };
    }

    // Clear session from config
    clearSession(allocator, config);
    ctx.session_ctx.saveConfig(config.*) catch {};
}

/// Check that cloud session exists, exit with error if not
pub fn requireCloudSession(provider_name: []const u8, ws_url: ?[]const u8) void {
    if (ws_url == null) {
        std.debug.print("No cloud session found.\n", .{});
        std.debug.print("Run 'zchrome open' to create a cloud browser session first.\n", .{});
        std.debug.print("Provider: {s}\n", .{provider_name});
        std.process.exit(1);
    }
}

/// Get provider and API key, exit with error if not configured
pub fn getProviderOrExit(
    effective_provider: []const u8,
    environ_map: *std.process.Environ.Map,
) struct { provider: *const cdp.Provider, api_key: []const u8 } {
    const provider = cdp.getProvider(effective_provider) orelse {
        std.debug.print("Error: Unknown provider '{s}'\n", .{effective_provider});
        std.process.exit(1);
    };

    const api_key = environ_map.get(provider.api_key_env_var) orelse {
        std.debug.print("Error: API key not set. Set {s}\n", .{provider.api_key_env_var});
        std.process.exit(1);
    };

    return .{ .provider = provider, .api_key = api_key };
}

/// Print cloud-specific connection error
pub fn printCloudConnectionError(err: anyerror) void {
    std.debug.print("Failed to connect to cloud session: {}\n", .{err});
    std.debug.print("Session may have expired. Run 'zchrome open' to create a new session.\n", .{});
}

/// Clear session info from config (public for use by provider.zig)
pub fn clearSession(allocator: std.mem.Allocator, config: *Config) void {
    if (config.provider_session_id) |old| allocator.free(old);
    config.provider_session_id = null;
    if (config.ws_url) |old| allocator.free(old);
    config.ws_url = null;
    if (config.provider_stop_url) |old| allocator.free(old);
    config.provider_stop_url = null;
    if (config.last_target) |old| allocator.free(old);
    config.last_target = null;
}

/// Attempt to delete session via stop_url. Returns true on success, false on failure.
/// If stop_url deletion fails and fallback params are provided, attempts destroySession as fallback.
pub fn deleteViaStopUrl(
    allocator: std.mem.Allocator,
    init: std.process.Init,
    stop_url: []const u8,
    fallback_provider: ?*const cdp.Provider,
    fallback_api_key: ?[]const u8,
    fallback_session_id: ?[]const u8,
) bool {
    const rest = cdp.rest;
    var response = rest.request(stop_url, .{
        .allocator = allocator,
        .init = init,
        .method = .DELETE,
    }) catch {
        // Try fallback if provided
        if (fallback_provider) |provider| {
            if (fallback_api_key) |api_key| {
                if (fallback_session_id) |session_id| {
                    provider.destroySession(allocator, init, api_key, session_id) catch {};
                }
            }
        }
        return false;
    };
    response.deinit();
    return true;
}
