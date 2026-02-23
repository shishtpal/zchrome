# Macro Recording and Playback

Record browser interactions as reusable, editable macros. Macros capture semantic commands (click, fill, press) rather than raw mouse/keyboard events, making them human-readable and robust.

## Quick Start

```bash
# Navigate to starting page
zchrome navigate https://example.com/login

# Start recording
zchrome cursor record login-flow.json
# Recording on port 4040... Press Enter to stop.
#   (browser connected)

# Interact with the page:
# - Click buttons, fill forms, press keys
# - Even reload pages - recording survives!

# Press Enter to stop
# Recorded 5 commands to login-flow.json

# Replay the recording
zchrome cursor replay login-flow.json --interval=500
```

## Recording Commands

### cursor record

Record browser interactions to a JSON macro file.

```bash
zchrome cursor record <filename.json>
```

**How it works:**

1. Starts a WebSocket server on port 4040
2. Injects JavaScript into the page via CDP
3. Events stream in real-time as you interact
4. Script auto-injects on page navigation (survives reloads)
5. Press Enter to stop recording and save

**Example:**

```bash
zchrome cursor record checkout-flow.json
# Recording on port 4040... Press Enter to stop.
# (Events stream in real-time, survives page reloads)
#   (browser connected)
# [interact with the page...]
# Recorded 12 commands to checkout-flow.json
```

## Macro File Format (Version 2)

Macros are stored as JSON with semantic commands:

```json
{
  "version": 2,
  "commands": [
    {"action": "click", "selector": "#login-btn"},
    {"action": "fill", "selector": "#email", "value": "user@example.com"},
    {"action": "fill", "selector": "#password", "value": "secret123"},
    {"action": "press", "key": "Enter"},
    {"action": "wait", "selector": ".dashboard"},
    {"action": "click", "selector": ".settings-link"}
  ]
}
```

### Supported Actions

| Action | Fields | Description |
|--------|--------|-------------|
| `click` | `selector` | Click an element |
| `dblclick` | `selector` | Double-click an element |
| `fill` | `selector`, `value` | Clear and fill input with text |
| `check` | `selector` | Check a checkbox |
| `uncheck` | `selector` | Uncheck a checkbox |
| `select` | `selector`, `value` | Select dropdown option by value |
| `press` | `key` | Press a key (e.g., "Enter", "Tab", "Control+a") |
| `scroll` | `scrollY` | Scroll the page (positive=down, negative=up) |
| `hover` | `selector` | Hover over an element |
| `navigate` | `value` | Navigate to URL |
| `wait` | `selector` or `value` | Wait for element, time (ms), or text |

### Selector Generation

The recorder generates CSS selectors in this priority order:

1. `#id` - Element ID
2. `[name="..."]` - Name attribute (for form inputs)
3. `[aria-label="..."]` - Accessibility label
4. `[placeholder="..."]` - Placeholder text
5. `.unique-class` - Unique CSS class
6. `[data-testid="..."]` - Test ID
7. `parent > tag:nth-of-type(n)` - Fallback

## Replaying Macros

### cursor replay

Replay commands from a macro file.

```bash
zchrome cursor replay <filename.json> [--interval=<ms>|<min-max>]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--interval=100` | Fixed 100ms delay between commands |
| `--interval=100-300` | Random delay between 100-300ms (more human-like) |

**Examples:**

```bash
# Default 100ms between commands
zchrome cursor replay login-flow.json

# Slower, fixed 500ms delay
zchrome cursor replay login-flow.json --interval=500

# Human-like random delay
zchrome cursor replay login-flow.json --interval=200-500

# Very slow for debugging
zchrome cursor replay login-flow.json --interval=1000-2000
```

**Output:**

```
Replaying 5 commands from login-flow.json (interval: 200-500ms)...
  [1/5] click "#login-btn"
  [2/5] fill "#email" "user@example.com"
  [3/5] fill "#password" "secret123"
  [4/5] press Enter
  [5/5] wait ".dashboard"
Replay complete.
```

## Editing Macros

One of the key benefits of semantic macros is that they're **human-readable and editable**. You can:

### Add Wait Commands

Insert waits to make replay more reliable:

```json
{"action": "click", "selector": "#submit"},
{"action": "wait", "selector": ".success-message"},
{"action": "click", "selector": "#continue"}
```

### Wait Types

```json
// Wait for element to be visible
{"action": "wait", "selector": "#loading-complete"}

// Wait for specific time (milliseconds)
{"action": "wait", "value": "2000"}

// Wait for text to appear
{"action": "wait", "value": "Welcome back"}
```

### Modify Values

Change form values without re-recording:

```json
// Before
{"action": "fill", "selector": "#email", "value": "old@example.com"}

// After
{"action": "fill", "selector": "#email", "value": "new@example.com"}
```

### Add Navigation

Insert page navigations:

```json
{"action": "navigate", "value": "https://example.com/settings"}
```

### Change Selectors

Update selectors if page structure changed:

```json
// Before (ID was removed)
{"action": "click", "selector": "#old-button-id"}

// After (use class instead)
{"action": "click", "selector": ".submit-button"}
```

## Use Cases

### Login Automation

```bash
# Record login once
zchrome navigate https://app.example.com/login
zchrome cursor record login.json
# [enter credentials, click login, wait for dashboard]

# Replay anytime
zchrome navigate https://app.example.com/login
zchrome cursor replay login.json --interval=300
```

### Form Testing

```bash
# Record form submission
zchrome cursor record signup-form.json

# Edit the JSON to test different values
# Then replay with variations
zchrome cursor replay signup-form.json
```

### E2E Test Scripts

```bash
# Record a user flow
zchrome cursor record checkout-flow.json

# Add wait commands for reliability
# Edit JSON: add {"action": "wait", "selector": ".cart-loaded"}

# Replay as part of test suite
zchrome cursor replay checkout-flow.json --interval=100-200
```

### Demo Recordings

```bash
# Record a product demo
zchrome cursor record demo.json

# Replay with slow timing for presentation
zchrome cursor replay demo.json --interval=1000-1500
```

## Tips

### Reliable Recordings

1. **Add waits** after actions that trigger async operations
2. **Use specific selectors** - IDs and data-testid are most reliable
3. **Test on clean state** - replay from the same starting page

### Debugging Failed Replays

```bash
# Use slow interval to watch what happens
zchrome cursor replay macro.json --interval=2000

# Take screenshots during replay to debug
# (manually or add to macro)
```

### Selector Best Practices

- Prefer `#id` or `[data-testid="..."]` for stability
- Avoid nth-of-type selectors when possible (brittle)
- Test selectors in browser DevTools first

## Legacy Format (Version 1)

Version 1 macros contain raw events (mouseMove, keyDown, etc.) and are still supported for backward compatibility. They replay with original timing.

```json
{
  "version": 1,
  "events": [
    {"type": "mouseMove", "timestamp": 0, "x": 100, "y": 200},
    {"type": "mouseDown", "timestamp": 50, "x": 100, "y": 200, "button": "left"},
    {"type": "mouseUp", "timestamp": 100, "x": 100, "y": 200, "button": "left"}
  ]
}
```

To convert to version 2, re-record the interaction - semantic commands are more maintainable.
