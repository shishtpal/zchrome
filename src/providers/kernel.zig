const std = @import("std");
const json = @import("json");
const mod = @import("mod.zig");
const rest = @import("../util/rest.zig");

const Provider = mod.Provider;
const SessionInfo = mod.SessionInfo;
const CreateOptions = mod.CreateOptions;
const ProviderError = mod.ProviderError;
const AutoCleanup = mod.AutoCleanup;

/// Kernel.sh API base URL
const API_BASE = "api.onkernel.com";
const API_PORT: u16 = 443;

/// Kernel.sh cloud browser provider
/// Documentation: https://www.kernel.sh/docs/browsers/create-a-browser
pub const provider = Provider{
    .name = "kernel",
    .display_name = "Kernel.sh",
    .api_key_env_var = "ZCHROME_KERNEL_API_KEY",
    .default_cleanup = .timeout, // Kernel auto-deletes after 60s inactivity

    .createSessionFn = createSession,
    .destroySessionFn = destroySession,
    .getSessionInfoFn = getSessionInfo,
};

/// Create a new browser session on Kernel.sh
/// POST https://api.onkernel.com/browsers
fn createSession(opts: CreateOptions) ProviderError!SessionInfo {
    const allocator = opts.allocator;

    // Build request body
    // Note: Only free the hashmap storage, not the keys (which are string literals)
    var body_obj = json.Value{ .object = .{} };
    defer body_obj.object.deinit(allocator);

    // Add timeout if specified
    if (opts.timeout_ms) |timeout| {
        const timeout_secs = @divFloor(timeout, 1000);
        body_obj.object.put(allocator, "timeout", .{ .integer = @intCast(timeout_secs) }) catch
            return ProviderError.OutOfMemory;
    }

    // Add proxy if specified
    if (opts.proxy) |proxy| {
        var proxy_obj = json.Value{ .object = .{} };
        proxy_obj.object.put(allocator, "host", .{ .string = proxy.host }) catch
            return ProviderError.OutOfMemory;
        proxy_obj.object.put(allocator, "port", .{ .integer = proxy.port }) catch
            return ProviderError.OutOfMemory;
        if (proxy.username) |u| {
            proxy_obj.object.put(allocator, "username", .{ .string = u }) catch
                return ProviderError.OutOfMemory;
        }
        if (proxy.password) |p| {
            proxy_obj.object.put(allocator, "password", .{ .string = p }) catch
                return ProviderError.OutOfMemory;
        }
        body_obj.object.put(allocator, "proxy", proxy_obj) catch
            return ProviderError.OutOfMemory;
    }

    // Serialize body to JSON
    const body_json = json.stringify(allocator, body_obj, .{}) catch
        return ProviderError.OutOfMemory;
    defer allocator.free(body_json);

    // Make API request
    const url = "https://" ++ API_BASE ++ "/browsers";
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

    // Extract fields
    const session_id = parsed.getString("session_id") catch
        return ProviderError.InvalidResponse;
    const cdp_ws_url = parsed.getString("cdp_ws_url") catch
        return ProviderError.InvalidResponse;

    // Optional fields
    const live_view_url: ?[]const u8 = if (parsed.get("live_view_url")) |v|
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

/// Delete a browser session on Kernel.sh
/// DELETE https://api.onkernel.com/browsers/{id}
fn destroySession(allocator: std.mem.Allocator, init: std.process.Init, api_key: []const u8, session_id: []const u8) ProviderError!void {
    const url = std.fmt.allocPrint(allocator, "https://{s}/browsers/{s}", .{ API_BASE, session_id }) catch
        return ProviderError.OutOfMemory;
    defer allocator.free(url);

    var response = rest.request(url, .{
        .allocator = allocator,
        .init = init,
        .method = .DELETE,
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
}

/// Get session info from Kernel.sh
/// GET https://api.onkernel.com/browsers/{id}
fn getSessionInfo(allocator: std.mem.Allocator, init: std.process.Init, api_key: []const u8, session_id: []const u8) ProviderError!SessionInfo {
    const url = std.fmt.allocPrint(allocator, "https://{s}/browsers/{s}", .{ API_BASE, session_id }) catch
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

    const cdp_ws_url = parsed.getString("cdp_ws_url") catch
        return ProviderError.InvalidResponse;

    const live_view_url: ?[]const u8 = if (parsed.get("live_view_url")) |v|
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
