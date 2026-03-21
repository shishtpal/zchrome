## Youtube Automations

```json
automations/youtube/
├── scrape-users.json       # Scrape channels from homepage
├── subscribe-all.json      # Subscribe to all users
├── subscribe-single.json   # Per-user subscribe (called by foreach)
├── unsubscribe-all.json    # Unsubscribe from all users
├── unsubscribe-single.json # Per-user unsubscribe (called by foreach)
└── data/yt-users.json           # (will be created when you run scrape)
```

## Usage

### Step 1: Scrape YouTube channels from homepage
zchrome cursor replay automations/youtube/scrape-users.json

### Step 2: Subscribe to all scraped channels
zchrome cursor replay automations/youtube/subscribe-all.json --interval=500

### Step 3: Unsubscribe from all channels
zchrome cursor replay automations/youtube/unsubscribe-all.json --interval=500
