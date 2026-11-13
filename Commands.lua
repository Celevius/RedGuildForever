-- SPDX-License-Identifier: MIT, see LICENSE
-- Slash commands. /rgf help lists them.

local _, ns = ...
ns = ns or _G.RedGuildForever

local function words(line)
    local list = {}
    for w in line:gmatch("%S+") do table.insert(list, w) end
    return list
end

local function itemLink(line)
    return line:match("(|c.-|h|r)") or line:match("(|H.-|h.-|h)")
end

-- Find the guild member someone typed, and explain when it does not work.
local function typedMember(name)
    local full, matches = ns.FindMember(name, true)
    if full then return full end
    if matches then
        local short = {}
        for i, m in ipairs(matches) do
            if i > 6 then table.insert(short, "...") break end
            table.insert(short, ns.ShortName(m))
        end
        ns.Print("more than one player matches " .. name .. ", " .. table.concat(short, ", ") .. ". Type more of the name")
    else
        ns.Print("nobody in the guild is called " .. (name or "?"))
    end
    return nil
end

ns.TypedMember = typedMember

local function joinWords(w, from, to)
    local parts = {}
    for i = from, to or #w do table.insert(parts, w[i]) end
    return table.concat(parts, " ")
end

-- "/rgf alt Cel Rog Cel Dru" has no clear split, so we try every split and
-- keep the one where both sides are guild members. A comma always works.
local function twoMembers(w, from)
    local line = joinWords(w, from)
    local left, right = line:match("^(.-)%s*,%s*(.+)$")
    if left then return typedMember(left), typedMember(right) end
    local found
    for i = from, #w - 1 do
        local a = ns.FindMember(joinWords(w, from, i), true)
        local b = ns.FindMember(joinWords(w, i + 1), true)
        if a and b then
            if found then
                ns.Print("not sure where the first name ends, put a comma between the two names")
                return nil
            end
            found = { a, b }
        end
    end
    if found then return found[1], found[2] end
    ns.Print("could not find both players, put a comma between the two names, for example /rgf alt Cel Rog, Cel Dru")
    return nil
end

local function needOfficer()
    if ns.CanEdit() then return true end
    ns.Print("only the guild leader and editors can do that")
    return false
end

local help = {
    "/rgf  open the standings",
    "/rgf me  show your own points",
    "/rgf minimap  show or hide the minimap button",
    "/rgf check Cel Dru  show the points of a player, the first name is enough if it is clear",
    "/rgf rebid  show the bid popup again to change your bid while bidding is open",
    "|cffffd100Loot master|r",
    "/rgf bid  open the Start Bidding window, or /rgf bid [item] to start right away",
    "/rgf test  turn test mode on or off, try everything alone",
    "/rgf settings  open the settings in the game's Options",
    "/rgf rules  open the guild rules in the game's Options",
    "/rgf bid [item] boss  same, priced as an end boss item (or rare)",
    "|cffffd100Editors|r",
    "/rgf edit Cel Dru  open the editor for a player, or your target without a name",
    "/rgf start  start the raid, gives the on time EP and starts the loot list",
    "/rgf end  end the raid, gives the raid EP",
    "/rgf loot  the loot of the raid, or /rgf loot Cel Dru for the items of a player",
    "/rgf raid  give raid EP to the raid and the bench",
    "/rgf ontime  give the on time bonus to the raid and the bench",
    "/rgf bench  open the bench, or /rgf bench add Cel Dru, remove Cel Dru, clear",
    "/rgf ep Cel Dru 50  give or take EP (use a minus to take)",
    "/rgf gp Cel Dru 100  give or take GP",
    "/rgf alt Cel Rog, Cel Dru  link the alt Cel Rog to the main Cel Dru",
    "/rgf unalt Cel Rog  make an alt a main again",
    "/rgf decay  weekly decay",
    "/rgf undo  undo your newest change, also one from an earlier day. The History tab can undo any change",
    "/rgf price [item] 250  fixed price for an item, or clear",
    "/rgf sync  sync the data with everyone online",
    "/rgf export  open the Sync tab with backup export and import",
    "/rgf log  show the last changes",
    "/rgf check  check that this game version has everything the addon needs",
    "/rgf discord  the standings as text for Discord, with the search and class of the window",
    "|cffffd100Guild leader|r",
    "/rgf editors  show who may change data",
    "/rgf editor add Cel Dru  let a player change data, any guild rank works",
    "/rgf editor remove Cel Dru  take it away again",
}

