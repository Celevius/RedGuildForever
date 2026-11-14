-- SPDX-License-Identifier: MIT, see LICENSE
-- Raid night and loot lists.
--   Start raid  gives the on time EP to the raid and the bench and starts the loot list
--   End raid    gives the raid EP, and asks about players who left early
-- Every item given out is a "loot" event, so the loot of a raid and of a
-- player comes straight from the history and is shared with Sync.

local _, ns = ...
ns = ns or _G.RedGuildForever

local function names(list)
    local short = {}
    for _, n in ipairs(list) do table.insert(short, ns.ShortName(n)) end
    return table.concat(short, ", ")
end

-- Raid EP or on time EP for the raid and the bench. kind is "raid" or
-- "ontime", each player gets it once per raid night.
function ns.AwardGroup(amount, label, kind, list)
    if not ns.CanEdit() then
        ns.Print("only the guild leader and editors can do that")
        return 0
    end
    local benched = #ns.Bench()
    local count, skipped, already = ns.AwardEP(list or ns.RaidAndBench(), amount, label, kind)
    if count > 0 then
        local msg = string.format("%d players got %d EP for %s", count, amount, label:lower())
        if benched > 0 and not list then msg = msg .. ", the bench included" end
        ns.Announce(msg .. ".")
    end
    if #already > 0 then
        ns.Print("already got " .. label:lower() .. " EP tonight, from this or another raid: " .. names(already))
    end
    if #skipped > 0 then
        ns.Print("not in the guild, no EP " .. names(skipped))
    end
    return count
end

------------------------------------------------------------------------
-- The raid of this loot master. Saved, so a reload keeps it.
------------------------------------------------------------------------
local function store()
    local db = RedGuildForeverDB
    if ns.IsTest() then
        db.test = db.test or {}
        return db.test
    end
    return db
end

-- The running raid, or nil
function ns.Session()
    local s = store().session
    if s and not s.ended and s.guild == ns.GuildKey() then return s end
    return nil
end

-- The running raid or the last one
function ns.LastSession()
    local s = store().session
    if s and s.guild == ns.GuildKey() then return s end
    return nil
end

local function noteRaid(s)
    for _, n in ipairs(ns.RaidMembers()) do s.seen[n] = true end
end

function ns.StartRaid()
    if not ns.CanChange() then return false end
    if ns.Session() then
        ns.Print("the raid is already running, End raid finishes it")
        return false
    end
    local s = { start = ns.Now(), seen = {}, guild = ns.GuildKey(), by = ns.PlayerName() }
    noteRaid(s)
    store().session = s
    ns.AwardGroup(ns.Setting("onTimeEP"), "Being on time", "ontime")
    ns.Fire("RGF_RAID_CHANGED")
    return true
end

