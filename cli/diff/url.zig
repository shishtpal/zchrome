//! URL diffing command implementation.
//!
//! Compares two URLs by capturing snapshots and/or screenshots
//! from each and running the appropriate diff.

const std = @import("std");
const cdp = @import("cdp");
const myers = @import("myers.zig");
const colors = @import("colors.zig");
const snapshot_diff = @import("snapshot.zig");
const image_diff = @import("image.zig");
const png_helper = @import("png.zig");
const snapshot_mod = @import("../snapshot.zig");
const types = @import("../commands/types.zig");
const helpers = @import("../commands/helpers.zig");

pub const CommandCtx = types.CommandCtx;
const Allocator = std.mem.Allocator;

pub const WaitStrategy = enum {
    load,
    domcontentloaded,
    networkidle,
};

/// Execute the diff url command
pub fn diffUrlCommand(session: *cdp.Session, ctx: CommandCtx) !void {
    const allocator = ctx.allocator;

    // Check for --help flag
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printDiffUrlHelp();
            return;
        }
    }

    // Need at least 2 URLs
    if (ctx.positional.len < 2) {
        std.debug.print("Error: diff url requires two URLs\n", .{});
        printDiffUrlHelp();
        return;
    }

    const url1 = ctx.positional[0];
    const url2 = ctx.positional[1];

    // Parse additional options
    var do_screenshot = false;
    var wait_strategy: WaitStrategy = .load;
    var threshold: f32 = 0.1;

    var i: usize = 2;
    while (i < ctx.positional.len) : (i += 1) {
        const arg = ctx.positional[i];
        if (std.mem.eql(u8, arg, "--screenshot")) {
            do_screenshot = true;
        } else if (std.mem.eql(u8, arg, "--wait-until")) {
            i += 1;
            if (i >= ctx.positional.len) {
                std.debug.print("Error: --wait-until requires a value\n", .{});
                return;
            }
            const strategy = ctx.positional[i];
            if (std.mem.eql(u8, strategy, "load")) {
                wait_strategy = .load;
            } else if (std.mem.eql(u8, strategy, "domcontentloaded")) {
                wait_strategy = .domcontentloaded;
            } else if (std.mem.eql(u8, strategy, "networkidle")) {
                wait_strategy = .networkidle;
            } else {
                std.debug.print("Error: Invalid wait strategy: {s}\n", .{strategy});
                return;
            }
        } else if (std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--threshold")) {
            i += 1;
            if (i >= ctx.positional.len) {
                std.debug.print("Error: --threshold requires a value\n", .{});
                return;
            }
            threshold = std.fmt.parseFloat(f32, ctx.positional[i]) catch {
                std.debug.print("Error: Invalid threshold value\n", .{});
                return;
            };
        }
    }

    std.debug.print("Comparing URLs:\n", .{});
    std.debug.print("  URL1: {s}\n", .{url1});
    std.debug.print("  URL2: {s}\n", .{url2});
    std.debug.print("\n", .{});

    var page = cdp.Page.init(session);
    try page.enable();

    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // Capture from URL1
    colors.printHeader("Capturing URL1...");
    _ = try page.navigate(allocator, url1);
    try waitForPage(wait_strategy);

    const snap1 = try captureSnapshot(allocator, &runtime, ctx);
    defer allocator.free(snap1);

    var screenshot1: ?[]u8 = null;
    var img1: ?png_helper.PngImage = null;
    if (do_screenshot) {
        screenshot1 = try captureScreenshot(allocator, &page, ctx);
        // Copy to mutable buffer for decoder
        const copy1 = try allocator.alloc(u8, screenshot1.?.len);
        defer allocator.free(copy1);
        @memcpy(copy1, screenshot1.?);
        img1 = png_helper.decodePng(allocator, copy1) catch null;
    }
    defer if (screenshot1) |s| allocator.free(s);
    defer if (img1) |*img| img.deinit();

    std.debug.print("  Snapshot: {} lines\n", .{countLines(snap1)});
    if (img1) |img| {
        std.debug.print("  Screenshot: {}x{} pixels\n", .{ img.width, img.height });
    }

    // Capture from URL2
    colors.printHeader("\nCapturing URL2...");
    _ = try page.navigate(allocator, url2);
    try waitForPage(wait_strategy);

    const snap2 = try captureSnapshot(allocator, &runtime, ctx);
    defer allocator.free(snap2);

    var screenshot2: ?[]u8 = null;
    var img2: ?png_helper.PngImage = null;
    if (do_screenshot) {
        screenshot2 = try captureScreenshot(allocator, &page, ctx);
        // Copy to mutable buffer for decoder
        const copy2 = try allocator.alloc(u8, screenshot2.?.len);
        defer allocator.free(copy2);
        @memcpy(copy2, screenshot2.?);
        img2 = png_helper.decodePng(allocator, copy2) catch null;
    }
    defer if (screenshot2) |s| allocator.free(s);
    defer if (img2) |*img| img.deinit();

    std.debug.print("  Snapshot: {} lines\n", .{countLines(snap2)});
    if (img2) |img| {
        std.debug.print("  Screenshot: {}x{} pixels\n", .{ img.width, img.height });
    }

    // Run snapshot diff
    colors.printHeader("\n=== Snapshot Diff ===");
    var diff_data = try snapshot_diff.diffSnapshots(allocator, snap1, snap2);
    defer diff_data.deinit();

    if (!diff_data.changed) {
        colors.printSuccess("Snapshots are identical");
    } else {
        printColoredDiff(&diff_data);
    }

    // Run screenshot diff if requested
    if (do_screenshot and img1 != null and img2 != null) {
        colors.printHeader("\n=== Screenshot Diff ===");

        const image1 = img1.?;
        const image2 = img2.?;

        if (image1.width != image2.width or image1.height != image2.height) {
            colors.printError("Screenshot dimensions don't match!");
            std.debug.print("URL1: {}x{}, URL2: {}x{}\n", .{ image1.width, image1.height, image2.width, image2.height });
        } else {
            var pixel_diff = try image_diff.diffPixels(
                allocator,
                image1.pixels,
                image2.pixels,
                image1.width,
                image1.height,
                threshold,
            );
            defer pixel_diff.deinit();

            if (pixel_diff.match()) {
                colors.printSuccess("Screenshots match!");
            } else {
                std.debug.print("\nTotal pixels: {}\n", .{pixel_diff.total_pixels});
                std.debug.print("{s}Different pixels: {}{s} ({d:.2}%)\n", .{
                    colors.RED,
                    pixel_diff.different_pixels,
                    colors.RESET,
                    pixel_diff.mismatch_percentage,
                });

                // Save diff image
                const diff_png = try png_helper.encodePng(
                    allocator,
                    pixel_diff.diff_image,
                    pixel_diff.width,
                    pixel_diff.height,
                );
                defer allocator.free(diff_png);

                try helpers.writeFile(ctx.io, "url-diff.png", diff_png);
                std.debug.print("Diff image saved to: url-diff.png\n", .{});
            }
        }
    }
}

