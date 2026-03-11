const std = @import("std");
const root = @import("../config.zig");
const Config = root.Config;

/// Merge two configs, with user config values taking precedence over base config.
/// For optional fields: use user value if present, otherwise base value.
/// Frees overridden base values and the user config's unused allocations.
pub fn mergeConfig(allocator: std.mem.Allocator, base: *Config, user: *Config) Config {
    return .{
        // String fields - user overrides base (free the losing value)
        .chrome_path = mergeStringField(allocator, &base.chrome_path, &user.chrome_path),
        .data_dir = mergeStringField(allocator, &base.data_dir, &user.data_dir),
        .ws_url = mergeStringField(allocator, &base.ws_url, &user.ws_url),
        .last_target = mergeStringField(allocator, &base.last_target, &user.last_target),
        .device_name = mergeStringField(allocator, &base.device_name, &user.device_name),
        .headers = mergeStringField(allocator, &base.headers, &user.headers),
        .auth_user = mergeStringField(allocator, &base.auth_user, &user.auth_user),
        .auth_pass = mergeStringField(allocator, &base.auth_pass, &user.auth_pass),
        .media_feature = mergeStringField(allocator, &base.media_feature, &user.media_feature),
        .user_agent = mergeStringField(allocator, &base.user_agent, &user.user_agent),
        .provider = mergeStringField(allocator, &base.provider, &user.provider),
        .provider_session_id = mergeStringField(allocator, &base.provider_session_id, &user.provider_session_id),

        // Numeric fields - user overrides base
        .last_mouse_x = user.last_mouse_x orelse base.last_mouse_x,
        .last_mouse_y = user.last_mouse_y orelse base.last_mouse_y,
        .viewport_width = user.viewport_width orelse base.viewport_width,
        .viewport_height = user.viewport_height orelse base.viewport_height,
        .geo_lat = user.geo_lat orelse base.geo_lat,
        .geo_lng = user.geo_lng orelse base.geo_lng,

        // Bool fields - user overrides base
        .offline = user.offline orelse base.offline,
        .provider_auto_cleanup = user.provider_auto_cleanup orelse base.provider_auto_cleanup,

        // Port - user overrides base if user has a value set
        .port = user.port orelse base.port,

        // Via mode - user overrides base
        .via = mergeStringField(allocator, &base.via, &user.via),

        // Array fields - user overrides base (free the losing value)
        .chrome_args = mergeArrayField(allocator, &base.chrome_args, &user.chrome_args),
        .extensions = mergeArrayField(allocator, &base.extensions, &user.extensions),
    };
}

/// Merge an optional string field, freeing the value that won't be used.
/// Returns user value if present (frees base), otherwise base value (frees user).
fn mergeStringField(
    allocator: std.mem.Allocator,
    base: *?[]const u8,
    user: *?[]const u8,
) ?[]const u8 {
    if (user.*) |u| {
        // User has value - use it, free base if present
        if (base.*) |b| allocator.free(b);
        base.* = null;
        user.* = null;
        return u;
    } else {
        // No user value - use base
        const result = base.*;
        base.* = null;
        return result;
    }
}

/// Merge an optional array field, freeing the value that won't be used.
fn mergeArrayField(
    allocator: std.mem.Allocator,
    base: *?[]const []const u8,
    user: *?[]const []const u8,
) ?[]const []const u8 {
    if (user.*) |u| {
        // User has value - use it, free base if present
        if (base.*) |b| {
            for (b) |item| allocator.free(item);
            allocator.free(b);
        }
        base.* = null;
        user.* = null;
        return u;
    } else {
        // No user value - use base
        const result = base.*;
        base.* = null;
        return result;
    }
}
