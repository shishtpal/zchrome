const std = @import("std");

/// Chrome process lifecycle management
/// NOTE: In Zig 0.16, file I/O is complex. For now, users should launch Chrome
/// manually with --remote-debugging-port and use Browser.connect().
pub const ChromeProcess = struct {
    child: ?std.process.Child,
    ws_url: ?[]const u8,
    allocator: std.mem.Allocator,
    io: std.Io,
    temp_dir: ?[]const u8,
    has_exited: bool,

    const Self = @This();

    /// Spawn a Chrome process
    pub fn spawn(
        allocator: std.mem.Allocator,
        io: std.Io,
        exe_path: []const u8,
        args: []const []const u8,
    ) !*Self {
        // Build argv with the executable path as first element
        const argv = try allocator.alloc([]const u8, args.len);
        defer allocator.free(argv);
        argv[0] = exe_path;
        for (args[1..], 1..) |arg, i| {
            argv[i] = arg;
        }

        // Spawn the child process
        const child = std.process.spawn(io, .{
            .argv = argv,
            .stdin = .ignore,
            .stdout = .ignore,
            .stderr = .pipe,
        }) catch |err| {
            return err;
        };

        const self = try allocator.create(Self);
        self.* = .{
            .child = child,
            .ws_url = null,
            .allocator = allocator,
            .io = io,
            .temp_dir = null,
            .has_exited = false,
        };

        return self;
    }

    /// Wait for WebSocket URL to be parsed from stderr
    /// NOTE: This is a stub. The Zig 0.16 file reading API needs proper implementation.
    /// For now, use Browser.connect() with a manually started Chrome instance.
    pub fn waitForWsUrl(self: *Self, timeout_ms: u64) ![]const u8 {
        _ = timeout_ms;

        if (self.ws_url) |url| {
            return url;
        }

        // Since reading from the child's stderr is complex in Zig 0.16,
        // return an error suggesting manual Chrome launch
        return error.StartupTimeout;
    }

    /// Wait for the process to exit
    pub fn waitForExit(self: *Self, timeout_ms: u64) !u32 {
        _ = timeout_ms;

        if (self.has_exited) {
            return 0;
        }

        if (self.child) |*child| {
            const term = child.wait(self.io) catch return error.Timeout;
            self.has_exited = true;
            self.child = null;

            return switch (term) {
                .exited => |code| code,
                .signal => |sig| @intFromEnum(sig),
                else => 1,
            };
        }

        return error.Timeout;
    }

    /// Kill the process
    pub fn kill(self: *Self) void {
        if (self.has_exited) return;

        if (self.child) |*child| {
            child.kill(self.io);
            self.child = null;
        }

        self.has_exited = true;
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        // Kill if still running
        if (!self.has_exited) {
            self.kill();
        }

        // Clean up temp directory
        if (self.temp_dir) |dir| {
            self.allocator.free(dir);
        }

        // Free WebSocket URL
        if (self.ws_url) |url| {
            self.allocator.free(url);
        }

        self.allocator.destroy(self);
    }

    /// Set the temp directory path
    pub fn setTempDir(self: *Self, path: []const u8) !void {
        self.temp_dir = try self.allocator.dupe(u8, path);
    }
};

/// Parse WebSocket URL from Chrome stderr output
fn parseWsUrlFromStderr(line: []const u8) ?[]const u8 {
    // Chrome outputs: "DevTools listening on ws://127.0.0.1:XXXXX/devtools/browser/GUID"
    const prefix = "DevTools listening on ";

    const start = std.mem.indexOf(u8, line, prefix) orelse return null;
    const url_start = start + prefix.len;

    // Find end of URL (whitespace or end of line)
    var url_end = url_start;
    while (url_end < line.len) : (url_end += 1) {
        const c = line[url_end];
        if (c == '\r' or c == '\n' or c == ' ') break;
    }

    return line[url_start..url_end];
}

// ─── Tests ──────────────────────────────────────────────────────────────────

test "parseWsUrlFromStderr" {
    const line = "DevTools listening on ws://127.0.0.1:9222/devtools/browser/abc123\n";
    const result = parseWsUrlFromStderr(line);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("ws://127.0.0.1:9222/devtools/browser/abc123", result.?);
}

test "parseWsUrlFromStderr - no match" {
    const line = "Some other output\n";
    const result = parseWsUrlFromStderr(line);
    try std.testing.expect(result == null);
}
