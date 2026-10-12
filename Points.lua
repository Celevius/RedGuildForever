-- Points: EP and GP stored in the addon's own save file, one data set per guild.
--
-- RedGuildForeverDB.guilds["Guild Name-Realm"] = {
--     started = true,                -- data exists or an officer started fresh
--     players = {
--         ["Cel Dru-Forever"] = { ep = 1250, gp = 300, t = 1760000000, by = "Cel Dru-Forever" },
--         ["Cel Rog-Forever"] = { main = "Cel Dru-Forever", t = 1760000000, by = "..." },
--     },
-- }
--
-- t is the server time of the last change. Sync keeps the newest entry per
-- player, so officers can change points on different computers.

local _, ns = ...
ns = ns or _G.RedGuildForever

ns.members = {}   -- guild roster, full name -> { index, rank, class, online }
ns.lookup = {}    -- lower case full name -> full name
ns.history = {}   -- actions this session, used by undo

------------------------------------------------------------------------
-- Old officer note format, only used to import data from version 1.3 and older
--   "1250,300"   1250 EP and 300 GP
--   "@Cel Dru"   an alt of Cel Dru
------------------------------------------------------------------------
function ns.ParseNote(note)
    note = note or ""
    local main = note:match("^@(.+)$")
    if main and ns.CleanName(main) then
        return { main = ns.FullName(main) }
    end
    local ep, gp, rest = note:match("^(%-?%d+),(%d+)(.*)$")
    if ep then
        return { ep = tonumber(ep), gp = tonumber(gp), rest = rest or "" }
    end
    return { rest = note }
end

------------------------------------------------------------------------
-- The data set of the current guild
------------------------------------------------------------------------
local tempData = { players = {} } -- used while the game does not know the guild yet

function ns.Now()
    if GetServerTime then
        local ok, t = pcall(GetServerTime)
        if ok and type(t) == "number" then return t end
    end
    return time and time() or 0
end

function ns.GuildKey()
    if not (IsInGuild and IsInGuild()) or not GetGuildInfo then return nil end
    local name = GetGuildInfo("player")
    if not name or name == "" then return nil end
    return name .. "-" .. ns.MyRealm()
end

-- copy a data set, used to start the test data from the real data
local function copyData(src)
    local players, rules = {}, {}
    for name, e in pairs(src.players or {}) do
        players[name] = { ep = e.ep, gp = e.gp, main = e.main, t = e.t, by = e.by }
    end
    for key, e in pairs(src.rules or {}) do
        rules[key] = { v = e.v, t = e.t, by = e.by }
    end
    return { players = players, rules = rules, started = true }
end

function ns.RealData()
    local key = ns.GuildKey()
    if not key or not RedGuildForeverDB then return tempData end
    RedGuildForeverDB.guilds = RedGuildForeverDB.guilds or {}
    local data = RedGuildForeverDB.guilds[key]
    if not data then
        data = { players = {} }
        RedGuildForeverDB.guilds[key] = data
    end
    data.players = data.players or {}
    data.rules = data.rules or {}
    return data
end

-- In test mode everything works on a copy, the real data is never touched.
function ns.Data()
    if ns.IsTest() then
        local db = RedGuildForeverDB
        if not db.test or not db.test.data then ns.ResetTestData() end
        return db.test.data
    end
    return ns.RealData()
end

function ns.ResetTestData()
    local db = RedGuildForeverDB
    db.test = db.test or {}
    db.test.data = copyData(ns.RealData())
    db.test.bench = {}
    db.test.log = {}
    ns.history = {}
    ns.PickTestRaid()
    ns.Fire("RGF_POINTS_CHANGED")
    ns.Fire("RGF_BENCH_CHANGED")
end

