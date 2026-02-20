const std = @import("std");

/// Comptime compute the length of snake_case converted to camelCase
fn SnakeToCamelLen(comptime snake: []const u8) comptime_int {
    var count: usize = 0;
    for (snake) |c| {
        if (c != '_') count += 1;
    }
    return count;
}

/// Convert snake_case to camelCase (comptime version)
/// Returns a pointer to a static comptime-known array
pub fn comptimeSnakeToCamel(comptime snake: []const u8) *const [SnakeToCamelLen(snake)]u8 {
    const len = comptime SnakeToCamelLen(snake);
    const result = comptime blk: {
        var buf: [len]u8 = undefined;
        var j: usize = 0;
        var capitalize_next = false;

        for (snake) |c| {
            if (c == '_') {
                capitalize_next = true;
            } else {
                buf[j] = if (capitalize_next) std.ascii.toUpper(c) else c;
                j += 1;
                capitalize_next = false;
            }
        }

        break :blk buf;
    };
    return &result;
}

/// Convert snake_case to camelCase (runtime version)
pub fn snakeToCamel(allocator: std.mem.Allocator, snake: []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var capitalize_next = false;
    for (snake) |c| {
        if (c == '_') {
            capitalize_next = true;
        } else {
            try result.append(allocator, if (capitalize_next) std.ascii.toUpper(c) else c);
            capitalize_next = false;
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Convert camelCase to snake_case
pub fn camelToSnake(allocator: std.mem.Allocator, camel: []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    for (camel, 0..) |c, i| {
        if (std.ascii.isUpper(c)) {
            if (i > 0) {
                try result.append(allocator, '_');
            }
            try result.append(allocator, std.ascii.toLower(c));
        } else {
            try result.append(allocator, c);
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Extract a string field from a JSON object
pub fn getString(value: std.json.Value, key: []const u8) ![]const u8 {
    const obj = value.object.get(key) orelse return error.MissingField;
    return switch (obj) {
        .string => |s| s,
        else => error.TypeMismatch,
    };
}

/// Extract an integer field from a JSON object
pub fn getInt(value: std.json.Value, key: []const u8) !i64 {
    const obj = value.object.get(key) orelse return error.MissingField;
    return switch (obj) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        else => error.TypeMismatch,
    };
}

/// Extract a float field from a JSON object
pub fn getFloat(value: std.json.Value, key: []const u8) !f64 {
    const obj = value.object.get(key) orelse return error.MissingField;
    return switch (obj) {
        .float => |f| f,
        .integer => |i| @floatFromInt(i),
        else => error.TypeMismatch,
    };
}

/// Extract a boolean field from a JSON object
pub fn getBool(value: std.json.Value, key: []const u8) !bool {
    const obj = value.object.get(key) orelse return error.MissingField;
    return switch (obj) {
        .bool => |b| b,
        else => error.TypeMismatch,
    };
}

/// Extract an array field from a JSON object
pub fn getArray(value: std.json.Value, key: []const u8) ![]const std.json.Value {
    const obj = value.object.get(key) orelse return error.MissingField;
    return switch (obj) {
        .array => |a| a.items,
        else => error.TypeMismatch,
    };
}

/// Extract an optional field from a JSON object
pub fn getOptional(
    comptime T: type,
    value: std.json.Value,
    key: []const u8,
    allocator: std.mem.Allocator,
) !?T {
    const obj = value.object.get(key) orelse return null;
    if (obj == .null) return null;
    return try decode(T, obj, allocator);
}

/// Decode a JSON value into a typed Zig struct
pub fn decode(
    comptime T: type,
    value: std.json.Value,
    allocator: std.mem.Allocator,
) !T {
    const type_info = @typeInfo(T);

    switch (type_info) {
        .int, .comptime_int => {
            return switch (value) {
                .integer => |i| @intCast(i),
                .float => |f| @intFromFloat(f),
                else => return error.TypeMismatch,
            };
        },
        .float, .comptime_float => {
            return switch (value) {
                .float => |f| @floatCast(f),
                .integer => |i| @floatFromInt(i),
                else => return error.TypeMismatch,
            };
        },
        .bool => {
            return switch (value) {
                .bool => |b| b,
                else => return error.TypeMismatch,
            };
        },
        .optional => |opt| {
            if (value == .null) return null;
            return try decode(opt.child, value, allocator);
        },
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                return switch (value) {
                    .string => |s| try allocator.dupe(u8, s),
                    else => return error.TypeMismatch,
                };
            }
            return error.TypeMismatch;
        },
        .@"enum" => |enum_info| {
            const str = switch (value) {
                .string => |s| s,
                else => return error.TypeMismatch,
            };
            inline for (enum_info.fields) |field| {
                if (std.mem.eql(u8, str, field.name)) {
                    return @field(T, field.name);
                }
            }
            return error.TypeMismatch;
        },
        .@"struct" => |struct_info| {
            if (value != .object) return error.TypeMismatch;

            var result: T = undefined;
            errdefer inline for (struct_info.fields) |field| {
                if (@typeInfo(field.type) == .pointer) {
                    // Clean up any allocated fields
                }
            };

            inline for (struct_info.fields) |field| {
                const camel_key: []const u8 = comptimeSnakeToCamel(field.name);
                const json_val = value.object.get(camel_key);

                const is_optional = @typeInfo(field.type) == .optional;
                const has_default = field.default_value_ptr != null;

                if (json_val) |jv| {
                    @field(result, field.name) = try decode(field.type, jv, allocator);
                } else if (is_optional) {
                    @field(result, field.name) = null;
                } else if (has_default) {
                    @field(result, field.name) = @as(*const field.type, @ptrCast(field.default_value_ptr.?)).*;
                } else {
                    return error.MissingField;
                }
            }

            return result;
        },
        .array => |arr| {
            if (value != .array) return error.TypeMismatch;
            if (value.array.items.len != arr.len) return error.TypeMismatch;

            var result: T = undefined;
            inline for (0..arr.len) |i| {
                result[i] = try decode(arr.child, value.array.items[i], allocator);
            }
            return result;
        },
        else => return error.TypeMismatch,
    }
}

/// Serialize a Zig value to a JSON string (returns allocated string)
pub fn stringifyValueToString(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    switch (type_info) {
        .int, .comptime_int => {
            return std.fmt.allocPrint(allocator, "{}", .{value});
        },
        .float, .comptime_float => {
            return std.fmt.allocPrint(allocator, "{d}", .{value});
        },
        .bool => {
            return allocator.dupe(u8, if (value) "true" else "false");
        },
        .null => {
            return allocator.dupe(u8, "null");
        },
        .optional => {
            if (value) |v| {
                return stringifyValueToString(allocator, v);
            } else {
                return allocator.dupe(u8, "null");
            }
        },
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                // Properly escape the string for JSON
                var list: std.ArrayList(u8) = .empty;
                errdefer list.deinit(allocator);
                try list.append(allocator, '"');
                for (value) |c| {
                    switch (c) {
                        '"' => try list.appendSlice(allocator, "\\\""),
                        '\\' => try list.appendSlice(allocator, "\\\\"),
                        '\n' => try list.appendSlice(allocator, "\\n"),
                        '\r' => try list.appendSlice(allocator, "\\r"),
                        '\t' => try list.appendSlice(allocator, "\\t"),
                        else => {
                            if (c < 0x20) {
                                // Control character - use unicode escape
                                const hex = "0123456789abcdef";
                                try list.appendSlice(allocator, "\\u00");
                                try list.append(allocator, hex[c >> 4]);
                                try list.append(allocator, hex[c & 0xf]);
                            } else {
                                try list.append(allocator, c);
                            }
                        },
                    }
                }
                try list.append(allocator, '"');
                return list.toOwnedSlice(allocator);
            } else if (ptr.size == .slice) {
                var list: std.ArrayList(u8) = .empty;
                errdefer list.deinit(allocator);
                try list.appendSlice(allocator, "[");
                for (value, 0..) |item, i| {
                    if (i > 0) try list.appendSlice(allocator, ",");
                    const item_str = try stringifyValueToString(allocator, item);
                    defer allocator.free(item_str);
                    try list.appendSlice(allocator, item_str);
                }
                try list.appendSlice(allocator, "]");
                return list.toOwnedSlice(allocator);
            } else {
                return stringifyValueToString(allocator, value.*);
            }
        },
        .array => |arr| {
            if (arr.child == u8) {
                // Treat as string - use the slice escaping logic
                const slice: []const u8 = &value;
                return stringifyValueToString(allocator, slice);
            } else {
                var list: std.ArrayList(u8) = .empty;
                errdefer list.deinit(allocator);
                try list.appendSlice(allocator, "[");
                inline for (value, 0..) |item, i| {
                    if (i > 0) try list.appendSlice(allocator, ",");
                    const item_str = try stringifyValueToString(allocator, item);
                    defer allocator.free(item_str);
                    try list.appendSlice(allocator, item_str);
                }
                try list.appendSlice(allocator, "]");
                return list.toOwnedSlice(allocator);
            }
        },
        .@"enum" => {
            return std.fmt.allocPrint(allocator, "\"{s}\"", .{@tagName(value)});
        },
        .@"struct" => |struct_info| {
            var list: std.ArrayList(u8) = .empty;
            errdefer list.deinit(allocator);
            try list.appendSlice(allocator, "{");
            var first = true;

            inline for (struct_info.fields) |field| {
                const field_value = @field(value, field.name);

                // Skip null optional fields
                if (@typeInfo(field.type) == .optional and field_value == null) {
                    continue;
                }

                if (!first) try list.appendSlice(allocator, ",");
                first = false;

                // Use comptime string concatenation for field name
                const camel_name = comptime comptimeSnakeToCamel(field.name);
                try list.appendSlice(allocator, "\"" ++ camel_name ++ "\":");

                const field_str = try stringifyValueToString(allocator, field_value);
                defer allocator.free(field_str);
                try list.appendSlice(allocator, field_str);
            }
            try list.appendSlice(allocator, "}");
            return list.toOwnedSlice(allocator);
        },
        else => {
            @compileError("Unsupported type for JSON serialization: " ++ @typeName(T));
        },
    }
}

// Alias for backward compatibility
pub const stringify = stringifyValueToString;

// ─── Tests ──────────────────────────────────────────────────────────────────

test "snakeToCamel - basic" {
    const result = try snakeToCamel(std.testing.allocator, "frame_id");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("frameId", result);
}

test "snakeToCamel - multiple underscores" {
    const result = try snakeToCamel(std.testing.allocator, "capture_beyond_viewport");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("captureBeyondViewport", result);
}

test "snakeToCamel - no underscores" {
    const result = try snakeToCamel(std.testing.allocator, "url");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("url", result);
}

test "camelToSnake - basic" {
    const result = try camelToSnake(std.testing.allocator, "frameId");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("frame_id", result);
}

test "comptimeSnakeToCamel" {
    const result = comptime comptimeSnakeToCamel("from_surface");
    try std.testing.expectEqualStrings("fromSurface", result);
}

test "getString - exists" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"key\":\"value\"}", .{});
    defer parsed.deinit();
    const result = try getString(parsed.value, "key");
    try std.testing.expectEqualStrings("value", result);
}

test "getString - missing key" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{}", .{});
    defer parsed.deinit();
    const result = getString(parsed.value, "key");
    try std.testing.expectError(error.MissingField, result);
}

test "decode struct from json value" {
    const TestStruct = struct {
        frame_id: []const u8,
        loader_id: ?[]const u8 = null,
        error_text: ?[]const u8 = null,
    };

    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "{\"frameId\":\"F1\",\"loaderId\":\"L1\"}",
        .{},
    );
    defer parsed.deinit();

    var result = try decode(TestStruct, parsed.value, std.testing.allocator);
    defer std.testing.allocator.free(result.frame_id);
    if (result.loader_id) |l| std.testing.allocator.free(l);

    try std.testing.expectEqualStrings("F1", result.frame_id);
    try std.testing.expectEqualStrings("L1", result.loader_id.?);
}

test "stringify struct to json" {
    const params = .{ .url = "https://example.com", .ignore_cache = true };
    const result = try stringifyValueToString(std.testing.allocator, params);
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "\"url\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"ignoreCache\"") != null);
}

test "stringify skips null optionals" {
    const params = .{ .url = "https://example.com", .referrer = @as(?[]const u8, null) };
    const result = try stringifyValueToString(std.testing.allocator, params);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "referrer") == null);
}
