# Layout Commands

Display the DOM as a tree of bounding boxes and work with layout-based selectors (`@L` paths). Useful for understanding page structure, debugging element positions, and generating stable position-based selectors.

## Overview

Layout paths provide an alternative to CSS selectors based on visual DOM structure. Each element gets a path like `@L0/2/1` representing its position in the tree of visible elements.

**Key Benefits:**
- Position-based: Works even when elements lack IDs or stable classes
- Visual: Represents what users actually see on the page
- Hierarchical: Navigate up/down/sideways through the structure
- Stable: Less affected by minor DOM changes than CSS selectors

## Path Format

| Path | Description |
|------|-------------|
| `@L` | The body element (root) |
| `@L0` | First visible child of body |
| `@L1` | Second visible child of body |
| `@L0/2` | Third visible child of @L0 |
| `@L0/2/1` | Second visible child of @L0/2 |

Paths are based on **visible elements** (width/height > 0) in DOM order. Hidden elements are skipped.

## Basic Usage

Display the layout tree:

```bash
# Full page layout tree
zchrome layout

# Scoped to specific container
zchrome layout -s "#main-content"

# Limit depth
zchrome layout -d 3

# Output as JSON
zchrome layout --json
```

**Output:**

```
[@L] 1920x1080 @ (0,0) <body>
  [@L0] 1920x80 @ (0,0) <header#nav>
    [@L0/0] 200x60 @ (10,10) <div.logo>
    [@L0/1] 800x60 @ (400,10) <nav.menu>
  [@L1] 1920x900 @ (0,80) <main#content>
    [@L1/0] 600x400 @ (20,100) <aside.sidebar>
    [@L1/1] 1280x400 @ (640,100) <article.post> "Welcome to..."
```

## Options

| Option | Description |
|--------|-------------|
| `-s, --selector <sel>` | Scope tree to CSS selector (default: body) |
| `-d, --depth <n>` | Limit tree depth |
| `--json` | Output raw JSON instead of formatted tree |

## Subcommands

### Conversion

Convert between selector formats.

#### xpath

Convert XPath to layout path:

```bash
zchrome layout xpath "/html/body/div[1]/h1"
# Output: @L0/0
```

#### css

Convert CSS selector to layout path:

```bash
zchrome layout css "#main > .header"
# Output: @L1/0
```

#### tocss

Convert layout path to CSS selector:

```bash
zchrome layout tocss @L0/1/2
# Output: body > :nth-child(1) > :nth-child(2) > :nth-child(3)
```

### Navigation

Navigate through the layout tree.

#### exists

Check if a path is valid:

```bash
zchrome layout exists @L0/5
# Output: true or false
```

#### parent

Get the parent path:

```bash
zchrome layout parent @L0/1/2
# Output: @L0/1
```

#### next

Get the next sibling path:

```bash
zchrome layout next @L0/1
# Output: @L0/2
```

#### prev

Get the previous sibling path:

```bash
zchrome layout prev @L0/2
# Output: @L0/1
```

#### children

List all child paths:

```bash
zchrome layout children @L0
# Output:
# @L0/0
# @L0/1
# @L0/2
```

### Search

Find elements by content or position.

#### find

Search for elements containing text:

```bash
zchrome layout find "Submit"
# Output:
# @L1/2/0 <button.btn> "Submit"
# @L1/3/1 <a.link> "Submit Form"
```

#### at

Find element at screen coordinates:

```bash
zchrome layout at 400 200
# Output: @L1/0/2 <div.card> at (380,180)
```

### Export & Comparison

Save, compare, and capture layout state.

#### save

Export layout tree to JSON file:

```bash
zchrome layout save layout.json
zchrome layout save layout.json -d 5  # with depth limit
# Output: Saved layout to layout.json
```

#### diff

Compare current layout against a saved snapshot:

```bash
# Save baseline
zchrome layout save before.json

# ... page changes ...

# Compare
zchrome layout diff before.json
```

**Output:**

```
+ @L0/3 <div> (added)
- @L0/1/2 <span> (removed)
~ @L0/0 size: 100x50 -> 120x60
~ @L1/0 pos: (10,20) -> (15,25)
```

Diff symbols:
- `+` Element added
- `-` Element removed
- `~` Element changed (size, position, or tag)

#### screenshot

Take a screenshot with @L path annotations overlaid:

```bash
# Default (depth 2, outputs to layout.png)
zchrome layout screenshot

# Custom depth and output
zchrome layout screenshot -d 3 -o annotated.png
```

The screenshot shows colored overlays on elements with their @L paths labeled, useful for documentation and debugging.

### Visual & Interactive

Visualize and pick elements interactively.

#### highlight

Show visual overlay with @L paths on the page:

```bash
# Highlight depth 0-2 (default 5 second timeout)
zchrome layout highlight

# Highlight specific depth range
zchrome layout highlight -f 3 -d 5

# Custom timeout (10 seconds)
zchrome layout highlight -t 10

# Highlight subtree at specific path
zchrome layout highlight @L0/1
```

**Highlight Options:**

| Option | Description |
|--------|-------------|
| `@L<path>` | Start from specific element (default: body) |
| `-f, --from <n>` | Start highlighting from depth n (default: 0) |
| `-d <n>` | Highlight up to depth n (default: from+2) |
| `-t, --time <sec>` | Timeout in seconds (default: 5) |

Elements are color-coded by depth level (blue, red, green, yellow cycling).

#### pick

Interactively pick an element to get its @L path:

```bash
zchrome layout pick
# Hover over elements to see preview, click to select
# Output: @L1/2/0
```

## Using @L Paths in Other Commands

Layout paths (`@L...`) can be used as selectors in any element command:

```bash
# Click element at path
zchrome click @L0/2/1

# Get text from element
zchrome get text @L1/0

# Fill input at path
zchrome fill @L1/2/0 "hello@example.com"

# Take screenshot of element
zchrome screenshot -s @L0/1 -o element.png

# Wait for element
zchrome wait @L1/0/3
```

## Examples

### Debug Page Layout

```bash
# Get overview of page structure
zchrome layout -d 2

# Find where a button is
zchrome layout find "Login"

# Check element position
zchrome layout at 500 300
```

### Regression Testing

```bash
# Save baseline layout
zchrome navigate https://example.com
zchrome layout save baseline.json -d 5

# Later, compare changes
zchrome navigate https://example.com
zchrome layout diff baseline.json
```

### Documentation Screenshots

```bash
# Annotated screenshot for docs
zchrome layout screenshot -d 3 -o docs/ui-overview.png
```

### Interactive Development

```bash
# Highlight elements to understand structure
zchrome layout highlight -d 4 -t 30

# Pick element for automation
zchrome layout pick
# Returns: @L1/2/0

# Use in automation
zchrome click @L1/2/0
```

### Automation with Layout Paths

```bash
# Navigate and interact using layout paths
zchrome navigate https://example.com
zchrome wait @L1/0          # Wait for main content
zchrome click @L1/0/2/0     # Click specific element
zchrome fill @L1/1/0 "test" # Fill input
```

## Notes

- Layout paths resolve on-the-fly - you don't need to run `layout` before using `@L` paths
- Paths are based on visible elements only (width/height > 0)
- Element order follows DOM order among visible siblings
- Position changes (scroll, resize) don't affect paths - they're based on DOM structure
- For dynamic content, layout paths may shift as elements are added/removed
