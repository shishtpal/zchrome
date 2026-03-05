//! Diff command dispatcher for snapshot, screenshot, and URL comparison.

const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");
const diff_mod = @import("../diff/mod.zig");

pub const CommandCtx = types.CommandCtx;

/// Dispatch diff subcommands (snapshot, screenshot, url)
pub fn dispatchDiffSubcommand(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len < 1) {
        printDiffHelp();
        return;
    }

    const subcommand = ctx.positional[0];

    if (std.mem.eql(u8, subcommand, "snapshot")) {
        // Create a new context with positional args shifted
        var sub_ctx = ctx;
        sub_ctx.positional = ctx.positional[1..];
        try diff_mod.diffSnapshotCommand(session, sub_ctx);
    } else if (std.mem.eql(u8, subcommand, "screenshot")) {
        var sub_ctx = ctx;
        sub_ctx.positional = ctx.positional[1..];
        try diff_mod.diffScreenshotCommand(session, sub_ctx);
    } else if (std.mem.eql(u8, subcommand, "url")) {
        var sub_ctx = ctx;
        sub_ctx.positional = ctx.positional[1..];
        try diff_mod.diffUrlCommand(session, sub_ctx);
    } else if (std.mem.eql(u8, subcommand, "--help") or std.mem.eql(u8, subcommand, "help")) {
        printDiffHelp();
    } else {
        std.debug.print("Unknown diff subcommand: {s}\n\n", .{subcommand});
        printDiffHelp();
    }
}

pub fn printDiffHelp() void {
    std.debug.print(
        \\Usage: diff <subcommand> [options]
        \\
        \\Subcommands:
        \\  snapshot    Compare current vs baseline snapshot (text diff)
        \\  screenshot  Visual pixel diff against baseline image
        \\  url         Compare two URLs (snapshot and/or screenshot)
        \\
        \\Examples:
        \\  diff snapshot                        # Compare vs last snapshot
        \\  diff snapshot --baseline before.txt  # Compare vs saved file
        \\  diff screenshot --baseline b.png     # Visual diff against baseline
        \\  diff url https://v1.com https://v2.com  # Compare two URLs
        \\
        \\Run 'diff <subcommand> --help' for subcommand-specific options.
        \\
    , .{});
}
