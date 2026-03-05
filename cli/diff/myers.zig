//! Myers diff algorithm for computing minimal edit scripts.
//!
//! Time complexity: O(ND) where N = len(a) + len(b), D = edit distance
//! Based on: "An O(ND) Difference Algorithm and Its Variations" by Eugene W. Myers

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const DiffEditType = enum {
    equal,
    insert,
    delete,
};

pub const DiffEdit = struct {
    type: DiffEditType,
    line: []const u8,
};

pub const DiffResult = struct {
    edits: []DiffEdit,
    additions: usize,
    removals: usize,
    unchanged: usize,
    allocator: Allocator,

    pub fn deinit(self: *DiffResult) void {
        self.allocator.free(self.edits);
    }

    pub fn changed(self: DiffResult) bool {
        return self.additions > 0 or self.removals > 0;
    }
};

/// Myers diff algorithm for computing minimal edit script
/// Returns a list of edit operations to transform `a` into `b`
pub fn myersDiff(
    allocator: Allocator,
    a: []const []const u8,
    b: []const []const u8,
) !DiffResult {
    const n: i32 = @intCast(a.len);
    const m: i32 = @intCast(b.len);
    const max: usize = a.len + b.len;

    var result: std.ArrayListUnmanaged(DiffEdit) = .{};
    errdefer result.deinit(allocator);

    if (max == 0) {
        return DiffResult{
            .edits = try result.toOwnedSlice(allocator),
            .additions = 0,
            .removals = 0,
            .unchanged = 0,
            .allocator = allocator,
        };
    }

    // Quick check: if arrays are identical, skip diff
    if (a.len == b.len) {
        var identical = true;
        for (0..a.len) |i| {
            if (!std.mem.eql(u8, a[i], b[i])) {
                identical = false;
                break;
            }
        }
        if (identical) {
            for (a) |line| {
                try result.append(allocator, .{ .type = .equal, .line = line });
            }
            return DiffResult{
                .edits = try result.toOwnedSlice(allocator),
                .additions = 0,
                .removals = 0,
                .unchanged = a.len,
                .allocator = allocator,
            };
        }
    }

    // Initialize V array (diagonal tracking)
    const vSize = 2 * max + 1;
    const v = try allocator.alloc(i32, vSize);
    defer allocator.free(v);
    @memset(v, -1);

    // Trace stores snapshots of V at each edit distance level
    var trace: std.ArrayListUnmanaged([]i32) = .{};
    defer {
        for (trace.items) |snapshot| {
            allocator.free(snapshot);
        }
        trace.deinit(allocator);
    }

    v[max + 1] = 0;

    outer: for (0..max + 1) |d| {
        // Save snapshot of current V
        const snapshot = try allocator.dupe(i32, v);
        try trace.append(allocator, snapshot);

        var k: i32 = -@as(i32, @intCast(d));
        while (k <= @as(i32, @intCast(d))) : (k += 2) {
            const idx: usize = @intCast(k + @as(i32, @intCast(max)));

            var x: i32 = undefined;
            if (k == -@as(i32, @intCast(d)) or
                (k != @as(i32, @intCast(d)) and v[idx - 1] < v[idx + 1]))
            {
                x = v[idx + 1];
            } else {
                x = v[idx - 1] + 1;
            }

            var y = x - k;

            // Extend diagonal (match equal lines)
            while (x < n and y < m and
                std.mem.eql(u8, a[@intCast(x)], b[@intCast(y)]))
            {
                x += 1;
                y += 1;
            }

            v[idx] = x;

            // Found shortest edit script
            if (x >= n and y >= m) {
                try buildEditScript(allocator, &trace, a, b, max, &result);
                break :outer;
            }
        }
    }

    // Count statistics
    var additions: usize = 0;
    var removals: usize = 0;
    var unchanged: usize = 0;
    for (result.items) |edit| {
        switch (edit.type) {
            .equal => unchanged += 1,
            .insert => additions += 1,
            .delete => removals += 1,
        }
    }

    return DiffResult{
        .edits = try result.toOwnedSlice(allocator),
        .additions = additions,
        .removals = removals,
        .unchanged = unchanged,
        .allocator = allocator,
    };
}

