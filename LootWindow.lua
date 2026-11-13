-- SPDX-License-Identifier: MIT, see LICENSE
-- The Loot Master window: everything for a boss kill in one place.
--   left   the items: running biddings first, then the items of the corpse.
--          Drag an item in, or Alt click it in your bags or in the loot window
--   right  the chosen item: its price, and every bid in the full list
--   one big button always does the next step: Start bidding, Close bids,
--   Award to the winner
-- Opens from the minimap menu, the Loot Master button or /rgf bid.

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
    if good and ns.Setting("autoOpenLoot") and ns.CanEdit() and inGroup and #ns.OpenAuctions() == 0 then
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
local text, button, classColor = UI.text, UI.button, UI.classColor

local frame
-- state.link is the chosen item that is not up for bids yet, state.show says
-- whether the right side shows that item ("item") or a running bidding ("auction")
local state = { link = nil, tier = "normal", show = "item" }
local knownAuctions = 0

local bidColumns = {
    { key = "name", label = "Name", w = 150 },
    { key = "spec", label = "Answer", w = 76 },
    { key = "ep", label = "EP", w = 56, justify = "RIGHT" },
    { key = "gp", label = "GP", w = 56, justify = "RIGHT" },
    { key = "pr", label = "Priority", w = 70, justify = "RIGHT" },
    { key = "roll", label = "Roll", w = 44, justify = "RIGHT" },
    { key = "action", label = "", w = 86 },
}

local SECTION_COLORS = {
    MS = { 0.25, 1, 0.25 },
    OS = { 0.4, 0.78, 1 },
    PASS = { 0.6, 0.6, 0.6 },
    WAIT = { 1, 0.5, 0.25 },
}

-- Choose an item for bidding. An item from the bags joins the list on the left.
local function selectItem(link)
    if not findSeen(link) then
        table.insert(ns.lootSeen, 1, { link = link, quality = quality(link), at = ns.Now(), fromBags = true })
    end
    state.link = link
    state.show = "item"
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

-- What the right side shows: "auction" and the auction, "item" and the link, or nil
local function shown()
    if state.show == "auction" and ns.auction then return "auction", ns.auction end
    if state.link then return "item", state.link end
    if ns.auction then return "auction", ns.auction end
    return nil
end

local function costText(cost)
    return cost > 0 and (cost .. " GP") or "free"
end

-- The next step for the chosen item: a label and what the big button does
local function nextStep()
    local kind, what = shown()
    if kind == "item" then
        return "Start bidding", function() ns.StartFromPicker() end, ns.CanEdit()
    elseif kind == "auction" then
        local a = what
        if a.open then
            local left = math.max(0, math.ceil(a.endsAt - GetTime()))
            return "Close bids now  (" .. left .. " s left)", function() ns.CloseBidding(a) end, true
        end
        local o = ns.AuctionOverview(a)
        if #o.all == 0 then
            return "Nobody wants it: Bank or Disenchant", function() ns.Award(nil, a) end, true
        end
        if #ns.TiedForFirst(a) > 0 then
            return "Tie, ask for rolls again", function() ns.RequestRolls(a) end, true
        end
        local cost, spec = ns.AwardCost(a, o.winner.name)
        return string.format("Award to %s  (%s, %s)", ns.ShortName(o.winner.name), spec == "MS" and "main spec" or "off spec", costText(cost)),
            function() ns.AskAward(o.winner.name, a) end, true
    end
    return "Choose an item on the left", function() end, false
end

