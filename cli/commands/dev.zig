//! Dev command dispatcher - routes to debugging subcommands.
//!
//! Usage: zchrome dev <subcommand> [args...]
//!
//! Subcommands:
//!   trace     - Start/stop trace recording
//!   profiler  - Start/stop Chrome DevTools profiling
//!   console   - View/clear console messages
//!   errors    - View/clear page errors
//!   highlight - Highlight DOM elements
//!   state     - Manage auth state (save/load/list/etc.)

const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");
const helpers = @import("helpers.zig");

pub const CommandCtx = types.CommandCtx;

/// Dev subcommand enum
pub const DevSubcommand = enum {
    trace,
    profiler,
    console,
    errors,
    highlight,
    state,
    help,
};

/// Parse dev subcommand from positional args
fn parseSubcommand(positional: []const []const u8) ?DevSubcommand {
    if (positional.len == 0) return null;
    return std.meta.stringToEnum(DevSubcommand, positional[0]);
}

/// Main dev command dispatcher
pub fn dev(session: *cdp.Session, ctx: CommandCtx) !void {
    // Check for --help flag
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printDevHelp();
            return;
        }
    }

    const subcmd = parseSubcommand(ctx.positional) orelse {
        printDevUsage();
        return;
    };

    // Create subcontext with remaining positional args
    const sub_positional = if (ctx.positional.len > 1) ctx.positional[1..] else &[_][]const u8{};
    const sub_ctx = CommandCtx{
        .allocator = ctx.allocator,
        .io = ctx.io,
        .positional = sub_positional,
        .output = ctx.output,
        .full_page = ctx.full_page,
        .snap_interactive = ctx.snap_interactive,
        .snap_compact = ctx.snap_compact,
        .snap_depth = ctx.snap_depth,
        .snap_selector = ctx.snap_selector,
        .wait_text = ctx.wait_text,
        .wait_url = ctx.wait_url,
        .wait_load = ctx.wait_load,
        .wait_fn = ctx.wait_fn,
        .click_js = ctx.click_js,
    };

    switch (subcmd) {
        .trace => try trace(session, sub_ctx),
        .profiler => try profiler(session, sub_ctx),
        .console => try console(session, sub_ctx),
        .errors => try errors(session, sub_ctx),
        .highlight => try highlight(session, sub_ctx),
        .state => try state(session, sub_ctx),
        .help => printDevHelp(),
    }
}

// ─── Subcommand Implementations ─────────────────────────────────────────────

fn trace(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        printTraceHelp();
        return;
    }

    const action = ctx.positional[0];
    if (std.mem.eql(u8, action, "start")) {
        var tracing = cdp.Tracing.init(session);

        // Start tracing with default categories
        try tracing.start(.{
            .categories = "-*,devtools.timeline,v8.execute,disabled-by-default-devtools.timeline,disabled-by-default-devtools.timeline.frame,blink.console,blink.user_timing,latencyInfo,disabled-by-default-devtools.timeline.stack,disabled-by-default-v8.cpu_profiler",
            .transfer_mode = "ReturnAsStream",
        });

        std.debug.print("Trace recording started\n", .{});
        std.debug.print("Run 'zchrome dev trace stop [path]' to save the trace\n", .{});
    } else if (std.mem.eql(u8, action, "stop")) {
        const output_path = if (ctx.positional.len > 1) ctx.positional[1] else "trace.json";

        var tracing = cdp.Tracing.init(session);
        try tracing.end();

        // Note: In a full implementation, we would need to handle the Tracing.tracingComplete
        // event and stream the data. For now, we just signal that tracing has stopped.
        // The trace data is complex to collect synchronously.

        std.debug.print("Trace recording stopped\n", .{});
        std.debug.print("Note: Full trace streaming not yet implemented. Use Chrome DevTools for now.\n", .{});
        std.debug.print("Output path would be: {s}\n", .{output_path});
    } else if (std.mem.eql(u8, action, "categories")) {
        // List available trace categories
        var tracing = cdp.Tracing.init(session);
        const categories = try tracing.getCategories(ctx.allocator);
        defer {
            for (categories) |c| ctx.allocator.free(c);
            ctx.allocator.free(categories);
        }

        std.debug.print("Available trace categories:\n", .{});
        for (categories) |cat| {
            std.debug.print("  {s}\n", .{cat});
        }
    } else {
        printTraceHelp();
    }
}

