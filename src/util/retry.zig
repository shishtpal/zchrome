const std = @import("std");

/// Configuration for retry behavior
pub const RetryOptions = struct {
    max_attempts: u32 = 10,
    initial_delay_ms: u64 = 100,
    max_delay_ms: u64 = 5_000,
    backoff_factor: f64 = 2.0,
};

/// Retry a function with exponential backoff
pub fn retry(
    comptime T: type,
    opts: RetryOptions,
    context: anytype,
    comptime func: fn (@TypeOf(context)) anyerror!T,
) anyerror!T {
    var delay_ms: u64 = opts.initial_delay_ms;
    var last_error: anyerror = error.Unknown;

    var attempt: u32 = 0;
    while (attempt < opts.max_attempts) : (attempt += 1) {
        const result = func(context) catch |err| {
            last_error = err;
            if (attempt < opts.max_attempts - 1) {
                std.time.sleep(delay_ms * std.time.ns_per_ms);
                delay_ms = @min(
                    @as(u64, @intFromFloat(@as(f64, @floatFromInt(delay_ms)) * opts.backoff_factor)),
                    opts.max_delay_ms,
                );
            }
            continue;
        };
        return result;
    }

    return last_error;
}

/// Retry a function with exponential backoff (no context)
pub fn retryNoContext(
    comptime T: type,
    opts: RetryOptions,
    comptime func: fn () anyerror!T,
) anyerror!T {
    var delay_ms: u64 = opts.initial_delay_ms;
    var last_error: anyerror = error.Unknown;

    var attempt: u32 = 0;
    while (attempt < opts.max_attempts) : (attempt += 1) {
        const result = func() catch |err| {
            last_error = err;
            if (attempt < opts.max_attempts - 1) {
                std.time.sleep(delay_ms * std.time.ns_per_ms);
                delay_ms = @min(
                    @as(u64, @intFromFloat(@as(f64, @floatFromInt(delay_ms)) * opts.backoff_factor)),
                    opts.max_delay_ms,
                );
            }
            continue;
        };
        return result;
    }

    return last_error;
}

// ─── Tests ──────────────────────────────────────────────────────────────────

test "retry - succeeds on first attempt" {
    const ctx = struct {
        var attempts: u32 = 0;

        fn run(_: void) anyerror!u32 {
            attempts += 1;
            return 42;
        }
    };

    ctx.attempts = 0;
    const result = try retry(u32, .{ .max_attempts = 3 }, {}, ctx.run);
    try std.testing.expectEqual(@as(u32, 42), result);
    try std.testing.expectEqual(@as(u32, 1), ctx.attempts);
}

test "retry - succeeds after failures" {
    const ctx = struct {
        var attempts: u32 = 0;

        fn run(_: void) anyerror!u32 {
            attempts += 1;
            if (attempts < 3) return error.TemporaryFailure;
            return 42;
        }
    };

    ctx.attempts = 0;
    const result = try retry(u32, .{
        .max_attempts = 5,
        .initial_delay_ms = 1,
    }, {}, ctx.run);
    try std.testing.expectEqual(@as(u32, 42), result);
    try std.testing.expectEqual(@as(u32, 3), ctx.attempts);
}

test "retry - fails after max attempts" {
    const ctx = struct {
        var attempts: u32 = 0;

        fn run(_: void) anyerror!u32 {
            attempts += 1;
            return error.PersistentFailure;
        }
    };

    ctx.attempts = 0;
    const result = retry(u32, .{
        .max_attempts = 3,
        .initial_delay_ms = 1,
    }, {}, ctx.run);
    try std.testing.expectError(error.PersistentFailure, result);
    try std.testing.expectEqual(@as(u32, 3), ctx.attempts);
}
