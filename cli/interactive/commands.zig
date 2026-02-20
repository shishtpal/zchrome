//! Command handlers for the interactive REPL.
//!
//! Each command handler receives the state and arguments, executes the
//! appropriate action, and prints the result.

const std = @import("std");
const cdp = @import("cdp");
const config_mod = @import("../config.zig");
const snapshot_mod = @import("../snapshot.zig");
const actions_mod = @import("../actions/mod.zig");
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
    if (args.len == 0) {
        std.debug.print("Usage: navigate <url>\n", .{});
        return;
    }
    const session = try requireSession(state);
    var page = cdp.Page.init(session);
    try page.enable();
    var result = try page.navigate(state.allocator, args[0]);
    defer result.deinit(state.allocator);
    if (result.error_text) |err| {
        std.debug.print("Navigation error: {s}\n", .{err});
        return;
    }
    var i: u32 = 0;
    while (i < 500000) : (i += 1) std.atomic.spinLoopHint();
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();
    const title = runtime.evaluateAs([]const u8, "document.title") catch "Unknown";
    std.debug.print("URL: {s}\nTitle: {s}\n", .{ args[0], title });
}

pub fn cmdScreenshot(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    var page = cdp.Page.init(session);
    try page.enable();
    const screenshot_data = try page.captureScreenshot(state.allocator, .{ .format = .png });
    defer state.allocator.free(screenshot_data);
    const decoded = try cdp.base64.decodeAlloc(state.allocator, screenshot_data);
    defer state.allocator.free(decoded);
    const output_path = if (args.len > 0) args[0] else "screenshot.png";
    const dir = std.Io.Dir.cwd();
    dir.writeFile(state.io, .{ .sub_path = output_path, .data = decoded }) catch |err| {
        std.debug.print("Error writing file: {}\n", .{err});
        return;
    };
    std.debug.print("Screenshot saved to {s} ({} bytes)\n", .{ output_path, decoded.len });
}

pub fn cmdPdf(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    var page = cdp.Page.init(session);
    try page.enable();
    const pdf_data = try page.printToPDF(state.allocator, .{});
    defer state.allocator.free(pdf_data);
    const decoded = try cdp.base64.decodeAlloc(state.allocator, pdf_data);
    defer state.allocator.free(decoded);
    const output_path = if (args.len > 0) args[0] else "page.pdf";
    const dir = std.Io.Dir.cwd();
    dir.writeFile(state.io, .{ .sub_path = output_path, .data = decoded }) catch |err| {
        std.debug.print("Error writing file: {}\n", .{err});
        return;
    };
    std.debug.print("PDF saved to {s} ({} bytes)\n", .{ output_path, decoded.len });
}

pub fn cmdEvaluate(state: *InteractiveState, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: evaluate <expression>\n", .{});
        return;
    }
    const session = try requireSession(state);
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();
    var result = try runtime.evaluate(state.allocator, args[0], .{ .return_by_value = true });
    defer result.deinit(state.allocator);
    if (result.value) |v| {
        switch (v) {
            .string => |s| std.debug.print("{s}\n", .{s}),
            .integer => |int_val| std.debug.print("{}\n", .{int_val}),
            .float => |f| std.debug.print("{d}\n", .{f}),
            .bool => |b| std.debug.print("{}\n", .{b}),
            .null => std.debug.print("null\n", .{}),
            else => std.debug.print("[complex value]\n", .{}),
        }
    } else {
        std.debug.print("{s}\n", .{result.description orelse "undefined"});
    }
}

pub fn cmdDom(state: *InteractiveState, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: dom <selector>\n", .{});
        return;
    }
    const session = try requireSession(state);
    var page = cdp.Page.init(session);
    try page.enable();
    var dom = cdp.DOM.init(session);
    try dom.enable();
    const doc = try dom.getDocument(state.allocator, 1);
    defer {
        var d = doc;
        d.deinit(state.allocator);
    }
    const node_id = try dom.querySelector(doc.node_id, args[0]);
    const html = try dom.getOuterHTML(state.allocator, node_id);
    defer state.allocator.free(html);
    std.debug.print("{s}\n", .{html});
}

