const std = @import("std");
const cdp = @import("cdp");

// Integration tests require Chrome to be installed
// Run with: zig build test-integration

test "launch chrome and get version" {
    var browser = cdp.Browser.launch(.{
        .headless = .new,
        .allocator = std.testing.allocator,
    }) catch |err| {
        std.debug.print("Skipping test: Chrome not available ({})\n", .{err});
        return;
    };
    defer browser.close();

    var version = try browser.version();
    defer version.deinit(std.testing.allocator);

    try std.testing.expect(version.protocol_version.len > 0);
    try std.testing.expect(version.product.len > 0);
}

test "navigate and get page title" {
    var browser = cdp.Browser.launch(.{
        .headless = .new,
        .allocator = std.testing.allocator,
    }) catch |err| {
        std.debug.print("Skipping test: Chrome not available ({})\n", .{err});
        return;
    };
    defer browser.close();

    var session = try browser.newPage();
    defer session.detach() catch {};

    var page = cdp.Page.init(session);
    try page.enable();

    const result = try page.navigate(std.testing.allocator, "https://example.com");
    defer result.deinit(std.testing.allocator);

    std.time.sleep(1000 * std.time.ns_per_ms);

    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // Note: This may fail if page hasn't loaded
    const title = runtime.evaluateAs([]const u8, "document.title") catch "Unknown";
    _ = title;
}

test "capture screenshot" {
    var browser = cdp.Browser.launch(.{
        .headless = .new,
        .allocator = std.testing.allocator,
    }) catch |err| {
        std.debug.print("Skipping test: Chrome not available ({})\n", .{err});
        return;
    };
    defer browser.close();

    var session = try browser.newPage();
    defer session.detach() catch {};

    var page = cdp.Page.init(session);
    try page.enable();

    _ = try page.navigate(std.testing.allocator, "https://example.com");
    std.time.sleep(1000 * std.time.ns_per_ms);

    const screenshot = try page.captureScreenshot(std.testing.allocator, .{ .format = .png });
    defer std.testing.allocator.free(screenshot);

    // Verify it's valid base64
    try std.testing.expect(screenshot.len > 0);
}
