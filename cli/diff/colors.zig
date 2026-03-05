//! ANSI color codes for terminal output.

const std = @import("std");

// ─── ANSI Escape Codes ──────────────────────────────────────────────────────

pub const RESET = "\x1b[0m";
pub const BOLD = "\x1b[1m";
pub const DIM = "\x1b[2m";

// Colors
pub const RED = "\x1b[31m";
pub const GREEN = "\x1b[32m";
pub const YELLOW = "\x1b[33m";
pub const BLUE = "\x1b[34m";
pub const MAGENTA = "\x1b[35m";
pub const CYAN = "\x1b[36m";
pub const WHITE = "\x1b[37m";

// Background colors
pub const BG_RED = "\x1b[41m";
pub const BG_GREEN = "\x1b[42m";

// ─── Helper Functions ───────────────────────────────────────────────────────

/// Print a line with deletion styling (red with - prefix)
pub fn printDeletion(line: []const u8) void {
    std.debug.print("{s}- {s}{s}\n", .{ RED, line, RESET });
}

/// Print a line with insertion styling (green with + prefix)
pub fn printInsertion(line: []const u8) void {
    std.debug.print("{s}+ {s}{s}\n", .{ GREEN, line, RESET });
}

/// Print a line with unchanged styling (dimmed with space prefix)
pub fn printUnchanged(line: []const u8) void {
    std.debug.print("{s}  {s}{s}\n", .{ DIM, line, RESET });
}

/// Print a header/title in bold
pub fn printHeader(text: []const u8) void {
    std.debug.print("{s}{s}{s}\n", .{ BOLD, text, RESET });
}

/// Print a success message in green
pub fn printSuccess(text: []const u8) void {
    std.debug.print("{s}{s}{s}\n", .{ GREEN, text, RESET });
}

/// Print an error message in red
pub fn printError(text: []const u8) void {
    std.debug.print("{s}{s}{s}\n", .{ RED, text, RESET });
}

/// Print a warning message in yellow
pub fn printWarning(text: []const u8) void {
    std.debug.print("{s}{s}{s}\n", .{ YELLOW, text, RESET });
}

/// Print diff statistics
pub fn printDiffStats(additions: usize, removals: usize, unchanged: usize) void {
    std.debug.print("\n--- Diff Statistics ---\n", .{});
    if (additions > 0) {
        std.debug.print("{s}+{} additions{s}\n", .{ GREEN, additions, RESET });
    }
    if (removals > 0) {
        std.debug.print("{s}-{} deletions{s}\n", .{ RED, removals, RESET });
    }
    std.debug.print("~{} unchanged\n", .{unchanged});
}
