local ITEM_ID = 280612
local BUFF_IDS = { 1309410, 1321139 }
local events = CreateFrame("Frame")
local button, holder, hideButton, hideHolder, settings, db
local preview = false
local lastCombatEnd
local Refresh
local settingsCategory
local fadeStart, reminderVisible
local temporarilySuppressed = false
local hadTorchBuff

local function UpdateFade()
    if not button or not hideHolder or InCombatLockdown() then return end
    if temporarilySuppressed and not preview then return end
    local now = GetTime()
    local hovering = reminderVisible and not preview and db.fadeEnabled
        and (button:IsMouseOver()
        or NightWatchTorchDismiss:IsMouseOver()
        or (db.showHideButton and hideButton:IsMouseOver()))
    if not reminderVisible or preview or not db.fadeEnabled or hovering then
        fadeStart = now
    end
    fadeStart = fadeStart or now
    local alpha = 1
    if reminderVisible and not preview and db.fadeEnabled and not hovering then
        alpha = 1 - math.max(0, math.min(1, (now - fadeStart - db.fadeSeconds) / 0.5))
    end
    holder:SetAlpha(alpha)
    hideHolder:SetAlpha(alpha)
end

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

local mealNames = { ["Food"] = true, ["Drink"] = true, ["Food & Drink"] = true, ["Refreshment"] = true }
local function IsEatingOrDrinking()
    -- Match active consumption buffs, not the long-lived Well Fed bonus.
    if C_Spell and C_Spell.GetSpellName then
        for _, id in ipairs({ 433, 430, 160903 }) do
            local name = C_Spell.GetSpellName(id)
            if name then mealNames[name] = true end
        end
    end
    for index = 1, 255 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
        if not aura then break end
        if aura.name and not (issecretvalue and issecretvalue(aura.name)) and mealNames[aura.name] then
            return true
        end
    end
    return false
end

Refresh = function()
    -- Track real zone changes even in combat; subzone changes do not reset Hide.
    if db then
        local zone = GetRealZoneText()
        if zone and zone ~= "" then
            if db.lastZone and db.lastZone ~= zone and zone == db.zone then
                db.dismissed = nil
                db.hiddenUntil = 0
                fadeStart = nil
            end
            db.lastZone = zone
        end
    end
    -- Never inspect combat auras or change protected frames in combat.
    if not button or InCombatLockdown() then return end
    local hasTorchBuff = HasTorchBuff()
    -- A lit torch resumes reminders, including one already active at login/reload.
    -- Only do this on first observation or a new buff, so Off still works afterward.
    if hasTorchBuff and hadTorchBuff ~= true then
        db.enabled = true
        db.dismissed = nil
        db.hiddenUntil = 0
        fadeStart = nil
    end
    hadTorchBuff = hasTorchBuff
    local wasSuppressed = temporarilySuppressed
    temporarilySuppressed = false
    local show = preview and db.enabled
    if settings then settings.showHelper:SetChecked(db.enabled) end
    local action = not preview and "item" or nil
    if button:GetAttribute("type1") ~= action then button:SetAttribute("type1", action) end
    hideButton:SetText("Hide")
    if not preview and db.enabled and not db.dismissed and GetRealZoneText() == db.zone
        and GetServerTime() >= (db.hiddenUntil or 0)
        and (not lastCombatEnd or GetTime() >= lastCombatEnd + db.combatDelay)
        and not UnitIsDeadOrGhost("player") and not hasTorchBuff then
        local bag, slot = FindTorch()
        if bag then
            local start, duration, enabled = C_Container.GetContainerItemCooldown(bag, slot)
            local info = C_Container.GetContainerItemInfo(bag, slot)
            show = info and not info.isLocked and enabled == 1
                and (start == 0 or start + duration <= GetTime())
            if show and (UnitCastingInfo("player") or UnitChannelInfo("player") or IsEatingOrDrinking()) then
                temporarilySuppressed = true
                show = false
            end
        end
    end
    button:SetShown(not not show)
    hideButton:SetShown(not not (show and db.showHideButton))
    if (not show and not temporarilySuppressed)
        or (show and not reminderVisible and not wasSuppressed) then fadeStart = nil end
    reminderVisible = not not show
    UpdateFade()
end

