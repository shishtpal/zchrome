//! Interactive REPL mode for zchrome.
//!
//! Provides a command-line interface for interacting with Chrome
//! using a persistent session for fast command execution.

const std = @import("std");
const cdp = @import("cdp");
const commands = @import("commands.zig");

/// State maintained throughout the interactive session
pub const InteractiveState = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    browser: *cdp.Browser,
    session: ?*cdp.Session,
    target_id: ?[]const u8,
    verbose: bool,

    pub fn deinit(self: *InteractiveState) void {
        if (self.session) |s| s.deinit();
        if (self.target_id) |t| self.allocator.free(t);
    }
};

/// Run the interactive REPL
pub fn run(state: *InteractiveState) !void {
    // Print welcome message
    var version = state.browser.version() catch {
        std.debug.print("Connected to Chrome\n", .{});
        printWelcome(null);
        return runLoop(state);
    };
    defer version.deinit(state.allocator);
    printWelcome(version.product);
    
    // Print current page info if we have a session
    if (state.session != null and state.target_id != null) {
        printCurrentPage(state);
    }

    try runLoop(state);
}

fn printWelcome(product: ?[]const u8) void {
    if (product) |p| {
        std.debug.print("Connected to Chrome ({s})\n", .{p});
    }
    std.debug.print("Type 'help' for commands, 'quit' to exit.\n\n", .{});
}

fn printCurrentPage(state: *InteractiveState) void {
    if (state.session) |session| {
        var runtime = cdp.Runtime.init(session);
        runtime.enable() catch return;
        
        const title = runtime.evaluateAs([]const u8, "document.title") catch "Unknown";
        const url = runtime.evaluateAs([]const u8, "window.location.href") catch "Unknown";
        
        std.debug.print("Using page: {s} ({s})\n\n", .{ title, url });
    }
}

fn runLoop(state: *InteractiveState) !void {
    const stdin_file = std.Io.File.stdin();
    
    while (true) {
        // Print prompt
        std.debug.print("zchrome> ", .{});
        
        // Read line from stdin
        const line = readLine(state.allocator, state.io, stdin_file) catch |err| {
            std.debug.print("\nRead error: {}\n", .{err});
            return err;
        };
        
        if (line == null) {
            std.debug.print("\nGoodbye!\n", .{});
            return;
        }
        defer state.allocator.free(line.?);
        
        // Trim whitespace (including \r for Windows)
        const trimmed = std.mem.trim(u8, line.?, " \t\r\n");
        if (trimmed.len == 0) continue;
        
        // Parse and execute command
        executeCommand(state, trimmed) catch |err| {
            std.debug.print("Error: {}\n", .{err});
        };
    }
}

/// Read a line from stdin (until newline or EOF)
fn readLine(allocator: std.mem.Allocator, io: std.Io, file: std.Io.File) !?[]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);
    
    // Use a fresh buffer for each read to avoid stale state
    var read_buf: [256]u8 = undefined;
    var reader = file.readerStreaming(io, &read_buf);
    
    while (true) {
        // Try to read one byte at a time
        const byte = reader.interface.takeByte() catch |err| {
            switch (err) {
                error.EndOfStream => {
                    if (result.items.len > 0) {
                        return try result.toOwnedSlice(allocator);
                    }
                    return null;
                },
                else => {
                    if (result.items.len > 0) {
                        return try result.toOwnedSlice(allocator);
                    }
                    return err;
                },
            }
        };
        
        if (byte == '\n') {
            return try result.toOwnedSlice(allocator);
        }
        
        try result.append(allocator, byte);
        
        // Safety limit
        if (result.items.len > 4096) {
            return try result.toOwnedSlice(allocator);
        }
    }
}

