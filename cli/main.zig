const std = @import("std");
const cdp = @import("cdp");
const config_mod = @import("config.zig");
const http_mod = @import("http.zig");
const snapshot_mod = @import("snapshot.zig");
const actions_mod = @import("actions/mod.zig");

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
        dom,
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
        @"type",
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
        .navigate, .screenshot, .pdf, .evaluate, .dom, .network, .cookies, .snapshot,
        .click, .dblclick, .focus, .@"type", .fill, .select, .hover, .check, .uncheck,
        .scroll, .scrollintoview, .drag, .get, .upload => true,
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
            .navigate => try cmdNavigate(browser, args, allocator),
            .screenshot => try cmdScreenshot(browser, args, allocator),
            .pdf => try cmdPdf(browser, args, allocator),
            .evaluate => try cmdEvaluate(browser, args, allocator),
            .dom => try cmdDom(browser, args, allocator),
            .network => try cmdNetwork(browser, args, allocator),
            .cookies => try cmdCookies(browser, args, allocator),
            .version => try cmdVersion(browser, allocator),
            .list_targets => try cmdListTargets(browser, allocator),
            .pages => try cmdPages(browser, allocator),
            .interactive => try cmdInteractive(allocator),
            .snapshot => try cmdSnapshot(browser, args, allocator),
            .click => try cmdClick(browser, args, allocator),
            .dblclick => try cmdDblClick(browser, args, allocator),
            .focus => try cmdFocus(browser, args, allocator),
            .@"type" => try cmdType(browser, args, allocator),
            .fill => try cmdFill(browser, args, allocator),
            .select => try cmdSelect(browser, args, allocator),
            .hover => try cmdHover(browser, args, allocator),
            .check => try cmdCheck(browser, args, allocator),
            .uncheck => try cmdUncheck(browser, args, allocator),
            .scroll => try cmdScroll(browser, args, allocator),
            .scrollintoview => try cmdScrollIntoView(browser, args, allocator),
            .drag => try cmdDrag(browser, args, allocator),
            .get => try cmdGet(browser, args, allocator),
            .upload => try cmdUpload(browser, args, allocator),
            .open, .connect, .help => unreachable,
        }
    }
}

/// Execute a command directly on a page-level connection (no session needed)
fn executeDirectly(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    // Page-level WebSocket URL: commands go directly without sessionId
    // Create a session with empty ID so commands are sent without sessionId
    var session = try cdp.Session.init("", browser.connection, allocator);
    defer session.deinit();

    switch (args.command) {
        .navigate => try cmdNavigateWithSession(session, args, allocator),
        .screenshot => try cmdScreenshotWithSession(session, args, allocator),
        .pdf => try cmdPdfWithSession(session, args, allocator),
        .evaluate => try cmdEvaluateWithSession(session, args, allocator),
        .dom => try cmdDomWithSession(session, args, allocator),
        .network => try cmdNetworkWithSession(session, args, allocator),
        .cookies => try cmdCookiesWithSession(session, args, allocator),
        .snapshot => try cmdSnapshotWithSession(session, args, allocator),
        .click => try cmdClickWithSession(session, args, allocator),
        .dblclick => try cmdDblClickWithSession(session, args, allocator),
        .focus => try cmdFocusWithSession(session, args, allocator),
        .@"type" => try cmdTypeWithSession(session, args, allocator),
        .fill => try cmdFillWithSession(session, args, allocator),
        .select => try cmdSelectWithSession(session, args, allocator),
        .hover => try cmdHoverWithSession(session, args, allocator),
        .check => try cmdCheckWithSession(session, args, allocator),
        .uncheck => try cmdUncheckWithSession(session, args, allocator),
        .scroll => try cmdScrollWithSession(session, args),
        .scrollintoview => try cmdScrollIntoViewWithSession(session, args, allocator),
        .drag => try cmdDragWithSession(session, args, allocator),
        .get => try cmdGetWithSession(session, args, allocator),
        .upload => try cmdUploadWithSession(session, args, allocator),
        .version => try cmdVersion(browser, allocator),
        .list_targets => try cmdListTargets(browser, allocator),
        .pages => try cmdPages(browser, allocator),
        else => std.debug.print("Error: Command not supported on page-level connections\n", .{}),
    }
}

