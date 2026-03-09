const std = @import("std");
const json = @import("json");

// ─── Provider Interface ─────────────────────────────────────────────────────

/// Information about an active browser session from a provider
pub const SessionInfo = struct {
    /// Provider-assigned session ID
    session_id: []const u8,
    /// CDP WebSocket URL for connecting to the browser
    cdp_ws_url: []const u8,
    /// Optional expiration timestamp (Unix seconds)
    expires_at: ?i64 = null,
    /// Optional live view URL for debugging
    live_view_url: ?[]const u8 = null,

    allocator: std.mem.Allocator,

    pub fn deinit(self: *SessionInfo) void {
        self.allocator.free(self.session_id);
        self.allocator.free(self.cdp_ws_url);
        if (self.live_view_url) |url| self.allocator.free(url);
    }
};

/// Options for creating a cloud browser session
pub const CreateOptions = struct {
    allocator: std.mem.Allocator,
    init: std.process.Init,
    /// API key for authentication
    api_key: []const u8,
    /// Session timeout in milliseconds
    timeout_ms: ?u32 = null,
    /// Proxy configuration
    proxy: ?ProxyConfig = null,
    /// Provider-specific extra options (passed as JSON)
    extra: ?json.Value = null,
};

pub const ProxyConfig = struct {
    host: []const u8,
    port: u16,
    username: ?[]const u8 = null,
    password: ?[]const u8 = null,
};

/// Session cleanup behavior
pub const AutoCleanup = enum {
    /// Delete session when zchrome command exits (default for per-session billing)
    on_exit,
    /// Keep session alive, require explicit close command
    manual,
    /// Provider handles cleanup after inactivity timeout
    timeout,
};

/// Provider error types
pub const ProviderError = error{
    /// API key is missing or invalid
    AuthenticationFailed,
    /// API request failed
    RequestFailed,
    /// Provider returned invalid response
    InvalidResponse,
    /// Session not found
    SessionNotFound,
    /// Rate limited
    RateLimited,
    /// Provider-specific error
    ProviderError,
    /// Network error
    ConnectionFailed,
    /// Timeout waiting for session
    Timeout,
    /// Out of memory
    OutOfMemory,
};

/// Provider interface - implemented by each cloud browser provider
pub const Provider = struct {
    /// Provider name (e.g., "kernel", "notte", "browserbase")
    name: []const u8,
    /// Human-readable display name
    display_name: []const u8,
    /// Environment variable name for API key
    api_key_env_var: []const u8,
    /// Default session cleanup behavior
    default_cleanup: AutoCleanup,

    /// Create a new browser session
    createSessionFn: *const fn (opts: CreateOptions) ProviderError!SessionInfo,
    /// Destroy/delete a browser session
    destroySessionFn: *const fn (allocator: std.mem.Allocator, init: std.process.Init, api_key: []const u8, session_id: []const u8) ProviderError!void,
    /// Get session info (optional, may return null if not supported)
    getSessionInfoFn: ?*const fn (allocator: std.mem.Allocator, init: std.process.Init, api_key: []const u8, session_id: []const u8) ProviderError!SessionInfo,

    pub fn createSession(self: *const Provider, opts: CreateOptions) ProviderError!SessionInfo {
        return self.createSessionFn(opts);
    }

    pub fn destroySession(self: *const Provider, allocator: std.mem.Allocator, init: std.process.Init, api_key: []const u8, session_id: []const u8) ProviderError!void {
        return self.destroySessionFn(allocator, init, api_key, session_id);
    }

    pub fn getSessionInfo(self: *const Provider, allocator: std.mem.Allocator, init: std.process.Init, api_key: []const u8, session_id: []const u8) ?SessionInfo {
        if (self.getSessionInfoFn) |func| {
            return func(allocator, init, api_key, session_id) catch null;
        }
        return null;
    }
};

// ─── Provider Registry ──────────────────────────────────────────────────────

/// Get provider by name
pub fn getProvider(name: []const u8) ?*const Provider {
    if (std.mem.eql(u8, name, "local")) return &local_provider;
    if (std.mem.eql(u8, name, "kernel")) return &kernel_provider;
    if (std.mem.eql(u8, name, "notte")) return &notte_provider;
    if (std.mem.eql(u8, name, "browserbase")) return &browserbase_provider;
    return null;
}

/// List all available providers
pub fn listProviders() []const *const Provider {
    return &[_]*const Provider{
        &local_provider,
        &kernel_provider,
        &notte_provider,
        &browserbase_provider,
    };
}

/// Get API key from environment variable for a provider
pub fn getApiKey(environ_map: *std.process.Environ.Map, provider: *const Provider) ?[]const u8 {
    return environ_map.get(provider.api_key_env_var);
}

// ─── Provider Implementations ───────────────────────────────────────────────

// Local provider (wraps existing Browser.launch/connect)
pub const local = @import("local.zig");
pub const local_provider = local.provider;

// Cloud providers
pub const kernel = @import("kernel.zig");
pub const kernel_provider = kernel.provider;

pub const notte = @import("notte.zig");
pub const notte_provider = notte.provider;

pub const browserbase = @import("browserbase.zig");
pub const browserbase_provider = browserbase.provider;

// ─── Tests ──────────────────────────────────────────────────────────────────

test "getProvider returns correct provider" {
    const kernel_p = getProvider("kernel");
    try std.testing.expect(kernel_p != null);
    try std.testing.expectEqualStrings("kernel", kernel_p.?.name);

    const unknown = getProvider("unknown");
    try std.testing.expect(unknown == null);
}

test "listProviders returns all providers" {
    const providers = listProviders();
    try std.testing.expect(providers.len == 4);
}
