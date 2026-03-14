# Developer Tools

```bash
# Console and errors
zchrome dev console                  # View console messages
zchrome dev console --clear
zchrome dev errors                   # View page errors
zchrome dev errors --clear

# Tracing
zchrome dev trace start [path]
zchrome dev trace stop [path]
zchrome dev trace categories

# Profiling
zchrome dev profiler <secs> [path]   # Profile for N seconds (0=until Enter)
zchrome dev profiler start           # REPL: start profiling
zchrome dev profiler stop [path]     # REPL: stop and save

# Visual
zchrome dev highlight "#selector"    # Highlight element (3s overlay)

# Auth state persistence
zchrome dev state save login.json    # Save cookies + storage
zchrome dev state load login.json    # Restore auth state
zchrome dev state list               # List saved states
```
