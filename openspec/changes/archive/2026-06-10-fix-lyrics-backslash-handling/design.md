## Context

`lyrics/lyrics_bar.luau` extracts string values out of raw JSON responses (from lrclib.net and Cider's local API) using Lua patterns rather than a real JSON parser, since Luau's sandbox here has no JSON library. Two helpers do this:

- `jsonStr(body, key)` — extracts `name`/`artistName`/`albumName` from Cider's `now-playing` response.
- The inline `body:match('"syncedLyrics":"(.-)"')` in `fetchLyrics()` — extracts the lyrics blob from lrclib.net's response.

Both then unescape JSON string escapes via a chain of independent `gsub` calls: `\n` → newline, `\r` → "", `\"` → `"`, `\\` → `\`.

This breaks whenever the underlying value contains a backslash:

1. **Extraction**: `"(.-)"` is a non-greedy match that stops at the *first* literal `"` byte. A `\"` (escaped quote) inside the JSON value contains a literal `"` byte, so extraction truncates right after it — losing the rest of the lyrics.
2. **Unescaping**: applying `\n`/`\r`/`\"`/`\\` replacements as separate sequential passes is not equivalent to a single left-to-right scan. E.g. a literal backslash immediately followed by the letter `n` (JSON-encoded as `\\n`, three raw bytes `\`, `\`, `n`) gets the *first* `gsub("\\n","\n")` pass matching the second `\` + `n` and turning it into an unintended newline, instead of collapsing to a literal `\n` (backslash + letter n).

## Goals / Non-Goals

**Goals:**
- Correctly extract JSON string field values even when they contain `\"` (escaped quotes).
- Correctly unescape `\"`, `\\`, `\n`, `\r` in a single left-to-right pass so escape pairs are never double-processed or mis-ordered.
- Keep the fix self-contained in `lyrics/lyrics_bar.luau` with no new dependencies (Luau sandbox has no `json` library available).

**Non-Goals:**
- Full RFC 8259 JSON parsing (e.g. `\uXXXX` unicode escapes, arbitrary nesting). Lyrics/metadata fields are flat strings; only the escapes lrclib.net/Cider actually emit (`\"`, `\\`, `\n`, `\r`, `\t`) need handling.
- Changing the Cider/lrclib.net request logic, caching, or LRC parsing (`parseLrc`) — only the extraction/unescape step changes.

## Decisions

- **Protect escape pairs with placeholder bytes before extracting**: Add `jsonProtect(s)`, which runs two `gsub` passes over the *whole* body: first `\\` (escaped backslash, 2 bytes) → `\1`, then `\"` (escaped quote, 2 bytes) → `\2`. Doing `\\` first means a 4-byte `\\\"` sequence (escaped backslash + escaped quote) becomes `\1\2` correctly, and a 3-byte `\\"` sequence (escaped backslash immediately followed by the real closing quote) becomes `\1"` — the real `"` survives as the boundary. After this pass, every literal `"` byte remaining in the body is a genuine JSON structural quote, so the existing `"<key>":"(.-)"` pattern correctly finds the value's true end even when the value contains `\"`.
- **Unescape `\n`/`\r` after protecting, then restore placeholders**: Once `\\` and `\"` are replaced by placeholders, any `\` byte still in the value can only be part of a `\n` or `\r` escape (never part of `\\` or `\"`), so `gsub("\\n","\n"):gsub("\\r","")` is now unambiguous and safe. A final `gsub("\1","\\"):gsub("\2",'"')` restores the protected bytes to literal `\` and `"`. `jsonUnescape(s) = jsonProtect(s):gsub("\\n","\n"):gsub("\\r",""):gsub("\1","\\"):gsub("\2",'"')`.
- **`jsonUnescape` is idempotent w.r.t. `jsonProtect`, so one function covers both call sites**: `jsonProtect` only matches *raw* `\\` and `\"` pairs. A string that's already been through `jsonProtect` (e.g. the substring captured from `jsonProtect(body):match(...)`) contains no such pairs anymore (only placeholders and possibly `\n`/`\r`), so re-running `jsonProtect` on it is a no-op. That means `jsonUnescape(captured_value)` gives the correct final text whether `captured_value` came from a protected or unprotected body — no need for two different "finishing" functions or a documented contract about which form a value is in.
- **All `gsub`, no manual loop**: Both `jsonProtect` and `jsonUnescape` are pure `gsub` chains over the full string — same style as the existing code, just reordered/extended, and still O(n) C-level string operations rather than a Lua-level character-by-character loop.
- **Shared helpers**: `jsonProtect`/`jsonUnescape` are small local functions used by `jsonStr()` and by the `syncedLyrics` path in `fetchLyrics()`, so the fix applies uniformly and isn't duplicated. (`jsonStr()` values won't contain `\n`/`\r` in practice, but decoding them is harmless.)

## Risks / Trade-offs

- [Placeholder bytes `\1`/`\2` (0x01/0x02) could in theory collide with real content] → The JSON spec requires control characters (0x00–0x1F) to be escaped as `\uXXXX` in valid JSON strings, so raw 0x01/0x02 bytes won't appear in a real lrclib.net or Cider response body.
- [Two extra whole-body `gsub` passes for protection] → Lyrics/metadata payloads are small (single JSON objects), and this runs at most once per song change, so the cost is negligible — and it's still cheaper than a Lua-level scan.