local function buildWindow()
    local f = UI.window("RedGuildForeverLootFrame", 810, 540, "Loot Master", UI.ICON_UNKNOWN)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)

    f.item = text(f, "GameFontNormalLarge")
    f.item:SetPoint("TOPLEFT", 66, -30)
    f.item:SetWidth(600)
    f.price = text(f, "GameFontHighlightSmall")
    f.price:SetPoint("TOPLEFT", f.item, "BOTTOMLEFT", 0, -3)
    f.price:SetWidth(600)

    local inset = f.Inset

    -- left: the items ----------------------------------------------------
    local left = CreateFrame("Frame", nil, inset)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(226)
    f.left = left
    local divider = left:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPRIGHT", 0, -4)
    divider:SetPoint("BOTTOMRIGHT", 0, 4)
    divider:SetWidth(1)
    divider:SetColorTexture(1, 0.82, 0, 0.25)

    f.slot = UI.itemButton(left, 36)
    f.slot:SetPoint("TOPLEFT", 10, -10)
    f.slot:SetScript("OnReceiveDrag", function() takeCursorItem() end)
    f.slot:SetScript("OnClick", function(self)
        if takeCursorItem() then return end
        if self.link and IsModifiedClick and HandleModifiedItemClick then
            pcall(HandleModifiedItemClick, self.link)
        end
    end)
    f.slot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Add an item")
        GameTooltip:AddLine("Drag it from your bags onto this slot, or Alt click it in your bags or in the loot window.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.slotEmpty = f.slot:CreateTexture(nil, "OVERLAY")
    f.slotEmpty:SetAllPoints()
    f.slotEmpty:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    f.slotHint = text(left, "GameFontDisableSmall")
    f.slotHint:SetPoint("LEFT", f.slot, "RIGHT", 8, 0)
    f.slotHint:SetWidth(160)
    f.slotHint:SetWordWrap(true)
    f.slotHint:SetText("Drag an item here,\nor Alt click it")

    f.empty = text(left, "GameFontDisableSmall")
    f.empty:SetPoint("TOPLEFT", 12, -62)
    f.empty:SetWidth(196)
    f.empty:SetWordWrap(true)
    f.empty:SetText("Open a corpse and its items show up here.")

    local listHolder = CreateFrame("Frame", nil, left)
    listHolder:SetPoint("TOPLEFT", 0, -54)
    listHolder:SetPoint("BOTTOMRIGHT", -2, 32)
    f.items = UI.scrollList(listHolder, 30, function(row)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("LEFT", 6, 0)
        row.name = text(row, "GameFontHighlightSmall")
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, 0)
        row.name:SetWidth(150)
        row.where = text(row, "GameFontDisableSmall")
        row.where:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 0)
        row.where:SetWidth(150)
        row.selected = row:CreateTexture(nil, "BACKGROUND")
        row.selected:SetAllPoints()
        row.selected:SetColorTexture(1, 0.82, 0, 0.14)
        row:SetScript("OnClick", function(self)
            UI.sound("U_CHAT_SCROLL_BUTTON")
            if self.auction then
                state.show = "auction"
                ns.SelectAuction(self.auction)
            elseif self.item then
                selectItem(self.item.link)
            end
        end)
        row:SetScript("OnEnter", function(self)
            local link = (self.auction and self.auction.link) or (self.item and self.item.link)
            if not link then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetHyperlink, GameTooltip, link)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnReceiveDrag", function() takeCursorItem() end)
    end)
    f.items:SetPoint("TOPLEFT", 4, -4)
    f.items:SetPoint("BOTTOMRIGHT", -24, 0)

    f.startAll = button(left, "Bid on all", 118, function() ns.StartAllFromPicker() end)
    f.startAll:SetPoint("BOTTOMLEFT", 6, 6)
    f.clear = button(left, "Clear list", 90, function()
        wipe(ns.lootSeen)
        state.link = nil
        ns.Fire("RGF_LOOT_CHANGED")
    end)
    f.clear:SetPoint("LEFT", f.startAll, "RIGHT", 2, 0)

    -- right: the chosen item ---------------------------------------------
    local right = CreateFrame("Frame", nil, inset)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 2, 0)
    right:SetPoint("BOTTOMRIGHT")
    f.right = right

    local tierLabel = text(right, "GameFontNormalSmall")
    tierLabel:SetPoint("TOPLEFT", 10, -14)
    tierLabel:SetText("Drops from")
    f.tierButtons = {}
    local prev = tierLabel
    for _, tier in ipairs(ns.defaults.tierOrder) do
        local b = button(right, ns.defaults.tierNames[tier], 96, function()
            local kind, what = shown()
            if kind == "auction" then
                ns.SetAuctionTier(tier, what)
            else
                state.tier = tier
                ns.Fire("RGF_LOOT_CHANGED")
            end
        end)
        b:SetPoint("LEFT", prev, "RIGHT", prev == tierLabel and 8 or 2, 0)
        f.tierButtons[tier] = b
        prev = b
    end
    local priceLabel = text(right, "GameFontNormalSmall")
    priceLabel:SetPoint("LEFT", prev, "RIGHT", 12, 0)
    priceLabel:SetText("Price")
    f.priceBox = UI.inputBox(right, 46, true)
    f.priceBox:SetPoint("LEFT", priceLabel, "RIGHT", 8, 0)
    local function setPrice()
        local kind, what = shown()
        if kind == "auction" and ns.SetAuctionPrice(f.priceBox:GetText(), what) then f.priceBox:ClearFocus() end
    end
    f.priceBox:SetScript("OnEnterPressed", setPrice)
    f.priceSet = button(right, "Set", 44, setPrice)
    f.priceSet:SetPoint("LEFT", f.priceBox, "RIGHT", 4, 0)

    -- the next step, always one click
    f.primary = button(right, "Start bidding", 420, function()
        local _, run, enabled = nextStep()
        if enabled then run() end
    end)
    f.primary:SetHeight(30)
    f.primary:SetPoint("TOPLEFT", 8, -42)
    f.start = f.primary

    f.state = text(right, "GameFontNormal")
    f.state:SetPoint("TOPLEFT", 10, -80)
    f.state:SetWidth(540)
    f.counts = text(right, "GameFontHighlightSmall")
    f.counts:SetPoint("TOPLEFT", 10, -98)
    f.counts:SetWidth(540)

    local bids = CreateFrame("Frame", nil, right)
    bids:SetPoint("TOPLEFT", 0, -112)
    bids:SetPoint("BOTTOMRIGHT")
    UI.headerRow(bids, bidColumns)
    f.list = UI.scrollList(bids, 22, function(row)
        UI.rowCells(row, bidColumns)
        row.section = text(row, "GameFontNormal")
        row.section:SetPoint("LEFT", 6, 0)
        row.section:SetWidth(400)
        row.sectionLine = row:CreateTexture(nil, "BACKGROUND")
        row.sectionLine:SetPoint("BOTTOMLEFT", 2, 1)
        row.sectionLine:SetPoint("BOTTOMRIGHT", -2, 1)
        row.sectionLine:SetHeight(1)
        row.sectionLine:SetColorTexture(1, 0.82, 0, 0.35)
        row.winner = text(row, "GameFontNormalSmall", "RIGHT")
        row.winner:SetPoint("RIGHT", -74, 0)
        row.winner:SetText("|cff40ff40Winner|r")
        row.award = button(row, "Award", 66, function()
            if row.bid and row.auction then ns.AskAward(row.bid.name, row.auction) end
        end)
        row.award:SetHeight(20)
        row.award:SetPoint("RIGHT", -2, 0)
        -- what the bidder got lately, helps with close calls
        row:SetScript("OnEnter", function(self)
            if not self.bid then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(ns.ShortName(self.bid.name))
            if #ns.LootOf(self.bid.name, 1) == 0 then GameTooltip:AddLine("No items yet", 1, 1, 1) end
            ns.AddLootLines(GameTooltip, self.bid.name)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end)
    f.list:SetPoint("TOPLEFT", 4, -30)
    f.list:SetPoint("BOTTOMRIGHT", -26, 4)
    f.listHint = text(bids, "GameFontDisable", "CENTER")
    f.listHint:SetPoint("TOP", 0, -70)
    f.listHint:SetWidth(440)
    f.listHint:SetWordWrap(true)

    -- bottom strip: the other things you can do with a running bidding
    f.cancel = button(f, "Cancel bidding", 120, function()
        local kind, what = shown()
        if kind == "auction" then ns.CancelAuction(what) end
    end)
    f.cancel:SetPoint("BOTTOMRIGHT", -6, 4)
    f.bank = button(f, "Bank or Disenchant", 150, function()
        local kind, what = shown()
        if kind == "auction" then ns.Award(nil, what) end
    end)
    f.bank:SetPoint("RIGHT", f.cancel, "LEFT", -2, 0)
    f.rolls = button(f, "Ask for rolls", 110, function()
        local kind, what = shown()
        if kind == "auction" then ns.RequestRolls(what) end
    end)
    f.rolls:SetPoint("RIGHT", f.bank, "LEFT", -2, 0)
    f.closeBids = button(f, "Close bids", 100, function()
        local kind, what = shown()
        if kind == "auction" then ns.CloseBidding(what) end
    end)
    f.closeBids:SetPoint("RIGHT", f.rolls, "LEFT", -2, 0)

    -- the countdown
    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.25 then return end
        elapsed = 0
        if #ns.OpenAuctions() > 0 then ns.RefreshLootMaster(true) end
    end)
    f:SetScript("OnReceiveDrag", function() takeCursorItem() end)
    f:HookScript("OnShow", function() ns.RefreshLootMaster() end)
    return f
