-- UI.lua
-- The player window, the platform menu and the minimap button.
-- Everything is drawn with plain coloured textures and the addon's own icons,
-- so it does not depend on any Blizzard template.

local ADDON_NAME, ns = ...
local L = ns.L

local UI = {}
ns.UI = UI

-- Path of one of the addon's own icons (see tools/make_icons.py).
local function Icon(name)
    return "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\" .. name .. ".tga"
end

local WIDTH, HEIGHT = 252, 112
local ACCENT = { 1.00, 0.82, 0.00 }
local TEXT = { 0.92, 0.92, 0.92 }
local DIM = { 0.58, 0.58, 0.62 }
local STATE_COLORS = {
    playing = { 0.30, 0.90, 0.45 },
    paused = { 1.00, 0.82, 0.00 },
    stopped = DIM,
}

-- Building blocks ---------------------------------------------------------------

local function Fill(parent, layer, r, g, b, a)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetColorTexture(r, g, b, a or 1)
    return texture
end

-- Dark panel with a one-unit border.
local function Panel(frame)
    local bg = Fill(frame, "BACKGROUND", 0.05, 0.05, 0.07, 0.92)
    bg:SetAllPoints(frame)
    local r, g, b, a = 0.30, 0.30, 0.34, 1
    local top = Fill(frame, "BORDER", r, g, b, a)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    top:SetHeight(1)
    local bottom = Fill(frame, "BORDER", r, g, b, a)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(1)
    local left = Fill(frame, "BORDER", r, g, b, a)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    left:SetWidth(1)
    local right = Fill(frame, "BORDER", r, g, b, a)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(1)
end

-- title and body may be functions, for text that depends on the state.
local function ShowTooltip(owner, title, body)
    if type(title) == "function" then
        title = title()
    end
    if type(body) == "function" then
        body = body()
    end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(title, 1, 1, 1)
    if body then
        GameTooltip:AddLine(body, 0.80, 0.80, 0.80, true)
    end
    GameTooltip:Show()
end

local function HideTooltip()
    GameTooltip:Hide()
end

-- Square button showing one of the addon's white icons.
local function IconButton(parent, icon, size, onClick, title, body)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)

    button.bg = Fill(button, "BACKGROUND", 1, 1, 1, 0.07)
    button.bg:SetAllPoints(button)

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(size * 0.75, size * 0.75)
    button.icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.icon:SetTexture(Icon(icon))
    button.icon:SetVertexColor(TEXT[1], TEXT[2], TEXT[3])

    button:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.18)
        self.icon:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
        ShowTooltip(self, title, body)
    end)
    button:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.07)
        self.icon:SetVertexColor(TEXT[1], TEXT[2], TEXT[3])
        HideTooltip()
    end)
    button:SetScript("OnMouseDown", function(self)
        self.icon:SetPoint("CENTER", self, "CENTER", 1, -1)
    end)
    button:SetScript("OnMouseUp", function(self)
        self.icon:SetPoint("CENTER", self, "CENTER", 0, 0)
    end)
    button:SetScript("OnClick", function(self, mouseButton)
        onClick(self, mouseButton)
        if GameTooltip:IsOwned(self) then
            ShowTooltip(self, title, body)
        end
    end)
    return button
end

-- Player window -----------------------------------------------------------------

local function SavePosition(frame)
    local point, _, relPoint, x, y = frame:GetPoint(1)
    local window = ns.db.window
    window.point, window.relPoint, window.x, window.y = point, relPoint, x, y
end

local function BuildTitleBar(frame)
    local logo = frame:CreateTexture(nil, "ARTWORK")
    logo:SetSize(14, 14)
    logo:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -5)
    logo:SetTexture(Icon("icon"))

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    title:SetPoint("LEFT", logo, "RIGHT", 5, 0)
    title:SetText(L.TITLE)

    local close = IconButton(frame, "close", 16, function()
        UI:ToggleWindow(false)
    end, L.CLOSE, L.CLOSE_TIP)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -4)

    local line = Fill(frame, "ARTWORK", 1, 1, 1, 0.08)
    line:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -24)
    line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -24)
    line:SetHeight(1)
