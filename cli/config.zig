const std = @import("std");

/// Configuration stored in zchrome.json alongside the executable
pub const Config = struct {
    chrome_path: ?[]const u8 = null,
    data_dir: ?[]const u8 = null,
    port: u16 = 9222,
    ws_url: ?[]const u8 = null,
    last_target: ?[]const u8 = null,

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        if (self.chrome_path) |p| allocator.free(p);
        if (self.data_dir) |d| allocator.free(d);
        if (self.ws_url) |u| allocator.free(u);
        if (self.last_target) |t| allocator.free(t);
        self.* = .{};
    }
};

/// Get the path to zchrome.json (alongside the executable)
pub fn getConfigPath(allocator: std.mem.Allocator, io: std.Io) ![]const u8 {
    _ = io;
    // For portability, use "zchrome.json" in the current working directory
    // This allows the config to be placed alongside the executable
    return allocator.dupe(u8, "zchrome.json");
}

/// Load configuration from zchrome.json
pub fn loadConfig(allocator: std.mem.Allocator, io: std.Io) ?Config {
    const config_path = getConfigPath(allocator, io) catch return null;
    defer allocator.free(config_path);

    // Read the file
    const dir = std.Io.Dir.cwd();
    var file_buf: [64 * 1024]u8 = undefined;
    const content = dir.readFile(io, config_path, &file_buf) catch return null;

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

    return config;
}

/// Save configuration to zchrome.json
pub fn saveConfig(config: Config, allocator: std.mem.Allocator, io: std.Io) !void {
    const config_path = try getConfigPath(allocator, io);
    defer allocator.free(config_path);

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

    try json_buf.appendSlice(allocator, "\n}\n");

    // Write to file
    const dir = std.Io.Dir.cwd();
    dir.writeFile(io, .{
        .sub_path = config_path,
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