fn profiler(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        printProfilerHelp();
        return;
    }

    const action = ctx.positional[0];

    // Check if it's a number (duration-based profiling)
    if (std.fmt.parseInt(u32, action, 10)) |duration_secs| {
        // Duration-based profiling: profile for N seconds then stop
        const output_path = if (ctx.positional.len > 1) ctx.positional[1] else "profile.cpuprofile";

        var prof = cdp.Profiler.init(session);
        try prof.enable();
        try prof.start();

        if (duration_secs == 0) {
            // Wait for user to press Enter
            std.debug.print("CPU profiler started. Press Enter to stop and save...\n", .{});
            waitForEnter(ctx.io);
        } else {
            std.debug.print("CPU profiler started. Recording for {} seconds...\n", .{duration_secs});
            waitForSeconds(duration_secs);
        }

        var profile = try prof.stop(ctx.allocator);
        defer profile.deinit(ctx.allocator);

        // Convert profile to Chrome DevTools compatible JSON
        const json_data = try profile.toJson(ctx.allocator);
        defer ctx.allocator.free(json_data);

        try helpers.writeFile(ctx.io, output_path, json_data);

        std.debug.print("CPU profile saved to {s}\n", .{output_path});
        std.debug.print("  Nodes: {}\n", .{profile.nodes.len});
        std.debug.print("  Duration: {d:.2}ms\n", .{(profile.end_time - profile.start_time) / 1000.0});
        std.debug.print("\nOpen in Chrome DevTools: Performance tab > Load profile\n", .{});
        return;
    } else |_| {}

    // start/stop commands (for interactive/REPL mode only)
    if (std.mem.eql(u8, action, "start")) {
        var prof = cdp.Profiler.init(session);
        try prof.enable();
        try prof.start();

        std.debug.print("CPU profiler started (REPL mode)\n", .{});
        std.debug.print("Use 'dev profiler stop [path]' to save the profile\n", .{});
        std.debug.print("\nNote: start/stop only works in interactive mode.\n", .{});
        std.debug.print("For CLI, use: zchrome dev profiler <seconds> [path]\n", .{});
    } else if (std.mem.eql(u8, action, "stop")) {
        const output_path = if (ctx.positional.len > 1) ctx.positional[1] else "profile.cpuprofile";

        var prof = cdp.Profiler.init(session);
        var profile = try prof.stop(ctx.allocator);
        defer profile.deinit(ctx.allocator);

        // Convert profile to Chrome DevTools compatible JSON
        const json_data = try profile.toJson(ctx.allocator);
        defer ctx.allocator.free(json_data);

        try helpers.writeFile(ctx.io, output_path, json_data);

        std.debug.print("CPU profile saved to {s}\n", .{output_path});
        std.debug.print("  Nodes: {}\n", .{profile.nodes.len});
        std.debug.print("  Duration: {d:.2}ms\n", .{(profile.end_time - profile.start_time) / 1000.0});
        std.debug.print("\nOpen in Chrome DevTools: Performance tab > Load profile\n", .{});
    } else {
        printProfilerHelp();
    }
}

/// Wait for user to press Enter
fn waitForEnter(io: std.Io) void {
    const stdin_file = std.Io.File.stdin();
    var buf: [16]u8 = undefined;
    var reader = stdin_file.readerStreaming(io, &buf);
    // Read until newline
    while (true) {
        const byte = reader.interface.takeByte() catch break;
        if (byte == '\n') break;
    }
}

/// Wait for N seconds using spinloop (Zig 0.16 compatible)
fn waitForSeconds(seconds: u32) void {
    // Empirically calibrated: ~20_000_000 iterations ≈ 1 second
    const iterations_per_second: u64 = 20_000_000;
    const total_iterations: u64 = @as(u64, seconds) * iterations_per_second;
    var i: u64 = 0;
    while (i < total_iterations) : (i += 1) {
        std.atomic.spinLoopHint();
    }
}

fn console(session: *cdp.Session, ctx: CommandCtx) !void {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // Check for --clear flag
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--clear")) {
            // Clear console using JS
            var result = try runtime.evaluate(ctx.allocator, "console.clear(); 'Console cleared'", .{ .return_by_value = true });
            defer result.deinit(ctx.allocator);
            std.debug.print("Console cleared\n", .{});
            return;
        }
    }

    // Get console messages using injected interceptor
    const js =
        \\(function() {
        \\  if (!window.__zchrome_console) {
        \\    window.__zchrome_console = [];
        \\    const orig = {};
        \\    ['log', 'warn', 'error', 'info', 'debug'].forEach(method => {
        \\      orig[method] = console[method];
        \\      console[method] = function(...args) {
        \\        window.__zchrome_console.push({
        \\          type: method,
        \\          message: args.map(a => typeof a === 'object' ? JSON.stringify(a) : String(a)).join(' '),
        \\          timestamp: Date.now()
        \\        });
        \\        orig[method].apply(console, args);
        \\      };
        \\    });
        \\  }
        \\  return JSON.stringify(window.__zchrome_console.slice(-50));
        \\})()
    ;

    var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
    defer result.deinit(ctx.allocator);

    const json_str = result.asString() orelse "[]";

    // Parse and display messages
    const parsed = std.json.parseFromSlice(std.json.Value, ctx.allocator, json_str, .{}) catch {
        std.debug.print("No console messages captured\n", .{});
        return;
    };
    defer parsed.deinit();

    if (parsed.value != .array or parsed.value.array.items.len == 0) {
        std.debug.print("No console messages captured\n", .{});
        return;
    }

    std.debug.print("Console Messages:\n", .{});
    std.debug.print("{s:-<60}\n", .{""});

    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const msg_type = if (item.object.get("type")) |v| (if (v == .string) v.string else "log") else "log";
        const message = if (item.object.get("message")) |v| (if (v == .string) v.string else "") else "";

        const type_color: []const u8 = if (std.mem.eql(u8, msg_type, "error"))
            "[ERR]"
        else if (std.mem.eql(u8, msg_type, "warn"))
            "[WRN]"
        else if (std.mem.eql(u8, msg_type, "info"))
            "[INF]"
        else
            "[LOG]";

        std.debug.print("{s} {s}\n", .{ type_color, message });
    }
}

