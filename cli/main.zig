const std = @import("std");
const cdp = @import("cdp");
const config_mod = @import("config.zig");
const http_mod = @import("http.zig");
const interactive_mod = @import("interactive/mod.zig");
const impl = @import("command_impl.zig");

/// Save target ID to config file for subsequent commands
fn saveTargetToConfig(target_id: []const u8, args: Args, allocator: std.mem.Allocator, io: std.Io) void {
    // Load existing config or create new one
    var config = config_mod.loadConfig(allocator, io) orelse config_mod.Config{};

    // Update with current values
    if (config.last_target) |old| allocator.free(old);
    config.last_target = allocator.dupe(u8, target_id) catch null;

    // Keep other values from args if provided
    if (args.url != null and config.ws_url == null) {
        config.ws_url = allocator.dupe(u8, args.url.?) catch null;
    }

    config_mod.saveConfig(config, allocator, io) catch |err| {
        std.debug.print("Warning: Could not save target to config: {}\n", .{err});
    };

    // Clean up config (but not last_target since we just set it)
    if (config.chrome_path) |p| allocator.free(p);
    if (config.data_dir) |d| allocator.free(d);
    if (config.ws_url) |u| allocator.free(u);
    if (config.last_target) |t| allocator.free(t);
}

/// Write binary data to a file
fn writeFile(io: std.Io, path: []const u8, data: []const u8) !void {
    const dir = std.Io.Dir.cwd();
    dir.writeFile(io, .{ .sub_path = path, .data = data }) catch |err| {
        std.debug.print("Error writing {s}: {}\n", .{ path, err });
        return err;
    };
}

/// Extract target ID from page-level WebSocket URL
fn extractTargetIdFromUrl(url: []const u8) ?[]const u8 {
    // URL format: ws://host:port/devtools/page/target-id
    if (std.mem.lastIndexOf(u8, url, "/devtools/page/")) |idx| {
        const target_start = idx + "/devtools/page/".len;
        return url[target_start..];
    }
    return null;
}

/// CLI arguments
const Args = struct {
    url: ?[]const u8 = null,
    headless: cdp.Headless = .new,
    port: u16 = 9222,
    chrome_path: ?[]const u8 = null,
    data_dir: ?[]const u8 = null,
    timeout_ms: u32 = 30_000,
    verbose: bool = false,
    output: ?[]const u8 = null,
    use_target: ?[]const u8 = null,
    full_page: bool = false,
    io: std.Io = undefined,
    command: Command,
    positional: []const []const u8,
    // Snapshot options
    snap_interactive: bool = false,
    snap_compact: bool = false,
    snap_depth: ?usize = null,
    snap_selector: ?[]const u8 = null,

    const Command = enum {
        open,
        connect,
        navigate,
        screenshot,
        pdf,
        evaluate,
        network,
        cookies,
        version,
        list_targets,
        pages,
        interactive,
        snapshot,
        click,
        dblclick,
        focus,
        type,
        fill,
        select,
        hover,
        check,
        uncheck,
        scroll,
        scrollintoview,
        drag,
        get,
        upload,
        back,
        forward,
        reload,
        press,
        keydown,
        keyup,
        help,
    };
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var args = parseArgs(allocator, init.minimal.args) catch {
        printUsage();
        std.process.exit(1);
    };
    args.io = init.io;
    defer {
        for (args.positional) |p| allocator.free(p);
        allocator.free(args.positional);
        if (args.url) |u| allocator.free(u);
        if (args.chrome_path) |p| allocator.free(p);
        if (args.data_dir) |d| allocator.free(d);
        if (args.output) |o| allocator.free(o);
        if (args.use_target) |t| allocator.free(t);
        if (args.snap_selector) |s| allocator.free(s);
    }

    if (args.command == .help) {
        printUsage();
        return;
    }

    // Load config file for defaults
    var config = config_mod.loadConfig(allocator, init.io) orelse config_mod.Config{};
    defer config.deinit(allocator);

    // Apply config defaults if args not explicitly provided
    if (args.chrome_path == null and config.chrome_path != null) {
        args.chrome_path = allocator.dupe(u8, config.chrome_path.?) catch null;
    }
    if (args.data_dir == null and config.data_dir != null) {
        args.data_dir = allocator.dupe(u8, config.data_dir.?) catch null;
    }
    if (args.url == null and config.ws_url != null) {
        args.url = allocator.dupe(u8, config.ws_url.?) catch null;
    }
    // Only apply last_target for page-level commands (not version, pages, list_targets, etc.)
    const needs_target = switch (args.command) {
        .navigate, .screenshot, .pdf, .evaluate, .network, .cookies, .snapshot, .click, .dblclick, .focus, .type, .fill, .select, .hover, .check, .uncheck, .scroll, .scrollintoview, .drag, .get, .upload, .back, .forward, .reload, .press, .keydown, .keyup => true,
        .version, .list_targets, .pages, .interactive, .open, .connect, .help => false,
    };
    if (needs_target and args.use_target == null and config.last_target != null) {
        args.use_target = allocator.dupe(u8, config.last_target.?) catch null;
    }

    // Handle commands that don't need browser connection
    switch (args.command) {
        .open => {
            try cmdOpen(args, allocator, init.io);
            return;
        },
        .connect => {
            try cmdConnect(args, allocator, init.io);
            return;
        },
        else => {},
    }

    // Launch or connect to browser
    const is_connected = args.url != null;
    var browser = if (args.url) |ws_url|
        cdp.Browser.connect(ws_url, allocator, init.io, .{ .verbose = args.verbose }) catch |err| {
            std.debug.print("Failed to connect: {}\n", .{err});
            std.process.exit(1);
        }
    else
        cdp.Browser.launch(.{
            .headless = args.headless,
            .executable_path = args.chrome_path,
            .allocator = allocator,
            .io = init.io,
            .timeout_ms = args.timeout_ms,
        }) catch |err| {
            std.debug.print("Failed to launch browser: {}\n", .{err});
            std.process.exit(1);
        };
    defer if (is_connected) browser.disconnect() else browser.close();

    // Check if URL is page-level (already attached to a page)
    // Page-level URLs: /devtools/page/<target-id>
    // Browser-level URLs: /devtools/browser/<browser-id>
    const is_page_url = if (args.url) |url|
        std.mem.indexOf(u8, url, "/devtools/page/") != null
    else
        false;

    // Execute command
    // If page-level URL, commands go directly (no session needed)
    if (is_page_url) {
        try executeDirectly(browser, args, allocator);
    } else if (args.use_target) |tid| {
        // Browser-level URL + --use: attach to target via session
        try executeOnTarget(browser, tid, args, allocator);
    } else {
        switch (args.command) {
            // Commands that manage their own session/page lifecycle
            .navigate => try cmdNavigate(browser, args, allocator),
            .screenshot => try cmdScreenshot(browser, args, allocator),
            .pdf => try cmdPdf(browser, args, allocator),
            .evaluate => try cmdEvaluate(browser, args, allocator),
            .cookies => try cmdCookies(browser, args, allocator),
            .version => try cmdVersion(browser, allocator),
            .list_targets => try cmdListTargets(browser, allocator),
            .pages => try cmdPages(browser, allocator),
            .interactive => try cmdInteractive(browser, args, allocator),
            .snapshot => try cmdSnapshot(browser, args, allocator),
            .open, .connect, .help => unreachable,
            // All other commands use first real page
            else => try withFirstPage(browser, args, allocator),
        }
    }
}

