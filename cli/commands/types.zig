//! Shared types for command implementations.

const std = @import("std");

/// Context passed to all command implementations.
pub const CommandCtx = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    positional: []const []const u8,
    output: ?[]const u8 = null,
    full_page: bool = false,
    // Snapshot options
    snap_interactive: bool = false,
    snap_compact: bool = false,
    snap_depth: ?usize = null,
    snap_selector: ?[]const u8 = null,
    // Wait options
    wait_text: ?[]const u8 = null,
    wait_url: ?[]const u8 = null,
    wait_load: ?[]const u8 = null,
    wait_fn: ?[]const u8 = null,
};
