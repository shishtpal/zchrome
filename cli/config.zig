const std = @import("std");

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

/// Load configuration from zchrome.json
pub fn loadConfig(allocator: std.mem.Allocator, io: std.Io) ?Config {
    // Try to get exe directory, fall back to cwd
    const exe_dir_path = std.process.executableDirPathAlloc(io, allocator) catch null;
    defer if (exe_dir_path) |p| allocator.free(p);

    const dir = if (exe_dir_path) |p|
        std.Io.Dir.openDirAbsolute(io, p, .{}) catch std.Io.Dir.cwd()
    else
        std.Io.Dir.cwd();

    // Read the file
    var file_buf: [64 * 1024]u8 = undefined;
    const content = dir.readFile(io, config_filename, &file_buf) catch return null;

    // Parse JSON
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch return null;
    defer parsed.deinit();

    // Extract fields
    var config = Config{};

    if (parsed.value.object.get("chrome_path")) |v| {
        if (v == .string) config.chrome_path = allocator.dupe(u8, v.string) catch null;
    }
    if (parsed.value.object.get("data_dir")) |v| {
        if (v == .string) config.data_dir = allocator.dupe(u8, v.string) catch null;
    }
    if (parsed.value.object.get("port")) |v| {
        if (v == .integer) config.port = @intCast(v.integer);
    }
    if (parsed.value.object.get("ws_url")) |v| {
        if (v == .string) config.ws_url = allocator.dupe(u8, v.string) catch null;
    }
    if (parsed.value.object.get("last_target")) |v| {
        if (v == .string) config.last_target = allocator.dupe(u8, v.string) catch null;
    }
    if (parsed.value.object.get("last_mouse_x")) |v| {
        if (v == .float) config.last_mouse_x = v.float;
        if (v == .integer) config.last_mouse_x = @floatFromInt(v.integer);
    }
    if (parsed.value.object.get("last_mouse_y")) |v| {
        if (v == .float) config.last_mouse_y = v.float;
        if (v == .integer) config.last_mouse_y = @floatFromInt(v.integer);
    }

    if (parsed.value.object.get("viewport_width")) |v| {
        if (v == .integer) config.viewport_width = @intCast(v.integer);
    }
    if (parsed.value.object.get("viewport_height")) |v| {
        if (v == .integer) config.viewport_height = @intCast(v.integer);
    }
    if (parsed.value.object.get("device_name")) |v| {
        if (v == .string) config.device_name = allocator.dupe(u8, v.string) catch null;
    }
    if (parsed.value.object.get("geo_lat")) |v| {
        if (v == .float) config.geo_lat = v.float;
        if (v == .integer) config.geo_lat = @floatFromInt(v.integer);
    }
    if (parsed.value.object.get("geo_lng")) |v| {
        if (v == .float) config.geo_lng = v.float;
        if (v == .integer) config.geo_lng = @floatFromInt(v.integer);
    }
    if (parsed.value.object.get("offline")) |v| {
        if (v == .bool) config.offline = v.bool;
    }
    if (parsed.value.object.get("headers")) |v| {
        if (v == .string) config.headers = allocator.dupe(u8, v.string) catch null;
    }
    if (parsed.value.object.get("auth_user")) |v| {
        if (v == .string) config.auth_user = allocator.dupe(u8, v.string) catch null;
    }
    if (parsed.value.object.get("auth_pass")) |v| {
        if (v == .string) config.auth_pass = allocator.dupe(u8, v.string) catch null;
    }
    if (parsed.value.object.get("media_feature")) |v| {
        if (v == .string) config.media_feature = allocator.dupe(u8, v.string) catch null;
    }

    return config;
}

