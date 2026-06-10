## Why

The DHV Timer bar widget currently polls ChillClock's `/status` endpoint every 250ms via `noctalia.runAsync`, spawning a new `curl` process four times per second indefinitely just to detect timer state changes. ChillClock now exposes a `/events` endpoint that pushes status updates as they happen, and Noctalia's new `noctalia.runStream(cmd, onLine)` host capability can run a single long-lived `curl` connected to that stream, invoking a callback per line. Switching to this lets the widget react to state changes immediately and removes the constant process-spawning overhead.

## What Changes

- Replace the 250ms `runAsync`-based polling of `/status` in `dhvtimer/chillclock.luau` with a single long-lived `noctalia.runStream` connection to ChillClock's `/events` endpoint.
- Parse incoming SSE `data:` lines and update `barWidget.setText`/`setColor` reactively as events arrive, instead of on a fixed timer.
- Keep the existing config-loading flow (`server_url` from `config.json`, `CHILLCLOCK_API_KEY` from `.env`) to build the SSE connection URL/headers.
- Keep `onClick`/`onRightClick`/`onMiddleClick` toggle/switch actions on `noctalia.runAsync` as one-shot POST requests (unchanged).
- Handle the case where the SSE stream ends or the server is unreachable (e.g. show a disconnected/fallback state and retry) so the widget doesn't get stuck on stale data.

## Capabilities

### New Capabilities
- `chillclock-bar`: DHV Timer bar widget behavior — config loading, SSE-based status streaming via `runStream`, display updates, reconnect/fallback handling, and click-driven timer controls.

### Modified Capabilities
(none — no existing spec covers the DHV Timer widget yet)

## Impact

- `dhvtimer/chillclock.luau`: core update loop reworked from polling to streaming.
- `dhvtimer/plugin.toml`: version bump to reflect the behavior change.
- `dhvtimer/README.md`: document the SSE-based update mechanism.