local function pointsLine(name)
    local ep, gp, pr, main = ns.GetPoints(name)
    local line = string.format("%s has %d EP, %d GP, priority %s", ns.ShortName(name), ep, gp, ns.FormatPR(pr))
    if main and main ~= ns.Resolve(name) then line = line .. " (points of " .. ns.ShortName(main) .. ")" end
    if ep < ns.Setting("minEP") then line = line .. ", new member" end
    return line
end

-- kind is "raid" or "ontime", each player gets it once per raid night
local function awardGroup(amount, label, kind)
    if not needOfficer() then return end
    ns.AwardGroup(amount, label, kind)
end

------------------------------------------------------------------------
-- /rgf check: is everything the addon uses there in this game version?
-- Prints a short report to paste into a bug report.
------------------------------------------------------------------------
local NEEDED = {
    "CreateFrame", "GetTime", "GetServerTime", "UnitName", "UnitIsPlayer", "IsInGuild", "IsInRaid", "IsInGroup",
    "GetNumGroupMembers", "GetRaidRosterInfo", "GetNumGuildMembers", "GetGuildRosterInfo", "GetGuildInfo",
    "GetGuildInfoText", "GetNormalizedRealmName", "GetNumLootItems", "GetLootSlotLink", "GetLootSlotInfo",
    "GetCursorInfo", "ClearCursor", "StaticPopup_Show", "StaticPopupDialogs",
    "C_ChatInfo.SendAddonMessage", "C_ChatInfo.RegisterAddonMessagePrefix", "C_ChatInfo.SendChatMessage|SendChatMessage",
    "C_Timer.After", "C_Timer.NewTicker", "C_Item.GetItemInfoInstant|GetItemInfoInstant",
    "C_GuildInfo.GuildRoster|GuildRoster",
}
-- without these the addon still works, something small is missing
local NICE = {
    "MenuUtil.CreateContextMenu", "Settings.RegisterCanvasLayoutCategory", "Settings.RegisterAddOnCategory",
    "C_ChatInfo.InChatMessagingLockdown", "C_ClassColor.GetClassColor|RAID_CLASS_COLORS", "C_Item.GetItemQualityByID",
    "GetAutoCompleteRealms", "GetInventoryItemLink", "PlaySound", "SOUNDKIT", "RANDOM_ROLL_RESULT",
    "LOCALIZED_CLASS_NAMES_MALE", "HandleModifiedItemClick", "SetItemButtonTexture",
}

local function exists(path)
    local value = _G
    for part in path:gmatch("[^%.]+") do
        if type(value) ~= "table" then return false end
        value = value[part]
    end
    return value ~= nil
end

-- "A|B" is fine when one of the two is there
local function missing(list)
    local gone = {}
    for _, entry in ipairs(list) do
        local found = false
        for path in entry:gmatch("[^|]+") do
            if exists(path) then found = true end
        end
        if not found then table.insert(gone, (entry:gsub("|", " or "))) end
    end
    return gone
end

