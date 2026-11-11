-- run.lua
-- Tests of the addon outside the game. From the repository root:
--
--     lua5.1 tests/lua/run.lua
--
-- The addon's real files are loaded into the fake game environment of
-- wowmock.lua, then driven the way a player would: buttons, slash commands,
-- logging out, reloading.

package.path = "tests/lua/?.lua;" .. package.path
local Mock = require("wowmock")

local ADDON_DIR, ADDON_NAME = "ForeverMusicPlayer", "ForeverMusicPlayer"

local passed, failed = 0, 0

local function test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        io.write("FAIL  ", name, "\n", err, "\n\n")
    end
end

local function eq(actual, expected, what)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(what or "value", tostring(expected), tostring(actual)), 2)
    end
end

-- Starts a session and loads the addon. Returns its private table.
local function start(options)
    Mock.Reset(options)
    return Mock.LoadAddon(ADDON_DIR, ADDON_NAME)
end

-- Ends the session and starts the next one, like /reload or a relog.
local function restart(secondsAway)
    local saved = Mock.Logout()
    Mock.clock = Mock.clock + (secondsAway or 2)
    return start({ savedVariables = saved })
end

local function freshCVars()
    Mock.cvars = nil
end

-- Reads the beacon back from the textures the addon coloured.
local function readBeacon(ns)
    local cells = {}
    for i, texture in ipairs(ns.Beacon.cells) do
        local r, g, b = unpack(texture.color)
        cells[i] = r * 4 + g * 2 + b
    end
    local bits = {}
    for i = 9, #cells do
        local value = cells[i]
        bits[#bits + 1] = math.floor(value / 4) % 2
        bits[#bits + 1] = math.floor(value / 2) % 2
        bits[#bits + 1] = value % 2
    end
    local position = 0
    local function take(count)
        local value = 0
        for _ = 1, count do
            position = position + 1
            value = value * 2 + bits[position]
        end
        return value
    end
    local message = { cells = cells }
    message.version = take(3)
    local flags = take(3)
    message.active = flags >= 4
    message.playing = flags % 4 >= 2
    message.platform = take(3)
    message.volume = take(9)
    message.nonce = take(6)
    message.seq = take(6)
    message.cmd = take(6)
    message.crc = take(12)
    local payload = {}
    for i = 1, 36 do
        payload[i] = bits[i]
    end
    message.crcOk = ns.Protocol.Crc12(payload) == message.crc
    return message
end

-- Packaging --------------------------------------------------------------------

test("the .toc lists files that exist, and not Bindings.xml", function()
    local toc = Mock.ReadToc(ADDON_DIR .. "/" .. ADDON_NAME .. ".toc")
    eq(toc.fields.Interface, "16001", "interface number")
    assert(#toc.files >= 5, "files listed")
    for _, file in ipairs(toc.files) do
        assert(io.open(ADDON_DIR .. "/" .. file), "missing file " .. file)
        assert(file ~= "Bindings.xml", "Bindings.xml is loaded by the game itself")
    end
    assert(toc.fields.SavedVariables == "ForeverMusicPlayerDB")
end)

test("every key binding has a name and calls a function that exists", function()
    freshCVars()
    start()
    local xml = assert(io.open(ADDON_DIR .. "/Bindings.xml")):read("*a")
    local count = 0
    for name, body in xml:gmatch('<Binding name="([%w_]+)"[^>]*>%s*(.-)%s*</Binding>') do
        count = count + 1
        assert(type(_G["BINDING_NAME_" .. name]) == "string", "no display name for " .. name)
        local fn = body:match("^ForeverMusicPlayer%.(%w+)%(%)$")
        assert(fn and type(ForeverMusicPlayer[fn]) == "function", "binding calls unknown function: " .. body)
    end
    eq(count, 7, "bindings")
    assert(type(BINDING_HEADER_FOREVERMUSICPLAYER) == "string")
end)

test("every icon used by the window exists on disk", function()
    local icons = { pause = true }
    for line in io.lines(ADDON_DIR .. "/UI.lua") do
        for icon in line:gmatch('Icon%("(%w+)"%)') do
            icons[icon] = true
        end
        for icon in line:gmatch('IconButton%(frame, "(%w+)"') do
            icons[icon] = true
        end
    end
    local count = 0
    for icon in pairs(icons) do
        count = count + 1
        local file = assert(io.open(ADDON_DIR .. "/Media/" .. icon .. ".tga", "rb"), "missing icon " .. icon)
        local header = file:read(18)
        file:close()
        -- Uncompressed true colour, 64 x 64, 32 bits: what the game expects.
        eq(header:byte(3), 2, icon .. " image type")
        eq(header:byte(13) + header:byte(14) * 256, 64, icon .. " width")
        eq(header:byte(15) + header:byte(16) * 256, 64, icon .. " height")
        eq(header:byte(17), 32, icon .. " bits per pixel")
    end
    eq(count, 10, "icons referenced by the window")
end)

test("the French locale translates every string", function()
    freshCVars()
    local english = start({ locale = "enUS" }).L
    local french = start({ locale = "frFR" }).L
    -- Same word in both languages.
    local untranslated = { TITLE = true, VOLUME = true, VOLUME_UNMANAGED = true, PAUSE = true }
    for key, text in pairs(english) do
        assert(french[key] ~= nil, "missing in French: " .. key)
        if type(text) == "string" and not untranslated[key] then
            assert(french[key] ~= text, "not translated: " .. key)
        end
    end
    eq(#french.HELP, #english.HELP, "help lines")
end)

-- Game music --------------------------------------------------------------------

test("play mutes the game music, stop brings it back unchanged", function()
    freshCVars()
    local ns = start()
    eq(Mock.cvars.Sound_EnableMusic, "1", "before")
    ns:Play()
    eq(Mock.cvars.Sound_EnableMusic, "0", "while playing")
    eq(Mock.cvars.Sound_MusicVolume, "0.4", "music volume while playing")
    assert(ns.Audio:IsMuted())
    ns:Stop()
    eq(Mock.cvars.Sound_EnableMusic, "1", "after stop")
    eq(Mock.cvars.Sound_MusicVolume, "0.4", "music volume after stop")
    eq(Mock.cvars.Sound_EnableAmbience, "1", "ambience untouched")
    assert(not ns.Audio:IsMuted())
end)

test("music that was already off stays off after stop", function()
    freshCVars()
    Mock.Reset()
    Mock.cvars.Sound_EnableMusic = "0"
    local ns = Mock.LoadAddon(ADDON_DIR, ADDON_NAME)
    ns:Play()
    ns:Stop()
    eq(Mock.cvars.Sound_EnableMusic, "0", "after stop")
end)

test("a setting the player changed while listening is left alone", function()
    freshCVars()
    Mock.Reset()
    Mock.cvars.Sound_EnableMusic = "0"
    local ns = Mock.LoadAddon(ADDON_DIR, ADDON_NAME)
    ns:Play()
    Mock.cvars.Sound_EnableMusic = "1" -- the player presses Ctrl+M
    ns:Stop()
    eq(Mock.cvars.Sound_EnableMusic, "1", "the player's choice is kept")
end)

test("pause keeps the game music off, unless the option says otherwise", function()
    freshCVars()
    local ns = start()
    ns:Play()
    ns:Pause()
    eq(ns.state, "paused")
    eq(Mock.cvars.Sound_EnableMusic, "0", "paused, default")

    Mock.Slash("pausemusic on")
    eq(Mock.cvars.Sound_EnableMusic, "1", "paused, option on")
    ns:Play()
    eq(Mock.cvars.Sound_EnableMusic, "0", "playing again")
    ns:Pause()
    eq(Mock.cvars.Sound_EnableMusic, "1", "paused again")
    ns:Stop()
    eq(Mock.cvars.Sound_EnableMusic, "1", "stopped")
end)

test("pause does nothing when stopped", function()
    freshCVars()
    local ns = start()
    ns:Pause()
    eq(ns.state, "stopped")
    eq(Mock.cvars.Sound_EnableMusic, "1")
end)

test("the ambience option mutes and restores ambient sounds too", function()
    freshCVars()
    local ns = start()
    Mock.Slash("ambience on")
    eq(Mock.cvars.Sound_EnableAmbience, "1", "nothing changes while stopped")
    ns:Play()
    eq(Mock.cvars.Sound_EnableAmbience, "0", "playing")
    Mock.Slash("ambience off")
    eq(Mock.cvars.Sound_EnableAmbience, "1", "option turned off while playing")
    eq(Mock.cvars.Sound_EnableMusic, "0", "music still muted")
    Mock.Slash("ambience on")
    eq(Mock.cvars.Sound_EnableAmbience, "0", "option back on")
    ns:Stop()
    eq(Mock.cvars.Sound_EnableAmbience, "1", "restored")
    eq(Mock.cvars.Sound_EnableMusic, "1", "restored")
end)

test("a refused sound change is retried when combat ends", function()
    freshCVars()
    local ns = start()
    Mock.blockCVars = true
    ns:Play()
    eq(Mock.cvars.Sound_EnableMusic, "1", "refused")
    assert(Mock.printed[#Mock.printed]:find("combat"), "the player is told")
    Mock.blockCVars = false
    Mock.FireEvent("PLAYER_REGEN_ENABLED")
    eq(Mock.cvars.Sound_EnableMusic, "0", "applied after combat")

    Mock.blockCVars = true
    ns:Stop()
    eq(Mock.cvars.Sound_EnableMusic, "0", "restore refused")
    Mock.blockCVars = false
    Mock.FireEvent("PLAYER_REGEN_ENABLED")
    eq(Mock.cvars.Sound_EnableMusic, "1", "restored after combat")
end)

-- Logging out and coming back ------------------------------------------------------

test("logging out while playing saves the game's own sound settings", function()
    freshCVars()
    local ns = start()
    ns:Play()
    local saved = Mock.Logout()
    eq(Mock.cvars.Sound_EnableMusic, "1", "what the game writes to disk")
    eq(saved.resume.state, "playing")
end)

test("a /reload comes back playing and muted", function()
    freshCVars()
    local ns = start()
    ns:Play()
    ns = restart(3)
    eq(ns.state, "playing")
    eq(Mock.cvars.Sound_EnableMusic, "0")
    assert(readBeacon(ns).playing)
    ns:Stop()
    eq(Mock.cvars.Sound_EnableMusic, "1")
end)

test("a /reload while paused comes back paused", function()
    freshCVars()
    local ns = start()
    ns:Play()
    ns:Pause()
    ns = restart(3)
    eq(ns.state, "paused")
    eq(Mock.cvars.Sound_EnableMusic, "0")
end)

test("coming back the next day starts stopped, with the game music on", function()
    freshCVars()
    local ns = start()
    ns:Play()
    ns = restart(24 * 3600)
    eq(ns.state, "stopped")
    eq(Mock.cvars.Sound_EnableMusic, "1")
    eq(ForeverMusicPlayerDB.resume, nil)
end)

test("logging out while stopped does not resume anything", function()
    freshCVars()
    local ns = start()
    ns:Play()
    ns:Stop()
    ns = restart(1)
    eq(ns.state, "stopped")
    eq(Mock.cvars.Sound_EnableMusic, "1")
end)

test("settings survive a restart", function()
    freshCVars()
    local ns = start()
    Mock.Slash("platform deezer")
    Mock.Slash("volume 35")
    Mock.Slash("beacon size 6")
    ns = restart(1)
    eq(ns.db.platform, 2)
    eq(ns.db.volume, 35)
    eq(ns.db.beacon.cell, 6)
end)

-- Beacon ------------------------------------------------------------------------------

test("the beacon shows the sync pattern and a valid checksum", function()
    freshCVars()
    local ns = start()
    local message = readBeacon(ns)
    eq(#message.cells, 24, "cells")
    local sync = { 7, 0, 4, 2, 1, 6, 3, 5 }
    for i = 1, 8 do
        eq(message.cells[i], sync[i], "sync cell " .. i)
    end
    eq(message.version, 1)
    assert(message.crcOk, "checksum")
    eq(message.active, false)
    eq(message.playing, false)
    eq(message.platform, 0)
    eq(message.volume, 511, "volume not managed by default")
    eq(message.seq, 0)
end)

test("the checksum matches a plain integer CRC-12", function()
    freshCVars()
    local ns = start()
    local function reference(bits)
        local reg = 0xFFF
        for _, bit in ipairs(bits) do
            local top = math.floor(reg / 2048) % 2
            reg = (reg * 2) % 4096
            if top ~= bit then
                -- XOR with 0x80F, one bit at a time
                local result, weight = 0, 1
                local a, b = reg, 0x80F
                for _ = 1, 12 do
                    if a % 2 ~= b % 2 then
                        result = result + weight
                    end
                    a, b, weight = math.floor(a / 2), math.floor(b / 2), weight * 2
                end
                reg = result
            end
        end
        return reg
    end
    math.randomseed(42)
    for _ = 1, 200 do
        local bits = {}
        for i = 1, 36 do
            bits[i] = math.random(0, 1)
        end
        eq(ns.Protocol.Crc12(bits), reference(bits), "crc")
    end
end)

test("the beacon follows the player's state, platform and volume", function()
    freshCVars()
    local ns = start()
    ns:Play()
    local message = readBeacon(ns)
    assert(message.active and message.playing and message.crcOk)

    ns:Pause()
    message = readBeacon(ns)
    assert(message.active and not message.playing and message.crcOk)

    ns:SetPlatform(4)
    ns:SetVolume(65)
    message = readBeacon(ns)
    eq(message.platform, 4)
    eq(message.volume, 65)
    assert(message.crcOk)

    ns:Stop()
    message = readBeacon(ns)
    assert(not message.active and not message.playing and message.crcOk)
end)

test("next and previous start playback and send one event each", function()
    freshCVars()
    local ns = start()
    local nonce = readBeacon(ns).nonce
    Mock.Advance(1)
    ns:Next()
    local message = readBeacon(ns)
    eq(ns.state, "playing")
    eq(Mock.cvars.Sound_EnableMusic, "0")
    eq(message.seq, 1)
    eq(message.cmd, ns.Protocol.CMD.NEXT)
    eq(message.nonce, nonce, "nonce is stable within a session")
    assert(message.playing and message.crcOk)

    Mock.Advance(1)
    ns:Previous()
    message = readBeacon(ns)
    eq(message.seq, 2)
    eq(message.cmd, ns.Protocol.CMD.PREVIOUS)
end)

test("events sent in a burst are shown one after the other", function()
    freshCVars()
    local ns = start()
    Mock.Advance(1)
    ns:Next()
    ns:Next()
    ns:ToggleShuffle()
    eq(readBeacon(ns).seq, 1, "first event shown at once")
    Mock.Advance(0.2)
    eq(readBeacon(ns).seq, 1, "held long enough to be seen")
    Mock.Advance(0.15)
    eq(readBeacon(ns).seq, 2, "second event")
    Mock.Advance(0.3)
    local message = readBeacon(ns)
    eq(message.seq, 3, "third event")
    eq(message.cmd, ns.Protocol.CMD.SHUFFLE)
    Mock.Advance(1)
    eq(readBeacon(ns).seq, 3, "nothing more")
    eq(ns.Beacon.driver:GetScript("OnUpdate"), nil, "timer stopped")
end)

test("the event counter wraps around at 64", function()
    freshCVars()
    local ns = start()
    for _ = 1, 70 do
        Mock.Advance(0.5)
        ns:Next()
    end
    local message = readBeacon(ns)
    eq(message.seq, 70 % 64)
    assert(message.crcOk)
end)

test("the beacon hides a few seconds after stop and returns on play", function()
    freshCVars()
    local ns = start()
    local frame = ns.Beacon.frame
    assert(frame:IsShown(), "visible right after loading")
    Mock.Advance(6)
    assert(not frame:IsShown(), "hidden when idle")
    ns:Play()
    assert(frame:IsShown(), "visible while playing")
    Mock.Advance(60)
    assert(frame:IsShown(), "stays visible while playing")
    ns:Pause()
    Mock.Advance(60)
    assert(frame:IsShown(), "stays visible while paused")
    ns:Stop()
    assert(frame:IsShown(), "visible just after stop")
    Mock.Advance(6)
    assert(not frame:IsShown(), "hidden again")
end)

test("the beacon can be turned off", function()
    freshCVars()
    local ns = start()
    Mock.Slash("beacon off")
    ns:Play()
    assert(not ns.Beacon.frame:IsShown())
    ns:Next()
    eq(readBeacon(ns).seq, 0, "no events while off")
    Mock.Slash("beacon on")
    assert(ns.Beacon.frame:IsShown())
end)

test("each UI load uses a new nonce", function()
    freshCVars()
    local ns = start()
    for _ = 1, 80 do
        local before = ns.Beacon.nonce
        ns = restart(1)
        assert(ns.Beacon.nonce ~= before, "nonce repeated")
        assert(ns.Beacon.nonce >= 0 and ns.Beacon.nonce <= 63)
    end
end)

test("the beacon is sized in screen pixels", function()
    freshCVars()
    local ns = start({ screenHeight = 2160 })
    local frame = ns.Beacon.frame
    eq(frame.scale, 768 / 2160, "scale")
    eq(frame.width, 96, "width")
    eq(frame.height, 4, "height")
    eq(frame.points[1][1], "TOPLEFT")
    for i, texture in ipairs(ns.Beacon.cells) do
        eq(texture.width, 4)
        eq(texture.points[1][4], (i - 1) * 4, "x of cell " .. i)
    end

    Mock.Slash("beacon size 8")
    Mock.Slash("beacon corner bottomright")
    eq(frame.width, 192)
    eq(frame.points[1][1], "BOTTOMRIGHT")
    eq(ns.Beacon.cells[3].points[1][4], 16)

    Mock.screenHeight = 1080
    Mock.FireEvent("DISPLAY_SIZE_CHANGED")
    eq(frame.scale, 768 / 1080, "scale follows the resolution")
end)

-- Window and commands ------------------------------------------------------------------

test("the play button toggles and shows the right icon", function()
    freshCVars()
    local ns = start()
    local button = ns.UI.playButton
    assert(button.icon.texture:find("\\play%.tga$"))
    button:Click()
    eq(ns.state, "playing")
    assert(button.icon.texture:find("\\pause%.tga$"))
    eq(ns.UI.status.text, ns.L.STATE_PLAYING)
    button:Click()
    eq(ns.state, "paused")
    assert(button.icon.texture:find("\\play%.tga$"))
    eq(ns.UI.status.text, ns.L.STATE_PAUSED)
end)

test("the platform menu selects a platform", function()
    freshCVars()
    local ns = start()
    assert(not ns.UI.menuCatcher:IsShown())
    ns.UI.selector:Click()
    assert(ns.UI.menuCatcher:IsShown())
    ns.UI.menu.rows[3]:Click()
    eq(ns.db.platform, 3)
    eq(ns.UI.selector.label.text, "Apple Music")
    assert(not ns.UI.menuCatcher:IsShown(), "menu closes")
    eq(readBeacon(ns).platform, 3)

    ns.UI.selector:Click()
    ns.UI.menuCatcher:Click()
    assert(not ns.UI.menuCatcher:IsShown(), "a click elsewhere closes the menu")
end)

test("the volume slider sets, and right-click releases, the volume", function()
    freshCVars()
    local ns = start()
    eq(ns.UI.volumeText.text, ns.L.VOLUME_UNMANAGED)
    ns.UI.slider:SetValue(42)
    eq(ns.db.volume, 42)
    eq(ns.UI.volumeText.text, "42%")
    eq(readBeacon(ns).volume, 42)

    ns.UI.slider.scripts.OnMouseWheel(ns.UI.slider, 1)
    eq(ns.db.volume, 47)
    ns.UI.slider.scripts.OnMouseUp(ns.UI.slider, "RightButton")
    eq(ns.db.volume, false)
    eq(readBeacon(ns).volume, 511)
    eq(ns.UI.volumeText.text, ns.L.VOLUME_UNMANAGED)
end)

test("volume is clamped to 0-100", function()
    freshCVars()
    local ns = start()
    ns:SetVolume(98)
    ns:AdjustVolume(5)
    eq(ns.db.volume, 100)
    ns:SetVolume(3)
    ns:AdjustVolume(-5)
    eq(ns.db.volume, 0)
    eq(readBeacon(ns).volume, 0)
end)

test("slash commands", function()
    freshCVars()
    local ns = start()
    Mock.Slash("play")
    eq(ns.state, "playing")
    Mock.Slash("TOGGLE")
    eq(ns.state, "paused")
    Mock.Slash("  stop  ")
    eq(ns.state, "stopped")

    Mock.Slash("platform youtube")
    eq(ns.db.platform, 4)
    Mock.Slash("platform nope")
    eq(ns.db.platform, 4)
    assert(Mock.printed[#Mock.printed]:find("spotify"), "lists the choices")

    Mock.Slash("volume 150")
    eq(ns.db.volume, false)
    Mock.Slash("volume 80")
    eq(ns.db.volume, 80)
    Mock.Slash("volume off")
    eq(ns.db.volume, false)

    local before = #Mock.printed
    Mock.Slash("help")
    eq(#Mock.printed - before, #ns.L.HELP)
    Mock.Slash("status")
    Mock.Slash("frobnicate")
    assert(Mock.printed[#Mock.printed]:find("/fmp help"))
end)

test("the window can be hidden, shown, scaled, locked and reset", function()
    freshCVars()
    local ns = start()
    local frame = ns.UI.frame
    assert(frame:IsShown())
    Mock.Slash("")
    assert(not frame:IsShown())
    eq(ns.db.window.shown, false)
    ForeverMusicPlayer.ToggleWindow()
    assert(frame:IsShown())

    Mock.Slash("scale 1.3")
    eq(frame.scale, 1.3)
    Mock.Slash("scale 9")
    eq(frame.scale, 1.3)

    frame.scripts.OnDragStart(frame)
    assert(frame.moving)
    frame.scripts.OnDragStop(frame)
    Mock.Slash("lock on")
    frame.moving = false
    frame.scripts.OnDragStart(frame)
    assert(not frame.moving, "locked window does not move")

    Mock.Slash("reset")
    eq(frame.scale, 1)
    eq(frame.points[1][1], "CENTER")
end)

test("the minimap button toggles the window and playback", function()
    freshCVars()
    local ns = start()
    local button = ns.UI.minimapButton
    assert(button:IsShown())
    button:Click("LeftButton")
    assert(not ns.UI.frame:IsShown())
    button:Click("RightButton")
    eq(ns.state, "playing")
    Mock.Slash("minimap")
    assert(not button:IsShown())
    Mock.Slash("minimap")
    assert(button:IsShown())
    ForeverMusicPlayer_OnAddonCompartmentClick(ADDON_NAME, "RightButton")
    eq(ns.state, "paused")
end)

test("saved variables hold plain data only", function()
    freshCVars()
    local ns = start()
    ns:Play()
    ns:Next()
    Mock.Slash("volume 20")
    local saved = Mock.Logout() -- Copy() rejects functions and userdata
    eq(saved.volume, 20)
    eq(type(saved.lastNonce), "number")
end)

io.write(("%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
