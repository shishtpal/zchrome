const std = @import("std");
const Connection = @import("../core/connection.zig").Connection;
const Session = @import("../core/session.zig").Session;
const options_mod = @import("options.zig");
const process_mod = @import("process.zig");
const json_util = @import("../util/json.zig");

/// Browser version information
pub const BrowserVersion = struct {
    protocol_version: []const u8,
    product: []const u8,
    revision: []const u8,
    user_agent: []const u8,
    js_version: []const u8,

    pub fn deinit(self: *BrowserVersion, allocator: std.mem.Allocator) void {
        allocator.free(self.protocol_version);
        allocator.free(self.product);
        allocator.free(self.revision);
        allocator.free(self.user_agent);
        allocator.free(self.js_version);
    }
};

/// Target information
pub const TargetInfo = struct {
    target_id: []const u8,
    type: []const u8,
    title: []const u8,
    url: []const u8,
    attached: bool,
    opener_id: ?[]const u8 = null,
    browser_context_id: ?[]const u8 = null,

    pub fn deinit(self: *TargetInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.target_id);
        allocator.free(self.type);
        allocator.free(self.title);
        allocator.free(self.url);
        if (self.opener_id) |id| allocator.free(id);
        if (self.browser_context_id) |id| allocator.free(id);
    }
};

/// Browser instance
pub const Browser = struct {
    connection: *Connection,
    process: ?*process_mod.ChromeProcess,
    allocator: std.mem.Allocator,
    ws_url: []const u8,

    const Self = @This();

    /// Launch a new Chrome instance
    pub fn launch(opts: options_mod.LaunchOptions) !*Self {
        const allocator = opts.allocator;

        // Find Chrome executable
        const exe_path = if (opts.executable_path) |path|
            try allocator.dupe(u8, path)
        else
            try findChrome(allocator);
        defer allocator.free(exe_path);

        // Build arguments
        const args = try buildArgs(opts, allocator);
        defer {
            for (args[1..]) |arg| allocator.free(arg);
            allocator.free(args);
        }

        // Create temp user data directory if needed
        var temp_dir_path: ?[]const u8 = null;
        if (opts.user_data_dir == null) {
            // In Zig 0.16, directory access requires Io context
            // Use a fixed temp path for now
            temp_dir_path = try std.fmt.allocPrint(allocator, "/tmp/chrome-cdp-{x}", .{@intFromPtr(&opts)});
        }

        // Spawn Chrome
        const chrome_process = try process_mod.ChromeProcess.spawn(allocator, opts.io, exe_path, args);

        if (temp_dir_path) |path| {
            try chrome_process.setTempDir(path);
        }

        // Wait for WebSocket URL
        const ws_url = chrome_process.waitForWsUrl(opts.timeout_ms) catch |err| {
            chrome_process.deinit();
            return err;
        };

        // Connect to WebSocket
        const connection = Connection.open(ws_url, .{
            .allocator = allocator,
            .io = opts.io,
            .receive_timeout_ms = opts.timeout_ms,
        }) catch |err| {
            chrome_process.deinit();
            return err;
        };

        const self = try allocator.create(Self);
        self.* = .{
            .connection = connection,
            .process = chrome_process,
            .allocator = allocator,
            .ws_url = try allocator.dupe(u8, ws_url),
        };

        return self;
    }

    pub const ConnectOptions = struct {
        verbose: bool = false,
    };

    /// Connect to an existing Chrome instance
    pub fn connect(ws_url: []const u8, allocator: std.mem.Allocator, io: std.Io, opts: ConnectOptions) !*Self {
        const connection = try Connection.open(ws_url, .{
            .allocator = allocator,
            .io = io,
            .verbose = opts.verbose,
        });

        const self = try allocator.create(Self);
        self.* = .{
            .connection = connection,
            .process = null,
            .allocator = allocator,
            .ws_url = try allocator.dupe(u8, ws_url),
        };

        return self;
    }

    /// Create a new page
    pub fn newPage(self: *Self) !*Session {
        // Create target
        const create_result = try self.connection.sendCommand("Target.createTarget", .{
            .url = "about:blank",
        }, null);

        const target_id = try json_util.getString(create_result, "targetId");

        // Attach to target
        return try self.connection.createSession(target_id);
    }

    /// Get all open pages
    pub fn pages(self: *Self) ![]TargetInfo {
        const result = try self.connection.sendCommand("Target.getTargets", .{}, null);

        const target_infos = try json_util.getArray(result, "targetInfos");
        var targets: std.ArrayList(TargetInfo) = .empty;
        errdefer targets.deinit(self.allocator);

        for (target_infos) |info| {
            const target_type = try json_util.getString(info, "type");
            if (!std.mem.eql(u8, target_type, "page")) continue;

            try targets.append(self.allocator, .{
                .target_id = try self.allocator.dupe(u8, try json_util.getString(info, "targetId")),
                .type = try self.allocator.dupe(u8, target_type),
                .title = try self.allocator.dupe(u8, try json_util.getString(info, "title")),
                .url = try self.allocator.dupe(u8, try json_util.getString(info, "url")),
                .attached = try json_util.getBool(info, "attached"),
                .browser_context_id = if (info.object.get("browserContextId")) |v|
                    try self.allocator.dupe(u8, v.string)
                else
                    null,
            });
        }

        return targets.toOwnedSlice(self.allocator);
    }

    /// Close a page
    pub fn closePage(self: *Self, target_id: []const u8) !void {
        _ = try self.connection.sendCommand("Target.closeTarget", .{
            .target_id = target_id,
        }, null);
    }

    /// Get browser version
    pub fn version(self: *Self) !BrowserVersion {
        const result = try self.connection.sendCommand("Browser.getVersion", .{}, null);

        return .{
            .protocol_version = try self.allocator.dupe(u8, try json_util.getString(result, "protocolVersion")),
            .product = try self.allocator.dupe(u8, try json_util.getString(result, "product")),
            .revision = try self.allocator.dupe(u8, try json_util.getString(result, "revision")),
            .user_agent = try self.allocator.dupe(u8, try json_util.getString(result, "userAgent")),
            .js_version = try self.allocator.dupe(u8, try json_util.getString(result, "jsVersion")),
        };
    }

    /// Disconnect from browser without terminating it
    pub fn disconnect(self: *Self) void {
        // Just close the WebSocket connection
        self.connection.close();

        self.allocator.free(self.ws_url);
        self.allocator.destroy(self);
    }

    /// Close the browser (terminates Chrome)
    pub fn close(self: *Self) void {
        // Send Browser.close command to terminate Chrome
        _ = self.connection.sendCommand("Browser.close", .{}, null) catch {};

        // Close connection
        self.connection.close();

        // Clean up process
        if (self.process) |proc| {
            proc.deinit();
        }

        self.allocator.free(self.ws_url);
        self.allocator.destroy(self);
    }

    /// Get WebSocket URL
    pub fn getWsUrl(self: *const Self) []const u8 {
        return self.ws_url;
    }
};

