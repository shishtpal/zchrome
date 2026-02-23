//! Cursor commands: active, hover, record, replay.
//! Shows information about element under cursor or with focus.
//! Also handles macro recording and playback.

const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");
const config_mod = @import("../config.zig");
const macro_mod = @import("macro.zig");
const record_server = @import("record_server.zig");

pub const CommandCtx = types.CommandCtx;

fn keyToWindowsVirtualKeyCode(key_opt: ?[]const u8, code_opt: ?[]const u8) ?i32 {
    if (code_opt) |code| {
        if (code.len == 4 and std.mem.startsWith(u8, code, "Key")) {
            const c = code[3];
            if (c >= 'A' and c <= 'Z') return @intCast(c);
        }
        if (code.len == 6 and std.mem.startsWith(u8, code, "Digit")) {
            const c = code[5];
            if (c >= '0' and c <= '9') return @intCast(c);
        }
        if (std.mem.eql(u8, code, "Space")) return 32;
        if (std.mem.eql(u8, code, "Enter")) return 13;
        if (std.mem.eql(u8, code, "Tab")) return 9;
        if (std.mem.eql(u8, code, "Backspace")) return 8;
        if (std.mem.eql(u8, code, "Escape")) return 27;
        if (std.mem.eql(u8, code, "ArrowLeft")) return 37;
        if (std.mem.eql(u8, code, "ArrowUp")) return 38;
        if (std.mem.eql(u8, code, "ArrowRight")) return 39;
        if (std.mem.eql(u8, code, "ArrowDown")) return 40;
    }

    if (key_opt) |key| {
        if (key.len == 1) {
            const c = key[0];
            if (c >= 'a' and c <= 'z') return @as(i32, c - 32);
            if (c >= 'A' and c <= 'Z') return @as(i32, c);
            if (c >= '0' and c <= '9') return @as(i32, c);
            if (c == ' ') return 32;
        }

        if (std.mem.eql(u8, key, "Enter")) return 13;
        if (std.mem.eql(u8, key, "Tab")) return 9;
        if (std.mem.eql(u8, key, "Backspace")) return 8;
        if (std.mem.eql(u8, key, "Escape")) return 27;
        if (std.mem.eql(u8, key, "ArrowLeft")) return 37;
        if (std.mem.eql(u8, key, "ArrowUp")) return 38;
        if (std.mem.eql(u8, key, "ArrowRight")) return 39;
        if (std.mem.eql(u8, key, "ArrowDown")) return 40;
    }

    return null;
}

// JavaScript helper loaded from external file at compile time
pub const GET_ELEMENT_INFO_JS = @embedFile("../js/get-element-info.js");

/// Cursor command dispatcher - handles active, hover subcommands
pub fn cursor(session: *cdp.Session, ctx: CommandCtx) !void {
    // Check for --help flag
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printCursorHelp();
            return;
        }
    }

    if (ctx.positional.len == 0) {
        printCursorUsage();
        return;
    }

    const subcommand = ctx.positional[0];

    const args = if (ctx.positional.len > 1) ctx.positional[1..] else &[_][]const u8{};

    if (std.mem.eql(u8, subcommand, "active")) {
        try cursorActive(session, ctx.allocator);
    } else if (std.mem.eql(u8, subcommand, "hover")) {
        try cursorHover(session, ctx.allocator, ctx.io);
    } else if (std.mem.eql(u8, subcommand, "record")) {
        try cursorRecord(session, ctx.allocator, ctx.io, args);
    } else if (std.mem.eql(u8, subcommand, "replay")) {
        try cursorReplay(session, ctx.allocator, ctx.io, args);
    } else if (std.mem.eql(u8, subcommand, "optimize")) {
        try cursorOptimize(ctx.allocator, ctx.io, args);
    } else {
        std.debug.print("Unknown cursor subcommand: {s}\n", .{subcommand});
        printCursorUsage();
    }
}

