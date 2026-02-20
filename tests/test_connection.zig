const std = @import("std");
const cdp = @import("cdp");

// IdAllocator tests (from protocol module)
test "IdAllocator - initial value is 1" {
    var alloc = cdp.protocol.IdAllocator.init();
    try std.testing.expectEqual(@as(u64, 1), alloc.next());
}

test "IdAllocator - monotonic increment" {
    var alloc = cdp.protocol.IdAllocator.init();
    _ = alloc.next(); // 1
    const id2 = alloc.next(); // 2
    const id3 = alloc.next(); // 3

    try std.testing.expectEqual(@as(u64, 2), id2);
    try std.testing.expectEqual(@as(u64, 3), id3);
}

test "IdAllocator - reset to zero" {
    var alloc = cdp.protocol.IdAllocator.init();
    _ = alloc.next();
    _ = alloc.next();
    alloc.reset();
    try std.testing.expectEqual(@as(u64, 1), alloc.next());
}

test "IdAllocator - thread-safe increment" {
    var alloc = cdp.protocol.IdAllocator.init();

    // In a single thread, this still works
    var ids: [10]u64 = undefined;
    for (&ids) |*id| {
        id.* = alloc.next();
    }

    // Verify all IDs are unique and sequential
    for (ids, 1..) |id, expected| {
        try std.testing.expectEqual(@as(u64, expected), id);
    }
}

// serializeCommand Tests
test "serializeCommand - basic command" {
    const result = try cdp.protocol.serializeCommand(
        std.testing.allocator,
        1,
        "Page.enable",
        .{},
        null,
    );
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "\"id\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"method\":\"Page.enable\"") != null);
}

test "serializeCommand - with params" {
    const result = try cdp.protocol.serializeCommand(
        std.testing.allocator,
        2,
        "Page.navigate",
        .{ .url = "https://example.com" },
        null,
    );
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "\"id\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"method\":\"Page.navigate\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"params\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"url\":\"https://example.com\"") != null);
}

test "serializeCommand - with session ID" {
    const result = try cdp.protocol.serializeCommand(
        std.testing.allocator,
        3,
        "Runtime.evaluate",
        .{ .expression = "1+1" },
        "SESSION_001",
    );
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "\"sessionId\":\"SESSION_001\"") != null);
}

// parseMessage Tests
test "parseMessage - success response" {
    const raw = "{\"id\":1,\"result\":{\"frameId\":\"F1\"}}";
    var msg = try cdp.protocol.parseMessage(std.testing.allocator, raw);
    defer msg.deinit(std.testing.allocator);

    try std.testing.expect(msg == .response);
    try std.testing.expectEqual(@as(u64, 1), msg.response.id);
}

test "parseMessage - error response" {
    const raw = "{\"id\":2,\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}";
    var msg = try cdp.protocol.parseMessage(std.testing.allocator, raw);
    defer msg.deinit(std.testing.allocator);

    try std.testing.expect(msg == .error_response);
    try std.testing.expectEqual(@as(i64, -32601), msg.error_response.code);
    try std.testing.expectEqualStrings("Method not found", msg.error_response.message);
}

test "parseMessage - event" {
    const raw = "{\"method\":\"Page.loadEventFired\",\"params\":{\"timestamp\":12345.0}}";
    var msg = try cdp.protocol.parseMessage(std.testing.allocator, raw);
    defer msg.deinit(std.testing.allocator);

    try std.testing.expect(msg == .event);
    try std.testing.expectEqualStrings("Page.loadEventFired", msg.event.method);
}

test "parseMessage - invalid JSON" {
    const result = cdp.protocol.parseMessage(std.testing.allocator, "not json");
    try std.testing.expectError(error.InvalidMessage, result);
}

// JSON Value Cloning Tests
fn cloneJsonValue(allocator: std.mem.Allocator, value: std.json.Value) !std.json.Value {
    return switch (value) {
        .null => .null,
        .bool => |b| .{ .bool = b },
        .integer => |i| .{ .integer = i },
        .float => |f| .{ .float = f },
        .number_string => |s| .{ .number_string = try allocator.dupe(u8, s) },
        .string => |s| .{ .string = try allocator.dupe(u8, s) },
        .array => |arr| blk: {
            var new_arr = std.json.Array.init(allocator);
            for (arr.items) |item| {
                try new_arr.append(try cloneJsonValue(allocator, item));
            }
            break :blk .{ .array = new_arr };
        },
        .object => |obj| blk: {
            var new_obj = std.json.ObjectMap.init(allocator);
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                try new_obj.put(
                    try allocator.dupe(u8, entry.key_ptr.*),
                    try cloneJsonValue(allocator, entry.value_ptr.*),
                );
            }
            break :blk .{ .object = new_obj };
        },
    };
}

test "cloneJsonValue - null" {
    const cloned = try cloneJsonValue(std.testing.allocator, .null);
    try std.testing.expect(cloned == .null);
}

test "cloneJsonValue - bool" {
    const cloned = try cloneJsonValue(std.testing.allocator, .{ .bool = true });
    try std.testing.expect(cloned == .bool);
    try std.testing.expect(cloned.bool == true);
}

test "cloneJsonValue - integer" {
    const cloned = try cloneJsonValue(std.testing.allocator, .{ .integer = 42 });
    try std.testing.expect(cloned == .integer);
    try std.testing.expectEqual(@as(i64, 42), cloned.integer);
}

test "cloneJsonValue - float" {
    const cloned = try cloneJsonValue(std.testing.allocator, .{ .float = 3.14 });
    try std.testing.expect(cloned == .float);
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), cloned.float, 0.001);
}

test "cloneJsonValue - string" {
    const original: std.json.Value = .{ .string = "hello" };
    const cloned = try cloneJsonValue(std.testing.allocator, original);
    defer if (cloned == .string) std.testing.allocator.free(cloned.string);

    try std.testing.expect(cloned == .string);
    try std.testing.expectEqualStrings("hello", cloned.string);
}

test "cloneJsonValue - array" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "[1,2,3]", .{});
    defer parsed.deinit();

    const cloned = try cloneJsonValue(std.testing.allocator, parsed.value);
    defer if (cloned == .array) {
        var arr = cloned.array;
        arr.deinit();
    };

    try std.testing.expect(cloned == .array);
    try std.testing.expectEqual(@as(usize, 3), cloned.array.items.len);
}
