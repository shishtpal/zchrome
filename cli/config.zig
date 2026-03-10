const std = @import("std");
const json = @import("json");

const load_config = @import("config/loadConfig.zig");
pub const loadConfig = load_config.loadConfig;
pub const loadConfigFromPath = load_config.loadConfigFromPath;

const save_config = @import("config/saveConfig.zig");
pub const saveConfig = save_config.saveConfig;
pub const saveConfigToPath = save_config.saveConfigToPath;

/// Configuration stored in zchrome.json alongside the executable
pub const Config = struct {
    chrome_path: ?[]const u8 = null,
    data_dir: ?[]const u8 = null,
    port: u16 = 9222,
    ws_url: ?[]const u8 = null,
    last_target: ?[]const u8 = null,
    last_mouse_x: ?f64 = null,
    last_mouse_y: ?f64 = null,

    // Session settings
    viewport_width: ?u32 = null,
    viewport_height: ?u32 = null,
    device_name: ?[]const u8 = null,
    geo_lat: ?f64 = null,
    geo_lng: ?f64 = null,
    offline: ?bool = null,
    headers: ?[]const u8 = null,
    auth_user: ?[]const u8 = null,
    auth_pass: ?[]const u8 = null,
    media_feature: ?[]const u8 = null,
    user_agent: ?[]const u8 = null,

    // Cloud provider settings
    provider: ?[]const u8 = null, // "local", "kernel", "notte", "browserbase"
    provider_session_id: ?[]const u8 = null, // Active cloud session ID
    provider_auto_cleanup: ?bool = null, // Override provider's default cleanup behavior

    // Chrome launch arguments
    chrome_args: ?[]const []const u8 = null, // Additional Chrome CLI arguments

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        if (self.chrome_path) |p| allocator.free(p);
        if (self.data_dir) |d| allocator.free(d);
        if (self.ws_url) |u| allocator.free(u);
        if (self.last_target) |t| allocator.free(t);
        if (self.device_name) |d| allocator.free(d);
        if (self.headers) |h| allocator.free(h);
        if (self.auth_user) |u| allocator.free(u);
        if (self.auth_pass) |p| allocator.free(p);
        if (self.media_feature) |m| allocator.free(m);
        if (self.user_agent) |u| allocator.free(u);
        if (self.provider) |p| allocator.free(p);
        if (self.provider_session_id) |s| allocator.free(s);
        if (self.chrome_args) |args| {
            for (args) |arg| allocator.free(arg);
            allocator.free(args);
        }
        self.* = .{};
    }
};

const config_filename = "zchrome.json";

/// Get the path to zchrome.json (alongside the executable)
pub fn getConfigPath(allocator: std.mem.Allocator, io: std.Io) ![]const u8 {
    // Get the directory containing the executable
    const exe_dir = std.process.executableDirPathAlloc(io, allocator) catch {
        // Fallback to current directory if we can't get exe path
        return allocator.dupe(u8, config_filename);
    };
    defer allocator.free(exe_dir);
    return std.fs.path.join(allocator, &.{ exe_dir, config_filename });
}

/// Get the default snapshot file path (alongside the executable)
pub fn getSnapshotPath(allocator: std.mem.Allocator, io: std.Io) ![]const u8 {
    // Get the directory containing the executable
    const exe_dir = std.process.executableDirPathAlloc(io, allocator) catch {
        // Fallback to current directory if we can't get exe path
        return allocator.dupe(u8, "zsnap.json");
    };
    defer allocator.free(exe_dir);
    return std.fs.path.join(allocator, &.{ exe_dir, "zsnap.json" });
}
