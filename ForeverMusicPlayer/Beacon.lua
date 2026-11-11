-- Beacon.lua
-- Draws the strip of coloured cells that the companion app reads on screen.
-- It is the only link between the game and the companion, and it is one-way:
-- the addon shows what the player asked for, nothing ever comes back in.
--
-- The strip is 24 cells of a few screen pixels each (96 x 4 px by default) in
-- a corner of the screen. It hides itself a few seconds after the player
-- stops. See Protocol.lua for the meaning of the cells.

local ADDON_NAME, ns = ...
local Protocol = ns.Protocol

local Beacon = {}
ns.Beacon = Beacon

local EVENT_HOLD = 0.30 -- seconds an event stays on screen before the next one
local IDLE_HIDE = 5     -- seconds the strip stays visible after the last change
local MAX_QUEUE = 8     -- pending events kept when buttons are spammed

Beacon.nonce = 0
Beacon.seq = 0
Beacon.cmd = Protocol.CMD.NONE
Beacon.queue = {}
Beacon.lastEventAt = 0
Beacon.visibleUntil = 0

-- Sizes the strip in real screen pixels, whatever the UI scale is.
function Beacon:Layout()
    local frame = self.frame
    local _, screenHeight = GetPhysicalScreenSize()
    -- The UI is always 768 units tall, so this scale makes 1 unit = 1 pixel.
    frame:SetScale((screenHeight and screenHeight > 0) and (768 / screenHeight) or 1)

    local cell = ns.db.beacon.cell
    local corner = ns.db.beacon.corner
    frame:SetSize(cell * Protocol.CELL_COUNT, cell)
    frame:ClearAllPoints()
    frame:SetPoint(corner, UIParent, corner, 0, 0)
    for i, texture in ipairs(self.cells) do
        texture:ClearAllPoints()
        texture:SetSize(cell, cell)
        texture:SetPoint("TOPLEFT", frame, "TOPLEFT", (i - 1) * cell, 0)
    end
end

function Beacon:Render()
    local cells = Protocol.Encode({
        active = ns.state ~= ns.STATE_STOPPED,
        playing = ns.state == ns.STATE_PLAYING,
        platform = ns.db.platform,
        volume = ns.db.volume or nil,
        nonce = self.nonce,
        seq = self.seq,
        cmd = self.cmd,
    })
    for i, texture in ipairs(self.cells) do
        local r, g, b = Protocol.CellColor(cells[i])
        texture:SetColorTexture(r, g, b, 1)
    end
end

function Beacon:UpdateVisibility()
    local visible = ns.db.beacon.enabled
        and (ns.state ~= ns.STATE_STOPPED or GetTime() < self.visibleUntil)
    self.frame:SetShown(visible)
end

-- Keeps the strip on screen long enough for the companion to see a change.
function Beacon:Touch()
    self.visibleUntil = GetTime() + IDLE_HIDE
    self:UpdateVisibility()
    C_Timer.After(IDLE_HIDE + 0.1, function()
        Beacon:UpdateVisibility()
    end)
end

-- Shows queued events one at a time, each for at least EVENT_HOLD seconds, so
-- the companion cannot miss one between two screen captures.
local function Pump()
    local self = Beacon
    if #self.queue == 0 then
        self.driver:SetScript("OnUpdate", nil)
        return
    end
    local now = GetTime()
    if now - self.lastEventAt >= EVENT_HOLD then
        self.seq = (self.seq + 1) % 64
        self.cmd = table.remove(self.queue, 1)
        self.lastEventAt = now
        self:Render()
        self:Touch()
    end
end

-- One-shot commands (next, previous, shuffle, repeat).
function Beacon:PushEvent(cmd)
    if not ns.db.beacon.enabled or #self.queue >= MAX_QUEUE then
        return
    end
    self.queue[#self.queue + 1] = cmd
    self.driver:SetScript("OnUpdate", Pump)
    Pump()
end

function Beacon:Init()
    -- A fresh number at every UI load tells the companion to start over
    -- instead of replaying the last event it saw before a /reload.
    repeat
        self.nonce = math.random(0, 63)
    until self.nonce ~= ns.db.lastNonce

    local frame = CreateFrame("Frame", "ForeverMusicPlayerBeacon", UIParent)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(9000)
    frame:SetIgnoreParentScale(true)
    frame:SetIgnoreParentAlpha(true)
    self.frame = frame

    self.cells = {}
    for i = 1, Protocol.CELL_COUNT do
        self.cells[i] = frame:CreateTexture(nil, "OVERLAY")
    end

    -- A frame of its own for timing: hidden frames get no OnUpdate.
    local driver = CreateFrame("Frame")
    driver:RegisterEvent("DISPLAY_SIZE_CHANGED")
    driver:RegisterEvent("UI_SCALE_CHANGED")
    driver:SetScript("OnEvent", function()
        Beacon:Layout()
    end)
    self.driver = driver

    self:Layout()
    self:Render()
    self:Touch()

    ns:OnChange(function(what)
        if what == "options" then
            Beacon:Layout()
        end
        Beacon:Render()
        Beacon:Touch()
    end)
end
