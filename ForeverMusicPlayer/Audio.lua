-- Audio.lua
-- Turns the game's own music off while the player is active and puts it back
-- afterwards.
--
-- Only on/off settings are touched (Sound_EnableMusic, and Sound_EnableAmbience
-- if the option is on). Volume sliders are never changed, so the game music
-- comes back at exactly the level it had. Each setting is put back to the value
-- found when it was taken over, unless the player changed it in the meantime:
-- in that case their choice is kept.

local ADDON_NAME, ns = ...

local Audio = {}
ns.Audio = Audio

local GetCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
local SetCVar = (C_CVar and C_CVar.SetCVar) or SetCVar

Audio.wanted = false   -- should the game music be off right now?
Audio.pending = false  -- did the game refuse a change we still owe?
Audio.snapshot = nil   -- [cvar] = { original = "1", forced = "0" } while muted

-- Settings forced while muted, as { cvar name = forced value }.
local function Takeover()
    local list = { Sound_EnableMusic = "0" }
    if ns.db.muteAmbience then
        list.Sound_EnableAmbience = "0"
    end
    return list
end

-- Sets a CVar and confirms the game accepted it.
local function TrySet(name, value)
    pcall(SetCVar, name, value)
    return GetCVar(name) == value
end

local function Release(self, name)
    local entry = self.snapshot[name]
    -- Restore only what is still as we left it; otherwise the player changed
    -- the setting themselves while listening and that choice stands.
    if entry.original ~= entry.forced and GetCVar(name) == entry.forced then
        if not TrySet(name, entry.original) then
            self.pending = true
            return
        end
    end
    self.snapshot[name] = nil
end

-- Brings the game settings in line with Audio.wanted.
-- Returns false if the game refused a change (retried on leaving combat).
function Audio:Apply()
    self.pending = false
    local takeover = self.wanted and Takeover() or {}

    if self.snapshot then
        for name in pairs(self.snapshot) do
            if not takeover[name] then
                Release(self, name)
            end
        end
    end

    for name, forced in pairs(takeover) do
        self.snapshot = self.snapshot or {}
        if not self.snapshot[name] then
            local original = GetCVar(name)
            if original ~= nil then
                if original == forced or TrySet(name, forced) then
                    self.snapshot[name] = { original = original, forced = forced }
                else
                    self.pending = true
                end
            end
        end
    end

    if self.snapshot and not next(self.snapshot) then
        self.snapshot = nil
    end
    return not self.pending
end

function Audio:SetMuted(muted)
    self.wanted = muted and true or false
    return self:Apply()
end

function Audio:Retry()
    if self.pending then
        self:Apply()
    end
end

function Audio:IsMuted()
    return self.snapshot ~= nil and self.snapshot.Sound_EnableMusic ~= nil
end
