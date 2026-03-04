//! JSON utilities for the CDP library.
//! This module re-exports functionality from the zlib-json library.
//!
//! Migration note: This file provides backward compatibility during migration.
//! Files should gradually migrate to using `@import("json")` directly.

const std = @import("std");
const json = @import("json");

// ─── Re-export types and functions from zlib-json ───

/// The JSON Value type (replaces std.json.Value)
pub const Value = json.Value;

/// Parse JSON string into a Value.
/// NOTE: Unlike std.json, caller must call `value.deinit(allocator)` when done.
pub const parse = json.parse;
pub const ParseError = json.ParseError;
pub const ParseOptions = json.ParseOptions;

/// Stringify a Value to JSON.
pub const stringifyValue = json.stringify;
pub const StringifyOptions = json.StringifyOptions;
pub const StringifyError = json.StringifyError;

/// Encode a Zig value to JSON string (with snake_case → camelCase).
pub const encode = json.encode;
pub const EncodeOptions = json.EncodeOptions;
pub const EncodeError = json.EncodeError;

/// Decode a JSON Value into a Zig struct (with camelCase → snake_case).
pub const decode = json.decode;
pub const decodeWithOptions = json.decodeWithOptions;
pub const DecodeOptions = json.DecodeOptions;
pub const DecodeError = json.DecodeError;

/// Case conversion functions.
pub const snakeToCamel = json.snakeToCamel;
pub const camelToSnake = json.camelToSnake;
pub const comptimeSnakeToCamel = json.comptimeSnakeToCamel;

/// String escaping.
pub const escapeString = json.escapeString;

// ─── Legacy compatibility functions ───

/// Alias for backward compatibility.
/// Use `json.encode` for new code.
pub fn stringifyValueToString(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    return json.encode(allocator, value, .{});
}

/// Alias for backward compatibility.
pub const stringify = stringifyValueToString;

/// Extract a string field from a Value object.
/// Compatibility wrapper - use `value.getString(key)` directly on new code.
pub fn getString(value: Value, key: []const u8) ![]const u8 {
    return value.getString(key);
}

/// Extract an integer field from a Value object.
/// Compatibility wrapper - use `value.getInt(key)` directly on new code.
pub fn getInt(value: Value, key: []const u8) !i64 {
    return value.getInt(key);
}

/// Extract a float field from a Value object.
/// Compatibility wrapper - use `value.getFloat(key)` directly on new code.
pub fn getFloat(value: Value, key: []const u8) !f64 {
    return value.getFloat(key);
}

/// Extract a boolean field from a Value object.
/// Compatibility wrapper - use `value.getBool(key)` directly on new code.
pub fn getBool(value: Value, key: []const u8) !bool {
    return value.getBool(key);
}

/// Extract an array field from a Value object.
/// Compatibility wrapper - use `value.getArray(key)` directly on new code.
pub fn getArray(value: Value, key: []const u8) ![]const Value {
    return value.getArray(key);
}

/// Extract an optional field from a Value object.
/// Compatibility wrapper - use `value.getOptional(T, key, allocator)` directly on new code.
pub fn getOptional(
    comptime T: type,
    value: Value,
    key: []const u8,
    allocator: std.mem.Allocator,
) !?T {
    return value.getOptional(T, key, allocator);
}

// ─── Tests ───

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
    var parsed = try json.parse(std.testing.allocator, "{\"key\":\"value\"}", .{});
    defer parsed.deinit(std.testing.allocator);
    const result = try getString(parsed, "key");
    try std.testing.expectEqualStrings("value", result);
}

test "getString - missing key" {
    var parsed = try json.parse(std.testing.allocator, "{}", .{});
    defer parsed.deinit(std.testing.allocator);
    const result = getString(parsed, "key");
    try std.testing.expectError(Value.FieldError.MissingField, result);
}

test "decode struct from json value" {
    const TestStruct = struct {
        frame_id: []const u8,
        loader_id: ?[]const u8 = null,
        error_text: ?[]const u8 = null,
    };

    var parsed = try json.parse(
        std.testing.allocator,
        "{\"frameId\":\"F1\",\"loaderId\":\"L1\"}",
        .{},
    );
    defer parsed.deinit(std.testing.allocator);

    var result = try decode(TestStruct, parsed, std.testing.allocator);
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
