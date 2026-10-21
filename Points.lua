-- Points: EP and GP stored in the addon's own save file, one data set per guild.
--
-- RedGuildForeverDB.guilds["Guild Name-Realm"] = {
--     started = true,                -- data exists or an editor started fresh
--     players = {                    -- the starting points, from version 1.7 and older
--         ["Cel Dru-Forever"] = { ep = 1250, gp = 300, t = 1760000000, by = "Cel Dru-Forever" },
--         ["Cel Rog-Forever"] = { main = "Cel Dru-Forever", t = 1760000000, by = "..." },
--     },
--     events = {                     -- every change since then, see below
--         ["68f1a2b30a1b2c"] = { id = "68f1a2b30a1b2c", k = "P", t = 1760000000, by = "Cel Dru-Forever",
--             ch = { { n = "Lisa Brightwater-Forever", ep = 0, gp = 150 } }, item = 19019, r = "label" },
--     },
--     rules = { tier_boss = { v = 150, t = 1760000000, by = "..." } },
--     editors = { ["Anna Frost-Forever"] = { on = true, t = 1760000000, by = "the guild leader" } },
--     bench = { ["Anna Frost-Forever"] = { on = true, t = 1760000000 } },
-- }
--
-- Points are never stored as a total. Every change is an event, and the
-- points are the starting points plus all events in the order they happened.
-- Sync hands the events around, so changes made at the same time on
-- different computers all count, nothing is overwritten.
--   P  points: a list of characters with an EP and GP change, a label,
--      optionally the item and the kind ("raid", "ontime" or "loot")
--   D  decay by pct percent
--   A  alt link, alt and main (no main makes the alt a main again)
--   U  undo of the event ref
-- Rules, editors and the bench are small settings, for them the newest
-- change wins (t is the server time of the change).

local _, ns = ...
ns = ns or _G.RedGuildForever

ns.members = {}   -- guild roster, full name -> { index, rank, class, online }
ns.lookup = {}    -- lower case full name -> full name

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
local tempData = { players = {}, events = {}, rules = {}, editors = {}, bench = {} } -- used while the game does not know the guild yet

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
    local editors, bench, events = {}, {}, {}
    for full, e in pairs(src.editors or {}) do
        editors[full] = { on = e.on, t = e.t, by = e.by }
    end
    for full, e in pairs(src.bench or {}) do
        bench[full] = { on = e.on, t = e.t }
    end
    for id, ev in pairs(src.events or {}) do
        events[id] = ns.CopyEvent(ev)
    end
    return { players = players, rules = rules, editors = editors, bench = bench, events = events, started = true }
end

function ns.CopyEvent(ev)
    local c = {}
    for k, v in pairs(ev) do c[k] = v end
    if ev.ch then
        c.ch = {}
        for i, x in ipairs(ev.ch) do c.ch[i] = { n = x.n, ep = x.ep, gp = x.gp } end
    end
    return c
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
    data.editors = data.editors or {}
    data.events = data.events or {}
    data.bench = data.bench or {}
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
    db.test.log = {}
    ns.Invalidate()
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
    for _, a in ipairs(ns.auctions or {}) do
        if not a.test then
            ns.Print("finish the bidding for " .. a.link .. " before switching test mode")
            return false
        end
    end
    if ns.CancelAllAuctions then ns.CancelAllAuctions() end
    db.settings.testMode = on
    ns.Invalidate()
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

-- The starting points (from version 1.7 and older, or a backup of it)
function ns.Base()
    return ns.Data().players
end

-- true when there is data to work with, or an editor chose to start fresh
function ns.HasData()
    local data = ns.Data()
    return data.started or next(data.players) ~= nil or next(data.events or {}) ~= nil
end

function ns.StartFresh()
    if not ns.CanEdit() then return false end
    ns.Data().started = true
    ns.Fire("RGF_POINTS_CHANGED")
    return true
end

