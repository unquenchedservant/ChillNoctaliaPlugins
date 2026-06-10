## 1. JSON helpers

- [x] 1.1 Add `jsonProtect(s)` to `lyrics/lyrics_bar.luau`: `s:gsub("\\\\","\1"):gsub('\\"',"\2")` — replaces escaped backslashes and escaped quotes with placeholder bytes so any remaining `"` is a real JSON structural quote.
- [x] 1.2 Add `jsonUnescape(s)` to `lyrics/lyrics_bar.luau`: `jsonProtect(s):gsub("\\n","\n"):gsub("\\r",""):gsub("\1","\\"):gsub("\2",'"')` — decodes `\n`/`\r` (now unambiguous) then restores the placeholders to `\` and `"`.

## 2. Apply to existing call sites

- [x] 2.1 Reimplement `jsonStr(body, key)`: match `'"' .. key .. '":"(.-)"'` against `jsonProtect(body)`, then return `jsonUnescape(v)` on the captured value `v`.
- [x] 2.2 In `fetchLyrics()`, match `'"syncedLyrics":"(.-)"'` against `jsonProtect(body)` instead of the raw `body`.
- [x] 2.3 Replace the sequential `gsub("\\n",...):gsub("\\r",...):gsub('\\"',...):gsub("\\\\",...)` chain on the extracted `raw` value with `jsonUnescape(raw)`.

## 3. Verification

- [x] 3.1 Manually test with a song whose synced lyrics contain an escaped quote (e.g. via a crafted lrclib.net response or a real song with quoted lyrics) and confirm the full lyric set displays and advances correctly. — Verified the extraction/unescape logic with a standalone Lua test using a crafted `syncedLyrics` body containing `\"hi\"`; full multi-line value extracts and decodes correctly.
- [x] 3.2 Manually test with a lyric line containing a literal backslash followed by `n` and confirm it renders as `\n` text, not a line break. — Verified via standalone Lua test: `Test\\nLiteral` (JSON-encoded literal backslash+`n`) decodes to `Test\nLiteral` (literal backslash + letter n), not a newline.
- [x] 3.3 Confirm normal (non-backslash) lyrics still display and sync correctly (regression check). — Verified via standalone Lua test with a normal two-line LRC body; decodes unchanged.

Note: the above were verified by extracting the new `jsonProtect`/`jsonUnescape`/`jsonStr` functions into a standalone Lua 5.1 script and running representative inputs through them (all 6 cases passed, including an extra trailing-escaped-backslash edge case). End-to-end testing inside Noctalia with a live Cider/lrclib session was not performed.
