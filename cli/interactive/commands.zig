//! Command handlers for the interactive REPL.
//!
//! Each command handler receives the state and arguments, executes the
//! appropriate action via the shared command_impl module, and prints the result.

const std = @import("std");
const cdp = @import("cdp");
const help = @import("help.zig");
const config_mod = @import("../config.zig");
const flags_mod = @import("../flags.zig");
const snapshot_mod = @import("../snapshot.zig");
const impl = @import("../commands/mod.zig");
const InteractiveState = @import("mod.zig").InteractiveState;

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub fn requireSession(state: *InteractiveState) !*cdp.Session {
    return state.session orelse {
        std.debug.print("No active session. Use 'pages' to list pages and 'use <id>' to select one.\n", .{});
        return error.NoSession;
    };
}

/// Build a CommandCtx from interactive state and args.
/// Uses unified flag parsing to populate ALL fields, ensuring feature parity with CLI.
/// Allocations are tracked on state._pending_flags and freed at the next buildCtx call.
fn buildCtx(state: *InteractiveState, args: []const []const u8) !impl.CommandCtx {
    // Free allocations from the previous command's buildCtx call
    state.freePendingFlags();
    var flags = try flags_mod.parseCommandFlags(state.allocator, args);
    // Store flags for deferred cleanup (freed at next buildCtx or state.deinit)
    state._pending_flags = flags;
    return .{
        .allocator = state.allocator,
        .io = state.io,
        .positional = flags.positional,
        .output = flags.output,
        .full_page = flags.full_page,
        .session = state.session_ctx,
        // Snapshot options
        .snap_interactive = flags.snap_interactive,
        .snap_compact = flags.snap_compact,
        .snap_depth = flags.snap_depth,
        .snap_selector = flags.snap_selector,
        .snap_mark = flags.snap_mark,
        // Wait options
        .wait_text = flags.wait_text,
        .wait_url = flags.wait_url,
        .wait_load = flags.wait_load,
        .wait_fn = flags.wait_fn,
        .wait_media_playing = flags.wait_media_playing,
        .wait_media_ended = flags.wait_media_ended,
        .wait_media_ready = flags.wait_media_ready,
        .wait_media_error = flags.wait_media_error,
        // Click options
        .click_js = flags.click_js,
        // Replay options
        .replay_retries = flags.replay_retries,
        .replay_retry_delay = flags.replay_retry_delay,
        .replay_fallback = flags.replay_fallback,
        .replay_resume = flags.replay_resume,
        .replay_from = flags.replay_from,
        // DOM options
        .extract_all = flags.extract_all,
    };
}

pub fn printHelp() void {
    help.print();
}

pub fn cmdTab(state: *InteractiveState, args: []const []const u8) !void {
    // Build a simple ctx with just positional args (tab command doesn't use flags)
    const ctx = impl.CommandCtx{
        .allocator = state.allocator,
        .io = state.io,
        .positional = args,
        .session = state.session_ctx,
    };

    const result = try impl.cmdTab(state.browser, state.allocator, ctx, state.target_id);

    // Handle session switching if needed
    if (result.should_switch_session) {
        switch (result.action) {
            .close => {
                // Closed current tab - clear session
                if (state.session) |s| s.deinit();
                state.session = null;
                if (state.target_id) |t| state.allocator.free(t);
                state.target_id = null;
            },
            .switch_tab => {
                // Switch to new session
                if (state.session) |s| s.deinit();
                if (state.target_id) |t| state.allocator.free(t);
                if (result.session_id) |sid| {
                    state.session = try cdp.Session.init(sid, state.browser.connection, state.allocator);
                    state.allocator.free(sid);
                }
                state.target_id = if (result.target_id) |tid| try state.allocator.dupe(u8, tid) else null;

                // Apply saved emulation settings
                if (state.session) |s| {
                    impl.applyEmulationSettings(s, state.allocator, state.io, state.session_ctx);
                }
            },
            else => {},
        }
    }
}

pub fn cmdWindow(state: *InteractiveState, args: []const []const u8) !void {
    const ctx = impl.CommandCtx{
        .allocator = state.allocator,
        .io = state.io,
        .positional = args,
        .session = state.session_ctx,
    };
    try impl.cmdWindow(state.browser, ctx);
}

pub fn cmdVersion(state: *InteractiveState) !void {
    var version = try state.browser.version();
    defer version.deinit(state.allocator);
    std.debug.print("Protocol: {s}\nProduct: {s}\nRevision: {s}\nUser Agent: {s}\nJS Version: {s}\n", .{
        version.protocol_version, version.product, version.revision, version.user_agent, version.js_version,
    });
}

pub fn cmdPages(state: *InteractiveState) !void {
    var target = cdp.Target.init(state.browser.connection);
    const targets = try target.getTargets(state.allocator);
    defer {
        for (targets) |*t| t.*.deinit(state.allocator);
        state.allocator.free(targets);
    }
    std.debug.print("{s:<42} {s:<30} {s:<50}\n", .{ "TARGET ID", "TITLE", "URL" });
    std.debug.print("{s:-<122}\n", .{""});
    var count: usize = 0;
    for (targets) |t| {
        if (std.mem.eql(u8, t.type, "page")) {
            const marker: []const u8 = if (state.target_id != null and std.mem.eql(u8, t.target_id, state.target_id.?)) "* " else "  ";
            std.debug.print("{s}{s:<40} {s:<30} {s:<50}\n", .{ marker, t.target_id, t.title, t.url });
            count += 1;
        }
    }
    if (count == 0) std.debug.print("No pages found.\n", .{}) else std.debug.print("\nTotal: {} page(s). * = current\n", .{count});
}

