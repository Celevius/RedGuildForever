-- Communication between addon users.
--
-- Messages use "^" as separator, because item links contain "|".
--   SQ                      ask everyone to sync (GUILD)
--   DB^n / DD^n^data / DE^n an officer sends all data, begin, data, end (GUILD)
--   A^id^seconds^gp^link    an auction starts (RAID)
--   B^id^MS|OS|PASS         a bid (WHISPER to the loot master)
--   C^id^winner             an auction ends (RAID)

local _, ns = ...
ns = ns or _G.RedGuildForever

local SEP = "^"
ns.commHandlers = {}

function ns.OnComm(kind, fn)
    ns.commHandlers[kind] = fn
end

function ns.SendComm(msg, channel, target)
    if ns.IsTest() then return true end -- in test mode nothing leaves this computer
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, ns.prefix, msg, channel, target)
    -- newer clients return a result code, 0 means success
    if not ok then return false end
    if type(result) == "number" then return result == 0 end
    return result ~= false
end

function ns.Split(msg)
    local parts = {}
    for part in (msg .. SEP):gmatch("(.-)%" .. SEP) do
        table.insert(parts, part)
    end
    return parts
end

-- Item links can contain "^" in theory, so the link is always the last field
-- and we join everything that is left.
function ns.SplitWithTail(msg, fields)
    local parts = ns.Split(msg)
    if #parts > fields then
        local tail = table.concat(parts, SEP, fields)
        for i = #parts, fields, -1 do parts[i] = nil end
        parts[fields] = tail
    end
    return parts
end

ns.On("RGF_READY", function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(ns.prefix)
    end
    -- ask the guild for the newest data a few seconds after login
    ns.After(8, function() ns.Sync(true) end)
end)

ns.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix ~= ns.prefix or type(text) ~= "string" then return end
    if ns.IsTest() then return end -- real data from others never mixes with test data
    local kind = text:match("^(%a+)")
    local fn = kind and ns.commHandlers[kind]
    -- handlers get the guild name, plus the name exactly as the game sent it for whispers
    if fn then fn(text, ns.Resolve(sender), channel, sender) end
end)

------------------------------------------------------------------------
-- Sync
--
-- Everyone keeps a copy of the data. Officers send their whole data set,
-- everyone merges it and the newest change per player wins. An officer who
-- notices he has newer entries than the sender answers with his own data,
-- so after one sync everyone online has the same data.
------------------------------------------------------------------------
local incoming = {}
local broadcastQueued = false
ns.syncInfo = { at = nil, from = {}, changes = 0 }

-- Entries are "Name,ep,gp,time", "Alt>Main,time" and for guild rules
-- "#rule,value,time", separated by ";". A cleared fixed item price is
-- sent as the value "x". Versions 1.5 and older ignore rule entries.
local function encode()
    local entries = {}
    for key, e in pairs(ns.Data().rules or {}) do
        local value = e.v == nil and "x" or ns.FormatNumber(e.v)
        table.insert(entries, string.format("#%s,%s,%d", key, value, e.t or 0))
    end
    for full, e in pairs(ns.Players()) do
        local t = e.t or 0
        if e.main then
            table.insert(entries, string.format("%s>%s,%d", ns.ShortName(full), ns.ShortName(e.main), t))
        elseif e.ep then
            table.insert(entries, string.format("%s,%d,%d,%d", ns.ShortName(full), e.ep, e.gp or ns.Setting("baseGP"), t))
        end
    end
    table.sort(entries)
    return entries
end

-- Returns the player name (or "#rule") and the entry.
local function decode(entryText)
    local key, value, rt = entryText:match("^#([^,;]+),([^,;]*),(%d+)$")
    if key then
        if not (ns.RULE[key] or key:match("^item:%d+$")) then return nil end
        local v
        if value ~= "x" then
            v = tonumber(value)
            if not v then return nil end
            if ns.RULE[key] then
                v = ns.CheckRule(key, v)
                if not v then return nil end -- out of range, ignore it
            elseif v < 0 then
                return nil
            end
        end
        return "#" .. key, { v = v, t = tonumber(rt) }
    end
    local alt, main, t = entryText:match("^(.-)>(.-),(%d+)$")
    if alt then
        return ns.FullName(alt), { main = ns.FullName(main), t = tonumber(t) }
    end
    local name, ep, gp, t2 = entryText:match("^(.-),(%-?%d+),(%d+),(%d+)$")
    if name then
        return ns.FullName(name), { ep = tonumber(ep), gp = tonumber(gp), t = tonumber(t2) }
    end
