-- Communication between addon users.
--
-- Messages use "^" as separator, because item links contain "|".
--   SR                      ask officers for standings (GUILD)
--   SB^n / SD^n^data / SE^n standings begin, data, end (GUILD)
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
    -- players who cannot read officer notes ask for standings
    ns.After(8, function()
        if IsInGuild and IsInGuild() and not ns.CanViewNotes() then
            ns.SendComm("SR", "GUILD")
        end
    end)
end)

ns.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix ~= ns.prefix or type(text) ~= "string" then return end
    local kind = text:match("^(%a+)")
    local fn = kind and ns.commHandlers[kind]
    if fn then fn(text, ns.FullName(sender), channel) end
end)

------------------------------------------------------------------------
-- Standings sync
------------------------------------------------------------------------
local incoming = {}
local lastBroadcastSeen = 0
local broadcastQueued = false

local function encodeStandings()
    local entries = {}
    for full, m in pairs(ns.members) do
        if m.main then
            table.insert(entries, ns.ShortName(full) .. ">" .. ns.ShortName(m.main))
        elseif m.hasPoints then
            table.insert(entries, string.format("%s,%d,%d", ns.ShortName(full), m.ep, m.gp))
        end
    end
    table.sort(entries)
    return entries
end

function ns.BroadcastStandings()
    if not (IsInGuild and IsInGuild()) or not ns.CanViewNotes() then return false end
    local nonce = tostring(math.random(100000, 999999))
    local entries = encodeStandings()
    ns.SendComm("SB" .. SEP .. nonce, "GUILD")
    local chunk = {}
    local size = 0
    local function flush()
        if #chunk > 0 then
            ns.SendComm("SD" .. SEP .. nonce .. SEP .. table.concat(chunk, ";"), "GUILD")
            chunk, size = {}, 0
        end
    end
    for _, e in ipairs(entries) do
        if size + #e + 1 > 230 then flush() end
        table.insert(chunk, e)
        size = size + #e + 1
    end
    flush()
    ns.SendComm("SE" .. SEP .. nonce, "GUILD")
    return true
end

-- Send standings a few seconds after a change, so several changes go out once.
function ns.QueueBroadcast(delay)
    if broadcastQueued then return end
    broadcastQueued = true
    ns.After(delay or 5, function()
        broadcastQueued = false
        ns.BroadcastStandings()
    end)
end

ns.On("RGF_LOCAL_CHANGE", function() ns.QueueBroadcast(5) end)

ns.OnComm("SR", function(_, sender)
    if not ns.CanViewNotes() or sender == ns.PlayerName() then return end
    -- several officers may be online, wait a random moment and skip if someone else answered
    local asked = GetTime and GetTime() or 0
    ns.After(1 + math.random() * 4, function()
        if lastBroadcastSeen > asked then return end
        ns.QueueBroadcast(0)
    end)
end)

ns.OnComm("SB", function(text, sender)
    local p = ns.Split(text)
    if not ns.IsOfficer(sender) then return end
    lastBroadcastSeen = GetTime and GetTime() or 0
    incoming[sender] = { nonce = p[2], points = {}, alts = {} }
end)

ns.OnComm("SD", function(text, sender)
    local p = ns.SplitWithTail(text, 3)
    local inc = incoming[sender]
    if not inc or inc.nonce ~= p[2] or not p[3] then return end
    for entry in p[3]:gmatch("[^;]+") do
        local alt, main = entry:match("^(.-)>(.+)$")
        if alt then
            inc.alts[ns.FullName(alt)] = ns.FullName(main)
        else
            local name, ep, gp = entry:match("^(.-),(%-?%d+),(%d+)$")
            if name then
                inc.points[ns.FullName(name)] = { ep = tonumber(ep), gp = tonumber(gp) }
            end
        end
    end
end)

ns.OnComm("SE", function(text, sender)
    local p = ns.Split(text)
    local inc = incoming[sender]
    if not inc or inc.nonce ~= p[2] then return end
    incoming[sender] = nil
    if ns.CanViewNotes() then return end -- we read notes ourselves
    ns.synced = { points = inc.points, alts = inc.alts, from = sender, at = time and time() or 0 }
    ns.Fire("RGF_POINTS_CHANGED")
end)