pub fn cmdCookies(state: *InteractiveState) !void {
    const session = try requireSession(state);
    var storage = cdp.Storage.init(session);
    const cookies = try storage.getCookies(state.allocator, null);
    defer {
        for (cookies) |*c| c.*.deinit(state.allocator);
        state.allocator.free(cookies);
    }
    std.debug.print("{s:<30} {s:<40} {s:<20}\n", .{ "Name", "Value", "Domain" });
    std.debug.print("{s:-<90}\n", .{""});
    for (cookies) |cookie| std.debug.print("{s:<30} {s:<40} {s:<20}\n", .{ cookie.name, cookie.value, cookie.domain });
}

pub fn cmdSnapshot(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    var snap_interactive = false;
    var snap_compact = false;
    var snap_depth: ?usize = null;
    var snap_selector: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (eql(arg, "-i") or eql(arg, "--interactive-only")) snap_interactive = true
        else if (eql(arg, "-c") or eql(arg, "--compact")) snap_compact = true
        else if (eql(arg, "-d") or eql(arg, "--depth")) {
            i += 1;
            if (i < args.len) snap_depth = std.fmt.parseInt(usize, args[i], 10) catch null;
        } else if (eql(arg, "-s") or eql(arg, "--selector")) {
            i += 1;
            if (i < args.len) snap_selector = args[i];
        }
    }
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();
    const js = try snapshot_mod.buildSnapshotJs(state.allocator, snap_selector, snap_depth);
    defer state.allocator.free(js);
    var result = try runtime.evaluate(state.allocator, js, .{ .return_by_value = true });
    defer result.deinit(state.allocator);
    const aria_tree = result.asString() orelse "(empty)";
    var processor = snapshot_mod.SnapshotProcessor.init(state.allocator);
    defer processor.deinit();
    const options = snapshot_mod.SnapshotOptions{ .interactive = snap_interactive, .compact = snap_compact, .max_depth = snap_depth, .selector = snap_selector };
    var snapshot = try processor.processAriaTree(aria_tree, options);
    defer snapshot.deinit();
    std.debug.print("{s}\n\n--- {} element(s) with refs ---\n", .{ snapshot.tree, snapshot.refs.count() });
    const output_path = try config_mod.getSnapshotPath(state.allocator, state.io);
    defer state.allocator.free(output_path);
    try snapshot_mod.saveSnapshot(state.allocator, state.io, output_path, &snapshot);
    std.debug.print("\nSnapshot saved to: {s}\n", .{output_path});
}

// Element action commands
pub fn cmdClick(state: *InteractiveState, args: []const []const u8) !void {
    if (args.len == 0) { std.debug.print("Usage: click <selector>\n", .{}); return; }
    const session = try requireSession(state);
    var resolved = try actions_mod.resolveSelector(state.allocator, state.io, args[0]);
    defer resolved.deinit();
    try actions_mod.clickElement(session, state.allocator, &resolved, 1);
    std.debug.print("Clicked: {s}\n", .{args[0]});
}

pub fn cmdDblClick(state: *InteractiveState, args: []const []const u8) !void {
    if (args.len == 0) { std.debug.print("Usage: dblclick <selector>\n", .{}); return; }
    const session = try requireSession(state);
    var resolved = try actions_mod.resolveSelector(state.allocator, state.io, args[0]);
    defer resolved.deinit();
    try actions_mod.clickElement(session, state.allocator, &resolved, 2);
    std.debug.print("Double-clicked: {s}\n", .{args[0]});
}

