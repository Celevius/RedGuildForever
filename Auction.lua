-- SPDX-License-Identifier: MIT, see LICENSE
-- Auctions: the loot master opens bidding, raiders bid main spec or off spec,
-- the loot master awards the item.
--
-- Order of winners
--   1. Main spec before off spec
--   2. Main spec: members with at least minEP before new members,
--      then the highest priority (EP / GP), ties are decided by /roll
--   3. Off spec costs the off spec percent of the price (free by default), the highest /roll wins

local _, ns = ...
ns = ns or _G.RedGuildForever

local SEP = "^"
ns.auctions = {}   -- the auctions this player runs as loot master, several can be open
ns.auction = nil   -- the one shown in the Loot Master window
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

-- Returns all bids in winning order, then main spec, off spec and passes.
function ns.SortedBids(auction)
    local ms, os, passed = {}, {}, {}
    for _, bid in pairs(auction.bids) do
        refreshBid(bid)
        if bid.spec == "MS" then
            table.insert(ms, bid)
        elseif bid.spec == "OS" then
            table.insert(os, bid)
        else
            table.insert(passed, bid)
        end
    end
    table.sort(passed, function(a, b) return a.name < b.name end)
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
    return all, ms, os, passed
end

-- Everything the loot master needs to see: who bid what and who is still missing.
function ns.AuctionOverview(auction)
    local all, ms, os, passed = ns.SortedBids(auction)
    local waiting = {}
    for _, name in ipairs(auction.expected or {}) do
        if not auction.bids[name] then table.insert(waiting, name) end
    end
    table.sort(waiting)
    return { all = all, ms = ms, os = os, passed = passed, waiting = waiting, winner = all[1] }
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
-- In test mode nothing goes to the raid and no points change.
local function say(a, msg)
    if a and a.test then
        ns.Print("|cffff8040[Test]|r " .. msg)
    else
        ns.Announce(msg)
    end
end

local function groupChannel(a)
    if a and a.test then return nil end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

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

-- The lowest number no running auction uses, raiders whisper "ms 2" with it
local function freeNumber()
    local used = {}
    for _, a in ipairs(ns.auctions) do used[a.n] = true end
    local n = 1
    while used[n] do n = n + 1 end
    return n
end

function ns.SelectAuction(a)
    ns.auction = a
    ns.Fire("RGF_AUCTION_CHANGED")
end

local function removeAuction(a)
    for i, x in ipairs(ns.auctions) do
        if x == a then table.remove(ns.auctions, i) break end
    end
    if ns.auction == a then
        -- show the next one that still needs the loot master
        ns.auction = ns.auctions[1]
    end
end

local function priceText(a)
    return (a.fixed and "fixed price" or ns.defaults.tierNames[a.tier] or "custom") .. ", " .. a.price .. " GP"
end

-- Raid chat lines are short, so a long list goes out in several lines
local function sayList(a, first, parts, last)
    local line = first
    for i, part in ipairs(parts) do
        local sep = i == 1 and " " or ", "
        if #line + #sep + #part > 240 then
            say(a, line)
            line = part
        else
            line = line .. sep .. part
        end
    end
    if #line + #last > 250 then
        say(a, line .. ".")
        line = last:gsub("^%.%s*", "")
        say(a, line)
    else
        say(a, line .. last)
    end
end

-- Open bidding for one item. With quiet the caller announces it.
function ns.StartAuction(link, tier, quiet)
    local test = ns.IsTest()
    if not ns.CanEdit() then
        ns.Print("only the guild leader and editors can start bidding, turn on test mode in the settings to try it")
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
        id = newId(), n = freeNumber(), link = link, itemID = itemID, icon = icon,
        tier = tier, price = price, fixed = fixed,
        bids = {}, open = true, endsAt = (GetTime and GetTime() or 0) + seconds,
        owner = ns.PlayerName(), expected = ns.RaidMembers(), test = test,
    }
    table.insert(ns.auctions, auction)
    if not (ns.auction and ns.auction.open) then ns.auction = auction end
    if IsInGroup() and not test then
        ns.SendComm(table.concat({ "A", auction.id, seconds, price, auction.n, link }, SEP), IsInRaid() and "RAID" or "PARTY")
    end
    -- the loot master gets the same bid popup as everyone else
    ns.ReceiveAuction(auction.id, ns.PlayerName(), ns.PlayerName(), link, price, seconds, auction.n)
    if not quiet then
        if #ns.OpenAuctions() > 1 then
            say(auction, string.format("Bids open for %d. %s (%s). Whisper me ms %d or os %d. %d seconds.",
                auction.n, link, priceText(auction), auction.n, auction.n, seconds))
        else
            say(auction, string.format("Bids open for %s (%s). Use the popup or whisper me ms or os. %d seconds.",
                link, priceText(auction), seconds))
        end
    end
    ns.After(seconds, function()
        if auction.open then ns.CloseBidding(auction) end
    end)
    if test then ns.SimulateBids(auction) end
    ns.Fire("RGF_AUCTION_CHANGED")
    return auction
