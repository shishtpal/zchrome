//! Chrome launcher with pipe-based debugging.
//!
//! Spawns Chrome with --remote-debugging-pipe and sets up file descriptors
//! 3 (Chrome reads) and 4 (Chrome writes) for CDP communication.
//!
//! Platform support:
//! - POSIX (Linux, macOS): Uses fork/dup2/exec
//! - Windows: Uses CreateProcessW with STARTUPINFO.lpReserved2

const std = @import("std");
const json = @import("json");
const builtin = @import("builtin");
const globals = @import("../globals.zig");

// Platform-specific types
const NativeHandle = if (builtin.os.tag == .windows)
    std.os.windows.HANDLE
else
    std.posix.fd_t;

// Platform-specific imports
const windows = if (builtin.os.tag == .windows) std.os.windows else struct {};

// Windows API extern declarations (not all in Zig stdlib)
const win32 = if (builtin.os.tag == .windows) struct {
    const HANDLE = std.os.windows.HANDLE;
    const BOOL = std.os.windows.BOOL;
    const DWORD = std.os.windows.DWORD;
    const LPDWORD = *DWORD;
    const LPVOID = *anyopaque;
    const LPCVOID = *const anyopaque;
    const SECURITY_ATTRIBUTES = std.os.windows.SECURITY_ATTRIBUTES;

    const HANDLE_FLAG_INHERIT: DWORD = 0x00000001;
    const STD_INPUT_HANDLE: DWORD = @bitCast(@as(i32, -10));
    const STD_OUTPUT_HANDLE: DWORD = @bitCast(@as(i32, -11));
    const STD_ERROR_HANDLE: DWORD = @bitCast(@as(i32, -12));
    const INVALID_HANDLE_VALUE: HANDLE = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));

    extern "kernel32" fn CreatePipe(
        hReadPipe: *HANDLE,
        hWritePipe: *HANDLE,
        lpPipeAttributes: ?*SECURITY_ATTRIBUTES,
        nSize: DWORD,
    ) callconv(.winapi) BOOL;

    extern "kernel32" fn SetHandleInformation(
        hObject: HANDLE,
        dwMask: DWORD,
        dwFlags: DWORD,
    ) callconv(.winapi) BOOL;

    extern "kernel32" fn ReadFile(
        hFile: HANDLE,
        lpBuffer: [*]u8,
        nNumberOfBytesToRead: DWORD,
        lpNumberOfBytesRead: ?LPDWORD,
        lpOverlapped: ?LPVOID,
    ) callconv(.winapi) BOOL;

    extern "kernel32" fn WriteFile(
        hFile: HANDLE,
        lpBuffer: [*]const u8,
        nNumberOfBytesToWrite: DWORD,
        lpNumberOfBytesWritten: ?LPDWORD,
        lpOverlapped: ?LPVOID,
    ) callconv(.winapi) BOOL;

    extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(.winapi) BOOL;

    extern "kernel32" fn GetStdHandle(nStdHandle: DWORD) callconv(.winapi) ?HANDLE;

    extern "kernel32" fn GetLastError() callconv(.winapi) DWORD;
} else struct {};

// Compile-time platform check
comptime {
    const supported = builtin.os.tag == .windows or
        builtin.os.tag == .linux or
        builtin.os.tag == .macos or
        builtin.os.tag.isDarwin();
    if (!supported) {
        @compileError("Pipe mode is only supported on Windows, Linux, and macOS");
    }
}

// Windows CRT flags for stdio buffer
const FOPEN: u8 = 0x01;
const FPIPE: u8 = 0x08;
const FDEV: u8 = 0x40;

/// Result from a CDP command, wrapping JSON for proper cleanup.
pub const CommandResult = struct {
    /// The parsed JSON value (root of the tree)
    root: json.Value,
    /// The result portion (may be same as root or a child)
    value: json.Value,
    /// Allocator for cleanup
    allocator: std.mem.Allocator,

    /// Free the JSON data.
    pub fn deinit(self: *CommandResult) void {
        self.root.deinit(self.allocator);
    }

    /// Get a field from the result value.
    pub fn get(self: *const CommandResult, key: []const u8) ?json.Value {
        return self.value.get(key);
    }
};

