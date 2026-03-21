//! CLI entry point and help for cursor replay commands.

const std = @import("std");
const json = @import("json");
const cdp = @import("cdp");

// Local imports
const macro = @import("../macro/mod.zig");
const state = @import("../state.zig");
const utils = @import("../utils.zig");
const display = @import("../display.zig");
const record = @import("../record.zig");
const video = @import("../video/mod.zig");

// Command imports
const types = @import("../../commands/types.zig");
const session_mod = @import("../../session.zig");

// Local replay imports
const executor = @import("executor.zig");

pub const CommandCtx = types.CommandCtx;

/// Replay interval configuration
pub const ReplayInterval = struct {
    min_ms: u32,
    max_ms: u32,

    pub fn getDelay(self: ReplayInterval, seed: u64) u32 {
        if (self.min_ms == self.max_ms) return self.min_ms;
        const range = self.max_ms - self.min_ms;
        const random_offset = @as(u32, @truncate(seed % @as(u64, range)));
        return self.min_ms + random_offset;
    }
};

/// Replay options
pub const ReplayOptions = struct {
    interval: ReplayInterval = .{ .min_ms = 100, .max_ms = 100 },
    max_retries: u32 = 3,
    retry_delay_ms: u32 = 1000,
    fallback_file: ?[]const u8 = null,
    resume_mode: bool = false,
    start_index: ?usize = null,
    session_ctx: ?*const session_mod.SessionContext = null,
    video_mode: video.OutputMode = .{},
    /// Existing video orchestrator (passed to nested goto calls)
    video_orch: ?*video.Orchestrator = null,
    /// Variables map (passed to nested foreach calls)
    variables: ?*std.StringHashMap(state.VarValue) = null,
};

/// Main cursor command entry point
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
        try display.cursorActive(session, ctx.allocator);
    } else if (std.mem.eql(u8, subcommand, "hover")) {
        try display.cursorHover(session, ctx);
    } else if (std.mem.eql(u8, subcommand, "record")) {
        try record.cursorRecord(session, ctx.allocator, ctx.io, args);
    } else if (std.mem.eql(u8, subcommand, "replay")) {
        try cursorReplay(session, ctx, args);
    } else {
        std.debug.print("Unknown cursor subcommand: {s}\n", .{subcommand});
        printCursorUsage();
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
        \\Video Recording & Streaming:
        \\  --record=<path>            Record replay to video file (mp4/webm/gif)
        \\  --fps=<n>                  Frames per second for recording (default: 10)
        \\  --quality=<0-100>          Video quality (default: 80)
        \\  --stream                   Enable live streaming
        \\  --port=<n>                 Stream server port (default: 8080)
        \\  --interactive              Allow viewers to interact
        \\
        \\Assert Action in JSON:
        \\  {{"action": "assert", "selector": "#el"}}           - Element exists
        \\  {{"action": "assert", "text": "Welcome"}}           - Text on page
        \\  {{"action": "assert", "text": "Record ID: *"}}      - Text with wildcard
        \\  {{"action": "assert", "url": "**/dashboard"}}       - URL matches
        \\  {{"action": "assert", "selector": "#el", "value": "expected"}}
        \\  {{"action": "assert", ..., "fallback": "error.json"}}
        \\
        \\Dialog Action in JSON:
        \\  {{"action": "dialog", "accept": true}}              - Accept dialog
        \\  {{"action": "dialog", "accept": true, "text": "OK to delete?"}} - Verify message
        \\  {{"action": "dialog", "accept": true, "text": "ID: *"}}  - Wildcard match
        \\
        \\Upload Action in JSON:
        \\  {{"action": "upload", "selector": "#file", "files": ["doc.pdf"]}}
        \\  {{"action": "upload", "selector": "#file", "files": ["a.pdf", "b.txt"]}}
        \\
        \\Goto Action in JSON (chain to another macro file):
        \\  {{"action": "goto", "file": "next-step.json"}}
        \\  {{"action": "goto", "file": "checkout.json"}}
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
        \\Video Recording & Streaming Examples:
        \\  zchrome cursor replay demo.json --record=demo.mp4
        \\  zchrome cursor replay demo.json --record=demo.webm --fps=15 --quality=90
        \\  zchrome cursor replay demo.json --stream --port=8080
        \\  zchrome cursor replay demo.json --stream --interactive
        \\  zchrome cursor replay demo.json --record=demo.mp4 --stream
        \\
    , .{});
}