/// Execute a command on an existing target
fn executeOnTarget(browser: *cdp.Browser, target_id: []const u8, args: Args, allocator: std.mem.Allocator) !void {
    if (args.verbose) {
        std.debug.print("Attaching to target: {s}\n", .{target_id});
    }

    // Attach to existing target
    var target = cdp.Target.init(browser.connection);
    const session_id = try target.attachToTarget(allocator, target_id, true);
    defer allocator.free(session_id);

    if (args.verbose) {
        std.debug.print("Session ID: {s}\n", .{session_id});
    }

    // Create session with the attached target
    var session = try cdp.Session.init(session_id, browser.connection, allocator);
    defer session.deinit();

    // Execute the command on this session
    switch (args.command) {
        .navigate => try cmdNavigateWithSession(session, args, allocator),
        .screenshot => try cmdScreenshotWithSession(session, args, allocator),
        .pdf => try cmdPdfWithSession(session, args, allocator),
        .evaluate => try cmdEvaluateWithSession(session, args, allocator),
        .dom => try cmdDomWithSession(session, args, allocator),
        .network => try cmdNetworkWithSession(session, args, allocator),
        .cookies => try cmdCookiesWithSession(session, args, allocator),
        .snapshot => try cmdSnapshotWithSession(session, args, allocator),
        .click => try cmdClickWithSession(session, args, allocator),
        .dblclick => try cmdDblClickWithSession(session, args, allocator),
        .focus => try cmdFocusWithSession(session, args, allocator),
        .@"type" => try cmdTypeWithSession(session, args, allocator),
        .fill => try cmdFillWithSession(session, args, allocator),
        .select => try cmdSelectWithSession(session, args, allocator),
        .hover => try cmdHoverWithSession(session, args, allocator),
        .check => try cmdCheckWithSession(session, args, allocator),
        .uncheck => try cmdUncheckWithSession(session, args, allocator),
        .scroll => try cmdScrollWithSession(session, args),
        .scrollintoview => try cmdScrollIntoViewWithSession(session, args, allocator),
        .drag => try cmdDragWithSession(session, args, allocator),
        .get => try cmdGetWithSession(session, args, allocator),
        .upload => try cmdUploadWithSession(session, args, allocator),
        else => std.debug.print("Error: Command not supported with --use\n", .{}),
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

/// DOM command
fn cmdDom(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len < 1) {
        std.debug.print("Error: dom requires a selector\n", .{});
        return;
    }

    // If 2+ positional args: first is URL, second is selector
    // If 1 positional arg: it's the selector (no navigation)
    const has_url = args.positional.len >= 2;
    const target_url = if (has_url) args.positional[0] else null;
    const selector = if (has_url) args.positional[1] else args.positional[0];

    var session = try browser.newPage();
    defer session.detach() catch {};

    var page = cdp.Page.init(session);
    try page.enable();

    var dom = cdp.DOM.init(session);
    try dom.enable();

    if (target_url) |url| {
        _ = try page.navigate(allocator, url);
        // Note: sleep API changed in Zig 0.16, using spinloop hint
        var i: u32 = 0;
        while (i < 500000) : (i += 1) {
            std.atomic.spinLoopHint();
        }
    }

    const doc = try dom.getDocument(allocator, 1);
    defer {
        var d = doc;
        d.deinit(allocator);
    }

    const node_id = try dom.querySelector(doc.node_id, selector);
    const html = try dom.getOuterHTML(allocator, node_id);
    defer allocator.free(html);

    std.debug.print("{s}\n", .{html});
}

/// Network command
fn cmdNetwork(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    _ = browser;
    _ = allocator;
    _ = args;
    std.debug.print("Network monitoring not yet implemented\n", .{});
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

/// Navigate command with existing session
fn cmdNavigateWithSession(session: *cdp.Session, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len < 1) {
        std.debug.print("Error: navigate requires a URL\n", .{});
        return;
    }

    const target_url = args.positional[0];

    var page = cdp.Page.init(session);
    try page.enable();

    var result = try page.navigate(allocator, target_url);
    defer result.deinit(allocator);

    if (result.error_text) |err| {
        std.debug.print("Navigation error: {s}\n", .{err});
        return;
    }

    // Wait for page load
    var i: u32 = 0;
    while (i < 500000) : (i += 1) {
        std.atomic.spinLoopHint();
    }

    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    const title = runtime.evaluateAs([]const u8, "document.title") catch "Unknown";

    std.debug.print("URL: {s}\n", .{target_url});
    std.debug.print("Title: {s}\n", .{title});
}

/// Screenshot command with existing session
fn cmdScreenshotWithSession(session: *cdp.Session, args: Args, allocator: std.mem.Allocator) !void {
    var page = cdp.Page.init(session);
    try page.enable();

    // Wait for page to be ready
    var j: u32 = 0;
    while (j < 500000) : (j += 1) {
        std.atomic.spinLoopHint();
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

/// PDF command with existing session
fn cmdPdfWithSession(session: *cdp.Session, args: Args, allocator: std.mem.Allocator) !void {
    var page = cdp.Page.init(session);
    try page.enable();

    // Wait for page to be ready
    var j: u32 = 0;
    while (j < 500000) : (j += 1) {
        std.atomic.spinLoopHint();
    }

    const pdf_data = try page.printToPDF(allocator, .{});
    defer allocator.free(pdf_data);

    const decoded = try cdp.base64.decodeAlloc(allocator, pdf_data);
    defer allocator.free(decoded);

    const output_path = args.output orelse "page.pdf";
    try writeFile(args.io, output_path, decoded);
    std.debug.print("PDF saved to {s} ({} bytes)\n", .{ output_path, decoded.len });
}

/// Evaluate command with existing session
fn cmdEvaluateWithSession(session: *cdp.Session, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len < 1) {
        std.debug.print("Error: evaluate requires an expression\n", .{});
        return;
    }

    const expression = args.positional[0];

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

/// DOM command with existing session
fn cmdDomWithSession(session: *cdp.Session, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len < 1) {
        std.debug.print("Error: dom requires a selector\n", .{});
        return;
    }

    const selector = args.positional[0];

    var page = cdp.Page.init(session);
    try page.enable();

    var dom = cdp.DOM.init(session);
    try dom.enable();

    const doc = try dom.getDocument(allocator, 1);
    defer {
        var d = doc;
        d.deinit(allocator);
    }

    const node_id = try dom.querySelector(doc.node_id, selector);
    const html = try dom.getOuterHTML(allocator, node_id);
    defer allocator.free(html);

    std.debug.print("{s}\n", .{html});
}

/// Network command with existing session
fn cmdNetworkWithSession(session: *cdp.Session, args: Args, allocator: std.mem.Allocator) !void {
    _ = session;
    _ = allocator;
    _ = args;
    std.debug.print("Network monitoring not yet implemented\n", .{});
}

/// Cookies command with existing session
fn cmdCookiesWithSession(session: *cdp.Session, args: Args, allocator: std.mem.Allocator) !void {
    _ = args; // Not used for cookies command
    var page = cdp.Page.init(session);
    try page.enable();

    var storage = cdp.Storage.init(session);

    var i: u32 = 0;
    while (i < 500000) : (i += 1) {
        std.atomic.spinLoopHint();
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

/// Interactive REPL
fn cmdInteractive(allocator: std.mem.Allocator) !void {
    _ = allocator;
    std.debug.print("Interactive mode not yet implemented\n", .{});
    std.debug.print("Use: navigate, screenshot, pdf, evaluate, dom, network, cookies, version, list-targets\n", .{});
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

    try cmdSnapshotWithSession(session, args, allocator);
}

/// Snapshot command with existing session
fn cmdSnapshotWithSession(session: *cdp.Session, args: Args, allocator: std.mem.Allocator) !void {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // Build and execute snapshot JavaScript
    const js = try snapshot_mod.buildSnapshotJs(allocator, args.snap_selector, args.snap_depth);
    defer allocator.free(js);

    var result = try runtime.evaluate(allocator, js, .{ .return_by_value = true });
    defer result.deinit(allocator);

    const aria_tree = result.asString() orelse "(empty)";

    // Process the ARIA tree
    var processor = snapshot_mod.SnapshotProcessor.init(allocator);
    defer processor.deinit();

    const options = snapshot_mod.SnapshotOptions{
        .interactive = args.snap_interactive,
        .compact = args.snap_compact,
        .max_depth = args.snap_depth,
        .selector = args.snap_selector,
    };

    var snapshot = try processor.processAriaTree(aria_tree, options);
    defer snapshot.deinit();

    // Print the tree
    std.debug.print("{s}\n", .{snapshot.tree});
    std.debug.print("\n--- {} element(s) with refs ---\n", .{snapshot.refs.count()});

    // Save to file
    const output_path = args.output orelse try config_mod.getSnapshotPath(allocator);
    defer if (args.output == null) allocator.free(output_path);

    try snapshot_mod.saveSnapshot(allocator, args.io, output_path, &snapshot);

    std.debug.print("\nSnapshot saved to: {s}\n", .{output_path});
    if (snapshot.refs.count() > 0) {
        std.debug.print("Use @e<N> refs in subsequent commands\n", .{});
    }
}

// ─── Action Commands ────────────────────────────────────────────────────────

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

/// Click command - uses existing page
fn cmdClick(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
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
    var session = try cdp.Session.init(session_id, browser.connection, allocator);
    defer session.deinit();

    try cmdClickWithSession(session, args, allocator);
}

fn cmdClickWithSession(session: *cdp.Session, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len == 0) {
        std.debug.print("Usage: zchrome click <selector>\n", .{});
        return;
    }

    var resolved = try actions_mod.resolveSelector(allocator, args.io, args.positional[0]);
    defer resolved.deinit();

    try actions_mod.clickElement(session, allocator, &resolved, 1);
    std.debug.print("Clicked: {s}\n", .{args.positional[0]});
}

/// Double-click command
fn cmdDblClick(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
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
    var session = try cdp.Session.init(session_id, browser.connection, allocator);
    defer session.deinit();

    try cmdDblClickWithSession(session, args, allocator);
}

fn cmdDblClickWithSession(session: *cdp.Session, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len == 0) {
        std.debug.print("Usage: zchrome dblclick <selector>\n", .{});
        return;
    }

    var resolved = try actions_mod.resolveSelector(allocator, args.io, args.positional[0]);
    defer resolved.deinit();

    try actions_mod.clickElement(session, allocator, &resolved, 2);
    std.debug.print("Double-clicked: {s}\n", .{args.positional[0]});
}

/// Focus command
fn cmdFocus(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
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
    var session = try cdp.Session.init(session_id, browser.connection, allocator);
    defer session.deinit();

    try cmdFocusWithSession(session, args, allocator);
}

fn cmdFocusWithSession(session: *cdp.Session, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len == 0) {
        std.debug.print("Usage: zchrome focus <selector>\n", .{});
        return;
    }

    var resolved = try actions_mod.resolveSelector(allocator, args.io, args.positional[0]);
    defer resolved.deinit();

    try actions_mod.focusElement(session, allocator, &resolved);
    std.debug.print("Focused: {s}\n", .{args.positional[0]});
}

/// Type command (type into focused element or specified element)
fn cmdType(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
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
    var session = try cdp.Session.init(session_id, browser.connection, allocator);
    defer session.deinit();

    try cmdTypeWithSession(session, args, allocator);
}

fn cmdTypeWithSession(session: *cdp.Session, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len < 2) {
        std.debug.print("Usage: zchrome type <selector> <text>\n", .{});
        return;
    }

    var resolved = try actions_mod.resolveSelector(allocator, args.io, args.positional[0]);
    defer resolved.deinit();

    try actions_mod.focusElement(session, allocator, &resolved);
    // Sleep using spinloop (Zig 0.16 changed time API)
    var j: u32 = 0;
    while (j < 500000) : (j += 1) {
        std.atomic.spinLoopHint();
    }
    try actions_mod.typeText(session, args.positional[1]);
    std.debug.print("Typed into: {s}\n", .{args.positional[0]});
}

