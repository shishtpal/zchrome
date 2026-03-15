# Cursor Commands

The `zchrome cursor` command provides tools for inspecting page elements, recording browser interactions, and replaying macros with video recording support.

## Overview

```bash
zchrome cursor <subcommand> [options]
```

| Subcommand | Description |
|------------|-------------|
| `active` | Show the currently focused element |
| `hover` | Show element under mouse cursor |
| `record` | Record interactions to a macro file |
| `replay` | Replay a macro with optional video recording |

## cursor active

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

## cursor hover

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

## cursor record

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
# Recorded 12 commands to macro.json
```

**Note:** The recording survives page reloads because the JavaScript is injected via `Page.addScriptToEvaluateOnNewDocument`, which automatically runs on every new page load.

### Output Format (v2)

The macro file contains semantic commands:

```json
{
  "version": 2,
  "commands": [
    {"action": "click", "selector": "#login-btn"},
    {"action": "fill", "selector": "#email", "value": "user@example.com"},
    {"action": "fill", "selector": "#password", "value": "secret"},
    {"action": "press", "key": "Enter"},
    {"action": "wait", "value": 2000},
    {"action": "click", "selector": ".dashboard"}
  ]
}
```

### Supported Actions

| Action | Fields | Description |
|--------|--------|-------------|
| `click` | `selector`, `selectors`? | Click an element |
| `dblclick` | `selector`, `selectors`? | Double-click an element |
| `fill` | `selector`, `selectors`?, `value` | Clear and fill input with text |
| `check` | `selector`, `selectors`? | Check a checkbox |
| `uncheck` | `selector`, `selectors`? | Uncheck a checkbox |
| `select` | `selector`, `selectors`?, `value` | Select dropdown option by value |
| `multiselect` | `selector`, `selectors`?, `value` | Select multiple options |
| `press` | `key` | Press a key (e.g., "Enter", "Tab", "Control+a") |
| `scroll` | `scrollX`?, `scrollY` | Scroll the page |
| `hover` | `selector`, `selectors`? | Hover over an element |
| `navigate` | `value` | Navigate to URL |
| `wait` | `selector` or `value` | Wait for element, time (ms), or text |
| `upload` | `selector`, `selectors`?, `files` | Upload files to a file input |
| `dialog` | `accept`, `value`? | Handle JavaScript dialog |
| `assert` | See below | Test conditions with retry on failure |
| `extract` | `selector`, `mode`?, `output` | Extract DOM data as JSON |
| `capture` | `selector`, capture fields | Capture values into variables |
| `goto` | `file` | Chain to another macro JSON file |

## Wait Action

The `wait` action pauses macro execution until a condition is met. It supports multiple wait types for different scenarios.

### Wait for Element

Wait for an element to be visible on the page:

```json
{"action": "wait", "selector": "#login-form"}
```

The element must be visible (not hidden via CSS `visibility: hidden` or `display: none`).

### Wait for Time

Wait for a fixed duration in milliseconds:

```json
{"action": "wait", "value": 2000}
```

This pauses execution for 2 seconds (2000ms).

### Wait for Text

Wait for specific text to appear anywhere on the page:

```json
{"action": "wait", "text": "Welcome"}
```

### Wait for URL Pattern

Wait for the page URL to match a glob pattern:

```json
{"action": "wait", "url": "**/dashboard"}
```

**Glob Patterns:**
- `**` matches any characters (including `/`)
- `*` matches any characters except `/`
- `?` matches a single character

**Examples:**
```json
{"action": "wait", "url": "**/login"}           // Any path ending with /login
{"action": "wait", "url": "https://example.com/**"}  // Any URL on example.com
{"action": "wait", "url": "**/users/*/profile"} // Dynamic user profiles
```

### Wait for Load State

Wait for the page to reach a specific load state:

```json
{"action": "wait", "load": "networkidle"}
```

**Load States:**

| State | Description |
|-------|-------------|
| `load` | Page has finished loading (window.onload fired) |
| `domcontentloaded` | DOM is ready (DOMContentLoaded event fired) |
| `networkidle` | Page loaded and no network requests for 500ms |

### Wait for JavaScript Condition

Wait for a JavaScript expression to return truthy:

```json
{"action": "wait", "fn": "window.myApp.ready"}
```

**Examples:**
```json
{"action": "wait", "fn": "document.querySelector('#spinner').style.display === 'none'"}
{"action": "wait", "fn": "window.dataLoaded === true"}
{"action": "wait", "fn": "document.querySelectorAll('.item').length > 0"}
```

### Wait for Media

Wait for audio/video media elements to reach specific states. The selector is optional—omit it to wait for any media element on the page.

**Wait for media to start playing:**
```json
{"action": "wait", "media_playing": "#video-player"}
{"action": "wait", "media_playing": ""}  // Any media
```

**Wait for media to end:**
```json
{"action": "wait", "media_ended": "#video-player"}
{"action": "wait", "media_ended": ""}  // Any media
```

**Wait for media to be ready (have enough data):**
```json
{"action": "wait", "media_ready": "#video-player"}
{"action": "wait", "media_ready": ""}  // Any media
```

**Wait for media error:**
```json
{"action": "wait", "media_error": "#video-player"}
{"action": "wait", "media_error": ""}  // Any media
```

### Timeout

All wait actions have a default timeout of 30 seconds. If the condition is not met within the timeout, the macro fails with a `Timeout` error.

### Examples

**Login flow with waits:**
```json
{
  "version": 2,
  "commands": [
    {"action": "fill", "selector": "#email", "value": "user@example.com"},
    {"action": "fill", "selector": "#password", "value": "secret"},
    {"action": "click", "selector": "#login-btn"},
    {"action": "wait", "url": "**/dashboard"},
    {"action": "wait", "selector": "#welcome-message"},
    {"action": "wait", "text": "Welcome back"}
  ]
}
```

**Wait for dynamic content:**
```json
{
  "version": 2,
  "commands": [
    {"action": "click", "selector": "#load-more"},
    {"action": "wait", "fn": "document.querySelectorAll('.item').length >= 10"},
    {"action": "assert", "selector": ".item", "count_min": 10}
  ]
}
```

**Wait for media playback:**
```json
{
  "version": 2,
  "commands": [
    {"action": "click", "selector": "#play-btn"},
    {"action": "wait", "media_playing": "#video-player"},
    {"action": "wait", "value": 5000},
    {"action": "wait", "media_ended": "#video-player"}
  ]
}
```

## cursor replay

Replay commands from a macro file with support for assertions, automatic retry on failure, and video recording.

```bash
zchrome cursor replay <filename.json> [options]
```

### Replay Options

| Option | Description |
|--------|-------------|
| `--interval=<ms>` | Fixed delay between commands (default: 100ms) |
| `--interval=<min-max>` | Random delay range (e.g., 200-500ms) |
| `--retries <n>` | Number of retries on assertion failure (default: 3) |
| `--retry-delay <ms>` | Wait time before retrying (default: 1000ms) |
| `--fallback <file.json>` | JSON file to execute on permanent failure |
| `--resume` | Resume from last successful action |
| `--from <n>` | Start replay from command index n |

### Video Recording & Streaming Options

| Option | Description |
|--------|-------------|
| `--record=<path>` | Record replay to video file (mp4/webm/gif) |
| `--fps=<n>` | Frames per second for recording (default: 10) |
| `--quality=<0-100>` | Video quality (default: 80) |
| `--stream` | Enable live streaming via HTTP |
| `--port=<n>` | Stream server port (default: 8080) |
| `--interactive` | Allow viewers to interact with the page |

### Basic Examples

```bash
# Replay with default 100ms interval
zchrome cursor replay macro.json

