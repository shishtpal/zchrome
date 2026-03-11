//! Chrome launcher with pipe-based debugging.
//!
//! Spawns Chrome with --remote-debugging-pipe and sets up file descriptors
//! 3 (Chrome reads) and 4 (Chrome writes) for CDP communication.

const std = @import("std");
const json = @import("json");
const builtin = @import("builtin");

/// Chrome process with pipe-based CDP communication.
pub const ChromePipe = struct {
    /// Pipe for sending commands to Chrome (parent writes, Chrome reads via fd 3)
    write_pipe: std.fs.File,
    /// Pipe for receiving responses from Chrome (Chrome writes via fd 4, parent reads)
    read_pipe: std.fs.File,
    /// Read buffer for accumulating responses
    read_buf: std.ArrayList(u8),
    /// Allocator
    allocator: std.mem.Allocator,
    /// IO context
    io: std.Io,
    /// Next command ID
    next_id: u32,
    /// Whether pipes are closed
    is_closed: bool,

    const Self = @This();

    /// Spawn Chrome with pipe-based debugging.
    /// Returns a ChromePipe for CDP communication.
    pub fn spawn(
        allocator: std.mem.Allocator,
        io: std.Io,
        chrome_path: []const u8,
        base_args: []const []const u8,
    ) !*Self {
        // Create pipes for communication
        // pipe_to_chrome: parent writes to [1], Chrome reads from [0] (becomes fd 3)
        // pipe_from_chrome: Chrome writes to [1] (becomes fd 4), parent reads from [0]
        const pipe_to_chrome = try std.posix.pipe();
        errdefer {
            std.posix.close(pipe_to_chrome[0]);
            std.posix.close(pipe_to_chrome[1]);
        }

        const pipe_from_chrome = try std.posix.pipe();
        errdefer {
            std.posix.close(pipe_from_chrome[0]);
            std.posix.close(pipe_from_chrome[1]);
        }

        // Build full argv with pipe debugging flags
        var argv_list: std.ArrayList([]const u8) = .empty;
        defer argv_list.deinit(allocator);

        try argv_list.append(allocator, chrome_path);

        // Add base args
        for (base_args) |arg| {
            try argv_list.append(allocator, arg);
        }

        // Add pipe debugging flags
        try argv_list.append(allocator, "--remote-debugging-pipe");
        try argv_list.append(allocator, "--enable-unsafe-extension-debugging");

        // Fork and exec
        const pid = try std.posix.fork();

        if (pid == 0) {
            // Child process
            // Close parent ends of pipes
            std.posix.close(pipe_to_chrome[1]);
            std.posix.close(pipe_from_chrome[0]);

            // Duplicate pipe fds to 3 and 4
            // fd 3: Chrome reads commands (from pipe_to_chrome[0])
            // fd 4: Chrome writes responses (to pipe_from_chrome[1])
            _ = std.posix.dup2(pipe_to_chrome[0], 3);
            _ = std.posix.dup2(pipe_from_chrome[1], 4);

            // Close original pipe fds (now duplicated)
            std.posix.close(pipe_to_chrome[0]);
            std.posix.close(pipe_from_chrome[1]);

            // Exec Chrome
            const argv_z = try allocator.allocSentinel(?[*:0]const u8, argv_list.items.len, null);
            for (argv_list.items, 0..) |arg, i| {
                argv_z[i] = try allocator.dupeZ(u8, arg);
            }

            const envp = std.c.environ;
            _ = std.posix.execvpeZ(argv_z[0].?, argv_z, envp);

            // If exec fails, exit
            std.posix.exit(1);
        }

        // Parent process
        // Close child ends of pipes
        std.posix.close(pipe_to_chrome[0]);
        std.posix.close(pipe_from_chrome[1]);

        // Create ChromePipe instance
        const self = try allocator.create(Self);
        self.* = .{
            .write_pipe = .{ .handle = pipe_to_chrome[1] },
            .read_pipe = .{ .handle = pipe_from_chrome[0] },
            .read_buf = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
            .io = io,
            .next_id = 1,
            .is_closed = false,
        };

        return self;
    }

    /// Wait for Chrome to be ready by reading initial response.
    pub fn waitReady(self: *Self, timeout_ms: u32) !void {
        _ = timeout_ms;
        // Chrome sends an initial message when ready
        // For now, we just try to read any initial data
        // TODO: Implement proper timeout handling
        _ = self;
    }

    /// Send a CDP command and wait for response.
    pub fn sendCommand(self: *Self, method: []const u8, params: anytype) !json.Value {
        const id = self.next_id;
        self.next_id += 1;

        // Build JSON command
        var cmd_buf: std.ArrayList(u8) = .empty;
        defer cmd_buf.deinit(self.allocator);

        try cmd_buf.appendSlice(self.allocator, "{\"id\":");
        var id_buf: [16]u8 = undefined;
        const id_str = std.fmt.bufPrint(&id_buf, "{}", .{id}) catch unreachable;
        try cmd_buf.appendSlice(self.allocator, id_str);
        try cmd_buf.appendSlice(self.allocator, ",\"method\":\"");
        try cmd_buf.appendSlice(self.allocator, method);
        try cmd_buf.appendSlice(self.allocator, "\"");

        // Add params if not void
        const ParamsType = @TypeOf(params);
        if (ParamsType != void and @typeInfo(ParamsType) == .@"struct") {
            try cmd_buf.appendSlice(self.allocator, ",\"params\":");
            try serializeParams(self.allocator, &cmd_buf, params);
        }

        try cmd_buf.appendSlice(self.allocator, "}");

        // Send command (null-terminated for pipe protocol)
        _ = try self.write_pipe.write(cmd_buf.items);
        _ = try self.write_pipe.write(&[_]u8{0});

        // Read response (until null byte)
        self.read_buf.clearRetainingCapacity();
        while (true) {
            var byte: [1]u8 = undefined;
            const n = try self.read_pipe.read(&byte);
            if (n == 0) return error.ConnectionClosed;
            if (byte[0] == 0) break;
            try self.read_buf.append(self.allocator, byte[0]);
        }

        // Parse response
        const parsed = json.parse(self.allocator, self.read_buf.items) catch {
            return error.InvalidResponse;
        };

        // Check for error
        if (parsed.get("error")) |err| {
            if (err.get("message")) |msg| {
                if (msg == .string) {
                    std.debug.print("CDP Error: {s}\n", .{msg.string});
                }
            }
            return error.CDPError;
        }

        // Return result
        if (parsed.get("result")) |result| {
            return result;
        }

        return parsed;
    }

    /// Close pipes and cleanup.
    pub fn deinit(self: *Self) void {
        if (!self.is_closed) {
            self.write_pipe.close();
            self.read_pipe.close();
            self.is_closed = true;
        }
        self.read_buf.deinit();
        self.allocator.destroy(self);
    }
};

