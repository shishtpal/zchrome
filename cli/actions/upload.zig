const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");
const helpers = @import("helpers.zig");

pub const ResolvedElement = types.ResolvedElement;

/// Upload files to a file input element using Runtime.evaluate with object reference
pub fn uploadFiles(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    io: std.Io,
    resolved: *const ResolvedElement,
    files: []const []const u8,
) !void {
    // Convert relative paths to absolute paths (CDP requires absolute paths)
    var absolute_files = try allocator.alloc([]const u8, files.len);
    defer {
        for (absolute_files) |f| allocator.free(f);
        allocator.free(absolute_files);
    }

    const cwd = std.Io.Dir.cwd();
    for (files, 0..) |file, i| {
        // Check if path is already absolute (starts with drive letter on Windows or / on Unix)
        const is_absolute = if (file.len >= 2 and file[1] == ':')
            true // Windows: C:\...
        else if (file.len >= 1 and file[0] == '/')
            true // Unix: /...
        else
            false;

        if (is_absolute) {
            absolute_files[i] = try allocator.dupe(u8, file);
        } else {
            // Convert to absolute path using realpath
            absolute_files[i] = try cwd.realPathFileAlloc(io, file, allocator);
        }
    }

    // Debug: print files being uploaded
    std.debug.print("Uploading {} file(s):\n", .{absolute_files.len});
    for (absolute_files) |f| {
        std.debug.print("  - {s}\n", .{f});
    }

    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // First, get a reference to the element using Runtime.evaluate
    var js: []const u8 = undefined;
    defer allocator.free(js);

    if (resolved.css_selector) |css| {
        const escaped_css = try helpers.escapeJsString(allocator, css);
        defer allocator.free(escaped_css);
        js = try std.fmt.allocPrint(allocator, "document.querySelector({s})", .{escaped_css});
    } else {
        const role = resolved.role orelse return error.InvalidSelector;
        const name_arg = if (resolved.name) |n| try helpers.escapeJsString(allocator, n) else try allocator.dupe(u8, "null");
        defer allocator.free(name_arg);
        const nth = resolved.nth orelse 0;

        js = try std.fmt.allocPrint(allocator,
            \\(function(role,name,nth){{var els=Array.from(document.querySelectorAll('input[type="file"]'));if(name)els=els.filter(function(e){{var label=e.getAttribute('aria-label')||e.name||'';return label===name}});return els[nth||0]||null}})('{s}',{s},{d})
        , .{ role, name_arg, nth });
    }

    // Evaluate to get object reference (not by value - we need the remote object ID)
    var result = try runtime.evaluate(allocator, js, .{});
    defer result.deinit(allocator);

    const object_id = result.object_id orelse {
        std.debug.print("Error: Could not get element reference (element not found?)\n", .{});
        return error.ElementNotFound;
    };

    std.debug.print("Object ID: {s}\n", .{object_id});

    // Now use DOM.setFileInputFiles with objectId instead of nodeId
    _ = try session.sendCommand("DOM.setFileInputFiles", .{
        .object_id = object_id,
        .files = absolute_files,
    });
}
