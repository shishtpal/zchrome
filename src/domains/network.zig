const std = @import("std");
const Session = @import("../core/session.zig").Session;
const json_util = @import("../util/json.zig");

/// Network domain client
pub const Network = struct {
    session: *Session,

    const Self = @This();

    pub fn init(session: *Session) Self {
        return .{ .session = session };
    }

    /// Enable network domain
    pub fn enable(self: *Self) !void {
        _ = try self.session.sendCommand("Network.enable", .{});
    }

    /// Disable network domain
    pub fn disable(self: *Self) !void {
        _ = try self.session.sendCommand("Network.disable", .{});
    }

    /// Get response body
    pub fn getResponseBody(self: *Self, allocator: std.mem.Allocator, request_id: []const u8) !ResponseBody {
        const result = try self.session.sendCommand("Network.getResponseBody", .{
            .request_id = request_id,
        });

        return .{
            .body = try allocator.dupe(u8, try json_util.getString(result, "body")),
            .base64_encoded = try json_util.getBool(result, "base64Encoded"),
        };
    }

    /// Set request interception
    pub fn setRequestInterception(self: *Self, patterns: []const RequestPattern) !void {
        _ = try self.session.sendCommand("Network.setRequestInterception", .{
            .patterns = patterns,
        });
    }

    /// Set cache disabled
    pub fn setCacheDisabled(self: *Self, disabled: bool) !void {
        _ = try self.session.sendCommand("Network.setCacheDisabled", .{
            .cache_disabled = disabled,
        });
    }

    /// Clear browser cache
    pub fn clearBrowserCache(self: *Self) !void {
        _ = try self.session.sendCommand("Network.clearBrowserCache", .{});
    }

    /// Clear browser cookies
    pub fn clearBrowserCookies(self: *Self) !void {
        _ = try self.session.sendCommand("Network.clearBrowserCookies", .{});
    }

    /// Set extra HTTP headers
    pub fn setExtraHTTPHeaders(self: *Self, headers: std.json.Value) !void {
        _ = try self.session.sendCommand("Network.setExtraHTTPHeaders", .{
            .headers = headers,
        });
    }

    /// Emulate network conditions
    pub fn emulateNetworkConditions(
        self: *Self,
        offline: bool,
        latency: f64,
        download_throughput: f64,
        upload_throughput: f64,
    ) !void {
        _ = try self.session.sendCommand("Network.emulateNetworkConditions", .{
            .offline = offline,
            .latency = latency,
            .download_throughput = download_throughput,
            .upload_throughput = upload_throughput,
        });
    }
};

/// Response body
pub const ResponseBody = struct {
    body: []const u8,
    base64_encoded: bool,

    pub fn deinit(self: *ResponseBody, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
    }
};

/// Request pattern for interception
pub const RequestPattern = struct {
    url_pattern: ?[]const u8 = null,
    resource_type: ?[]const u8 = null,
    interception_stage: ?[]const u8 = null,
};

/// Request information
pub const Request = struct {
    url: []const u8,
    method: []const u8,
    headers: std.json.Value,
    post_data: ?[]const u8 = null,
};

/// Network response
pub const NetworkResponse = struct {
    url: []const u8,
    status: i64,
    status_text: []const u8,
    headers: std.json.Value,
    mime_type: []const u8,
};

// Event types
pub const RequestWillBeSent = struct {
    request_id: []const u8,
    loader_id: []const u8,
    document_url: []const u8,
    request: Request,
    timestamp: f64,
    type: ?[]const u8 = null,
};

pub const ResponseReceived = struct {
    request_id: []const u8,
    response: NetworkResponse,
    timestamp: f64,
    type: ?[]const u8 = null,
};

pub const LoadingFinished = struct {
    request_id: []const u8,
    timestamp: f64,
    encoded_data_length: f64,
};

pub const LoadingFailed = struct {
    request_id: []const u8,
    timestamp: f64,
    error_text: []const u8,
    canceled: ?bool = null,
};
