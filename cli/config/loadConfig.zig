const std = @import("std");
const json = @import("json");
const root = @import("../config.zig");
const merge_config = @import("mergeConfig.zig");

const Config = root.Config;
const getConfigPath = root.getConfigPath;
const getUserConfigPath = root.getUserConfigPath;
const mergeConfig = merge_config.mergeConfig;

pub const LoadOptions = struct {
    verbose: bool = false,
};

/// Load configuration from zchrome.json (legacy - uses exe directory)
pub fn loadConfig(allocator: std.mem.Allocator, io: std.Io, options: LoadOptions) ?Config {
    const config_path = getConfigPath(allocator, io) catch return null;
    defer allocator.free(config_path);
    return loadConfigFromPath(allocator, io, config_path, options);
}

/// Load configuration from a specific path
pub fn loadConfigFromPath(allocator: std.mem.Allocator, io: std.Io, path: []const u8, options: LoadOptions) ?Config {
    if (options.verbose) {
        std.debug.print("[config] Loading base config: {s}\n", .{path});
    }

    var config = readConfigFile(allocator, io, path, options) orelse return null;

    // Try to load user config and merge over base
    const user_path = getUserConfigPath(allocator, path) orelse return config;
    defer allocator.free(user_path);

    if (options.verbose) {
        std.debug.print("[config] Looking for user config: {s}\n", .{user_path});
    }

    var user_config = readConfigFile(allocator, io, user_path, options) orelse {
        if (options.verbose) {
            std.debug.print("[config] No user config found, using base config only\n", .{});
        }
        return config;
    };

    if (options.verbose) {
        std.debug.print("[config] Merging user config over base config\n", .{});
    }

    return mergeConfig(allocator, &config, &user_config);
}

/// Read and parse a config file from the given path
fn readConfigFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8, options: LoadOptions) ?Config {
    var file_buf: [64 * 1024]u8 = undefined;

    const content = blk: {
        const dir = std.Io.Dir.cwd();
        break :blk dir.readFile(io, path, &file_buf) catch {
            const parent = std.fs.path.dirname(path) orelse return null;
            const filename = std.fs.path.basename(path);
            const abs_dir = std.Io.Dir.openDirAbsolute(io, parent, .{}) catch return null;
            break :blk abs_dir.readFile(io, filename, &file_buf) catch return null;
        };
    };

    if (options.verbose) {
        std.debug.print("[config] Successfully read: {s}\n", .{path});
    }

    return parseConfigFromContent(allocator, content);
}

/// Parse config from JSON content
fn parseConfigFromContent(allocator: std.mem.Allocator, content: []const u8) ?Config {
    var parsed = json.parse(allocator, content, .{}) catch return null;
    defer parsed.deinit(allocator);

    var config = Config{};

    if (parsed.get("chrome_path")) |v| {
        if (v == .string) config.chrome_path = allocator.dupe(u8, v.string) catch null;
    }
    if (parsed.get("data_dir")) |v| {
        if (v == .string) config.data_dir = allocator.dupe(u8, v.string) catch null;
    }
    if (parsed.get("port")) |v| {
        if (v == .integer) config.port = @intCast(v.integer);
    }
    if (parsed.get("ws_url")) |v| {
        if (v == .string) config.ws_url = allocator.dupe(u8, v.string) catch null;
    }
    if (parsed.get("last_target")) |v| {
        if (v == .string) config.last_target = allocator.dupe(u8, v.string) catch null;
    }
    if (parsed.get("last_mouse_x")) |v| {
        if (v == .float) config.last_mouse_x = v.float;
        if (v == .integer) config.last_mouse_x = @floatFromInt(v.integer);
    }
    if (parsed.get("last_mouse_y")) |v| {
        if (v == .float) config.last_mouse_y = v.float;
        if (v == .integer) config.last_mouse_y = @floatFromInt(v.integer);
    }

    if (parsed.get("viewport_width")) |v| {
        if (v == .integer) config.viewport_width = @intCast(v.integer);
    }
    if (parsed.get("viewport_height")) |v| {
        if (v == .integer) config.viewport_height = @intCast(v.integer);
    }
    if (parsed.get("device_name")) |v| {
        if (v == .string) config.device_name = allocator.dupe(u8, v.string) catch null;
    }
    if (parsed.get("geo_lat")) |v| {
        if (v == .float) config.geo_lat = v.float;
        if (v == .integer) config.geo_lat = @floatFromInt(v.integer);
    }
    if (parsed.get("geo_lng")) |v| {
        if (v == .float) config.geo_lng = v.float;
        if (v == .integer) config.geo_lng = @floatFromInt(v.integer);
    }
    if (parsed.get("offline")) |v| {
        if (v == .bool) config.offline = v.bool;
    }
    if (parsed.get("headers")) |v| {
        if (v == .string) config.headers = allocator.dupe(u8, v.string) catch null;
    }
    if (parsed.get("auth_user")) |v| {
        if (v == .string) config.auth_user = allocator.dupe(u8, v.string) catch null;
    }
    if (parsed.get("auth_pass")) |v| {
        if (v == .string) config.auth_pass = allocator.dupe(u8, v.string) catch null;
    }
    if (parsed.get("media_feature")) |v| {
        if (v == .string) config.media_feature = allocator.dupe(u8, v.string) catch null;
    }
    if (parsed.get("user_agent")) |v| {
        if (v == .string) config.user_agent = allocator.dupe(u8, v.string) catch null;
    }
    if (parsed.get("provider")) |v| {
        if (v == .string) config.provider = allocator.dupe(u8, v.string) catch null;
    }
    if (parsed.get("provider_session_id")) |v| {
        if (v == .string) config.provider_session_id = allocator.dupe(u8, v.string) catch null;
    }
    if (parsed.get("provider_auto_cleanup")) |v| {
        if (v == .bool) config.provider_auto_cleanup = v.bool;
    }
    if (parsed.get("chrome_args")) |v| {
        if (v == .array) {
            var args_list: std.ArrayList([]const u8) = .empty;
            for (v.array.items) |item| {
                if (item == .string) {
                    if (allocator.dupe(u8, item.string)) |s| {
                        args_list.append(allocator, s) catch {};
                    } else |_| {}
                }
            }
            config.chrome_args = args_list.toOwnedSlice(allocator) catch null;
        }
    }

    return config;
}
