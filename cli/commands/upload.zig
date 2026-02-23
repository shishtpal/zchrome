//! File upload command.

const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");
const actions_mod = @import("../actions/mod.zig");

pub const CommandCtx = types.CommandCtx;

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
