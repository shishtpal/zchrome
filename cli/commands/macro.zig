//! Macro recording and playback data structures.
//!
//! This module provides types for representing recorded mouse/keyboard events
//! and semantic commands, with functions for loading/saving macros to JSON files.
//!
//! Two formats are supported:
//! - Version 1: Raw events (mouseMove, keyDown, etc.) - low-level, coordinate-based
//! - Version 2: Semantic commands (click, fill, press, etc.) - high-level, selector-based

const std = @import("std");
const json = @import("json");

const escapeString = json.escapeString;

// ============================================================================
// Version 2: Semantic Commands (high-level, human-readable)
// ============================================================================

/// Action types for semantic command recording
pub const ActionType = enum {
    click,
    dblclick,
    fill,
    check,
    uncheck,
    select,
    multiselect,
    press,
    scroll,
    hover,
    navigate,
    wait,
    assert,
    extract,
    dialog,

    pub fn toString(self: ActionType) []const u8 {
        return switch (self) {
            .click => "click",
            .dblclick => "dblclick",
            .fill => "fill",
            .check => "check",
            .uncheck => "uncheck",
            .select => "select",
            .multiselect => "multiselect",
            .press => "press",
            .scroll => "scroll",
            .hover => "hover",
            .navigate => "navigate",
            .wait => "wait",
            .assert => "assert",
            .extract => "extract",
            .dialog => "dialog",
        };
    }

    pub fn fromString(s: []const u8) ?ActionType {
        if (std.mem.eql(u8, s, "click")) return .click;
        if (std.mem.eql(u8, s, "dblclick")) return .dblclick;
        if (std.mem.eql(u8, s, "fill")) return .fill;
        if (std.mem.eql(u8, s, "check")) return .check;
        if (std.mem.eql(u8, s, "uncheck")) return .uncheck;
        if (std.mem.eql(u8, s, "select")) return .select;
        if (std.mem.eql(u8, s, "multiselect")) return .multiselect;
        if (std.mem.eql(u8, s, "press")) return .press;
        if (std.mem.eql(u8, s, "scroll")) return .scroll;
        if (std.mem.eql(u8, s, "hover")) return .hover;
        if (std.mem.eql(u8, s, "navigate")) return .navigate;
        if (std.mem.eql(u8, s, "wait")) return .wait;
        if (std.mem.eql(u8, s, "assert")) return .assert;
        if (std.mem.eql(u8, s, "extract")) return .extract;
        if (std.mem.eql(u8, s, "dialog")) return .dialog;
        return null;
    }

    /// Returns true if this action is a "real" action command (not press/scroll/wait/assert/extract/dialog)
    /// Used to determine where to retry from on assertion failure
    pub fn isActionCommand(self: ActionType) bool {
        return switch (self) {
            .click, .dblclick, .fill, .check, .uncheck, .select, .multiselect, .hover, .navigate => true,
            .press, .scroll, .wait, .assert, .extract, .dialog => false,
        };
    }
};