/// Show the currently active/focused element
fn cursorActive(session: *cdp.Session, allocator: std.mem.Allocator) !void {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // Replace ELEMENT_VAR with document.activeElement
    const js = try std.mem.replaceOwned(u8, allocator, GET_ELEMENT_INFO_JS, "ELEMENT_VAR", "document.activeElement");
    defer allocator.free(js);

    // Wrap in check for body element
    const wrapped_js = try std.fmt.allocPrint(allocator,
        \\(function() {{
        \\  var el = document.activeElement;
        \\  if (!el || el === document.body) return null;
        \\  return {s}
        \\}})()
    , .{js});
    defer allocator.free(wrapped_js);

    var result = try runtime.evaluate(allocator, wrapped_js, .{ .return_by_value = true });
    defer result.deinit(allocator);

    if (result.value) |val| {
        if (val == .object) {
            printElementInfo("Active element", val.object);
            return;
        }
    }

    std.debug.print("No active element (body has focus)\n", .{});
}

/// Show the element under the mouse cursor
fn cursorHover(session: *cdp.Session, allocator: std.mem.Allocator, io: std.Io) !void {
    // Get mouse position from config
    var config = config_mod.loadConfig(allocator, io) orelse config_mod.Config{};
    defer config.deinit(allocator);

    const x = config.last_mouse_x orelse {
        std.debug.print("No mouse position recorded. Use 'mouse move <x> <y>' first.\n", .{});
        return;
    };
    const y = config.last_mouse_y orelse {
        std.debug.print("No mouse position recorded. Use 'mouse move <x> <y>' first.\n", .{});
        return;
    };

    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // Replace ELEMENT_VAR with document.elementFromPoint(x, y)
    const element_var = try std.fmt.allocPrint(allocator, "document.elementFromPoint({d}, {d})", .{ x, y });
    defer allocator.free(element_var);

    const js = try std.mem.replaceOwned(u8, allocator, GET_ELEMENT_INFO_JS, "ELEMENT_VAR", element_var);
    defer allocator.free(js);

    var result = try runtime.evaluate(allocator, js, .{ .return_by_value = true });
    defer result.deinit(allocator);

    std.debug.print("Element at cursor ({d:.0}, {d:.0}):\n", .{ x, y });

    if (result.value) |val| {
        if (val == .object) {
            printElementInfo(null, val.object);
            return;
        }
    }

    std.debug.print("  (no element found)\n", .{});
}

/// Record mouse and keyboard events to a macro file via WebSocket streaming.
/// Events are streamed in real-time and survive page reloads.
fn cursorRecord(session: *cdp.Session, allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: cursor record <filename.json>\n", .{});
        return;
    }

    const filename = args[0];
    const port = record_server.DEFAULT_PORT;

    // Start WebSocket server (runs in background thread)
    var server = record_server.RecordServer.init(allocator, io, port) catch |err| {
        std.debug.print("Failed to start recording server: {}\n", .{err});
        return;
    };
    defer server.deinit();

    // Set up browser to inject recording script
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    var page = cdp.Page.init(session);
    try page.enable();

    // Get recording JavaScript
    const recording_js = try record_server.getRecordingJs(allocator, port);
    defer allocator.free(recording_js);

    // Auto-inject on page navigation
    const script_id = try page.addScriptToEvaluateOnNewDocument(recording_js);
    defer page.removeScriptToEvaluateOnNewDocument(script_id) catch {};

    // Inject on current page
    var init_result = try runtime.evaluate(allocator, recording_js, .{ .return_by_value = true });
    init_result.deinit(allocator);

    std.debug.print("Recording on port {}... Press Enter to stop.\n", .{port});
    std.debug.print("(Events stream in real-time, survives page reloads)\n", .{});

    // Wait for Enter key (WebSocket server runs in background thread)
    const stdin_file = std.Io.File.stdin();
    var read_buf: [256]u8 = undefined;
    var reader = stdin_file.readerStreaming(io, &read_buf);

    while (true) {
        const byte = reader.interface.takeByte() catch break;
        if (byte == '\n' or byte == '\r') break;
    }

    // Stop server and get events
    const events = server.stop();

    if (events.len == 0) {
        std.debug.print("No events recorded.\n", .{});
        return;
    }

    // Save macro
    var macro = macro_mod.Macro{
        .version = 1,
        .recorded_at = null,
        .events = events,
    };

    try macro_mod.saveMacro(allocator, io, filename, &macro);
    std.debug.print("Recorded {} events to {s}\n", .{events.len, filename});
}