/// Fill command (clear then type)
fn cmdFill(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
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
    var session = try cdp.Session.init(session_id, browser.connection, allocator);
    defer session.deinit();

    try cmdFillWithSession(session, args, allocator);
}

fn cmdFillWithSession(session: *cdp.Session, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len < 2) {
        std.debug.print("Usage: zchrome fill <selector> <text>\n", .{});
        return;
    }

    var resolved = try actions_mod.resolveSelector(allocator, args.io, args.positional[0]);
    defer resolved.deinit();

    try actions_mod.fillElement(session, allocator, &resolved, args.positional[1]);
    std.debug.print("Filled: {s}\n", .{args.positional[0]});
}

/// Select command (select dropdown option)
fn cmdSelect(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
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
    var session = try cdp.Session.init(session_id, browser.connection, allocator);
    defer session.deinit();

    try cmdSelectWithSession(session, args, allocator);
}

fn cmdSelectWithSession(session: *cdp.Session, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len < 2) {
        std.debug.print("Usage: zchrome select <selector> <value>\n", .{});
        return;
    }

    var resolved = try actions_mod.resolveSelector(allocator, args.io, args.positional[0]);
    defer resolved.deinit();

    try actions_mod.selectOption(session, allocator, &resolved, args.positional[1]);
    std.debug.print("Selected '{s}' in: {s}\n", .{ args.positional[1], args.positional[0] });
}

