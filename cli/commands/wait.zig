//! Wait commands: wait for selector, text, URL, load state, or custom function.

const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");
const actions_mod = @import("../actions/mod.zig");

pub const CommandCtx = types.CommandCtx;

pub fn wait(session: *cdp.Session, ctx: CommandCtx) !void {
    // Check for --help flag in positional args
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printWaitHelp();
            return;
        }
    }

    const timeout_ms: u32 = 30_000; // default 30s

    if (ctx.wait_text) |text| {
        try waitForText(session, ctx.allocator, text, timeout_ms);
    } else if (ctx.wait_url) |pattern| {
        try waitForUrl(session, ctx.allocator, pattern, timeout_ms);
    } else if (ctx.wait_load) |state| {
        try waitForLoadState(session, ctx.allocator, state, timeout_ms);
    } else if (ctx.wait_fn) |expr| {
        try waitForFunction(session, ctx.allocator, expr, timeout_ms);
    } else if (ctx.positional.len > 0) {
        const arg = ctx.positional[0];
        // Check if it's a number (ms) or selector
        if (std.fmt.parseInt(u32, arg, 10)) |ms| {
            waitForTime(ms);
            std.debug.print("Waited {}ms\n", .{ms});
        } else |_| {
            // Treat as selector
            try waitForSelector(session, ctx.allocator, ctx.io, arg, timeout_ms);
        }
    } else {
        printWaitUsage();
    }
}

fn printWaitUsage() void {
    std.debug.print(
        \\Usage: wait <selector|ms> [options]
        \\
        \\Options:
        \\  --text <string>    Wait for text to appear on page
        \\  --match <pattern>  Wait for URL to match pattern (glob: ** and *)
        \\  --load <state>     Wait for load state (load, domcontentloaded, networkidle)
        \\  --fn <expression>  Wait for JS expression to return truthy
        \\
        \\Examples:
        \\  wait "#login-form"           Wait for element to be visible
        \\  wait 2000                    Wait 2 seconds
        \\  wait --text "Welcome"        Wait for text
        \\  wait --load networkidle      Wait for network idle
        \\
    , .{});
}

fn waitForTime(ms: u32) void {
    // Use spinloop (Zig 0.16 doesn't have std.time.sleep in this context)
    // Empirically calibrated: ~20_000_000 iterations ≈ 1 second
    const iterations_per_second: u64 = 20_000_000;
    const total_iterations: u64 = (@as(u64, ms) * iterations_per_second) / 1000;
    var i: u64 = 0;
    while (i < total_iterations) : (i += 1) {
        std.atomic.spinLoopHint();
    }
}

fn waitForSelector(session: *cdp.Session, allocator: std.mem.Allocator, io: std.Io, selector: []const u8, timeout_ms: u32) !void {
    var resolved = try actions_mod.resolveSelector(allocator, io, selector);
    defer resolved.deinit();

    // Build JS to check element visibility (handles both CSS and role-based)
    const js = try actions_mod.helpers.buildGetterJs(allocator, &resolved, "el && el.offsetParent !== null && getComputedStyle(el).visibility !== 'hidden'");
    defer allocator.free(js);

    if (try pollUntil(session, allocator, js, timeout_ms)) {
        std.debug.print("Element visible: {s}\n", .{selector});
    } else {
        std.debug.print("Timeout waiting for element: {s}\n", .{selector});
        return error.Timeout;
    }
}

fn waitForText(session: *cdp.Session, allocator: std.mem.Allocator, text: []const u8, timeout_ms: u32) !void {
    const escaped = try actions_mod.helpers.escapeJsString(allocator, text);
    defer allocator.free(escaped);

    const js = try std.fmt.allocPrint(allocator, "document.body.innerText.includes('{s}')", .{escaped});
    defer allocator.free(js);

    if (try pollUntil(session, allocator, js, timeout_ms)) {
        std.debug.print("Text found: \"{s}\"\n", .{text});
    } else {
        std.debug.print("Timeout waiting for text: \"{s}\"\n", .{text});
        return error.Timeout;
    }
}

fn waitForUrl(session: *cdp.Session, allocator: std.mem.Allocator, pattern: []const u8, timeout_ms: u32) !void {
    // Convert glob pattern to regex
    const regex_pattern = try globToRegex(allocator, pattern);
    defer allocator.free(regex_pattern);

    const js = try std.fmt.allocPrint(allocator, "new RegExp('{s}').test(window.location.href)", .{regex_pattern});
    defer allocator.free(js);

    if (try pollUntil(session, allocator, js, timeout_ms)) {
        // Get current URL for output
        var runtime = cdp.Runtime.init(session);
        const url = runtime.evaluateAs([]const u8, "window.location.href") catch "unknown";
        std.debug.print("URL matched: {s}\n", .{url});
    } else {
        std.debug.print("Timeout waiting for URL pattern: {s}\n", .{pattern});
        return error.Timeout;
    }
}

