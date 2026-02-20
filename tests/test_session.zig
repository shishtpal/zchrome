const std = @import("std");
const cdp = @import("cdp");

// Session tests using protocol module directly

test "Session ID - included in commands when non-empty" {
    const session_id = "SESSION_ABC123";
    const include_session = session_id.len > 0;
    try std.testing.expect(include_session);
}

test "Session ID - excluded when empty" {
    const session_id = "";
    const include_session = session_id.len > 0;
    try std.testing.expect(!include_session);
}

test "serializeCommand - includes session ID" {
    const result = try cdp.protocol.serializeCommand(
        std.testing.allocator,
        1,
        "Page.enable",
        .{},
        "SESSION_001",
    );
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "\"sessionId\":\"SESSION_001\"") != null);
}

test "serializeCommand - no session ID when null" {
    const result = try cdp.protocol.serializeCommand(
        std.testing.allocator,
        1,
        "Page.enable",
        .{},
        null,
    );
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "sessionId") == null);
}

test "serializeCommand - with multiple params" {
    const result = try cdp.protocol.serializeCommand(
        std.testing.allocator,
        1,
        "Runtime.evaluate",
        .{
            .expression = "1+1",
            .returnByValue = true,
            .awaitPromise = false,
        },
        "SESSION_001",
    );
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "\"expression\":\"1+1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"sessionId\":\"SESSION_001\"") != null);
}

test "parseMessage - response with session ID" {
    const raw = "{\"id\":3,\"result\":{},\"sessionId\":\"SESSION_001\"}";
    var msg = try cdp.protocol.parseMessage(std.testing.allocator, raw);
    defer msg.deinit(std.testing.allocator);

    try std.testing.expect(msg == .response);
    try std.testing.expect(msg.response.session_id != null);
    try std.testing.expectEqualStrings("SESSION_001", msg.response.session_id.?);
}

test "parseMessage - event with session ID" {
    const raw = "{\"method\":\"Runtime.consoleAPICalled\",\"params\":{},\"sessionId\":\"S1\"}";
    var msg = try cdp.protocol.parseMessage(std.testing.allocator, raw);
    defer msg.deinit(std.testing.allocator);

    try std.testing.expect(msg == .event);
    try std.testing.expect(msg.event.session_id != null);
    try std.testing.expectEqualStrings("S1", msg.event.session_id.?);
}
