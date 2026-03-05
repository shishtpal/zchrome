//! Image pixel diffing for screenshot comparison.
//!
//! Compares two images pixel-by-pixel using color distance threshold.

const std = @import("std");
const cdp = @import("cdp");
const png_helper = @import("png.zig");
const colors = @import("colors.zig");
const types = @import("../commands/types.zig");
const helpers = @import("../commands/helpers.zig");

pub const CommandCtx = types.CommandCtx;
const Allocator = std.mem.Allocator;

pub const PixelDiffResult = struct {
    total_pixels: usize,
    different_pixels: usize,
    mismatch_percentage: f64,
    dimension_mismatch: bool,
    diff_image: []u8, // RGBA pixel buffer
    width: u32,
    height: u32,
    allocator: Allocator,

    pub fn deinit(self: *PixelDiffResult) void {
        self.allocator.free(self.diff_image);
    }

    pub fn match(self: PixelDiffResult) bool {
        return self.different_pixels == 0 and !self.dimension_mismatch;
    }
};

pub const DiffScreenshotData = struct {
    diff_path: []const u8,
    total_pixels: usize,
    different_pixels: usize,
    mismatch_percentage: f64,
    match: bool,
    dimension_mismatch: bool,
};

/// Compare two RGBA pixel buffers
pub fn diffPixels(
    allocator: Allocator,
    baseline: []const u8,
    current: []const u8,
    width: u32,
    height: u32,
    threshold: f32,
) !PixelDiffResult {
    const expected_size = width * height * 4;

    // Validate buffer sizes
    if (baseline.len != expected_size or current.len != expected_size) {
        // Dimension mismatch - create red error image
        const diff_image = try allocator.alloc(u8, expected_size);
        @memset(diff_image, 0);
        // Fill with red to indicate error
        var i: usize = 0;
        while (i < expected_size) : (i += 4) {
            diff_image[i] = 255; // R
            diff_image[i + 1] = 0; // G
            diff_image[i + 2] = 0; // B
            diff_image[i + 3] = 255; // A
        }

        return PixelDiffResult{
            .total_pixels = width * height,
            .different_pixels = width * height,
            .mismatch_percentage = 100.0,
            .dimension_mismatch = true,
            .diff_image = diff_image,
            .width = width,
            .height = height,
            .allocator = allocator,
        };
    }

    // Allocate diff image buffer
    const diff_image = try allocator.alloc(u8, expected_size);
    errdefer allocator.free(diff_image);

    // Calculate max color distance for threshold
    // Maximum possible distance is sqrt(255^2 * 3) ≈ 441.67
    const max_distance: f32 = 441.67;
    const threshold_distance = threshold * max_distance;

    var different_pixels: usize = 0;
    const total_pixels = width * height;

    // Compare each pixel
    for (0..total_pixels) |i| {
        const offset = i * 4;

        const rA = baseline[offset];
        const gA = baseline[offset + 1];
        const bA = baseline[offset + 2];

        const rB = current[offset];
        const gB = current[offset + 1];
        const bB = current[offset + 2];

        // Calculate Euclidean color distance
        const dr: f32 = @floatFromInt(@as(i16, rA) - @as(i16, rB));
        const dg: f32 = @floatFromInt(@as(i16, gA) - @as(i16, gB));
        const db: f32 = @floatFromInt(@as(i16, bA) - @as(i16, bB));

        const distance = @sqrt(dr * dr + dg * dg + db * db);

        if (distance > threshold_distance) {
            // Mark as different (bright red)
            different_pixels += 1;
            diff_image[offset] = 255;
            diff_image[offset + 1] = 0;
            diff_image[offset + 2] = 0;
            diff_image[offset + 3] = 255;
        } else {
            // Darken original (30% opacity) to show unchanged areas
            diff_image[offset] = @intFromFloat(@as(f32, @floatFromInt(rA)) * 0.3);
            diff_image[offset + 1] = @intFromFloat(@as(f32, @floatFromInt(gA)) * 0.3);
            diff_image[offset + 2] = @intFromFloat(@as(f32, @floatFromInt(bA)) * 0.3);
            diff_image[offset + 3] = 255;
        }
    }

    const mismatch_percentage: f64 = @as(f64, @floatFromInt(different_pixels)) /
        @as(f64, @floatFromInt(total_pixels)) * 100.0;

    return PixelDiffResult{
        .total_pixels = total_pixels,
        .different_pixels = different_pixels,
        .mismatch_percentage = mismatch_percentage,
        .dimension_mismatch = false,
        .diff_image = diff_image,
        .width = width,
        .height = height,
        .allocator = allocator,
    };
}

