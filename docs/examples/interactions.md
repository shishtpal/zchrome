# Browser Interactions

This guide covers using the CLI for browser automation with element interactions.

## Overview

zchrome provides two ways to target elements:

1. **CSS Selectors**: Standard CSS selectors like `#id`, `.class`, `button[type="submit"]`
2. **Snapshot Refs**: References from `zchrome snapshot` like `@e1`, `@e2`, `@e15`

## Basic Workflow

### 1. Navigate and Snapshot

```bash
# Launch browser and connect
zchrome open
zchrome connect

# Navigate to your target page
zchrome navigate https://example.com/login

# Take a snapshot to see available elements
zchrome snapshot -i
```

**Output:**

```
- navigation
  - link "Home" [ref=e1]
  - link "About" [ref=e2]
- main
  - heading "Login"
  - textbox "Email" [ref=e3]
  - textbox "Password" [ref=e4]
  - checkbox "Remember me" [ref=e5]
  - button "Sign In" [ref=e6]
  - link "Forgot password?" [ref=e7]

--- 7 element(s) with refs ---
```

### 2. Interact with Elements

```bash
# Fill the login form using refs
zchrome fill @e3 "user@example.com"
zchrome fill @e4 "secretpassword"
zchrome check @e5
zchrome click @e6
```

Or using CSS selectors:

```bash
zchrome fill "input[name='email']" "user@example.com"
zchrome fill "input[name='password']" "secretpassword"
zchrome check "#remember-me"
zchrome click "button[type='submit']"
```

## Snapshot Options

### Interactive Only (`-i`)

Show only interactive elements (buttons, links, inputs, etc.):

```bash
zchrome snapshot -i
```

### Compact Mode (`-c`)

Skip empty structural elements:

```bash
zchrome snapshot -c
```

### Depth Limit (`-d`)

Limit tree depth for complex pages:

```bash
zchrome snapshot -d 3
```

### Scope to Selector (`-s`)

Focus on a specific part of the page:

```bash
zchrome snapshot -s "#main-content"
zchrome snapshot -s ".form-container"
```

### Combine Options

```bash
zchrome snapshot -i -c -d 5 -s "#app"
```

## Element Actions Reference

### Click Actions

```bash
# Single click
zchrome click "#submit-btn"
zchrome click @e6

# Double click
zchrome dblclick "#item-row"
zchrome dblclick @e10

# Hover (for dropdowns, tooltips)
zchrome hover "#menu-trigger"
zchrome hover @e3
```

### Input Actions

```bash
# Focus an element
zchrome focus "#search-input"
zchrome focus @e4

# Type text (appends to existing)
zchrome type "#search" "hello world"
zchrome type @e4 "additional text"

# Fill (clears first, then types)
zchrome fill "#email" "new@example.com"
zchrome fill @e3 "replaced text"
```

### Form Controls

```bash
# Select dropdown option by value
zchrome select "#country" "US"
zchrome select @e8 "option-value"

# Check a checkbox
zchrome check "#agree-terms"
zchrome check @e5

# Uncheck a checkbox
zchrome uncheck "#newsletter"
zchrome uncheck @e5
```

### Scrolling

```bash
# Scroll the page
zchrome scroll down 500    # Scroll down 500px
zchrome scroll up 200      # Scroll up 200px
zchrome scroll left 100    # Scroll left 100px
zchrome scroll right 100   # Scroll right 100px
zchrome scroll down        # Default: 300px

# Scroll element into view
zchrome scrollintoview "#footer"
zchrome scrollinto @e15    # Alias
```

### Drag and Drop

```bash
# Drag element to another element
zchrome drag "#draggable-item" "#drop-zone"
zchrome drag @e3 @e7
```

### Keyboard Input

```bash
# Press Enter to submit
zchrome press Enter

# Press Tab to move focus
zchrome press Tab

# Keyboard shortcuts
zchrome press Control+a  # Select all
zchrome press Control+c  # Copy
zchrome press Control+v  # Paste
zchrome press Escape     # Close modal/cancel

# Hold modifier for multi-select
zchrome keydown Control
zchrome click @e5
zchrome click @e7
zchrome click @e9
zchrome keyup Control
```

### File Upload

```bash
# Upload a single file to a file input
zchrome upload "#file-input" document.pdf
zchrome upload @e5 ./report.xlsx

# Upload multiple files
zchrome upload "input[type=file]" file1.txt file2.txt file3.txt

# Note: This only selects files, does not submit the form
# Click the submit button afterwards if needed
zchrome click "#upload-btn"
```

## Complete Examples

### Login Flow

```bash
# Setup
zchrome open
zchrome connect
zchrome navigate https://app.example.com/login

# Discover elements
zchrome snapshot -i

# Fill login form
zchrome fill @e1 "john@example.com"
zchrome fill @e2 "password123"
zchrome click @e3

# Wait and verify
zchrome snapshot -i
zchrome screenshot --output logged-in.png
```

### Form Submission

```bash
# Navigate to form
zchrome navigate https://example.com/signup

# Fill form fields
zchrome fill "#firstName" "John"
zchrome fill "#lastName" "Doe"
zchrome fill "#email" "john.doe@example.com"
zchrome fill "#phone" "+1-555-1234"

# Select options
zchrome select "#country" "US"
zchrome select "#state" "CA"

# Check required boxes
zchrome check "#terms"
zchrome check "#privacy"

# Submit
zchrome click "#submit-button"

# Capture result
zchrome screenshot --output submitted.png
```

