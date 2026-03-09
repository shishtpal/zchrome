const std = @import("std");
const json = @import("json");
const mod = @import("mod.zig");
const rest = @import("../util/rest.zig");

const Provider = mod.Provider;
const SessionInfo = mod.SessionInfo;
const CreateOptions = mod.CreateOptions;
const ProviderError = mod.ProviderError;
const AutoCleanup = mod.AutoCleanup;

/// Browserbase API base URL
const API_BASE = "api.browserbase.com";
const CONNECT_BASE = "connect.browserbase.com";
const API_PORT: u16 = 443;

/// Browserbase cloud browser provider
/// Documentation: https://docs.browserbase.com/
pub const provider = Provider{
    .name = "browserbase",
    .display_name = "Browserbase",
    .api_key_env_var = "ZCHROME_BROWSERBASE_API_KEY",
    .default_cleanup = .on_exit, // Browserbase bills per session

    .createSessionFn = createSession,
    .destroySessionFn = destroySession,
    .getSessionInfoFn = getSessionInfo,
};

/// Create a new browser session on Browserbase
/// POST https://api.browserbase.com/v1/sessions
fn createSession(opts: CreateOptions) ProviderError!SessionInfo {
    const allocator = opts.allocator;

    // Build request body
    // Note: Only free the hashmap storage, not the keys (which are string literals)
    var body_obj = json.Value{ .object = .{} };
    defer body_obj.object.deinit(allocator);

    // Browserbase requires a projectId (from API key or explicit)
    // The API key typically encodes the project

    // Add browser settings
    var browser_settings = json.Value{ .object = .{} };

    // Add proxy if specified
    if (opts.proxy) |proxy| {
        var proxy_obj = json.Value{ .object = .{} };
        proxy_obj.object.put(allocator, "type", .{ .string = "custom" }) catch
            return ProviderError.OutOfMemory;

        const proxy_server = std.fmt.allocPrint(allocator, "{s}:{}", .{ proxy.host, proxy.port }) catch
            return ProviderError.OutOfMemory;
        defer allocator.free(proxy_server);

        proxy_obj.object.put(allocator, "server", .{ .string = proxy_server }) catch
            return ProviderError.OutOfMemory;

        if (proxy.username) |u| {
            proxy_obj.object.put(allocator, "username", .{ .string = u }) catch
                return ProviderError.OutOfMemory;
        }
        if (proxy.password) |p| {
            proxy_obj.object.put(allocator, "password", .{ .string = p }) catch
                return ProviderError.OutOfMemory;
        }

        browser_settings.object.put(allocator, "proxy", proxy_obj) catch
            return ProviderError.OutOfMemory;
    }

    // Add keep alive setting based on timeout
    if (opts.timeout_ms) |timeout| {
        if (timeout > 300_000) { // > 5 minutes
            body_obj.object.put(allocator, "keepAlive", .{ .bool = true }) catch
                return ProviderError.OutOfMemory;
        }
    }

    if (browser_settings.object.count() > 0) {
        body_obj.object.put(allocator, "browserSettings", browser_settings) catch
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

    // Browserbase returns: { id, status, ... }
    // The CDP URL is constructed: wss://connect.browserbase.com?sessionId={id}&apiKey={key}
    const session_id = parsed.getString("id") catch
        return ProviderError.InvalidResponse;

    // Build CDP WebSocket URL
    const cdp_ws_url = std.fmt.allocPrint(allocator, "wss://{s}?sessionId={s}", .{
        CONNECT_BASE,
        session_id,
    }) catch return ProviderError.OutOfMemory;

    // Live view URL
    const live_view_url = std.fmt.allocPrint(allocator, "https://www.browserbase.com/sessions/{s}", .{
        session_id,
    }) catch null;

    return SessionInfo{
        .session_id = allocator.dupe(u8, session_id) catch return ProviderError.OutOfMemory,
        .cdp_ws_url = cdp_ws_url,
        .live_view_url = live_view_url,
        .expires_at = null,
        .allocator = allocator,
    };
}

/// Stop a browser session on Browserbase
/// POST https://api.browserbase.com/v1/sessions/{id}/stop (or just let it timeout)
fn destroySession(allocator: std.mem.Allocator, init: std.process.Init, api_key: []const u8, session_id: []const u8) ProviderError!void {
    // Browserbase uses PATCH to update session status to "REQUEST_RELEASE"
    const url = std.fmt.allocPrint(allocator, "https://{s}/v1/sessions/{s}", .{ API_BASE, session_id }) catch
        return ProviderError.OutOfMemory;
    defer allocator.free(url);

    const body = "{\"status\":\"REQUEST_RELEASE\"}";

    var response = rest.request(url, .{
        .allocator = allocator,
        .init = init,
        .method = .PATCH,
        .body = body,
        .bearer_token = api_key,
        .content_type = "application/json",
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

/// Get session info from Browserbase
/// GET https://api.browserbase.com/v1/sessions/{id}
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

    // Rebuild CDP URL
    const cdp_ws_url = std.fmt.allocPrint(allocator, "wss://{s}?sessionId={s}", .{
        CONNECT_BASE,
        session_id,
    }) catch return ProviderError.OutOfMemory;

    const live_view_url = std.fmt.allocPrint(allocator, "https://www.browserbase.com/sessions/{s}", .{
        session_id,
    }) catch null;

    return SessionInfo{
        .session_id = allocator.dupe(u8, session_id) catch return ProviderError.OutOfMemory,
        .cdp_ws_url = cdp_ws_url,
        .live_view_url = live_view_url,
        .expires_at = null,
        .allocator = allocator,
    };
}
