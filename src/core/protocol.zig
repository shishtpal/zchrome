const std = @import("std");
const json_util = @import("../util/json.zig");
const types = @import("types.zig");

pub const CommandId = u64;

/// Error payload from CDP
pub const ErrorPayload = struct {
    code: i64,
    message: []const u8,
    data: ?[]const u8 = null,

    pub fn deinit(self: *ErrorPayload, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        if (self.data) |d| allocator.free(d);
    }
};

/// Raw message structure (for parsing)
pub const RawMessage = struct {
    id: ?CommandId = null,
    method: ?[]const u8 = null,
    params: ?std.json.Value = null,
    result: ?std.json.Value = null,
    @"error": ?ErrorPayload = null,
    sessionId: ?[]const u8 = null,
};

/// Parsed message type
pub const Message = union(enum) {
    response: Response,
    event: Event,
    error_response: ErrorResponse,

    pub fn deinit(self: *Message, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .response => |*r| r.deinit(allocator),
            .event => |*e| e.deinit(allocator),
            .error_response => |*er| er.deinit(allocator),
        }
    }
};

/// Successful command response
pub const Response = struct {
    id: CommandId,
    result: std.json.Value,
    session_id: ?[]const u8 = null,

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        if (self.session_id) |sid| allocator.free(sid);
    }
};

/// Server-pushed event
pub const Event = struct {
    method: []const u8,
    params: std.json.Value,
    session_id: ?[]const u8 = null,

    pub fn deinit(self: *Event, allocator: std.mem.Allocator) void {
        allocator.free(self.method);
        if (self.session_id) |sid| allocator.free(sid);
    }
};

/// Error response to a command
pub const ErrorResponse = struct {
    id: CommandId,
    code: i64,
    message: []const u8,
    data: ?[]const u8 = null,

    pub fn deinit(self: *ErrorResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        if (self.data) |d| allocator.free(d);
    }
};

/// Create an empty JSON object value
fn emptyObjectValue(allocator: std.mem.Allocator) std.json.Value {
    return .{ .object = std.json.ObjectMap.init(allocator) };
}

/// Parse a raw JSON string into a Message
pub fn parseMessage(allocator: std.mem.Allocator, raw_json: []const u8) !Message {
    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        raw_json,
        .{},
    ) catch return error.InvalidMessage;
    defer parsed.deinit();

    const value = parsed.value;

    if (value != .object) {
        return error.InvalidMessage;
    }

    // Check for "id" field to distinguish response from event
    if (value.object.get("id")) |id_val| {
        const id: CommandId = switch (id_val) {
            .integer => |i| @intCast(i),
            .float => |f| @intFromFloat(f),
            else => return error.InvalidMessage,
        };

        // Check for error
        if (value.object.get("error")) |err_val| {
            const err_payload = try parseErrorPayload(allocator, err_val);

            var session_id: ?[]const u8 = null;
            if (value.object.get("sessionId")) |sid_val| {
                session_id = try json_util.getString(sid_val, "");
                _ = &session_id; // Workaround for unused variable
            }

            return .{
                .error_response = .{
                    .id = id,
                    .code = err_payload.code,
                    .message = err_payload.message,
                    .data = err_payload.data,
                },
            };
        }

        // Success response
        const result = value.object.get("result") orelse emptyObjectValue(allocator);

        var session_id: ?[]const u8 = null;
        if (value.object.get("sessionId")) |sid_val| {
            if (sid_val == .string) {
                session_id = try allocator.dupe(u8, sid_val.string);
            }
        }

        return .{
            .response = .{
                .id = id,
                .result = result,
                .session_id = session_id,
            },
        };
    }

    // Event (no "id" field, has "method" field)
    if (value.object.get("method")) |method_val| {
        if (method_val != .string) return error.InvalidMessage;

        const params = value.object.get("params") orelse emptyObjectValue(allocator);

        var session_id: ?[]const u8 = null;
        if (value.object.get("sessionId")) |sid_val| {
            if (sid_val == .string) {
                session_id = try allocator.dupe(u8, sid_val.string);
            }
        }

        return .{
            .event = .{
                .method = try allocator.dupe(u8, method_val.string),
                .params = params,
                .session_id = session_id,
            },
        };
    }

    return error.InvalidMessage;
}

/// Parse error payload from JSON
fn parseErrorPayload(allocator: std.mem.Allocator, value: std.json.Value) !ErrorPayload {
    if (value != .object) return error.InvalidMessage;

    const code = value.object.get("code") orelse return error.InvalidMessage;
    const message = value.object.get("message") orelse return error.InvalidMessage;

    const code_int: i64 = switch (code) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => return error.InvalidMessage,
    };

    const message_str = switch (message) {
        .string => |s| try allocator.dupe(u8, s),
        else => return error.InvalidMessage,
    };

    var data: ?[]const u8 = null;
    if (value.object.get("data")) |data_val| {
        if (data_val == .string) {
            data = try allocator.dupe(u8, data_val.string);
        }
    }

    return .{
        .code = code_int,
        .message = message_str,
        .data = data,
    };
}