/// A semantic command (click, fill, press, assert, dialog, etc.)
pub const MacroCommand = struct {
    action: ActionType,
    selector: ?[]const u8 = null, // CSS selector for element (primary)
    selectors: ?[][]const u8 = null, // Fallback selectors for dynamic pages
    value: ?[]const u8 = null, // Text value for fill/select, URL for navigate, prompt text for dialog
    key: ?[]const u8 = null, // Key name for press
    scroll_x: ?i32 = null, // Scroll delta X
    scroll_y: ?i32 = null, // Scroll delta Y
    // Assert-specific fields
    attribute: ?[]const u8 = null, // Attribute name to check (for assert)
    contains: ?[]const u8 = null, // Substring to find in attribute/text (for assert)
    url: ?[]const u8 = null, // URL pattern to match (for assert)
    text: ?[]const u8 = null, // Text to find on page (for assert), or expected dialog message (for dialog)
    timeout: ?u32 = null, // Timeout in ms (default: 5000)
    fallback: ?[]const u8 = null, // Fallback JSON file on assertion failure
    // Extract-specific fields
    mode: ?[]const u8 = null, // Extraction mode: dom, text, html, attrs, table, form
    output: ?[]const u8 = null, // Output file path for extract
    extract_all: ?bool = null, // Use querySelectorAll for extract
    // Snapshot assertion field
    snapshot: ?[]const u8 = null, // Expected JSON file for snapshot comparison
    // Dialog-specific fields
    accept: ?bool = null, // For dialog: true=accept (OK), false=dismiss (Cancel)

    pub fn deinit(self: *MacroCommand, allocator: std.mem.Allocator) void {
        if (self.selector) |s| allocator.free(s);
        if (self.selectors) |sels| {
            for (sels) |sel| allocator.free(sel);
            allocator.free(sels);
        }
        if (self.value) |v| allocator.free(v);
        if (self.key) |k| allocator.free(k);
        if (self.attribute) |a| allocator.free(a);
        if (self.contains) |c| allocator.free(c);
        if (self.url) |u| allocator.free(u);
        if (self.text) |t| allocator.free(t);
        if (self.fallback) |f| allocator.free(f);
        if (self.mode) |m| allocator.free(m);
        if (self.output) |o| allocator.free(o);
        if (self.snapshot) |sn| allocator.free(sn);
    }

    pub fn clone(self: *const MacroCommand, allocator: std.mem.Allocator) !MacroCommand {
        var cloned_selectors: ?[][]const u8 = null;
        if (self.selectors) |sels| {
            var new_sels = try allocator.alloc([]const u8, sels.len);
            for (sels, 0..) |sel, i| {
                new_sels[i] = try allocator.dupe(u8, sel);
            }
            cloned_selectors = new_sels;
        }
        return .{
            .action = self.action,
            .selector = if (self.selector) |s| try allocator.dupe(u8, s) else null,
            .selectors = cloned_selectors,
            .value = if (self.value) |v| try allocator.dupe(u8, v) else null,
            .key = if (self.key) |k| try allocator.dupe(u8, k) else null,
            .scroll_x = self.scroll_x,
            .scroll_y = self.scroll_y,
            .attribute = if (self.attribute) |a| try allocator.dupe(u8, a) else null,
            .contains = if (self.contains) |c| try allocator.dupe(u8, c) else null,
            .url = if (self.url) |u| try allocator.dupe(u8, u) else null,
            .text = if (self.text) |t| try allocator.dupe(u8, t) else null,
            .timeout = self.timeout,
            .fallback = if (self.fallback) |f| try allocator.dupe(u8, f) else null,
            .mode = if (self.mode) |m| try allocator.dupe(u8, m) else null,
            .output = if (self.output) |o| try allocator.dupe(u8, o) else null,
            .extract_all = self.extract_all,
            .snapshot = if (self.snapshot) |sn| try allocator.dupe(u8, sn) else null,
            .accept = self.accept,
        };
    }
};

/// Command-based macro (version 2)
pub const CommandMacro = struct {
    version: u32 = 2,
    commands: []MacroCommand,

    pub fn deinit(self: *CommandMacro, allocator: std.mem.Allocator) void {
        for (self.commands) |*c| {
            c.deinit(allocator);
        }
        allocator.free(self.commands);
    }
};