/// Build a CommandCtx from CLI Args
fn buildCtx(args: Args, allocator: std.mem.Allocator) impl.CommandCtx {
    return .{
        .allocator = allocator,
        .io = args.io,
        .positional = args.positional,
        .output = args.output,
        .full_page = args.full_page,
        .snap_interactive = args.snap_interactive,
        .snap_compact = args.snap_compact,
        .snap_depth = args.snap_depth,
        .snap_selector = args.snap_selector,
    };
}

/// Execute a session-level command. Creates the session and dispatches.
fn executeWithSession(browser: *cdp.Browser, session_id: []const u8, args: Args, allocator: std.mem.Allocator) !void {
    var session = try cdp.Session.init(session_id, browser.connection, allocator);
    defer session.deinit();

    const ctx = buildCtx(args, allocator);
    if (!try impl.dispatchSessionCommand(session, args.command, ctx)) {
        // Non-session commands
        switch (args.command) {
            .version => try cmdVersion(browser, allocator),
            .list_targets => try cmdListTargets(browser, allocator),
            .pages => try cmdPages(browser, allocator),
            else => std.debug.print("Error: Command not supported in this mode\n", .{}),
        }
    }
}

/// Execute a command directly on a page-level connection (no session needed)
fn executeDirectly(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    try executeWithSession(browser, "", args, allocator);
}

/// Execute a command on an existing target
fn executeOnTarget(browser: *cdp.Browser, target_id: []const u8, args: Args, allocator: std.mem.Allocator) !void {
    if (args.verbose) {
        std.debug.print("Attaching to target: {s}\n", .{target_id});
    }

    var target = cdp.Target.init(browser.connection);
    const session_id = try target.attachToTarget(allocator, target_id, true);
    defer allocator.free(session_id);

    if (args.verbose) {
        std.debug.print("Session ID: {s}\n", .{session_id});
    }

    try executeWithSession(browser, session_id, args, allocator);
}