------------------------------------------------------------------------
-- Who may change data: the guild leader and the editors.
-- The guild leader picks the editors by hand in the Settings tab or with
-- /rgf editor add Name. The list is saved with the guild data and shared
-- with Sync, everyone only accepts list changes made by the guild leader.
--
-- Until the guild leader adds the first editor, the old rank rule still
-- applies, so updating the addon never locks anyone out: rank 0 and 1, or
-- what "EPGP officers 2" in the guild information allows.
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

local function rankOf(full)
    if full == ns.PlayerName() then return ns.MyRank() end
    local m = ns.members[full]
    return m and m.rank
end

function ns.EditorList()
    local data = ns.Data()
    data.editors = data.editors or {}
    return data.editors
end

-- true once the guild leader added or removed an editor
function ns.EditorsInUse()
    return next(ns.EditorList()) ~= nil
end

function ns.IsGuildLeader(full)
    full = full and ns.Resolve(full)
    return full ~= nil and rankOf(full) == 0
end

function ns.IsEditor(full)
    full = full and ns.Resolve(full)
    if not full then return false end
    local rank = rankOf(full)
    if rank == 0 then return true end
    if ns.EditorsInUse() then
        local e = ns.EditorList()[full]
        return e ~= nil and e.on == true
    end
    return rank ~= nil and rank <= ns.OfficerRank()
end
ns.IsOfficer = ns.IsEditor -- older name

function ns.CanEdit()
    if ns.IsTest() then return true end -- in test mode everyone can try the editor tools
    if not (IsInGuild and IsInGuild()) then return false end
    return ns.IsEditor(ns.PlayerName())
end
ns.CanEditNotes = ns.CanEdit -- older name, used in a few places

-- Only the guild leader manages the editors. In test mode everyone can try it.
function ns.CanManageEditors()
    if ns.IsTest() then return true end
    return IsInGuild and IsInGuild() and ns.MyRank() == 0 or false
end

-- Editors by name, sorted. Removed editors are left out.
function ns.Editors()
    local list = {}
    for full, e in pairs(ns.EditorList()) do
        if e.on then table.insert(list, full) end
    end
    table.sort(list)
    return list
end

-- Add (on true) or remove an editor. Returns true, or nil and a reason.
function ns.SetEditor(name, on)
    if not ns.CanManageEditors() then return nil, "only the guild leader can add or remove editors" end
    local full = ns.FindMember(name, true)
    if not full or not ns.members[full] then return nil, "nobody in the guild is called " .. (name or "?") end
    if rankOf(full) == 0 then return nil, ns.ShortName(full) .. " is the guild leader and can always edit" end
    on = on and true or false
    local list = ns.EditorList()
    local e = list[full]
    if e and e.on == on then
        return nil, ns.ShortName(full) .. (on and " is already an editor" or " is not an editor")
    end
    if not e and not on and not ns.EditorsInUse() then
        return nil, "the editor list is still empty, add the editors you want first"
    end
    local me = ns.PlayerName()
    list[full] = { on = on, t = ns.Now(), by = me }
    ns.AddLogEntry(ns.ShortName(full) .. (on and " is now an editor" or " is no editor anymore"), 1)
    ns.Fire("RGF_EDITORS_CHANGED")
    ns.Fire("RGF_POINTS_CHANGED")
    ns.Fire("RGF_LOCAL_CHANGE", { state = true })
    return true, full
end

-- Start the list with everyone the old rank rule allows, without the guild leader.
-- Returns the number of added editors.
function ns.AddRankEditors()
    if not ns.CanManageEditors() then return 0 end
    local limit, names = ns.OfficerRank(), {}
    for full, m in pairs(ns.members) do
        if m.rank and m.rank > 0 and m.rank <= limit then table.insert(names, full) end
    end
    table.sort(names)
    local count = 0
    for _, full in ipairs(names) do
        local e = ns.EditorList()[full]
        if not (e and e.on) and ns.SetEditor(full, true) then count = count + 1 end
    end
    return count
end

