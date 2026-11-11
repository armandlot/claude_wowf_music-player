-- wowmock.lua
-- A small stand-in for the World of Warcraft Lua environment, enough to load
-- the addon outside the game and drive it from tests.
--
-- The widget classes below list the game methods the addon is allowed to
-- call. Calling anything else is an error, so a typo in a method name fails
-- the tests instead of failing in game.

local Mock = {}

-- Widget classes -------------------------------------------------------------

local function Class(parent, methods)
    for name, fn in pairs(parent or {}) do
        if methods[name] == nil then
            methods[name] = fn
        end
    end
    return methods
end

local Region = {}
function Region:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Region:ClearAllPoints() self.points = {} end
function Region:SetAllPoints(other) self.points = { { "ALL", other } } end
function Region:GetPoint(index) return unpack(self.points[index or 1] or {}) end
function Region:SetSize(width, height) self.width, self.height = width, height end
function Region:SetWidth(width) self.width = width end
function Region:SetHeight(height) self.height = height end
function Region:GetWidth() return self.width or 0 end
function Region:GetHeight() return self.height or 0 end
function Region:GetCenter() return 500, 500 end
function Region:Show() self.shown = true end
function Region:Hide()
    local wasShown = self.shown
    self.shown = false
    if wasShown and self.scripts and self.scripts.OnHide then
        self.scripts.OnHide(self)
    end
end
function Region:SetShown(shown) if shown then self:Show() else self:Hide() end end
function Region:IsShown() return self.shown end
function Region:SetAlpha(alpha) self.alpha = alpha end

local Texture = Class(Region, {})
function Texture:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function Texture:SetTexture(path) self.texture = path end
function Texture:SetVertexColor(r, g, b, a) self.vertexColor = { r, g, b, a } end

local FontString = Class(Region, {})
function FontString:SetText(text) self.text = text end
function FontString:GetText() return self.text end
function FontString:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a } end
function FontString:SetJustifyH(justify) self.justifyH = justify end

local Frame = Class(Region, {})
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:CreateTexture(name, layer)
    return Mock.NewWidget(Texture, "Texture", self, { layer = layer })
end
function Frame:CreateFontString(name, layer, template)
    return Mock.NewWidget(FontString, "FontString", self, { layer = layer, template = template })
end
function Frame:SetFrameStrata(strata) self.strata = strata end
function Frame:SetFrameLevel(level) self.level = level end
function Frame:GetFrameLevel() return self.level or 1 end
function Frame:SetScale(scale) self.scale = scale end
function Frame:GetScale() return self.scale or 1 end
function Frame:GetEffectiveScale() return self.scale or 1 end
function Frame:SetMovable(movable) self.movable = movable end
function Frame:EnableMouse(enabled) self.mouse = enabled end
function Frame:EnableMouseWheel(enabled) self.mouseWheel = enabled end
function Frame:RegisterForDrag(...) self.dragButtons = { ... } end
function Frame:SetClampedToScreen(clamped) self.clamped = clamped end
function Frame:StartMoving() self.moving = true end
function Frame:StopMovingOrSizing() self.moving = false end
function Frame:SetIgnoreParentScale(ignore) self.ignoreParentScale = ignore end
function Frame:SetIgnoreParentAlpha(ignore) self.ignoreParentAlpha = ignore end

local Button = Class(Frame, {})
function Button:RegisterForClicks(...) self.clicks = { ... } end
function Button:SetHighlightTexture(path) self.highlight = path end
function Button:Click(mouseButton)
    if self.scripts.OnClick then
        self.scripts.OnClick(self, mouseButton or "LeftButton")
    end
end

local Slider = Class(Frame, {})
function Slider:SetOrientation(orientation) self.orientation = orientation end
function Slider:SetMinMaxValues(low, high) self.min, self.max = low, high end
function Slider:SetValueStep(step) self.step = step end
function Slider:SetObeyStepOnDrag(obey) self.obeyStep = obey end
function Slider:SetThumbTexture(texture) self.thumbTexture = texture end
function Slider:GetValue() return self.value end
function Slider:SetValue(value)
    value = math.max(self.min or value, math.min(self.max or value, value))
    if value ~= self.value then
        self.value = value
        if self.scripts.OnValueChanged then
            self.scripts.OnValueChanged(self, value, false)
        end
    end
end

local Tooltip = Class(Frame, {})
function Tooltip:SetOwner(owner, anchor) self.owner, self.lines = owner, {} end
function Tooltip:SetText(text) self.lines = { text } end
function Tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function Tooltip:IsOwned(frame) return self.shown and self.owner == frame end

local CLASSES = { Frame = Frame, Button = Button, Slider = Slider }

function Mock.NewWidget(class, kind, parent, fields)
    local widget = fields or {}
    widget.kind = kind
    widget.parent = parent
    widget.shown = true
    widget.points = {}
    widget.scripts = {}
    widget.events = {}
    return setmetatable(widget, { __index = class })
end

-- Is the frame shown, along with everything it sits in?
local function IsVisible(frame)
    while frame do
        if not frame.shown then
            return false
        end
        frame = frame.parent
    end
    return true
end

-- Environment ------------------------------------------------------------------

