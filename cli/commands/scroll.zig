//! Scroll commands: scroll, scrollIntoView.

const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");
const actions_mod = @import("../actions/mod.zig");

pub const CommandCtx = types.CommandCtx;

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
