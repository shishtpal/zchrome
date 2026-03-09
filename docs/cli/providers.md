# Cloud Browser Providers

zchrome supports cloud browser providers for running browser automation in the cloud. Cloud providers work the same way as local Chrome - use `open` to create a session, then subsequent commands use that session.

## Supported Providers

| Provider | Description | API Key Environment Variable |
|----------|-------------|------------------------------|
| `local` | Local Chrome (default) | None required |
| `kernel` | [Kernel.sh](https://kernel.sh) | `ZCHROME_KERNEL_API_KEY` |
| `notte` | [Notte.cc](https://notte.cc) | `ZCHROME_NOTTE_API_KEY` |
| `browserbase` | [Browserbase](https://browserbase.com) | `ZCHROME_BROWSERBASE_API_KEY` |

## Quick Start

```bash
# 1. Set your API key
$env:ZCHROME_KERNEL_API_KEY = "your-api-key"

# 2. Set the provider for this session
zchrome provider set kernel

# 3. Create a cloud browser session (like 'open' for local Chrome)
zchrome open
# Output:
# Creating cloud browser session on Kernel.sh...
# Cloud browser session created!
# Session ID: sess_abc123...
# WebSocket URL: wss://...
# Live view: https://...

# 4. Now run commands - they use the cloud browser
zchrome navigate https://example.com
zchrome screenshot --output page.png
zchrome snapshot

# 5. Close the session when done
zchrome provider close
```

## Provider Command

The `provider` command manages cloud browser providers.

```bash
zchrome provider list          # List available providers
zchrome provider set <name>    # Set default provider for session
zchrome provider status        # Show current provider and session info
zchrome provider close         # Close active cloud session
```

### provider list

Show all available providers and their configuration status.

```bash
zchrome provider list
```

**Output:**

```
Available Cloud Browser Providers:
------------------------------------------------------------
  local           Local Chrome         [configured]
  kernel          Kernel.sh            [needs API key]
                  env: ZCHROME_KERNEL_API_KEY
  notte           Notte.cc             [needs API key]
                  env: ZCHROME_NOTTE_API_KEY
  browserbase     Browserbase          [needs API key]
                  env: ZCHROME_BROWSERBASE_API_KEY

To set a provider: zchrome provider set <name>
To configure: set the environment variable shown above
```

### provider set

Set the default provider for the current session.

```bash
zchrome provider set <name>
```

**Examples:**

```bash
# Use Kernel.sh
zchrome provider set kernel

# Use Browserbase
zchrome provider set browserbase

# Switch back to local Chrome
zchrome provider set local
```

## Open and Connect Commands

The `open` and `connect` commands work for both local and cloud providers:

### open (Cloud Provider)

Create a new cloud browser session:

```bash
zchrome open
```

**Output:**

```
Creating cloud browser session on Kernel.sh...
Cloud browser session created!
Session ID: sess_abc123...
WebSocket URL: wss://...
Live view: https://...
```

The session info is saved to config for subsequent commands.

### connect (Cloud Provider)

Verify and reconnect to an existing cloud session:

```bash
zchrome connect
```

**Output:**

```
Connected to cloud session on Kernel.sh
Session ID: sess_abc123...
WebSocket URL: wss://...
```

If the session has expired, you'll be prompted to run `open` again.

### provider status

Show the current provider configuration and active session info.

```bash
zchrome provider status
```

**Output:**

```
Session: default
----------------------------------------
Provider: kernel (Kernel.sh)
API Key: configured (via ZCHROME_KERNEL_API_KEY)
Auto-cleanup: timeout

Active Session ID: sess_abc123...
WebSocket URL: wss://...
```

### provider close

Explicitly close the active cloud session and clear session info from config.

```bash
zchrome provider close
```

**Output:**

```
Closing cloud session: sess_abc123...
Session closed successfully
```

## Session Persistence

Cloud browser sessions **persist between commands** by default. This means:

1. First command creates a new cloud session
2. Subsequent commands reuse the same session
3. Browser state (cookies, localStorage, open tabs) is preserved
4. Session stays alive until explicitly closed or it times out

This is efficient because you don't pay for session creation on every command.

### Example Workflow

```bash
# First command - creates new cloud session
zchrome navigate https://app.example.com/login

# Same session - browser state preserved
zchrome fill "#email" "user@example.com"
zchrome fill "#password" "secret"
zchrome click "#submit"

# Same session - now logged in
zchrome wait --text "Dashboard"
zchrome screenshot --output dashboard.png

# When done, close the session
zchrome provider close
```

## Cleanup Options

By default, cloud sessions are kept alive for reuse. You can control cleanup behavior:

### Manual Cleanup

```bash
# Explicitly close session when done
zchrome provider close
```

### Per-Command Cleanup

Use `--cleanup` flag to destroy the session after a single command:

```bash
# Creates session, runs command, destroys session
zchrome --cleanup navigate https://example.com
```

This is useful for:
- One-off tasks
- CI/CD pipelines where you want a fresh session each run
- Avoiding session timeout charges

## Command-Line Override

Override the session provider for a single command with `--provider`:

```bash
# Use kernel just for this command (even if local is default)
zchrome --provider kernel screenshot --output cloud.png

# Use local Chrome even when cloud provider is set
zchrome --provider local open
```

## Using Local Chrome with Cloud Provider Set

If you need to use local Chrome while a cloud provider is set, use the `--provider local` flag:

```bash
# Use local Chrome for this command only
zchrome --provider local open

# Or switch back to local permanently
zchrome provider set local
```

## Session Recovery

If a cloud session expires or becomes invalid, zchrome automatically:

1. Detects the connection failure
2. Creates a new session
3. Updates the config
4. Continues with the command

This happens transparently - you don't need to manually handle expired sessions.

## Environment Variables

Set provider via environment variable:

```bash
# Set default provider
$env:ZCHROME_PROVIDER = "kernel"

# Set API keys
$env:ZCHROME_KERNEL_API_KEY = "your-kernel-api-key"
$env:ZCHROME_NOTTE_API_KEY = "your-notte-api-key"
$env:ZCHROME_BROWSERBASE_API_KEY = "your-browserbase-api-key"
```

Priority order:
1. `--provider` CLI flag (highest)
2. Session config (`provider` field in `zchrome.json`)
3. `ZCHROME_PROVIDER` environment variable
4. `"local"` (default)

## CI/CD Examples

### GitHub Actions

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    env:
      ZCHROME_KERNEL_API_KEY: ${{ secrets.KERNEL_API_KEY }}
      ZCHROME_PROVIDER: kernel
    steps:
      - uses: actions/checkout@v4
      - name: Run browser tests
        run: |
          zchrome --cleanup navigate https://example.com
          zchrome --cleanup screenshot --output test.png
```

### GitLab CI

```yaml
test:
  variables:
    ZCHROME_PROVIDER: "kernel"
    ZCHROME_KERNEL_API_KEY: $KERNEL_API_KEY
  script:
    - zchrome --cleanup navigate https://example.com
    - zchrome --cleanup screenshot --output screenshot.png
```

## Live View URLs

Some providers (like Kernel.sh) offer live view URLs to watch the browser in real-time. When available, these are shown with `--verbose`:

```bash
$ zchrome --verbose navigate https://example.com
Creating new cloud session on Kernel.sh...
Created cloud session: sess_abc123
Live view: https://kernel.sh/live/sess_abc123
...
```

## See Also

- [Environment Variables](/guide/environment) - All environment variables including provider keys
- [Config File](/cli/config) - How provider settings are stored
- [Sessions](/cli/sessions) - Named sessions (each can have different providers)
