//! Replay state persistence for assert/retry functionality.
//!
//! Stores replay progress in replay-state.json within the session directory,
//! allowing for resume/retry after failures.

const std = @import("std");
const json = @import("json");
const session_mod = @import("../session.zig");

/// Variable value - can be integer, string, array, or object (JSON)
pub const VarValue = union(enum) {
    int: i64,
    string: []const u8,
    array: []const u8, // JSON string representation of array
    object: []const u8, // JSON string representation of object

    pub fn deinit(self: *VarValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            .array => |a| allocator.free(a),
            .object => |o| allocator.free(o),
            .int => {},
        }
    }

    pub fn clone(self: VarValue, allocator: std.mem.Allocator) !VarValue {
        return switch (self) {
            .int => |i| .{ .int = i },
            .string => |s| .{ .string = try allocator.dupe(u8, s) },
            .array => |a| .{ .array = try allocator.dupe(u8, a) },
            .object => |o| .{ .object = try allocator.dupe(u8, o) },
        };
    }

    /// Get a field from a JSON object variable
    /// Returns the field value as a string, or null if not found/not an object
    pub fn getField(self: VarValue, allocator: std.mem.Allocator, field_path: []const u8) ?[]const u8 {
        const json_str = switch (self) {
            .object => |o| o,
            .array => return null, // Arrays don't have named fields
            .int => return null,
            .string => return null,
        };

        // Parse the JSON
        var parsed = json.parse(allocator, json_str, .{}) catch return null;
        defer parsed.deinit(allocator);

        // Navigate the path
        var current = parsed;
        var remaining = field_path;

        while (remaining.len > 0) {
            const dot_pos = std.mem.indexOf(u8, remaining, ".");
            const key = if (dot_pos) |pos| remaining[0..pos] else remaining;
            remaining = if (dot_pos) |pos| remaining[pos + 1 ..] else &[_]u8{};

            if (current != .object) return null;
            const next_val = current.object.get(key) orelse return null;
            current = next_val;
        }

        // Return string representation of the value
        return switch (current) {
            .string => |s| allocator.dupe(u8, s) catch null,
            .integer => |i| std.fmt.allocPrint(allocator, "{}", .{i}) catch null,
            .float => |f| std.fmt.allocPrint(allocator, "{d}", .{f}) catch null,
            .bool => |b| allocator.dupe(u8, if (b) "true" else "false") catch null,
            .null => allocator.dupe(u8, "null") catch null,
            else => null,
        };
    }

    /// Get the length of an array variable
    pub fn arrayLen(self: VarValue, allocator: std.mem.Allocator) ?usize {
        const json_str = switch (self) {
            .array => |a| a,
            else => return null,
        };

        var parsed = json.parse(allocator, json_str, .{}) catch return null;
        defer parsed.deinit(allocator);

        if (parsed != .array) return null;
        return parsed.array.items.len;
    }

    /// Get an item from an array variable by index
    /// Returns the item as a JSON string
    pub fn arrayGet(self: VarValue, allocator: std.mem.Allocator, index: usize) ?[]const u8 {
        const json_str = switch (self) {
            .array => |a| a,
            else => return null,
        };

        var parsed = json.parse(allocator, json_str, .{}) catch return null;
        defer parsed.deinit(allocator);

        if (parsed != .array) return null;
        if (index >= parsed.array.items.len) return null;

        // Serialize the item back to JSON
        return serializeValue(allocator, parsed.array.items[index]) catch null;
    }
};

/// Serialize a JSON value to string
fn serializeValue(allocator: std.mem.Allocator, value: json.Value) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);

    try serializeValueInto(allocator, &buf, value);
    return try buf.toOwnedSlice(allocator);
}

