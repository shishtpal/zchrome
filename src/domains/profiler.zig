const std = @import("std");
const json = @import("json");
const Session = @import("../core/session.zig").Session;

/// Profiler domain client for CPU profiling
pub const Profiler = struct {
    session: *Session,

    const Self = @This();

    pub fn init(session: *Session) Self {
        return .{ .session = session };
    }

    /// Enable profiler
    pub fn enable(self: *Self) !void {
        _ = try self.session.sendCommand("Profiler.enable", .{});
    }

    /// Disable profiler
    pub fn disable(self: *Self) !void {
        _ = try self.session.sendCommand("Profiler.disable", .{});
    }

    /// Set sampling interval in microseconds
    pub fn setSamplingInterval(self: *Self, interval: u32) !void {
        _ = try self.session.sendCommand("Profiler.setSamplingInterval", .{
            .interval = interval,
        });
    }

    /// Start CPU profiling
    pub fn start(self: *Self) !void {
        _ = try self.session.sendCommand("Profiler.start", .{});
    }

    /// Stop CPU profiling and return the profile
    pub fn stop(self: *Self, allocator: std.mem.Allocator) !Profile {
        const result = try self.session.sendCommand("Profiler.stop", .{});
        const profile_val = result.get("profile") orelse return error.MissingField;
        return try parseProfile(allocator, profile_val);
    }

    /// Start precise coverage collection
    pub fn startPreciseCoverage(self: *Self, opts: CoverageOptions) !f64 {
        const result = try self.session.sendCommand("Profiler.startPreciseCoverage", .{
            .callCount = opts.call_count,
            .detailed = opts.detailed,
            .allowTriggeredUpdates = opts.allow_triggered_updates,
        });
        return try result.getFloat("timestamp");
    }

    /// Stop coverage collection
    pub fn stopPreciseCoverage(self: *Self) !void {
        _ = try self.session.sendCommand("Profiler.stopPreciseCoverage", .{});
    }

    /// Take coverage snapshot
    pub fn takePreciseCoverage(self: *Self, allocator: std.mem.Allocator) !CoverageResult {
        const result = try self.session.sendCommand("Profiler.takePreciseCoverage", .{});

        const coverage_arr = try result.getArray("result");
        var scripts: std.ArrayList(ScriptCoverage) = .empty;
        errdefer scripts.deinit(allocator);

        for (coverage_arr) |sc| {
            try scripts.append(allocator, try parseScriptCoverage(allocator, sc));
        }

        return .{
            .result = try scripts.toOwnedSlice(allocator),
            .timestamp = try result.getFloat("timestamp"),
        };
    }

    /// Get best effort coverage
    pub fn getBestEffortCoverage(self: *Self, allocator: std.mem.Allocator) ![]ScriptCoverage {
        const result = try self.session.sendCommand("Profiler.getBestEffortCoverage", .{});

        const coverage_arr = try result.getArray("result");
        var scripts: std.ArrayList(ScriptCoverage) = .empty;
        errdefer scripts.deinit(allocator);

        for (coverage_arr) |sc| {
            try scripts.append(allocator, try parseScriptCoverage(allocator, sc));
        }

        return scripts.toOwnedSlice(allocator);
    }
};

/// Coverage options
pub const CoverageOptions = struct {
    call_count: ?bool = null,
    detailed: ?bool = null,
    allow_triggered_updates: ?bool = null,
};