/// Hover command
fn cmdHover(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
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
    var session = try cdp.Session.init(session_id, browser.connection, allocator);
    defer session.deinit();

    try cmdHoverWithSession(session, args, allocator);
}

fn cmdHoverWithSession(session: *cdp.Session, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len == 0) {
        std.debug.print("Usage: zchrome hover <selector>\n", .{});
        return;
    }

    var resolved = try actions_mod.resolveSelector(allocator, args.io, args.positional[0]);
    defer resolved.deinit();

    try actions_mod.hoverElement(session, allocator, &resolved);
    std.debug.print("Hovering: {s}\n", .{args.positional[0]});
}

/// Check command (check checkbox)
fn cmdCheck(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
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
    var session = try cdp.Session.init(session_id, browser.connection, allocator);
    defer session.deinit();

    try cmdCheckWithSession(session, args, allocator);
}

fn cmdCheckWithSession(session: *cdp.Session, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len == 0) {
        std.debug.print("Usage: zchrome check <selector>\n", .{});
        return;
    }

    var resolved = try actions_mod.resolveSelector(allocator, args.io, args.positional[0]);
    defer resolved.deinit();

    try actions_mod.setChecked(session, allocator, &resolved, true);
    std.debug.print("Checked: {s}\n", .{args.positional[0]});
}

