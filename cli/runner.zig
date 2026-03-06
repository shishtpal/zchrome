const std = @import("std");
const cdp = @import("cdp");
const args_mod = @import("args.zig");
const config_mod = @import("config.zig");
const http_mod = @import("http.zig");
const interactive_mod = @import("interactive/mod.zig");
const impl = @import("commands/mod.zig");
const session_mod = @import("session.zig");

const Args = args_mod.Args;

fn saveTargetToConfig(target_id: []const u8, args: Args) void {
    const session_ctx = args.session_ctx orelse return;
    const allocator = session_ctx.allocator;

    var config = session_ctx.loadConfig() orelse config_mod.Config{};

    if (config.last_target) |old| allocator.free(old);
    config.last_target = allocator.dupe(u8, target_id) catch null;

    if (args.url != null and config.ws_url == null) {
        config.ws_url = allocator.dupe(u8, args.url.?) catch null;
    }

    session_ctx.saveConfig(config) catch |err| {
        std.debug.print("Warning: Could not save target to config: {}\n", .{err});
    };

    if (config.chrome_path) |p| allocator.free(p);
    if (config.data_dir) |d| allocator.free(d);
    if (config.ws_url) |u| allocator.free(u);
    if (config.last_target) |t| allocator.free(t);
}

fn writeFile(io: std.Io, path: []const u8, data: []const u8) !void {
    const dir = std.Io.Dir.cwd();
    dir.writeFile(io, .{ .sub_path = path, .data = data }) catch |err| {
        std.debug.print("Error writing {s}: {}\n", .{ path, err });
        return err;
    };
}

fn buildCtx(args: Args, allocator: std.mem.Allocator) impl.CommandCtx {
    return .{
        .allocator = allocator,
        .io = args.io,
        .positional = args.positional,
        .output = args.output,
        .full_page = args.full_page,
        .session = args.session_ctx,
        .snap_interactive = args.snap_interactive,
        .snap_compact = args.snap_compact,
        .snap_depth = args.snap_depth,
        .snap_selector = args.snap_selector,
        .wait_text = args.wait_text,
        .wait_url = args.wait_url,
        .wait_load = args.wait_load,
        .wait_fn = args.wait_fn,
        .click_js = args.click_js,
        .replay_retries = args.replay_retries,
        .replay_retry_delay = args.replay_retry_delay,
        .replay_fallback = args.replay_fallback,
        .replay_resume = args.replay_resume,
        .replay_from = args.replay_from,
    };
}

fn executeWithSession(browser: *cdp.Browser, session_id: []const u8, args: Args, allocator: std.mem.Allocator) !void {
    var session = try cdp.Session.init(session_id, browser.connection, allocator);
    defer session.deinit();

    impl.applyEmulationSettings(session, allocator, args.io, args.session_ctx);

    const ctx = buildCtx(args, allocator);
    if (!try impl.dispatchSessionCommand(session, args.command, ctx)) {
        switch (args.command) {
            .version => try cmdVersion(browser, allocator),
            .list_targets => try cmdListTargets(browser, allocator),
            .pages => try cmdPages(browser, allocator),
            else => std.debug.print("Error: Command not supported in this mode\n", .{}),
        }
    }
}

pub fn executeDirectly(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    try executeWithSession(browser, "", args, allocator);
}

