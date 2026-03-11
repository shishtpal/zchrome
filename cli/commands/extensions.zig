//! Extension management command implementation.
//!
//! Provides commands for loading, listing, and unloading Chrome extensions.

const std = @import("std");
const session_mod = @import("../session.zig");
const config_mod = @import("../config.zig");

/// Extensions command - load, list, unload extensions
pub fn extensions(session_ctx: *const session_mod.SessionContext, positional: []const []const u8) !void {
    const allocator = session_ctx.allocator;

    if (positional.len == 0) {
        // Show loaded extensions
        try listExtensions(session_ctx);
        return;
    }

    const subcmd = positional[0];

    if (std.mem.eql(u8, subcmd, "load")) {
        if (positional.len < 2) {
            std.debug.print("Error: extensions load requires a path\n", .{});
            std.debug.print("Usage: zchrome extensions load <path>\n", .{});
            return;
        }
        try loadExtension(session_ctx, positional[1]);
    } else if (std.mem.eql(u8, subcmd, "list")) {
        try listExtensions(session_ctx);
    } else if (std.mem.eql(u8, subcmd, "unload")) {
        if (positional.len < 2) {
            std.debug.print("Error: extensions unload requires a path\n", .{});
            std.debug.print("Usage: zchrome extensions unload <path>\n", .{});
            return;
        }
        try unloadExtension(allocator, session_ctx, positional[1]);
    } else {
        std.debug.print("Unknown extensions command: {s}\n", .{subcmd});
        printExtensionsHelp();
    }
}

/// Load an extension by path
fn loadExtension(session_ctx: *const session_mod.SessionContext, path: []const u8) !void {
    const allocator = session_ctx.allocator;
    const io = session_ctx.io;

    // Resolve to absolute path (Chrome requires absolute paths for --load-extension)
    const cwd = std.Io.Dir.cwd();

    // Check if path is already absolute
    const is_absolute = if (path.len >= 2 and path[1] == ':')
        true // Windows: C:\...
    else if (path.len >= 1 and path[0] == '/')
        true // Unix: /...
    else
        false;

    // Validate the path exists and get absolute path
    const absolute_path = blk: {
        if (is_absolute) {
            // Validate absolute path exists
            var dir = std.Io.Dir.openDirAbsolute(io, path, .{}) catch {
                std.debug.print("Error: Extension path does not exist: {s}\n", .{path});
                return;
            };
            dir.close(io);
            break :blk try allocator.dupe(u8, path);
        } else {
            // Validate relative path exists
            var dir = cwd.openDir(io, path, .{}) catch {
                std.debug.print("Error: Extension path does not exist: {s}\n", .{path});
                return;
            };
            dir.close(io);
            // Get the real absolute path using manifest.json as anchor
            const manifest_path = std.fs.path.join(allocator, &.{ path, "manifest.json" }) catch {
                std.debug.print("Error: Could not resolve path: {s}\n", .{path});
                return;
            };
            defer allocator.free(manifest_path);
            const abs_manifest = cwd.realPathFileAlloc(io, manifest_path, allocator) catch {
                std.debug.print("Error: Extension path missing manifest.json: {s}\n", .{path});
                return;
            };
            defer allocator.free(abs_manifest);
            // Strip /manifest.json from the end to get directory path
            break :blk try allocator.dupe(u8, std.fs.path.dirname(abs_manifest) orelse path);
        }
    };
    defer allocator.free(absolute_path);

    // Load current config
    var config = session_ctx.loadConfig() orelse config_mod.Config{};
    defer config.deinit(allocator);

    // Check if already loaded
    if (config.extensions) |exts| {
        for (exts) |ext| {
            if (std.mem.eql(u8, ext, absolute_path)) {
                std.debug.print("Extension already loaded: {s}\n", .{absolute_path});
                return;
            }
        }
    }

    // Add to extensions list
    var ext_list: std.ArrayList([]const u8) = .empty;
    defer ext_list.deinit(allocator);

    // Copy existing extensions
    if (config.extensions) |exts| {
        for (exts) |ext| {
            try ext_list.append(allocator, try allocator.dupe(u8, ext));
        }
    }

    // Add new extension (using absolute path)
    try ext_list.append(allocator, try allocator.dupe(u8, absolute_path));

    // Update config
    if (config.extensions) |old| {
        for (old) |ext| allocator.free(ext);
        allocator.free(old);
    }
    config.extensions = try ext_list.toOwnedSlice(allocator);

    // Save config
    session_ctx.saveConfig(config) catch |err| {
        std.debug.print("Error saving config: {}\n", .{err});
        return;
    };

    std.debug.print("Loaded extension: {s}\n", .{path});
    std.debug.print("Note: Restart Chrome with 'zchrome open' to apply changes.\n", .{});
}