-- Gives the raid EP and finishes the raid. Players who were in the raid but
-- left before the end are offered the raid EP too.
function ns.EndRaid()
    if not ns.CanChange() then return false end
    local s = ns.Session()
    if not s then
        ns.Print("no raid is running, Start raid begins one")
        return false
    end
    noteRaid(s)
    ns.AwardGroup(ns.Setting("raidEP"), "Raid night", "raid")
    local present = {}
    for _, n in ipairs(ns.RaidAndBench()) do present[n] = true end
    local leavers = {}
    for n in pairs(s.seen) do
        if not present[n] and ns.members[ns.MainOf(n)] and not ns.GotTonight(ns.MainOf(n), "raid") then
            table.insert(leavers, n)
        end
    end
    table.sort(leavers)
    s.ended = ns.Now()
    s.leavers = leavers
    local loot = ns.RaidLoot(s)
    ns.Print(string.format("raid finished, %d players, %d items given out. The loot list is in the Raid tab", ns.SeenCount(s), #loot))
    if #leavers > 0 and StaticPopup_Show then
        StaticPopup_Show("REDGUILDFOREVER_LEAVERS", #leavers, names(leavers))
    end
    if ns.AutoBackup then ns.AutoBackup("raid") end
    ns.RemindDecay()
    ns.Fire("RGF_RAID_CHANGED")
    return true, leavers
end

-- Raid EP for the players who left early, from the question after End raid
function ns.AwardLeavers()
    local s = ns.LastSession()
    if not (s and s.leavers and #s.leavers > 0) then return 0 end
    local count = ns.AwardGroup(ns.Setting("raidEP"), "Raid night", "raid", s.leavers)
    s.leavers = {}
    return count
end

function ns.SeenCount(s)
    local n = 0
    for _ in pairs(s and s.seen or {}) do n = n + 1 end
    return n
end

-- a minute after login, when sync had time to bring the newest decay
ns.On("RGF_READY", function()
    ns.After(60, function() ns.RemindDecay() end)
end)

ns.On("GROUP_ROSTER_UPDATE", function()
    local s = ns.Session()
    if s then noteRaid(s) end
end)

------------------------------------------------------------------------
-- Loot lists
------------------------------------------------------------------------
-- The item link in the label of a loot event, and its plain name
local function itemOf(ev)
    local link = ns.LinkIn(ev.r)
    local name = link and link:match("%[(.-)%]")
    if not link and ev.item then
        -- only the number is known, ask the game for the item
        local known, knownName = ns.ItemById(ev.item)
        link, name = known, knownName
    end
    name = name or (ev.item and ("item " .. ev.item)) or "?"
    return link or name, name
end
ns.ItemOfEvent = itemOf

local function lootEntry(ev, c, st)
    local link, name = itemOf(ev)
    return { time = ev.t, name = c.n, main = ns.MainOf(c.n), gp = c.gp or 0, link = link, itemName = name,
        item = ev.item, by = ev.by, id = ev.id, label = link }
end

local function eachLoot(fn)
    local st = ns.State()
    for i = #st.events, 1, -1 do
        local ev = st.events[i]
        if ev.k == "P" and ev.kind == "loot" and not st.undone[ev.id] then
            for _, c in ipairs(ev.ch or {}) do
                if fn(ev, c, st) == false then return end
            end
        end
    end
end

-- Items given out in a raid, newest first: by this loot master, or won by
-- somebody who was in the raid.
function ns.RaidLoot(s)
    local list = {}
    if not s then return list end
    local last = (s.ended or ns.Now()) + 3600
    eachLoot(function(ev, c, st)
        if ev.t < s.start then return false end
        if ev.t <= last and (ev.by == s.by or s.seen[c.n]) then
            table.insert(list, lootEntry(ev, c, st))
        end
    end)
    return list
end

-- Items of a player and his alts, newest first
function ns.LootOf(name, limit)
    local main = ns.MainOf(name)
    local list = {}
    eachLoot(function(ev, c, st)
        if ns.MainOf(c.n) == main then
            table.insert(list, lootEntry(ev, c, st))
            if limit and #list >= limit then return false end
        end
    end)
    return list
end

------------------------------------------------------------------------
-- Loot history: every item, who bid on it and who got it
------------------------------------------------------------------------
-- Newest first. Items given out before version 2.4 have no bids recorded.
function ns.LootHistory()
    local st = ns.State()
    local list, covered = {}, {}
    for _, ev in ipairs(st.events) do
        if ev.k == "L" then
            if ev.ref then covered[ev.ref] = true end
            local link, name = itemOf(ev)
            table.insert(list, { id = ev.id, time = ev.t, link = link, itemName = name, item = ev.item,
                winner = ev.winner, cost = ev.cost or 0, spec = ev.spec, by = ev.by, bids = ev.bids or {},
                ref = ev.ref, undone = ev.ref ~= nil and st.undone[ev.ref] ~= nil })
        end
    end
    for _, ev in ipairs(st.events) do
        if ev.k == "P" and ev.kind == "loot" and not covered[ev.id] then
            local link, name = itemOf(ev)
            for _, c in ipairs(ev.ch or {}) do
                table.insert(list, { id = ev.id, time = ev.t, link = link, itemName = name, item = ev.item,
                    winner = c.n, cost = c.gp or 0, by = ev.by, bids = {}, old = true, ref = ev.id,
                    undone = st.undone[ev.id] ~= nil })
            end
        end
    end
    table.sort(list, function(a, b)
        if a.time ~= b.time then return a.time > b.time end
        return a.id > b.id
    end)
    return list
end

-- filter = { text = "ring", days = 7, mine = true }, every part is optional.
-- The text is looked for in the item, the winner, the loot master and the bidders.
function ns.FilterLoot(list, filter)
    filter = filter or {}
    local textValue = (filter.text or ""):lower()
    local since = filter.days and (ns.Now() - filter.days * 86400) or nil
    local me = filter.mine and ns.MainOf(ns.PlayerName()) or nil
    local out = {}
    local function has(name)
        return name and ns.ShortName(name):lower():find(textValue, 1, true) ~= nil
    end
    for _, l in ipairs(list) do
        local ok = not since or l.time >= since
        if ok and me then
            ok = l.winner ~= nil and ns.MainOf(l.winner) == me
            for _, b in ipairs(l.bids) do
                if b.s ~= "PASS" and ns.MainOf(b.n) == me then ok = true end
            end
        end
        if ok and textValue ~= "" then
            ok = l.itemName:lower():find(textValue, 1, true) ~= nil or has(l.winner) or has(l.by)
            for _, b in ipairs(l.bids) do
                if has(b.n) then ok = true end
            end
        end
        if ok then table.insert(out, l) end
    end
    return out
end

-- EP, GP and priority of the players right before an item was given out,
-- for the loot history: { [main] = { ep, gp } } and a function for any character.
function ns.PointsBefore(l)
    local st = ns.StateBefore(l.ref or l.id)
    local base = ns.Setting("baseGP")
    return function(name)
        local e = st.players[name]
        if e and e.main then e = st.players[e.main] end
        local ep, gp = e and e.ep or 0, e and e.gp or base
        return ep, gp, ep / math.max(gp, 1)
    end
end

-- "2 main, 1 off, 3 pass" for a list of bids
function ns.BidCounts(bids)
    local ms, os, pass = 0, 0, 0
    for _, b in ipairs(bids or {}) do
        if b.s == "MS" then ms = ms + 1 elseif b.s == "OS" then os = os + 1 else pass = pass + 1 end
    end
    return ms, os, pass
end

-- The loot of a raid as plain text, for Discord
function ns.RaidLootText(s)
    s = s or ns.LastSession()
    if not s then return "No raid yet." end
    local loot = ns.RaidLoot(s)
    local lines = { string.format("Raid on %s, %d players, %d items", date("%d.%m.%Y", s.start), ns.SeenCount(s), #loot) }
    for i = #loot, 1, -1 do
        local l = loot[i]
        table.insert(lines, string.format("%s  %s  %d GP", l.itemName, ns.ShortName(l.name), l.gp))
    end
    return table.concat(lines, "\n")
end
