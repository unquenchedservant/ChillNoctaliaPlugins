## Context

`update()` currently does:

```lua
query Cider /now-playing
if body has status:"ok" and name != "":
    updateFromCider(body)   -- queries /is-playing, sets status Playing/Paused
else:
    updateFromPlayerctl()
```

Cider "wins" as soon as it has *any* cached `now-playing` payload, even if
`/is-playing` reports `false` because the user closed/paused Cider ages ago and is
now actively listening to something else via MPRIS (Spotify, a browser tab, etc.).
`playerctl` is never consulted in that case, so the bar shows Cider's stale lyric.

`cur.player`, `fetchedFor` (title/artist of the last lyrics request), and the
synchronous reset inside `fetchLyrics()` (`isLoading=true; lastLyric=""; lyrics={}`)
already exist and already correctly prevent a stale lyric line / stale fetch response
from leaking across a *song* change, regardless of which backend reports it. This
design reuses that mechanism rather than replacing it.

## Goals / Non-Goals

**Goals:**
- Whichever backend (Cider or playerctl/MPRIS) is actively `Playing` becomes the
  active source, even if the other backend also has cached/loaded track data.
- When neither backend is actively `Playing`, avoid flicker by sticking with the
  previously-active source as long as it still has a track loaded.
- Preserve the existing documented tiebreak ("Cider takes priority") for the
  first-run / both-idle / sticky-source-gone cases.
- Verify (and cover with test scenarios) that switching the active source mid-song
  does not display a stale lyric line and does not let a stale in-flight lyrics
  fetch from the previous source overwrite the new song's lyrics.

**Non-Goals:**
- Selecting among *multiple simultaneous* MPRIS players — `playerctl` (without `-p`)
  still returns whatever single player it considers active; this change does not add
  per-player enumeration/selection within the MPRIS side.
- New configuration options or UI changes.
- Changing lyrics-fetch source (lrclib.net) or LRC parsing.

## Decisions

### 1. Sequential query order: Cider first, playerctl only if Cider isn't actively playing

`update()` queries Cider's `/now-playing` + `/is-playing` first (as today). If
`is_playing == true`, Cider is the active source and `playerctl` is not queried —
this is the steady-state path when Cider is the user's player and stays cheap (one
round trip).

If Cider is *not* actively playing (no track, or a loaded-but-paused track), `update()`
additionally queries `playerctl`. Both results are now available before deciding.

**Alternative considered**: query both backends in parallel every cycle. Rejected —
adds an extra subprocess call on every tick even in the common case (Cider actively
playing), for no behavioral benefit, and requires join/synchronization logic for two
independent `noctalia.runAsync` callbacks.

### 2. Source-selection priority

Given `cider = {hasTrack, isPlaying, title, artist, album, length, pos}` and
`pctl = {hasTrack, isPlaying, status, player, title, artist, album, length, pos}`
(either may be "empty"/nil if the backend has nothing):

1. If `cider.isPlaying` → active source = Cider.
2. Else if `pctl.isPlaying` → active source = playerctl/`pctl.player`.
3. Else (neither actively playing) — **sticky tiebreak**:
   - If `cur.player == "cider"` and `cider.hasTrack` → stay on Cider (Paused).
   - Else if `cur.player == pctl.player` and `pctl.hasTrack` → stay on playerctl (Paused).
   - Else if `cider.hasTrack` → Cider (Paused) — preserves documented Cider-priority default.
   - Else if `pctl.hasTrack` → playerctl (Paused).
   - Else → `showEmpty()`.

This is a pure function of the two query results plus `cur.player`; no extra state is
introduced beyond what already exists.

**Alternative considered**: always prefer Cider when both are idle/paused, with no
stickiness. Rejected — if the user pauses Spotify (after it had been the active
source) while Cider still has an old paused track loaded, this would flip the bar
back to Cider's old song every tick, which is more disruptive than staying on the
just-paused song.

### 3. Reuse existing reset/staleness mechanism for source switches

When the resolved active source's `(title, artist)` differs from `fetchedFor`,
`processTrack()` already calls `fetchLyrics()`, which synchronously sets
`isLoading = true`, `lastLyric = ""`, `lyrics = {}` and updates `fetchedFor` *before*
the async `curl` fires. The subsequent "Playing" branch in the same `processTrack`
call sees `isLoading == true` and renders `"..."` — no stale line from the old source
is shown. Any in-flight fetch for the previous song is discarded by the existing
`forTitle/forArtist ~= fetchedFor` check in `fetchLyrics`'s callback.

No code changes are needed for this mechanism itself; this design only adds explicit
test scenarios (since source switches were previously rare/impossible while Cider had
unconditional priority, this path was effectively untested).

## Risks / Trade-offs

- **[Risk]** Extra `playerctl` subprocess call on every cycle where Cider isn't
  actively playing (e.g. Cider closed entirely) → **Mitigation**: `playerctl` is a
  fast local call; this matches the call volume of the *current* fallback path
  (today it's called whenever Cider has no usable now-playing data), so steady-state
  cost is unchanged — only the "Cider paused with stale track" case now also calls
  `playerctl`.
- **[Risk]** If both Cider and an MPRIS player are simultaneously `Playing` (unusual
  dual-playback), Cider always wins per rule 1 — unchanged from current documented
  behavior, but now reachable in more situations since playerctl is queried more
  often → **Mitigation**: document this tiebreak explicitly in `lyrics/README.md`.
- **[Risk]** Sticky tiebreak (rule 3) could keep showing a long-paused source
  indefinitely if its track metadata never clears → **Mitigation**: identical to
  today's behavior for Cider; users who don't want paused lyrics already have
  `hide_when_paused`.

## Migration Plan

Pure logic change confined to `lyrics/lyrics_bar.luau` (`update`, `updateFromCider`,
`updateFromPlayerctl`, `processTrack`) plus a documentation update in
`lyrics/README.md`. No config schema changes, no data migration. Users pick up the
change on next plugin reload.
