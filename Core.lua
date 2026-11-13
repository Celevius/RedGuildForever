-- SPDX-License-Identifier: MIT, see LICENSE
-- Red Guild EPGP for World of Warcraft Forever
-- Core: namespace, settings, name helpers, API compatibility, events.

local ADDON, ns = ...
ns = ns or {}
ns.name = ADDON or "RedGuildForever"
ns.version = "2.1.0"
ns.prefix = "RGFEPGP2" -- addon message prefix, max 16 characters, new for the event sync of 2.0

------------------------------------------------------------------------
-- Guild rules. The defaults match the guild loot rule book. The guild
-- leader and officers change them in the Settings tab, they are saved
-- with the guild data and shared with Sync, so every officer uses the
-- same values. Each rule has its own time stamp, the newest change wins.
------------------------------------------------------------------------
ns.RULES = {
    { section = "Item prices", key = "tier_normal", label = "Item from a normal boss", default = 100, min = 0, max = 100000 },
    { key = "tier_boss", label = "Item from the end boss", default = 150, min = 0, max = 100000 },
    { key = "tier_rare", label = "Very rare item", default = 200, min = 0, max = 100000 },
    { key = "offSpecPercent", label = "Off spec costs, percent of the price", default = 0, min = 0, max = 100 },

    { section = "Slot multipliers", key = "mult_twohand", label = "Two handed weapon", default = 2, min = 0, max = 10, decimal = true },
    { key = "mult_large", label = "One handed weapon, chest, legs, head", default = 1.5, min = 0, max = 10, decimal = true },
    { key = "mult_medium", label = "Shoulders, hands, feet, waist, trinket, ranged", default = 1, min = 0, max = 10, decimal = true },
    { key = "mult_small", label = "Wrist, neck, ring, cloak, off hand, shield, relic", default = 0.75, min = 0, max = 10, decimal = true },
    { key = "mult_noslot", label = "Items without a slot, like tokens", default = 1, min = 0, max = 10, decimal = true },

    { section = "Effort points", key = "raidEP", label = "EP per raid night, raid and bench", default = 100, min = 0, max = 100000 },
    { key = "onTimeEP", label = "EP for being on time, raid and bench", default = 25, min = 0, max = 100000 },
    { key = "minEP", label = "New member until this much EP", default = 300, min = 0, max = 100000 },

    { section = "Gear points and decay", key = "baseGP", label = "Starting GP and lowest possible GP", default = 100, min = 1, max = 100000 },
    { key = "decayPercent", label = "Weekly decay in percent", default = 10, min = 0, max = 100 },

    { section = "Bidding", key = "bidSeconds", label = "Bidding time in seconds", default = 30, min = 10, max = 300 },
}
ns.RULE = {}
for _, r in ipairs(ns.RULES) do ns.RULE[r.key] = r end

-- Personal settings of this player, not shared.
ns.defaults = {
    officerRank = 1,     -- rank index 0 (guild leader) up to this index may change data
    showWinner = true,   -- a short popup with the winner when loot is given out
    autoOpenLoot = false, -- open Start Bidding by itself when an editor loots good items in a group, off by default
    tierOrder = { "normal", "boss", "rare" },
    tierNames = { normal = "Normal boss", boss = "End boss", rare = "Very rare" },
}

-- The value of a guild rule, from the guild data or the default.
function ns.Rule(key)
    local def = ns.RULE[key]
    local rules = ns.Data and ns.Data().rules
    local e = rules and rules[key]
    if e and e.v ~= nil then return e.v end
    return def and def.default
end

function ns.Setting(key)
    if ns.RULE[key] then return ns.Rule(key) end
    if key == "tiers" then
        return { normal = ns.Rule("tier_normal"), boss = ns.Rule("tier_boss"), rare = ns.Rule("tier_rare") }
    end
    local db = RedGuildForeverDB
    if db and db.settings and db.settings[key] ~= nil then
        return db.settings[key]
    end
    return ns.defaults[key]
end

