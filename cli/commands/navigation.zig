//! Navigation commands: navigate, back, forward, reload.

const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");

pub const CommandCtx = types.CommandCtx;

pub fn navigate(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: navigate <url>\n", .{});
        return;
    }

    const target_url = ctx.positional[0];
    var page = cdp.Page.init(session);
    try page.enable();

    var result = try page.navigate(ctx.allocator, target_url);
    defer result.deinit(ctx.allocator);

    if (result.error_text) |err| {
        std.debug.print("Navigation error: {s}\n", .{err});
        return;
    }

    var i: u32 = 0;
    while (i < 500000) : (i += 1) std.atomic.spinLoopHint();

    var runtime = cdp.Runtime.init(session);
    try runtime.enable();
    const title = runtime.evaluateAs([]const u8, "document.title") catch "Unknown";
    std.debug.print("URL: {s}\nTitle: {s}\n", .{ target_url, title });
}

pub fn back(session: *cdp.Session) !void {
    var page = cdp.Page.init(session);
    if (try page.goBack())
        std.debug.print("Navigated back\n", .{})
    else
        std.debug.print("No previous page in history\n", .{});
}

pub fn forward(session: *cdp.Session) !void {
    var page = cdp.Page.init(session);
    if (try page.goForward())
        std.debug.print("Navigated forward\n", .{})
    else
        std.debug.print("No next page in history\n", .{});
}

pub fn reload(session: *cdp.Session) !void {
    var page = cdp.Page.init(session);
    try page.reload(null);
    std.debug.print("Page reloaded\n", .{});
}
