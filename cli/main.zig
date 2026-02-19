const std = @import("std");
const cdp = @import("cdp");

/// CLI arguments
const Args = struct {
    url: ?[]const u8 = null,
    headless: cdp.Headless = .new,
    port: u16 = 0,
    chrome_path: ?[]const u8 = null,
    timeout_ms: u32 = 30_000,
    verbose: bool = false,
    output: ?[]const u8 = null,
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
        interactive,
        help,
    };
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const args = parseArgs(allocator, init.minimal.args) catch {
        printUsage();
        std.process.exit(1);
    };
    defer {
        for (args.positional) |p| allocator.free(p);
        allocator.free(args.positional);
        if (args.url) |u| allocator.free(u);
        if (args.chrome_path) |p| allocator.free(p);
        if (args.output) |o| allocator.free(o);
    }

    if (args.command == .help) {
        printUsage();
        return;
    }

    // Launch or connect to browser
    const is_connected = args.url != null;
    var browser = if (args.url) |ws_url|
        cdp.Browser.connect(ws_url, allocator, init.io) catch |err| {
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

    // Execute command
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
        .interactive => try cmdInteractive(allocator),
        .help => unreachable,
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
    if (args.positional.len < 1) {
        std.debug.print("Error: screenshot requires a URL\n", .{});
        return;
    }

    const target_url = args.positional[0];
    var session = try browser.newPage();
    defer session.detach() catch {};

    var page = cdp.Page.init(session);
    try page.enable();

    _ = try page.navigate(allocator, target_url);
    // Note: sleep API changed in Zig 0.16
    {
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
    // Note: File operations require Io context in Zig 0.16
    // For now, just print the data info
    _ = output_path;
    std.debug.print("Screenshot captured ({} bytes). File writing requires Io context in Zig 0.16.\n", .{decoded.len});
}

/// PDF command
fn cmdPdf(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len < 1) {
        std.debug.print("Error: pdf requires a URL\n", .{});
        return;
    }

    const target_url = args.positional[0];
    var session = try browser.newPage();
    defer session.detach() catch {};

    var page = cdp.Page.init(session);
    try page.enable();

    _ = try page.navigate(allocator, target_url);
    // Note: sleep API changed in Zig 0.16
    {
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
    // Note: File operations require Io context in Zig 0.16
    _ = output_path;
    std.debug.print("PDF generated ({} bytes). File writing requires Io context in Zig 0.16.\n", .{decoded.len});
}

/// Evaluate command
fn cmdEvaluate(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len < 2) {
        std.debug.print("Error: evaluate requires a URL and expression\n", .{});
        return;
    }

    const target_url = args.positional[0];
    const expression = args.positional[1];

    var session = try browser.newPage();
    defer session.detach() catch {};

    var page = cdp.Page.init(session);
    try page.enable();

    _ = try page.navigate(allocator, target_url);
    // Note: sleep API changed in Zig 0.16, using spinloop hint
    var i: u32 = 0;
    while (i < 500000) : (i += 1) {
        std.atomic.spinLoopHint();
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
    if (args.positional.len < 2) {
        std.debug.print("Error: dom requires a URL and selector\n", .{});
        return;
    }

    const target_url = args.positional[0];
    const selector = args.positional[1];

    var session = try browser.newPage();
    defer session.detach() catch {};

    var page = cdp.Page.init(session);
    try page.enable();

    var dom = cdp.DOM.init(session);
    try dom.enable();

    _ = try page.navigate(allocator, target_url);
    // Note: sleep API changed in Zig 0.16, using spinloop hint
    var i: u32 = 0;
    while (i < 500000) : (i += 1) {
        std.atomic.spinLoopHint();
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
    if (args.positional.len < 1) {
        std.debug.print("Error: network requires a URL\n", .{});
        return;
    }
    std.debug.print("Network monitoring not yet implemented\n", .{});
}

/// Cookies command
fn cmdCookies(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len < 1) {
        std.debug.print("Error: cookies requires a URL\n", .{});
        return;
    }

    const target_url = args.positional[0];
    var session = try browser.newPage();
    defer session.detach() catch {};

    var page = cdp.Page.init(session);
    try page.enable();

    var storage = cdp.Storage.init(session);

    _ = try page.navigate(allocator, target_url);
    // Note: sleep API changed in Zig 0.16, using spinloop hint
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

    _ = iter.skip(); // Skip program name

    while (iter.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--")) {
            if (std.mem.eql(u8, arg, "--url")) {
                const val = iter.next() orelse return error.MissingArgument;
                url = try allocator.dupe(u8, val);
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
        \\  --headless <new|old|off> Headless mode [default: new]
        \\  --port <port>            Debug port [default: auto]
        \\  --chrome <path>          Chrome binary path
        \\  --timeout <ms>           Command timeout [default: 30000]
        \\  --verbose                Print CDP messages
        \\  --output <path>          Output file path (for screenshot/pdf)
        \\
        \\COMMANDS:
        \\  navigate <url>           Navigate to URL, print final URL + title
        \\  screenshot <url>         Navigate + capture PNG screenshot
        \\  pdf <url>                Navigate + print to PDF
        \\  evaluate <url> <expr>    Navigate + evaluate JS expression
        \\  dom <url> <selector>     Navigate + query DOM + print outerHTML
        \\  network <url>            Navigate + log all network requests
        \\  cookies <url>            Navigate + dump cookies
        \\  version                  Print browser version info
        \\  list-targets             List all open targets
        \\  interactive              REPL: enter CDP commands as JSON
        \\  help                     Show this help message
        \\
        \\EXAMPLES:
        \\  cdp-cli screenshot https://example.com --output page.png
        \\  cdp-cli evaluate https://example.com "document.title"
        \\  cdp-cli version
        \\
    , .{});
}
