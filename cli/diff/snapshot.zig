//! Snapshot diffing command implementation.
//!
//! Compares the current page snapshot against a baseline snapshot
//! using the Myers diff algorithm.

const std = @import("std");
const cdp = @import("cdp");
const myers = @import("myers.zig");
const colors = @import("colors.zig");
const snapshot_mod = @import("../snapshot.zig");
const config_mod = @import("../config.zig");
const types = @import("../commands/types.zig");

pub const CommandCtx = types.CommandCtx;

pub const DiffSnapshotData = struct {
    diff: []u8,
    additions: usize,
    removals: usize,
    unchanged: usize,
    changed: bool,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *DiffSnapshotData) void {
        self.allocator.free(self.diff);
    }
};

/// Compare two snapshot strings and return diff data
pub fn diffSnapshots(
    allocator: std.mem.Allocator,
    before: []const u8,
    after: []const u8,
) !DiffSnapshotData {
    // Split into lines
    const linesA = try myers.splitLines(allocator, before);
    defer allocator.free(linesA);

    const linesB = try myers.splitLines(allocator, after);
    defer allocator.free(linesB);

    // Run Myers diff
    var result = try myers.myersDiff(allocator, linesA, linesB);
    defer result.deinit();

    // Generate output with prefixes
    var diffLines: std.ArrayListUnmanaged(u8) = .{ .items = &.{}, .capacity = 0 };
    errdefer diffLines.deinit(allocator);

    for (result.edits) |edit| {
        const prefix: []const u8 = switch (edit.type) {
            .equal => "  ",
            .insert => "+ ",
            .delete => "- ",
        };
        try diffLines.appendSlice(allocator, prefix);
        try diffLines.appendSlice(allocator, edit.line);
        try diffLines.append(allocator, '\n');
    }

    return DiffSnapshotData{
        .diff = try diffLines.toOwnedSlice(allocator),
        .additions = result.additions,
        .removals = result.removals,
        .unchanged = result.unchanged,
        .changed = result.changed(),
        .allocator = allocator,
    };
}

/// Print diff output with colors
fn printColoredDiff(diff_data: *const DiffSnapshotData) void {
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

/// Execute the diff snapshot command
pub fn diffSnapshotCommand(session: *cdp.Session, ctx: CommandCtx) !void {
    const allocator = ctx.allocator;

    // Check for --help flag
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printDiffSnapshotHelp();
            return;
        }
    }

    // Parse baseline option from positional args
    var baseline_path: ?[]const u8 = null;
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
        }
    }

    // Load baseline snapshot
    var baseline_text: []const u8 = undefined;
    var baseline_allocated = false;

    if (baseline_path) |path| {
        // Load from specified file
        const dir = std.Io.Dir.cwd();
        var file_buf: [256 * 1024]u8 = undefined;
        baseline_text = dir.readFile(ctx.io, path, &file_buf) catch |err| {
            std.debug.print("Error reading baseline file '{s}': {}\n", .{ path, err });
            return;
        };
        std.debug.print("Loaded baseline from: {s}\n", .{path});
    } else {
        // Load from last session snapshot (default)
        const snapshot_path = blk: {
            if (ctx.session) |s| {
                break :blk s.snapshotPath() catch {
                    std.debug.print("Error: Could not determine session snapshot path\n", .{});
                    return;
                };
            }
            break :blk config_mod.getSnapshotPath(allocator, ctx.io) catch {
                std.debug.print("Error: Could not determine snapshot path\n", .{});
                return;
            };
        };
        defer allocator.free(snapshot_path);

        // Load and parse JSON to get tree
        const data = snapshot_mod.loadSnapshot(allocator, ctx.io, snapshot_path) catch |err| {
            std.debug.print("Error loading baseline snapshot: {}\n", .{err});
            std.debug.print("Hint: Run 'zchrome snapshot' first, or use --baseline <file>\n", .{});
            return;
        };
        // Note: data.tree is owned by data, need to dupe
        baseline_text = try allocator.dupe(u8, data.tree);
        baseline_allocated = true;
        std.debug.print("Loaded baseline from session snapshot\n", .{});
    }
    defer if (baseline_allocated) allocator.free(baseline_text);

    // Capture current snapshot
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    const js = try snapshot_mod.buildSnapshotJs(allocator, ctx.snap_selector, ctx.snap_depth, false);
    defer allocator.free(js);

    var eval_result = try runtime.evaluate(allocator, js, .{ .return_by_value = true });
    defer eval_result.deinit(allocator);

    const aria_tree = eval_result.asString() orelse "(empty)";

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

    // Run diff
    var diff_data = try diffSnapshots(allocator, baseline_text, snap.tree);
    defer diff_data.deinit();

    // Print results
    if (!diff_data.changed) {
        colors.printSuccess("No changes detected - snapshots are identical");
        return;
    }

    colors.printHeader("=== Snapshot Diff ===");
    std.debug.print("\n", .{});
    printColoredDiff(&diff_data);
}

pub fn printDiffSnapshotHelp() void {
    std.debug.print(
        \\Usage: diff snapshot [options]
        \\
        \\Compare current page snapshot against a baseline.
        \\
        \\Options:
        \\  -b, --baseline <file>    Baseline snapshot file (default: last session snapshot)
        \\  -i, --interactive-only   Only include interactive elements
        \\  -c, --compact            Compact output (skip empty structural elements)
        \\  -d, --depth <n>          Limit tree depth
        \\  -s, --selector <sel>     Scope snapshot to CSS selector
        \\
        \\Examples:
        \\  diff snapshot                        # Compare vs last session snapshot
        \\  diff snapshot --baseline before.txt  # Compare vs saved file
        \\  diff snapshot -s "#main" -c          # Scoped, compact diff
        \\
    , .{});
}
