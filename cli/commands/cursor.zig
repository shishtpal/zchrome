//! Cursor commands: active, hover, record, replay.
//! Shows information about element under cursor or with focus.
//! Also handles macro recording and playback.

const std = @import("std");
const json = @import("json");
const cdp = @import("cdp");
const types = @import("types.zig");
const config_mod = @import("../config.zig");
const macro_mod = @import("macro.zig");
const record_server = @import("record_server.zig");
const elements = @import("elements.zig");
const keyboard = @import("keyboard.zig");
const scroll_mod = @import("scroll.zig");
const wait_mod = @import("wait.zig");
const navigation = @import("navigation.zig");
const replay_state = @import("replay_state.zig");
const session_mod = @import("../session.zig");
const helpers = @import("helpers.zig");

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
        try cursorHover(session, ctx);
    } else if (std.mem.eql(u8, subcommand, "record")) {
        try cursorRecord(session, ctx.allocator, ctx.io, args);
    } else if (std.mem.eql(u8, subcommand, "replay")) {
        try cursorReplay(session, ctx, args);
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
            printElementInfo("Active element", val);
            return;
        }
    }

    std.debug.print("No active element (body has focus)\n", .{});
}

/// Show the element under the mouse cursor
fn cursorHover(session: *cdp.Session, ctx: CommandCtx) !void {
    // Get mouse position from config (using session context if available)
    var config = ctx.loadConfig();
    defer config.deinit(ctx.allocator);

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
    const element_var = try std.fmt.allocPrint(ctx.allocator, "document.elementFromPoint({d}, {d})", .{ x, y });
    defer ctx.allocator.free(element_var);

    const js = try std.mem.replaceOwned(u8, ctx.allocator, GET_ELEMENT_INFO_JS, "ELEMENT_VAR", element_var);
    defer ctx.allocator.free(js);

    var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
    defer result.deinit(ctx.allocator);

    std.debug.print("Element at cursor ({d:.0}, {d:.0}):\n", .{ x, y });

    if (result.value) |val| {
        if (val == .object) {
            printElementInfo(null, val);
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
    waitForEnter(io);

    // Ask browser-side recorder to close its WebSocket so server read loop unblocks.
    var stop_result = runtime.evaluate(allocator,
        \\(function() {
        \\  try {
        \\    if (window.__zchrome_rec && window.__zchrome_rec.ws) {
        \\      window.__zchrome_rec.ws.close();
        \\    }
        \\  } catch (_) {}
        \\  return true;
        \\})()
    , .{ .return_by_value = false }) catch null;
    if (stop_result) |*res| {
        res.deinit(allocator);
    }

    // Stop server and get commands
    const commands = server.stop();

    if (commands.len == 0) {
        std.debug.print("No commands recorded.\n", .{});
        return;
    }

    // Save command macro
    var macro = macro_mod.CommandMacro{
        .version = 2,
        .commands = commands,
    };

    try macro_mod.saveCommandMacro(allocator, io, filename, &macro);
    std.debug.print("Recorded {} commands to {s}\n", .{ commands.len, filename });
}

/// Interval configuration for replay
const ReplayInterval = struct {
    min_ms: u32 = 100,
    max_ms: u32 = 100,

    fn isRandom(self: ReplayInterval) bool {
        return self.min_ms != self.max_ms;
    }

    fn getDelay(self: ReplayInterval, seed: u64) u32 {
        if (self.min_ms == self.max_ms) return self.min_ms;
        // Simple random using seed
        const range = self.max_ms - self.min_ms;
        const rand = @as(u32, @truncate(seed *% 1103515245 +% 12345));
        return self.min_ms + (rand % (range + 1));
    }
};

fn parseInterval(arg: []const u8) ?ReplayInterval {
    // Parse "100" or "100-200"
    if (std.mem.indexOf(u8, arg, "-")) |dash_pos| {
        const min_str = arg[0..dash_pos];
        const max_str = arg[dash_pos + 1 ..];
        const min = std.fmt.parseInt(u32, min_str, 10) catch return null;
        const max = std.fmt.parseInt(u32, max_str, 10) catch return null;
        if (min > max) return null;
        return .{ .min_ms = min, .max_ms = max };
    } else {
        const val = std.fmt.parseInt(u32, arg, 10) catch return null;
        return .{ .min_ms = val, .max_ms = val };
    }
}

/// Replay commands or events from a macro file
fn cursorReplay(session: *cdp.Session, ctx: CommandCtx, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: cursor replay <filename.json> [options]\n", .{});
        std.debug.print("Options:\n", .{});
        std.debug.print("  --interval=<ms>|<min-max>  Delay between commands (default: 100)\n", .{});
        std.debug.print("  --retries <n>              Retries on assertion failure (default: 3)\n", .{});
        std.debug.print("  --retry-delay <ms>         Wait before retry (default: 100)\n", .{});
        std.debug.print("  --fallback <file.json>     Fallback file on permanent failure\n", .{});
        std.debug.print("  --resume                   Resume from last action\n", .{});
        std.debug.print("  --from <n>                 Start from command index n\n", .{});
        return;
    }

    const allocator = ctx.allocator;
    const io = ctx.io;
    const filename = args[0];
    var interval = ReplayInterval{ .min_ms = 100, .max_ms = 100 }; // Default 100ms

    // Parse options from args (--interval is passed through positional)
    for (args[1..]) |arg| {
        if (std.mem.startsWith(u8, arg, "--interval=")) {
            const val = arg["--interval=".len..];
            if (parseInterval(val)) |iv| {
                interval = iv;
            } else {
                std.debug.print("Invalid --interval value: {s}\n", .{val});
                std.debug.print("Use --interval=100 or --interval=100-300\n", .{});
                return;
            }
        }
    }

    // First read file to check version
    const dir = std.Io.Dir.cwd();
    var file_buf: [256 * 1024]u8 = undefined;
    const content = dir.readFile(io, filename, &file_buf) catch |err| {
        std.debug.print("Error reading macro file: {}\n", .{err});
        return;
    };

    // Parse to check version
    var version_check = json.parse(allocator, content, .{}) catch |err| {
        std.debug.print("Error parsing macro JSON: {}\n", .{err});
        return;
    };
    defer version_check.deinit(allocator);

    var version: u32 = 1;
    if (version_check.get("version")) |v| {
        if (v == .integer) version = @intCast(v.integer);
    }

    // Version 2: Command-based replay with assert/retry support
    if (version == 2) {
        const options = ReplayOptions{
            .interval = interval,
            .max_retries = ctx.replay_retries,
            .retry_delay_ms = ctx.replay_retry_delay,
            .fallback_file = ctx.replay_fallback,
            .resume_mode = ctx.replay_resume,
            .start_index = ctx.replay_from,
            .session_ctx = ctx.session,
        };
        return replayCommandsWithOptions(session, allocator, io, filename, options);
    }

    // Version 1: Event-based replay (legacy)
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

/// Try executing a simple selector-based command with fallback selectors
fn tryWithFallbackSelectors(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    io: std.Io,
    cmd: macro_mod.MacroCommand,
    comptime action_fn: fn (*cdp.Session, types.CommandCtx) anyerror!void,
) void {
    // Build list of selectors to try
    const selectors = cmd.selectors orelse if (cmd.selector) |sel| blk: {
        var single: [1][]const u8 = .{sel};
        break :blk &single;
    } else return;

    for (selectors, 0..) |sel, idx| {
        var pos_args: [1][]const u8 = .{sel};
        const ctx = types.CommandCtx{
            .allocator = allocator,
            .io = io,
            .positional = &pos_args,
        };
        action_fn(session, ctx) catch |err| {
            if (idx + 1 < selectors.len) {
                std.debug.print("    (trying fallback selector...)\n", .{});
                continue;
            }
            std.debug.print("    Error: {}\n", .{err});
            return;
        };
        return; // Success
    }
}

/// Try fill command with fallback selectors
fn tryWithFallbackSelectorsFill(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    io: std.Io,
    cmd: macro_mod.MacroCommand,
) void {
    const value = cmd.value orelse return;
    const selectors = cmd.selectors orelse if (cmd.selector) |sel| blk: {
        var single: [1][]const u8 = .{sel};
        break :blk &single;
    } else return;

    for (selectors, 0..) |sel, idx| {
        var pos_args: [2][]const u8 = .{ sel, value };
        const ctx = types.CommandCtx{
            .allocator = allocator,
            .io = io,
            .positional = &pos_args,
        };
        elements.fill(session, ctx) catch |err| {
            if (idx + 1 < selectors.len) {
                std.debug.print("    (trying fallback selector...)\n", .{});
                continue;
            }
            std.debug.print("    Error: {}\n", .{err});
            return;
        };
        return; // Success
    }
}

/// Try select command with fallback selectors
fn tryWithFallbackSelectorsSelect(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    io: std.Io,
    cmd: macro_mod.MacroCommand,
) void {
    const value = cmd.value orelse return;
    const selectors = cmd.selectors orelse if (cmd.selector) |sel| blk: {
        var single: [1][]const u8 = .{sel};
        break :blk &single;
    } else return;

    for (selectors, 0..) |sel, idx| {
        var pos_args: [2][]const u8 = .{ sel, value };
        const ctx = types.CommandCtx{
            .allocator = allocator,
            .io = io,
            .positional = &pos_args,
        };
        elements.selectOption(session, ctx) catch |err| {
            if (idx + 1 < selectors.len) {
                std.debug.print("    (trying fallback selector...)\n", .{});
                continue;
            }
            std.debug.print("    Error: {}\n", .{err});
            return;
        };
        return; // Success
    }
}

/// Try multiselect command with fallback selectors (value is JSON array)
fn tryWithFallbackSelectorsMultiselect(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    io: std.Io,
    cmd: macro_mod.MacroCommand,
) void {
    const value = cmd.value orelse return;
    const selectors = cmd.selectors orelse if (cmd.selector) |sel| blk: {
        var single: [1][]const u8 = .{sel};
        break :blk &single;
    } else return;

    const actions_mod = @import("../actions/mod.zig");

    for (selectors, 0..) |sel, idx| {
        var resolved = actions_mod.resolveSelector(allocator, io, sel, null) catch {
            if (idx + 1 < selectors.len) {
                std.debug.print("    (trying fallback selector...)\n", .{});
                continue;
            }
            std.debug.print("    Error: selector resolution failed\n", .{});
            return;
        };
        defer resolved.deinit();

        actions_mod.multiselectOptions(session, allocator, &resolved, value) catch |err| {
            if (idx + 1 < selectors.len) {
                std.debug.print("    (trying fallback selector...)\n", .{});
                continue;
            }
            std.debug.print("    Error: {}\n", .{err});
            return;
        };
        return; // Success
    }
}

/// Options for replay command
pub const ReplayOptions = struct {
    interval: ReplayInterval = .{},
    max_retries: u32 = 3,
    retry_delay_ms: u32 = 100,
    fallback_file: ?[]const u8 = null,
    resume_mode: bool = false,
    start_index: ?usize = null,
    session_ctx: ?*const session_mod.SessionContext = null,
};

/// Execute an assertion command, returns true on success, false on failure
fn executeAssertion(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    io: std.Io,
    cmd: macro_mod.MacroCommand,
    _: ?*const session_mod.SessionContext,
) !bool {
    const timeout_ms = cmd.timeout orelse 5000;
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // 1. Check URL pattern if specified
    if (cmd.url) |url_pattern| {
        const regex_pattern = try globToRegex(allocator, url_pattern);
        defer allocator.free(regex_pattern);

        const js = try std.fmt.allocPrint(allocator, "new RegExp('{s}').test(window.location.href)", .{regex_pattern});
        defer allocator.free(js);

        if (try pollUntilTrue(session, allocator, js, timeout_ms)) {
            return true;
        }
        return false;
    }

    // 2. Check text on page if specified
    if (cmd.text) |text| {
        const escaped = try escapeForJs(allocator, text);
        defer allocator.free(escaped);

        const js = try std.fmt.allocPrint(allocator, "document.body.innerText.includes('{s}')", .{escaped});
        defer allocator.free(js);

        if (try pollUntilTrue(session, allocator, js, timeout_ms)) {
            return true;
        }
        return false;
    }

    // 3. Check selector-based assertions
    if (cmd.selector) |sel| {
        const escaped_sel = try escapeForJs(allocator, sel);
        defer allocator.free(escaped_sel);

        var js: []const u8 = undefined;

        if (cmd.value) |expected_value| {
            // Check element value/text content matches
            const escaped_val = try escapeForJs(allocator, expected_value);
            defer allocator.free(escaped_val);

            js = try std.fmt.allocPrint(allocator,
                \\(function(s,v){{
                \\  var el = document.querySelector(s);
                \\  if (!el) return false;
                \\  if (el.multiple) {{
                \\    var expected = JSON.parse(v);
                \\    var selected = Array.from(el.selectedOptions).map(function(o){{ return o.value; }});
                \\    return expected.length === selected.length && expected.every(function(e){{ return selected.includes(e); }});
                \\  }}
                \\  return el.value === v || el.textContent.trim() === v;
                \\}})('{s}', '{s}')
            , .{ escaped_sel, escaped_val });
        } else if (cmd.attribute) |attr| {
            // Check attribute value
            const escaped_attr = try escapeForJs(allocator, attr);
            defer allocator.free(escaped_attr);

            if (cmd.contains) |contains_val| {
                const escaped_contains = try escapeForJs(allocator, contains_val);
                defer allocator.free(escaped_contains);
                js = try std.fmt.allocPrint(allocator,
                    \\(function(s,a,c){{
                    \\  var el = document.querySelector(s);
                    \\  if (!el) return false;
                    \\  var av = el.getAttribute(a);
                    \\  return av && av.includes(c);
                    \\}})('{s}', '{s}', '{s}')
                , .{ escaped_sel, escaped_attr, escaped_contains });
            } else {
                js = try std.fmt.allocPrint(allocator,
                    \\(function(s,a){{
                    \\  var el = document.querySelector(s);
                    \\  return el && el.hasAttribute(a);
                    \\}})('{s}', '{s}')
                , .{ escaped_sel, escaped_attr });
            }
        } else {
            // Just check element exists and is visible
            js = try std.fmt.allocPrint(allocator,
                \\(function(s){{
                \\  var el = document.querySelector(s);
                \\  if (!el) return false;
                \\  var style = getComputedStyle(el);
                \\  return style.display !== 'none' && style.visibility !== 'hidden';
                \\}})('{s}')
            , .{escaped_sel});
        }
        defer allocator.free(js);

        if (try pollUntilTrue(session, allocator, js, timeout_ms)) {
            return true;
        }
        return false;
    }

    // 4. Snapshot comparison
    if (cmd.snapshot) |snapshot_path| {
        if (cmd.selector) |sel| {
            const dom_mod = @import("dom.zig");

            // Extract current DOM state
            const current_json = try dom_mod.executeExtract(session, allocator, sel, .dom, false);
            defer allocator.free(current_json);

            // Read expected snapshot file
            const dir = std.Io.Dir.cwd();
            const expected_json = dir.readFileAlloc(io, snapshot_path, allocator, std.Io.Limit.limited(10 * 1024 * 1024)) catch |err| {
                std.debug.print("    Failed to read snapshot file {s}: {}\n", .{ snapshot_path, err });
                return false;
            };
            defer allocator.free(expected_json);

            // Normalize and compare JSON (trim whitespace for comparison)
            const current_trimmed = std.mem.trim(u8, current_json, " \t\n\r");
            const expected_trimmed = std.mem.trim(u8, expected_json, " \t\n\r");

            if (std.mem.eql(u8, current_trimmed, expected_trimmed)) {
                return true;
            }

            std.debug.print("    Snapshot mismatch for {s}\n", .{sel});
            return false;
        }
    }

    // No assertion conditions specified - pass by default
    return true;
}

/// Escape a string for use in JavaScript (without adding quotes)
fn escapeForJs(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
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
fn pollUntilTrue(session: *cdp.Session, allocator: std.mem.Allocator, js_condition: []const u8, timeout_ms: u32) !bool {
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
fn globToRegex(allocator: std.mem.Allocator, pattern: []const u8) ![]u8 {
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
fn waitForTime(ms: u32) void {
    const iterations_per_second: u64 = 20_000_000;
    const total_iterations: u64 = (@as(u64, ms) * iterations_per_second) / 1000;
    var k: u64 = 0;
    while (k < total_iterations) : (k += 1) std.atomic.spinLoopHint();
}

/// Replay semantic commands from a v2 macro file
fn replayCommands(session: *cdp.Session, allocator: std.mem.Allocator, io: std.Io, filename: []const u8, interval: ReplayInterval) !void {
    // Use default options for backward compatibility
    const options = ReplayOptions{ .interval = interval };
    return replayCommandsWithOptions(session, allocator, io, filename, options);
}

/// Replay semantic commands with full options (retries, fallback, etc.)
fn replayCommandsWithOptions(session: *cdp.Session, allocator: std.mem.Allocator, io: std.Io, filename: []const u8, options: ReplayOptions) !void {
    var macro = macro_mod.loadCommandMacro(allocator, io, filename) catch |err| {
        std.debug.print("Error loading command macro: {}\n", .{err});
        return;
    };
    defer macro.deinit(allocator);

    if (macro.commands.len == 0) {
        std.debug.print("No commands in macro file.\n", .{});
        return;
    }

    const interval = options.interval;

    // Check for resume mode
    var start_idx: usize = options.start_index orelse 0;
    if (options.resume_mode) {
        if (replay_state.loadState(allocator, io, options.session_ctx)) |state| {
            var loaded_state = state;
            defer loaded_state.deinit(allocator);
            if (loaded_state.last_action_index) |idx| {
                start_idx = idx;
                std.debug.print("Resuming from command {}...\n", .{idx + 1});
            }
        }
    }

    // Print header
    std.debug.print("Replaying {} commands from {s} (retries: {}, delay: {}ms)...\n", .{
        macro.commands.len,
        filename,
        options.max_retries,
        options.retry_delay_ms,
    });

    // Track state for retry logic
    var last_action_index: usize = 0;
    var retry_count: u32 = 0;
    var total_retries: u32 = 0;
    var has_assertions = false;

    // Enable Page domain upfront so we can intercept dialogs triggered by any command.
    // This must happen BEFORE any action that might trigger a dialog, otherwise the
    // dialog gets auto-dismissed when Page.enable() is called later.
    var page = cdp.Page.init(session);
    try page.enable();

    var i: usize = start_idx;
    while (i < macro.commands.len) {
        const cmd = macro.commands[i];

        // Print progress
        const action_name = cmd.action.toString();
        if (cmd.action == .assert) {
            has_assertions = true;
            // Print assertion info
            if (cmd.selector) |sel| {
                std.debug.print("  [{}/{}] {s} \"{s}\"", .{ i + 1, macro.commands.len, action_name, sel });
            } else if (cmd.url) |url_val| {
                std.debug.print("  [{}/{}] {s} URL \"{s}\"", .{ i + 1, macro.commands.len, action_name, url_val });
            } else if (cmd.text) |txt| {
                std.debug.print("  [{}/{}] {s} text \"{s}\"", .{ i + 1, macro.commands.len, action_name, txt });
            } else {
                std.debug.print("  [{}/{}] {s}", .{ i + 1, macro.commands.len, action_name });
            }
        } else {
            if (cmd.selector) |sel| {
                std.debug.print("  [{}/{}] {s} \"{s}\"", .{ i + 1, macro.commands.len, action_name, sel });
            } else if (cmd.key) |key| {
                std.debug.print("  [{}/{}] {s} {s}", .{ i + 1, macro.commands.len, action_name, key });
            } else {
                std.debug.print("  [{}/{}] {s}", .{ i + 1, macro.commands.len, action_name });
            }
        }
        if (cmd.value) |val| {
            std.debug.print(" \"{s}\"", .{val});
        }

        // Handle assert command
        if (cmd.action == .assert) {
            const assert_result = executeAssertion(session, allocator, io, cmd, options.session_ctx) catch false;
            if (assert_result) {
                std.debug.print(" ✓\n", .{});
                retry_count = 0; // Reset retry count on success
            } else {
                const timeout_val = cmd.timeout orelse 5000;
                std.debug.print("\n    ✗ Assertion failed (timeout {}ms)\n", .{timeout_val});

                retry_count += 1;
                if (retry_count <= options.max_retries) {
                    std.debug.print("    Waiting {}ms before retry...\n", .{options.retry_delay_ms});
                    waitForTime(options.retry_delay_ms);
                    std.debug.print("    Retry {}/{}: Re-executing from last action [{}] {s}\n", .{
                        retry_count,
                        options.max_retries,
                        last_action_index + 1,
                        macro.commands[last_action_index].action.toString(),
                    });

                    // Save state before retry
                    var state = replay_state.ReplayState{
                        .macro_file = allocator.dupe(u8, filename) catch null,
                        .last_action_index = last_action_index,
                        .last_attempted_index = i,
                        .retry_count = retry_count,
                        .status = .running,
                    };
                    defer state.deinit(allocator);
                    replay_state.saveState(state, allocator, io, options.session_ctx) catch {};

                    // Jump back to last action command
                    i = last_action_index;
                    total_retries += 1;
                    continue;
                } else {
                    // Max retries exceeded - check for fallback
                    std.debug.print("    ✗ Assertion failed after {} retries\n", .{options.max_retries});

                    // Save failed state
                    var state = replay_state.ReplayState{
                        .macro_file = allocator.dupe(u8, filename) catch null,
                        .last_action_index = last_action_index,
                        .last_attempted_index = i,
                        .failure_reason = allocator.dupe(u8, "Assertion failed after max retries") catch null,
                        .retry_count = retry_count,
                        .status = .failed,
                    };
                    defer state.deinit(allocator);
                    replay_state.saveState(state, allocator, io, options.session_ctx) catch {};
                    std.debug.print("    State saved: last_action={}, status=failed\n", .{last_action_index + 1});

                    // Determine fallback: assert-level > CLI-level > stop
                    const fallback_file = cmd.fallback orelse options.fallback_file;
                    if (fallback_file) |fb| {
                        std.debug.print("    Executing fallback: {s}\n", .{fb});
                        // Load and execute fallback macro
                        const fb_options = ReplayOptions{
                            .interval = options.interval,
                            .max_retries = options.max_retries,
                            .retry_delay_ms = options.retry_delay_ms,
                            .session_ctx = options.session_ctx,
                        };
                        try replayCommandsWithOptions(session, allocator, io, fb, fb_options);
                        return;
                    } else {
                        std.debug.print("Replay stopped. Use --resume to continue from last action.\n", .{});
                        return;
                    }
                }
            }
            i += 1;
            continue;
        }

        std.debug.print("\n", .{});

        // Track last action command for retry
        if (cmd.action.isActionCommand()) {
            last_action_index = i;
        }

        // Build context for command execution
        var pos_args: [3][]const u8 = undefined;
        var pos_len: usize = 0;

        if (cmd.selector) |sel| {
            pos_args[pos_len] = sel;
            pos_len += 1;
        }
        if (cmd.value) |val| {
            pos_args[pos_len] = val;
            pos_len += 1;
        }
        if (cmd.key) |key| {
            pos_args[pos_len] = key;
            pos_len += 1;
        }

        const ctx = types.CommandCtx{
            .allocator = allocator,
            .io = io,
            .positional = pos_args[0..pos_len],
        };

        // Execute command with fallback selector support
        switch (cmd.action) {
            .click => tryWithFallbackSelectors(session, allocator, io, cmd, elements.click),
            .dblclick => tryWithFallbackSelectors(session, allocator, io, cmd, elements.dblclick),
            .fill => tryWithFallbackSelectorsFill(session, allocator, io, cmd),
            .check => tryWithFallbackSelectors(session, allocator, io, cmd, elements.check),
            .uncheck => tryWithFallbackSelectors(session, allocator, io, cmd, elements.uncheck),
            .select => tryWithFallbackSelectorsSelect(session, allocator, io, cmd),
            .multiselect => tryWithFallbackSelectorsMultiselect(session, allocator, io, cmd),
            .press => keyboard.press(session, ctx) catch |err| {
                std.debug.print("    Error: {}\n", .{err});
            },
            .hover => tryWithFallbackSelectors(session, allocator, io, cmd, elements.hover),
            .scroll => {
                // For scroll, we need to handle scrollX/scrollY
                if (cmd.scroll_y) |sy| {
                    const direction: []const u8 = if (sy > 0) "down" else "up";
                    const amount = if (sy > 0) sy else -sy;
                    var scroll_buf: [16]u8 = undefined;
                    const amount_str = std.fmt.bufPrint(&scroll_buf, "{}", .{amount}) catch "300";
                    var scroll_args: [2][]const u8 = .{ direction, amount_str };
                    const scroll_ctx = types.CommandCtx{
                        .allocator = allocator,
                        .io = io,
                        .positional = &scroll_args,
                    };
                    scroll_mod.scroll(session, scroll_ctx) catch |err| {
                        std.debug.print("    Error: {}\n", .{err});
                    };
                }
            },
            .navigate => {
                // Navigate to URL
                if (cmd.value) |url| {
                    var nav_args: [1][]const u8 = .{url};
                    const nav_ctx = types.CommandCtx{
                        .allocator = allocator,
                        .io = io,
                        .positional = &nav_args,
                    };
                    navigation.navigate(session, nav_ctx) catch |err| {
                        std.debug.print("    Error: {}\n", .{err});
                    };
                }
            },
            .wait => {
                // Wait for selector, time, or text
                if (cmd.selectors != null or cmd.selector != null) {
                    // Wait for element with fallback selectors
                    const selectors = cmd.selectors orelse if (cmd.selector) |sel| blk: {
                        var single: [1][]const u8 = .{sel};
                        break :blk &single;
                    } else &.{};

                    for (selectors, 0..) |sel, idx| {
                        var wait_args: [1][]const u8 = .{sel};
                        const wait_ctx = types.CommandCtx{
                            .allocator = allocator,
                            .io = io,
                            .positional = &wait_args,
                        };
                        wait_mod.wait(session, wait_ctx) catch |err| {
                            if (idx + 1 < selectors.len) {
                                std.debug.print("    (trying fallback selector...)\n", .{});
                                continue;
                            }
                            std.debug.print("    Error: {}\n", .{err});
                            break;
                        };
                        break; // Success
                    }
                } else if (cmd.value) |val| {
                    // Check if it's a number (time) or text
                    if (std.fmt.parseInt(u32, val, 10)) |ms| {
                        // Wait for time
                        std.debug.print(" ({}ms)", .{ms});
                        waitForTime(ms);
                    } else |_| {
                        // Wait for text
                        const wait_ctx = types.CommandCtx{
                            .allocator = allocator,
                            .io = io,
                            .positional = &.{},
                            .wait_text = val,
                        };
                        wait_mod.wait(session, wait_ctx) catch |err| {
                            std.debug.print("    Error: {}\n", .{err});
                        };
                    }
                }
            },
            .assert => {}, // Already handled above
            .extract => {
                // Execute DOM extraction
                const selector = cmd.selector orelse {
                    std.debug.print("    Error: extract requires selector\n", .{});
                    continue;
                };
                const dom_mod = @import("dom.zig");
                const mode = if (cmd.mode) |m| dom_mod.ExtractMode.fromString(m) orelse .dom else .dom;
                const extract_all = cmd.extract_all orelse false;

                const result = dom_mod.executeExtract(session, allocator, selector, mode, extract_all) catch |err| {
                    std.debug.print("    Error: {}\n", .{err});
                    continue;
                };
                defer allocator.free(result);

                if (cmd.output) |output_path| {
                    helpers.writeFile(io, output_path, result) catch |err| {
                        std.debug.print("    Error writing {s}: {}\n", .{ output_path, err });
                        continue;
                    };
                    std.debug.print(" -> {s}\n", .{output_path});
                } else {
                    std.debug.print("\n{s}\n", .{result});
                }
            },
            .dialog => {
                // Handle JavaScript dialog (alert/confirm/prompt)
                // Note: Page domain is already enabled at start of replay

                const should_accept = cmd.accept orelse true;
                const timeout_ms = cmd.timeout orelse 5000;

                // Wait for dialog event to capture message
                var dialog_info = page.waitForJavaScriptDialogOpening(allocator, timeout_ms) catch |err| {
                    std.debug.print("\n    Error waiting for dialog: {}\n", .{err});
                    continue;
                };
                defer dialog_info.deinit(allocator);

                // Assert dialog message if specified
                if (cmd.text) |expected_text| {
                    if (!std.mem.eql(u8, dialog_info.message, expected_text)) {
                        std.debug.print("\n    Dialog message mismatch\n", .{});
                        std.debug.print("      Expected: \"{s}\"\n", .{expected_text});
                        std.debug.print("      Actual:   \"{s}\"\n", .{dialog_info.message});
                        continue;
                    }
                    std.debug.print(" (message verified)", .{});
                }

                // Handle the dialog
                page.handleJavaScriptDialog(.{
                    .accept = should_accept,
                    .prompt_text = if (should_accept) cmd.value else null,
                }) catch |err| {
                    std.debug.print("\n    Error handling dialog: {}\n", .{err});
                    continue;
                };

                if (should_accept) {
                    if (cmd.value) |v| {
                        std.debug.print(" accepted with text: \"{s}\"\n", .{v});
                    } else {
                        std.debug.print(" accepted\n", .{});
                    }
                } else {
                    std.debug.print(" dismissed\n", .{});
                }
            },
        }

        // Delay between commands
        const now_ns = std.Io.Timestamp.now(io, .real).nanoseconds;
        const seed: u64 = @as(u64, i) *% 12345 +% @as(u64, @intCast(@mod(now_ns, std.math.maxInt(i64))));
        const delay_ms = interval.getDelay(seed);
        waitForTime(delay_ms);

        i += 1;
    }

    // Clear state on successful completion
    replay_state.clearState(allocator, io, options.session_ctx) catch {};

    if (has_assertions) {
        if (total_retries > 0) {
            std.debug.print("Replay complete. {} retries needed.\n", .{total_retries});
        } else {
            std.debug.print("Replay complete. All assertions passed.\n", .{});
        }
    } else {
        std.debug.print("Replay complete.\n", .{});
    }
}

/// Print element info from JSON value
fn printElementInfo(header: ?[]const u8, obj: json.Value) void {
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

/// Wait for user to press Enter from stdin.
fn waitForEnter(io: std.Io) void {
    const stdin_file = std.Io.File.stdin();
    var buf: [32]u8 = undefined;
    var reader = stdin_file.readerStreaming(io, &buf);

    // Stop on either LF or CR so Enter works reliably across terminal modes.
    while (true) {
        const b = reader.interface.takeByte() catch break;
        if (b == '\n' or b == '\r') break;
    }
}

fn printCursorUsage() void {
    std.debug.print(
        \\Usage: cursor <subcommand>
        \\
        \\Subcommands:
        \\  cursor active           Show the currently focused element
        \\  cursor hover            Show the element under the mouse cursor
        \\  cursor record <file>    Record interactions to macro file
        \\  cursor replay <file>    Replay macro file
        \\
        \\Examples:
        \\  zchrome cursor active
        \\  zchrome cursor hover
        \\  zchrome cursor record macro.json
        \\  zchrome cursor replay macro.json --interval=500
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
        \\  cursor record <file>    Record interactions to macro file
        \\  cursor replay <file>    Replay macro file (with assert support)
        \\
        \\The 'active' subcommand shows which element currently has keyboard focus.
        \\The 'hover' subcommand shows which element is under the last known mouse position.
        \\  (Use 'mouse move <x> <y>' to set the mouse position first)
        \\
        \\The 'record' subcommand captures semantic commands (click, fill, press, etc.)
        \\as you interact with the page. Press Enter to stop recording.
        \\
        \\The 'replay' subcommand executes commands from a macro JSON file.
        \\Supports 'assert' commands for testing with automatic retry on failure.
        \\
        \\Replay Options:
        \\  --interval=<ms>|<min-max>  Delay between commands (default: 100ms)
        \\  --retries <n>              Retries on assertion failure (default: 3)
        \\  --retry-delay <ms>         Wait before retry (default: 100ms)
        \\  --fallback <file.json>     Fallback file on permanent failure
        \\  --resume                   Resume from last successful action
        \\  --from <n>                 Start from command index n
        \\
        \\Assert Action in JSON:
        \\  {{"action": "assert", "selector": "#el"}}           - Element exists
        \\  {{"action": "assert", "text": "Welcome"}}           - Text on page
        \\  {{"action": "assert", "url": "**/dashboard"}}       - URL matches
        \\  {{"action": "assert", "selector": "#el", "value": "expected"}}
        \\  {{"action": "assert", ..., "fallback": "error.json"}}
        \\
        \\Examples:
        \\  zchrome cursor active
        \\  zchrome cursor hover
        \\  zchrome cursor record macro.json
        \\  zchrome cursor replay macro.json
        \\  zchrome cursor replay form.json --retries 5
        \\  zchrome cursor replay form.json --fallback error.json
        \\  zchrome cursor replay form.json --resume
        \\
    , .{});
}
