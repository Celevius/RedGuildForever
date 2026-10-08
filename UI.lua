-- Windows: standings, loot master auction window, bid popup, bench.

local _, ns = ...
ns = ns or _G.RedGuildForever

if not CreateFrame then return end

local RED = { 0.77, 0.12, 0.23 }
local GOLD = { 1, 0.82, 0 }

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function classColor(classFile)
    if classFile and C_ClassColor and C_ClassColor.GetClassColor then
        local c = C_ClassColor.GetClassColor(classFile)
        if c then return c.r, c.g, c.b end
    end
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        return c.r, c.g, c.b
    end
    return 0.9, 0.9, 0.9
end

local function panel(name, width, height, title)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.06, 0.05, 0.05, 0.94)
    f:SetBackdropBorderColor(RED[1], RED[2], RED[3], 0.9)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    local bar = f:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(24)
    bar:SetColorTexture(RED[1] * 0.55, RED[2] * 0.55, RED[3] * 0.55, 0.9)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -7)
    f.title:SetText(title)
    f.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)

    if name and UISpecialFrames then table.insert(UISpecialFrames, name) end
    f:Hide()
    return f
end

local function button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function text(parent, template, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function scrollList(parent, rowHeight, buildRow)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self, w) content:SetWidth(w) end)
    local rows = {}
    function scroll:Row(i)
        if not rows[i] then
            local row = CreateFrame("Frame", nil, content)
            row:SetHeight(rowHeight)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
            row:SetPoint("RIGHT", content, "RIGHT")
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0)
            buildRow(row)
            rows[i] = row
        end
        return rows[i]
    end
    function scroll:SetCount(n)
        for i = n + 1, #rows do rows[i]:Hide() end
        content:SetHeight(math.max(1, n * rowHeight))
    end
    return scroll
end

------------------------------------------------------------------------
-- Standings
------------------------------------------------------------------------
local standings
local showAll = false
local columns = {
    { key = "name", label = "Name", x = 6, w = 150, justify = "LEFT" },
    { key = "ep", label = "EP", x = 160, w = 60, justify = "RIGHT" },
    { key = "gp", label = "GP", x = 225, w = 60, justify = "RIGHT" },
    { key = "pr", label = "Priority", x = 290, w = 70, justify = "RIGHT" },
    { key = "alts", label = "Alts", x = 365, w = 40, justify = "RIGHT" },
}

