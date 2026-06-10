-- Noctalia Bar Widget: Synced Lyrics
-- Polls playerctl every 500ms, fetches LRC lyrics from lrclib.net,
-- and displays the current line in the bar.

noctalia.setUpdateInterval(500)

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

    noctalia.runAsync("curl -sf --max-time 10 '" .. url .. "'", function(out)
        -- Discard if a newer song started; otherwise always clear isLoading
        isLoading = false
        if forTitle ~= fetchedFor.title or forArtist ~= fetchedFor.artist then return end
        local body = type(out) == "table" and (out.stdout or "") or (out or "")
        if body == "" then return end
        -- Bail on missing/null/empty syncedLyrics field
        if body:find('"syncedLyrics":null') or body:find('"syncedLyrics":""') then return end
        -- Extract string value — safe for typical lyrics (no embedded quotes)
        local raw = body:match('"syncedLyrics":"(.-)"')
        if not raw or raw == "" then return end
        -- Unescape JSON string escapes (\n → newline, etc.)
        raw = raw:gsub("\\n", "\n"):gsub("\\r", ""):gsub('\\"', '"'):gsub("\\\\", "\\")
        lyrics = parseLrc(raw)
    end, 15000)
end

-- ── Update loop ───────────────────────────────────────────────────────────────

function update()
    if busy then return end
    busy = true

    -- One playerctl call gives us status, player, metadata, AND current position.
    -- mpris:length and position are both in microseconds (MPRIS spec).
    noctalia.runAsync(
        "playerctl metadata --format '{{ status }}:::{{ playerName }}:::{{ xesam:artist }}:::{{ xesam:title }}:::{{ xesam:album }}:::{{ mpris:length }}:::{{ position }}'",
        function(out)
            busy = false
            local text = type(out) == "table" and (out.stdout or "") or (out or "")
            local hideEmpty  = barWidget.getConfig("hide_when_empty")
            local hidePaused = barWidget.getConfig("hide_when_paused")

            -- No active player
            if trim(text) == "" then
                cur.status = "Stopped"
                barWidget.setVisible(not hideEmpty)
                barWidget.setText("")
                return
            end

            local p      = split(trim(text), ":::")
            local status = trim(p[1] or "")
            local player = trim(p[2] or "")
            local artist = trim(p[3] or "")
            local title  = trim(p[4] or "")
            local album  = trim(p[5] or "")
            local length = (tonumber(p[6]) or 0) / 1e6   -- μs → seconds
            position     = (tonumber(p[7]) or 0) / 1e6   -- μs → seconds

            cur.status = status; cur.player = player; cur.artist = artist
            cur.title  = title;  cur.album  = album;  cur.length = length

            -- Compare against fetchedFor, not cur — so a song seen while Paused
            -- still triggers a fetch once the player is Playing again
            if status == "Playing" and title ~= "" and artist ~= "" then
                if title ~= fetchedFor.title or artist ~= fetchedFor.artist then
                    fetchedFor.title  = title
                    fetchedFor.artist = artist
                    fetchLyrics(title, artist, album, length)
                end
            end

            -- ── Stopped ──────────────────────────────────────────────────────
            if status == "Stopped" or status == "" then
                barWidget.setVisible(not hideEmpty)
                barWidget.setText("")
                return
            end

            -- ── Paused ───────────────────────────────────────────────────────
            if status == "Paused" then
                if hidePaused then
                    barWidget.setVisible(false)
                    return
                end
                barWidget.setVisible(true)
                barWidget.setText(lastLyric)
                return
            end

            -- ── Playing ──────────────────────────────────────────────────────
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
    )
end