/// CPU Profile
pub const Profile = struct {
    nodes: []ProfileNode,
    start_time: f64,
    end_time: f64,
    samples: ?[]i64 = null,
    time_deltas: ?[]i64 = null,

    pub fn deinit(self: *Profile, allocator: std.mem.Allocator) void {
        for (self.nodes) |*node| {
            node.deinit(allocator);
        }
        allocator.free(self.nodes);
        if (self.samples) |s| allocator.free(s);
        if (self.time_deltas) |t| allocator.free(t);
    }

    /// Serialize profile to Chrome DevTools compatible JSON
    pub fn toJson(self: *const Profile, allocator: std.mem.Allocator) ![]const u8 {
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(allocator);

        try buf.appendSlice(allocator, "{\"nodes\":[");

        for (self.nodes, 0..) |node, i| {
            if (i > 0) try buf.append(allocator, ',');
            try buf.appendSlice(allocator, "{\"id\":");
            const id_str = try std.fmt.allocPrint(allocator, "{}", .{node.id});
            defer allocator.free(id_str);
            try buf.appendSlice(allocator, id_str);

            try buf.appendSlice(allocator, ",\"callFrame\":{\"functionName\":\"");
            try buf.appendSlice(allocator, node.call_frame.function_name);
            try buf.appendSlice(allocator, "\",\"scriptId\":\"");
            try buf.appendSlice(allocator, node.call_frame.script_id);
            try buf.appendSlice(allocator, "\",\"url\":\"");
            try buf.appendSlice(allocator, node.call_frame.url);

            const line_str = try std.fmt.allocPrint(allocator, "\",\"lineNumber\":{},\"columnNumber\":{}}}", .{ node.call_frame.line_number, node.call_frame.column_number });
            defer allocator.free(line_str);
            try buf.appendSlice(allocator, line_str);

            if (node.children) |children| {
                try buf.appendSlice(allocator, ",\"children\":[");
                for (children, 0..) |child, j| {
                    if (j > 0) try buf.append(allocator, ',');
                    const child_str = try std.fmt.allocPrint(allocator, "{}", .{child});
                    defer allocator.free(child_str);
                    try buf.appendSlice(allocator, child_str);
                }
                try buf.append(allocator, ']');
            }

            try buf.append(allocator, '}');
        }

        const times_str = try std.fmt.allocPrint(allocator, "],\"startTime\":{d},\"endTime\":{d}", .{ self.start_time, self.end_time });
        defer allocator.free(times_str);
        try buf.appendSlice(allocator, times_str);

        if (self.samples) |samples| {
            try buf.appendSlice(allocator, ",\"samples\":[");
            for (samples, 0..) |s, i| {
                if (i > 0) try buf.append(allocator, ',');
                const s_str = try std.fmt.allocPrint(allocator, "{}", .{s});
                defer allocator.free(s_str);
                try buf.appendSlice(allocator, s_str);
            }
            try buf.append(allocator, ']');
        }

        if (self.time_deltas) |deltas| {
            try buf.appendSlice(allocator, ",\"timeDeltas\":[");
            for (deltas, 0..) |d, i| {
                if (i > 0) try buf.append(allocator, ',');
                const d_str = try std.fmt.allocPrint(allocator, "{}", .{d});
                defer allocator.free(d_str);
                try buf.appendSlice(allocator, d_str);
            }
            try buf.append(allocator, ']');
        }

        try buf.append(allocator, '}');

        return buf.toOwnedSlice(allocator);
    }
};

/// Profile node
pub const ProfileNode = struct {
    id: i64,
    call_frame: CallFrame,
    hit_count: ?i64 = null,
    children: ?[]i64 = null,
    deopt_reason: ?[]const u8 = null,
    position_ticks: ?[]PositionTickInfo = null,

    pub fn deinit(self: *ProfileNode, allocator: std.mem.Allocator) void {
        allocator.free(self.call_frame.function_name);
        allocator.free(self.call_frame.script_id);
        allocator.free(self.call_frame.url);
        if (self.children) |c| allocator.free(c);
        if (self.deopt_reason) |d| allocator.free(d);
        if (self.position_ticks) |p| allocator.free(p);
    }
};

/// Call frame
pub const CallFrame = struct {
    function_name: []const u8,
    script_id: []const u8,
    url: []const u8,
    line_number: i32,
    column_number: i32,
};

/// Position tick info
pub const PositionTickInfo = struct {
    line: i32,
    ticks: i64,
};

/// Script coverage
pub const ScriptCoverage = struct {
    script_id: []const u8,
    url: []const u8,
    functions: []FunctionCoverage,

    pub fn deinit(self: *ScriptCoverage, allocator: std.mem.Allocator) void {
        allocator.free(self.script_id);
        allocator.free(self.url);
        for (self.functions) |*f| {
            f.deinit(allocator);
        }
        allocator.free(self.functions);
    }
};

/// Function coverage
pub const FunctionCoverage = struct {
    function_name: []const u8,
    ranges: []CoverageRange,
    is_block_coverage: bool,

    pub fn deinit(self: *FunctionCoverage, allocator: std.mem.Allocator) void {
        allocator.free(self.function_name);
        allocator.free(self.ranges);
    }
};

/// Coverage range
pub const CoverageRange = struct {
    start_offset: i32,
    end_offset: i32,
    count: i64,
};

/// Coverage result
pub const CoverageResult = struct {
    result: []ScriptCoverage,
    timestamp: f64,
};

