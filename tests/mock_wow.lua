-- SPDX-License-Identifier: MIT, see LICENSE
-- A small fake of the WoW API, enough to run the addon logic outside the game.
-- Run from the repository root with: lua5.1 tests/run.lua

local M = {}

M.realm = "Forever"
M.player = "Cel Dru"
M.chat = {}       -- messages sent with SendChatMessage
M.comms = {}      -- addon messages sent
M.printed = {}
M.now = 1000
M.timers = {}
M.raid = {}
M.inRaid = false
M.canEdit = true
M.canView = true
M.server = 1760000000   -- server time, tests move it forward
M.guildName = "Redemption"
M.guildInfo = ""

-- guild roster rows: { name, rankIndex, officerNote, classFile }
M.roster = {}

function M.reset()
    M.chat, M.comms, M.printed, M.timers = {}, {}, {}, {}
    M.context, M.switch, M.blockAddon = nil, nil, nil
end

-- run every queued timer in the order of their delay, timers can add timers.
-- GetTime moves forward to each timer, like the game clock would.
-- With several computers (M.switch), a timer runs on the computer that made it.
function M.flush()
    local active = M.context
    for _ = 1, 5000 do
        if #M.timers == 0 then break end
        local best = 1
        for i, t in ipairs(M.timers) do
            if t.due < M.timers[best].due or (t.due == M.timers[best].due and t.seq < M.timers[best].seq) then
                best = i
            end
        end
        local t = table.remove(M.timers, best)
        if t.due > M.now then M.now = t.due end
        if t.ctx and M.switch then M.switch(t.ctx) end
        t.fn()
    end
    if active and M.switch then M.switch(active) end
end
M.seq = 0

-- the real client throws on events it does not know, so we do too
M.knownEvents = {
    ADDON_LOADED = true, GUILD_ROSTER_UPDATE = true, PLAYER_GUILD_UPDATE = true,
    CHAT_MSG_ADDON = true, CHAT_MSG_SYSTEM = true, CHAT_MSG_WHISPER = true,
    LOOT_OPENED = true, LOOT_SLOT_CLEARED = true, LOOT_CLOSED = true,
    PLAYER_LOGOUT = true, GROUP_ROSTER_UPDATE = true,
}
M.registered = {}

-- A fake frame. Unknown fields return another fake frame, so template
-- children like frame.Inset or frame.TitleContainer exist, and calling a
-- fake returns a fake. Show, Hide and scripts behave like the game.
local frameStub
local methods = {}

local function scripts(t, name)
    local all = rawget(t, "_scripts")
    if not all then all = {} rawset(t, "_scripts", all) end
    all[name] = all[name] or {}
    return all[name]
end

local function run(t, name, ...)
    for _, fn in ipairs(scripts(t, name)) do fn(t, ...) end
end

function methods.RegisterEvent(t, event)
    if not M.knownEvents[event] then
        error('Attempt to register unknown event "' .. tostring(event) .. '"')
    end
    M.registered[event] = true
end
function methods.IsShown(t) return rawget(t, "_shown") ~= false end
function methods.IsVisible(t) return methods.IsShown(t) end
function methods.Show(t)
    local was = methods.IsShown(t)
    rawset(t, "_shown", true)
    if not was then run(t, "OnShow") end
end
function methods.Hide(t)
    local was = methods.IsShown(t)
    rawset(t, "_shown", false)
    if was then run(t, "OnHide") end
end
function methods.SetShown(t, show) if show then methods.Show(t) else methods.Hide(t) end end
function methods.SetScript(t, name, fn)
    local list = scripts(t, name)
    for i = #list, 1, -1 do list[i] = nil end
    if fn then list[1] = fn end
end
function methods.HookScript(t, name, fn) table.insert(scripts(t, name), fn) end
function methods.GetScript(t, name) return scripts(t, name)[1] end
function methods.SetID(t, id) rawset(t, "_id", id) end
function methods.GetID(t) return rawget(t, "_id") or 0 end
function methods.SetChecked(t, v) rawset(t, "_checked", v and true or false) end
function methods.GetChecked(t) return rawget(t, "_checked") or false end
function methods.SetText(t, v) rawset(t, "_text", v) end
function methods.GetText(t) return rawget(t, "_text") end
function methods.Click(t) run(t, "OnClick") end
function methods.HasFocus(t) return rawget(t, "_focus") or false end
function methods.SetFocus(t) rawset(t, "_focus", true) end
function methods.ClearFocus(t) rawset(t, "_focus", false) end
function methods.IsEnabled(t) return rawget(t, "_enabled") ~= false end
function methods.SetEnabled(t, v) rawset(t, "_enabled", v and true or false) end

frameStub = function()
    return setmetatable({}, {
        __index = function(t, k)
            if methods[k] then return methods[k] end
            local child = frameStub()
            rawset(t, k, child)
            return child
        end,
        __call = function() return frameStub() end,
    })
end
M.frameStub = frameStub

