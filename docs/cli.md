# CLI Reference

zchrome includes a command-line tool for quick browser automation tasks.

## Building

```bash
zig build
```

The CLI binary is located at `./zig-out/bin/zchrome`.

## Usage

```bash
zchrome [options] <command> [command-args]
```

## Global Options

| Option | Description |
|--------|-------------|
| `--url <ws-url>` | Connect to existing Chrome instance |
| `--use <target-id>` | Execute command on existing page |
| `--headless [new\|old]` | Enable headless mode (default: off) |
| `--port <port>` | Debug port (default: 9222) |
| `--chrome <path>` | Chrome binary path |
| `--data-dir <path>` | User data directory for Chrome profile |
| `--timeout <ms>` | Command timeout (default: 30000) |
| `--verbose` | Print CDP messages |
| `--output <path>` | Output file path |
| `--full` | Capture full page screenshot (not just viewport) |

## Config File (zchrome.json)

zchrome stores session information in `zchrome.json` in the current directory. This makes the tool portable and allows subsequent commands to reuse connection information.

```json
{
  "chrome_path": "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
  "data_dir": "D:\\tmp\\chrome-dev-profile",
  "port": 9222,
  "ws_url": "ws://127.0.0.1:9222/devtools/browser/...",
  "last_target": "DC6E72F7B31F6A70C4C2B7A2D5A9ED74"
}
```

Options from command line override config file values.

## Commands

### open

Launch Chrome with remote debugging enabled.

```bash
zchrome open [--chrome <path>] [--data-dir <path>] [--port <port>] [--headless]
```

**Example:**

```bash
# Launch Chrome
zchrome open --chrome "C:\Program Files\Google\Chrome\Application\chrome.exe" --data-dir "D:\tmp\chrome-profile"

# Launch in headless mode
zchrome open --headless
```

### connect

Connect to a running Chrome instance and save the WebSocket URL.

```bash
zchrome connect [--port <port>]
```

**Example:**

```bash
zchrome connect
# Output:
# Connected to Chrome on port 9222
# WebSocket URL: ws://127.0.0.1:9222/devtools/browser/...
```

### navigate

Navigate to a URL and print the final URL and title.

```bash
zchrome navigate <url>
```

**Example:**

```bash
zchrome navigate https://example.com

# Output:
# URL: https://example.com/
# Title: Example Domain
```

### screenshot

Capture a PNG screenshot.

```bash
# Create new page and navigate
zchrome screenshot <url> [--output <path>] [--full]

# Or use existing page (no URL needed)
zchrome --use <target-id> screenshot [--output <path>] [--full]
```

**Options:**
- `--output <path>` - Output file path (default: screenshot.png)
- `--full` - Capture full page screenshot (not just viewport)

**Example:**

```bash
# Viewport screenshot
zchrome screenshot https://example.com --output page.png

# Full page screenshot (captures entire scrollable content)
zchrome screenshot https://example.com --output full.png --full

# Use existing page
zchrome --use 75E5402CE67C63D19659EEFDC1CF292D screenshot --output page.png --full
```

### pdf

Generate a PDF.

```bash
# Create new page and navigate
zchrome pdf <url> [--output <path>]

# Or use existing page (no URL needed)
zchrome --url $url --use <target-id> pdf [--output <path>]
```

**Example:**

```bash
# Create new page
zchrome pdf https://example.com --output page.pdf

# Use existing page
zchrome --url $url --use 75E5402CE67C63D19659EEFDC1CF292D pdf --output page.pdf
```

### evaluate

Evaluate a JavaScript expression.

```bash
# Create new page and navigate
zchrome evaluate <url> <expression>

# Or use existing page (no URL needed)
zchrome --url $url --use <target-id> evaluate <expression>
```

**Example:**

```bash
# Create new page
zchrome evaluate https://example.com "document.title"
# Output: Example Domain

zchrome evaluate https://example.com "document.links.length"
# Output: 1

# Use existing page
zchrome --url $url --use 75E5402CE67C63D19659EEFDC1CF292D evaluate "document.title"
# Output: Result: Example Domain
```

### dom

Query a CSS selector and print the outer HTML.

```bash
# Create new page and navigate
zchrome dom <url> <selector>

# Or use existing page (no URL needed)
zchrome --url $url --use <target-id> dom <selector>
```

**Example:**

```bash
# Create new page
zchrome dom https://example.com "h1"
# Output: <h1>Example Domain</h1>

# Use existing page
zchrome --url $url --use 75E5402CE67C63D19659EEFDC1CF292D dom "h1"
# Output: <h1>Example Domain</h1>
```

### network

Navigate to a URL and log network requests.

```bash
zchrome network <url>
```

::: warning
Network monitoring is not yet fully implemented in the CLI.
:::

### cookies

