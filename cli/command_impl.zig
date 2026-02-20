//! Shared command implementations used by both CLI and interactive REPL.
//!
//! Each function takes a `*cdp.Session` and a `CommandCtx` containing
//! allocator, io, and positional arguments. This avoids duplicating
//! the command logic across main.zig and interactive/commands.zig.

const std = @import("std");
const cdp = @import("cdp");
const snapshot_mod = @import("snapshot.zig");
const config_mod = @import("config.zig");
const actions_mod = @import("actions/mod.zig");

pub const CommandCtx = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    positional: []const []const u8,
    output: ?[]const u8 = null,
    full_page: bool = false,
    // Snapshot options
    snap_interactive: bool = false,
    snap_compact: bool = false,
    snap_depth: ?usize = null,
    snap_selector: ?[]const u8 = null,
};

// ─── Navigation ─────────────────────────────────────────────────────────────

pub fn navigate(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: navigate <url>\n", .{});
        return;
    }

    const target_url = ctx.positional[0];
    var page = cdp.Page.init(session);
    try page.enable();

    var result = try page.navigate(ctx.allocator, target_url);
    defer result.deinit(ctx.allocator);

    if (result.error_text) |err| {
        std.debug.print("Navigation error: {s}\n", .{err});
        return;
    }

    var i: u32 = 0;
    while (i < 500000) : (i += 1) std.atomic.spinLoopHint();

    var runtime = cdp.Runtime.init(session);
    try runtime.enable();
    const title = runtime.evaluateAs([]const u8, "document.title") catch "Unknown";
    std.debug.print("URL: {s}\nTitle: {s}\n", .{ target_url, title });
}

pub fn back(session: *cdp.Session) !void {
    var page = cdp.Page.init(session);
    if (try page.goBack())
        std.debug.print("Navigated back\n", .{})
    else
        std.debug.print("No previous page in history\n", .{});
}

pub fn forward(session: *cdp.Session) !void {
    var page = cdp.Page.init(session);
    if (try page.goForward())
        std.debug.print("Navigated forward\n", .{})
    else
        std.debug.print("No next page in history\n", .{});
}

pub fn reload(session: *cdp.Session) !void {
    var page = cdp.Page.init(session);
    try page.reload(null);
    std.debug.print("Page reloaded\n", .{});
}

// ─── Capture ────────────────────────────────────────────────────────────────

pub fn screenshot(session: *cdp.Session, ctx: CommandCtx) !void {
    var page = cdp.Page.init(session);
    try page.enable();

    var j: u32 = 0;
    while (j < 500000) : (j += 1) std.atomic.spinLoopHint();

    const screenshot_data = try page.captureScreenshot(ctx.allocator, .{
        .format = .png,
        .capture_beyond_viewport = if (ctx.full_page) true else null,
    });
    defer ctx.allocator.free(screenshot_data);

    const decoded = try cdp.base64.decodeAlloc(ctx.allocator, screenshot_data);
    defer ctx.allocator.free(decoded);

    const output_path = ctx.output orelse "screenshot.png";
    try writeFile(ctx.io, output_path, decoded);
    std.debug.print("Screenshot saved to {s} ({} bytes){s}\n", .{
        output_path,
        decoded.len,
        if (ctx.full_page) " (full page)" else "",
    });
}

pub fn pdf(session: *cdp.Session, ctx: CommandCtx) !void {
    var page = cdp.Page.init(session);
    try page.enable();

    var j: u32 = 0;
    while (j < 500000) : (j += 1) std.atomic.spinLoopHint();

    const pdf_data = try page.printToPDF(ctx.allocator, .{});
    defer ctx.allocator.free(pdf_data);

    const decoded = try cdp.base64.decodeAlloc(ctx.allocator, pdf_data);
    defer ctx.allocator.free(decoded);

    const output_path = ctx.output orelse "page.pdf";
    try writeFile(ctx.io, output_path, decoded);
    std.debug.print("PDF saved to {s} ({} bytes)\n", .{ output_path, decoded.len });
}