/// Find first real page, attach a session, and dispatch a command through command_impl
fn withFirstPage(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    const pages = try browser.pages();
    defer {
        for (pages) |*p| {
            var page_info = p.*;
            page_info.deinit(allocator);
        }
        allocator.free(pages);
    }

    const page = findFirstRealPage(pages) orelse {
        std.debug.print("Error: No pages open\n", .{});
        return error.NoPages;
    };

    var target = cdp.Target.init(browser.connection);
    const session_id = try target.attachToTarget(allocator, page.target_id, true);
    defer allocator.free(session_id);
    var session = try cdp.Session.init(session_id, browser.connection, allocator);
    defer session.deinit();

    const ctx = buildCtx(args, allocator);
    if (!try impl.dispatchSessionCommand(session, args.command, ctx)) {
        std.debug.print("Error: Command not supported in this mode\n", .{});
    }
}

/// Navigate command - uses existing page or creates new one, saves target ID
fn cmdNavigate(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len < 1) {
        std.debug.print("Error: navigate requires a URL\n", .{});
        return;
    }

    const target_url = args.positional[0];

    // Get existing pages first
    const pages = try browser.pages();
    defer {
        for (pages) |*p| {
            var page_info = p.*;
            page_info.deinit(allocator);
        }
        allocator.free(pages);
    }

    // Use first existing page or create new one
    var target_id: []const u8 = undefined;
    var session: *cdp.Session = undefined;
    var created_new = false;

    if (pages.len > 0) {
        // Use first existing page
        target_id = pages[0].target_id;
        if (args.verbose) {
            std.debug.print("Using existing page: {s}\n", .{target_id});
        }
        var target = cdp.Target.init(browser.connection);
        const session_id = try target.attachToTarget(allocator, target_id, true);
        defer allocator.free(session_id);
        session = try cdp.Session.init(session_id, browser.connection, allocator);
    } else {
        // Create new page
        if (args.verbose) {
            std.debug.print("Creating new page\n", .{});
        }
        session = try browser.newPage();
        created_new = true;
        // Get the target ID from the new page
        const new_pages = try browser.pages();
        defer {
            for (new_pages) |*p| {
                var page_info = p.*;
                page_info.deinit(allocator);
            }
            allocator.free(new_pages);
        }
        if (new_pages.len > 0) {
            target_id = try allocator.dupe(u8, new_pages[0].target_id);
        }
    }
    defer session.deinit();

    var page = cdp.Page.init(session);
    try page.enable();

    var result = try page.navigate(allocator, target_url);
    defer result.deinit(allocator);

    if (result.error_text) |err| {
        std.debug.print("Navigation error: {s}\n", .{err});
        return;
    }

    // Wait for page to load
    var i: u32 = 0;
    while (i < 500000) : (i += 1) {
        std.atomic.spinLoopHint();
    }

    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    const title = runtime.evaluateAs([]const u8, "document.title") catch "Unknown";

    std.debug.print("URL: {s}\n", .{target_url});
    std.debug.print("Title: {s}\n", .{title});
    std.debug.print("Target: {s}\n", .{target_id});

    // Save target ID to config
    saveTargetToConfig(target_id, args, allocator, args.io);

    if (created_new) {
        allocator.free(target_id);
    }
}

/// Screenshot command
fn cmdScreenshot(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    var session = try browser.newPage();
    defer session.detach() catch {};

    var page = cdp.Page.init(session);
    try page.enable();

    if (args.positional.len > 0) {
        _ = try page.navigate(allocator, args.positional[0]);
        // Note: sleep API changed in Zig 0.16
        var j: u32 = 0;
        while (j < 1000000) : (j += 1) {
            std.atomic.spinLoopHint();
        }
    }

    const screenshot_data = try page.captureScreenshot(allocator, .{
        .format = .png,
        .capture_beyond_viewport = if (args.full_page) true else null,
    });
    defer allocator.free(screenshot_data);

    const decoded = try cdp.base64.decodeAlloc(allocator, screenshot_data);
    defer allocator.free(decoded);

    const output_path = args.output orelse "screenshot.png";
    try writeFile(args.io, output_path, decoded);
    std.debug.print("Screenshot saved to {s} ({} bytes){s}\n", .{
        output_path,
        decoded.len,
        if (args.full_page) " (full page)" else "",
    });
}

/// PDF command
fn cmdPdf(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    var session = try browser.newPage();
    defer session.detach() catch {};

    var page = cdp.Page.init(session);
    try page.enable();

    if (args.positional.len > 0) {
        _ = try page.navigate(allocator, args.positional[0]);
        // Note: sleep API changed in Zig 0.16
        var j: u32 = 0;
        while (j < 1000000) : (j += 1) {
            std.atomic.spinLoopHint();
        }
    }

    const pdf_data = try page.printToPDF(allocator, .{});
    defer allocator.free(pdf_data);

    const decoded = try cdp.base64.decodeAlloc(allocator, pdf_data);
    defer allocator.free(decoded);

    const output_path = args.output orelse "page.pdf";
    try writeFile(args.io, output_path, decoded);
    std.debug.print("PDF saved to {s} ({} bytes)\n", .{ output_path, decoded.len });
}