Dump cookies from a page.

```bash
# Create new page and navigate
zchrome cookies <url>

# Or use existing page (no URL needed)
zchrome --url $url --use <target-id> cookies
```

**Example:**

```bash
# Create new page
zchrome cookies https://example.com

# Use existing page
zchrome --url $url --use 75E5402CE67C63D19659EEFDC1CF292D cookies

# Output:
# Name                           Value                                    Domain
# ------------------------------------------------------------------------------------------
# session_id                     abc123...                                .example.com
```

### version

Print browser version information.

```bash
zchrome version
```

**Example:**

```bash
zchrome version

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
zchrome list-targets
```

**Example:**

```bash
zchrome list-targets

# Output:
# ID                                       Type            Title
# -------------------------------------------------------------------------------------
# 1234567890ABCDEF...                      page            New Tab
# FEDCBA0987654321...                      page            Example Domain
```

### pages

List all open pages with their target IDs. This is useful for finding the target ID to use with the `--use` flag.

```bash
zchrome --url <ws-url> pages
```

**Example:**

```bash
zchrome --url ws://127.0.0.1:9222/devtools/browser/... pages

# Output:
# TARGET ID                                 TITLE                          URL
# --------------------------------------------------------------------------------------------------------------------------
# F8011F4EDE26C3319EC2D2F8ABEA1D96          DevTools                       devtools://devtools/...
# 75E5402CE67C63D19659EEFDC1CF292D          Example Domain                 https://example.com/
# Total: 2 page(s)
```

## Using --use Flag

Execute commands on existing pages by specifying the target ID with the `--use` flag. This allows you to operate on already-open pages instead of creating new ones.

```bash
zchrome --url <ws-url> --use <target-id> <command> [command-args...]
```

**Key Difference:**
- **Without `--use`**: Commands like `screenshot <url>` create a new page, navigate to the URL, then execute
- **With `--use`**: Commands like `screenshot` operate directly on the existing page (no URL parameter needed)

**Parameters:**
- `--use <target-id>` - Target ID from the `pages` command
- `<command>` - Any supported command (navigate, screenshot, pdf, evaluate, dom, cookies)
- `[command-args...]` - Arguments for the command (URL not needed for most commands)

**Examples:**

```bash
# List pages to get target ID
zchrome --url $url pages

# Evaluate JavaScript on an existing page (no URL needed)
zchrome --url $url --use 75E5402CE67C63D19659EEFDC1CF292D evaluate "document.title"
# Output: Result: Example Domain

# Navigate an existing page to new URL
zchrome --url $url --use 75E5402CE67C63D19659EEFDC1CF292D navigate https://example.org

# Take screenshot of existing page (no URL needed)
zchrome --url $url --use 75E5402CE67C63D19659EEFDC1CF292D screenshot --output page.png

# Query DOM on existing page (no URL needed)
zchrome --url $url --use 75E5402CE67C63D19659EEFDC1CF292D dom "h1"

# Dump cookies from existing page (no URL needed)
zchrome --url $url --use 75E5402CE67C63D19659EEFDC1CF292D cookies
```

**Note:** The `--use` flag requires connecting to the browser-level WebSocket URL (`/devtools/browser/...`), not a page-specific URL.

### interactive

Start an interactive REPL session.

```bash
zchrome interactive
```

::: warning
Interactive mode is not yet fully implemented.
:::

### help

Show help message.

```bash
zchrome help
```

## Examples

### Basic Screenshot

```bash
zchrome screenshot https://news.ycombinator.com --output hn.png
```

### Non-Headless Mode

See the browser while it runs:

```bash
zchrome --headless off navigate https://example.com
```

### Custom Chrome Path

```bash
zchrome --chrome "/Applications/Chromium.app/Contents/MacOS/Chromium" version
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
zchrome --url ws://127.0.0.1:9222/devtools/browser/... navigate https://example.com
```

### Longer Timeout

For slow pages:

```bash
zchrome --timeout 60000 screenshot https://slow-site.com --output slow.png
```

### Multiple Commands

```bash
# Get version
zchrome version

# Navigate and get title
zchrome evaluate https://example.com "document.title"

# Capture screenshot
zchrome screenshot https://example.com --output example.png

# Generate PDF
zchrome pdf https://example.com --output example.pdf
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
zchrome --chrome /path/to/chrome navigate https://example.com
```

### Connection Timeout

If you see timeout errors:

1. Increase timeout with `--timeout`
2. Check if Chrome is responding

```bash
zchrome --timeout 60000 navigate https://example.com
```

### Permission Denied

On Linux, you may need to run Chrome without sandbox:

```bash
zchrome --chrome "/usr/bin/chromium-browser" navigate https://example.com
```

The CLI automatically adds `--no-sandbox` when needed.