fn errors(session: *cdp.Session, ctx: CommandCtx) !void {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // Check for --clear flag
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--clear")) {
            var result = try runtime.evaluate(ctx.allocator, "window.__zchrome_errors = []; 'Errors cleared'", .{ .return_by_value = true });
            defer result.deinit(ctx.allocator);
            std.debug.print("Errors cleared\n", .{});
            return;
        }
    }

    // Get errors using injected handler
    const js =
        \\(function() {
        \\  if (!window.__zchrome_errors) {
        \\    window.__zchrome_errors = [];
        \\    window.onerror = function(msg, url, line, col, error) {
        \\      window.__zchrome_errors.push({
        \\        message: msg,
        \\        url: url,
        \\        line: line,
        \\        column: col,
        \\        stack: error ? error.stack : null,
        \\        timestamp: Date.now()
        \\      });
        \\    };
        \\    window.addEventListener('unhandledrejection', function(e) {
        \\      window.__zchrome_errors.push({
        \\        message: 'Unhandled Promise rejection: ' + (e.reason ? e.reason.message || e.reason : 'Unknown'),
        \\        stack: e.reason ? e.reason.stack : null,
        \\        timestamp: Date.now()
        \\      });
        \\    });
        \\  }
        \\  return JSON.stringify(window.__zchrome_errors);
        \\})()
    ;

    var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
    defer result.deinit(ctx.allocator);

    const json_str = result.asString() orelse "[]";

    const parsed = std.json.parseFromSlice(std.json.Value, ctx.allocator, json_str, .{}) catch {
        std.debug.print("No errors captured\n", .{});
        return;
    };
    defer parsed.deinit();

    if (parsed.value != .array or parsed.value.array.items.len == 0) {
        std.debug.print("No errors captured\n", .{});
        return;
    }

    std.debug.print("Page Errors:\n", .{});
    std.debug.print("{s:-<60}\n", .{""});

    for (parsed.value.array.items, 0..) |item, i| {
        if (item != .object) continue;
        const message = if (item.object.get("message")) |v| (if (v == .string) v.string else "Unknown error") else "Unknown error";
        const url = if (item.object.get("url")) |v| (if (v == .string) v.string else "") else "";
        const line = if (item.object.get("line")) |v| (if (v == .integer) v.integer else 0) else 0;

        std.debug.print("\n[{}] {s}\n", .{ i + 1, message });
        if (url.len > 0) {
            std.debug.print("    at {s}:{}\n", .{ url, line });
        }
    }
}

fn highlight(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: dev highlight <selector>\n", .{});
        return;
    }

    const selector = ctx.positional[0];

    // Use DOM.highlightNode via JavaScript for now (Overlay domain requires more setup)
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // Build JS with selector directly embedded (escape braces for Zig fmt)
    const selector_escaped = try helpers.jsStringLiteral(ctx.allocator, selector);
    defer ctx.allocator.free(selector_escaped);

    // Build the full JS string with the selector embedded
    const js = try std.fmt.allocPrint(ctx.allocator,
        \\(function() {{
        \\  const el = document.querySelector({s});
        \\  if (!el) return 'Element not found';
        \\  const prev = document.getElementById('__zchrome_highlight');
        \\  if (prev) prev.remove();
        \\  const rect = el.getBoundingClientRect();
        \\  const highlight = document.createElement('div');
        \\  highlight.id = '__zchrome_highlight';
        \\  highlight.style.cssText = 'position:fixed;left:'+rect.left+'px;top:'+rect.top+'px;width:'+rect.width+'px;height:'+rect.height+'px;background:rgba(111,168,220,0.66);border:2px solid rgb(111,168,220);pointer-events:none;z-index:2147483647;box-sizing:border-box';
        \\  document.body.appendChild(highlight);
        \\  setTimeout(function() {{ highlight.remove(); }}, 3000);
        \\  return 'Highlighted: ' + el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') + (el.className ? '.' + el.className.split(' ').join('.') : '');
        \\}})()
    , .{selector_escaped});
    defer ctx.allocator.free(js);

    var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
    defer result.deinit(ctx.allocator);

    if (result.value) |v| {
        switch (v) {
            .string => |s| std.debug.print("{s}\n", .{s}),
            else => std.debug.print("Highlight applied\n", .{}),
        }
    }
}