### Dropdown Navigation

```bash
# Hover to open dropdown
zchrome hover "#products-menu"

# Wait briefly for animation (manual delay)
# Then click sub-item
zchrome click "#products-menu .item-laptops"
```

### Scroll and Click

```bash
# Scroll to element first
zchrome scrollinto "#pricing-section"

# Then interact
zchrome click "#plan-pro .select-btn"
```

### Search and Results

```bash
# Find search box
zchrome snapshot -i -s "header"

# Type search query
zchrome fill @e2 "zig programming"
zchrome click @e3  # Search button

# Take snapshot of results
zchrome snapshot -i -s "#results"

# Click first result
zchrome click @e1
```

### Keyboard Navigation Flow

```bash
# Navigate form with keyboard only
zchrome focus "#first-field"
zchrome type @e1 "John"
zchrome press Tab
zchrome type @e2 "Doe"
zchrome press Tab
zchrome press Space      # Check checkbox
zchrome press Tab
zchrome press Enter      # Submit form

# Multi-select with modifier
zchrome keydown Control
zchrome click @e5
zchrome click @e7
zchrome click @e9
zchrome keyup Control

# Select all and copy
zchrome click "#text-area"
zchrome press Control+a
zchrome press Control+c
```

### File Upload Flow

```bash
# Navigate to upload page
zchrome navigate https://example.com/upload

# Take snapshot to find the file input
zchrome snapshot -i

# Upload file(s) - relative paths work
zchrome upload @e4 ./documents/report.pdf

# Or use CSS selector
zchrome upload "input[type=file]" invoice.pdf receipt.pdf

# Click submit to complete the upload
zchrome click "#submit-upload"

# Verify upload success
zchrome screenshot --output upload-result.png
```

## Getting Information

### Get Element Content

```bash
# Get text content
zchrome get text @e3
zchrome get text "#heading"

# Get HTML
zchrome get html "#content"

# Get input value
zchrome get value "#email"
```

### Get Attributes

```bash
# Get specific attribute
zchrome get attr @e5 href
zchrome get attr "#link" data-id
zchrome get attr "img" src
```

### Get Page Info

```bash
# Page title and URL
zchrome get title
zchrome get url

# Count elements
zchrome get count "li.item"
zchrome get count "button.primary"
```

### Get Element Position

```bash
# Get bounding box
zchrome get box @e5
# Output: x=100 y=200 width=300 height=50

# Useful for verifying element visibility
zchrome get box "#modal"
```

### Get Styles

```bash
# Get all computed styles as JSON
zchrome get styles "#button"
```

## Tips

### Finding Elements

1. **Use `-i` flag** to filter to interactive elements only
2. **Use `-s` flag** to scope to specific containers
3. **Check the role** in snapshot output - it tells you the element type

### Reliable Selection

- **CSS selectors** are more stable if element IDs/classes don't change
- **Snapshot refs** are great for quick automation but change if page structure changes
- **Combine both**: Use snapshot to discover, then CSS selectors in scripts

### Debugging

Use `--verbose` to see CDP messages:

```bash
zchrome click @e5 --verbose
```

### Timing

If actions fail because page hasn't loaded:

```bash
# Take a screenshot to verify page state
zchrome screenshot --output debug.png

# Retake snapshot
zchrome snapshot -i
```

## Macro Recording

Record and replay browser interactions for automation.

### Record a Session

```bash
# Navigate to starting page
zchrome navigate https://example.com/app

# Start recording (WebSocket server on port 4040)
zchrome cursor record workflow.json
# Recording on port 4040... Press Enter to stop.
#   (browser connected)

# Perform your actions in the browser:
# - Click buttons, fill forms, navigate
# - Even reload pages - events are preserved!

# Press Enter to stop
# Recorded 156 events to workflow.json
```

### Replay a Recording

```bash
# Navigate to the same starting page
zchrome navigate https://example.com/app

# Replay the recorded events
zchrome cursor replay workflow.json
# Replaying 156 events from workflow.json...
# Replay complete.
```

### Optimize for Speed

```bash
# Speed up playback 3x (default)
zchrome cursor optimize workflow.json

# Custom speed multiplier
zchrome cursor optimize workflow.json --speed=5

# Preserve original timing
zchrome cursor optimize workflow.json --speed=0
```

### How Recording Works

The recording uses WebSocket streaming for reliability:

1. **WebSocket server** starts on port 4040
2. **JavaScript injected** via CDP `Page.addScriptToEvaluateOnNewDocument`
3. **Events stream** in real-time as you interact
4. **Survives page reloads** - script auto-injects on each navigation
5. **Server-side timestamps** ensure consistent timing

## Troubleshooting

### "Element not found"

1. Take a new snapshot - element refs may have changed
2. Check if element is visible (not hidden by CSS)
3. Try scrolling element into view first
4. Use `--verbose` to see what selector is being used

### Click doesn't work

1. Element might be covered by another element
2. Try `scrollinto` first to ensure visibility
3. Some elements need focus before click

### Type not working

1. Ensure element is focusable
2. Try `focus` before `type`
3. Use `fill` instead to clear existing content
