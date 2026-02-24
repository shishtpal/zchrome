//! Network routing and request tracking commands.
//!
//! Uses the CDP Fetch domain to intercept, mock, or block network requests.
//! Subcommands: route, unroute, requests.

const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");

pub const CommandCtx = types.CommandCtx;

pub fn network(session: *cdp.Session, ctx: CommandCtx) !void {
    // Check for --help flag
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printNetworkHelp();
            return;
        }
    }

    const args = ctx.positional;

    if (args.len == 0) {
        printNetworkUsage();
        return;
    }

    if (std.mem.eql(u8, args[0], "route")) {
        try routeCmd(session, ctx);
    } else if (std.mem.eql(u8, args[0], "unroute")) {
        try unrouteCmd(session, ctx);
    } else if (std.mem.eql(u8, args[0], "requests")) {
        try requestsCmd(session, ctx);
    } else {
        std.debug.print("Unknown network subcommand: {s}\n", .{args[0]});
        printNetworkUsage();
    }
}

// ─── route ──────────────────────────────────────────────────────────────────

fn routeCmd(session: *cdp.Session, ctx: CommandCtx) !void {
    const args = ctx.positional;
    // args[0] == "route", args[1] == url_pattern, rest are flags
    if (args.len < 2) {
        std.debug.print("Usage: network route <url-pattern> [--abort] [--body <json>] [--file <path>] [--redirect <url>]\n", .{});
        return;
    }

    const url_pattern = args[1];

    // Parse flags from positional[2..]
    var abort = false;
    var mock_body: ?[]const u8 = null;
    var file_body: ?[]const u8 = null;
    var redirect_target: ?[]const u8 = null;
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--abort")) {
            abort = true;
        } else if (std.mem.eql(u8, args[i], "--body")) {
            i += 1;
            if (i < args.len) {
                mock_body = args[i];
            } else {
                std.debug.print("Error: --body requires a value\n", .{});
                return;
            }
        } else if (std.mem.eql(u8, args[i], "--file")) {
            i += 1;
            if (i < args.len) {
                const path = args[i];
                const dir = std.Io.Dir.cwd();
                const content = dir.readFileAlloc(ctx.io, path, ctx.allocator, std.Io.Limit.limited(10 * 1024 * 1024)) catch |err| {
                    std.debug.print("Error reading file '{s}': {}\n", .{ path, err });
                    return;
                };
                file_body = content;
            } else {
                std.debug.print("Error: --file requires a file path\n", .{});
                return;
            }
        } else if (std.mem.eql(u8, args[i], "--redirect")) {
            i += 1;
            if (i < args.len) {
                redirect_target = args[i];
            } else {
                std.debug.print("Error: --redirect requires a target URL (e.g. http://localhost:3000)\n", .{});
                return;
            }
        }
    }

    // --file provides mock body from file contents
    if (file_body) |fb| {
        if (mock_body != null) {
            std.debug.print("Error: --body and --file cannot be used together\n", .{});
            return;
        }
        mock_body = fb;
    }

    // Enable Fetch domain with the requested pattern
    _ = try session.sendCommand("Fetch.enable", .{
        .patterns = &[_]struct { urlPattern: []const u8, requestStage: []const u8 }{
            .{ .urlPattern = url_pattern, .requestStage = "Request" },
        },
    });

    if (abort) {
        std.debug.print("Route added: {s} (abort)\n", .{url_pattern});
        std.debug.print("Waiting for requests... (Ctrl+C to stop)\n", .{});
        try interceptLoop(session, .abort, null, null);
    } else if (mock_body) |body| {
        std.debug.print("Route added: {s} (mock response)\n", .{url_pattern});
        std.debug.print("Waiting for requests... (Ctrl+C to stop)\n", .{});
        try interceptLoop(session, .mock, body, null);
    } else if (redirect_target) |target| {
        std.debug.print("Route added: {s} (redirect → {s})\n", .{ url_pattern, target });
        std.debug.print("Waiting for requests... (Ctrl+C to stop)\n", .{});
        try interceptLoop(session, .redirect, null, target);
    } else {
        std.debug.print("Route added: {s} (continue/log)\n", .{url_pattern});
        std.debug.print("Waiting for requests... (Ctrl+C to stop)\n", .{});
        try interceptLoop(session, .continue_req, null, null);
    }
}

const InterceptAction = enum { abort, mock, continue_req, redirect };

