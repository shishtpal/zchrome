//! Media inspection commands: list audio/video elements, get state, detect errors.

const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");

pub const CommandCtx = types.CommandCtx;

/// JavaScript to list all media elements on the page
const JS_LIST_MEDIA =
    \\(() => {
    \\  const elements = [...document.querySelectorAll('audio, video')];
    \\  return JSON.stringify(elements.map((el, i) => {
    \\    let selector = el.tagName.toLowerCase();
    \\    if (el.id) selector += '#' + el.id;
    \\    else if (el.className) selector += '.' + el.className.split(' ')[0];
    \\    return {
    \\      index: i,
    \\      selector: selector,
    \\      tagName: el.tagName,
    \\      src: el.src || null,
    \\      currentSrc: el.currentSrc || null,
    \\      paused: el.paused,
    \\      ended: el.ended,
    \\      currentTime: el.currentTime,
    \\      duration: isNaN(el.duration) ? null : el.duration,
    \\      volume: el.volume,
    \\      muted: el.muted,
    \\      readyState: el.readyState,
    \\      networkState: el.networkState,
    \\      error: el.error ? { code: el.error.code, message: el.error.message } : null
    \\    };
    \\  }));
    \\})()
;

/// JavaScript template to get detailed state of a specific media element
const JS_GET_MEDIA_TEMPLATE =
    \\(() => {{
    \\  const el = document.querySelector('{s}');
    \\  if (!el || (el.tagName !== 'AUDIO' && el.tagName !== 'VIDEO')) {{
    \\    return JSON.stringify({{ error: 'Media element not found: {s}' }});
    \\  }}
    \\  return JSON.stringify({{
    \\    selector: '{s}',
    \\    tagName: el.tagName,
    \\    src: el.src || null,
    \\    currentSrc: el.currentSrc || null,
    \\    paused: el.paused,
    \\    ended: el.ended,
    \\    seeking: el.seeking,
    \\    currentTime: el.currentTime,
    \\    duration: isNaN(el.duration) ? null : el.duration,
    \\    volume: el.volume,
    \\    muted: el.muted,
    \\    defaultMuted: el.defaultMuted,
    \\    playbackRate: el.playbackRate,
    \\    defaultPlaybackRate: el.defaultPlaybackRate,
    \\    autoplay: el.autoplay,
    \\    loop: el.loop,
    \\    controls: el.controls,
    \\    readyState: el.readyState,
    \\    networkState: el.networkState,
    \\    preload: el.preload,
    \\    buffered: el.buffered.length > 0 ? {{ start: el.buffered.start(0), end: el.buffered.end(el.buffered.length - 1) }} : null,
    \\    error: el.error ? {{ code: el.error.code, message: el.error.message || getMediaErrorMessage(el.error.code) }} : null
    \\  }});
    \\  function getMediaErrorMessage(code) {{
    \\    switch(code) {{
    \\      case 1: return 'MEDIA_ERR_ABORTED';
    \\      case 2: return 'MEDIA_ERR_NETWORK';
    \\      case 3: return 'MEDIA_ERR_DECODE';
    \\      case 4: return 'MEDIA_ERR_SRC_NOT_SUPPORTED';
    \\      default: return 'Unknown error';
    \\    }}
    \\  }}
    \\}})()
;

/// JavaScript template to check autoplay blocking
const JS_CHECK_AUTOPLAY_TEMPLATE =
    \\(async () => {{
    \\  const el = document.querySelector('{s}');
    \\  if (!el || (el.tagName !== 'AUDIO' && el.tagName !== 'VIDEO')) {{
    \\    return JSON.stringify({{ error: 'Media element not found: {s}' }});
    \\  }}
    \\  const wasPaused = el.paused;
    \\  const wasTime = el.currentTime;
    \\  try {{
    \\    await el.play();
    \\    if (wasPaused) {{
    \\      el.pause();
    \\      el.currentTime = wasTime;
    \\    }}
    \\    return JSON.stringify({{ autoplayBlocked: false }});
    \\  }} catch (e) {{
    \\    return JSON.stringify({{ autoplayBlocked: true, autoplayBlockReason: e.name + ': ' + e.message }});
    \\  }}
    \\}})()
;

pub fn media(session: *cdp.Session, ctx: CommandCtx) !void {
    // Check for --help flag
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printMediaHelp();
            return;
        }
    }

    if (ctx.positional.len == 0) {
        printMediaUsage();
        return;
    }

    const subcommand = ctx.positional[0];

    if (std.mem.eql(u8, subcommand, "list")) {
        try listMedia(session, ctx.allocator, ctx.io);
    } else if (std.mem.eql(u8, subcommand, "get")) {
        const selector = if (ctx.positional.len > 1) ctx.positional[1] else null;
        const check_autoplay = hasFlag(ctx.positional, "--check-autoplay");
        try getMedia(session, ctx.allocator, ctx.io, selector, check_autoplay);
    } else {
        std.debug.print("Unknown media subcommand: {s}\n", .{subcommand});
        printMediaUsage();
    }
}

fn hasFlag(args: []const []const u8, flag: []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, flag)) return true;
    }
    return false;
}

fn listMedia(session: *cdp.Session, allocator: std.mem.Allocator, io: std.Io) !void {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    var result = try runtime.evaluate(allocator, JS_LIST_MEDIA, .{ .return_by_value = true });
    defer result.deinit(allocator);

    // Write to stdout for proper piping
    var stdout_buf: [4096]u8 = undefined;
    var stdout = std.Io.File.Writer.init(std.Io.File.stdout(), io, &stdout_buf);

    if (result.asString()) |json_str| {
        try stdout.interface.print("{s}\n", .{json_str});
    } else {
        try stdout.interface.print("[]\n", .{});
    }
    try stdout.flush();
}

