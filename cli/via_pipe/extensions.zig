//! CDP extension operations via pipe transport.
//!
//! Provides functions to load, unload, and list extensions using
//! Chrome DevTools Protocol Extensions domain.

const std = @import("std");
const json = @import("json");
const launcher = @import("launcher.zig");

const ChromePipe = launcher.ChromePipe;

/// Extension information returned by getExtensions.
pub const ExtensionInfo = struct {
    id: []const u8,
    name: []const u8,
    version: []const u8,
    path: []const u8,
    enabled: bool,
};

/// Load an unpacked extension via CDP Extensions.loadUnpacked.
/// Returns the extension ID on success.
pub fn loadExtension(chrome: *ChromePipe, path: []const u8) ![]const u8 {
    const result = try chrome.sendCommand("Extensions.loadUnpacked", .{
        .path = path,
    });

    // Extract extension ID from result
    if (result.get("id")) |id_val| {
        if (id_val == .string) {
            return try chrome.allocator.dupe(u8, id_val.string);
        }
    }

    return error.NoExtensionId;
}

/// Load an unpacked extension with incognito mode enabled.
pub fn loadExtensionWithIncognito(chrome: *ChromePipe, path: []const u8) ![]const u8 {
    const result = try chrome.sendCommand("Extensions.loadUnpacked", .{
        .path = path,
        .enableInIncognito = true,
    });

    if (result.get("id")) |id_val| {
        if (id_val == .string) {
            return try chrome.allocator.dupe(u8, id_val.string);
        }
    }

    return error.NoExtensionId;
}

/// Unload an extension via CDP Extensions.uninstall.
pub fn unloadExtension(chrome: *ChromePipe, extension_id: []const u8) !void {
    _ = try chrome.sendCommand("Extensions.uninstall", .{
        .id = extension_id,
    });
}

/// Get list of loaded unpacked extensions.
pub fn getExtensions(chrome: *ChromePipe) ![]ExtensionInfo {
    const result = try chrome.sendCommand("Extensions.getExtensions", .{});

    if (result.get("extensions")) |exts_val| {
        if (exts_val == .array) {
            var list = std.ArrayList(ExtensionInfo).init(chrome.allocator);
            errdefer {
                for (list.items) |item| {
                    chrome.allocator.free(item.id);
                    chrome.allocator.free(item.name);
                    chrome.allocator.free(item.version);
                    chrome.allocator.free(item.path);
                }
                list.deinit();
            }

            for (exts_val.array.items) |ext| {
                const info = ExtensionInfo{
                    .id = if (ext.get("id")) |v| if (v == .string) try chrome.allocator.dupe(u8, v.string) else "" else "",
                    .name = if (ext.get("name")) |v| if (v == .string) try chrome.allocator.dupe(u8, v.string) else "" else "",
                    .version = if (ext.get("version")) |v| if (v == .string) try chrome.allocator.dupe(u8, v.string) else "" else "",
                    .path = if (ext.get("path")) |v| if (v == .string) try chrome.allocator.dupe(u8, v.string) else "" else "",
                    .enabled = if (ext.get("enabled")) |v| v == .true else false,
                };
                try list.append(info);
            }

            return try list.toOwnedSlice();
        }
    }

    return &[_]ExtensionInfo{};
}

/// Free extension info list returned by getExtensions.
pub fn freeExtensions(allocator: std.mem.Allocator, extensions: []ExtensionInfo) void {
    for (extensions) |ext| {
        if (ext.id.len > 0) allocator.free(ext.id);
        if (ext.name.len > 0) allocator.free(ext.name);
        if (ext.version.len > 0) allocator.free(ext.version);
        if (ext.path.len > 0) allocator.free(ext.path);
    }
    allocator.free(extensions);
}