/// Uncheck command (uncheck checkbox)
fn cmdUncheck(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
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
    var session = try cdp.Session.init(session_id, browser.connection, allocator);
    defer session.deinit();

    try cmdUncheckWithSession(session, args, allocator);
}

fn cmdUncheckWithSession(session: *cdp.Session, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len == 0) {
        std.debug.print("Usage: zchrome uncheck <selector>\n", .{});
        return;
    }

    var resolved = try actions_mod.resolveSelector(allocator, args.io, args.positional[0]);
    defer resolved.deinit();

    try actions_mod.setChecked(session, allocator, &resolved, false);
    std.debug.print("Unchecked: {s}\n", .{args.positional[0]});
}

/// Scroll command
fn cmdScroll(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
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
    var session = try cdp.Session.init(session_id, browser.connection, allocator);
    defer session.deinit();

    try cmdScrollWithSession(session, args);
}

fn cmdScrollWithSession(session: *cdp.Session, args: Args) !void {
    if (args.positional.len == 0) {
        std.debug.print("Usage: zchrome scroll <up|down|left|right> [pixels]\n", .{});
        return;
    }

    const direction = args.positional[0];
    const pixels: f64 = if (args.positional.len > 1)
        @floatFromInt(std.fmt.parseInt(i32, args.positional[1], 10) catch 300)
    else
        300;

    var delta_x: f64 = 0;
    var delta_y: f64 = 0;

    if (std.mem.eql(u8, direction, "up")) {
        delta_y = -pixels;
    } else if (std.mem.eql(u8, direction, "down")) {
        delta_y = pixels;
    } else if (std.mem.eql(u8, direction, "left")) {
        delta_x = -pixels;
    } else if (std.mem.eql(u8, direction, "right")) {
        delta_x = pixels;
    } else {
        std.debug.print("Invalid direction: {s}. Use up, down, left, or right.\n", .{direction});
        return;
    }

    try actions_mod.scroll(session, delta_x, delta_y);
    std.debug.print("Scrolled {s} {d}px\n", .{ direction, pixels });
}