end

-- Open bidding for several items at once, items = { { link, tier }, ... }.
-- Returns the number of started auctions.
function ns.StartAuctions(items)
    local started = {}
    for _, item in ipairs(items) do
        local a = ns.StartAuction(item[1], item[2], true)
        if a then table.insert(started, a) end
    end
    if #started == 0 then return 0 end
    if #started == 1 and #ns.OpenAuctions() == 1 then
        local a = started[1]
        say(a, string.format("Bids open for %s (%s). Use the popup or whisper me ms or os. %d seconds.",
            a.link, priceText(a), ns.Setting("bidSeconds")))
    else
        local parts = {}
        for _, a in ipairs(started) do table.insert(parts, a.n .. ". " .. a.link .. " " .. a.price .. " GP") end
        sayList(started[1], "Bids open for", parts, string.format(". Use the popup or whisper me ms %d, os %d or pass %d with the number. %d seconds.",
            started[1].n, started[#started].n, started[1].n, ns.Setting("bidSeconds")))
    end
    return #started
end

function ns.SetAuctionTier(tier, auction)
    local a = auction or ns.auction
    if not a or a.fixed or not ns.Setting("tiers")[tier] then return end
    a.tier = tier
    a.price = ns.ItemPrice(a.link, tier)
    local channel = groupChannel(a)
    if channel then ns.SendComm(table.concat({ "P", a.id, a.price }, SEP), channel) end
    if ns.incoming[a.id] then
        ns.incoming[a.id].price = a.price
        ns.Fire("RGF_INCOMING_AUCTION", ns.incoming[a.id])
    end
    if a.open then
        say(a, string.format("%s now costs %d GP (%s).", a.link, a.price, ns.defaults.tierNames[tier]))
    end
    ns.Fire("RGF_AUCTION_CHANGED")
end

-- Passes are kept, so the loot master sees who said no.
-- The loot master can type any price for this one item.
function ns.SetAuctionPrice(gp, auction)
    local a = auction or ns.auction
    gp = tonumber(gp)
    if not a or not gp or gp < 0 then return false end
    a.price = math.floor(gp)
    a.tier = "custom"
    local channel = groupChannel(a)
    if channel then ns.SendComm(table.concat({ "P", a.id, a.price }, SEP), channel) end
    if ns.incoming[a.id] then
        ns.incoming[a.id].price = a.price
        ns.Fire("RGF_INCOMING_AUCTION", ns.incoming[a.id])
    end
    if a.open then say(a, string.format("%s now costs %d GP.", a.link, a.price)) end
    ns.Fire("RGF_AUCTION_CHANGED")
    return true
end

function ns.RecordBid(name, spec, auction)
    local a = auction or ns.auction
    if not a or not a.open then return false end
    if spec ~= "MS" and spec ~= "OS" and spec ~= "PASS" then return false end
    local full = ns.Resolve(name)
    local bid = a.bids[full] or { name = full }
    -- the name exactly as the game sent it, to whisper back
    if type(name) == "string" and name ~= full then bid.raw = name end
    bid.spec = spec
    bid.at = GetTime and GetTime() or 0
    a.bids[full] = bid
    ns.Fire("RGF_AUCTION_CHANGED")
    return true
end

function ns.CloseBidding(auction)
    local a = auction or ns.auction
    if not a or not a.open then return end
    a.open = false
    ns.lastClosed = { link = a.link, at = GetTime and GetTime() or 0 }
    local all, ms, os = ns.SortedBids(a)
    if #all == 0 then
        say(a, "Bids closed for " .. a.link .. ". Nobody wants it, it goes to the guild bank or gets disenchanted.")
    else
        local text = "Bids closed for " .. a.link .. "."
        if #ms > 0 then text = text .. " Main spec " .. bidsText(ms, 5) .. "." end
        if #os > 0 then text = text .. " Off spec " .. bidsText(os, 5) .. "." end
        say(a, text)
        local tied = ns.TiedForFirst(a)
        if #tied > 0 then ns.RequestRolls(a) end
    end
    ns.Fire("RGF_AUCTION_CHANGED")
end

function ns.RequestRolls(auction)
    local a = auction or ns.auction
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
    if a.test then ns.After(2, function() ns.Fire("RGF_TEST_ROLLS") end) end
    say(a, "Tie for " .. a.link .. " between " .. table.concat(names, ", ") .. ". Please /roll now.")
    ns.Fire("RGF_AUCTION_CHANGED")
end

local function closeOwnPopup(a, winner)
    local inc = ns.incoming[a.id]
    if inc then
        ns.incoming[a.id] = nil
        ns.Fire("RGF_INCOMING_CLOSED", inc, winner)
    end
end

-- What a player would pay for the item, and whether as main spec or off spec.
function ns.AwardCost(a, name)
    local bid = a.bids[ns.Resolve(name)]
    local spec = bid and bid.spec or "MS"
    if spec == "PASS" then spec = "MS" end -- given to someone who passed, normal price
    return spec == "MS" and a.price or ns.OffSpecCost(a.price), spec
end

-- Award to a bidder or to the guild bank (name nil).
function ns.Award(name, auction)
    local a = auction or ns.auction
    if not a then return false end
    if a.open then ns.CloseBidding(a) end
    local channel = groupChannel(a)
    if not name then
        say(a, a.link .. " goes to the guild bank or gets disenchanted. It costs 0 GP.")
        if channel then ns.SendComm(table.concat({ "C", a.id, "" }, SEP), channel) end
        closeOwnPopup(a)
        removeAuction(a)
        ns.Fire("RGF_AUCTION_CHANGED")
        return true
    end
    local full = ns.Resolve(name)
    local bid = a.bids[full]
    local spec = bid and bid.spec or "MS"
    if spec == "PASS" then spec = "MS" end -- given to someone who passed, normal price
    local cost = spec == "MS" and a.price or ns.OffSpecCost(a.price)
    ns.BeginAction(ns.ShortName(full) .. " " .. a.link .. " " .. cost .. " GP", { kind = "loot", item = a.itemID })
    local main = ns.Adjust(full, 0, cost)
    ns.EndAction()
    if not main then return false end
    local who = ns.ShortName(full)
    if main ~= full then who = who .. " (alt of " .. ns.ShortName(main) .. ")" end
    if spec == "MS" then
        say(a, string.format("%s wins %s for %d GP.", who, a.link, cost))
    else
        if cost > 0 then
            say(a, string.format("%s gets %s for off spec for %d GP.", who, a.link, cost))
        else
            say(a, string.format("%s gets %s for off spec. It is free.", who, a.link))
        end
    end
    -- the cost, the spec and the link travel along, for the winner popup of everyone
    if channel then ns.SendComm(table.concat({ "C", a.id, full, cost, spec, a.link }, SEP), channel) end
    closeOwnPopup(a, full)
    ns.Fire("RGF_WINNER", { name = full, link = a.link, cost = cost, spec = spec, test = a.test })
    -- tell the winner, also players without the addon, and the new priority
    if full ~= ns.PlayerName() and not a.test then
        local ep, gp, pr = ns.GetPoints(full)
        ns.SendChat(string.format("You got %s for %d GP. Your priority is now %s (%d EP, %d GP).",
            a.link, cost, ns.FormatPR(pr), ep, gp), "WHISPER", bid and bid.raw or ns.ShortName(full))
    end
    ns.lastAward = { link = a.link, name = full, cost = cost }
    removeAuction(a)
    ns.Fire("RGF_AUCTION_CHANGED")
    return true
end

function ns.CancelAuction(auction)
    local a = auction or ns.auction
    if not a then return end
    local channel = groupChannel(a)
    if channel then ns.SendComm(table.concat({ "C", a.id, "" }, SEP), channel) end
    say(a, "Bidding for " .. a.link .. " was cancelled.")
    closeOwnPopup(a)
    removeAuction(a)
    ns.Fire("RGF_AUCTION_CHANGED")
end

-- Cancel everything, used when test mode is switched
function ns.CancelAllAuctions()
    while ns.auctions[1] do ns.CancelAuction(ns.auctions[1]) end
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

-- With several ties at once, a roll counts for the first item the player still has to roll for.
ns.On("CHAT_MSG_SYSTEM", function(text)
    if type(text) ~= "string" then return end
    local ok, name, roll, low, high = pcall(ns.ParseRoll, text)
    if not ok or not name or low ~= 1 or high ~= 100 then return end
    local full = ns.Resolve(name)
    for _, a in ipairs(ns.auctions) do
        local bid = a.rollsOpen and a.bids[full]
        if bid and bid.wantsRoll and not bid.roll then
            bid.roll = roll
            ns.Fire("RGF_AUCTION_CHANGED")
            if #ns.TiedForFirst(a) == 0 then
                a.rollsOpen = false
                local all = ns.SortedBids(a)
                say(a, ns.ShortName(all[1].name) .. " has the highest roll for " .. a.link .. ".")
                ns.Fire("RGF_AUCTION_CHANGED")
            end
            return
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
-- words that clearly mean a bid, these get an answer also when nothing is open
local clearBids = { ms = true, mainspec = true, os = true, offspec = true, pass = true }

-- "ms", "MS 2", "os 1", "pass". Returns the spec, the item number (or nil)
-- and the word.
function ns.ParseWhisperBid(text)
    local ok, word, number = pcall(function()
        local t = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
        local w, n = t:match("^(%S+)%s*(%d*)$")
        return w, n
    end)
    if not ok or not word then return nil end
    local spec = whisperWords[word]
    if not spec then return nil end
    return spec, tonumber(number), word
end

-- The open auctions of this loot master, numbered like in the raid announcement
function ns.OpenAuctions()
    local list = {}
    for _, a in ipairs(ns.auctions) do
        if a.open then table.insert(list, a) end
    end
    return list
end

local function bidReply(a, spec)
    if spec == "PASS" then return "You passed on " .. a.link .. "." end
    return "Got your " .. (spec == "MS" and "main spec" or "off spec") .. " bid for " .. a.link .. "."
end

ns.On("CHAT_MSG_WHISPER", function(text, sender)
    if type(text) ~= "string" or ns.IsTest() then return end
    local spec, number, word = ns.ParseWhisperBid(text)
    if not spec then return end
    local open = ns.OpenAuctions()
    local a
    if number then
        for _, x in ipairs(open) do if (x.n or 1) == number then a = x end end
    elseif #open == 1 then
        a = open[1]
    end
    if a then
        if ns.RecordBid(sender, spec, a) then ns.SendChat(bidReply(a, spec), "WHISPER", sender) end
        return
    end
    -- nothing to bid on: answer real bids, but not a "+" for a raid invite
    if not clearBids[word] or not ns.CanEdit() or not (IsInGroup and IsInGroup()) then return end
    if #open > 1 then
        local items = {}
        for _, x in ipairs(open) do table.insert(items, (x.n or 1) .. " " .. x.link) end
        ns.SendChat("Several items are open: " .. table.concat(items, ", ") .. ". Whisper for example ms " .. (open[1].n or 1) .. " or os " .. (open[#open].n or 1) .. ".", "WHISPER", sender)
    elseif ns.lastClosed and ns.lastClosed.at and (GetTime() - ns.lastClosed.at) < 120 then
        ns.SendChat("Bidding for " .. ns.lastClosed.link .. " is closed already.", "WHISPER", sender)
    else
        ns.SendChat("No bidding is open right now. Wait for the announcement in raid chat.", "WHISPER", sender)
    end
end)

------------------------------------------------------------------------
-- Raider side
------------------------------------------------------------------------
-- Show the bid popup. The loot master calls this himself, everyone else
-- gets it by addon message. A second call for the same item keeps the bid.
function ns.ReceiveAuction(id, owner, ownerRaw, link, price, seconds, n)
    if not id or not link then return end
    local inc = ns.incoming[id]
    if not inc then
        inc = {
            id = id, owner = owner, ownerRaw = ownerRaw or owner, link = link, n = n,
            duration = seconds or 30,
            endsAt = (GetTime and GetTime() or 0) + (seconds or 30),
        }
        ns.incoming[id] = inc
    end
    inc.price = price or inc.price or 0
    ns.Fire("RGF_INCOMING_AUCTION", inc)
end

ns.OnComm("A", function(text, sender, _, rawSender)
    local p = ns.SplitWithTail(text, 6)
    ns.ReceiveAuction(p[2], sender, rawSender, p[6], tonumber(p[4]), tonumber(p[3]), tonumber(p[5]))
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
    for _, a in ipairs(ns.OpenAuctions()) do
        if a.id == p[2] then ns.RecordBid(sender, p[3], a) end
    end
end)

ns.OnComm("C", function(text, sender)
    local p = ns.SplitWithTail(text, 6)
    local winner = p[3] ~= "" and p[3] or nil
    local inc = ns.incoming[p[2]]
    if inc then
        ns.incoming[p[2]] = nil
        ns.Fire("RGF_INCOMING_CLOSED", inc, winner)
    end
    -- the loot master shows his own popup when he awards
    local link = p[6] or (inc and inc.link)
    if winner and link and sender ~= ns.PlayerName() then
        ns.Fire("RGF_WINNER", { name = ns.Resolve(winner), link = link, cost = tonumber(p[4]) or (inc and inc.price) or 0,
            spec = p[5] == "OS" and "OS" or "MS" })
    end
end)

function ns.SendBid(inc, spec)
    if not inc then return end
    local msg = table.concat({ "B", inc.id, spec }, SEP)
    if inc.owner == ns.PlayerName() then
        ns.RecordBid(ns.PlayerName(), spec)
    elseif not ns.SendComm(msg, "WHISPER", inc.ownerRaw or inc.owner) then
        -- addon messages can be blocked, a normal whisper always works
        local word = spec == "MS" and "ms" or (spec == "OS" and "os" or "pass")
        ns.SendChat(word .. (inc.n and (" " .. inc.n) or ""), "WHISPER", inc.ownerRaw or inc.owner)
    end
    local first = inc.myBid == nil
    inc.myBid = spec
    if first and spec ~= "PASS" then
        ns.Print("you bid " .. (spec == "MS" and "main spec" or "off spec") .. " on " .. (inc.link or "the item") .. ". To change it while bidding is open, type /rgf rebid")
    end
    ns.Fire("RGF_INCOMING_AUCTION", inc)
end

------------------------------------------------------------------------
-- Test mode: the loot master window with fake bids, works without a group
------------------------------------------------------------------------
local function testItem()
    if GetInventoryItemLink then
        for _, slot in ipairs({ 16, 5, 1, 7, 3, 10, 15, 6, 8, 9, 2, 11, 13, 17, 18 }) do
            local link = GetInventoryItemLink("player", slot)
            if link then return link end
        end
    end
    return "|cffa335ee|Hitem:19019::::::::60:::::|h[Test Sword]|h|r"
end

-- The simulated raid answers by itself, one after another, and a few never answer.
function ns.SimulateBids(a)
    local me = ns.PlayerName()
    local others = {}
    for _, name in ipairs(a.expected or {}) do
        if name ~= me then table.insert(others, name) end
    end
    local answers = { "MS", "OS", "MS", false, "PASS", "MS", "OS", false, "MS" }
    for i, name in ipairs(others) do
        local answer = answers[(i - 1) % #answers + 1]
        if answer then
            ns.After(1 + i * 1.5, function()
                if a.open then ns.RecordBid(name, answer, a) end
            end)
        end
    end
    if #others == 0 then
        ns.Print(ns.TEST_TAG .. "the guild roster is still empty, so only your own bid shows up")
    end
end

-- older name, opens bidding with whatever mode is set
function ns.StartTestAuction(link, tier)
    return ns.StartAuction(link or testItem(), tier or "normal")
end

-- In test mode the fake bidders roll by themselves
ns.On("RGF_TEST_ROLLS", function()
    local me = ns.PlayerName()
    for _, a in ipairs(ns.auctions) do
        if a.test and a.rollsOpen then
            for _, b in ipairs(ns.TiedForFirst(a)) do
                if b.name ~= me and b.wantsRoll and not b.roll then
                    b.roll = math.random(1, 100)
                end
            end
            if #ns.TiedForFirst(a) == 0 then a.rollsOpen = false end
        end
    end
    ns.Fire("RGF_AUCTION_CHANGED")
end)
