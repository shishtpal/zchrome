# Clipboard Commands

Manage the system clipboard and simulate copy/paste keyboard shortcuts in the browser.

## Commands

### Read Clipboard

Read text content from the system clipboard:

```bash
zchrome clipboard read
```

### Write to Clipboard

Write text to the system clipboard:

```bash
zchrome clipboard write "Hello, World!"
```

### Copy Selection

Simulate <kbd>Ctrl+C</kbd> to copy the current browser selection:

```bash
zchrome clipboard copy
```

### Paste from Clipboard

Simulate <kbd>Ctrl+V</kbd> to paste clipboard contents into the focused element:

```bash
zchrome clipboard paste
```

## Examples

### Copy text from a page element

```bash
# Select all text in an input, copy it, then read from clipboard
zchrome click "#my-input"
zchrome press Control+a
zchrome clipboard copy
zchrome clipboard read
```

### Fill a field via clipboard

```bash
# Write text to clipboard, then paste into a focused input
zchrome clipboard write "test@example.com"
zchrome click "#email"
zchrome clipboard paste
```

### Extract and reuse text

```bash
# Read clipboard content and use it elsewhere
zchrome clipboard read
# Output: Hello, World!
```

## Interactive Mode

In the REPL, use `clipboard` or the short alias `cb`:

```
zchrome> clipboard read
Hello, World!

zchrome> cb write "new text"
Written to clipboard: new text

zchrome> cb copy
Copied (Ctrl+C)

zchrome> cb paste
Pasted (Ctrl+V)
```

## Notes

- **read** and **write** operate on the host system clipboard using the [zlib_clipboard](https://github.com/shishtpal/zlib_clipboard) library, not the browser's `navigator.clipboard` API.
- **copy** and **paste** simulate keyboard shortcuts (<kbd>Ctrl+C</kbd> / <kbd>Ctrl+V</kbd>) via the Chrome DevTools Protocol `Input.dispatchKeyEvent`.
- Clipboard read/write requires a session (active page), since the command is session-scoped.
