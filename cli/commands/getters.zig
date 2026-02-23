//! Getter commands: get text, html, value, attr, title, url, count, box, styles.

const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");
const actions_mod = @import("../actions/mod.zig");

pub const CommandCtx = types.CommandCtx;

pub fn get(session: *cdp.Session, ctx: CommandCtx) !void {
    // Check for --help flag
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printGetHelp();
            return;
        }
    }

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

    if (std.mem.eql(u8, subcommand, "useragent") or std.mem.eql(u8, subcommand, "ua")) {
        var runtime = cdp.Runtime.init(session);
        try runtime.enable();
        var result = runtime.evaluate(ctx.allocator, "navigator.userAgent", .{ .return_by_value = true }) catch |err| {
            std.debug.print("Error: Failed to evaluate user agent: {}\n", .{err});
            return;
        };
        defer result.deinit(ctx.allocator);

        if (result.asString()) |ua| {
            std.debug.print("{s}\n", .{ua});
        } else {
            std.debug.print("(unknown)\n", .{});
        }
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
        \\  useragent            Get browser user agent (alias: ua)
        \\  count <sel>          Count matching elements
        \\  box <sel>            Get bounding box
        \\  styles <sel>         Get computed styles (JSON)
        \\
    , .{});
}

pub fn printGetHelp() void {
    std.debug.print(
        \\Usage: get <subcommand> [selector] [args]
        \\
        \\Subcommands:
        \\  get title                Get page title
        \\  get url                  Get current URL
        \\  get useragent            Get browser user agent (alias: ua)
        \\  get text <sel>           Get text content
        \\  get html <sel>           Get innerHTML
        \\  get dom <sel>            Get outerHTML
        \\  get value <sel>          Get input value
        \\  get attr <sel> <attr>    Get attribute value
        \\  get count <sel>          Count matching elements
        \\  get box <sel>            Get bounding box (x, y, width, height)
        \\  get styles <sel>         Get computed styles (JSON)
        \\
        \\Examples:
        \\  get title
        \\  get useragent
        \\  get ua
        \\  get text "#header"
        \\  get attr "#link" href
        \\  get count "li.item"
        \\
    , .{});
}
