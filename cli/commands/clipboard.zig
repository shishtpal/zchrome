//! Clipboard commands: read, write, copy, paste.

const std = @import("std");
const cdp = @import("cdp");
const clipboard = @import("clipboard");
const types = @import("types.zig");
const actions_mod = @import("../actions/mod.zig");

pub const CommandCtx = types.CommandCtx;

pub fn clipboardCmd(session: *cdp.Session, ctx: CommandCtx) !void {
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printClipboardHelp();
            return;
        }
    }

    if (ctx.positional.len == 0) {
        printClipboardHelp();
        return;
    }

    const subcmd = ctx.positional[0];

    if (std.mem.eql(u8, subcmd, "read")) {
        const text = clipboard.getText(ctx.allocator) catch |err| {
            std.debug.print("Error reading clipboard: {}\n", .{err});
            return;
        };
        if (text) |t| {
            defer ctx.allocator.free(t);
            std.debug.print("{s}\n", .{t});
        } else {
            std.debug.print("(clipboard empty)\n", .{});
        }
    } else if (std.mem.eql(u8, subcmd, "write")) {
        if (ctx.positional.len < 2) {
            std.debug.print("Usage: clipboard write <text>\n", .{});
            return;
        }
        // Join all remaining arguments with spaces
        const text_parts = ctx.positional[1..];
        const text = std.mem.join(ctx.allocator, " ", text_parts) catch |err| {
            std.debug.print("Error joining text: {}\n", .{err});
            return;
        };
        defer ctx.allocator.free(text);
        clipboard.setText(text) catch |err| {
            std.debug.print("Error writing to clipboard: {}\n", .{err});
            return;
        };
        std.debug.print("Written to clipboard: {s}\n", .{text});
    } else if (std.mem.eql(u8, subcmd, "copy")) {
        actions_mod.pressKey(session, "Control+c") catch |err| {
            std.debug.print("Error sending Ctrl+C: {}\n", .{err});
            return;
        };
        std.debug.print("Copied (Ctrl+C)\n", .{});
    } else if (std.mem.eql(u8, subcmd, "paste")) {
        actions_mod.pressKey(session, "Control+v") catch |err| {
            std.debug.print("Error sending Ctrl+V: {}\n", .{err});
            return;
        };
        std.debug.print("Pasted (Ctrl+V)\n", .{});
    } else {
        std.debug.print("Unknown clipboard subcommand: {s}\n", .{subcmd});
        printClipboardHelp();
    }
}

pub fn printClipboardHelp() void {
    std.debug.print(
        \\Usage: clipboard <subcommand> [args]
        \\
        \\Subcommands:
        \\  clipboard read             Read text from system clipboard
        \\  clipboard write <text>     Write text to system clipboard
        \\  clipboard copy             Copy current selection (Ctrl+C)
        \\  clipboard paste            Paste from clipboard (Ctrl+V)
        \\
        \\Examples:
        \\  clipboard read                       # Print clipboard text
        \\  clipboard write "Hello, World!"      # Set clipboard text
        \\  clipboard copy                       # Simulate Ctrl+C
        \\  clipboard paste                      # Simulate Ctrl+V
        \\
    , .{});
}
