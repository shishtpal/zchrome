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

zchrome stores session information in `zchrome.json` alongside the executable. This makes the tool portable and allows subsequent commands to reuse connection information and session settings.

```json
{
  "chrome_path": "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
  "data_dir": "D:\\tmp\\chrome-dev-profile",
  "port": 9222,
  "ws_url": "ws://127.0.0.1:9222/devtools/browser/...",
  "last_target": "DC6E72F7B31F6A70C4C2B7A2D5A9ED74",
  "user_agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Firefox/121.0",
  "viewport_width": 1920,
  "viewport_height": 1080,
  "device_name": "Desktop",
  "geo_lat": 40.7128,
  "geo_lng": -74.0060,
  "offline": false,
  "media_feature": "dark"
}
```

**Configuration fields:**

| Field | Description |
|-------|-------------|
| `chrome_path` | Path to Chrome executable |
| `data_dir` | User data directory for Chrome profile |
| `port` | Debug port (default: 9222) |
| `ws_url` | WebSocket URL for browser connection |
| `last_target` | Last used target ID (for `--use` flag) |
| `user_agent` | Custom user agent string |
| `viewport_width` | Viewport width in pixels |
| `viewport_height` | Viewport height in pixels |
| `device_name` | Emulated device name |
| `geo_lat` | Geolocation latitude |
| `geo_lng` | Geolocation longitude |
| `offline` | Offline mode enabled |
| `media_feature` | Preferred color scheme (dark/light) |

**Note:** Session settings (user_agent, viewport, geo, offline, media_feature) are automatically re-applied when connecting to a page.

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

### network

Network monitoring command.

```bash
zchrome network <url>
```

::: info
Network monitoring CLI is a placeholder. For network interception, use the programmatic API with the Network or Fetch domains.
:::

### cookies

Manage browser cookies. Without a subcommand, lists all cookies for the current page.

```bash
zchrome cookies [domain]                 # List all cookies (optional domain filter)
zchrome cookies get <name> [domain]      # Get a specific cookie
zchrome cookies set <name> <val>         # Set a cookie
zchrome cookies delete <name> [domain]   # Delete a cookie
zchrome cookies clear [domain]           # Clear all cookies (optional domain filter)
zchrome cookies export <path> [domain]   # Export cookies to JSON file
zchrome cookies import <path> [domain]   # Import cookies from JSON file
```

**Examples:**

```bash
# List all cookies
zchrome cookies
# Output:
# Name                           Value                                    Domain
# ------------------------------------------------------------------------------------------
# session_id                     abc123...                                .example.com

# List cookies for a specific domain
zchrome cookies .google.com

# Get a specific cookie
zchrome cookies get session_id

# Set a cookie (uses current page URL for domain)
zchrome cookies set theme dark

# Delete a cookie
zchrome cookies delete tracking_id

# Clear all cookies for a domain
zchrome cookies clear .example.com

# Export cookies
zchrome cookies export cookies.json

# Import cookies (override domain)
zchrome cookies import cookies.json .staging.example.com
```

### storage

Manage localStorage and sessionStorage on the current page.

```bash
zchrome storage local                  # Get all localStorage entries (JSON)
zchrome storage local <key>            # Get specific key
zchrome storage local set <key> <val>  # Set value
zchrome storage local clear            # Clear all localStorage
zchrome storage local export <file>    # Export to JSON/YAML file
zchrome storage local import <file>    # Import from JSON/YAML file

zchrome storage session                # Same for sessionStorage
zchrome storage session <key>
zchrome storage session set <key> <val>
zchrome storage session clear
zchrome storage session export <file>
zchrome storage session import <file>
```

**Examples:**

```bash
# List all localStorage entries
zchrome storage local
# Output: {"theme":"dark","lang":"en"}

# Get a specific key
zchrome storage local theme
# Output: dark

# Set a value
zchrome storage local set theme light

# Clear all localStorage
zchrome storage local clear

# Export localStorage to JSON file
zchrome storage local export storage.json
# Output: Exported local storage to storage.json

# Export localStorage to YAML file
zchrome storage local export storage.yaml
# Output: Exported local storage to storage.yaml

# Import localStorage from JSON file
zchrome storage local import storage.json
# Output: Imported 2 entries into local storage

# Import localStorage from YAML file
zchrome storage local import storage.yaml

# Same commands work for sessionStorage
zchrome storage session
zchrome storage session set token abc123
zchrome storage session export session.json
zchrome storage session import session.json
```