local function Copy(value)
    assert(type(value) ~= "function" and type(value) ~= "userdata", "saved variables must be plain data")
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[Copy(k)] = Copy(v)
    end
    return copy
end
Mock.Copy = Copy

-- Starts a fresh game session. Sound settings and saved variables are kept
-- from one session to the next unless given again.
function Mock.Reset(options)
    options = options or {}
    Mock.cvars = options.cvars or Mock.cvars or {
        Sound_EnableMusic = "1",
        Sound_MusicVolume = "0.4",
        Sound_EnableAmbience = "1",
        Sound_AmbienceVolume = "0.6",
    }
    Mock.blockCVars = false
    Mock.now = 0
    Mock.clock = Mock.clock or 1700000000
    Mock.frames = {}
    Mock.timers = {}
    Mock.printed = {}
    Mock.locale = options.locale or "enUS"
    Mock.screenHeight = options.screenHeight or 1440

    _G.ForeverMusicPlayerDB = options.savedVariables
    _G.ForeverMusicPlayer = nil
    _G.SlashCmdList = {}

    _G.CreateFrame = function(kind, name, parent)
        local class = assert(CLASSES[kind], "unknown frame type " .. tostring(kind))
        local frame = Mock.NewWidget(class, kind, parent, { name = name })
        Mock.frames[#Mock.frames + 1] = frame
        if name then
            _G[name] = frame
        end
        return frame
    end
    _G.UIParent = Mock.NewWidget(Frame, "Frame", nil, { name = "UIParent" })
    _G.Minimap = Mock.NewWidget(Frame, "Frame", UIParent, { name = "Minimap", width = 140, height = 140 })
    _G.GameTooltip = Mock.NewWidget(Tooltip, "GameTooltip", UIParent, { shown = false })
    GameTooltip.shown = false

    _G.GetLocale = function() return Mock.locale end
    _G.GetTime = function() return Mock.now end
    _G.time = function() return Mock.clock end
    _G.GetPhysicalScreenSize = function() return Mock.screenHeight * 16 / 9, Mock.screenHeight end
    _G.GetCursorPosition = function() return 0, 0 end
    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring((select(i, ...)))
        end
        Mock.printed[#Mock.printed + 1] = table.concat(parts, " ")
    end

    _G.C_CVar = {
        GetCVar = function(name) return Mock.cvars[name] end,
        SetCVar = function(name, value)
            if Mock.blockCVars then
                return false
            end
            Mock.cvars[name] = tostring(value)
            return true
        end,
    }
    _G.C_Timer = {
        After = function(delay, fn)
            Mock.timers[#Mock.timers + 1] = { at = Mock.now + delay, fn = fn }
        end,
    }
    _G.C_AddOns = {
        GetAddOnMetadata = function(_, field) return Mock.toc and Mock.toc.fields[field] end,
    }
end

-- Reads a .toc: "## Key: value" lines and the list of files.
function Mock.ReadToc(path)
    local toc = { fields = {}, files = {} }
    for line in io.lines(path) do
        local key, value = line:match("^##%s*([^:]+):%s*(.-)%s*$")
        if key then
            toc.fields[key] = value
        elseif line:match("%S") and not line:match("^#") then
            toc.files[#toc.files + 1] = line:match("^%s*(.-)%s*$")
        end
    end
    return toc
end

-- Loads the addon's files in .toc order and logs the player in.
function Mock.LoadAddon(dir, name)
    Mock.toc = Mock.ReadToc(dir .. "/" .. name .. ".toc")
    local ns = {}
    for _, file in ipairs(Mock.toc.files) do
        local chunk = assert(loadfile(dir .. "/" .. file))
        chunk(name, ns)
    end
    Mock.FireEvent("ADDON_LOADED", "SomeOtherAddon")
    Mock.FireEvent("ADDON_LOADED", name)
    Mock.FireEvent("PLAYER_LOGIN")
    return ns
end

function Mock.FireEvent(event, ...)
    for _, frame in ipairs(Mock.frames) do
        if frame.events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end

-- Lets game time pass: runs OnUpdate handlers of visible frames and timers.
function Mock.Advance(seconds)
    local step = 0.05
    local elapsed = 0
    while elapsed < seconds - 1e-9 do
        elapsed = elapsed + step
        Mock.now = Mock.now + step
        Mock.clock = Mock.clock + step
        for _, frame in ipairs(Mock.frames) do
            if frame.scripts.OnUpdate and IsVisible(frame) then
                frame.scripts.OnUpdate(frame, step)
            end
        end
        local due = {}
        for i = #Mock.timers, 1, -1 do
            if Mock.timers[i].at <= Mock.now then
                due[#due + 1] = table.remove(Mock.timers, i)
            end
        end
        for i = #due, 1, -1 do
            due[i].fn()
        end
    end
end

-- Ends the session the way the game does, and returns what it would save.
function Mock.Logout()
    Mock.FireEvent("PLAYER_LOGOUT")
    return Copy(_G.ForeverMusicPlayerDB)
end

function Mock.Slash(text)
    SlashCmdList["FOREVERMUSICPLAYER"](text)
end

Mock.IsVisible = IsVisible

return Mock