pub fn snapshot(session: *cdp.Session, ctx: CommandCtx) !void {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    const js = try snapshot_mod.buildSnapshotJs(ctx.allocator, ctx.snap_selector, ctx.snap_depth);
    defer ctx.allocator.free(js);

    var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
    defer result.deinit(ctx.allocator);

    const aria_tree = result.asString() orelse "(empty)";

    var processor = snapshot_mod.SnapshotProcessor.init(ctx.allocator);
    defer processor.deinit();

    const options = snapshot_mod.SnapshotOptions{
        .interactive = ctx.snap_interactive,
        .compact = ctx.snap_compact,
        .max_depth = ctx.snap_depth,
        .selector = ctx.snap_selector,
    };

    var snap = try processor.processAriaTree(aria_tree, options);
    defer snap.deinit();

    std.debug.print("{s}\n", .{snap.tree});
    std.debug.print("\n--- {} element(s) with refs ---\n", .{snap.refs.count()});

    const output_path = ctx.output orelse try config_mod.getSnapshotPath(ctx.allocator, ctx.io);
    defer if (ctx.output == null) ctx.allocator.free(output_path);

    try snapshot_mod.saveSnapshot(ctx.allocator, ctx.io, output_path, &snap);

    std.debug.print("\nSnapshot saved to: {s}\n", .{output_path});
    if (snap.refs.count() > 0) {
        std.debug.print("Use @e<N> refs in subsequent commands\n", .{});
    }
}

// ─── Inspection ─────────────────────────────────────────────────────────────

pub fn evaluate(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: evaluate <expression>\n", .{});
        return;
    }

    const expression = ctx.positional[0];
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    var result = try runtime.evaluate(ctx.allocator, expression, .{ .return_by_value = true });
    defer result.deinit(ctx.allocator);

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

pub fn cookies(session: *cdp.Session, ctx: CommandCtx) !void {
    var page = cdp.Page.init(session);
    try page.enable();

    var storage = cdp.Storage.init(session);

    var i: u32 = 0;
    while (i < 500000) : (i += 1) std.atomic.spinLoopHint();

    const cookie_list = try storage.getCookies(ctx.allocator, null);
    defer {
        for (cookie_list) |*c| {
            var cookie = c.*;
            cookie.deinit(ctx.allocator);
        }
        ctx.allocator.free(cookie_list);
    }

    std.debug.print("{s:<30} {s:<40} {s:<20}\n", .{ "Name", "Value", "Domain" });
    std.debug.print("{s:-<90}\n", .{""});
    for (cookie_list) |cookie| {
        std.debug.print("{s:<30} {s:<40} {s:<20}\n", .{ cookie.name, cookie.value, cookie.domain });
    }
}

pub fn network() void {
    std.debug.print("Network monitoring not yet implemented\n", .{});
}

// ─── Element Actions ────────────────────────────────────────────────────────

pub fn click(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: click <selector>\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    try actions_mod.clickElement(session, ctx.allocator, &resolved, 1);
    std.debug.print("Clicked: {s}\n", .{ctx.positional[0]});
}

pub fn dblclick(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: dblclick <selector>\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    try actions_mod.clickElement(session, ctx.allocator, &resolved, 2);
    std.debug.print("Double-clicked: {s}\n", .{ctx.positional[0]});
}

pub fn focus(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: focus <selector>\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    try actions_mod.focusElement(session, ctx.allocator, &resolved);
    std.debug.print("Focused: {s}\n", .{ctx.positional[0]});
}

pub fn typeText(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len < 2) {
        std.debug.print("Usage: type <selector> <text>\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    try actions_mod.focusElement(session, ctx.allocator, &resolved);
    var j: u32 = 0;
    while (j < 500000) : (j += 1) std.atomic.spinLoopHint();
    try actions_mod.typeText(session, ctx.positional[1]);
    std.debug.print("Typed into: {s}\n", .{ctx.positional[0]});
}

pub fn fill(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len < 2) {
        std.debug.print("Usage: fill <selector> <text>\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    try actions_mod.fillElement(session, ctx.allocator, &resolved, ctx.positional[1]);
    std.debug.print("Filled: {s}\n", .{ctx.positional[0]});
}

pub fn selectOption(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len < 2) {
        std.debug.print("Usage: select <selector> <value>\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    try actions_mod.selectOption(session, ctx.allocator, &resolved, ctx.positional[1]);
    std.debug.print("Selected '{s}' in: {s}\n", .{ ctx.positional[1], ctx.positional[0] });
}

pub fn check(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: check <selector>\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    try actions_mod.setChecked(session, ctx.allocator, &resolved, true);
    std.debug.print("Checked: {s}\n", .{ctx.positional[0]});
}

pub fn uncheck(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: uncheck <selector>\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    try actions_mod.setChecked(session, ctx.allocator, &resolved, false);
    std.debug.print("Unchecked: {s}\n", .{ctx.positional[0]});
}

pub fn hover(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: hover <selector>\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    try actions_mod.hoverElement(session, ctx.allocator, &resolved);
    std.debug.print("Hovering: {s}\n", .{ctx.positional[0]});
}

pub fn scroll(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: scroll <up|down|left|right> [pixels]\n", .{});
        return;
    }

    const direction = ctx.positional[0];
    const pixels: f64 = if (ctx.positional.len > 1)
        @floatFromInt(std.fmt.parseInt(i32, ctx.positional[1], 10) catch 300)
    else
        300;

    var delta_x: f64 = 0;
    var delta_y: f64 = 0;

    if (std.mem.eql(u8, direction, "up")) {
        delta_y = -pixels;
    } else if (std.mem.eql(u8, direction, "down")) {
        delta_y = pixels;
    } else if (std.mem.eql(u8, direction, "left")) {
        delta_x = -pixels;
    } else if (std.mem.eql(u8, direction, "right")) {
        delta_x = pixels;
    } else {
        std.debug.print("Invalid direction: {s}. Use up, down, left, or right.\n", .{direction});
        return;
    }

    try actions_mod.scroll(session, delta_x, delta_y);
    std.debug.print("Scrolled {s} {d}px\n", .{ direction, pixels });
}

pub fn scrollIntoView(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: scrollintoview <selector>\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    try actions_mod.scrollIntoView(session, ctx.allocator, &resolved);
    std.debug.print("Scrolled into view: {s}\n", .{ctx.positional[0]});
}

pub fn drag(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len < 2) {
        std.debug.print("Usage: drag <source-selector> <target-selector>\n", .{});
        return;
    }
    var src_resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer src_resolved.deinit();
    var tgt_resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[1]);
    defer tgt_resolved.deinit();
    try actions_mod.dragElement(session, ctx.allocator, &src_resolved, &tgt_resolved);
    std.debug.print("Dragged: {s} -> {s}\n", .{ ctx.positional[0], ctx.positional[1] });
}

