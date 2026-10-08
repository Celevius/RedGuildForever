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
    ns.Print("only the guild leader and officers can do that")
    return false
end

local help = {
    "/rgf  open the standings",
    "/rgf me  show your own points",
    "/rgf minimap  show or hide the minimap button",
    "/rgf check Cel Dru  show the points of a player, the first name is enough if it is clear",
    "|cffffd100Loot master|r",
    "/rgf bid  open the Start Bidding window, or /rgf bid [item] to start right away",
    "/rgf test  turn test mode on or off, try everything alone",
    "/rgf settings  open the settings",
    "/rgf bid [item] boss  same, priced as an end boss item (or rare)",
    "|cffffd100Officers|r",
    "/rgf edit Cel Dru  open the editor for a player, or your target without a name",
    "/rgf raid  give raid EP to the raid and the bench",
    "/rgf ontime  give the on time bonus to the raid and the bench",
    "/rgf bench  open the bench, or /rgf bench add Cel Dru, remove Cel Dru, clear",
    "/rgf ep Cel Dru 50  give or take EP (use a minus to take)",
    "/rgf gp Cel Dru 100  give or take GP",
    "/rgf alt Cel Rog, Cel Dru  link the alt Cel Rog to the main Cel Dru",
    "/rgf unalt Cel Rog  make an alt a main again",
    "/rgf decay  weekly decay",
    "/rgf undo  undo the last change from this session",
    "/rgf price [item] 250  fixed price for an item, or clear",
    "/rgf sync  sync the data with everyone online",
    "/rgf export  open the Sync tab with backup export and import",
    "/rgf log  show the last changes",
}

local function pointsLine(name)
    local ep, gp, pr, main = ns.GetPoints(name)
    local line = string.format("%s has %d EP, %d GP, priority %s", ns.ShortName(name), ep, gp, ns.FormatPR(pr))
    if main and main ~= ns.Resolve(name) then line = line .. " (points of " .. ns.ShortName(main) .. ")" end
    if ep < ns.Setting("minEP") then line = line .. ", new member" end
    return line
end

local function awardGroup(amount, label)
    if not needOfficer() then return end
    local names = ns.RaidAndBench()
    local benched = #ns.Bench()
    local count, skipped = ns.AwardEP(names, amount, label)
    local msg = string.format("%d players got %d EP for %s", count, amount, label:lower())
    if benched > 0 then msg = msg .. ", the " .. benched .. " on the bench included" end
    ns.Announce(msg .. ".")
    if #skipped > 0 then
        local short = {}
        for _, n in ipairs(skipped) do table.insert(short, ns.ShortName(n)) end
        ns.Print("not in the guild, no EP " .. table.concat(short, ", "))
    end
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

    elseif cmd == "raid" then
        awardGroup(ns.Setting("raidEP"), "Raid night")

    elseif cmd == "ontime" then
        awardGroup(ns.Setting("onTimeEP"), "Being on time")

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
            ns.Print(ns.ShortName(alt) .. " is a main again and starts at 0 EP")
        end

    elseif cmd == "decay" then
        if not needOfficer() then return end
        if StaticPopup_Show then
            StaticPopup_Show("REDGUILDFOREVER_DECAY", ns.Setting("decayPercent"))
        end

    elseif cmd == "undo" then
        if not needOfficer() then return end
        local action = ns.Undo()
        ns.Print(action and ("undone " .. action.label) or "nothing to undo in this session")

    elseif cmd == "price" then
        local link = itemLink(line)
        if not link then ns.Print("type /rgf price, shift click the item, then the GP or clear") return end
        local rest = line:sub((line:find(link, 1, true) or 0) + #link)
        local value = rest:match("(%d+)")
        if rest:lower():match("clear") then
            local id = ns.ItemInfo(link)
            if id then RedGuildForeverDB.priceOverrides[id] = nil end
            ns.Print(link .. " uses the normal price again")
        elseif value then
            if not needOfficer() then return end
            ns.SetPriceOverride(link, tonumber(value))
            ns.Print(link .. " now always costs " .. value .. " GP")
        else
            local normal = ns.ItemPrice(link, "normal")
            local boss = ns.ItemPrice(link, "boss")
            local rare = ns.ItemPrice(link, "rare")
            ns.Print(string.format("%s costs %d GP (normal), %d GP (end boss), %d GP (rare)", link, normal, boss, rare))
        end

    elseif cmd == "sync" then
        ns.RequestRoster()
        ns.Sync()

    elseif cmd == "export" then
        ns.ToggleStandings(4)

    elseif cmd == "fresh" then
        if not needOfficer() then return end
        if StaticPopup_Show then StaticPopup_Show("REDGUILDFOREVER_FRESH") end

    elseif cmd == "test" then
        ns.SetTestMode(not ns.IsTest())

    elseif cmd == "settings" or cmd == "options" then
        ns.ToggleStandings(5)

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
            ns.Print(date("%d.%m %H:%M", e.time) .. " " .. e.label .. " (" .. e.count .. " players, by " .. ns.ShortName(e.by) .. ")")
        end

    else
        ns.Print("unknown command, type /rgf help")
    end
end

SLASH_REDGUILDFOREVER1 = "/rgf"
SLASH_REDGUILDFOREVER2 = "/epgp"
SlashCmdList["REDGUILDFOREVER"] = function(msg) ns.Command(msg) end
