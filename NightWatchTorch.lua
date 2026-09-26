local ITEM_ID = 280612
local BUFF_IDS = { 1309410, 1321139 }
local events = CreateFrame("Frame")
local button, holder, db

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

local function Refresh()
    -- Never inspect combat auras or change protected frames in combat.
    if not button or InCombatLockdown() then return end
    local show = false
    if db.enabled and GetRealZoneText() == db.zone
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
end

local function Initialize()
    if button or InCombatLockdown() then return end
    NightWatchTorchDB = type(NightWatchTorchDB) == "table" and NightWatchTorchDB or {}
    db = NightWatchTorchDB
    if db.enabled == nil then db.enabled = true end
    if type(db.zone) ~= "string" or db.zone == "" then db.zone = "Duskwood" end

    -- A secure parent handles combat hiding without addon code touching it.
    holder = CreateFrame("Frame", "NightWatchTorchHolder", UIParent, "SecureHandlerStateTemplate")
    holder:SetSize(160, 42)
    holder:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
    RegisterStateDriver(holder, "visibility", "[combat] hide; show")

    button = CreateFrame("Button", "NightWatchTorchButton", holder, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    button:SetAllPoints(holder)
    button:SetText("Light Torch")
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetAttribute("type1", "item")
    button:SetAttribute("item1", "item:" .. ITEM_ID)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(ITEM_ID)
        GameTooltip:AddLine("Click to light your torch.", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:Hide()
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
    else
        Say((db.enabled and "Enabled" or "Disabled") .. " in " .. db.zone .. ".")
        Say("/nwt zone: use your current zone. /nwt on or off. /nwt reset: Duskwood.")
    end
    Refresh()
end
