## Why

The lyrics bar currently treats Cider as the permanent primary source: if Cider's
`/now-playing` returns *any* cached track (even one it finished or paused long ago),
the widget displays Cider's lyrics and never checks `playerctl` — even while another
app (Spotify, a browser tab, etc.) is actively playing a different song. Users who
switch away from Cider to another MPRIS player see stale Cider lyrics instead of the
song that's actually playing.

## What Changes

- Source selection now prefers whichever backend (Cider or playerctl/MPRIS) is
  **actively `Playing`**, instead of always preferring Cider when it has any cached
  track.
- If neither backend is actively playing, the widget keeps showing whichever source
  was active last (sticky), as long as that source still has a track loaded — falling
  back to Cider-first, then playerctl, then empty, only once the previously-active
  source's track disappears entirely. This preserves the existing "Cider takes
  priority" tiebreak for the idle/paused case while preventing per-tick flicker
  between two paused sources.
- When the active source switches to a different song, the existing `fetchLyrics`
  reset (clears `lyrics`, `lastLyric`, sets `isLoading`) and `fetchedFor` staleness
  check are relied on to avoid showing the previous source's lyric line and to
  discard any in-flight lyric fetch for the song that's no longer active. This change
  adds explicit verification/test coverage for that race now that source switches can
  happen mid-playback (previously Cider's priority made this rare).

## Capabilities

### Modified Capabilities
- `lyrics-bar`: source-selection logic (Cider vs. playerctl/MPRIS) changes from
  "Cider wins whenever it has cached track data" to "whichever backend is actively
  Playing wins, with sticky idle/paused tiebreaking"; adds a requirement that
  switching the active source/song does not display a stale lyric line or apply a
  stale in-flight lyrics fetch from the previously-active source.

## Impact

- `lyrics/lyrics_bar.luau`: `update()`, `updateFromCider()`, `updateFromPlayerctl()`,
  and `processTrack()` — source-selection and state-handoff logic.
- `lyrics/README.md`: "Cider support" / "How it works" sections need updating to
  describe the new priority rule.