fn state(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        printStateHelp();
        return;
    }

    const action = ctx.positional[0];
    if (std.mem.eql(u8, action, "save")) {
        if (ctx.positional.len < 2) {
            std.debug.print("Usage: dev state save <path>\n", .{});
            return;
        }
        try stateSave(session, ctx, ctx.positional[1]);
    } else if (std.mem.eql(u8, action, "load")) {
        if (ctx.positional.len < 2) {
            std.debug.print("Usage: dev state load <path>\n", .{});
            return;
        }
        try stateLoad(session, ctx, ctx.positional[1]);
    } else if (std.mem.eql(u8, action, "list")) {
        try stateList(ctx);
    } else if (std.mem.eql(u8, action, "show")) {
        if (ctx.positional.len < 2) {
            std.debug.print("Usage: dev state show <file>\n", .{});
            return;
        }
        try stateShow(ctx, ctx.positional[1]);
    } else if (std.mem.eql(u8, action, "rename")) {
        if (ctx.positional.len < 3) {
            std.debug.print("Usage: dev state rename <old> <new>\n", .{});
            return;
        }
        try stateRename(ctx, ctx.positional[1], ctx.positional[2]);
    } else if (std.mem.eql(u8, action, "clear")) {
        // Check for --all flag
        var clear_all = false;
        var specific_name: ?[]const u8 = null;
        for (ctx.positional[1..]) |arg| {
            if (std.mem.eql(u8, arg, "--all")) {
                clear_all = true;
            } else {
                specific_name = arg;
            }
        }
        try stateClear(ctx, clear_all, specific_name);
    } else if (std.mem.eql(u8, action, "clean")) {
        // Parse --older-than <days>
        var days: ?u32 = null;
        var i: usize = 1;
        while (i < ctx.positional.len) : (i += 1) {
            if (std.mem.eql(u8, ctx.positional[i], "--older-than") and i + 1 < ctx.positional.len) {
                days = std.fmt.parseInt(u32, ctx.positional[i + 1], 10) catch null;
                break;
            }
        }
        if (days) |d| {
            try stateClean(ctx, d);
        } else {
            std.debug.print("Usage: dev state clean --older-than <days>\n", .{});
        }
    } else {
        printStateHelp();
    }
}

/// Get the states directory path (alongside executable)
fn getStatesDir(allocator: std.mem.Allocator, io: std.Io) ![]const u8 {
    const exe_dir = std.process.executableDirPathAlloc(io, allocator) catch {
        return allocator.dupe(u8, "zchrome-states");
    };
    defer allocator.free(exe_dir);
    return std.fs.path.join(allocator, &.{ exe_dir, "zchrome-states" });
}

/// Ensure states directory exists
fn ensureStatesDir(allocator: std.mem.Allocator, io: std.Io) ![]const u8 {
    const states_dir = try getStatesDir(allocator, io);
    const dir = std.Io.Dir.cwd();
    const perms: std.Io.File.Permissions = @enumFromInt(0o755);
    dir.createDir(io, states_dir, perms) catch |err| {
        if (err != error.PathAlreadyExists) {
            std.debug.print("Warning: Could not create states directory: {}\n", .{err});
        }
    };
    return states_dir;
}