pub fn upload(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len < 2) {
        std.debug.print("Usage: upload <selector> <file1> [file2...]\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    const files = ctx.positional[1..];
    try actions_mod.uploadFiles(session, ctx.allocator, ctx.io, &resolved, files);
    std.debug.print("Uploaded {} file(s) to: {s}\n", .{ files.len, ctx.positional[0] });
}

// ─── Keyboard ───────────────────────────────────────────────────────────────

pub fn press(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: press <key>\n", .{});
        std.debug.print("Examples: press Enter, press Tab, press Control+a\n", .{});
        return;
    }
    try actions_mod.pressKey(session, ctx.positional[0]);
    std.debug.print("Pressed: {s}\n", .{ctx.positional[0]});
}

pub fn keyDown(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: keydown <key>\n", .{});
        return;
    }
    try actions_mod.keyDown(session, ctx.positional[0]);
    std.debug.print("Key down: {s}\n", .{ctx.positional[0]});
}

pub fn keyUp(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: keyup <key>\n", .{});
        return;
    }
    try actions_mod.keyUp(session, ctx.positional[0]);
    std.debug.print("Key up: {s}\n", .{ctx.positional[0]});
}

// ─── Getters ────────────────────────────────────────────────────────────────

pub fn get(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        printGetUsage();
        return;
    }

    const subcommand = ctx.positional[0];

    if (std.mem.eql(u8, subcommand, "title")) {
        const title = try actions_mod.getPageTitle(session, ctx.allocator);
        defer ctx.allocator.free(title);
        std.debug.print("{s}\n", .{title});
        return;
    }

    if (std.mem.eql(u8, subcommand, "url")) {
        const url = try actions_mod.getPageUrl(session, ctx.allocator);
        defer ctx.allocator.free(url);
        std.debug.print("{s}\n", .{url});
        return;
    }

    if (ctx.positional.len < 2) {
        std.debug.print("Error: Missing selector\n", .{});
        printGetUsage();
        return;
    }

    const selector = ctx.positional[1];

    if (std.mem.eql(u8, subcommand, "text")) {
        var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, selector);
        defer resolved.deinit();
        if (try actions_mod.getText(session, ctx.allocator, &resolved)) |text| {
            defer ctx.allocator.free(text);
            std.debug.print("{s}\n", .{text});
        } else {
            std.debug.print("(not found)\n", .{});
        }
    } else if (std.mem.eql(u8, subcommand, "html")) {
        var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, selector);
        defer resolved.deinit();
        if (try actions_mod.getHtml(session, ctx.allocator, &resolved)) |html| {
            defer ctx.allocator.free(html);
            std.debug.print("{s}\n", .{html});
        } else {
            std.debug.print("(not found)\n", .{});
        }
    } else if (std.mem.eql(u8, subcommand, "dom")) {
        var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, selector);
        defer resolved.deinit();

        const js = try actions_mod.helpers.buildGetterJs(ctx.allocator, &resolved, "el.outerHTML");
        defer ctx.allocator.free(js);

        var runtime = cdp.Runtime.init(session);
        try runtime.enable();

        var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
        defer result.deinit(ctx.allocator);

        if (result.asString()) |html| {
            std.debug.print("{s}\n", .{html});
        } else {
            std.debug.print("(not found)\n", .{});
        }
    } else if (std.mem.eql(u8, subcommand, "value")) {
        var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, selector);
        defer resolved.deinit();
        if (try actions_mod.getValue(session, ctx.allocator, &resolved)) |value| {
            defer ctx.allocator.free(value);
            std.debug.print("{s}\n", .{value});
        } else {
            std.debug.print("(not found)\n", .{});
        }
    } else if (std.mem.eql(u8, subcommand, "attr")) {
        if (ctx.positional.len < 3) {
            std.debug.print("Error: Missing attribute name\nUsage: get attr <selector> <attribute>\n", .{});
            return;
        }
        var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, selector);
        defer resolved.deinit();
        if (try actions_mod.getAttribute(session, ctx.allocator, &resolved, ctx.positional[2])) |v| {
            defer ctx.allocator.free(v);
            std.debug.print("{s}\n", .{v});
        } else {
            std.debug.print("(null)\n", .{});
        }
    } else if (std.mem.eql(u8, subcommand, "count")) {
        const count = try actions_mod.getCount(session, ctx.allocator, selector);
        std.debug.print("{}\n", .{count});
    } else if (std.mem.eql(u8, subcommand, "box")) {
        var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, selector);
        defer resolved.deinit();
        const pos = actions_mod.getElementPosition(session, ctx.allocator, &resolved) catch {
            std.debug.print("(not found)\n", .{});
            return;
        };
        std.debug.print("x={d:.0} y={d:.0} width={d:.0} height={d:.0}\n", .{ pos.x, pos.y, pos.width, pos.height });
    } else if (std.mem.eql(u8, subcommand, "styles")) {
        var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, selector);
        defer resolved.deinit();
        if (try actions_mod.getStyles(session, ctx.allocator, &resolved)) |styles| {
            defer ctx.allocator.free(styles);
            std.debug.print("{s}\n", .{styles});
        } else {
            std.debug.print("(not found)\n", .{});
        }
    } else {
        std.debug.print("Unknown subcommand: {s}\n", .{subcommand});
        printGetUsage();
    }
}

