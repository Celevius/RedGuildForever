-- SPDX-License-Identifier: MIT, see LICENSE
-- Whisper commands, so players without the addon can look up points too.
--   !ep          your own points and place
--   !ep Name     the points of another player
--   !bid         what is open for bids right now
--   !top         the five highest priorities, !top mage for one class
--   !loot        the items you got lately, !loot Name for another player
--   !help        this list
-- Every addon user with data answers, so a raider can whisper anyone who has it.
-- Bids by whisper (ms, os, pass) are handled in Auction.lua.

local _, ns = ...
ns = ns or _G.RedGuildForever

local lastAnswer = {} -- sender -> GetTime, one answer every two seconds per player

local function reply(target, lines)
    for i, line in ipairs(lines) do
        if i > 5 then break end
        ns.SendChat(line, "WHISPER", target)
    end
end

-- The place of a main in the standings, and how many have points
local function place(main)
    local list = ns.Standings(false)
    for i, e in ipairs(list) do
        if e.name == main then return i, #list end
    end
    return nil, #list
end

function ns.PointsText(full)
    local ep, gp, pr, main = ns.GetPoints(full)
    local line = string.format("%s: %d EP, %d GP, priority %s", ns.ShortName(full), ep, gp, ns.FormatPR(pr))
    local at, of = place(main)
    if at then line = line .. string.format(", place %d of %d", at, of) end
    if main ~= full then line = line .. ", uses the points of " .. ns.ShortName(main) end
    if ep < ns.Setting("minEP") then line = line .. ". New member until " .. ns.Setting("minEP") .. " EP" end
    return line .. "."
end

-- A typed name, or nil and the answer why it did not work
local function whom(sender, arg)
    if not arg or arg == "" then return ns.Resolve(sender) end
    local full, matches = ns.FindMember(arg, true)
    if full then return full end
    if matches then
        local short = {}
        for i, m in ipairs(matches) do
            if i > 5 then break end
            table.insert(short, ns.ShortName(m))
        end
        return nil, "More than one player matches " .. arg .. ": " .. table.concat(short, ", ") .. "."
    end
    return nil, "Nobody in the guild is called " .. arg .. "."
end

-- "mage", "Mages", "death knight" to the class token of the roster
local function classToken(word)
    local w = word:lower():gsub("%s", ""):gsub("s$", "")
    for _, m in pairs(ns.members) do
        if m.class and m.class:lower() == w then return m.class end
    end
    return nil
end

local commands = {}

commands.ep = function(sender, arg)
    local full, err = whom(sender, arg)
    if not full then return { err } end
    return { ns.PointsText(full) }
end
commands.points = commands.ep
commands.prio = commands.ep

commands.bid = function()
    local open = ns.OpenAuctions()
    if #open > 0 then
        local lines = {}
        for _, a in ipairs(open) do
            local left = math.max(0, math.floor((a.endsAt or 0) - (GetTime and GetTime() or 0)))
            table.insert(lines, string.format("%s%s for %d GP, %d seconds left.", #open > 1 and ((a.n or 1) .. ". ") or "", a.link, a.price, left))
        end
        if #open > 1 then
            table.insert(lines, "Whisper me ms, os or pass with the number, for example ms " .. (open[1].n or 1) .. ".")
        else
            table.insert(lines, "Whisper me ms, os or pass.")
        end
        return lines
    end
    -- another loot master runs it, we know it from the raid
    local me = ns.PlayerName()
    for _, inc in pairs(ns.incoming) do
        if inc.owner ~= me then
            return { string.format("%s is open for %d GP with %s. Whisper %s ms, os or pass.",
                inc.link, inc.price or 0, ns.ShortName(inc.owner), ns.ShortName(inc.owner)) }
        end
    end
    return { "No bidding is open right now." }
end

commands.top = function(_, arg)
    local class = arg ~= "" and classToken(arg) or nil
    if arg ~= "" and not class then return { "I do not know the class " .. arg .. "." } end
    local parts = {}
    for _, e in ipairs(ns.Standings(false)) do
        if not class or e.class == class then
            table.insert(parts, string.format("%d. %s %s", #parts + 1, ns.ShortName(e.name), ns.FormatPR(e.pr)))
            if #parts == 5 then break end
        end
    end
    if #parts == 0 then return { "Nobody has points yet." } end
    return { "Top " .. #parts .. (class and (" " .. arg:lower()) or "") .. ": " .. table.concat(parts, ", ") }
end

commands.loot = function(sender, arg)
    local full, err = whom(sender, arg)
    if not full then return { err } end
    local items = ns.LootOf and ns.LootOf(full, 5) or {}
    if #items == 0 then return { ns.ShortName(full) .. " got no items yet." } end
    local parts = {}
    for _, l in ipairs(items) do
        table.insert(parts, string.format("%s %s %d GP", date("%d.%m.", l.time), l.label or "?", l.gp or 0))
    end
    return { ns.ShortName(full) .. ": " .. table.concat(parts, ", ") }
end

commands.help = function()
    return {
        "Whisper !ep for your points, !ep Name for another player, !bid for open items, !top or !top mage for the best priorities, !loot for your items.",
        "While bidding is open whisper the loot master ms, os or pass.",
    }
end

ns.whisperCommands = commands

ns.On("CHAT_MSG_WHISPER", function(text, sender)
    if type(text) ~= "string" or ns.IsTest() or not ns.HasData() then return end
    local ok, cmd, arg = pcall(function()
        local c, a = text:match("^%s*!(%a+)%s*(.-)%s*$")
        return c and c:lower(), a
    end)
    if not ok or not cmd or not commands[cmd] then return end
    local now = GetTime and GetTime() or 0
    if lastAnswer[sender] and now - lastAnswer[sender] < 2 then return end
    lastAnswer[sender] = now
    reply(sender, commands[cmd](sender, arg or ""))
end)
