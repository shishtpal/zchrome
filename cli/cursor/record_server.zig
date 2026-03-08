//! Recording server for macro capture via WebSocket.
//!
//! Uses a background thread to handle WebSocket connections while
//! the main thread waits for user input.

const std = @import("std");
const json = @import("json");
const cdp = @import("cdp");
const macro_mod = @import("macro/mod.zig");

pub const DEFAULT_PORT: u16 = 4040;

/// Thread-safe command storage
const CommandStorage = struct {
    commands: std.ArrayList(macro_mod.MacroCommand),
    mutex: std.atomic.Mutex,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) CommandStorage {
        return .{
            .commands = .empty,
            .mutex = .unlocked,
            .allocator = allocator,
        };
    }

    fn addCommand(self: *CommandStorage, cmd: macro_mod.MacroCommand) void {
        while (!self.mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        defer self.mutex.unlock();
        self.commands.append(self.allocator, cmd) catch {};
    }

    fn getCommands(self: *CommandStorage) []macro_mod.MacroCommand {
        while (!self.mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        defer self.mutex.unlock();
        return self.commands.items;
    }

    fn deinit(self: *CommandStorage) void {
        for (self.commands.items) |*c| {
            c.deinit(self.allocator);
        }
        self.commands.deinit(self.allocator);
    }
};

/// Recording server state
pub const RecordServer = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    storage: *CommandStorage,
    port: u16,
    should_stop: std.atomic.Value(bool),
    thread: ?std.Thread,

    const Self = @This();

    /// Start the recording server in a background thread
    pub fn init(allocator: std.mem.Allocator, io: std.Io, port: u16) !*Self {
        const storage = try allocator.create(CommandStorage);
        storage.* = CommandStorage.init(allocator);

        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .storage = storage,
            .port = port,
            .should_stop = std.atomic.Value(bool).init(false),
            .thread = null,
        };

        // Start background thread
        self.thread = std.Thread.spawn(.{}, serverThread, .{ self, io }) catch |err| {
            std.debug.print("Failed to spawn server thread: {}\n", .{err});
            allocator.destroy(storage);
            allocator.destroy(self);
            return err;
        };

        return self;
    }

    fn serverThread(self: *Self, io: std.Io) void {
        // Start WebSocket server
        var server = cdp.WsServer.init(self.allocator, io, self.port) catch |err| {
            std.debug.print("Failed to start WebSocket server: {}\n", .{err});
            return;
        };
        defer server.close();

        // Accept and process connections until stopped
        while (!self.should_stop.load(.acquire)) {
            // Accept connection (blocking)
            var client = server.accept() catch {
                continue;
            };
            std.debug.print("  (browser connected)\n", .{});

            // Process messages until disconnect or stop
            while (!self.should_stop.load(.acquire)) {
                const frame = client.readFrame() catch {
                    // Any read error means the connection is broken
                    break;
                };
                defer self.allocator.free(frame.data);

                // Handle close frame
                if (frame.opcode == .close) break;

                // Handle text frame (command data)
                if (frame.opcode == .text) {
                    self.parseAndStoreCommand(frame.data);
                }
            }

            client.close();
        }
    }

    fn parseAndStoreCommand(self: *Self, data: []const u8) void {
        var parsed = json.parse(self.allocator, data, .{}) catch return;
        defer parsed.deinit(self.allocator);

        if (parsed != .object) return;
        const obj = parsed.object;

        var cmd = macro_mod.MacroCommand{ .action = .click };

        // Parse action type
        if (obj.get("action")) |a| {
            if (a == .string) {
                if (macro_mod.ActionType.fromString(a.string)) |action| {
                    cmd.action = action;
                } else return;
            }
        } else return;

        // Parse selector (primary)
        if (obj.get("selector")) |s| {
            if (s == .string) cmd.selector = self.allocator.dupe(u8, s.string) catch null;
        }

        // Parse selectors (fallback list)
        if (obj.get("selectors")) |sels_val| {
            if (sels_val == .array) {
                var sels_list: std.ArrayList([]const u8) = .empty;
                for (sels_val.array.items) |sel_val| {
                    if (sel_val == .string) {
                        if (self.allocator.dupe(u8, sel_val.string)) |duped| {
                            sels_list.append(self.allocator, duped) catch {
                                self.allocator.free(duped);
                            };
                        } else |_| {}
                    }
                }
                if (sels_list.items.len > 0) {
                    cmd.selectors = sels_list.toOwnedSlice(self.allocator) catch null;
                } else {
                    sels_list.deinit(self.allocator);
                }
            }
        }

        // Parse value
        if (obj.get("value")) |v| {
            if (v == .string) cmd.value = self.allocator.dupe(u8, v.string) catch null;
        }

        // Parse key
        if (obj.get("key")) |k| {
            if (k == .string) cmd.key = self.allocator.dupe(u8, k.string) catch null;
        }

        // Parse scroll
        if (obj.get("scrollX")) |sx| {
            if (sx == .integer) cmd.scroll_x = @intCast(sx.integer);
        }
        if (obj.get("scrollY")) |sy| {
            if (sy == .integer) cmd.scroll_y = @intCast(sy.integer);
        }

        self.storage.addCommand(cmd);
    }

    /// Stop recording and get commands
    pub fn stop(self: *Self) []macro_mod.MacroCommand {
        self.should_stop.store(true, .release);

        // Connect to self to unblock accept
        const addr = std.Io.net.IpAddress.parse("127.0.0.1", self.port) catch return self.storage.getCommands();
        const conn = std.Io.net.IpAddress.connect(addr, self.io, .{
            .mode = .stream,
            .protocol = .tcp,
        }) catch return self.storage.getCommands();
        conn.close(self.io);

        // Wait for thread to finish
        if (self.thread) |t| {
            t.join();
        }

        return self.storage.getCommands();
    }

    /// Clean up
    pub fn deinit(self: *Self) void {
        self.storage.deinit();
        self.allocator.destroy(self.storage);
        self.allocator.destroy(self);
    }
};