local function buildStandings()
    local f = panel("RedGuildForeverStandings", 450, 500, "Red Guild EPGP Standings")

    for _, c in ipairs(columns) do
        local h = text(f, "GameFontNormalSmall", c.justify)
        h:SetPoint("TOPLEFT", c.x + 8, -34)
        h:SetWidth(c.w)
        h:SetText(c.label)
    end

    f.list = scrollList(f, 18, function(row)
        row.cells = {}
        for _, c in ipairs(columns) do
            local fs = text(row, "GameFontHighlightSmall", c.justify)
            fs:SetPoint("LEFT", c.x, 0)
            fs:SetWidth(c.w)
            row.cells[c.key] = fs
        end
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            if not self.entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(ns.ShortName(self.entry.name))
            local alts = ns.AltsOf(self.entry.name)
            if #alts > 0 then
                local names = {}
                for _, a in ipairs(alts) do table.insert(names, ns.ShortName(a)) end
                GameTooltip:AddLine("Alts " .. table.concat(names, ", "), 1, 1, 1, true)
            end
            if self.entry.ep < ns.Setting("minEP") then
                GameTooltip:AddLine("New member until " .. ns.Setting("minEP") .. " EP", 0.6, 0.8, 1)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end)
    f.list:SetPoint("TOPLEFT", 8, -52)
    f.list:SetPoint("BOTTOMRIGHT", -30, 96)

    f.status = text(f, "GameFontDisableSmall")
    f.status:SetPoint("BOTTOMLEFT", 10, 74)
    f.status:SetPoint("RIGHT", -10, 0)

    f.allButton = button(f, "Show everyone", 120, function()
        showAll = not showAll
        ns.RefreshStandings()
    end)
    f.allButton:SetPoint("BOTTOMLEFT", 8, 42)

    f.syncButton = button(f, "Refresh", 90, function()
        ns.RequestRoster()
        if ns.CanViewNotes() then ns.QueueBroadcast(0) else ns.SendComm("SR", "GUILD") end
        ns.Print("refreshing standings")
    end)
    f.syncButton:SetPoint("LEFT", f.allButton, "RIGHT", 4, 0)

    -- officer tools
    f.officer = CreateFrame("Frame", nil, f)
    f.officer:SetPoint("BOTTOMLEFT", 8, 10)
    f.officer:SetSize(430, 24)
    local raid = button(f.officer, "Raid EP", 80, function() ns.Command("raid") end)
    raid:SetPoint("LEFT")
    local ontime = button(f.officer, "On time", 80, function() ns.Command("ontime") end)
    ontime:SetPoint("LEFT", raid, "RIGHT", 4, 0)
    local bench = button(f.officer, "Bench", 80, function() ns.ToggleBench() end)
    bench:SetPoint("LEFT", ontime, "RIGHT", 4, 0)
    local decay = button(f.officer, "Decay", 80, function() ns.Command("decay") end)
    decay:SetPoint("LEFT", bench, "RIGHT", 4, 0)
    local undo = button(f.officer, "Undo", 80, function() ns.Command("undo") end)
    undo:SetPoint("LEFT", decay, "RIGHT", 4, 0)

    f:SetScript("OnShow", function() ns.RefreshStandings() end)
    return f
end