/// Replay events from a macro file
fn cursorReplay(session: *cdp.Session, allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: cursor replay <filename.json>\n", .{});
        return;
    }

    const filename = args[0];

    // Load macro
    var macro = macro_mod.loadMacro(allocator, io, filename) catch |err| {
        std.debug.print("Error loading macro: {}\n", .{err});
        return;
    };
    defer macro.deinit(allocator);

    if (macro.events.len == 0) {
        std.debug.print("No events in macro file.\n", .{});
        return;
    }

    std.debug.print("Replaying {} events from {s}...\n", .{ macro.events.len, filename });

    var input = cdp.Input.init(session);
    var prev_timestamp: i64 = 0;

    for (macro.events) |event| {
        // Wait for the appropriate delay
        const delay = event.timestamp - prev_timestamp;
        if (delay > 0) {
            // Approximate delay using spin loop (CPU-dependent, ~1ms per 10000 iterations on modern CPUs)
            // For more precise timing, consider using OS-level sleep when available
            var i: u64 = 0;
            const loops: u64 = @intCast(delay * 10000);
            while (i < loops) : (i += 1) {
                std.atomic.spinLoopHint();
            }
        }
        prev_timestamp = event.timestamp;

        // Dispatch event based on type
        switch (event.event_type) {
            .mouseMove => {
                try input.dispatchMouseEvent(.{
                    .type = .mouseMoved,
                    .x = event.x orelse 0,
                    .y = event.y orelse 0,
                });
            },
            .mouseDown => {
                const button: cdp.MouseButton = if (event.button) |b| switch (b) {
                    .left => .left,
                    .right => .right,
                    .middle => .middle,
                    .none => .left,
                } else .left;
                try input.dispatchMouseEvent(.{
                    .type = .mousePressed,
                    .x = event.x orelse 0,
                    .y = event.y orelse 0,
                    .button = button,
                    .click_count = 1,
                });
            },
            .mouseUp => {
                const button: cdp.MouseButton = if (event.button) |b| switch (b) {
                    .left => .left,
                    .right => .right,
                    .middle => .middle,
                    .none => .left,
                } else .left;
                try input.dispatchMouseEvent(.{
                    .type = .mouseReleased,
                    .x = event.x orelse 0,
                    .y = event.y orelse 0,
                    .button = button,
                    .click_count = 1,
                });
            },
            .mouseWheel => {
                try input.dispatchMouseEvent(.{
                    .type = .mouseWheel,
                    .x = event.x orelse 0,
                    .y = event.y orelse 0,
                    .delta_x = event.delta_x,
                    .delta_y = event.delta_y,
                });
            },
            .keyDown => {
                const vk = keyToWindowsVirtualKeyCode(event.key, event.code);
                const should_text = event.key != null and event.key.?.len == 1 and ((event.modifiers & 0x7) == 0);
                try input.dispatchKeyEvent(.{
                    .type = .keyDown,
                    .key = event.key,
                    .code = event.code,
                    .modifiers = if (event.modifiers != 0) event.modifiers else null,
                    .windows_virtual_key_code = vk,
                    .text = if (should_text) event.key else null,
                });
            },
            .keyUp => {
                const vk = keyToWindowsVirtualKeyCode(event.key, event.code);
                try input.dispatchKeyEvent(.{
                    .type = .keyUp,
                    .key = event.key,
                    .code = event.code,
                    .modifiers = if (event.modifiers != 0) event.modifiers else null,
                    .windows_virtual_key_code = vk,
                });
            },
        }
    }

    std.debug.print("Replay complete.\n", .{});
}