// ─── Parsing Functions ──────────────────────────────────────────────────────

fn parseProfile(allocator: std.mem.Allocator, obj: json.Value) !Profile {
    const nodes_arr = try obj.getArray("nodes");
    var nodes: std.ArrayList(ProfileNode) = .empty;
    errdefer nodes.deinit(allocator);

    for (nodes_arr) |n| {
        try nodes.append(allocator, try parseProfileNode(allocator, n));
    }

    var samples: ?[]i64 = null;
    if (obj.get("samples")) |s_arr| {
        if (s_arr == .array) {
            const items = s_arr.asArray() orelse return error.InvalidJson;
            var s_list: std.ArrayList(i64) = .empty;
            for (items) |s| {
                if (s == .integer) try s_list.append(allocator, s.integer);
            }
            samples = try s_list.toOwnedSlice(allocator);
        }
    }

    var time_deltas: ?[]i64 = null;
    if (obj.get("timeDeltas")) |t_arr| {
        if (t_arr == .array) {
            const items = t_arr.asArray() orelse return error.InvalidJson;
            var t_list: std.ArrayList(i64) = .empty;
            for (items) |t| {
                if (t == .integer) try t_list.append(allocator, t.integer);
            }
            time_deltas = try t_list.toOwnedSlice(allocator);
        }
    }

    return .{
        .nodes = try nodes.toOwnedSlice(allocator),
        .start_time = try obj.getFloat("startTime"),
        .end_time = try obj.getFloat("endTime"),
        .samples = samples,
        .time_deltas = time_deltas,
    };
}

fn parseProfileNode(allocator: std.mem.Allocator, obj: json.Value) !ProfileNode {
    const call_frame = obj.get("callFrame") orelse return error.MissingField;

    var children: ?[]i64 = null;
    if (obj.get("children")) |c_arr| {
        if (c_arr == .array) {
            const items = c_arr.asArray() orelse return error.InvalidJson;
            var c_list: std.ArrayList(i64) = .empty;
            for (items) |c| {
                if (c == .integer) try c_list.append(allocator, c.integer);
            }
            children = try c_list.toOwnedSlice(allocator);
        }
    }

    return .{
        .id = try obj.getInt("id"),
        .call_frame = .{
            .function_name = try allocator.dupe(u8, try call_frame.getString("functionName")),
            .script_id = try allocator.dupe(u8, try call_frame.getString("scriptId")),
            .url = try allocator.dupe(u8, try call_frame.getString("url")),
            .line_number = @intCast(try call_frame.getInt("lineNumber")),
            .column_number = @intCast(try call_frame.getInt("columnNumber")),
        },
        .hit_count = if (obj.get("hitCount")) |v| (if (v == .integer) v.integer else null) else null,
        .children = children,
        .deopt_reason = if (obj.get("deoptReason")) |v| (if (v == .string) try allocator.dupe(u8, v.string) else null) else null,
        .position_ticks = null, // TODO: parse if needed
    };
}

fn parseScriptCoverage(allocator: std.mem.Allocator, obj: json.Value) !ScriptCoverage {
    const functions_arr = try obj.getArray("functions");
    var functions: std.ArrayList(FunctionCoverage) = .empty;
    errdefer functions.deinit(allocator);

    for (functions_arr) |f| {
        try functions.append(allocator, try parseFunctionCoverage(allocator, f));
    }

    return .{
        .script_id = try allocator.dupe(u8, try obj.getString("scriptId")),
        .url = try allocator.dupe(u8, try obj.getString("url")),
        .functions = try functions.toOwnedSlice(allocator),
    };
}

fn parseFunctionCoverage(allocator: std.mem.Allocator, obj: json.Value) !FunctionCoverage {
    const ranges_arr = try obj.getArray("ranges");
    var ranges: std.ArrayList(CoverageRange) = .empty;
    errdefer ranges.deinit(allocator);

    for (ranges_arr) |r| {
        try ranges.append(allocator, .{
            .start_offset = @intCast(try r.getInt("startOffset")),
            .end_offset = @intCast(try r.getInt("endOffset")),
            .count = try r.getInt("count"),
        });
    }

    return .{
        .function_name = try allocator.dupe(u8, try obj.getString("functionName")),
        .ranges = try ranges.toOwnedSlice(allocator),
        .is_block_coverage = try obj.getBool("isBlockCoverage"),
    };
}