/// Evaluate command
fn cmdEvaluate(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len < 1) {
        std.debug.print("Error: evaluate requires an expression\n", .{});
        return;
    }

    // If 2+ positional args: first is URL, second is expression
    // If 1 positional arg: it's the expression (no navigation)
    const has_url = args.positional.len >= 2;
    const target_url = if (has_url) args.positional[0] else null;
    const expression = if (has_url) args.positional[1] else args.positional[0];

    var session = try browser.newPage();
    defer session.detach() catch {};

    var page = cdp.Page.init(session);
    try page.enable();

    if (target_url) |url| {
        _ = try page.navigate(allocator, url);
        // Note: sleep API changed in Zig 0.16, using spinloop hint
        var i: u32 = 0;
        while (i < 500000) : (i += 1) {
            std.atomic.spinLoopHint();
        }
    }

    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    var result = try runtime.evaluate(allocator, expression, .{ .return_by_value = true });
    defer result.deinit(allocator);

    std.debug.print("Result: ", .{});
    if (result.value) |v| {
        switch (v) {
            .string => |s| std.debug.print("{s}\n", .{s}),
            .integer => |int_val| std.debug.print("{}\n", .{int_val}),
            .float => |f| std.debug.print("{d}\n", .{f}),
            .bool => |b| std.debug.print("{}\n", .{b}),
            .null => std.debug.print("null\n", .{}),
            else => std.debug.print("[complex value]\n", .{}),
        }
    } else {
        std.debug.print("{s}\n", .{result.description orelse "undefined"});
    }
}

/// Cookies command
fn cmdCookies(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    var session = try browser.newPage();
    defer session.detach() catch {};

    var page = cdp.Page.init(session);
    try page.enable();

    var storage = cdp.Storage.init(session);

    if (args.positional.len > 0) {
        _ = try page.navigate(allocator, args.positional[0]);
        // Note: sleep API changed in Zig 0.16, using spinloop hint
        var i: u32 = 0;
        while (i < 500000) : (i += 1) {
            std.atomic.spinLoopHint();
        }
    }

    const cookies = try storage.getCookies(allocator, null);
    defer {
        for (cookies) |*c| {
            var cookie = c.*;
            cookie.deinit(allocator);
        }
        allocator.free(cookies);
    }

    std.debug.print("{s:<30} {s:<40} {s:<20}\n", .{ "Name", "Value", "Domain" });
    std.debug.print("{s:-<90}\n", .{""});
    for (cookies) |cookie| {
        std.debug.print("{s:<30} {s:<40} {s:<20}\n", .{ cookie.name, cookie.value, cookie.domain });
    }
}

/// Version command
fn cmdVersion(browser: *cdp.Browser, allocator: std.mem.Allocator) !void {
    var version = try browser.version();
    defer version.deinit(allocator);

    std.debug.print("Protocol Version: {s}\n", .{version.protocol_version});
    std.debug.print("Product: {s}\n", .{version.product});
    std.debug.print("Revision: {s}\n", .{version.revision});
    std.debug.print("User Agent: {s}\n", .{version.user_agent});
    std.debug.print("JS Version: {s}\n", .{version.js_version});
}

/// List targets command
fn cmdListTargets(browser: *cdp.Browser, allocator: std.mem.Allocator) !void {
    var target = cdp.Target.init(browser.connection);
    const targets = try target.getTargets(allocator);
    defer {
        for (targets) |*t| {
            var ti = t.*;
            ti.deinit(allocator);
        }
        allocator.free(targets);
    }

    std.debug.print("{s:<40} {s:<15} {s:<30}\n", .{ "ID", "Type", "Title" });
    std.debug.print("{s:-<85}\n", .{""});
    for (targets) |t| {
        std.debug.print("{s:<40} {s:<15} {s:<30}\n", .{ t.target_id, t.type, t.title });
    }
}

/// List pages command
fn cmdPages(browser: *cdp.Browser, allocator: std.mem.Allocator) !void {
    var target = cdp.Target.init(browser.connection);
    const targets = try target.getTargets(allocator);
    defer {
        for (targets) |*t| {
            var ti = t.*;
            ti.deinit(allocator);
        }
        allocator.free(targets);
    }

    std.debug.print("{s:<42} {s:<30} {s:<50}\n", .{ "TARGET ID", "TITLE", "URL" });
    std.debug.print("{s:-<122}\n", .{""});

    var count: usize = 0;
    for (targets) |t| {
        if (std.mem.eql(u8, t.type, "page")) {
            std.debug.print("{s:<42} {s:<30} {s:<50}\n", .{ t.target_id, t.title, t.url });
            count += 1;
        }
    }

    if (count == 0) {
        std.debug.print("No pages found.\n", .{});
    } else {
        std.debug.print("\nTotal: {} page(s)\n", .{count});
    }
}

