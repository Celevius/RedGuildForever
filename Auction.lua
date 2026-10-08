-- Auctions: the loot master opens bidding, raiders bid main spec or off spec,
-- the loot master awards the item.
--
-- Order of winners
--   1. Main spec before off spec
--   2. Main spec: members with at least minEP before new members,
--      then the highest priority (EP / GP), ties are decided by /roll
--   3. Off spec is free, the highest /roll wins

local _, ns = ...
ns = ns or _G.RedGuildForever

local SEP = "^"
ns.auction = nil   -- the auction this player runs as loot master
ns.incoming = {}   -- auctions this player can bid on, by id

local EPSILON = 0.000001

------------------------------------------------------------------------
-- Sorting
------------------------------------------------------------------------
local function refreshBid(bid)
    local ep, gp, pr, main = ns.GetPoints(bid.name)
    bid.ep, bid.gp, bid.pr, bid.main = ep, gp, pr, main
    bid.newcomer = ep < ns.Setting("minEP")
end

function ns.SortedBids(auction)
    local ms, os = {}, {}
    for _, bid in pairs(auction.bids) do
        refreshBid(bid)
        if bid.spec == "MS" then table.insert(ms, bid) else table.insert(os, bid) end
    end
    table.sort(ms, function(a, b)
        if a.newcomer ~= b.newcomer then return not a.newcomer end
        if math.abs(a.pr - b.pr) > EPSILON then return a.pr > b.pr end
        if (a.roll or -1) ~= (b.roll or -1) then return (a.roll or -1) > (b.roll or -1) end
        return a.name < b.name
    end)
    table.sort(os, function(a, b)
        if (a.roll or -1) ~= (b.roll or -1) then return (a.roll or -1) > (b.roll or -1) end
        return a.name < b.name
    end)
    local all = {}
    for _, b in ipairs(ms) do table.insert(all, b) end
    for _, b in ipairs(os) do table.insert(all, b) end
    return all, ms, os
end

-- Bidders that are tied for first place and still need to /roll.
function ns.TiedForFirst(auction)
    local _, ms, os = ns.SortedBids(auction)
    local group = {}
    if #ms > 0 then
        local top = ms[1]
        for _, b in ipairs(ms) do
            if b.newcomer == top.newcomer and math.abs(b.pr - top.pr) <= EPSILON then
                table.insert(group, b)
            end
        end
    elseif #os > 1 then
        group = os
    end
    if #group < 2 then return {} end
    -- once everyone in the group rolled and the top roll is unique, the tie is solved
    local allRolled, best, bestCount = true, -1, 0
    for _, b in ipairs(group) do
        if not b.roll then allRolled = false
        elseif b.roll > best then best, bestCount = b.roll, 1
        elseif b.roll == best then bestCount = bestCount + 1 end
    end
    if allRolled and bestCount == 1 then return {} end
    return group
end

------------------------------------------------------------------------
-- Loot master side
------------------------------------------------------------------------
local function newId()
    return tostring(math.random(100000, 999999))
end

