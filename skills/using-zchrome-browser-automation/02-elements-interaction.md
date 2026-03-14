# Element Discovery and Interaction

## Accessibility Tree Snapshots

Use `snapshot` to discover interactive elements on a page:

```bash
zchrome snapshot -i              # Interactive elements only
zchrome snapshot -i -c           # Compact (skip empty structural elements)
zchrome snapshot -i -d 3         # Limit depth
zchrome snapshot -s "#main"      # Scope to selector
zchrome snapshot --mark          # Inject stable IDs (zc-1, zc-2, ...)
```

Output example:
```
- textbox "Email" [ref=e1]
- textbox "Password" [ref=e2]
- button "Login" [ref=e3]
```

## Element Selectors

zchrome supports two selector types:
- **CSS selectors**: `#id`, `.class`, `[data-testid="x"]`, `button[type="submit"]`
- **Snapshot refs**: `@e1`, `@e2` (from `snapshot` output — quick but change if page structure changes)
- **Marked IDs**: `#zc-1`, `#zc-2` (from `snapshot --mark` — stable across data updates)

## Element Actions

```bash
# Click
zchrome click "#submit-btn"
zchrome click @e3
zchrome dblclick "#item"
zchrome hover "#menu"

# Input
zchrome focus "#search"
zchrome type "#search" "hello"        # Appends text
zchrome fill "#email" "user@test.com" # Clears first, then types

# Form controls
zchrome select "#country" "US"
zchrome check "#agree"
zchrome uncheck "#newsletter"

# Scrolling
zchrome scroll down 500
zchrome scroll up 200
zchrome scrollintoview "#footer"      # (alias: scrollinto)

# Drag and drop
zchrome drag "#source" "#target"

# File upload
zchrome upload "#file-input" document.pdf
zchrome upload @e5 file1.txt file2.txt
```

## Keyboard Input

```bash
zchrome press Enter
zchrome press Tab
zchrome press Control+a              # Select all
zchrome press Control+c              # Copy
zchrome keydown Shift                # Hold
zchrome keyup Shift                  # Release
```

## Mouse Control

```bash
zchrome mouse move 100 200
zchrome mouse down left
zchrome mouse up
zchrome mouse wheel -100             # Scroll down
```

## Getting Information

```bash
zchrome get text @e3                 # Text content
zchrome get html "#content"          # innerHTML
zchrome get dom "#element"           # outerHTML
zchrome get value "#email"           # Input value
zchrome get attr @e5 href            # Attribute value
zchrome get title                    # Page title
zchrome get url                      # Current URL
zchrome get count "li.item"          # Count matching elements
zchrome get box @e5                  # Bounding box (x, y, width, height)
zchrome get styles "#button"         # Computed styles (JSON)
```

## Wait Conditions

```bash
zchrome wait "#login-form"           # Wait for element to be visible
zchrome wait 2000                    # Wait milliseconds
zchrome wait --text "Welcome"        # Wait for text on page
zchrome wait --match "**/dashboard"  # Wait for URL glob pattern
zchrome wait --load networkidle      # Wait for load state
zchrome wait --fn "window.ready"     # Wait for JS expression to be truthy
```
