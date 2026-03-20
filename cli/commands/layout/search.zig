//! Search subcommands: find, at

const std = @import("std");
const json = @import("json");
const cdp = @import("cdp");
const cmd_types = @import("../types.zig");
const cmd_helpers = @import("../helpers.zig");
const layout_types = @import("types.zig");
const action_helpers = @import("../../actions/helpers.zig");

pub const CommandCtx = cmd_types.CommandCtx;
const LAYOUT_JS = action_helpers.LAYOUT_JS;

/// find - search by text
pub fn find(runtime: *cdp.Runtime, ctx: CommandCtx) !void {
    if (ctx.positional.len < 2) {
        std.debug.print("Error: Missing search text\nUsage: layout find <text>\n", .{});
        return;
    }
    const search_text = ctx.positional[1];
    const escaped_text = try cmd_helpers.jsStringLiteral(ctx.allocator, search_text);
    defer ctx.allocator.free(escaped_text);

    const js = try std.fmt.allocPrint(ctx.allocator, "{s}('find', {s}, null)", .{ LAYOUT_JS, escaped_text });
    defer ctx.allocator.free(js);

    var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
    defer result.deinit(ctx.allocator);

    if (result.value) |val| {
        if (val == .array) {
            if (val.array.items.len == 0) {
                std.debug.print("(no matches)\n", .{});
                return;
            }
            for (val.array.items) |item| {
                if (item == .object) {
                    const selector = layout_types.getJsonString(item, "selector");
                    const tag = layout_types.getJsonString(item, "tag");
                    const id = layout_types.getJsonString(item, "id");
                    const cls = layout_types.getJsonString(item, "cls");
                    const text = layout_types.getJsonString(item, "text");

                    // Format: @L0/1 <button#id.class> "text"
                    std.debug.print("{s} ", .{selector});
                    layout_types.formatElementTag(tag, id, cls);
                    if (text.len > 0) std.debug.print(" \"{s}\"", .{text});
                    std.debug.print("\n", .{});
                }
            }
            return;
        }
    }
    std.debug.print("(search error)\n", .{});
}

/// at - lookup by coordinates
pub fn at(runtime: *cdp.Runtime, ctx: CommandCtx) !void {
    if (ctx.positional.len < 3) {
        std.debug.print("Error: Missing coordinates\nUsage: layout at <x> <y>\n", .{});
        return;
    }
    const x = ctx.positional[1];
    const y = ctx.positional[2];
    const coords = try std.fmt.allocPrint(ctx.allocator, "{s},{s}", .{ x, y });
    defer ctx.allocator.free(coords);
    const escaped_coords = try cmd_helpers.jsStringLiteral(ctx.allocator, coords);
    defer ctx.allocator.free(escaped_coords);

    const js = try std.fmt.allocPrint(ctx.allocator, "{s}('at', {s}, null)", .{ LAYOUT_JS, escaped_coords });
    defer ctx.allocator.free(js);

    var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
    defer result.deinit(ctx.allocator);

    if (result.value) |val| {
        if (val == .object) {
            const selector = layout_types.getJsonString(val, "selector");
            const tag = layout_types.getJsonString(val, "tag");
            const id = layout_types.getJsonString(val, "id");
            const cls = layout_types.getJsonString(val, "cls");
            const ex = layout_types.getJsonInt(val, "x");
            const ey = layout_types.getJsonInt(val, "y");
            const ew = layout_types.getJsonInt(val, "w");
            const eh = layout_types.getJsonInt(val, "h");

            // Format: @L0/1 <div#id.class> 100x50 @ (200,300)
            std.debug.print("{s} ", .{selector});
            layout_types.formatElementTag(tag, id, cls);
            std.debug.print(" {}x{} @ ({},{})\n", .{ ew, eh, ex, ey });
            return;
        }
    }
    std.debug.print("(no element at coordinates)\n", .{});
}
