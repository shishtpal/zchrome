//! Navigation subcommands: exists, parent, next, prev, children

const std = @import("std");
const json = @import("json");
const cdp = @import("cdp");
const cmd_types = @import("../types.zig");
const cmd_helpers = @import("../helpers.zig");
const layout_types = @import("types.zig");
const action_helpers = @import("../../actions/helpers.zig");

pub const CommandCtx = cmd_types.CommandCtx;
const LAYOUT_JS = action_helpers.LAYOUT_JS;

/// exists - check if path is valid
pub fn exists(runtime: *cdp.Runtime, ctx: CommandCtx) !void {
    const path = if (ctx.positional.len > 1) layout_types.extractLayoutPath(ctx.positional[1]) else "";
    const escaped_path = try cmd_helpers.jsStringLiteral(ctx.allocator, path);
    defer ctx.allocator.free(escaped_path);

    const js = try std.fmt.allocPrint(ctx.allocator, "{s}('exists', {s}, null)", .{ LAYOUT_JS, escaped_path });
    defer ctx.allocator.free(js);

    var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
    defer result.deinit(ctx.allocator);

    if (result.value) |val| {
        if (val == .bool) {
            std.debug.print("{}\n", .{val.bool});
            return;
        }
    }
    std.debug.print("false\n", .{});
}

/// parent - get parent path
pub fn parent(runtime: *cdp.Runtime, ctx: CommandCtx) !void {
    if (ctx.positional.len < 2) {
        std.debug.print("Error: Missing path\nUsage: layout parent @L<path>\n", .{});
        return;
    }
    const path = layout_types.extractLayoutPath(ctx.positional[1]);
    const escaped_path = try cmd_helpers.jsStringLiteral(ctx.allocator, path);
    defer ctx.allocator.free(escaped_path);

    const js = try std.fmt.allocPrint(ctx.allocator, "{s}('parent', {s}, null)", .{ LAYOUT_JS, escaped_path });
    defer ctx.allocator.free(js);

    var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
    defer result.deinit(ctx.allocator);

    if (result.value) |val| {
        if (val == .object) {
            if (val.object.get("selector")) |sel| {
                if (sel == .string) {
                    std.debug.print("{s}\n", .{sel.string});
                    return;
                } else if (sel == .null) {
                    std.debug.print("(no parent - already at body)\n", .{});
                    return;
                }
            }
        }
    }
    std.debug.print("(invalid path)\n", .{});
}

/// next/prev - get sibling path
pub fn sibling(runtime: *cdp.Runtime, ctx: CommandCtx, direction: []const u8) !void {
    if (ctx.positional.len < 2) {
        std.debug.print("Error: Missing path\nUsage: layout {s} @L<path>\n", .{direction});
        return;
    }
    const path = layout_types.extractLayoutPath(ctx.positional[1]);
    const escaped_path = try cmd_helpers.jsStringLiteral(ctx.allocator, path);
    defer ctx.allocator.free(escaped_path);

    const js = try std.fmt.allocPrint(ctx.allocator, "{s}('{s}', {s}, null)", .{ LAYOUT_JS, direction, escaped_path });
    defer ctx.allocator.free(js);

    var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
    defer result.deinit(ctx.allocator);

    if (result.value) |val| {
        if (val == .object) {
            if (val.object.get("selector")) |sel| {
                if (sel == .string) {
                    std.debug.print("{s}\n", .{sel.string});
                    return;
                }
            }
        }
    }
    std.debug.print("(no {s} sibling)\n", .{direction});
}

/// children - list child paths
pub fn children(runtime: *cdp.Runtime, ctx: CommandCtx) !void {
    const path = if (ctx.positional.len > 1) layout_types.extractLayoutPath(ctx.positional[1]) else "";
    const escaped_path = try cmd_helpers.jsStringLiteral(ctx.allocator, path);
    defer ctx.allocator.free(escaped_path);

    const js = try std.fmt.allocPrint(ctx.allocator, "{s}('children', {s}, null)", .{ LAYOUT_JS, escaped_path });
    defer ctx.allocator.free(js);

    var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
    defer result.deinit(ctx.allocator);

    if (result.value) |val| {
        if (val == .array) {
            if (val.array.items.len == 0) {
                std.debug.print("(no children)\n", .{});
                return;
            }
            for (val.array.items) |item| {
                if (item == .string) {
                    std.debug.print("{s}\n", .{item.string});
                }
            }
            return;
        }
    }
    std.debug.print("(invalid path)\n", .{});
}
