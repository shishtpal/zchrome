# CLI Sessions

zchrome supports **named sessions** to manage multiple isolated Chrome configurations. Each session maintains its own configuration file with separate connection settings, emulation preferences, and stored state.

## Why Use Sessions?

Sessions solve common workflow challenges:

### Multiple Projects
Work on different projects that need different Chrome profiles or configurations:

```bash
# Project A uses port 9222 with a specific Chrome profile
zchrome --session project-a open --data-dir ~/chrome-profiles/project-a

# Project B uses port 9223 with a different profile
zchrome --session project-b open --port 9223 --data-dir ~/chrome-profiles/project-b
```

### Different Environments
Test with different device emulations or user agents:

```bash
# Mobile testing session
zchrome --session mobile set device "iPhone 14"
zchrome --session mobile navigate https://example.com

# Desktop testing session
zchrome --session desktop set viewport 1920 1080
zchrome --session desktop navigate https://example.com
```

### Team Workflows
Share session configurations or keep personal settings separate:

```bash
# Personal development session
zchrome --session dev set geo 40.7128 -74.0060

# QA testing session with specific settings
zchrome --session qa set offline on
```

## Session Storage

Sessions are stored in a `sessions/` directory alongside the zchrome executable:

```
zchrome.exe (or zchrome binary)
sessions/
├── default/
│   ├── zchrome.json      # Config: port, ws_url, settings
│   ├── zsnap.json        # Snapshot data
│   ├── chrome-profile/   # Chrome user data (cookies, history, etc.)
│   └── states/           # Auth state files (dev state save/load)
│       └── github.json
├── work/
│   ├── zchrome.json
│   ├── zsnap.json
│   ├── chrome-profile/
│   └── states/
└── mobile-test/
    ├── zchrome.json
    ├── zsnap.json
    └── chrome-profile/
```

Each session gets its own Chrome profile directory by default, providing complete isolation of:
- Browser cookies and localStorage
- Browsing history
- Saved passwords and autofill data
- Extensions and settings

This makes zchrome **portable** - copy the executable and sessions folder together to preserve all configurations.

## Using Sessions

### Command-Line Flag

The `--session` flag specifies which session to use:

```bash
zchrome --session work connect
zchrome --session work navigate https://example.com
zchrome --session work screenshot --output page.png
```

### Environment Variable

Set `ZCHROME_SESSION` to avoid typing `--session` repeatedly:

```bash
# Windows
set ZCHROME_SESSION=work

# Linux/macOS
export ZCHROME_SESSION=work

# Now all commands use the "work" session
zchrome connect
zchrome navigate https://example.com
```

### Resolution Order

Session name is resolved in this order:
1. `--session <name>` flag (highest priority)
2. `ZCHROME_SESSION` environment variable
3. `"default"` (fallback)

## Session Commands

### View Current Session

```bash
zchrome session
```

Output:
```
Current session: default
Config: D:\Tools\zchrome\sessions\default\zchrome.json
Port: 9222
WebSocket URL: ws://127.0.0.1:9222/devtools/browser/...
Viewport: 1920x1080
```

### List All Sessions

```bash
zchrome session list
```

Output:
```
Sessions:
  default (current)
  work
  mobile-test
Total: 3 session(s)
```

### Show Session Details

```bash
zchrome session show work
```

Output:
```
Session: work
Directory: D:\Tools\zchrome\sessions\work
Port: 9223
WebSocket URL: ws://127.0.0.1:9223/devtools/browser/...
Chrome: C:\Program Files\Google\Chrome\Application\chrome.exe
Data dir: D:\chrome-profiles\work
Viewport: 1920x1080
Device: Desktop
```

### Create a Session

```bash
zchrome session create work
```

Output:
```
Created session: work
Use: zchrome --session work <command>
```

The session directory is created but remains empty until you run commands that save configuration (like `connect` or `set viewport`).

### Delete a Session

```bash
zchrome session delete work
```

Output:
```
Deleted session: work
```

**Note:** The `default` session cannot be deleted.

## Practical Examples

### Multi-Environment Testing

```bash
# Set up production-like session
zchrome --session prod set device "Desktop"
zchrome --session prod set ua chrome

# Set up mobile session
zchrome --session mobile set device "iPhone 15"

# Run tests against each
zchrome --session prod navigate https://example.com
zchrome --session prod screenshot --output prod.png

zchrome --session mobile navigate https://example.com
zchrome --session mobile screenshot --output mobile.png
```

### Parallel Chrome Instances

Run multiple Chrome instances on different ports:

```bash
# Session 1: Port 9222 (default)
zchrome --session dev1 open

# Session 2: Port 9223 (different terminal)
zchrome --session dev2 open --port 9223

# Commands target the correct instance automatically
# (each session remembers its port)
zchrome --session dev1 navigate https://example.com
zchrome --session dev2 navigate https://google.com
```

**Port persistence:** When you specify `--port`, it's saved to the session's config. Future commands automatically use the saved port - no need to repeat `--port`.

**Port conflict detection:** If you try to open a new session on a port already in use by another Chrome instance:

```
> $env:ZCHROME_SESSION="youtube"
> zchrome open
Error: Port 9222 is already in use by another Chrome instance.

To run multiple Chrome instances for different sessions, use --port:
  zchrome open --port 9223

The port will be saved to this session's config for future commands.
```

**Reconnecting to same session:** If the port is already used by the *same* session's Chrome instance, zchrome reconnects normally:

```
> zchrome open
Chrome already running on port 9223
WebSocket URL: ws://127.0.0.1:9223/devtools/browser/...
```

### Interactive Mode with Sessions

```bash
zchrome --session work interactive
```

All commands in interactive mode use the specified session:

```
zchrome> navigate https://example.com
URL: https://example.com
Title: Example Domain

zchrome> set viewport 1920 1080
Viewport set to 1920x1080 (page reloaded)

zchrome> exit
```

### Automation Scripts

```bash
#!/bin/bash
# test-all-devices.sh

DEVICES=("iPhone 14" "iPad" "Pixel 8" "Desktop")

for device in "${DEVICES[@]}"; do
    session_name=$(echo "$device" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
    
    # Create and configure session
    zchrome --session "$session_name" session create "$session_name" 2>/dev/null
    zchrome --session "$session_name" set device "$device"
    
    # Run test
    zchrome --session "$session_name" navigate https://example.com
    zchrome --session "$session_name" screenshot --output "${session_name}.png"
done
```

## Migration from Single Config

If you have an existing `zchrome.json` file from an older version, zchrome automatically migrates it to the `sessions/default/` directory on first run.

## Session vs Browser Sessions

Don't confuse **CLI sessions** with **browser sessions** (CDP sessions):

| CLI Sessions | Browser Sessions |
|--------------|------------------|
| Named configuration profiles | Active connections to browser targets |
| Stored in `sessions/<name>/` | Runtime-only, in memory |
| Persist across zchrome runs | Exist only while connected |
| Managed via `session` command | Managed via `tab`/`window` commands |

See [Sessions & Targets](/guide/sessions) for information about browser sessions and CDP targets.
