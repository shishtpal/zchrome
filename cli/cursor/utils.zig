//! Utility functions for cursor module.

const std = @import("std");
const cdp = @import("cdp");

/// Escape a string for use in JavaScript (without adding quotes)
pub fn escapeForJs(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    for (s) |c| {
        switch (c) {
            '\'' => try result.appendSlice(allocator, "\\'"),
            '\\' => try result.appendSlice(allocator, "\\\\"),
            '\n' => try result.appendSlice(allocator, "\\n"),
            '\r' => try result.appendSlice(allocator, "\\r"),
            '\t' => try result.appendSlice(allocator, "\\t"),
            else => try result.append(allocator, c),
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Poll until JS expression returns true or timeout
pub fn pollUntilTrue(session: *cdp.Session, allocator: std.mem.Allocator, js_condition: []const u8, timeout_ms: u32) !bool {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    const poll_interval_ms: u32 = 250;
    const max_polls = (timeout_ms + poll_interval_ms - 1) / poll_interval_ms;
    var poll_count: u32 = 0;

    while (poll_count < max_polls) : (poll_count += 1) {
        var result = try runtime.evaluate(allocator, js_condition, .{ .return_by_value = true });
        defer result.deinit(allocator);

        if (result.asBool()) |b| {
            if (b) return true;
        }

        // Wait between polls
        waitForTime(poll_interval_ms);
    }
    return false;
}

/// Convert glob pattern to regex
pub fn globToRegex(allocator: std.mem.Allocator, pattern: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < pattern.len) {
        const c = pattern[i];
        if (c == '*') {
            if (i + 1 < pattern.len and pattern[i + 1] == '*') {
                try result.appendSlice(allocator, ".*");
                i += 2;
            } else {
                try result.appendSlice(allocator, "[^/]*");
                i += 1;
            }
        } else if (c == '.' or c == '?' or c == '+' or c == '^' or c == '$' or
            c == '{' or c == '}' or c == '(' or c == ')' or c == '|' or
            c == '[' or c == ']' or c == '\\')
        {
            try result.append(allocator, '\\');
            try result.append(allocator, c);
            i += 1;
        } else {
            try result.append(allocator, c);
            i += 1;
        }
    }
    return result.toOwnedSlice(allocator);
}

/// Wait for a specified time in milliseconds using spinloop
pub fn waitForTime(ms: u32) void {
    const iterations_per_second: u64 = 20_000_000;
    const total_iterations: u64 = (@as(u64, ms) * iterations_per_second) / 1000;
    var k: u64 = 0;
    while (k < total_iterations) : (k += 1) std.atomic.spinLoopHint();
}

/// Wait for user to press Enter
pub fn waitForEnter(io: std.Io) void {
    const stdin_file = std.Io.File.stdin();
    var buf: [32]u8 = undefined;
    var reader = stdin_file.readerStreaming(io, &buf);

    // Stop on either LF or CR so Enter works reliably across terminal modes.
    while (true) {
        const b = reader.interface.takeByte() catch break;
        if (b == '\n' or b == '\r') break;
    }
}

/// Match a string against a glob pattern with * wildcards.
/// The * matches any sequence of characters (including empty).
pub fn matchesGlobPattern(text: []const u8, pattern: []const u8) bool {
    // Handle edge cases
    if (pattern.len == 0) return text.len == 0;
    if (std.mem.eql(u8, pattern, "*")) return true;

    // Check if pattern has wildcards
    const has_wildcard = std.mem.indexOf(u8, pattern, "*") != null;
    if (!has_wildcard) return std.mem.eql(u8, text, pattern);

    // Split pattern by '*' and match each part in sequence
    var text_pos: usize = 0;
    var part_index: usize = 0;
    var iter = std.mem.splitSequence(u8, pattern, "*");

    while (iter.next()) |part| : (part_index += 1) {
        if (part.len == 0) continue; // Empty part (leading/trailing/consecutive *)

        // For first part, must match at start
        if (part_index == 0) {
            if (!std.mem.startsWith(u8, text, part)) return false;
            text_pos = part.len;
        } else {
            // Find part in remaining text
            if (std.mem.indexOf(u8, text[text_pos..], part)) |pos| {
                text_pos += pos + part.len;
            } else {
                return false;
            }
        }
    }

    // If pattern doesn't end with *, the text must end exactly where we are
    if (!std.mem.endsWith(u8, pattern, "*")) {
        // Check that remaining text is covered
        const last_part = blk: {
            var last: []const u8 = "";
            var it = std.mem.splitSequence(u8, pattern, "*");
            while (it.next()) |p| last = p;
            break :blk last;
        };
        if (last_part.len > 0) {
            return std.mem.endsWith(u8, text, last_part);
        }
    }

    return true;
}