/// Serialize a command to JSON
pub fn serializeCommand(
    allocator: std.mem.Allocator,
    id: CommandId,
    method: []const u8,
    params: anytype,
    session_id: ?[]const u8,
) ![]const u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    // Build JSON string manually
    const header = try std.fmt.allocPrint(allocator, "{{\"id\":{},\"method\":\"{s}\"", .{ id, method });
    defer allocator.free(header);
    try list.appendSlice(allocator, header);

    // Add params if not empty
    const params_type = @TypeOf(params);
    const params_type_info = @typeInfo(params_type);

    if (params_type_info == .@"struct") {
        const struct_info = params_type_info.@"struct";
        var has_fields = false;

        inline for (struct_info.fields) |field| {
            const field_value = @field(params, field.name);
            const is_optional = @typeInfo(field.type) == .optional;

            if (!is_optional or field_value != null) {
                if (!has_fields) {
                    try list.appendSlice(allocator, ",\"params\":{");
                    has_fields = true;
                } else {
                    try list.appendSlice(allocator, ",");
                }

                // Use comptime field name formatting
                const camel_name = comptime json_util.comptimeSnakeToCamel(field.name);
                try list.appendSlice(allocator, "\"" ++ camel_name ++ "\":");

                const field_str = try json_util.stringifyValueToString(allocator, field_value);
                defer allocator.free(field_str);
                try list.appendSlice(allocator, field_str);
            }
        }

        if (has_fields) {
            try list.appendSlice(allocator, "}");
        }
    } else if (params_type_info == .void) {
        // No params
    } else {
        // Assume it's already a value type
        try list.appendSlice(allocator, ",\"params\":");
        const params_str = try json_util.stringifyValueToString(allocator, params);
        defer allocator.free(params_str);
        try list.appendSlice(allocator, params_str);
    }

    // Add session_id if present
    if (session_id) |sid| {
        const sid_str = try std.fmt.allocPrint(allocator, ",\"sessionId\":\"{s}\"", .{sid});
        defer allocator.free(sid_str);
        try list.appendSlice(allocator, sid_str);
    }

    try list.appendSlice(allocator, "}");

    return list.toOwnedSlice(allocator);
}

/// Thread-safe command ID allocator
pub const IdAllocator = struct {
    counter: std.atomic.Value(CommandId),

    pub fn init() IdAllocator {
        return .{
            .counter = std.atomic.Value(CommandId).init(0),
        };
    }

    pub fn next(self: *IdAllocator) CommandId {
        return self.counter.fetchAdd(1, .monotonic) + 1;
    }

    pub fn reset(self: *IdAllocator) void {
        self.counter.store(0, .monotonic);
    }
};

// ─── Tests ──────────────────────────────────────────────────────────────────

test "parseMessage - response with result" {
    const raw = "{\"id\":1,\"result\":{\"frameId\":\"F1\"}}";
    var msg = try parseMessage(std.testing.allocator, raw);
    defer msg.deinit(std.testing.allocator);

    try std.testing.expect(msg == .response);
    try std.testing.expectEqual(@as(CommandId, 1), msg.response.id);
}

test "parseMessage - response with session id" {
    const raw = "{\"id\":2,\"result\":{},\"sessionId\":\"S1\"}";
    var msg = try parseMessage(std.testing.allocator, raw);
    defer msg.deinit(std.testing.allocator);

    try std.testing.expect(msg == .response);
    try std.testing.expectEqualStrings("S1", msg.response.session_id.?);
}

test "parseMessage - error response" {
    const raw = "{\"id\":3,\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}";
    var msg = try parseMessage(std.testing.allocator, raw);
    defer msg.deinit(std.testing.allocator);

    try std.testing.expect(msg == .error_response);
    try std.testing.expectEqual(@as(i64, -32601), msg.error_response.code);
    try std.testing.expectEqualStrings("Method not found", msg.error_response.message);
}

test "parseMessage - event" {
    const raw = "{\"method\":\"Page.loadEventFired\",\"params\":{\"timestamp\":12345.0}}";
    var msg = try parseMessage(std.testing.allocator, raw);
    defer msg.deinit(std.testing.allocator);

    try std.testing.expect(msg == .event);
    try std.testing.expectEqualStrings("Page.loadEventFired", msg.event.method);
}

test "parseMessage - invalid json" {
    const result = parseMessage(std.testing.allocator, "not json{{{");
    try std.testing.expectError(error.InvalidMessage, result);
}

test "serializeCommand - with params" {
    const result = try serializeCommand(
        std.testing.allocator,
        1,
        "Page.navigate",
        .{ .url = "https://example.com" },
        null,
    );
    defer std.testing.allocator.free(result);

    // Verify structure
    try std.testing.expect(std.mem.indexOf(u8, result, "\"id\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"method\":\"Page.navigate\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"params\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"url\":\"https://example.com\"") != null);
}

test "serializeCommand - with session id" {
    const result = try serializeCommand(
        std.testing.allocator,
        2,
        "Page.enable",
        .{},
        "SESSION_001",
    );
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "\"sessionId\":\"SESSION_001\"") != null);
}

test "IdAllocator - monotonic" {
    var alloc = IdAllocator.init();
    try std.testing.expectEqual(@as(CommandId, 1), alloc.next());
    try std.testing.expectEqual(@as(CommandId, 2), alloc.next());
    try std.testing.expectEqual(@as(CommandId, 3), alloc.next());
}
