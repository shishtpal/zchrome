//! Core replay execution loop with retry, video, and state management.

const std = @import("std");
const json = @import("json");
const cdp = @import("cdp");

// Local imports
const macro = @import("../macro/mod.zig");
const state = @import("../state.zig");
const utils = @import("../utils.zig");
const assertions = @import("../assertions.zig");
const video = @import("../video/mod.zig");

// Local replay imports
const actions = @import("actions.zig");
const cli = @import("cli.zig");

pub const MarkError = actions.MarkError;
pub const ReplayOptions = cli.ReplayOptions;
pub const ReplayInterval = cli.ReplayInterval;

/// Execute macro commands with full options (retry, video, state management)
pub fn replayCommandsWithOptions(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    io: std.Io,
    filename: []const u8,
    options: ReplayOptions,
) anyerror!void {
    var macro_data = macro.loadCommandMacro(allocator, io, filename) catch |err| {
        std.debug.print("Error loading command macro: {}\n", .{err});
        return;
    };
    defer macro_data.deinit(allocator);

    if (macro_data.commands.len == 0) {
        std.debug.print("No commands in macro file.\n", .{});
        return;
    }

    const interval = options.interval;

    // Use existing video orchestrator if provided, otherwise create new one
    var video_orch: ?*video.Orchestrator = options.video_orch;
    var owns_video_orch = false;

    if (video_orch == null and (options.video_mode.record != null or options.video_mode.stream != null)) {
        video_orch = video.Orchestrator.init(allocator, io, session, options.video_mode) catch |err| {
            std.debug.print("Failed to initialize video: {}\n", .{err});
            return;
        };
        owns_video_orch = true;

        // Print stream URL if streaming
        if (video_orch.?.getStreamUrl()) |url| {
            std.debug.print("Streaming at: {s}\n", .{url});
        }

        // Start capture
        video_orch.?.startCapture() catch |err| {
            std.debug.print("Failed to start video capture: {}\n", .{err});
            video_orch.?.deinit();
            return;
        };
    }
    defer if (owns_video_orch) {
        if (video_orch) |orch| {
            orch.stopCapture() catch {};
            orch.deinit();
        }
    };

    // Check for resume mode
    var start_idx: usize = options.start_index orelse 0;
    if (options.resume_mode) {
        if (state.loadState(allocator, io, options.session_ctx)) |loaded| {
            var loaded_state = loaded;
            defer loaded_state.deinit(allocator);
            if (loaded_state.last_action_index) |idx| {
                start_idx = idx;
                std.debug.print("Resuming from command {}...\n", .{idx + 1});
            }
        }
    }

    // Print header
    std.debug.print("Replaying {} commands from {s} (retries: {}, delay: {}ms)...\n", .{
        macro_data.commands.len,
        filename,
        options.max_retries,
        options.retry_delay_ms,
    });

    // Track state for retry logic
    var last_action_index: usize = 0;
    var retry_count: u32 = 0;
    var total_retries: u32 = 0;
    var has_assertions = false;

    // Variables map for capture action - use passed variables or create new
    var owned_variables = std.StringHashMap(state.VarValue).init(allocator);
    const variables: *std.StringHashMap(state.VarValue) = if (options.variables) |v| v else &owned_variables;
    defer if (options.variables == null) {
        var iter = owned_variables.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        owned_variables.deinit();
    };

    // Enable Page domain upfront
    var page = cdp.Page.init(session);
    try page.enable();

    var i: usize = start_idx;
    while (i < macro_data.commands.len) {
        const cmd = macro_data.commands[i];

        // Print progress
        const action_name = cmd.action.toString();
        if (cmd.action == .assert) {
            has_assertions = true;
            if (cmd.selector) |sel| {
                std.debug.print("  [{}/{}] {s} \"{s}\"", .{ i + 1, macro_data.commands.len, action_name, sel });
            } else if (cmd.url) |url_val| {
                std.debug.print("  [{}/{}] {s} URL \"{s}\"", .{ i + 1, macro_data.commands.len, action_name, url_val });
            } else if (cmd.text) |txt| {
                std.debug.print("  [{}/{}] {s} text \"{s}\"", .{ i + 1, macro_data.commands.len, action_name, txt });
            } else {
                std.debug.print("  [{}/{}] {s}", .{ i + 1, macro_data.commands.len, action_name });
            }
        } else {
            if (cmd.selector) |sel| {
                std.debug.print("  [{}/{}] {s} \"{s}\"", .{ i + 1, macro_data.commands.len, action_name, sel });
            } else if (cmd.key) |key| {
                std.debug.print("  [{}/{}] {s} {s}", .{ i + 1, macro_data.commands.len, action_name, key });
            } else if (cmd.file) |f| {
                std.debug.print("  [{}/{}] {s} \"{s}\"", .{ i + 1, macro_data.commands.len, action_name, f });
            } else {
                std.debug.print("  [{}/{}] {s}", .{ i + 1, macro_data.commands.len, action_name });
            }
        }
        if (cmd.value) |val| {
            std.debug.print(" \"{s}\"", .{val});
        }

        // Handle assert command
        if (cmd.action == .assert) {
            const assert_result = assertions.executeAssertion(session, allocator, io, cmd, options.session_ctx, variables) catch false;

            if (assert_result) {
                std.debug.print(" OK\n", .{});
            } else {
                std.debug.print(" FAILED\n", .{});

                // Retry logic
                if (retry_count < options.max_retries) {
                    retry_count += 1;
                    total_retries += 1;
                    std.debug.print("    Retrying from command {} (attempt {}/{})...\n", .{
                        last_action_index + 1,
                        retry_count,
                        options.max_retries,
                    });
                    utils.waitForTime(options.retry_delay_ms);
                    i = last_action_index;
                    continue;
                }

                // Permanent failure
                std.debug.print("    Assertion failed after {} retries\n", .{options.max_retries});

                // Check for fallback
                const fallback = cmd.fallback orelse options.fallback_file;
                if (fallback) |fb| {
                    std.debug.print("    Switching to fallback: {s}\n", .{fb});
                    return replayCommandsWithOptions(session, allocator, io, fb, options);
                }

                // Save state for resume
                var save_state = state.ReplayState{
                    .macro_file = allocator.dupe(u8, filename) catch null,
                    .last_action_index = last_action_index,
                    .last_attempted_index = i,
                    .retry_count = retry_count,
                    .status = .failed,
                };
                defer save_state.deinit(allocator);
                state.saveState(save_state, allocator, io, options.session_ctx) catch {};
                return;
            }

            retry_count = 0;
            i += 1;
            continue;
        }

        std.debug.print("\n", .{});

        // Track last action command for retry
        if (cmd.action != .wait and cmd.action != .press and cmd.action != .scroll and cmd.action != .assert) {
            last_action_index = i;
        }

        // Execute the command based on action type
        const action_ctx = actions.ActionContext{
            .session = session,
            .allocator = allocator,
            .io = io,
            .variables = variables,
            .page = &page,
            .macro_file = filename,
            .options = options,
            .video_orch = video_orch,
        };

        actions.executeCommand(action_ctx, cmd) catch |err| {
            // Mark errors bubble up to foreach handler
            return err;
        };

        // Capture video frame after command (if video mode is enabled)
        if (video_orch) |orch| {
            _ = orch.captureFrame();
        }

        // Delay between commands
        const now_ns = std.Io.Timestamp.now(io, .real).nanoseconds;
        const seed: u64 = @as(u64, i) *% 12345 +% @as(u64, @intCast(@mod(now_ns, std.math.maxInt(i64))));
        const delay_ms = interval.getDelay(seed);
        utils.waitForTime(delay_ms);

        i += 1;
    }

    // Clear state on successful completion
    state.clearState(allocator, io, options.session_ctx) catch {};

    if (has_assertions) {
        if (total_retries > 0) {
            std.debug.print("Replay complete. {} retries needed.\n", .{total_retries});
        } else {
            std.debug.print("Replay complete. All assertions passed.\n", .{});
        }
    } else {
        std.debug.print("Replay complete.\n", .{});
    }
}
