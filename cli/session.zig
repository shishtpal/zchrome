const std = @import("std");
const config_mod = @import("config.zig");

/// Global session context - initialized once in main() and used throughout
pub const SessionContext = struct {
    name: []const u8,
    allocator: std.mem.Allocator,
    io: std.Io,
    init: std.process.Init,

    /// Get config path for this session
    pub fn configPath(self: *const SessionContext) ![]const u8 {
        return getSessionConfigPath(self.allocator, self.io, self.name);
    }

    /// Get snapshot path for this session
    pub fn snapshotPath(self: *const SessionContext) ![]const u8 {
        return getSessionSnapshotPath(self.allocator, self.io, self.name);
    }

    /// Load config for this session
    pub fn loadConfig(self: *const SessionContext) ?config_mod.Config {
        return loadSessionConfig(self.allocator, self.io, self.name);
    }

    /// Save config for this session
    pub fn saveConfig(self: *const SessionContext, config: config_mod.Config) !void {
        return saveSessionConfig(config, self.allocator, self.io, self.name);
    }

    pub fn deinit(self: *SessionContext) void {
        self.allocator.free(self.name);
    }
};

/// Resolve session name from args or environment
/// Priority: 1. --session flag, 2. ZCHROME_SESSION env var, 3. "default"
pub fn resolveSessionName(allocator: std.mem.Allocator, environ_map: *std.process.Environ.Map, session_arg: ?[]const u8) ![]const u8 {
    // 1. Explicit --session flag takes highest priority
    if (session_arg) |name| {
        return allocator.dupe(u8, name);
    }

    // 2. Check ZCHROME_SESSION environment variable
    if (environ_map.get("ZCHROME_SESSION")) |env_val| {
        if (env_val.len > 0) {
            return allocator.dupe(u8, env_val);
        }
    }

    // 3. Fall back to "default"
    return allocator.dupe(u8, "default");
}

/// Get sessions directory path (alongside executable)
pub fn getSessionsDir(allocator: std.mem.Allocator, io: std.Io) ![]const u8 {
    const exe_dir = std.process.executableDirPathAlloc(io, allocator) catch {
        return allocator.dupe(u8, "sessions");
    };
    defer allocator.free(exe_dir);
    return std.fs.path.join(allocator, &.{ exe_dir, "sessions" });
}

/// Get session directory path for a named session
pub fn getSessionDir(allocator: std.mem.Allocator, io: std.Io, session_name: []const u8) ![]const u8 {
    const sessions_dir = try getSessionsDir(allocator, io);
    defer allocator.free(sessions_dir);
    return std.fs.path.join(allocator, &.{ sessions_dir, session_name });
}

/// Get config path for a session
pub fn getSessionConfigPath(allocator: std.mem.Allocator, io: std.Io, session_name: []const u8) ![]const u8 {
    const session_dir = try getSessionDir(allocator, io, session_name);
    defer allocator.free(session_dir);
    return std.fs.path.join(allocator, &.{ session_dir, "zchrome.json" });
}

/// Get snapshot path for a session
pub fn getSessionSnapshotPath(allocator: std.mem.Allocator, io: std.Io, session_name: []const u8) ![]const u8 {
    const session_dir = try getSessionDir(allocator, io, session_name);
    defer allocator.free(session_dir);
    return std.fs.path.join(allocator, &.{ session_dir, "zsnap.json" });
}

/// Ensure session directory exists
fn ensureSessionDir(allocator: std.mem.Allocator, io: std.Io, session_name: []const u8) !void {
    const session_dir = try getSessionDir(allocator, io, session_name);
    defer allocator.free(session_dir);

    // Create sessions/ parent directory if needed
    const sessions_dir = try getSessionsDir(allocator, io);
    defer allocator.free(sessions_dir);

    const cwd = std.Io.Dir.cwd();
    const perms: std.Io.File.Permissions = @enumFromInt(0o755);

    // Try to create parent sessions/ dir (ignore if exists)
    cwd.createDir(io, sessions_dir, perms) catch |err| {
        if (err != error.PathAlreadyExists) {
            // Ignore other errors, the session dir creation will fail if needed
        }
    };

    // Create session-specific directory
    cwd.createDir(io, session_dir, perms) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
}

/// Load config for a session
pub fn loadSessionConfig(allocator: std.mem.Allocator, io: std.Io, session_name: []const u8) ?config_mod.Config {
    const config_path = getSessionConfigPath(allocator, io, session_name) catch return null;
    defer allocator.free(config_path);

    return config_mod.loadConfigFromPath(allocator, io, config_path);
}

/// Save config for a session (creates session dir if needed)
pub fn saveSessionConfig(config: config_mod.Config, allocator: std.mem.Allocator, io: std.Io, session_name: []const u8) !void {
    // Ensure session directory exists
    try ensureSessionDir(allocator, io, session_name);

    const config_path = try getSessionConfigPath(allocator, io, session_name);
    defer allocator.free(config_path);

    try config_mod.saveConfigToPath(config, allocator, io, config_path);
}