end

local function BuildPlatformRow(frame)
    local selector = CreateFrame("Button", nil, frame)
    selector:SetSize(136, 18)
    selector:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -30)

    selector.bg = Fill(selector, "BACKGROUND", 1, 1, 1, 0.07)
    selector.bg:SetAllPoints(selector)

    selector.dot = Fill(selector, "ARTWORK", 1, 1, 1, 1)
    selector.dot:SetSize(8, 8)
    selector.dot:SetPoint("LEFT", selector, "LEFT", 6, 0)

    selector.label = selector:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    selector.label:SetPoint("LEFT", selector.dot, "RIGHT", 6, 0)

    selector.arrow = selector:CreateTexture(nil, "ARTWORK")
    selector.arrow:SetSize(10, 10)
    selector.arrow:SetPoint("RIGHT", selector, "RIGHT", -5, 0)
    selector.arrow:SetTexture(Icon("arrow"))
    selector.arrow:SetVertexColor(DIM[1], DIM[2], DIM[3])

    selector:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.18)
        ShowTooltip(self, L.PLATFORM, L.PLATFORM_TIP)
    end)
    selector:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.07)
        HideTooltip()
    end)
    selector:SetScript("OnClick", function()
        UI:TogglePlatformMenu()
    end)
    UI.selector = selector

    local status = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("RIGHT", frame, "TOPRIGHT", -9, -39)
    status:SetJustifyH("RIGHT")
    UI.status = status
end

local function BuildTransportRow(frame)
    local previous = IconButton(frame, "previous", 24, function() ns:Previous() end, L.PREVIOUS)
    previous:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -58)

    local play = IconButton(frame, "play", 32, function() ns:Toggle() end, function()
        return ns.state == ns.STATE_PLAYING and L.PAUSE or L.PLAY
    end)
    play:SetPoint("LEFT", previous, "RIGHT", 5, 0)
    UI.playButton = play

    local stop = IconButton(frame, "stop", 24, function() ns:Stop() end, L.STOP, L.STOP_TIP)
    stop:SetPoint("LEFT", play, "RIGHT", 5, 0)

    local nextTrack = IconButton(frame, "next", 24, function() ns:Next() end, L.NEXT)
    nextTrack:SetPoint("LEFT", stop, "RIGHT", 5, 0)

    local repeatMode = IconButton(frame, "repeat", 22, function() ns:ToggleRepeat() end, L.REPEAT, L.ONE_WAY_TIP)
    repeatMode:SetPoint("RIGHT", frame, "TOPRIGHT", -8, -70)

    local shuffle = IconButton(frame, "shuffle", 22, function() ns:ToggleShuffle() end, L.SHUFFLE, L.ONE_WAY_TIP)
    shuffle:SetPoint("RIGHT", repeatMode, "LEFT", -5, 0)
end