/// Save configuration to zchrome.json
pub fn saveConfig(config: Config, allocator: std.mem.Allocator, io: std.Io) !void {
    // Build JSON string
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(allocator);

    try json_buf.appendSlice(allocator, "{\n");

    var first = true;

    if (config.chrome_path) |path| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"chrome_path\": \"");
        try appendEscapedString(&json_buf, allocator, path);
        try json_buf.appendSlice(allocator, "\"");
    }

    if (config.data_dir) |dir| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"data_dir\": \"");
        try appendEscapedString(&json_buf, allocator, dir);
        try json_buf.appendSlice(allocator, "\"");
    }

    // Always write port
    if (!first) try json_buf.appendSlice(allocator, ",\n");
    first = false;
    const port_str = try std.fmt.allocPrint(allocator, "  \"port\": {}", .{config.port});
    defer allocator.free(port_str);
    try json_buf.appendSlice(allocator, port_str);

    if (config.ws_url) |url| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"ws_url\": \"");
        try appendEscapedString(&json_buf, allocator, url);
        try json_buf.appendSlice(allocator, "\"");
    }

    if (config.last_target) |target| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"last_target\": \"");
        try appendEscapedString(&json_buf, allocator, target);
        try json_buf.appendSlice(allocator, "\"");
    }

    if (config.last_mouse_x) |x| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        const x_str = try std.fmt.allocPrint(allocator, "  \"last_mouse_x\": {d}", .{x});
        defer allocator.free(x_str);
        try json_buf.appendSlice(allocator, x_str);
    }

    if (config.last_mouse_y) |y| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        const y_str = try std.fmt.allocPrint(allocator, "  \"last_mouse_y\": {d}", .{y});
        defer allocator.free(y_str);
        try json_buf.appendSlice(allocator, y_str);
    }

    if (config.viewport_width) |w| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        const s = try std.fmt.allocPrint(allocator, "  \"viewport_width\": {}", .{w});
        defer allocator.free(s);
        try json_buf.appendSlice(allocator, s);
    }
    if (config.viewport_height) |h| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        const s = try std.fmt.allocPrint(allocator, "  \"viewport_height\": {}", .{h});
        defer allocator.free(s);
        try json_buf.appendSlice(allocator, s);
    }
    if (config.device_name) |d| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"device_name\": \"");
        try appendEscapedString(&json_buf, allocator, d);
        try json_buf.appendSlice(allocator, "\"");
    }
    if (config.geo_lat) |lat| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        const s = try std.fmt.allocPrint(allocator, "  \"geo_lat\": {d}", .{lat});
        defer allocator.free(s);
        try json_buf.appendSlice(allocator, s);
    }
    if (config.geo_lng) |lng| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        const s = try std.fmt.allocPrint(allocator, "  \"geo_lng\": {d}", .{lng});
        defer allocator.free(s);
        try json_buf.appendSlice(allocator, s);
    }
    if (config.offline) |off| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, if (off) "  \"offline\": true" else "  \"offline\": false");
    }
    if (config.headers) |h| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"headers\": \"");
        try appendEscapedString(&json_buf, allocator, h);
        try json_buf.appendSlice(allocator, "\"");
    }
    if (config.auth_user) |u| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"auth_user\": \"");
        try appendEscapedString(&json_buf, allocator, u);
        try json_buf.appendSlice(allocator, "\"");
    }
    if (config.auth_pass) |p| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"auth_pass\": \"");
        try appendEscapedString(&json_buf, allocator, p);
        try json_buf.appendSlice(allocator, "\"");
    }
    if (config.media_feature) |m| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"media_feature\": \"");
        try appendEscapedString(&json_buf, allocator, m);
        try json_buf.appendSlice(allocator, "\"");
    }

    try json_buf.appendSlice(allocator, "\n}\n");

    // Try to get exe directory, fall back to cwd
    const exe_dir_path = std.process.executableDirPathAlloc(io, allocator) catch null;
    defer if (exe_dir_path) |p| allocator.free(p);

    const dir = if (exe_dir_path) |p|
        std.Io.Dir.openDirAbsolute(io, p, .{}) catch std.Io.Dir.cwd()
    else
        std.Io.Dir.cwd();

    // Write to file
    dir.writeFile(io, .{
        .sub_path = config_filename,
        .data = json_buf.items,
    }) catch |err| {
        std.debug.print("Error writing config: {}\n", .{err});
        return err;
    };
}

/// Escape a string for JSON output (handles backslashes and quotes)
fn appendEscapedString(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, str: []const u8) !void {
    for (str) |c| {
        switch (c) {
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            '"' => try buf.appendSlice(allocator, "\\\""),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            '\t' => try buf.appendSlice(allocator, "\\t"),
            else => try buf.append(allocator, c),
        }
    }
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
