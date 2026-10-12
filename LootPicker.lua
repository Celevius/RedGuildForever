-- Start Bidding window: choose the item without typing anything.
--   * drag an item from your bags onto the slot
--   * or click an item that is still on the corpse, or was seen on a corpse this session
--   * choose where it dropped (price), tick Test mode to try it alone
-- Opens from the minimap menu, and by itself when an officer loots good items in a group.

local _, ns = ...
ns = ns or _G.RedGuildForever

local MIN_QUALITY = 2       -- uncommon and better are listed
local AUTO_OPEN_QUALITY = 3 -- rare and better open the window by itself in a group
local QUALITY_COLORS = {
    [0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd",
    [4] = "ffa335ee", [5] = "ffff8000", [6] = "ffe6cc80", [7] = "ff00ccff",
}

ns.lootSeen = {}   -- { link, quality, onCorpse, at }

------------------------------------------------------------------------
-- Loot on the corpse
------------------------------------------------------------------------
local function quality(link, fromLoot)
    if fromLoot then return fromLoot end
    if C_Item and C_Item.GetItemQualityByID then
        local ok, q = pcall(C_Item.GetItemQualityByID, link)
        if ok and q then return q end
    end
    local color = link and link:match("|c(%x%x%x%x%x%x%x%x)")
    if color then
        for q, c in pairs(QUALITY_COLORS) do if c == color:lower() then return q end end
    end
    return 1
end

local function findSeen(link)
    for i, item in ipairs(ns.lootSeen) do
        if item.link == link then return item, i end
    end
end

-- Reads the open loot window. Returns true when a good new item showed up.
function ns.ScanLoot()
    for _, item in ipairs(ns.lootSeen) do item.onCorpse = false end
    if not GetNumLootItems then return false end
    local good = false
    for slot = 1, GetNumLootItems() or 0 do
        local link = GetLootSlotLink and GetLootSlotLink(slot)
        if link then
            local _, _, _, _, lootQuality = GetLootSlotInfo(slot)
            local q = quality(link, lootQuality)
            if q >= MIN_QUALITY then
                local item = findSeen(link)
                if not item then
                    item = { link = link, quality = q, at = ns.Now() }
                    table.insert(ns.lootSeen, 1, item)
                    if q >= AUTO_OPEN_QUALITY then good = true end
                end
                item.onCorpse = true
            end
        end
    end
    while #ns.lootSeen > 30 do table.remove(ns.lootSeen) end
    ns.Fire("RGF_LOOT_CHANGED")
    return good
end

ns.On("LOOT_OPENED", function()
    local good = ns.ScanLoot()
    local inGroup = (IsInGroup and IsInGroup()) or ns.IsTest()
    if good and ns.Setting("autoOpenLoot") and ns.CanEdit() and inGroup and not (ns.auction and ns.auction.open) then
        ns.OpenPicker()
    end
end)
ns.On("LOOT_SLOT_CLEARED", function() ns.ScanLoot() end)
ns.On("LOOT_CLOSED", function()
    for _, item in ipairs(ns.lootSeen) do item.onCorpse = false end
    ns.Fire("RGF_LOOT_CHANGED")
end)

------------------------------------------------------------------------
-- The window
------------------------------------------------------------------------
if not CreateFrame then return end
local UI = ns.UI

local picker
local state = { link = nil, tier = "normal" }

local function selectItem(link)
    state.link = link
    ns.Fire("RGF_LOOT_CHANGED")
end

-- accept an item the player holds on the cursor (dragged from the bags)
local function takeCursorItem()
    if not GetCursorInfo then return false end
    local kind, _, link = GetCursorInfo()
    if kind == "item" and link then
        if ClearCursor then ClearCursor() end
        selectItem(link)
        UI.sound("PUT_DOWN_SMALL_CHAIN")
        return true
    end
    return false
end

local function buildPicker()
    local f = UI.window("RedGuildForeverPickerFrame", 440, 520, "Start Bidding", "Interface\\Icons\\INV_Misc_Bag_10")
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", -160, 20)

    f.hint = UI.text(f, "GameFontNormal")
    f.hint:SetPoint("TOPLEFT", 66, -32)
    f.hint:SetWidth(340)
    f.hint:SetText("Drag an item onto the slot")
    f.sub = UI.text(f, "GameFontHighlightSmall")
    f.sub:SetPoint("TOPLEFT", f.hint, "BOTTOMLEFT", 0, -3)
    f.sub:SetWidth(340)
    f.sub:SetText("or pick one from the loot below")

    local inset = f.Inset

    -- drop slot
    f.slot = UI.itemButton(inset, 52)
    f.slot:SetPoint("TOPLEFT", 14, -14)
    f.slot:SetScript("OnReceiveDrag", function() takeCursorItem() end)
    f.slot:SetScript("OnClick", function(self)
        if takeCursorItem() then return end
        if self.link and IsModifiedClick and HandleModifiedItemClick then
            pcall(HandleModifiedItemClick, self.link)
        end
    end)
    f.slot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.link then
            GameTooltip:SetHyperlink(self.link)
        else
            GameTooltip:SetText("Drop an item here")
            GameTooltip:AddLine("Pick it up in your bags and let it go on this slot", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    f.slotEmpty = f.slot:CreateTexture(nil, "OVERLAY")
    f.slotEmpty:SetAllPoints()
    f.slotEmpty:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")

    f.itemName = UI.text(inset, "GameFontNormalLarge")
    f.itemName:SetPoint("TOPLEFT", f.slot, "TOPRIGHT", 12, -4)
    f.itemName:SetWidth(320)
    f.price = UI.text(inset, "GameFontHighlightSmall")
    f.price:SetPoint("TOPLEFT", f.itemName, "BOTTOMLEFT", 0, -6)
    f.price:SetWidth(320)

    -- where it dropped
    local tierLabel = UI.text(inset, "GameFontNormalSmall")
    tierLabel:SetPoint("TOPLEFT", 14, -82)
    tierLabel:SetText("Drops from")
    f.tierButtons = {}
    local prev = tierLabel
    for _, tier in ipairs(ns.defaults.tierOrder) do
        local b = UI.button(inset, ns.defaults.tierNames[tier], 100, function()
            state.tier = tier
            ns.Fire("RGF_LOOT_CHANGED")
        end)
        b:SetPoint("LEFT", prev, "RIGHT", prev == tierLabel and 8 or 2, 0)
        f.tierButtons[tier] = b
        prev = b
    end

    f.testNote = UI.text(inset, "GameFontNormalSmall")
    f.testNote:SetPoint("TOPLEFT", 14, -114)
    f.testNote:SetWidth(400)

    -- loot list
    local listTitle = UI.text(inset, "GameFontNormal")
    listTitle:SetPoint("TOPLEFT", 14, -142)
    listTitle:SetText("Loot")
    f.empty = UI.text(inset, "GameFontDisableSmall")
    f.empty:SetPoint("TOPLEFT", 14, -164)
    f.empty:SetWidth(400)
    f.empty:SetWordWrap(true)
    f.empty:SetText("Open a corpse and its items show up here. Items you saw on corpses this session stay in the list.")

    local holder = CreateFrame("Frame", nil, inset)
    holder:SetPoint("TOPLEFT", 0, -158)
    holder:SetPoint("BOTTOMRIGHT")
    f.list = UI.scrollList(holder, 28, function(row)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("LEFT", 6, 0)
        row.name = UI.text(row, "GameFontHighlight")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.name:SetWidth(250)
        row.where = UI.text(row, "GameFontDisableSmall", "RIGHT")
        row.where:SetPoint("RIGHT", -8, 0)
        row.where:SetWidth(110)
        row.selected = row:CreateTexture(nil, "BACKGROUND")
        row.selected:SetAllPoints()
        row.selected:SetColorTexture(1, 0.82, 0, 0.12)
        row:SetScript("OnClick", function(self)
            if self.item then
                selectItem(self.item.link)
                UI.sound("U_CHAT_SCROLL_BUTTON")
            end
        end)
        row:SetScript("OnEnter", function(self)
            if not self.item then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.item.link)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnReceiveDrag", function() takeCursorItem() end)
    end)
    f.list:SetPoint("TOPLEFT", 4, -4)
    f.list:SetPoint("BOTTOMRIGHT", -26, 4)

    -- bottom strip
    f.start = UI.button(f, "Start bidding", 140, function() ns.StartFromPicker() end)
    f.start:SetPoint("BOTTOMRIGHT", -6, 4)
    f.clear = UI.button(f, "Clear list", 100, function()
        wipe(ns.lootSeen)
        state.link = nil
        ns.Fire("RGF_LOOT_CHANGED")
    end)
    f.clear:SetPoint("BOTTOMLEFT", 6, 4)

    f:SetScript("OnReceiveDrag", function() takeCursorItem() end)
    f:HookScript("OnShow", function() ns.RefreshPicker() end)
    return f
end

function ns.RefreshPicker()
    if not picker or not picker:IsShown() then return end
    local officer = ns.CanEdit()
    UI.setTitle(picker, ns.IsTest() and "Start Bidding  |cffff8040Test mode|r" or "Start Bidding")
    if ns.IsTest() then
        picker.testNote:SetText(ns.TEST_TAG .. "test mode is on, the simulated raid answers by itself")
    else
        picker.testNote:SetText("")
    end

    local link = state.link
    if link then
        picker.slot:SetItem(link)
        picker.slotEmpty:Hide()
        picker.itemName:SetText(link)
        local price, _, fixed = ns.ItemPrice(link, state.tier)
        picker.price:SetText("Main spec costs |cffffffff" .. price .. " GP|r, " .. ns.OffSpecText(price) .. (fixed and ", fixed price for this item" or ""))
    else
        picker.slot.link = nil
        if SetItemButtonTexture then pcall(SetItemButtonTexture, picker.slot, nil) end
        if picker.slot.icon then pcall(picker.slot.icon.SetTexture, picker.slot.icon, nil) end
        if SetItemButtonQuality then pcall(SetItemButtonQuality, picker.slot, nil) end
        picker.slotEmpty:Show()
        picker.itemName:SetText("|cff999999No item chosen|r")
        picker.price:SetText("")
    end
    for tier, b in pairs(picker.tierButtons) do b:SetEnabled(tier ~= state.tier) end

    local busy = ns.auction and ns.auction.open
    picker.start:SetEnabled(link ~= nil and not busy and officer)
    picker.start:SetText("Start bidding")
    if busy then
        picker.sub:SetText("|cffff8040bidding for another item is still open|r")
    elseif not officer then
        picker.sub:SetText("only officers start bidding, turn on test mode in the settings to try it")
    else
        picker.sub:SetText("or pick one from the loot below")
    end

    local n = 0
    for _, item in ipairs(ns.lootSeen) do
        n = n + 1
        local row = picker.list:Row(n)
        row.item = item
        local _, _, icon = ns.ItemInfo(item.link)
        row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.name:SetText(item.link)
        if item.onCorpse then
            row.where:SetText("|cff40ff40on the corpse|r")
        else
            local minutes = math.floor((ns.Now() - (item.at or ns.Now())) / 60)
            row.where:SetText(minutes < 1 and "seen just now" or ("seen " .. minutes .. " min ago"))
        end
        row.selected:SetShown(item.link == link)
        row:Show()
    end
    picker.list:SetCount(n)
    picker.empty:SetShown(n == 0)
end

function ns.StartFromPicker()
    local link = state.link
    if not link then return false end
    local ok = ns.StartAuction(link, state.tier)
    if ok and not ns.IsTest() then
        local _, i = findSeen(link)
        if i then table.remove(ns.lootSeen, i) end
    end
    if ok then
        state.link = nil
        if picker then picker:Hide() end
    end
    return ok
end

function ns.OpenPicker()
    picker = picker or buildPicker()
    ns.picker, ns.pickerState = picker, state
    if not state.link and ns.lootSeen[1] and ns.lootSeen[1].onCorpse then
        state.link = ns.lootSeen[1].link
    end
    picker:Show()
    ns.RefreshPicker()
end

function ns.TogglePicker()
    if picker and picker:IsShown() then
        picker:Hide()
    else
        ns.OpenPicker()
    end
end

-- The Loot Master button: the running bidding if there is one, otherwise Start Bidding.
function ns.OpenLootMaster()
    if ns.auction then
        ns.RefreshLootMaster()
    else
        ns.OpenPicker()
    end
end

ns.On("RGF_LOOT_CHANGED", function() ns.RefreshPicker() end)
ns.On("RGF_AUCTION_CHANGED", function() ns.RefreshPicker() end)
ns.On("RGF_TEST_MODE", function() ns.RefreshPicker() end)