fn interceptLoop(session: *cdp.Session, action: InterceptAction, mock_body: ?[]const u8, redirect_target: ?[]const u8) !void {
    // Read events from the WebSocket and handle Fetch.requestPaused events
    var count: u32 = 0;
    const max_events: u32 = 10000;

    while (count < max_events) : (count += 1) {
        // Read raw WebSocket message
        var msg = session.connection.websocket.receiveMessage() catch |err| {
            std.debug.print("Connection error: {}\n", .{err});
            return;
        };
        defer msg.deinit(session.connection.allocator);

        // Parse JSON
        const parsed = std.json.parseFromSlice(
            std.json.Value,
            session.connection.allocator,
            msg.data,
            .{},
        ) catch continue;
        defer parsed.deinit();

        // Check if this is a Fetch.requestPaused event
        const method_val = parsed.value.object.get("method") orelse continue;
        if (method_val != .string) continue;
        if (!std.mem.eql(u8, method_val.string, "Fetch.requestPaused")) continue;

        const params_val = parsed.value.object.get("params") orelse continue;
        if (params_val != .object) continue;

        const request_id = blk: {
            const rid = params_val.object.get("requestId") orelse continue;
            if (rid != .string) continue;
            break :blk rid.string;
        };

        // Extract request URL for logging
        const request_url = if (params_val.object.get("request")) |req| blk: {
            if (req == .object) {
                if (req.object.get("url")) |u| {
                    if (u == .string) break :blk u.string;
                }
            }
            break :blk "(unknown)";
        } else "(unknown)";

        switch (action) {
            .abort => {
                std.debug.print("  BLOCKED: {s}\n", .{request_url});
                _ = try session.sendCommand("Fetch.failRequest", .{
                    .requestId = request_id,
                    .errorReason = "BlockedByClient",
                });
            },
            .mock => {
                const body = mock_body orelse "{}";
                std.debug.print("  MOCKED: {s}\n", .{request_url});
                // CDP requires body to be base64-encoded
                const encoded_body = try cdp.base64.encodeAlloc(session.connection.allocator, body);
                defer session.connection.allocator.free(encoded_body);
                _ = try session.sendCommand("Fetch.fulfillRequest", .{
                    .requestId = request_id,
                    .responseCode = @as(i32, 200),
                    .responseHeaders = &[_]struct { name: []const u8, value: []const u8 }{
                        .{ .name = "Content-Type", .value = "application/json" },
                    },
                    .body = encoded_body,
                });
            },
            .redirect => {
                const target = redirect_target orelse continue;
                // Replace the origin of the request URL with the redirect target.
                // e.g. https://prod.example.com/api/users → http://localhost:3000/api/users
                const new_url = rewriteUrl(session.connection.allocator, request_url, target) catch |err| {
                    std.debug.print("  ERROR rewriting URL: {}\n", .{err});
                    _ = try session.sendCommand("Fetch.continueRequest", .{
                        .requestId = request_id,
                    });
                    continue;
                };
                defer session.connection.allocator.free(new_url);
                std.debug.print("  REDIRECT: {s} => {s}\n", .{ request_url, new_url });
                _ = try session.sendCommand("Fetch.continueRequest", .{
                    .requestId = request_id,
                    .url = new_url,
                });
            },
            .continue_req => {
                std.debug.print("  INTERCEPTED: {s}\n", .{request_url});
                _ = try session.sendCommand("Fetch.continueRequest", .{
                    .requestId = request_id,
                });
            },
        }
    }
}

/// Rewrite a URL by replacing its origin with the redirect target.
/// "https://prod.example.com/api/users?q=1" + "http://localhost:3000"
///  → "http://localhost:3000/api/users?q=1"
///
/// If the target includes a base path (e.g. "http://localhost:3000/v2"),
/// it is prepended to the original path:
///  → "http://localhost:3000/v2/api/users?q=1"
fn rewriteUrl(allocator: std.mem.Allocator, url: []const u8, target: []const u8) ![]const u8 {
    // Find the path portion of the original URL (after scheme://host[:port])
    const path = blk: {
        // Skip scheme (e.g. "https://")
        const after_scheme = if (std.mem.indexOf(u8, url, "://")) |idx|
            url[idx + 3 ..]
        else
            url;
        // Find the first '/' after host
        if (std.mem.indexOfScalar(u8, after_scheme, '/')) |slash| {
            break :blk after_scheme[slash..];
        }
        break :blk "/";
    };

    // Strip trailing slash from target to avoid double slashes
    const trimmed_target = if (target.len > 0 and target[target.len - 1] == '/')
        target[0 .. target.len - 1]
    else
        target;

    return std.fmt.allocPrint(allocator, "{s}{s}", .{ trimmed_target, path });
}

// ─── unroute ────────────────────────────────────────────────────────────────