/// Save auth state (cookies + localStorage + sessionStorage)
fn stateSave(session: *cdp.Session, ctx: CommandCtx, path: []const u8) !void {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // Get current URL
    var url_result = try runtime.evaluate(ctx.allocator, "window.location.href", .{ .return_by_value = true });
    defer url_result.deinit(ctx.allocator);
    const origin = url_result.asString() orelse "unknown";

    // Get cookies via Storage domain
    var storage = cdp.Storage.init(session);
    const cookies = try storage.getCookies(ctx.allocator, null);
    defer {
        for (cookies) |*c| {
            var cookie = c.*;
            cookie.deinit(ctx.allocator);
        }
        ctx.allocator.free(cookies);
    }

    // Get localStorage
    var local_result = try runtime.evaluate(ctx.allocator, "JSON.stringify(Object.fromEntries(Object.keys(localStorage).map(k => [k, localStorage.getItem(k)])))", .{ .return_by_value = true });
    defer local_result.deinit(ctx.allocator);
    const local_storage = local_result.asString() orelse "{}";

    // Get sessionStorage
    var session_result = try runtime.evaluate(ctx.allocator, "JSON.stringify(Object.fromEntries(Object.keys(sessionStorage).map(k => [k, sessionStorage.getItem(k)])))", .{ .return_by_value = true });
    defer session_result.deinit(ctx.allocator);
    const session_storage = session_result.asString() orelse "{}";

    // Build JSON state file
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(ctx.allocator);

    try json_buf.appendSlice(ctx.allocator, "{\n  \"version\": 1,\n  \"origin\": \"");
    try json_buf.appendSlice(ctx.allocator, origin);
    try json_buf.appendSlice(ctx.allocator, "\",\n  \"cookies\": [");

    for (cookies, 0..) |cookie, i| {
        if (i > 0) try json_buf.appendSlice(ctx.allocator, ",");
        try json_buf.appendSlice(ctx.allocator, "\n    {\"name\": \"");
        try json_buf.appendSlice(ctx.allocator, cookie.name);
        try json_buf.appendSlice(ctx.allocator, "\", \"value\": \"");
        // Escape cookie value
        for (cookie.value) |c| {
            switch (c) {
                '"' => try json_buf.appendSlice(ctx.allocator, "\\\""),
                '\\' => try json_buf.appendSlice(ctx.allocator, "\\\\"),
                '\n' => try json_buf.appendSlice(ctx.allocator, "\\n"),
                '\r' => try json_buf.appendSlice(ctx.allocator, "\\r"),
                else => try json_buf.append(ctx.allocator, c),
            }
        }
        try json_buf.appendSlice(ctx.allocator, "\", \"domain\": \"");
        try json_buf.appendSlice(ctx.allocator, cookie.domain);
        try json_buf.appendSlice(ctx.allocator, "\", \"path\": \"");
        try json_buf.appendSlice(ctx.allocator, cookie.path);
        const cookie_rest = try std.fmt.allocPrint(ctx.allocator, "\", \"expires\": {d}, \"httpOnly\": {}, \"secure\": {}}}", .{ cookie.expires, cookie.http_only, cookie.secure });
        defer ctx.allocator.free(cookie_rest);
        try json_buf.appendSlice(ctx.allocator, cookie_rest);
    }

    try json_buf.appendSlice(ctx.allocator, "\n  ],\n  \"localStorage\": ");
    try json_buf.appendSlice(ctx.allocator, local_storage);
    try json_buf.appendSlice(ctx.allocator, ",\n  \"sessionStorage\": ");
    try json_buf.appendSlice(ctx.allocator, session_storage);
    try json_buf.appendSlice(ctx.allocator, "\n}\n");

    // Determine filename (strip any directory components for portability)
    const filename = std.fs.path.basename(path);
    const filename_with_ext = if (std.mem.endsWith(u8, filename, ".json")) filename else blk: {
        const with_ext = try std.fmt.allocPrint(ctx.allocator, "{s}.json", .{filename});
        break :blk with_ext;
    };
    defer if (!std.mem.endsWith(u8, filename, ".json")) ctx.allocator.free(filename_with_ext);

    // Save to zchrome-states directory (alongside executable)
    const states_dir = try ensureStatesDir(ctx.allocator, ctx.io);
    defer ctx.allocator.free(states_dir);
    const output_path = try std.fs.path.join(ctx.allocator, &.{ states_dir, filename_with_ext });
    defer ctx.allocator.free(output_path);

    try helpers.writeFile(ctx.io, output_path, json_buf.items);
    std.debug.print("State saved to {s}\n", .{output_path});
    std.debug.print("  Origin: {s}\n", .{origin});
    std.debug.print("  Cookies: {}\n", .{cookies.len});
}

