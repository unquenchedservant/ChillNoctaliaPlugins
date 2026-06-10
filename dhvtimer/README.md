# Noctalia DHV Timer plugin

A Noctalia v5 bar widget plugin that connects to a ChillClock timer server.
This connects to ChillClock, more is explained there.

## Installation

Clone or copy this repo into `$XDG_DATA_HOME/noctalia/plugins/dhvtimer`
(usually `~/.local/share/noctalia/plugins/dhvtimer`), then enable the
"DHV Timer" widget from Noctalia's bar settings.

## Configuration

The widget reads `server_url` from `~/.config/ChillClock/config.json` and
`CHILLCLOCK_API_KEY` from `~/.config/ChillClock/.env` — the same files
ChillClock itself uses, so no extra setup is required.

## How it works

The bar text/color update from a single long-lived connection to ChillClock's
`/events` SSE endpoint, rather than polling `/status` on a timer. If the
connection goes silent (e.g. the ChillClock server restarts), the widget
detects it within a few seconds and reconnects automatically.

- **Left click** — toggle the timer selected by the "Default timer" plugin
  setting (1 or 2)
- **Right click** — toggle the other timer
- **Middle click** — switch between timers