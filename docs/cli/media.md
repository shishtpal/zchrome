# Media Commands

Inspect audio and video elements on the page. Useful for testing TTS products, voice agents, media players, and any application that relies on audio/video playback.

## Commands

### `media list`

List all audio and video elements on the page.

```bash
zchrome media list
```

**Output (JSON array):**
```json
[
  {"index": 0, "selector": "video#player", "tagName": "VIDEO", "paused": false, "currentTime": 83.5, "duration": 300},
  {"index": 1, "selector": "audio.preview", "tagName": "AUDIO", "paused": true, "currentTime": 0, "duration": 30}
]
```

### `media get [selector]`

Get detailed state of a specific media element or all elements.

```bash
# Get specific element
zchrome media get "video#player"

# Get all elements (same as list but with full details)
zchrome media get
```

**Output (JSON object):**
```json
{
  "selector": "video#player",
  "tagName": "VIDEO",
  "src": "https://example.com/video.mp4",
  "currentSrc": "https://example.com/video.mp4",
  "paused": false,
  "ended": false,
  "seeking": false,
  "currentTime": 83.5,
  "duration": 300.0,
  "volume": 0.8,
  "muted": false,
  "defaultMuted": false,
  "playbackRate": 1.0,
  "defaultPlaybackRate": 1.0,
  "autoplay": true,
  "loop": false,
  "controls": true,
  "readyState": 4,
  "networkState": 2,
  "preload": "auto",
  "buffered": {"start": 0, "end": 150.5},
  "error": null
}
```

### `media get --check-autoplay`

Check if autoplay is blocked by browser policy. This flag attempts to call `play()` on the element to detect `NotAllowedError`.

```bash
zchrome media get "video#player" --check-autoplay
```

**Output with autoplay check:**
```json
{
  "selector": "video#player",
  "paused": true,
  "autoplayBlocked": true,
  "autoplayBlockReason": "NotAllowedError: play() failed because the user didn't interact with the document first"
}
```

::: warning
The `--check-autoplay` flag briefly attempts to play the media element. Use with caution in production tests.
:::

## Wait Options

The `wait` command supports media-specific conditions. The selector is optional - omit it to wait for ANY media element.

### `--media-playing [selector]`

Wait for media to start playing.

```bash
# Wait for any media to play
zchrome wait --media-playing

# Wait for specific element
zchrome wait --media-playing "video#player"
```

### `--media-ended [selector]`

Wait for media playback to end.

```bash
zchrome wait --media-ended "audio.preview"
```

### `--media-ready [selector]`

Wait for media to have enough data to play (`readyState >= 3`).

```bash
zchrome wait --media-ready "video"
```

### `--media-error [selector]`

Wait for a media error to occur.

```bash
zchrome wait --media-error "video#player"
```

## Media State Properties

| Property | Description |
|----------|-------------|
| `paused` | `true` if playback is paused |
| `ended` | `true` if playback has ended |
| `currentTime` | Current playback position (seconds) |
| `duration` | Total duration (seconds, `null` if unknown) |
| `volume` | Volume level (0.0 to 1.0) |
| `muted` | `true` if muted |
| `readyState` | Data availability state (see below) |
| `networkState` | Network state (see below) |
| `error` | `null` or `{code, message}` |

### `readyState` Values

| Value | Constant | Description |
|-------|----------|-------------|
| 0 | `HAVE_NOTHING` | No information about the media |
| 1 | `HAVE_METADATA` | Metadata loaded |
| 2 | `HAVE_CURRENT_DATA` | Current frame loaded |
| 3 | `HAVE_FUTURE_DATA` | Enough data for next frame |
| 4 | `HAVE_ENOUGH_DATA` | Enough data to play through |

### `networkState` Values

| Value | Constant | Description |
|-------|----------|-------------|
| 0 | `NETWORK_EMPTY` | Not initialized |
| 1 | `NETWORK_IDLE` | Active but not using network |
| 2 | `NETWORK_LOADING` | Downloading data |
| 3 | `NETWORK_NO_SOURCE` | No source found |

### Media Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| 1 | `MEDIA_ERR_ABORTED` | Playback aborted by user |
| 2 | `MEDIA_ERR_NETWORK` | Network error |
| 3 | `MEDIA_ERR_DECODE` | Decoding error |
| 4 | `MEDIA_ERR_SRC_NOT_SUPPORTED` | Format not supported |

## Use Cases

### Testing TTS/Voice Preview

```bash
# Navigate to page
zchrome navigate https://app.example.com/voice-preview

# Click play button
zchrome click "#play-sample"

# Wait for audio to start and then end
zchrome wait --media-playing "audio"
zchrome wait --media-ended "audio"

# Verify no errors
zchrome media get "audio" | jq '.error'
```

### Detecting Autoplay Blocking

```bash
# Check if video autoplays
zchrome navigate https://example.com/video-page
zchrome media get "video" --check-autoplay | jq '.autoplayBlocked'
```

### Monitoring Media State

```bash
# Get all media elements
zchrome media list | jq '.[] | select(.paused == false)'

# Check for errors
zchrome media list | jq '.[] | select(.error != null)'
```

## Interactive Mode

All media commands work in the interactive REPL:

```
zchrome> media list
zchrome> media get "video#player" --check-autoplay
zchrome> wait --media-playing
```