**File Formats:**

- **JSON**: A flat object with string keys and string values: `{"key1": "value1", "key2": "value2"}`
- **YAML**: Simple `key: value` lines (detected by `.yaml` or `.yml` extension):
  ```yaml
  key1: value1
  key2: value2
  ```

### tab

Manage browser tabs with simple numbered references.

```bash
zchrome tab                     # List tabs (numbered)
zchrome tab new [url]           # Open new tab (optionally with URL)
zchrome tab <n>                 # Switch to tab n
zchrome tab close [n]           # Close tab n (default: current)
```

**Examples:**

```bash
# List all tabs
zchrome tab
#   1: Example Domain               https://example.com
#   2: Google                        https://www.google.com
# Total: 2 tab(s)

# Open new tab
zchrome tab new
zchrome tab new https://github.com

# Switch to tab 2
zchrome tab 2

# Close tab 1
zchrome tab close 1
```

### window

Manage browser windows.

```bash
zchrome window new              # Open new browser window
```

**Example:**

```bash
zchrome window new
# New window opened
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
- `<command>` - Any supported command (navigate, screenshot, pdf, evaluate, get, cookies, storage)
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

# Get outerHTML on existing page (no URL needed)
zchrome --url $url --use 75E5402CE67C63D19659EEFDC1CF292D get dom "h1"

# List cookies from existing page
zchrome --url $url --use 75E5402CE67C63D19659EEFDC1CF292D cookies

# Set cookie on existing page
zchrome --url $url --use 75E5402CE67C63D19659EEFDC1CF292D cookies set theme dark

# Get localStorage from existing page
zchrome --url $url --use 75E5402CE67C63D19659EEFDC1CF292D storage local
```

**Note:** The `--use` flag requires connecting to the browser-level WebSocket URL (`/devtools/browser/...`), not a page-specific URL.

### snapshot

Capture the accessibility tree of the active page and save it to `zsnap.json`. This creates refs (like `@e1`, `@e2`) that can be used in subsequent commands.

```bash
zchrome snapshot [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `-i, --interactive-only` | Only include interactive elements (buttons, links, inputs, etc.) |
| `-c, --compact` | Skip empty structural elements |
| `-d, --depth <n>` | Limit tree depth |
| `-s, --selector <sel>` | Scope snapshot to a CSS selector |

**Example:**

```bash
# Basic snapshot
zchrome snapshot

# Interactive elements only (cleaner output)
zchrome snapshot -i

# Compact mode with depth limit
zchrome snapshot -c -d 3

# Scope to specific container
zchrome snapshot -s "#main-content"
```

**Output:**

```
- navigation
  - link "Home" [ref=e1]
  - link "Products" [ref=e2]
- main
  - heading "Welcome" [ref=e3]
  - textbox "Email" [ref=e4]
  - button "Submit" [ref=e5]

--- 5 element(s) with refs ---

Snapshot saved to: zsnap.json
Use @e<N> refs in subsequent commands
```

## Element Actions

All element action commands accept a `<selector>` which can be:
- **CSS selector**: `#login-btn`, `.submit`, `input[name="email"]`
- **Snapshot ref**: `@e3`, `@e15` (from the last `zchrome snapshot`)

### click

Click an element.

```bash
zchrome click <selector>
```

**Example:**

```bash
# By CSS selector
zchrome click "#login-btn"
zchrome click "button.submit"

# By snapshot ref
zchrome click @e5
```

### dblclick

Double-click an element.

```bash
zchrome dblclick <selector>
```

**Example:**

```bash
zchrome dblclick "#item-row"
zchrome dblclick @e7
```

### hover

Hover over an element (move mouse to element center).

```bash
zchrome hover <selector>
```

**Example:**

```bash
zchrome hover "#dropdown-trigger"
zchrome hover @e3
```

### focus

Focus an element.

```bash
zchrome focus <selector>
```

**Example:**

```bash
zchrome focus "#email-input"
zchrome focus @e4
```

### type