pub fn cmdFill(state: *InteractiveState, args: []const []const u8) !void {
    if (args.len < 2) { std.debug.print("Usage: fill <selector> <text>\n", .{}); return; }
    const session = try requireSession(state);
    var resolved = try actions_mod.resolveSelector(state.allocator, state.io, args[0]);
    defer resolved.deinit();
    try actions_mod.fillElement(session, state.allocator, &resolved, args[1]);
    std.debug.print("Filled: {s}\n", .{args[0]});
}

pub fn cmdType(state: *InteractiveState, args: []const []const u8) !void {
    if (args.len < 2) { std.debug.print("Usage: type <selector> <text>\n", .{}); return; }
    const session = try requireSession(state);
    var resolved = try actions_mod.resolveSelector(state.allocator, state.io, args[0]);
    defer resolved.deinit();
    try actions_mod.focusElement(session, state.allocator, &resolved);
    var j: u32 = 0;
    while (j < 500000) : (j += 1) std.atomic.spinLoopHint();
    try actions_mod.typeText(session, args[1]);
    std.debug.print("Typed into: {s}\n", .{args[0]});
}

pub fn cmdSelect(state: *InteractiveState, args: []const []const u8) !void {
    if (args.len < 2) { std.debug.print("Usage: select <selector> <value>\n", .{}); return; }
    const session = try requireSession(state);
    var resolved = try actions_mod.resolveSelector(state.allocator, state.io, args[0]);
    defer resolved.deinit();
    try actions_mod.selectOption(session, state.allocator, &resolved, args[1]);
    std.debug.print("Selected '{s}' in: {s}\n", .{ args[1], args[0] });
}

pub fn cmdCheck(state: *InteractiveState, args: []const []const u8) !void {
    if (args.len == 0) { std.debug.print("Usage: check <selector>\n", .{}); return; }
    const session = try requireSession(state);
    var resolved = try actions_mod.resolveSelector(state.allocator, state.io, args[0]);
    defer resolved.deinit();
    try actions_mod.setChecked(session, state.allocator, &resolved, true);
    std.debug.print("Checked: {s}\n", .{args[0]});
}

pub fn cmdUncheck(state: *InteractiveState, args: []const []const u8) !void {
    if (args.len == 0) { std.debug.print("Usage: uncheck <selector>\n", .{}); return; }
    const session = try requireSession(state);
    var resolved = try actions_mod.resolveSelector(state.allocator, state.io, args[0]);
    defer resolved.deinit();
    try actions_mod.setChecked(session, state.allocator, &resolved, false);
    std.debug.print("Unchecked: {s}\n", .{args[0]});
}

pub fn cmdHover(state: *InteractiveState, args: []const []const u8) !void {
    if (args.len == 0) { std.debug.print("Usage: hover <selector>\n", .{}); return; }
    const session = try requireSession(state);
    var resolved = try actions_mod.resolveSelector(state.allocator, state.io, args[0]);
    defer resolved.deinit();
    try actions_mod.hoverElement(session, state.allocator, &resolved);
    std.debug.print("Hovering: {s}\n", .{args[0]});
}

pub fn cmdFocus(state: *InteractiveState, args: []const []const u8) !void {
    if (args.len == 0) { std.debug.print("Usage: focus <selector>\n", .{}); return; }
    const session = try requireSession(state);
    var resolved = try actions_mod.resolveSelector(state.allocator, state.io, args[0]);
    defer resolved.deinit();
    try actions_mod.focusElement(session, state.allocator, &resolved);
    std.debug.print("Focused: {s}\n", .{args[0]});
}

