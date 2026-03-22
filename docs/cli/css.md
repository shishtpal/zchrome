# CSS Commands

Inspect and modify stylesheets in the browser.

## Overview

```bash
zchrome css <subcommand> [options]
```

| Subcommand | Description |
|------------|-------------|
| `list` | Enable CSS domain (stylesheets reported via events) |
| `get` | Get stylesheet content |
| `set` | Replace stylesheet content from file |
| `computed` | Get computed styles for an element |
| `inject` | Inject CSS into the page |
| `pseudo` | Force pseudo states on an element |

## css list

Enable the CSS domain. Stylesheets will be reported via events as they are loaded.

```bash
zchrome css list
```

## css get

Get the content of a stylesheet by its ID.

```bash
zchrome css get <styleSheetId> [-o <file>]
```

### Options

| Option | Description |
|--------|-------------|
| `-o <file>` | Save stylesheet content to file |

### Example

```bash
# Print stylesheet content
zchrome css get ss-123

# Save to file
zchrome css get ss-123 -o styles.css
```

## css set

Replace a stylesheet's content with content from a file.

```bash
zchrome css set <styleSheetId> <file>
```

### Example

```bash
# Replace stylesheet with new content
zchrome css set ss-123 ./new-styles.css
```

## css computed

Get computed styles for an element matching a CSS selector.

```bash
zchrome css computed <selector>
```

### Example

```bash
# Get computed styles for a button
zchrome css computed "button.primary"

# Get computed styles for body
zchrome css computed "body"
```

**Output:**

```
Computed styles for 'button.primary':
  display: inline-block
  background-color: rgb(0, 123, 255)
  color: rgb(255, 255, 255)
  padding: 10px 20px
  ...
```

## css inject

Inject CSS into the page. Creates a new stylesheet with the given content.

```bash
zchrome css inject <css-text>
```

### Examples

```bash
# Change background color
zchrome css inject "body { background: #f0f0f0; }"

# Hide elements
zchrome css inject ".ad-banner { display: none !important; }"

# Multiple rules
zchrome css inject "h1 { color: red; } p { font-size: 18px; }"
```

**Output:**

```
CSS injected (styleSheetId: ss-456)
```

## css pseudo

Force pseudo states on an element (useful for testing hover/focus styles).

```bash
zchrome css pseudo <selector> <states...>
```

### Available States

- `hover` - `:hover`
- `active` - `:active`
- `focus` - `:focus`
- `focus-within` - `:focus-within`
- `focus-visible` - `:focus-visible`
- `target` - `:target`

### Examples

```bash
# Force hover state
zchrome css pseudo "button.primary" hover

# Force multiple states
zchrome css pseudo "a.link" hover active

# Force focus state on input
zchrome css pseudo "#email" focus
```

**Output:**

```
Forced pseudo states on 'button.primary': :hover
```

## Interactive Mode

All CSS commands work in interactive mode:

```
zchrome> css list
CSS domain enabled. Stylesheets will be reported via events.

zchrome> css computed "body"
Computed styles for 'body':
  display: block
  margin: 8px
  ...

zchrome> css inject "body { background: lightblue; }"
CSS injected (styleSheetId: ss-789)

zchrome> css pseudo "button" hover
Forced pseudo states on 'button': :hover
```

## Use Cases

### Testing Hover States

```bash
# Navigate to page
zchrome navigate https://example.com

# Force hover on button to see hover styles
zchrome css pseudo "button.submit" hover

# Take screenshot of hover state
zchrome screenshot -o hover-state.png
```

### Quick Styling Changes

```bash
# Hide annoying elements
zchrome css inject ".cookie-banner, .newsletter-popup { display: none; }"

# Change theme colors
zchrome css inject ":root { --primary-color: #ff6600; }"
```

### Debugging Layout Issues

```bash
# Get computed styles to debug layout
zchrome css computed ".problematic-element"

# Add debug borders
zchrome css inject "* { outline: 1px solid red; }"
```
