const std = @import("std");
const cdp = @import("cdp");
const json = cdp.json;

// Target information
pub const TargetInfo = struct {
    target_id: []const u8,
    type: []const u8,
    title: []const u8,
    url: []const u8,
    attached: bool,
    opener_id: ?[]const u8 = null,
    browser_context_id: ?[]const u8 = null,

    pub fn deinit(self: *TargetInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.target_id);
        allocator.free(self.type);
        allocator.free(self.title);
        allocator.free(self.url);
        if (self.opener_id) |id| allocator.free(id);
        if (self.browser_context_id) |id| allocator.free(id);
    }
};

fn parseTargetInfo(allocator: std.mem.Allocator, obj: std.json.Value) !TargetInfo {
    return .{
        .target_id = try allocator.dupe(u8, try json.getString(obj, "targetId")),
        .type = try allocator.dupe(u8, try json.getString(obj, "type")),
        .title = try allocator.dupe(u8, try json.getString(obj, "title")),
        .url = try allocator.dupe(u8, try json.getString(obj, "url")),
        .attached = try json.getBool(obj, "attached"),
        .opener_id = if (obj.object.get("openerId")) |v| try allocator.dupe(u8, v.string) else null,
        .browser_context_id = if (obj.object.get("browserContextId")) |v| try allocator.dupe(u8, v.string) else null,
    };
}

// TargetInfo Parsing Tests
test "TargetInfo - parse from JSON with all fields" {
    const json_str =
        \\{
        \\  "targetId": "TARGET_001",
        \\  "type": "page",
        \\  "title": "Example Domain",
        \\  "url": "https://example.com",
        \\  "attached": true,
        \\  "openerId": "OPENER_001",
        \\  "browserContextId": "CTX_001"
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var info = try parseTargetInfo(std.testing.allocator, parsed.value);
    defer info.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("TARGET_001", info.target_id);
    try std.testing.expectEqualStrings("page", info.type);
    try std.testing.expectEqualStrings("Example Domain", info.title);
    try std.testing.expectEqualStrings("https://example.com", info.url);
    try std.testing.expect(info.attached);
    try std.testing.expect(info.opener_id != null);
    try std.testing.expectEqualStrings("OPENER_001", info.opener_id.?);
    try std.testing.expect(info.browser_context_id != null);
    try std.testing.expectEqualStrings("CTX_001", info.browser_context_id.?);
}

test "TargetInfo - parse with minimal fields" {
    const json_str =
        \\{
        \\  "targetId": "TARGET_001",
        \\  "type": "page",
        \\  "title": "New Tab",
        \\  "url": "chrome://newtab/",
        \\  "attached": false
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var info = try parseTargetInfo(std.testing.allocator, parsed.value);
    defer info.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("TARGET_001", info.target_id);
    try std.testing.expectEqualStrings("page", info.type);
    try std.testing.expect(!info.attached);
    try std.testing.expect(info.opener_id == null);
    try std.testing.expect(info.browser_context_id == null);
}

test "TargetInfo - deinit frees all memory" {
    var info = TargetInfo{
        .target_id = try std.testing.allocator.dupe(u8, "T1"),
        .type = try std.testing.allocator.dupe(u8, "page"),
        .title = try std.testing.allocator.dupe(u8, "Title"),
        .url = try std.testing.allocator.dupe(u8, "https://example.com"),
        .attached = true,
        .opener_id = try std.testing.allocator.dupe(u8, "O1"),
        .browser_context_id = try std.testing.allocator.dupe(u8, "C1"),
    };
    info.deinit(std.testing.allocator);
}

// attachToTarget Response Tests
test "attachToTarget - parse session ID from response" {
    const json_str = "{\"sessionId\":\"SESSION_001\"}";
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    const session_id = try json.getString(parsed.value, "sessionId");
    try std.testing.expectEqualStrings("SESSION_001", session_id);
}

// createTarget Response Tests
test "createTarget - parse target ID from response" {
    const json_str = "{\"targetId\":\"TARGET_NEW_001\"}";
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    const target_id = try json.getString(parsed.value, "targetId");
    try std.testing.expectEqualStrings("TARGET_NEW_001", target_id);
}

// closeTarget Response Tests
test "closeTarget - parse success from response" {
    const json_str = "{\"success\":true}";
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    const success = try json.getBool(parsed.value, "success");
    try std.testing.expect(success);
}