-- Returns the missing needed and the missing optional functions.
function ns.SelfCheck()
    local version, build, _, interface = "?", "?", nil, nil
    if GetBuildInfo then version, build, _, interface = GetBuildInfo() end
    ns.Print(string.format("Red Guild EPGP %s, game %s (build %s, interface %s)", ns.version, tostring(version), tostring(build), tostring(interface)))
    local needed, nice = missing(NEEDED), missing(NICE)
    if #needed == 0 then
        ns.Print("|cff40ff40all " .. #NEEDED .. " game functions the addon needs are there|r")
    else
        ns.Print("|cffff5555missing, the addon cannot work fully:|r " .. table.concat(needed, ", "))
    end
    if #nice > 0 then ns.Print("missing, small things do not work: " .. table.concat(nice, ", ")) end
    local data = ns.Data()
    local players, changes = 0, 0
    for _ in pairs(ns.Players()) do players = players + 1 end
    for _ in pairs(data.events or {}) do changes = changes + 1 end
    ns.Print(string.format("guild %s, %s, %d players, %d changes, %d sync messages waiting%s",
        tostring(ns.GuildKey() or "none"), ns.CanEdit() and "you can edit" or "you cannot edit", players, changes,
        ns.QueuedMessages(), ns.IsTest() and ", test mode is on" or ""))
    return needed, nice
end

function ns.Command(line)
    line = line or ""
    local w = words(line)
    local cmd = (w[1] or ""):lower()

    if cmd == "" or cmd == "show" or cmd == "standings" then
        ns.ToggleStandings()

    elseif cmd == "help" then
        for _, l in ipairs(help) do ns.Print(l) end

    elseif cmd == "me" then
        ns.Print(pointsLine(ns.PlayerName()))

    elseif cmd == "check" and w[2] then
        local full = typedMember(joinWords(w, 2))
        if full then ns.Print(pointsLine(full)) end

    elseif cmd == "bid" or cmd == "auction" then
        local link = itemLink(line)
        if not link then
            ns.OpenPicker()
            return
        end
        local after = line:sub((line:find(link, 1, true) or 0) + #link):lower()
        local tier = after:match("boss") and "boss" or (after:match("rare") and "rare" or "normal")
        ns.StartAuction(link, tier)

    elseif cmd == "start" then
        ns.StartRaid()

    elseif cmd == "end" then
        ns.EndRaid()

    elseif cmd == "loot" then
        if w[2] then
            local full = typedMember(joinWords(w, 2))
            if not full then return end
            local items = ns.LootOf(full, 10)
            if #items == 0 then ns.Print(ns.ShortName(full) .. " got no items yet") end
            for _, l in ipairs(items) do
                ns.Print(date("%d.%m.", l.time) .. " " .. l.link .. " " .. l.gp .. " GP" .. (l.name ~= full and (" (" .. ns.ShortName(l.name) .. ")") or ""))
            end
        else
            for line in ns.RaidLootText():gmatch("[^\n]+") do ns.Print(line) end
        end

    elseif cmd == "raid" then
        awardGroup(ns.Setting("raidEP"), "Raid night", "raid")

    elseif cmd == "ontime" then
        awardGroup(ns.Setting("onTimeEP"), "Being on time", "ontime")

    elseif cmd == "bench" then
        local sub = (w[2] or ""):lower()
        if sub == "add" and w[3] then
            local member = typedMember(joinWords(w, 3))
            if member then
                local ok, full = ns.BenchAdd(member)
                ns.Print(ok and (ns.ShortName(full) .. " is on the bench") or (ns.ShortName(member) .. " is already on the bench"))
            end
        elseif sub == "remove" and w[3] then
            local member = typedMember(joinWords(w, 3))
            if member then
                local ok, full = ns.BenchRemove(member)
                ns.Print(ok and (ns.ShortName(full) .. " is off the bench") or (ns.ShortName(member) .. " is not on the bench"))
            end
        elseif sub == "clear" then
            ns.BenchClear()
            ns.Print("bench cleared")
        elseif sub == "list" then
            local short = {}
            for _, n in ipairs(ns.Bench()) do table.insert(short, ns.ShortName(n)) end
            ns.Print(#short > 0 and ("bench " .. table.concat(short, ", ")) or "nobody is on the bench")
        else
            ns.ToggleBench()
        end

    elseif (cmd == "ep" or cmd == "gp") and w[2] then
        if not needOfficer() then return end
        -- the name can have several words, the first number ends it
        local at
        for i = 3, #w do
            if w[i]:match("^[%+%-]?%d+$") then at = i break end
        end
        if not at then
            ns.Print("type /rgf " .. cmd .. " Name 50, use a minus to take away")
            return
        end
        local full = typedMember(joinWords(w, 2, at - 1))
        if not full then return end
        local amount = tonumber(w[at])
        local reason = joinWords(w, at + 1)
        ns.BeginAction(string.format("%s %+d %s %s", ns.ShortName(full), amount, cmd:upper(), reason))
        local main = cmd == "ep" and ns.Adjust(full, amount, 0) or ns.Adjust(full, 0, amount)
        ns.EndAction()
        if main then ns.Print(pointsLine(main)) end

    elseif cmd == "alt" and w[3] then
        local alt, mainName = twoMembers(w, 2)
        if alt and mainName and ns.SetAlt(alt, mainName) then
            ns.Print(ns.ShortName(alt) .. " now shares points with " .. ns.ShortName(mainName))
        end

    elseif cmd == "unalt" and w[2] then
        local alt = typedMember(joinWords(w, 2))
        if alt and ns.UnsetAlt(alt) then
            ns.Print(ns.ShortName(alt) .. " is a main again and starts at 0 EP, undo brings the link back")
        end

    elseif cmd == "decay" then
        if not needOfficer() then return end
        ns.AskDecay()

    elseif cmd == "undo" then
        if not needOfficer() then return end
        local action = ns.Undo()
        ns.Print(action and ("undone " .. action.label) or "nothing of yours to undo")

    elseif cmd == "price" then
        local link = itemLink(line)
        if not link then ns.Print("type /rgf price, shift click the item, then the GP or clear") return end
        local rest = line:sub((line:find(link, 1, true) or 0) + #link)
        local value = rest:match("(%d+)")
        if rest:lower():match("clear") then
            if not needOfficer() then return end
            if ns.ClearPriceOverride(link) then ns.Print(link .. " uses the normal price again") end
        elseif value then
            if not needOfficer() then return end
            if ns.SetPriceOverride(link, tonumber(value)) then
                ns.Print(link .. " now always costs " .. value .. " GP")
            end
        else
            local normal = ns.ItemPrice(link, "normal")
            local boss = ns.ItemPrice(link, "boss")
            local rare = ns.ItemPrice(link, "rare")
            ns.Print(string.format("%s costs %d GP (normal), %d GP (end boss), %d GP (rare)", link, normal, boss, rare))
        end

    elseif cmd == "editors" or (cmd == "editor" and not w[2]) then
        local names = {}
        for _, full in ipairs(ns.Editors()) do table.insert(names, ns.ShortName(full)) end
        if ns.EditorsInUse() then
            ns.Print("editors besides the guild leader, " .. (#names > 0 and table.concat(names, ", ") or "nobody"))
        else
            ns.Print("the editor list is still empty, the guild leader and rank 1 to " .. ns.OfficerRank() .. " can change data. The guild leader adds editors with /rgf editor add Name")
        end

    elseif cmd == "editor" then
        local sub = (w[2] or ""):lower()
        if (sub == "add" or sub == "remove") and w[3] then
            if not ns.CanManageEditors() then
                ns.Print("only the guild leader can add or remove editors")
                return
            end
            local member = typedMember(joinWords(w, 3))
            if not member then return end
            local ok, result = ns.SetEditor(member, sub == "add")
            if ok then
                ns.Print(ns.ShortName(result) .. (sub == "add" and " is now an editor" or " is no editor anymore"))
            else
                ns.Print(result)
            end
        else
            ns.Print("type /rgf editor add Name or /rgf editor remove Name")
        end

    elseif cmd == "sync" then
        ns.RequestRoster()
        ns.Sync()

    elseif cmd == "rebid" then
        if not ns.ReopenBidPopup() then ns.Print("no bidding is open right now") end

    elseif cmd == "check" then
        ns.SelfCheck()

    elseif cmd == "discord" then
        ns.ToggleStandings(ns.TAB.standings)
        ns.ShowCopyText("Standings", ns.StandingsText(ns.mainFrame.pages[ns.TAB.standings].shown or {}))

    elseif cmd == "export" then
        ns.ToggleStandings(ns.TAB.data)

    elseif cmd == "fresh" then
        if not needOfficer() then return end
        if StaticPopup_Show then StaticPopup_Show("REDGUILDFOREVER_FRESH") end

    elseif cmd == "test" then
        ns.SetTestMode(not ns.IsTest())

    elseif cmd == "settings" or cmd == "options" then
        ns.OpenSettings("settings")

    elseif cmd == "rules" then
        ns.OpenSettings("rules")

    elseif cmd == "edit" then
        if not needOfficer() then return end
        local full
        if w[2] then
            full = typedMember(joinWords(w, 2))
        else
            local target = UnitIsPlayer("target") and ns.UnitFullName("target")
            if target then
                full = typedMember(target)
            else
                ns.Print("type /rgf edit Cel Dru, or target a player first")
            end
        end
        if full then ns.OpenEditor(full) end

    elseif cmd == "minimap" then
        local hidden = RedGuildForeverDB.minimap and RedGuildForeverDB.minimap.hide
        ns.SetMinimapShown(hidden and true or false)
        if hidden then ns.Print("minimap button shown") end

    elseif cmd == "log" then
        local log = ns.Log()
        if #log == 0 then ns.Print("no changes recorded yet") return end
        for i = math.max(1, #log - 9), #log do
            local e = log[i]
            ns.Print(date("%d.%m %H:%M", e.time) .. " " .. e.label .. " (" .. e.count .. " players, by " .. ns.ShortName(e.by) .. ")"
                .. (e.undone and ", undone" or ""))
        end

    else
        ns.Print("unknown command, type /rgf help")
    end
end

SLASH_REDGUILDFOREVER1 = "/rgf"
SLASH_REDGUILDFOREVER2 = "/epgp"
SlashCmdList["REDGUILDFOREVER"] = function(msg) ns.Command(msg) end
