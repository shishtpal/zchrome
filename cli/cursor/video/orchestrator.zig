//! Orchestrator module for video recording and streaming.
//!
//! Coordinates frame capture with encoding and streaming outputs.
//! Uses synchronous frame capture to avoid CDP thread-safety issues.

const std = @import("std");
const cdp = @import("cdp");
const frame_capture = @import("frame_capture.zig");
const encoder = @import("encoder.zig");
const stream = @import("stream.zig");

const FrameCapture = frame_capture.FrameCapture;
const FrameCaptureConfig = frame_capture.FrameCaptureConfig;
const Frame = frame_capture.Frame;
const VideoEncoder = encoder.VideoEncoder;
const EncoderConfig = encoder.EncoderConfig;
const VideoFormat = encoder.VideoFormat;
const StreamServer = stream.StreamServer;
const StreamConfig = stream.StreamConfig;
const ViewerInput = stream.ViewerInput;

/// Recording configuration
pub const RecordConfig = struct {
    output_path: []const u8,
    format: VideoFormat = .mp4,
    fps: u32 = 10,
    quality: u8 = 80,
};

/// Output mode configuration
pub const OutputMode = struct {
    record: ?RecordConfig = null,
    stream: ?StreamConfig = null,
};

/// Orchestrator coordinates capture with outputs
/// Uses synchronous capture - call captureFrame() from the main thread
pub const Orchestrator = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    session: *cdp.Session,
    mode: OutputMode,

    // Components
    frame_capture_inst: ?*FrameCapture = null,
    video_encoder: ?*VideoEncoder = null,
    stream_server: ?*StreamServer = null,

    // State
    is_running: bool = false,
    frame_count: u64 = 0,
    start_time_ns: ?i128 = null,
    last_capture_ns: i128 = 0,
    frame_interval_ns: u64 = 100_000_000, // 100ms = 10fps default

    // Input injection for interactive mode
    input: ?cdp.Input = null,

    const Self = @This();

    /// Initialize the orchestrator
    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        session: *cdp.Session,
        mode: OutputMode,
    ) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .io = io,
            .session = session,
            .mode = mode,
        };

        // Check for recording and verify FFmpeg
        if (mode.record) |_| {
            if (!VideoEncoder.checkFFmpeg(allocator, io)) {
                encoder.printFFmpegNotFound();
                allocator.destroy(self);
                return error.FFmpegNotFound;
            }
        }

        // Initialize stream server if streaming enabled
        if (mode.stream) |stream_config| {
            self.stream_server = try StreamServer.init(allocator, io, stream_config);

            // Set up input callback for interactive mode
            if (stream_config.interactive) {
                self.input = cdp.Input.init(session);
                self.stream_server.?.setInputCallback(handleViewerInputCallback, self);
            }

            try self.stream_server.?.start();
        }

        // Initialize video encoder if recording enabled
        if (mode.record) |record_config| {
            const enc = try allocator.create(VideoEncoder);
            enc.* = try VideoEncoder.init(allocator, io, .{
                .output_path = record_config.output_path,
                .format = record_config.format,
                .fps = record_config.fps,
                .quality = record_config.quality,
            });
            self.video_encoder = enc;

            // Calculate frame interval from fps
            self.frame_interval_ns = @divFloor(1_000_000_000, record_config.fps);
        }

        return self;
    }

    /// Start capture session (initializes frame capture, but doesn't start a thread)
    pub fn startCapture(self: *Self) !void {
        if (self.is_running) return error.AlreadyRunning;

        const fps = blk: {
            if (self.mode.record) |r| break :blk r.fps;
            break :blk @as(u32, 10);
        };

        // Create frame capture instance
        const fc = try self.allocator.create(FrameCapture);
        fc.* = try FrameCapture.init(self.session, self.allocator, self.io, .{
            .fps = fps,
            .format = .jpeg,
            .quality = 80,
            .skip_identical_frames = false, // Don't skip for video
        });
        self.frame_capture_inst = fc;

        self.is_running = true;
        self.start_time_ns = std.Io.Timestamp.now(self.io, .real).nanoseconds;
        self.last_capture_ns = self.start_time_ns.?;
    }

    /// Capture a single frame (call this from the main replay loop)
    /// Returns true if a frame was captured, false if skipped due to timing
    pub fn captureFrame(self: *Self) bool {
        if (!self.is_running) return false;

        const now_ns = std.Io.Timestamp.now(self.io, .real).nanoseconds;
        const elapsed_ns: u64 = @intCast(@max(0, now_ns - self.last_capture_ns));

        // Skip if not enough time has passed
        if (elapsed_ns < self.frame_interval_ns) {
            return false;
        }

        // Capture frame
        if (self.frame_capture_inst) |fc| {
            if (fc.captureFrame()) |frame_data| {
                var f = frame_data;
                defer f.deinit(self.allocator);

                self.frame_count += 1;
                self.last_capture_ns = now_ns;

                // Send to encoder
                if (self.video_encoder) |enc| {
                    enc.writeFrame(&f) catch |err| {
                        std.debug.print("Encoder error: {}\n", .{err});
                    };
                }

                // Broadcast to stream
                if (self.stream_server) |srv| {
                    srv.broadcastFrame(&f) catch |err| {
                        std.debug.print("Stream error: {}\n", .{err});
                    };
                }

                return true;
            } else |err| {
                if (err != error.IdenticalFrame) {
                    std.debug.print("Capture error: {}\n", .{err});
                }
            }
        }

        return false;
    }

    /// Force capture a frame regardless of timing
    pub fn captureFrameNow(self: *Self) void {
        if (!self.is_running) return;

        const now_ns = std.Io.Timestamp.now(self.io, .real).nanoseconds;

        if (self.frame_capture_inst) |fc| {
            if (fc.captureFrame()) |frame_data| {
                var f = frame_data;
                defer f.deinit(self.allocator);

                self.frame_count += 1;
                self.last_capture_ns = now_ns;

                // Send to encoder
                if (self.video_encoder) |enc| {
                    enc.writeFrame(&f) catch |err| {
                        std.debug.print("Encoder error: {}\n", .{err});
                    };
                }

                // Broadcast to stream
                if (self.stream_server) |srv| {
                    srv.broadcastFrame(&f) catch |err| {
                        std.debug.print("Stream error: {}\n", .{err});
                    };
                }
            } else |_| {}
        }
    }

    /// Handle viewer input callback (for interactive mode)
    fn handleViewerInputCallback(input_event: ViewerInput, ctx: ?*anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ctx orelse return));
        self.handleViewerInput(input_event);
    }

    /// Handle input from viewer
    pub fn handleViewerInput(self: *Self, input_event: ViewerInput) void {
        if (self.input == null) return;
        var inp = self.input.?;

        switch (input_event.input_type) {
            .click => {
                const x = input_event.x orelse return;
                const y = input_event.y orelse return;

                // Move mouse and click
                inp.dispatchMouseEvent(.{
                    .type = .mouseMoved,
                    .x = x,
                    .y = y,
                }) catch {};

                inp.dispatchMouseEvent(.{
                    .type = .mousePressed,
                    .x = x,
                    .y = y,
                    .button = .left,
                    .click_count = 1,
                }) catch {};

                inp.dispatchMouseEvent(.{
                    .type = .mouseReleased,
                    .x = x,
                    .y = y,
                    .button = .left,
                    .click_count = 1,
                }) catch {};

                std.debug.print("  [viewer] click at ({}, {})\n", .{ x, y });
            },
            .mousemove => {
                const x = input_event.x orelse return;
                const y = input_event.y orelse return;

                inp.dispatchMouseEvent(.{
                    .type = .mouseMoved,
                    .x = x,
                    .y = y,
                }) catch {};
            },
            .keydown => {},
            .keyup => {},
            .scroll => {},
        }
    }

    /// Stop capture and finalize
    pub fn stopCapture(self: *Self) !void {
        if (!self.is_running) return;

        self.is_running = false;

        // Finalize encoder
        if (self.video_encoder) |enc| {
            try enc.finalize();
        }

        // Calculate stats
        const elapsed_ns: u64 = if (self.start_time_ns) |start_val|
            @intCast(@max(0, std.Io.Timestamp.now(self.io, .real).nanoseconds - start_val))
        else
            0;
        const elapsed_secs = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;

        // Print summary
        if (self.mode.record) |record_config| {
            std.debug.print("\nVideo saved: {s}\n", .{record_config.output_path});
            std.debug.print("  Frames: {}\n", .{self.frame_count});
            std.debug.print("  Duration: {d:.1}s\n", .{elapsed_secs});
        }

        if (self.stream_server) |_| {
            std.debug.print("Stream ended. {} frames broadcast.\n", .{self.frame_count});
        }
    }

    /// Check if currently running
    pub fn isRunning(self: *const Self) bool {
        return self.is_running;
    }

    /// Get frame count
    pub fn getFrameCount(self: *const Self) u64 {
        return self.frame_count;
    }

    /// Get stream URL (if streaming)
    pub fn getStreamUrl(self: *const Self) ?[]const u8 {
        if (self.stream_server) |_| {
            return "http://localhost:8080/";
        }
        return null;
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        // Stop capture if running
        self.stopCapture() catch {};

        // Clean up components
        if (self.frame_capture_inst) |fc| {
            var fc_mut = fc;
            fc_mut.deinit();
            self.allocator.destroy(fc);
        }

        if (self.video_encoder) |enc| {
            var enc_mut = enc;
            enc_mut.deinit();
            self.allocator.destroy(enc);
        }

        if (self.stream_server) |srv| {
            srv.deinit();
        }

        self.allocator.destroy(self);
    }
};

