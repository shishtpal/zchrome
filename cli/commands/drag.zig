//! Drag and drop command.

const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");
const actions_mod = @import("../actions/mod.zig");

pub const CommandCtx = types.CommandCtx;

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
