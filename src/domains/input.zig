const std = @import("std");
const Session = @import("../core/session.zig").Session;

/// Input domain client
pub const Input = struct {
    session: *Session,

    const Self = @This();

    pub fn init(session: *Session) Self {
        return .{ .session = session };
    }

    /// Dispatch mouse event
    pub fn dispatchMouseEvent(self: *Self, params: MouseEvent) !void {
        _ = try self.session.sendCommand("Input.dispatchMouseEvent", params);
    }

    /// Dispatch key event
    pub fn dispatchKeyEvent(self: *Self, params: KeyEvent) !void {
        _ = try self.session.sendCommand("Input.dispatchKeyEvent", params);
    }

    /// Dispatch touch event
    pub fn dispatchTouchEvent(self: *Self, params: TouchEvent) !void {
        _ = try self.session.sendCommand("Input.dispatchTouchEvent", params);
    }

    /// Convenience: Click at position
    pub fn click(self: *Self, x: f64, y: f64, opts: ClickOptions) !void {
        // Move mouse to target first — required for sites that track mousemove
        // (e.g. Google search result links use JS event handlers that need
        // a mousemove before mousedown to register the click correctly)
        try self.dispatchMouseEvent(.{
            .type = .mouseMoved,
            .x = x,
            .y = y,
            .button = .none,
        });

        try self.dispatchMouseEvent(.{
            .type = .mousePressed,
            .x = x,
            .y = y,
            .button = opts.button,
            .click_count = opts.click_count,
        });

        // Sleep using spinloop (Zig 0.16 changed time API)
        var i: u64 = 0;
        const loops = opts.delay_ms * 10000;
        while (i < loops) : (i += 1) {
            std.atomic.spinLoopHint();
        }

        try self.dispatchMouseEvent(.{
            .type = .mouseReleased,
            .x = x,
            .y = y,
            .button = opts.button,
            .click_count = opts.click_count,
        });
    }

    /// Convenience: Move mouse
    pub fn moveTo(self: *Self, x: f64, y: f64) !void {
        try self.dispatchMouseEvent(.{
            .type = .mouseMoved,
            .x = x,
            .y = y,
        });
    }

    /// Convenience: Press mouse button down
    pub fn mouseDown(self: *Self, x: f64, y: f64, button: MouseButton) !void {
        try self.dispatchMouseEvent(.{
            .type = .mousePressed,
            .x = x,
            .y = y,
            .button = button,
            .click_count = 1,
        });
    }

    /// Convenience: Release mouse button
    pub fn mouseUp(self: *Self, x: f64, y: f64, button: MouseButton) !void {
        try self.dispatchMouseEvent(.{
            .type = .mouseReleased,
            .x = x,
            .y = y,
            .button = button,
            .click_count = 1,
        });
    }

    /// Convenience: Type text
    pub fn typeText(self: *Self, text: []const u8, delay_ms: ?u64) !void {
        for (text) |char| {
            try self.dispatchKeyEvent(.{
                .type = .char,
                .text = &[_]u8{char},
            });
            if (delay_ms) |d| {
                // Sleep using spinloop (Zig 0.16 changed time API)
                var j: u64 = 0;
                const loops = d * 10000;
                while (j < loops) : (j += 1) {
                    std.atomic.spinLoopHint();
                }
            }
        }
    }

    /// Convenience: Press key
    pub fn press(self: *Self, key: []const u8) !void {
        try self.dispatchKeyEvent(.{
            .type = .keyDown,
            .key = key,
        });
        try self.dispatchKeyEvent(.{
            .type = .keyUp,
            .key = key,
        });
    }

    /// Convenience: Double click at position
    pub fn doubleClick(self: *Self, x: f64, y: f64, opts: ClickOptions) !void {
        var double_opts = opts;
        double_opts.click_count = 2;
        try self.click(x, y, double_opts);
    }

    /// Convenience: Scroll (mouse wheel)
    pub fn scroll(self: *Self, delta_x: f64, delta_y: f64) !void {
        try self.dispatchMouseEvent(.{
            .type = .mouseWheel,
            .x = 100,
            .y = 100,
            .delta_x = delta_x,
            .delta_y = delta_y,
        });
    }
};

/// Mouse event type
pub const MouseEventType = enum {
    mousePressed,
    mouseReleased,
    mouseMoved,
    mouseWheel,
};

/// Mouse button
pub const MouseButton = enum {
    none,
    left,
    middle,
    right,
};

/// Mouse event parameters
pub const MouseEvent = struct {
    type: MouseEventType,
    x: f64,
    y: f64,
    button: ?MouseButton = null,
    click_count: ?i32 = null,
    modifiers: ?i32 = null,
    delta_x: ?f64 = null,
    delta_y: ?f64 = null,
};

/// Key event type
pub const KeyEventType = enum {
    keyDown,
    keyUp,
    rawKeyDown,
    char,
};

/// Key event parameters
pub const KeyEvent = struct {
    type: KeyEventType,
    modifiers: ?i32 = null,
    text: ?[]const u8 = null,
    key: ?[]const u8 = null,
    code: ?[]const u8 = null,
    windows_virtual_key_code: ?i32 = null,
};

/// Touch event parameters
pub const TouchEvent = struct {
    type: []const u8,
    touch_points: []const TouchPoint,
    modifiers: ?i32 = null,
};

/// Touch point
pub const TouchPoint = struct {
    x: f64,
    y: f64,
    radius_x: ?f64 = null,
    radius_y: ?f64 = null,
    rotation_angle: ?f64 = null,
    force: ?f64 = null,
    id: ?f64 = null,
};

/// Click options
pub const ClickOptions = struct {
    button: MouseButton = .left,
    click_count: i32 = 1,
    delay_ms: u64 = 0,
};
