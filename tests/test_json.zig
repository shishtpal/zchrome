const std = @import("std");
const json = @import("cdp").json;

test "snakeToCamel - basic" {
    const result = try json.snakeToCamel(std.testing.allocator, "frame_id");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("frameId", result);
}

test "snakeToCamel - multiple underscores" {
    const result = try json.snakeToCamel(std.testing.allocator, "capture_beyond_viewport");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("captureBeyondViewport", result);
}

test "snakeToCamel - no underscores" {
    const result = try json.snakeToCamel(std.testing.allocator, "url");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("url", result);
}

test "camelToSnake - basic" {
    const result = try json.camelToSnake(std.testing.allocator, "frameId");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("frame_id", result);
}

test "comptimeSnakeToCamel" {
    const result = comptime json.comptimeSnakeToCamel("from_surface");
    try std.testing.expectEqualStrings("fromSurface", result);
}

test "getString - exists" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"key\":\"value\"}", .{});
    defer parsed.deinit();
    const result = try json.getString(parsed.value, "key");
    try std.testing.expectEqualStrings("value", result);
}

test "getString - missing key" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{}", .{});
    defer parsed.deinit();
    const result = json.getString(parsed.value, "key");
    try std.testing.expectError(error.MissingField, result);
}

test "getInt - valid" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"num\":42}", .{});
    defer parsed.deinit();
    const result = try json.getInt(parsed.value, "num");
    try std.testing.expectEqual(@as(i64, 42), result);
}

test "getBool - valid" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"flag\":true}", .{});
    defer parsed.deinit();
    const result = try json.getBool(parsed.value, "flag");
    try std.testing.expect(result);
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

    var result = try json.decode(TestStruct, parsed.value, std.testing.allocator);
    defer std.testing.allocator.free(result.frame_id);
    if (result.loader_id) |l| std.testing.allocator.free(l);

    try std.testing.expectEqualStrings("F1", result.frame_id);
    try std.testing.expectEqualStrings("L1", result.loader_id.?);
}

test "stringify struct to json" {
    const params = .{ .url = "https://example.com", .ignore_cache = true };
    const result = try json.stringify(std.testing.allocator, params);
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "\"url\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"ignoreCache\"") != null);
}

test "stringify skips null optionals" {
    const params = .{ .url = "https://example.com", .referrer = @as(?[]const u8, null) };
    const result = try json.stringify(std.testing.allocator, params);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "referrer") == null);
}
