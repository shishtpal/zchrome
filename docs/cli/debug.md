# Debug Commands

Debug JavaScript execution in the browser.

## Overview

```bash
zchrome debug <subcommand> [options]
```

| Subcommand | Description |
|------------|-------------|
| `enable` | Enable debugger |
| `disable` | Disable debugger |
| `scripts` | List scripts on the page |
| `source` | Get inline script content |
| `pause` | Pause execution |
| `resume` | Resume execution |
| `step-over` | Step over next statement |
| `step-into` | Step into function call |
| `step-out` | Step out of current function |
| `break` | Set breakpoint |
| `unbreak` | Remove breakpoint |
| `exceptions` | Set pause on exceptions |

## Quick Start Guide

### 1. Create a Test Page

Create a folder with these files:

**index.html:**
```html
<!DOCTYPE html>
<html>
<head><title>Debug Test</title></head>
<body>
  <h1>Debug Test</h1>
  <button onclick="addItem()">Add Item</button>
  <ul id="list"></ul>
  <script src="app.js"></script>
</body>
</html>
```

**app.js:**
```javascript
let count = 0;

function addItem() {
  count++;                                      // line 4
  const item = document.createElement('li');   // line 5
  item.textContent = 'Item ' + count;          // line 6
  document.getElementById('list').appendChild(item);
  console.log('Added item', count);
}
```

### 2. Start a Local Server

```bash
# Python
python -m http.server 9000

# Node.js
npx serve -p 9000
```

### 3. Test Debug Commands

```bash
# Navigate to the page
zchrome navigate http://localhost:9000

# Set breakpoint on line 4
zchrome debug break http://localhost:9000/app.js 4

# Set pause on uncaught exceptions
zchrome debug exceptions uncaught
```

### 4. Trigger the Breakpoint

Click the "Add Item" button in the browser. Execution pauses at line 4.

```bash
# Step through the code
zchrome debug step-over    # Move to line 5
zchrome debug step-over    # Move to line 6
zchrome debug resume       # Continue execution
```

## Command Reference

### debug enable

Enable the debugger domain.

```bash
zchrome debug enable
```

### debug disable

Disable the debugger domain.

```bash
zchrome debug disable
```

### debug scripts

List all scripts on the page.

```bash
zchrome debug scripts
```

**Output:**
```
Scripts on page:
================

[0] https://localhost:9000/app.js
[1] <inline> (function() { console.log('hello')...
[2] <inline> var config = { api: 'https://...
```

### debug source

Get inline script content by index (from `debug scripts`).

```bash
zchrome debug source <index> [-o <file>]
```

**Examples:**
```bash
zchrome debug source 1              # Print to console
zchrome debug source 1 -o script.js # Save to file
```

::: warning
Only works for inline scripts. External scripts must be fetched from their URL.
:::

### debug pause

Pause JavaScript execution immediately.

```bash
zchrome debug pause
```

### debug resume

Resume execution after being paused.

```bash
zchrome debug resume
```

### debug step-over

Step over the next statement (doesn't enter function calls).

```bash
zchrome debug step-over
```

### debug step-into

Step into a function call.

```bash
zchrome debug step-into
```

### debug step-out

Step out of the current function.

```bash
zchrome debug step-out
```

### debug break

Set a breakpoint at a specific URL and line number.

```bash
zchrome debug break <url> <line> [condition]
```

| Argument | Description |
|----------|-------------|
| `url` | Script URL (full or partial match) |
| `line` | Line number (1-based) |
| `condition` | Optional JavaScript expression |

**Examples:**
```bash
# Simple breakpoint
zchrome debug break http://localhost:9000/app.js 10

# Conditional breakpoint (only pause when count > 5)
zchrome debug break http://localhost:9000/app.js 10 "count > 5"

# Partial URL match
zchrome debug break app.js 10
```

**Output:**
```
Breakpoint set: 1:10:0:http://localhost:9000/app.js
  URL: http://localhost:9000/app.js
  Line: 10
  Resolved at 1 location(s)
```

### debug unbreak

Remove a breakpoint by its ID.

```bash
zchrome debug unbreak <breakpointId>
```

**Example:**
```bash
zchrome debug unbreak "1:10:0:http://localhost:9000/app.js"
```

### debug exceptions

Set how the debugger handles exceptions.

```bash
zchrome debug exceptions <none|uncaught|all>
```

| Value | Description |
|-------|-------------|
| `none` | Don't pause on exceptions |
| `uncaught` | Pause only on uncaught exceptions |
| `all` | Pause on all exceptions (caught and uncaught) |

**Examples:**
```bash
zchrome debug exceptions uncaught  # Recommended for debugging
zchrome debug exceptions all       # Pause on every exception
zchrome debug exceptions none      # Disable exception pausing
```

## Interactive Mode

Debug commands work seamlessly in interactive mode:

```bash
zchrome interactive
```

```
> navigate http://localhost:9000
Navigated to: http://localhost:9000

> debug break http://localhost:9000/app.js 4
Breakpoint set: 1:4:0:http://localhost:9000/app.js

> debug exceptions uncaught
Pause on exceptions: uncaught
```

Click the button in the browser, then:

```
> debug step-over
Stepped over.

> debug step-over
Stepped over.

> debug resume
Execution resumed.
```

## Use Cases

### Debugging a Form Submission

```bash
# Set breakpoint in form handler
zchrome debug break http://localhost:9000/form.js 25

# Pause on errors
zchrome debug exceptions uncaught

# Navigate to form
zchrome navigate http://localhost:9000/form.html
```

Submit the form, then step through:

```bash
zchrome debug step-over
zchrome debug step-into   # Enter a function
zchrome debug step-out    # Exit the function
zchrome debug resume
```

### Catching Errors

```bash
# Pause on uncaught exceptions
zchrome debug exceptions uncaught

# Navigate to page with buggy code
zchrome navigate http://localhost:9000/buggy.html
```

When an error occurs, execution pauses. Use `debug scripts` and `debug source` to inspect.

### Conditional Breakpoints

Only pause when specific conditions are met:

```bash
# Pause only when user is admin
zchrome debug break app.js 50 "user.role === 'admin'"

# Pause only on large arrays
zchrome debug break data.js 100 "items.length > 100"

# Pause only on specific values
zchrome debug break checkout.js 75 "total > 1000"
```

## Tips

1. **Use interactive mode** for debugging sessions - it's more convenient than running separate CLI commands.

2. **Set `exceptions uncaught`** early - it helps catch errors you might miss.

3. **Breakpoint IDs** are returned when you set them - save them if you need to remove specific breakpoints.

4. **Partial URL matching** works for `debug break` - you don't need the full URL.

5. **All commands auto-enable** the debugger - you don't need to run `debug enable` first.