/// Load auth state from file
fn stateLoad(session: *cdp.Session, ctx: CommandCtx, path: []const u8) !void {
    const dir = std.Io.Dir.cwd();

    // Try zchrome-states directory first, then fall back to provided path
    const filename = std.fs.path.basename(path);
    const states_dir = getStatesDir(ctx.allocator, ctx.io) catch path;
    const states_path = std.fs.path.join(ctx.allocator, &.{ states_dir, filename }) catch path;
    defer if (states_path.ptr != path.ptr) ctx.allocator.free(states_path);
    defer if (states_dir.ptr != path.ptr) ctx.allocator.free(states_dir);

    // Try states directory first, then fall back to provided path
    const content = dir.readFileAlloc(ctx.io, states_path, ctx.allocator, std.Io.Limit.limited(10 * 1024 * 1024)) catch blk: {
        break :blk dir.readFileAlloc(ctx.io, path, ctx.allocator, std.Io.Limit.limited(10 * 1024 * 1024)) catch |err| {
            std.debug.print("Error reading state file {s}: {}\n", .{ path, err });
            return;
        };
    };
    defer ctx.allocator.free(content);

    const parsed = std.json.parseFromSlice(std.json.Value, ctx.allocator, content, .{}) catch |err| {
        std.debug.print("Error parsing state file: {}\n", .{err});
        return;
    };
    defer parsed.deinit();

    if (parsed.value != .object) {
        std.debug.print("Error: state file must contain a JSON object\n", .{});
        return;
    }

    // Load cookies
    if (parsed.value.object.get("cookies")) |cookies_val| {
        if (cookies_val == .array) {
            var storage = cdp.Storage.init(session);

            // Build cookie params
            var cookie_params: std.ArrayList(cdp.CookieParam) = .empty;
            defer cookie_params.deinit(ctx.allocator);

            for (cookies_val.array.items) |c| {
                if (c != .object) continue;
                const name = if (c.object.get("name")) |v| (if (v == .string) v.string else continue) else continue;
                const value = if (c.object.get("value")) |v| (if (v == .string) v.string else "") else "";
                const domain = if (c.object.get("domain")) |v| (if (v == .string) v.string else null) else null;
                const cookie_path = if (c.object.get("path")) |v| (if (v == .string) v.string else null) else null;
                const http_only = if (c.object.get("httpOnly")) |v| (if (v == .bool) v.bool else null) else null;
                const secure = if (c.object.get("secure")) |v| (if (v == .bool) v.bool else null) else null;
                const expires = if (c.object.get("expires")) |v| (if (v == .float) v.float else if (v == .integer) @as(f64, @floatFromInt(v.integer)) else null) else null;

                try cookie_params.append(ctx.allocator, .{
                    .name = name,
                    .value = value,
                    .domain = domain,
                    .path = cookie_path,
                    .http_only = http_only,
                    .secure = secure,
                    .expires = expires,
                });
            }

            if (cookie_params.items.len > 0) {
                try storage.setCookies(cookie_params.items);
                std.debug.print("Loaded {} cookies\n", .{cookie_params.items.len});
            }
        }
    }

    // Load localStorage
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    if (parsed.value.object.get("localStorage")) |local_val| {
        if (local_val == .object) {
            var count: usize = 0;
            var it = local_val.object.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.* != .string) continue;
                const key_lit = try helpers.jsStringLiteral(ctx.allocator, entry.key_ptr.*);
                defer ctx.allocator.free(key_lit);
                const val_lit = try helpers.jsStringLiteral(ctx.allocator, entry.value_ptr.*.string);
                defer ctx.allocator.free(val_lit);
                const js = try std.fmt.allocPrint(ctx.allocator, "localStorage.setItem({s}, {s})", .{ key_lit, val_lit });
                defer ctx.allocator.free(js);
                var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
                result.deinit(ctx.allocator);
                count += 1;
            }
            if (count > 0) {
                std.debug.print("Loaded {} localStorage entries\n", .{count});
            }
        }
    }

    // Load sessionStorage
    if (parsed.value.object.get("sessionStorage")) |session_val| {
        if (session_val == .object) {
            var count: usize = 0;
            var it = session_val.object.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.* != .string) continue;
                const key_lit = try helpers.jsStringLiteral(ctx.allocator, entry.key_ptr.*);
                defer ctx.allocator.free(key_lit);
                const val_lit = try helpers.jsStringLiteral(ctx.allocator, entry.value_ptr.*.string);
                defer ctx.allocator.free(val_lit);
                const js = try std.fmt.allocPrint(ctx.allocator, "sessionStorage.setItem({s}, {s})", .{ key_lit, val_lit });
                defer ctx.allocator.free(js);
                var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
                result.deinit(ctx.allocator);
                count += 1;
            }
            if (count > 0) {
                std.debug.print("Loaded {} sessionStorage entries\n", .{count});
            }
        }
    }

    std.debug.print("State loaded from {s}\n", .{path});
}

/// List saved state files
fn stateList(ctx: CommandCtx) !void {
    const states_dir = try getStatesDir(ctx.allocator, ctx.io);
    defer ctx.allocator.free(states_dir);

    const dir = std.Io.Dir.openDirAbsolute(ctx.io, states_dir, .{ .iterate = true }) catch {
        std.debug.print("No saved states found\n", .{});
        return;
    };

    std.debug.print("Saved states in {s}:\n", .{states_dir});
    std.debug.print("{s:-<50}\n", .{""});

    var count: usize = 0;
    var iter = dir.iterate();
    while (try iter.next(ctx.io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".json")) continue;

        std.debug.print("  {s}\n", .{entry.name});
        count += 1;
    }

    if (count == 0) {
        std.debug.print("  (no state files found)\n", .{});
    } else {
        std.debug.print("\nTotal: {} state file(s)\n", .{count});
    }
}

