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
    // Wait options
    wait_text: ?[]const u8 = null,
    wait_url: ?[]const u8 = null,
    wait_load: ?[]const u8 = null,
    wait_fn: ?[]const u8 = null,

    const Command = enum {
        open,
        connect,
        navigate,
        screenshot,
        pdf,
        evaluate,
        network,
        cookies,
        storage,
        tab,
        window,
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
        wait,
        mouse,
        set,
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
        if (args.wait_text) |w| allocator.free(w);
        if (args.wait_url) |w| allocator.free(w);
        if (args.wait_load) |w| allocator.free(w);
        if (args.wait_fn) |w| allocator.free(w);
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
        .navigate, .screenshot, .pdf, .evaluate, .network, .cookies, .storage, .snapshot, .click, .dblclick, .focus, .type, .fill, .select, .hover, .check, .uncheck, .scroll, .scrollintoview, .drag, .get, .upload, .back, .forward, .reload, .press, .keydown, .keyup, .wait, .mouse, .set => true,
        .tab, .window, .version, .list_targets, .pages, .interactive, .open, .connect, .help => false,
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
            .tab => try cmdTab(browser, args, allocator),
            .window => try cmdWindow(browser, args, allocator),
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
        .wait_text = args.wait_text,
        .wait_url = args.wait_url,
        .wait_load = args.wait_load,
        .wait_fn = args.wait_fn,
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

/// Tab command - list, new, switch, close tabs
fn cmdTab(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    // Check for --help flag
    for (args.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            impl.printTabHelp();
            return;
        }
    }

    var target = cdp.Target.init(browser.connection);

    // tab new [url]
    if (args.positional.len >= 1 and std.mem.eql(u8, args.positional[0], "new")) {
        const url = if (args.positional.len >= 2) args.positional[1] else "about:blank";
        const target_id = try target.createTarget(url);
        std.debug.print("New tab: {s}\n", .{target_id});
        saveTargetToConfig(target_id, args, allocator, args.io);
        return;
    }

    // tab close [n]
    if (args.positional.len >= 1 and std.mem.eql(u8, args.positional[0], "close")) {
        const page_tabs = try browser.pages();
        defer {
            for (page_tabs) |*p| {
                var pi = p.*;
                pi.deinit(allocator);
            }
            allocator.free(page_tabs);
        }
        if (page_tabs.len == 0) {
            std.debug.print("No tabs open\n", .{});
            return;
        }
        // Default: close current (last_target from config, or last tab)
        var close_idx: usize = page_tabs.len - 1;
        if (args.positional.len >= 2) {
            close_idx = std.fmt.parseInt(usize, args.positional[1], 10) catch {
                std.debug.print("Invalid tab number: {s}\n", .{args.positional[1]});
                return;
            };
            if (close_idx == 0 or close_idx > page_tabs.len) {
                std.debug.print("Tab number out of range (1-{})\n", .{page_tabs.len});
                return;
            }
            close_idx -= 1; // Convert 1-based to 0-based
        }
        const success = try target.closeTarget(page_tabs[close_idx].target_id);
        if (success) {
            std.debug.print("Closed tab {}: {s}\n", .{ close_idx + 1, page_tabs[close_idx].title });
        } else {
            std.debug.print("Failed to close tab\n", .{});
        }
        return;
    }

    // tab <n> — switch to tab n
    if (args.positional.len >= 1) {
        const tab_num = std.fmt.parseInt(usize, args.positional[0], 10) catch {
            std.debug.print("Unknown subcommand: {s}\n", .{args.positional[0]});
            printTabUsage();
            return;
        };
        const page_tabs = try browser.pages();
        defer {
            for (page_tabs) |*p| {
                var pi = p.*;
                pi.deinit(allocator);
            }
            allocator.free(page_tabs);
        }
        if (tab_num == 0 or tab_num > page_tabs.len) {
            std.debug.print("Tab number out of range (1-{})\n", .{page_tabs.len});
            return;
        }
        const selected = page_tabs[tab_num - 1];
        try target.activateTarget(selected.target_id);
        saveTargetToConfig(selected.target_id, args, allocator, args.io);
        std.debug.print("Switched to tab {}: {s} ({s})\n", .{ tab_num, selected.title, selected.url });
        return;
    }

    // Default: list tabs with 1-based numbers
    const page_tabs = try browser.pages();
    defer {
        for (page_tabs) |*p| {
            var pi = p.*;
            pi.deinit(allocator);
        }
        allocator.free(page_tabs);
    }
    if (page_tabs.len == 0) {
        std.debug.print("No tabs open\n", .{});
        return;
    }
    for (page_tabs, 1..) |t, i| {
        std.debug.print("  {}: {s:<30} {s}\n", .{ i, t.title, t.url });
    }
    std.debug.print("\nTotal: {} tab(s)\n", .{page_tabs.len});
}

fn printTabUsage() void {
    std.debug.print(
        \\Usage: tab [subcommand]
        \\
        \\Subcommands:
        \\  tab                  List open tabs
        \\  tab new [url]        Open new tab (optionally navigate to URL)
        \\  tab <n>              Switch to tab n
        \\  tab close [n]        Close tab n (default: current)
        \\
    , .{});
}

/// Window command - new window
fn cmdWindow(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    _ = allocator;
    
    // Check for --help flag
    for (args.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            impl.printWindowHelp();
            return;
        }
    }
    
    if (args.positional.len >= 1 and std.mem.eql(u8, args.positional[0], "new")) {
        _ = try browser.connection.sendCommand("Target.createTarget", .{
            .url = "about:blank",
            .newWindow = true,
        }, null);
        std.debug.print("New window opened\n", .{});
        return;
    }

    std.debug.print(
        \\Usage: window <subcommand>
        \\
        \\Subcommands:
        \\  window new           Open new browser window
        \\
    , .{});
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

