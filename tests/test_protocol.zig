const std = @import("std");
const protocol = @import("cdp");
const fixtures = @import("helpers/fixtures.zig");

test "parseMessage - response with result" {
    const raw = "{\"id\":1,\"result\":{\"frameId\":\"F1\"}}";
    var msg = protocol.protocol.parseMessage(std.testing.allocator, raw) catch return;
    defer msg.deinit(std.testing.allocator);

    try std.testing.expect(msg == .response);
    try std.testing.expectEqual(@as(u64, 1), msg.response.id);
}

test "parseMessage - response with session id" {
    const raw = "{\"id\":2,\"result\":{},\"sessionId\":\"S1\"}";
    var msg = try protocol.protocol.parseMessage(std.testing.allocator, raw);
    defer msg.deinit(std.testing.allocator);

    try std.testing.expect(msg == .response);
    try std.testing.expectEqualStrings("S1", msg.response.session_id.?);
}

test "parseMessage - error response" {
    const raw = "{\"id\":3,\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}";
    var msg = try protocol.protocol.parseMessage(std.testing.allocator, raw);
    defer msg.deinit(std.testing.allocator);

    try std.testing.expect(msg == .error_response);
    try std.testing.expectEqual(@as(i64, -32601), msg.error_response.code);
    try std.testing.expectEqualStrings("Method not found", msg.error_response.message);
}

test "parseMessage - event" {
    const raw = fixtures.page_load_event_fired;
    var msg = try protocol.protocol.parseMessage(std.testing.allocator, raw);
    defer msg.deinit(std.testing.allocator);

    try std.testing.expect(msg == .event);
    try std.testing.expectEqualStrings("Page.loadEventFired", msg.event.method);
}

test "parseMessage - invalid json" {
    const result = protocol.protocol.parseMessage(std.testing.allocator, "not json{{{");
    try std.testing.expectError(error.InvalidMessage, result);
}

test "serializeCommand - with params" {
    const result = try protocol.protocol.serializeCommand(
        std.testing.allocator,
        1,
        "Page.navigate",
        .{ .url = "https://example.com" },
        null,
    );
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "\"id\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"method\":\"Page.navigate\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"params\":") != null);
}

test "serializeCommand - with session id" {
    const result = try protocol.protocol.serializeCommand(
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
    var alloc = protocol.protocol.IdAllocator.init();
    try std.testing.expectEqual(@as(u64, 1), alloc.next());
    try std.testing.expectEqual(@as(u64, 2), alloc.next());
    try std.testing.expectEqual(@as(u64, 3), alloc.next());
}
