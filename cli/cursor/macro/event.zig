//! Version 1: Raw Events (low-level, for backward compatibility)
//!
//! Event-based macros record raw mouse/keyboard events with coordinates
//! and timestamps. This format is lower-level and used for legacy macros.

const std = @import("std");
const json = @import("json");

const escapeString = json.escapeString;

/// Event types that can be recorded
pub const EventType = enum {
    mouseMove,
    mouseDown,
    mouseUp,
    mouseWheel,
    keyDown,
    keyUp,
};

/// Mouse button enum matching CDP
pub const MouseButton = enum {
    left,
    right,
    middle,
    none,

    pub fn fromInt(val: i64) MouseButton {
        return switch (val) {
            0 => .left,
            1 => .middle,
            2 => .right,
            else => .none,
        };
    }

    pub fn toInt(self: MouseButton) i32 {
        return switch (self) {
            .left => 0,
            .middle => 1,
            .right => 2,
            .none => 0,
        };
    }
};

/// A single recorded event
pub const MacroEvent = struct {
    event_type: EventType,
    timestamp: i64, // milliseconds since recording start
    // Mouse properties
    x: ?f64 = null,
    y: ?f64 = null,
    button: ?MouseButton = null,
    delta_x: ?f64 = null,
    delta_y: ?f64 = null,
    // Keyboard properties
    key: ?[]const u8 = null,
    code: ?[]const u8 = null,
    modifiers: i32 = 0,

    pub fn deinit(self: *MacroEvent, allocator: std.mem.Allocator) void {
        if (self.key) |k| allocator.free(k);
        if (self.code) |c| allocator.free(c);
    }
};

/// A complete macro recording
pub const Macro = struct {
    version: u32 = 1,
    recorded_at: ?[]const u8 = null,
    events: []MacroEvent,

    pub fn deinit(self: *Macro, allocator: std.mem.Allocator) void {
        for (self.events) |*e| {
            e.deinit(allocator);
        }
        allocator.free(self.events);
        if (self.recorded_at) |r| allocator.free(r);
    }
};

