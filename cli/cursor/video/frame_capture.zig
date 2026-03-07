//! Frame capture module for video recording and streaming.
//!
//! Captures browser screenshots at configurable intervals using CDP.

const std = @import("std");
const cdp = @import("cdp");

/// Screenshot format for capture
pub const ScreenshotFormat = enum {
    png,
    jpeg,
    webp,

    pub fn mimeType(self: ScreenshotFormat) []const u8 {
        return switch (self) {
            .png => "image/png",
            .jpeg => "image/jpeg",
            .webp => "image/webp",
        };
    }
};

/// Configuration for frame capture
pub const FrameCaptureConfig = struct {
    fps: u32 = 10,
    format: ScreenshotFormat = .jpeg,
    quality: ?u8 = 80,
    capture_beyond_viewport: bool = false,
    skip_identical_frames: bool = true,
};

/// A captured frame with metadata
pub const Frame = struct {
    data: []const u8,
    timestamp_ns: i128,
    index: u64,
    format: ScreenshotFormat,

    pub fn deinit(self: *Frame, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
        self.* = undefined;
    }
};

/// Frame capture callback type
pub const FrameCallback = *const fn (frame: *const Frame, ctx: ?*anyopaque) void;

/// Frame capture controller
pub const FrameCapture = struct {
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    io: std.Io,
    config: FrameCaptureConfig,
    page: cdp.Page,

    // State
    frame_count: u64 = 0,
    last_frame_hash: ?u64 = null,
    enabled: bool = false,

    // Continuous capture
    capture_thread: ?std.Thread = null,
    should_stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    frame_callback: ?FrameCallback = null,
    callback_ctx: ?*anyopaque = null,

    const Self = @This();

    /// Initialize frame capture
    pub fn init(session: *cdp.Session, allocator: std.mem.Allocator, io: std.Io, config: FrameCaptureConfig) !Self {
        var page = cdp.Page.init(session);
        try page.enable();

        return Self{
            .session = session,
            .allocator = allocator,
            .io = io,
            .config = config,
            .page = page,
            .enabled = true,
        };
    }

    /// Capture a single frame
    pub fn captureFrame(self: *Self) !Frame {
        const screenshot_data = try self.page.captureScreenshot(self.allocator, .{
            .format = switch (self.config.format) {
                .png => .png,
                .jpeg => .jpeg,
                .webp => .webp,
            },
            .quality = if (self.config.format == .jpeg) @as(i32, @intCast(self.config.quality orelse 80)) else null,
            .capture_beyond_viewport = if (self.config.capture_beyond_viewport) true else null,
        });
        defer self.allocator.free(screenshot_data);

        // Decode base64
        const decoded = try cdp.base64.decodeAlloc(self.allocator, screenshot_data);
        errdefer self.allocator.free(decoded);

        // Check for identical frame
        if (self.config.skip_identical_frames) {
            const hash = std.hash.Wyhash.hash(0, decoded);
            if (self.last_frame_hash) |last_hash| {
                if (hash == last_hash) {
                    self.allocator.free(decoded);
                    return error.IdenticalFrame;
                }
            }
            self.last_frame_hash = hash;
        }

        const timestamp = std.Io.Timestamp.now(self.io, .real);
        const frame_index = self.frame_count;
        self.frame_count += 1;

        return Frame{
            .data = decoded,
            .timestamp_ns = timestamp.nanoseconds,
            .index = frame_index,
            .format = self.config.format,
        };
    }

    /// Start continuous capture in background thread
    pub fn startContinuousCapture(self: *Self, callback: FrameCallback, ctx: ?*anyopaque) !void {
        if (self.capture_thread != null) return error.AlreadyRunning;

        self.frame_callback = callback;
        self.callback_ctx = ctx;
        self.should_stop.store(false, .release);

        self.capture_thread = try std.Thread.spawn(.{}, captureLoop, .{self});
    }

    /// Stop continuous capture
    pub fn stopContinuousCapture(self: *Self) void {
        self.should_stop.store(true, .release);
        if (self.capture_thread) |thread| {
            thread.join();
            self.capture_thread = null;
        }
    }

    fn captureLoop(self: *Self) void {
        const frame_interval_ns: u64 = @divFloor(1_000_000_000, self.config.fps);

        while (!self.should_stop.load(.acquire)) {
            const start_time = std.Io.Timestamp.now(self.io, .real);

            // Capture frame
            if (self.captureFrame()) |frame| {
                var f = frame;
                if (self.frame_callback) |callback| {
                    callback(&f, self.callback_ctx);
                }
                f.deinit(self.allocator);
            } else |err| {
                if (err != error.IdenticalFrame) {
                    std.debug.print("Frame capture error: {}\n", .{err});
                }
            }

            // Sleep until next frame
            const elapsed_time = std.Io.Timestamp.now(self.io, .real);
            const elapsed_ns: u64 = @intCast(@max(0, elapsed_time.nanoseconds - start_time.nanoseconds));
            if (elapsed_ns < frame_interval_ns) {
                const sleep_ns = frame_interval_ns - elapsed_ns;
                const sleep_ms = @as(u32, @intCast(sleep_ns / 1_000_000));
                if (sleep_ms > 0) {
                    var j: u32 = 0;
                    while (j < sleep_ms * 1000) : (j += 1) std.atomic.spinLoopHint();
                }
            }
        }
    }

    /// Get frame interval in milliseconds
    pub fn getFrameIntervalMs(self: *const Self) u32 {
        return @divFloor(1000, self.config.fps);
    }

    /// Get total frames captured
    pub fn getFrameCount(self: *const Self) u64 {
        return self.frame_count;
    }

    pub fn deinit(self: *Self) void {
        self.stopContinuousCapture();
        self.enabled = false;
    }
};
