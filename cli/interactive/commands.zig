//! Command handlers for the interactive REPL.
//!
//! Each command handler receives the state and arguments, executes the
//! appropriate action via the shared command_impl module, and prints the result.

const std = @import("std");
const cdp = @import("cdp");
const help = @import("help.zig");
const config_mod = @import("../config.zig");
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

/// Build a CommandCtx from interactive state and args
fn buildCtx(state: *InteractiveState, args: []const []const u8) impl.CommandCtx {
    return .{
        .allocator = state.allocator,
        .io = state.io,
        .positional = args,
    };
}

pub fn printHelp() void {
    help.print();
}

pub fn cmdTab(state: *InteractiveState, args: []const []const u8) !void {
    var target = cdp.Target.init(state.browser.connection);

    // tab new [url]
    if (args.len >= 1 and eql(args[0], "new")) {
        const url = if (args.len >= 2) args[1] else "about:blank";
        const target_id = try target.createTarget(url);
        std.debug.print("New tab: {s}\n", .{target_id});
        return;
    }

    // tab close [n]
    if (args.len >= 1 and eql(args[0], "close")) {
        const page_tabs = try state.browser.pages();
        defer {
            for (page_tabs) |*p| p.*.deinit(state.allocator);
            state.allocator.free(page_tabs);
        }
        if (page_tabs.len == 0) {
            std.debug.print("No tabs open\n", .{});
            return;
        }
        var close_idx: usize = page_tabs.len - 1;
        if (args.len >= 2) {
            close_idx = std.fmt.parseInt(usize, args[1], 10) catch {
                std.debug.print("Invalid tab number: {s}\n", .{args[1]});
                return;
            };
            if (close_idx == 0 or close_idx > page_tabs.len) {
                std.debug.print("Tab number out of range (1-{})\n", .{page_tabs.len});
                return;
            }
            close_idx -= 1;
        }
        const success = try target.closeTarget(page_tabs[close_idx].target_id);
        if (success) {
            std.debug.print("Closed tab {}: {s}\n", .{ close_idx + 1, page_tabs[close_idx].title });
            // If we closed our current tab, clear session
            if (state.target_id != null and std.mem.eql(u8, state.target_id.?, page_tabs[close_idx].target_id)) {
                if (state.session) |s| s.deinit();
                state.session = null;
                state.allocator.free(state.target_id.?);
                state.target_id = null;
            }
        } else {
            std.debug.print("Failed to close tab\n", .{});
        }
        return;
    }

    // tab <n> — switch to tab n
    if (args.len >= 1) {
        const tab_num = std.fmt.parseInt(usize, args[0], 10) catch {
            std.debug.print("Unknown subcommand: {s}\n", .{args[0]});
            printTabUsage();
            return;
        };
        const page_tabs = try state.browser.pages();
        defer {
            for (page_tabs) |*p| p.*.deinit(state.allocator);
            state.allocator.free(page_tabs);
        }
        if (tab_num == 0 or tab_num > page_tabs.len) {
            std.debug.print("Tab number out of range (1-{})\n", .{page_tabs.len});
            return;
        }
        const selected = page_tabs[tab_num - 1];
        try target.activateTarget(selected.target_id);
        // Switch session to this tab
        if (state.session) |s| s.deinit();
        if (state.target_id) |t| state.allocator.free(t);
        const session_id = try target.attachToTarget(state.allocator, selected.target_id, true);
        state.session = try cdp.Session.init(session_id, state.browser.connection, state.allocator);
        state.target_id = try state.allocator.dupe(u8, selected.target_id);

        // Apply saved emulation settings (user agent, viewport, etc.)
        if (state.session) |s| {
            impl.applyEmulationSettings(s, state.allocator, state.io);
        }

        std.debug.print("Switched to tab {}: {s} ({s})\n", .{ tab_num, selected.title, selected.url });
        return;
    }

    // Default: list tabs
    const page_tabs = try state.browser.pages();
    defer {
        for (page_tabs) |*p| p.*.deinit(state.allocator);
        state.allocator.free(page_tabs);
    }
    if (page_tabs.len == 0) {
        std.debug.print("No tabs open\n", .{});
        return;
    }
    for (page_tabs, 1..) |t, i| {
        const marker: []const u8 = if (state.target_id != null and std.mem.eql(u8, t.target_id, state.target_id.?)) "* " else "  ";
        std.debug.print("{s}{}: {s:<30} {s}\n", .{ marker, i, t.title, t.url });
    }
    std.debug.print("\nTotal: {} tab(s). * = current\n", .{page_tabs.len});
}

fn printTabUsage() void {
    std.debug.print(
        \\Usage: tab [subcommand]
        \\
        \\  tab                  List open tabs
        \\  tab new [url]        Open new tab
        \\  tab <n>              Switch to tab n
        \\  tab close [n]        Close tab n (default: current)
        \\
    , .{});
}

pub fn cmdWindow(state: *InteractiveState, args: []const []const u8) !void {
    if (args.len >= 1 and eql(args[0], "new")) {
        _ = try state.browser.connection.sendCommand("Target.createTarget", .{
            .url = "about:blank",
            .newWindow = true,
        }, null);
        std.debug.print("New window opened\n", .{});
        return;
    }
    std.debug.print(
        \\Usage: window <subcommand>
        \\
        \\  window new           Open new browser window
        \\
    , .{});
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
        impl.applyEmulationSettings(s, state.allocator, state.io);
    }

    std.debug.print("Switched to target: {s}\n", .{args[0]});
}