local function bidsText(list, limit)
    local parts = {}
    for i, b in ipairs(list) do
        if i > limit then
            table.insert(parts, "and " .. (#list - limit) .. " more")
            break
        end
        local text = ns.ShortName(b.name)
        if b.spec == "MS" then
            text = text .. " " .. ns.FormatPR(b.pr)
            if b.newcomer then text = text .. " new" end
        end
        if b.roll then text = text .. " roll " .. b.roll end
        table.insert(parts, text)
    end
    return table.concat(parts, ", ")
end

function ns.StartAuction(link, tier)
    if not ns.CanEditNotes() then
        ns.Print("only officers who can edit officer notes can start bidding")
        return false
    end
    if ns.auction and ns.auction.open then
        ns.Print("bidding for " .. ns.auction.link .. " is still open, finish it first")
        return false
    end
    local itemID, _, icon = ns.ItemInfo(link)
    if not itemID then
        ns.Print("that is not an item link. Type /rgf bid and shift click the item")
        return false
    end
    tier = tier or "normal"
    local price, _, fixed = ns.ItemPrice(link, tier)
    local seconds = ns.Setting("bidSeconds")
    local auction = {
        id = newId(), link = link, itemID = itemID, icon = icon,
        tier = tier, price = price, fixed = fixed,
        bids = {}, open = true, endsAt = (GetTime and GetTime() or 0) + seconds,
        owner = ns.PlayerName(),
    }
    ns.auction = auction
    ns.SendComm(table.concat({ "A", auction.id, seconds, price, link }, SEP), IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or "WHISPER"), not IsInGroup() and UnitName("player") or nil)
    ns.Announce(string.format("Bids open for %s (%s, %d GP). Use the popup or whisper me ms or os. %d seconds.",
        link, fixed and "fixed price" or ns.defaults.tierNames[tier], price, seconds))
    ns.After(seconds, function()
        if ns.auction == auction and auction.open then ns.CloseBidding() end
    end)
    ns.Fire("RGF_AUCTION_CHANGED")
    return true
end

function ns.SetAuctionTier(tier)
    local a = ns.auction
    if not a or a.fixed or not ns.Setting("tiers")[tier] then return end
    a.tier = tier
    a.price = ns.ItemPrice(a.link, tier)
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if channel then ns.SendComm(table.concat({ "P", a.id, a.price }, SEP), channel) end
    if a.open then
        ns.Announce(string.format("%s now costs %d GP (%s).", a.link, a.price, ns.defaults.tierNames[tier]))
    end
    ns.Fire("RGF_AUCTION_CHANGED")
end

function ns.RecordBid(name, spec)
    local a = ns.auction
    if not a or not a.open then return false end
    local full = ns.FullName(name)
    if spec == "PASS" then
        a.bids[full] = nil
    elseif spec == "MS" or spec == "OS" then
        local bid = a.bids[full] or { name = full }
        bid.spec = spec
        a.bids[full] = bid
    else
        return false
    end
    ns.Fire("RGF_AUCTION_CHANGED")
    return true
end

function ns.CloseBidding()
    local a = ns.auction
    if not a or not a.open then return end
    a.open = false
    local all, ms, os = ns.SortedBids(a)
    if #all == 0 then
        ns.Announce("Bids closed for " .. a.link .. ". Nobody wants it, it goes to the guild bank or gets disenchanted.")
    else
        local text = "Bids closed for " .. a.link .. "."
        if #ms > 0 then text = text .. " Main spec " .. bidsText(ms, 5) .. "." end
        if #os > 0 then text = text .. " Off spec " .. bidsText(os, 5) .. "." end
        ns.Announce(text)
        local tied = ns.TiedForFirst(a)
        if #tied > 0 then ns.RequestRolls() end
    end
    ns.Fire("RGF_AUCTION_CHANGED")
end

function ns.RequestRolls()
    local a = ns.auction
    if not a then return end
    local tied = ns.TiedForFirst(a)
    if #tied == 0 then return end
    local names = {}
    for _, b in ipairs(tied) do
        b.roll = nil
        b.wantsRoll = true
        table.insert(names, ns.ShortName(b.name))
    end
    a.rollsOpen = true
    ns.Announce("Tie for " .. a.link .. " between " .. table.concat(names, ", ") .. ". Please /roll now.")
    ns.Fire("RGF_AUCTION_CHANGED")
end

-- Award to a bidder or to the guild bank (name nil).
function ns.Award(name)
    local a = ns.auction
    if not a then return false end
    if a.open then ns.CloseBidding() end
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if not name then
        ns.Announce(a.link .. " goes to the guild bank or gets disenchanted. It costs 0 GP.")
        if channel then ns.SendComm(table.concat({ "C", a.id, "" }, SEP), channel) end
        ns.auction = nil
        ns.Fire("RGF_AUCTION_CHANGED")
        return true
    end
    local full = ns.FullName(name)
    local bid = a.bids[full]
    local spec = bid and bid.spec or "MS"
    local cost = spec == "MS" and a.price or 0
    ns.BeginAction(ns.ShortName(full) .. " " .. a.link .. " " .. cost .. " GP")
    local main = ns.Adjust(full, 0, cost)
    ns.EndAction()
    if not main then return false end
    local who = ns.ShortName(full)
    if main ~= full then who = who .. " (alt of " .. ns.ShortName(main) .. ")" end
    if spec == "MS" then
        ns.Announce(string.format("%s wins %s for %d GP.", who, a.link, cost))
    else
        ns.Announce(string.format("%s gets %s for off spec. It is free.", who, a.link))
    end
    if channel then ns.SendComm(table.concat({ "C", a.id, full }, SEP), channel) end
    ns.lastAward = { link = a.link, name = full, cost = cost }
    ns.auction = nil
    ns.Fire("RGF_AUCTION_CHANGED")
    return true
end

function ns.CancelAuction()
    local a = ns.auction
    if not a then return end
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if channel then ns.SendComm(table.concat({ "C", a.id, "" }, SEP), channel) end
    ns.Announce("Bidding for " .. a.link .. " was cancelled.")
    ns.auction = nil
    ns.Fire("RGF_AUCTION_CHANGED")
end

------------------------------------------------------------------------
-- Rolls. We read the system message "Name rolls 57 (1-100)".
------------------------------------------------------------------------
local rollPattern
local function buildRollPattern()
    local fmt = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
    -- mark the placeholders, escape magic characters, then turn the marks into captures
    local p = fmt:gsub("%%%d?%$?s", "\001"):gsub("%%%d?%$?d", "\002")
    p = p:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1")
    p = p:gsub("\001", "(.+)"):gsub("\002", "(%%d+)")
    return "^" .. p .. "$"
end

function ns.ParseRoll(text)
    rollPattern = rollPattern or buildRollPattern()
    local name, roll, low, high = text:match(rollPattern)
    if not name then return nil end
    return name, tonumber(roll), tonumber(low), tonumber(high)
end

ns.On("CHAT_MSG_SYSTEM", function(text)
    local a = ns.auction
    if not a or not a.rollsOpen or type(text) ~= "string" then return end
    local ok, name, roll, low, high = pcall(ns.ParseRoll, text)
    if not ok or not name or low ~= 1 or high ~= 100 then return end
    local bid = a.bids[ns.FullName(name)]
    if bid and bid.wantsRoll and not bid.roll then
        bid.roll = roll
        ns.Fire("RGF_AUCTION_CHANGED")
        if #ns.TiedForFirst(a) == 0 then
            a.rollsOpen = false
            local all = ns.SortedBids(a)
            ns.Announce(ns.ShortName(all[1].name) .. " has the highest roll for " .. a.link .. ".")
            ns.Fire("RGF_AUCTION_CHANGED")
        end
    end
end)

------------------------------------------------------------------------
-- Whisper bids for players without the addon
------------------------------------------------------------------------
local whisperWords = {
    ms = "MS", main = "MS", mainspec = "MS", need = "MS", ["+"] = "MS",
    os = "OS", off = "OS", offspec = "OS", greed = "OS",
    pass = "PASS",
}

ns.On("CHAT_MSG_WHISPER", function(text, sender)
    local a = ns.auction
    if not a or not a.open or type(text) ~= "string" then return end
    local ok, word = pcall(function() return text:lower():gsub("%s", "") end)
    if not ok then return end
    local spec = whisperWords[word]
    if not spec then return end
    if ns.RecordBid(sender, spec) then
        local reply = spec == "PASS" and ("You passed on " .. a.link .. ".")
            or ("Got your " .. (spec == "MS" and "main spec" or "off spec") .. " bid for " .. a.link .. ".")
        ns.SendChat(reply, "WHISPER", sender)
    end
end)

------------------------------------------------------------------------
-- Raider side
------------------------------------------------------------------------
ns.OnComm("A", function(text, sender)
    local p = ns.SplitWithTail(text, 5)
    local id, seconds, price, link = p[2], tonumber(p[3]), tonumber(p[4]), p[5]
    if not id or not link then return end
    ns.incoming[id] = {
        id = id, owner = sender, link = link, price = price or 0,
        duration = seconds or 30,
        endsAt = (GetTime and GetTime() or 0) + (seconds or 30),
    }
    ns.Fire("RGF_INCOMING_AUCTION", ns.incoming[id])
end)

ns.OnComm("P", function(text)
    local p = ns.Split(text)
    local inc = ns.incoming[p[2]]
    if inc then
        inc.price = tonumber(p[3]) or inc.price
        ns.Fire("RGF_INCOMING_AUCTION", inc)
    end
end)

ns.OnComm("B", function(text, sender)
    local p = ns.Split(text)
    local a = ns.auction
    if a and a.id == p[2] then ns.RecordBid(sender, p[3]) end
end)

ns.OnComm("C", function(text)
    local p = ns.Split(text)
    local inc = ns.incoming[p[2]]
    if inc then
        ns.incoming[p[2]] = nil
        ns.Fire("RGF_INCOMING_CLOSED", inc, p[3] ~= "" and p[3] or nil)
    end
end)

function ns.SendBid(inc, spec)
    if not inc then return end
    local msg = table.concat({ "B", inc.id, spec }, SEP)
    if inc.owner == ns.PlayerName() then
        ns.RecordBid(ns.PlayerName(), spec)
    elseif not ns.SendComm(msg, "WHISPER", inc.owner) then
        -- addon messages can be blocked, a normal whisper always works
        ns.SendChat(spec == "MS" and "ms" or (spec == "OS" and "os" or "pass"), "WHISPER", inc.owner)
    end
    inc.myBid = spec
    ns.Fire("RGF_INCOMING_AUCTION", inc)
end