function ns.RefreshStandings()
    if not standings or not standings:IsShown() then return end
    local list = ns.Standings(showAll)
    for i, e in ipairs(list) do
        local row = standings.list:Row(i)
        row.entry = e
        row.cells.name:SetText(ns.ShortName(e.name))
        row.cells.name:SetTextColor(classColor(e.class))
        row.cells.ep:SetText(e.ep)
        row.cells.gp:SetText(e.gp)
        row.cells.pr:SetText(ns.FormatPR(e.pr))
        if e.ep < ns.Setting("minEP") then
            row.cells.pr:SetTextColor(0.6, 0.8, 1)
        else
            row.cells.pr:SetTextColor(1, 1, 1)
        end
        row.cells.alts:SetText(e.alts > 0 and e.alts or "")
        row:Show()
    end
    standings.list:SetCount(#list)
    standings.allButton:SetText(showAll and "Only with points" or "Show everyone")
    standings.officer:SetShown(ns.CanEditNotes())

    local status
    if not (IsInGuild and IsInGuild()) then
        status = "You are not in a guild."
    elseif ns.CanViewNotes() then
        status = #list .. " players, read from officer notes. Blue priority means new member."
    elseif ns.synced.from then
        status = #list .. " players, sent by " .. ns.ShortName(ns.synced.from) .. " " .. date("%H:%M", ns.synced.at)
    else
        status = "Waiting for an officer to send the standings."
    end
    standings.status:SetText(status)
end

function ns.ToggleStandings()
    standings = standings or buildStandings()
    standings:SetShown(not standings:IsShown())
end

ns.On("RGF_POINTS_CHANGED", function() ns.RefreshStandings() end)

------------------------------------------------------------------------
-- Bench
------------------------------------------------------------------------
local bench

local function buildBench()
    local f = panel("RedGuildForeverBench", 240, 300, "Bench")
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", standings or UIParent, "TOPRIGHT", 6, 0)

    local hint = text(f, "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 10, -32)
    hint:SetText("Benched players get the same EP as the raid.")
    hint:SetWidth(220)

    f.list = scrollList(f, 18, function(row)
        row.label = text(row)
        row.label:SetPoint("LEFT", 4, 0)
        row.label:SetWidth(150)
        row.remove = button(row, "Remove", 60, function()
            ns.BenchRemove(row.name)
        end)
        row.remove:SetHeight(16)
        row.remove:SetPoint("RIGHT", -2, 0)
    end)
    f.list:SetPoint("TOPLEFT", 8, -50)
    f.list:SetPoint("BOTTOMRIGHT", -30, 40)

    local add = button(f, "Add target", 100, function()
        local name, realm = UnitName("target")
        if not name or not UnitIsPlayer("target") then
            ns.Print("target a player first, or type /rgf bench add Name")
            return
        end
        ns.BenchAdd(realm and realm ~= "" and (name .. "-" .. realm) or name)
    end)
    add:SetPoint("BOTTOMLEFT", 8, 10)
    local clear = button(f, "Clear", 70, function() ns.BenchClear() end)
    clear:SetPoint("LEFT", add, "RIGHT", 4, 0)

    f:SetScript("OnShow", function() ns.RefreshBench() end)
    return f
end

function ns.RefreshBench()
    if not bench or not bench:IsShown() then return end
    local list = ns.Bench()
    for i, name in ipairs(list) do
        local row = bench.list:Row(i)
        row.name = name
        row.label:SetText(ns.ShortName(name))
        local m = ns.members[name]
        row.label:SetTextColor(classColor(m and m.class))
        row:Show()
    end
    bench.list:SetCount(#list)
end

function ns.ToggleBench()
    bench = bench or buildBench()
    bench:SetShown(not bench:IsShown())
end

ns.On("RGF_BENCH_CHANGED", function() ns.RefreshBench() end)

------------------------------------------------------------------------
-- Loot master window
------------------------------------------------------------------------
local lm

local bidColumns = {
    { key = "name", label = "Name", x = 4, w = 130 },
    { key = "spec", label = "Spec", x = 136, w = 36 },
    { key = "ep", label = "EP", x = 174, w = 48, justify = "RIGHT" },
    { key = "gp", label = "GP", x = 224, w = 48, justify = "RIGHT" },
    { key = "pr", label = "Priority", x = 274, w = 56, justify = "RIGHT" },
    { key = "roll", label = "Roll", x = 334, w = 34, justify = "RIGHT" },
}

local function buildLootMaster()
    local f = panel("RedGuildForeverAuction", 470, 420, "Loot")
    f:ClearAllPoints()
    f:SetPoint("RIGHT", UIParent, "RIGHT", -120, 40)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(36, 36)
    f.icon:SetPoint("TOPLEFT", 10, -32)

    f.itemButton = CreateFrame("Button", nil, f)
    f.itemButton:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, 0)
    f.itemButton:SetSize(380, 18)
    f.item = text(f.itemButton, "GameFontNormal")
    f.item:SetAllPoints()
    f.itemButton:SetScript("OnEnter", function(self)
        if ns.auction then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(ns.auction.link)
            GameTooltip:Show()
        end
    end)
    f.itemButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.price = text(f, "GameFontHighlight")
    f.price:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, -20)

    f.tierButtons = {}
    local prev
    for _, tier in ipairs(ns.defaults.tierOrder) do
        local b = button(f, ns.defaults.tierNames[tier], 100, function() ns.SetAuctionTier(tier) end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 10, -76) end
        f.tierButtons[tier] = b
        prev = b
    end

    f.state = text(f, "GameFontNormalSmall")
    f.state:SetPoint("TOPLEFT", 10, -104)
    f.state:SetWidth(440)

    for _, c in ipairs(bidColumns) do
        local h = text(f, "GameFontNormalSmall", c.justify)
        h:SetPoint("TOPLEFT", c.x + 8, -124)
        h:SetWidth(c.w)
        h:SetText(c.label)
    end

    f.list = scrollList(f, 22, function(row)
        row.cells = {}
        for _, c in ipairs(bidColumns) do
            local fs = text(row, "GameFontHighlightSmall", c.justify)
            fs:SetPoint("LEFT", c.x, 0)
            fs:SetWidth(c.w)
            row.cells[c.key] = fs
        end
        row.award = button(row, "Award", 60, function()
            if row.bid then ns.Award(row.bid.name) end
        end)
        row.award:SetHeight(18)
        row.award:SetPoint("RIGHT", -2, 0)
    end)
    f.list:SetPoint("TOPLEFT", 8, -140)
    f.list:SetPoint("BOTTOMRIGHT", -30, 44)

    f.closeBids = button(f, "Close bids", 100, function() ns.CloseBidding() end)
    f.closeBids:SetPoint("BOTTOMLEFT", 8, 12)
    f.rolls = button(f, "Ask for rolls", 100, function() ns.RequestRolls() end)
    f.rolls:SetPoint("LEFT", f.closeBids, "RIGHT", 4, 0)
    f.bank = button(f, "Bank or DE", 100, function() ns.Award(nil) end)
    f.bank:SetPoint("LEFT", f.rolls, "RIGHT", 4, 0)
    f.cancel = button(f, "Cancel", 80, function() ns.CancelAuction() end)
    f.cancel:SetPoint("LEFT", f.bank, "RIGHT", 4, 0)

    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.5 then return end
        elapsed = 0
        local a = ns.auction
        if a and a.open then
            local left = math.max(0, math.ceil(a.endsAt - GetTime()))
            f.state:SetText("Bidding open, " .. left .. " seconds left")
        end
    end)
    return f
