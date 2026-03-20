//! Conversion subcommands: xpath, css, tocss

const std = @import("std");
const json = @import("json");
const cdp = @import("cdp");
const cmd_types = @import("../types.zig");
const cmd_helpers = @import("../helpers.zig");
const layout_types = @import("types.zig");
const action_helpers = @import("../../actions/helpers.zig");

pub const CommandCtx = cmd_types.CommandCtx;
const LAYOUT_JS = action_helpers.LAYOUT_JS;

/// xpath/css - convert selector to layout path
pub fn selectorToLayout(runtime: *cdp.Runtime, ctx: CommandCtx, is_xpath: bool) !void {
    if (ctx.positional.len < 2) {
        const cmd_name = if (is_xpath) "xpath" else "css";
        std.debug.print("Error: Missing selector\nUsage: layout {s} <selector>\n", .{cmd_name});
        return;
    }

    const selector = ctx.positional[1];
    const action = if (is_xpath) "xpath" else "css2layout";
    const escaped_selector = try cmd_helpers.jsStringLiteral(ctx.allocator, selector);
    defer ctx.allocator.free(escaped_selector);

    const js = try std.fmt.allocPrint(ctx.allocator, "{s}('{s}', {s}, null)", .{ LAYOUT_JS, action, escaped_selector });
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

    std.debug.print("(not found or not visible)\n", .{});
}

/// tocss - generate CSS selector from layout path
pub fn toCss(runtime: *cdp.Runtime, ctx: CommandCtx) !void {
    const path = if (ctx.positional.len > 1) layout_types.extractLayoutPath(ctx.positional[1]) else "";
    const escaped_path = try cmd_helpers.jsStringLiteral(ctx.allocator, path);
    defer ctx.allocator.free(escaped_path);

    const js = try std.fmt.allocPrint(ctx.allocator, "{s}('tocss', {s}, null)", .{ LAYOUT_JS, escaped_path });
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
    std.debug.print("(invalid path)\n", .{});
}