/// Interactive REPL
fn cmdInteractive(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    // Find the first "real" page to attach to
    const pages = try browser.pages();
    defer {
        for (pages) |*p| {
            var page_info = p.*;
            page_info.deinit(allocator);
        }
        allocator.free(pages);
    }

    var state = interactive_mod.InteractiveState{
        .allocator = allocator,
        .io = args.io,
        .browser = browser,
        .session = null,
        .target_id = null,
        .verbose = args.verbose,
    };
    defer state.deinit();

    // Auto-attach to the first real page if available
    const page = findFirstRealPage(pages);
    if (page) |p| {
        var target = cdp.Target.init(browser.connection);
        const session_id = target.attachToTarget(allocator, p.target_id, true) catch |err| {
            std.debug.print("Warning: Could not attach to page: {}\n", .{err});
            try interactive_mod.run(&state);
            return;
        };
        state.session = cdp.Session.init(session_id, browser.connection, allocator) catch |err| {
            std.debug.print("Warning: Could not create session: {}\n", .{err});
            allocator.free(session_id);
            try interactive_mod.run(&state);
            return;
        };
        state.target_id = allocator.dupe(u8, p.target_id) catch null;
    }

    try interactive_mod.run(&state);
}

/// Snapshot command - capture accessibility tree and save to zsnap.json
fn cmdSnapshot(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    // Get existing pages first
    const pages = try browser.pages();
    defer {
        for (pages) |*p| {
            var page_info = p.*;
            page_info.deinit(allocator);
        }
        allocator.free(pages);
    }

    // Use first existing page or create new one
    var session: *cdp.Session = undefined;
    var target_id: []const u8 = undefined;

    if (pages.len > 0) {
        // Use first existing page
        target_id = pages[0].target_id;
        if (args.verbose) {
            std.debug.print("Using existing page: {s}\n", .{target_id});
        }
        var target = cdp.Target.init(browser.connection);
        const session_id = try target.attachToTarget(allocator, target_id, true);
        session = try cdp.Session.init(session_id, browser.connection, allocator);
    } else {
        // Create new page only if no pages exist
        if (args.verbose) {
            std.debug.print("Creating new page\n", .{});
        }
        session = try browser.newPage();
    }
    defer session.deinit();

    const ctx = buildCtx(args, allocator);
    try impl.snapshot(session, ctx);
}

/// Find the first "real" page (skipping devtools://, chrome://, etc.)
fn findFirstRealPage(pages: []const cdp.TargetInfo) ?*const cdp.TargetInfo {
    for (pages) |*p| {
        // Skip internal browser pages
        if (std.mem.startsWith(u8, p.url, "devtools://")) continue;
        if (std.mem.startsWith(u8, p.url, "chrome://")) continue;
        if (std.mem.startsWith(u8, p.url, "chrome-extension://")) continue;
        if (std.mem.startsWith(u8, p.url, "about:")) continue;
        return p;
    }
    // Fallback to first page if no "real" page found
    if (pages.len > 0) return &pages[0];
    return null;
}