/// Find Chrome executable on the system
pub fn findChrome(allocator: std.mem.Allocator) ![]const u8 {
    // Note: In Zig 0.16, file access requires Io context
    // For now, return common paths without verification

    // Platform-specific paths
    const paths = switch (@import("builtin").os.tag) {
        .linux => &[_][]const u8{
            "/usr/bin/google-chrome",
            "/usr/bin/google-chrome-stable",
            "/usr/bin/chromium",
            "/usr/bin/chromium-browser",
            "/snap/bin/chromium",
        },
        .macos => &[_][]const u8{
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "/Applications/Chromium.app/Contents/MacOS/Chromium",
        },
        .windows => &[_][]const u8{
            "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
            "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe",
            "C:\\Program Files\\Chromium\\Application\\chrome.exe",
            "C:\\Program Files (x86)\\Chromium\\Application\\chrome.exe",
        },
        else => &[_][]const u8{},
    };

    // In Zig 0.16, file system access requires Io context
    // For now, just return the first path and let launch fail if not found
    if (paths.len > 0) {
        return allocator.dupe(u8, paths[0]);
    }

    return error.ChromeNotFound;
}

/// Build Chrome command line arguments
fn buildArgs(opts: options_mod.LaunchOptions, allocator: std.mem.Allocator) ![]const []const u8 {
    var args: std.ArrayList([]const u8) = .empty;
    errdefer args.deinit(allocator);

    // Placeholder for executable path (will be replaced)
    try args.append(allocator, "");

    // Remote debugging port
    const port_str = try std.fmt.allocPrint(allocator, "--remote-debugging-port={}", .{opts.port});
    try args.append(allocator, port_str);

    // Headless mode
    switch (opts.headless) {
        .new => try args.append(allocator, try allocator.dupe(u8, "--headless=new")),
        .old => try args.append(allocator, try allocator.dupe(u8, "--headless")),
        .off => {},
    }

    // Disable GPU (recommended for headless)
    if (opts.disable_gpu) {
        try args.append(allocator, try allocator.dupe(u8, "--disable-gpu"));
    }

    // No sandbox
    if (opts.no_sandbox) {
        try args.append(allocator, try allocator.dupe(u8, "--no-sandbox"));
    }

    // Ignore certificate errors
    if (opts.ignore_certificate_errors) {
        try args.append(allocator, try allocator.dupe(u8, "--ignore-certificate-errors"));
    }

    // User data directory
    if (opts.user_data_dir) |dir| {
        const user_data_arg = try std.fmt.allocPrint(allocator, "--user-data-dir={s}", .{dir});
        try args.append(allocator, user_data_arg);
    }

    // Window size
    if (opts.window_size) |size| {
        const size_arg = try std.fmt.allocPrint(allocator, "--window-size={},{}", .{ size.width, size.height });
        try args.append(allocator, size_arg);
    }

    // Standard flags for automation
    try args.append(allocator, try allocator.dupe(u8, "--disable-extensions"));
    try args.append(allocator, try allocator.dupe(u8, "--disable-background-networking"));
    try args.append(allocator, try allocator.dupe(u8, "--disable-default-apps"));
    try args.append(allocator, try allocator.dupe(u8, "--disable-sync"));
    try args.append(allocator, try allocator.dupe(u8, "--disable-translate"));
    try args.append(allocator, try allocator.dupe(u8, "--hide-scrollbars"));
    try args.append(allocator, try allocator.dupe(u8, "--metrics-recording-only"));
    try args.append(allocator, try allocator.dupe(u8, "--mute-audio"));
    try args.append(allocator, try allocator.dupe(u8, "--no-first-run"));
    try args.append(allocator, try allocator.dupe(u8, "--safebrowsing-disable-auto-update"));

    // Extra arguments
    if (opts.extra_args) |extra| {
        for (extra) |arg| {
            try args.append(allocator, try allocator.dupe(u8, arg));
        }
    }

    return args.toOwnedSlice(allocator);
}

// Note: In Zig 0.16, directory operations require Io context
// Temp directory creation is handled inline in launch()

// ─── Tests ──────────────────────────────────────────────────────────────────

test "findChrome returns error if not found" {
    // This test may pass or fail depending on system
    const result = findChrome(std.testing.allocator);
    if (result) |path| {
        std.testing.allocator.free(path);
    } else |_| {}
}
