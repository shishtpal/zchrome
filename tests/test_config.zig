const std = @import("std");

/// Config structure (mirrors cli/config.zig)
pub const Config = struct {
    chrome_path: ?[]const u8 = null,
    data_dir: ?[]const u8 = null,
    port: u16 = 9222,
    ws_url: ?[]const u8 = null,
    last_target: ?[]const u8 = null,

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        if (self.chrome_path) |p| allocator.free(p);
        if (self.data_dir) |d| allocator.free(d);
        if (self.ws_url) |u| allocator.free(u);
        if (self.last_target) |t| allocator.free(t);
        self.* = .{};
    }
};

/// Parse config from JSON value
fn parseConfigFromJson(allocator: std.mem.Allocator, value: std.json.Value) !Config {
    var config = Config{};

    if (value.object.get("chrome_path")) |v| {
        if (v == .string) config.chrome_path = try allocator.dupe(u8, v.string);
    }
    if (value.object.get("data_dir")) |v| {
        if (v == .string) config.data_dir = try allocator.dupe(u8, v.string);
    }
    if (value.object.get("port")) |v| {
        if (v == .integer) config.port = @intCast(v.integer);
    }
    if (value.object.get("ws_url")) |v| {
        if (v == .string) config.ws_url = try allocator.dupe(u8, v.string);
    }
    if (value.object.get("last_target")) |v| {
        if (v == .string) config.last_target = try allocator.dupe(u8, v.string);
    }

    return config;
}

/// Escape a string for JSON output
fn appendEscapedString(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, str: []const u8) !void {
    for (str) |c| {
        switch (c) {
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            '"' => try buf.appendSlice(allocator, "\\\""),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            '\t' => try buf.appendSlice(allocator, "\\t"),
            else => try buf.append(allocator, c),
        }
    }
}

/// Serialize config to JSON string
fn serializeConfig(allocator: std.mem.Allocator, config: Config) ![]const u8 {
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(allocator);

    try json_buf.appendSlice(allocator, "{\n");

    var first = true;

    if (config.chrome_path) |path| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"chrome_path\": \"");
        try appendEscapedString(&json_buf, allocator, path);
        try json_buf.appendSlice(allocator, "\"");
    }

    if (config.data_dir) |dir| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"data_dir\": \"");
        try appendEscapedString(&json_buf, allocator, dir);
        try json_buf.appendSlice(allocator, "\"");
    }

    if (!first) try json_buf.appendSlice(allocator, ",\n");
    first = false;
    const port_str = try std.fmt.allocPrint(allocator, "  \"port\": {}", .{config.port});
    defer allocator.free(port_str);
    try json_buf.appendSlice(allocator, port_str);

    if (config.ws_url) |url| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"ws_url\": \"");
        try appendEscapedString(&json_buf, allocator, url);
        try json_buf.appendSlice(allocator, "\"");
    }

    if (config.last_target) |target| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"last_target\": \"");
        try appendEscapedString(&json_buf, allocator, target);
        try json_buf.appendSlice(allocator, "\"");
    }

    try json_buf.appendSlice(allocator, "\n}\n");

    return json_buf.toOwnedSlice(allocator);
}

// ─── Config Parsing Tests ────────────────────────────────────────────────────

test "parseConfigFromJson - empty object" {
    const json_str = "{}";
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var config = try parseConfigFromJson(std.testing.allocator, parsed.value);
    defer config.deinit(std.testing.allocator);

    try std.testing.expect(config.chrome_path == null);
    try std.testing.expect(config.data_dir == null);
    try std.testing.expectEqual(@as(u16, 9222), config.port);
    try std.testing.expect(config.ws_url == null);
    try std.testing.expect(config.last_target == null);
}

test "parseConfigFromJson - all fields" {
    const json_str =
        \\{
        \\  "chrome_path": "/usr/bin/google-chrome",
        \\  "data_dir": "/tmp/chrome-profile",
        \\  "port": 9223,
        \\  "ws_url": "ws://localhost:9223/devtools/browser/abc123",
        \\  "last_target": "TARGET_001"
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var config = try parseConfigFromJson(std.testing.allocator, parsed.value);
    defer config.deinit(std.testing.allocator);

    try std.testing.expect(config.chrome_path != null);
    try std.testing.expectEqualStrings("/usr/bin/google-chrome", config.chrome_path.?);
    try std.testing.expect(config.data_dir != null);
    try std.testing.expectEqualStrings("/tmp/chrome-profile", config.data_dir.?);
    try std.testing.expectEqual(@as(u16, 9223), config.port);
    try std.testing.expect(config.ws_url != null);
    try std.testing.expectEqualStrings("ws://localhost:9223/devtools/browser/abc123", config.ws_url.?);
    try std.testing.expect(config.last_target != null);
    try std.testing.expectEqualStrings("TARGET_001", config.last_target.?);
}

test "parseConfigFromJson - partial fields" {
    const json_str =
        \\{
        \\  "port": 8080,
        \\  "ws_url": "ws://localhost:8080/devtools/browser/xyz"
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var config = try parseConfigFromJson(std.testing.allocator, parsed.value);
    defer config.deinit(std.testing.allocator);

    try std.testing.expect(config.chrome_path == null);
    try std.testing.expect(config.data_dir == null);
    try std.testing.expectEqual(@as(u16, 8080), config.port);
    try std.testing.expect(config.ws_url != null);
    try std.testing.expect(config.last_target == null);
}

test "parseConfigFromJson - ignores unknown fields" {
    const json_str =
        \\{
        \\  "port": 9222,
        \\  "unknown_field": "should be ignored"
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var config = try parseConfigFromJson(std.testing.allocator, parsed.value);
    defer config.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u16, 9222), config.port);
}

// ─── Config Serialization Tests ──────────────────────────────────────────────

test "serializeConfig - empty config" {
    const config = Config{};
    const result = try serializeConfig(std.testing.allocator, config);
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "\"port\": 9222") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "chrome_path") == null);
}

