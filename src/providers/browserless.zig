const std = @import("std");
const json = @import("json");
const mod = @import("mod.zig");
const rest = @import("../util/rest.zig");

const Provider = mod.Provider;
const SessionInfo = mod.SessionInfo;
const CreateOptions = mod.CreateOptions;
const ProviderError = mod.ProviderError;
const AutoCleanup = mod.AutoCleanup;

/// Regional endpoints for Browserless.io
const REGIONS = struct {
    const sfo = "production-sfo.browserless.io";
    const lon = "production-lon.browserless.io";
    const ams = "production-ams.browserless.io";
};

/// Default TTL in milliseconds (5 minutes)
const DEFAULT_TTL: i64 = 300000;

/// Browserless.io cloud browser provider
/// Documentation: https://docs.browserless.io/
pub const provider = Provider{
    .name = "browserless",
    .display_name = "Browserless.io",
    .api_key_env_var = "ZCHROME_BROWSERLESS_API_KEY",
    .default_cleanup = .timeout, // Browserless auto-cleans after TTL expires

    .createSessionFn = createSession,
    .destroySessionFn = destroySession,
    .getSessionInfoFn = null, // Browserless doesn't have per-session GET endpoint
};

/// Get the API base URL based on region environment variable
fn getApiBase(environ_map: *std.process.Environ.Map) []const u8 {
    const region = environ_map.get("ZCHROME_BROWSERLESS_REGION") orelse "sfo";

    if (std.mem.eql(u8, region, "lon")) {
        return REGIONS.lon;
    } else if (std.mem.eql(u8, region, "ams")) {
        return REGIONS.ams;
    }
    return REGIONS.sfo;
}

/// Check if stealth mode is enabled via environment variable
fn isStealthEnabled(environ_map: *std.process.Environ.Map) bool {
    const stealth = environ_map.get("ZCHROME_BROWSERLESS_STEALTH") orelse return false;
    return std.mem.eql(u8, stealth, "true") or std.mem.eql(u8, stealth, "1");
}

/// Create a new browser session on Browserless.io
/// POST https://{region}.browserless.io/session?token=API_KEY
fn createSession(opts: CreateOptions) ProviderError!SessionInfo {
    const allocator = opts.allocator;
    const api_base = getApiBase(opts.init.environ_map);

    // Build request body
    var body_obj = json.Value{ .object = .{} };
    defer body_obj.object.deinit(allocator);

    // ttl is required for Browserless
    const ttl: i64 = if (opts.timeout_ms) |timeout|
        @intCast(timeout)
    else
        DEFAULT_TTL;
    body_obj.object.put(allocator, "ttl", .{ .integer = ttl }) catch
        return ProviderError.OutOfMemory;

    // Enable processKeepAlive to persist browser state between connections
    // This keeps the browser process alive so subsequent connections can reuse it
    body_obj.object.put(allocator, "processKeepAlive", .{ .integer = @divFloor(ttl, 2) }) catch
        return ProviderError.OutOfMemory;

    // Check stealth mode from environment
    if (isStealthEnabled(opts.init.environ_map)) {
        body_obj.object.put(allocator, "stealth", .{ .bool = true }) catch
            return ProviderError.OutOfMemory;
    }

    // Add proxy if specified (using externalProxyServer format)
    if (opts.proxy) |proxy| {
        // Format: http(s)://[username:password@]host:port
        const proxy_url = if (proxy.username != null and proxy.password != null)
            std.fmt.allocPrint(allocator, "http://{s}:{s}@{s}:{}", .{
                proxy.username.?,
                proxy.password.?,
                proxy.host,
                proxy.port,
            }) catch return ProviderError.OutOfMemory
        else
            std.fmt.allocPrint(allocator, "http://{s}:{}", .{
                proxy.host,
                proxy.port,
            }) catch return ProviderError.OutOfMemory;
        defer allocator.free(proxy_url);

        body_obj.object.put(allocator, "externalProxyServer", .{ .string = proxy_url }) catch
            return ProviderError.OutOfMemory;
    }

    // Serialize body to JSON
    const body_json = json.stringify(allocator, body_obj, .{}) catch
        return ProviderError.OutOfMemory;
    defer allocator.free(body_json);

    // Build URL with token in query parameter (Browserless uses query param auth)
    const url = std.fmt.allocPrint(allocator, "https://{s}/session?token={s}", .{
        api_base,
        opts.api_key,
    }) catch return ProviderError.OutOfMemory;
    defer allocator.free(url);

    // Make API request (no bearer_token since auth is in URL)
    var response = rest.request(url, .{
        .allocator = allocator,
        .init = opts.init,
        .method = .POST,
        .body = body_json,
        .content_type = "application/json",
    }) catch |err| {
        return switch (err) {
            rest.RestError.TlsError => ProviderError.ConnectionFailed,
            rest.RestError.ConnectionFailed => ProviderError.ConnectionFailed,
            rest.RestError.InvalidResponse => ProviderError.InvalidResponse,
            else => ProviderError.RequestFailed,
        };
    };
    defer response.deinit();

    // Check response status
    if (response.status_code == 401 or response.status_code == 403) {
        return ProviderError.AuthenticationFailed;
    }
    if (response.status_code == 429) {
        return ProviderError.RateLimited;
    }
    if (response.status_code < 200 or response.status_code >= 300) {
        return ProviderError.RequestFailed;
    }

    // Parse response
    var parsed = response.parseJson(allocator) catch
        return ProviderError.InvalidResponse;
    defer parsed.deinit(allocator);

    // Browserless returns: { id, connect, ttl, stop, browserQL }
    const session_id = parsed.getString("id") catch
        return ProviderError.InvalidResponse;
    const cdp_ws_url = parsed.getString("connect") catch
        return ProviderError.InvalidResponse;

    // Get the stop URL for session deletion
    const stop_url: ?[]const u8 = if (parsed.get("stop")) |v|
        (if (v == .string) allocator.dupe(u8, v.string) catch null else null)
    else
        null;

    return SessionInfo{
        .session_id = allocator.dupe(u8, session_id) catch return ProviderError.OutOfMemory,
        .cdp_ws_url = allocator.dupe(u8, cdp_ws_url) catch return ProviderError.OutOfMemory,
        .live_view_url = null, // Browserless doesn't provide a live view URL in response
        .stop_url = stop_url,
        .expires_at = null,
        .allocator = allocator,
    };
}

/// Stop a browser session on Browserless.io
/// DELETE https://{region}.browserless.io/session/{id}?token=API_KEY
fn destroySession(allocator: std.mem.Allocator, init: std.process.Init, api_key: []const u8, session_id: []const u8) ProviderError!void {
    const api_base = getApiBase(init.environ_map);

    // Build URL with token in query parameter
    const url = std.fmt.allocPrint(allocator, "https://{s}/session/{s}?token={s}", .{
        api_base,
        session_id,
        api_key,
    }) catch return ProviderError.OutOfMemory;
    defer allocator.free(url);

    var response = rest.request(url, .{
        .allocator = allocator,
        .init = init,
        .method = .DELETE,
    }) catch |err| {
        return switch (err) {
            rest.RestError.TlsError => ProviderError.ConnectionFailed,
            rest.RestError.ConnectionFailed => ProviderError.ConnectionFailed,
            else => ProviderError.RequestFailed,
        };
    };
    defer response.deinit();

    if (response.status_code == 404) {
        return ProviderError.SessionNotFound;
    }
    if (response.status_code < 200 or response.status_code >= 300) {
        return ProviderError.RequestFailed;
    }
}