end

function ns.SendData()
    if not (IsInGuild and IsInGuild()) or not ns.CanEdit() or not ns.HasData() then return false end
    local nonce = tostring(math.random(100000, 999999))
    ns.SendComm("DB" .. SEP .. nonce, "GUILD")
    local chunk, size = {}, 0
    local function flush()
        if #chunk > 0 then
            ns.SendComm("DD" .. SEP .. nonce .. SEP .. table.concat(chunk, ";"), "GUILD")
            chunk, size = {}, 0
        end
    end
    for _, e in ipairs(encode()) do
        if size + #e + 1 > 230 then flush() end
        table.insert(chunk, e)
        size = size + #e + 1
    end
    flush()
    ns.SendComm("DE" .. SEP .. nonce, "GUILD")
    return true
end

-- Send our data a few seconds after a change, so several changes go out once.
function ns.QueueBroadcast(delay)
    if broadcastQueued then return end
    broadcastQueued = true
    ns.After(delay or 5, function()
        broadcastQueued = false
        ns.SendData()
    end)
end

-- The Sync button. Officers send their data, everyone asks for the newest.
function ns.Sync(quiet)
    if ns.IsTest() then
        ns.SimulateSync(quiet)
        return true
    end
    if not (IsInGuild and IsInGuild()) then
        if not quiet then ns.Print("you are not in a guild") end
        return false
    end
    ns.syncInfo = { at = ns.Now(), from = {}, changes = 0, running = true }
    ns.SendComm("SQ", "GUILD")
    if ns.CanEdit() and ns.HasData() then ns.QueueBroadcast(0) end
    if not quiet then ns.Print("syncing with everyone online") end
    ns.After(10, function()
        ns.syncInfo.running = false
        if not quiet then
            local who = {}
            for name in pairs(ns.syncInfo.from) do table.insert(who, ns.ShortName(name)) end
            table.sort(who)
            if #who == 0 then
                ns.Print("sync done, no other officer with data is online")
            else
                ns.Print("sync done with " .. table.concat(who, ", ") .. ", " .. ns.syncInfo.changes .. " changes")
            end
        end
        ns.Fire("RGF_SYNC_DONE")
    end)
    ns.Fire("RGF_SYNC_DONE")
    return true
end

ns.On("RGF_LOCAL_CHANGE", function() ns.QueueBroadcast(5) end)

ns.OnComm("SQ", function(_, sender)
    if sender == ns.PlayerName() or not ns.CanEdit() or not ns.HasData() then return end
    ns.After(1 + math.random() * 3, function() ns.QueueBroadcast(0) end)
end)

ns.OnComm("DB", function(text, sender)
    if sender == ns.PlayerName() or not ns.IsOfficer(sender) then return end
    incoming[sender] = { nonce = ns.Split(text)[2], players = {} }
end)

ns.OnComm("DD", function(text, sender)
    local p = ns.SplitWithTail(text, 3)
    local inc = incoming[sender]
    if not inc or inc.nonce ~= p[2] or not p[3] then return end
    for entryText in p[3]:gmatch("[^;]+") do
        local name, e = decode(entryText)
        if name then inc.players[name] = e end
    end
end)

-- Merge the data of another officer. Returns how many entries changed and
-- whether we have entries the sender does not know or knows older.
-- Merge data of another officer. Players and "#rule" entries both keep
-- the newest change. Returns how many entries changed and whether we have
-- entries the sender does not know or knows older.
function ns.MergeData(theirs, sender)
    local data = ns.Data()
    data.rules = data.rules or {}
    local players, rules = data.players, data.rules
    local changes, rulesChanged = 0, false
    local function tableFor(name)
        if name:sub(1, 1) == "#" then return rules, name:sub(2) end
        return players, name
    end
    for name, e in pairs(theirs) do
        local tbl, key = tableFor(name)
        local local_ = tbl[key]
        if not local_ or (e.t or 0) > (local_.t or 0) then
            e.by = sender
            tbl[key] = e
            changes = changes + 1
            if tbl == rules then rulesChanged = true end
        end
    end
    local weAreNewer = false
    local function check(tbl, prefix)
        for key, e in pairs(tbl) do
            local t = theirs[prefix .. key]
            if not t or (e.t or 0) > (t.t or 0) then weAreNewer = true return end
        end
    end
    check(players, "")
    if not weAreNewer then check(rules, "#") end
    if changes > 0 or next(theirs) then data.started = true end
    if rulesChanged then ns.Fire("RGF_RULES_CHANGED") end
    return changes, weAreNewer
