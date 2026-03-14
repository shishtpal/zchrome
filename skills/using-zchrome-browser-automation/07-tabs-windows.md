# Tab and Window Management

```bash
zchrome tab                          # List open tabs
zchrome tab new [url]                # Open new tab
zchrome tab <n>                      # Switch to tab n
zchrome tab close [n]                # Close tab
zchrome window new                   # Open new window
zchrome pages                        # List all pages with target IDs
zchrome list-targets                 # List all targets
```

## Working with Specific Pages

```bash
zchrome pages                                          # Get target IDs
zchrome --use <target-id> evaluate "document.title"    # Run on specific page
zchrome --use <target-id> screenshot --output page.png
```
