-- Core.lua
-- The player's state (stopped / playing / paused), saved settings, events and
-- slash commands. Everything else reacts to changes announced from here.

local ADDON_NAME, ns = ...
local L = ns.L
local CMD = ns.Protocol.CMD

ns.STATE_STOPPED = "stopped"
ns.STATE_PLAYING = "playing"
ns.STATE_PAUSED = "paused"
ns.state = ns.STATE_STOPPED

-- Index = platform number sent to the companion app.
ns.PLATFORMS = {
    [0] = { key = "auto", name = L.PLATFORM_AUTO, color = { 0.75, 0.75, 0.78 } },
    [1] = { key = "spotify", name = "Spotify", color = { 0.12, 0.84, 0.38 } },
    [2] = { key = "deezer", name = "Deezer", color = { 0.64, 0.22, 1.00 } },
    [3] = { key = "apple", name = "Apple Music", color = { 0.98, 0.26, 0.35 } },
    [4] = { key = "youtube", name = "YouTube Music", color = { 1.00, 0.20, 0.20 } },
}
ns.PLATFORM_COUNT = 5

local PLATFORM_ALIASES = {
    auto = 0, spotify = 1, deezer = 2,
    apple = 3, applemusic = 3,
    youtube = 4, youtubemusic = 4, ytmusic = 4, yt = 4,
}

local DEFAULTS = {
    version = 1,
    platform = 0,
    volume = false,          -- false: the music app's volume is left alone
    muteAmbience = false,
    restoreOnPause = false,
    beacon = { enabled = true, cell = 4, corner = "TOPLEFT" },
    window = { shown = true, locked = false, scale = 1, point = "CENTER", relPoint = "CENTER", x = 0, y = 160 },
    minimap = { hide = false, angle = 215 },
}

-- After a /reload or a quick character switch the player comes back in the
-- state it was in. After a longer break it starts stopped.
local RESUME_WINDOW = 180 -- seconds

local function ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            ApplyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

function ns:Print(text)
    print("|cffffd100" .. L.TITLE .. "|r: " .. text)
end

-- Change notifications ------------------------------------------------------

local listeners = {}