/// Scroll into view command
fn cmdScrollIntoView(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
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
    var session = try cdp.Session.init(session_id, browser.connection, allocator);
    defer session.deinit();

    try cmdScrollIntoViewWithSession(session, args, allocator);
}

fn cmdScrollIntoViewWithSession(session: *cdp.Session, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len == 0) {
        std.debug.print("Usage: zchrome scrollintoview <selector>\n", .{});
        return;
    }

    var resolved = try actions_mod.resolveSelector(allocator, args.io, args.positional[0]);
    defer resolved.deinit();

    try actions_mod.scrollIntoView(session, allocator, &resolved);
    std.debug.print("Scrolled into view: {s}\n", .{args.positional[0]});
}

/// Drag command - drag from source element to target element
fn cmdDrag(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
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
    var session = try cdp.Session.init(session_id, browser.connection, allocator);
    defer session.deinit();

    try cmdDragWithSession(session, args, allocator);
}

fn cmdDragWithSession(session: *cdp.Session, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len < 2) {
        std.debug.print("Usage: zchrome drag <source-selector> <target-selector>\n", .{});
        return;
    }

    var src_resolved = try actions_mod.resolveSelector(allocator, args.io, args.positional[0]);
    defer src_resolved.deinit();

    var tgt_resolved = try actions_mod.resolveSelector(allocator, args.io, args.positional[1]);
    defer tgt_resolved.deinit();

    try actions_mod.dragElement(session, allocator, &src_resolved, &tgt_resolved);
    std.debug.print("Dragged: {s} -> {s}\n", .{ args.positional[0], args.positional[1] });
}

/// Upload command - upload files to file input element
fn cmdUpload(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
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
    var session = try cdp.Session.init(session_id, browser.connection, allocator);
    defer session.deinit();

    try cmdUploadWithSession(session, args, allocator);
}

fn cmdUploadWithSession(session: *cdp.Session, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len < 2) {
        std.debug.print("Usage: zchrome upload <selector> <file1> [file2...]\n", .{});
        return;
    }

    var resolved = try actions_mod.resolveSelector(allocator, args.io, args.positional[0]);
    defer resolved.deinit();

    const files = args.positional[1..];
    try actions_mod.uploadFiles(session, allocator, args.io, &resolved, files);
    std.debug.print("Uploaded {} file(s) to: {s}\n", .{ files.len, args.positional[0] });
}

/// Get command - retrieve information from elements and page
fn cmdGet(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
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
    var session = try cdp.Session.init(session_id, browser.connection, allocator);
    defer session.deinit();

    try cmdGetWithSession(session, args, allocator);
}

