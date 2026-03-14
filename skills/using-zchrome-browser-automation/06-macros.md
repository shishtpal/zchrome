# Macro Recording and Replay

Record and replay browser interactions with semantic commands.

## Recording

```bash
zchrome cursor record login-flow.json
# Recording on port 4040... Press Enter to stop.
# (interact with the page — survives reloads)
# Recorded 5 commands to login-flow.json
```

## Macro File Format (Version 2)

```json
{
  "version": 2,
  "commands": [
    {"action": "click", "selector": "#login-btn"},
    {"action": "fill", "selector": "#email", "value": "user@example.com"},
    {"action": "fill", "selector": "#password", "value": "secret123"},
    {"action": "press", "key": "Enter"},
    {"action": "assert", "url": "**/dashboard", "timeout": 10000},
    {"action": "assert", "text": "Welcome back"}
  ]
}
```

## Supported Macro Actions

| Action | Key Fields | Description |
|--------|-----------|-------------|
| `click` | `selector`, `selectors`? | Click element |
| `dblclick` | `selector`, `selectors`? | Double-click |
| `fill` | `selector`, `value` | Clear + type text |
| `check` | `selector` | Check checkbox |
| `uncheck` | `selector` | Uncheck checkbox |
| `select` | `selector`, `value` | Select dropdown option |
| `multiselect` | `selector`, `value` | Select multiple (value is JSON array) |
| `press` | `key` | Press key (Enter, Tab, Control+a) |
| `scroll` | `scrollX`?, `scrollY` | Scroll page |
| `hover` | `selector` | Hover over element |
| `navigate` | `value` | Navigate to URL |
| `wait` | `selector` or `value` | Wait for element/time/text |
| `upload` | `selector`, `files` | Upload files |
| `dialog` | `accept`, `value`? | Handle JS dialog |
| `assert` | See below | Verify conditions with retry |
| `extract` | `selector`, `mode`?, `output` | Extract DOM data as JSON |
| `capture` | `selector`, capture field | Capture value into variable |
| `goto` | `file` | Chain to another macro file |

All element actions support `selectors` (array of fallback CSS selectors tried if primary `selector` fails).

## Replaying

```bash
# Basic replay
zchrome cursor replay login-flow.json

# Custom timing
zchrome cursor replay macro.json --interval=500       # Fixed delay
zchrome cursor replay macro.json --interval=200-500   # Random (human-like)

# Assertion retry settings
zchrome cursor replay form.json --retries 5 --retry-delay 2000

# Fallback macro on permanent failure
zchrome cursor replay form.json --fallback error-handler.json

# Resume from last successful action
zchrome cursor replay form.json --resume

# Start from specific index
zchrome cursor replay form.json --from 5
```

## Assertions

The `assert` action verifies application state. On failure, zchrome retries from the last action command (click/fill/select/check).

```json
{"action": "assert", "selector": "#success"}                           // Element exists
{"action": "assert", "selector": "#email", "value": "user@test.com"}   // Value matches
{"action": "assert", "selector": "#btn", "attribute": "class", "contains": "active"} // Attribute
{"action": "assert", "url": "**/dashboard"}                            // URL pattern
{"action": "assert", "text": "Welcome back"}                          // Text on page
{"action": "assert", "text": "Record ID: *"}                          // Glob pattern
{"action": "assert", "selector": "tr", "count": 5}                    // Exact count
{"action": "assert", "selector": ".item", "count_min": 1}             // Min count
{"action": "assert", "selector": ".item", "count_max": 10}            // Max count
{"action": "assert", "selector": "#el", "timeout": 10000}             // Custom timeout
{"action": "assert", "selector": "#el", "fallback": "error.json"}     // Per-assertion fallback
{"action": "assert", "selector": "#el", "snapshot": "expected.json"}  // DOM snapshot comparison
```

## Capture Variables (Before/After Comparisons)

```json
{"action": "capture", "selector": "table tbody tr", "count_as": "before_rows"},
{"action": "fill", "selector": "#name", "value": "John"},
{"action": "click", "selector": "#submit"},
{"action": "wait", "value": "1000"},
{"action": "assert", "selector": "table tbody tr", "count_gt": "$before_rows"}
```

Capture modes: `count_as`, `text_as`, `value_as`, `attr_as`.
Assert with: `count_gt`, `count_lt`, `count_gte`, `count_lte`, `text_eq`, `text_neq`, `text_contains`, `value_eq`, `value_neq`.

## Data Extraction

```json
{"action": "extract", "selector": "table#results", "mode": "table", "output": "data.json"}
```

Modes: `dom` (default), `text`, `html`, `attrs`, `table`, `form`.

## Macro Chaining

```json
{"action": "goto", "file": "step2-profile.json"}
```

Splits complex flows into reusable steps.

## Dialog Handling in Macros

```json
{"action": "click", "selector": "#show-alert"},
{"action": "dialog", "accept": true},
{"action": "click", "selector": "#show-prompt"},
{"action": "dialog", "accept": true, "value": "my input", "text": "Enter name:"}
```

## Video Recording and Live Streaming

```bash
# Record replay to video (requires FFmpeg)
zchrome cursor replay demo.json --record=demo.mp4
zchrome cursor replay demo.json --record=demo.webm --fps=15 --quality=90
zchrome cursor replay demo.json --record=demo.gif

# Live stream replay
zchrome cursor replay demo.json --stream
zchrome cursor replay demo.json --stream --port=9000 --interactive

# Record + stream
zchrome cursor replay demo.json --record=demo.mp4 --stream
```

## Generating Macro Templates from DOM

```bash
zchrome dom "#login-form" macro --output login.json
```

Auto-generates `wait` → action → `assert` commands for each input. Edit `TODO` placeholders and replay.
