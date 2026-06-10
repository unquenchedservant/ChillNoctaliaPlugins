## Context

`dhvtimer/chillclock.luau` currently calls `update()` every 250ms (`noctalia.setUpdateInterval(250)`), and each tick spawns a `curl` via `noctalia.runAsync` against ChillClock's `/status` endpoint, parsing `"text"` and `"class"` fields out of the JSON body to set the bar's text/color.

ChillClock now exposes `/events`, a server-sent-events stream that pushes status updates as they occur. The new `noctalia.runStream(cmd, onLine)` host capability runs a long-lived command and invokes `onLine(line)` for each line of output, with the process auto-terminated on script reload or widget removal.

## Goals / Non-Goals

**Goals:**
- Replace the 250ms polling loop with a single long-lived `curl -N` connection to `/events`, updating the bar reactively per SSE event.
- Preserve existing config-loading (`server_url`, `CHILLCLOCK_API_KEY`) and click-handler behavior unchanged.
- Avoid the widget getting stuck displaying stale state if the SSE connection drops.

**Non-Goals:**
- Changing the ChillClock server's API surface or SSE payload format.
- Changing `onClick`/`onRightClick`/`onMiddleClick` semantics.

## Decisions

### Connection command
Use `curl -N -s -H "X-API-KEY: <key>" "<serverUrl>/events"` via `noctalia.runStream`. `-N` disables curl's output buffering, which is required for line-by-line SSE delivery to `onLine` as events arrive rather than in batches.

### SSE line parsing
SSE frames arrive as `data: <json>` lines (with blank separator lines and possible `:`-prefixed comment/heartbeat lines per the SSE spec). `onLine` is reused with the same `"text"`/`"class"` regex extraction as the current `/status` parser, applied to the JSON after stripping a `data: ` prefix. Lines that don't start with `data: ` (blanks, comments, other event types) are ignored.

### Single stream lifecycle
`noctalia.setUpdateInterval` is reduced from 250ms to a coarse interval (e.g. 5000ms) and repurposed as a watchdog rather than the primary update mechanism. `update()`:
1. If config isn't loaded yet, load it (as today).
2. If the stream hasn't been started yet, start it via `runStream` and record `streamStarted = true`.
3. Otherwise, do nothing — display updates now happen entirely inside `onLine`.

### Reconnect / liveness watchdog
Confirmed against the live server: `/events` broadcasts the full status payload continuously (~10/sec, every ~100ms) regardless of whether anything changed, so every received line doubles as a heartbeat — no separate heartbeat frame format to handle.

The Noctalia plugin docs don't document `os.time`/`os.clock` availability, so rather than depend on wall-clock time, the watchdog is tick-counter based: `onLine` increments an `eventsThisTick` counter, and `update()` (called every 3s via `setUpdateInterval`) checks that counter. If a full 3s tick passes with zero events (~30x the normal ~100ms cadence) — after a one-tick grace period following (re)connect — `update()` restarts the `runStream` connection.

## Risks / Trade-offs

- **[Risk]** `runStream` may not expose a "process exited" signal, so a dropped connection is only detected by the liveness watchdog → the bar can show stale state for up to the watchdog timeout window. **Mitigation**: at ~100ms event cadence, a 3s timeout is ~30x normal cadence, so false positives are unlikely while detection stays fast.
- **[Risk]** Restarting `runStream` to reconnect could leave a previous `curl` process running if it didn't actually exit (host capability only guarantees cleanup on script reload/widget removal). **Mitigation**: only attempt a restart after the liveness timeout fires; accept the small residual risk of an orphaned `curl` until the next script reload.

## Migration Plan

This is a personal Noctalia plugin (not a deployed service): bump `dhvtimer/plugin.toml` version, update `dhvtimer/README.md` to describe the SSE-based update flow, and reload the widget. Rollback is a plain git revert of `chillclock.luau` to restore the polling behavior.

## Open Questions

(none — resolved during implementation: see "Reconnect / liveness watchdog" above)
