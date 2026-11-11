-- scenario.lua
-- Plays a session of the addon in the fake game and prints what the beacon
-- shows at each screen capture (one every 0.05 s). The companion's end-to-end
-- test reads these lines as if they were the screen.
--
--     lua5.1 tests/lua/scenario.lua
--
-- Each line: step name | 1 if the beacon is visible, else 0 | 24 cell values

package.path = "tests/lua/?.lua;" .. package.path
local Mock = require("wowmock")

local ADDON = "ForeverMusicPlayer"
local ns

local function capture(step, count)
    for _ = 1, count do
        Mock.Advance(0.05)
        local cells = {}
        for i, texture in ipairs(ns.Beacon.cells) do
            local r, g, b = unpack(texture.color)
            cells[i] = r * 4 + g * 2 + b
        end
        io.write(step, " | ", Mock.IsVisible(ns.Beacon.frame) and 1 or 0, " | ", table.concat(cells, " "), "\n")
    end
end

Mock.Reset()
ns = Mock.LoadAddon(ADDON, ADDON)
ns:SetPlatform(1) -- Spotify
capture("loaded", 3)

ns:Play()
capture("play", 3)

ns:Next()
ns:Next()
ns:Previous()
capture("skip-burst", 30)

ns:SetVolume(40)
capture("volume", 3)

ns:Pause()
capture("pause", 3)

ns:SetPlatform(2) -- Deezer
capture("platform", 3)

ns:Play()
capture("play-deezer", 3)

-- /reload while playing
local saved = Mock.Logout()
Mock.Reset({ savedVariables = saved })
ns = Mock.LoadAddon(ADDON, ADDON)
capture("reload", 3)

ns:Stop()
capture("stop", 3)
capture("idle", 120) -- six seconds: the beacon hides

ns:Toggle()
capture("play-again", 3)