fn cursorOptimize(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: cursor optimize <filename.json> [--speed=N]\n", .{});
        return;
    }

    const filename = args[0];
    var speed: i32 = 3;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.startsWith(u8, a, "--speed=")) {
            const v = a[8..];
            speed = std.fmt.parseInt(i32, v, 10) catch {
                std.debug.print("Invalid --speed value: {s}\n", .{v});
                return;
            };
        } else if (std.mem.eql(u8, a, "--help")) {
            std.debug.print("Usage: cursor optimize <filename.json> [--speed=N]\n", .{});
            std.debug.print("  --speed=N   Speed multiplier (default 3). Positive speeds up, negative slows down.\n", .{});
            return;
        } else {
            std.debug.print("Unknown option: {s}\n", .{a});
            return;
        }
    }

    var macro = macro_mod.loadMacro(allocator, io, filename) catch |err| {
        std.debug.print("Error loading macro: {}\n", .{err});
        return;
    };
    defer macro.deinit(allocator);

    const before_count = macro.events.len;
    try macro_mod.optimizeMacro(allocator, &macro, speed);
    const after_count = macro.events.len;

    try macro_mod.saveMacro(allocator, io, filename, &macro);
    std.debug.print("Optimized {s}: {} -> {} events (speed={})\n", .{ filename, before_count, after_count, speed });
}

/// Print element info from JSON object
fn printElementInfo(header: ?[]const u8, obj: std.json.ObjectMap) void {
    if (header) |h| {
        std.debug.print("{s}:\n", .{h});
    }

    if (obj.get("type")) |t| {
        if (t == .string) std.debug.print("  type: {s}\n", .{t.string});
    }
    if (obj.get("tag")) |t| {
        if (t == .string) std.debug.print("  tag: {s}\n", .{t.string});
    }
    if (obj.get("role")) |r| {
        if (r == .string) std.debug.print("  role: {s}\n", .{r.string});
    }
    if (obj.get("name")) |n| {
        if (n == .string) std.debug.print("  name: \"{s}\"\n", .{n.string});
    }
    if (obj.get("id")) |i| {
        if (i == .string) std.debug.print("  id: {s}\n", .{i.string});
    }
    if (obj.get("selector")) |s| {
        if (s == .string) std.debug.print("  selector: {s}\n", .{s.string});
    }
    if (obj.get("x")) |x_val| {
        if (obj.get("y")) |y_val| {
            const xf = if (x_val == .float) x_val.float else if (x_val == .integer) @as(f64, @floatFromInt(x_val.integer)) else 0;
            const yf = if (y_val == .float) y_val.float else if (y_val == .integer) @as(f64, @floatFromInt(y_val.integer)) else 0;
            std.debug.print("  position: ({d:.0}, {d:.0})\n", .{ xf, yf });
        }
    }
}

fn printCursorUsage() void {
    std.debug.print(
        \\Usage: cursor <subcommand>
        \\
        \\Subcommands:
        \\  cursor active           Show the currently focused element
        \\  cursor hover            Show the element under the mouse cursor
        \\  cursor record <file>    Record mouse/keyboard events to file
        \\  cursor replay <file>    Replay events from file
        \\  cursor optimize <file>  Optimize macro JSON (remove redundant events)
        \\
        \\Examples:
        \\  zchrome cursor active
        \\  zchrome cursor hover
        \\  zchrome cursor record macro.json
        \\  zchrome cursor replay macro.json
        \\  zchrome cursor optimize macro.json --speed=3
        \\
    , .{});
}

pub fn printCursorHelp() void {
    std.debug.print(
        \\Usage: cursor <subcommand>
        \\
        \\Subcommands:
        \\  cursor active           Show the currently focused element
        \\  cursor hover            Show the element under the mouse cursor
        \\  cursor record <file>    Record mouse/keyboard events to JSON file
        \\  cursor replay <file>    Replay events from JSON file
        \\  cursor optimize <file>  Optimize macro JSON file
        \\
        \\The 'active' subcommand shows which element currently has keyboard focus.
        \\The 'hover' subcommand shows which element is under the last known mouse position.
        \\  (Use 'mouse move <x> <y>' to set the mouse position first)
        \\
        \\The 'record' subcommand injects event listeners into the page and captures
        \\all mouse/keyboard events. Press Enter to stop recording and save to file.
        \\
        \\The 'optimize' subcommand removes redundant mouseMove events and rescales
        \\timing using --speed=N (default 3). Positive values speed up; negative values slow down.
        \\
        \\The 'replay' subcommand loads events from a JSON file and dispatches them
        \\to the browser with the original timing preserved.
        \\
        \\Examples:
        \\  zchrome cursor active
        \\  zchrome cursor hover
        \\  zchrome cursor record macro.json    # Press Enter to stop
        \\  zchrome cursor replay macro.json
        \\
    , .{});
}
