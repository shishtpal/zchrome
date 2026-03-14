# Common Patterns

## Login + Scrape

```bash
zchrome open
zchrome navigate https://app.example.com/login
zchrome snapshot -i
zchrome fill @e1 "user@example.com"
zchrome fill @e2 "password123"
zchrome click @e3
zchrome wait --text "Dashboard"
zchrome navigate https://app.example.com/data
zchrome snapshot -s "table"
zchrome get text "table"
```

## Form Testing with Macros

```json
{
  "version": 2,
  "commands": [
    {"action": "navigate", "value": "https://example.com/form"},
    {"action": "fill", "selector": "#name", "value": "John Doe"},
    {"action": "assert", "selector": "#name", "value": "John Doe"},
    {"action": "fill", "selector": "#email", "value": "john@test.com"},
    {"action": "assert", "selector": "#email", "value": "john@test.com"},
    {"action": "select", "selector": "#country", "value": "US"},
    {"action": "check", "selector": "#agree"},
    {"action": "click", "selector": "#submit"},
    {"action": "assert", "text": "Success", "timeout": 5000}
  ]
}
```

```bash
zchrome cursor replay form-test.json --retries 3 --retry-delay 1000
```

## CI/CD Pipeline (GitHub Actions)

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    env:
      ZCHROME_PROVIDER: kernel
      ZCHROME_KERNEL_API_KEY: ${{ secrets.KERNEL_API_KEY }}
    steps:
      - uses: actions/checkout@v4
      - name: Run browser tests
        run: |
          zchrome --cleanup navigate https://example.com
          zchrome --cleanup screenshot --output test.png
```

## Save and Restore Auth State

```bash
# Login once
zchrome navigate https://app.example.com/login
zchrome fill "#email" "user@test.com"
zchrome fill "#password" "secret"
zchrome click "#submit"
zchrome wait --text "Dashboard"

# Save auth state
zchrome dev state save login-state.json

# Later: restore without re-logging in
zchrome dev state load login-state.json
zchrome navigate https://app.example.com/dashboard
```

## Screenshot Testing

```bash
# Capture baseline
zchrome navigate https://example.com
zchrome screenshot --output baseline.png

# After changes, diff
zchrome navigate https://example.com
zchrome diff screenshot --baseline baseline.png --output diff.png -t 0.05
```
