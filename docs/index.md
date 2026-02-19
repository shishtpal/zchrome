---
layout: home

hero:
  name: "zchrome"
  text: "Chrome DevTools Protocol for Zig"
  tagline: Native CDP client with zero external dependencies
  actions:
    - theme: brand
      text: Get Started
      link: /guide/getting-started
    - theme: alt
      text: API Reference
      link: /api/browser
    - theme: alt
      text: View on GitHub
      link: https://github.com/shishtpal/zchrome

features:
  - icon: "&#9889;"
    title: Zero Dependencies
    details: Built entirely on Zig's standard library. No external dependencies required.
  - icon: "&#128274;"
    title: Type-Safe API
    details: Strongly typed domain clients with compile-time safety and clear error handling.
  - icon: "&#128640;"
    title: Full CDP Coverage
    details: 11 CDP domains implemented - Page, DOM, Runtime, Network, Input, and more.
  - icon: "&#128296;"
    title: Dual Transport
    details: WebSocket and Pipe transport support for maximum flexibility.
  - icon: "&#128187;"
    title: Cross-Platform
    details: Works on Windows, macOS, and Linux with automatic Chrome discovery.
  - icon: "&#128736;"
    title: CLI Included
    details: Ready-to-use command-line tool for common automation tasks.
---

## Quick Example

```zig
const std = @import("std");
const cdp = @import("cdp");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // Launch browser
    var browser = try cdp.Browser.launch(.{
        .headless = .new,
        .allocator = allocator,
        .io = init.io,
    });
    defer browser.close();

    // Create new page and navigate
    var session = try browser.newPage();
    var page = cdp.Page.init(session);
    try page.enable();

    _ = try page.navigate(allocator, "https://example.com");

    // Capture screenshot
    const screenshot = try page.captureScreenshot(allocator, .{ .format = .png });
    defer allocator.free(screenshot);
}
```

## Supported Domains

| Domain | Description |
|--------|-------------|
| **Page** | Navigation, screenshots, PDF generation |
| **DOM** | Document querying and manipulation |
| **Runtime** | JavaScript execution |
| **Network** | Request/response tracking |
| **Input** | Mouse and keyboard events |
| **Emulation** | Device and viewport emulation |
| **Fetch** | Network request interception |
| **Storage** | Cookies and local storage |
| **Target** | Tab and target management |
| **Performance** | Performance metrics |
| **Browser** | Browser-level operations |
