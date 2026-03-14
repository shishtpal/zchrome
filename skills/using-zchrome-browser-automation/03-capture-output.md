# Screenshots, PDFs, and JavaScript

## Screenshots

```bash
zchrome screenshot output.png                  # Viewport screenshot
zchrome screenshot --output full.png --full    # Full page
zchrome screenshot -s "#login-form" -o form.png  # Element screenshot
zchrome screenshot -s @e5 -o element.png       # Element by ref
zchrome screenshot https://example.com -o page.png  # Navigate + screenshot
```

## PDF Generation

```bash
zchrome pdf --output page.pdf
zchrome pdf https://example.com --output page.pdf
```

## JavaScript Evaluation

```bash
zchrome evaluate "document.title"
zchrome evaluate "document.querySelectorAll('a').length"
zchrome evaluate https://example.com "document.title"   # Navigate first
```
