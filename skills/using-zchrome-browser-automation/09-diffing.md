# Page Diffing

## Snapshot Diff (Accessibility Tree)

```bash
zchrome diff snapshot                             # Current vs last session snapshot
zchrome diff snapshot --baseline before.txt       # Current vs saved file
zchrome diff snapshot -s "#main" -c               # Scoped + compact
```

## Screenshot Diff (Visual Pixel Comparison)

```bash
zchrome diff screenshot --baseline before.png     # Visual diff
zchrome diff screenshot -b before.png -t 0.05     # Custom threshold
```

## URL Comparison

```bash
zchrome diff url https://v1.com https://v2.com                # Snapshot diff
zchrome diff url https://v1.com https://v2.com --screenshot   # Visual diff
```
