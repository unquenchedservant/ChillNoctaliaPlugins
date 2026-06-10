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

## How it works

Every 500ms the widget polls `playerctl` for the active player's status,
metadata, and playback position. When a new track starts playing, it
queries lrclib.net for synced (LRC) lyrics and displays the line matching
the current playback position.
