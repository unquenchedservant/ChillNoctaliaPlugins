## ADDED Requirements

### Requirement: Active Source Selection Prefers an Actively Playing Backend
The widget SHALL choose its active playback source (Cider's local API vs.
playerctl/MPRIS) by preferring whichever backend reports `Playing` status, rather
than always preferring Cider whenever Cider has any cached now-playing data.

#### Scenario: Cider paused with a stale track, another player actively playing
- **WHEN** Cider's `/now-playing` returns a cached track but `/is-playing` reports
  `false`, and `playerctl` reports a different player with status `Playing`
- **THEN** the widget treats the `playerctl` player as the active source and displays
  lyrics for its track, not Cider's cached track

#### Scenario: Cider actively playing
- **WHEN** Cider's `/is-playing` reports `true`
- **THEN** the widget treats Cider as the active source regardless of what
  `playerctl` reports

### Requirement: Sticky Source Selection When Nothing Is Actively Playing
When neither Cider nor playerctl reports `Playing` status, the widget SHALL continue
displaying the previously-active source as long as that source still has a track
loaded, falling back to Cider (if it has a loaded track), then playerctl (if it has a
loaded track), then an empty state, only once the previously-active source's track is
no longer present.

#### Scenario: Previously-active playerctl source is paused while Cider still has an old track loaded
- **WHEN** the active source was a playerctl player showing track B, that player is
  now `Paused` (not `Playing`), and Cider's `/now-playing` still reports its old
  track A with `is_playing: false`
- **THEN** the widget continues displaying track B's last lyric line (Paused display)
  rather than switching back to track A

#### Scenario: Previously-active source's track disappears entirely
- **WHEN** the previously-active source no longer reports any loaded track, and
  neither backend is `Playing`
- **THEN** the widget falls back to Cider's loaded track if present, otherwise
  playerctl's loaded track if present, otherwise hides/clears the bar per
  `hide_when_empty`

### Requirement: Switching the Active Source Does Not Display Stale Lyrics
When the active source switches to a different song (different title/artist than the
last one lyrics were fetched for), the widget SHALL NOT display a lyric line from the
previous source's song, and SHALL discard any in-flight lyrics fetch response that was
requested for the previous source's song.

#### Scenario: Source switch triggers immediate lyric reset
- **WHEN** the active source switches from song A (with a currently displayed lyric
  line) to song B with a different title/artist
- **THEN** on the same update cycle the bar shows the loading indicator (or is hidden
  per `hide_when_empty` if applicable) instead of song A's last lyric line

#### Scenario: In-flight fetch for the previous song completes after the switch
- **WHEN** a lyrics fetch for song A is still in flight at the moment the active
  source switches to song B, and that fetch later completes
- **THEN** song A's fetch response does not overwrite the lyrics or displayed line
  for song B
