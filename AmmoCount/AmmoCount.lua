-- AmmoCount: Hunter-only. Shows "current / max" ammo over each equipped quiver / ammo pouch.
local _, playerClass = UnitClass("player")
if playerClass ~= "HUNTER" then return end   -- non-hunters: nothing is created, no events registered

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------
local DEFAULTS = {
    yellow = 50,   -- % at/below which text turns yellow ("getting low")
    red    = 20,   -- % at/below which text turns red ("very low")
    size   = 15,   -- font size of the current count (max count is 2 smaller)
    hideBlizz = true, -- hide Blizzard's own ammo number (backpack + ammo bag buttons)
}
local COLORS = {
    white  = { 1, 1, 1 },
    yellow = { 1, 0.82, 0 },
    red    = { 1, 0.1, 0.1 },
}
local DEFAULT_STACK = 200
local FIRST_BAG, LAST_BAG = 1, 4   -- equipped bag slots (0 = backpack)

------------------------------------------------------------------------
-- API compatibility wrappers
------------------------------------------------------------------------
local CC = C_Container
local GetNumSlots = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
local GetNumFree  = (CC and CC.GetContainerNumFreeSlots) or GetContainerNumFreeSlots

local function GetSlotInfo(bag, slot)
    if CC and CC.GetContainerItemInfo then
        local info = CC.GetContainerItemInfo(bag, slot)
        if info then return info.stackCount or 1, info.itemID end
    elseif GetContainerItemInfo then
        local _, count, _, _, _, _, _, _, _, itemID = GetContainerItemInfo(bag, slot)
        if count then return count, itemID end
    end
end

local function GetMaxStack(itemID)
    if itemID then
        if C_Item and C_Item.GetItemMaxStackSizeByID then
            local m = C_Item.GetItemMaxStackSizeByID(itemID)
            if m and m > 0 then return m end
        end
        local m = select(8, GetItemInfo(itemID))
        if m and m > 0 then return m end
    end
    return DEFAULT_STACK
end

------------------------------------------------------------------------
-- Ammo bag scanning
------------------------------------------------------------------------
-- bag family flags: 1 = quiver, 2 = ammo pouch
local function IsAmmoBag(bag)
    local numSlots = GetNumSlots(bag)
    if not numSlots or numSlots == 0 then return false end
    local _, bagFamily = GetNumFree(bag)
    return bagFamily and bagFamily > 0 and bit.band(bagFamily, 3) ~= 0
end

local function ScanBag(bag)
    if not IsAmmoBag(bag) then return nil end
    local numSlots = GetNumSlots(bag)
    local total, stackSize = 0, nil
    for slot = 1, numSlots do
        local count, itemID = GetSlotInfo(bag, slot)
        if count then
            total = total + count
            stackSize = stackSize or GetMaxStack(itemID)
        end
    end
    return total, numSlots * (stackSize or DEFAULT_STACK)
end

------------------------------------------------------------------------
-- Overlay frames
------------------------------------------------------------------------
local overlays = {}
local fallback

local function FindBagButton(bag)
    local b = _G["CharacterBag" .. (bag - 1) .. "Slot"]
    if b then return b end
    if BagsBar and BagsBar.buttons then
        for _, btn in ipairs(BagsBar.buttons) do
            if btn.GetBagID and btn:GetBagID() == bag then return btn end
        end
    end
end

local function MakeOverlay(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:SetFrameLevel(parent:GetFrameLevel() + 10)
    f.cur = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    f.max = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    f.fontPath = f.cur:GetFont()
    f.max:SetTextColor(0.9, 0.9, 0.9)
    return f
end

local function ApplyFont(o)
    local size = AmmoCountDB.size
    o.cur:SetFont(o.fontPath, size, "OUTLINE")
    o.max:SetFont(o.fontPath, math.max(size - 2, 6), "OUTLINE")
    local off = math.ceil(size / 2)
    o.cur:ClearAllPoints()
    o.cur:SetPoint("CENTER", o, "CENTER", 0, off)
    o.max:ClearAllPoints()
    o.max:SetPoint("CENTER", o, "CENTER", 0, -off + 1)
end

local function GetFallback()
    if fallback then return fallback end
    fallback = CreateFrame("Frame", "AmmoCountFallbackFrame", UIParent)
    fallback:SetSize(40, 40)
    fallback:SetMovable(true)
    fallback:EnableMouse(true)
    fallback:RegisterForDrag("LeftButton")
    fallback:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
    fallback:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        AmmoCountDB.pos = { p, rp, x, y }
    end)
    local pos = AmmoCountDB.pos
    if pos then fallback:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else fallback:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -260, 80) end
    fallback.overlay = MakeOverlay(fallback)
    return fallback