pub fn cmdUse(state: *InteractiveState, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: use <target-id>\n", .{});
        return;
    }
    if (state.session) |s| s.deinit();
    if (state.target_id) |t| state.allocator.free(t);
    var target = cdp.Target.init(state.browser.connection);
    const session_id = try target.attachToTarget(state.allocator, args[0], true);
    state.session = try cdp.Session.init(session_id, state.browser.connection, state.allocator);
    state.target_id = try state.allocator.dupe(u8, args[0]);

    // Apply saved emulation settings (user agent, viewport, etc.)
    if (state.session) |s| {
        impl.applyEmulationSettings(s, state.allocator, state.io, state.session_ctx);
    }

    std.debug.print("Switched to target: {s}\n", .{args[0]});
}

pub fn cmdNavigate(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.navigate(session, try buildCtx(state, args));
}

pub fn cmdScreenshot(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.screenshot(session, try buildCtx(state, args));
}

pub fn cmdPdf(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.pdf(session, try buildCtx(state, args));
}

pub fn cmdEvaluate(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.evaluate(session, try buildCtx(state, args));
}

pub fn cmdCookies(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.cookies(session, try buildCtx(state, args));
}

pub fn cmdStorage(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.webStorage(session, try buildCtx(state, args));
}

pub fn cmdSnapshot(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    // buildCtx now handles all flag parsing via flags_mod.parseCommandFlags
    try impl.snapshot(session, try buildCtx(state, args));
}

// Element action commands - all delegate to shared impl
pub fn cmdClick(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    // Now properly handles --js flag via buildCtx
    try impl.click(session, try buildCtx(state, args));
}

pub fn cmdDblClick(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.dblclick(session, try buildCtx(state, args));
}

pub fn cmdFill(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.fill(session, try buildCtx(state, args));
}

pub fn cmdType(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.typeText(session, try buildCtx(state, args));
}

pub fn cmdSelect(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.selectOption(session, try buildCtx(state, args));
}

pub fn cmdCheck(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.check(session, try buildCtx(state, args));
}

pub fn cmdUncheck(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.uncheck(session, try buildCtx(state, args));
}

pub fn cmdHover(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.hover(session, try buildCtx(state, args));
}

pub fn cmdFocus(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.focus(session, try buildCtx(state, args));
}

pub fn cmdScroll(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.scroll(session, try buildCtx(state, args));
}

pub fn cmdScrollIntoView(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.scrollIntoView(session, try buildCtx(state, args));
}

pub fn cmdDrag(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.drag(session, try buildCtx(state, args));
}

pub fn cmdUpload(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.upload(session, try buildCtx(state, args));
}

pub fn cmdGet(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.get(session, try buildCtx(state, args));
}

pub fn cmdBack(state: *InteractiveState) !void {
    const session = try requireSession(state);
    try impl.back(session);
}

pub fn cmdForward(state: *InteractiveState) !void {
    const session = try requireSession(state);
    try impl.forward(session);
}

pub fn cmdReload(state: *InteractiveState) !void {
    const session = try requireSession(state);
    try impl.reload(session);
}

pub fn cmdPress(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.press(session, try buildCtx(state, args));
}

pub fn cmdKeyDown(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.keyDown(session, try buildCtx(state, args));
}

pub fn cmdKeyUp(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.keyUp(session, try buildCtx(state, args));
}

pub fn cmdWait(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    // buildCtx now handles all wait flag parsing via flags_mod.parseCommandFlags
    try impl.wait(session, try buildCtx(state, args));
}

// ─── Mouse Commands ──────────────────────────────────────────────────────────

/// Thin wrapper: delegates to impl.mouse(), then updates in-memory position
/// if the subcommand was "move" so subsequent down/up/wheel use the new coords.
pub fn cmdMouse(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.mouse(session, try buildCtx(state, args));

    // Keep in-memory position in sync after a successful "move"
    if (args.len >= 3 and eql(args[0], "move")) {
        state.mouse_x = std.fmt.parseFloat(f64, args[1]) catch state.mouse_x;
        state.mouse_y = std.fmt.parseFloat(f64, args[2]) catch state.mouse_y;
    }
}

pub fn cmdSet(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.set(session, try buildCtx(state, args));
}

pub fn cmdCursor(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    // Now properly handles --retries, --retry-delay, etc. via buildCtx
    try impl.cursor(session, try buildCtx(state, args));
}

pub fn cmdNetwork(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.network(session, try buildCtx(state, args));
}

pub fn cmdDialog(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.dialog(session, try buildCtx(state, args));
}

pub fn cmdDev(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.dev(session, try buildCtx(state, args));
}

pub fn cmdDiff(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.diff(session, try buildCtx(state, args));
}

pub fn cmdClipboard(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.clipboardCmd(session, try buildCtx(state, args));
}

pub fn cmdMedia(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.media(session, try buildCtx(state, args));
}

pub fn cmdDom(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    // buildCtx now handles --output/-o and --all/-a via flags_mod.parseCommandFlags
    // extract_all is passed through ctx.extract_all field
    try impl.dom(session, try buildCtx(state, args));
}