/// Save a command macro to JSON file
pub fn saveCommandMacro(allocator: std.mem.Allocator, io: std.Io, path: []const u8, macro: *const CommandMacro) !void {
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(allocator);

    try json_buf.appendSlice(allocator, "{\n");
    try json_buf.appendSlice(allocator, "  \"version\": 2,\n");
    try json_buf.appendSlice(allocator, "  \"commands\": [\n");

    for (macro.commands, 0..) |cmd, i| {
        if (i > 0) try json_buf.appendSlice(allocator, ",\n");
        try json_buf.appendSlice(allocator, "    {");

        // Action
        try json_buf.appendSlice(allocator, "\"action\": \"");
        try json_buf.appendSlice(allocator, cmd.action.toString());
        try json_buf.appendSlice(allocator, "\"");

        // Selector (primary)
        if (cmd.selector) |sel| {
            const escaped = try escapeString(allocator, sel);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"selector\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }

        // Selectors (fallback list)
        if (cmd.selectors) |sels| {
            try json_buf.appendSlice(allocator, ", \"selectors\": [");
            for (sels, 0..) |sel, j| {
                if (j > 0) try json_buf.appendSlice(allocator, ", ");
                const escaped = try escapeString(allocator, sel);
                defer allocator.free(escaped);
                try json_buf.appendSlice(allocator, "\"");
                try json_buf.appendSlice(allocator, escaped);
                try json_buf.appendSlice(allocator, "\"");
            }
            try json_buf.appendSlice(allocator, "]");
        }

        // Value
        if (cmd.value) |val| {
            const escaped = try escapeString(allocator, val);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"value\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }

        // Key
        if (cmd.key) |key| {
            const escaped = try escapeString(allocator, key);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"key\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }

        // Scroll
        if (cmd.scroll_x) |sx| {
            const sx_str = try std.fmt.allocPrint(allocator, ", \"scrollX\": {}", .{sx});
            defer allocator.free(sx_str);
            try json_buf.appendSlice(allocator, sx_str);
        }
        if (cmd.scroll_y) |sy| {
            const sy_str = try std.fmt.allocPrint(allocator, ", \"scrollY\": {}", .{sy});
            defer allocator.free(sy_str);
            try json_buf.appendSlice(allocator, sy_str);
        }

        // Assert-specific fields
        if (cmd.attribute) |attr| {
            const escaped = try escapeString(allocator, attr);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"attribute\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.contains) |cont| {
            const escaped = try escapeString(allocator, cont);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"contains\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.url) |url_val| {
            const escaped = try escapeString(allocator, url_val);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"url\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.text) |txt| {
            const escaped = try escapeString(allocator, txt);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"text\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.timeout) |to| {
            const to_str = try std.fmt.allocPrint(allocator, ", \"timeout\": {}", .{to});
            defer allocator.free(to_str);
            try json_buf.appendSlice(allocator, to_str);
        }
        if (cmd.fallback) |fb| {
            const escaped = try escapeString(allocator, fb);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"fallback\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }

        // Extract-specific fields
        if (cmd.mode) |m| {
            const escaped = try escapeString(allocator, m);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"mode\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.output) |o| {
            const escaped = try escapeString(allocator, o);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"output\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.extract_all) |ea| {
            try json_buf.appendSlice(allocator, if (ea) ", \"extract_all\": true" else ", \"extract_all\": false");
        }
        // Snapshot assertion field
        if (cmd.snapshot) |sn| {
            const escaped = try escapeString(allocator, sn);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"snapshot\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        // Dialog-specific field
        if (cmd.accept) |ac| {
            try json_buf.appendSlice(allocator, if (ac) ", \"accept\": true" else ", \"accept\": false");
        }

        try json_buf.appendSlice(allocator, "}");
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

/// Load a command macro from JSON file
pub fn loadCommandMacro(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !CommandMacro {
    const dir = std.Io.Dir.cwd();
    var file_buf: [256 * 1024]u8 = undefined;
    const content = dir.readFile(io, path, &file_buf) catch |err| {
        std.debug.print("Error reading macro file: {}\n", .{err});
        return err;
    };

    var parsed = json.parse(allocator, content, .{}) catch |err| {
        std.debug.print("Error parsing macro JSON: {}\n", .{err});
        return err;
    };
    defer parsed.deinit(allocator);

    var macro = CommandMacro{
        .version = 2,
        .commands = &[_]MacroCommand{},
    };

    if (parsed.get("commands")) |cmds_val| {
        if (cmds_val == .array) {
            var cmds_list: std.ArrayList(MacroCommand) = .empty;
            errdefer {
                for (cmds_list.items) |*c| c.deinit(allocator);
                cmds_list.deinit(allocator);
            }

            for (cmds_val.array.items) |cmd_val| {
                if (cmd_val != .object) continue;
                const obj = cmd_val.object;

                var cmd = MacroCommand{ .action = .click };

                if (obj.get("action")) |a| {
                    if (a == .string) {
                        if (ActionType.fromString(a.string)) |action| {
                            cmd.action = action;
                        }
                    }
                }

                if (obj.get("selector")) |s| {
                    if (s == .string) cmd.selector = try allocator.dupe(u8, s.string);
                }
                if (obj.get("selectors")) |sels_val| {
                    if (sels_val == .array) {
                        var sels_list: std.ArrayList([]const u8) = .empty;
                        errdefer {
                            for (sels_list.items) |sel| allocator.free(sel);
                            sels_list.deinit(allocator);
                        }
                        for (sels_val.array.items) |sel_val| {
                            if (sel_val == .string) {
                                try sels_list.append(allocator, try allocator.dupe(u8, sel_val.string));
                            }
                        }
                        if (sels_list.items.len > 0) {
                            cmd.selectors = try sels_list.toOwnedSlice(allocator);
                        } else {
                            sels_list.deinit(allocator);
                        }
                    }
                }
                if (obj.get("value")) |v| {
                    if (v == .string) {
                        cmd.value = try allocator.dupe(u8, v.string);
                    } else if (v == .integer) {
                        // Handle numeric values (e.g., wait time in ms)
                        cmd.value = try std.fmt.allocPrint(allocator, "{}", .{v.integer});
                    }
                }
                if (obj.get("key")) |k| {
                    if (k == .string) cmd.key = try allocator.dupe(u8, k.string);
                }
                if (obj.get("scrollX")) |sx| {
                    if (sx == .integer) cmd.scroll_x = @intCast(sx.integer);
                }
                if (obj.get("scrollY")) |sy| {
                    if (sy == .integer) cmd.scroll_y = @intCast(sy.integer);
                }
                // Assert-specific fields
                if (obj.get("attribute")) |attr| {
                    if (attr == .string) cmd.attribute = try allocator.dupe(u8, attr.string);
                }
                if (obj.get("contains")) |cont| {
                    if (cont == .string) cmd.contains = try allocator.dupe(u8, cont.string);
                }
                if (obj.get("url")) |url_val| {
                    if (url_val == .string) cmd.url = try allocator.dupe(u8, url_val.string);
                }
                if (obj.get("text")) |txt| {
                    if (txt == .string) cmd.text = try allocator.dupe(u8, txt.string);
                }
                if (obj.get("timeout")) |to| {
                    if (to == .integer) cmd.timeout = @intCast(to.integer);
                }
                if (obj.get("fallback")) |fb| {
                    if (fb == .string) cmd.fallback = try allocator.dupe(u8, fb.string);
                }
                // Extract-specific fields
                if (obj.get("mode")) |m| {
                    if (m == .string) cmd.mode = try allocator.dupe(u8, m.string);
                }
                if (obj.get("output")) |o| {
                    if (o == .string) cmd.output = try allocator.dupe(u8, o.string);
                }
                if (obj.get("extract_all")) |ea| {
                    if (ea == .bool) cmd.extract_all = ea.bool;
                }
                // Snapshot assertion field
                if (obj.get("snapshot")) |sn| {
                    if (sn == .string) cmd.snapshot = try allocator.dupe(u8, sn.string);
                }
                // Dialog-specific field
                if (obj.get("accept")) |ac| {
                    if (ac == .bool) cmd.accept = ac.bool;
                }

                try cmds_list.append(allocator, cmd);
            }

            macro.commands = try cmds_list.toOwnedSlice(allocator);
        }
    }

    return macro;
}

// ============================================================================
// Version 1: Raw Events (low-level, for backward compatibility)
// ============================================================================

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
pub fn loadMacro(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !Macro {
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
pub fn saveMacro(allocator: std.mem.Allocator, io: std.Io, path: []const u8, macro: *const Macro) !void {
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

/// JavaScript code to inject for event recording (legacy v1)
pub const RECORD_INIT_JS =
    \\(function() {
    \\  if (window.__zchrome_macro) return 'already_initialized';
    \\  window.__zchrome_macro = {
    \\    events: [],
    \\    startTime: Date.now(),
    \\    recording: true
    \\  };
    \\  var m = window.__zchrome_macro;
    \\  function record(e) {
    \\    if (!m.recording) return;
    \\    var ev = {
    \\      type: e.type,
    \\      timestamp: Date.now() - m.startTime
    \\    };
    \\    if (e.clientX !== undefined) { ev.x = e.clientX; ev.y = e.clientY; }
    \\    if (e.button !== undefined) ev.button = e.button;
    \\    if (e.deltaX !== undefined) { ev.deltaX = e.deltaX; ev.deltaY = e.deltaY; }
    \\    if (e.key !== undefined) { ev.key = e.key; ev.code = e.code; }
    \\    ev.modifiers = (e.altKey ? 1 : 0) | (e.ctrlKey ? 2 : 0) | (e.metaKey ? 4 : 0) | (e.shiftKey ? 8 : 0);
    \\    m.events.push(ev);
    \\  }
    \\  ['mousedown', 'mouseup', 'mousemove', 'wheel', 'keydown', 'keyup'].forEach(function(type) {
    \\    document.addEventListener(type, record, true);
    \\  });
    \\  return 'initialized';
    \\})()
;

/// JavaScript to retrieve recorded events
pub const RECORD_GET_EVENTS_JS =
    \\(function() {
    \\  if (!window.__zchrome_macro) return null;
    \\  window.__zchrome_macro.recording = false;
    \\  return JSON.stringify(window.__zchrome_macro.events);
    \\})()
;

/// JavaScript to retrieve and clear recorded events (for polling)
pub const RECORD_POLL_EVENTS_JS =
    \\(function() {
    \\  if (!window.__zchrome_macro) return null;
    \\  var events = window.__zchrome_macro.events;
    \\  window.__zchrome_macro.events = [];
    \\  return JSON.stringify(events);
    \\})()
;

/// JavaScript to clean up recording
pub const RECORD_CLEANUP_JS =
    \\(function() {
    \\  delete window.__zchrome_macro;
    \\  return 'cleaned';
    \\})()
;