-- Check a typed value. Returns the number, or nil and a reason.
function ns.CheckRule(key, value)
    local def = ns.RULE[key]
    if not def then return nil, "unknown setting " .. tostring(key) end
    local n = tonumber(type(value) == "string" and value:gsub(",", ".") or value)
    if not n then return nil, def.label .. " must be a number" end
    if not def.decimal then n = math.floor(n + 0.5) end
    if n < def.min or n > def.max then
        return nil, string.format("%s must be between %s and %s", def.label, ns.FormatNumber(def.min), ns.FormatNumber(def.max))
    end
    return n
end

function ns.FormatNumber(n)
    if type(n) ~= "number" then return tostring(n) end
    if n == math.floor(n) then return string.format("%d", n) end
    return (string.format("%.2f", n):gsub("0+$", ""):gsub("%.$", ""))
end

-- What off spec costs for an item with this main spec price.
function ns.OffSpecCost(price)
    return math.floor((price or 0) * ns.Rule("offSpecPercent") / 100 + 0.5)
end

function ns.OffSpecText(price)
    local cost = ns.OffSpecCost(price)
    if cost <= 0 then return "off spec is free" end
    return "off spec costs |cffffffff" .. cost .. " GP|r"
end

function ns.SetSetting(key, value)
    RedGuildForeverDB.settings = RedGuildForeverDB.settings or {}
    RedGuildForeverDB.settings[key] = value
end

------------------------------------------------------------------------
-- Output
------------------------------------------------------------------------
local TAG = "|cffc41e3aRed EPGP|r "

function ns.Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(TAG .. tostring(msg))
    else
        print(TAG .. tostring(msg))
    end
end

------------------------------------------------------------------------
-- API compatibility. Forever uses the Mainline API, but some functions
-- moved into C_ namespaces over time, so we look for both.
------------------------------------------------------------------------
local function pick(tbl, key, global)
    if tbl and tbl[key] then return tbl[key] end
    return _G[global]
end

function ns.RequestRoster()
    local f = pick(C_GuildInfo, "GuildRoster", "GuildRoster")
    if f then f() end
end

-- Who may edit is decided in Points.lua (ns.CanEdit)

------------------------------------------------------------------------
-- Test mode. When it is on, the addon works on a separate copy of the data
-- with a simulated raid. Nothing is sent to other players.
------------------------------------------------------------------------
function ns.IsTest()
    local db = RedGuildForeverDB
    return db and db.settings and db.settings.testMode and true or false
end

ns.TEST_TAG = "|cffff8040[Test]|r "

-- the tabs of the main window
ns.TAB = { standings = 1, raid = 2, history = 3, rules = 4, data = 5, settings = 6 }

-- The addon never writes in guild or officer chat, only raid, party and whispers.
local blockedChannels = { GUILD = true, OFFICER = true }

function ns.SendChat(msg, channel, target)
    if blockedChannels[channel] then return false end
    if ns.IsTest() then
        ns.Print(ns.TEST_TAG .. (target and ("whisper to " .. tostring(target) .. ", ") or "") .. msg)
        return true
    end
    local f = pick(C_ChatInfo, "SendChatMessage", "SendChatMessage")
    if not f then return false end
    return pcall(f, msg, channel, nil, target)
end

function ns.ItemInfo(link)
    local f = pick(C_Item, "GetItemInfoInstant", "GetItemInfoInstant")
    if not f or not link then return nil end
    local ok, itemID, _, _, equipLoc, icon = pcall(f, link)
    if not ok then return nil end
    return itemID, equipLoc, icon
end

