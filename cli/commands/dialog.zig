//! JavaScript dialog handling commands.
//!
//! Supports:
//!   dialog accept [text]
//!   dialog dismiss

const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");

pub const CommandCtx = types.CommandCtx;

pub const DialogAction = union(enum) {
    accept: ?[]const u8,
    dismiss,
};

/// Parse dialog command args into an action. Returns null for invalid input.
pub fn parseDialogArgs(allocator: std.mem.Allocator, args: []const []const u8) !?DialogAction {
    if (args.len == 0) return null;

    if (std.mem.eql(u8, args[0], "accept")) {
        if (args.len == 1) return .{ .accept = null };

        var text = std.ArrayList(u8).empty;
        defer text.deinit(allocator);

        for (args[1..], 0..) |part, i| {
            if (i > 0) try text.append(allocator, ' ');
            try text.appendSlice(allocator, part);
        }

        return .{ .accept = try text.toOwnedSlice(allocator) };
    }

    if (std.mem.eql(u8, args[0], "dismiss")) {
        return .dismiss;
    }

    return null;
}

pub fn deinitDialogAction(allocator: std.mem.Allocator, action: DialogAction) void {
    switch (action) {
        .accept => |text| {
            if (text) |t| allocator.free(t);
        },
        .dismiss => {},
    }
}

pub fn dialog(session: *cdp.Session, ctx: CommandCtx) !void {
    const parsed = try parseDialogArgs(ctx.allocator, ctx.positional);
    if (parsed == null) {
        printDialogUsage();
        return;
    }

    const action = parsed.?;
    defer deinitDialogAction(ctx.allocator, action);

    var page = cdp.Page.init(session);
    try page.enable();
    switch (action) {
        .accept => |text| {
            try page.handleJavaScriptDialog(.{
                .accept = true,
                .prompt_text = text,
            });
            if (text) |t| {
                std.debug.print("Dialog accepted with text: {s}\n", .{t});
            } else {
                std.debug.print("Dialog accepted\n", .{});
            }
        },
        .dismiss => {
            try page.handleJavaScriptDialog(.{
                .accept = false,
            });
            std.debug.print("Dialog dismissed\n", .{});
        },
    }
}

fn printDialogUsage() void {
    std.debug.print("Usage: dialog <accept [text] | dismiss>\n", .{});
}