fn waitForPage(strategy: WaitStrategy) !void {
    // Simple wait based on strategy
    const iterations: u32 = switch (strategy) {
        .load => 500000,
        .domcontentloaded => 300000,
        .networkidle => 1000000,
    };
    var j: u32 = 0;
    while (j < iterations) : (j += 1) std.atomic.spinLoopHint();
}

fn captureSnapshot(allocator: Allocator, runtime: *cdp.Runtime, ctx: CommandCtx) ![]u8 {
    const js = try snapshot_mod.buildSnapshotJs(allocator, ctx.snap_selector, ctx.snap_depth, false);
    defer allocator.free(js);

    var result = try runtime.evaluate(allocator, js, .{ .return_by_value = true });
    defer result.deinit(allocator);

    const aria_tree = result.asString() orelse "(empty)";

    var processor = snapshot_mod.SnapshotProcessor.init(allocator);
    defer processor.deinit();

    const options = snapshot_mod.SnapshotOptions{
        .interactive = ctx.snap_interactive,
        .compact = ctx.snap_compact,
        .max_depth = ctx.snap_depth,
        .selector = ctx.snap_selector,
    };

    var snap = try processor.processAriaTree(aria_tree, options);
    defer snap.deinit();

    return try allocator.dupe(u8, snap.tree);
}

fn captureScreenshot(allocator: Allocator, page: *cdp.Page, ctx: CommandCtx) ![]u8 {
    const screenshot_data = try page.captureScreenshot(allocator, .{
        .format = .png,
        .capture_beyond_viewport = if (ctx.full_page) true else null,
    });
    defer allocator.free(screenshot_data);

    return try cdp.base64.decodeAlloc(allocator, screenshot_data);
}

fn countLines(text: []const u8) usize {
    var count: usize = 0;
    var iter = std.mem.splitScalar(u8, text, '\n');
    while (iter.next()) |_| count += 1;
    return count;
}

fn printColoredDiff(diff_data: *const snapshot_diff.DiffSnapshotData) void {
    var iter = std.mem.splitScalar(u8, diff_data.diff, '\n');
    while (iter.next()) |line| {
        if (line.len < 2) continue;

        const prefix = line[0..2];
        const content = line[2..];

        if (std.mem.eql(u8, prefix, "+ ")) {
            colors.printInsertion(content);
        } else if (std.mem.eql(u8, prefix, "- ")) {
            colors.printDeletion(content);
        } else {
            colors.printUnchanged(content);
        }
    }

    colors.printDiffStats(diff_data.additions, diff_data.removals, diff_data.unchanged);
}

pub fn printDiffUrlHelp() void {
    std.debug.print(
        \\Usage: diff url <url1> <url2> [options]
        \\
        \\Compare two URLs by capturing and diffing their content.
        \\
        \\Options:
        \\  --screenshot             Also perform visual (pixel) diff
        \\  --wait-until <strategy>  Wait strategy: load, domcontentloaded, networkidle
        \\  -t, --threshold <0-1>    Color difference threshold for screenshots (default: 0.1)
        \\  -i, --interactive-only   Only include interactive elements in snapshot
        \\  -c, --compact            Compact snapshot output
        \\  -d, --depth <n>          Limit snapshot tree depth
        \\  -s, --selector <sel>     Scope snapshot to CSS selector
        \\
        \\Examples:
        \\  diff url https://v1.com https://v2.com
        \\  diff url https://v1.com https://v2.com --screenshot
        \\  diff url https://v1.com https://v2.com --wait-until networkidle
        \\  diff url https://v1.com https://v2.com -s "#main" -c
        \\
    , .{});
}