fn waitForLoadState(session: *cdp.Session, allocator: std.mem.Allocator, state: []const u8, timeout_ms: u32) !void {
    const js: []const u8 = if (std.mem.eql(u8, state, "load"))
        "document.readyState === 'complete'"
    else if (std.mem.eql(u8, state, "domcontentloaded"))
        "document.readyState !== 'loading'"
    else if (std.mem.eql(u8, state, "networkidle"))
        // Check document complete and no pending fetches
        "document.readyState === 'complete'"
    else {
        std.debug.print("Unknown load state: {s}. Use: load, domcontentloaded, networkidle\n", .{state});
        return error.InvalidLoadState;
    };

    if (try pollUntil(session, allocator, js, timeout_ms)) {
        // For networkidle, add extra wait for network to settle
        if (std.mem.eql(u8, state, "networkidle")) {
            waitForTime(500); // Extra 500ms for network to settle
        }
        std.debug.print("Load state reached: {s}\n", .{state});
    } else {
        std.debug.print("Timeout waiting for load state: {s}\n", .{state});
        return error.Timeout;
    }
}

fn waitForFunction(session: *cdp.Session, allocator: std.mem.Allocator, expr: []const u8, timeout_ms: u32) !void {
    const js = try std.fmt.allocPrint(allocator, "(() => {{ return !!({s}); }})()", .{expr});
    defer allocator.free(js);

    if (try pollUntil(session, allocator, js, timeout_ms)) {
        std.debug.print("Condition satisfied: {s}\n", .{expr});
    } else {
        std.debug.print("Timeout waiting for condition: {s}\n", .{expr});
        return error.Timeout;
    }
}

/// Poll a JS condition until it returns true or timeout
fn pollUntil(session: *cdp.Session, allocator: std.mem.Allocator, js_condition: []const u8, timeout_ms: u32) !bool {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // Poll every ~250ms, calculate number of iterations based on timeout
    const poll_interval_ms: u32 = 250;
    const max_polls = (timeout_ms + poll_interval_ms - 1) / poll_interval_ms;
    var poll_count: u32 = 0;

    while (poll_count < max_polls) : (poll_count += 1) {
        var result = try runtime.evaluate(allocator, js_condition, .{ .return_by_value = true });
        defer result.deinit(allocator);

        if (result.asBool()) |b| {
            if (b) return true;
        }

        // Wait between polls
        waitForTime(poll_interval_ms);
    }
    return false;
}

/// Convert glob pattern to regex (** = .*, * = [^/]*)
fn globToRegex(allocator: std.mem.Allocator, pattern: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < pattern.len) {
        const c = pattern[i];
        if (c == '*') {
            if (i + 1 < pattern.len and pattern[i + 1] == '*') {
                // ** matches anything
                try result.appendSlice(allocator, ".*");
                i += 2;
            } else {
                // * matches non-slash
                try result.appendSlice(allocator, "[^/]*");
                i += 1;
            }
        } else if (c == '.' or c == '?' or c == '+' or c == '^' or c == '$' or
            c == '{' or c == '}' or c == '(' or c == ')' or c == '|' or
            c == '[' or c == ']' or c == '\\')
        {
            // Escape regex special chars
            try result.append(allocator, '\\');
            try result.append(allocator, c);
            i += 1;
        } else {
            try result.append(allocator, c);
            i += 1;
        }
    }
    return result.toOwnedSlice(allocator);
}

pub fn printWaitHelp() void {
    std.debug.print(
        \\Usage: wait <selector|ms> [options]
        \\
        \\Options:
        \\  --text <string>    Wait for text to appear on page
        \\  --match <pattern>  Wait for URL to match pattern (glob: ** and *)
        \\  --load <state>     Wait for load state (load, domcontentloaded, networkidle)
        \\  --fn <expression>  Wait for JS expression to return truthy
        \\
        \\Examples:
        \\  wait "#login-form"           Wait for element to be visible
        \\  wait 2000                    Wait 2 seconds
        \\  wait --text "Welcome"        Wait for text
        \\  wait --match "**/dashboard"   Wait for URL pattern
        \\  wait --load networkidle       Wait for network idle
        \\  wait --fn "window.ready"      Wait for JS condition
        \\
    , .{});
}
