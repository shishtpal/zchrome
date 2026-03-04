const std = @import("std");
const json = @import("json");

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
    /// The raw JSON string of the result. Caller must free.
    result_json: []const u8,
    session_id: ?[]const u8 = null,

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        allocator.free(self.result_json);
        if (self.session_id) |sid| allocator.free(sid);
    }

    /// Parse the result JSON into a Value. Caller must deinit the value.
    pub fn parseResult(self: Response, allocator: std.mem.Allocator) !json.Value {
        return json.parse(allocator, self.result_json, .{});
    }
};

/// Server-pushed event
pub const Event = struct {
    method: []const u8,
    /// The raw JSON string of the params. Caller must free.
    params_json: []const u8,
    session_id: ?[]const u8 = null,

    pub fn deinit(self: *Event, allocator: std.mem.Allocator) void {
        allocator.free(self.method);
        allocator.free(self.params_json);
        if (self.session_id) |sid| allocator.free(sid);
    }

    /// Parse the params JSON into a Value. Caller must deinit the value.
    pub fn parseParams(self: Event, allocator: std.mem.Allocator) !json.Value {
        return json.parse(allocator, self.params_json, .{});
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

/// Parse a raw JSON string into a Message
pub fn parseMessage(allocator: std.mem.Allocator, raw_json: []const u8) !Message {
    var parsed = json.parse(allocator, raw_json, .{}) catch return error.InvalidMessage;
    defer parsed.deinit(allocator);

    if (parsed != .object) {
        return error.InvalidMessage;
    }

    // Check for "id" field to distinguish response from event
    if (parsed.get("id")) |id_val| {
        const id: CommandId = switch (id_val) {
            .integer => |i| @intCast(i),
            .float => |f| @intFromFloat(f),
            else => return error.InvalidMessage,
        };

        // Check for error
        if (parsed.get("error")) |err_val| {
            const err_payload = try parseErrorPayload(allocator, err_val);

            return .{
                .error_response = .{
                    .id = id,
                    .code = err_payload.code,
                    .message = err_payload.message,
                    .data = err_payload.data,
                },
            };
        }

        // Success response - extract result JSON substring
        const result_json = try extractSubJson(allocator, raw_json, "result");

        var session_id: ?[]const u8 = null;
        if (parsed.get("sessionId")) |sid_val| {
            if (sid_val == .string) {
                session_id = try allocator.dupe(u8, sid_val.string);
            }
        }

        return .{
            .response = .{
                .id = id,
                .result_json = result_json,
                .session_id = session_id,
            },
        };
    }

    // Event (no "id" field, has "method" field)
    if (parsed.get("method")) |method_val| {
        if (method_val != .string) return error.InvalidMessage;

        // Extract params JSON substring
        const params_json = try extractSubJson(allocator, raw_json, "params");

        var session_id: ?[]const u8 = null;
        if (parsed.get("sessionId")) |sid_val| {
            if (sid_val == .string) {
                session_id = try allocator.dupe(u8, sid_val.string);
            }
        }

        return .{
            .event = .{
                .method = try allocator.dupe(u8, method_val.string),
                .params_json = params_json,
                .session_id = session_id,
            },
        };
    }

    return error.InvalidMessage;
}

/// Extract a JSON substring for a key from the raw JSON.
/// Returns "{}" if the key doesn't exist.
fn extractSubJson(allocator: std.mem.Allocator, raw_json: []const u8, key: []const u8) ![]const u8 {
    // Build the search pattern: "key":
    var pattern_buf: [64]u8 = undefined;
    const pattern = std.fmt.bufPrint(&pattern_buf, "\"{s}\":", .{key}) catch return allocator.dupe(u8, "{}");

    const key_start = std.mem.indexOf(u8, raw_json, pattern) orelse {
        return allocator.dupe(u8, "{}");
    };

    const value_start = key_start + pattern.len;
    if (value_start >= raw_json.len) return allocator.dupe(u8, "{}");

    // Skip whitespace
    var pos = value_start;
    while (pos < raw_json.len and (raw_json[pos] == ' ' or raw_json[pos] == '\t' or raw_json[pos] == '\n' or raw_json[pos] == '\r')) {
        pos += 1;
    }

    if (pos >= raw_json.len) return allocator.dupe(u8, "{}");

    const start_char = raw_json[pos];
    const start = pos;

    // Find the end based on the start character
    if (start_char == '{') {
        var depth: usize = 1;
        pos += 1;
        var in_string = false;
        var prev_backslash = false;
        while (pos < raw_json.len and depth > 0) {
            const c = raw_json[pos];
            if (in_string) {
                if (c == '"' and !prev_backslash) {
                    in_string = false;
                }
                prev_backslash = (c == '\\' and !prev_backslash);
            } else {
                switch (c) {
                    '"' => in_string = true,
                    '{' => depth += 1,
                    '}' => depth -= 1,
                    else => {},
                }
            }
            pos += 1;
        }
        return allocator.dupe(u8, raw_json[start..pos]);
    } else if (start_char == '[') {
        var depth: usize = 1;
        pos += 1;
        var in_string = false;
        var prev_backslash = false;
        while (pos < raw_json.len and depth > 0) {
            const c = raw_json[pos];
            if (in_string) {
                if (c == '"' and !prev_backslash) {
                    in_string = false;
                }
                prev_backslash = (c == '\\' and !prev_backslash);
            } else {
                switch (c) {
                    '"' => in_string = true,
                    '[' => depth += 1,
                    ']' => depth -= 1,
                    else => {},
                }
            }
            pos += 1;
        }
        return allocator.dupe(u8, raw_json[start..pos]);
    } else if (start_char == '"') {
        // String value
        pos += 1;
        var prev_backslash = false;
        while (pos < raw_json.len) {
            const c = raw_json[pos];
            if (c == '"' and !prev_backslash) {
                pos += 1;
                break;
            }
            prev_backslash = (c == '\\' and !prev_backslash);
            pos += 1;
        }
        return allocator.dupe(u8, raw_json[start..pos]);
    } else {
        // Primitive value (number, bool, null)
        while (pos < raw_json.len) {
            const c = raw_json[pos];
            if (c == ',' or c == '}' or c == ']' or c == ' ' or c == '\n' or c == '\r' or c == '\t') {
                break;
            }
            pos += 1;
        }
        return allocator.dupe(u8, raw_json[start..pos]);
    }
}

/// Parse error payload from JSON
fn parseErrorPayload(allocator: std.mem.Allocator, value: json.Value) !ErrorPayload {
    if (value != .object) return error.InvalidMessage;

    const code_int = value.getInt("code") catch return error.InvalidMessage;
    const message_str = value.getString("message") catch return error.InvalidMessage;

    var data: ?[]const u8 = null;
    if (value.get("data")) |data_val| {
        if (data_val == .string) {
            data = try allocator.dupe(u8, data_val.string);
        }
    }

    return .{
        .code = code_int,
        .message = try allocator.dupe(u8, message_str),
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
                const camel_name = comptime json.comptimeSnakeToCamel(field.name);
                try list.appendSlice(allocator, "\"" ++ camel_name ++ "\":");

                const field_str = try json.encode(allocator, field_value, .{});
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
        const params_str = try json.encode(allocator, params, .{});
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

test "extractSubJson - object" {
    const json_str = "{\"id\":1,\"result\":{\"frameId\":\"F1\",\"nested\":{\"a\":1}}}";
    const result = try extractSubJson(std.testing.allocator, json_str, "result");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("{\"frameId\":\"F1\",\"nested\":{\"a\":1}}", result);
}

test "extractSubJson - missing key" {
    const json_str = "{\"id\":1}";
    const result = try extractSubJson(std.testing.allocator, json_str, "result");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("{}", result);
}

test "Response.parseResult" {
    const raw = "{\"id\":1,\"result\":{\"frameId\":\"F1\"}}";
    var msg = try parseMessage(std.testing.allocator, raw);
    defer msg.deinit(std.testing.allocator);

    var result = try msg.response.parseResult(std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    const frame_id = try result.getString("frameId");
    try std.testing.expectEqualStrings("F1", frame_id);
}
