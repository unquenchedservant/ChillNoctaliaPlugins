local COLORS = { green = "#69db7c", yellow = "#ffd43b", red = "#ff6b6b", white = "#ffffff" }
local home = noctalia.getenv("HOME")

local defaultTimer = barWidget.getConfig("default_timer")

noctalia.setUpdateInterval(250)

local serverUrl = nil
local apiKey    = nil

local function curl(path, method)
    local m = method and ("-X " .. method) or ""
    return ('curl -s %s -H "X-API-KEY: %s" "%s%s"'):format(m, apiKey, serverUrl, path)
end

local function fetchStatus()
    noctalia.runAsync(curl("/status"), function(result)
        local out = result.stdout
        if not out or out == "" then
            barWidget.setText("--:--")
            barWidget.setColor("#888888")
            return
        end
        local text  = out:match('"text":"([^"]+)"')
        local class = out:match('"class":"([^"]+)"')
        barWidget.setText(text or "--:--")
        barWidget.setColor(COLORS[class] or "#ffffff")
    end)
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
        loadConfig(fetchStatus)
        return
    end
    fetchStatus()
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