pub fn executeOnTarget(browser: *cdp.Browser, target_id: []const u8, args: Args, allocator: std.mem.Allocator) !void {
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

pub fn withFirstPage(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
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

    impl.applyEmulationSettings(session, allocator, args.io, args.session_ctx);

    const ctx = buildCtx(args, allocator);
    if (!try impl.dispatchSessionCommand(session, args.command, ctx)) {
        std.debug.print("Error: Command not supported in this mode\n", .{});
    }
}

pub fn cmdNavigate(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len < 1) {
        std.debug.print("Error: navigate requires a URL\n", .{});
        return;
    }

    const target_url = args.positional[0];

    const pages = try browser.pages();
    defer {
        for (pages) |*p| {
            var page_info = p.*;
            page_info.deinit(allocator);
        }
        allocator.free(pages);
    }

    var target_id: ?[]const u8 = null;
    var session: *cdp.Session = undefined;
    var created_new = false;

    if (pages.len > 0) {
        target_id = pages[0].target_id;
        if (args.verbose) {
            std.debug.print("Using existing page: {s}\n", .{target_id.?});
        }
        var target = cdp.Target.init(browser.connection);
        const session_id = try target.attachToTarget(allocator, target_id.?, true);
        defer allocator.free(session_id);
        session = try cdp.Session.init(session_id, browser.connection, allocator);
    } else {
        if (args.verbose) {
            std.debug.print("Creating new page\n", .{});
        }
        session = try browser.newPage();
        created_new = true;
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

    impl.applyEmulationSettings(session, allocator, args.io, args.session_ctx);

    var page = cdp.Page.init(session);
    try page.enable();

    var result = try page.navigate(allocator, target_url);
    defer result.deinit(allocator);

    if (result.error_text) |err| {
        std.debug.print("Navigation error: {s}\n", .{err});
        return;
    }

    var i: u32 = 0;
    while (i < 500000) : (i += 1) {
        std.atomic.spinLoopHint();
    }

    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    var eval_result = runtime.evaluate(allocator, "document.title", .{ .return_by_value = true }) catch null;
    defer if (eval_result) |*r| r.deinit(allocator);
    const title = if (eval_result) |r|
        if (r.value) |v| switch (v) {
            .string => |s| s,
            else => r.description orelse "Unknown",
        } else r.description orelse "Unknown"
    else
        "Unknown";

    std.debug.print("URL: {s}\n", .{target_url});
    std.debug.print("Title: {s}\n", .{title});
    if (target_id) |tid| {
        std.debug.print("Target: {s}\n", .{tid});
        saveTargetToConfig(tid, args);
        if (created_new) allocator.free(tid);
    }
}

pub fn cmdScreenshot(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    var session = try browser.newPage();
    defer session.detach() catch {};

    impl.applyEmulationSettings(session, allocator, args.io, args.session_ctx);

    var page = cdp.Page.init(session);
    try page.enable();

    if (args.positional.len > 0) {
        _ = try page.navigate(allocator, args.positional[0]);
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

pub fn cmdPdf(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    var session = try browser.newPage();
    defer session.detach() catch {};

    impl.applyEmulationSettings(session, allocator, args.io, args.session_ctx);

    var page = cdp.Page.init(session);
    try page.enable();

    if (args.positional.len > 0) {
        _ = try page.navigate(allocator, args.positional[0]);
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

pub fn cmdEvaluate(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    if (args.positional.len < 1) {
        std.debug.print("Error: evaluate requires an expression\n", .{});
        return;
    }

    const has_url = args.positional.len >= 2;
    const target_url = if (has_url) args.positional[0] else null;
    const expression = if (has_url) args.positional[1] else args.positional[0];

    var session = try browser.newPage();
    defer session.detach() catch {};

    impl.applyEmulationSettings(session, allocator, args.io, args.session_ctx);

    var page = cdp.Page.init(session);
    try page.enable();

    if (target_url) |url| {
        _ = try page.navigate(allocator, url);
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

pub fn cmdTab(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    for (args.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            impl.printTabHelp();
            return;
        }
    }

    var target = cdp.Target.init(browser.connection);

    if (args.positional.len >= 1 and std.mem.eql(u8, args.positional[0], "new")) {
        const url = if (args.positional.len >= 2) args.positional[1] else "about:blank";
        const target_id = try target.createTarget(url);
        std.debug.print("New tab: {s}\n", .{target_id});
        saveTargetToConfig(target_id, args);
        return;
    }

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
            close_idx -= 1;
        }
        const success = try target.closeTarget(page_tabs[close_idx].target_id);
        if (success) {
            std.debug.print("Closed tab {}: {s}\n", .{ close_idx + 1, page_tabs[close_idx].title });
        } else {
            std.debug.print("Failed to close tab\n", .{});
        }
        return;
    }

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
        saveTargetToConfig(selected.target_id, args);
        std.debug.print("Switched to tab {}: {s} ({s})\n", .{ tab_num, selected.title, selected.url });
        return;
    }

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

pub fn cmdWindow(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    _ = allocator;

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

pub fn cmdVersion(browser: *cdp.Browser, allocator: std.mem.Allocator) !void {
    var version = try browser.version();
    defer version.deinit(allocator);

    std.debug.print("Protocol Version: {s}\n", .{version.protocol_version});
    std.debug.print("Product: {s}\n", .{version.product});
    std.debug.print("Revision: {s}\n", .{version.revision});
    std.debug.print("User Agent: {s}\n", .{version.user_agent});
    std.debug.print("JS Version: {s}\n", .{version.js_version});
}

pub fn cmdListTargets(browser: *cdp.Browser, allocator: std.mem.Allocator) !void {
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

pub fn cmdPages(browser: *cdp.Browser, allocator: std.mem.Allocator) !void {
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

pub fn cmdInteractive(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
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
        .session_ctx = args.session_ctx,
    };
    defer state.deinit();

    const page = findFirstRealPage(pages);
    if (page) |p| {
        var target = cdp.Target.init(browser.connection);
        const session_id = target.attachToTarget(allocator, p.target_id, true) catch |err| {
            std.debug.print("Warning: Could not attach to page: {}\n", .{err});
            try interactive_mod.run(&state);
            return;
        };
        defer allocator.free(session_id);
        state.session = cdp.Session.init(session_id, browser.connection, allocator) catch |err| {
            std.debug.print("Warning: Could not create session: {}\n", .{err});
            try interactive_mod.run(&state);
            return;
        };
        state.target_id = allocator.dupe(u8, p.target_id) catch null;

        if (state.session) |s| {
            impl.applyEmulationSettings(s, allocator, args.io, args.session_ctx);
        }
    }

    try interactive_mod.run(&state);
}

pub fn cmdSnapshot(browser: *cdp.Browser, args: Args, allocator: std.mem.Allocator) !void {
    const pages = try browser.pages();
    defer {
        for (pages) |*p| {
            var page_info = p.*;
            page_info.deinit(allocator);
        }
        allocator.free(pages);
    }

    const session: *cdp.Session = blk: {
        if (pages.len > 0) {
            const target_id = pages[0].target_id;
            if (args.verbose) {
                std.debug.print("Using existing page: {s}\n", .{target_id});
            }
            var target = cdp.Target.init(browser.connection);
            const session_id = try target.attachToTarget(allocator, target_id, true);
            defer allocator.free(session_id);
            break :blk try cdp.Session.init(session_id, browser.connection, allocator);
        } else {
            if (args.verbose) {
                std.debug.print("Creating new page\n", .{});
            }
            break :blk try browser.newPage();
        }
    };
    defer session.deinit();

    impl.applyEmulationSettings(session, allocator, args.io, args.session_ctx);

    const ctx = buildCtx(args, allocator);
    try impl.snapshot(session, ctx);
}

fn findFirstRealPage(pages: []cdp.TargetInfo) ?*cdp.TargetInfo {
    for (pages) |*p| {
        if (std.mem.startsWith(u8, p.url, "devtools://")) continue;
        if (std.mem.startsWith(u8, p.url, "chrome://")) continue;
        if (std.mem.startsWith(u8, p.url, "chrome-extension://")) continue;
        if (std.mem.startsWith(u8, p.url, "about:")) continue;
        return p;
    }
    if (pages.len > 0) return &pages[0];
    return null;
}

pub fn cmdOpen(args: Args, allocator: std.mem.Allocator, io: std.Io) !void {
    const port = args.port orelse 9222;

    if (http_mod.isChromeRunning(io, port)) {
        const current_ws_url = http_mod.getChromeWsUrl(allocator, io, port) catch |err| {
            std.debug.print("Warning: Could not get WebSocket URL: {}\n", .{err});
            return;
        };
        defer allocator.free(current_ws_url);

        var is_same_session = false;
        if (args.session_ctx) |ctx| {
            if (ctx.loadConfig()) |cfg| {
                var config = cfg;
                defer config.deinit(allocator);
                if (config.ws_url) |saved_ws_url| {
                    is_same_session = std.mem.eql(u8, saved_ws_url, current_ws_url);
                }
            }
        }

        if (is_same_session) {
            std.debug.print("Chrome already running on port {}\n", .{port});
            std.debug.print("WebSocket URL: {s}\n", .{current_ws_url});

            const save_config = config_mod.Config{
                .chrome_path = args.chrome_path,
                .data_dir = args.data_dir,
                .port = port,
                .ws_url = current_ws_url,
                .last_target = null,
            };
            if (args.session_ctx) |ctx| {
                ctx.saveConfig(save_config) catch |err| {
                    std.debug.print("Warning: Could not save config: {}\n", .{err});
                };
            }
        } else {
            std.debug.print("Error: Port {} is already in use by another Chrome instance.\n\n", .{port});
            std.debug.print("To run multiple Chrome instances for different sessions, use --port:\n", .{});
            std.debug.print("  zchrome open --port {}\n\n", .{@as(u32, port) + 1});
            std.debug.print("The port will be saved to this session's config for future commands.\n", .{});
        }
        return;
    }

    const chrome_path = args.chrome_path orelse blk: {
        break :blk cdp.findChrome(allocator) catch {
            std.debug.print("Error: Chrome not found. Use --chrome to specify path.\n", .{});
            std.process.exit(1);
        };
    };

    var data_dir_allocated = false;
    const data_dir = args.data_dir orelse blk: {
        if (args.session_ctx) |ctx| {
            const session_dir = session_mod.getSessionDir(allocator, io, ctx.name) catch break :blk @as([]const u8, "zchrome-profile");
            defer allocator.free(session_dir);
            const profile_dir = std.fs.path.join(allocator, &.{ session_dir, "chrome-profile" }) catch break :blk @as([]const u8, "zchrome-profile");
            data_dir_allocated = true;
            break :blk profile_dir;
        }
        break :blk @as([]const u8, "zchrome-profile");
    };
    defer if (data_dir_allocated) allocator.free(data_dir);

    var argv_list: std.ArrayList([]const u8) = .empty;
    defer argv_list.deinit(allocator);

    try argv_list.append(allocator, chrome_path);

    const port_arg = try std.fmt.allocPrint(allocator, "--remote-debugging-port={}", .{port});
    defer allocator.free(port_arg);
    try argv_list.append(allocator, port_arg);

    const data_arg = try std.fmt.allocPrint(allocator, "--user-data-dir={s}", .{data_dir});
    defer allocator.free(data_arg);
    try argv_list.append(allocator, data_arg);

    if (args.headless != .off) {
        const headless_arg: []const u8 = if (args.headless == .new) "--headless=new" else "--headless";
        try argv_list.append(allocator, headless_arg);
    }

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

    const new_config = config_mod.Config{
        .chrome_path = chrome_path,
        .data_dir = data_dir,
        .port = port,
        .ws_url = null,
        .last_target = null,
    };
    if (args.session_ctx) |ctx| {
        ctx.saveConfig(new_config) catch |err| {
            std.debug.print("Warning: Could not save config: {}\n", .{err});
        };
    }
}

pub fn cmdConnect(args: Args, allocator: std.mem.Allocator, io: std.Io) !void {
    const port = args.port orelse 9222;

    if (args.verbose) {
        std.debug.print("Checking if Chrome is running on port {}...\n", .{port});
    }

    if (!http_mod.isChromeRunning(io, port)) {
        std.debug.print("Error: Chrome not running on port {}.\n", .{port});
        std.debug.print("Run 'zchrome open' to launch Chrome first.\n", .{});
        std.process.exit(1);
    }

    if (args.verbose) {
        std.debug.print("Chrome is running. Fetching WebSocket URL...\n", .{});
    }

    const ws_url = http_mod.getChromeWsUrl(allocator, io, port) catch |err| {
        std.debug.print("Error: Could not get WebSocket URL: {}\n", .{err});
        std.process.exit(1);
    };
    defer allocator.free(ws_url);

    std.debug.print("Connected to Chrome on port {}\n", .{port});
    std.debug.print("WebSocket URL: {s}\n", .{ws_url});

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
    if (args.session_ctx) |ctx| {
        ctx.saveConfig(save_config) catch |err| {
            std.debug.print("Warning: Could not save config: {}\n", .{err});
        };
    }

    if (args.verbose) {
        std.debug.print("Config saved successfully.\n", .{});
    }
}