-- Every change goes through here, it explains why a change is not possible.
function ns.CanChange()
    if not ns.CanEdit() then
        ns.Print("only the guild leader and editors can change points")
        return false
    end
    if not ns.HasData() then
        ns.Print("no EPGP data loaded yet. Click Sync to get it from the editors, or Start fresh if your guild is new")
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
    ns.Invalidate() -- the guild may be known only now, or another guild
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
    ns.MigrateOldBench()
    if ns.CheckEmptyData then ns.CheckEmptyData() end
    ns.Fire("RGF_POINTS_CHANGED")
end

------------------------------------------------------------------------
-- Changing guild rules
------------------------------------------------------------------------
-- Change several rules at once. values maps rule keys to typed values.
-- Returns the number of changed rules, or nil and a reason.
function ns.SetRules(values)
    if not ns.CanChange() then return nil, "only the guild leader and editors can change the rules" end
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
    ns.AddLogEntry("Settings changed, " .. table.concat(parts, ", "), #parts)
    ns.Invalidate()
    ns.Fire("RGF_RULES_CHANGED")
    ns.Fire("RGF_POINTS_CHANGED")
    ns.Fire("RGF_LOCAL_CHANGE", { state = true })
    return #parts
end

-- Set every rule back to the rule book. Fixed item prices stay.
function ns.ResetRules()
    local values = {}
    for _, def in ipairs(ns.RULES) do values[def.key] = def.default end
    return ns.SetRules(values)
end

------------------------------------------------------------------------
-- Reading points: the starting points plus every event, in order
------------------------------------------------------------------------
local cache

-- Forget the computed points, they are computed again when needed.
function ns.Invalidate()
    cache = nil
end

local function byTime(a, b)
    if a.t ~= b.t then return a.t < b.t end
    return a.id < b.id
end

-- Every event, oldest first
function ns.SortedEvents()
    local list = {}
    for _, ev in pairs(ns.Data().events or {}) do table.insert(list, ev) end
    table.sort(list, byTime)
    return list
end

local function compute()
    local data = ns.Data()
    local base = ns.Setting("baseGP")
    local players = {}
    for full, e in pairs(data.players or {}) do
        if e.main then
            players[full] = { main = e.main }
        elseif e.ep then
            players[full] = { ep = e.ep, gp = math.max(e.gp or base, base) }
        end
    end
    local events = ns.SortedEvents()
    local undone = {}
    for _, ev in ipairs(events) do
        if ev.k == "U" and ev.ref then undone[ev.ref] = ev end
    end
    local function mainOf(full)
        local e = players[full]
        if e and e.main then
            local m = players[e.main]
            if not (m and m.main) then return e.main end
        end
        return full
    end
    local function points(full)
        local e = players[full]
        if not e or not e.ep then
            e = { ep = 0, gp = base }
            players[full] = e
        end
        return e
    end
    for _, ev in ipairs(events) do
        if not undone[ev.id] then
            if ev.k == "P" then
                local seen = {}
                for _, c in ipairs(ev.ch or {}) do
                    local main = mainOf(c.n)
                    if not seen[main] then
                        seen[main] = true
                        local e = points(main)
                        e.ep = e.ep + (c.ep or 0)
                        e.gp = math.max(e.gp + (c.gp or 0), base)
                    end
                end
            elseif ev.k == "D" then
                local f = 1 - (ev.pct or 0) / 100
                for _, e in pairs(players) do
                    if e.ep then
                        e.ep = ns.Round(e.ep * f)
                        e.gp = math.max(ns.Round(e.gp * f), base)
                    end
                end
            elseif ev.k == "A" and ev.alt then
                local alt = ev.alt
                local ae = players[alt]
                if ev.main then
                    local main = mainOf(ev.main)
                    if main ~= alt and not (ae and ae.main == main) then
                        -- the alt brings its points to the main
                        if ae and ae.ep then
                            local me = points(main)
                            me.ep = me.ep + ae.ep
                            me.gp = math.max(me.gp + (ae.gp - base), base)
                        end
                        -- alts of the alt now belong to the main, there is only one level
                        for _, e in pairs(players) do
                            if e.main == alt then e.main = main end
                        end
                        players[alt] = { main = main }
                    end
                elseif ae and ae.main then
                    players[alt] = { ep = 0, gp = base }
                end
            end
        end
    end
    return { players = players, undone = undone, events = events }
end

-- The computed points: { players = ..., undone = { [id] = undo event }, events = sorted list }
function ns.State()
    -- a new guild or test mode has its own data
    local data = ns.Data()
    if not cache or cache.data ~= data then
        cache = compute()
        cache.data = data
    end
    return cache
end

-- Every character with points or an alt link, computed from the events
function ns.Players()
    return ns.State().players
end

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
-- Writing: every change is a new event
------------------------------------------------------------------------
local seq = 0

-- Ids start with the time, then a counter, so the changes of one computer
-- keep their order within a second, and a random part.
local function newId()
    seq = (seq + 1) % 256
    return string.format("%x%02x%04x", ns.Now(), seq, math.random(0, 65535))
end

-- Store a change made on this computer. Sync sends it to everyone.
function ns.AddEvent(ev)
    local events = ns.Data().events
    ev.t = ev.t or ns.Now()
    ev.by = ev.by or ns.PlayerName()
    ev.id = newId()
    while events[ev.id] do ev.id = newId() end
    events[ev.id] = ev
    ns.Data().started = true
    ns.Invalidate()
    ns.Fire("RGF_POINTS_CHANGED")
    ns.Fire("RGF_LOCAL_CHANGE", ev)
    return ev
end

-- Start a change, every Adjust until EndAction goes into one event.
-- opts.kind is "raid", "ontime" or "loot", opts.item the item id of loot.
function ns.BeginAction(label, opts)
    local action = { label = label, changes = {}, kind = opts and opts.kind, item = opts and opts.item }
    ns.currentAction = action
    return action
end

function ns.EndAction()
    local action = ns.currentAction
    ns.currentAction = nil
    if action and #action.changes > 0 then
        local ch = {}
        for _, c in ipairs(action.changes) do table.insert(ch, { n = c.name, ep = c.ep, gp = c.gp }) end
        if (action.label or "") == "" then
            -- a change without a label, for example from another addon or a macro
            local c = ch[1]
            local parts = {}
            if c.ep ~= 0 then table.insert(parts, string.format("%+d EP", c.ep)) end
            if c.gp ~= 0 then table.insert(parts, string.format("%+d GP", c.gp)) end
            action.label = ns.ShortName(c.n) .. " " .. table.concat(parts, " ") .. (#ch > 1 and (" and " .. (#ch - 1) .. " more") or "")
        end
        local ev = ns.AddEvent({ k = "P", ch = ch, r = action.label, kind = action.kind, item = action.item })
        action.id = ev.id
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
    local change = { name = ns.Resolve(name), ep = math.floor(dEP or 0), gp = math.floor(dGP or 0) }
    if ns.currentAction then
        table.insert(ns.currentAction.changes, change)
    else
        ns.BeginAction("")
        table.insert(ns.currentAction.changes, change)
        ns.EndAction()
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

local NIGHT = 12 * 3600

-- true when the main already got EP of this kind ("raid" or "ontime") in the
-- last 12 hours, from any raid. Two raids on the same evening give it once.
function ns.GotTonight(main, kind)
    local st = ns.State()
    local since = ns.Now() - NIGHT
    for i = #st.events, 1, -1 do
        local ev = st.events[i]
        if ev.t < since then break end
        if ev.k == "P" and ev.kind == kind and not st.undone[ev.id] then
            for _, c in ipairs(ev.ch or {}) do
                if ns.MainOf(c.n) == main and (c.ep or 0) > 0 then return true end
            end
        end
    end
    return false
end

-- Give EP to a list of characters, each player only once even with alts.
-- With a kind ("raid", "ontime") players who already got it tonight are left out.
-- Returns the number of players, the names outside the guild and the names
-- that already got it.
function ns.AwardEP(names, amount, label, kind)
    if not ns.CanChange() then return 0, {}, {} end
    local done, skipped, already = {}, {}, {}
    local count = 0
    ns.BeginAction(label .. " +" .. amount .. " EP", { kind = kind })
    for _, name in ipairs(names) do
        local main = ns.MainOf(name)
        if main and ns.members[main] then
            if not done[main] then
                done[main] = true
                if kind and ns.GotTonight(main, kind) then
                    table.insert(already, name)
                else
                    ns.Adjust(name, amount, 0)
                    count = count + 1
                end
            end
        else
            table.insert(skipped, name)
        end
    end
    ns.EndAction()
    return count, skipped, already
end

function ns.Decay()
    if not ns.CanChange() then return 0 end
    local count = 0
    for _, e in pairs(ns.Players()) do
        if e.ep then count = count + 1 end
    end
    local pct = ns.Setting("decayPercent")
    ns.AddEvent({ k = "D", pct = pct, r = "Weekly decay " .. pct .. "%" })
    return count
end

-- The newest change of this player that is not undone yet
function ns.LastOwnEvent()
    local st = ns.State()
    local me = ns.PlayerName()
    for i = #st.events, 1, -1 do
        local ev = st.events[i]
        if ev.by == me and ev.k ~= "U" and not st.undone[ev.id] then return ev end
    end
    return nil
end

-- Undo any change, also one from an earlier session or another editor.
-- The change stays in the history, marked as undone.
function ns.UndoEvent(id)
    if not ns.CanChange() then return nil end
    local ev = ns.Data().events[id]
    if not ev or ev.k == "U" or ns.State().undone[id] then return nil end
    ns.AddEvent({ k = "U", ref = id, r = "Undo " .. (ev.r or "") })
    return { label = ev.r or "", id = id }
end

-- Undo the newest change of this player
function ns.Undo()
    if not ns.CanChange() then return nil end
    local ev = ns.LastOwnEvent()
    if not ev then return nil end
    return ns.UndoEvent(ev.id)
end

-- Link an alt to a main. The alt's points move to the main.
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
    if ae and ae.main == m then
        ns.Print(ns.ShortName(a) .. " is already an alt of " .. ns.ShortName(m))
        return false
    end
    if ae and ae.ep and (ae.ep ~= 0 or (ae.gp or 0) > ns.Setting("baseGP")) then
        ns.Print(string.format("%s brings %d EP and %d GP above the start to %s", ns.ShortName(a), ae.ep,
            ae.gp - ns.Setting("baseGP"), ns.ShortName(m)))
    end
    ns.AddEvent({ k = "A", alt = a, main = m, r = ns.ShortName(a) .. " linked as alt of " .. ns.ShortName(m) })
    return true
end

-- The alt becomes a main again and starts at 0 EP. Undo brings the link back.
function ns.UnsetAlt(alt)
    if not ns.CanChange() then return false end
    local a = ns.Resolve(alt)
    local e = entry(a)
    if not e or not e.main then ns.Print(alt .. " is not linked as an alt") return false end
    ns.AddEvent({ k = "A", alt = a, r = ns.ShortName(a) .. " is a main again" })
    return true
end

-- One time import of points from officer notes (versions 1.3 and older).
function ns.ImportOfficerNotes()
    if not ns.CanEdit() then
        ns.Print("only the guild leader and editors can import")
        return 0
    end
    if not GetNumGuildMembers then return 0 end
    local base = ns.Base()
    local players = ns.Players()
    local count = 0
    for i = 1, GetNumGuildMembers() or 0 do
        local name, _, _, _, _, _, _, officerNote = GetGuildRosterInfo(i)
        if name and officerNote and officerNote ~= "" then
            local full = ns.FullName(name)
            local info = ns.ParseNote(officerNote)
            if (info.ep or info.main) and not players[full] then
                local e = info.main and { main = info.main }
                    or { ep = info.ep, gp = math.max(info.gp, ns.Setting("baseGP")) }
                e.t, e.by = ns.Now(), ns.PlayerName()
                base[full] = e
                count = count + 1
            end
        end
    end
    if count > 0 then
        ns.Data().started = true
        ns.Invalidate()
        ns.Fire("RGF_POINTS_CHANGED")
        ns.Fire("RGF_LOCAL_CHANGE", { state = true })
    end
    return count
end

------------------------------------------------------------------------
-- History: every event plus the settings changes of this computer
------------------------------------------------------------------------
local function settingsLog()
    local db = RedGuildForeverDB
    if not db then return {} end
    if ns.IsTest() then
        db.test = db.test or {}
        db.test.log = db.test.log or {}
        return db.test.log
    end
    db.log = db.log or {}
    return db.log
end

function ns.AddLogEntry(label, count)
    local log = settingsLog()
    table.insert(log, { time = ns.Now(), label = label, count = count or 1, by = ns.PlayerName() })
    while #log > 500 do table.remove(log, 1) end
end

-- How many players an event changed
local function eventCount(ev)
    if ev.k == "P" then return #(ev.ch or {}) end
    return 1
end

-- Everything that happened, oldest first. Entries of events carry the id,
-- so the History tab can undo them.
function ns.Log()
    local st = ns.State()
    local list = {}
    for _, e in ipairs(settingsLog()) do
        table.insert(list, { time = e.time or 0, label = e.label, count = e.count or 1, by = e.by, order = #list })
    end
    for _, ev in ipairs(st.events) do
        table.insert(list, { time = ev.t, label = ev.r ~= "" and ev.r or "Points changed", count = eventCount(ev), by = ev.by,
            id = ev.id, undo = ev.k == "U", undone = st.undone[ev.id] ~= nil, item = ev.item, order = #list })
    end
    table.sort(list, function(a, b)
        if a.time ~= b.time then return a.time < b.time end
        return a.order < b.order
    end)
    return list
end

------------------------------------------------------------------------
-- Bench, shared with Sync. The newest change of each player wins.
------------------------------------------------------------------------
function ns.Bench()
    local list = {}
    for full, e in pairs(ns.Data().bench or {}) do
        if e.on then table.insert(list, full) end
    end
    table.sort(list)
    return list
end

local function setBench(full, on)
    local bench = ns.Data().bench
    bench[full] = { on = on, t = ns.Now() }
    ns.Data().started = ns.Data().started or ns.HasData()
end

local function benchChanged()
    ns.Fire("RGF_BENCH_CHANGED")
    ns.Fire("RGF_LOCAL_CHANGE", { state = true })
end

function ns.BenchAdd(name)
    if not ns.CanEdit() then return false end
    local full = ns.Resolve(name)
    if not full then return false end
    local e = ns.Data().bench[full]
    if e and e.on then return false end
    setBench(full, true)
    benchChanged()
    return true, full
end

function ns.BenchRemove(name)
    if not ns.CanEdit() then return false end
    local full = ns.Resolve(name)
    local e = full and ns.Data().bench[full]
    if not (e and e.on) then return false end
    setBench(full, false)
    benchChanged()
    return true, full
end

function ns.BenchClear()
    if not ns.CanEdit() then return end
    for _, full in ipairs(ns.Bench()) do setBench(full, false) end
    benchChanged()
end

-- The bench of version 1.7 and older was saved only on this computer.
-- Move it into the guild data once, so it is shared.
function ns.MigrateOldBench()
    local old = RedGuildForeverDB and RedGuildForeverDB.bench
    if type(old) ~= "table" or #old == 0 or ns.IsTest() or not ns.GuildKey() then return end
    local bench = ns.RealData().bench
    for _, full in ipairs(old) do
        if not bench[full] then bench[full] = { on = true, t = ns.Now() } end
    end
    wipe(old)
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
