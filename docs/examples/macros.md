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
| `multiselect` | `selector`, `selectors`?, `value` | Select multiple options (value is JSON array string) |
| `press` | `key` | Press a key (e.g., "Enter", "Tab", "Control+a") |
| `scroll` | `scrollX`?, `scrollY` | Scroll the page (positive=down, negative=up) |
| `hover` | `selector`, `selectors`? | Hover over an element |
| `navigate` | `value` | Navigate to URL |
| `wait` | `selector` or `value` | Wait for element, time (ms), or text |
| `upload` | `selector`, `selectors`?, `files` | Upload files to a file input element |
| `dialog` | `accept`, `value`? | Handle JavaScript dialog (see below) |
| `assert` | See below | Test conditions with retry on failure |
| `extract` | `selector`, `mode`?, `output` | Extract DOM data as JSON |
| `capture` | `selector`, capture fields | Capture values into variables for comparison |
| `goto` | `file` | Chain to another macro JSON file |

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

**Multiselect has selected values:**
```json
{"action": "assert", "selector": "#multi_select", "value": "[\"option1\", \"option3\"]"}
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
{"action": "assert", "text": "Order #* has been placed"}
```

Use `*` as a wildcard to match any characters. This is useful for asserting text that contains dynamic values like IDs, timestamps, or usernames.

**Element count assertions:**
```json
{"action": "assert", "selector": "table#results tbody tr", "count": 5}
{"action": "assert", "selector": ".item", "count_min": 1}
{"action": "assert", "selector": ".item", "count_max": 10}
```

Use `count` for exact count, `count_min` for minimum, `count_max` for maximum. These can be combined.

**With custom timeout:**
```json
{"action": "assert", "selector": ".slow-element", "timeout": 10000}
```

**With per-assertion fallback:**
```json
{"action": "assert", "text": "Email available", "fallback": "email-taken.json"}
```

### Retry Behavior

![Assertion Retry Flow](/replay-flow-with-assertions.png)

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

### Snapshot Assertions

Compare DOM structure against a saved baseline file:

```json
{"action": "assert", "selector": "#user-profile", "snapshot": "expected-profile.json"}
```

This extracts the current DOM structure of the element and compares it to the JSON in the snapshot file. Useful for regression testing to catch unexpected DOM changes.

**Creating a snapshot baseline:**

1. Use the `extract` action to save the expected state:
   ```json
   {"action": "extract", "selector": "#user-profile", "output": "expected-profile.json"}
   ```

2. Then use `snapshot` assertions in subsequent runs:
   ```json
   {"action": "assert", "selector": "#user-profile", "snapshot": "expected-profile.json"}
   ```

### Capture Action (Variables)

The `capture` action stores values into variables for later comparison. This enables "before/after" assertions.

**Capture Modes:**

| Field | Captures | Description |
|-------|----------|-------------|
| `count_as` | Integer | Number of elements matching selector |
| `text_as` | String | Text content of element |
| `value_as` | String | Value of input/select element |
| `attr_as` | String | Attribute value (requires `attribute` field) |

**Example: Verify row count increased after form submission:**
```json
{
  "version": 2,
  "commands": [
    {"action": "capture", "selector": "table#results tbody tr", "count_as": "before"},
    {"action": "fill", "selector": "#name", "value": "John Doe"},
    {"action": "fill", "selector": "#email", "value": "john@example.com"},
    {"action": "click", "selector": "#submit"},
    {"action": "wait", "value": "1000"},
    {"action": "assert", "selector": "table#results tbody tr", "count_gt": "$before"}
  ]
}
```

**Variable-Based Comparison Operators:**

| Field | Type | Description |
|-------|------|-------------|
| `count_gt` | `"5"` or `"$var"` | Count greater than value or variable |
| `count_lt` | `"5"` or `"$var"` | Count less than |
| `count_gte` | `"5"` or `"$var"` | Count greater than or equal |
| `count_lte` | `"5"` or `"$var"` | Count less than or equal |
| `text_eq` | `"text"` or `"$var"` | Text equals value or variable |
| `text_neq` | `"text"` or `"$var"` | Text not equals |
| `text_contains` | `"text"` or `"$var"` | Text contains substring |
| `value_eq` | `"val"` or `"$var"` | Input value equals |
| `value_neq` | `"val"` or `"$var"` | Input value not equals |

**Example: Verify text changed:**
```json
{"action": "capture", "selector": "#status", "text_as": "old_status"}
{"action": "click", "selector": "#refresh"}
{"action": "assert", "selector": "#status", "text_neq": "$old_status"}
```

**Example: Capture attribute:**
```json
{"action": "capture", "selector": "#row-1", "attribute": "data-id", "attr_as": "row_id"}
{"action": "click", "selector": "#delete"}
{"action": "assert", "text": "Deleted row $row_id"}
```

Variables persist across `--resume`, allowing assertions to work correctly after retry.

## Data Extraction

The `extract` action extracts DOM data as JSON during macro playback. Useful for scraping data after navigation/login.

### Extract Action Format

```json
{
  "action": "extract",
  "selector": "#element",        // CSS selector for target element
  "mode": "table",               // Extraction mode (default: "dom")
  "output": "data.json",         // Output file path
  "extract_all": true            // Optional: extract all matching elements
}
```

### Extraction Modes

| Mode | Description | Output |
|------|-------------|--------|
| `dom` | Full DOM tree structure (default) | `{"tag": "div", "attrs": {...}, "children": [...]}` |
| `text` | Text content only | `"Hello world"` or `["Item 1", "Item 2"]` |
| `html` | Raw innerHTML | `"<span>content</span>"` |
| `attrs` | Attributes only | `{"id": "main", "class": "container"}` |
| `table` | HTML table to objects | `[{"Name": "Alice", "Age": "30"}, ...]` |
| `form` | Form field values | `{"email": "a@b.com", "name": "John"}` |