end

ns.OnComm("DE", function(text, sender)
    local inc = incoming[sender]
    if not inc or inc.nonce ~= ns.Split(text)[2] then return end
    incoming[sender] = nil
    local changes, weAreNewer = ns.MergeData(inc.players, sender)
    ns.syncInfo.from[sender] = true
    ns.syncInfo.changes = (ns.syncInfo.changes or 0) + changes
    ns.syncInfo.last = ns.Now()
    if changes > 0 then ns.RebuildFromRoster() end
    if weAreNewer and ns.CanEdit() then ns.QueueBroadcast(2 + math.random() * 3) end
    ns.Fire("RGF_POINTS_CHANGED")
    ns.Fire("RGF_SYNC_DONE")
end)

------------------------------------------------------------------------
-- Backup as text, to keep outside the game (Discord, a text file)
------------------------------------------------------------------------
local BACKUP_TAG = "RGFEPGP1"

function ns.ExportText()
    local key = ns.GuildKey() or "?"
    return BACKUP_TAG .. ";" .. key .. ";" .. ns.Now() .. ";" .. table.concat(encode(), ";")
end

-- Returns the number of changed entries, or nil and a reason.
function ns.ImportText(textValue)
    if not ns.CanEdit() then return nil, "only the guild leader and officers can import" end
    if type(textValue) ~= "string" then return nil, "nothing to import" end
    textValue = textValue:gsub("%s*\n%s*", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local tag, guild, rest = textValue:match("^([^;]+);([^;]*);%d+;?(.*)$")
    if tag ~= BACKUP_TAG then return nil, "this is not a Red Guild EPGP backup" end
    local key = ns.GuildKey()
    if key and guild ~= key then return nil, "this backup belongs to " .. guild end
    local theirs, count = {}, 0
    for entryText in rest:gmatch("[^;]+") do
        local name, e = decode(entryText)
        if name then theirs[name] = e count = count + 1 end
    end
    if count == 0 then return nil, "the backup is empty" end
    local changes = ns.MergeData(theirs, ns.PlayerName())
    ns.Data().started = true
    ns.RebuildFromRoster()
    ns.Fire("RGF_POINTS_CHANGED")
    if changes > 0 then ns.QueueBroadcast(2) end
    return changes
end

------------------------------------------------------------------------
-- Sync in test mode: nothing is sent, a simulated officer sends one newer change
------------------------------------------------------------------------
function ns.SimulateSync(quiet)
    ns.syncInfo = { at = ns.Now(), from = {}, changes = 0, running = true }
    ns.Fire("RGF_SYNC_DONE")
    ns.After(2, function()
        local officer = "Simulated Officer-" .. ns.MyRealm()
        local raid = ns.RaidMembers()
        local target = raid[math.random(#raid)]
        local main = ns.MainOf(target)
        local ep, gp = ns.GetPoints(main)
        local theirs = { [main] = { ep = ep + 25, gp = gp, t = ns.Now() + 1 } }
        local changes = ns.MergeData(theirs, officer)
        ns.syncInfo = { at = ns.syncInfo.at, from = { [officer] = true }, changes = changes, last = ns.Now() }
        ns.RebuildFromRoster()
        ns.Fire("RGF_POINTS_CHANGED")
        ns.Fire("RGF_SYNC_DONE")
        if not quiet then
            ns.Print(ns.TEST_TAG .. "sync simulated. A simulated officer sent a newer entry, " .. ns.ShortName(main) .. " now has " .. (ep + 25) .. " EP. Nothing was sent to anyone")
        end
    end)
end
