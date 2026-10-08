-- Red Guild EPGP for World of Warcraft Forever
-- Core: namespace, settings, name helpers, API compatibility, events.

local ADDON, ns = ...
ns = ns or {}
ns.name = ADDON or "RedGuildForever"
ns.version = "1.2.0"
ns.prefix = "RGFEPGP" -- addon message prefix, max 16 characters

------------------------------------------------------------------------
-- Settings. These match the guild loot rule book.
-- They are hardcoded on purpose: the Forever beta does not reliably load
-- SavedVariables on login, so every officer gets the same values.
------------------------------------------------------------------------
ns.defaults = {
    baseGP = 100,        -- everyone starts with 100 GP, GP never decays below this
    minEP = 300,         -- new members below this EP lose to members above it
    decayPercent = 10,   -- weekly decay of EP and GP
    raidEP = 100,        -- EP per raid night (raid and bench)
    onTimeEP = 25,       -- bonus for being on time (raid and bench)
    officerRank = 1,     -- rank index 0 (Guild Master) up to this index may run auctions and send standings
    bidSeconds = 30,     -- how long bidding stays open
    tiers = {            -- base GP depending on where the item drops
        normal = 100,
        boss = 150,
        rare = 200,
    },
    tierOrder = { "normal", "boss", "rare" },
    tierNames = { normal = "Normal boss", boss = "End boss", rare = "Very rare" },
}

function ns.Setting(key)
    local db = RedGuildForeverDB
    if db and db.settings and db.settings[key] ~= nil then
        return db.settings[key]
    end
    return ns.defaults[key]
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

function ns.CanEditNotes()
    local f = pick(C_GuildInfo, "CanEditOfficerNote", "CanEditOfficerNote")
    return f and f() and true or false
end

function ns.CanViewNotes()
    local f = pick(C_GuildInfo, "CanViewOfficerNote", "CanViewOfficerNote")
    return f and f() and true or false
end

function ns.SendChat(msg, channel, target)
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

function ns.PlayerName()
    local name, realm = UnitName("player")
    if realm and realm ~= "" then name = name .. "-" .. realm end
    -- the guild roster knows the full name, use it when the game gives us less
    if ns.Resolve then return ns.Resolve(name) end
    return ns.FullName(name)
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
    RedGuildForeverDB.bench = RedGuildForeverDB.bench or {}
    ns.Fire("RGF_READY")
end)

-- Expose for debugging and tests
_G.RedGuildForever = ns
return ns