### Extract Examples

**Scrape table data:**
```json
{
  "action": "extract",
  "selector": "table#results",
  "mode": "table",
  "output": "scraped-data.json"
}
```

**Get form values:**
```json
{
  "action": "extract",
  "selector": "form#checkout",
  "mode": "form",
  "output": "form-state.json"
}
```

**Extract multiple elements:**
```json
{
  "action": "extract",
  "selector": ".product-card",
  "mode": "dom",
  "extract_all": true,
  "output": "products.json"
}
```

### Full Workflow Example

Navigate to a page, login, and extract data:

```json
{
  "version": 2,
  "commands": [
    {"action": "navigate", "value": "https://example.com/login"},
    {"action": "fill", "selector": "#email", "value": "user@example.com"},
    {"action": "fill", "selector": "#password", "value": "secret123"},
    {"action": "click", "selector": "#login-btn"},
    {"action": "assert", "url": "**/dashboard", "timeout": 10000},
    {"action": "navigate", "value": "https://example.com/data"},
    {"action": "wait", "selector": "table#results"},
    {"action": "extract", "selector": "table#results", "mode": "table", "output": "results.json"}
  ]
}
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

### File Upload

Upload files to `<input type="file">` elements during macro replay:

```json
{
  "version": 2,
  "commands": [
    {"action": "click", "selector": "#upload-btn"},
    {"action": "upload", "selector": "#file-input", "files": ["document.pdf"]},
    {"action": "click", "selector": "#submit"}
  ]
}
```

**Upload Action Format:**

```json
{
  "action": "upload",
  "selector": "#file-input",           // CSS selector for file input
  "selectors": ["input[type=file]"],   // Optional: fallback selectors
  "files": ["file1.pdf", "file2.txt"]  // Array of file paths
}
```

**Features:**
- Supports multiple files in a single upload
- Accepts both relative and absolute file paths (relative paths are resolved from current working directory)
- Works with fallback selectors for dynamic pages
- Uses the same underlying mechanism as the CLI `upload` command

**Examples:**

```json
// Single file upload
{"action": "upload", "selector": "#photo", "files": ["profile.jpg"]}

// Multiple files
{"action": "upload", "selector": "#attachments", "files": ["doc1.pdf", "doc2.pdf", "image.png"]}

// With fallback selectors
{
  "action": "upload",
  "selector": "#file-upload",
  "selectors": ["input[name='file']", "input[type='file']"],
  "files": ["report.xlsx"]
}

// Absolute path
{"action": "upload", "selector": "#import", "files": ["C:\\Users\\name\\data.csv"]}
```

**Note:** The upload action only selects the files on the input element. Use a subsequent `click` action on the submit button if you need to submit the form.

### Dialog Handling

Handle JavaScript dialogs (alert, confirm, prompt) during macro replay. Place the `dialog` action **after** the action that triggers the dialog:

```json
{
  "version": 2,
  "commands": [
    {"action": "click", "selector": "#show-alert"},
    {"action": "dialog", "accept": true},
    {"action": "click", "selector": "#show-confirm"},
    {"action": "dialog", "accept": false},
    {"action": "click", "selector": "#show-prompt"},
    {"action": "dialog", "accept": true, "value": "my input"}
  ]
}
```

**Dialog Action Format:**

```json
{
  "action": "dialog",
  "accept": true,           // true = accept, false = dismiss
  "value": "prompt text",   // Optional: text for prompt dialogs
  "text": "Expected message"  // Optional: verify dialog message
}
```

**Asserting Dialog Messages:**

You can verify the dialog message matches an expected value:

```json
{"action": "dialog", "accept": true, "text": "Are you sure you want to delete?"}
```

**Pattern Matching for Dynamic Dialog Messages:**

Use `*` as a wildcard to match dynamic content in dialog messages:

```json
{"action": "dialog", "accept": true, "text": "Data saved. Record ID: *"}
{"action": "dialog", "accept": true, "text": "Order #* confirmed"}
{"action": "dialog", "accept": true, "text": "Welcome, *!"}
```

This is useful when the dialog contains dynamic values like record IDs, timestamps, or usernames that change between runs.

**How It Works:**

The macro replay system buffers CDP events, so when a click triggers a dialog:

1. The click action executes
2. Chrome fires `Page.javascriptDialogOpening` event (buffered)
3. The dialog action retrieves the buffered event
4. Dialog is handled immediately

::: tip
Unlike the CLI `dialog` command, macro replay doesn't need to wait for dialogs because events are buffered during replay.
:::

### Macro Chaining (goto)

Split complex flows across multiple macro files and chain them together using the `goto` action. When replay encounters a `goto`, it loads and replays the target file before continuing.

**Goto Action Format:**

```json
{
  "action": "goto",
  "file": "next-step.json"    // Path to the next macro file
}
```

**Example: Multi-step form flow**

Break a long registration flow into separate files:

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

`step2-profile.json`:
```json
{
  "version": 2,
  "commands": [
    {"action": "fill", "selector": "#firstName", "value": "John"},
    {"action": "fill", "selector": "#lastName", "value": "Doe"},
    {"action": "click", "selector": "#submit"},
    {"action": "assert", "text": "Registration complete"}
  ]
}
```

```bash
# Replay the entire flow starting from step 1
zchrome cursor replay step1-account.json
```

**Benefits:**
- **Reusable steps** — share common flows (e.g., login) across test suites
- **Easier maintenance** — edit one step without touching others
- **Composable** — mix and match steps for different scenarios

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