fn parseInterval(arg: []const u8) ?ReplayInterval {
    if (std.mem.indexOf(u8, arg, "-")) |dash_pos| {
        const min_str = arg[0..dash_pos];
        const max_str = arg[dash_pos + 1 ..];
        const min = std.fmt.parseInt(u32, min_str, 10) catch return null;
        const max = std.fmt.parseInt(u32, max_str, 10) catch return null;
        if (min > max) return null;
        return .{ .min_ms = min, .max_ms = max };
    }
    const ms = std.fmt.parseInt(u32, arg, 10) catch return null;
    return .{ .min_ms = ms, .max_ms = ms };
}

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
    var interval = ReplayInterval{ .min_ms = 100, .max_ms = 100 };

    // Parse options from args
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

    // Read file to check version
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
        // Parse video options from args
        const video_mode = video.orchestrator.parseVideoOptions(args);

        const options = ReplayOptions{
            .interval = interval,
            .max_retries = ctx.replay_retries,
            .retry_delay_ms = ctx.replay_retry_delay,
            .fallback_file = ctx.replay_fallback,
            .resume_mode = ctx.replay_resume,
            .start_index = ctx.replay_from,
            .session_ctx = ctx.session,
            .video_mode = video_mode,
        };
        return executor.replayCommandsWithOptions(session, allocator, io, filename, options);
    }

    // Version 1: Event-based replay (legacy)
    var macro_data = macro.loadMacro(allocator, io, filename) catch |err| {
        std.debug.print("Error loading macro: {}\n", .{err});
        return;
    };
    defer macro_data.deinit(allocator);

    if (macro_data.events.len == 0) {
        std.debug.print("No events in macro file.\n", .{});
        return;
    }

    std.debug.print("Replaying {} events from {s}...\n", .{ macro_data.events.len, filename });

    var input = cdp.Input.init(session);
    for (macro_data.events) |event| {
        switch (event.event_type) {
            .mouseMove => input.dispatchMouseEvent(.{
                .type = .mouseMoved,
                .x = event.x orelse 0,
                .y = event.y orelse 0,
            }) catch {},
            .mouseDown => input.dispatchMouseEvent(.{
                .type = .mousePressed,
                .x = event.x orelse 0,
                .y = event.y orelse 0,
                .button = .left,
                .click_count = 1,
            }) catch {},
            .mouseUp => input.dispatchMouseEvent(.{
                .type = .mouseReleased,
                .x = event.x orelse 0,
                .y = event.y orelse 0,
                .button = .left,
                .click_count = 1,
            }) catch {},
            .keyDown => input.dispatchKeyEvent(.{
                .type = .keyDown,
                .key = event.key,
                .code = event.code,
                .windows_virtual_key_code = record.keyToWindowsVirtualKeyCode(event.key, event.code),
            }) catch {},
            .keyUp => input.dispatchKeyEvent(.{
                .type = .keyUp,
                .key = event.key,
                .code = event.code,
                .windows_virtual_key_code = record.keyToWindowsVirtualKeyCode(event.key, event.code),
            }) catch {},
            .mouseWheel => {
                const delta_y_val = event.delta_y orelse 0;
                const delta_y: i32 = @intFromFloat(delta_y_val);
                input.dispatchMouseEvent(.{
                    .type = .mouseWheel,
                    .x = event.x orelse 0,
                    .y = event.y orelse 0,
                    .delta_x = 0,
                    .delta_y = delta_y,
                }) catch {};
            },
        }

        // Delay between events
        const seed: u64 = @intCast(@mod(std.Io.Timestamp.now(io, .real).nanoseconds, std.math.maxInt(i64)));
        utils.waitForTime(interval.getDelay(seed));
    }

    std.debug.print("Replay complete.\n", .{});
}
