# Config File

zchrome stores session information in `zchrome.json` within each session directory. This makes the tool portable and allows subsequent commands to reuse connection information and session settings.

## File Location

The config file is stored per session:

```
sessions/
├── default/
│   └── zchrome.json    # Default session config
├── work/
│   └── zchrome.json    # Work session config
└── testing/
    └── zchrome.json    # Testing session config
```

## Config Format

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

## Configuration Fields

### Connection Settings

| Field | Description |
|-------|-------------|
| `chrome_path` | Path to Chrome executable |
| `data_dir` | User data directory for Chrome profile |
| `port` | Debug port (default: 9222) |
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

## See Also

- [CLI Sessions](/cli/sessions) - Managing named sessions
- [Environment Variables](/guide/environment) - All supported environment variables
- [Session Emulation](/cli#session-emulation-set) - Emulation commands