/// Chrome process with pipe-based CDP communication.
pub const ChromePipe = struct {
    /// Pipe for sending commands to Chrome (parent writes, Chrome reads via fd 3)
    write_handle: NativeHandle,
    /// Pipe for receiving responses from Chrome (Chrome writes via fd 4, parent reads)
    read_handle: NativeHandle,
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
        if (builtin.os.tag == .windows) {
            return spawnWindows(allocator, io, chrome_path, base_args);
        } else {
            return spawnPosix(allocator, io, chrome_path, base_args);
        }
    }

    /// POSIX spawn implementation using fork/dup2/exec
    fn spawnPosix(
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
            .write_handle = pipe_to_chrome[1],
            .read_handle = pipe_from_chrome[0],
            .read_buf = .empty,
            .allocator = allocator,
            .io = io,
            .next_id = 1,
            .is_closed = false,
        };

        return self;
    }

    /// Windows spawn implementation using CreateProcessW with lpReserved2
    fn spawnWindows(
        allocator: std.mem.Allocator,
        io: std.Io,
        chrome_path: []const u8,
        base_args: []const []const u8,
    ) !*Self {
        const HANDLE = win32.HANDLE;
        const INVALID_HANDLE_VALUE = win32.INVALID_HANDLE_VALUE;

        // Security attributes for inheritable handles
        var sa: windows.SECURITY_ATTRIBUTES = .{
            .nLength = @sizeOf(windows.SECURITY_ATTRIBUTES),
            .lpSecurityDescriptor = null,
            .bInheritHandle = windows.TRUE,
        };

        // Create pipe for parent->Chrome (Chrome reads from fd 3)
        var pipe_to_chrome_read: HANDLE = INVALID_HANDLE_VALUE;
        var pipe_to_chrome_write: HANDLE = INVALID_HANDLE_VALUE;
        if (win32.CreatePipe(&pipe_to_chrome_read, &pipe_to_chrome_write, &sa, 0) == 0) {
            return error.PipeCreationFailed;
        }
        errdefer {
            _ = win32.CloseHandle(pipe_to_chrome_read);
            _ = win32.CloseHandle(pipe_to_chrome_write);
        }

        // Make write end non-inheritable (parent keeps this)
        if (win32.SetHandleInformation(pipe_to_chrome_write, win32.HANDLE_FLAG_INHERIT, 0) == 0) {
            return error.SetHandleInfoFailed;
        }

        // Create pipe for Chrome->parent (Chrome writes to fd 4)
        var pipe_from_chrome_read: HANDLE = INVALID_HANDLE_VALUE;
        var pipe_from_chrome_write: HANDLE = INVALID_HANDLE_VALUE;
        if (win32.CreatePipe(&pipe_from_chrome_read, &pipe_from_chrome_write, &sa, 0) == 0) {
            return error.PipeCreationFailed;
        }
        errdefer {
            _ = win32.CloseHandle(pipe_from_chrome_read);
            _ = win32.CloseHandle(pipe_from_chrome_write);
        }

        // Make read end non-inheritable (parent keeps this)
        if (win32.SetHandleInformation(pipe_from_chrome_read, win32.HANDLE_FLAG_INHERIT, 0) == 0) {
            return error.SetHandleInfoFailed;
        }

        // Get standard handles for fd 0-2 (may be null)
        const std_input = win32.GetStdHandle(win32.STD_INPUT_HANDLE) orelse INVALID_HANDLE_VALUE;
        const std_output = win32.GetStdHandle(win32.STD_OUTPUT_HANDLE) orelse INVALID_HANDLE_VALUE;
        const std_error = win32.GetStdHandle(win32.STD_ERROR_HANDLE) orelse INVALID_HANDLE_VALUE;

        // Build stdio buffer for Windows CRT fd inheritance
        // Layout: int count, u8[count] flags, HANDLE[count] handles
        const fd_count: u32 = 5; // stdin, stdout, stderr, fd3, fd4
        const buffer_size = @sizeOf(u32) + fd_count + fd_count * @sizeOf(HANDLE);
        var stdio_buffer = try allocator.alloc(u8, buffer_size);
        defer allocator.free(stdio_buffer);

        // Write fd count
        @as(*align(1) u32, @ptrCast(stdio_buffer.ptr)).* = fd_count;

        // Write CRT flags for each fd
        const flags_ptr = stdio_buffer.ptr + @sizeOf(u32);
        flags_ptr[0] = FOPEN | FDEV; // stdin
        flags_ptr[1] = FOPEN | FDEV; // stdout
        flags_ptr[2] = FOPEN | FDEV; // stderr
        flags_ptr[3] = FOPEN | FPIPE; // fd 3 (Chrome reads)
        flags_ptr[4] = FOPEN | FPIPE; // fd 4 (Chrome writes)

        // Write handles for each fd
        const handles_ptr: [*]align(1) HANDLE = @ptrCast(stdio_buffer.ptr + @sizeOf(u32) + fd_count);
        handles_ptr[0] = if (std_input != INVALID_HANDLE_VALUE) std_input else INVALID_HANDLE_VALUE;
        handles_ptr[1] = if (std_output != INVALID_HANDLE_VALUE) std_output else INVALID_HANDLE_VALUE;
        handles_ptr[2] = if (std_error != INVALID_HANDLE_VALUE) std_error else INVALID_HANDLE_VALUE;
        handles_ptr[3] = pipe_to_chrome_read; // Chrome reads from this
        handles_ptr[4] = pipe_from_chrome_write; // Chrome writes to this

        // Build command line
        var cmd_line: std.ArrayList(u8) = .empty;
        defer cmd_line.deinit(allocator);

        // Quote chrome path if needed
        try cmd_line.append(allocator, '"');
        try cmd_line.appendSlice(allocator, chrome_path);
        try cmd_line.append(allocator, '"');

        // Add base args
        for (base_args) |arg| {
            try cmd_line.append(allocator, ' ');
            try cmd_line.append(allocator, '"');
            try cmd_line.appendSlice(allocator, arg);
            try cmd_line.append(allocator, '"');
        }

        // Add pipe debugging flags
        try cmd_line.appendSlice(allocator, " \"--remote-debugging-pipe\"");
        try cmd_line.appendSlice(allocator, " \"--enable-unsafe-extension-debugging\"");

        // Null terminate
        try cmd_line.append(allocator, 0);

        // Convert to wide string for CreateProcessW (null-terminated)
        const cmd_line_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, cmd_line.items[0 .. cmd_line.items.len - 1]);
        defer allocator.free(cmd_line_w);

        // Set up STARTUPINFOW
        var startup_info: windows.STARTUPINFOW = std.mem.zeroes(windows.STARTUPINFOW);
        startup_info.cb = @sizeOf(windows.STARTUPINFOW);
        startup_info.dwFlags = windows.STARTF_USESTDHANDLES;
        startup_info.hStdInput = std_input;
        startup_info.hStdOutput = std_output;
        startup_info.hStdError = std_error;
        startup_info.cbReserved2 = @intCast(buffer_size);
        startup_info.lpReserved2 = @ptrCast(stdio_buffer.ptr);

        var process_info: windows.PROCESS.INFORMATION = std.mem.zeroes(windows.PROCESS.INFORMATION);

        // Create the process
        const result = windows.kernel32.CreateProcessW(
            null, // lpApplicationName
            @constCast(@as([*:0]u16, cmd_line_w.ptr)), // lpCommandLine
            null, // lpProcessAttributes
            null, // lpThreadAttributes
            windows.TRUE, // bInheritHandles
            .{}, // dwCreationFlags
            null, // lpEnvironment
            null, // lpCurrentDirectory
            &startup_info,
            &process_info,
        );

        if (result == 0) {
            const err = win32.GetLastError();
            std.debug.print("CreateProcessW failed with error: {}\n", .{err});
            return error.ProcessCreationFailed;
        }

        // Close process and thread handles (we don't need them)
        _ = win32.CloseHandle(process_info.hProcess);
        _ = win32.CloseHandle(process_info.hThread);

        // Close child ends of pipes (Chrome has them now)
        _ = win32.CloseHandle(pipe_to_chrome_read);
        _ = win32.CloseHandle(pipe_from_chrome_write);

        // Create ChromePipe instance with parent ends
        const self = try allocator.create(Self);
        self.* = .{
            .write_handle = pipe_to_chrome_write,
            .read_handle = pipe_from_chrome_read,
            .read_buf = .empty,
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
    /// Returns a CommandResult that must be freed with .deinit().
    pub fn sendCommand(self: *Self, method: []const u8, params: anytype) !CommandResult {
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

        // Debug: print command being sent
        if (globals.verbose) {
            std.debug.print("[pipe] Sending CDP command: {s}\n", .{cmd_buf.items});
        }

        // Send command (null-terminated for pipe protocol)
        try writeAll(self.write_handle, cmd_buf.items);
        try writeAll(self.write_handle, &[_]u8{0});

        // Read response (until null byte)
        self.read_buf.clearRetainingCapacity();
        while (true) {
            var byte: [1]u8 = undefined;
            const n = try readOne(self.read_handle, &byte);
            if (n == 0) return error.ConnectionClosed;
            if (byte[0] == 0) break;
            try self.read_buf.append(self.allocator, byte[0]);
        }

        // Debug: print raw response
        if (globals.verbose) {
            std.debug.print("[pipe] CDP response ({} bytes): {s}\n", .{ self.read_buf.items.len, self.read_buf.items });
        }

        // Parse response
        var parsed = json.parse(self.allocator, self.read_buf.items, .{}) catch |err| {
            if (globals.verbose) {
                std.debug.print("[pipe] JSON parse error: {}\n", .{err});
            }
            return error.InvalidResponse;
        };
        errdefer parsed.deinit(self.allocator);

        // Check for error
        if (parsed.get("error")) |err| {
            if (err.get("message")) |msg| {
                if (msg == .string) {
                    std.debug.print("CDP Error: {s}\n", .{msg.string});
                }
            }
            parsed.deinit(self.allocator);
            return error.CDPError;
        }

        // Return result wrapped in CommandResult for proper cleanup
        const result_value = parsed.get("result") orelse parsed;
        return CommandResult{
            .root = parsed,
            .value = result_value,
            .allocator = self.allocator,
        };
    }

    /// Close pipes and cleanup.
    pub fn deinit(self: *Self) void {
        if (!self.is_closed) {
            closeHandle(self.write_handle);
            closeHandle(self.read_handle);
            self.is_closed = true;
        }
        self.read_buf.deinit(self.allocator);
        self.allocator.destroy(self);
    }
};

