//! Command handlers for the interactive REPL.
//!
//! Each command handler receives the state and arguments, executes the
//! appropriate action via the shared command_impl module, and prints the result.

const std = @import("std");
const cdp = @import("cdp");
const config_mod = @import("../config.zig");
const snapshot_mod = @import("../snapshot.zig");
const actions_mod = @import("../actions/mod.zig");
const impl = @import("../command_impl.zig");
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
    std.debug.print(
        \\Commands:
        \\  help, ?               Show this help
        \\  quit, exit            Exit interactive mode
        \\  version               Show browser version
        \\  pages                 List open pages
        \\  use <target-id>       Switch to a different page
        \\
        \\Navigation:
        \\  navigate <url>        Navigate to URL (aliases: nav, goto)
        \\  back                  Go back in history
        \\  forward               Go forward in history
        \\  reload                Reload current page
        \\
        \\Capture:
        \\  screenshot [path]     Take screenshot (aliases: ss)
        \\  pdf [path]            Generate PDF
        \\  snapshot [opts]       Capture accessibility tree (aliases: snap)
        \\    Options: -i (interactive only), -c (compact), -d <n> (depth)
        \\
        \\Inspection:
        \\  evaluate <expr>       Evaluate JavaScript (aliases: eval, js)
        \\  dom <selector>        Query DOM element
        \\  cookies               List cookies
        \\
        \\Element Actions:
        \\  click <selector>      Click element
        \\  dblclick <selector>   Double-click element
        \\  fill <sel> <text>     Clear and fill input
        \\  type <sel> <text>     Type text (append)
        \\  select <sel> <value>  Select dropdown option
        \\  check <selector>      Check checkbox
        \\  uncheck <selector>    Uncheck checkbox
        \\  hover <selector>      Hover over element
        \\  focus <selector>      Focus element
        \\  scroll <dir> [px]     Scroll page (up/down/left/right)
        \\  scrollinto <selector> Scroll element into view
        \\  drag <src> <tgt>      Drag element to target
        \\  upload <sel> <files>  Upload files to input
        \\
        \\Keyboard:
        \\  press <key>           Press key (Enter, Control+a) (alias: key)
        \\  keydown <key>         Hold key down
        \\  keyup <key>           Release key
        \\
        \\Getters:
        \\  get text <sel>        Get text content
        \\  get html <sel>        Get innerHTML
        \\  get value <sel>       Get input value
        \\  get attr <sel> <attr> Get attribute
        \\  get title             Get page title
        \\  get url               Get page URL
        \\  get count <sel>       Count matching elements
        \\  get box <sel>         Get bounding box
        \\
        \\Selectors can be CSS selectors or @refs from snapshot (e.g., @e3)
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

pub fn cmdCookies(state: *InteractiveState) !void {
    const session = try requireSession(state);
    try impl.cookies(session, buildCtx(state, &.{}));
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