/// Open command - launch Chrome with remote debugging
fn cmdOpen(args: Args, allocator: std.mem.Allocator, io: std.Io) !void {
    const port = args.port;

    // Check if Chrome is already running on this port
    if (http_mod.isChromeRunning(io, port)) {
        std.debug.print("Chrome already running on port {}\n", .{port});

        // Try to get the WebSocket URL
        const ws_url = http_mod.getChromeWsUrl(allocator, io, port) catch |err| {
            std.debug.print("Warning: Could not get WebSocket URL: {}\n", .{err});
            return;
        };
        defer allocator.free(ws_url);

        std.debug.print("WebSocket URL: {s}\n", .{ws_url});

        // Save to config
        const save_config = config_mod.Config{
            .chrome_path = args.chrome_path,
            .data_dir = args.data_dir,
            .port = port,
            .ws_url = ws_url,
            .last_target = null,
        };
        config_mod.saveConfig(save_config, allocator, io) catch |err| {
            std.debug.print("Warning: Could not save config: {}\n", .{err});
        };
        return;
    }

    // Get Chrome executable path
    const chrome_path = args.chrome_path orelse blk: {
        // Try to find Chrome
        break :blk cdp.findChrome(allocator) catch {
            std.debug.print("Error: Chrome not found. Use --chrome to specify path.\n", .{});
            std.process.exit(1);
        };
    };

    // Get data directory
    const data_dir = args.data_dir orelse "zchrome-profile";

    // Build command arguments
    var argv_list: std.ArrayList([]const u8) = .empty;
    defer argv_list.deinit(allocator);

    try argv_list.append(allocator, chrome_path);

    const port_arg = try std.fmt.allocPrint(allocator, "--remote-debugging-port={}", .{port});
    defer allocator.free(port_arg);
    try argv_list.append(allocator, port_arg);

    const data_arg = try std.fmt.allocPrint(allocator, "--user-data-dir={s}", .{data_dir});
    defer allocator.free(data_arg);
    try argv_list.append(allocator, data_arg);

    // Add headless flag if needed
    if (args.headless != .off) {
        const headless_arg: []const u8 = if (args.headless == .new) "--headless=new" else "--headless";
        try argv_list.append(allocator, headless_arg);
    }

    // Spawn Chrome
    std.debug.print("Launching Chrome...\n", .{});
    std.debug.print("  Executable: {s}\n", .{chrome_path});
    std.debug.print("  Port: {}\n", .{port});
    std.debug.print("  Data dir: {s}\n", .{data_dir});
    if (args.headless != .off) {
        std.debug.print("  Headless: {s}\n", .{@tagName(args.headless)});
    }

    _ = std.process.spawn(io, .{
        .argv = argv_list.items,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch |err| {
        std.debug.print("Error launching Chrome: {}\n", .{err});
        std.process.exit(1);
    };

    std.debug.print("\nChrome launched. Run 'zchrome connect' to get WebSocket URL.\n", .{});

    // Save config (without ws_url since we don't have it yet)
    // Use the actual values being used, not the original args
    const new_config = config_mod.Config{
        .chrome_path = chrome_path,
        .data_dir = data_dir,
        .port = port,
        .ws_url = null,
        .last_target = null,
    };
    config_mod.saveConfig(new_config, allocator, io) catch |err| {
        std.debug.print("Warning: Could not save config: {}\n", .{err});
    };
}

/// Connect command - connect to existing Chrome and get WebSocket URL
fn cmdConnect(args: Args, allocator: std.mem.Allocator, io: std.Io) !void {
    const port = args.port;

    if (args.verbose) {
        std.debug.print("Checking if Chrome is running on port {}...\n", .{port});
    }

    // Check if Chrome is running
    if (!http_mod.isChromeRunning(io, port)) {
        std.debug.print("Error: Chrome not running on port {}.\n", .{port});
        std.debug.print("Run 'zchrome open' to launch Chrome first.\n", .{});
        std.process.exit(1);
    }

    if (args.verbose) {
        std.debug.print("Chrome is running. Fetching WebSocket URL...\n", .{});
    }

    // Get WebSocket URL
    const ws_url = http_mod.getChromeWsUrl(allocator, io, port) catch |err| {
        std.debug.print("Error: Could not get WebSocket URL: {}\n", .{err});
        std.process.exit(1);
    };

    std.debug.print("Connected to Chrome on port {}\n", .{port});
    std.debug.print("WebSocket URL: {s}\n", .{ws_url});

    // Save to config
    if (args.verbose) {
        std.debug.print("Saving config to zchrome.json...\n", .{});
    }

    const save_config = config_mod.Config{
        .chrome_path = args.chrome_path,
        .data_dir = args.data_dir,
        .port = port,
        .ws_url = ws_url,
        .last_target = args.use_target,
    };
    config_mod.saveConfig(save_config, allocator, io) catch |err| {
        std.debug.print("Warning: Could not save config: {}\n", .{err});
    };

    if (args.verbose) {
        std.debug.print("Config saved successfully.\n", .{});
    }

    allocator.free(ws_url);
}

/// Parse command line arguments
fn parseArgs(allocator: std.mem.Allocator, args: std.process.Args) !Args {
    var iter = try std.process.Args.Iterator.initAllocator(args, allocator);
    defer iter.deinit();

    var positional: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (positional.items) |p| allocator.free(p);
        positional.deinit(allocator);
    }

    var command: Args.Command = .help;
    var url: ?[]const u8 = null;
    var headless: cdp.Headless = .off;
    var port: u16 = 9222;
    var chrome_path: ?[]const u8 = null;
    var data_dir: ?[]const u8 = null;
    var timeout_ms: u32 = 30_000;
    var verbose: bool = false;
    var output: ?[]const u8 = null;
    var use_target: ?[]const u8 = null;
    var full_page: bool = false;
    // Snapshot options
    var snap_interactive: bool = false;
    var snap_compact: bool = false;
    var snap_depth: ?usize = null;
    var snap_selector: ?[]const u8 = null;

    _ = iter.skip(); // Skip program name

    while (iter.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "-") and arg.len > 1 and arg[1] != '-') {
            // Single-dash short options (-i, -c, -d, -s)
            if (std.mem.eql(u8, arg, "-i")) {
                snap_interactive = true;
            } else if (std.mem.eql(u8, arg, "-c")) {
                snap_compact = true;
            } else if (std.mem.eql(u8, arg, "-d")) {
                const val = iter.next() orelse return error.MissingArgument;
                snap_depth = try std.fmt.parseInt(usize, val, 10);
            } else if (std.mem.eql(u8, arg, "-s")) {
                const val = iter.next() orelse return error.MissingArgument;
                snap_selector = try allocator.dupe(u8, val);
            }
        } else if (std.mem.startsWith(u8, arg, "--")) {
            if (std.mem.eql(u8, arg, "--url")) {
                const val = iter.next() orelse return error.MissingArgument;
                url = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, arg, "--use")) {
                const val = iter.next() orelse return error.MissingArgument;
                use_target = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, arg, "--headless")) {
                const val = iter.next() orelse "new";
                headless = if (std.mem.eql(u8, val, "off"))
                    .off
                else if (std.mem.eql(u8, val, "old"))
                    .old
                else
                    .new;
            } else if (std.mem.eql(u8, arg, "--port")) {
                const val = iter.next() orelse return error.MissingArgument;
                port = try std.fmt.parseInt(u16, val, 10);
            } else if (std.mem.eql(u8, arg, "--chrome")) {
                const val = iter.next() orelse return error.MissingArgument;
                chrome_path = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, arg, "--data-dir")) {
                const val = iter.next() orelse return error.MissingArgument;
                data_dir = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, arg, "--timeout")) {
                const val = iter.next() orelse return error.MissingArgument;
                timeout_ms = try std.fmt.parseInt(u32, val, 10);
            } else if (std.mem.eql(u8, arg, "--verbose")) {
                verbose = true;
            } else if (std.mem.eql(u8, arg, "--full")) {
                full_page = true;
            } else if (std.mem.eql(u8, arg, "--output")) {
                const val = iter.next() orelse return error.MissingArgument;
                output = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, arg, "--help")) {
                command = .help;
                break;
            } else if (std.mem.eql(u8, arg, "--interactive-only")) {
                snap_interactive = true;
            } else if (std.mem.eql(u8, arg, "--compact")) {
                snap_compact = true;
            } else if (std.mem.eql(u8, arg, "--depth")) {
                const val = iter.next() orelse return error.MissingArgument;
                snap_depth = try std.fmt.parseInt(usize, val, 10);
            } else if (std.mem.eql(u8, arg, "--selector")) {
                const val = iter.next() orelse return error.MissingArgument;
                snap_selector = try allocator.dupe(u8, val);
            }
        } else {
            if (command == .help) {
                // Handle hyphenated command names and aliases
                if (std.mem.eql(u8, arg, "list-targets")) {
                    command = .list_targets;
                } else if (std.mem.eql(u8, arg, "scrollinto")) {
                    command = .scrollintoview;
                } else if (std.mem.eql(u8, arg, "key")) {
                    command = .press;
                } else {
                    command = std.meta.stringToEnum(Args.Command, arg) orelse .help;
                }
            } else {
                try positional.append(allocator, try allocator.dupe(u8, arg));
            }
        }
    }

    return .{
        .url = url,
        .headless = headless,
        .port = port,
        .chrome_path = chrome_path,
        .data_dir = data_dir,
        .timeout_ms = timeout_ms,
        .verbose = verbose,
        .output = output,
        .use_target = use_target,
        .full_page = full_page,
        .command = command,
        .positional = try positional.toOwnedSlice(allocator),
        .snap_interactive = snap_interactive,
        .snap_compact = snap_compact,
        .snap_depth = snap_depth,
        .snap_selector = snap_selector,
    };
}