pub fn cmdNavigate(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.navigate(session, buildCtx(state, args));
}

pub fn cmdScreenshot(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.screenshot(session, buildCtx(state, args));
}

pub fn cmdPdf(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.pdf(session, buildCtx(state, args));
}

pub fn cmdEvaluate(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.evaluate(session, buildCtx(state, args));
}

pub fn cmdCookies(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.cookies(session, buildCtx(state, args));
}

pub fn cmdStorage(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.webStorage(session, buildCtx(state, args));
}

pub fn cmdSnapshot(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    // Parse snapshot-specific options from args
    var snap_interactive = false;
    var snap_compact = false;
    var snap_depth: ?usize = null;
    var snap_selector: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (eql(arg, "-i") or eql(arg, "--interactive-only")) snap_interactive = true else if (eql(arg, "-c") or eql(arg, "--compact")) snap_compact = true else if (eql(arg, "-d") or eql(arg, "--depth")) {
            i += 1;
            if (i < args.len) snap_depth = std.fmt.parseInt(usize, args[i], 10) catch null;
        } else if (eql(arg, "-s") or eql(arg, "--selector")) {
            i += 1;
            if (i < args.len) snap_selector = args[i];
        }
    }
    // Pass the raw args as positional (snapshot ignores positional today, but
    // this keeps the ctx consistent if snapshot is extended to accept a URL).
    var ctx = buildCtx(state, args);
    ctx.snap_interactive = snap_interactive;
    ctx.snap_compact = snap_compact;
    ctx.snap_depth = snap_depth;
    ctx.snap_selector = snap_selector;
    try impl.snapshot(session, ctx);
}

// Element action commands - all delegate to shared impl
pub fn cmdClick(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.click(session, buildCtx(state, args));
}

pub fn cmdDblClick(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.dblclick(session, buildCtx(state, args));
}

pub fn cmdFill(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.fill(session, buildCtx(state, args));
}

pub fn cmdType(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.typeText(session, buildCtx(state, args));
}

pub fn cmdSelect(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.selectOption(session, buildCtx(state, args));
}

pub fn cmdCheck(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.check(session, buildCtx(state, args));
}

pub fn cmdUncheck(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.uncheck(session, buildCtx(state, args));
}

pub fn cmdHover(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.hover(session, buildCtx(state, args));
}

pub fn cmdFocus(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.focus(session, buildCtx(state, args));
}

pub fn cmdScroll(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.scroll(session, buildCtx(state, args));
}

pub fn cmdScrollIntoView(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.scrollIntoView(session, buildCtx(state, args));
}

pub fn cmdDrag(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.drag(session, buildCtx(state, args));
}

pub fn cmdUpload(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.upload(session, buildCtx(state, args));
}

pub fn cmdGet(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.get(session, buildCtx(state, args));
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
    try impl.press(session, buildCtx(state, args));
}

pub fn cmdKeyDown(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.keyDown(session, buildCtx(state, args));
}

pub fn cmdKeyUp(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.keyUp(session, buildCtx(state, args));
}

pub fn cmdWait(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    // Parse wait options from args
    var wait_text: ?[]const u8 = null;
    var wait_url: ?[]const u8 = null;
    var wait_load: ?[]const u8 = null;
    var wait_fn: ?[]const u8 = null;
    var positional: std.ArrayList([]const u8) = .empty;
    defer positional.deinit(state.allocator);

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (eql(arg, "--text") and i + 1 < args.len) {
            i += 1;
            wait_text = args[i];
        } else if (eql(arg, "--match") and i + 1 < args.len) {
            i += 1;
            wait_url = args[i];
        } else if (eql(arg, "--load") and i + 1 < args.len) {
            i += 1;
            wait_load = args[i];
        } else if (eql(arg, "--fn") and i + 1 < args.len) {
            i += 1;
            wait_fn = args[i];
        } else {
            try positional.append(state.allocator, arg);
        }
    }

    var ctx = buildCtx(state, positional.items);
    ctx.wait_text = wait_text;
    ctx.wait_url = wait_url;
    ctx.wait_load = wait_load;
    ctx.wait_fn = wait_fn;
    try impl.wait(session, ctx);
}

// ─── Mouse Commands ──────────────────────────────────────────────────────────

/// Thin wrapper: delegates to impl.mouse(), then updates in-memory position
/// if the subcommand was "move" so subsequent down/up/wheel use the new coords.
pub fn cmdMouse(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.mouse(session, buildCtx(state, args));

    // Keep in-memory position in sync after a successful "move"
    if (args.len >= 3 and eql(args[0], "move")) {
        state.mouse_x = std.fmt.parseFloat(f64, args[1]) catch state.mouse_x;
        state.mouse_y = std.fmt.parseFloat(f64, args[2]) catch state.mouse_y;
    }
}

pub fn cmdSet(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.set(session, buildCtx(state, args));
}

pub fn cmdCursor(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.cursor(session, buildCtx(state, args));
}

pub fn cmdNetwork(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.network(session, buildCtx(state, args));
}