fn serializeValueInto(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), value: json.Value) !void {
    switch (value) {
        .null => try buf.appendSlice(allocator, "null"),
        .bool => |b| try buf.appendSlice(allocator, if (b) "true" else "false"),
        .integer => |i| {
            const s = try std.fmt.allocPrint(allocator, "{}", .{i});
            defer allocator.free(s);
            try buf.appendSlice(allocator, s);
        },
        .float => |f| {
            const s = try std.fmt.allocPrint(allocator, "{d}", .{f});
            defer allocator.free(s);
            try buf.appendSlice(allocator, s);
        },
        .string => |s| {
            try buf.append(allocator, '"');
            const escaped = try json.escapeString(allocator, s);
            defer allocator.free(escaped);
            try buf.appendSlice(allocator, escaped);
            try buf.append(allocator, '"');
        },
        .array => |arr| {
            try buf.append(allocator, '[');
            for (arr.items, 0..) |item, i| {
                if (i > 0) try buf.appendSlice(allocator, ", ");
                try serializeValueInto(allocator, buf, item);
            }
            try buf.append(allocator, ']');
        },
        .object => |obj| {
            try buf.append(allocator, '{');
            var first = true;
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                if (!first) try buf.appendSlice(allocator, ", ");
                first = false;
                try buf.append(allocator, '"');
                try buf.appendSlice(allocator, entry.key_ptr.*);
                try buf.appendSlice(allocator, "\": ");
                try serializeValueInto(allocator, buf, entry.value_ptr.*);
            }
            try buf.append(allocator, '}');
        },
    }
}

