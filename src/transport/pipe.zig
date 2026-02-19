const std = @import("std");

/// Pipe transport for Chrome's --remote-debugging-pipe mode
/// Uses file descriptors 3 (read) and 4 (write) by convention
pub const PipeTransport = struct {
    read_file: std.fs.File,
    write_file: std.fs.File,
    allocator: std.mem.Allocator,
    read_buf: std.ArrayList(u8),
    is_closed: bool,

    const Self = @This();

    /// Initialize a pipe transport with the given file descriptors
    /// Chrome uses fd 3 for reading and fd 4 for writing
    pub fn init(
        allocator: std.mem.Allocator,
        read_fd: std.posix.fd_t,
        write_fd: std.posix.fd_t,
    ) Self {
        return .{
            .read_file = std.fs.File{ .handle = read_fd },
            .write_file = std.fs.File{ .handle = write_fd },
            .allocator = allocator,
            .read_buf = std.ArrayList(u8).init(allocator),
            .is_closed = false,
        };
    }

    /// Send a message (zero-delimited)
    pub fn send(self: *Self, message: []const u8) !void {
        // Write message followed by null byte delimiter
        _ = try self.write_file.write(message);
        _ = try self.write_file.write(&[_]u8{0});
    }

    /// Receive a message (reads until null byte)
    /// Caller owns the returned slice
    pub fn receive(self: *Self) ![]const u8 {
        self.read_buf.clearRetainingCapacity();

        while (true) {
            var byte: [1]u8 = undefined;
            const n = try self.read_file.read(&byte);

            if (n == 0) {
                return error.ConnectionClosed;
            }

            if (byte[0] == 0) {
                // End of message
                break;
            }

            try self.read_buf.append(byte[0]);
        }

        return try self.read_buf.toOwnedSlice();
    }

    /// Close both file descriptors
    pub fn close(self: *Self) void {
        if (!self.is_closed) {
            self.read_file.close();
            self.write_file.close();
            self.read_buf.deinit();
            self.is_closed = true;
        }
    }

    /// Get the read file descriptor
    pub fn getReadFd(self: *const Self) std.posix.fd_t {
        return self.read_file.handle;
    }

    /// Get the write file descriptor
    pub fn getWriteFd(self: *const Self) std.posix.fd_t {
        return self.write_file.handle;
    }
};

// ─── Tests ──────────────────────────────────────────────────────────────────

test "PipeTransport init" {
    // Create a pipe pair for testing
    var fds: [2]std.posix.fd_t = undefined;
    const result = std.posix.pipe(&fds);
    if (result != 0) return error.TestFailed;

    var transport = PipeTransport.init(std.testing.allocator, fds[0], fds[1]);
    defer transport.close();

    try std.testing.expectEqual(fds[0], transport.getReadFd());
    try std.testing.expectEqual(fds[1], transport.getWriteFd());
}

test "PipeTransport send and receive" {
    // Create a pipe pair for testing
    var fds: [2]std.posix.fd_t = undefined;
    const result = std.posix.pipe(&fds);
    if (result != 0) return error.TestFailed;

    var transport = PipeTransport.init(std.testing.allocator, fds[0], fds[1]);
    defer transport.close();

    // Send a message
    try transport.send("Hello, World!");

    // Receive the message
    const received = try transport.receive();
    defer std.testing.allocator.free(received);

    try std.testing.expectEqualStrings("Hello, World!", received);
}

test "PipeTransport multiple messages" {
    // Create a pipe pair for testing
    var fds: [2]std.posix.fd_t = undefined;
    const result = std.posix.pipe(&fds);
    if (result != 0) return error.TestFailed;

    var transport = PipeTransport.init(std.testing.allocator, fds[0], fds[1]);
    defer transport.close();

    // Send multiple messages
    try transport.send("First");
    try transport.send("Second");
    try transport.send("Third");

    // Receive them in order
    const msg1 = try transport.receive();
    defer std.testing.allocator.free(msg1);
    try std.testing.expectEqualStrings("First", msg1);

    const msg2 = try transport.receive();
    defer std.testing.allocator.free(msg2);
    try std.testing.expectEqualStrings("Second", msg2);

    const msg3 = try transport.receive();
    defer std.testing.allocator.free(msg3);
    try std.testing.expectEqualStrings("Third", msg3);
}
