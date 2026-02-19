const std = @import("std");
const Session = @import("../core/session.zig").Session;
const json_util = @import("../util/json.zig");

/// Storage domain client
pub const Storage = struct {
    session: *Session,

    const Self = @This();

    pub fn init(session: *Session) Self {
        return .{ .session = session };
    }

    /// Get cookies
    pub fn getCookies(self: *Self, allocator: std.mem.Allocator, urls: ?[]const []const u8) ![]Cookie {
        const result = try self.session.sendCommand("Storage.getCookies", .{
            .urls = urls,
        });

        const cookies_arr = try json_util.getArray(result, "cookies");
        var cookies: std.ArrayList(Cookie) = .empty;
        errdefer cookies.deinit(allocator);

        for (cookies_arr) |c| {
            try cookies.append(allocator, try parseCookie(allocator, c));
        }

        return cookies.toOwnedSlice(allocator);
    }

    /// Set cookies
    pub fn setCookies(self: *Self, cookies: []const CookieParam) !void {
        _ = try self.session.sendCommand("Storage.setCookies", .{
            .cookies = cookies,
        });
    }

    /// Clear cookies
    pub fn clearCookies(self: *Self) !void {
        _ = try self.session.sendCommand("Storage.clearCookies", .{});
    }

    /// Delete cookies
    pub fn deleteCookies(self: *Self, name: []const u8, url: ?[]const u8, domain: ?[]const u8) !void {
        _ = try self.session.sendCommand("Storage.deleteCookies", .{
            .name = name,
            .url = url,
            .domain = domain,
        });
    }
};

/// Cookie
pub const Cookie = struct {
    name: []const u8,
    value: []const u8,
    domain: []const u8,
    path: []const u8,
    expires: f64,
    size: i64,
    http_only: bool,
    secure: bool,
    session: bool,
    same_site: ?[]const u8 = null,

    pub fn deinit(self: *Cookie, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.value);
        allocator.free(self.domain);
        allocator.free(self.path);
        if (self.same_site) |s| allocator.free(s);
    }
};

/// Cookie parameter for setting
pub const CookieParam = struct {
    name: []const u8,
    value: []const u8,
    url: ?[]const u8 = null,
    domain: ?[]const u8 = null,
    path: ?[]const u8 = null,
    secure: ?bool = null,
    http_only: ?bool = null,
    same_site: ?[]const u8 = null,
    expires: ?f64 = null,
};

/// Parse cookie from JSON
fn parseCookie(allocator: std.mem.Allocator, obj: std.json.Value) !Cookie {
    return .{
        .name = try allocator.dupe(u8, try json_util.getString(obj, "name")),
        .value = try allocator.dupe(u8, try json_util.getString(obj, "value")),
        .domain = try allocator.dupe(u8, try json_util.getString(obj, "domain")),
        .path = try allocator.dupe(u8, try json_util.getString(obj, "path")),
        .expires = try json_util.getFloat(obj, "expires"),
        .size = try json_util.getInt(obj, "size"),
        .http_only = try json_util.getBool(obj, "httpOnly"),
        .secure = try json_util.getBool(obj, "secure"),
        .session = try json_util.getBool(obj, "session"),
        .same_site = if (obj.object.get("sameSite")) |v|
            try allocator.dupe(u8, v.string)
        else
            null,
    };
}