Type text into an element. This appends to existing content.

```bash
zchrome type <selector> <text>
```

**Example:**

```bash
zchrome type "#search" "hello world"
zchrome type @e4 "user@example.com"
```

### fill

Clear an element and fill it with text. This is like `type` but clears existing content first.

```bash
zchrome fill <selector> <text>
```

**Example:**

```bash
zchrome fill "#email" "new@example.com"
zchrome fill @e4 "password123"
```

### select

Select an option in a dropdown by value.

```bash
zchrome select <selector> <value>
```

**Example:**

```bash
zchrome select "#country" "US"
zchrome select @e8 "option2"
```

### check

Check a checkbox (no-op if already checked).

```bash
zchrome check <selector>
```

**Example:**

```bash
zchrome check "#agree-terms"
zchrome check @e6
```

### uncheck

Uncheck a checkbox (no-op if already unchecked).

```bash
zchrome uncheck <selector>
```

**Example:**

```bash
zchrome uncheck "#newsletter"
zchrome uncheck @e6
```

### scroll

Scroll the page in a direction.

```bash
zchrome scroll <direction> [pixels]
```

**Parameters:**
- `<direction>` - One of: `up`, `down`, `left`, `right`
- `[pixels]` - Optional scroll amount (default: 300)

**Example:**

```bash
zchrome scroll down
zchrome scroll down 500
zchrome scroll up 200
zchrome scroll right 100
```

### scrollintoview

Scroll an element into view (centered in viewport).

```bash
zchrome scrollintoview <selector>
zchrome scrollinto <selector>  # alias
```

**Example:**

```bash
zchrome scrollintoview "#footer"
zchrome scrollinto @e15
```

### drag

Drag an element to another element.

```bash
zchrome drag <source-selector> <target-selector>
```

**Example:**

```bash
zchrome drag "#draggable" "#dropzone"
zchrome drag @e3 @e7
```

### upload

Upload files to a file input element. This sets the files on the input without submitting the form.

```bash
zchrome upload <selector> <file1> [file2...]
```

**Parameters:**
- `<selector>` - CSS selector or snapshot ref for the file input element
- `<file1> [file2...]` - One or more file paths (relative or absolute)

**Example:**

```bash
# Single file upload
zchrome upload "#file-input" document.pdf
zchrome upload "input[type=file]" ./report.xlsx

# Multiple files
zchrome upload @e5 file1.txt file2.txt file3.txt

# Absolute path
zchrome upload "#upload" "C:\Users\name\Documents\report.pdf"
```

**Note:** File paths are automatically converted to absolute paths. The command only selects the files - it does not submit any form. Use `click` on the submit button afterwards if needed.

## Keyboard Actions

### press

Press and release a key. Supports modifier combinations.

```bash
zchrome press <key>
zchrome key <key>  # alias
```

**Key Format:**
- Simple keys: `Enter`, `Tab`, `Escape`, `Backspace`, `Delete`, `Space`
- Arrow keys: `ArrowUp`, `ArrowDown`, `ArrowLeft`, `ArrowRight`
- Function keys: `F1`, `F2`, ... `F12`
- With modifiers: `Control+a`, `Control+Shift+s`, `Alt+Tab`

**Modifier Keys:**
| Modifier | Aliases |
|----------|---------|
| Control | `Control`, `Ctrl` |
| Alt | `Alt` |
| Shift | `Shift` |
| Meta (Cmd) | `Meta`, `Cmd` |

**Example:**

```bash
# Simple key press
zchrome press Enter
zchrome press Tab
zchrome key Escape  # Using alias

# Key combinations
zchrome press Control+a      # Select all
zchrome press Control+c      # Copy
zchrome press Control+v      # Paste
zchrome press Control+Shift+s # Save as
zchrome press Alt+F4         # Close window
```

### keydown

Hold a key down. Useful for modifier keys during other actions.

```bash
zchrome keydown <key>
```

**Example:**

```bash
# Hold Shift while clicking (for selection)
zchrome keydown Shift
zchrome click "#item1"
zchrome click "#item3"
zchrome keyup Shift

# Hold Control for multi-select
zchrome keydown Control
zchrome click @e5
zchrome click @e7
zchrome keyup Control
```

### keyup

Release a held key.

