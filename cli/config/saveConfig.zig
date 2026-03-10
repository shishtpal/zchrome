const std = @import("std");
const json = @import("json");
const root = @import("../config.zig");

const Config = root.Config;

/// Save configuration to zchrome.json (legacy - uses exe directory)
pub fn saveConfig(config: Config, allocator: std.mem.Allocator, io: std.Io) !void {
    const config_path = try root.getConfigPath(allocator, io);
    defer allocator.free(config_path);
    try saveConfigToPath(config, allocator, io, config_path);
}

/// Save configuration to a specific path
pub fn saveConfigToPath(config: Config, allocator: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    // Build JSON string
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(allocator);

    try json_buf.appendSlice(allocator, "{\n");

    var first = true;

    if (config.chrome_path) |cp| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"chrome_path\": \"");
        try json.appendEscapedString(allocator, &json_buf, cp);
        try json_buf.appendSlice(allocator, "\"");
    }

    if (config.data_dir) |dir| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"data_dir\": \"");
        try json.appendEscapedString(allocator, &json_buf, dir);
        try json_buf.appendSlice(allocator, "\"");
    }

    if (config.port) |port| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        const port_str = try std.fmt.allocPrint(allocator, "  \"port\": {}", .{port});
        defer allocator.free(port_str);
        try json_buf.appendSlice(allocator, port_str);
    }

    if (config.ws_url) |url| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"ws_url\": \"");
        try json.appendEscapedString(allocator, &json_buf, url);
        try json_buf.appendSlice(allocator, "\"");
    }

    if (config.last_target) |target| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"last_target\": \"");
        try json.appendEscapedString(allocator, &json_buf, target);
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
        try json.appendEscapedString(allocator, &json_buf, d);
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
        try json.appendEscapedString(allocator, &json_buf, h);
        try json_buf.appendSlice(allocator, "\"");
    }
    if (config.auth_user) |u| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"auth_user\": \"");
        try json.appendEscapedString(allocator, &json_buf, u);
        try json_buf.appendSlice(allocator, "\"");
    }
    if (config.auth_pass) |p| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"auth_pass\": \"");
        try json.appendEscapedString(allocator, &json_buf, p);
        try json_buf.appendSlice(allocator, "\"");
    }
    if (config.media_feature) |m| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"media_feature\": \"");
        try json.appendEscapedString(allocator, &json_buf, m);
        try json_buf.appendSlice(allocator, "\"");
    }
    if (config.user_agent) |ua| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"user_agent\": \"");
        try json.appendEscapedString(allocator, &json_buf, ua);
        try json_buf.appendSlice(allocator, "\"");
    }
    if (config.provider) |p| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"provider\": \"");
        try json.appendEscapedString(allocator, &json_buf, p);
        try json_buf.appendSlice(allocator, "\"");
    }
    if (config.provider_session_id) |sid| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, "  \"provider_session_id\": \"");
        try json.appendEscapedString(allocator, &json_buf, sid);
        try json_buf.appendSlice(allocator, "\"");
    }
    if (config.provider_auto_cleanup) |cleanup| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;
        try json_buf.appendSlice(allocator, if (cleanup) "  \"provider_auto_cleanup\": true" else "  \"provider_auto_cleanup\": false");
    }
    if (config.chrome_args) |args| {
        if (args.len > 0) {
            if (!first) try json_buf.appendSlice(allocator, ",\n");
            first = false;
            try json_buf.appendSlice(allocator, "  \"chrome_args\": [");
            for (args, 0..) |arg, i| {
                if (i > 0) try json_buf.appendSlice(allocator, ", ");
                try json_buf.appendSlice(allocator, "\"");
                try json.appendEscapedString(allocator, &json_buf, arg);
                try json_buf.appendSlice(allocator, "\"");
            }
            try json_buf.appendSlice(allocator, "]");
        }
    }

    try json_buf.appendSlice(allocator, "\n}\n");

    // Write to file at specified path
    const parent_dir = std.fs.path.dirname(path);
    const filename = std.fs.path.basename(path);

    if (parent_dir) |pd| {
        // Absolute or relative path with directory
        const dir = std.Io.Dir.openDirAbsolute(io, pd, .{}) catch std.Io.Dir.cwd();
        dir.writeFile(io, .{
            .sub_path = filename,
            .data = json_buf.items,
        }) catch |err| {
            std.debug.print("Error writing config: {}\n", .{err});
            return err;
        };
    } else {
        // Just a filename, use cwd
        const dir = std.Io.Dir.cwd();
        dir.writeFile(io, .{
            .sub_path = path,
            .data = json_buf.items,
        }) catch |err| {
            std.debug.print("Error writing config: {}\n", .{err});
            return err;
        };
    }
}
