local ITEM_ID = 280612
local BUFF_IDS = { 1309410, 1321139 }
local events = CreateFrame("Frame")
local button, holder, hideButton, hideHolder, settings, db
local preview = false
local lastCombatEnd
local Refresh

local function Number(value, default, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value then return default end
    return math.max(minimum, math.min(maximum, value))
end

local function Place(frame, key, defaultY)
    local position = db[key]
    frame:ClearAllPoints()
    if type(position) == "table" and tonumber(position.x) and tonumber(position.y) then
        frame:SetPoint("CENTER", UIParent, "CENTER", position.x, position.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, defaultY)
    end
end

local function EnableDrag(control, frame, key)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    control:RegisterForDrag("LeftButton")
    control:SetScript("OnDragStart", function()
        if preview and not InCombatLockdown() then frame:StartMoving() end
    end)
    control:SetScript("OnDragStop", function()
        if InCombatLockdown() then return end
        frame:StopMovingOrSizing()
        local x, y = frame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if x and y and ux and uy then
            db[key] = { x = x - ux, y = y - uy }
            Place(frame, key, 0)
        end
    end)
end

local function Say(message)
    print("|cffffcc00Night Watch Torch:|r " .. message)
end

local function FindTorch()
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            if C_Container.GetContainerItemID(bag, slot) == ITEM_ID then
                return bag, slot
            end
        end
    end
end

local function HasTorchBuff()
    for _, spellID in ipairs(BUFF_IDS) do
        if C_UnitAuras.GetPlayerAuraBySpellID(spellID) then
            return true
        end
    end
    return false
end

Refresh = function()
    -- Never inspect combat auras or change protected frames in combat.
    if not button or InCombatLockdown() then return end
    local show = preview
    local action = not preview and "item" or nil
    if button:GetAttribute("type1") ~= action then button:SetAttribute("type1", action) end
    hideButton:SetText("Hide")
    if not preview and db.enabled and GetRealZoneText() == db.zone
        and GetServerTime() >= (db.hiddenUntil or 0)
        and (not lastCombatEnd or GetTime() >= lastCombatEnd + db.combatDelay)
        and not UnitIsDeadOrGhost("player") and not HasTorchBuff() then
        local bag, slot = FindTorch()
        if bag then
            local start, duration, enabled = C_Container.GetContainerItemCooldown(bag, slot)
            local info = C_Container.GetContainerItemInfo(bag, slot)
            show = info and not info.isLocked and enabled == 1
                and (start == 0 or start + duration <= GetTime())
                and not UnitCastingInfo("player") and not UnitChannelInfo("player")
        end
    end
    button:SetShown(not not show)
    hideButton:SetShown(not not (show and db.showHideButton))
end

local function OpenSettings()
    if InCombatLockdown() then Say("Open settings after combat ends."); return end
    if not settings then
        settings = CreateFrame("Frame", "NightWatchTorchSettings", UIParent, "BackdropTemplate")
        settings:SetSize(420, 390)
        settings:SetPoint("CENTER", UIParent, "CENTER", 250, 120)
        settings:SetFrameStrata("DIALOG")
        settings:SetClampedToScreen(true)
        settings:SetMovable(true)
        settings:EnableMouse(true)
        settings:RegisterForDrag("LeftButton")
        settings:SetScript("OnDragStart", function(self) self:StartMoving() end)
        settings:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        settings:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true,
            tileSize = 32, edgeSize = 32, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
        local title = settings:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -20)
        title:SetText("Night Watch Torch")
        local close = CreateFrame("Button", nil, settings, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -5, -5)
        close:SetScript("OnClick", function() settings:Hide() end)
        UISpecialFrames[#UISpecialFrames + 1] = "NightWatchTorchSettings"

        local instructions = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        instructions:SetPoint("TOPLEFT", 24, -54)
        instructions:SetWidth(372)
        instructions:SetJustifyH("LEFT")
        instructions:SetText("Drag a preview button to move it. Enable the Hide button below to preview it. Positions save automatically. Combat temporarily hides previews.")

        settings.showHide = CreateFrame("CheckButton", "NightWatchTorchShowHide", settings, "UICheckButtonTemplate")
        settings.showHide:SetPoint("TOPLEFT", 20, -118)
        settings.showHide.Text:SetText("Show Hide button")
        settings.showHide:SetScript("OnClick", function(self)
            db.showHideButton = not not self:GetChecked()
            if not db.showHideButton then db.hiddenUntil = 0 end
            Refresh()
        end)

        local function Field(label, y, name)
            local text = settings:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            text:SetPoint("TOPLEFT", 24, y)
            text:SetText(label)
            local input = CreateFrame("EditBox", name, settings, "InputBoxTemplate")
            input:SetSize(72, 26)
            input:SetPoint("TOPRIGHT", -30, y + 6)
            input:SetAutoFocus(false)
            input:SetMaxLetters(6)
            input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            return input
        end
        settings.minutes = Field("Hide duration (minutes, 1-1440)", -170, "NightWatchTorchMinutes")
        settings.delay = Field("Delay after combat (seconds, 0-600)", -210, "NightWatchTorchDelay")
        settings.message = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        settings.message:SetPoint("TOPLEFT", 24, -247)
        settings.message:SetWidth(372)
        settings.message:SetJustifyH("LEFT")

        local function SmallButton(name, text, x, y, width, callback)
            local control = CreateFrame("Button", name, settings, "UIPanelButtonTemplate")
            control:SetSize(width, 26)
            control:SetPoint("BOTTOMLEFT", x, y)
            control:SetText(text)
            control:SetScript("OnClick", callback)
            return control
        end
        local function Save()
            local minutes, delay = tonumber(settings.minutes:GetText()), tonumber(settings.delay:GetText())
            if not minutes or minutes ~= minutes or minutes < 1 or minutes > 1440
                or not delay or delay ~= delay or delay < 0 or delay > 600 then
                settings.message:SetText("Enter 1-1440 minutes and 0-600 seconds, then click Save.")
                return
            end
            db.hideMinutes, db.combatDelay = minutes, delay
            settings.minutes:ClearFocus()
            settings.delay:ClearFocus()
            settings.message:SetText("Saved. Close this window to leave preview mode.")
            Refresh()
        end
        SmallButton("NightWatchTorchSave", "Save", 24, 26, 90, Save)
        SmallButton(nil, "Show again now", 24, 64, 160, function()
            db.hiddenUntil = 0
            settings.message:SetText("Hide timer cleared. Normal checks resume when you close settings.")
            Refresh()
        end)
        SmallButton(nil, "Reset positions", 204, 64, 190, function()
            if InCombatLockdown() then
                settings.message:SetText("Wait until combat ends to reset positions.")
                return
            end
            db.position, db.hidePosition = nil, nil
            Place(holder, "position", -160)
            Place(hideHolder, "hidePosition", -198)
            settings.message:SetText("Button positions reset.")
        end)
        SmallButton(nil, "Close", 304, 26, 90, function() settings:Hide() end)
        settings.minutes:SetScript("OnEnterPressed", Save)
        settings.delay:SetScript("OnEnterPressed", Save)
        settings:SetScript("OnHide", function()
            preview = false
            Refresh()
        end)
    end
    settings.minutes:SetText(tostring(db.hideMinutes))
    settings.showHide:SetChecked(db.showHideButton)
    settings.delay:SetText(tostring(db.combatDelay))
    settings.message:SetText("Changes to the numbers take effect when you click Save.")
    preview = true
    settings:Show()
    Refresh()
end

local function Initialize()
    if button or InCombatLockdown() then return end
    NightWatchTorchDB = type(NightWatchTorchDB) == "table" and NightWatchTorchDB or {}
    db = NightWatchTorchDB
    if db.enabled == nil then db.enabled = true end
    if type(db.zone) ~= "string" or db.zone == "" then db.zone = "Duskwood" end
    db.hideMinutes = Number(db.hideMinutes, 5, 1, 1440)
    db.showHideButton = db.showHideButton == true
    if not db.showHideButton then db.hiddenUntil = 0 end
    db.combatDelay = Number(db.combatDelay, 0, 0, 600)
    db.hiddenUntil = Number(db.hiddenUntil, 0, 0, GetServerTime() + 86400)

    -- A secure parent handles combat hiding without addon code touching it.
    holder = CreateFrame("Frame", "NightWatchTorchHolder", UIParent, "SecureHandlerStateTemplate")
    holder:SetSize(160, 42)
    Place(holder, "position", -160)
    RegisterStateDriver(holder, "visibility", "[combat] hide; show")

    button = CreateFrame("Button", "NightWatchTorchButton", holder, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    button:SetAllPoints(holder)
    button:SetText("Light Torch")
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetAttribute("type1", "item")
    button:SetAttribute("item1", "item:" .. ITEM_ID)
    EnableDrag(button, holder, "position")
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(ITEM_ID)
        GameTooltip:AddLine("Click to light your torch.", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:Hide()

    hideHolder = CreateFrame("Frame", "NightWatchTorchHideHolder", UIParent, "SecureHandlerStateTemplate")
    hideHolder:SetSize(132, 26)
    Place(hideHolder, "hidePosition", -198)
    RegisterStateDriver(hideHolder, "visibility", "[combat] hide; show")
    hideButton = CreateFrame("Button", "NightWatchTorchHideButton", hideHolder, "UIPanelButtonTemplate")
    hideButton:SetAllPoints(hideHolder)
    hideButton:SetScript("OnClick", function()
        if preview or InCombatLockdown() then return end
        db.hiddenUntil = GetServerTime() + db.hideMinutes * 60
        Refresh()
    end)
    EnableDrag(hideButton, hideHolder, "hidePosition")
    hideButton:Hide()
    -- Also catches cooldown completion, natural buff expiry and bag changes.
    local elapsed = 0
    events:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= 0.5 then
            elapsed = 0
            Refresh()
        end
    end)
    Refresh()
end

events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_ENABLED" then lastCombatEnd = GetTime() end
    if event == "PLAYER_LOGIN" or event == "PLAYER_REGEN_ENABLED" then
        Initialize()
    end
    if event ~= "UNIT_AURA" or unit == "player" then Refresh() end
end)
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "BAG_UPDATE_DELAYED", "UNIT_AURA" }) do
    events:RegisterEvent(event)
end

SLASH_NIGHTWATCHTORCH1 = "/nwt"
SlashCmdList.NIGHTWATCHTORCH = function(message)
    if not db then Say("Please wait until combat ends."); return end
    local command = (message or ""):lower():match("^%s*(.-)%s*$")
    if command == "on" or command == "off" then
        db.enabled = command == "on"
        Say(db.enabled and "Enabled." or "Disabled.")
    elseif command == "zone" then
        db.zone = GetRealZoneText()
        Say("Zone set to " .. db.zone .. ".")
    elseif command == "reset" then
        db.zone = "Duskwood"
        db.enabled = true
        Say("Enabled for Duskwood.")
    elseif command == "" or command == "settings" or command == "options" then
        OpenSettings()
    elseif command == "show" then
        db.hiddenUntil = 0
    else
        Say((db.enabled and "Enabled" or "Disabled") .. " in " .. db.zone .. ".")
        Say("/nwt: settings. /nwt zone: current zone. /nwt on or off. /nwt show: clear hide timer. /nwt reset: Duskwood.")
    end
    Refresh()
end