```bash
zchrome keyup <key>
```

**Example:**

```bash
zchrome keyup Shift
zchrome keyup Control
```

## Mouse Commands

Low-level mouse control. The last mouse position is persisted to `zchrome.json` so that `mouse down`, `mouse up`, and `mouse wheel` can be used in subsequent commands without repeating coordinates.

### mouse move

Move the mouse cursor to absolute viewport coordinates.

```bash
zchrome mouse move <x> <y>
```

**Example:**

```bash
zchrome mouse move 100 200
```

### mouse down

Press a mouse button at the last known mouse position.

```bash
zchrome mouse down [button]
```

`button` is one of `left` (default), `right`, or `middle`.

**Example:**

```bash
zchrome mouse move 300 400
zchrome mouse down left
```

### mouse up

Release a mouse button at the last known mouse position.

```bash
zchrome mouse up [button]
```

**Example:**

```bash
zchrome mouse up left
```

### mouse wheel

Scroll the mouse wheel at the last known mouse position.

```bash
zchrome mouse wheel <dy> [dx]
```

Positive `dy` scrolls down; negative scrolls up.

**Example:**

```bash
# Scroll down 300 pixels
zchrome mouse wheel 300

# Scroll up 200 pixels
zchrome mouse wheel -200

# Scroll right 100 pixels
zchrome mouse wheel 0 100

# Drag-and-drop sequence
zchrome mouse move 100 200
zchrome mouse down
zchrome mouse move 400 200
zchrome mouse up
```

## Cursor Commands

Show information about elements at the cursor position or with focus.

### cursor active

Show the currently focused element (the element that would receive keyboard input).

```bash
zchrome cursor active
```

**Output:**

```
Active element:
  type: html
  tag: input
  role: textbox
  name: "Search"
  id: search-box
  selector: input#search-box
  position: (100, 200)
```

**Element Types:**

| Type | Description |
|------|-------------|
| `html` | Standard HTML element |
| `img` | Image element |
| `svg` | SVG element |
| `canvas` | Canvas element |
| `iframe` | Iframe element |
| `shadow` | Element in shadow DOM |
| `placeholder` | Input with placeholder text |

**Example:**

```bash
# Focus an element and check what's active
zchrome focus "#email"
zchrome cursor active
# Output shows the email input element

# After clicking a button
zchrome click "#submit"
zchrome cursor active
# Output shows the submit button (it received focus from the click)
```

### cursor hover

Show the element under the last known mouse cursor position. Requires `mouse move` to be called first to set the position.

```bash
zchrome cursor hover
```

**Output:**

```
Element at cursor (150, 300):
  type: html
  tag: button
  role: button
  name: "Submit"
  selector: button.submit-btn
```

**Example:**

```bash
# Move mouse and check what's under it
zchrome mouse move 300 400
zchrome cursor hover
# Output shows the element at coordinates (300, 400)

# Useful for debugging hover states
zchrome mouse move 100 200
zchrome cursor hover
```

**Note:** The `cursor hover` command uses the last saved mouse position from `zchrome.json`. You must use `mouse move` first to set the position.

### cursor record

Record mouse and keyboard events to a JSON macro file using WebSocket streaming. Events are captured in real-time and survive page reloads.

```bash
zchrome cursor record <filename.json>
```

**How it works:**

1. Starts a WebSocket server on port 4040
2. Injects JavaScript into the page that connects to the server
3. Events stream in real-time to zchrome
4. Script auto-injects on page navigation (survives reloads)
5. Press Enter to stop recording and save

**Example:**

```bash
# Start recording
zchrome cursor record macro.json
# Recording on port 4040... Press Enter to stop.
# (Events stream in real-time, survives page reloads)
#   (browser connected)
# (interact with the page, navigate, reload - all captured)
# Recorded 42 events to macro.json
```

**Note:** The recording survives page reloads because the JavaScript is injected via `Page.addScriptToEvaluateOnNewDocument`, which automatically runs on every new page load.

**Output Format:**

The macro file is a JSON file with the following structure:

