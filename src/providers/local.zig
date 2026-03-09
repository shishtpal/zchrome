const std = @import("std");
const mod = @import("mod.zig");

const Provider = mod.Provider;
const SessionInfo = mod.SessionInfo;
const CreateOptions = mod.CreateOptions;
const ProviderError = mod.ProviderError;
const AutoCleanup = mod.AutoCleanup;

/// Local browser provider - wraps existing Browser.launch/connect functionality
/// This provider doesn't actually create sessions via API - it's a passthrough
/// that signals the CLI to use local Chrome launching
pub const provider = Provider{
    .name = "local",
    .display_name = "Local Chrome",
    .api_key_env_var = "", // No API key needed
    .default_cleanup = .on_exit,

    .createSessionFn = createSession,
    .destroySessionFn = destroySession,
    .getSessionInfoFn = null, // Not supported for local
};

/// For local provider, we return a special marker that tells the CLI
/// to use the traditional Browser.launch() flow
fn createSession(opts: CreateOptions) ProviderError!SessionInfo {
    // Local provider doesn't create sessions via API
    // Return a marker session that the CLI interprets specially
    return SessionInfo{
        .session_id = opts.allocator.dupe(u8, "local") catch return ProviderError.OutOfMemory,
        .cdp_ws_url = opts.allocator.dupe(u8, "") catch return ProviderError.OutOfMemory,
        .expires_at = null,
        .live_view_url = null,
        .allocator = opts.allocator,
    };
}

fn destroySession(allocator: std.mem.Allocator, init: std.process.Init, api_key: []const u8, session_id: []const u8) ProviderError!void {
    // Local sessions are managed by Browser.close(), nothing to do here
    _ = allocator;
    _ = init;
    _ = api_key;
    _ = session_id;
}