local function BuildVolumeRow(frame)
    local label = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("LEFT", frame, "BOTTOMLEFT", 9, 14)
    label:SetText(L.VOLUME)
    label:SetTextColor(DIM[1], DIM[2], DIM[3])

    local value = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    value:SetPoint("RIGHT", frame, "BOTTOMRIGHT", -9, 14)
    value:SetJustifyH("RIGHT")
    UI.volumeText = value

    local slider = CreateFrame("Slider", nil, frame)
    slider:SetOrientation("HORIZONTAL")
    slider:SetHeight(14)
    slider:SetPoint("LEFT", label, "RIGHT", 8, 0)
    slider:SetPoint("RIGHT", frame, "BOTTOMRIGHT", -46, 14)
    slider:SetMinMaxValues(0, 100)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:EnableMouseWheel(true)

    local track = Fill(slider, "BACKGROUND", 1, 1, 1, 0.12)
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetHeight(4)

    local thumb = Fill(slider, "OVERLAY", ACCENT[1], ACCENT[2], ACCENT[3], 1)
    thumb:SetSize(6, 14)
    slider:SetThumbTexture(thumb)
    slider.thumb = thumb

    local filled = Fill(slider, "ARTWORK", ACCENT[1], ACCENT[2], ACCENT[3], 0.55)
    filled:SetPoint("LEFT", track, "LEFT", 0, 0)
    filled:SetPoint("RIGHT", thumb, "CENTER", 0, 0)
    filled:SetHeight(4)
    slider.filled = filled

    slider:SetScript("OnValueChanged", function(self, newValue)
        -- Ignore the changes made by Refresh() itself.
        if not self.refreshing then
            ns:SetVolume(newValue)
        end
    end)
    slider:SetScript("OnMouseWheel", function(_, delta)
        ns:AdjustVolume(delta * 5)
    end)
    slider:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            ns:SetVolume(nil)
        end
    end)
    slider:SetScript("OnEnter", function(self)
        ShowTooltip(self, L.VOLUME, L.VOLUME_TIP)
    end)
    slider:SetScript("OnLeave", HideTooltip)
    UI.slider = slider
end

local function BuildWindow()
    local frame = CreateFrame("Frame", "ForeverMusicPlayerFrame", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not ns.db.window.locked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        ns:AdjustVolume(delta * 5)
    end)
    frame:SetScript("OnHide", function()
        UI:TogglePlatformMenu(false)
    end)

    Panel(frame)
    BuildTitleBar(frame)
    BuildPlatformRow(frame)
    BuildTransportRow(frame)
    BuildVolumeRow(frame)
    UI.frame = frame
end

-- Platform menu -----------------------------------------------------------------

local ROW_HEIGHT = 20

local function BuildPlatformMenu()
    -- Invisible full-screen button: a click anywhere else closes the menu.
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("DIALOG")
    catcher:SetScript("OnClick", function()
        UI:TogglePlatformMenu(false)
    end)
    catcher:Hide()

    local menu = CreateFrame("Frame", nil, catcher)
    menu:SetSize(UI.selector:GetWidth(), ROW_HEIGHT * ns.PLATFORM_COUNT + 4)
    menu:SetPoint("TOPLEFT", UI.selector, "BOTTOMLEFT", 0, -2)
    menu:SetFrameStrata("DIALOG")
    menu:SetFrameLevel(catcher:GetFrameLevel() + 5)
    menu:EnableMouse(true)
    Panel(menu)

    menu.rows = {}
    for id = 0, ns.PLATFORM_COUNT - 1 do
        local platform = ns.PLATFORMS[id]
        local row = CreateFrame("Button", nil, menu)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -2 - id * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -2, -2 - id * ROW_HEIGHT)

        row.bg = Fill(row, "BACKGROUND", 1, 1, 1, 0)
        row.bg:SetAllPoints(row)

        row.dot = Fill(row, "ARTWORK", platform.color[1], platform.color[2], platform.color[3], 1)
        row.dot:SetSize(8, 8)
        row.dot:SetPoint("LEFT", row, "LEFT", 5, 0)

        row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row.dot, "RIGHT", 6, 0)
        row.label:SetText(platform.name)

        row:SetScript("OnEnter", function(self)
            self.bg:SetColorTexture(1, 1, 1, 0.15)
            if id == 0 then
                ShowTooltip(self, L.PLATFORM_AUTO, L.PLATFORM_AUTO_TIP)
            end
        end)
        row:SetScript("OnLeave", function(self)
            self.bg:SetColorTexture(1, 1, 1, 0)
            HideTooltip()
        end)
        row:SetScript("OnClick", function()
            ns:SetPlatform(id)
            UI:TogglePlatformMenu(false)
        end)
        menu.rows[id] = row
    end

    UI.menuCatcher = catcher
    UI.menu = menu
