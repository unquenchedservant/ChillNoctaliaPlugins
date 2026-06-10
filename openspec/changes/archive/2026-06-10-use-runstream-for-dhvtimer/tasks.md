## 1. Verify ChillClock SSE behavior

- [x] 1.1 Confirm `/events`'s payload format against the running ChillClock server (event/`data:` framing, JSON keys, whether it matches `/status`'s `"text"`/`"class"` shape) — confirmed: `data: {json}\n\n` frames with the same shape as `/status` (plus extra fields), existing `"text"`/`"class"` regex extraction works unchanged
- [x] 1.2 Confirm whether ChillClock emits periodic heartbeat/keepalive frames over `/events`, and at what interval — confirmed: it broadcasts the full status payload continuously (~10/sec, every ~100ms) regardless of state changes, so every line doubles as a heartbeat
- [x] 1.3 Confirm `noctalia.runStream` behavior on process exit (does `onLine` ever stop firing silently, or is there any signal?) — informs the reconnect design — no documented exit signal; given the ~100ms event cadence from 1.2, a silence-based watchdog (e.g. 3s timeout) works regardless and needs no separate exit signal

## 2. Implement SSE-based status updates

- [x] 2.1 Add an SSE line parser that strips a `data: ` prefix, ignores blank/comment lines, and extracts `"text"`/`"class"` using the existing regex approach
- [x] 2.2 Build the `curl -N -s -H "X-API-KEY: <key>" "<server_url>/events"` command for `noctalia.runStream`
- [x] 2.3 Wire parsed `"text"`/`"class"` into `barWidget.setText`/`setColor` (reuse the existing `COLORS` map and `#ffffff` fallback)
- [x] 2.4 Keep the `"0:00"` / `#888888` display as the initial state until the first event arrives

## 3. Rework update loop and lifecycle

- [x] 3.1 Replace `noctalia.setUpdateInterval(250)` with a coarser watchdog interval (informed by task 1.2's findings)
- [x] 3.2 Update `update()` to: load config if missing, then start the `runStream` connection once (guarded by a `streamStarted` flag), then no-op on subsequent ticks
- [x] 3.3 Track an `eventsThisTick` counter (incremented on each `onLine` call, reset by the watchdog) and implement the silence reconnect: if a watchdog tick (every 3s) finds zero events since the last tick (after a one-tick grace period post-connect), restart the `runStream` connection
- [x] 3.4 Remove the now-unused `fetchStatus`/polling code path

## 4. Preserve click handlers

- [x] 4.1 Confirm `onClick`/`onRightClick`/`onMiddleClick` remain unchanged (one-shot `runAsync` POSTs) and still no-op before config is loaded

## 5. Docs and versioning

- [x] 5.1 Update `dhvtimer/README.md` to describe the SSE-based update mechanism and reconnect behavior
- [x] 5.2 Bump `dhvtimer/plugin.toml` version (and `catalog.toml`) to 2.0.2

## 6. Manual verification

- [x] 6.1 Reload the widget and confirm it shows `"0:00"` then updates promptly when ChillClock's timer state changes, without 250ms polling
- [x] 6.2 Restart the ChillClock server while the widget is running and confirm the widget reconnects and resumes updates within the silence-timeout window
- [x] 6.3 Confirm left/right/middle click still toggle/switch timers correctly