# Fixed 500ms between commands
zchrome cursor replay macro.json --interval=500

# Random 200-500ms between commands (human-like timing)
zchrome cursor replay macro.json --interval=200-500

# With custom retry settings for assertions
zchrome cursor replay form.json --retries 5 --retry-delay 2000

# With fallback on permanent failure
zchrome cursor replay form.json --fallback error-handler.json

# Resume from last successful action
zchrome cursor replay form.json --resume
```

### Video Recording Examples

```bash
# Record replay to MP4 video
zchrome cursor replay demo.json --record=demo.mp4

# Record with custom settings
zchrome cursor replay demo.json --record=demo.webm --fps=15 --quality=90

# Record as GIF (for quick sharing)
zchrome cursor replay demo.json --record=demo.gif
```

**Supported Video Formats:**

| Format | Extension | Use Case |
|--------|-----------|----------|
| MP4 | `.mp4` | Best compatibility, recommended for sharing |
| WebM | `.webm` | Web-optimized, smaller files |
| GIF | `.gif` | Quick previews, embeddable anywhere |

**Requirements:** FFmpeg must be installed and in your PATH.

### Live Streaming Examples

```bash
# Start streaming on default port 8080
zchrome cursor replay demo.json --stream

# Stream on custom port
zchrome cursor replay demo.json --stream --port=9000

# Interactive mode (viewers can click/type)
zchrome cursor replay demo.json --stream --interactive

# Record and stream simultaneously
zchrome cursor replay demo.json --record=demo.mp4 --stream
```

Open `http://localhost:8080/` in any browser to watch the stream.

**Stream Features:**
- **MJPEG over HTTP** - Works in any browser via `<img>` tag
- **WebSocket support** - Lower latency for interactive mode
- **Multiple viewers** - Share the URL with team members

### Replay Output

```
Replaying 12 commands from macro.json (retries: 3, delay: 1000ms)...
  [1/12] click "#login-btn"
  [2/12] fill "#email" "user@example.com"
  [3/12] assert "#email" OK
  [4/12] press Enter
  [5/12] wait ".dashboard"
  [6/12] goto "checkout.json" -> checkout.json
Replay complete. All assertions passed.
```

