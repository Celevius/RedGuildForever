-- SPDX-License-Identifier: MIT, see LICENSE
-- Popups: the bid cards for raiders and the winner popup. Both can be dragged
-- anywhere, the place is remembered. /rgf resetpos puts them back.

local _, ns = ...
ns = ns or _G.RedGuildForever
if not CreateFrame then return end

local UI = ns.UI
local create, text, button, window, itemButton = UI.create, UI.text, UI.button, UI.window, UI.itemButton
local setTitle, setPortrait, sound, classColor = UI.setTitle, UI.setPortrait, UI.sound, UI.classColor
local ICON_UNKNOWN = UI.ICON_UNKNOWN

------------------------------------------------------------------------
-- Where the popups sit. Dragging one saves its place.
------------------------------------------------------------------------
local DEFAULTS = {
    bid = { "BOTTOM", 0, 240 },   -- above the action bars, like the game's loot rolls
    winner = { "TOP", 0, -70 },
}
local placed = {}

local function positions()
    RedGuildForeverDB.positions = RedGuildForeverDB.positions or {}
    return RedGuildForeverDB.positions
end

local function place(f, key)
    local p = positions()[key] or DEFAULTS[key]
    f:ClearAllPoints()
    f:SetPoint(p[1], UIParent, p[1], p[2], p[3])
    placed[key] = f
end

local function remember(f, key)
    local point, _, _, x, y = f:GetPoint(1)
    if type(point) == "string" and type(x) == "number" and type(y) == "number" then
        positions()[key] = { point, math.floor(x + 0.5), math.floor(y + 0.5) }
    end
end

-- dragging handle moves mover and saves the place under key
local function makeMovable(handle, mover, key)
    mover:SetMovable(true)
    mover:SetClampedToScreen(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function() mover:StartMoving() end)
    handle:SetScript("OnDragStop", function()
        mover:StopMovingOrSizing()
        remember(mover, key)
    end)
end

-- Put the popups back where they were at the start
function ns.ResetPositions()
    wipe(positions())
    for key, f in pairs(placed) do place(f, key) end
end