fn cmdGetWithSession(session: *cdp.Session, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len == 0) {
        printGetUsage();
        return;
    }

    const subcommand = args.positional[0];

    // Page-level getters (no selector needed)
    if (std.mem.eql(u8, subcommand, "title")) {
        const title = try actions_mod.getPageTitle(session, allocator);
        defer allocator.free(title);
        std.debug.print("{s}\n", .{title});
        return;
    }

    if (std.mem.eql(u8, subcommand, "url")) {
        const url = try actions_mod.getPageUrl(session, allocator);
        defer allocator.free(url);
        std.debug.print("{s}\n", .{url});
        return;
    }

    // Element-level getters (need selector)
    if (args.positional.len < 2) {
        std.debug.print("Error: Missing selector\n", .{});
        printGetUsage();
        return;
    }

    const selector = args.positional[1];

    if (std.mem.eql(u8, subcommand, "text")) {
        var resolved = try actions_mod.resolveSelector(allocator, args.io, selector);
        defer resolved.deinit();

        if (try actions_mod.getText(session, allocator, &resolved)) |text| {
            defer allocator.free(text);
            std.debug.print("{s}\n", .{text});
        } else {
            std.debug.print("(element not found)\n", .{});
        }
    } else if (std.mem.eql(u8, subcommand, "html")) {
        var resolved = try actions_mod.resolveSelector(allocator, args.io, selector);
        defer resolved.deinit();

        if (try actions_mod.getHtml(session, allocator, &resolved)) |html| {
            defer allocator.free(html);
            std.debug.print("{s}\n", .{html});
        } else {
            std.debug.print("(element not found)\n", .{});
        }
    } else if (std.mem.eql(u8, subcommand, "value")) {
        var resolved = try actions_mod.resolveSelector(allocator, args.io, selector);
        defer resolved.deinit();

        if (try actions_mod.getValue(session, allocator, &resolved)) |value| {
            defer allocator.free(value);
            std.debug.print("{s}\n", .{value});
        } else {
            std.debug.print("(element not found)\n", .{});
        }
    } else if (std.mem.eql(u8, subcommand, "attr")) {
        if (args.positional.len < 3) {
            std.debug.print("Error: Missing attribute name\n", .{});
            std.debug.print("Usage: zchrome get attr <selector> <attribute>\n", .{});
            return;
        }
        const attr_name = args.positional[2];

        var resolved = try actions_mod.resolveSelector(allocator, args.io, selector);
        defer resolved.deinit();

        if (try actions_mod.getAttribute(session, allocator, &resolved, attr_name)) |value| {
            defer allocator.free(value);
            std.debug.print("{s}\n", .{value});
        } else {
            std.debug.print("(null)\n", .{});
        }
    } else if (std.mem.eql(u8, subcommand, "count")) {
        const count = try actions_mod.getCount(session, allocator, selector);
        std.debug.print("{}\n", .{count});
    } else if (std.mem.eql(u8, subcommand, "box")) {
        var resolved = try actions_mod.resolveSelector(allocator, args.io, selector);
        defer resolved.deinit();

        const pos = actions_mod.getElementPosition(session, allocator, &resolved) catch {
            std.debug.print("(element not found)\n", .{});
            return;
        };
        std.debug.print("x={d:.0} y={d:.0} width={d:.0} height={d:.0}\n", .{ pos.x, pos.y, pos.width, pos.height });
    } else if (std.mem.eql(u8, subcommand, "styles")) {
        var resolved = try actions_mod.resolveSelector(allocator, args.io, selector);
        defer resolved.deinit();

        if (try actions_mod.getStyles(session, allocator, &resolved)) |styles| {
            defer allocator.free(styles);
            std.debug.print("{s}\n", .{styles});
        } else {
            std.debug.print("(element not found)\n", .{});
        }
    } else {
        std.debug.print("Unknown subcommand: {s}\n", .{subcommand});
        printGetUsage();
    }
}

fn printGetUsage() void {
    std.debug.print(
        \\Usage: zchrome get <subcommand> [selector] [args]
        \\
        \\Subcommands:
        \\  text <sel>           Get text content
        \\  html <sel>           Get innerHTML
        \\  value <sel>          Get input value
        \\  attr <sel> <attr>    Get attribute value
        \\  title                Get page title
        \\  url                  Get current URL
        \\  count <sel>          Count matching elements
        \\  box <sel>            Get bounding box
        \\  styles <sel>         Get computed styles (JSON)
        \\
        \\Examples:
        \\  zchrome get text @e3
        \\  zchrome get value "#email"
        \\  zchrome get attr @e5 href
        \\  zchrome get title
        \\  zchrome get count "li.item"
        \\
    , .{});
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
        \\  dom [url] <selector>     Query DOM, print outerHTML
        \\  network [url]            Log network requests
        \\  cookies [url]            Dump cookies
        \\  snapshot                 Capture accessibility tree of active page, save to zsnap.json
        \\  version                  Print browser version info
        \\  list-targets             List all open targets
        \\  pages                    List all open pages with target IDs
        \\  interactive              REPL: enter CDP commands as JSON
        \\  help                     Show this help message
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
        \\GETTERS:
        \\  get text <sel>           Get text content
        \\  get html <sel>           Get innerHTML
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
    , .{});
}
