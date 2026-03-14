---
name: using-zchrome-browser-automation
description: "Automate Chrome browsers using the zchrome CLI tool. Use when asked to interact with web pages, take screenshots, fill forms, scrape data, record/replay macros, run browser tests, or control Chrome via CDP. Triggers on: browser automation, web scraping, form filling, screenshot, macro recording, e2e testing, zchrome."
---

# Using zchrome for Browser Automation

zchrome is a Chrome DevTools Protocol (CDP) CLI tool and Zig library for programmatic browser control. It provides stateless, composable commands that persist session state in `zchrome.json`.

## Prerequisites

- **Chrome/Chromium** installed (or a cloud provider API key)
- **zchrome** binary built: `zig build -Doptimize=ReleaseFast`
- (Optional) **FFmpeg** for video recording of macro replays

## Quick Reference

```
zchrome [options] <command> [command-args]
```

### Global Options

| Option | Description |
|--------|-------------|
| `--url <ws-url>` | Connect to existing Chrome (ws://...) |
| `--use <target-id>` | Execute command on a specific page |
| `--headless [new\|old]` | Headless mode |
| `--port <port>` | Debug port (default: 9222) |
| `--chrome <path>` | Chrome binary path |
| `--data-dir <path>` | User data directory |
| `--timeout <ms>` | Command timeout (default: 30000) |
| `--verbose` | Print CDP messages |
| `--output <path>` | Output file path (screenshot/pdf) |
| `--full` | Full page screenshot |
| `--provider <name>` | Cloud provider (kernel, notte, browserbase, browserless) |
| `--cleanup` | Close cloud session when command exits |
| `--session <name>` | Named session for isolated config |

## Workflow Guides

Each workflow is documented in its own file for focused reference:

| File | Topics |
|------|--------|
| [01-launch-connect.md](01-launch-connect.md) | Launch Chrome, connect, navigate, headless mode, named sessions |
| [02-elements-interaction.md](02-elements-interaction.md) | Snapshots, selectors, click/fill/type, keyboard, mouse, getters, waits |
| [03-capture-output.md](03-capture-output.md) | Screenshots, PDFs, JavaScript evaluation |
| [04-cookies-storage.md](04-cookies-storage.md) | Cookie management, localStorage/sessionStorage |
| [05-network.md](05-network.md) | Network interception, mocking, blocking, redirecting |
| [06-macros.md](06-macros.md) | Macro recording, replay, assertions, capture variables, chaining, video |
| [07-tabs-windows.md](07-tabs-windows.md) | Tab/window management, multi-page targeting |
| [08-devtools.md](08-devtools.md) | Console, tracing, profiling, highlight, auth state |
| [09-diffing.md](09-diffing.md) | Snapshot diff, screenshot diff, URL comparison |
| [10-cloud-providers.md](10-cloud-providers.md) | Kernel, Notte, Browserbase, Browserless setup |
| [11-extensions.md](11-extensions.md) | Loading/managing Chrome extensions |
| [12-interactive-repl.md](12-interactive-repl.md) | Interactive REPL mode |
| [13-common-patterns.md](13-common-patterns.md) | Login+scrape, form testing, CI/CD, auth state, screenshot testing |
| [14-troubleshooting.md](14-troubleshooting.md) | Common errors, Chrome not found, port conflicts, connection issues |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `ZCHROME_SESSION` | Default session name (default: "default") |
| `ZCHROME_BROWSER` | Chrome executable path |
| `ZCHROME_PORT` | Debug port (default: 9222) |
| `ZCHROME_DATA_DIR` | Chrome user data directory |
| `ZCHROME_HEADLESS` | Headless mode: new, old, off |
| `ZCHROME_VERBOSE` | Enable verbose output (1 or true) |
| `ZCHROME_PROVIDER` | Cloud provider name |
| `ZCHROME_EXTENSIONS` | Comma-separated extension paths |

Priority: CLI flag > Environment variable > Session config > Default.