end

function ns.RefreshLootMaster()
    local a = ns.auction
    if not a then
        if lm then lm:Hide() end
        return
    end
    lm = lm or buildLootMaster()
    lm:Show()
    lm.icon:SetTexture(a.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    lm.item:SetText(a.link)
    lm.price:SetText(a.price .. " GP for main spec, off spec is free" .. (a.fixed and " (fixed price)" or ""))
    for tier, b in pairs(lm.tierButtons) do
        b:SetEnabled(not a.fixed and tier ~= a.tier)
    end

    local list = ns.SortedBids(a)
    local tied = ns.TiedForFirst(a)
    if not a.open then
        if #list == 0 then
            lm.state:SetText("Bidding closed. No bids, give it to the bank or disenchant it.")
        elseif #tied > 0 then
            lm.state:SetText("Bidding closed. Tie for first place, waiting for /roll.")
        else
            lm.state:SetText("Bidding closed. Award the item to the first player.")
        end
    end
    for i, b in ipairs(list) do
        local row = lm.list:Row(i)
        row.bid = b
        local name = ns.ShortName(b.name)
        if b.main and b.main ~= b.name then name = name .. " (" .. ns.ShortName(b.main) .. ")" end
        row.cells.name:SetText(name)
        local m = ns.members[b.name]
        row.cells.name:SetTextColor(classColor(m and m.class))
        row.cells.spec:SetText(b.spec)
        row.cells.spec:SetTextColor(b.spec == "MS" and 0.4 or 0.7, b.spec == "MS" and 1 or 0.7, b.spec == "MS" and 0.4 or 0.7)
        row.cells.ep:SetText(b.ep)
        row.cells.gp:SetText(b.gp)
        row.cells.pr:SetText(b.spec == "MS" and (ns.FormatPR(b.pr) .. (b.newcomer and " new" or "")) or "free")
        row.cells.roll:SetText(b.roll or (b.wantsRoll and "..." or ""))
        row:Show()
    end
    lm.list:SetCount(#list)
    lm.closeBids:SetEnabled(a.open)
    lm.rolls:SetEnabled(not a.open and #tied > 0)
end

ns.On("RGF_AUCTION_CHANGED", function() ns.RefreshLootMaster() end)

------------------------------------------------------------------------
-- Bid popup for raiders
------------------------------------------------------------------------
local popup

local function buildPopup()
    local f = panel("RedGuildForeverBid", 320, 170, "Loot bid")
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "TOP", 0, -160)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(40, 40)
    f.icon:SetPoint("TOPLEFT", 10, -32)

    f.itemButton = CreateFrame("Button", nil, f)
    f.itemButton:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, 0)
    f.itemButton:SetSize(250, 18)
    f.item = text(f.itemButton, "GameFontNormal")
    f.item:SetAllPoints()
    f.itemButton:SetScript("OnEnter", function(self)
        if f.inc then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(f.inc.link)
            GameTooltip:Show()
        end
    end)
    f.itemButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.price = text(f, "GameFontHighlightSmall")
    f.price:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, -20)
    f.price:SetWidth(250)

    f.mine = text(f, "GameFontHighlightSmall")
    f.mine:SetPoint("TOPLEFT", 10, -80)
    f.mine:SetWidth(300)

    f.timer = text(f, "GameFontDisableSmall")
    f.timer:SetPoint("TOPLEFT", 10, -98)
    f.timer:SetWidth(300)

    f.ms = button(f, "Main spec", 96, function() ns.SendBid(f.inc, "MS") end)
    f.ms:SetPoint("BOTTOMLEFT", 10, 12)
    f.os = button(f, "Off spec", 96, function() ns.SendBid(f.inc, "OS") end)
    f.os:SetPoint("LEFT", f.ms, "RIGHT", 6, 0)
    f.pass = button(f, "Pass", 96, function()
        if f.inc and f.inc.myBid then ns.SendBid(f.inc, "PASS") end
        f:Hide()
    end)
    f.pass:SetPoint("LEFT", f.os, "RIGHT", 6, 0)

    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.5 or not f.inc then return end
        elapsed = 0
        local left = math.ceil(f.inc.endsAt - GetTime())
        if left <= 0 then
            f.timer:SetText("Bidding closed, waiting for the loot master.")
            f.ms:SetEnabled(false)
            f.os:SetEnabled(false)
        else
            f.timer:SetText(left .. " seconds left")
        end
    end)
    return f