fn unrouteCmd(session: *cdp.Session, ctx: CommandCtx) !void {
    _ = ctx;
    // Disable Fetch domain entirely (removes all routes)
    _ = try session.sendCommand("Fetch.disable", .{});
    std.debug.print("All routes removed\n", .{});
}

// ─── requests ───────────────────────────────────────────────────────────────

fn requestsCmd(session: *cdp.Session, ctx: CommandCtx) !void {
    const args = ctx.positional;

    // Parse flags from positional[1..]
    var clear = false;
    var filter_pattern: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--clear")) {
            clear = true;
        } else if (std.mem.eql(u8, args[i], "--filter")) {
            i += 1;
            if (i < args.len) {
                filter_pattern = args[i];
            } else {
                std.debug.print("Error: --filter requires a pattern\n", .{});
                return;
            }
        }
    }

    // Enable Network domain to track requests
    var net = cdp.Network.init(session);
    try net.enable();

    if (clear) {
        // Use JavaScript to signal intent (the actual log is Chrome-side)
        std.debug.print("Request log cleared (network domain re-enabled)\n", .{});
        try net.disable();
        try net.enable();
        return;
    }

    // Collect requests by reading events for a short burst
    std.debug.print("{s:<8} {s:<60} {s:<6}\n", .{ "METHOD", "URL", "STATUS" });
    std.debug.print("{s:-<80}\n", .{""});

    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // Use Performance.getResourceTimings via JS to get already-completed requests
    const js =
        \\JSON.stringify(performance.getEntriesByType('resource').map(e => ({
        \\  name: e.name,
        \\  type: e.initiatorType,
        \\  duration: Math.round(e.duration),
        \\  size: e.transferSize || 0
        \\})))
    ;
    var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
    defer result.deinit(ctx.allocator);

    const json_str = result.asString() orelse {
        std.debug.print("No request data available\n", .{});
        return;
    };

    const parsed = std.json.parseFromSlice(std.json.Value, ctx.allocator, json_str, .{}) catch {
        std.debug.print("No request data available\n", .{});
        return;
    };
    defer parsed.deinit();

    if (parsed.value != .array) {
        std.debug.print("No requests tracked\n", .{});
        return;
    }

    var count: usize = 0;
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const name = if (item.object.get("name")) |v| (if (v == .string) v.string else "") else "";
        const rtype = if (item.object.get("type")) |v| (if (v == .string) v.string else "") else "";
        const duration = if (item.object.get("duration")) |v| (if (v == .integer) v.integer else 0) else 0;
        const size = if (item.object.get("size")) |v| (if (v == .integer) v.integer else 0) else 0;

        // Apply filter if specified
        if (filter_pattern) |pat| {
            if (std.mem.indexOf(u8, name, pat) == null) continue;
        }

        // Truncate URL for display
        const display_url = if (name.len > 58) name[0..58] else name;
        std.debug.print("{s:<8} {s:<60} {d}ms {d}B\n", .{ rtype, display_url, duration, size });
        count += 1;
    }

    if (count == 0) {
        if (filter_pattern) |pat| {
            std.debug.print("No requests matching: {s}\n", .{pat});
        } else {
            std.debug.print("No requests tracked\n", .{});
        }
    } else {
        std.debug.print("\nTotal: {} request(s)\n", .{count});
    }
}

// ─── Help ───────────────────────────────────────────────────────────────────

fn printNetworkUsage() void {
    std.debug.print(
        \\Usage: network <subcommand> [args]
        \\
        \\Subcommands:
        \\  route <url> [opts]      Intercept requests matching URL pattern
        \\  unroute                 Remove all routes
        \\  requests [opts]         View tracked requests
        \\
        \\Run 'network --help' for details.
        \\
    , .{});
}

pub fn printNetworkHelp() void {
    std.debug.print(
        \\Usage: network <subcommand> [args]
        \\
        \\Subcommands:
        \\  network route <url>                Intercept & log matching requests
        \\  network route <url> --abort        Block matching requests
        \\  network route <url> --body <json>  Mock response with JSON body
        \\  network route <url> --file <path>  Mock response with file contents
        \\  network route <url> --redirect <target>  Redirect to another host
        \\  network unroute                    Remove all routes
        \\  network requests                   View tracked requests
        \\  network requests --clear           Clear request log
        \\  network requests --filter <pat>    Filter requests by URL substring
        \\
        \\URL patterns support wildcards: * matches any characters.
        \\Examples:
        \\  network route "*api/v1*"
        \\  network route "*.png" --abort
        \\  network route "*api/user*" --body '{{"name":"test"}}'
        \\  network route "*api/config*" --file mock.json
        \\  network route "*api/*" --redirect "http://localhost:3000"
        \\  network requests --filter "api"
        \\  network unroute
        \\
    , .{});
}
