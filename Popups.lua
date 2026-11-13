-- SPDX-License-Identifier: MIT, see LICENSE
-- Popups: the bid popup for raiders and the winner popup.

local _, ns = ...
ns = ns or _G.RedGuildForever
if not CreateFrame then return end

local UI = ns.UI
local create, text, button, window, itemButton = UI.create, UI.text, UI.button, UI.window, UI.itemButton
local setTitle, setPortrait, sound, classColor = UI.setTitle, UI.setPortrait, UI.sound, UI.classColor
local ICON_UNKNOWN = UI.ICON_UNKNOWN

------------------------------------------------------------------------
-- Bid popup for raiders, inspired by the Need or Greed loot roll
------------------------------------------------------------------------
local popup
local nextUnanswered, showPopup

local function buildPopup()
    local f = window("RedGuildForeverBidFrame", 380, 214, "Loot Bid", ICON_UNKNOWN)
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    f:SetFrameStrata("DIALOG")

    f.item = text(f, "GameFontNormal")
    f.item:SetPoint("TOPLEFT", 66, -32)
    f.item:SetWidth(290)
    f.price = text(f, "GameFontHighlightSmall")
    f.price:SetPoint("TOPLEFT", f.item, "BOTTOMLEFT", 0, -3)
    f.price:SetWidth(290)

    f.slot = itemButton(f.Inset, 40)
    f.slot:SetPoint("TOPLEFT", 12, -12)

    f.mine = text(f.Inset, "GameFontHighlight")
    f.mine:SetPoint("TOPLEFT", f.slot, "TOPRIGHT", 10, -2)
    f.mine:SetWidth(280)
    f.note = text(f.Inset, "GameFontNormalSmall")
    f.note:SetPoint("TOPLEFT", f.mine, "BOTTOMLEFT", 0, -4)
    f.note:SetWidth(280)

    -- timer bar like the loot roll frame
    f.timer = CreateFrame("StatusBar", nil, f.Inset)
    f.timer:SetPoint("BOTTOMLEFT", 12, 12)
    f.timer:SetPoint("BOTTOMRIGHT", -12, 12)
    f.timer:SetHeight(10)
    f.timer:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    f.timer:SetStatusBarColor(1, 0.82, 0)
    f.timer:SetMinMaxValues(0, 1)
    local bg = f.timer:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    f.timerText = text(f.Inset, "GameFontDisableSmall", "CENTER")
    f.timerText:SetPoint("BOTTOM", f.timer, "TOP", 0, 3)

    f.ms = button(f, "Main Spec", 112, function() ns.SendBid(f.inc, "MS") end)
    f.ms:SetPoint("BOTTOMLEFT", 6, 4)
    f.pass = button(f, "Pass", 112, function()
        local inc = f.inc
        if inc and inc.myBid then ns.SendBid(inc, "PASS") end
        if inc then inc.myBid = inc.myBid or "PASS" end
        local nextInc = nextUnanswered(inc)
        if nextInc then showPopup(nextInc) else f:Hide() end
    end)
    f.pass:SetPoint("BOTTOMRIGHT", -6, 4)
    f.os = button(f, "Off Spec", 112, function() ns.SendBid(f.inc, "OS") end)
    f.os:SetPoint("LEFT", f.ms, "RIGHT", 6, 0)
    f.os:SetPoint("RIGHT", f.pass, "LEFT", -6, 0)

    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.1 or not f.inc then return end
        elapsed = 0
        local total = f.inc.duration or 30
        local left = f.inc.endsAt - GetTime()
        f.timer:SetValue(math.max(0, left / total))
        if left <= 0 then
            f.timerText:SetText("Bidding closed, waiting for the loot master")
            f.ms:SetEnabled(false)
            f.os:SetEnabled(false)
        else
            f.timerText:SetText(math.ceil(left) .. " seconds")
        end
    end)
    return f
end

-- The next item that is open and not answered yet, lowest number first
nextUnanswered = function(except)
    local best
    local now = GetTime()
    for _, inc in pairs(ns.incoming) do
        if inc ~= except and not inc.myBid and now < inc.endsAt then
            if not best or (inc.n or 0) < (best.n or 0) or ((inc.n or 0) == (best.n or 0) and inc.id < best.id) then
                best = inc
            end
        end
    end
    return best