end

local function ResetFallbackPosition()
    AmmoCountDB.pos = nil
    if fallback then
        fallback:ClearAllPoints()
        fallback:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -260, 80)
    end
end

-- Blizzard's built-in ammo number: hide it on the backpack (where it bugs out)
-- and on any bag button that holds an ammo bag (ours replaces it).
local hooked, hidden = {}, {}

local function SetBlizzCountHidden(fs, hide)
    if not fs then return end
    if not hooked[fs] then
        hooked[fs] = true
        -- Blizzard re-sets/re-shows the text on updates, so re-apply when it does
        if fs.SetText then
            hooksecurefunc(fs, "SetText", function(self) if hidden[self] then self:SetAlpha(0) end end)
        end
        if fs.Show then
            hooksecurefunc(fs, "Show", function(self) if hidden[self] then self:SetAlpha(0) end end)
        end
    end
    hidden[fs] = hide or nil
    fs:SetAlpha(hide and 0 or 1)
end

local function GetCountRegion(button)
    if not button then return nil end
    local name = button:GetName()
    return (name and _G[name .. "Count"]) or button.Count
end

local function UpdateBlizzCounts()
    local on = AmmoCountDB.hideBlizz and true or false
    SetBlizzCountHidden(GetCountRegion(MainMenuBarBackpackButton), on)
    for bag = FIRST_BAG, LAST_BAG do
        local fs = GetCountRegion(FindBagButton(bag))
        if fs then SetBlizzCountHidden(fs, on and IsAmmoBag(bag)) end
    end
end

local function ColorFor(cur, max)
    local pct = (max > 0) and (cur / max * 100) or 0
    if pct <= AmmoCountDB.red then return COLORS.red
    elseif pct <= AmmoCountDB.yellow then return COLORS.yellow end
    return COLORS.white
end

local function Update()
    UpdateBlizzCounts()
    local used = {}
    local fallbackUsed = false
    for bag = FIRST_BAG, LAST_BAG do
        local cur, max = ScanBag(bag)
        if cur then
            local btn = FindBagButton(bag)
            local o = btn and (overlays[btn] or MakeOverlay(btn))
            if btn then overlays[btn] = o
            else
                o = GetFallback().overlay   -- no bag button found: use a small movable box
                fallbackUsed = true
            end
            ApplyFont(o)
            local c = ColorFor(cur, max)
            o.cur:SetText(cur)
            o.cur:SetTextColor(c[1], c[2], c[3])
            o.max:SetText(max)
            o:Show()
            if fallbackUsed and not btn then fallback:Show() end
            used[o] = true
        end
    end
    for _, o in pairs(overlays) do if not used[o] then o:Hide() end end
    if fallback and not fallbackUsed then fallback:Hide() end
end

------------------------------------------------------------------------
-- Safe update + helpers
------------------------------------------------------------------------
local lastErr
local function SafeUpdate()
    local ok, err = pcall(Update)
    if not ok and err ~= lastErr then
        lastErr = err
        print("|cff33ff99AmmoCount|r error: " .. tostring(err))
    end
end

local pending
local function Queue()
    if pending then return end
    pending = true
    C_Timer.After(0.2, function() pending = false; SafeUpdate() end)
end