function ns.After(seconds, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(seconds, fn)
    else
        fn()
    end
end

-- Announce to the raid (or party). Falls back to local chat when solo.
function ns.Announce(msg)
    if ns.IsTest() then
        ns.Print(ns.TEST_TAG .. msg)
        return
    end
    local channel
    if IsInRaid and IsInRaid() then
        channel = "RAID"
    elseif IsInGroup and IsInGroup() then
        channel = "PARTY"
    end
    if channel and ns.SendChat(msg, channel) then return end
    ns.Print(msg)
end

------------------------------------------------------------------------
-- Names. We always store "Name-Realm" internally.
------------------------------------------------------------------------
function ns.MyRealm()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then
        realm = (GetRealmName and GetRealmName() or ""):gsub("[%s%-]", "")
    end
    return realm
end

-- Forever characters have a first and a last name, for example "Cel Dru".
-- Names keep their space. Each word starts with a capital letter, letters
-- with accents stay as they are.
local function capitalize(name)
    return (name:gsub("(%S)(%S*)", function(first, rest)
        if first:match("%a") then return first:upper() .. rest end
        return first .. rest
    end))
end

-- Clean up spacing: no space at the start or end, one space between words.
function ns.CleanName(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if name == "" then return nil end
    return name
end

-- Split "Cel Dru-Forever" into "Cel Dru" and "Forever".
-- Realm names never contain spaces, so only a last part without spaces counts.
function ns.SplitRealm(name)
    local short, realm = name:match("^(.-)%s*%-%s*([^%s%-]+)$")
    if short and short ~= "" then return short, realm end
    return name, nil
end

function ns.FullName(name)
    name = ns.CleanName(name)
    if not name then return nil end
    local short, realm = ns.SplitRealm(name)
    realm = realm or ns.MyRealm()
    short = capitalize(short)
    if realm and realm ~= "" then
        return short .. "-" .. realm
    end
    return short
end

function ns.ShortName(full)
    if not full then return "?" end
    local short, realm = ns.SplitRealm(full)
    if realm == nil or realm == ns.MyRealm() then return short end
    return full
end

-- Realms the game knows (our realm and connected realms), to tell a realm
-- apart from a last name.
function ns.IsKnownRealm(part)
    if not part or part == "" then return false end
    if part == ns.MyRealm() then return true end
    if GetAutoCompleteRealms then
        local ok, realms = pcall(GetAutoCompleteRealms)
        if ok and type(realms) == "table" then
            for _, r in ipairs(realms) do if r == part then return true end end
        end
    end
    return false
end

-- The full name of a unit. Forever returns the first name and the last name
-- ("Cel", "Dru") where other clients return the name and the realm, so the
-- second value is only treated as a realm when it really is one.
function ns.UnitFullName(unit)
    local name, second = UnitName(unit)
    if type(name) ~= "string" or name == "" then return nil end
    if type(second) ~= "string" or second == "" then
        if ns.Resolve then return ns.Resolve(name) end
        return ns.FullName(name)
    end
    local asLastName = name .. " " .. second
    local asRealm = name .. "-" .. second
    if ns.FindMember then
        local hit = ns.FindMember(asLastName)
        if hit then return hit end
    end
    if unit ~= "player" and ns.IsKnownRealm(second) then
        if ns.Resolve then return ns.Resolve(asRealm) end
        return ns.FullName(asRealm)
    end
    if ns.Resolve then return ns.Resolve(asLastName) end
    return ns.FullName(asLastName)
end

function ns.PlayerName()
    return ns.UnitFullName("player")
end

------------------------------------------------------------------------
-- Formatting
------------------------------------------------------------------------
function ns.Round(x)
    return math.floor(x + 0.5)
end

function ns.FormatPR(pr)
    return string.format("%.2f", pr or 0)
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
ns.handlers = {}

function ns.On(event, fn)
    ns.handlers[event] = ns.handlers[event] or {}
    table.insert(ns.handlers[event], fn)
    -- RGF_ events are our own signals, only real game events get registered
    if ns.eventFrame and not event:match("^RGF_") then
        local ok = pcall(ns.eventFrame.RegisterEvent, ns.eventFrame, event)
        if not ok then ns.Print("this client does not know the event " .. event) end
    end
end

function ns.Fire(event, ...)
    local list = ns.handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then ns.Print("|cffff5555error|r " .. tostring(err)) end
    end
end

if CreateFrame then
    ns.eventFrame = CreateFrame("Frame")
    ns.eventFrame:SetScript("OnEvent", function(_, event, ...) ns.Fire(event, ...) end)
    ns.eventFrame:RegisterEvent("ADDON_LOADED")
end

ns.On("ADDON_LOADED", function(name)
    if name ~= ns.name then return end
    RedGuildForeverDB = RedGuildForeverDB or {}
    RedGuildForeverDB.log = RedGuildForeverDB.log or {}
    RedGuildForeverDB.priceOverrides = RedGuildForeverDB.priceOverrides or {}
    ns.Fire("RGF_READY")
end)

-- Expose for debugging and tests
_G.RedGuildForever = ns
return ns