end

------------------------------------------------------------------------
-- Filling the window
------------------------------------------------------------------------
local function showSection(row, label, count, key)
    row.bid = nil
    for _, cell in pairs(row.cells) do cell:SetText("") end
    local c = SECTION_COLORS[key]
    row.section:SetText(label .. "  |cffffffff" .. count .. "|r")
    row.section:SetTextColor(c[1], c[2], c[3])
    row.section:Show()
    row.sectionLine:Show()
    row.winner:Hide()
    row.award:Hide()
    row:Show()
end

local function showBid(row, a, b, isWinner, canAward)
    row.bid, row.auction = b, a
    row.section:Hide()
    row.sectionLine:Hide()
    local label = ns.ShortName(b.name)
    if b.main and b.main ~= b.name then label = label .. " |cff999999(" .. ns.ShortName(b.main) .. ")|r" end
    row.cells.name:SetText(label)
    local m = ns.members[b.name]
    row.cells.name:SetTextColor(classColor(m and m.class))
    local c = SECTION_COLORS[b.spec] or SECTION_COLORS.PASS
    row.cells.spec:SetText(b.spec == "MS" and "Main Spec" or (b.spec == "OS" and "Off Spec" or "Pass"))
    row.cells.spec:SetTextColor(c[1], c[2], c[3])
    row.cells.ep:SetText(b.ep)
    row.cells.gp:SetText(b.gp)
    if b.spec == "MS" then
        row.cells.pr:SetText(ns.FormatPR(b.pr))
        if b.newcomer then row.cells.pr:SetTextColor(0.4, 0.78, 1) else row.cells.pr:SetTextColor(1, 0.82, 0) end
    elseif b.spec == "OS" then
        local osCost = ns.OffSpecCost(a.price or 0)
        row.cells.pr:SetText(costText(osCost))
        row.cells.pr:SetTextColor(0.7, 0.7, 0.7)
    else
        row.cells.pr:SetText("")
    end
    row.cells.roll:SetText(b.roll or (b.wantsRoll and "..." or ""))
    row.winner:SetShown(isWinner)
    row.award:SetShown(canAward)
    row:Show()
