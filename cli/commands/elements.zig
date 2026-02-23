//! Element interaction commands: click, dblclick, focus, type, fill, select, check, uncheck, hover.

const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");
const actions_mod = @import("../actions/mod.zig");

pub const CommandCtx = types.CommandCtx;

pub fn click(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: click <selector>\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    try actions_mod.clickElement(session, ctx.allocator, &resolved, 1, ctx.click_js);
    std.debug.print("Clicked: {s}\n", .{ctx.positional[0]});
}

pub fn dblclick(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: dblclick <selector>\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    try actions_mod.clickElement(session, ctx.allocator, &resolved, 2, ctx.click_js);
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