/// Parse video options from command line arguments
pub fn parseVideoOptions(args: []const []const u8) OutputMode {
    var mode = OutputMode{};

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.startsWith(u8, arg, "--record=")) {
            const path = arg["--record=".len..];
            mode.record = RecordConfig{
                .output_path = path,
                .format = VideoFormat.fromPath(path) orelse .mp4,
            };
        } else if (std.mem.startsWith(u8, arg, "--fps=")) {
            const fps_str = arg["--fps=".len..];
            const fps = std.fmt.parseInt(u32, fps_str, 10) catch 10;
            if (mode.record) |*r| {
                r.fps = fps;
            }
        } else if (std.mem.startsWith(u8, arg, "--quality=")) {
            const q_str = arg["--quality=".len..];
            const quality = std.fmt.parseInt(u8, q_str, 10) catch 80;
            if (mode.record) |*r| {
                r.quality = quality;
            }
        } else if (std.mem.eql(u8, arg, "--stream")) {
            mode.stream = StreamConfig{};
        } else if (std.mem.startsWith(u8, arg, "--port=")) {
            const port_str = arg["--port=".len..];
            const port = std.fmt.parseInt(u16, port_str, 10) catch 8080;
            if (mode.stream) |*s| {
                s.port = port;
            } else {
                mode.stream = StreamConfig{ .port = port };
            }
        } else if (std.mem.eql(u8, arg, "--interactive")) {
            if (mode.stream) |*s| {
                s.interactive = true;
            } else {
                mode.stream = StreamConfig{ .interactive = true };
            }
        }
    }

    return mode;
}

/// Check if video mode is enabled in arguments
pub fn hasVideoMode(args: []const []const u8) bool {
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--record=") or
            std.mem.eql(u8, arg, "--stream") or
            std.mem.startsWith(u8, arg, "--port="))
        {
            return true;
        }
    }
    return false;
}
