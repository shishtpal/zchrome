const std = @import("std");
const Session = @import("../core/session.zig").Session;

/// Emulation domain client
pub const Emulation = struct {
    session: *Session,

    const Self = @This();

    pub fn init(session: *Session) Self {
        return .{ .session = session };
    }

    /// Set device metrics override
    pub fn setDeviceMetricsOverride(self: *Self, params: DeviceMetrics) !void {
        _ = try self.session.sendCommand("Emulation.setDeviceMetricsOverride", params);
    }

    /// Clear device metrics override
    pub fn clearDeviceMetricsOverride(self: *Self) !void {
        _ = try self.session.sendCommand("Emulation.clearDeviceMetricsOverride", .{});
    }

    /// Set user agent override
    pub fn setUserAgentOverride(self: *Self, user_agent: []const u8, platform: ?[]const u8) !void {
        _ = try self.session.sendCommand("Emulation.setUserAgentOverride", .{
            .user_agent = user_agent,
            .platform = platform,
        });
    }

    /// Set geolocation override
    pub fn setGeolocationOverride(self: *Self, lat: ?f64, lon: ?f64, accuracy: ?f64) !void {
        _ = try self.session.sendCommand("Emulation.setGeolocationOverride", .{
            .latitude = lat,
            .longitude = lon,
            .accuracy = accuracy,
        });
    }

    /// Clear geolocation override
    pub fn clearGeolocationOverride(self: *Self) !void {
        _ = try self.session.sendCommand("Emulation.clearGeolocationOverride", .{});
    }

    /// Set timezone override
    pub fn setTimezoneOverride(self: *Self, timezone_id: []const u8) !void {
        _ = try self.session.sendCommand("Emulation.setTimezoneOverride", .{
            .timezone_id = timezone_id,
        });
    }

    /// Set locale override
    pub fn setLocaleOverride(self: *Self, locale: ?[]const u8) !void {
        _ = try self.session.sendCommand("Emulation.setLocaleOverride", .{
            .locale = locale,
        });
    }

    /// Set touch emulation enabled
    pub fn setTouchEmulationEnabled(self: *Self, enabled: bool) !void {
        _ = try self.session.sendCommand("Emulation.setTouchEmulationEnabled", .{
            .enabled = enabled,
        });
    }

    /// Set emulated media
    pub fn setEmulatedMedia(self: *Self, media: ?[]const u8, features: ?[]const MediaFeature) !void {
        _ = try self.session.sendCommand("Emulation.setEmulatedMedia", .{
            .media = media,
            .features = features,
        });
    }

    /// Set script execution disabled
    pub fn setScriptExecutionDisabled(self: *Self, value: bool) !void {
        _ = try self.session.sendCommand("Emulation.setScriptExecutionDisabled", .{
            .value = value,
        });
    }
};

/// Device metrics
pub const DeviceMetrics = struct {
    width: i32,
    height: i32,
    device_scale_factor: f64 = 1.0,
    mobile: bool = false,
    screen_width: ?i32 = null,
    screen_height: ?i32 = null,
    screen_orientation: ?ScreenOrientation = null,
};

/// Screen orientation
pub const ScreenOrientation = struct {
    type: []const u8,
    angle: i32,
};

/// Media feature
pub const MediaFeature = struct {
    name: []const u8,
    value: []const u8,
};
