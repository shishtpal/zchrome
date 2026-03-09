const std = @import("std");
const json = @import("json");
const mod = @import("mod.zig");
const rest = @import("../util/rest.zig");

const Provider = mod.Provider;
const SessionInfo = mod.SessionInfo;
const CreateOptions = mod.CreateOptions;
const ProviderError = mod.ProviderError;
const AutoCleanup = mod.AutoCleanup;

/// Notte.cc API base URL
const API_BASE = "api.notte.cc";
const API_PORT: u16 = 443;

/// Notte.cc cloud browser provider
/// Documentation: https://docs.notte.cc/
pub const provider = Provider{
    .name = "notte",
    .display_name = "Notte.cc",
    .api_key_env_var = "ZCHROME_NOTTE_API_KEY",
    .default_cleanup = .on_exit, // Notte bills per session, cleanup on exit

    .createSessionFn = createSession,
    .destroySessionFn = destroySession,
    .getSessionInfoFn = getSessionInfo,
};

/// Create a new browser session on Notte.cc
/// POST https://api.notte.cc/v1/sessions
fn createSession(opts: CreateOptions) ProviderError!SessionInfo {
    const allocator = opts.allocator;

    // Build request body
    // Note: Only free the hashmap storage, not the keys (which are string literals)
    var body_obj = json.Value{ .object = .{} };
    defer body_obj.object.deinit(allocator);

    // Add idle timeout if specified (Notte uses minutes)
    if (opts.timeout_ms) |timeout| {
        const timeout_mins = @divFloor(timeout, 60_000);
        body_obj.object.put(allocator, "idle_timeout_minutes", .{ .integer = @intCast(if (timeout_mins > 0) timeout_mins else 1) }) catch
            return ProviderError.OutOfMemory;
    }

    // Add proxy if specified
    if (opts.proxy) |proxy| {
        const proxy_url = std.fmt.allocPrint(allocator, "{s}:{}", .{ proxy.host, proxy.port }) catch
            return ProviderError.OutOfMemory;
        defer allocator.free(proxy_url);
        body_obj.object.put(allocator, "proxy", .{ .string = proxy_url }) catch
            return ProviderError.OutOfMemory;
    }

    // Serialize body to JSON
    const body_json = json.stringify(allocator, body_obj, .{}) catch
        return ProviderError.OutOfMemory;
    defer allocator.free(body_json);

    // Make API request
    const url = "https://" ++ API_BASE ++ "/v1/sessions";
    var response = rest.request(url, .{
        .allocator = allocator,
        .init = opts.init,
        .method = .POST,
        .body = body_json,
        .bearer_token = opts.api_key,
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

    // Notte returns: { id, cdp_url, live_url, ... }
    const session_id = parsed.getString("id") catch
        return ProviderError.InvalidResponse;
    const cdp_ws_url = parsed.getString("cdp_url") catch
        return ProviderError.InvalidResponse;

    // Optional fields
    const live_view_url: ?[]const u8 = if (parsed.get("live_url")) |v|
        (if (v == .string) allocator.dupe(u8, v.string) catch null else null)
    else
        null;

    return SessionInfo{
        .session_id = allocator.dupe(u8, session_id) catch return ProviderError.OutOfMemory,
        .cdp_ws_url = allocator.dupe(u8, cdp_ws_url) catch return ProviderError.OutOfMemory,
        .live_view_url = live_view_url,
        .expires_at = null,
        .allocator = allocator,
    };
}

/// Stop a browser session on Notte.cc
/// POST https://api.notte.cc/v1/sessions/{id}/stop
fn destroySession(allocator: std.mem.Allocator, init: std.process.Init, api_key: []const u8, session_id: []const u8) ProviderError!void {
    const url = std.fmt.allocPrint(allocator, "https://{s}/v1/sessions/{s}/stop", .{ API_BASE, session_id }) catch
        return ProviderError.OutOfMemory;
    defer allocator.free(url);

    var response = rest.request(url, .{
        .allocator = allocator,
        .init = init,
        .method = .POST,
        .bearer_token = api_key,
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
    // Notte returns 200 on success
    if (response.status_code < 200 or response.status_code >= 300) {
        return ProviderError.RequestFailed;
    }
}

/// Get session info from Notte.cc
/// GET https://api.notte.cc/v1/sessions/{id}
fn getSessionInfo(allocator: std.mem.Allocator, init: std.process.Init, api_key: []const u8, session_id: []const u8) ProviderError!SessionInfo {
    const url = std.fmt.allocPrint(allocator, "https://{s}/v1/sessions/{s}", .{ API_BASE, session_id }) catch
        return ProviderError.OutOfMemory;
    defer allocator.free(url);

    var response = rest.request(url, .{
        .allocator = allocator,
        .init = init,
        .method = .GET,
        .bearer_token = api_key,
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

    var parsed = response.parseJson(allocator) catch
        return ProviderError.InvalidResponse;
    defer parsed.deinit(allocator);

    const cdp_ws_url = parsed.getString("cdp_url") catch
        return ProviderError.InvalidResponse;

    const live_view_url: ?[]const u8 = if (parsed.get("live_url")) |v|
        (if (v == .string) allocator.dupe(u8, v.string) catch null else null)
    else
        null;

    return SessionInfo{
        .session_id = allocator.dupe(u8, session_id) catch return ProviderError.OutOfMemory,
        .cdp_ws_url = allocator.dupe(u8, cdp_ws_url) catch return ProviderError.OutOfMemory,
        .live_view_url = live_view_url,
        .expires_at = null,
        .allocator = allocator,
    };
}
