//! Browser emulation helpers (user agent, viewport, geolocation, etc.)

const std = @import("std");
const cdp = @import("cdp");
const config_mod = @import("../config.zig");

pub fn applyUserAgent(session: *cdp.Session, ua: []const u8) !void {
    // Enable domains first
    _ = session.sendCommand("Network.enable", .{}) catch {};
    _ = session.sendCommand("Page.enable", .{}) catch {};

    // Set via Emulation.setUserAgentOverride
    // This affects both navigator.userAgent AND the User-Agent HTTP header for ALL requests
    _ = try session.sendCommand("Emulation.setUserAgentOverride", .{
        .userAgent = ua,
    });
}

pub fn applyViewport(session: *cdp.Session, width: u32, height: u32, scale: f64, mobile: bool) !void {
    _ = try session.sendCommand("Emulation.setDeviceMetricsOverride", .{
        .width = width,
        .height = height,
        .deviceScaleFactor = scale,
        .mobile = mobile,
    });
}

pub fn applyGeolocation(session: *cdp.Session, lat: f64, lng: f64) !void {
    _ = try session.sendCommand("Emulation.setGeolocationOverride", .{
        .latitude = lat,
        .longitude = lng,
        .accuracy = 1.0,
    });
}

pub fn applyOfflineMode(session: *cdp.Session, offline: bool) !void {
    _ = try session.sendCommand("Network.emulateNetworkConditions", .{
        .offline = offline,
        .latency = 0,
        .downloadThroughput = -1,
        .uploadThroughput = -1,
    });
}

pub fn applyMediaFeature(session: *cdp.Session, scheme: []const u8) !void {
    _ = try session.sendCommand("Emulation.setEmulatedMedia", .{
        .features = &[_]struct { name: []const u8, value: []const u8 }{
            .{ .name = "prefers-color-scheme", .value = scheme },
        },
    });
}

/// Apply saved emulation settings from config to a session.
/// Call this after attaching to a target to ensure user agent and other settings persist.
pub fn applyEmulationSettings(session: *cdp.Session, allocator: std.mem.Allocator, io: std.Io) void {
    var config = config_mod.loadConfig(allocator, io) orelse return;
    defer config.deinit(allocator);

    if (config.user_agent) |ua| {
        applyUserAgent(session, ua) catch |err| {
            std.debug.print("Warning: Failed to apply user agent: {}\n", .{err});
        };
    }
    if (config.viewport_width != null and config.viewport_height != null) {
        applyViewport(session, config.viewport_width.?, config.viewport_height.?, 1.0, false) catch {};
    }
    if (config.geo_lat != null and config.geo_lng != null) {
        applyGeolocation(session, config.geo_lat.?, config.geo_lng.?) catch {};
    }
    if (config.offline) |offline| {
        applyOfflineMode(session, offline) catch {};
    }
    if (config.media_feature) |scheme| {
        applyMediaFeature(session, scheme) catch {};
    }
}
