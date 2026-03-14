# Launch, Connect, and Navigate

## Opening a Local Browser

```bash
# Launch Chrome with remote debugging
zchrome open

# Specify Chrome path explicitly
zchrome open --chrome "C:\Program Files\Google\Chrome\Application\chrome.exe"

# On macOS
zchrome open --chrome "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# On Linux
zchrome open --chrome /usr/bin/google-chrome
```

## Connect and Navigate

```bash
# Connect (saves WebSocket URL to zchrome.json)
zchrome connect

# Navigate
zchrome navigate https://example.com

# Get browser version
zchrome version
```

All subsequent commands reuse the saved WebSocket URL automatically.

## Headless Mode

```bash
zchrome open --headless        # new headless (recommended)
zchrome open --headless old    # old headless
```

## Custom Port

```bash
zchrome open --port 9333       # Use port 9333 instead of default 9222
```

## Named Sessions (Isolated Configs)

```bash
zchrome --session work open --port 9222
zchrome --session personal open --port 9223

# Or via env var
$env:ZCHROME_SESSION = "work"
zchrome navigate https://example.com
```

Each session stores its own config, Chrome profile, and cookies under `sessions/<name>/`.

### Session Management Commands

```bash
zchrome session                    # Show current session info
zchrome session list               # List all sessions
zchrome session create <name>      # Create new session
zchrome session delete <name>      # Delete a session
```

## Common Errors When Opening Chrome

See [14-troubleshooting.md](14-troubleshooting.md) for detailed solutions to:
- Chrome not installed / not found
- Port already in use
- Connection refused
- Permission issues