end

function UI:TogglePlatformMenu(show)
    if not self.menuCatcher then
        return
    end
    if show == nil then
        show = not self.menuCatcher:IsShown()
    end
    self.menu:SetScale(ns.db.window.scale)
    self.menuCatcher:SetShown(show)
end

-- Minimap button ----------------------------------------------------------------

local function PlaceMinimapButton(button)
    local angle = math.rad(ns.db.minimap.angle)
    local radius = Minimap:GetWidth() / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

-- While dragging, the button follows the cursor around the minimap.
local function FollowCursor(button)
    local centerX, centerY = Minimap:GetCenter()
    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local angle = math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX))
    ns.db.minimap.angle = angle % 360
    PlaceMinimapButton(button)
end

local function BuildMinimapButton()
    local button = CreateFrame("Button", "ForeverMusicPlayerMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(24, 24)
    background:SetPoint("CENTER", button, "CENTER", 0, 1)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", button, "CENTER", 0, 1)
    icon:SetTexture(Icon("icon"))

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(50, 50)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            ns:Toggle()
        else
            UI:ToggleWindow()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", FollowCursor)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L.TITLE, 1, 1, 1)
        GameTooltip:AddLine(L.MINIMAP_LEFT, 0.80, 0.80, 0.80)
        GameTooltip:AddLine(L.MINIMAP_RIGHT, 0.80, 0.80, 0.80)
        GameTooltip:AddLine(L.MINIMAP_DRAG, 0.80, 0.80, 0.80)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", HideTooltip)

    PlaceMinimapButton(button)
    UI.minimapButton = button
end

-- Keeping the display in sync ----------------------------------------------------

local STATE_TEXT = {
    playing = L.STATE_PLAYING,
    paused = L.STATE_PAUSED,
    stopped = L.STATE_STOPPED,
}

-- Position, size and visibility, from the saved settings.
function UI:ApplyLayout()
    local window = ns.db.window
    local frame = self.frame
    frame:SetScale(window.scale)
    frame:ClearAllPoints()
    frame:SetPoint(window.point, UIParent, window.relPoint, window.x, window.y)
    frame:SetShown(window.shown)

    self.minimapButton:SetShown(not ns.db.minimap.hide)
    PlaceMinimapButton(self.minimapButton)
end

-- What the window shows: state, platform and volume.
function UI:Refresh()
    local db = ns.db

    self.playButton.icon:SetTexture(Icon(ns.state == ns.STATE_PLAYING and "pause" or "play"))

    local color = STATE_COLORS[ns.state]
    self.status:SetText(STATE_TEXT[ns.state])
    self.status:SetTextColor(color[1], color[2], color[3])

    local platform = ns.PLATFORMS[db.platform]
    self.selector.label:SetText(platform.name)
    self.selector.dot:SetColorTexture(platform.color[1], platform.color[2], platform.color[3], 1)

    local slider = self.slider
    local thumbColor = db.volume and ACCENT or DIM
    slider.refreshing = true
    slider:SetValue(db.volume or 100)
    slider.refreshing = false
    slider.thumb:SetColorTexture(thumbColor[1], thumbColor[2], thumbColor[3], 1)
    slider.filled:SetColorTexture(thumbColor[1], thumbColor[2], thumbColor[3], 0.55)
    self.volumeText:SetText(db.volume and (db.volume .. "%") or L.VOLUME_UNMANAGED)
end

function UI:ToggleWindow(show)
    local window = ns.db.window
    if show == nil then
        show = not window.shown
    end
    window.shown = show and true or false
    self.frame:SetShown(window.shown)
end

function UI:Init()
    BuildWindow()
    BuildPlatformMenu()
    BuildMinimapButton()
    self:ApplyLayout()
    self:Refresh()
    ns:OnChange(function(what)
        if what == "options" then
            UI:ApplyLayout()
        end
        UI:Refresh()
    end)
end
