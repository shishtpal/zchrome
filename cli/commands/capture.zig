//! Capture commands: screenshot, pdf, snapshot.

const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");
const helpers = @import("helpers.zig");
const snapshot_mod = @import("../snapshot.zig");
const config_mod = @import("../config.zig");

pub const CommandCtx = types.CommandCtx;

pub fn screenshot(session: *cdp.Session, ctx: CommandCtx) !void {
    var page = cdp.Page.init(session);
    try page.enable();

    var j: u32 = 0;
    while (j < 500000) : (j += 1) std.atomic.spinLoopHint();

    const screenshot_data = try page.captureScreenshot(ctx.allocator, .{
        .format = .png,
        .capture_beyond_viewport = if (ctx.full_page) true else null,
    });
    defer ctx.allocator.free(screenshot_data);

    const decoded = try cdp.base64.decodeAlloc(ctx.allocator, screenshot_data);
    defer ctx.allocator.free(decoded);

    const output_path = ctx.output orelse "screenshot.png";
    try helpers.writeFile(ctx.io, output_path, decoded);
    std.debug.print("Screenshot saved to {s} ({} bytes){s}\n", .{
        output_path,
        decoded.len,
        if (ctx.full_page) " (full page)" else "",
    });
}

pub fn pdf(session: *cdp.Session, ctx: CommandCtx) !void {
    var page = cdp.Page.init(session);
    try page.enable();

    var j: u32 = 0;
    while (j < 500000) : (j += 1) std.atomic.spinLoopHint();

    const pdf_data = try page.printToPDF(ctx.allocator, .{});
    defer ctx.allocator.free(pdf_data);

    const decoded = try cdp.base64.decodeAlloc(ctx.allocator, pdf_data);
    defer ctx.allocator.free(decoded);

    const output_path = ctx.output orelse "page.pdf";
    try helpers.writeFile(ctx.io, output_path, decoded);
    std.debug.print("PDF saved to {s} ({} bytes)\n", .{ output_path, decoded.len });
}

pub fn snapshot(session: *cdp.Session, ctx: CommandCtx) !void {
    // Check for --help flag in positional args
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printSnapshotHelp();
            return;
        }
    }

    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    const js = try snapshot_mod.buildSnapshotJs(ctx.allocator, ctx.snap_selector, ctx.snap_depth);
    defer ctx.allocator.free(js);

    var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
    defer result.deinit(ctx.allocator);

    const aria_tree = result.asString() orelse "(empty)";

    var processor = snapshot_mod.SnapshotProcessor.init(ctx.allocator);
    defer processor.deinit();

    const options = snapshot_mod.SnapshotOptions{
        .interactive = ctx.snap_interactive,
        .compact = ctx.snap_compact,
        .max_depth = ctx.snap_depth,
        .selector = ctx.snap_selector,
    };

    var snap = try processor.processAriaTree(aria_tree, options);
    defer snap.deinit();

    std.debug.print("{s}\n", .{snap.tree});
    std.debug.print("\n--- {} element(s) with refs ---\n", .{snap.refs.count()});

    const output_path = ctx.output orelse try config_mod.getSnapshotPath(ctx.allocator, ctx.io);
    defer if (ctx.output == null) ctx.allocator.free(output_path);

    try snapshot_mod.saveSnapshot(ctx.allocator, ctx.io, output_path, &snap);

    std.debug.print("\nSnapshot saved to: {s}\n", .{output_path});
    if (snap.refs.count() > 0) {
        std.debug.print("Use @e<N> refs in subsequent commands\n", .{});
    }
}

pub fn printSnapshotHelp() void {
    std.debug.print(
        \\Usage: snapshot [options]
        \\
        \\Options:
        \\  -i, --interactive-only   Only include interactive elements
        \\  -c, --compact            Compact output (skip empty structural elements)
        \\  -d, --depth <n>          Limit tree depth
        \\  -s, --selector <sel>     Scope snapshot to CSS selector
        \\  --output <path>          Output file path (default: zsnap.json)
        \\
        \\Examples:
        \\  snapshot                       # Snapshot current page
        \\  snapshot -i                    # Interactive elements only
        \\  snapshot -c -d 3               # Compact mode, depth 3
        \\  snapshot -s "#main-content"    # Scope to selector
        \\
    , .{});
}