/// Set command - update config without browser connection
fn cmdSet(args: Args, allocator: std.mem.Allocator, io: std.Io) !void {
    // Check for --help flag
    for (args.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            impl.printSetHelp();
            return;
        }
    }

    if (args.positional.len < 1) {
        std.debug.print(
            \\Usage: zchrome set <subcommand> [args]
            \\
            \\Subcommands:
            \\  viewport <w> <h>      Set viewport size
            \\  device <name>         Emulate device ("iPhone 14", "Pixel 7", "Desktop")
            \\  geo <lat> <lng>       Set geolocation
            \\  offline <on|off>      Toggle offline mode
            \\  headers <json>        Set extra HTTP headers
            \\  credentials <u> <p>   Set HTTP basic auth credentials
            \\  media <dark|light>    Set prefers-color-scheme
            \\
        , .{});
        return;
    }
    const sub = args.positional[0];

    var config = config_mod.loadConfig(allocator, io) orelse config_mod.Config{};
    defer config.deinit(allocator);

    if (std.mem.eql(u8, sub, "viewport")) {
        if (args.positional.len < 3) {
            std.debug.print("Usage: set viewport <width> <height>\n", .{});
            return;
        }
        const w = try std.fmt.parseInt(u32, args.positional[1], 10);
        const h = try std.fmt.parseInt(u32, args.positional[2], 10);
        config.viewport_width = w;
        config.viewport_height = h;
        std.debug.print("Viewport set to {}x{}\n", .{ w, h });
    } else if (std.mem.eql(u8, sub, "device")) {
        if (args.positional.len < 2) {
            std.debug.print("Usage: set device <name>\n", .{});
            return;
        }
        if (config.device_name) |old| allocator.free(old);
        config.device_name = try allocator.dupe(u8, args.positional[1]);
        std.debug.print("Device set to {s}\n", .{config.device_name.?});
    } else if (std.mem.eql(u8, sub, "geo")) {
        if (args.positional.len < 3) {
            std.debug.print("Usage: set geo <lat> <lng>\n", .{});
            return;
        }
        const lat = try std.fmt.parseFloat(f64, args.positional[1]);
        const lng = try std.fmt.parseFloat(f64, args.positional[2]);
        config.geo_lat = lat;
        config.geo_lng = lng;
        std.debug.print("Geolocation set to {d}, {d}\n", .{ lat, lng });
    } else if (std.mem.eql(u8, sub, "offline")) {
        if (args.positional.len < 2) {
            std.debug.print("Usage: set offline <on|off>\n", .{});
            return;
        }
        config.offline = std.mem.eql(u8, args.positional[1], "on");
        std.debug.print("Offline mode: {}\n", .{config.offline.?});
    } else if (std.mem.eql(u8, sub, "headers")) {
        if (args.positional.len < 2) {
            std.debug.print("Usage: set headers <json>\n", .{});
            return;
        }
        const json_str = args.positional[1];
        const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_str, .{}) catch {
            std.debug.print("Error: Invalid JSON\n", .{});
            return;
        };
        parsed.deinit();

        if (config.headers) |old| allocator.free(old);
        config.headers = try allocator.dupe(u8, json_str);
        std.debug.print("Headers updated\n", .{});
    } else if (std.mem.eql(u8, sub, "credentials")) {
        if (args.positional.len < 3) {
            std.debug.print("Usage: set credentials <user> <pass>\n", .{});
            return;
        }
        if (config.auth_user) |old| allocator.free(old);
        config.auth_user = try allocator.dupe(u8, args.positional[1]);
        if (config.auth_pass) |old| allocator.free(old);
        config.auth_pass = try allocator.dupe(u8, args.positional[2]);
        std.debug.print("Credentials updated\n", .{});
    } else if (std.mem.eql(u8, sub, "media")) {
        if (args.positional.len < 2) {
            std.debug.print("Usage: set media <dark|light>\n", .{});
            return;
        }
        if (config.media_feature) |old| allocator.free(old);
        config.media_feature = try allocator.dupe(u8, args.positional[1]);
        std.debug.print("Media feature set to {s}\n", .{config.media_feature.?});
    } else {
        std.debug.print("Unknown subcommand: {s}\n", .{sub});
        return;
    }

    try config_mod.saveConfig(config, allocator, io);
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
    // Wait options
    var wait_text: ?[]const u8 = null;
    var wait_url: ?[]const u8 = null;
    var wait_load: ?[]const u8 = null;
    var wait_fn: ?[]const u8 = null;

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
                // If we haven't parsed a command yet, treat --help as the global help command
                if (command == .help) {
                    command = .help;
                    break;
                }
                // Otherwise pass --help to the subcommand
                try positional.append(allocator, try allocator.dupe(u8, arg));
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
            } else if (std.mem.eql(u8, arg, "--text")) {
                const val = iter.next() orelse return error.MissingArgument;
                wait_text = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, arg, "--match")) {
                const val = iter.next() orelse return error.MissingArgument;
                wait_url = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, arg, "--load")) {
                const val = iter.next() orelse return error.MissingArgument;
                wait_load = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, arg, "--fn")) {
                const val = iter.next() orelse return error.MissingArgument;
                wait_fn = try allocator.dupe(u8, val);
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
        .wait_text = wait_text,
        .wait_url = wait_url,
        .wait_load = wait_load,
        .wait_fn = wait_fn,
    };
}

/// Usage text embedded from separate file
const USAGE_TEXT = @embedFile("usage.txt");

/// Print usage information
fn printUsage() void {
    std.debug.print("{s}", .{USAGE_TEXT});
}
