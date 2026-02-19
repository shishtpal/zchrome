const std = @import("std");

/// Headless mode options
pub const Headless = enum {
    off, // Run with GUI
    new, // --headless=new (Chrome 112+)
    old, // --headless (old mode)
};

/// Options for launching Chrome
pub const LaunchOptions = struct {
    /// Path to Chrome executable (auto-detect if null)
    executable_path: ?[]const u8 = null,

    /// Headless mode
    headless: Headless = .new,

    /// Remote debugging port (0 = random available port)
    port: u16 = 0,

    /// User data directory (null = temp directory)
    user_data_dir: ?[]const u8 = null,

    /// Window size
    window_size: ?struct {
        width: u32,
        height: u32,
    } = null,

    /// Ignore certificate errors
    ignore_certificate_errors: bool = false,

    /// Disable GPU (recommended for headless)
    disable_gpu: bool = true,

    /// Disable sandbox (needed for some environments)
    no_sandbox: bool = false,

    /// Additional Chrome arguments
    extra_args: ?[]const []const u8 = null,

    /// Allocator for memory allocations
    allocator: std.mem.Allocator,

    /// I/O context for networking
    io: std.Io,

    /// Connection timeout in milliseconds
    timeout_ms: u32 = 30_000,
};
