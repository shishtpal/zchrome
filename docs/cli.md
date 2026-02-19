# CLI Reference

zchrome includes a command-line tool for quick browser automation tasks.

## Building

```bash
zig build
```

The CLI binary is located at `./zig-out/bin/cdp-cli`.

## Usage

```bash
cdp-cli [options] <command> [command-args]
```

## Global Options

| Option | Description |
|--------|-------------|
| `--url <ws-url>` | Connect to existing Chrome instance |
| `--headless <mode>` | Headless mode: `new`, `old`, `off` (default: `new`) |
| `--port <port>` | Debug port (default: auto) |
| `--chrome <path>` | Chrome binary path |
| `--timeout <ms>` | Command timeout (default: 30000) |
| `--verbose` | Print CDP messages |
| `--output <path>` | Output file path |

## Commands

### navigate

Navigate to a URL and print the final URL and title.

```bash
cdp-cli navigate <url>
```

**Example:**

```bash
cdp-cli navigate https://example.com

# Output:
# URL: https://example.com/
# Title: Example Domain
```

### screenshot

Navigate to a URL and capture a PNG screenshot.

```bash
cdp-cli screenshot <url> [--output <path>]
```

**Example:**

```bash
cdp-cli screenshot https://example.com --output page.png
```

### pdf

Navigate to a URL and generate a PDF.

```bash
cdp-cli pdf <url> [--output <path>]
```

**Example:**

```bash
cdp-cli pdf https://example.com --output page.pdf
```

### evaluate

Navigate to a URL and evaluate a JavaScript expression.

```bash
cdp-cli evaluate <url> <expression>
```

**Example:**

```bash
cdp-cli evaluate https://example.com "document.title"
# Output: Example Domain

cdp-cli evaluate https://example.com "document.links.length"
# Output: 1

cdp-cli evaluate https://example.com "location.href"
# Output: https://example.com/
```

### dom

Navigate to a URL, query a CSS selector, and print the outer HTML.

```bash
cdp-cli dom <url> <selector>
```

**Example:**

```bash
cdp-cli dom https://example.com "h1"
# Output: <h1>Example Domain</h1>

cdp-cli dom https://example.com "p"
# Output: <p>This domain is...</p>
```

### network

Navigate to a URL and log network requests.

```bash
cdp-cli network <url>
```

::: warning
Network monitoring is not yet fully implemented in the CLI.
:::

### cookies

Navigate to a URL and dump cookies.

```bash
cdp-cli cookies <url>
```

**Example:**

```bash
cdp-cli cookies https://example.com

# Output:
# Name                           Value                                    Domain
# ------------------------------------------------------------------------------------------
# session_id                     abc123...                                .example.com
```

### version

Print browser version information.

```bash
cdp-cli version
```

**Example:**

```bash
cdp-cli version

# Output:
# Protocol Version: 1.3
# Product: Chrome/120.0.6099.130
# Revision: @...
# User Agent: Mozilla/5.0...
# JS Version: 12.0.267.17
```

### list-targets

List all open browser targets (tabs, workers, etc.).

```bash
cdp-cli list-targets
```

**Example:**

```bash
cdp-cli list-targets

# Output:
# ID                                       Type            Title
# -------------------------------------------------------------------------------------
# 1234567890ABCDEF...                      page            New Tab
# FEDCBA0987654321...                      page            Example Domain
```

### interactive

Start an interactive REPL session.

```bash
cdp-cli interactive
```

::: warning
Interactive mode is not yet fully implemented.
:::

### help

Show help message.

```bash
cdp-cli help
```

## Examples

### Basic Screenshot

```bash
cdp-cli screenshot https://news.ycombinator.com --output hn.png
```

### Non-Headless Mode

See the browser while it runs:

```bash
cdp-cli --headless off navigate https://example.com
```

### Custom Chrome Path

```bash
cdp-cli --chrome "/Applications/Chromium.app/Contents/MacOS/Chromium" version
```

### Connect to Existing Chrome

First, start Chrome with debugging:

```bash
chrome --remote-debugging-port=9222
```

You can get the URL from `http://127.0.0.1:9222/json/version`

```ps1
Invoke-RestMethod -Uri "http://127.0.0.1:9222/json"         # List all pages/targets
Invoke-RestMethod -Uri "http://127.0.0.1:9222/json/version" # Browser info + ws URL
```


```json
{
   "Browser": "Chrome/145.0.7632.76",
   "Protocol-Version": "1.3",
   "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36",
   "V8-Version": "14.5.201.7",
   "WebKit-Version": "537.36 (@ee36f024f43a5615aa1aea2186a06e5cabc45bb7)",
   "webSocketDebuggerUrl": "ws://127.0.0.1:9222/devtools/browser/8caa65d2-8631-44ab-b4a1-e5ef11377ab4"
}
```

Then connect:

```bash
cdp-cli --url ws://127.0.0.1:9222/devtools/browser/... navigate https://example.com
```

### Longer Timeout

For slow pages:

```bash
cdp-cli --timeout 60000 screenshot https://slow-site.com --output slow.png
```

### Multiple Commands

```bash
# Get version
cdp-cli version

# Navigate and get title
cdp-cli evaluate https://example.com "document.title"

# Capture screenshot
cdp-cli screenshot https://example.com --output example.png

# Generate PDF
cdp-cli pdf https://example.com --output example.pdf
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error (invalid arguments, Chrome not found, etc.) |

## Troubleshooting

### Chrome Not Found

If you see "Failed to launch browser: ChromeNotFound":

1. Install Chrome or Chromium
2. Or specify the path with `--chrome`

```bash
cdp-cli --chrome /path/to/chrome navigate https://example.com
```

### Connection Timeout

If you see timeout errors:

1. Increase timeout with `--timeout`
2. Check if Chrome is responding

```bash
cdp-cli --timeout 60000 navigate https://example.com
```

### Permission Denied

On Linux, you may need to run Chrome without sandbox:

```bash
cdp-cli --chrome "/usr/bin/chromium-browser" navigate https://example.com
```

The CLI automatically adds `--no-sandbox` when needed.
