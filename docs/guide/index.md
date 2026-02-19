# What is zchrome?

**zchrome** is a native Zig library for controlling Chromium-based browsers through the [Chrome DevTools Protocol](https://chromedevtools.github.io/devtools-protocol/) (CDP).

## Why zchrome?

- **Zero external dependencies** - Built entirely on Zig's standard library
- **Type-safe API** - Strongly typed domain clients with compile-time safety
- **Memory-efficient** - Explicit allocator control with no hidden allocations
- **Cross-platform** - Works on Windows, macOS, and Linux
- **Full CDP coverage** - 11 core domains implemented

## Use Cases

zchrome enables you to:

- **Web Scraping** - Extract data from JavaScript-rendered pages
- **Testing** - Automate browser-based tests
- **Screenshots** - Capture full-page or element screenshots
- **PDF Generation** - Convert web pages to PDF
- **Performance Monitoring** - Collect performance metrics
- **Network Analysis** - Intercept and modify network requests

## Architecture Overview

```
┌─────────────────────────────────────────────────┐
│ Your Application                                │
├─────────────────────────────────────────────────┤
│ Domain Clients (Page, DOM, Runtime, etc.)       │
├─────────────────────────────────────────────────┤
│ Core Protocol (Session, Connection)             │
├─────────────────────────────────────────────────┤
│ Transport (WebSocket / Pipe)                    │
├─────────────────────────────────────────────────┤
│ Chrome/Chromium Browser                         │
└─────────────────────────────────────────────────┘
```

## Requirements

- **Zig** 0.16.0-dev.2535 or later
- **Chrome/Chromium** browser installed on the system

## Next Steps

- [Getting Started](/guide/getting-started) - Install and run your first script
- [Architecture](/guide/architecture) - Understand the library design
- [API Reference](/api/browser) - Explore the full API