```json
{
  "version": 1,
  "recorded_at": "2026-02-23T15:20:00Z",
  "events": [
    {
      "type": "mousemove",
      "timestamp": 0,
      "x": 100.0,
      "y": 200.0
    },
    {
      "type": "mousedown",
      "timestamp": 150,
      "x": 100.0,
      "y": 200.0,
      "button": "left"
    },
    {
      "type": "keydown",
      "timestamp": 300,
      "key": "a",
      "code": "KeyA",
      "modifiers": 0
    }
  ]
}
```

**Event Types:**
- `mousemove` - Mouse movement (x, y coordinates)
- `mousedown` - Mouse button pressed (button: left/right/middle)
- `mouseup` - Mouse button released
- `wheel` - Mouse wheel scroll (deltaX, deltaY)
- `keydown` - Key pressed (key, code, modifiers)
- `keyup` - Key released

### cursor replay

Replay recorded events from a macro file.

```bash
zchrome cursor replay <filename.json>
```

**Example:**

```bash
# Replay recorded events
zchrome cursor replay macro.json
# Replaying 42 events from macro.json...
# Replay complete.
```

**Timing:** Events are replayed with the original timing preserved. The delay between events is calculated from the timestamps in the macro file.

### cursor optimize

Optimize a macro file by removing redundant events and rescaling timing.

```bash
zchrome cursor optimize <filename.json> [--speed=N]
```

**Options:**
- `--speed=N` - Speed multiplier (default: 3)
  - Positive values speed up playback (divide delays)
  - Negative values slow down playback (multiply delays)
  - `0` preserves original timing

**Example:**

```bash
# Speed up playback by 3x (default)
zchrome cursor optimize macro.json

# Speed up by 5x
zchrome cursor optimize macro.json --speed=5

# Slow down by 2x
zchrome cursor optimize macro.json --speed=-2

# Preserve original timing
zchrome cursor optimize macro.json --speed=0
```

**Output:**

```
Optimized macro.json: 42 -> 38 events (speed=3)
```

**Optimization Details:**
- Merges consecutive `mousemove` events within 15ms
- Rescales all event timestamps based on speed multiplier
- Reduces file size and improves replay performance

## Wait Commands

Wait for various conditions before proceeding. All wait commands have a default timeout of 30 seconds (configurable with `--timeout`).

### wait (selector)

Wait for an element to be visible on the page.

```bash
zchrome wait <selector>
```

**Example:**

```bash
zchrome wait "#login-form"
zchrome wait ".loading-complete"
zchrome wait @e5  # Wait for snapshot ref
```

### wait (time)

Wait for a specified number of milliseconds.

```bash
zchrome wait <milliseconds>
```

**Example:**

```bash
zchrome wait 1000    # Wait 1 second
zchrome wait 5000    # Wait 5 seconds
```

### wait --text

Wait for specific text to appear anywhere on the page.

```bash
zchrome wait --text "Welcome"
zchrome wait --text "Login successful"
```

### wait --match

Wait for the URL to match a pattern. Supports glob patterns with `*` (single segment) and `**` (multiple segments).

```bash
zchrome wait --match "**/dashboard"
zchrome wait --match "*/login*"
zchrome wait --match "https://example.com/success"
```

### wait --load

Wait for a specific load state.

```bash
zchrome wait --load load            # Wait for load event
zchrome wait --load domcontentloaded # Wait for DOMContentLoaded
zchrome wait --load networkidle     # Wait for network to be idle
```

**Load States:**

| State | Description |
|-------|-------------|
| `load` | Wait for the `load` event to fire |
| `domcontentloaded` | Wait for `DOMContentLoaded` event |
| `networkidle` | Wait for network activity to settle |

### wait --fn

Wait for a JavaScript expression to return a truthy value.

```bash
zchrome wait --fn "window.ready === true"
zchrome wait --fn "document.querySelector('#app').dataset.loaded"
zchrome wait --fn "typeof myApp !== 'undefined'"
```

### Combining with Other Commands

```bash
# Navigate and wait for content
zchrome navigate https://example.com
zchrome wait --load networkidle
zchrome wait "#main-content"
zchrome snapshot -i

# Form submission workflow
zchrome fill "#email" "user@example.com"
zchrome click "#submit"
zchrome wait --text "Success"
zchrome screenshot --output success.png

# Wait for SPA navigation
zchrome click "#dashboard-link"
zchrome wait --match "**/dashboard"
zchrome wait --fn "window.dashboardLoaded"
```