/// Execute the diff screenshot command
pub fn diffScreenshotCommand(session: *cdp.Session, ctx: CommandCtx) !void {
    const allocator = ctx.allocator;

    // Check for --help flag
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printDiffScreenshotHelp();
            return;
        }
    }

    // Parse arguments
    var baseline_path: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var threshold: f32 = 0.1;

    var i: usize = 0;
    while (i < ctx.positional.len) : (i += 1) {
        const arg = ctx.positional[i];
        if (std.mem.eql(u8, arg, "-b") or std.mem.eql(u8, arg, "--baseline")) {
            i += 1;
            if (i >= ctx.positional.len) {
                std.debug.print("Error: --baseline requires a file path\n", .{});
                return;
            }
            baseline_path = ctx.positional[i];
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            i += 1;
            if (i >= ctx.positional.len) {
                std.debug.print("Error: --output requires a file path\n", .{});
                return;
            }
            output_path = ctx.positional[i];
        } else if (std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--threshold")) {
            i += 1;
            if (i >= ctx.positional.len) {
                std.debug.print("Error: --threshold requires a value (0-1)\n", .{});
                return;
            }
            threshold = std.fmt.parseFloat(f32, ctx.positional[i]) catch {
                std.debug.print("Error: Invalid threshold value\n", .{});
                return;
            };
            if (threshold < 0 or threshold > 1) {
                std.debug.print("Error: Threshold must be between 0 and 1\n", .{});
                return;
            }
        }
    }

    if (baseline_path == null) {
        std.debug.print("Error: --baseline is required for screenshot diff\n", .{});
        printDiffScreenshotHelp();
        return;
    }

    // Load baseline PNG
    const dir = std.Io.Dir.cwd();
    var baseline_buf: [10 * 1024 * 1024]u8 = undefined; // 10MB max
    const baseline_data = dir.readFile(ctx.io, baseline_path.?, &baseline_buf) catch |err| {
        std.debug.print("Error reading baseline file '{s}': {}\n", .{ baseline_path.?, err });
        return;
    };

    // Copy to mutable buffer for decoder
    const baseline_copy = try allocator.alloc(u8, baseline_data.len);
    defer allocator.free(baseline_copy);
    @memcpy(baseline_copy, baseline_data);

    var baseline_img = png_helper.decodePng(allocator, baseline_copy) catch |err| {
        std.debug.print("Error decoding baseline PNG: {}\n", .{err});
        return;
    };
    defer baseline_img.deinit();

    std.debug.print("Loaded baseline: {}x{} pixels\n", .{ baseline_img.width, baseline_img.height });

    // Capture current screenshot
    var page = cdp.Page.init(session);
    try page.enable();

    // Small delay for page render
    var j: u32 = 0;
    while (j < 500000) : (j += 1) std.atomic.spinLoopHint();

    const screenshot_data = try page.captureScreenshot(allocator, .{
        .format = .png,
        .capture_beyond_viewport = if (ctx.full_page) true else null,
    });
    defer allocator.free(screenshot_data);

    // Decode base64 screenshot
    const decoded = try cdp.base64.decodeAlloc(allocator, screenshot_data);
    defer allocator.free(decoded);

    // Copy to mutable buffer
    const current_copy = try allocator.alloc(u8, decoded.len);
    defer allocator.free(current_copy);
    @memcpy(current_copy, decoded);

    var current_img = png_helper.decodePng(allocator, current_copy) catch |err| {
        std.debug.print("Error decoding current screenshot: {}\n", .{err});
        return;
    };
    defer current_img.deinit();

    std.debug.print("Current screenshot: {}x{} pixels\n", .{ current_img.width, current_img.height });

    // Check dimension match
    if (baseline_img.width != current_img.width or baseline_img.height != current_img.height) {
        colors.printError("Dimension mismatch!");
        std.debug.print("Baseline: {}x{}, Current: {}x{}\n", .{
            baseline_img.width,
            baseline_img.height,
            current_img.width,
            current_img.height,
        });
        return;
    }

    // Run pixel diff
    var diff_result = try diffPixels(
        allocator,
        baseline_img.pixels,
        current_img.pixels,
        baseline_img.width,
        baseline_img.height,
        threshold,
    );
    defer diff_result.deinit();

    // Print results
    if (diff_result.match()) {
        colors.printSuccess("Screenshots match!");
        std.debug.print("Total pixels: {}\n", .{diff_result.total_pixels});
        return;
    }

    colors.printHeader("=== Screenshot Diff ===");
    std.debug.print("\nTotal pixels: {}\n", .{diff_result.total_pixels});
    std.debug.print("{s}Different pixels: {}{s} ({d:.2}%)\n", .{
        colors.RED,
        diff_result.different_pixels,
        colors.RESET,
        diff_result.mismatch_percentage,
    });

    // Save diff image
    const diff_output_path = output_path orelse "diff.png";
    const diff_png = try png_helper.encodePng(
        allocator,
        diff_result.diff_image,
        diff_result.width,
        diff_result.height,
    );
    defer allocator.free(diff_png);

    try helpers.writeFile(ctx.io, diff_output_path, diff_png);
    std.debug.print("\nDiff image saved to: {s}\n", .{diff_output_path});
}

pub fn printDiffScreenshotHelp() void {
    std.debug.print(
        \\Usage: diff screenshot --baseline <file> [options]
        \\
        \\Compare current page screenshot against a baseline image.
        \\
        \\Options:
        \\  -b, --baseline <file>    Baseline PNG file (required)
        \\  -o, --output <file>      Output diff image path (default: diff.png)
        \\  -t, --threshold <0-1>    Color difference threshold (default: 0.1)
        \\  --full                   Capture full page screenshot
        \\
        \\Examples:
        \\  diff screenshot --baseline before.png
        \\  diff screenshot -b before.png -o result.png -t 0.05
        \\  diff screenshot --baseline before.png --full
        \\
    , .{});
}