/// Replay state persisted between runs
pub const ReplayState = struct {
    macro_file: ?[]const u8 = null,
    last_action_index: ?usize = null, // Last action command (click/fill/etc) index
    last_attempted_index: ?usize = null, // Last command we tried to execute
    failed_at: ?[]const u8 = null, // ISO timestamp of failure
    failure_reason: ?[]const u8 = null,
    retry_count: u32 = 0,
    status: Status = .running,
    // Captured variables (keyed by variable name)
    variables: ?std.StringHashMap(VarValue) = null,

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
        if (self.variables) |*vars| {
            var iter = vars.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            vars.deinit();
        }
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
    // Parse variables
    if (parsed.get("variables")) |vars_obj| {
        if (vars_obj == .object) {
            var vars_map = std.StringHashMap(VarValue).init(allocator);
            var iter = vars_obj.object.iterator();
            while (iter.next()) |entry| {
                const key = allocator.dupe(u8, entry.key_ptr.*) catch continue;
                const val = entry.value_ptr.*;
                const var_val: VarValue = switch (val) {
                    .integer => |i| .{ .int = i },
                    .string => |s| .{ .string = allocator.dupe(u8, s) catch {
                        allocator.free(key);
                        continue;
                    } },
                    .float => |f| .{ .int = @intFromFloat(f) },
                    else => {
                        allocator.free(key);
                        continue;
                    },
                };
                vars_map.put(key, var_val) catch {
                    allocator.free(key);
                    switch (var_val) {
                        .string => |s| allocator.free(s),
                        else => {},
                    }
                    continue;
                };
            }
            if (vars_map.count() > 0) {
                state.variables = vars_map;
            } else {
                vars_map.deinit();
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

    // Write variables if any
    if (state.variables) |vars| {
        if (vars.count() > 0) {
            try json_buf.appendSlice(allocator, ",\n  \"variables\": {");
            var vars_first = true;
            var iter = vars.iterator();
            while (iter.next()) |entry| {
                if (!vars_first) try json_buf.appendSlice(allocator, ",");
                vars_first = false;
                try json_buf.appendSlice(allocator, "\n    \"");
                try appendEscaped(&json_buf, allocator, entry.key_ptr.*);
                try json_buf.appendSlice(allocator, "\": ");
                switch (entry.value_ptr.*) {
                    .int => |i| {
                        const i_str = try std.fmt.allocPrint(allocator, "{}", .{i});
                        defer allocator.free(i_str);
                        try json_buf.appendSlice(allocator, i_str);
                    },
                    .string => |s| {
                        try json_buf.appendSlice(allocator, "\"");
                        try appendEscaped(&json_buf, allocator, s);
                        try json_buf.appendSlice(allocator, "\"");
                    },
                    .array => |a| {
                        // Array is already JSON, write it directly
                        try json_buf.appendSlice(allocator, a);
                    },
                    .object => |o| {
                        // Object is already JSON, write it directly
                        try json_buf.appendSlice(allocator, o);
                    },
                }
            }
            try json_buf.appendSlice(allocator, "\n  }");
        }
    }

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

/// Escape a string for JSON and append to buffer
fn appendEscaped(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, str: []const u8) !void {
    const escaped = try json.escapeString(allocator, str);
    defer allocator.free(escaped);
    try buf.appendSlice(allocator, escaped);
}

// ============================================================================
// Foreach Execution Tracking & Reporting
// ============================================================================

/// Result of a single iteration in foreach
pub const IterationResult = struct {
    index: usize, // 0-based index in source array
    item_id: ?[]const u8 = null, // Auto-detected identifier (href, id, name, url)
    status: Status,
    failed_at_step: ?usize = null, // Which command failed (1-based)
    failed_action: ?[]const u8 = null, // Action name (navigate, click, etc.)
    error_message: ?[]const u8 = null,
    duration_ms: u64 = 0, // How long this iteration took

    pub const Status = enum {
        success,
        failed,
        skipped,

        pub fn toString(self: Status) []const u8 {
            return switch (self) {
                .success => "success",
                .failed => "failed",
                .skipped => "skipped",
            };
        }
    };

    pub fn deinit(self: *IterationResult, allocator: std.mem.Allocator) void {
        if (self.item_id) |id| allocator.free(id);
        if (self.failed_action) |a| allocator.free(a);
        if (self.error_message) |m| allocator.free(m);
    }
};

/// Report for a foreach execution
pub const ForeachReport = struct {
    source_var: ?[]const u8 = null, // The source variable name
    macro_file: ?[]const u8 = null, // The main macro file
    nested_macro: ?[]const u8 = null, // The per-item macro
    started_at: ?[]const u8 = null, // ISO timestamp
    completed_at: ?[]const u8 = null,
    total_items: usize = 0,
    succeeded: usize = 0,
    failed: usize = 0,
    skipped: usize = 0,
    results: std.ArrayListUnmanaged(IterationResult) = .{ .items = &.{}, .capacity = 0 },

    pub fn deinit(self: *ForeachReport, allocator: std.mem.Allocator) void {
        if (self.source_var) |s| allocator.free(s);
        if (self.macro_file) |m| allocator.free(m);
        if (self.nested_macro) |n| allocator.free(n);
        if (self.started_at) |s| allocator.free(s);
        if (self.completed_at) |c| allocator.free(c);
        for (self.results.items) |*r| {
            r.deinit(allocator);
        }
        self.results.deinit(allocator);
    }

    pub fn addResult(self: *ForeachReport, allocator: std.mem.Allocator, result: IterationResult) !void {
        try self.results.append(allocator, result);
        switch (result.status) {
            .success => self.succeeded += 1,
            .failed => self.failed += 1,
            .skipped => self.skipped += 1,
        }
    }
};

/// Extract an identifier from item JSON (auto-detect href, id, name, url)
pub fn extractItemId(allocator: std.mem.Allocator, item_json: []const u8) ?[]const u8 {
    const fields = [_][]const u8{ "href", "id", "name", "url" };

    var parsed = json.parse(allocator, item_json, .{}) catch return null;
    defer parsed.deinit(allocator);

    if (parsed != .object) return null;

    for (fields) |field| {
        if (parsed.object.get(field)) |val| {
            if (val == .string) return allocator.dupe(u8, val.string) catch null;
        }
    }
    return null;
}

/// Get current timestamp as string (unix seconds)
pub fn getTimestamp(allocator: std.mem.Allocator, io: std.Io) ?[]const u8 {
    const now = std.Io.Timestamp.now(io, .real);
    const secs = @divTrunc(now.nanoseconds, std.time.ns_per_s);
    return std.fmt.allocPrint(allocator, "{}", .{secs}) catch null;
}

/// Save foreach report to JSON file
pub fn saveForeachReport(report: *const ForeachReport, allocator: std.mem.Allocator, io: std.Io, output_path: []const u8) !void {
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(allocator);

    try json_buf.appendSlice(allocator, "{\n");

    // Source var
    if (report.source_var) |sv| {
        try json_buf.appendSlice(allocator, "  \"source\": \"");
        try appendEscaped(&json_buf, allocator, sv);
        try json_buf.appendSlice(allocator, "\",\n");
    }

    // Macro file
    if (report.macro_file) |mf| {
        try json_buf.appendSlice(allocator, "  \"macro_file\": \"");
        try appendEscaped(&json_buf, allocator, mf);
        try json_buf.appendSlice(allocator, "\",\n");
    }

    // Nested macro
    if (report.nested_macro) |nm| {
        try json_buf.appendSlice(allocator, "  \"nested_macro\": \"");
        try appendEscaped(&json_buf, allocator, nm);
        try json_buf.appendSlice(allocator, "\",\n");
    }

    // Timestamps
    if (report.started_at) |sa| {
        try json_buf.appendSlice(allocator, "  \"started_at\": \"");
        try appendEscaped(&json_buf, allocator, sa);
        try json_buf.appendSlice(allocator, "\",\n");
    }
    if (report.completed_at) |ca| {
        try json_buf.appendSlice(allocator, "  \"completed_at\": \"");
        try appendEscaped(&json_buf, allocator, ca);
        try json_buf.appendSlice(allocator, "\",\n");
    }

    // Summary stats
    const stats = try std.fmt.allocPrint(allocator,
        \\  "total": {},
        \\  "succeeded": {},
        \\  "failed": {},
        \\  "skipped": {},
        \\  "results": [
    , .{ report.total_items, report.succeeded, report.failed, report.skipped });
    defer allocator.free(stats);
    try json_buf.appendSlice(allocator, stats);

    // Results array
    for (report.results.items, 0..) |result, i| {
        if (i > 0) try json_buf.appendSlice(allocator, ",");
        try json_buf.appendSlice(allocator, "\n    {");

        // Index
        const idx_str = try std.fmt.allocPrint(allocator, "\"index\": {}", .{result.index});
        defer allocator.free(idx_str);
        try json_buf.appendSlice(allocator, idx_str);

        // Item ID
        if (result.item_id) |id| {
            try json_buf.appendSlice(allocator, ", \"item_id\": \"");
            try appendEscaped(&json_buf, allocator, id);
            try json_buf.appendSlice(allocator, "\"");
        }

        // Status
        try json_buf.appendSlice(allocator, ", \"status\": \"");
        try json_buf.appendSlice(allocator, result.status.toString());
        try json_buf.appendSlice(allocator, "\"");

        // Duration
        const dur_str = try std.fmt.allocPrint(allocator, ", \"duration_ms\": {}", .{result.duration_ms});
        defer allocator.free(dur_str);
        try json_buf.appendSlice(allocator, dur_str);

        // Error details (only for failed)
        if (result.status == .failed) {
            if (result.failed_at_step) |step| {
                const step_str = try std.fmt.allocPrint(allocator, ", \"failed_at_step\": {}", .{step});
                defer allocator.free(step_str);
                try json_buf.appendSlice(allocator, step_str);
            }
            if (result.failed_action) |action| {
                try json_buf.appendSlice(allocator, ", \"failed_action\": \"");
                try appendEscaped(&json_buf, allocator, action);
                try json_buf.appendSlice(allocator, "\"");
            }
            if (result.error_message) |msg| {
                try json_buf.appendSlice(allocator, ", \"error\": \"");
                try appendEscaped(&json_buf, allocator, msg);
                try json_buf.appendSlice(allocator, "\"");
            }
        }

        try json_buf.appendSlice(allocator, "}");
    }

    try json_buf.appendSlice(allocator, "\n  ]\n}\n");

    // Write file
    const dir = std.Io.Dir.cwd();
    try dir.writeFile(io, .{ .sub_path = output_path, .data = json_buf.items });
}
