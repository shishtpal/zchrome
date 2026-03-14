# Network Interception

```bash
# Log intercepted requests
zchrome network route "*api/*"

# Block requests (ads, images, etc.)
zchrome network route "*.png" --abort
zchrome network route "*google-analytics*" --abort

# Mock API responses
zchrome network route "*api/user*" --body '{"name":"Test","id":42}'
zchrome network route "*api/config*" --file mock.json

# Redirect to local dev server
zchrome network route "*api/*" --redirect "http://localhost:3000"

# Remove all routes
zchrome network unroute

# View tracked requests
zchrome network requests
zchrome network requests --filter "api"
zchrome network requests --clear
```
