const std = @import("std");
const Session = @import("../core/session.zig").Session;
const json_util = @import("../util/json.zig");

/// Fetch domain client (for request interception)
pub const Fetch = struct {
    session: *Session,

    const Self = @This();

    pub fn init(session: *Session) Self {
        return .{ .session = session };
    }

    /// Enable fetch domain
    pub fn enable(self: *Self, patterns: ?[]const RequestPattern, handle_auth_requests: ?bool) !void {
        _ = try self.session.sendCommand("Fetch.enable", .{
            .patterns = patterns,
            .handle_auth_requests = handle_auth_requests,
        });
    }

    /// Disable fetch domain
    pub fn disable(self: *Self) !void {
        _ = try self.session.sendCommand("Fetch.disable", .{});
    }

    /// Fulfill a request
    pub fn fulfillRequest(self: *Self, params: FulfillParams) !void {
        _ = try self.session.sendCommand("Fetch.fulfillRequest", params);
    }

    /// Fail a request
    pub fn failRequest(self: *Self, request_id: []const u8, reason: []const u8) !void {
        _ = try self.session.sendCommand("Fetch.failRequest", .{
            .request_id = request_id,
            .error_reason = reason,
        });
    }

    /// Continue a request
    pub fn continueRequest(self: *Self, params: ContinueParams) !void {
        _ = try self.session.sendCommand("Fetch.continueRequest", params);
    }

    /// Continue with auth
    pub fn continueWithAuth(self: *Self, request_id: []const u8, response: AuthResponse) !void {
        _ = try self.session.sendCommand("Fetch.continueWithAuth", .{
            .request_id = request_id,
            .auth_challenge_response = response,
        });
    }

    /// Get response body
    pub fn getResponseBody(self: *Self, allocator: std.mem.Allocator, request_id: []const u8) !ResponseBody {
        const result = try self.session.sendCommand("Fetch.getResponseBody", .{
            .request_id = request_id,
        });

        return .{
            .body = try allocator.dupe(u8, try json_util.getString(result, "body")),
            .base64_encoded = try json_util.getBool(result, "base64Encoded"),
        };
    }
};

/// Request pattern
pub const RequestPattern = struct {
    url_pattern: ?[]const u8 = null,
    resource_type: ?[]const u8 = null,
    request_stage: ?[]const u8 = null,
};

/// Fulfill parameters
pub const FulfillParams = struct {
    request_id: []const u8,
    response_code: i32,
    response_headers: ?[]const HeaderEntry = null,
    body: ?[]const u8 = null,
    response_phrase: ?[]const u8 = null,
};

/// Continue parameters
pub const ContinueParams = struct {
    request_id: []const u8,
    url: ?[]const u8 = null,
    method: ?[]const u8 = null,
    post_data: ?[]const u8 = null,
    headers: ?[]const HeaderEntry = null,
};

/// Header entry
pub const HeaderEntry = struct {
    name: []const u8,
    value: []const u8,
};

/// Auth response
pub const AuthResponse = struct {
    response: []const u8,
    username: ?[]const u8 = null,
    password: ?[]const u8 = null,
};

/// Response body
pub const ResponseBody = struct {
    body: []const u8,
    base64_encoded: bool,

    pub fn deinit(self: *ResponseBody, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
    }
};

/// Request paused event
pub const RequestPaused = struct {
    request_id: []const u8,
    request: NetworkRequest,
    frame_id: []const u8,
    resource_type: []const u8,
    response_error_reason: ?[]const u8 = null,
    response_status_code: ?i32 = null,
    response_headers: ?[]const HeaderEntry = null,
};

/// Network request (simplified)
pub const NetworkRequest = struct {
    url: []const u8,
    method: []const u8,
    headers: std.json.Value,
    post_data: ?[]const u8 = null,
};