fn printGetUsage() void {
    std.debug.print(
        \\Usage: get <subcommand> [selector] [args]
        \\
        \\Subcommands:
        \\  text <sel>           Get text content
        \\  html <sel>           Get innerHTML
        \\  dom <sel>            Get outerHTML
        \\  value <sel>          Get input value
        \\  attr <sel> <attr>    Get attribute value
        \\  title                Get page title
        \\  url                  Get current URL
        \\  count <sel>          Count matching elements
        \\  box <sel>            Get bounding box
        \\  styles <sel>         Get computed styles (JSON)
        \\
    , .{});
}

// ─── Dispatch ───────────────────────────────────────────────────────────────

/// Dispatch a session-level command. Returns true if handled.
pub fn dispatchSessionCommand(session: *cdp.Session, command: anytype, ctx: CommandCtx) !bool {
    switch (command) {
        .navigate => try navigate(session, ctx),
        .screenshot => try screenshot(session, ctx),
        .pdf => try pdf(session, ctx),
        .evaluate => try evaluate(session, ctx),
        .network => network(),
        .cookies => try cookies(session, ctx),
        .snapshot => try snapshot(session, ctx),
        .click => try click(session, ctx),
        .dblclick => try dblclick(session, ctx),
        .focus => try focus(session, ctx),
        .type => try typeText(session, ctx),
        .fill => try fill(session, ctx),
        .select => try selectOption(session, ctx),
        .hover => try hover(session, ctx),
        .check => try check(session, ctx),
        .uncheck => try uncheck(session, ctx),
        .scroll => try scroll(session, ctx),
        .scrollintoview => try scrollIntoView(session, ctx),
        .drag => try drag(session, ctx),
        .get => try get(session, ctx),
        .upload => try upload(session, ctx),
        .back => try back(session),
        .forward => try forward(session),
        .reload => try reload(session),
        .press => try press(session, ctx),
        .keydown => try keyDown(session, ctx),
        .keyup => try keyUp(session, ctx),
        else => {
            std.debug.print("Warning: unhandled command in dispatchSessionCommand\n", .{});
            return false;
        },
    }
    return true;
}

// ─── Helpers ────────────────────────────────────────────────────────────────

fn writeFile(io: std.Io, path: []const u8, data: []const u8) !void {
    const dir = std.Io.Dir.cwd();
    dir.writeFile(io, .{ .sub_path = path, .data = data }) catch |err| {
        std.debug.print("Error writing {s}: {}\n", .{ path, err });
        return err;
    };
}