pub fn cmdScroll(state: *InteractiveState, args: []const []const u8) !void {
    if (args.len == 0) { std.debug.print("Usage: scroll <up|down|left|right> [pixels]\n", .{}); return; }
    const session = try requireSession(state);
    const direction = args[0];
    const pixels: f64 = if (args.len > 1) @floatFromInt(std.fmt.parseInt(i32, args[1], 10) catch 300) else 300;
    var delta_x: f64 = 0;
    var delta_y: f64 = 0;
    if (eql(direction, "up")) delta_y = -pixels
    else if (eql(direction, "down")) delta_y = pixels
    else if (eql(direction, "left")) delta_x = -pixels
    else if (eql(direction, "right")) delta_x = pixels
    else { std.debug.print("Invalid direction: {s}. Use up, down, left, or right.\n", .{direction}); return; }
    try actions_mod.scroll(session, delta_x, delta_y);
    std.debug.print("Scrolled {s} {d}px\n", .{ direction, pixels });
}

pub fn cmdScrollIntoView(state: *InteractiveState, args: []const []const u8) !void {
    if (args.len == 0) { std.debug.print("Usage: scrollinto <selector>\n", .{}); return; }
    const session = try requireSession(state);
    var resolved = try actions_mod.resolveSelector(state.allocator, state.io, args[0]);
    defer resolved.deinit();
    try actions_mod.scrollIntoView(session, state.allocator, &resolved);
    std.debug.print("Scrolled into view: {s}\n", .{args[0]});
}

pub fn cmdDrag(state: *InteractiveState, args: []const []const u8) !void {
    if (args.len < 2) { std.debug.print("Usage: drag <source> <target>\n", .{}); return; }
    const session = try requireSession(state);
    var src = try actions_mod.resolveSelector(state.allocator, state.io, args[0]);
    defer src.deinit();
    var tgt = try actions_mod.resolveSelector(state.allocator, state.io, args[1]);
    defer tgt.deinit();
    try actions_mod.dragElement(session, state.allocator, &src, &tgt);
    std.debug.print("Dragged: {s} -> {s}\n", .{ args[0], args[1] });
}

pub fn cmdUpload(state: *InteractiveState, args: []const []const u8) !void {
    if (args.len < 2) { std.debug.print("Usage: upload <selector> <file1> [file2...]\n", .{}); return; }
    const session = try requireSession(state);
    var resolved = try actions_mod.resolveSelector(state.allocator, state.io, args[0]);
    defer resolved.deinit();
    try actions_mod.uploadFiles(session, state.allocator, state.io, &resolved, args[1..]);
    std.debug.print("Uploaded {} file(s) to: {s}\n", .{ args.len - 1, args[0] });
}