test "serializeConfig - all fields" {
    const config = Config{
        .chrome_path = "/usr/bin/chrome",
        .data_dir = "/tmp/profile",
        .port = 9223,
        .ws_url = "ws://localhost:9223/devtools/browser/test",
        .last_target = "TARGET_123",
    };
    const result = try serializeConfig(std.testing.allocator, config);
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "\"chrome_path\": \"/usr/bin/chrome\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"data_dir\": \"/tmp/profile\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"port\": 9223") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"ws_url\": \"ws://localhost:9223/devtools/browser/test\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"last_target\": \"TARGET_123\"") != null);
}

test "serializeConfig - escapes special characters in paths" {
    const config = Config{
        .chrome_path = "C:\\Program Files\\Chrome\\chrome.exe",
        .data_dir = "/tmp/data\ntest",
    };
    const result = try serializeConfig(std.testing.allocator, config);
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "C:\\\\Program Files\\\\Chrome\\\\chrome.exe") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "/tmp/data\\ntest") != null);
}

// ─── appendEscapedString Tests ───────────────────────────────────────────────

test "appendEscapedString - no special characters" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);

    try appendEscapedString(&buf, std.testing.allocator, "hello world");
    try std.testing.expectEqualStrings("hello world", buf.items);
}

test "appendEscapedString - with backslashes" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);

    try appendEscapedString(&buf, std.testing.allocator, "path\\to\\file");
    try std.testing.expectEqualStrings("path\\\\to\\\\file", buf.items);
}

test "appendEscapedString - with quotes" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);

    try appendEscapedString(&buf, std.testing.allocator, "say \"hello\"");
    try std.testing.expectEqualStrings("say \\\"hello\\\"", buf.items);
}

test "appendEscapedString - with newlines" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);

    try appendEscapedString(&buf, std.testing.allocator, "line1\nline2");
    try std.testing.expectEqualStrings("line1\\nline2", buf.items);
}

test "appendEscapedString - with carriage returns" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);

    try appendEscapedString(&buf, std.testing.allocator, "line1\r\nline2");
    try std.testing.expectEqualStrings("line1\\r\\nline2", buf.items);
}

test "appendEscapedString - with tabs" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);

    try appendEscapedString(&buf, std.testing.allocator, "col1\tcol2");
    try std.testing.expectEqualStrings("col1\\tcol2", buf.items);
}

test "appendEscapedString - all special characters" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);

    try appendEscapedString(&buf, std.testing.allocator, "a\"b\\c\nd\re\tf");
    try std.testing.expectEqualStrings("a\\\"b\\\\c\\nd\\re\\tf", buf.items);
}

// ─── Roundtrip Tests ─────────────────────────────────────────────────────────

test "config roundtrip - all fields" {
    const original = Config{
        .chrome_path = "/usr/bin/chrome",
        .data_dir = "/tmp/profile",
        .port = 9223,
        .ws_url = "ws://localhost:9223/test",
        .last_target = "TARGET_1",
    };

    // Serialize
    const json_str = try serializeConfig(std.testing.allocator, original);
    defer std.testing.allocator.free(json_str);

    // Parse back
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var config = try parseConfigFromJson(std.testing.allocator, parsed.value);
    defer config.deinit(std.testing.allocator);

    // Verify
    try std.testing.expectEqualStrings(original.chrome_path.?, config.chrome_path.?);
    try std.testing.expectEqualStrings(original.data_dir.?, config.data_dir.?);
    try std.testing.expectEqual(original.port, config.port);
    try std.testing.expectEqualStrings(original.ws_url.?, config.ws_url.?);
    try std.testing.expectEqualStrings(original.last_target.?, config.last_target.?);
}

test "config roundtrip - partial fields" {
    const original = Config{
        .port = 8080,
        .ws_url = "ws://localhost:8080/devtools/browser/abc",
    };

    // Serialize
    const json_str = try serializeConfig(std.testing.allocator, original);
    defer std.testing.allocator.free(json_str);

    // Parse back
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var config = try parseConfigFromJson(std.testing.allocator, parsed.value);
    defer config.deinit(std.testing.allocator);

    // Verify
    try std.testing.expect(config.chrome_path == null);
    try std.testing.expect(config.data_dir == null);
    try std.testing.expectEqual(original.port, config.port);
    try std.testing.expectEqualStrings(original.ws_url.?, config.ws_url.?);
    try std.testing.expect(config.last_target == null);
}

// ─── Config deinit Tests ─────────────────────────────────────────────────────

test "Config.deinit - frees all allocated memory" {
    var config = Config{
        .chrome_path = try std.testing.allocator.dupe(u8, "/path/to/chrome"),
        .data_dir = try std.testing.allocator.dupe(u8, "/tmp/profile"),
        .ws_url = try std.testing.allocator.dupe(u8, "ws://localhost:9222/test"),
        .last_target = try std.testing.allocator.dupe(u8, "TARGET_1"),
        .port = 9222,
    };

    config.deinit(std.testing.allocator);

    // After deinit, all fields should be null
    try std.testing.expect(config.chrome_path == null);
    try std.testing.expect(config.data_dir == null);
    try std.testing.expect(config.ws_url == null);
    try std.testing.expect(config.last_target == null);
}

test "Config.deinit - handles null fields" {
    var config = Config{};
    config.deinit(std.testing.allocator);
    // Should not crash
}