local function OpenSettings()
    if InCombatLockdown() then Say("Open settings after combat ends."); return end
    if not settings then
        settings = CreateFrame("Frame", "NightWatchTorchSettings", UIParent, "BackdropTemplate")
        settings:SetSize(420, 502)
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

        settings.showHelper = CreateFrame("CheckButton", "NightWatchTorchShowHelper", settings, "UICheckButtonTemplate")
        settings.showHelper:SetPoint("TOPLEFT", 20, -118)
        settings.showHelper.Text:SetText("Show torch helper")
        settings.showHelper:SetScript("OnClick", function(self)
            db.enabled = not not self:GetChecked()
            if db.enabled then db.hiddenUntil = 0; db.dismissed = nil end
            Refresh()
        end)

        settings.showHide = CreateFrame("CheckButton", "NightWatchTorchShowHide", settings, "UICheckButtonTemplate")
        settings.showHide:SetPoint("TOPLEFT", 20, -154)
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
        settings.minutes = Field("Hide duration (minutes, 1-1440)", -206, "NightWatchTorchMinutes")
        settings.delay = Field("Delay after combat (seconds, 0-600)", -246, "NightWatchTorchDelay")
        settings.fade = CreateFrame("CheckButton", "NightWatchTorchFadeEnabled", settings, "UICheckButtonTemplate")
        settings.fade:SetPoint("TOPLEFT", 20, -274)
        settings.fade.Text:SetText("Fade buttons when not hovered")
        settings.fade:SetScript("OnClick", function(self)
            db.fadeEnabled = not not self:GetChecked()
            fadeStart = nil
            Refresh()
        end)
        settings.fadeSeconds = Field("Fade after (seconds, 1-600)", -322, "NightWatchTorchFadeSeconds")
        settings.message = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        settings.message:SetPoint("TOPLEFT", 24, -359)
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
            local fadeSeconds = tonumber(settings.fadeSeconds:GetText())
            if not minutes or minutes ~= minutes or minutes < 1 or minutes > 1440
                or not delay or delay ~= delay or delay < 0 or delay > 600 then
                settings.message:SetText("Enter 1-1440 minutes and 0-600 seconds, then click Save.")
                return
            end
            if not fadeSeconds or fadeSeconds ~= fadeSeconds or fadeSeconds < 1 or fadeSeconds > 600 then
                settings.message:SetText("Enter a fade time from 1 to 600 seconds, then click Save.")
                return
            end
            db.hideMinutes, db.combatDelay = minutes, delay
            db.fadeSeconds = fadeSeconds
            fadeStart = nil
            settings.fadeSeconds:ClearFocus()
            settings.minutes:ClearFocus()
            settings.delay:ClearFocus()
            settings.message:SetText("Saved. Close this window to leave preview mode.")
            Refresh()
        end
        SmallButton("NightWatchTorchSave", "Save", 24, 26, 90, Save)
        SmallButton(nil, "Show again now", 24, 64, 160, function()
            db.dismissed = nil
            db.hiddenUntil = 0
            fadeStart = nil
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
        settings.fadeSeconds:SetScript("OnEnterPressed", Save)
        settings:SetScript("OnHide", function()
            preview = false
            fadeStart = nil
            Refresh()
        end)
    end
    settings.minutes:SetText(tostring(db.hideMinutes))
    settings.showHide:SetChecked(db.showHideButton)
    settings.delay:SetText(tostring(db.combatDelay))
    settings.fade:SetChecked(db.fadeEnabled)
    settings.fadeSeconds:SetText(tostring(db.fadeSeconds))
    settings.message:SetText("Changes to the numbers take effect when you click Save.")
    preview = true
    settings:Show()
    Refresh()
end

local function RegisterOptions()
    if settingsCategory or not Settings or not Settings.RegisterCanvasLayoutCategory then return end
    local panel = CreateFrame("Frame", "NightWatchTorchOptions")
    panel:Hide()
    panel.name = "Night Watch Torch"
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Night Watch Torch")
    local description = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    description:SetPoint("TOPLEFT", 16, -52)
    description:SetWidth(500)
    description:SetJustifyH("LEFT")
    description:SetText("Show or hide the torch helper, set its timers, and move the buttons in the settings window. You can also open it with /nwt.")
    local open = CreateFrame("Button", "NightWatchTorchOpenOptions", panel, "UIPanelButtonTemplate")
    open:SetSize(260, 28)
    open:SetPoint("TOPLEFT", 16, -112)
    open:SetText("Open settings and move buttons")
    open:SetScript("OnClick", function()
        if InCombatLockdown() then Say("Open settings after combat ends."); return end
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        OpenSettings()
    end)
    settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(settingsCategory)
end

-- Keep the decoration on the action button so it shares visibility and fading.
local function StyleHelper(control, title)
    control:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    control:SetBackdropColor(0.055, 0.045, 0.035, 0.96)
    control:SetBackdropBorderColor(0.65, 0.51, 0.28, 1)
    local text = control:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER")
    control:SetFontString(text)
    control:SetNormalFontObject(GameFontHighlightSmall)
    control:SetHighlightFontObject(GameFontNormalSmall)
    local highlight = control:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetPoint("TOPLEFT", 4, -4)
    highlight:SetPoint("BOTTOMRIGHT", -4, 4)
    highlight:SetColorTexture(1, 0.82, 0.45, 0.10)
    control:SetHighlightTexture(highlight)
    if title then
        local icon = control:CreateTexture(nil, "ARTWORK")
        icon:SetSize(28, 28)
        icon:SetPoint("LEFT", 9, 0)
        icon:SetTexture(C_Item.GetItemIconByID(ITEM_ID))
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local heading = control:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        heading:SetPoint("TOPLEFT", 45, -9)
        heading:SetText(title)
        local label = control:GetFontString()
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", 45, -24)
        label:SetJustifyH("LEFT")
    end
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
    -- Move the former zero default to ten once; preserve custom nonzero delays.
    if not db.delayDefault10Applied then
        if db.combatDelay == nil or db.combatDelay == 0 then db.combatDelay = 10 end
        db.delayDefault10Applied = true
    end
    db.combatDelay = Number(db.combatDelay, 10, 0, 600)
    db.fadeEnabled = db.fadeEnabled == true
    db.fadeSeconds = Number(db.fadeSeconds, 10, 1, 600)
    db.hiddenUntil = Number(db.hiddenUntil, 0, 0, GetServerTime() + 86400)
    RegisterOptions()

    -- A secure parent handles combat hiding without addon code touching it.
    holder = CreateFrame("Frame", "NightWatchTorchHolder", UIParent, "SecureHandlerStateTemplate")
    holder:SetSize(190, 46)
    Place(holder, "position", -160)
    RegisterStateDriver(holder, "visibility", "[combat] hide; show")

    button = CreateFrame("Button", "NightWatchTorchButton", holder, "SecureActionButtonTemplate,BackdropTemplate")
    button:SetAllPoints(holder)
    StyleHelper(button, "Night Watch Torch")
    button:SetText("Light Torch")
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetAttribute("type1", "item")
    button:SetAttribute("item1", "item:" .. ITEM_ID)
    EnableDrag(button, holder, "position")
    button:SetScript("OnEnter", function(self)
        UpdateFade()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(ITEM_ID)
        GameTooltip:AddLine("Click to light your torch.", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:Hide()

    local dismiss = CreateFrame("Button", "NightWatchTorchDismiss", button, "UIPanelCloseButton")
    dismiss:SetSize(20, 20)
    dismiss:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
    dismiss:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        db.dismissed = true
        GameTooltip:Hide()
        Refresh()
        Say("Hidden until combat ends, you use your torch, or you re-enter the zone. /nwt show restores it now.")
    end)
    dismiss:SetScript("OnEnter", function(self)
        UpdateFade()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Hide torch helper")
        GameTooltip:AddLine("Returns after combat, using your torch, or re-entering the zone. /nwt show restores it now.", 1, 1, 1)
        GameTooltip:Show()
    end)
    dismiss:SetScript("OnLeave", function() GameTooltip:Hide() end)

    hideHolder = CreateFrame("Frame", "NightWatchTorchHideHolder", UIParent, "SecureHandlerStateTemplate")
    hideHolder:SetSize(80, 24)
    Place(hideHolder, "hidePosition", -198)
    RegisterStateDriver(hideHolder, "visibility", "[combat] hide; show")
    hideButton = CreateFrame("Button", "NightWatchTorchHideButton", hideHolder, "BackdropTemplate")
    hideButton:SetAllPoints(hideHolder)
    StyleHelper(hideButton)
    hideButton:SetScript("OnEnter", UpdateFade)
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
        UpdateFade()
    end)
    Refresh()
end

events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_ENABLED" then
        lastCombatEnd = GetTime()
        fadeStart = nil
        -- Combat can remove a torch before its lit aura was observed. Re-arm
        -- enabled reminders without relying on that missed aura transition.
        if db and db.enabled then
            db.dismissed = nil
            db.hiddenUntil = 0
        end
    end
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
        if db.enabled then db.dismissed = nil; db.hiddenUntil = 0 end
        Say(db.enabled and "Enabled." or "Disabled.")
    elseif command == "zone" then
        db.zone = GetRealZoneText()
        Say("Zone set to " .. db.zone .. ".")
    elseif command == "reset" then
        db.zone = "Duskwood"
        db.enabled = true
        db.dismissed = nil
        db.hiddenUntil = 0
        Say("Enabled for Duskwood.")
    elseif command == "" or command == "settings" or command == "options" then
        OpenSettings()
    elseif command == "show" then
        db.dismissed = nil
        db.hiddenUntil = 0
        fadeStart = nil
    else
        Say((db.enabled and "Enabled" or "Disabled") .. " in " .. db.zone .. ".")
        Say("/nwt: settings. /nwt zone: current zone. /nwt on or off. /nwt show: clear hide timer. /nwt reset: Duskwood.")
    end
    Refresh()
end