/// Show state file summary
fn stateShow(ctx: CommandCtx, path: []const u8) !void {
    const dir = std.Io.Dir.cwd();

    // Try zchrome-states directory first, then fall back to provided path
    const filename = std.fs.path.basename(path);
    const states_dir = getStatesDir(ctx.allocator, ctx.io) catch path;
    const states_path = std.fs.path.join(ctx.allocator, &.{ states_dir, filename }) catch path;
    defer if (states_path.ptr != path.ptr) ctx.allocator.free(states_path);
    defer if (states_dir.ptr != path.ptr) ctx.allocator.free(states_dir);

    // Try states directory first
    const content = dir.readFileAlloc(ctx.io, states_path, ctx.allocator, std.Io.Limit.limited(10 * 1024 * 1024)) catch blk: {
        // Fall back to provided path
        break :blk dir.readFileAlloc(ctx.io, path, ctx.allocator, std.Io.Limit.limited(10 * 1024 * 1024)) catch |err| {
            std.debug.print("Error reading state file {s}: {}\n", .{ path, err });
            return;
        };
    };
    defer ctx.allocator.free(content);

    const parsed = std.json.parseFromSlice(std.json.Value, ctx.allocator, content, .{}) catch |err| {
        std.debug.print("Error parsing state file: {}\n", .{err});
        return;
    };
    defer parsed.deinit();

    std.debug.print("State file: {s}\n", .{path});
    std.debug.print("{s:-<50}\n", .{""});

    if (parsed.value.object.get("origin")) |v| {
        if (v == .string) std.debug.print("Origin: {s}\n", .{v.string});
    }

    if (parsed.value.object.get("cookies")) |v| {
        if (v == .array) std.debug.print("Cookies: {}\n", .{v.array.items.len});
    }

    if (parsed.value.object.get("localStorage")) |v| {
        if (v == .object) std.debug.print("localStorage entries: {}\n", .{v.object.count()});
    }

    if (parsed.value.object.get("sessionStorage")) |v| {
        if (v == .object) std.debug.print("sessionStorage entries: {}\n", .{v.object.count()});
    }
}

/// Rename state file
fn stateRename(ctx: CommandCtx, old_name: []const u8, new_name: []const u8) !void {
    const states_dir = try getStatesDir(ctx.allocator, ctx.io);
    defer ctx.allocator.free(states_dir);

    // Use basenames only and ensure .json extension
    const old_base = std.fs.path.basename(old_name);
    const new_base = std.fs.path.basename(new_name);
    const old_filename = if (std.mem.endsWith(u8, old_base, ".json")) old_base else blk: {
        break :blk try std.fmt.allocPrint(ctx.allocator, "{s}.json", .{old_base});
    };
    defer if (!std.mem.endsWith(u8, old_base, ".json")) ctx.allocator.free(old_filename);
    const new_filename = if (std.mem.endsWith(u8, new_base, ".json")) new_base else blk: {
        break :blk try std.fmt.allocPrint(ctx.allocator, "{s}.json", .{new_base});
    };
    defer if (!std.mem.endsWith(u8, new_base, ".json")) ctx.allocator.free(new_filename);

    const old_path = try std.fs.path.join(ctx.allocator, &.{ states_dir, old_filename });
    defer ctx.allocator.free(old_path);
    const new_path = try std.fs.path.join(ctx.allocator, &.{ states_dir, new_filename });
    defer ctx.allocator.free(new_path);

    const dir = std.Io.Dir.cwd();
    dir.rename(old_path, dir, new_path, ctx.io) catch |err| {
        std.debug.print("Error renaming {s} to {s}: {}\n", .{ old_filename, new_filename, err });
        return;
    };
    std.debug.print("Renamed {s} to {s}\n", .{ old_filename, new_filename });
}