fn getMedia(session: *cdp.Session, allocator: std.mem.Allocator, io: std.Io, selector: ?[]const u8, check_autoplay: bool) !void {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // Write to stdout for proper piping
    var stdout_buf: [4096]u8 = undefined;
    var stdout = std.Io.File.Writer.init(std.Io.File.stdout(), io, &stdout_buf);

    if (selector) |sel| {
        // Get specific element
        const escaped_selector = try escapeJsString(allocator, sel);
        defer allocator.free(escaped_selector);

        const js = try std.fmt.allocPrint(allocator, JS_GET_MEDIA_TEMPLATE, .{ escaped_selector, escaped_selector, escaped_selector });
        defer allocator.free(js);

        var result = try runtime.evaluate(allocator, js, .{ .return_by_value = true });
        defer result.deinit(allocator);

        if (result.asString()) |json_str| {
            if (check_autoplay) {
                // Also check autoplay and merge results
                const autoplay_js = try std.fmt.allocPrint(allocator, JS_CHECK_AUTOPLAY_TEMPLATE, .{ escaped_selector, escaped_selector });
                defer allocator.free(autoplay_js);

                var autoplay_result = try runtime.evaluate(allocator, autoplay_js, .{ .return_by_value = true, .await_promise = true });
                defer autoplay_result.deinit(allocator);

                if (autoplay_result.asString()) |autoplay_json| {
                    // Merge JSON objects (simple approach: print both)
                    try printMergedJson(&stdout, json_str, autoplay_json);
                } else {
                    try stdout.interface.print("{s}\n", .{json_str});
                }
            } else {
                try stdout.interface.print("{s}\n", .{json_str});
            }
        } else {
            try stdout.interface.print("{{\"error\": \"Failed to evaluate\"}}\n", .{});
        }
        try stdout.flush();
    } else {
        // Get all elements (same as list but with full details)
        try listMedia(session, allocator, io);
    }
}

/// Simple JSON merge - removes trailing } from first, adds comma, removes leading { from second
fn printMergedJson(stdout: *std.Io.File.Writer, json1: []const u8, json2: []const u8) !void {
    // Find positions to merge
    var end1: usize = json1.len;
    while (end1 > 0 and (json1[end1 - 1] == '}' or json1[end1 - 1] == ' ' or json1[end1 - 1] == '\n')) {
        end1 -= 1;
    }

    var start2: usize = 0;
    while (start2 < json2.len and (json2[start2] == '{' or json2[start2] == ' ' or json2[start2] == '\n')) {
        start2 += 1;
    }

    if (end1 > 0 and start2 < json2.len) {
        try stdout.interface.print("{s}, {s}\n", .{ json1[0..end1], json2[start2..] });
    } else {
        try stdout.interface.print("{s}\n", .{json1});
    }
}

fn escapeJsString(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    for (str) |c| {
        switch (c) {
            '\'' => try result.appendSlice(allocator, "\\'"),
            '\\' => try result.appendSlice(allocator, "\\\\"),
            '\n' => try result.appendSlice(allocator, "\\n"),
            '\r' => try result.appendSlice(allocator, "\\r"),
            '\t' => try result.appendSlice(allocator, "\\t"),
            else => try result.append(allocator, c),
        }
    }
    return result.toOwnedSlice(allocator);
}

fn printMediaUsage() void {
    std.debug.print(
        \\Usage: media <subcommand> [options]
        \\
        \\Subcommands:
        \\  list                     List all audio/video elements (JSON)
        \\  get [selector]           Get media element state (JSON)
        \\
        \\Options:
        \\  --check-autoplay         Check if autoplay is blocked (for 'get')
        \\
        \\Examples:
        \\  media list
        \\  media get "video#player"
        \\  media get "audio.preview" --check-autoplay
        \\
    , .{});
}

pub fn printMediaHelp() void {
    std.debug.print(
        \\Media Commands - Inspect audio/video elements
        \\
        \\Usage: media <subcommand> [options]
        \\
        \\Subcommands:
        \\  list                     List all audio/video elements on the page
        \\                           Returns JSON array with basic state
        \\
        \\  get [selector]           Get detailed media element state
        \\                           Without selector: returns all elements
        \\                           With selector: returns specific element
        \\
        \\Options:
        \\  --check-autoplay         Attempt play() to detect autoplay blocking
        \\                           Only works with 'get' and a selector
        \\                           Note: May briefly start playback
        \\
        \\Output Format: JSON
        \\
        \\Media State Properties:
        \\  paused         - true if playback is paused
        \\  ended          - true if playback has ended
        \\  currentTime    - current playback position (seconds)
        \\  duration       - total duration (seconds, null if unknown)
        \\  volume         - volume level (0.0 to 1.0)
        \\  muted          - true if muted
        \\  readyState     - 0=HAVE_NOTHING, 1=HAVE_METADATA, 2=HAVE_CURRENT_DATA,
        \\                   3=HAVE_FUTURE_DATA, 4=HAVE_ENOUGH_DATA
        \\  networkState   - 0=NETWORK_EMPTY, 1=NETWORK_IDLE, 2=NETWORK_LOADING,
        \\                   3=NETWORK_NO_SOURCE
        \\  error          - null or {{code, message}}
        \\
        \\Error Codes:
        \\  1 - MEDIA_ERR_ABORTED
        \\  2 - MEDIA_ERR_NETWORK
        \\  3 - MEDIA_ERR_DECODE
        \\  4 - MEDIA_ERR_SRC_NOT_SUPPORTED
        \\
        \\Examples:
        \\  media list
        \\  media get "video#player"
        \\  media get "video" --check-autoplay
        \\
    , .{});
}
