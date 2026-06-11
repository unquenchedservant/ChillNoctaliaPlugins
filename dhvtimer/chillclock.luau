local COLORS = { green = "#69db7c", yellow = "#ffd43b", red = "#ff6b6b", white = "#ffffff" }
local home = noctalia.getenv("HOME")

local defaultTimer = barWidget.getConfig("default_timer")

-- Watchdog tick: /events normally delivers ~10 lines/sec, so a full tick
-- with zero lines (~30x the normal cadence) means the stream died.
noctalia.setUpdateInterval(3000)

local serverUrl = nil
local apiKey    = nil

local streamStarted    = false
local eventsThisTick   = 0
local graceTicks       = 0  -- skip the liveness check for this many ticks after (re)connect

local lastPhase       = nil
local lastActiveTimer = nil

local function curl(path, method)
    local m = method and ("-X " .. method) or ""
    return ('curl -s %s -H "X-API-KEY: %s" "%s%s"'):format(m, apiKey, serverUrl, path)
end

-- Apply a status payload (same shape as /status and each /events line) to the bar
local function applyStatus(body)
    local text  = body:match('"text":"([^"]+)"')
    local class = body:match('"class":"([^"]+)"')
    barWidget.setText(text or "0:00")
    barWidget.setColor(COLORS[class] or "#ffffff")

    local phase  = tonumber(body:match('"phase":(%d+)'))
    local temp   = body:match('"temp":(%d+)')
    local active = tonumber(body:match('"activeTimer":(%d+)'))

    if phase and active then
        if lastPhase == nil or active ~= lastActiveTimer then
            -- First event since (re)connect, or active timer changed: establish
            -- a new baseline without notifying.
            lastPhase = phase
            lastActiveTimer = active
        elseif phase > lastPhase then
            noctalia.notify("Phase " .. phase, (temp or "?") .. "°")
            lastPhase = phase
        elseif lastPhase == 4 and phase == 0 then
            noctalia.notify("Session Ended", "Stay Toasty")
            lastPhase = phase
        end
    end
end

-- Open a long-lived SSE connection to /events; each line is either a
-- "data: {json}" frame or a blank/comment separator, which we ignore.
local function startStream()
    streamStarted  = true
    graceTicks     = 1
    eventsThisTick = 0
    noctalia.runStream(
        ('curl -Ns -H "X-API-KEY: %s" "%s/events"'):format(apiKey, serverUrl),
        function(line)
            eventsThisTick = eventsThisTick + 1
            local data = line:match("^data:%s*(.+)$")
            if data then applyStatus(data) end
        end
    )
end

local function loadConfig(callback)
    noctalia.runAsync(
        'jq -r \'.server_url // "http://localhost:2420"\' ' .. home .. '/.config/ChillClock/config.json',
        function(result)
            local url = result.stdout or ""
            serverUrl = url:match("^%s*(.-)%s*$")
            if serverUrl == "" then serverUrl = "http://localhost:2420" end
            noctalia.runAsync(
                'grep -m1 "CHILLCLOCK_API_KEY=" ' .. home .. '/.config/ChillClock/.env | cut -d= -f2',
                function(result2)
                    apiKey = (result2.stdout or ""):match("^%s*(.-)%s*$")
                    callback()
                end
            )
        end
    )
end

function update()
    if not serverUrl then
        barWidget.setText("0:00")
        barWidget.setColor("#888888")
        loadConfig(startStream)
        return
    end

    if not streamStarted then
        startStream()
        return
    end

    if graceTicks > 0 then
        graceTicks = graceTicks - 1
    elseif eventsThisTick == 0 then
        -- No events for a full tick: connection likely dead, reconnect.
        startStream()
        return
    end

    eventsThisTick = 0
end

function onClick()
    if not serverUrl then return end
    noctalia.runAsync(curl("/toggle?timer=" .. defaultTimer, "POST"))
end

function onRightClick()
    if not serverUrl then return end
    noctalia.runAsync(curl("/toggle?timer=" .. (defaultTimer == 1 and 2 or 1), "POST"))
end

function onMiddleClick()
    if not serverUrl then return end
    noctalia.runAsync(curl("/switch", "POST"))
end