/// Clear state files
fn stateClear(ctx: CommandCtx, clear_all: bool, specific_name: ?[]const u8) !void {
    if (clear_all) {
        const states_dir = try getStatesDir(ctx.allocator, ctx.io);
        defer ctx.allocator.free(states_dir);

        const dir = std.Io.Dir.openDirAbsolute(ctx.io, states_dir, .{ .iterate = true }) catch {
            std.debug.print("No saved states to clear\n", .{});
            return;
        };

        var count: usize = 0;
        var iter = dir.iterate();
        while (try iter.next(ctx.io)) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".json")) continue;

            dir.deleteFile(ctx.io, entry.name) catch continue;
            count += 1;
        }

        std.debug.print("Cleared {} state file(s)\n", .{count});
    } else if (specific_name) |name| {
        const states_dir = try getStatesDir(ctx.allocator, ctx.io);
        defer ctx.allocator.free(states_dir);

        // Use basename and ensure .json extension
        const base = std.fs.path.basename(name);
        const filename = if (std.mem.endsWith(u8, base, ".json")) base else blk: {
            break :blk try std.fmt.allocPrint(ctx.allocator, "{s}.json", .{base});
        };
        defer if (!std.mem.endsWith(u8, base, ".json")) ctx.allocator.free(filename);

        const full_path = try std.fs.path.join(ctx.allocator, &.{ states_dir, filename });
        defer ctx.allocator.free(full_path);

        const dir = std.Io.Dir.cwd();
        dir.deleteFile(ctx.io, full_path) catch |err| {
            std.debug.print("Error deleting {s}: {}\n", .{ filename, err });
            return;
        };
        std.debug.print("Deleted {s}\n", .{filename});
    } else {
        std.debug.print("Usage: dev state clear [name] or dev state clear --all\n", .{});
    }
}

/// Clean old state files
fn stateClean(ctx: CommandCtx, days: u32) !void {
    const states_dir = try getStatesDir(ctx.allocator, ctx.io);
    defer ctx.allocator.free(states_dir);

    std.debug.print("Cleaning states older than {} days in {s}\n", .{ days, states_dir });
    std.debug.print("Note: Age-based cleanup not yet implemented\n", .{});
}

// ─── Help Functions ─────────────────────────────────────────────────────────

fn printDevUsage() void {
    std.debug.print(
        \\Usage: zchrome dev <subcommand> [args...]
        \\
        \\Run 'zchrome dev --help' for more information.
        \\
    , .{});
}

pub fn printDevHelp() void {
    std.debug.print(
        \\Usage: zchrome dev <subcommand> [args...]
        \\
        \\Developer tools and debugging commands.
        \\
        \\Subcommands:
        \\  trace       Start/stop trace recording
        \\  profiler    Start/stop Chrome DevTools profiling
        \\  console     View/clear console messages
        \\  errors      View/clear page errors
        \\  highlight   Highlight DOM elements
        \\  state       Manage auth state (save/load/list)
        \\
        \\Examples:
        \\  zchrome dev console              # View console messages
        \\  zchrome dev console --clear      # Clear console
        \\  zchrome dev errors               # View page errors
        \\  zchrome dev highlight "#login"   # Highlight element
        \\  zchrome dev state save auth.json # Save auth state
        \\  zchrome dev trace start          # Start trace recording
        \\
    , .{});
}

fn printTraceHelp() void {
    std.debug.print(
        \\Usage: zchrome dev trace <start|stop> [path]
        \\
        \\Record Chrome trace for performance analysis.
        \\
        \\Commands:
        \\  start [path]   Start recording trace
        \\  stop [path]    Stop and save trace to file
        \\
        \\Examples:
        \\  zchrome dev trace start
        \\  zchrome dev trace stop trace.json
        \\
    , .{});
}

fn printProfilerHelp() void {
    std.debug.print(
        \\Usage: zchrome dev profiler <seconds> [path]
        \\       zchrome dev profiler <start|stop> [path]  (REPL only)
        \\
        \\Record CPU profile for Chrome DevTools.
        \\
        \\CLI Usage (recommended):
        \\  <seconds> [path]   Profile for N seconds, then save
        \\                     Use 0 to profile until Enter is pressed
        \\
        \\REPL Usage (interactive mode only):
        \\  start              Start profiling
        \\  stop [path]        Stop and save profile (.cpuprofile)
        \\
        \\Examples:
        \\  zchrome dev profiler 10 profile.cpuprofile   # Profile for 10 seconds
        \\  zchrome dev profiler 0 profile.cpuprofile    # Profile until Enter
        \\
        \\  # In interactive mode:
        \\  zchrome> dev profiler start
        \\  zchrome> dev profiler stop profile.cpuprofile
        \\
    , .{});
}

fn printStateHelp() void {
    std.debug.print(
        \\Usage: zchrome dev state <command> [args...]
        \\
        \\Manage authentication state (cookies, storage).
        \\
        \\Commands:
        \\  save <path>           Save auth state to file
        \\  load <path>           Load auth state from file
        \\  list                  List saved state files
        \\  show <file>           Show state file summary
        \\  rename <old> <new>    Rename state file
        \\  clear [name]          Clear states (or specific state)
        \\  clear --all           Clear all saved states
        \\  clean --older-than N  Delete states older than N days
        \\
        \\Examples:
        \\  zchrome dev state save login.json
        \\  zchrome dev state load login.json
        \\  zchrome dev state list
        \\
    , .{});
}