/// Parse command line into tokens, handling quoted strings
fn tokenize(allocator: std.mem.Allocator, line: []const u8) ![][]const u8 {
    var tokens: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (tokens.items) |t| allocator.free(t);
        tokens.deinit(allocator);
    }
    
    var i: usize = 0;
    while (i < line.len) {
        // Skip whitespace
        while (i < line.len and (line[i] == ' ' or line[i] == '\t')) : (i += 1) {}
        if (i >= line.len) break;
        
        var token_start = i;
        var token_end = i;
        
        if (line[i] == '"') {
            // Quoted string
            i += 1;
            token_start = i;
            while (i < line.len and line[i] != '"') : (i += 1) {}
            token_end = i;
            if (i < line.len) i += 1; // Skip closing quote
        } else {
            // Regular token
            while (i < line.len and line[i] != ' ' and line[i] != '\t') : (i += 1) {}
            token_end = i;
        }
        
        if (token_end > token_start) {
            try tokens.append(allocator, try allocator.dupe(u8, line[token_start..token_end]));
        }
    }
    
    return tokens.toOwnedSlice(allocator);
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// Execute a command
fn executeCommand(state: *InteractiveState, line: []const u8) !void {
    const tokens = try tokenize(state.allocator, line);
    defer {
        for (tokens) |t| state.allocator.free(t);
        state.allocator.free(tokens);
    }
    
    if (tokens.len == 0) return;
    
    const cmd = tokens[0];
    const args = if (tokens.len > 1) tokens[1..] else &[_][]const u8{};
    
    // Handle commands
    if (eql(cmd, "help") or eql(cmd, "?")) {
        commands.printHelp();
    } else if (eql(cmd, "quit") or eql(cmd, "exit")) {
        std.debug.print("Goodbye!\n", .{});
        std.process.exit(0);
    } else if (eql(cmd, "version")) {
        try commands.cmdVersion(state);
    } else if (eql(cmd, "pages")) {
        try commands.cmdPages(state);
    } else if (eql(cmd, "use")) {
        try commands.cmdUse(state, args);
    } else if (eql(cmd, "navigate") or eql(cmd, "nav") or eql(cmd, "goto")) {
        try commands.cmdNavigate(state, args);
    } else if (eql(cmd, "screenshot") or eql(cmd, "ss")) {
        try commands.cmdScreenshot(state, args);
    } else if (eql(cmd, "pdf")) {
        try commands.cmdPdf(state, args);
    } else if (eql(cmd, "evaluate") or eql(cmd, "eval") or eql(cmd, "js")) {
        try commands.cmdEvaluate(state, args);
    } else if (eql(cmd, "dom")) {
        try commands.cmdDom(state, args);
    } else if (eql(cmd, "cookies")) {
        try commands.cmdCookies(state);
    } else if (eql(cmd, "snapshot") or eql(cmd, "snap")) {
        try commands.cmdSnapshot(state, args);
    } else if (eql(cmd, "click")) {
        try commands.cmdClick(state, args);
    } else if (eql(cmd, "dblclick")) {
        try commands.cmdDblClick(state, args);
    } else if (eql(cmd, "fill")) {
        try commands.cmdFill(state, args);
    } else if (eql(cmd, "type")) {
        try commands.cmdType(state, args);
    } else if (eql(cmd, "select")) {
        try commands.cmdSelect(state, args);
    } else if (eql(cmd, "check")) {
        try commands.cmdCheck(state, args);
    } else if (eql(cmd, "uncheck")) {
        try commands.cmdUncheck(state, args);
    } else if (eql(cmd, "hover")) {
        try commands.cmdHover(state, args);
    } else if (eql(cmd, "focus")) {
        try commands.cmdFocus(state, args);
    } else if (eql(cmd, "scroll")) {
        try commands.cmdScroll(state, args);
    } else if (eql(cmd, "scrollinto") or eql(cmd, "scrollintoview")) {
        try commands.cmdScrollIntoView(state, args);
    } else if (eql(cmd, "drag")) {
        try commands.cmdDrag(state, args);
    } else if (eql(cmd, "upload")) {
        try commands.cmdUpload(state, args);
    } else if (eql(cmd, "get")) {
        try commands.cmdGet(state, args);
    } else if (eql(cmd, "back")) {
        try commands.cmdBack(state);
    } else if (eql(cmd, "forward")) {
        try commands.cmdForward(state);
    } else if (eql(cmd, "reload")) {
        try commands.cmdReload(state);
    } else {
        std.debug.print("Unknown command: {s}\nType 'help' for available commands.\n", .{cmd});
    }
}
