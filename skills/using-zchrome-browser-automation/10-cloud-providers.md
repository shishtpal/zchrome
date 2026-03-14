# Cloud Browser Providers

Use cloud browsers instead of local Chrome:

```bash
# Set API key
$env:ZCHROME_KERNEL_API_KEY = "your-api-key"

# Configure provider
zchrome provider set kernel           # kernel, notte, browserbase, browserless
zchrome provider list                 # List available providers
zchrome provider status               # Show current provider + session

# Create cloud session
zchrome open                          # Creates cloud browser session

# Use normally — all commands use cloud browser
zchrome navigate https://example.com
zchrome screenshot --output page.png

# Close when done
zchrome provider close

# One-off command with auto-cleanup
zchrome --cleanup navigate https://example.com

# Switch back to local
zchrome provider set local
```

## Provider API Key Environment Variables

| Provider | Environment Variable |
|----------|---------------------|
| Kernel.sh | `ZCHROME_KERNEL_API_KEY` |
| Notte.cc | `ZCHROME_NOTTE_API_KEY` |
| Browserbase | `ZCHROME_BROWSERBASE_API_KEY` |
| Browserless.io | `ZCHROME_BROWSERLESS_API_KEY` |
