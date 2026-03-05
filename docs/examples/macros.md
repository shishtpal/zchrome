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

### Fallback Selectors

For dynamic pages where elements may have different selectors, use the `selectors` array to specify fallbacks:

```json
{
  "version": 2,
  "commands": [
    {
      "action": "click",
      "selector": "#submit-btn",
      "selectors": ["[data-testid='submit']", ".btn-primary", "button[type='submit']"]
    },
    {
      "action": "fill",
      "selector": "#email",
      "selectors": ["[name='email']", "[type='email']", ".email-input"],
      "value": "user@example.com"
    }
  ]
}
```

During replay, zchrome tries selectors in order:
1. `selector` (primary) - tried first
2. `selectors[0]`, `selectors[1]`, ... - fallbacks tried in order

This makes macros more robust across different page states or minor UI changes.

### Supported Actions

| Action | Fields | Description |
|--------|--------|-------------|
| `click` | `selector`, `selectors`? | Click an element |
| `dblclick` | `selector`, `selectors`? | Double-click an element |
| `fill` | `selector`, `selectors`?, `value` | Clear and fill input with text |
| `check` | `selector`, `selectors`? | Check a checkbox |
| `uncheck` | `selector`, `selectors`? | Uncheck a checkbox |
| `select` | `selector`, `selectors`?, `value` | Select dropdown option by value |
| `press` | `key` | Press a key (e.g., "Enter", "Tab", "Control+a") |
| `scroll` | `scrollX`?, `scrollY` | Scroll the page (positive=down, negative=up) |
| `hover` | `selector`, `selectors`? | Hover over an element |
| `navigate` | `value` | Navigate to URL |
| `wait` | `selector` or `value` | Wait for element, time (ms), or text |
| `assert` | See below | Test conditions with retry on failure |

**Note:** `selectors` is an optional array of fallback CSS selectors tried if `selector` fails.

### Selector Generation

The recorder generates multiple CSS selectors for robustness. It stores the best selector as `selector` and additional options in `selectors`:

**Primary selector** (most specific, tried first):
1. `#id` - Element ID (most reliable)
2. `[data-testid="..."]` - Test ID attribute

**Fallback selectors** (tried if primary fails):
3. `[name="..."]` - Name attribute (for form inputs)
4. `[aria-label="..."]` - Accessibility label
5. `[placeholder="..."]` - Placeholder text
6. `.unique-class` - Unique CSS class
7. `parent > tag:nth-of-type(n)` - Structural fallback

**Example recorded command:**
```json
{
  "action": "click",
  "selector": "#submit-btn",
  "selectors": ["[data-testid='submit']", "[name='submit']", ".btn-submit"]
}
```

## Replaying Macros

### cursor replay

Replay commands from a macro file with support for assertions and automatic retry on failure.

```bash
zchrome cursor replay <filename.json> [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--interval=<ms>` | Fixed delay between commands (default: 100ms) |
| `--interval=<min-max>` | Random delay range (e.g., 100-300ms) |
| `--retries <n>` | Number of retries on assertion failure (default: 3) |
| `--retry-delay <ms>` | Wait time before retrying (default: 100ms) |
| `--fallback <file.json>` | JSON file to execute on permanent failure |
| `--resume` | Resume from last successful action |
| `--from <n>` | Start replay from command index n |

**Examples:**

```bash
# Default 100ms between commands
zchrome cursor replay login-flow.json

# Slower, fixed 500ms delay
zchrome cursor replay login-flow.json --interval=500

# Human-like random delay
zchrome cursor replay login-flow.json --interval=200-500

# With custom retry settings
zchrome cursor replay form.json --retries 5 --retry-delay 2000

# With fallback on failure
zchrome cursor replay form.json --fallback error-handler.json

# Resume from last successful action
zchrome cursor replay form.json --resume
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

## Assertions (Testing)

The `assert` action allows you to verify application state during replay. When an assertion fails, zchrome automatically retries from the last "action" command (click, fill, select, etc.) up to `--retries` times.

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

**With custom timeout:**
```json
{"action": "assert", "selector": ".slow-element", "timeout": 10000}
```

**With per-assertion fallback:**
```json
{"action": "assert", "text": "Email available", "fallback": "email-taken.json"}
```

### Retry Behavior

When an assertion fails:

1. zchrome waits `--retry-delay` ms (default: 1000)
2. Finds the **last action command** (click, fill, select, check, etc.)
3. Re-executes from that point (skipping press, wait, scroll)
4. Repeats up to `--retries` times

This ensures form interactions are re-done meaningfully, not just keypresses.

### Fallback Priority

When an assertion permanently fails:

1. **Assert-level fallback**: Uses `fallback` field on the assert command
2. **CLI fallback**: Uses `--fallback` argument
3. **Default**: Stops replay and saves state for `--resume`

### Example: Form with Assertions

```json
{
  "version": 2,
  "commands": [
    {"action": "fill", "selector": "#email", "value": "test@example.com"},
    {"action": "assert", "selector": "#email", "value": "test@example.com"},
    {"action": "fill", "selector": "#password", "value": "secret123"},
    {"action": "click", "selector": "#submit"},
    {"action": "assert", "url": "**/dashboard", "timeout": 10000},
    {"action": "assert", "text": "Welcome back"}
  ]
}
```

**Output with passing assertions:**
```
Replaying 6 commands from form.json (retries: 3, delay: 1000ms)...
  [1/6] fill "#email" "test@example.com"
  [2/6] assert "#email" ✓
  [3/6] fill "#password" "***"
  [4/6] click "#submit"
  [5/6] assert URL "**/dashboard" ✓
  [6/6] assert text "Welcome" ✓
Replay complete. All assertions passed.
```

**Output with retry:**
```
  [4/6] click "#submit"
  [5/6] assert URL "**/dashboard"
    ✗ Assertion failed (timeout 5000ms)
    Waiting 1000ms before retry...
    Retry 1/3: Re-executing from last action [4] click "#submit"
  [4/6] click "#submit"
  [5/6] assert URL "**/dashboard" ✓
Replay complete. 1 retry needed.
```

### Multi-Branch Flows

Use per-assertion fallbacks for conditional flows:

```json
{
  "version": 2,
  "commands": [
    {"action": "fill", "selector": "#email", "value": "test@example.com"},
    {"action": "click", "selector": "#check-email"},
    {"action": "assert", "text": "Email available", "fallback": "email-taken.json"},
    {"action": "fill", "selector": "#password", "value": "secret123"},
    {"action": "click", "selector": "#submit"},
    {"action": "assert", "text": "Account created", "fallback": "captcha-required.json"}
  ]
}
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

// Or add fallbacks for robustness
{
  "action": "click",
  "selector": ".submit-button",
  "selectors": ["[type='submit']", "form button:last-child"]
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
- Use fallback `selectors` array for dynamic pages where elements may change
- The recorder automatically generates fallbacks - review and edit if needed

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