fn buildEditScript(
    allocator: Allocator,
    trace: *std.ArrayListUnmanaged([]i32),
    a: []const []const u8,
    b: []const []const u8,
    max: usize,
    result: *std.ArrayListUnmanaged(DiffEdit),
) !void {
    var x: i32 = @intCast(a.len);
    var y: i32 = @intCast(b.len);

    var d: i32 = @intCast(trace.items.len - 1);
    while (d > 0) : (d -= 1) {
        const v = trace.items[@intCast(d)];
        const k = x - y;
        const idx: usize = @intCast(k + @as(i32, @intCast(max)));

        var prevK: i32 = undefined;
        if (k == -d or (k != d and v[idx - 1] < v[idx + 1])) {
            prevK = k + 1;
        } else {
            prevK = k - 1;
        }

        const prevIdx: usize = @intCast(prevK + @as(i32, @intCast(max)));
        const prevX = v[prevIdx];
        const prevY = prevX - prevK;

        // Process diagonal (equal lines)
        while (x > prevX and y > prevY) {
            x -= 1;
            y -= 1;
            try result.append(allocator, .{ .type = .equal, .line = a[@intCast(x)] });
        }

        if (x == prevX) {
            // Insertion
            y -= 1;
            try result.append(allocator, .{ .type = .insert, .line = b[@intCast(y)] });
        } else {
            // Deletion
            x -= 1;
            try result.append(allocator, .{ .type = .delete, .line = a[@intCast(x)] });
        }
    }

    // Process remaining diagonal at d=0
    while (x > 0 and y > 0) {
        x -= 1;
        y -= 1;
        try result.append(allocator, .{ .type = .equal, .line = a[@intCast(x)] });
    }

    // Reverse edits to get correct order
    std.mem.reverse(DiffEdit, result.items);
}

/// Split a string into lines
pub fn splitLines(allocator: Allocator, text: []const u8) ![]const []const u8 {
    var lines: std.ArrayListUnmanaged([]const u8) = .{};
    errdefer lines.deinit(allocator);

    var iter = std.mem.splitSequence(u8, text, "\n");
    while (iter.next()) |line| {
        // Handle Windows line endings
        const clean_line = if (line.len > 0 and line[line.len - 1] == '\r')
            line[0 .. line.len - 1]
        else
            line;
        try lines.append(allocator, clean_line);
    }

    return lines.toOwnedSlice(allocator);
}

// ─── Tests ──────────────────────────────────────────────────────────────────

test "myers diff - identical strings" {
    const allocator = std.testing.allocator;

    const a = [_][]const u8{ "hello", "world" };
    const b = [_][]const u8{ "hello", "world" };

    var result = try myersDiff(allocator, &a, &b);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.edits.len);
    try std.testing.expectEqual(@as(usize, 0), result.additions);
    try std.testing.expectEqual(@as(usize, 0), result.removals);
    try std.testing.expectEqual(@as(usize, 2), result.unchanged);
    try std.testing.expect(!result.changed());
}

test "myers diff - simple insertion" {
    const allocator = std.testing.allocator;

    const a = [_][]const u8{"hello"};
    const b = [_][]const u8{ "hello", "world" };

    var result = try myersDiff(allocator, &a, &b);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.edits.len);
    try std.testing.expectEqual(@as(usize, 1), result.additions);
    try std.testing.expectEqual(@as(usize, 0), result.removals);
    try std.testing.expectEqual(@as(usize, 1), result.unchanged);
    try std.testing.expect(result.changed());
}

test "myers diff - simple deletion" {
    const allocator = std.testing.allocator;

    const a = [_][]const u8{ "hello", "world" };
    const b = [_][]const u8{"hello"};

    var result = try myersDiff(allocator, &a, &b);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.edits.len);
    try std.testing.expectEqual(@as(usize, 0), result.additions);
    try std.testing.expectEqual(@as(usize, 1), result.removals);
    try std.testing.expectEqual(@as(usize, 1), result.unchanged);
    try std.testing.expect(result.changed());
}

test "myers diff - replacement" {
    const allocator = std.testing.allocator;

    const a = [_][]const u8{ "hello", "world" };
    const b = [_][]const u8{ "hello", "zig" };

    var result = try myersDiff(allocator, &a, &b);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.edits.len);
    try std.testing.expectEqual(@as(usize, 1), result.additions);
    try std.testing.expectEqual(@as(usize, 1), result.removals);
    try std.testing.expectEqual(@as(usize, 1), result.unchanged);
    try std.testing.expect(result.changed());
}

test "myers diff - empty arrays" {
    const allocator = std.testing.allocator;

    const a = [_][]const u8{};
    const b = [_][]const u8{};

    var result = try myersDiff(allocator, &a, &b);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), result.edits.len);
    try std.testing.expect(!result.changed());
}

test "splitLines - unix style" {
    const allocator = std.testing.allocator;

    const text = "line1\nline2\nline3";
    const lines = try splitLines(allocator, text);
    defer allocator.free(lines);

    try std.testing.expectEqual(@as(usize, 3), lines.len);
    try std.testing.expectEqualStrings("line1", lines[0]);
    try std.testing.expectEqualStrings("line2", lines[1]);
    try std.testing.expectEqualStrings("line3", lines[2]);
}

test "splitLines - windows style" {
    const allocator = std.testing.allocator;

    const text = "line1\r\nline2\r\nline3";
    const lines = try splitLines(allocator, text);
    defer allocator.free(lines);

    try std.testing.expectEqual(@as(usize, 3), lines.len);
    try std.testing.expectEqualStrings("line1", lines[0]);
    try std.testing.expectEqualStrings("line2", lines[1]);
    try std.testing.expectEqualStrings("line3", lines[2]);
}