local function say(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99AmmoCount:|r " .. text)
end

local function Clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-- The two color limits are kept in order: red is never above yellow.
local function SetYellow(v)
    v = Clamp(v, 1, 100)
    AmmoCountDB.yellow = v
    if AmmoCountDB.red > v then AmmoCountDB.red = v end
end
local function SetRed(v)
    AmmoCountDB.red = Clamp(v, 0, AmmoCountDB.yellow)
end

local function Debug()
    say("debug:")
    for bag = 0, 5 do
        local slots = GetNumSlots(bag)
        local free, fam = GetNumFree(bag)
        local btn = (bag >= 1 and bag <= 4) and FindBagButton(bag) or nil
        local cur, max = ScanBag(bag)
        print(("  bag %d: slots=%s free=%s family=%s button=%s scan=%s/%s"):format(
            bag, tostring(slots), tostring(free), tostring(fam),
            btn and (btn:GetName() or "unnamed") or "none", tostring(cur), tostring(max)))
    end
end

------------------------------------------------------------------------
-- Settings window. Built the same way as PetHealthWatch / RangeHelper (the
-- game's own frame template, arrow steppers, bottom button bar) so the addons
-- look and behave alike. Each control registers a "refresher" that redraws it
-- from the saved settings.
------------------------------------------------------------------------
local settings
local refreshers = {}

local function RefreshUI()
    if not settings or not settings:IsShown() or not AmmoCountDB then return end
    for _, fn in ipairs(refreshers) do fn() end
end

-- Try several templates; use the first one this client knows about.
local function TryCreate(frameType, name, parent, templates)
    for _, tpl in ipairs(templates) do
        local ok, obj = pcall(CreateFrame, frameType, name, parent, tpl)
        if ok and obj then return obj, tpl end
    end
    return CreateFrame(frameType, name, parent)
end

-- Text label. y is negative (distance down from the top of the parent).
local function WLabel(parent, fontObject, text, x, y, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", fontObject)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetJustifyH("LEFT")
    if width then fs:SetWidth(width) end
    fs:SetText(text)
    return fs
end

local function WHeader(parent, text, x, y)
    return WLabel(parent, "GameFontHighlightLarge", text, x, y)
end

local function HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- Arrow art: the same atlas the game's option sliders use when available,
-- otherwise a plain - / + button.
local function ArrowButton(parent, direction)
    local base = "Minimal_SliderBar_Button_" .. direction
    if HasAtlas(base) then
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(14, 20)
        pcall(function()
            b:SetNormalAtlas(base)
            if HasAtlas(base .. "_Pressed") then b:SetPushedAtlas(base .. "_Pressed") end
            if HasAtlas(base .. "_Disabled") then b:SetDisabledAtlas(base .. "_Disabled") end
            if HasAtlas(base .. "_Highlight") then b:SetHighlightAtlas(base .. "_Highlight") end
        end)
        return b
    end
    local b = TryCreate("Button", nil, parent, { "UIPanelButtonTemplate" })
    b:SetSize(22, 22)
    b:SetText(direction == "Left" and "-" or "+")
    return b
end

-- [<] value [>]. Click = one step, Shift+click = a big step.
-- rangeFn returns: min, max, step, bigStep.  Returns a table with the next y.
local function WStepper(parent, x, y, text, rangeFn, getFn, setFn, tip)
    local st = {}
    st.label = WLabel(parent, "GameFontNormal", text, x, y - 4)
    local minus = ArrowButton(parent, "Left")
    minus:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 185, y - 1)

    local valueFS = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valueFS:SetPoint("LEFT", minus, "RIGHT", 0, 0)
    valueFS:SetWidth(40)
    valueFS:SetJustifyH("CENTER")

    local plus = ArrowButton(parent, "Right")
    plus:SetPoint("LEFT", minus, "RIGHT", 40, 0)

    local function change(dir)
        local lo, hi, step, big = rangeFn()
        local amount = ((IsShiftKeyDown and IsShiftKeyDown()) and big or step) * dir
        setFn(Clamp((getFn() or lo) + amount, lo, hi))
        SafeUpdate()
        RefreshUI()
    end
    minus:SetScript("OnClick", function() change(-1) end)
    plus:SetScript("OnClick", function() change(1) end)

    if tip then
        for _, w in ipairs({ minus, plus }) do
            w:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tip, 1, 1, 1, 1, true)
            end)
            w:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end

    refreshers[#refreshers + 1] = function() valueFS:SetText(tostring(getFn() or "")) end
    st.left, st.right, st.value, st.y = minus, plus, valueFS, y - 28
    return st
end

local function WButton(parent, text, width, point, rel, relPoint, x, y, onClick)
    local b = TryCreate("Button", nil, parent, { "UIPanelButtonTemplate" })
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetPoint(point, rel, relPoint, x, y)
    b:SetScript("OnClick", onClick)
    return b
end

local function WCheck(parent, x, y, text, onClick)
    local c = TryCreate("CheckButton", nil, parent, { "UICheckButtonTemplate" })
    c:SetSize(26, 26)
    c:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    c:SetHitRectInsets(0, -260, 0, 0)
    WLabel(parent, "GameFontNormal", text, x + 30, y - 6)
    c:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    return c
end

-- A small color swatch with a dark edge
local function WSwatch(parent, x, y, color)
    local edge = parent:CreateTexture(nil, "ARTWORK")
    edge:SetColorTexture(0, 0, 0, 1)
    edge:SetSize(16, 16)
    edge:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local fill = parent:CreateTexture(nil, "OVERLAY")
    fill:SetColorTexture(color[1], color[2], color[3], 1)
    fill:SetSize(14, 14)
    fill:SetPoint("CENTER", edge, "CENTER", 0, 0)
end

local function BuildSettings()
    -- Same frame the game's own Options window uses (marble background, gold
    -- border, title bar, bottom button bar), with fallbacks for older clients.
    local win, tpl = TryCreate("Frame", "AmmoCountSettingsFrame", UIParent,
        { "ButtonFrameTemplateNoPortrait", "ButtonFrameTemplate", "BasicFrameTemplateWithInset", "BackdropTemplate" })
    settings = win
    win:SetSize(420, 470)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    win:SetFrameStrata("DIALOG")
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local isButtonFrame = (tpl == "ButtonFrameTemplateNoPortrait" or tpl == "ButtonFrameTemplate")
    if tpl == "ButtonFrameTemplate" then
        pcall(function()
            if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(win) end
        end)
    end
    if isButtonFrame and win.Inset then
        win.Inset:ClearAllPoints()
        win.Inset:SetPoint("TOPLEFT", win, "TOPLEFT", 4, -26)
        win.Inset:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -6, 28)
    end
    if not isButtonFrame and tpl ~= "BasicFrameTemplateWithInset" then
        -- plain fallback look
        if win.SetBackdrop then
            win:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 32,
                insets = { left = 8, right = 8, top = 8, bottom = 8 },
            })
        end
        local closeBtn = TryCreate("Button", nil, win, { "UIPanelCloseButton" })
        closeBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, -4)
    end

    if isButtonFrame and win.SetTitle then
        win:SetTitle("AmmoCount Settings")
    else
        local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", win, "TOP", 0, -6)
        title:SetText("AmmoCount Settings")
    end

    table.insert(UISpecialFrames, "AmmoCountSettingsFrame")   -- Escape closes it

    local lx = 20
    local y = -38

    -- ===== Number colors =====
    WHeader(win, "When do the numbers change color?", lx, y); y = y - 28
    WLabel(win, "GameFontDisableSmall",
        "Based on how full your quiver or ammo pouch is.", lx, y + 4, 380)
    y = y - 20

    local yellowStep = WStepper(win, lx, y, "Yellow at or below (%)",
        function() return 1, 100, 1, 10 end,
        function() return AmmoCountDB.yellow end,
        SetYellow,
        "Click an arrow for one step; hold Shift for a bigger step.")
    y = yellowStep.y
    local redStep = WStepper(win, lx, y, "Red at or below (%)",
        function() return 0, AmmoCountDB.yellow, 1, 10 end,
        function() return AmmoCountDB.red end,
        SetRed,
        "Red can never be higher than yellow. Hold Shift for a bigger step.")
    y = redStep.y + 4

    -- legend: what each color means with the current limits
    local legend = {
        { COLORS.white,  function() return ("Plenty of ammo (over %d%% full)"):format(AmmoCountDB.yellow) end },
        { COLORS.yellow, function() return ("Getting low (%d%% full or less)"):format(AmmoCountDB.yellow) end },
        { COLORS.red,    function() return ("Very low (%d%% full or less)"):format(AmmoCountDB.red) end },
    }
    for _, row in ipairs(legend) do
        WSwatch(win, lx + 4, y, row[1])
        local fs = WLabel(win, "GameFontHighlight", "", lx + 28, y - 1)
        refreshers[#refreshers + 1] = function() fs:SetText(row[2]()) end
        y = y - 22
    end
    y = y - 10

    -- ===== Look =====
    WHeader(win, "How it looks", lx, y); y = y - 28
    local sizeStep = WStepper(win, lx, y, "Number size",
        function() return 8, 24, 1, 3 end,
        function() return AmmoCountDB.size end,
        function(v) AmmoCountDB.size = v end,
        "Size of the ammo count. The max number below it is 2 smaller. Hold Shift for a bigger step.")
    y = sizeStep.y - 10

    -- ===== Blizzard's own number =====
    WHeader(win, "The game's built-in ammo number", lx, y); y = y - 28
    local hideCheck = WCheck(win, lx - 2, y, "Hide the game's own ammo number", function(checked)
        AmmoCountDB.hideBlizz = checked
        SafeUpdate()
    end)
    refreshers[#refreshers + 1] = function() hideCheck:SetChecked(AmmoCountDB.hideBlizz and true or false) end
    y = y - 28
    WLabel(win, "GameFontDisableSmall",
        "Wow Forever currently draws an ammo count on the backpack by mistake. " ..
        "AmmoCount shows a better one on your quiver, so this hides the game's. " ..
        "Untick it to see the game's number again.",
        lx + 28, y + 2, 350)

    -- ===== Bottom =====
    WLabel(win, "GameFontDisableSmall",
        "Tip: click an arrow to change a value, or hold Shift while clicking for a bigger step. Changes apply right away.",
        lx, -418, 380)

    -- these sit in the frame's bottom bar, like the Close button in the game's Options window
    WButton(win, "Reset defaults", 110, "BOTTOMLEFT", win, "BOTTOMLEFT", 12, 4, function()
        for k, v in pairs(DEFAULTS) do AmmoCountDB[k] = v end
        ResetFallbackPosition()
        SafeUpdate()
        RefreshUI()
    end)
    WButton(win, "Debug info", 100, "BOTTOMLEFT", win, "BOTTOMLEFT", 128, 4, Debug)
    WButton(win, "Close", 90, "BOTTOMRIGHT", win, "BOTTOMRIGHT", -10, 4, function() win:Hide() end)

    win:SetScript("OnShow", function() RefreshUI() end)
    win:Hide()
end

local function ToggleSettings()
    if not AmmoCountDB then
        say("Settings aren't loaded yet; try again in a moment.")
        return
    end
    if not settings then BuildSettings() end
    if settings:IsShown() then settings:Hide() else settings:Show() end
end

local function OpenSettings()
    if not AmmoCountDB then
        say("Settings aren't loaded yet; try again in a moment.")
        return
    end
    if not settings then BuildSettings() end
    if not settings:IsShown() then settings:Show() end
end

------------------------------------------------------------------------
-- Entry in the game's Options > AddOns tab: a small info page with a button
-- that opens the settings window. Wrapped in pcall so a different or missing
-- Settings API can never break the addon.
------------------------------------------------------------------------
local panelRegistered = false
local function RegisterOptionsPanel()
    if panelRegistered then return end
    panelRegistered = true

    local panel = CreateFrame("Frame", "AmmoCountOptionsPanel")
    panel.name = "AmmoCount"

    local version = ""
    pcall(function()
        local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
        version = getMeta and getMeta("AmmoCount", "Version") or ""
    end)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText("AmmoCount " .. version)

    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -52)
    desc:SetWidth(560)
    desc:SetJustifyH("LEFT")
    desc:SetText("Shows how much ammo is in your quiver or ammo pouch (current over maximum) " ..
        "on the bag's icon. The number turns yellow when you're getting low and red when " ..
        "you're very low. Hunters only.")

    local open = TryCreate("Button", nil, panel, { "UIPanelButtonTemplate" })
    open:SetSize(160, 26)
    open:SetText("Open settings")
    open:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -120)
    open:SetScript("OnClick", function()
        -- Close the game's options window first so ours isn't hidden behind it
        pcall(function()
            if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        end)
        OpenSettings()
    end)

    local tip = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    tip:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -166)
    tip:SetWidth(560)
    tip:SetJustifyH("LEFT")
    tip:SetText("Type /ammo to open the settings window at any time, or /ammo help for the list of commands.")

    pcall(function()
        if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
            local category = Settings.RegisterCanvasLayoutCategory(panel, "AmmoCount")
            Settings.RegisterAddOnCategory(category)
        elseif InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(panel)
        end
    end)
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local EVENTS = {
    "BAG_UPDATE", "BAG_UPDATE_DELAYED", "BAG_CONTAINER_UPDATE", "PLAYER_ENTERING_WORLD",
    "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED",
}

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        AmmoCountDB = AmmoCountDB or {}
        for k, v in pairs(DEFAULTS) do if AmmoCountDB[k] == nil then AmmoCountDB[k] = v end end
        for _, e in ipairs(EVENTS) do pcall(self.RegisterEvent, self, e) end
        pcall(RegisterOptionsPanel)
        C_Timer.After(1, SafeUpdate)
        C_Timer.After(4, SafeUpdate)   -- retry in case the bag bar wasn't ready yet
    else
        Queue()
    end
