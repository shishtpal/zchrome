//! Keyboard commands: press, keyDown, keyUp.

const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");
const actions_mod = @import("../actions/mod.zig");

pub const CommandCtx = types.CommandCtx;

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
