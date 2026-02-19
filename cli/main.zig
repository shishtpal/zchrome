const std = @import("std");
const cdp = @import("cdp");

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
    port: u16 = 0,
    chrome_path: ?[]const u8 = null,
    timeout_ms: u32 = 30_000,
    verbose: bool = false,
    output: ?[]const u8 = null,
    use_target: ?[]const u8 = null,
    io: std.Io = undefined,
    command: Command,
    positional: []const []const u8,

    const Command = enum {
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
        if (args.output) |o| allocator.free(o);
        if (args.use_target) |t| allocator.free(t);
    }

    if (args.command == .help) {
        printUsage();
        return;
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
            .help => unreachable,
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
        else => std.debug.print("Error: Command not supported with --use\n", .{}),
    }
}

/// Navigate command
fn cmdNavigate(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len < 1) {
        std.debug.print("Error: navigate requires a URL\n", .{});
        return;
    }

    const target_url = args.positional[0];
    var session = try browser.newPage();
    defer session.detach() catch {};

    var page = cdp.Page.init(session);
    try page.enable();

    var result = try page.navigate(allocator, target_url);
    defer result.deinit(allocator);

    if (result.error_text) |err| {
        std.debug.print("Navigation error: {s}\n", .{err});
        return;
    }

    // Note: sleep API changed in Zig 0.16, using spinloop hint
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

    const screenshot_data = try page.captureScreenshot(allocator, .{ .format = .png });
    defer allocator.free(screenshot_data);

    const decoded = try cdp.base64.decodeAlloc(allocator, screenshot_data);
    defer allocator.free(decoded);

    const output_path = args.output orelse "screenshot.png";
    try writeFile(args.io, output_path, decoded);
    std.debug.print("Screenshot saved to {s} ({} bytes)\n", .{ output_path, decoded.len });
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

    const screenshot_data = try page.captureScreenshot(allocator, .{ .format = .png });
    defer allocator.free(screenshot_data);

    const decoded = try cdp.base64.decodeAlloc(allocator, screenshot_data);
    defer allocator.free(decoded);

    const output_path = args.output orelse "screenshot.png";
    try writeFile(args.io, output_path, decoded);
    std.debug.print("Screenshot saved to {s} ({} bytes)\n", .{ output_path, decoded.len });
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
    var headless: cdp.Headless = .new;
    var port: u16 = 0;
    var chrome_path: ?[]const u8 = null;
    var timeout_ms: u32 = 30_000;
    var verbose: bool = false;
    var output: ?[]const u8 = null;
    var use_target: ?[]const u8 = null;

    _ = iter.skip(); // Skip program name

    while (iter.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--")) {
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
            } else if (std.mem.eql(u8, arg, "--timeout")) {
                const val = iter.next() orelse return error.MissingArgument;
                timeout_ms = try std.fmt.parseInt(u32, val, 10);
            } else if (std.mem.eql(u8, arg, "--verbose")) {
                verbose = true;
            } else if (std.mem.eql(u8, arg, "--output")) {
                const val = iter.next() orelse return error.MissingArgument;
                output = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, arg, "--help")) {
                command = .help;
                break;
            }
        } else {
            if (command == .help) {
                command = std.meta.stringToEnum(Args.Command, arg) orelse .help;
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
        .timeout_ms = timeout_ms,
        .verbose = verbose,
        .output = output,
        .use_target = use_target,
        .command = command,
        .positional = try positional.toOwnedSlice(allocator),
    };
}

/// Print usage information
fn printUsage() void {
    std.debug.print(
        \\cdp-cli [options] <command> [command-args]
        \\
        \\GLOBAL OPTIONS:
        \\  --url <ws-url>           Connect to existing Chrome (ws://...)
        \\  --use <target-id>        Execute command on existing page (no URL needed)
        \\  --headless <new|old|off> Headless mode [default: new]
        \\  --port <port>            Debug port [default: auto]
        \\  --chrome <path>          Chrome binary path
        \\  --timeout <ms>           Command timeout [default: 30000]
        \\  --verbose                Print CDP messages
        \\  --output <path>          Output file path (for screenshot/pdf)
        \\
        \\COMMANDS:
        \\  navigate <url>           Navigate to URL, print final URL + title
        \\  screenshot [url]         Capture PNG screenshot (no URL = current page)
        \\  pdf [url]                Generate PDF (no URL = current page)
        \\  evaluate [url] <expr>    Evaluate JS expression (no URL = current page)
        \\  dom [url] <selector>     Query DOM, print outerHTML (no URL = current page)
        \\  network [url]            Log network requests (no URL = current page)
        \\  cookies [url]            Dump cookies (no URL = current page)
        \\  version                  Print browser version info
        \\  list-targets             List all open targets
        \\  pages                    List all open pages with target IDs
        \\  interactive              REPL: enter CDP commands as JSON
        \\  help                     Show this help message
        \\
        \\EXAMPLES:
        \\  # List pages and execute on existing page
        \\  cdp-cli --url $url pages
        \\  cdp-cli --url $url --use <target-id> screenshot --output page.png
        \\  cdp-cli --url $url --use <target-id> evaluate "document.title"
        \\  
        \\  # Create new page, navigate, and execute
        \\  cdp-cli screenshot https://example.com --output page.png
        \\  cdp-cli evaluate https://example.com "document.title"
        \\
    , .{});
}