function M.install()
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.GetTime = function() return M.now end
    _G.time = os.time
    _G.date = os.date
    -- M.units holds the two values UnitName returns, like Forever does:
    -- { "Cel", "Dru" } for first and last name, or { "Name", "Realm" } elsewhere
    M.units = M.units or {}
    _G.UnitName = function(unit)
        local u = M.units[unit]
        if u then return u[1], u[2] end
        if unit == "player" then return M.player end
    end
    _G.GetAutoCompleteRealms = function() return M.realms or { M.realm } end
    _G.UnitIsPlayer = function() return true end
    _G.GetNormalizedRealmName = function() return M.realm end
    _G.GetRealmName = function() return M.realm end
    _G.IsInGuild = function() return true end
    _G.IsInRaid = function() return M.inRaid end
    _G.IsInGroup = function() return M.inRaid end
    _G.GetNumGroupMembers = function() return #M.raid end
    _G.GetRaidRosterInfo = function(i) return M.raid[i] end
    _G.GetNumGuildMembers = function() return #M.roster end
    _G.GetGuildRosterInfo = function(i)
        local r = M.roster[i]
        if not r then return nil end
        -- name, rankName, rankIndex, level, class, zone, publicNote, officerNote, online, status, classFile
        return r[1] .. "-" .. M.realm, "Rank", r[2], 60, r[4], "Zone", "", M.canView and r[3] or "", true, 0, r[4]
    end
    _G.GuildRosterSetOfficerNote = function()
        error("the addon must not write officer notes anymore")
    end
    _G.GetGuildInfo = function(unit)
        if unit ~= "player" then return nil end
        local rank = M.rank or (M.canEdit and 0 or 5)
        return M.guildName, "Rank " .. rank, rank, M.realm
    end
    _G.GetGuildInfoText = function() return M.guildInfo end
    _G.GetServerTime = function() return M.server end
    M.loot, M.cursor = {}, nil
    _G.GetNumLootItems = function() return #M.loot end
    _G.GetLootSlotLink = function(i) return M.loot[i] and M.loot[i].link end
    _G.GetLootSlotInfo = function(i)
        local l = M.loot[i]
        if not l then return nil end
        return 12345, "Item", 1, nil, l.quality
    end
    _G.GetCursorInfo = function()
        if M.cursor then return "item", 1, M.cursor end
        return nil
    end
    _G.ClearCursor = function() M.cursor = nil end
    _G.C_GuildInfo = {
        GuildRoster = function() end,
        CanEditOfficerNote = function() return M.canEdit end,
        CanViewOfficerNote = function() return M.canView end,
    }
    _G.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function(prefix, msg, channel, target)
            assert(#msg <= 255, "addon message too long")
            if M.blockAddon then return 9 end -- like a blocked message in an instance
            table.insert(M.comms, { prefix = prefix, msg = msg, channel = channel, target = target, from = M.context })
            return 0
        end,
        SendChatMessage = function(msg, channel, _, target)
            table.insert(M.chat, { msg = msg, channel = channel, target = target })
        end,
    }
    _G.C_Item = {
        GetItemInfoInstant = function(link)
            local id = tonumber(link:match("item:(%d+)"))
            if not id then return nil end
            local slot = M.itemSlots and M.itemSlots[id] or "INVTYPE_HAND"
            return id, "Armor", "Plate", slot, 12345
        end,
    }
    _G.C_Timer = {
        After = function(delay, fn)
            M.seq = M.seq + 1
            table.insert(M.timers, { due = M.now + (delay or 0), seq = M.seq, fn = fn, ctx = M.context })
        end,
        NewTicker = function() return {} end,
    }
    _G.RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(M.printed, msg) end }
    _G.CreateFrame = function() return frameStub() end
    _G.UIParent = frameStub()
    _G.Minimap = frameStub()
    _G.GetCursorPosition = function() return 0, 0 end
    _G.MenuUtil = M.menuUtil
    _G.UISpecialFrames = {}
    _G.GameTooltip = frameStub()
    _G.StaticPopupDialogs = {}
    _G.StaticPopup_Show = function(which) M.popup = which end
    _G.SlashCmdList = {}
    _G.RedGuildForeverDB = nil
    _G.RedGuildForeverBackup = nil
end

-- load the files in the order the toc file lists them, like the game does
function M.tocFiles()
    local files = {}
    for line in io.lines("RedGuildForever.toc") do
        if line:match("%.lua%s*$") then table.insert(files, (line:gsub("%s+$", ""))) end
    end
    return files
end

function M.load(ns)
    for _, file in ipairs(M.tocFiles()) do
        local chunk = assert(loadfile(file))
        chunk("RedGuildForever", ns)
    end
    ns.Fire("ADDON_LOADED", "RedGuildForever")
    M.flush()
end

function M.link(id, name)
    return "|cffa335ee|Hitem:" .. id .. "::::::::60:::::|h[" .. name .. "]|h|r"
end

-- deliver every addon message sent so far to the addon, as if the server echoed it
function M.deliver(ns, sender)
    local list = M.comms
    M.comms = {}
    for _, c in ipairs(list) do
        ns.Fire("CHAT_MSG_ADDON", c.prefix, c.msg, c.channel, (sender or M.player) .. "-" .. M.realm)
    end
end

return M