/// List loaded extensions
fn listExtensions(session_ctx: *const session_mod.SessionContext) !void {
    const allocator = session_ctx.allocator;

    const cfg = session_ctx.loadConfig();
    if (cfg == null) {
        std.debug.print("No extensions loaded.\n", .{});
        return;
    }

    var config = cfg.?;
    defer config.deinit(allocator);

    if (config.extensions == null or config.extensions.?.len == 0) {
        std.debug.print("No extensions loaded.\n", .{});
        return;
    }

    std.debug.print("Loaded extensions:\n", .{});
    for (config.extensions.?, 0..) |ext, i| {
        std.debug.print("  {}. {s}\n", .{ i + 1, ext });
    }
    std.debug.print("\nTotal: {} extension(s)\n", .{config.extensions.?.len});
}

/// Unload an extension by path
fn unloadExtension(allocator: std.mem.Allocator, session_ctx: *const session_mod.SessionContext, path: []const u8) !void {
    // Load current config
    var config = session_ctx.loadConfig() orelse {
        std.debug.print("No extensions loaded.\n", .{});
        return;
    };
    defer config.deinit(allocator);

    if (config.extensions == null or config.extensions.?.len == 0) {
        std.debug.print("No extensions loaded.\n", .{});
        return;
    }

    // Find and remove the extension
    var found = false;
    var ext_list: std.ArrayList([]const u8) = .empty;
    defer ext_list.deinit(allocator);

    for (config.extensions.?) |ext| {
        if (std.mem.eql(u8, ext, path)) {
            found = true;
            // Don't add to new list (removing it)
        } else {
            try ext_list.append(allocator, try allocator.dupe(u8, ext));
        }
    }

    if (!found) {
        std.debug.print("Extension not found: {s}\n", .{path});
        return;
    }

    // Update config
    if (config.extensions) |old| {
        for (old) |ext| allocator.free(ext);
        allocator.free(old);
    }
    config.extensions = if (ext_list.items.len > 0)
        try ext_list.toOwnedSlice(allocator)
    else
        null;

    // Save config
    session_ctx.saveConfig(config) catch |err| {
        std.debug.print("Error saving config: {}\n", .{err});
        return;
    };

    std.debug.print("Unloaded extension: {s}\n", .{path});
    std.debug.print("Note: Restart Chrome with 'zchrome open' to apply changes.\n", .{});
}

/// Print extensions command help
pub fn printExtensionsHelp() void {
    std.debug.print(
        \\Usage: zchrome extensions [subcommand]
        \\
        \\Manage Chrome extensions for the current session.
        \\
        \\Subcommands:
        \\  extensions              List loaded extensions
        \\  extensions list         List loaded extensions
        \\  extensions load <path>  Load an unpacked extension
        \\  extensions unload <p>   Unload an extension by path
        \\
        \\Environment variable:
        \\  ZCHROME_EXTENSIONS      Comma-separated paths to load
        \\                          (merges with config file extensions)
        \\
        \\Config file:
        \\  Add to zchrome.json:
        \\  {{
        \\    "extensions": ["/path/to/ext1", "/path/to/ext2"]
        \\  }}
        \\
        \\Notes:
        \\  - Extensions require headed mode (headless is auto-disabled)
        \\  - Extensions cannot be used with cloud providers
        \\  - Restart Chrome after loading/unloading extensions
        \\
        \\Examples:
        \\  zchrome extensions load /path/to/my-extension
        \\  zchrome extensions list
        \\  zchrome extensions unload /path/to/my-extension
        \\  ZCHROME_EXTENSIONS="/ext1,/ext2" zchrome open
        \\
    , .{});
}