/// Serialize params struct to JSON.
fn serializeParams(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), params: anytype) !void {
    const T = @TypeOf(params);
    const info = @typeInfo(T);

    if (info != .@"struct") {
        try buf.appendSlice(allocator, "{}");
        return;
    }

    try buf.appendSlice(allocator, "{");
    var first = true;

    inline for (info.@"struct".fields) |field| {
        const value = @field(params, field.name);
        const FieldType = @TypeOf(value);

        // Skip null optionals
        if (@typeInfo(FieldType) == .optional) {
            if (value == null) continue;
        }

        if (!first) try buf.appendSlice(allocator, ",");
        first = false;

        try buf.appendSlice(allocator, "\"");
        try buf.appendSlice(allocator, field.name);
        try buf.appendSlice(allocator, "\":");

        // Serialize value based on type
        if (@typeInfo(FieldType) == .optional) {
            try serializeValue(allocator, buf, value.?);
        } else {
            try serializeValue(allocator, buf, value);
        }
    }

    try buf.appendSlice(allocator, "}");
}

fn serializeValue(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), value: anytype) !void {
    const T = @TypeOf(value);

    if (T == []const u8) {
        try buf.appendSlice(allocator, "\"");
        // TODO: Escape string properly
        try buf.appendSlice(allocator, value);
        try buf.appendSlice(allocator, "\"");
    } else if (T == bool) {
        try buf.appendSlice(allocator, if (value) "true" else "false");
    } else if (@typeInfo(T) == .int or @typeInfo(T) == .float) {
        var num_buf: [32]u8 = undefined;
        const num_str = std.fmt.bufPrint(&num_buf, "{}", .{value}) catch unreachable;
        try buf.appendSlice(allocator, num_str);
    } else {
        try buf.appendSlice(allocator, "null");
    }
}
