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
    // Parse options first so flags (e.g. --timeout=5000) are not treated as prompt text.
    var timeout_ms: u32 = 30000;
    const action_args = try ctx.allocator.alloc([]const u8, ctx.positional.len);
    defer ctx.allocator.free(action_args);

    var action_len: usize = 0;
    for (ctx.positional) |arg| {
        if (std.mem.startsWith(u8, arg, "--timeout=")) {
            const val = arg["--timeout=".len..];
            timeout_ms = std.fmt.parseInt(u32, val, 10) catch 30000;
            continue;
        }
        action_args[action_len] = arg;
        action_len += 1;
    }

    const parsed = try parseDialogArgs(ctx.allocator, action_args[0..action_len]);
    if (parsed == null) {
        printDialogUsage();
        return;
    }

    const action = parsed.?;
    defer deinitDialogAction(ctx.allocator, action);

    var page = cdp.Page.init(session);
    try page.enable();

    // First, try to handle an existing dialog
    switch (action) {
        .accept => |text| {
            try handleDialogWithWait(&page, ctx.allocator, true, text, timeout_ms);
            if (text) |t| {
                std.debug.print("Dialog accepted with text: {s}\n", .{t});
            } else {
                std.debug.print("Dialog accepted\n", .{});
            }
        },
        .dismiss => {
            try handleDialogWithWait(&page, ctx.allocator, false, null, timeout_ms);
            std.debug.print("Dialog dismissed\n", .{});
        },
    }
}

fn handleDialogWithWait(page: *cdp.Page, allocator: std.mem.Allocator, accept: bool, prompt_text: ?[]const u8, timeout_ms: u32) !void {
    page.handleJavaScriptDialog(.{
        .accept = accept,
        .prompt_text = prompt_text,
    }) catch |err| {
        if (err == error.InvalidParams) {
            std.debug.print("Waiting for dialog (timeout: {}ms)...\n", .{timeout_ms});
            std.debug.print("Trigger a dialog on the page now.\n", .{});

            var dialog_info = page.waitForJavaScriptDialogOpening(allocator, timeout_ms) catch |wait_err| {
                std.debug.print("Error waiting for dialog: {}\n", .{wait_err});
                return;
            };
            defer dialog_info.deinit(allocator);

            std.debug.print("Dialog appeared: type={s}, message=\"{s}\"\n", .{ dialog_info.dialog_type, dialog_info.message });

            try page.handleJavaScriptDialog(.{
                .accept = accept,
                .prompt_text = prompt_text,
            });
        } else {
            return err;
        }
    };
}

fn printDialogUsage() void {
    std.debug.print(
        \\Usage: dialog <accept [text] | dismiss> [--timeout=<ms>]
        \\
        \\Handle JavaScript dialogs (alert/confirm/prompt).
        \\
        \\Commands:
        \\  accept [text]    Accept the dialog (optionally with prompt text)
        \\  dismiss          Dismiss/cancel the dialog
        \\
        \\Options:
        \\  --timeout=<ms>   Timeout waiting for dialog (default: 30000)
        \\
        \\Note: Run this command BEFORE triggering the dialog on the page.
        \\      The command will wait for a dialog to appear, then handle it.
        \\
        \\Examples:
        \\  zchrome dialog accept
        \\  zchrome dialog accept "my input"
        \\  zchrome dialog dismiss
        \\  zchrome dialog accept --timeout=5000
        \\
    , .{});
}