end

local function waitingCount(except)
    local n = 0
    local now = GetTime()
    for _, inc in pairs(ns.incoming) do
        if inc ~= except and not inc.myBid and now < inc.endsAt then n = n + 1 end
    end
    return n
end

ns.On("RGF_INCOMING_AUCTION", function(inc)
    popup = popup or buildPopup()
    local current = popup:IsShown() and popup.inc
    if current and current ~= inc and not current.myBid and GetTime() < current.endsAt then
        -- the player still has to answer the shown item, the new one waits
        showPopup(current)
        return
    end
    if inc.myBid then
        -- answered: the popup goes away, or goes on with the next item that waits.
        -- A later price change does not bring it back, /rgf rebid does.
        if current == inc then
            local nextInc = nextUnanswered(inc)
            if nextInc then showPopup(nextInc) else popup:Hide() end
        end
        return
    end
    showPopup(inc)
end)

-- Show the bid popup again to change a bid, as long as bidding is open.
-- Returns the shown item, or nil when nothing is open.
function ns.ReopenBidPopup()
    local inc = nextUnanswered(nil)
    if not inc then
        for _, x in pairs(ns.incoming) do
            if GetTime() < x.endsAt and (not inc or (x.n or 0) < (inc.n or 0)) then inc = x end
        end
    end
    if not inc then return nil end
    popup = popup or buildPopup()
    showPopup(inc)
    return inc
end

showPopup = function(inc)
    popup.inc = inc
    ns.bidPopup = popup
    setTitle(popup, ns.IsTest() and "Loot Bid  |cffff8040Test mode|r" or "Loot Bid")
    local _, _, icon = ns.ItemInfo(inc.link)
    setPortrait(popup, icon or ICON_UNKNOWN)
    popup.slot:SetItem(inc.link)
    popup.item:SetText(inc.link)
    popup.price:SetText("Main spec |cffffffff" .. inc.price .. " GP|r, " .. ns.OffSpecText(inc.price))

    local me = ns.PlayerName()
    local ep, gp, pr, mainName = ns.GetPoints(me)
    popup.mine:SetText("Your priority |cffffd100" .. ns.FormatPR(pr) .. "|r")
    local note = ep .. " EP, " .. gp .. " GP"
    if mainName and mainName ~= me then note = note .. ", points of " .. ns.ShortName(mainName) end
    if ep < ns.Setting("minEP") then note = note .. ", |cff66c7ffnew member|r" end
    popup.note:SetText(note)

    local open = GetTime() < inc.endsAt
    popup.ms:SetEnabled(open)
    popup.os:SetEnabled(open)
    popup.ms:SetText(inc.myBid == "MS" and "|cff40ff40Main Spec|r" or "Main Spec")
    popup.os:SetText(inc.myBid == "OS" and "|cff40ff40Off Spec|r" or "Off Spec")
    local waiting = waitingCount(inc)
    popup.timerText:SetText("")
    if waiting > 0 then
        popup.note:SetText(note .. "\n|cffff8040" .. waiting .. (waiting == 1 and " more item waits" or " more items wait") .. "|r")
    end
    if not popup:IsShown() then
        popup:Show()
        sound("RAID_WARNING")
    end
end

ns.On("RGF_INCOMING_CLOSED", function(inc)
    if popup and popup.inc == inc then
        local nextInc = nextUnanswered(inc)
        if nextInc then showPopup(nextInc) else popup:Hide() end
    end
end)

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
    f:SetPoint("TOP", UIParent, "TOP", 0, -70)
    f:SetFrameStrata("HIGH")
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.02, 0.02, 0.88)
    -- a thin gold frame
    for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
        { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
        local line = f:CreateTexture(nil, "BORDER")
        line:SetPoint(edge[1])
        line:SetPoint(edge[2])
        if edge[3] then line:SetWidth(edge[3]) else line:SetHeight(edge[4]) end
        line:SetColorTexture(1, 0.82, 0, 0.9)
    end
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
        GameTooltip:AddLine("Click to close. Turn this popup off in the game's Options under AddOns, Red Guild EPGP", 0.6, 0.6, 0.6, true)
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

