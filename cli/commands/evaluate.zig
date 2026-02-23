//! JavaScript evaluation command.

const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");

pub const CommandCtx = types.CommandCtx;

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
