## 1. Normalize backend query helpers

- [x] 1.1 Replace `updateFromCider(nowPlayingBody)` with `queryCider(callback)`: keep the existing `/now-playing` + `/is-playing` curl chain, but instead of calling `processTrack` directly, invoke `callback(result)` where `result` is `nil` (no usable track) or `{hasTrack, isPlaying, title, artist, album, length, pos}`.
- [x] 1.2 Replace `updateFromPlayerctl()` with `queryPlayerctl(callback)`: keep the existing single playerctl call, but instead of calling `processTrack` directly, invoke `callback(result)` where `result` is `nil` (empty/unparseable output) or `{hasTrack, isPlaying, status, player, title, artist, album, length, pos}` (`hasTrack = title ~= ""`, `isPlaying = status == "Playing"`).

## 2. Source selection

- [x] 2.1 Implement `pickActive(cider, pctl)` per design.md's priority rules: (1) `cider.isPlaying` → `"cider"`; (2) else `pctl.isPlaying` → `pctl.player`; (3) else sticky tiebreak using `cur.player` (stay on Cider if `cur.player == "cider"` and `cider.hasTrack`; stay on playerctl if `cur.player == pctl.player` and `pctl.hasTrack`); (4) else `cider.hasTrack` → `"cider"`; (5) else `pctl.hasTrack` → `pctl.player`; (6) else `nil`.
- [x] 2.2 Implement `applyChoice(choice, cider, pctl)`: if `choice == nil`, call `showEmpty()`; otherwise derive `status` (`"Playing"` if the chosen result's `isPlaying`, else `"Paused"`) and call `processTrack(status, player, artist, title, album, length, pos)` using the chosen result's fields.

## 3. Rewrite update()

- [x] 3.1 Rewrite `update()`: after the existing Cider-key load step, call `queryCider(...)`. If `cider ~= nil and cider.isPlaying`, call `applyChoice("cider", cider, nil)` directly without querying playerctl. Otherwise call `queryPlayerctl(...)` and then `applyChoice(pickActive(cider, pctl), cider, pctl)`.
- [x] 3.2 Audit all branches of the rewritten `update()` to ensure `busy = false` is set exactly once on every path (Cider-playing shortcut, Cider-not-playing + playerctl path, and the existing Cider-key-load path).

## 4. Documentation

- [x] 4.1 Update `lyrics/README.md` ("Cider support" and "How it works" sections) to describe the new selection rule: the actively-`Playing` backend wins; if neither is playing, the previously-active source stays shown while paused, falling back to Cider, then playerctl, then empty.

## 5. Verification

- [x] 5.1 Manually verify: Cider has an old track loaded but `is_playing: false`, and `playerctl` reports a different player as `Playing` — the bar shows that player's lyrics, not Cider's. — Verified via standalone Lua harness (`pickActive`/`applyChoice` extracted from `lyrics_bar.luau`): given a paused Cider result and a Playing playerctl result, the playerctl track is selected and rendered.
- [x] 5.2 Manually verify: Cider is actively `Playing` — the bar shows Cider's lyrics regardless of what `playerctl` reports. — Verified: `update()`'s shortcut (`cider.isPlaying` → `applyChoice("cider", cider, nil)`) renders Cider's track without consulting playerctl.
- [x] 5.3 Manually verify: the active playerctl player is paused while Cider still has an old paused track loaded — the bar keeps showing the playerctl player's last lyric line (sticky), not Cider's. — Verified: with `cur.player` set to the playerctl player from the prior cycle, `pickActive` returns that player (not Cider) when both are paused/idle; also verified the fallback to Cider once that player's track disappears entirely.
- [x] 5.4 Manually verify: when the active source switches to a different song, the bar immediately shows the loading indicator (or hides per `hide_when_empty`), with no stale lyric line from the previous source. — Verified: `processTrack` for the new song synchronously resets `lyrics`/`lastLyric`/`fetchedFor` and sets `isLoading`, so the same render shows `"..."` instead of the previous song's lyric.
- [x] 5.5 Manually verify: trigger a source/song switch while a lyrics fetch for the previous song is still in flight, and confirm the late response does not overwrite the new song's displayed lyrics. — Found and fixed a related bug while verifying this: the fetch callback cleared `isLoading` *before* checking staleness, so a late response for the previous song would clear `isLoading` for the new song's still-in-flight fetch (briefly showing an empty bar instead of `"..."`). Fixed by moving the staleness check before `isLoading = false` in `fetchLyrics`. Re-verified with the harness: a stale Song A response no longer affects Song B's `isLoading`/`lyrics`, and the bar continues showing `"..."` until Song B's own fetch resolves.

Note: verified with a standalone Lua 5.1 harness (`/tmp/test_player_switch.lua`, 17/17 assertions pass) that copies `pickActive`, `applyChoice`, `processTrack`, and `fetchLyrics` out of `lyrics/lyrics_bar.luau` with stubbed `noctalia`/`barWidget`. End-to-end testing inside Noctalia with live Cider + a second MPRIS player was not performed.
