# Config File

zchrome stores session information in `zchrome.json` within each session directory. This makes the tool portable and allows subsequent commands to reuse connection information and session settings.

## File Location

The config file is stored per session:

```
sessions/
├── default/
│   ├── zchrome.json       # Base session config
│   └── zchrome.user.json  # User overrides (optional)
├── work/
│   ├── zchrome.json
│   └── zchrome.user.json
└── testing/
    └── zchrome.json
```

### User Config Files

Each session can have an optional `zchrome.user.json` file that overrides values from the base `zchrome.json`. This is useful for:

- **Personal settings** that shouldn't be shared (e.g., local Chrome path)
- **Development overrides** without modifying the base config
- **Machine-specific settings** when sharing configs across machines

User config values take precedence over base config values. Fields not specified in the user config fall back to the base config.

## Config Format

**Base config (`zchrome.json`):**

```json
{
  "chrome_path": "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
  "data_dir": "D:\\tmp\\chrome-dev-profile",
  "port": 9222,
  "ws_url": "ws://127.0.0.1:9222/devtools/browser/...",
  "last_target": "DC6E72F7B31F6A70C4C2B7A2D5A9ED74",
  "user_agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Firefox/121.0",
  "viewport_width": 1920,
  "viewport_height": 1080,
  "device_name": "Desktop",
  "geo_lat": 40.7128,
  "geo_lng": -74.0060,
  "offline": false,
  "media_feature": "dark"
}
```

**User override (`zchrome.user.json`):**

```json
{
  "chrome_path": "D:\\Apps\\ChromePortable\\chrome.exe",
  "port": 9223
}
```

In this example, the user config overrides `chrome_path` and `port`, while all other settings come from the base config.

## Configuration Fields

All fields are optional. In user config files, only specify the fields you want to override.

### Connection Settings

| Field | Description |
|-------|-------------|
| `chrome_path` | Path to Chrome executable |
| `data_dir` | User data directory for Chrome profile |
| `port` | Debug port (defaults to 9222 if not specified) |
| `ws_url` | WebSocket URL for browser connection |
| `last_target` | Last used target ID (for `--use` flag) |

### Emulation Settings

| Field | Description |
|-------|-------------|
| `user_agent` | Custom user agent string |
| `viewport_width` | Viewport width in pixels |
| `viewport_height` | Viewport height in pixels |
| `device_name` | Emulated device name |
| `geo_lat` | Geolocation latitude |
| `geo_lng` | Geolocation longitude |
| `offline` | Offline mode enabled |
| `media_feature` | Preferred color scheme (dark/light) |

### Cloud Provider Settings

| Field | Description |
|-------|-------------|
| `provider` | Cloud provider name: `local`, `kernel`, `notte`, `browserbase` |
| `provider_session_id` | Active cloud session ID (auto-managed) |
| `provider_auto_cleanup` | Whether to cleanup session on exit |

### Extension Settings

| Field | Description |
|-------|-------------|
| `via` | Extension loading mode: `port` (default) or `pipe` |
| `extensions` | Array of paths to unpacked extensions |

## Auto-Applied Settings

Session settings are automatically re-applied when connecting to a page:

- `user_agent` - Applied via CDP Emulation domain
- `viewport_width` / `viewport_height` - Applied via CDP Emulation domain
- `geo_lat` / `geo_lng` - Applied via CDP Emulation domain
- `offline` - Applied via CDP Network domain
- `media_feature` - Applied via CDP Emulation domain

## Command Line Override

Options from command line override config file values:

```bash
# Config has port: 9222, but this uses 9223
zchrome --port 9223 connect

# Config has viewport 1920x1080, but this uses 1366x768
zchrome set viewport 1366 768
```

## Debugging Config Loading

Use `--verbose` to see which config files are loaded and how they're merged:

```bash
zchrome --verbose open
# [config] Loading base config: .../sessions/default/zchrome.json
# [config] Successfully read: .../sessions/default/zchrome.json
# [config] Looking for user config: .../sessions/default/zchrome.user.json
# [config] Successfully read: .../sessions/default/zchrome.user.json
# [config] Merging user config over base config
```

## Setting Config Values

Use `set` commands to update config values:

```bash
# Viewport
zchrome set viewport 1920 1080

# Device emulation (sets viewport + user agent)
zchrome set device "iPhone 14"

# User agent
zchrome set ua firefox
zchrome set ua "Custom User Agent String"

# Geolocation
zchrome set geo 40.7128 -74.0060

# Offline mode
zchrome set offline on
zchrome set offline off

# Color scheme
zchrome set media dark
zchrome set media light
```

## Portability

The config file makes zchrome portable:

1. **Copy the executable and sessions folder** to another machine
2. **Update paths** if necessary (chrome_path, data_dir)
3. **Run commands** - connection will be re-established

## Example Workflows

### Fresh Start

```bash
# First time setup
zchrome open --chrome "C:\Program Files\Google\Chrome\Application\chrome.exe"
# Config created with chrome_path, port, ws_url

# Subsequent commands use saved config
zchrome navigate https://example.com
zchrome screenshot --output page.png
```

### Reconnecting

```bash
# Open Chrome (saves ws_url to config)
zchrome open

# Later, reconnect using saved config
zchrome connect
# Uses saved port from config

# Or connect to a specific page
zchrome --use DC6E72F7B31F6A70C4C2B7A2D5A9ED74 screenshot
# Uses last_target from config if --use not specified
```

### Multi-Session Setup

```bash
# Create sessions with different configs
zchrome --session dev session create dev
zchrome --session dev open --port 9222
zchrome --session dev set device "Desktop"

zchrome --session mobile session create mobile
zchrome --session mobile open --port 9223
zchrome --session mobile set device "iPhone 14"

# Each session has its own config file
# sessions/dev/zchrome.json
# sessions/mobile/zchrome.json
```

### Cloud Provider Config

```bash
# Set provider (saves to config)
zchrome provider set kernel

# Config now contains:
# {
#   "provider": "kernel",
#   "provider_session_id": "sess_abc123...",
#   "ws_url": "wss://..."
# }

# Subsequent commands use saved cloud session
zchrome navigate https://example.com

# Close session (clears provider_session_id and ws_url)
zchrome provider close
```

### Extensions Config

```bash
# Load an extension (saves to config)
zchrome extensions load /path/to/my-extension

# Config now contains:
# {
#   "extensions": ["/path/to/my-extension"],
#   "via": "port"
# }

# Launch Chrome with extension
zchrome open

# Subsequent opens will include the extension
zchrome open

# Use pipe mode for Chrome 137+ (experimental)
zchrome open --via=pipe

# Unload extension
zchrome extensions unload /path/to/my-extension
```

## See Also

- [CLI Sessions](/cli/sessions) - Managing named sessions
- [Cloud Providers](/cli/providers) - Cloud browser provider setup
- [Environment Variables](/guide/environment) - All supported environment variables
- [Session Emulation](/cli#session-emulation-set) - Emulation commands
