//! Macro replay functionality with assertion and retry support.
//!
//! Provides the main `cursor` command entry point and replay logic.

const std = @import("std");
const json = @import("json");
const cdp = @import("cdp");

// Module imports
const macro = @import("macro/mod.zig");
const state = @import("state.zig");
const utils = @import("utils.zig");
const assertions = @import("assertions.zig");
const actions = @import("actions.zig");
const display = @import("display.zig");
const record = @import("record.zig");
const video = @import("video/mod.zig");

// Command imports
const types = @import("../commands/types.zig");
const elements = @import("../commands/elements.zig");
const keyboard = @import("../commands/keyboard.zig");
const scroll_mod = @import("../commands/scroll.zig");
const wait_mod = @import("../commands/wait.zig");
const navigation = @import("../commands/navigation.zig");
const session_mod = @import("../session.zig");

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
        return replayCommandsWithOptions(session, allocator, io, filename, options);
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

fn replayCommandsWithOptions(session: *cdp.Session, allocator: std.mem.Allocator, io: std.Io, filename: []const u8, options: ReplayOptions) !void {
    var macro_data = macro.loadCommandMacro(allocator, io, filename) catch |err| {
        std.debug.print("Error loading command macro: {}\n", .{err});
        return;
    };
    defer macro_data.deinit(allocator);

    if (macro_data.commands.len == 0) {
        std.debug.print("No commands in macro file.\n", .{});
        return;
    }

    const interval = options.interval;

    // Use existing video orchestrator if provided, otherwise create new one
    var video_orch: ?*video.Orchestrator = options.video_orch;
    var owns_video_orch = false;

    if (video_orch == null and (options.video_mode.record != null or options.video_mode.stream != null)) {
        video_orch = video.Orchestrator.init(allocator, io, session, options.video_mode) catch |err| {
            std.debug.print("Failed to initialize video: {}\n", .{err});
            return;
        };
        owns_video_orch = true;

        // Print stream URL if streaming
        if (video_orch.?.getStreamUrl()) |url| {
            std.debug.print("Streaming at: {s}\n", .{url});
        }

        // Start capture
        video_orch.?.startCapture() catch |err| {
            std.debug.print("Failed to start video capture: {}\n", .{err});
            video_orch.?.deinit();
            return;
        };
    }
    defer if (owns_video_orch) {
        if (video_orch) |orch| {
            orch.stopCapture() catch {};
            orch.deinit();
        }
    };

    // Check for resume mode
    var start_idx: usize = options.start_index orelse 0;
    if (options.resume_mode) {
        if (state.loadState(allocator, io, options.session_ctx)) |loaded| {
            var loaded_state = loaded;
            defer loaded_state.deinit(allocator);
            if (loaded_state.last_action_index) |idx| {
                start_idx = idx;
                std.debug.print("Resuming from command {}...\n", .{idx + 1});
            }
        }
    }

    // Print header
    std.debug.print("Replaying {} commands from {s} (retries: {}, delay: {}ms)...\n", .{
        macro_data.commands.len,
        filename,
        options.max_retries,
        options.retry_delay_ms,
    });

    // Track state for retry logic
    var last_action_index: usize = 0;
    var retry_count: u32 = 0;
    var total_retries: u32 = 0;
    var has_assertions = false;

    // Variables map for capture action
    var variables = std.StringHashMap(state.VarValue).init(allocator);
    defer {
        var iter = variables.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        variables.deinit();
    }

    // Enable Page domain upfront
    var page = cdp.Page.init(session);
    try page.enable();

    var i: usize = start_idx;
    while (i < macro_data.commands.len) {
        const cmd = macro_data.commands[i];

        // Print progress
        const action_name = cmd.action.toString();
        if (cmd.action == .assert) {
            has_assertions = true;
            if (cmd.selector) |sel| {
                std.debug.print("  [{}/{}] {s} \"{s}\"", .{ i + 1, macro_data.commands.len, action_name, sel });
            } else if (cmd.url) |url_val| {
                std.debug.print("  [{}/{}] {s} URL \"{s}\"", .{ i + 1, macro_data.commands.len, action_name, url_val });
            } else if (cmd.text) |txt| {
                std.debug.print("  [{}/{}] {s} text \"{s}\"", .{ i + 1, macro_data.commands.len, action_name, txt });
            } else {
                std.debug.print("  [{}/{}] {s}", .{ i + 1, macro_data.commands.len, action_name });
            }
        } else {
            if (cmd.selector) |sel| {
                std.debug.print("  [{}/{}] {s} \"{s}\"", .{ i + 1, macro_data.commands.len, action_name, sel });
            } else if (cmd.key) |key| {
                std.debug.print("  [{}/{}] {s} {s}", .{ i + 1, macro_data.commands.len, action_name, key });
            } else if (cmd.file) |f| {
                std.debug.print("  [{}/{}] {s} \"{s}\"", .{ i + 1, macro_data.commands.len, action_name, f });
            } else {
                std.debug.print("  [{}/{}] {s}", .{ i + 1, macro_data.commands.len, action_name });
            }
        }
        if (cmd.value) |val| {
            std.debug.print(" \"{s}\"", .{val});
        }

        // Handle assert command
        if (cmd.action == .assert) {
            const assert_result = assertions.executeAssertion(session, allocator, io, cmd, options.session_ctx, &variables) catch false;

            if (assert_result) {
                std.debug.print(" OK\n", .{});
            } else {
                std.debug.print(" FAILED\n", .{});

                // Retry logic
                if (retry_count < options.max_retries) {
                    retry_count += 1;
                    total_retries += 1;
                    std.debug.print("    Retrying from command {} (attempt {}/{})...\n", .{
                        last_action_index + 1,
                        retry_count,
                        options.max_retries,
                    });
                    utils.waitForTime(options.retry_delay_ms);
                    i = last_action_index;
                    continue;
                }

                // Permanent failure
                std.debug.print("    Assertion failed after {} retries\n", .{options.max_retries});

                // Check for fallback
                const fallback = cmd.fallback orelse options.fallback_file;
                if (fallback) |fb| {
                    std.debug.print("    Switching to fallback: {s}\n", .{fb});
                    return replayCommandsWithOptions(session, allocator, io, fb, options);
                }

                // Save state for resume
                const save_state = state.ReplayState{
                    .macro_file = allocator.dupe(u8, filename) catch null,
                    .last_action_index = last_action_index,
                    .last_attempted_index = i,
                    .retry_count = retry_count,
                    .status = .failed,
                };
                state.saveState(save_state, allocator, io, options.session_ctx) catch {};
                return;
            }

            retry_count = 0;
            i += 1;
            continue;
        }

        std.debug.print("\n", .{});

        // Track last action command for retry
        if (cmd.action != .wait and cmd.action != .press and cmd.action != .scroll and cmd.action != .assert) {
            last_action_index = i;
        }

        // Execute the command based on action type
        executeCommand(session, allocator, io, cmd, &variables, &page, filename, options, video_orch);

        // Capture video frame after command (if video mode is enabled)
        if (video_orch) |orch| {
            _ = orch.captureFrame();
        }

        // Delay between commands
        const now_ns = std.Io.Timestamp.now(io, .real).nanoseconds;
        const seed: u64 = @as(u64, i) *% 12345 +% @as(u64, @intCast(@mod(now_ns, std.math.maxInt(i64))));
        const delay_ms = interval.getDelay(seed);
        utils.waitForTime(delay_ms);

        i += 1;
    }

    // Clear state on successful completion
    state.clearState(allocator, io, options.session_ctx) catch {};

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

fn executeCommand(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    io: std.Io,
    cmd: macro.MacroCommand,
    variables: *std.StringHashMap(state.VarValue),
    page: *cdp.Page,
    macro_file: []const u8,
    options: ReplayOptions,
    video_orch: ?*video.Orchestrator,
) void {
    // Build context for command execution
    var pos_args: [2][]const u8 = .{ "", "" };
    var pos_len: usize = 0;

    if (cmd.selector) |s| {
        pos_args[pos_len] = s;
        pos_len += 1;
    }
    if (cmd.value) |v| {
        pos_args[pos_len] = v;
        pos_len += 1;
    }

    const ctx = types.CommandCtx{
        .allocator = allocator,
        .io = io,
        .positional = pos_args[0..pos_len],
    };

    switch (cmd.action) {
        .click => actions.tryWithFallbackSelectors(session, allocator, io, cmd, elements.click),
        .dblclick => actions.tryWithFallbackSelectors(session, allocator, io, cmd, elements.dblclick),
        .fill => actions.tryWithFallbackSelectorsFill(session, allocator, io, cmd),
        .@"type" => actions.tryWithFallbackSelectorsType(session, allocator, io, cmd),
        .check => actions.tryWithFallbackSelectors(session, allocator, io, cmd, elements.check),
        .uncheck => actions.tryWithFallbackSelectors(session, allocator, io, cmd, elements.uncheck),
        .select => actions.tryWithFallbackSelectorsSelect(session, allocator, io, cmd),
        .multiselect => actions.tryWithFallbackSelectorsMultiselect(session, allocator, io, cmd),
        .press => keyboard.press(session, ctx) catch |err| {
            std.debug.print("    Error: {}\n", .{err});
        },
        .hover => actions.tryWithFallbackSelectors(session, allocator, io, cmd, elements.hover),
        .scroll => {
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
            if (cmd.selectors != null or cmd.selector != null) {
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
                    break;
                }
            } else if (cmd.value) |val| {
                if (std.fmt.parseInt(u32, val, 10)) |ms| {
                    std.debug.print(" ({}ms)", .{ms});
                    utils.waitForTime(ms);
                } else |_| {
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
        .assert => {}, // Handled above
        .extract => {
            const selector = cmd.selector orelse {
                std.debug.print("    Error: extract requires selector\n", .{});
                return;
            };
            const output = cmd.output orelse {
                std.debug.print("    Error: extract requires output path\n", .{});
                return;
            };
            const dom_mod = @import("../commands/dom.zig");
            const mode: dom_mod.ExtractMode = if (cmd.mode) |m|
                std.meta.stringToEnum(dom_mod.ExtractMode, m) orelse .dom
            else
                .dom;
            const result_json = dom_mod.executeExtract(session, allocator, selector, mode, cmd.extract_all orelse false) catch |err| {
                std.debug.print("    Error: {}\n", .{err});
                return;
            };
            defer allocator.free(result_json);
            const dir = std.Io.Dir.cwd();
            dir.writeFile(io, .{ .sub_path = output, .data = result_json }) catch |err| {
                std.debug.print("    Error writing: {}\n", .{err});
                return;
            };
            std.debug.print(" -> {s}\n", .{output});
        },
        .dialog => {
            const should_accept = cmd.accept orelse true;
            const timeout_ms = cmd.timeout orelse 5000;
            var dialog_info = page.waitForJavaScriptDialogOpening(allocator, timeout_ms) catch |err| {
                std.debug.print("\n    No dialog appeared: {}\n", .{err});
                return;
            };
            defer dialog_info.deinit(allocator);

            if (cmd.text) |expected_text| {
                const has_wildcard = std.mem.indexOf(u8, expected_text, "*") != null;
                const matches = if (has_wildcard)
                    utils.matchesGlobPattern(dialog_info.message, expected_text)
                else
                    std.mem.eql(u8, dialog_info.message, expected_text);

                if (!matches) {
                    std.debug.print("\n    Dialog message mismatch\n", .{});
                    if (has_wildcard) {
                        std.debug.print("      Pattern: \"{s}\"\n", .{expected_text});
                    } else {
                        std.debug.print("      Expected: \"{s}\"\n", .{expected_text});
                    }
                    std.debug.print("      Actual:  \"{s}\"\n", .{dialog_info.message});
                    return;
                }
                std.debug.print(" (message verified)", .{});
            }

            page.handleJavaScriptDialog(.{
                .accept = should_accept,
                .prompt_text = if (should_accept) cmd.value else null,
            }) catch |err| {
                std.debug.print("\n    Error handling dialog: {}\n", .{err});
                return;
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
        .upload => {
            const files = cmd.files orelse {
                std.debug.print("    Error: upload requires files array\n", .{});
                return;
            };
            if (files.len == 0) {
                std.debug.print("    Error: files array is empty\n", .{});
                return;
            }
            actions.tryWithFallbackSelectorsUpload(session, allocator, io, cmd, files);
        },
        .goto => {
            const target_file = cmd.file orelse {
                std.debug.print("    Error: goto requires file field\n", .{});
                return;
            };

            // Resolve target file path relative to macro file's directory
            const resolved_path = blk: {
                const macro_dir = std.fs.path.dirname(macro_file);
                if (macro_dir) |dir| {
                    // Try joining with macro's directory first
                    const joined = std.fs.path.join(allocator, &.{ dir, target_file }) catch break :blk target_file;

                    // Check if the joined path exists by trying to read it
                    const test_dir = std.Io.Dir.cwd();
                    var test_buf: [1]u8 = undefined;
                    if (test_dir.readFile(io, joined, &test_buf)) |_| {
                        break :blk joined;
                    } else |_| {
                        // File not found relative to macro dir, try CWD
                        allocator.free(joined);
                        break :blk target_file;
                    }
                }
                break :blk target_file;
            };
            defer if (resolved_path.ptr != target_file.ptr) allocator.free(resolved_path);

            std.debug.print(" -> {s}\n", .{resolved_path});
            // Pass full options to nested call (preserves interval, retries, video, etc.)
            var nested_options = options;
            nested_options.video_orch = video_orch; // Ensure orchestrator is passed
            nested_options.resume_mode = false; // Don't resume nested calls
            nested_options.start_index = null;
            replayCommandsWithOptions(session, allocator, io, resolved_path, nested_options) catch |err| {
                std.debug.print("    Error replaying {s}: {}\n", .{ resolved_path, err });
            };
        },
        .capture => {
            const selector = cmd.selector orelse {
                std.debug.print("    Error: capture requires selector\n", .{});
                return;
            };
            const escaped_sel = utils.escapeForJs(allocator, selector) catch |err| {
                std.debug.print("    Error escaping selector: {}\n", .{err});
                return;
            };
            defer allocator.free(escaped_sel);

            var runtime = cdp.Runtime.init(session);
            runtime.enable() catch {};

            // count_as: capture element count
            if (cmd.count_as) |var_name| {
                const js = std.fmt.allocPrint(allocator, "document.querySelectorAll('{s}').length", .{escaped_sel}) catch return;
                defer allocator.free(js);
                var result = runtime.evaluate(allocator, js, .{ .return_by_value = true }) catch return;
                defer result.deinit(allocator);
                if (result.asNumber()) |num| {
                    const int_val: i64 = @intFromFloat(num);
                    const key = allocator.dupe(u8, var_name) catch return;
                    if (variables.fetchRemove(key)) |old| {
                        allocator.free(old.key);
                        var old_val = old.value;
                        old_val.deinit(allocator);
                    }
                    variables.put(key, .{ .int = int_val }) catch {
                        allocator.free(key);
                        return;
                    };
                    std.debug.print(" {s}={}\n", .{ var_name, int_val });
                }
            }
            // text_as: capture text content
            if (cmd.text_as) |var_name| {
                const js = std.fmt.allocPrint(allocator, "document.querySelector('{s}')?.textContent?.trim()||''", .{escaped_sel}) catch return;
                defer allocator.free(js);
                var result = runtime.evaluate(allocator, js, .{ .return_by_value = true }) catch return;
                defer result.deinit(allocator);
                if (result.asString()) |str| {
                    const key = allocator.dupe(u8, var_name) catch return;
                    const val_str = allocator.dupe(u8, str) catch {
                        allocator.free(key);
                        return;
                    };
                    if (variables.fetchRemove(key)) |old| {
                        allocator.free(old.key);
                        var old_val = old.value;
                        old_val.deinit(allocator);
                    }
                    variables.put(key, .{ .string = val_str }) catch {
                        allocator.free(key);
                        allocator.free(val_str);
                        return;
                    };
                    std.debug.print(" {s}=\"{s}\"\n", .{ var_name, str });
                }
            }
            // value_as: capture input value
            if (cmd.value_as) |var_name| {
                const js = std.fmt.allocPrint(allocator, "document.querySelector('{s}')?.value||''", .{escaped_sel}) catch return;
                defer allocator.free(js);
                var result = runtime.evaluate(allocator, js, .{ .return_by_value = true }) catch return;
                defer result.deinit(allocator);
                if (result.asString()) |str| {
                    const key = allocator.dupe(u8, var_name) catch return;
                    const val_str = allocator.dupe(u8, str) catch {
                        allocator.free(key);
                        return;
                    };
                    if (variables.fetchRemove(key)) |old| {
                        allocator.free(old.key);
                        var old_val = old.value;
                        old_val.deinit(allocator);
                    }
                    variables.put(key, .{ .string = val_str }) catch {
                        allocator.free(key);
                        allocator.free(val_str);
                        return;
                    };
                    std.debug.print(" {s}=\"{s}\"\n", .{ var_name, str });
                }
            }
            // attr_as: capture attribute value
            if (cmd.attr_as) |var_name| {
                const attr = cmd.attribute orelse {
                    std.debug.print("    Error: attr_as requires attribute field\n", .{});
                    return;
                };
                const escaped_attr = utils.escapeForJs(allocator, attr) catch return;
                defer allocator.free(escaped_attr);
                const js = std.fmt.allocPrint(allocator, "document.querySelector('{s}')?.getAttribute('{s}')||''", .{ escaped_sel, escaped_attr }) catch return;
                defer allocator.free(js);
                var result = runtime.evaluate(allocator, js, .{ .return_by_value = true }) catch return;
                defer result.deinit(allocator);
                if (result.asString()) |str| {
                    const key = allocator.dupe(u8, var_name) catch return;
                    const val_str = allocator.dupe(u8, str) catch {
                        allocator.free(key);
                        return;
                    };
                    if (variables.fetchRemove(key)) |old| {
                        allocator.free(old.key);
                        var old_val = old.value;
                        old_val.deinit(allocator);
                    }
                    variables.put(key, .{ .string = val_str }) catch {
                        allocator.free(key);
                        allocator.free(val_str);
                        return;
                    };
                    std.debug.print(" {s}=\"{s}\"\n", .{ var_name, str });
                }
            }
        },
    }
}
