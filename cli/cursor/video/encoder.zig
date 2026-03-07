//! Video encoder module using FFmpeg subprocess.
//!
//! Pipes captured frames directly to FFmpeg stdin for encoding.

const std = @import("std");
const frame_capture = @import("frame_capture.zig");
const Frame = frame_capture.Frame;
const ScreenshotFormat = frame_capture.ScreenshotFormat;

/// Output video format
pub const VideoFormat = enum {
    mp4,
    webm,
    gif,

    pub fn extension(self: VideoFormat) []const u8 {
        return switch (self) {
            .mp4 => ".mp4",
            .webm => ".webm",
            .gif => ".gif",
        };
    }

    pub fn fromPath(path: []const u8) ?VideoFormat {
        if (std.mem.endsWith(u8, path, ".mp4")) return .mp4;
        if (std.mem.endsWith(u8, path, ".webm")) return .webm;
        if (std.mem.endsWith(u8, path, ".gif")) return .gif;
        return null;
    }
};

/// Encoder configuration
pub const EncoderConfig = struct {
    output_path: []const u8,
    format: VideoFormat = .mp4,
    fps: u32 = 10,
    quality: u8 = 80,
    width: ?u32 = null,
    height: ?u32 = null,
    input_format: ScreenshotFormat = .jpeg,
};

