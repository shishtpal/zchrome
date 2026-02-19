const std = @import("std");

/// Parsed WebSocket URL components
pub const WsUrl = struct {
    host: []const u8,
    port: u16,
    path: []const u8,
    is_secure: bool, // wss:// vs ws://

    /// Free all allocated fields
    pub fn deinit(self: *WsUrl, allocator: std.mem.Allocator) void {
        allocator.free(self.host);
        allocator.free(self.path);
    }
};

/// Parse a WebSocket URL into its components
/// Supports: ws://host:port/path and wss://host:port/path
pub fn parseWsUrl(allocator: std.mem.Allocator, url: []const u8) !WsUrl {
    var remaining = url;

    // Parse scheme
    var is_secure: bool = false;
    if (std.mem.startsWith(u8, remaining, "wss://")) {
        is_secure = true;
        remaining = remaining["wss://".len..];
    } else if (std.mem.startsWith(u8, remaining, "ws://")) {
        is_secure = false;
        remaining = remaining["ws://".len..];
    } else {
        return error.InvalidScheme;
    }

    // Find path separator
    const path_start = std.mem.indexOfScalar(u8, remaining, '/') orelse remaining.len;

    // Parse host:port
    const host_port = remaining[0..path_start];

    // Find port separator
    const port_start = std.mem.lastIndexOfScalar(u8, host_port, ':');

    var host: []const u8 = undefined;
    var port: u16 = undefined;

    if (port_start) |ps| {
        host = host_port[0..ps];
        const port_str = host_port[ps + 1 ..];
        port = std.fmt.parseInt(u16, port_str, 10) catch return error.InvalidPort;
    } else {
        host = host_port;
        port = if (is_secure) 443 else 80;
    }

    var path: []const u8 = undefined;
    if (path_start < remaining.len) {
        path = try allocator.dupe(u8, remaining[path_start..]);
    } else {
        path = try allocator.dupe(u8, "/");
    }

    return .{
        .host = try allocator.dupe(u8, host),
        .port = port,
        .path = path,
        .is_secure = is_secure,
    };
}

/// Build an HTTP URL from components
pub fn buildHttpUrl(allocator: std.mem.Allocator, host: []const u8, port: u16, path: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "http://{s}:{}{s}", .{ host, port, path });
}

// ─── Tests ──────────────────────────────────────────────────────────────────

test "parseWsUrl - ws:// with port and path" {
    const result = try parseWsUrl(std.testing.allocator, "ws://127.0.0.1:9222/devtools/browser/abc123");
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("127.0.0.1", result.host);
    try std.testing.expectEqual(@as(u16, 9222), result.port);
    try std.testing.expectEqualStrings("/devtools/browser/abc123", result.path);
    try std.testing.expect(!result.is_secure);
}

test "parseWsUrl - wss:// secure" {
    const result = try parseWsUrl(std.testing.allocator, "wss://example.com:443/path");
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("example.com", result.host);
    try std.testing.expectEqual(@as(u16, 443), result.port);
    try std.testing.expect(result.is_secure);
}

test "parseWsUrl - default port ws" {
    const result = try parseWsUrl(std.testing.allocator, "ws://localhost/path");
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("localhost", result.host);
    try std.testing.expectEqual(@as(u16, 80), result.port);
    try std.testing.expect(!result.is_secure);
}

test "parseWsUrl - default port wss" {
    const result = try parseWsUrl(std.testing.allocator, "wss://localhost/path");
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("localhost", result.host);
    try std.testing.expectEqual(@as(u16, 443), result.port);
    try std.testing.expect(result.is_secure);
}

test "parseWsUrl - no path" {
    const result = try parseWsUrl(std.testing.allocator, "ws://localhost:9222");
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("localhost", result.host);
    try std.testing.expectEqual(@as(u16, 9222), result.port);
    try std.testing.expectEqualStrings("/", result.path);
}

test "parseWsUrl - invalid scheme" {
    const result = parseWsUrl(std.testing.allocator, "http://localhost");
    try std.testing.expectError(error.InvalidScheme, result);
}

test "buildHttpUrl" {
    const result = try buildHttpUrl(std.testing.allocator, "127.0.0.1", 9222, "/json/version");
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("http://127.0.0.1:9222/json/version", result);
}
