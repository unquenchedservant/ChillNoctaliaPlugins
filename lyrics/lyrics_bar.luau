-- Noctalia Bar Widget: Synced Lyrics
-- Polls Cider's local API (if running) or playerctl every 500ms,
-- fetches LRC lyrics from lrclib.net, and displays the current line in the bar.

noctalia.setUpdateInterval(500)

local home = noctalia.getenv("HOME")

-- ── State ──────────────────────────────────────────────────────────────────────
local cur = {
    title = "", artist = "", album = "",
    player = "", status = "Stopped", length = 0,
}
local position   = 0.0
local lyrics     = {}   -- { time: number (seconds), lyric: string }[]
local lastLyric  = ""
local isLoading  = false
local busy       = false  -- guard: skip update() if previous call still pending
local fetchedFor = { title = "", artist = "" }  -- what song we last requested lyrics for

local ciderKey = nil  -- nil = not yet loaded from ~/.config/ChillNoctaliaPlugins/.env

-- ── Utilities ─────────────────────────────────────────────────────────────────

local function split(s, sep)
    local t, pos = {}, 1
    while true do
        local a, b = s:find(sep, pos, true)
        if not a then t[#t+1] = s:sub(pos); break end
        t[#t+1] = s:sub(pos, a - 1)
        pos = b + 1
    end
    return t
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function asString(out)
    return type(out) == "table" and (out.stdout or "") or (out or "")
end

-- Wrap a string in single quotes for safe use as a shell argument
local function shellQuote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- Protect JSON-escaped backslashes and quotes with placeholder bytes so that
-- (1) a "(.-)" extraction below doesn't stop early at a \" inside a value, and
-- (2) any "\" left afterwards can only be part of a \n or \r escape.
local function jsonProtect(s)
    return (s:gsub("\\\\", "\1"):gsub('\\"', "\2"))
end

-- Decode a JSON string value (protected or not): unescape \n/\r, then restore
-- the placeholder bytes to literal \ and ". Re-running jsonProtect here is a
-- no-op if the value is already protected, since no raw \\ or \" remain.
local function jsonUnescape(s)
    return (jsonProtect(s):gsub("\\n", "\n"):gsub("\\r", ""):gsub("\1", "\\"):gsub("\2", '"'))
end

-- Extract a JSON string field, correctly handling \" and \\ inside the value
local function jsonStr(body, key)
    local v = jsonProtect(body):match('"' .. key .. '":"(.-)"')
    if not v then return "" end
    return jsonUnescape(v)
end

local function jsonNum(body, key)
    return tonumber(body:match('"' .. key .. '":(-?[%d%.]+)')) or 0
end

local function jsonBool(body, key)
    return body:match('"' .. key .. '":(%a+)') == "true"
end

-- Binary search: largest i where lyrics[i].time <= pos (1-based).
-- Returns 0 before first lyric, nil on error, #lyrics if past end.
local function findLyricIndex(pos)
    local n = #lyrics
    if n < 2 then return nil end
    if pos < lyrics[1].time then return 0 end
    if pos >= lyrics[n].time then return n end
    local s, c = 1, n
    while c > 1 do
        local h = math.floor(c / 2)
        if pos < lyrics[s + h].time then
            c = h
        else
            c = c - h
            s = s + h
        end
    end
    return s
end

-- Parse LRC format: "[mm:ss.xx] text\n..." → sorted {time, lyric}[]
local function parseLrc(text)
    local result = {}
    for ts, line in text:gmatch("%[(%d+:%d+%.%d+)%]([^\n]*)\n?") do
        local mm, ss = ts:match("(%d+):(%d+%.%d+)")
        if mm and ss then
            result[#result+1] = {
                time  = tonumber(mm) * 60 + tonumber(ss),
                lyric = trim(line),
            }
        end
    end
    table.sort(result, function(a, b) return a.time < b.time end)
    return result
end

-- ── Config ────────────────────────────────────────────────────────────────────

local function loadCiderKey(callback)
    noctalia.runAsync(
        'grep -m1 "^CIDER_KEY=" ' .. home .. '/.config/ChillNoctaliaPlugins/.env 2>/dev/null | cut -d= -f2',
        function(out)
            ciderKey = trim(asString(out))
            callback()
        end
    )
end

-- ── Lyrics fetch ──────────────────────────────────────────────────────────────

local function fetchLyrics(title, artist, album, length)
    isLoading = true
    lastLyric = ""
    lyrics    = {}
    -- Snapshot at call time so the callback can detect if it's gone stale
    local forTitle  = title
    local forArtist = artist

    local function enc(s)
        -- Match QML plugin: spaces → +, full-width comma → ASCII comma
        return (s:gsub(" ", "+"):gsub("，", ","))
    end

    local url = ("https://lrclib.net/api/get?track_name=%s&artist_name=%s&album_name=%s&duration=%d")
        :format(enc(title), enc(artist), enc(album), math.floor(length))

    noctalia.runAsync("curl -sf --max-time 10 " .. shellQuote(url), function(out)
        -- Discard if a newer song started; otherwise always clear isLoading
        isLoading = false
        if forTitle ~= fetchedFor.title or forArtist ~= fetchedFor.artist then return end
        local body = asString(out)
        if body == "" then return end
        -- Bail on missing/null/empty syncedLyrics field
        if body:find('"syncedLyrics":null') or body:find('"syncedLyrics":""') then return end
        -- Extract string value, correctly handling \" and \\ inside the value
        local raw = jsonProtect(body):match('"syncedLyrics":"(.-)"')
        if not raw or raw == "" then return end
        -- Unescape JSON string escapes (\n → newline, \", \\, etc.)
        raw = jsonUnescape(raw)
        lyrics = parseLrc(raw)
    end, 15000)
end

-- ── Shared track-state handling ──────────────────────────────────────────────
-- status is one of "Playing", "Paused", "Stopped"

local function processTrack(status, player, artist, title, album, length, pos)
    local hideEmpty  = barWidget.getConfig("hide_when_empty")
    local hidePaused = barWidget.getConfig("hide_when_paused")

    cur.status = status; cur.player = player; cur.artist = artist
    cur.title  = title;  cur.album  = album;  cur.length = length
    position   = pos

    -- Compare against fetchedFor, not cur — so a song seen while Paused
    -- still triggers a fetch once the player is Playing again
    if status == "Playing" and title ~= "" and artist ~= "" then
        if title ~= fetchedFor.title or artist ~= fetchedFor.artist then
            fetchedFor.title  = title
            fetchedFor.artist = artist
            fetchLyrics(title, artist, album, length)
        end
    end

    -- ── Stopped ──────────────────────────────────────────────────────────
    if status == "Stopped" or status == "" then
        barWidget.setVisible(not hideEmpty)
        barWidget.setText("")
        return
    end

    -- ── Paused ───────────────────────────────────────────────────────────
    if status == "Paused" then
        if hidePaused then
            barWidget.setVisible(false)
            return
        end
        barWidget.setVisible(true)
        barWidget.setText(lastLyric)
        return
    end

    -- ── Playing ──────────────────────────────────────────────────────────
    barWidget.setVisible(true)

    if isLoading then
        barWidget.setText("...")
        return
    end

    if #lyrics == 0 then
        barWidget.setVisible(not hideEmpty)
        barWidget.setText("")
        return
    end

    -- Advance to the lyric line matching current playback position
    local idx = findLyricIndex(position)
    if idx and idx > 0 then
        lastLyric = lyrics[idx].lyric or ""
    elseif idx == 0 then
        lastLyric = ""
    end

    barWidget.setText(lastLyric)
end

local function showEmpty()
    cur.status = "Stopped"
    barWidget.setVisible(not barWidget.getConfig("hide_when_empty"))
    barWidget.setText("")
end

-- ── playerctl (MPRIS) backend ────────────────────────────────────────────────

-- Query playerctl and report its result via callback(result), where result is
-- nil (no player/metadata) or {hasTrack, isPlaying, status, player, artist,
-- title, album, length, pos}. Does not touch display state directly.
local function queryPlayerctl(callback)
    -- One playerctl call gives us status, player, metadata, AND current position.
    -- mpris:length and position are both in microseconds (MPRIS spec).
    noctalia.runAsync(
        "playerctl metadata --format '{{ status }}:::{{ playerName }}:::{{ xesam:artist }}:::{{ xesam:title }}:::{{ xesam:album }}:::{{ mpris:length }}:::{{ position }}'",
        function(out)
            local text = asString(out)

            if trim(text) == "" then
                callback(nil)
                return
            end

            local p      = split(trim(text), ":::")
            local status = trim(p[1] or "")
            local player = trim(p[2] or "")
            local artist = trim(p[3] or "")
            local title  = trim(p[4] or "")
            local album  = trim(p[5] or "")
            local length = (tonumber(p[6]) or 0) / 1e6   -- μs → seconds
            local pos    = (tonumber(p[7]) or 0) / 1e6   -- μs → seconds

            callback({
                -- "Stopped" players sometimes still report stale metadata; treat
                -- that as no track, matching the previous hide-the-bar behavior.
                hasTrack  = title ~= "" and (status == "Playing" or status == "Paused"),
                isPlaying = status == "Playing",
                status    = status,
                player    = player,
                artist    = artist,
                title     = title,
                album     = album,
                length    = length,
                pos       = pos,
            })
        end
    )
end

-- ── Cider local API backend ──────────────────────────────────────────────────

local CIDER_BASE = "http://127.0.0.1:10767/api/v1/playback"

local function ciderCurl(path)
    local hdr = ciderKey ~= "" and (" -H " .. shellQuote("apptoken: " .. ciderKey)) or ""
    return ("curl -sf --max-time 2%s %s"):format(hdr, shellQuote(CIDER_BASE .. path))
end

-- Query Cider's local API and report its result via callback(result), where
-- result is nil (nothing loaded) or {hasTrack, isPlaying, player, artist,
-- title, album, length, pos}. Does not touch display state directly.
local function queryCider(callback)
    noctalia.runAsync(ciderCurl("/now-playing"), function(out)
        local body = asString(out)
        if body == "" or not body:find('"status":"ok"') or jsonStr(body, "name") == "" then
            callback(nil)
            return
        end

        local title  = jsonStr(body, "name")
        local artist = jsonStr(body, "artistName")
        local album  = jsonStr(body, "albumName")
        local length = jsonNum(body, "durationInMillis") / 1000
        local pos    = jsonNum(body, "currentPlaybackTime")

        noctalia.runAsync(ciderCurl("/is-playing"), function(out2)
            callback({
                hasTrack  = true,
                isPlaying = jsonBool(asString(out2), "is_playing"),
                player    = "cider",
                artist    = artist,
                title     = title,
                album     = album,
                length    = length,
                pos       = pos,
            })
        end)
    end)
end

-- ── Source selection ─────────────────────────────────────────────────────────

-- Pick the active source given this cycle's Cider/playerctl results (either may
-- be nil). Prefers whichever backend is actively Playing; if neither is, sticks
-- with the previously-active source (cur.player) while it still has a track
-- loaded, then falls back to Cider, then playerctl, then nothing.
local function pickActive(cider, pctl)
    if cider and cider.isPlaying then return "cider" end
    if pctl and pctl.isPlaying then return pctl.player end

    if cider and cider.hasTrack and cur.player == "cider" then return "cider" end
    if pctl and pctl.hasTrack and cur.player == pctl.player then return pctl.player end

    if cider and cider.hasTrack then return "cider" end
    if pctl and pctl.hasTrack then return pctl.player end

    return nil
end

-- Render the chosen source's track, or clear the bar if nothing is active.
local function applyChoice(choice, cider, pctl)
    if choice == nil then
        showEmpty()
        return
    end

    local r      = (choice == "cider") and cider or pctl
    local status = r.isPlaying and "Playing" or "Paused"
    processTrack(status, choice, r.artist, r.title, r.album, r.length, r.pos)
end

-- ── Update loop ───────────────────────────────────────────────────────────────

function update()
    if busy then return end
    busy = true

    if ciderKey == nil then
        loadCiderKey(function() busy = false; update() end)
        return
    end

    -- Cider is queried first; if it's actively playing it wins outright and
    -- playerctl isn't queried. Otherwise also check playerctl/MPRIS so an
    -- actively-playing MPRIS player can take over from an idle/paused Cider.
    queryCider(function(cider)
        if cider and cider.isPlaying then
            busy = false
            applyChoice("cider", cider, nil)
            return
        end

        queryPlayerctl(function(pctl)
            busy = false
            applyChoice(pickActive(cider, pctl), cider, pctl)
        end)
    end)
end
