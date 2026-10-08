-- Points: reading and writing EP and GP in guild officer notes.
--
-- Officer note formats
--   "1250,300"        a main with 1250 EP and 300 GP (GP includes the base 100)
--   "@Thrall"         an alt that shares the points of the main Thrall
--   anything after the numbers is kept, for example "1250,300 tank"

local _, ns = ...
ns = ns or _G.RedGuildForever

ns.members = {}   -- full name -> { index, rank, class, online, ep, gp, main, rest, hasPoints }
ns.lookup = {}    -- lower case full name -> full name
ns.synced = { points = {}, alts = {}, from = nil, at = nil } -- for players who cannot read officer notes
ns.pending = {}   -- full name -> { note, at } writes we sent but the roster may not show yet
ns.queue = {}     -- officer note writes waiting to be sent
ns.history = {}   -- actions this session, used by undo

------------------------------------------------------------------------
-- Notes
------------------------------------------------------------------------
function ns.ParseNote(note)
    note = note or ""
    -- the main's name may contain a space, for example "@Cel Dru"
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

function ns.FormatNote(ep, gp, rest)
    local note = string.format("%d,%d", ep, gp)
    if rest and rest ~= "" then
        if not rest:match("^%s") then rest = " " .. rest end
        note = note .. rest
    end
    return note:sub(1, 31)
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
    local canView = ns.CanViewNotes()
    local members, lookup = {}, {}
    local now = GetTime and GetTime() or 0
    local count = GetNumGuildMembers() or 0
    for i = 1, count do
        local name, _, rankIndex, _, _, _, _, officerNote, online, _, classFile = GetGuildRosterInfo(i)
        if name then
            local full = ns.FullName(name)
            local p = ns.pending[full]
            if p then
                if officerNote == p.note or now - p.at > 15 then
                    ns.pending[full] = nil
                else
                    officerNote = p.note -- our write has not shown up yet
                end
            end
            local info = canView and ns.ParseNote(officerNote) or {}
            members[full] = {
                index = i,
                rank = rankIndex,
                class = classFile,
                online = online,
                ep = info.ep,
                gp = info.gp,
                main = info.main,
                rest = info.rest,
                hasPoints = info.ep ~= nil,
            }
            lookup[full:lower()] = full
        end
    end
    -- alts must point to a main in the guild, and only one level deep
    for _, m in pairs(members) do
        if m.main then
            local target = members[lookup[m.main:lower()] or m.main]
            if target and not target.main then
                m.main = lookup[m.main:lower()] or m.main
            else
                m.main = nil
            end
        end
    end
    ns.members, ns.lookup = members, lookup
    ns.Fire("RGF_POINTS_CHANGED")
end

function ns.IsOfficer(full)
    local m = ns.members[ns.Resolve(full) or ""]
    return m and m.rank ~= nil and m.rank <= ns.Setting("officerRank")
end

-- The main whose points a character uses.
function ns.MainOf(name)
    local full = ns.Resolve(name)
    if not full then return nil end
    if ns.CanViewNotes() then
        local m = ns.members[full]
        if m and m.main then return m.main end
        return full
    end
    return ns.synced.alts[full] or full
end

function ns.AltsOf(main)
    local list = {}
    for full, m in pairs(ns.members) do
        if m.main == main then table.insert(list, full) end
    end
    for alt, m in pairs(ns.synced.alts) do
        if m == main and not ns.members[alt] then table.insert(list, alt) end
    end
    table.sort(list)
    return list
end

-- Returns ep, gp, priority for any character (alts use their main).
function ns.GetPoints(name)
    local main = ns.MainOf(name)
    local base = ns.Setting("baseGP")
    local ep, gp = 0, base
    if main then
        if ns.CanViewNotes() then
            local m = ns.members[main]
            if m and m.ep then ep, gp = m.ep, m.gp end
        else
            local s = ns.synced.points[main]
            if s then ep, gp = s.ep, s.gp end
        end
    end
    if gp < base then gp = base end
    return ep, gp, ep / gp, main
end

function ns.IsNewMember(name)
    local ep = ns.GetPoints(name)
    return ep < ns.Setting("minEP")
end

