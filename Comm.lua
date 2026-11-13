-- SPDX-License-Identifier: MIT, see LICENSE
-- Communication between addon users.
--
-- Messages use "^" as separator, because item links contain "|".
--   Q^req^digest                          ask for what is missing (GUILD)
--   H^n^mode^req^cutoff^parts^digest      an editor starts a transfer (GUILD)
--   D^n^seq^piece                         one piece of the transfer
--   E^n^count                             the end, count pieces were sent
--   A^id^seconds^gp^link                  an auction starts (RAID)
--   P^id^gp                               the price of an auction changed (RAID)
--   B^id^MS|OS|PASS                       a bid (WHISPER to the loot master)
--   C^id^winner^gp^MS|OS^link             an auction ends, without a winner only C^id^ (RAID)
-- Version 2.0 uses its own prefix, so it never mixes with 1.7 and older.

local _, ns = ...
ns = ns or _G.RedGuildForever

local SEP = "^"
ns.commHandlers = {}

function ns.OnComm(kind, fn)
    ns.commHandlers[kind] = fn
end

-- The result codes of the game (Enum.SendAddonMessageResult)
local SENT, THROTTLED, CHANNEL_THROTTLED, GENERAL_ERROR, LOCKDOWN = 0, 3, 8, 9, 11
-- these can work a moment later, every other code will never work for this message
local TRY_AGAIN = { [THROTTLED] = true, [CHANNEL_THROTTLED] = true, [GENERAL_ERROR] = true, [LOCKDOWN] = true }