## Assertions

The `assert` action verifies application state during replay. When an assertion fails, zchrome automatically retries from the last action command.

### Assert Action Format

```json
{
  "action": "assert",
  "selector": "#element",      // Element must exist and be visible
  "value": "expected",         // Optional: element text/value must match
  "attribute": "class",        // Optional: attribute to check
  "contains": "active",        // Optional: attribute must contain this
  "url": "**/dashboard",       // Optional: URL must match pattern
  "text": "Welcome",           // Optional: text must appear on page
  "timeout": 5000,             // Optional: wait up to N ms (default: 5000)
  "fallback": "error.json"     // Optional: run this macro if assertion fails
}
```

### Assertion Types

**Element exists:**
```json
{"action": "assert", "selector": "#success-message"}
```

**Element has value/text:**
```json
{"action": "assert", "selector": "#email", "value": "user@example.com"}
```

**Element has attribute:**
```json
{"action": "assert", "selector": "#btn", "attribute": "class", "contains": "active"}
```

**URL matches pattern:**
```json
{"action": "assert", "url": "**/dashboard"}
```

**Text visible on page:**
```json
{"action": "assert", "text": "Login successful"}
```

**Text with glob pattern (for dynamic content):**
```json
{"action": "assert", "text": "Record ID: *"}
{"action": "assert", "text": "Welcome, * to the dashboard"}
```

**Element count assertions:**
```json
{"action": "assert", "selector": "table#results tbody tr", "count": 5}
{"action": "assert", "selector": ".item", "count_min": 1}
{"action": "assert", "selector": ".item", "count_max": 10}
```

## Macro Chaining (goto)

Split complex flows across multiple macro files using the `goto` action:

```json
{"action": "goto", "file": "next-step.json"}
```

**Example: Multi-step form flow**

`step1-account.json`:
```json
{
  "version": 2,
  "commands": [
    {"action": "fill", "selector": "#email", "value": "user@example.com"},
    {"action": "fill", "selector": "#password", "value": "secret123"},
    {"action": "click", "selector": "#next"},
    {"action": "assert", "url": "**/profile"},
    {"action": "goto", "file": "step2-profile.json"}
  ]
}
```

When replaying with video recording, the recording continues seamlessly across chained macro files.

## Capture Action (Variables)

The `capture` action stores values into variables for later comparison:

```json
{"action": "capture", "selector": "table#results tbody tr", "count_as": "before"}
{"action": "fill", "selector": "#name", "value": "John Doe"}
{"action": "click", "selector": "#submit"}
{"action": "assert", "selector": "table#results tbody tr", "count_gt": "$before"}
```

**Capture Modes:**

| Field | Captures | Description |
|-------|----------|-------------|
| `count_as` | Integer | Number of elements matching selector |
| `text_as` | String | Text content of element |
| `value_as` | String | Value of input/select element |
| `attr_as` | String | Attribute value (requires `attribute` field) |

## Data Extraction

Extract DOM data during macro replay:

```json
{
  "action": "extract",
  "selector": "table#results",
  "mode": "table",
  "output": "scraped-data.json"
}
```

**Extraction Modes:**

| Mode | Description |
|------|-------------|
| `dom` | Full DOM tree structure (default) |
| `text` | Text content only |
| `html` | Raw innerHTML |
| `attrs` | Attributes only |
| `table` | HTML table to objects |
| `form` | Form field values |

## Dialog Handling

Handle JavaScript dialogs during replay:

```json
{"action": "click", "selector": "#show-alert"},
{"action": "dialog", "accept": true},
{"action": "click", "selector": "#show-confirm"},
{"action": "dialog", "accept": false},
{"action": "click", "selector": "#show-prompt"},
{"action": "dialog", "accept": true, "value": "my input"}
```

## File Upload

Upload files during macro replay:

```json
{
  "action": "upload",
  "selector": "#file-input",
  "files": ["document.pdf", "image.png"]
}
```

## Use Cases

### Login Automation

```bash
# Record login once
zchrome navigate https://app.example.com/login
zchrome cursor record login.json
# [enter credentials, click login, wait for dashboard]

# Replay anytime
zchrome cursor replay login.json --interval=300
```

### E2E Test with Video

```bash
# Record test flow with video for debugging
zchrome cursor replay checkout-flow.json --record=test-run.mp4 --fps=15
```

### Demo Recording

```bash
# Record a product demo video
zchrome cursor replay demo.json --record=demo.mp4 --interval=800 --fps=15
```

### Collaborative Testing

```bash
# Stream replay for team review
zchrome cursor replay form.json --stream --port=8080
# Team members watch at http://localhost:8080/
```

### Interactive Remote Session

```bash
# Allow remote viewers to interact
zchrome cursor replay demo.json --stream --interactive
```

## See Also

- [Macro Recording Guide](/examples/macros) - Full documentation on macro format and best practices
- [CLI Reference](/cli) - All CLI commands
- [Browser Interactions](/examples/interactions) - Element action commands