end

local function showWaiting(row, name)
    row.bid = nil
    row.section:Hide()
    row.sectionLine:Hide()
    row.cells.name:SetText(ns.ShortName(name))
    local m = ns.members[name]
    local r, g, b = classColor(m and m.class)
    row.cells.name:SetTextColor(r * 0.6, g * 0.6, b * 0.6)
    row.cells.spec:SetText("No answer")
    row.cells.spec:SetTextColor(SECTION_COLORS.WAIT[1], SECTION_COLORS.WAIT[2], SECTION_COLORS.WAIT[3])
    row.cells.ep:SetText("")
    row.cells.gp:SetText("")
    row.cells.pr:SetText("")
    row.cells.roll:SetText("")
    row.winner:Hide()
    row.award:Hide()
    row:Show()
end

local function fillItems(f)
    local kind, what = shown()
    local n = 0
    for _, a in ipairs(ns.auctions) do
        n = n + 1
        local row = f.items:Row(n)
        row.auction, row.item = a, nil
        row.icon:SetTexture(a.icon or UI.ICON_UNKNOWN)
        row.name:SetText(a.n .. ". " .. a.link)
        if a.open then
            row.where:SetText("|cff40ff40bids open, " .. math.max(0, math.ceil(a.endsAt - GetTime())) .. " s|r")
        else
            row.where:SetText("|cffffd100closed, give it out|r")
        end
        row.selected:SetShown(kind == "auction" and what == a)
        row:Show()
    end
    for _, item in ipairs(ns.lootSeen) do
        n = n + 1
        local row = f.items:Row(n)
        row.auction, row.item = nil, item
        local _, _, icon = ns.ItemInfo(item.link)
        row.icon:SetTexture(icon or UI.ICON_UNKNOWN)
        row.name:SetText(item.link)
        if item.onCorpse then
            row.where:SetText("on the corpse")
        elseif item.fromBags then
            row.where:SetText("from your bags")
        else
            local minutes = math.floor((ns.Now() - (item.at or ns.Now())) / 60)
            row.where:SetText(minutes < 1 and "seen just now" or ("seen " .. minutes .. " min ago"))
        end
        row.selected:SetShown(kind == "item" and what == item.link)
        row:Show()
    end
    f.items:SetCount(n)
    f.empty:SetShown(n == 0)
    local all = ns.CorpseItems()
    f.startAll:SetEnabled(ns.CanEdit() and #all > 1)
    f.startAll:SetText(#all > 1 and ("Bid on all " .. #all) or "Bid on all")
    f.clear:SetEnabled(#ns.lootSeen > 0)
end

local function fillBids(f, a)
    local o = ns.AuctionOverview(a)
    local tied = ns.TiedForFirst(a)
    if a.open then
        f.state:SetText("Bidding is open, |cffffffff" .. math.max(0, math.ceil(a.endsAt - GetTime())) .. "|r seconds left")
    elseif #o.all == 0 then
        f.state:SetText("Bidding is closed. Nobody wants it, give it to the bank or disenchant it.")
    elseif #tied > 0 then
        f.state:SetText("Bidding is closed. |cffff8040Tie for first place|r, waiting for /roll.")
    else
        f.state:SetText("Bidding is closed. Award the item to the winner, or to anyone in the list.")
    end
    f.counts:SetText(string.format(
        "|cff40ff40Main Spec %d|r     |cff66c7ffOff Spec %d|r     |cff999999Pass %d|r     |cffff8040No answer %d|r",
        #o.ms, #o.os, #o.passed, #o.waiting))
    local n = 0
    local function nextRow()
        n = n + 1
        return f.list:Row(n)
    end
    local winner = (#tied == 0) and o.winner or nil
    local sections = {
        { key = "MS", label = "Main Spec", list = o.ms },
        { key = "OS", label = "Off Spec", list = o.os },
        { key = "PASS", label = "Passed", list = o.passed },
    }
    for _, sec in ipairs(sections) do
        if #sec.list > 0 then
            showSection(nextRow(), sec.label, #sec.list, sec.key)
            for _, b in ipairs(sec.list) do
                showBid(nextRow(), a, b, b == winner, sec.key ~= "PASS")
            end
        end
    end
    if #o.waiting > 0 then
        showSection(nextRow(), "No answer yet", #o.waiting, "WAIT")
        for _, name in ipairs(o.waiting) do showWaiting(nextRow(), name) end
    end
    f.list:SetCount(n)
    f.listHint:SetShown(n == 0)
    f.listHint:SetText("No bids yet.")
    return tied
end

-- Fill the window. quick only refreshes the countdown, the lists stay.
function ns.RefreshLootMaster(quick)
    local f = frame
    if not f or not f:IsShown() then return end
    local label, _, enabled = nextStep()
    f.primary:SetText(label)
    f.primary:SetEnabled(enabled and true or false)
    local kind, what = shown()
    if quick then
        if kind == "auction" and what.open then
            f.state:SetText("Bidding is open, |cffffffff" .. math.max(0, math.ceil(what.endsAt - GetTime())) .. "|r seconds left")
        end
        fillItems(f)
        return
    end
    local officer = ns.CanEdit()
    local test = ns.IsTest()
    local title = "Loot Master"
    if #ns.auctions > 1 and kind == "auction" then title = title .. "  " .. what.n .. " of " .. #ns.auctions end
    UI.setTitle(f, test and (title .. "  |cffff8040Test mode|r") or title)
    fillItems(f)

    local link = (kind == "auction" and what.link) or (kind == "item" and what) or nil
    if link then
        local _, _, icon = ns.ItemInfo(link)
        UI.setPortrait(f, icon or UI.ICON_UNKNOWN)
        f.item:SetText(link)
    else
        UI.setPortrait(f, UI.ICON_UNKNOWN)
        f.item:SetText("|cff999999No item chosen|r")
    end
    -- the slot always shows the item that waits to be started
    if state.link then
        f.slot:SetItem(state.link)
        f.slotEmpty:Hide()
    else
        f.slot.link = nil
        if SetItemButtonTexture then pcall(SetItemButtonTexture, f.slot, nil) end
        if f.slot.icon then pcall(f.slot.icon.SetTexture, f.slot.icon, nil) end
        if SetItemButtonQuality then pcall(SetItemButtonQuality, f.slot, nil) end
        f.slotEmpty:Show()
    end

    local isAuction = kind == "auction"
    f.closeBids:SetEnabled(isAuction and what.open and true or false)
    f.bank:SetEnabled(isAuction)
    f.cancel:SetEnabled(isAuction)
    f.priceBox:SetEnabled(isAuction)
    f.priceSet:SetEnabled(isAuction)
    if isAuction then
        local a = what
        f.price:SetText("Main spec costs |cffffffff" .. a.price .. " GP|r, " .. ns.OffSpecText(a.price) .. (a.fixed and ", fixed price" or ""))
        for tier, b in pairs(f.tierButtons) do b:SetEnabled(not a.fixed and tier ~= a.tier) end
        if not f.priceBox:HasFocus() then f.priceBox:SetText(tostring(a.price)) end
        local tied = fillBids(f, a)
        f.rolls:SetEnabled(not a.open and #tied > 0)
    else
        f.rolls:SetEnabled(false)
        f.list:SetCount(0)
        f.counts:SetText("")
        f.listHint:Show()
        if kind == "item" then
            local price, _, fixed = ns.ItemPrice(what, state.tier)
            f.price:SetText("Main spec costs |cffffffff" .. price .. " GP|r, " .. ns.OffSpecText(price) .. (fixed and ", fixed price for this item" or ""))
            for tier, b in pairs(f.tierButtons) do b:SetEnabled(not fixed and tier ~= state.tier) end
            f.priceBox:SetText(tostring(price))
            if not officer then
                f.state:SetText("Only editors start bidding. Turn on test mode in the game's Options to try it.")
            elseif test then
                f.state:SetText(ns.TEST_TAG .. "Test mode is on, the simulated raid answers by itself.")
            else
                f.state:SetText("Choose where it dropped, then start bidding.")
            end
            f.listHint:SetText("The bids show up here once bidding has started.")
        else
            f.price:SetText("")
            for _, b in pairs(f.tierButtons) do b:SetEnabled(false) end
            f.priceBox:SetText("")
            f.state:SetText("Drag an item onto the slot on the left, Alt click it in your bags, or open a corpse.")
            f.listHint:SetText("")
        end
    end
end
ns.RefreshPicker = ns.RefreshLootMaster

------------------------------------------------------------------------
-- Opening, starting and awarding
------------------------------------------------------------------------
local function open()
    frame = frame or buildWindow()
    ns.lootFrame, ns.picker, ns.lootMasterFrame, ns.pickerState = frame, frame, frame, state
    if not frame:IsShown() then frame:Show() end
    ns.RefreshLootMaster()
    return frame
end

-- The rare and better items on the open corpse, for Bid on all
function ns.CorpseItems()
    local list = {}
    for i = #ns.lootSeen, 1, -1 do
        local item = ns.lootSeen[i]
        if item.onCorpse and (item.quality or 0) >= AUTO_OPEN_QUALITY then table.insert(list, item) end
    end
    return list
end

local function forget(link)
    if ns.IsTest() then return end
    local _, i = findSeen(link)
    if i then table.remove(ns.lootSeen, i) end
end

-- Start bidding for the chosen item. The window stays and shows the bids.
function ns.StartFromPicker()
    local link = state.link
    if not link then return false end
    local a = ns.StartAuction(link, state.tier)
    if not a then return false end
    forget(link)
    state.link = nil
    state.show = "auction"
    ns.SelectAuction(a)
    return true
end

function ns.StartAllFromPicker()
    local items = {}
    for _, item in ipairs(ns.CorpseItems()) do table.insert(items, { item.link, state.tier }) end
    if #items == 0 then return 0 end
    local before = #ns.auctions
    local count = ns.StartAuctions(items)
    if count > 0 then
        for _, item in ipairs(items) do forget(item[1]) end
        state.link = nil
        state.show = "auction"
        ns.SelectAuction(ns.auctions[before + 1] or ns.auction)
    end
    return count
end

-- Open the window to choose an item, the first one of the corpse is chosen already.
function ns.OpenPicker()
    if not state.link and ns.lootSeen[1] and ns.lootSeen[1].onCorpse then
        state.link = ns.lootSeen[1].link
    end
    if state.link or not ns.auction then state.show = "item" end
    open()
end

function ns.TogglePicker()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        ns.OpenPicker()
    end
end

-- The Loot Master button: the running bidding if there is one, otherwise the items.
function ns.OpenLootMaster()
    if ns.auction or ns.auctions[1] then
        ns.auction = ns.auction or ns.auctions[1]
        state.show = "auction"
        open()
    else
        ns.OpenPicker()
    end
end

-- Alt click on an item in the bags or in the loot window: choose it for bidding.
function ns.AltClickItem(link)
    if type(link) ~= "string" or not link:find("|Hitem:", 1, true) then return false end
    if not ns.Setting("altClickBid") or not ns.CanEdit() then return false end
    if not ((IsInGroup and IsInGroup()) or ns.IsTest()) then return false end
    selectItem(link)
    open()
    return true
end

if hooksecurefunc and HandleModifiedItemClick then
    pcall(hooksecurefunc, "HandleModifiedItemClick", function(link)
        if IsAltKeyDown and IsAltKeyDown() then ns.AltClickItem(link) end
    end)
end

-- Award with a short question first, so a wrong click costs nothing.
function ns.AskAward(name, auction)
    local a = auction or ns.auction
    if not a or not name then return false end
    if not ns.Setting("confirmAward") or not StaticPopup_Show then return ns.Award(name, a) end
    local full = ns.Resolve(name)
    local cost, spec = ns.AwardCost(a, full)
    ns.pendingAward = { name = full, auction = a }
    StaticPopup_Show("REDGUILDFOREVER_AWARD", a.link,
        string.format("%s for %s, %s", ns.ShortName(full), spec == "MS" and "main spec" or "off spec", costText(cost)))
    return true
end

if StaticPopupDialogs then
    StaticPopupDialogs["REDGUILDFOREVER_AWARD"] = {
        text = "Give %s\nto %s?",
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function()
            local p = ns.pendingAward
            ns.pendingAward = nil
            if not p then return end
            for _, a in ipairs(ns.auctions) do
                if a == p.auction then ns.Award(p.name, a) return end
            end
        end,
        OnCancel = function() ns.pendingAward = nil end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

-- A new bidding brings the window up. It closes by itself when nothing is left to do.
ns.On("RGF_AUCTION_CHANGED", function()
    local count = #ns.auctions
    if count > knownAuctions and ns.CanEdit() then
        if state.show ~= "item" or not state.link then state.show = "auction" end
        knownAuctions = count
        open()
        return
    end
    knownAuctions = count
    if count == 0 and frame and frame:IsShown() and not state.link and #ns.lootSeen == 0 then
        frame:Hide()
        return
    end
    if count == 0 and state.show == "auction" then state.show = "item" end
    ns.RefreshLootMaster()
end)
ns.On("RGF_LOOT_CHANGED", function() ns.RefreshLootMaster() end)
ns.On("RGF_TEST_MODE", function() ns.RefreshLootMaster() end)
ns.On("RGF_BENCH_CHANGED", function() ns.RefreshStandings() end)
ns.On("RGF_SYNC_DONE", function() ns.RefreshStandings() end)
ns.On("RGF_TEST_MODE", function() ns.RefreshStandings() end)