/// Video encoder state
pub const VideoEncoder = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    config: EncoderConfig,
    child: ?std.process.Child = null,
    frame_count: u64 = 0,
    started: bool = false,
    finalized: bool = false,

    // Buffers for FFmpeg arguments (need to persist during process lifetime)
    fps_buf: [16]u8 = undefined,
    crf_buf: [8]u8 = undefined,

    const Self = @This();

    /// Check if FFmpeg is available
    pub fn checkFFmpeg(_: std.mem.Allocator, io: std.Io) bool {
        const check_child = std.process.spawn(io, .{
            .argv = &.{ "ffmpeg", "-version" },
            .stdin = .ignore,
            .stdout = .ignore,
            .stderr = .ignore,
        }) catch return false;

        var child = check_child;
        const term = child.wait(io) catch return false;
        return switch (term) {
            .exited => |code| code == 0,
            else => false,
        };
    }

    /// Initialize the encoder
    pub fn init(allocator: std.mem.Allocator, io: std.Io, config: EncoderConfig) !Self {
        return Self{
            .allocator = allocator,
            .io = io,
            .config = config,
        };
    }

    /// Start FFmpeg process
    pub fn start(self: *Self) !void {
        if (self.started) return error.AlreadyStarted;

        // Build FFmpeg arguments
        var args_list: [32][]const u8 = undefined;
        var arg_idx: usize = 0;

        // Base command
        args_list[arg_idx] = "ffmpeg";
        arg_idx += 1;
        args_list[arg_idx] = "-y"; // Overwrite output
        arg_idx += 1;

        // Input settings
        args_list[arg_idx] = "-f";
        arg_idx += 1;
        args_list[arg_idx] = "image2pipe";
        arg_idx += 1;
        args_list[arg_idx] = "-framerate";
        arg_idx += 1;

        const fps_str = std.fmt.bufPrint(&self.fps_buf, "{d}", .{self.config.fps}) catch "10";
        args_list[arg_idx] = fps_str;
        arg_idx += 1;

        args_list[arg_idx] = "-i";
        arg_idx += 1;
        args_list[arg_idx] = "-"; // Read from stdin
        arg_idx += 1;

        // Quality and codec settings based on format
        switch (self.config.format) {
            .mp4 => {
                args_list[arg_idx] = "-c:v";
                arg_idx += 1;
                args_list[arg_idx] = "libx264";
                arg_idx += 1;
                args_list[arg_idx] = "-preset";
                arg_idx += 1;
                args_list[arg_idx] = "medium";
                arg_idx += 1;
                args_list[arg_idx] = "-crf";
                arg_idx += 1;
                // Map quality 0-100 to CRF 51-0 (lower CRF = better quality)
                const crf_val = 51 - @as(u32, self.config.quality) * 51 / 100;
                const crf_str = std.fmt.bufPrint(&self.crf_buf, "{d}", .{crf_val}) catch "23";
                args_list[arg_idx] = crf_str;
                arg_idx += 1;
                args_list[arg_idx] = "-pix_fmt";
                arg_idx += 1;
                args_list[arg_idx] = "yuv420p";
                arg_idx += 1;
            },
            .webm => {
                args_list[arg_idx] = "-c:v";
                arg_idx += 1;
                args_list[arg_idx] = "libvpx-vp9";
                arg_idx += 1;
                args_list[arg_idx] = "-crf";
                arg_idx += 1;
                const crf_val = 63 - @as(u32, self.config.quality) * 63 / 100;
                const crf_str = std.fmt.bufPrint(&self.crf_buf, "{d}", .{crf_val}) catch "30";
                args_list[arg_idx] = crf_str;
                arg_idx += 1;
                args_list[arg_idx] = "-b:v";
                arg_idx += 1;
                args_list[arg_idx] = "0";
                arg_idx += 1;
            },
            .gif => {
                args_list[arg_idx] = "-vf";
                arg_idx += 1;
                args_list[arg_idx] = "fps=10,scale=640:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse";
                arg_idx += 1;
            },
        }

        // Output file
        args_list[arg_idx] = self.config.output_path;
        arg_idx += 1;

        // Spawn FFmpeg process
        const child = std.process.spawn(self.io, .{
            .argv = args_list[0..arg_idx],
            .stdin = .pipe,
            .stdout = .ignore,
            .stderr = .pipe,
        }) catch return error.SpawnFailed;

        self.child = child;
        self.started = true;
    }

    /// Write a frame to FFmpeg
    pub fn writeFrame(self: *Self, frame: *const Frame) !void {
        if (!self.started) {
            try self.start();
        }

        if (self.child) |*child| {
            if (child.stdin) |stdin| {
                var writer = stdin.writer(self.io, &.{});
                _ = writer.interface.write(frame.data) catch return error.WriteFailed;
                writer.interface.flush() catch return error.WriteFailed;
                self.frame_count += 1;
            } else {
                return error.StdinNotAvailable;
            }
        } else {
            return error.ProcessNotStarted;
        }
    }

    /// Write raw image data to FFmpeg
    pub fn writeRawFrame(self: *Self, data: []const u8) !void {
        if (!self.started) {
            try self.start();
        }

        if (self.child) |*child| {
            if (child.stdin) |stdin| {
                var write_buf: [4096]u8 = undefined;
                var writer = stdin.writer(self.io, &write_buf);
                
                // Write in chunks
                var offset: usize = 0;
                while (offset < data.len) {
                    const chunk_size = @min(data.len - offset, 4096);
                    _ = writer.interface.write(data[offset..][0..chunk_size]) catch return error.WriteFailed;
                    writer.interface.flush() catch return error.WriteFailed;
                    offset += chunk_size;
                }
                self.frame_count += 1;
            } else {
                return error.StdinNotAvailable;
            }
        } else {
            return error.ProcessNotStarted;
        }
    }

    /// Finalize encoding (close stdin, wait for FFmpeg)
    pub fn finalize(self: *Self) !void {
        if (self.finalized) return;
        self.finalized = true;

        // Close stdin to signal EOF to FFmpeg, then null it out
        // to prevent double-close in child.wait()
        if (self.child) |*child| {
            if (child.stdin) |stdin| {
                stdin.close(self.io);
                child.stdin = null;
            }
        }

        // Wait for FFmpeg to finish
        if (self.child) |*child| {
            const term = child.wait(self.io) catch return error.WaitFailed;
            switch (term) {
                .exited => |code| {
                    if (code != 0) {
                        std.debug.print("FFmpeg exited with code: {}\n", .{code});
                        return error.FFmpegFailed;
                    }
                },
                .signal => |sig| {
                    std.debug.print("FFmpeg killed by signal: {}\n", .{@intFromEnum(sig)});
                    return error.FFmpegFailed;
                },
                else => return error.FFmpegFailed,
            }
        }
    }

    /// Get total frames written
    pub fn getFrameCount(self: *const Self) u64 {
        return self.frame_count;
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        if (!self.finalized) {
            self.finalize() catch {};
        }
        self.child = null;
    }
};

/// Print error message when FFmpeg is not found
pub fn printFFmpegNotFound() void {
    std.debug.print(
        \\Video recording requires FFmpeg to be installed.
        \\
        \\Installation:
        \\  Windows: winget install FFmpeg
        \\           or download from https://ffmpeg.org/download.html
        \\  macOS:   brew install ffmpeg
        \\  Linux:   sudo apt install ffmpeg  (Debian/Ubuntu)
        \\           sudo dnf install ffmpeg  (Fedora)
        \\
    , .{});
}
