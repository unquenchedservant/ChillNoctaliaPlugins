# Lyrics Bar

## Purpose

Synced lyrics bar widget for Noctalia. Polls Cider's local API (or playerctl/MPRIS as a fallback) for now-playing track metadata, fetches time-synced lyrics from lrclib.net, and displays the current line in the bar as playback advances.

## Requirements

### Requirement: JSON String Field Extraction Handles Escaped Quotes
When extracting a string field's value from a raw JSON response body (e.g. `syncedLyrics`, `name`, `artistName`, `albumName`), the widget SHALL find the true end of the value, treating any `\"` (escaped double-quote) inside the value as part of the value rather than as the closing quote.

#### Scenario: Synced lyrics contain an escaped quote
- **WHEN** the lrclib.net response's `syncedLyrics` value contains an escaped double-quote, e.g. `[00:01.00] She said \"hi\"\n[00:05.00] more lyrics`
- **THEN** the widget extracts the entire `syncedLyrics` value, including all lines after the escaped quote, without truncating at the embedded `\"`

#### Scenario: Cider track metadata contains an escaped quote
- **WHEN** Cider's `now-playing` response has a `name`, `artistName`, or `albumName` value containing an escaped double-quote
- **THEN** the widget extracts the full field value rather than truncating at the embedded `\"`

### Requirement: JSON Escape Sequences Decoded in a Single Pass
When decoding a raw JSON string value into display text, the widget SHALL decode `\"`, `\\`, `\n`, and `\r` escape sequences in a single left-to-right pass, so that a literal backslash adjacent to `n`, `r`, or `"` is not misinterpreted as part of a different escape sequence.

#### Scenario: Literal backslash followed by the letter "n"
- **WHEN** a JSON string value contains a literal backslash character immediately followed by the letter `n` (encoded in JSON as the three bytes `\`, `\`, `n`)
- **THEN** the decoded value contains a literal backslash followed by the letter `n`, and does not contain a newline character in its place

#### Scenario: Lyrics line with an escaped quote decodes correctly
- **WHEN** a `syncedLyrics` value contains `She said \"hi\"`
- **THEN** the decoded lyric line displayed in the bar reads `She said "hi"`