-- fn(what) is called with "state", "platform", "volume" or "options".
function ns:OnChange(fn)
    listeners[#listeners + 1] = fn
end

function ns:Changed(what)
    for i = 1, #listeners do
        listeners[i](what)
    end
end

-- Player state ---------------------------------------------------------------

-- Game music is off while playing, and while paused unless the player asked
-- to get it back during pauses.
local function ApplyAudio()
    local mute = ns.state == ns.STATE_PLAYING
        or (ns.state == ns.STATE_PAUSED and not ns.db.restoreOnPause)
    if not ns.Audio:SetMuted(mute) then
        ns:Print(L.CVAR_BLOCKED)
    end
end

local function SetState(state)
    if ns.state == state then
        return
    end
    ns.state = state
    ApplyAudio()
    ns:Changed("state")
end

function ns:Play()
    SetState(ns.STATE_PLAYING)
end

function ns:Pause()
    if ns.state == ns.STATE_PLAYING then
        SetState(ns.STATE_PAUSED)
    end
end

function ns:Stop()
    SetState(ns.STATE_STOPPED)
end

function ns:Toggle()
    if ns.state == ns.STATE_PLAYING then
        ns:Pause()
    else
        ns:Play()
    end
end

-- Skipping a track starts playback, like the buttons of a real player.
function ns:Next()
    ns:Play()
    ns.Beacon:PushEvent(CMD.NEXT)
end

function ns:Previous()
    ns:Play()
    ns.Beacon:PushEvent(CMD.PREVIOUS)
end

function ns:ToggleShuffle()
    ns.Beacon:PushEvent(CMD.SHUFFLE)
end

function ns:ToggleRepeat()
    ns.Beacon:PushEvent(CMD.REPEAT)
end

function ns:SetPlatform(id)
    if not ns.PLATFORMS[id] or ns.db.platform == id then
        return
    end
    ns.db.platform = id
    ns:Changed("platform")
end

-- volume: 0-100, or nil/false to stop managing the music app's volume.
function ns:SetVolume(volume)
    if volume then
        volume = math.floor(math.max(0, math.min(100, volume)) + 0.5)
    else
        volume = false
    end
    if ns.db.volume == volume then
        return
    end
    ns.db.volume = volume
    ns:Changed("volume")
end

function ns:AdjustVolume(delta)
    ns:SetVolume((ns.db.volume or 100) + delta)
end

function ns:SetOption(name, value)
    ns.db[name] = value and true or false
    ApplyAudio()
    ns:Changed("options")
end

-- Slash commands ---------------------------------------------------------------

-- "on"/"off" set the value, anything else flips it.
local function OnOff(arg, current)
    if arg == "on" or arg == "1" then
        return true
    elseif arg == "off" or arg == "0" then
        return false
    end
    return not current
end

local function Report(label, value)
    ns:Print((value and L.OPTION_ON or L.OPTION_OFF):format(label))
end

local CORNERS = { topleft = "TOPLEFT", topright = "TOPRIGHT", bottomleft = "BOTTOMLEFT", bottomright = "BOTTOMRIGHT" }

local commands = {}

commands.play = function() ns:Play() end
commands.pause = function() ns:Pause() end
commands.stop = function() ns:Stop() end
commands.toggle = function() ns:Toggle() end
commands.next = function() ns:Next() end
commands.prev = function() ns:Previous() end
commands.previous = commands.prev
commands.shuffle = function() ns:ToggleShuffle() end
commands["repeat"] = function() ns:ToggleRepeat() end

commands.platform = function(arg)
    local id = PLATFORM_ALIASES[arg or ""]
    if not id then
        ns:Print(L.UNKNOWN_PLATFORM)
        return
    end
    ns:SetPlatform(id)
    ns:Print(L.PLATFORM_SET:format(ns.PLATFORMS[id].name))
end

commands.volume = function(arg)
    if arg == "off" then
        ns:SetVolume(nil)
        ns:Print(L.VOLUME_RELEASED)
        return
    end
    local value = tonumber(arg)
    if not value or value < 0 or value > 100 then
        ns:Print(L.BAD_NUMBER:format(0, 100))
        return
    end
    ns:SetVolume(value)
    ns:Print(L.VOLUME_SET:format(ns.db.volume))
end

commands.ambience = function(arg)
    ns:SetOption("muteAmbience", OnOff(arg, ns.db.muteAmbience))
    Report(L.OPT_AMBIENCE, ns.db.muteAmbience)
end

commands.pausemusic = function(arg)
    ns:SetOption("restoreOnPause", OnOff(arg, ns.db.restoreOnPause))
    Report(L.OPT_PAUSE_RESTORE, ns.db.restoreOnPause)
end

commands.beacon = function(arg, arg2)
    local beacon = ns.db.beacon
    if arg == "size" then
        local size = tonumber(arg2)
        if not size or size < 2 or size > 12 then
            ns:Print(L.BAD_NUMBER:format(2, 12))
            return
        end
        beacon.cell = math.floor(size)
        ns:Print(L.BEACON_SIZE:format(beacon.cell))
    elseif arg == "corner" then
        local corner = CORNERS[arg2 or ""]
        if not corner then
            ns:Print(L.UNKNOWN_COMMAND)
            return
        end
        beacon.corner = corner
        ns:Print(L.BEACON_CORNER:format(corner))
    else
        beacon.enabled = OnOff(arg, beacon.enabled)
        Report(L.OPT_BEACON, beacon.enabled)
    end
    ns:Changed("options")
end

commands.minimap = function(arg)
    ns.db.minimap.hide = not OnOff(arg, not ns.db.minimap.hide)
    Report(L.OPT_MINIMAP, not ns.db.minimap.hide)
    ns:Changed("options")
end

commands.lock = function(arg)
    ns.db.window.locked = OnOff(arg, ns.db.window.locked)
    Report(L.OPT_LOCK, ns.db.window.locked)
end

commands.scale = function(arg)
    local value = tonumber(arg)
    if not value or value < 0.6 or value > 1.6 then
        ns:Print(L.BAD_NUMBER:format(0.6, 1.6))
        return
    end
    ns.db.window.scale = value
    ns:Changed("options")
end

commands.reset = function()
    local window = ns.db.window
    window.point, window.relPoint = DEFAULTS.window.point, DEFAULTS.window.relPoint
    window.x, window.y, window.scale = DEFAULTS.window.x, DEFAULTS.window.y, DEFAULTS.window.scale
    window.shown = true
    ns:Changed("options")
    ns:Print(L.WINDOW_RESET)
end

commands.status = function()
    local stateText = L.STATE_STOPPED
    if ns.state == ns.STATE_PLAYING then
        stateText = L.STATE_PLAYING
    elseif ns.state == ns.STATE_PAUSED then
        stateText = L.STATE_PAUSED
    end
    ns:Print(stateText .. " - " .. (ns.Audio:IsMuted() and L.GAME_MUSIC_MUTED or L.GAME_MUSIC_ON))
    ns:Print(L.PLATFORM_SET:format(ns.PLATFORMS[ns.db.platform].name))
    if ns.db.volume then
        ns:Print(L.VOLUME_SET:format(ns.db.volume))
    else
        ns:Print(L.VOLUME_RELEASED)
    end
    Report(L.OPT_BEACON, ns.db.beacon.enabled)
    Report(L.OPT_AMBIENCE, ns.db.muteAmbience)
    Report(L.OPT_PAUSE_RESTORE, ns.db.restoreOnPause)
end

commands.help = function()
    for _, line in ipairs(L.HELP) do
        ns:Print(line)
    end
end

local function HandleSlash(input)
    local command, arg, arg2 = (input or ""):lower():match("^%s*(%S*)%s*(%S*)%s*(%S*)")
    if command == "" then
        ns.UI:ToggleWindow()
        return
    end
    local handler = commands[command]
    if not handler then
        ns:Print(L.UNKNOWN_COMMAND)
        return
    end
    handler(arg ~= "" and arg or nil, arg2 ~= "" and arg2 or nil)
end

SLASH_FOREVERMUSICPLAYER1 = "/fmp"
SLASH_FOREVERMUSICPLAYER2 = "/forevermusicplayer"
SlashCmdList["FOREVERMUSICPLAYER"] = HandleSlash

-- Public table, for key bindings (Bindings.xml) and macros:
--   /run ForeverMusicPlayer.Toggle()
ForeverMusicPlayer = {
    Play = function() ns:Play() end,
    Pause = function() ns:Pause() end,
    Stop = function() ns:Stop() end,
    Toggle = function() ns:Toggle() end,
    Next = function() ns:Next() end,
    Previous = function() ns:Previous() end,
    VolumeUp = function() ns:AdjustVolume(5) end,
    VolumeDown = function() ns:AdjustVolume(-5) end,
    ToggleWindow = function() ns.UI:ToggleWindow() end,
    GetState = function() return ns.state end,
}

-- Entry in the addon list next to the minimap, on clients that have one.
function ForeverMusicPlayer_OnAddonCompartmentClick(_, button)
    if button == "RightButton" then
        ns:Toggle()
    else
        ns.UI:ToggleWindow()
    end
end

-- Events -------------------------------------------------------------------------

local function GetVersion()
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return (getMetadata and getMetadata(ADDON_NAME, "Version")) or "?"
end

local events = CreateFrame("Frame")

local handlers = {}

function handlers.ADDON_LOADED(name)
    if name ~= ADDON_NAME then
        return
    end
    events:UnregisterEvent("ADDON_LOADED")
    if type(ForeverMusicPlayerDB) ~= "table" then
        ForeverMusicPlayerDB = {}
    end
    ns.db = ForeverMusicPlayerDB
    ApplyDefaults(ns.db, DEFAULTS)
    if not ns.PLATFORMS[ns.db.platform] then
        ns.db.platform = 0
    end
end

function handlers.PLAYER_LOGIN()
    local resume = ns.db.resume
    ns.db.resume = nil

    ns.Beacon:Init()
    ns.UI:Init()

    if type(resume) == "table" and type(resume.at) == "number"
        and (resume.state == ns.STATE_PLAYING or resume.state == ns.STATE_PAUSED)
        and math.abs(time() - resume.at) <= RESUME_WINDOW then
        SetState(resume.state)
    end

    ns:Print(L.LOADED:format(GetVersion()))
    if not ns.db.hintShown then
        ns.db.hintShown = true
        ns:Print(L.COMPANION_HINT)
    end
end

-- Fires on logout, on exit and on /reload, just before settings are saved.
-- The sound settings always go back to the player's own values here, so the
-- game never saves "music off" on our behalf, even if the addon is removed.
function handlers.PLAYER_LOGOUT()
    if ns.state ~= ns.STATE_STOPPED then
        ns.db.resume = { state = ns.state, at = time() }
    end
    ns.db.lastNonce = ns.Beacon.nonce
    ns.Audio:SetMuted(false)
end

-- Leaving combat: retry a sound change the game refused earlier.
function handlers.PLAYER_REGEN_ENABLED()
    ns.Audio:Retry()
end

events:SetScript("OnEvent", function(_, event, ...)
    handlers[event](...)
end)
for event in pairs(handlers) do
    events:RegisterEvent(event)
end
