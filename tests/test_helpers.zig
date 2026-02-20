const std = @import("std");
const cdp = @import("cdp");
const json = cdp.json;

// ─── escapeJsString Tests ────────────────────────────────────────────────────

fn escapeJsString(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    try result.append(allocator, '"');
    for (s) |c| {
        switch (c) {
            '"' => try result.appendSlice(allocator, "\\\""),
            '\\' => try result.appendSlice(allocator, "\\\\"),
            '\n' => try result.appendSlice(allocator, "\\n"),
            '\r' => try result.appendSlice(allocator, "\\r"),
            '\t' => try result.appendSlice(allocator, "\\t"),
            else => try result.append(allocator, c),
        }
    }
    try result.append(allocator, '"');

    return result.toOwnedSlice(allocator);
}

fn getFloatFromJson(val: ?std.json.Value) ?f64 {
    if (val) |v| {
        return switch (v) {
            .float => |f| f,
            .integer => |i| @floatFromInt(i),
            else => null,
        };
    }
    return null;
}

test "escapeJsString - simple string" {
    const result = try escapeJsString(std.testing.allocator, "hello");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("\"hello\"", result);
}

test "escapeJsString - with quotes" {
    const result = try escapeJsString(std.testing.allocator, "say \"hello\"");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("\"say \\\"hello\\\"\"", result);
}

test "escapeJsString - with backslashes" {
    const result = try escapeJsString(std.testing.allocator, "path\\to\\file");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("\"path\\\\to\\\\file\"", result);
}

test "escapeJsString - with newlines" {
    const result = try escapeJsString(std.testing.allocator, "line1\nline2");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("\"line1\\nline2\"", result);
}

test "escapeJsString - with tabs" {
    const result = try escapeJsString(std.testing.allocator, "col1\tcol2");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("\"col1\\tcol2\"", result);
}

test "escapeJsString - empty string" {
    const result = try escapeJsString(std.testing.allocator, "");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("\"\"", result);
}

test "getFloatFromJson - with float value" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"num\":3.14}", .{});
    defer parsed.deinit();
    const val = parsed.value.object.get("num");
    const result = getFloatFromJson(val);
    try std.testing.expect(result != null);
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), result.?, 0.001);
}

test "getFloatFromJson - with integer value" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"num\":42}", .{});
    defer parsed.deinit();
    const val = parsed.value.object.get("num");
    const result = getFloatFromJson(val);
    try std.testing.expect(result != null);
    try std.testing.expectApproxEqAbs(@as(f64, 42.0), result.?, 0.001);
}

test "getFloatFromJson - with null value" {
    const result = getFloatFromJson(null);
    try std.testing.expect(result == null);
}

test "getFloatFromJson - with string value" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"str\":\"not a number\"}", .{});
    defer parsed.deinit();
    const val = parsed.value.object.get("str");
    const result = getFloatFromJson(val);
    try std.testing.expect(result == null);
}

test "getFloatFromJson - with negative integer" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"num\":-42}", .{});
    defer parsed.deinit();
    const val = parsed.value.object.get("num");
    const result = getFloatFromJson(val);
    try std.testing.expect(result != null);
    try std.testing.expectApproxEqAbs(@as(f64, -42.0), result.?, 0.001);
}