/// Migrate old-style config to sessions/default/
pub fn migrateToSessions(allocator: std.mem.Allocator, io: std.Io) !void {
    // Check if old-style zchrome.json exists at exe dir
    const exe_dir = std.process.executableDirPathAlloc(io, allocator) catch return;
    defer allocator.free(exe_dir);

    const old_config_path = std.fs.path.join(allocator, &.{ exe_dir, "zchrome.json" }) catch return;
    defer allocator.free(old_config_path);

    const old_snap_path = std.fs.path.join(allocator, &.{ exe_dir, "zsnap.json" }) catch return;
    defer allocator.free(old_snap_path);

    // Check if sessions/default already exists
    const default_session_dir = getSessionDir(allocator, io, "default") catch return;
    defer allocator.free(default_session_dir);

    // Check if old config exists
    const dir = std.Io.Dir.openDirAbsolute(io, exe_dir, .{}) catch return;

    var buf: [64 * 1024]u8 = undefined;
    const old_config_content = dir.readFile(io, "zchrome.json", &buf) catch return;

    // Old config exists - check if we should migrate
    const default_dir_exists = blk: {
        _ = std.Io.Dir.openDirAbsolute(io, default_session_dir, .{}) catch break :blk false;
        break :blk true;
    };

    if (default_dir_exists) {
        // Default session already exists, don't migrate
        return;
    }

    // Create default session directory
    ensureSessionDir(allocator, io, "default") catch return;

    // Move config
    const new_config_path = getSessionConfigPath(allocator, io, "default") catch return;
    defer allocator.free(new_config_path);

    // Write to new location
    const new_dir = std.Io.Dir.cwd();
    new_dir.writeFile(io, .{ .sub_path = new_config_path, .data = old_config_content }) catch return;

    // Try to move snapshot too
    var snap_buf: [256 * 1024]u8 = undefined;
    if (dir.readFile(io, "zsnap.json", &snap_buf)) |old_snap_content| {
        const new_snap_path = getSessionSnapshotPath(allocator, io, "default") catch return;
        defer allocator.free(new_snap_path);
        new_dir.writeFile(io, .{ .sub_path = new_snap_path, .data = old_snap_content }) catch {};
    } else |_| {}

    // Delete old files
    dir.deleteFile(io, "zchrome.json") catch {};
    dir.deleteFile(io, "zsnap.json") catch {};

    std.debug.print("Migrated config to sessions/default/\n", .{});
}

/// List all session names
pub fn listSessions(allocator: std.mem.Allocator, io: std.Io) !std.ArrayList([]const u8) {
    var sessions: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (sessions.items) |s| allocator.free(s);
        sessions.deinit(allocator);
    }

    const sessions_dir = try getSessionsDir(allocator, io);
    defer allocator.free(sessions_dir);

    var dir = std.Io.Dir.openDirAbsolute(io, sessions_dir, .{ .iterate = true }) catch {
        return sessions;
    };
    defer dir.close(io);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind == .directory) {
            const name = try allocator.dupe(u8, entry.name);
            try sessions.append(allocator, name);
        }
    }

    return sessions;
}

/// Check if session exists
pub fn sessionExists(allocator: std.mem.Allocator, io: std.Io, session_name: []const u8) bool {
    const session_dir = getSessionDir(allocator, io, session_name) catch return false;
    defer allocator.free(session_dir);

    _ = std.Io.Dir.openDirAbsolute(io, session_dir, .{}) catch return false;
    return true;
}

/// Create a new session directory
pub fn createSession(allocator: std.mem.Allocator, io: std.Io, session_name: []const u8) !void {
    try ensureSessionDir(allocator, io, session_name);
}

/// Delete a session
pub fn deleteSession(allocator: std.mem.Allocator, io: std.Io, session_name: []const u8) !void {
    // Prevent deleting "default" session
    if (std.mem.eql(u8, session_name, "default")) {
        return error.CannotDeleteDefault;
    }

    const session_dir = try getSessionDir(allocator, io, session_name);
    defer allocator.free(session_dir);

    // Delete files in session directory
    var dir = std.Io.Dir.openDirAbsolute(io, session_dir, .{ .iterate = true }) catch return error.SessionNotFound;

    // Delete config and snapshot files
    dir.deleteFile(io, "zchrome.json") catch {};
    dir.deleteFile(io, "zsnap.json") catch {};

    // Close dir before removing it
    dir.close(io);

    // Remove the session directory
    const sessions_dir = try getSessionsDir(allocator, io);
    defer allocator.free(sessions_dir);

    var parent_dir = std.Io.Dir.openDirAbsolute(io, sessions_dir, .{}) catch return error.SessionNotFound;
    defer parent_dir.close(io);

    parent_dir.deleteDir(io, session_name) catch |err| {
        std.debug.print("Warning: Could not delete session directory: {}\n", .{err});
    };
}
