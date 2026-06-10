# Noctalia Lyrics plugin

A Noctalia v5 bar widget plugin that displays synced lyrics for the
currently playing track, fetched from [lrclib.net](https://lrclib.net).

## Installation

Clone or copy this repo into `$XDG_DATA_HOME/noctalia/plugins/lyrics`
(usually `~/.local/share/noctalia/plugins/lyrics`), then enable the
"Lyrics" widget from Noctalia's bar settings.

## Requirements

- `playerctl` must be installed and able to see your media player (MPRIS).
- `curl` must be installed for fetching lyrics from lrclib.net.

## Configuration

- **Hide when empty** — hide the widget when no synced lyrics are
  available for the current track (default: on).
- **Hide when paused** — hide the widget while playback is paused
  instead of showing the last lyric line (default: off).

## Cider support

[Cider](https://cider.sh) doesn't expose an MPRIS interface, so the widget
talks to Cider's local API at `http://127.0.0.1:10767` instead.

The widget picks whichever source is **actively playing**: if Cider is
playing, it's used; if Cider is idle/paused but another player (via
playerctl/MPRIS) is playing, that player is used instead. If neither is
playing, the widget keeps showing whichever source was active most recently
(as long as it still has a track loaded), falling back to Cider, then
playerctl, then an empty bar.

If Cider's "API tokens required" connectivity setting is enabled, add a
token to its `apiTokens` list and put the same value in
`~/.config/ChillNoctaliaPlugins/.env` as:

```
CIDER_KEY=your-token-here
```

If token validation is disabled, this file isn't needed.

## How it works

Every 500ms the widget checks Cider's local API first. If Cider is actively
playing, it's used directly. Otherwise the widget also polls `playerctl` for
the active player's status, metadata, and playback position, and picks the
active source as described in [Cider support](#cider-support). When the
active source switches to a new track, it queries lrclib.net for synced
(LRC) lyrics and displays the line matching the current playback position.