-- Returns true when the game took the message, otherwise false and the result code.
local function rawSend(msg, channel, target)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
    local results = { pcall(C_ChatInfo.SendAddonMessage, ns.prefix, msg, channel, target) }
    if not results[1] then return false end
    -- the result code is the last value, older clients return true or false
    local result = results[#results]
    if type(result) == "number" then return result == SENT, result end
    return result ~= false, GENERAL_ERROR
end

-- During boss fights and other restricted content the game takes no addon messages.
local function lockedDown()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        return ok and locked == true
    end
    return false
end

------------------------------------------------------------------------
-- Send queue. The game gives every addon an allowance of 10 messages, which
-- refills by one per second. A message over the allowance is refused, so
-- we count the allowance ourselves and never send more. Sync data waits in
-- the queue and leaves a few messages of the allowance free, so auctions
-- and bids always go out right away. A refused message is tried again, it
-- is only given up when the game refuses it for ten minutes.
------------------------------------------------------------------------
local ALLOWANCE = 10 -- messages the game takes in one go
local REFILL = 1     -- messages per second that come back
local RESERVE = 3    -- kept free for auctions and bids
local RETRY = 2      -- seconds to wait when the game refused a message
local GIVE_UP = 600  -- seconds after which a refused message is dropped

local urgent, queue = {}, {} -- urgent: auction messages the game refused
local pumping = false
local tokens, tokenTime = ALLOWANCE, nil

local function now()
    return GetTime and GetTime() or 0
end

local function refill()
    local t = now()
    if tokenTime then tokens = math.min(ALLOWANCE, tokens + (t - tokenTime) * REFILL) end
    tokenTime = t
end

local pump

local function pumpLater(seconds)
    ns.After(seconds, pump)
end

pump = function()
    refill()
    if lockedDown() then
        pumpLater(RETRY)
        return
    end
    while true do
        local list = urgent[1] and urgent or queue
        local m = list[1]
        if not m then
            pumping = false
            return
        end
        local need = list == urgent and 1 or (RESERVE + 1)
        if tokens < need then
            pumpLater((need - tokens) / REFILL + 0.05)
            return
        end
        local ok, code = rawSend(m.msg, m.channel, m.target)
        if ok then
            tokens = tokens - 1
            table.remove(list, 1)
        elseif TRY_AGAIN[code or GENERAL_ERROR] and now() - m.since < GIVE_UP then
            -- the game says we sent too much, so our count was too high
            if code == THROTTLED or code == CHANNEL_THROTTLED then tokens = 0 end
            pumpLater(RETRY)
            return
        else
            table.remove(list, 1) -- it can never go out, or we tried for too long
        end
    end
end

local function enqueue(list, msg, channel, target)
    table.insert(list, { msg = msg, channel = channel, target = target, since = now() })
    if not pumping then
        pumping = true
        pump()
    end
end

-- bulk messages (sync data) wait in the queue, everything else goes out at once.
-- Returns false only for a whisper the game refused, the caller then whispers in chat.
function ns.SendComm(msg, channel, target, bulk)
    if ns.IsTest() then return true end -- in test mode nothing leaves this computer
    if bulk then
        enqueue(queue, msg, channel, target)
        return true
    end
    refill()
    if not urgent[1] and not lockedDown() then
        local ok, code = rawSend(msg, channel, target)
        if ok then
            tokens = math.max(0, tokens - 1)
            return true
        end
        if not TRY_AGAIN[code or GENERAL_ERROR] then return false end
    end
    if channel == "WHISPER" then return false end
    -- an auction message for the raid must not get lost, it goes out first when the game allows it
    enqueue(urgent, msg, channel, target)
    return true
end

function ns.QueuedMessages()
    return #queue + #urgent
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
    -- ask the guild for the newest data a few seconds after login, and
    -- every 15 minutes, so changes that got lost on the way arrive anyway
    ns.After(8, function() ns.Sync(true) end)
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(900, function() ns.Sync(true) end)
    end
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
-- Encoding. Every piece of data is one text entry, entries are separated
-- by ";".
--   Name,ep,gp,time                 starting points of a player
--   Alt>Main,time                   starting alt link
--   #rule,value,time                guild rule or fixed item price ("x" is cleared)
--   @Name,1 or 0,time,changed by    editor
--   ~Name,1 or 0,time               bench
--   !P,id,time,by,kind,item,Name:ep:gp/Name:ep:gp,label
--   !D,id,time,by,percent,label
--   !A,id,time,by,alt,main,label    an empty main makes the alt a main again
--   !U,id,time,by,undone id,label
------------------------------------------------------------------------
local function clean(textValue)
    return ((textValue or ""):gsub("[;%^\r\n]", " "))
end

local function short(full)
    return full and ns.ShortName(full) or ""
end

function ns.EncodeEvent(ev)
    local head = string.format("!%s,%s,%d,%s,", ev.k, ev.id, ev.t or 0, short(ev.by))
    if ev.k == "P" then
        local ch = {}
        for _, c in ipairs(ev.ch or {}) do
            table.insert(ch, string.format("%s:%d:%d", short(c.n), c.ep or 0, c.gp or 0))
        end
        return head .. string.format("%s,%s,%s,%s", ev.kind or "", ev.item or "", table.concat(ch, "/"), clean(ev.r))
    elseif ev.k == "D" then
        return head .. string.format("%s,%s", ns.FormatNumber(ev.pct or 0), clean(ev.r))
    elseif ev.k == "A" then
        return head .. string.format("%s,%s,%s", short(ev.alt), short(ev.main), clean(ev.r))
    elseif ev.k == "U" then
        return head .. string.format("%s,%s", ev.ref or "", clean(ev.r))
    end
end

local function decodeEvent(entryText)
    local k, id, t, by, rest = entryText:match("^!(%u),(%x+),(%d+),([^,]*),(.*)$")
    if not k then return nil end
    local ev = { k = k, id = id, t = tonumber(t), by = by ~= "" and ns.FullName(by) or nil }
    if k == "P" then
        local kind, item, ch, label = rest:match("^(%a*),(%d*),([^,]*),(.*)$")
        if not kind then return nil end
        ev.kind = kind ~= "" and kind or nil
        ev.item = tonumber(item)
        ev.r = label
        ev.ch = {}
        for name, ep, gp in ch:gmatch("([^/:]+):(%-?%d+):(%-?%d+)") do
            table.insert(ev.ch, { n = ns.FullName(name), ep = tonumber(ep), gp = tonumber(gp) })
        end
        if #ev.ch == 0 then return nil end
    elseif k == "D" then
        local pct, label = rest:match("^([%d%.]+),(.*)$")
        pct = tonumber(pct)
        if not pct or pct < 0 or pct > 100 then return nil end
        ev.pct, ev.r = pct, label
    elseif k == "A" then
        local alt, main, label = rest:match("^([^,]+),([^,]*),(.*)$")
        if not alt then return nil end
        ev.alt, ev.main, ev.r = ns.FullName(alt), main ~= "" and ns.FullName(main) or nil, label
    elseif k == "U" then
        local ref, label = rest:match("^(%x+),(.*)$")
        if not ref then return nil end
        ev.ref, ev.r = ref, label
    else
        return nil
    end
    return ev
end

-- Returns the kind of entry ("event", "base", "rule", "editor", "bench"),
-- the key and the value.
local function decode(entryText)
    if entryText:sub(1, 1) == "!" then
        local ev = decodeEvent(entryText)
        if ev then return "event", ev.id, ev end
        return nil
    end
    local benchName, benchOn, bt = entryText:match("^~([^,;]+),([01]),(%d+)$")
    if benchName then
        return "bench", ns.FullName(benchName), { on = benchOn == "1", t = tonumber(bt) }
    end
    local editor, on, et, by = entryText:match("^@([^,;]+),([01]),(%d+),([^,;]*)$")
    if editor then
        return "editor", ns.FullName(editor), { on = on == "1", t = tonumber(et), by = by ~= "" and ns.FullName(by) or nil }
    end
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
        return "rule", key, { v = v, t = tonumber(rt) }
    end
    local alt, main, t = entryText:match("^(.-)>(.-),(%d+)$")
    if alt then
        return "base", ns.FullName(alt), { main = ns.FullName(main), t = tonumber(t) }
    end
    local name, ep, gp, t2 = entryText:match("^(.-),(%-?%d+),(%d+),(%d+)$")
    if name then
        return "base", ns.FullName(name), { ep = tonumber(ep), gp = tonumber(gp), t = tonumber(t2) }
    end
end

------------------------------------------------------------------------
-- Buckets. To find out what is missing, both sides compare a short digest:
-- the number of entries and a checksum for each bucket.
--   B  starting points
--   S  settings: rules, editors, bench
--   O  events older than the cutoff (about two months)
--   M  events of one month after the cutoff, for example M680
-- Only buckets that differ are sent.
------------------------------------------------------------------------
local MONTH = 30 * 24 * 3600
local MOD = 2147483647

local function hash(textValue)
    local h = 0
    for i = 1, #textValue do h = (h * 31 + textValue:byte(i)) % MOD end
    return h
end

function ns.SyncCutoff(now)
    return (math.floor((now or ns.Now()) / MONTH) - 2) * MONTH
end

local function bucketKey(ev, cutoff)
    if (ev.t or 0) < cutoff then return "O" end
    return "M" .. math.floor(ev.t / MONTH)
end

-- every bucket with its entries, count and checksum
local function buildBuckets(cutoff)
    local data = ns.Data()
    local buckets = {}
    local function add(key, entryText)
        local b = buckets[key]
        if not b then
            b = { entries = {}, count = 0, sum = 0 }
            buckets[key] = b
        end
        table.insert(b.entries, entryText)
        b.count = b.count + 1
        b.sum = (b.sum + hash(entryText)) % MOD
    end
    for full, e in pairs(data.players or {}) do
        local t = e.t or 0
        if e.main then
            add("B", string.format("%s>%s,%d", short(full), short(e.main), t))
        elseif e.ep then
            add("B", string.format("%s,%d,%d,%d", short(full), e.ep, e.gp or ns.Setting("baseGP"), t))
        end
    end
    for key, e in pairs(data.rules or {}) do
        local value = e.v == nil and "x" or ns.FormatNumber(e.v)
        add("S", string.format("#%s,%s,%d", key, value, e.t or 0))
    end
    for full, e in pairs(data.editors or {}) do
        add("S", string.format("@%s,%d,%d,%s", short(full), e.on and 1 or 0, e.t or 0, short(e.by)))
    end
    for full, e in pairs(data.bench or {}) do
        add("S", string.format("~%s,%d,%d", short(full), e.on and 1 or 0, e.t or 0))
    end
    for _, ev in pairs(data.events or {}) do
        local entryText = ns.EncodeEvent(ev)
        if entryText then add(bucketKey(ev, cutoff), entryText) end
    end
    return buckets
end

local function digestOf(buckets)
    local keys = {}
    for key in pairs(buckets) do table.insert(keys, key) end
    table.sort(keys)
    local parts = {}
    for _, key in ipairs(keys) do
        local b = buckets[key]
        table.insert(parts, key .. ":" .. b.count .. ":" .. b.sum)
    end
    return table.concat(parts, ",")
end

local function parseDigest(textValue)
    local d = {}
    for key, count, sum in (textValue or ""):gmatch("(%w+):(%d+):(%d+)") do
        d[key] = count .. ":" .. sum
    end
    return d
end

local function same(b, digestValue)
    if not b then return digestValue == nil or digestValue == "0:0" end
    return digestValue == b.count .. ":" .. b.sum
end

-- The digest of this computer, used by the Sync tab and the tests
function ns.SyncDigest(cutoff)
    return digestOf(buildBuckets(cutoff or ns.SyncCutoff()))
end

------------------------------------------------------------------------
-- Every entry that goes into a backup or a full transfer
------------------------------------------------------------------------
local function allEntries()
    local list = {}
    for _, b in pairs(buildBuckets(0)) do
        for _, entryText in ipairs(b.entries) do table.insert(list, entryText) end
    end
    table.sort(list)
    return list
end

------------------------------------------------------------------------
-- Merging. Events are added when they are new, for starting points and
-- settings the newest change wins.
------------------------------------------------------------------------
-- Only the guild leader changes the editor list. An entry counts when the
-- guild leader sends it, or when an editor passes on a change the guild
-- leader made.
local function trustedEditorEntry(e, sender)
    return ns.IsGuildLeader(sender) or (e.by ~= nil and ns.IsGuildLeader(e.by))
end

-- Merge a list of entry texts from an editor. Returns how many entries changed.
function ns.MergeEntries(entryTexts, sender)
    local data = ns.Data()
    local tables = { base = data.players, rule = data.rules, editor = data.editors, bench = data.bench }
    local changes, rulesChanged, editorsChanged, benchChanged = 0, false, false, false
    for _, entryText in ipairs(entryTexts) do
        local kind, key, e = decode(entryText)
        if kind == "event" then
            if not data.events[key] then
                data.events[key] = e
                changes = changes + 1
            end
        elseif kind then
            local tbl = tables[kind]
            local local_ = tbl[key]
            local trusted = kind ~= "editor" or trustedEditorEntry(e, sender)
            if trusted and (not local_ or (e.t or 0) > (local_.t or 0)) then
                if kind ~= "editor" or not e.by then e.by = sender end
                if kind == "bench" then e.by = nil end
                tbl[key] = e
                changes = changes + 1
                if kind == "rule" then rulesChanged = true end
                if kind == "editor" then editorsChanged = true end
                if kind == "bench" then benchChanged = true end
            end
        end
    end
    if changes > 0 or #entryTexts > 0 then data.started = true end
    if changes > 0 then
        ns.Invalidate()
        if rulesChanged then ns.Fire("RGF_RULES_CHANGED") end
        if editorsChanged then ns.Fire("RGF_EDITORS_CHANGED") end
        if benchChanged then ns.Fire("RGF_BENCH_CHANGED") end
    end
    return changes
end

------------------------------------------------------------------------
-- Sync
--
-- Everyone keeps a copy of the data. A player who wants the newest data
-- sends the digest of his buckets (Q). Editors compare it with their own
-- and send the buckets that differ (a reply). An editor who notices after
-- a reply that he has more than the sender sends his part too, so after
-- one sync everyone online has the same data. New changes are sent to
-- everyone right away (a live transfer).
------------------------------------------------------------------------
local incoming = {}      -- transfers that are still arriving, by sender
local pendingReplies = {} -- replies we plan to send, by request
local live = { events = {}, state = false, base = false, queued = false }
local resyncQueued = false
ns.syncInfo = { at = nil, from = {}, changes = 0 }

local function newNonce()
    return tostring(math.random(100000, 999999))
end

-- Send entries to the guild, cut into pieces that fit in a message.
local function sendTransfer(mode, req, cutoff, parts, digestValue, entryTexts)
    local nonce = newNonce()
    ns.SendComm(table.concat({ "H", nonce, mode, req or "-", cutoff or "-", parts or "-", digestValue or "-" }, SEP), "GUILD", nil, true)
    local textValue = table.concat(entryTexts, ";")
    local size = 230
    local count = 0
    for i = 1, #textValue, size do
        count = count + 1
        ns.SendComm(table.concat({ "D", nonce, count, textValue:sub(i, i + size - 1) }, SEP), "GUILD", nil, true)
    end
    ns.SendComm(table.concat({ "E", nonce, count }, SEP), "GUILD", nil, true)
end

-- Send the buckets listed in keys, with our digest at the cutoff.
local function sendBuckets(mode, req, cutoff, keys)
    local buckets = buildBuckets(cutoff)
    local entryTexts = {}
    for _, key in ipairs(keys) do
        local b = buckets[key]
        if b then
            for _, entryText in ipairs(b.entries) do table.insert(entryTexts, entryText) end
        end
    end
    table.sort(keys)
    sendTransfer(mode, req, cutoff, table.concat(keys, "."), digestOf(buckets), entryTexts)
end

-- Send everything we have to everyone online.
function ns.SendAllData()
    if not (IsInGuild and IsInGuild()) or not ns.CanEdit() or not ns.HasData() then return false end
    sendTransfer("L", "-", "-", "-", "-", allEntries())
    return true
end

-- The Sync button, and the automatic sync. Everyone asks, editors answer.
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
    local cutoff = ns.SyncCutoff()
    ns.SendComm(table.concat({ "Q", newNonce(), cutoff .. "=" .. ns.SyncDigest(cutoff) }, SEP), "GUILD", nil, true)
    if not quiet then ns.Print("syncing with everyone online") end
    ns.After(15, function()
        ns.syncInfo.running = false
        if not quiet then
            local who = {}
            for name in pairs(ns.syncInfo.from) do table.insert(who, ns.ShortName(name)) end
            table.sort(who)
            if #who == 0 then
                ns.Print("sync done, everyone online has the same data")
            else
                ns.Print("sync done with " .. table.concat(who, ", ") .. ", " .. ns.syncInfo.changes .. " changes")
            end
        end
        ns.Fire("RGF_SYNC_DONE")
    end)
    ns.Fire("RGF_SYNC_DONE")
    return true
end

-- A transfer got lost on the way, ask again a bit later.
local function queueResync()
    if resyncQueued then return end
    resyncQueued = true
    ns.After(20 + math.random() * 20, function()
        resyncQueued = false
        ns.Sync(true)
    end)
end

-- New changes of this computer go out right away, a second later, so
-- several changes travel together.
ns.On("RGF_LOCAL_CHANGE", function(what)
    if ns.IsTest() or not ns.CanEdit() then return end
    if type(what) == "table" and what.k then
        table.insert(live.events, what)
    else
        live.state = true
        if type(what) == "table" and what.base then live.base = true end
    end
    if live.queued then return end
    live.queued = true
    ns.After(1, function()
        live.queued = false
        if not (IsInGuild and IsInGuild()) then return end
        local entryTexts = {}
        for _, ev in ipairs(live.events) do
            local entryText = ns.EncodeEvent(ev)
            if entryText then table.insert(entryTexts, entryText) end
        end
        if live.state or live.base then
            local buckets = buildBuckets(0)
            for _, key in ipairs(live.base and { "S", "B" } or { "S" }) do
                for _, entryText in ipairs(buckets[key] and buckets[key].entries or {}) do table.insert(entryTexts, entryText) end
            end
        end
        live.events, live.state, live.base = {}, false, false
        if #entryTexts > 0 then sendTransfer("L", "-", "-", "-", "-", entryTexts) end
    end)
end)

-- Somebody asks. Editors answer with every bucket that differs, also with
-- an empty one, so the asker learns that he has more and sends it.
ns.OnComm("Q", function(text, sender)
    if sender == ns.PlayerName() or not ns.CanEdit() or not ns.HasData() then return end
    local p = ns.Split(text)
    local req = p[2]
    local cutoff, digestValue = (p[3] or ""):match("^(%d+)=(.*)$")
    cutoff = tonumber(cutoff)
    if not req or not cutoff then return end
    local theirs = parseDigest(digestValue)
    local mine = buildBuckets(cutoff)
    local keys = {}
    local seen = {}
    for key, b in pairs(mine) do
        seen[key] = true
        if not same(b, theirs[key]) then table.insert(keys, key) end
    end
    for key, d in pairs(theirs) do
        if not seen[key] and d ~= "0:0" then table.insert(keys, key) end
    end
    if #keys == 0 then return end
    local reply = { keys = keys, cutoff = cutoff }
    pendingReplies[req] = reply
    -- wait a moment, maybe another editor answers with the same data
    ns.After(1 + math.random() * 3, function()
        if pendingReplies[req] == reply then pendingReplies[req] = nil end
        if reply.cancelled then return end
        sendBuckets("R", req, cutoff, keys)
    end)
end)

ns.OnComm("H", function(text, sender)
    if sender == ns.PlayerName() or not ns.IsEditor(sender) then return end
    local p = ns.Split(text)
    local nonce, mode, req, cutoff, parts, digestValue = p[2], p[3], p[4], tonumber(p[5]), p[6], p[7]
    if not nonce then return end
    if incoming[sender] then queueResync() end -- the previous one never finished
    incoming[sender] = {
        nonce = nonce, mode = mode, req = req, cutoff = cutoff, digest = digestValue,
        parts = {}, pieces = {},
    }
    for key in (parts or ""):gmatch("[^%.%-]+") do table.insert(incoming[sender].parts, key) end
    -- another editor answers the same request: if he has what we have, we stay quiet
    local reply = req and pendingReplies[req]
    if reply and cutoff == reply.cutoff then
        local his = parseDigest(digestValue)
        local mine = buildBuckets(cutoff)
        local covered = true
        for _, key in ipairs(reply.keys) do
            if not same(mine[key], his[key]) then covered = false break end
        end
        if covered then reply.cancelled = true end
    end
end)

ns.OnComm("D", function(text, sender)
    local p = ns.SplitWithTail(text, 4)
    local inc = incoming[sender]
    local seq = tonumber(p[3])
    if not inc or inc.nonce ~= p[2] or not seq or not p[4] then return end
    inc.pieces[seq] = p[4]
end)

ns.OnComm("E", function(text, sender)
    local p = ns.Split(text)
    local inc = incoming[sender]
    if not inc or inc.nonce ~= p[2] then return end
    incoming[sender] = nil
    local count = tonumber(p[3]) or 0
    for i = 1, count do
        if not inc.pieces[i] then
            queueResync() -- a piece got lost, ask again later
            return
        end
    end
    local textValue = table.concat(inc.pieces, "", 1, count)
    local entryTexts = {}
    for entryText in textValue:gmatch("[^;]+") do table.insert(entryTexts, entryText) end
    local changes = ns.MergeEntries(entryTexts, sender)
    if changes > 0 then ns.Fire("RGF_DATA_MERGED") end
    ns.syncInfo.from[sender] = true
    ns.syncInfo.changes = (ns.syncInfo.changes or 0) + changes
    ns.syncInfo.last = ns.Now()
    if changes > 0 then ns.RebuildFromRoster() end
    -- after a reply: do we have more in one of the sent buckets than the sender?
    if inc.mode == "R" and inc.cutoff and ns.CanEdit() then
        local his = parseDigest(inc.digest)
        local mine = buildBuckets(inc.cutoff)
        local keys = {}
        for _, key in ipairs(inc.parts) do
            if mine[key] and not same(mine[key], his[key]) then table.insert(keys, key) end
        end
        if #keys > 0 then
            ns.After(2 + math.random() * 3, function() sendBuckets("R", "-", inc.cutoff, keys) end)
        end
    end
    ns.Fire("RGF_POINTS_CHANGED")
    ns.Fire("RGF_SYNC_DONE")
end)

------------------------------------------------------------------------
-- Backup as text, to keep outside the game (Discord, a text file)
------------------------------------------------------------------------
local BACKUP_TAG = "RGFEPGP2"
local OLD_BACKUP_TAG = "RGFEPGP1" -- version 1.7 and older, only starting points and settings

function ns.ExportText()
    local key = ns.GuildKey() or "?"
    return BACKUP_TAG .. ";" .. key .. ";" .. ns.Now() .. ";" .. table.concat(allEntries(), ";")
end

-- Returns the number of changed entries, or nil and a reason.
function ns.ImportText(textValue)
    if not ns.CanEdit() then return nil, "only the guild leader and editors can import" end
    if type(textValue) ~= "string" then return nil, "nothing to import" end
    textValue = textValue:gsub("%s*\n%s*", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local tag, guild, rest = textValue:match("^([^;]+);([^;]*);%d+;?(.*)$")
    if tag ~= BACKUP_TAG and tag ~= OLD_BACKUP_TAG then return nil, "this is not a Red Guild EPGP backup" end
    local key = ns.GuildKey()
    if key and guild ~= key then return nil, "this backup belongs to " .. guild end
    local entryTexts = {}
    for entryText in rest:gmatch("[^;]+") do
        if decode(entryText) then table.insert(entryTexts, entryText) end
    end
    if #entryTexts == 0 then return nil, "the backup is empty" end
    local changes = ns.MergeEntries(entryTexts, ns.PlayerName())
    ns.Data().started = true
    ns.Invalidate()
    ns.RebuildFromRoster()
    ns.Fire("RGF_POINTS_CHANGED")
    if changes > 0 then ns.Sync(true) end
    return changes
end

------------------------------------------------------------------------
-- Automatic backups. The newest three are kept in a second save file, one
-- per character (RedGuildForeverBackup). When the guild data comes back
-- empty, for example because the game did not load the main save file, the
-- newest backup is put back by itself.
------------------------------------------------------------------------
local KEEP = 3
local backupDirty = false
local backupQueued = false

local function backups()
    if type(RedGuildForeverBackup) ~= "table" then RedGuildForeverBackup = {} end
    RedGuildForeverBackup.list = RedGuildForeverBackup.list or {}
    return RedGuildForeverBackup.list
end

local function body(textValue)
    return textValue:match("^[^;]+;[^;]*;%d+;(.*)$") or textValue
end

-- Returns true when a new backup was written.
function ns.AutoBackup(reason)
    if ns.IsTest() or not ns.GuildKey() or not ns.HasData() then return false end
    local list = backups()
    local textValue = ns.ExportText()
    local key = ns.GuildKey()
    for i = #list, 1, -1 do
        if list[i].guild == key then
            if body(list[i].text) == body(textValue) then
                list[i].time = ns.Now() -- nothing changed
                return false
            end
            break
        end
    end
    table.insert(list, { time = ns.Now(), guild = key, text = textValue, reason = reason })
    -- keep the newest few of each guild
    local count = 0
    for i = #list, 1, -1 do
        if list[i].guild == key then
            count = count + 1
            if count > KEEP then table.remove(list, i) end
        end
    end
    backupDirty = false
    return true
end

-- The newest backup of the current guild, or nil
function ns.LatestAutoBackup()
    local key = ns.GuildKey()
    local list = backups()
    for i = #list, 1, -1 do
        if list[i].guild == key then return list[i] end
    end
    return nil
end

-- Put the newest backup back. Works for everyone, members keep a copy too.
function ns.RestoreAutoBackup()
    local b = ns.LatestAutoBackup()
    if not b then return nil end
    local entryTexts = {}
    for entryText in body(b.text):gmatch("[^;]+") do table.insert(entryTexts, entryText) end
    local changes = ns.MergeEntries(entryTexts, ns.PlayerName())
    ns.Invalidate()
    ns.Fire("RGF_POINTS_CHANGED")
    return changes, b
end

-- A backup ten minutes after changes, and when logging out
local function changed()
    backupDirty = true
    if backupQueued then return end
    backupQueued = true
    ns.After(600, function()
        backupQueued = false
        if backupDirty then ns.AutoBackup("changes") end
    end)
end
ns.On("RGF_LOCAL_CHANGE", changed)
ns.On("RGF_DATA_MERGED", changed)
ns.On("PLAYER_LOGOUT", function()
    if backupDirty then ns.AutoBackup("logout") end
end)

-- The save file came back empty: use the newest automatic backup.
function ns.CheckEmptyData()
    if ns.IsTest() or not ns.GuildKey() or ns.HasData() then return end
    local changes, b = ns.RestoreAutoBackup()
    if changes and changes > 0 then
        ns.Print(string.format("the save file had no data. The automatic backup from %s is back (%d entries), sync brings the newest changes",
            date("%d.%m. %H:%M", b.time), changes))
    end
end

------------------------------------------------------------------------
-- Sync in test mode: nothing is sent, a simulated editor sends one change
------------------------------------------------------------------------
function ns.SimulateSync(quiet)
    ns.syncInfo = { at = ns.Now(), from = {}, changes = 0, running = true }
    ns.Fire("RGF_SYNC_DONE")
    ns.After(2, function()
        local editor = "Simulated Editor-" .. ns.MyRealm()
        local raid = ns.RaidMembers()
        local target = raid[math.random(#raid)]
        local main = ns.MainOf(target)
        local ev = { k = "P", id = string.format("%x%06x", ns.Now(), math.random(0, 16777215)), t = ns.Now(), by = editor,
            ch = { { n = main, ep = 25, gp = 0 } }, r = ns.ShortName(main) .. " +25 EP, simulated" }
        local changes = ns.MergeEntries({ ns.EncodeEvent(ev) }, editor)
        ns.syncInfo = { at = ns.syncInfo.at, from = { [editor] = true }, changes = changes, last = ns.Now() }
        ns.RebuildFromRoster()
        ns.Fire("RGF_POINTS_CHANGED")
        ns.Fire("RGF_SYNC_DONE")
        if not quiet then
            local ep = ns.GetPoints(main)
            ns.Print(ns.TEST_TAG .. "sync simulated. A simulated editor sent a change, " .. ns.ShortName(main) .. " now has " .. ep .. " EP. Nothing was sent to anyone")
        end
    end)
end