pub fn cmdGet(state: *InteractiveState, args: []const []const u8) !void {
    if (args.len == 0) { printGetHelp(); return; }
    const session = try requireSession(state);
    const sub = args[0];
    if (eql(sub, "title")) {
        const title = try actions_mod.getPageTitle(session, state.allocator);
        defer state.allocator.free(title);
        std.debug.print("{s}\n", .{title});
    } else if (eql(sub, "url")) {
        const url = try actions_mod.getPageUrl(session, state.allocator);
        defer state.allocator.free(url);
        std.debug.print("{s}\n", .{url});
    } else if (args.len < 2) {
        std.debug.print("Error: Missing selector\n", .{});
        printGetHelp();
    } else {
        const sel = args[1];
        if (eql(sub, "text")) {
            var r = try actions_mod.resolveSelector(state.allocator, state.io, sel);
            defer r.deinit();
            if (try actions_mod.getText(session, state.allocator, &r)) |t| { defer state.allocator.free(t); std.debug.print("{s}\n", .{t}); } else std.debug.print("(not found)\n", .{});
        } else if (eql(sub, "html")) {
            var r = try actions_mod.resolveSelector(state.allocator, state.io, sel);
            defer r.deinit();
            if (try actions_mod.getHtml(session, state.allocator, &r)) |h| { defer state.allocator.free(h); std.debug.print("{s}\n", .{h}); } else std.debug.print("(not found)\n", .{});
        } else if (eql(sub, "value")) {
            var r = try actions_mod.resolveSelector(state.allocator, state.io, sel);
            defer r.deinit();
            if (try actions_mod.getValue(session, state.allocator, &r)) |v| { defer state.allocator.free(v); std.debug.print("{s}\n", .{v}); } else std.debug.print("(not found)\n", .{});
        } else if (eql(sub, "attr")) {
            if (args.len < 3) { std.debug.print("Usage: get attr <selector> <attribute>\n", .{}); return; }
            var r = try actions_mod.resolveSelector(state.allocator, state.io, sel);
            defer r.deinit();
            if (try actions_mod.getAttribute(session, state.allocator, &r, args[2])) |v| { defer state.allocator.free(v); std.debug.print("{s}\n", .{v}); } else std.debug.print("(null)\n", .{});
        } else if (eql(sub, "count")) {
            const count = try actions_mod.getCount(session, state.allocator, sel);
            std.debug.print("{}\n", .{count});
        } else if (eql(sub, "box")) {
            var r = try actions_mod.resolveSelector(state.allocator, state.io, sel);
            defer r.deinit();
            const pos = actions_mod.getElementPosition(session, state.allocator, &r) catch { std.debug.print("(not found)\n", .{}); return; };
            std.debug.print("x={d:.0} y={d:.0} width={d:.0} height={d:.0}\n", .{ pos.x, pos.y, pos.width, pos.height });
        } else if (eql(sub, "styles")) {
            var r = try actions_mod.resolveSelector(state.allocator, state.io, sel);
            defer r.deinit();
            if (try actions_mod.getStyles(session, state.allocator, &r)) |s| { defer state.allocator.free(s); std.debug.print("{s}\n", .{s}); } else std.debug.print("(not found)\n", .{});
        } else { std.debug.print("Unknown: {s}\n", .{sub}); printGetHelp(); }
    }
}

fn printGetHelp() void {
    std.debug.print(
        \\Usage: get <subcommand> [selector] [args]
        \\  text <sel>           Get text content
        \\  html <sel>           Get innerHTML
        \\  value <sel>          Get input value
        \\  attr <sel> <attr>    Get attribute
        \\  title                Get page title
        \\  url                  Get current URL
        \\  count <sel>          Count elements
        \\  box <sel>            Get bounding box
        \\  styles <sel>         Get computed styles
        \\
    , .{});
}

pub fn cmdBack(state: *InteractiveState) !void {
    const session = try requireSession(state);
    var page = cdp.Page.init(session);
    if (try page.goBack()) std.debug.print("Navigated back\n", .{}) else std.debug.print("No previous page\n", .{});
}

pub fn cmdForward(state: *InteractiveState) !void {
    const session = try requireSession(state);
    var page = cdp.Page.init(session);
    if (try page.goForward()) std.debug.print("Navigated forward\n", .{}) else std.debug.print("No next page\n", .{});
}

pub fn cmdReload(state: *InteractiveState) !void {
    const session = try requireSession(state);
    var page = cdp.Page.init(session);
    try page.reload(null);
    std.debug.print("Page reloaded\n", .{});
}

// ─── Keyboard Commands ──────────────────────────────────────────────────────

pub fn cmdPress(state: *InteractiveState, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: press <key>\n", .{});
        std.debug.print("Examples: press Enter, press Tab, press Control+a\n", .{});
        return;
    }
    const session = try requireSession(state);
    try actions_mod.pressKey(session, args[0]);
    std.debug.print("Pressed: {s}\n", .{args[0]});
}

pub fn cmdKeyDown(state: *InteractiveState, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: keydown <key>\n", .{});
        return;
    }
    const session = try requireSession(state);
    try actions_mod.keyDown(session, args[0]);
    std.debug.print("Key down: {s}\n", .{args[0]});
}

pub fn cmdKeyUp(state: *InteractiveState, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: keyup <key>\n", .{});
        return;
    }
    const session = try requireSession(state);
    try actions_mod.keyUp(session, args[0]);
    std.debug.print("Key up: {s}\n", .{args[0]});
}
