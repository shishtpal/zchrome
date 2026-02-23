//! Simple YAML serialization/deserialization for flat string maps.
//!
//! This module provides basic YAML support for web storage export/import.
//! Only handles flat `key: value` format (no nested structures, no arrays).
//! Keys and values are always double-quoted to safely handle colons, newlines,
//! and other special characters.

const std = @import("std");

/// Check if a file path has a YAML extension
pub fn isYamlPath(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".yaml") or std.mem.endsWith(u8, path, ".yml");
}

/// Write a double-quoted YAML scalar, escaping special characters.
fn writeQuotedYaml(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, s: []const u8) !void {
    try buf.append(allocator, '"');
    for (s) |c| {
        switch (c) {
            '"' => try buf.appendSlice(allocator, "\\\""),
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            '\t' => try buf.appendSlice(allocator, "\\t"),
            else => try buf.append(allocator, c),
        }
    }
    try buf.append(allocator, '"');
}

/// Unescape a double-quoted YAML scalar (strips surrounding quotes and processes escapes).
/// Returns a newly allocated string. Caller owns the memory.
fn unquoteYaml(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    // Strip surrounding quotes if present
    const inner = if (s.len >= 2 and s[0] == '"' and s[s.len - 1] == '"')
        s[1 .. s.len - 1]
    else
        s;

    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);
    var i: usize = 0;
    while (i < inner.len) {
        if (inner[i] == '\\' and i + 1 < inner.len) {
            switch (inner[i + 1]) {
                '"' => try buf.append(allocator, '"'),
                '\\' => try buf.append(allocator, '\\'),
                'n' => try buf.append(allocator, '\n'),
                'r' => try buf.append(allocator, '\r'),
                't' => try buf.append(allocator, '\t'),
                else => {
                    try buf.append(allocator, inner[i]);
                    try buf.append(allocator, inner[i + 1]);
                },
            }
            i += 2;
        } else {
            try buf.append(allocator, inner[i]);
            i += 1;
        }
    }
    return buf.toOwnedSlice(allocator);
}

/// Serialize a flat JSON object {"k":"v",...} to YAML key: value\n lines.
/// Keys and values are always double-quoted to safely handle colons, newlines,
/// and other special characters.
pub fn jsonToYaml(allocator: std.mem.Allocator, json_str: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);
    if (parsed.value == .object) {
        var it = parsed.value.object.iterator();
        while (it.next()) |entry| {
            const val = if (entry.value_ptr.* == .string) entry.value_ptr.*.string else "";
            try writeQuotedYaml(&buf, allocator, entry.key_ptr.*);
            try buf.appendSlice(allocator, ": ");
            try writeQuotedYaml(&buf, allocator, val);
            try buf.append(allocator, '\n');
        }
    }
    return buf.toOwnedSlice(allocator);
}

