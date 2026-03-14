# Cookie and Storage Management

## Cookies

```bash
zchrome cookies                      # List all
zchrome cookies set name value       # Set cookie
zchrome cookies clear                # Clear all
```

## Web Storage

```bash
zchrome storage local                # List all localStorage
zchrome storage local <key>          # Get specific key
zchrome storage local set <k> <v>    # Set value
zchrome storage local clear          # Clear all
zchrome storage local export data.json   # Export to file
zchrome storage local import data.json   # Import from file
zchrome storage session              # Same commands for sessionStorage
```