## Getters

### get text

Get the text content of an element.

```bash
zchrome get text <selector>
```

**Example:**

```bash
zchrome get text "#heading"
zchrome get text @e3
```

### get html

Get the innerHTML of an element.

```bash
zchrome get html <selector>
```

**Example:**

```bash
zchrome get html "#content"
zchrome get html @e5
```

### get dom

Get the outerHTML of an element (includes the element's own tag).

```bash
zchrome get dom <selector>
```

**Example:**

```bash
zchrome get dom "h1"
zchrome get dom @e22
```

### get value

Get the value of an input element.

```bash
zchrome get value <selector>
```

**Example:**

```bash
zchrome get value "#email"
zchrome get value @e4
```

### get attr

Get an attribute value from an element.

```bash
zchrome get attr <selector> <attribute>
```

**Example:**

```bash
zchrome get attr "#link" href
zchrome get attr @e3 data-id
zchrome get attr "img.logo" src
```

### get title

Get the page title.

```bash
zchrome get title
```

### get url

Get the current page URL.

```bash
zchrome get url
```

### get useragent

Get the browser's user agent string.

```bash
zchrome get useragent
zchrome get ua  # alias
```

**Example:**

```bash
zchrome get ua
# Output: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36...
```

### get count

Count elements matching a selector.

```bash
zchrome get count <selector>
```

**Example:**

```bash
zchrome get count "li.item"
zchrome get count "button"
```

### get box

Get the bounding box (position and size) of an element.

```bash
zchrome get box <selector>
```

**Output format:** `x=100 y=200 width=300 height=50`

**Example:**

```bash
zchrome get box "#banner"
zchrome get box @e5
```

### get styles

Get all computed styles of an element as JSON.

```bash
zchrome get styles <selector>
```

**Example:**

```bash
zchrome get styles "#button"
zchrome get styles @e3
```

**Output:** JSON object with all computed CSS properties.

## Session Emulation (set)

Configure browser session settings. Settings are applied immediately via CDP and persisted to `zchrome.json` for future sessions.

### set viewport

Set the viewport (window) size.

```bash
zchrome set viewport <width> <height>
```

**Example:**

```bash
zchrome set viewport 1920 1080
zchrome set viewport 375 667   # iPhone SE size
```

### set device

Emulate a specific device (sets viewport, device scale, and user agent).

```bash
zchrome set device <name>
```

**Available devices:**
- **Mobile:** `iPhone 14`, `iPhone 14 Pro`, `iPhone 15`, `Pixel 7`, `Pixel 8`
- **Tablet:** `iPad`, `iPad Pro`
- **Desktop:** `Desktop` (1920x1080), `Desktop HD` (1366x768), `Desktop 4K` (3840x2160)

**Example:**

```bash
zchrome set device "iPhone 14"
zchrome set device "Pixel 8"
zchrome set device "iPad Pro"
```

### set useragent

Override the browser's user agent string. Can use a preset name or a custom string.

```bash
zchrome set useragent <name|custom-string>
zchrome set ua <name|custom-string>  # alias
```

**Built-in user agents:**
- **Desktop:** `chrome`, `chrome-mac`, `chrome-linux`, `edge`, `firefox`, `firefox-mac`, `safari`, `brave`, `opera`, `vivaldi`
- **Mobile:** `chrome-android`, `chrome-ios`, `safari-ios`, `firefox-android`, `samsung`
- **Bots:** `googlebot`, `bingbot`
- **Other:** `curl`

**Example:**

```bash
# Use a preset
zchrome set ua firefox
zchrome set ua googlebot
zchrome set ua safari-ios

# Use a custom string
zchrome set ua "Mozilla/5.0 (Custom Browser) AppleWebKit/537.36"
```

### set geo

Override the browser's geolocation.

```bash
zchrome set geo <latitude> <longitude>
```

**Example:**

```bash
zchrome set geo 40.7128 -74.0060   # New York
zchrome set geo 51.5074 -0.1278    # London
zchrome set geo 35.6762 139.6503   # Tokyo
```

### set offline

Toggle offline mode to simulate network disconnection.

```bash
zchrome set offline <on|off>
```

**Example:**

```bash
zchrome set offline on    # Simulate offline
zchrome set offline off   # Back online
```

### set headers

Set extra HTTP headers to be sent with every request.

```bash
zchrome set headers <json>
```

**Example:**

```bash
zchrome set headers '{"X-Custom-Header": "value", "Authorization": "Bearer token123"}'
```

**Note:** Headers are saved to config and applied on subsequent navigations.

### set credentials

Set HTTP basic authentication credentials.

```bash
zchrome set credentials <username> <password>
```

**Example:**

```bash
zchrome set credentials admin secretpass
```

**Note:** Credentials are saved to config and applied on subsequent navigations.

### set media

Set the preferred color scheme (for `prefers-color-scheme` CSS media query).

```bash
zchrome set media <dark|light>
```

**Example:**

```bash
zchrome set media dark    # Enable dark mode
zchrome set media light   # Enable light mode
```

## Navigation Commands

### back

Navigate to the previous page in history.

```bash
zchrome back
```

### forward

Navigate to the next page in history.

```bash
zchrome forward
```

### reload

Reload the current page.

```bash
zchrome reload
```

### interactive

Start an interactive REPL session. This provides a command prompt where you can run any zchrome command without the `zchrome` prefix.

```bash
zchrome interactive
```

**Example session:**

```
zchrome> navigate https://example.com
URL: https://example.com
Title: Example Domain

zchrome> snapshot -i
- link "More information..." [ref=e1]
--- 1 element(s) with refs ---

zchrome> click @e1
Clicked: @e1

zchrome> get title
IANA-managed Reserved Domains

zchrome> tab
  1: Example Domain                 https://example.com
* 2: IANA — IANA-managed...         https://www.iana.org/...
Total: 2 tab(s). * = current

zchrome> exit
```

**Interactive commands:**

All CLI commands work in interactive mode without the `zchrome` prefix. Additional commands:
- `help` - Show available commands
- `exit` or `quit` - Exit interactive mode
- `version` - Show browser version
- `pages` - List all open pages
- `tab` - Manage tabs
- `use <target-id>` - Switch to a different page

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

### Browser Automation Workflow

A typical workflow using snapshots and element actions:

```bash
# 1. Launch Chrome and navigate to a page
zchrome open
zchrome connect
zchrome navigate https://example.com/login

# 2. Take a snapshot to see available elements
zchrome snapshot -i

# Output shows:
# - textbox "Email" [ref=e1]
# - textbox "Password" [ref=e2]
# - button "Login" [ref=e3]

# 3. Fill out the form using refs
zchrome fill @e1 "user@example.com"
zchrome fill @e2 "secretpassword"
zchrome click @e3

# 4. Wait and take a new snapshot
zchrome snapshot -i

# 5. Continue automation...
zchrome click @e5
```

### Form Filling Example

```bash
# Navigate to form page
zchrome navigate https://example.com/signup

# Take snapshot to see form fields
zchrome snapshot -i

# Fill form fields (using CSS selectors)
zchrome fill "#firstName" "John"
zchrome fill "#lastName" "Doe"
zchrome fill "#email" "john@example.com"
zchrome select "#country" "US"
zchrome check "#terms"
zchrome click "#submit"
```

### Keyboard Navigation Example

```bash
# Navigate form with keyboard
zchrome focus "#first-field"
zchrome fill @e1 "John"
zchrome press Tab           # Move to next field
zchrome fill @e2 "Doe"
zchrome press Tab
zchrome press Space         # Check checkbox
zchrome press Tab
zchrome press Enter         # Submit form

# Use keyboard shortcuts
zchrome press Control+a     # Select all
zchrome press Control+c     # Copy
zchrome press Control+v     # Paste
zchrome press Escape        # Close modal/cancel
```

### Using Snapshot Refs

```bash
# Snapshot creates refs like @e1, @e2, etc.
zchrome snapshot

# Refs are stored in zsnap.json with element info:
# {
#   "refs": {
#     "e1": { "role": "link", "name": "Home", "selector": "..." },
#     "e2": { "role": "button", "name": "Submit", "selector": "..." }
#   }
# }

# Use refs in subsequent commands
zchrome click @e1
zchrome hover @e2
zchrome scrollinto @e15
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