local function goldFrame(f)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.02, 0.02, 0.9)
    for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
        { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
        local line = f:CreateTexture(nil, "BORDER")
        line:SetPoint(edge[1])
        line:SetPoint(edge[2])
        if edge[3] then line:SetWidth(edge[3]) else line:SetHeight(edge[4]) end
        line:SetColorTexture(1, 0.82, 0, 0.9)
    end
end

------------------------------------------------------------------------
-- Bid cards for raiders, small like the game's Need or Greed rolls.
-- Every item that is up for bids gets its own card, they stack upwards.
-- A card goes away when you answer it or when the time is over.
------------------------------------------------------------------------
local MAX_CARDS = 4
local CARD_WIDTH, CARD_HEIGHT = 348, 76
local anchor
local cards = {}

-- true or false when the game knows whether this character can use the item, nil when not
function ns.CanUseItem(link)
    local itemID = ns.ItemInfo(link)
    if not itemID then return nil end
    if C_PlayerInfo and C_PlayerInfo.CanUseItem then
        local ok, usable = pcall(C_PlayerInfo.CanUseItem, itemID)
        if ok and type(usable) == "boolean" then return usable end
    end
    return nil
end

-- The cards to show: open items that still wait for an answer, lowest number first
local function waiting()
    local list = {}
    local now = GetTime()
    for _, inc in pairs(ns.incoming) do
        if now < inc.endsAt and (not inc.myBid or inc.reopened) then table.insert(list, inc) end
    end
    table.sort(list, function(a, b)
        if (a.n or 0) ~= (b.n or 0) then return (a.n or 0) < (b.n or 0) end
        return a.id < b.id
    end)
    return list
end

local layout

local function answer(card, spec)
    local inc = card.inc
    if not inc then return end
    inc.reopened = nil
    if spec == "PASS" and not inc.myBid then
        inc.myBid = "PASS" -- a pass without an earlier bid needs no message
        layout()
    else
        ns.SendBid(inc, spec)
    end
end

local function buildCard(i)
    local c = create("Button", "RedGuildForeverBidCard" .. i, anchor)
    c:SetSize(CARD_WIDTH, CARD_HEIGHT)
    c:SetFrameStrata("DIALOG")
    goldFrame(c)
    makeMovable(c, anchor, "bid")

    c.icon = itemButton(c, 40)
    c.icon:SetPoint("TOPLEFT", 9, -9)
    c.item = text(c, "GameFontNormal")
    c.item:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 8, 0)
    c.item:SetWidth(280)
    c.note = text(c, "GameFontHighlightSmall")
    c.note:SetPoint("TOPLEFT", c.item, "BOTTOMLEFT", 0, -3)
    c.note:SetWidth(280)

    c.ms = button(c, "Main Spec", 96, function() answer(c, "MS") end)
    c.ms:SetHeight(20)
    c.ms:SetPoint("BOTTOMLEFT", 57, 10)
    c.os = button(c, "Off Spec", 96, function() answer(c, "OS") end)
    c.os:SetHeight(20)
    c.os:SetPoint("LEFT", c.ms, "RIGHT", 4, 0)
    c.pass = button(c, "Pass", 76, function() answer(c, "PASS") end)
    c.pass:SetHeight(20)
    c.pass:SetPoint("LEFT", c.os, "RIGHT", 4, 0)
    c.ms:SetScript("OnEnter", function(self)
        if not c.unusable then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Your character cannot use this item", 1, 0.3, 0.3)
        GameTooltip:Show()
    end)
    c.ms:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- the time left, as a thin bar at the bottom
    c.timer = CreateFrame("StatusBar", nil, c)
    c.timer:SetPoint("BOTTOMLEFT", 3, 3)
    c.timer:SetPoint("BOTTOMRIGHT", -3, 3)
    c.timer:SetHeight(4)
    c.timer:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    c.timer:SetStatusBarColor(1, 0.82, 0)
    c.timer:SetMinMaxValues(0, 1)

    local elapsed = 0
    c:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.1 or not c.inc then return end
        elapsed = 0
        local left = c.inc.endsAt - GetTime()
        c.timer:SetValue(math.max(0, left / (c.inc.duration or 30)))
        if left <= 0 then layout() end -- the time is over, the card goes away
    end)
    c:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Loot bid")
        GameTooltip:AddLine("Drag to move. Keys for Main Spec, Off Spec and Pass can be set in the game's key bindings under Red Guild EPGP.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c:Hide()
    return c
end

local function fillCard(c, inc, total)
    c.inc = inc
    c.icon:SetItem(inc.link)
    c.item:SetText(((inc.n and total > 1) and (inc.n .. ". ") or "") .. inc.link)

    local me = ns.PlayerName()
    local ep, gp, pr = ns.GetPoints(me)
    local price = inc.price or 0
    local after = ep / math.max(gp + price, 1)
    local note = (ns.IsTest() and ns.TEST_TAG or "") .. price .. " GP.  Your priority |cffffd100" .. ns.FormatPR(pr)
        .. "|r, after a win |cffffd100" .. ns.FormatPR(after) .. "|r"
    local osCost = ns.OffSpecCost(price)
    if osCost > 0 then note = note .. ".  Off spec " .. osCost .. " GP" end
    c.unusable = ns.CanUseItem(inc.link) == false
    if c.unusable then note = "|cffff5555You cannot use this item.|r  " .. price .. " GP" end
    c.note:SetText(note)

    c.ms:SetEnabled(not c.unusable)
    c.os:SetEnabled(true)
    c.ms:SetText(inc.myBid == "MS" and "|cff40ff40Main Spec|r" or "Main Spec")
    c.os:SetText(inc.myBid == "OS" and "|cff40ff40Off Spec|r" or "Off Spec")
    c:Show()
end

layout = function()
    local list = waiting()
    if #list == 0 and not anchor then return end
    if not anchor then
        anchor = CreateFrame("Frame", "RedGuildForeverBidAnchor", UIParent)
        anchor:SetSize(CARD_WIDTH, 1)
        place(anchor, "bid")
    end
    local shown = math.min(#list, MAX_CARDS)
    local fresh = false
    for i = 1, shown do
        local c = cards[i]
        if not c then
            c = buildCard(i)
            c:SetPoint("BOTTOM", anchor, "BOTTOM", 0, (i - 1) * (CARD_HEIGHT + 4))
            cards[i] = c
        end
        if not list[i].seen then
            list[i].seen = true
            fresh = true
        end
        fillCard(c, list[i], #list)
    end
    for i = shown + 1, #cards do
        cards[i].inc = nil
        cards[i]:Hide()
    end
    ns.bidCards, ns.bidPopup = cards, cards[1]
    if fresh then sound("RAID_WARNING") end
end

ns.On("RGF_INCOMING_AUCTION", function(inc)
    -- answered: the card goes away. A later price change does not bring it back, /rgf rebid does.
    if inc.myBid then inc.reopened = nil end
    layout()
end)

ns.On("RGF_INCOMING_CLOSED", function() layout() end)

-- Show the cards again to change a bid, as long as bidding is open.
-- Returns the first shown item, or nil when nothing is open.
function ns.ReopenBidPopup()
    local now = GetTime()
    for _, inc in pairs(ns.incoming) do
        if now < inc.endsAt then inc.reopened = true end
    end
    layout()
    return cards[1] and cards[1]:IsShown() and cards[1].inc or nil
end

-- Answer the first card, for the key bindings. Returns true when a card was answered.
function ns.AnswerFirstBid(spec)
    local c = cards[1]
    if not (c and c:IsShown() and c.inc) then return false end
    if spec == "MS" and c.unusable then return false end
    answer(c, spec)
    return true
end

------------------------------------------------------------------------
-- Winner popup. Everyone with the addon sees for a few seconds who got the
-- item. It closes by itself or with a click, and can be turned off in the
-- settings. Several awards in a row are shown one after the other.
------------------------------------------------------------------------
local WINNER_SECONDS = 5
local winnerFrame
local winnerQueue = {}
local winnerShown = 0 -- counts up, so an old timer does not close a newer popup

local function buildWinner()
    local f = create("Button", "RedGuildForeverWinnerFrame", UIParent)
    f:SetSize(340, 64)
    place(f, "winner")
    f:SetFrameStrata("HIGH")
    goldFrame(f)
    makeMovable(f, f, "winner")
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(44, 44)
    f.icon:SetPoint("LEFT", 10, 0)
    f.title = text(f, "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, 0)
    f.title:SetWidth(266)
    f.item = text(f, "GameFontHighlight")
    f.item:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
    f.item:SetWidth(266)
    f.detail = text(f, "GameFontDisableSmall")
    f.detail:SetPoint("TOPLEFT", f.item, "BOTTOMLEFT", 0, -3)
    f.detail:SetWidth(266)
    f:SetScript("OnClick", function() ns.CloseWinner() end)
    f:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
        GameTooltip:AddLine("Click to close, drag to move. Turn this popup off in the game's Options under AddOns, Red Guild EPGP", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:Hide()
    return f
end

local function showNextWinner()
    local w = table.remove(winnerQueue, 1)
    if not w then
        if winnerFrame then winnerFrame:Hide() end
        return
    end
    winnerFrame = winnerFrame or buildWinner()
    ns.winnerFrame = winnerFrame
    local f = winnerFrame
    f.link = w.link
    local _, _, icon = ns.ItemInfo(w.link)
    f.icon:SetTexture(icon or ICON_UNKNOWN)
    local m = ns.members[w.name]
    local me = w.name == ns.PlayerName()
    f.title:SetText((me and "You win" or (ns.ShortName(w.name) .. " wins")) .. (w.test and "  |cffff8040Test|r" or ""))
    f.title:SetTextColor(classColor(m and m.class))
    f.item:SetText(w.link)
    f.detail:SetText((w.spec == "OS" and "Off spec" or "Main spec") .. ", " .. (w.cost > 0 and (w.cost .. " GP") or "free"))
    f:Show()
    if me then sound("UI_EPICLOOT_TOAST") end
    winnerShown = winnerShown + 1
    local shown = winnerShown
    ns.After(WINNER_SECONDS, function()
        if shown == winnerShown then showNextWinner() end
    end)
end

-- Close the shown popup now, the next winner follows if one waits
function ns.CloseWinner()
    winnerShown = winnerShown + 1
    showNextWinner()
end

ns.On("RGF_WINNER", function(w)
    if not ns.Setting("showWinner") or not (w and w.name and w.link) then return end
    table.insert(winnerQueue, w)
    if not (winnerFrame and winnerFrame:IsShown()) then showNextWinner() end
end)

