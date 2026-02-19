# Emulation Domain

The `Emulation` domain provides methods for device emulation, viewport configuration, and geolocation simulation.

## Import

```zig
const cdp = @import("cdp");
const Emulation = cdp.Emulation;
```

## Initialization

```zig
var session = try browser.newPage();
var emulation = Emulation.init(session);
```

## Methods

### setDeviceMetricsOverride

Set device metrics (viewport, device scale, etc.).

```zig
pub fn setDeviceMetricsOverride(
    self: *Emulation,
    width: i32,
    height: i32,
    device_scale_factor: f64,
    mobile: bool,
) !void
```

**Example:**

```zig
// iPhone 12 Pro
try emulation.setDeviceMetricsOverride(390, 844, 3, true);

// Desktop 1080p
try emulation.setDeviceMetricsOverride(1920, 1080, 1, false);
```

### clearDeviceMetricsOverride

Clear device metrics override.

```zig
pub fn clearDeviceMetricsOverride(self: *Emulation) !void
```

### setUserAgentOverride

Override user agent string.

```zig
pub fn setUserAgentOverride(
    self: *Emulation,
    user_agent: []const u8,
    accept_language: ?[]const u8,
    platform: ?[]const u8,
) !void
```

**Example:**

```zig
try emulation.setUserAgentOverride(
    "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15",
    "en-US",
    "iPhone",
);
```

### setGeolocationOverride

Set geolocation coordinates.

```zig
pub fn setGeolocationOverride(
    self: *Emulation,
    latitude: f64,
    longitude: f64,
    accuracy: ?f64,
) !void
```

**Example:**

```zig
// New York City
try emulation.setGeolocationOverride(40.7128, -74.0060, 100);

// London
try emulation.setGeolocationOverride(51.5074, -0.1278, 100);
```

### clearGeolocationOverride

Clear geolocation override.

```zig
pub fn clearGeolocationOverride(self: *Emulation) !void
```

### setTouchEmulationEnabled

Enable touch event emulation.

```zig
pub fn setTouchEmulationEnabled(self: *Emulation, enabled: bool, max_touch_points: ?i32) !void
```

**Example:**

```zig
try emulation.setTouchEmulationEnabled(true, 5);
```

### setEmulatedMedia

Emulate media type and features.

```zig
pub fn setEmulatedMedia(
    self: *Emulation,
    media: ?[]const u8,
    features: ?[]const MediaFeature,
) !void
```

**Example:**

```zig
// Print preview
try emulation.setEmulatedMedia("print", null);

// Dark mode
try emulation.setEmulatedMedia(null, &[_]MediaFeature{
    .{ .name = "prefers-color-scheme", .value = "dark" },
});
```

### setTimezoneOverride

Override timezone.

```zig
pub fn setTimezoneOverride(self: *Emulation, timezone_id: []const u8) !void
```

**Example:**

```zig
try emulation.setTimezoneOverride("America/New_York");
try emulation.setTimezoneOverride("Europe/London");
try emulation.setTimezoneOverride("Asia/Tokyo");
```

### setLocaleOverride

Override locale.

```zig
pub fn setLocaleOverride(self: *Emulation, locale: []const u8) !void
```

### setCPUThrottlingRate

Throttle CPU.

```zig
pub fn setCPUThrottlingRate(self: *Emulation, rate: f64) !void
```

**Example:**

```zig
// 4x slowdown
try emulation.setCPUThrottlingRate(4);
```

### setScriptExecutionDisabled

Disable JavaScript execution.

```zig
pub fn setScriptExecutionDisabled(self: *Emulation, disabled: bool) !void
```

## Device Presets

Common device configurations:

### iPhone 12 Pro

```zig
try emulation.setDeviceMetricsOverride(390, 844, 3, true);
try emulation.setUserAgentOverride(
    "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15",
    "en-US",
    "iPhone",
);
try emulation.setTouchEmulationEnabled(true, 5);
```

### Pixel 5

```zig
try emulation.setDeviceMetricsOverride(393, 851, 2.75, true);
try emulation.setUserAgentOverride(
    "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 Chrome/90.0.4430.91 Mobile Safari/537.36",
    "en-US",
    "Linux armv8l",
);
try emulation.setTouchEmulationEnabled(true, 5);
```

### iPad Pro

```zig
try emulation.setDeviceMetricsOverride(1024, 1366, 2, true);
try emulation.setUserAgentOverride(
    "Mozilla/5.0 (iPad; CPU OS 15_0 like Mac OS X) AppleWebKit/605.1.15",
    "en-US",
    "iPad",
);
try emulation.setTouchEmulationEnabled(true, 5);
```

## Complete Example

```zig
const std = @import("std");
const cdp = @import("cdp");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var browser = try cdp.Browser.launch(.{
        .headless = .new,
        .allocator = allocator,
        .io = init.io,
    });
    defer browser.close();

    var session = try browser.newPage();
    defer session.detach() catch {};

    var page = cdp.Page.init(session);
    var emulation = cdp.Emulation.init(session);
    
    try page.enable();

    // Emulate iPhone
    try emulation.setDeviceMetricsOverride(390, 844, 3, true);
    try emulation.setUserAgentOverride(
        "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)",
        "en-US",
        "iPhone",
    );
    try emulation.setTouchEmulationEnabled(true, 5);

    // Set location to San Francisco
    try emulation.setGeolocationOverride(37.7749, -122.4194, 100);

    // Set timezone
    try emulation.setTimezoneOverride("America/Los_Angeles");

    _ = try page.navigate(allocator, "https://example.com");

    // Capture mobile screenshot
    const screenshot = try page.captureScreenshot(allocator, .{ .format = .png });
    defer allocator.free(screenshot);

    std.debug.print("Mobile screenshot: {} bytes\n", .{screenshot.len});
}
```