// ─── Platform-specific I/O helpers ─────────────────────────────────────────────

fn writeAll(handle: NativeHandle, data: []const u8) !void {
    if (builtin.os.tag == .windows) {
        var written: u32 = 0;
        const result = win32.WriteFile(
            handle,
            data.ptr,
            @intCast(data.len),
            &written,
            null,
        );
        if (result == 0) return error.WriteError;
    } else {
        var total: usize = 0;
        while (total < data.len) {
            const n = std.posix.write(handle, data[total..]) catch |err| {
                if (err == error.WouldBlock) continue;
                return error.WriteError;
            };
            if (n == 0) return error.WriteError;
            total += n;
        }
    }
}

fn readOne(handle: NativeHandle, buf: *[1]u8) !usize {
    if (builtin.os.tag == .windows) {
        var bytes_read: u32 = 0;
        const result = win32.ReadFile(
            handle,
            buf,
            1,
            &bytes_read,
            null,
        );
        if (result == 0) return error.ReadError;
        return bytes_read;
    } else {
        return std.posix.read(handle, buf) catch |err| {
            if (err == error.WouldBlock) return 0;
            return error.ReadError;
        };
    }
}

fn closeHandle(handle: NativeHandle) void {
    if (builtin.os.tag == .windows) {
        _ = win32.CloseHandle(handle);
    } else {
        std.posix.close(handle);
    }
}

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
        // Escape special characters in JSON strings
        for (value) |c| {
            switch (c) {
                '\\' => try buf.appendSlice(allocator, "\\\\"),
                '"' => try buf.appendSlice(allocator, "\\\""),
                '\n' => try buf.appendSlice(allocator, "\\n"),
                '\r' => try buf.appendSlice(allocator, "\\r"),
                '\t' => try buf.appendSlice(allocator, "\\t"),
                else => try buf.append(allocator, c),
            }
        }
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
