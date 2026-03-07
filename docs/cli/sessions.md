# CLI Sessions

zchrome supports **named sessions** to manage multiple isolated Chrome configurations. Each session stores its own `zchrome.json` config file in a separate directory.

## Why Use Sessions?

- **Multiple Chrome profiles**: Work with different Chrome data directories for different projects
- **Isolated settings**: Each session can have its own viewport, user agent, geolocation, etc.
- **Easy switching**: Switch between configurations with a single flag

## Session Storage

Sessions are stored in a `sessions/` directory alongside the executable:

```
zchrome.exe
sessions/
├── default/
│   ├── zchrome.json       # Config
│   ├── chrome-profile/    # Chrome data (cookies, history)
│   └── states/            # Auth state files
├── work/
│   ├── zchrome.json
│   └── chrome-profile/
└── testing/
    └── zchrome.json
```

Each session gets its own Chrome profile by default, ensuring complete browser isolation.

## Using Sessions

```bash
# Use the default session (implicit)
zchrome navigate https://example.com

# Use a named session
zchrome --session work connect

# Create and use a new session
zchrome --session testing session create testing

# Set environment variable for default session
set ZCHROME_SESSION=work
zchrome navigate https://example.com
```

## Precedence

Session name is resolved in this order:
1. `--session` flag (highest priority)
2. `ZCHROME_SESSION` environment variable
3. `"default"` (fallback)

## Session Command

Manage named sessions for isolated Chrome configurations.

```bash
zchrome session                     # Show current session info
zchrome session list                # List all sessions
zchrome session show [name]         # Show session details (default: current)
zchrome session create <name>       # Create new session
zchrome session delete <name>       # Delete a session
```

### Examples

```bash
# Show current session
zchrome session
# Output:
# Current session: default
# Config: D:\Tools\zchrome\sessions\default\zchrome.json

# List all sessions
zchrome session list
# Output:
# Sessions:
#   default (current)
#   work
#   testing
# Total: 3 session(s)

# Create a new session
zchrome session create work
# Output:
# Created session: work
# Use: zchrome --session work <command>

# Show session details
zchrome session show work
# Output:
# Session: work
# Directory: D:\Tools\zchrome\sessions\work
# Port: 9222
# Viewport: 1920x1080

# Delete a session
zchrome session delete testing
# Output:
# Deleted session: testing

# Use a session with other commands
zchrome --session work open
zchrome --session work navigate https://example.com
```

### Notes

- The `default` session cannot be deleted
- Settings (viewport, user agent, etc.) are isolated per session
- Environment variable `ZCHROME_SESSION` sets the default session name

## Use Cases

### Multiple Projects

Keep separate browser profiles for different projects:

```bash
# Project A - production site testing
zchrome --session project-a open
zchrome --session project-a navigate https://app.example.com

# Project B - staging environment
zchrome --session project-b open --port 9223
zchrome --session project-b navigate https://staging.example.com
```

### Different User Accounts

Test with different logged-in accounts:

```bash
# Admin account
zchrome --session admin open
zchrome --session admin navigate https://app.example.com/login
# Login as admin...

# Regular user account
zchrome --session user open --port 9223
zchrome --session user navigate https://app.example.com/login
# Login as user...
```

### Device Testing

Emulate different devices per session:

```bash
# Desktop session
zchrome --session desktop open
zchrome --session desktop set viewport 1920 1080

# Mobile session
zchrome --session mobile open --port 9223
zchrome --session mobile set device "iPhone 14"
```

## See Also

- [Config File](/cli/config) - Configuration file format
- [Environment Variables](/guide/environment) - All supported environment variables
- [Sessions Guide](/guide/cli-sessions) - Detailed sessions documentation