/// Print usage information
fn printUsage() void {
    std.debug.print(
        \\zchrome [options] <command> [command-args]
        \\
        \\GLOBAL OPTIONS:
        \\  --url <ws-url>           Connect to existing Chrome (ws://...)
        \\  --use <target-id>        Execute command on existing page
        \\  --headless [new|old]     Enable headless mode (default: off)
        \\  --port <port>            Debug port [default: 9222]
        \\  --chrome <path>          Chrome binary path
        \\  --data-dir <path>        User data directory for Chrome profile
        \\  --timeout <ms>           Command timeout [default: 30000]
        \\  --verbose                Print CDP messages
        \\  --output <path>          Output file path (for screenshot/pdf)
        \\  --full                   Capture full page screenshot (not just viewport)
        \\
        \\COMMANDS:
        \\  open                     Launch Chrome with remote debugging
        \\  connect                  Connect to running Chrome, get WebSocket URL
        \\  navigate <url>           Navigate to URL, print final URL + title
        \\  screenshot [url]         Capture PNG screenshot
        \\  pdf [url]                Generate PDF
        \\  evaluate [url] <expr>    Evaluate JS expression
        \\  network [url]            Log network requests
        \\  cookies [url]            Dump cookies
        \\  snapshot                 Capture accessibility tree of active page, save to zsnap.json
        \\  version                  Print browser version info
        \\  list-targets             List all open targets
        \\  pages                    List all open pages with target IDs
        \\  interactive              REPL: enter CDP commands as JSON
        \\  help                     Show this help message
        \\
        \\NAVIGATION:
        \\  back                     Go back in history
        \\  forward                  Go forward in history
        \\  reload                   Reload current page
        \\
        \\ELEMENT ACTIONS:
        \\  click <sel>              Click element (CSS selector or @ref)
        \\  dblclick <sel>           Double-click element
        \\  hover <sel>              Hover over element
        \\  focus <sel>              Focus element
        \\  type <sel> <text>        Type text into element (appends)
        \\  fill <sel> <text>        Clear and fill element with text
        \\  select <sel> <value>     Select dropdown option by value
        \\  check <sel>              Check checkbox
        \\  uncheck <sel>            Uncheck checkbox
        \\  scroll <dir> [px]        Scroll page (up/down/left/right) [default: 300px]
        \\  scrollintoview <sel>     Scroll element into view (alias: scrollinto)
        \\  drag <src> <tgt>         Drag and drop from source to target element
        \\  upload <sel> <files>     Upload files to file input
        \\
        \\KEYBOARD:
        \\  press <key>              Press key (Enter, Tab, Control+a) (alias: key)
        \\  keydown <key>            Hold key down
        \\  keyup <key>              Release key
        \\
        \\GETTERS:
        \\  get text <sel>           Get text content
        \\  get html <sel>           Get innerHTML
        \\  get dom <sel>            Get outerHTML
        \\  get value <sel>          Get input value
        \\  get attr <sel> <attr>    Get attribute value
        \\  get title                Get page title
        \\  get url                  Get current URL
        \\  get count <sel>          Count matching elements
        \\  get box <sel>            Get bounding box (x, y, width, height)
        \\  get styles <sel>         Get computed styles (JSON)
        \\
        \\SNAPSHOT OPTIONS:
        \\  -i, --interactive-only   Only include interactive elements
        \\  -c, --compact            Compact output (skip empty structural elements)
        \\  -d, --depth <n>          Limit tree depth
        \\  -s, --selector <sel>     Scope snapshot to CSS selector
        \\
        \\CONFIG FILE:
        \\  zchrome.json is stored alongside the executable for portability.
        \\  It stores chrome_path, data_dir, port, ws_url, and last_target.
        \\  Options from command line override config file values.
        \\
        \\EXAMPLES:
        \\  # Launch Chrome and connect
        \\  zchrome open --chrome "C:\Program Files\Google\Chrome\Application\chrome.exe"
        \\  zchrome connect
        \\
        \\  # Subsequent commands use saved WebSocket URL
        \\  zchrome pages
        \\  zchrome --use <target-id> screenshot --output page.png
        \\  zchrome evaluate "document.title"
        \\
        \\  # Launch headless and take screenshot
        \\  zchrome open --headless
        \\  zchrome connect
        \\  zchrome screenshot https://example.com --output page.png
        \\
        \\  # Take snapshot of active page's accessibility tree
        \\  zchrome snapshot                       # Snapshot current page
        \\  zchrome snapshot -i                    # Interactive elements only
        \\  zchrome snapshot -c -d 3               # Compact mode, depth 3
        \\  zchrome snapshot -s "#main-content"    # Scope to selector
        \\
        \\  # Interact with elements (use CSS selectors or @refs from snapshot)
        \\  zchrome click "#login-btn"             # Click by CSS selector
        \\  zchrome click @e3                      # Click by snapshot ref
        \\  zchrome fill "#email" "test@example.com"
        \\  zchrome type @e5 "password"
        \\  zchrome select "#country" "US"
        \\  zchrome scroll down 500
        \\  zchrome scrollinto "#footer"
        \\  zchrome drag @e3 @e7                    # Drag element to another
        \\  zchrome upload "#file-input" /path/to/file.pdf  # Upload file
        \\  zchrome upload @e5 doc1.txt doc2.txt   # Upload multiple files
        \\
        \\  # Get element information
        \\  zchrome get text @e3                   # Get text content by ref
        \\  zchrome get value "#email"             # Get input value
        \\  zchrome get attr @e5 href              # Get href attribute
        \\  zchrome get title                      # Get page title
        \\  zchrome get url                        # Get current URL
        \\  zchrome get count "li.item"            # Count elements
        \\
        \\  # Keyboard input
        \\  zchrome press Enter                   # Press Enter key
        \\  zchrome press Control+a               # Select all
        \\  zchrome key Tab                       # Press Tab (alias for press)
        \\  zchrome keydown Shift                 # Hold Shift down
        \\  zchrome keyup Shift                   # Release Shift
        \\
    , .{});
}