end

ns.On("RGF_INCOMING_AUCTION", function(inc)
    popup = popup or buildPopup()
    popup.inc = inc
    local _, _, icon = ns.ItemInfo(inc.link)
    popup.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    popup.item:SetText(inc.link)
    popup.price:SetText(inc.price .. " GP for main spec, off spec is free")
    local ep, gp, pr, main = ns.GetPoints(ns.PlayerName())
    local line = "Your priority " .. ns.FormatPR(pr) .. " (" .. ep .. " EP, " .. gp .. " GP)"
    if main and main ~= ns.PlayerName() then line = line .. " via " .. ns.ShortName(main) end
    if ep < ns.Setting("minEP") then line = line .. ", new member" end
    popup.mine:SetText(line)
    local open = GetTime() < inc.endsAt
    popup.ms:SetEnabled(open)
    popup.os:SetEnabled(open)
    if inc.myBid == "MS" then
        popup.timer:SetText("You bid main spec")
    elseif inc.myBid == "OS" then
        popup.timer:SetText("You bid off spec")
    end
    popup.ms:SetText(inc.myBid == "MS" and "[Main spec]" or "Main spec")
    popup.os:SetText(inc.myBid == "OS" and "[Off spec]" or "Off spec")
    popup:Show()
end)

ns.On("RGF_INCOMING_CLOSED", function(inc)
    if popup and popup.inc == inc then popup:Hide() end
end)

------------------------------------------------------------------------
-- Decay confirmation
------------------------------------------------------------------------
if StaticPopupDialogs then
    StaticPopupDialogs["REDGUILDFOREVER_DECAY"] = {
        text = "Shrink all EP and GP by %s percent? Do this once a week.",
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function()
            local n = ns.Decay()
            ns.Print("decay done for " .. n .. " players")
            ns.SendChat("Weekly EPGP decay of " .. ns.Setting("decayPercent") .. " percent is done.", "GUILD")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end
