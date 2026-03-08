//! Shared types for command implementations.

const std = @import("std");
const session_mod = @import("../session.zig");
const config_mod = @import("../config.zig");

/// Context passed to all command implementations.
pub const CommandCtx = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    positional: []const []const u8,
    output: ?[]const u8 = null,
    full_page: bool = false,
    // Session context for config operations
    session: ?*const session_mod.SessionContext = null,
    // Snapshot options
    snap_interactive: bool = false,
    snap_compact: bool = false,
    snap_depth: ?usize = null,
    snap_selector: ?[]const u8 = null,
    snap_mark: bool = false,
    // Wait options
    wait_text: ?[]const u8 = null,
    wait_url: ?[]const u8 = null,
    wait_load: ?[]const u8 = null,
    wait_fn: ?[]const u8 = null,
    // Click options
    click_js: bool = false,
    // Replay options
    replay_retries: u32 = 3,
    replay_retry_delay: u32 = 100,
    replay_fallback: ?[]const u8 = null,
    replay_resume: bool = false,
    replay_from: ?usize = null,

    /// Load config using session context if available, otherwise fallback to global
    pub fn loadConfig(self: CommandCtx) config_mod.Config {
        if (self.session) |s| {
            return s.loadConfig() orelse config_mod.Config{};
        }
        return config_mod.loadConfig(self.allocator, self.io) orelse config_mod.Config{};
    }

    /// Save config using session context if available, otherwise fallback to global
    pub fn saveConfig(self: CommandCtx, config: config_mod.Config) !void {
        if (self.session) |s| {
            try s.saveConfig(config);
        } else {
            try config_mod.saveConfig(config, self.allocator, self.io);
        }
    }
};