/// JavaScript to inject that tracks semantic actions and sends commands
pub fn getRecordingJs(allocator: std.mem.Allocator, port: u16) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        \\(function() {{
        \\  if (window.__zchrome_rec) return;
        \\  var ws = new WebSocket('ws://127.0.0.1:{d}/');
        \\  var state = {{
        \\    focusEl: null,
        \\    focusSel: null,
        \\    focusSels: [],
        \\    typedText: '',
        \\    lastValue: '',
        \\    scrollY: 0,
        \\    ws: ws,
        \\    heartbeat: null
        \\  }};
        \\  window.__zchrome_rec = state;
        \\
        \\  // Generate multiple CSS selectors for element (fallback support)
        \\  function getSelectors(el) {{
        \\    if (!el || el === document.body || el === document.documentElement) return [];
        \\    var sels = [];
        \\    // ID (highest priority)
        \\    if (el.id) sels.push('#' + CSS.escape(el.id));
        \\    // name attribute (for form inputs)
        \\    if (el.name) {{
        \\      // For radio buttons, include value to disambiguate
        \\      if (el.type === 'radio' && el.value) {{
        \\        sels.push('input[name="' + el.name + '"][value="' + el.value + '"]');
        \\      }}
        \\      sels.push(el.tagName.toLowerCase() + '[name="' + el.name + '"]');
        \\    }}
        \\    // data-testid (common in React/testing)
        \\    if (el.dataset.testid) sels.push('[data-testid="' + el.dataset.testid + '"]');
        \\    // aria-label
        \\    if (el.getAttribute('aria-label')) {{
        \\      sels.push(el.tagName.toLowerCase() + '[aria-label="' + el.getAttribute('aria-label') + '"]');
        \\    }}
        \\    // placeholder
        \\    if (el.placeholder) {{
        \\      sels.push(el.tagName.toLowerCase() + '[placeholder="' + el.placeholder + '"]');
        \\    }}
        \\    // type for inputs (if unique)
        \\    if (el.tagName === 'INPUT' && el.type) {{
        \\      var inputs = document.querySelectorAll('input[type="' + el.type + '"]');
        \\      if (inputs.length === 1) sels.push('input[type="' + el.type + '"]');
        \\    }}
        \\    // Unique class
        \\    if (el.classList.length > 0) {{
        \\      for (var i = 0; i < el.classList.length; i++) {{
        \\        var cls = '.' + CSS.escape(el.classList[i]);
        \\        if (document.querySelectorAll(cls).length === 1) sels.push(cls);
        \\      }}
        \\    }}
        \\    // Fallback: nth-of-type
        \\    var parent = el.parentElement;
        \\    if (parent) {{
        \\      var siblings = parent.querySelectorAll(':scope > ' + el.tagName.toLowerCase());
        \\      var idx = Array.prototype.indexOf.call(siblings, el) + 1;
        \\      var parentSels = getSelectors(parent);
        \\      if (parentSels.length > 0) {{
        \\        sels.push(parentSels[0] + ' > ' + el.tagName.toLowerCase() + ':nth-of-type(' + idx + ')');
        \\      }}
        \\    }}
        \\    // Last resort: just tag name
        \\    if (sels.length === 0) sels.push(el.tagName.toLowerCase());
        \\    return sels;
        \\  }}
        \\  // Get best single selector (first from list)
        \\  function getSelector(el) {{
        \\    var sels = getSelectors(el);
        \\    return sels.length > 0 ? sels[0] : null;
        \\  }}
        \\
        \\  function send(cmd) {{
        \\    if (ws && ws.readyState === 1) {{
        \\      ws.send(JSON.stringify(cmd));
        \\      console.log('[zchrome]', cmd);
        \\    }}
        \\  }}
        \\
        \\  function flushTyped() {{
        \\    if (state.focusEl && state.focusSel) {{
        \\      var val = state.focusEl.value || '';
        \\      if (val && val !== state.lastValue) {{
        \\        send({{ action: 'fill', selector: state.focusSel, selectors: state.focusSels, value: val }});
        \\      }}
        \\    }}
        \\    state.typedText = '';
        \\    state.lastValue = '';
        \\  }}
        \\
        \\  // Click handler
        \\  document.addEventListener('click', function(e) {{
        \\    var el = e.target;
        \\    var sels = getSelectors(el);
        \\    if (sels.length === 0) return;
        \\
        \\    // Check if it's a checkbox
        \\    if (el.type === 'checkbox') {{
        \\      send({{ action: el.checked ? 'check' : 'uncheck', selector: sels[0], selectors: sels }});
        \\      return;
        \\    }}
        \\
        \\    // Check if it's a radio button
        \\    if (el.type === 'radio') {{
        \\      send({{ action: 'check', selector: sels[0], selectors: sels, value: el.value }});
        \\      return;
        \\    }}
        \\
        \\    // Regular click
        \\    send({{ action: 'click', selector: sels[0], selectors: sels }});
        \\  }}, true);
        \\
        \\  // Double click
        \\  document.addEventListener('dblclick', function(e) {{
        \\    var sels = getSelectors(e.target);
        \\    if (sels.length > 0) send({{ action: 'dblclick', selector: sels[0], selectors: sels }});
        \\  }}, true);
        \\
        \\  // Focus tracking
        \\  document.addEventListener('focus', function(e) {{
        \\    flushTyped();
        \\    state.focusEl = e.target;
        \\    state.focusSels = getSelectors(e.target);
        \\    state.focusSel = state.focusSels.length > 0 ? state.focusSels[0] : null;
        \\    state.lastValue = e.target.value || '';
        \\  }}, true);
        \\
        \\  // Blur - emit fill if value changed
        \\  document.addEventListener('blur', function(e) {{
        \\    flushTyped();
        \\    state.focusEl = null;
        \\    state.focusSel = null;
        \\    state.focusSels = [];
        \\  }}, true);
        \\
        \\  // Select change
        \\  document.addEventListener('change', function(e) {{
        \\    var el = e.target;
        \\    var sels = getSelectors(el);
        \\    if (sels.length === 0) return;
        \\    if (el.tagName === 'SELECT') {{
        \\      if (el.multiple) {{
        \\        // Multiselect: capture all selected values as JSON string (playback expects JSON.parse)
        \\        var values = Array.from(el.selectedOptions).map(function(o) {{ return o.value; }});
        \\        send({{ action: 'multiselect', selector: sels[0], selectors: sels, value: JSON.stringify(values) }});
        \\      }} else {{
        \\        send({{ action: 'select', selector: sels[0], selectors: sels, value: el.value }});
        \\      }}
        \\    }}
        \\  }}, true);
        \\
        \\  // Key press for special keys
        \\  document.addEventListener('keydown', function(e) {{
        \\    // Special keys that should be recorded as press commands
        \\    var special = ['Enter', 'Tab', 'Escape', 'Backspace', 'Delete',
        \\                   'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight',
        \\                   'Home', 'End', 'PageUp', 'PageDown'];
        \\    if (special.includes(e.key) || e.ctrlKey || e.altKey || e.metaKey) {{
        \\      var keyStr = '';
        \\      if (e.ctrlKey) keyStr += 'Control+';
        \\      if (e.altKey) keyStr += 'Alt+';
        \\      if (e.metaKey) keyStr += 'Meta+';
        \\      if (e.shiftKey && (e.ctrlKey || e.altKey || e.metaKey)) keyStr += 'Shift+';
        \\      keyStr += e.key;
        \\      send({{ action: 'press', key: keyStr }});
        \\    }}
        \\  }}, true);
        \\
        \\  // Scroll tracking (debounced)
        \\  var scrollTimeout = null;
        \\  window.addEventListener('scroll', function() {{
        \\    if (scrollTimeout) clearTimeout(scrollTimeout);
        \\    scrollTimeout = setTimeout(function() {{
        \\      var delta = window.scrollY - state.scrollY;
        \\      if (Math.abs(delta) > 50) {{
        \\        send({{ action: 'scroll', scrollY: delta > 0 ? Math.abs(delta) : -Math.abs(delta) }});
        \\        state.scrollY = window.scrollY;
        \\      }}
        \\    }}, 150);
        \\  }}, true);
        \\  state.scrollY = window.scrollY;
        \\
        \\  ws.onopen = function() {{
        \\    console.log('[zchrome] Recording connected');
        \\    // Keep server read loop interruptible so CLI stop can join promptly.
        \\    state.heartbeat = setInterval(function() {{
        \\      if (ws && ws.readyState === 1) {{
        \\        ws.send(JSON.stringify({{ action: '__heartbeat' }}));
        \\      }}
        \\    }}, 500);
        \\  }};
        \\  ws.onclose = function() {{
        \\    if (state.heartbeat) {{
        \\      clearInterval(state.heartbeat);
        \\      state.heartbeat = null;
        \\    }}
        \\    window.__zchrome_rec = null;
        \\  }};
        \\}})();
    , .{port});
}
