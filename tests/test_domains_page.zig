const std = @import("std");
const cdp = @import("cdp");
const json = cdp.json;

// Frame information
pub const Frame = struct {
    id: []const u8,
    parent_id: ?[]const u8 = null,
    loader_id: []const u8,
    name: ?[]const u8 = null,
    url: []const u8,
    security_origin: ?[]const u8 = null,
    mime_type: ?[]const u8 = null,

    pub fn deinit(self: *Frame, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        if (self.parent_id) |id| allocator.free(id);
        allocator.free(self.loader_id);
        if (self.name) |n| allocator.free(n);
        allocator.free(self.url);
        if (self.security_origin) |o| allocator.free(o);
        if (self.mime_type) |m| allocator.free(m);
    }
};

// Result of Page.navigate
pub const NavigateResult = struct {
    frame_id: []const u8,
    loader_id: ?[]const u8 = null,
    error_text: ?[]const u8 = null,

    pub fn deinit(self: *NavigateResult, allocator: std.mem.Allocator) void {
        allocator.free(self.frame_id);
        if (self.loader_id) |id| allocator.free(id);
        if (self.error_text) |t| allocator.free(t);
    }
};

// Screenshot format
pub const ScreenshotFormat = enum {
    jpeg,
    png,
    webp,
};

// NavigateResult Tests
test "NavigateResult - parse from JSON" {
    const json_str = "{\"frameId\":\"F1\",\"loaderId\":\"L1\"}";
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var result = NavigateResult{
        .frame_id = try std.testing.allocator.dupe(u8, try json.getString(parsed.value, "frameId")),
        .loader_id = if (parsed.value.object.get("loaderId")) |v|
            try std.testing.allocator.dupe(u8, v.string)
        else
            null,
        .error_text = null,
    };
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("F1", result.frame_id);
    try std.testing.expect(result.loader_id != null);
    try std.testing.expectEqualStrings("L1", result.loader_id.?);
}

test "NavigateResult - parse with error_text" {
    const json_str = "{\"frameId\":\"F1\",\"loaderId\":\"L1\",\"errorText\":\"net::ERR_NAME_NOT_RESOLVED\"}";
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var result = NavigateResult{
        .frame_id = try std.testing.allocator.dupe(u8, try json.getString(parsed.value, "frameId")),
        .loader_id = if (parsed.value.object.get("loaderId")) |v|
            try std.testing.allocator.dupe(u8, v.string)
        else
            null,
        .error_text = if (parsed.value.object.get("errorText")) |v|
            try std.testing.allocator.dupe(u8, v.string)
        else
            null,
    };
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.error_text != null);
    try std.testing.expectEqualStrings("net::ERR_NAME_NOT_RESOLVED", result.error_text.?);
}

test "NavigateResult - deinit frees all memory" {
    var result = NavigateResult{
        .frame_id = try std.testing.allocator.dupe(u8, "F1"),
        .loader_id = try std.testing.allocator.dupe(u8, "L1"),
        .error_text = try std.testing.allocator.dupe(u8, "error"),
    };
    result.deinit(std.testing.allocator);
}

// Frame Tests
test "Frame - parse from JSON with all fields" {
    const json_str =
        \\{
        \\  "id": "FRAME_001",
        \\  "parentId": "PARENT_001",
        \\  "loaderId": "LOADER_001",
        \\  "name": "myFrame",
        \\  "url": "https://example.com",
        \\  "securityOrigin": "https://example.com",
        \\  "mimeType": "text/html"
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var frame = Frame{
        .id = try std.testing.allocator.dupe(u8, try json.getString(parsed.value, "id")),
        .parent_id = if (parsed.value.object.get("parentId")) |v|
            try std.testing.allocator.dupe(u8, v.string)
        else
            null,
        .loader_id = try std.testing.allocator.dupe(u8, try json.getString(parsed.value, "loaderId")),
        .name = if (parsed.value.object.get("name")) |v|
            try std.testing.allocator.dupe(u8, v.string)
        else
            null,
        .url = try std.testing.allocator.dupe(u8, try json.getString(parsed.value, "url")),
        .security_origin = if (parsed.value.object.get("securityOrigin")) |v|
            try std.testing.allocator.dupe(u8, v.string)
        else
            null,
        .mime_type = if (parsed.value.object.get("mimeType")) |v|
            try std.testing.allocator.dupe(u8, v.string)
        else
            null,
    };
    defer frame.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("FRAME_001", frame.id);
    try std.testing.expect(frame.parent_id != null);
    try std.testing.expectEqualStrings("PARENT_001", frame.parent_id.?);
    try std.testing.expectEqualStrings("LOADER_001", frame.loader_id);
    try std.testing.expect(frame.name != null);
    try std.testing.expectEqualStrings("myFrame", frame.name.?);
    try std.testing.expectEqualStrings("https://example.com", frame.url);
}

test "Frame - parse with minimal fields" {
    const json_str =
        \\{
        \\  "id": "FRAME_001",
        \\  "loaderId": "LOADER_001",
        \\  "url": "https://example.com"
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var frame = Frame{
        .id = try std.testing.allocator.dupe(u8, try json.getString(parsed.value, "id")),
        .loader_id = try std.testing.allocator.dupe(u8, try json.getString(parsed.value, "loaderId")),
        .url = try std.testing.allocator.dupe(u8, try json.getString(parsed.value, "url")),
    };
    defer frame.deinit(std.testing.allocator);

    try std.testing.expect(frame.parent_id == null);
    try std.testing.expect(frame.name == null);
    try std.testing.expect(frame.security_origin == null);
    try std.testing.expect(frame.mime_type == null);
}

test "Frame - deinit frees all memory" {
    var frame = Frame{
        .id = try std.testing.allocator.dupe(u8, "F1"),
        .parent_id = try std.testing.allocator.dupe(u8, "P1"),
        .loader_id = try std.testing.allocator.dupe(u8, "L1"),
        .name = try std.testing.allocator.dupe(u8, "name"),
        .url = try std.testing.allocator.dupe(u8, "url"),
        .security_origin = try std.testing.allocator.dupe(u8, "origin"),
        .mime_type = try std.testing.allocator.dupe(u8, "text/html"),
    };
    frame.deinit(std.testing.allocator);
}

// ScreenshotFormat Tests
test "ScreenshotFormat - enum values" {
    try std.testing.expectEqual(@as(usize, 3), @typeInfo(ScreenshotFormat).@"enum".fields.len);
    try std.testing.expectEqual(ScreenshotFormat.jpeg, @as(ScreenshotFormat, @enumFromInt(0)));
    try std.testing.expectEqual(ScreenshotFormat.png, @as(ScreenshotFormat, @enumFromInt(1)));
    try std.testing.expectEqual(ScreenshotFormat.webp, @as(ScreenshotFormat, @enumFromInt(2)));
}
