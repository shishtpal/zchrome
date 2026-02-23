//! Help text functions for commands.

const std = @import("std");

pub fn printTabHelp() void {
    std.debug.print(
        \\Usage: tab [subcommand] [args]
        \\
        \\Subcommands:
        \\  tab                      List open tabs (numbered)
        \\  tab new [url]            Open new tab (optionally navigate to URL)
        \\  tab <n>                  Switch to tab n
        \\  tab close [n]            Close tab n (default: current)
        \\
        \\Examples:
        \\  tab new https://example.com
        \\  tab 2
        \\  tab close
        \\  tab close 1
        \\
    , .{});
}

pub fn printWindowHelp() void {
    std.debug.print(
        \\Usage: window [subcommand]
        \\
        \\Subcommands:
        \\  window new           Open new browser window
        \\
        \\Examples:
        \\  window new           # Open new browser window
        \\
    , .{});
}
