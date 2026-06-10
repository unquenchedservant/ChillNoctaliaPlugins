## Why

The synced-lyrics bar widget breaks (lyrics get truncated or garbled) whenever the fetched lyrics text contains a backslash, most commonly when a line includes an escaped double-quote (`\"`) for quoted speech (e.g. `She said \"hi\"`). The current JSON string extraction uses a naive Lua pattern (`"(.-)"`,) that stops at the first literal `"` byte, including ones that are part of a `\"` escape sequence inside the value — so the captured text is cut off right after the escaped quote. The follow-up unescape step also applies `\n`, `\r`, `\"`, `\\` replacements as independent sequential `gsub` calls, which mishandles a literal backslash that happens to be followed by `n`, `r`, `"`, or `\`.

## What Changes

- Replace the `"(.-)"` pattern-based JSON string extraction with an escape-aware extractor that scans character-by-character, treating `\` + next-char as an atomic pair, so an embedded `\"` no longer terminates the value early.
- Replace the sequential `gsub("\\n",...):gsub("\\r",...):gsub('\\"',...):gsub("\\\\",...)` unescape chain with a single left-to-right pass that consumes `\X` pairs atomically, so a literal backslash followed by `n`/`r`/`"`/`\` is decoded correctly.
- Apply both fixes consistently to `jsonStr()` (used for Cider's `name`/`artistName`/`albumName`) and to the `syncedLyrics` extraction/unescape in `fetchLyrics()`.

## Capabilities

### New Capabilities
- `lyrics-bar`: Synced lyrics bar widget for Noctalia — polls Cider/playerctl for now-playing metadata, fetches time-synced lyrics from lrclib.net, and displays the current line, including correct handling of JSON string fields containing escaped quotes and backslashes.

### Modified Capabilities
(none — no existing specs cover this plugin yet)

## Impact

- `lyrics/lyrics_bar.luau`: `jsonStr()` helper and the `syncedLyrics` extraction/unescape logic inside `fetchLyrics()`.
- No changes to external APIs, dependencies, or the plugin manifest.
