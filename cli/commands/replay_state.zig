//! Replay state persistence for assert/retry functionality.
//!
//! Stores replay progress in replay-state.json within the session directory,
//! allowing for resume/retry after failures.

const std = @import("std");
const json = @import("json");
const session_mod = @import("../session.zig");

/// Replay state persisted between runs
pub const ReplayState = struct {
    macro_file: ?[]const u8 = null,
    last_action_index: ?usize = null, // Last action command (click/fill/etc) index
    last_attempted_index: ?usize = null, // Last command we tried to execute
    failed_at: ?[]const u8 = null, // ISO timestamp of failure
    failure_reason: ?[]const u8 = null,
    retry_count: u32 = 0,
    status: Status = .running,

    pub const Status = enum {
        running,
        paused,
        completed,
        failed,

        pub fn toString(self: Status) []const u8 {
            return switch (self) {
                .running => "running",
                .paused => "paused",
                .completed => "completed",
                .failed => "failed",
            };
        }

        pub fn fromString(s: []const u8) ?Status {
            if (std.mem.eql(u8, s, "running")) return .running;
            if (std.mem.eql(u8, s, "paused")) return .paused;
            if (std.mem.eql(u8, s, "completed")) return .completed;
            if (std.mem.eql(u8, s, "failed")) return .failed;
            return null;
        }
    };

    pub fn deinit(self: *ReplayState, allocator: std.mem.Allocator) void {
        if (self.macro_file) |m| allocator.free(m);
        if (self.failed_at) |f| allocator.free(f);
        if (self.failure_reason) |r| allocator.free(r);
        self.* = .{};
    }
};

/// Get replay state file path for a session
pub fn getStatePath(allocator: std.mem.Allocator, io: std.Io, session_name: []const u8) ![]const u8 {
    const session_dir = try session_mod.getSessionDir(allocator, io, session_name);
    defer allocator.free(session_dir);
    return std.fs.path.join(allocator, &.{ session_dir, "replay-state.json" });
}

/// Load replay state from session directory
pub fn loadState(allocator: std.mem.Allocator, io: std.Io, session_ctx: ?*const session_mod.SessionContext) ?ReplayState {
    const session_name = if (session_ctx) |ctx| ctx.name else "default";

    const state_path = getStatePath(allocator, io, session_name) catch return null;
    defer allocator.free(state_path);

    // Read file
    var file_buf: [16 * 1024]u8 = undefined;
    const dir = std.Io.Dir.cwd();
    const content = dir.readFile(io, state_path, &file_buf) catch return null;

    // Parse JSON
    var parsed = json.parse(allocator, content, .{}) catch return null;
    defer parsed.deinit(allocator);

    var state = ReplayState{};

    if (parsed.get("macro_file")) |v| {
        if (v == .string) state.macro_file = allocator.dupe(u8, v.string) catch null;
    }
    if (parsed.get("last_action_index")) |v| {
        if (v == .integer) state.last_action_index = @intCast(v.integer);
    }
    if (parsed.get("last_attempted_index")) |v| {
        if (v == .integer) state.last_attempted_index = @intCast(v.integer);
    }
    if (parsed.get("failed_at")) |v| {
        if (v == .string) state.failed_at = allocator.dupe(u8, v.string) catch null;
    }
    if (parsed.get("failure_reason")) |v| {
        if (v == .string) state.failure_reason = allocator.dupe(u8, v.string) catch null;
    }
    if (parsed.get("retry_count")) |v| {
        if (v == .integer) state.retry_count = @intCast(v.integer);
    }
    if (parsed.get("status")) |v| {
        if (v == .string) {
            if (ReplayState.Status.fromString(v.string)) |s| {
                state.status = s;
            }
        }
    }

    return state;
}

/// Save replay state to session directory
pub fn saveState(state: ReplayState, allocator: std.mem.Allocator, io: std.Io, session_ctx: ?*const session_mod.SessionContext) !void {
    const session_name = if (session_ctx) |ctx| ctx.name else "default";

    // Ensure session directory exists
    session_mod.createSession(allocator, io, session_name) catch {};

    const state_path = try getStatePath(allocator, io, session_name);
    defer allocator.free(state_path);

    // Build JSON
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(allocator);

    try json_buf.appendSlice(allocator, "{\n");

    var first = true;

    if (state.macro_file) |mf| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"macro_file\": \"");
        try appendEscaped(&json_buf, allocator, mf);
        try json_buf.appendSlice(allocator, "\"");
    }

    if (state.last_action_index) |idx| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        const s = try std.fmt.allocPrint(allocator, "  \"last_action_index\": {}", .{idx});
        defer allocator.free(s);
        try json_buf.appendSlice(allocator, s);
    }

    if (state.last_attempted_index) |idx| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        const s = try std.fmt.allocPrint(allocator, "  \"last_attempted_index\": {}", .{idx});
        defer allocator.free(s);
        try json_buf.appendSlice(allocator, s);
    }

    if (state.failed_at) |fa| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"failed_at\": \"");
        try appendEscaped(&json_buf, allocator, fa);
        try json_buf.appendSlice(allocator, "\"");
    }

    if (state.failure_reason) |fr| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"failure_reason\": \"");
        try appendEscaped(&json_buf, allocator, fr);
        try json_buf.appendSlice(allocator, "\"");
    }

    // Always write retry_count
    if (!first) try json_buf.appendSlice(allocator, ",\n");
    first = false;
    const rc_str = try std.fmt.allocPrint(allocator, "  \"retry_count\": {}", .{state.retry_count});
    defer allocator.free(rc_str);
    try json_buf.appendSlice(allocator, rc_str);

    // Always write status
    if (!first) try json_buf.appendSlice(allocator, ",\n");
    try json_buf.appendSlice(allocator, "  \"status\": \"");
    try json_buf.appendSlice(allocator, state.status.toString());
    try json_buf.appendSlice(allocator, "\"");

    try json_buf.appendSlice(allocator, "\n}\n");

    // Write file
    const parent_dir = std.fs.path.dirname(state_path);
    const filename = std.fs.path.basename(state_path);

    if (parent_dir) |pd| {
        const dir = std.Io.Dir.openDirAbsolute(io, pd, .{}) catch std.Io.Dir.cwd();
        try dir.writeFile(io, .{ .sub_path = filename, .data = json_buf.items });
    } else {
        const dir = std.Io.Dir.cwd();
        try dir.writeFile(io, .{ .sub_path = state_path, .data = json_buf.items });
    }
}

/// Clear replay state (delete the file)
pub fn clearState(allocator: std.mem.Allocator, io: std.Io, session_ctx: ?*const session_mod.SessionContext) !void {
    const session_name = if (session_ctx) |ctx| ctx.name else "default";

    const state_path = try getStatePath(allocator, io, session_name);
    defer allocator.free(state_path);

    const parent_dir = std.fs.path.dirname(state_path);
    const filename = std.fs.path.basename(state_path);

    if (parent_dir) |pd| {
        const dir = std.Io.Dir.openDirAbsolute(io, pd, .{}) catch return;
        dir.deleteFile(io, filename) catch {};
    } else {
        const dir = std.Io.Dir.cwd();
        dir.deleteFile(io, state_path) catch {};
    }
}

/// Escape a string for JSON
fn appendEscaped(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, str: []const u8) !void {
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
