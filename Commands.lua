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

local function needOfficer()
    if ns.CanEditNotes() then return true end
    ns.Print("only officers who can edit officer notes can do that")
    return false
end

local help = {
    "/rgf  open the standings",
    "/rgf me  show your own points",
    "/rgf check Name  show the points of a player",
    "|cffffd100Loot master|r",
    "/rgf bid [item]  open bidding, shift click the item into the command",
    "/rgf bid [item] boss  same, priced as an end boss item (or rare)",
    "|cffffd100Officers|r",
    "/rgf raid  give raid EP to the raid and the bench",
    "/rgf ontime  give the on time bonus to the raid and the bench",
    "/rgf bench  open the bench, or /rgf bench add Name, remove Name, clear",
    "/rgf ep Name 50  give or take EP (use a minus to take)",
    "/rgf gp Name 100  give or take GP",
    "/rgf alt Alt Main  link an alt to a main, they share points",
    "/rgf unalt Alt  make an alt a main again",
    "/rgf decay  weekly decay",
    "/rgf undo  undo the last change from this session",
    "/rgf price [item] 250  fixed price for an item, or clear",
    "/rgf sync  send the standings to everyone",
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
        ns.Print(pointsLine(w[2]))

    elseif cmd == "bid" or cmd == "auction" then
        local link = itemLink(line)
        if not link then
            ns.Print("type /rgf bid and then shift click the item")
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
            local ok, full = ns.BenchAdd(w[3])
            ns.Print(ok and (ns.ShortName(full) .. " is on the bench") or "already on the bench")
        elseif sub == "remove" and w[3] then
            local ok, full = ns.BenchRemove(w[3])
            ns.Print(ok and (ns.ShortName(full) .. " is off the bench") or "not on the bench")
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

    elseif (cmd == "ep" or cmd == "gp") and w[2] and tonumber(w[3]) then
        if not needOfficer() then return end
        local amount = tonumber(w[3])
        local reason = table.concat(w, " ", 4)
        ns.BeginAction(string.format("%s %+d %s %s", ns.ShortName(ns.Resolve(w[2])), amount, cmd:upper(), reason))
        local main = cmd == "ep" and ns.Adjust(w[2], amount, 0) or ns.Adjust(w[2], 0, amount)
        ns.EndAction()
        if main then ns.Print(pointsLine(main)) end

    elseif cmd == "alt" and w[2] and w[3] then
        if ns.SetAlt(w[2], w[3]) then
            ns.Print(ns.ShortName(ns.Resolve(w[2])) .. " now shares points with " .. ns.ShortName(ns.Resolve(w[3])))
        end

    elseif cmd == "unalt" and w[2] then
        if ns.UnsetAlt(w[2]) then
            ns.Print(ns.ShortName(ns.Resolve(w[2])) .. " is a main again and starts at 0 EP")
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
        if ns.CanViewNotes() then
            ns.RequestRoster()
            ns.QueueBroadcast(1)
            ns.Print("sending standings to the guild")
        else
            ns.SendComm("SR", "GUILD")
            ns.Print("asking officers for the standings")
        end

    elseif cmd == "log" then
        local log = RedGuildForeverDB.log
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
SlashCmdList = SlashCmdList or {}
SlashCmdList["REDGUILDFOREVER"] = function(msg) ns.Command(msg) end