-- Sorted list of mains for the standings window.
function ns.Standings(showAll)
    local list = {}
    local base = ns.Setting("baseGP")
    if ns.CanViewNotes() then
        for full, m in pairs(ns.members) do
            if not m.main and (m.hasPoints or showAll) then
                local ep, gp, pr = ns.GetPoints(full)
                table.insert(list, { name = full, ep = ep, gp = gp, pr = pr, class = m.class, alts = #ns.AltsOf(full) })
            end
        end
    else
        for full, s in pairs(ns.synced.points) do
            local gp = math.max(s.gp, base)
            local m = ns.members[full]
            table.insert(list, { name = full, ep = s.ep, gp = gp, pr = s.ep / gp, class = m and m.class, alts = #ns.AltsOf(full) })
        end
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
local function findIndex(full)
    local count = GetNumGuildMembers() or 0
    for i = 1, count do
        local name = GetGuildRosterInfo(i)
        if name and ns.FullName(name) == full then return i end
    end
end

local processing = false
local function processQueue()
    local job = table.remove(ns.queue, 1)
    if not job then
        processing = false
        ns.RequestRoster()
        return
    end
    local index = findIndex(job.name)
    if index then
        local ok, err = pcall(GuildRosterSetOfficerNote, index, job.note)
        if not ok then ns.Print("could not write note for " .. ns.ShortName(job.name) .. " " .. tostring(err)) end
    else
        ns.Print(ns.ShortName(job.name) .. " is not in the guild, change skipped")
    end
    ns.After(0.15, processQueue)
end

function ns.WriteNote(full, note)
    ns.pending[full] = { note = note, at = GetTime and GetTime() or 0 }
    table.insert(ns.queue, { name = full, note = note })
    if not processing then
        processing = true
        ns.After(0, processQueue)
    end
end

-- Set the points of a main directly and update the local copy right away.
local function setPoints(main, ep, gp)
    local m = ns.members[main]
    if not m then return false end
    gp = math.max(gp, ns.Setting("baseGP"))
    m.ep, m.gp, m.hasPoints = ep, gp, true
    ns.WriteNote(main, ns.FormatNote(ep, gp, m.rest))
    return true
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
        local log = RedGuildForeverDB and RedGuildForeverDB.log
        if log then
            table.insert(log, { time = action.time, label = action.label, count = #action.changes, by = ns.PlayerName() })
            while #log > 500 do table.remove(log, 1) end
        end
        ns.Fire("RGF_POINTS_CHANGED")
        ns.Fire("RGF_LOCAL_CHANGE")
    end
    return action
end

-- Add EP and GP to a character. Alts change their main. Returns the main.
function ns.Adjust(name, dEP, dGP)
    if not ns.CanEditNotes() then
        ns.Print("you need permission to edit officer notes")
        return nil
    end
    local main = ns.MainOf(name)
    if not main or not ns.members[main] then
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

-- Give EP to a list of characters, each player only once even with alts.
function ns.AwardEP(names, amount, label)
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
    if not ns.CanEditNotes() then
        ns.Print("you need permission to edit officer notes")
        return 0
    end
    local factor = 1 - ns.Setting("decayPercent") / 100
    local count = 0
    ns.BeginAction("Weekly decay " .. ns.Setting("decayPercent") .. "%")
    for full, m in pairs(ns.members) do
        if m.hasPoints and not m.main then
            local ep, gp = ns.GetPoints(full)
            local newEP = ns.Round(ep * factor)
            local newGP = math.max(ns.Round(gp * factor), ns.Setting("baseGP"))
            if newEP ~= ep or newGP ~= gp then
                ns.Adjust(full, newEP - ep, newGP - gp)
                count = count + 1
            end
        end
    end
    ns.EndAction()
    return count
end

function ns.Undo()
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
    if not ns.CanEditNotes() then
        ns.Print("you need permission to edit officer notes")
        return false
    end
    local a, m = ns.Resolve(alt), ns.Resolve(main)
    if not ns.members[a] then ns.Print(alt .. " is not in the guild") return false end
    if not ns.members[m] then ns.Print(main .. " is not in the guild") return false end
    if a == m then ns.Print("a character cannot be its own alt") return false end
    if ns.members[m].main then
        ns.Print(ns.ShortName(m) .. " is an alt of " .. ns.ShortName(ns.members[m].main) .. ", link to the main instead")
        return false
    end
    if #ns.AltsOf(a) > 0 then
        ns.Print(ns.ShortName(a) .. " has alts of its own, unlink them first")
        return false
    end
    local am = ns.members[a]
    if am.hasPoints and (am.ep ~= 0 or am.gp ~= ns.Setting("baseGP")) then
        ns.Print(ns.ShortName(a) .. " had " .. am.ep .. " EP and " .. am.gp .. " GP, these are dropped. Use /rgf ep or /rgf gp on the main if needed")
    end
    am.main, am.ep, am.gp, am.hasPoints = m, nil, nil, false
    ns.WriteNote(a, ("@" .. ns.ShortName(m)):sub(1, 31))
    ns.Fire("RGF_POINTS_CHANGED")
    ns.Fire("RGF_LOCAL_CHANGE")
    return true
end

function ns.UnsetAlt(alt)
    if not ns.CanEditNotes() then
        ns.Print("you need permission to edit officer notes")
        return false
    end
    local a = ns.Resolve(alt)
    local m = ns.members[a]
    if not m or not m.main then ns.Print(alt .. " is not linked as an alt") return false end
    m.main = nil
    setPoints(a, 0, ns.Setting("baseGP"))
    ns.Fire("RGF_POINTS_CHANGED")
    ns.Fire("RGF_LOCAL_CHANGE")
    return true
end

------------------------------------------------------------------------
-- Bench
------------------------------------------------------------------------
function ns.Bench()
    return RedGuildForeverDB.bench
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
    wipe(RedGuildForeverDB.bench)
    ns.Fire("RGF_BENCH_CHANGED")
end

function ns.RaidMembers()
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
            local name, realm = UnitName("party" .. i)
            if name then
                table.insert(list, ns.Resolve(realm and realm ~= "" and (name .. "-" .. realm) or name))
            end
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
    ns.RequestRoster()
    -- officer notes only refresh when someone asks, so ask every minute
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(60, function() ns.RequestRoster() end)
    end
end)