end)

------------------------------------------------------------------------
-- Slash commands: /ammo (or /ammocount). With nothing after it, opens the window.
------------------------------------------------------------------------
SLASH_AMMOCOUNT1, SLASH_AMMOCOUNT2 = "/ammo", "/ammocount"
SlashCmdList.AMMOCOUNT = function(msg)
    if not AmmoCountDB then return end
    local cmd, arg = strsplit(" ", (msg or ""):lower(), 2)
    local val = tonumber(arg)

    if cmd == nil or cmd == "" or cmd == "config" or cmd == "options" or cmd == "settings" then
        ToggleSettings()
        return
    elseif cmd == "debug" then
        Debug()
        return
    end

    local changed = true
    if cmd == "yellow" and val then SetYellow(val)
    elseif cmd == "red" and val then SetRed(val)
    elseif cmd == "size" and val then AmmoCountDB.size = Clamp(val, 8, 24)
    elseif cmd == "blizz" and (arg == "on" or arg == "off") then
        AmmoCountDB.hideBlizz = (arg == "off")   -- "blizz on" = show the game's number, "blizz off" = hide it
    elseif cmd == "reset" then
        for k, v in pairs(DEFAULTS) do AmmoCountDB[k] = v end
        ResetFallbackPosition()
    else
        changed = false
    end

    if changed then
        say(("yellow at <= %d%%, red at <= %d%%, size %d, game's ammo number: %s."):format(
            AmmoCountDB.yellow, AmmoCountDB.red, AmmoCountDB.size,
            AmmoCountDB.hideBlizz and "hidden" or "shown"))
    else
        if cmd ~= "help" then say("Unknown or incomplete command '" .. cmd .. "'.") end
        say("Commands:")
        print("  |cff00ff00/ammo|r - open the settings window")
        print("  |cff00ff00/ammo yellow <pct>|r, |cff00ff00/ammo red <pct>|r - color limits (% full)")
        print("  |cff00ff00/ammo size <8-24>|r - number size")
        print("  |cff00ff00/ammo blizz on|off|r - show/hide the game's own ammo number")
        print("  |cff00ff00/ammo reset|r - restore defaults")
        print("  |cff00ff00/ammo debug|r - show what the addon sees in your bags")
    end
    SafeUpdate()
    RefreshUI()
end