/// Parse simple YAML key: value lines into a JSON object string.
/// Supports both quoted ("key": "value") and unquoted (key: value) formats.
/// For unquoted values, the entire remainder after the first ": " is the value,
/// so values containing ": " are preserved correctly.
pub fn yamlToJson(allocator: std.mem.Allocator, yaml: []const u8) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);
    try buf.append(allocator, '{');
    var first = true;
    var lines = std.mem.splitScalar(u8, yaml, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Find the key separator: first ": " in the line.
        // For quoted keys like "foo: bar": value, we need to find the ": " after the closing quote.
        const sep_pos = blk: {
            if (trimmed.len > 0 and trimmed[0] == '"') {
                // Quoted key: find closing quote, then expect ": "
                var i: usize = 1;
                while (i < trimmed.len) {
                    if (trimmed[i] == '\\') {
                        i += 2; // skip escape sequence
                    } else if (trimmed[i] == '"') {
                        // Found closing quote; check for ": " immediately after
                        if (i + 2 < trimmed.len and trimmed[i + 1] == ':' and trimmed[i + 2] == ' ') {
                            break :blk i + 1; // position of ':'
                        }
                        break;
                    } else {
                        i += 1;
                    }
                }
                break :blk null;
            } else {
                // Unquoted key: find first ": "
                break :blk std.mem.indexOf(u8, trimmed, ": ");
            }
        } orelse continue;

        const raw_key = std.mem.trim(u8, trimmed[0..sep_pos], " \t");
        // Value is everything after ": " (position sep_pos + 2)
        const raw_val = if (sep_pos + 2 <= trimmed.len)
            std.mem.trim(u8, trimmed[sep_pos + 2 ..], " \t")
        else
            "";

        // Unescape key and value (handles both quoted and unquoted)
        const key = try unquoteYaml(allocator, raw_key);
        defer allocator.free(key);
        const val = try unquoteYaml(allocator, raw_val);
        defer allocator.free(val);

        if (!first) try buf.appendSlice(allocator, ",");
        first = false;

        // Write "key": "value" with proper JSON escaping
        try buf.append(allocator, '"');
        for (key) |c| {
            switch (c) {
                '"' => try buf.appendSlice(allocator, "\\\""),
                '\\' => try buf.appendSlice(allocator, "\\\\"),
                '\n' => try buf.appendSlice(allocator, "\\n"),
                '\r' => try buf.appendSlice(allocator, "\\r"),
                '\t' => try buf.appendSlice(allocator, "\\t"),
                else => try buf.append(allocator, c),
            }
        }
        try buf.appendSlice(allocator, "\":\"");
        for (val) |c| {
            switch (c) {
                '"' => try buf.appendSlice(allocator, "\\\""),
                '\\' => try buf.appendSlice(allocator, "\\\\"),
                '\n' => try buf.appendSlice(allocator, "\\n"),
                '\r' => try buf.appendSlice(allocator, "\\r"),
                '\t' => try buf.appendSlice(allocator, "\\t"),
                else => try buf.append(allocator, c),
            }
        }
        try buf.append(allocator, '"');
    }
    try buf.append(allocator, '}');
    return buf.toOwnedSlice(allocator);
}

test "jsonToYaml and yamlToJson round-trip" {
    const allocator = std.testing.allocator;
    const json = "{\"name\":\"value\",\"key2\":\"value2\"}";
    const yaml = try jsonToYaml(allocator, json);
    defer allocator.free(yaml);
    // Should contain the key-value pairs (quoted)
    try std.testing.expect(std.mem.indexOf(u8, yaml, "\"name\": \"value\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, yaml, "\"key2\": \"value2\"") != null);
    // Round-trip back to JSON
    const json2 = try yamlToJson(allocator, yaml);
    defer allocator.free(json2);
    // Parse both to compare structure
    const parsed1 = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed1.deinit();
    const parsed2 = try std.json.parseFromSlice(std.json.Value, allocator, json2, .{});
    defer parsed2.deinit();
    // Both should be objects with same keys and values
    try std.testing.expect(parsed1.value.object.count() == parsed2.value.object.count());
    var it = parsed1.value.object.iterator();
    while (it.next()) |entry| {
        const v2 = parsed2.value.object.get(entry.key_ptr.*) orelse
            return error.MissingKey;
        try std.testing.expectEqualStrings(entry.value_ptr.*.string, v2.string);
    }
}

test "jsonToYaml handles special characters in values" {
    const allocator = std.testing.allocator;
    // Value containing ": " (URL with port) — the classic truncation bug
    const json = "{\"url\":\"https://example.com: 8080\",\"css\":\"color: red\"}";
    const yaml = try jsonToYaml(allocator, json);
    defer allocator.free(yaml);
    const json2 = try yamlToJson(allocator, yaml);
    defer allocator.free(json2);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json2, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings(
        "https://example.com: 8080",
        parsed.value.object.get("url").?.string,
    );
    try std.testing.expectEqualStrings(
        "color: red",
        parsed.value.object.get("css").?.string,
    );
}

test "jsonToYaml handles newlines and quotes in values" {
    const allocator = std.testing.allocator;
    const json = "{\"msg\":\"line1\\nline2\",\"q\":\"say \\\"hello\\\"\"}";
    const yaml = try jsonToYaml(allocator, json);
    defer allocator.free(yaml);
    const json2 = try yamlToJson(allocator, yaml);
    defer allocator.free(json2);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json2, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("line1\nline2", parsed.value.object.get("msg").?.string);
    try std.testing.expectEqualStrings("say \"hello\"", parsed.value.object.get("q").?.string);
}