-- The simulated raid: you and up to 9 guild members.
function ns.PickTestRaid()
    local db = RedGuildForeverDB
    db.test = db.test or {}
    local me = ns.PlayerName()
    local pool = {}
    for full in pairs(ns.members) do
        if full ~= me then table.insert(pool, full) end
    end
    table.sort(pool)
    for i = #pool, 2, -1 do
        local j = math.random(i)
        pool[i], pool[j] = pool[j], pool[i]
    end
    local raid = { me }
    for i = 1, math.min(9, #pool) do table.insert(raid, pool[i]) end
    db.test.raid = raid
    return raid
end

function ns.SetTestMode(on)
    local db = RedGuildForeverDB
    db.settings = db.settings or {}
    on = on and true or false
    if ns.IsTest() == on then return end
    if ns.auction and not ns.auction.test then
        ns.Print("finish the bidding for " .. ns.auction.link .. " before switching test mode")
        return false
    end
    if ns.auction then ns.CancelAuction() end
    db.settings.testMode = on
    ns.history = {}
    if on then
        if not db.test or not db.test.data then ns.ResetTestData() end
        if not db.test.raid or #db.test.raid <= 1 then ns.PickTestRaid() end
        ns.Print(ns.TEST_TAG .. "test mode is on. You work on a copy of the data with a simulated raid, nothing is sent and your real points stay as they are")
    else
        ns.Print("test mode is off, you see the real data again")
    end
    ns.RebuildFromRoster()
    ns.Fire("RGF_TEST_MODE")
    ns.Fire("RGF_POINTS_CHANGED")
    ns.Fire("RGF_BENCH_CHANGED")
    ns.Fire("RGF_AUCTION_CHANGED")
end

function ns.Players()
    return ns.Data().players
end

-- true when there is data to work with, or an officer chose to start fresh
function ns.HasData()
    local data = ns.Data()
    return data.started or next(data.players) ~= nil
end

function ns.StartFresh()
    if not ns.CanEdit() then return false end
    ns.Data().started = true
    ns.Fire("RGF_POINTS_CHANGED")
    return true
end

------------------------------------------------------------------------
-- Who may change data: the guild leader and the officer ranks.
-- The guild leader can set the officer ranks in the guild information,
-- for example "EPGP officers 2" lets ranks 0, 1 and 2 edit (0 is the leader).
------------------------------------------------------------------------
function ns.OfficerRank()
    if GetGuildInfoText then
        local ok, info = pcall(GetGuildInfoText)
        if ok and type(info) == "string" then
            local rank = info:lower():match("epgp%s+officers?%s*[=:]?%s*(%d+)")
            if rank then return tonumber(rank) end
        end
    end
    return ns.Setting("officerRank")
end

function ns.MyRank()
    if not GetGuildInfo then return nil end
    local _, _, rankIndex = GetGuildInfo("player")
    return rankIndex
end

function ns.CanEdit()
    if ns.IsTest() then return true end -- in test mode everyone can try the officer tools
    if not (IsInGuild and IsInGuild()) then return false end
    local rank = ns.MyRank()
    return rank ~= nil and rank <= ns.OfficerRank()
end
ns.CanEditNotes = ns.CanEdit -- older name, used in a few places

function ns.IsOfficer(full)
    local m = ns.members[ns.Resolve(full) or ""]
    return m and m.rank ~= nil and m.rank <= ns.OfficerRank()
end

-- Every change goes through here, it explains why a change is not possible.
function ns.CanChange()
    if not ns.CanEdit() then
        ns.Print("only the guild leader and officers can change points")
        return false
    end
    if not ns.HasData() then
        ns.Print("no EPGP data loaded yet. Click Sync to get it from the other officers, or Start fresh if your guild is new")
        ns.Fire("RGF_NEEDS_DATA")
        return false
    end
    return true
end

------------------------------------------------------------------------
-- Roster
------------------------------------------------------------------------
-- Find a guild member from whatever we got: "Cel Dru", "cel dru",
-- "Cel Dru-Forever", or only "Cel" when exactly one member is called Cel.
-- loose also allows the start of a name ("Ang" for "Anglicus Boniface"),
-- which is only used for names typed into commands.
-- Returns the full name, or nil and a list of names when it is not clear.
function ns.FindMember(name, loose)
    local clean = ns.CleanName(name)
    if not clean then return nil end
    local full = ns.FullName(clean)
    local hit = ns.lookup[full:lower()]
    if hit then return hit end

    -- "Cel-Dru" or "Cel-Dru-Forever", where a dash stands for the space
    -- between first and last name
    local base, tail = ns.SplitRealm(clean)
    if tail then
        local realm = ns.IsKnownRealm(tail) and tail or nil
        local nameParts = realm and base or clean
        local candidate = nameParts:gsub("%s*%-%s*", " ")
        if realm then candidate = candidate .. "-" .. realm end
        local asLastName = ns.FullName(candidate)
        hit = asLastName and ns.lookup[asLastName:lower()]
        if hit then return hit end
    end

    local wanted = ns.SplitRealm(clean):lower()
    local hasSpace = wanted:find(" ", 1, true) ~= nil
    local exact, first, prefix = {}, {}, {}
    for _, member in pairs(ns.lookup) do
        local short = ns.SplitRealm(member):lower()
        if short == wanted then
            table.insert(exact, member)
        elseif not hasSpace and short:match("^(%S+)") == wanted then
            table.insert(first, member)
        elseif loose and short:sub(1, #wanted) == wanted then
            table.insert(prefix, member)
        end
    end
    for _, list in ipairs({ exact, first, prefix }) do
        if #list == 1 then return list[1] end
        if #list > 1 then
            table.sort(list)
            return nil, list
        end
    end
    return nil
end

-- Like FindMember, but always returns a name, also for players outside the guild.
function ns.Resolve(name)
    if not name then return nil end
    local found = ns.FindMember(name)
    if found then return found end
    return ns.FullName(name)
end

function ns.RebuildFromRoster()
    if not (IsInGuild and IsInGuild()) then return end
    local members, lookup = {}, {}
    local count = GetNumGuildMembers() or 0
    for i = 1, count do
        local name, _, rankIndex, _, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name then
            local full = ns.FullName(name)
            members[full] = { index = i, rank = rankIndex, class = classFile, online = online }
            lookup[full:lower()] = full
        end
    end
    -- players in the data who left the guild can still be found by name
    for full in pairs(ns.Players()) do
        if not lookup[full:lower()] then lookup[full:lower()] = full end
    end
    ns.members, ns.lookup = members, lookup
    if ns.MigrateOldOverrides then ns.MigrateOldOverrides() end
    ns.Fire("RGF_POINTS_CHANGED")
end

------------------------------------------------------------------------
-- Changing guild rules
------------------------------------------------------------------------
-- Change several rules at once. values maps rule keys to typed values.
-- Returns the number of changed rules, or nil and a reason.
function ns.SetRules(values)
    if not ns.CanChange() then return nil, "only the guild leader and officers can change the rules" end
    local checked = {}
    for _, def in ipairs(ns.RULES) do
        local value = values[def.key]
        if value ~= nil then
            local n, err = ns.CheckRule(def.key, value)
            if not n then return nil, err end
            checked[def.key] = n
        end
    end
    local data = ns.Data()
    data.rules = data.rules or {}
    local now, me = ns.Now(), ns.PlayerName()
    local parts = {}
    for _, def in ipairs(ns.RULES) do
        local n = checked[def.key]
        if n ~= nil and n ~= ns.Rule(def.key) then
            table.insert(parts, string.format("%s %s to %s", def.label, ns.FormatNumber(ns.Rule(def.key)), ns.FormatNumber(n)))
            data.rules[def.key] = { v = n, t = now, by = me }
        end
    end
    if #parts == 0 then return 0 end
    local log = ns.Log()
    if log then
        table.insert(log, { time = time and time() or 0, label = "Settings changed, " .. table.concat(parts, ", "), count = #parts, by = me })
        while #log > 500 do table.remove(log, 1) end
    end
    ns.Fire("RGF_RULES_CHANGED")
    ns.Fire("RGF_POINTS_CHANGED")
    ns.Fire("RGF_LOCAL_CHANGE")
    return #parts
end

-- Set every rule back to the rule book. Fixed item prices stay.
function ns.ResetRules()
    local values = {}
    for _, def in ipairs(ns.RULES) do values[def.key] = def.default end
    return ns.SetRules(values)
end

------------------------------------------------------------------------
-- Reading points
------------------------------------------------------------------------
local function entry(full)
    return full and ns.Players()[full]
end

-- The main whose points a character uses.
function ns.MainOf(name)
    local full = ns.Resolve(name)
    if not full then return nil end
    local e = entry(full)
    if e and e.main then
        local m = entry(e.main)
        if not (m and m.main) then return e.main end -- only one level of alts
    end
    return full
end

function ns.AltsOf(main)
    local list = {}
    for full, e in pairs(ns.Players()) do
        if e.main == main then table.insert(list, full) end
    end
    table.sort(list)
    return list
end

-- Returns ep, gp, priority and the main for any character.
function ns.GetPoints(name)
    local main = ns.MainOf(name)
    local base = ns.Setting("baseGP")
    local ep, gp = 0, base
    local e = entry(main)
    if e and e.ep then ep, gp = e.ep, e.gp or base end
    if gp < base then gp = base end
    return ep, gp, ep / gp, main
end

function ns.IsNewMember(name)
    local ep = ns.GetPoints(name)
    return ep < ns.Setting("minEP")
end

function ns.HasPoints(full)
    local e = entry(full)
    return e ~= nil and e.ep ~= nil
end

-- Sorted list of mains for the standings window.
function ns.Standings(showAll)
    local list, seen = {}, {}
    local function add(full)
        if seen[full] then return end
        seen[full] = true
        local e = entry(full)
        if e and e.main then return end
        local ep, gp, pr = ns.GetPoints(full)
        local m = ns.members[full]
        table.insert(list, { name = full, ep = ep, gp = gp, pr = pr, class = m and m.class,
            alts = #ns.AltsOf(full), left = m == nil })
    end
    for full, e in pairs(ns.Players()) do
        if e.ep then add(full) end
    end
    if showAll then
        for full in pairs(ns.members) do add(full) end
    end
    table.sort(list, function(a, b)
        if a.pr ~= b.pr then return a.pr > b.pr end
        return a.name < b.name
    end)
    return list
end

------------------------------------------------------------------------
-- Writing
------------------------------------------------------------------------
local function stamp(e)
    e.t = ns.Now()
    e.by = ns.PlayerName()
    return e
end

local function setPoints(main, ep, gp)
    local players = ns.Players()
    local e = players[main] or {}
    e.ep, e.gp, e.main = ep, math.max(gp, ns.Setting("baseGP")), nil
    players[main] = stamp(e)
    ns.Data().started = true
end

-- Start an undoable action. Every change inside it is recorded.
function ns.BeginAction(label)
    local action = { label = label, changes = {}, time = time and time() or 0 }
    ns.currentAction = action
    return action
end

function ns.EndAction()
    local action = ns.currentAction
    ns.currentAction = nil
    if action and #action.changes > 0 then
        table.insert(ns.history, action)
        local log = ns.Log()
        if log then
            table.insert(log, { time = action.time, label = action.label, count = #action.changes, by = ns.PlayerName() })
            while #log > 500 do table.remove(log, 1) end
        end
        ns.Fire("RGF_POINTS_CHANGED")
        ns.Fire("RGF_LOCAL_CHANGE")
    end
    return action
end

-- Players we accept points for: guild members, or anyone already in the data.
local function known(full)
    return full and (ns.members[full] ~= nil or entry(full) ~= nil)
end

-- Add EP and GP to a character. Alts change their main. Returns the main.
function ns.Adjust(name, dEP, dGP)
    if not ns.CanChange() then return nil end
    local main = ns.MainOf(name)
    if not known(main) then
        ns.Print((name or "?") .. " is not in the guild")
        return nil
    end
    local ep, gp = ns.GetPoints(main)
    local newEP, newGP = ep + (dEP or 0), math.max(gp + (dGP or 0), ns.Setting("baseGP"))
    setPoints(main, newEP, newGP)
    if ns.currentAction then
        table.insert(ns.currentAction.changes, { name = main, ep = newEP - ep, gp = newGP - gp })
    end
    return main
end

-- Set exact EP and GP for a player (alts change their main). Undoable.
function ns.SetExactPoints(name, ep, gp, reason)
    if not ns.CanChange() then return nil end
    ep, gp = tonumber(ep), tonumber(gp)
    if not ep or not gp then return nil end
    ep = math.floor(ep)
    gp = math.max(math.floor(gp), ns.Setting("baseGP"))
    local main = ns.MainOf(name)
    if not known(main) then
        ns.Print((name or "?") .. " is not in the guild")
        return nil
    end
    local oldEP, oldGP = ns.GetPoints(main)
    if oldEP == ep and oldGP == gp then return main end
    local label = string.format("%s set to %d EP and %d GP", ns.ShortName(main), ep, gp)
    if reason and reason ~= "" then label = label .. ", " .. reason end
    ns.BeginAction(label)
    ns.Adjust(main, ep - oldEP, gp - oldGP)
    ns.EndAction()
    return main
end

-- Give EP to a list of characters, each player only once even with alts.
function ns.AwardEP(names, amount, label)
    if not ns.CanChange() then return 0, {} end
    local done, skipped = {}, {}
    ns.BeginAction(label .. " +" .. amount .. " EP")
    for _, name in ipairs(names) do
        local main = ns.MainOf(name)
        if main and ns.members[main] then
            if not done[main] then
                done[main] = true
                ns.Adjust(main, amount, 0)
            end
        else
            table.insert(skipped, name)
        end
    end
    ns.EndAction()
    local count = 0
    for _ in pairs(done) do count = count + 1 end
    return count, skipped
end

function ns.Decay()
    if not ns.CanChange() then return 0 end
    local factor = 1 - ns.Setting("decayPercent") / 100
    local count = 0
    local mains = {}
    for full, e in pairs(ns.Players()) do
        if e.ep and not e.main then table.insert(mains, full) end
    end
    table.sort(mains)
    ns.BeginAction("Weekly decay " .. ns.Setting("decayPercent") .. "%")
    for _, full in ipairs(mains) do
        local ep, gp = ns.GetPoints(full)
        local newEP = ns.Round(ep * factor)
        local newGP = math.max(ns.Round(gp * factor), ns.Setting("baseGP"))
        if newEP ~= ep or newGP ~= gp then
            ns.Adjust(full, newEP - ep, newGP - gp)
            count = count + 1
        end
    end
    ns.EndAction()
    return count
end

function ns.Undo()
    if not ns.CanChange() then return nil end
    local action = table.remove(ns.history)
    if not action then return nil end
    ns.BeginAction("Undo " .. action.label)
    for i = #action.changes, 1, -1 do
        local c = action.changes[i]
        ns.Adjust(c.name, -c.ep, -c.gp)
    end
    local undo = ns.EndAction()
    if undo and #undo.changes > 0 then
        table.remove(ns.history) -- the undo itself should not be undoable
    end
    return action
end

-- Link an alt to a main. Points stay with the main.
function ns.SetAlt(alt, main)
    if not ns.CanChange() then return false end
    local a, m = ns.Resolve(alt), ns.Resolve(main)
    if not ns.members[a] then ns.Print(alt .. " is not in the guild") return false end
    if not ns.members[m] then ns.Print(main .. " is not in the guild") return false end
    if a == m then ns.Print("a character cannot be its own alt") return false end
    local me = entry(m)
    if me and me.main then
        ns.Print(ns.ShortName(m) .. " is an alt of " .. ns.ShortName(me.main) .. ", link to the main instead")
        return false
    end
    if #ns.AltsOf(a) > 0 then
        ns.Print(ns.ShortName(a) .. " has alts of its own, unlink them first")
        return false
    end
    local ae = entry(a)
    if ae and ae.ep and (ae.ep ~= 0 or (ae.gp or 0) > ns.Setting("baseGP")) then
        ns.Print(ns.ShortName(a) .. " had " .. ae.ep .. " EP and " .. ae.gp .. " GP, these are dropped. Edit the main if needed")
    end
    ns.Players()[a] = stamp({ main = m })
    ns.Data().started = true
    ns.Fire("RGF_POINTS_CHANGED")
    ns.Fire("RGF_LOCAL_CHANGE")
    return true
end

function ns.UnsetAlt(alt)
    if not ns.CanChange() then return false end
    local a = ns.Resolve(alt)
    local e = entry(a)
    if not e or not e.main then ns.Print(alt .. " is not linked as an alt") return false end
    setPoints(a, 0, ns.Setting("baseGP"))
    ns.Fire("RGF_POINTS_CHANGED")
    ns.Fire("RGF_LOCAL_CHANGE")
    return true
end

-- One time import of points from officer notes (versions 1.3 and older).
function ns.ImportOfficerNotes()
    if not ns.CanEdit() then
        ns.Print("only the guild leader and officers can import")
        return 0
    end
    if not GetNumGuildMembers then return 0 end
    local players = ns.Players()
    local count = 0
    for i = 1, GetNumGuildMembers() or 0 do
        local name, _, _, _, _, _, _, officerNote = GetGuildRosterInfo(i)
        if name and officerNote and officerNote ~= "" then
            local full = ns.FullName(name)
            local info = ns.ParseNote(officerNote)
            if (info.ep or info.main) and not players[full] then
                if info.main then
                    players[full] = stamp({ main = info.main })
                else
                    players[full] = stamp({ ep = info.ep, gp = math.max(info.gp, ns.Setting("baseGP")) })
                end
                count = count + 1
            end
        end
    end
    if count > 0 then
        ns.Data().started = true
        ns.Fire("RGF_POINTS_CHANGED")
        ns.Fire("RGF_LOCAL_CHANGE")
    end
    return count
end

------------------------------------------------------------------------
-- Bench
------------------------------------------------------------------------
function ns.Bench()
    if ns.IsTest() then
        RedGuildForeverDB.test.bench = RedGuildForeverDB.test.bench or {}
        return RedGuildForeverDB.test.bench
    end
    return RedGuildForeverDB.bench
end

function ns.Log()
    if not RedGuildForeverDB then return nil end
    if ns.IsTest() then
        RedGuildForeverDB.test = RedGuildForeverDB.test or {}
        RedGuildForeverDB.test.log = RedGuildForeverDB.test.log or {}
        return RedGuildForeverDB.test.log
    end
    return RedGuildForeverDB.log
end

function ns.BenchAdd(name)
    local full = ns.Resolve(name)
    if not full then return false end
    for _, n in ipairs(ns.Bench()) do if n == full then return false end end
    table.insert(ns.Bench(), full)
    ns.Fire("RGF_BENCH_CHANGED")
    return true, full
end

function ns.BenchRemove(name)
    local full = ns.Resolve(name)
    for i, n in ipairs(ns.Bench()) do
        if n == full then
            table.remove(ns.Bench(), i)
            ns.Fire("RGF_BENCH_CHANGED")
            return true, full
        end
    end
    return false
end

function ns.BenchClear()
    wipe(ns.Bench())
    ns.Fire("RGF_BENCH_CHANGED")
end

function ns.RaidMembers()
    if ns.IsTest() then
        local raid = RedGuildForeverDB.test and RedGuildForeverDB.test.raid
        if not raid or #raid == 0 then raid = ns.PickTestRaid() end
        local copy = {}
        for i, n in ipairs(raid) do copy[i] = n end
        return copy
    end
    local list = {}
    local count = GetNumGroupMembers and GetNumGroupMembers() or 0
    if IsInRaid and IsInRaid() then
        for i = 1, count do
            local name = GetRaidRosterInfo(i)
            if name then table.insert(list, ns.Resolve(name)) end
        end
    else
        table.insert(list, ns.PlayerName())
        for i = 1, count - 1 do
            local full = ns.UnitFullName("party" .. i)
            if full then table.insert(list, full) end
        end
    end
    return list
end

-- Raid plus bench, used for raid EP and the on time bonus.
function ns.RaidAndBench()
    local list, seen = {}, {}
    for _, n in ipairs(ns.RaidMembers()) do
        if not seen[n] then seen[n] = true table.insert(list, n) end
    end
    for _, n in ipairs(ns.Bench()) do
        if not seen[n] then seen[n] = true table.insert(list, n) end
    end
    return list
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local rebuildQueued = false
ns.On("GUILD_ROSTER_UPDATE", function()
    if rebuildQueued then return end
    rebuildQueued = true
    ns.After(0.5, function()
        rebuildQueued = false
        ns.RebuildFromRoster()
    end)
end)

ns.On("PLAYER_GUILD_UPDATE", function() ns.RequestRoster() end)

ns.On("RGF_READY", function()
    RedGuildForeverDB.guilds = RedGuildForeverDB.guilds or {}
    ns.RequestRoster()
    -- the roster only refreshes when someone asks, so ask every minute
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(60, function() ns.RequestRoster() end)
    end
end)