/// Load a macro from a JSON file
pub fn load(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !Macro {
    // Read file content
    const dir = std.Io.Dir.cwd();
    var file_buf: [256 * 1024]u8 = undefined; // 256KB buffer
    const content = dir.readFile(io, path, &file_buf) catch |err| {
        std.debug.print("Error reading macro file: {}\n", .{err});
        return err;
    };

    // Parse JSON
    var parsed = json.parse(allocator, content, .{}) catch |err| {
        std.debug.print("Error parsing macro JSON: {}\n", .{err});
        return err;
    };
    defer parsed.deinit(allocator);

    // Extract version
    var macro = Macro{
        .version = 1,
        .recorded_at = null,
        .events = &[_]MacroEvent{},
    };

    if (parsed.get("version")) |v| {
        if (v == .integer) macro.version = @intCast(v.integer);
    }

    if (parsed.get("recorded_at")) |v| {
        if (v == .string) macro.recorded_at = try allocator.dupe(u8, v.string);
    }

    // Parse events array
    if (parsed.get("events")) |events_val| {
        if (events_val == .array) {
            var events_list: std.ArrayList(MacroEvent) = .empty;
            errdefer {
                for (events_list.items) |*e| e.deinit(allocator);
                events_list.deinit(allocator);
            }

            for (events_val.array.items) |event_val| {
                if (event_val != .object) continue;

                const obj = event_val.object;
                var event = MacroEvent{
                    .event_type = .mouseMove,
                    .timestamp = 0,
                };

                // Parse event type
                if (obj.get("type")) |t| {
                    if (t == .string) {
                        if (std.mem.eql(u8, t.string, "mouseMove") or std.mem.eql(u8, t.string, "mousemove")) {
                            event.event_type = .mouseMove;
                        } else if (std.mem.eql(u8, t.string, "mouseDown") or std.mem.eql(u8, t.string, "mousedown")) {
                            event.event_type = .mouseDown;
                        } else if (std.mem.eql(u8, t.string, "mouseUp") or std.mem.eql(u8, t.string, "mouseup")) {
                            event.event_type = .mouseUp;
                        } else if (std.mem.eql(u8, t.string, "mouseWheel") or std.mem.eql(u8, t.string, "wheel")) {
                            event.event_type = .mouseWheel;
                        } else if (std.mem.eql(u8, t.string, "keyDown") or std.mem.eql(u8, t.string, "keydown")) {
                            event.event_type = .keyDown;
                        } else if (std.mem.eql(u8, t.string, "keyUp") or std.mem.eql(u8, t.string, "keyup")) {
                            event.event_type = .keyUp;
                        }
                    }
                }

                // Parse timestamp (with bounds checking)
                if (obj.get("timestamp")) |ts| {
                    if (ts == .integer) {
                        event.timestamp = ts.integer;
                    } else if (ts == .float) {
                        const f = ts.float;
                        // Bounds check: ensure float is in valid i64 range
                        if (f >= 0 and f <= @as(f64, @floatFromInt(std.math.maxInt(i64)))) {
                            event.timestamp = @intFromFloat(f);
                        } else {
                            // Clamp to valid range
                            event.timestamp = if (f < 0) 0 else std.math.maxInt(i64);
                        }
                    }
                }

                // Parse coordinates
                if (obj.get("x")) |x| {
                    if (x == .float) event.x = x.float;
                    if (x == .integer) event.x = @floatFromInt(x.integer);
                }
                if (obj.get("y")) |y| {
                    if (y == .float) event.y = y.float;
                    if (y == .integer) event.y = @floatFromInt(y.integer);
                }

                // Parse mouse button
                if (obj.get("button")) |b| {
                    if (b == .integer) {
                        event.button = MouseButton.fromInt(b.integer);
                    } else if (b == .string) {
                        if (std.mem.eql(u8, b.string, "left")) event.button = .left else if (std.mem.eql(u8, b.string, "right")) event.button = .right else if (std.mem.eql(u8, b.string, "middle")) event.button = .middle else event.button = .none;
                    }
                }

                // Parse wheel deltas
                if (obj.get("deltaX")) |dx| {
                    if (dx == .float) event.delta_x = dx.float;
                    if (dx == .integer) event.delta_x = @floatFromInt(dx.integer);
                }
                if (obj.get("deltaY")) |dy| {
                    if (dy == .float) event.delta_y = dy.float;
                    if (dy == .integer) event.delta_y = @floatFromInt(dy.integer);
                }

                // Parse key properties
                if (obj.get("key")) |k| {
                    if (k == .string) event.key = try allocator.dupe(u8, k.string);
                }
                if (obj.get("code")) |c| {
                    if (c == .string) event.code = try allocator.dupe(u8, c.string);
                }
                if (obj.get("modifiers")) |m| {
                    if (m == .integer) event.modifiers = @intCast(m.integer);
                }

                try events_list.append(allocator, event);
            }

            macro.events = try events_list.toOwnedSlice(allocator);
        }
    }

    return macro;
}

/// Save a macro to a JSON file
pub fn save(allocator: std.mem.Allocator, io: std.Io, path: []const u8, macro: *const Macro) !void {
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(allocator);

    try json_buf.appendSlice(allocator, "{\n");
    try json_buf.appendSlice(allocator, "  \"version\": ");
    const ver_str = try std.fmt.allocPrint(allocator, "{}", .{macro.version});
    defer allocator.free(ver_str);
    try json_buf.appendSlice(allocator, ver_str);

    if (macro.recorded_at) |ra| {
        const escaped_ra = try escapeString(allocator, ra);
        defer allocator.free(escaped_ra);
        try json_buf.appendSlice(allocator, ",\n  \"recorded_at\": \"");
        try json_buf.appendSlice(allocator, escaped_ra);
        try json_buf.appendSlice(allocator, "\"");
    }

    try json_buf.appendSlice(allocator, ",\n  \"events\": [\n");

    for (macro.events, 0..) |event, i| {
        if (i > 0) try json_buf.appendSlice(allocator, ",\n");
        try json_buf.appendSlice(allocator, "    {\n");

        // Event type
        const type_str = switch (event.event_type) {
            .mouseMove => "mouseMove",
            .mouseDown => "mouseDown",
            .mouseUp => "mouseUp",
            .mouseWheel => "mouseWheel",
            .keyDown => "keyDown",
            .keyUp => "keyUp",
        };
        try json_buf.appendSlice(allocator, "      \"type\": \"");
        try json_buf.appendSlice(allocator, type_str);
        try json_buf.appendSlice(allocator, "\"");

        // Timestamp
        const ts_str = try std.fmt.allocPrint(allocator, ",\n      \"timestamp\": {}", .{event.timestamp});
        defer allocator.free(ts_str);
        try json_buf.appendSlice(allocator, ts_str);

        // Coordinates (for mouse events)
        if (event.x) |x| {
            const x_str = try std.fmt.allocPrint(allocator, ",\n      \"x\": {d:.1}", .{x});
            defer allocator.free(x_str);
            try json_buf.appendSlice(allocator, x_str);
        }
        if (event.y) |y| {
            const y_str = try std.fmt.allocPrint(allocator, ",\n      \"y\": {d:.1}", .{y});
            defer allocator.free(y_str);
            try json_buf.appendSlice(allocator, y_str);
        }

        // Button (for mouse down/up)
        if (event.button) |b| {
            const btn_str = switch (b) {
                .left => "left",
                .right => "right",
                .middle => "middle",
                .none => "none",
            };
            try json_buf.appendSlice(allocator, ",\n      \"button\": \"");
            try json_buf.appendSlice(allocator, btn_str);
            try json_buf.appendSlice(allocator, "\"");
        }

        // Wheel deltas
        if (event.delta_x) |dx| {
            const dx_str = try std.fmt.allocPrint(allocator, ",\n      \"deltaX\": {d:.1}", .{dx});
            defer allocator.free(dx_str);
            try json_buf.appendSlice(allocator, dx_str);
        }
        if (event.delta_y) |dy| {
            const dy_str = try std.fmt.allocPrint(allocator, ",\n      \"deltaY\": {d:.1}", .{dy});
            defer allocator.free(dy_str);
            try json_buf.appendSlice(allocator, dy_str);
        }

        // Key properties
        if (event.key) |k| {
            const escaped_k = try escapeString(allocator, k);
            defer allocator.free(escaped_k);
            try json_buf.appendSlice(allocator, ",\n      \"key\": \"");
            try json_buf.appendSlice(allocator, escaped_k);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (event.code) |c| {
            const escaped_c = try escapeString(allocator, c);
            defer allocator.free(escaped_c);
            try json_buf.appendSlice(allocator, ",\n      \"code\": \"");
            try json_buf.appendSlice(allocator, escaped_c);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (event.modifiers != 0) {
            const mod_str = try std.fmt.allocPrint(allocator, ",\n      \"modifiers\": {}", .{event.modifiers});
            defer allocator.free(mod_str);
            try json_buf.appendSlice(allocator, mod_str);
        }

        try json_buf.appendSlice(allocator, "\n    }");
    }

    try json_buf.appendSlice(allocator, "\n  ]\n}\n");

    // Write to file
    const dir = std.Io.Dir.cwd();
    dir.writeFile(io, .{
        .sub_path = path,
        .data = json_buf.items,
    }) catch |err| {
        std.debug.print("Error writing macro file: {}\n", .{err});
        return err;
    };
}
