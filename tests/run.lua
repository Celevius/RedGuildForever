-- SPDX-License-Identifier: MIT, see LICENSE
-- Logic tests for Red Guild EPGP. Run from the repository root:
--   lua5.1 tests/run.lua

package.path = "./tests/?.lua;" .. package.path
local W = require("mock_wow")

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("  ok    " .. name)
    else
        failed = failed + 1
        print("  FAIL  " .. name .. "\n        " .. tostring(err))
    end
end

local function eq(a, b, what)
    if a ~= b then error((what or "value") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end
end

local function near(a, b, what)
    if math.abs(a - b) > 0.005 then error((what or "value") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end
end

local function noErrors()
    for _, p in ipairs(W.printed) do
        if p:find("error", 1, true) then error("addon printed an error: " .. p, 2) end
    end
    for _, c in ipairs(W.chat) do
        if c.channel == "GUILD" or c.channel == "OFFICER" then
            error("addon wrote in " .. c.channel .. " chat: " .. c.msg, 2)
        end
    end
end

-- fresh addon with a guild roster
local ns
local function setup(roster)
    W.install()
    W.reset()
    W.player = "Cel Dru"
    W.roster = roster
    W.raid, W.inRaid = {}, false
    W.canEdit, W.canView = true, true
    W.guildInfo = ""
    W.units = {}
    W.realms = nil
    W.rank = nil
    W.server = 1760000000
    W.itemSlots = {}
    ns = {}
    W.load(ns)
    -- the third column is the saved data of that player, as if it came from the save file
    local players = ns.Base()
    for _, r in ipairs(roster) do
        if r[3] and r[3] ~= "" then
            local info = ns.ParseNote(r[3])
            local full = ns.FullName(r[1])
            if info.main then
                players[full] = { main = info.main, t = W.server - 100 }
            else
                players[full] = { ep = info.ep, gp = info.gp, t = W.server - 100 }
            end
        end
        r[3] = "" -- officer notes stay empty, the addon does not use them
    end
    ns.Data().started = true
    ns.Invalidate()
    ns.RebuildFromRoster()
    W.flush()
end

-- change the starting points of a player directly
local function set(name, value)
    local info = ns.ParseNote(value)
    W.server = W.server + 1
    ns.Base()[ns.FullName(name)] = info.main and { main = info.main, t = W.server }
        or { ep = info.ep, gp = info.gp, t = W.server }
    -- the starting points count, changes made before are forgotten
    for id, ev in pairs(ns.Data().events) do
        local hit = ev.alt == ns.FullName(name)
        for _, c in ipairs(ev.ch or {}) do if ns.MainOf(c.n) == ns.FullName(name) then hit = true end end
        if hit or ev.k == "D" then ns.Data().events[id] = nil end
    end
    ns.Invalidate()
end

local function guild()
    return {
        { "Cel Dru", 0, "", "DRUID" },
        { "Tom Hammer", 2, "200,100", "WARRIOR" },
        { "Lisa Brightwater", 2, "1000,500", "PRIEST" },
        { "Max Ironhide", 2, "1000,100", "PALADIN" },
        { "Ben Swift", 3, "", "ROGUE" },
        { "Anna Frost", 2, "500,200", "MAGE" },
        { "Tom Spark", 2, "@Tom Hammer", "MAGE" },
    }
end

-- the saved data of a player in the old note style, "ep,gp" or "@Main"
local function note(name)
    local e = ns.Players()[ns.FullName(name)]
    if not e then return nil end
    if e.main then return "@" .. ns.ShortName(e.main) end
    return string.format("%d,%d", e.ep, e.gp)
end

print("Red Guild EPGP tests")

test("loads cleanly and registers only real game events", function()
    W.registered = {}
    setup(guild())
    for _, event in ipairs({ "ADDON_LOADED", "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE",
        "CHAT_MSG_ADDON", "CHAT_MSG_SYSTEM", "CHAT_MSG_WHISPER" }) do
        assert(W.registered[event], event .. " not registered")
    end
    for event in pairs(W.registered) do
        assert(not event:match("^RGF_"), "internal signal registered with the game " .. event)
    end
    for _, p in ipairs(W.printed) do
        assert(not p:find("does not know", 1, true), p)
    end
    noErrors()
end)

test("old officer notes still parse for the import", function()
    setup(guild())
    local p = ns.ParseNote("1250,300 tank")
    eq(p.ep, 1250) eq(p.gp, 300)
    eq(ns.ParseNote("@Cel Dru").main, "Cel Dru-Forever")
    eq(ns.ParseNote("just text").ep, nil)
end)

test("item prices from the rule book", function()
    setup(guild())
    W.itemSlots = { [1] = "INVTYPE_2HWEAPON", [2] = "INVTYPE_HAND", [3] = "INVTYPE_FINGER", [4] = "INVTYPE_CHEST" }
    eq(ns.ItemPrice(W.link(1, "Axe"), "boss"), 300, "two hander from end boss")
    eq(ns.ItemPrice(W.link(2, "Gloves"), "normal"), 100, "gloves")
    eq(ns.ItemPrice(W.link(3, "Ring"), "normal"), 75, "ring")
    eq(ns.ItemPrice(W.link(4, "Chest"), "rare"), 300, "rare chest")
    ns.SetPriceOverride(W.link(3, "Ring"), 250)
    eq(ns.ItemPrice(W.link(3, "Ring"), "normal"), 250, "override")
end)

test("priority examples from the rule book", function()
    setup(guild())
    local _, _, pr = ns.GetPoints("Tom Hammer") near(pr, 2, "Tom Hammer")
    _, _, pr = ns.GetPoints("Lisa Brightwater") near(pr, 2, "Lisa Brightwater")
    _, _, pr = ns.GetPoints("Max Ironhide") near(pr, 10, "Max Ironhide")
    local ep, gp
    ep, gp, pr = ns.GetPoints("Ben Swift")
    eq(ep, 0) eq(gp, 100) eq(pr, 0)
    eq(ns.IsNewMember("Tom Hammer"), true, "Tom is new")
    eq(ns.IsNewMember("Lisa Brightwater"), false, "Lisa is not new")
end)

test("alts share the points of their main", function()
    setup(guild())
    local ep, gp, pr, main = ns.GetPoints("Tom Spark")
    eq(main, "Tom Hammer-Forever") eq(ep, 200) eq(gp, 100) near(pr, 2)
    eq(#ns.AltsOf("Tom Hammer-Forever"), 1)
end)

test("sword auction, Max wins and drops to 3.33", function()
    setup(guild())
    W.itemSlots = { [10] = "INVTYPE_WEAPON" }
    local sword = W.link(10, "Sword")
    ns.SetPriceOverride(sword, 200)
    W.inRaid = true
    assert(ns.StartAuction(sword))
    W.deliver(ns) -- popup for the loot master too
    ns.RecordBid("Tom Hammer", "MS")
    ns.RecordBid("Lisa Brightwater", "MS")
    ns.RecordBid("Max Ironhide", "MS")
    local list = ns.SortedBids(ns.auction)
    eq(list[1].name, "Max Ironhide-Forever", "first")
    ns.CloseBidding()
    eq(#ns.TiedForFirst(ns.auction), 0, "no tie")
    assert(ns.Award("Max Ironhide"))
    W.flush()
    eq(note("Max Ironhide"), "1000,300")
    local _, _, pr = ns.GetPoints("Max Ironhide")
    near(pr, 3.33, "Max after sword")
    noErrors()
end)

test("tie between Tom and Lisa is decided by /roll", function()
    setup(guild())
    W.itemSlots = { [11] = "INVTYPE_FINGER" }
    W.inRaid = true
    ns.StartAuction(W.link(11, "Ring"))
    ns.RecordBid("Tom Hammer", "MS")
    ns.RecordBid("Lisa Brightwater", "MS")
    -- Tom is a new member (200 EP), so Lisa wins without a roll
    eq(ns.SortedBids(ns.auction)[1].name, "Lisa Brightwater-Forever", "Lisa before new member Tom")
    eq(#ns.TiedForFirst(ns.auction), 0)
    -- make Tom a regular with the same priority as Lisa
    set("Tom Hammer", "400,200")
    eq(#ns.TiedForFirst(ns.auction), 2, "tie")
    ns.CloseBidding() -- asks for rolls
    assert(ns.auction.rollsOpen, "rolls open")
    ns.Fire("CHAT_MSG_SYSTEM", "Tom Hammer rolls 40 (1-100)")
    ns.Fire("CHAT_MSG_SYSTEM", "Tom Hammer rolls 99 (1-100)") -- second roll ignored
    ns.Fire("CHAT_MSG_SYSTEM", "Lisa Brightwater rolls 77 (1-100)")
    ns.Fire("CHAT_MSG_SYSTEM", "Max Ironhide rolls 100 (1-100)") -- not a bidder
    eq(#ns.TiedForFirst(ns.auction), 0, "tie solved")
    eq(ns.SortedBids(ns.auction)[1].name, "Lisa Brightwater-Forever", "highest roll")
    noErrors()
end)

test("new member Ben loses to Lisa even with higher priority", function()
    setup(guild())
    set("Lisa Brightwater", "1000,900")  -- Lisa priority 1.11
    set("Ben Swift", "125,100")          -- Ben priority 1.25 but new
    W.inRaid = true
    ns.StartAuction(W.link(12, "Ring"))
    ns.RecordBid("Ben Swift", "MS")
    ns.RecordBid("Lisa Brightwater", "MS")
    eq(ns.SortedBids(ns.auction)[1].name, "Lisa Brightwater-Forever")
    ns.RecordBid("Lisa Brightwater", "PASS")
    eq(ns.SortedBids(ns.auction)[1].name, "Ben Swift-Forever", "Ben when nobody else wants it")
end)

test("off spec is free and main spec goes first", function()
    setup(guild())
    W.inRaid = true
    ns.StartAuction(W.link(13, "Staff"))
    ns.RecordBid("Lisa Brightwater", "OS")
    ns.RecordBid("Ben Swift", "MS")
    eq(ns.SortedBids(ns.auction)[1].name, "Ben Swift-Forever", "main spec first even for a new member")
    ns.RecordBid("Ben Swift", "PASS")
    ns.Award("Lisa Brightwater")
    W.flush()
    eq(note("Lisa Brightwater"), "1000,500", "Lisa GP unchanged")
end)

test("alt loot costs the main", function()
    setup(guild())
    W.itemSlots = { [14] = "INVTYPE_CLOAK" }
    W.inRaid = true
    ns.StartAuction(W.link(14, "Cloak"))
    ns.RecordBid("Tom Spark", "MS")
    ns.Award("Tom Spark")
    W.flush()
    eq(note("Tom Hammer"), "200,175", "Tom pays 75 GP")
    eq(note("Tom Spark"), "@Tom Hammer", "alt note untouched")
end)

test("raid EP goes to raid and bench, each player once", function()
    setup(guild())
    W.inRaid = true
    W.raid = { "Cel Dru", "Lisa Brightwater", "Tom Spark", "Some Stranger-Otherrealm" }
    ns.BenchAdd("Anna Frost")
    ns.BenchAdd("Tom Hammer") -- Tom is in the raid on his alt
    local count, skipped = ns.AwardEP(ns.RaidAndBench(), 100, "Raid night")
    W.flush()
    eq(count, 4, "players")
    eq(#skipped, 1, "stranger skipped")
    eq(note("Lisa Brightwater"), "1100,500")
    eq(note("Tom Hammer"), "300,100", "Tom only once")
    eq(note("Anna Frost"), "600,200", "bench same EP")
    eq(note("Cel Dru"), "100,100", "new note created")
end)

test("weekly decay keeps GP at the base", function()
    setup(guild())
    set("Max Ironhide", "1000,105")
    ns.Decay()
    W.flush()
    eq(note("Lisa Brightwater"), "900,450")
    eq(note("Max Ironhide"), "900,100", "GP floor")
    eq(note("Tom Spark"), "@Tom Hammer", "alts untouched")
end)

test("undo reverts the last action", function()
    setup(guild())
    ns.AwardEP({ "Lisa Brightwater", "Max Ironhide" }, 100, "Raid night")
    W.flush()
    eq(note("Lisa Brightwater"), "1100,500")
    ns.Undo()
    W.flush()
    eq(note("Lisa Brightwater"), "1000,500")
    eq(note("Max Ironhide"), "1000,100")
    eq(ns.Undo(), nil, "nothing left")
end)

test("link and unlink alts", function()
    setup(guild())
    assert(ns.SetAlt("Ben Swift", "Anna Frost"))
    W.flush()
    eq(note("Ben Swift"), "@Anna Frost")
    ns.RebuildFromRoster() W.flush()
    eq(select(4, ns.GetPoints("Ben Swift")), "Anna Frost-Forever")
    eq(ns.SetAlt("Lisa Brightwater", "Tom Spark"), false, "cannot link to an alt")
    assert(ns.UnsetAlt("Ben Swift"))
    W.flush()
    eq(note("Ben Swift"), "0,100")
end)

test("whisper bids for players without the addon", function()
    setup(guild())
    W.inRaid = true
    ns.StartAuction(W.link(15, "Boots"))
    ns.Fire("CHAT_MSG_WHISPER", "  MS ", "Lisa Brightwater-Forever")
    ns.Fire("CHAT_MSG_WHISPER", "os", "Tom Hammer-Forever")
    ns.Fire("CHAT_MSG_WHISPER", "hello", "Max Ironhide-Forever")
    eq(ns.auction.bids["Lisa Brightwater-Forever"].spec, "MS")
    eq(ns.auction.bids["Tom Hammer-Forever"].spec, "OS")
    eq(ns.auction.bids["Max Ironhide-Forever"], nil)
    local replies = 0
    for _, c in ipairs(W.chat) do if c.channel == "WHISPER" then replies = replies + 1 end end
    eq(replies, 2, "confirmation whispers")
end)

test("addon bids from raiders reach the loot master", function()
    setup(guild())
    W.inRaid = true
    ns.StartAuction(W.link(16, "Helm"))
    local id = ns.auction.id
    W.comms = {}
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "B^" .. id .. "^MS", "WHISPER", "Max Ironhide-Forever")
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "B^000000^MS", "WHISPER", "Lisa Brightwater-Forever")
    eq(ns.auction.bids["Max Ironhide-Forever"].spec, "MS")
    eq(ns.auction.bids["Lisa Brightwater-Forever"], nil, "wrong auction id ignored")
end)

test("raider popup receives auction with item link", function()
    setup(guild())
    W.inRaid = true
    local link = W.link(17, "Shoulders")
    ns.StartAuction(link)
    W.deliver(ns, "Cel Dru")
    local got
    for _, inc in pairs(ns.incoming) do got = inc end
    assert(got, "incoming auction")
    eq(got.link, link)
    eq(got.price, 100)
    ns.Award(nil)
    W.deliver(ns, "Cel Dru")
    eq(next(ns.incoming), nil, "closed")
    noErrors()
end)

test("roll pattern works with other client languages", function()
    setup(guild())
    _G.RANDOM_ROLL_RESULT = "%s würfelt. Ergebnis %d (%d-%d)"
    local loader = assert(loadfile("Auction.lua"))
    loader("RedGuildForever", ns)
    local name, roll, low, high = ns.ParseRoll("Lisa Brightwater würfelt. Ergebnis 42 (1-100)")
    eq(name, "Lisa Brightwater") eq(roll, 42) eq(low, 1) eq(high, 100)
end)

test("slash commands run without errors", function()
    setup(guild())
    W.inRaid = true
    W.raid = { "Cel Dru", "Lisa Brightwater" }
    for _, cmd in ipairs({ "", "help", "me", "check Lisa", "raid", "ontime", "bench add Anna", "bench list",
        "bench remove Anna", "bench", "ep Lisa 50 bonus", "gp Lisa -20", "undo", "decay", "log", "sync",
        "price " .. W.link(18, "Belt"), "price " .. W.link(18, "Belt") .. " 250", "price " .. W.link(18, "Belt") .. " clear",
        "bid " .. W.link(19, "Axe") .. " boss", "nonsense" }) do
        ns.Command(cmd)
        W.flush()
    end
    eq(ns.auction.tier, "boss")
    eq(W.popup, "REDGUILDFOREVER_DECAY")
    noErrors()
end)

test("windows and tabs build and refresh without errors", function()
    setup(guild())
    W.inRaid = true
    W.raid = { "Cel Dru", "Lisa Brightwater", "Max Ironhide" }
    ns.BenchAdd("Anna Frost")
    ns.Command("raid") W.flush()
    -- standings window, every tab, as officer and as normal member
    ns.ToggleStandings()
    ns.ToggleStandings(ns.TAB.raid)
    ns.ToggleStandings(ns.TAB.history)
    ns.ToggleStandings(1)
    W.canEdit, W.canView = false, false
    ns.RebuildFromRoster() W.flush()
    ns.ToggleStandings(ns.TAB.raid)
    ns.ToggleStandings(1)
    W.canEdit, W.canView = true, true
    ns.RebuildFromRoster() W.flush()
    -- loot master window and bid popup through a whole auction with a tie
    set("Tom Hammer", "1000,500") -- Tom ties with Lisa
    ns.Command("bid " .. W.link(30, "Helm of Testing") .. " boss")
    W.deliver(ns, "Cel Dru")
    ns.RecordBid("Tom Hammer", "MS")
    ns.RecordBid("Lisa Brightwater", "MS")
    ns.RecordBid("Max Ironhide", "OS")
    local inc
    for _, i in pairs(ns.incoming) do inc = i end
    ns.SendBid(inc, "MS")
    ns.SetAuctionTier("rare")
    ns.CloseBidding()
    ns.Fire("CHAT_MSG_SYSTEM", "Tom Hammer rolls 12 (1-100)")
    ns.Fire("CHAT_MSG_SYSTEM", "Lisa Brightwater rolls 88 (1-100)")
    ns.Award("Lisa Brightwater")
    W.deliver(ns, "Cel Dru")
    W.flush()
    ns.ToggleStandings(ns.TAB.history)
    noErrors()
end)

test("names with first and last name", function()
    setup(guild())
    eq(ns.FullName("Cel Dru"), "Cel Dru-Forever")
    eq(ns.FullName("  cel   dru  "), "Cel Dru-Forever", "spacing and capitals")
    eq(ns.FullName("Cel Dru-Otherrealm"), "Cel Dru-Otherrealm")
    eq(ns.FullName("Cel Dru - Otherrealm"), "Cel Dru-Otherrealm")
    eq(ns.FullName("élise d'arc"), "élise D'arc-Forever", "accents stay")
    eq(ns.ShortName("Cel Dru-Forever"), "Cel Dru")
    eq(ns.ShortName("Cel Dru-Otherrealm"), "Cel Dru-Otherrealm")
    eq(ns.PlayerName(), "Cel Dru-Forever")
end)

test("finding members by full name, first name and start of name", function()
    setup(guild())
    eq(ns.FindMember("lisa brightwater"), "Lisa Brightwater-Forever")
    eq(ns.FindMember("Lisa"), "Lisa Brightwater-Forever", "unique first name")
    eq(ns.FindMember("Lisa Bright"), nil, "partial only when typed")
    eq(ns.FindMember("Lisa Bright", true), "Lisa Brightwater-Forever")
    local none, list = ns.FindMember("Tom")
    eq(none, nil, "two players called Tom")
    eq(#list, 2)
    eq(ns.FindMember("Lisa Stranger"), nil, "a full name never matches someone else")
    eq(ns.Resolve("Lisa Stranger"), "Lisa Stranger-Forever")
end)

test("game gives only the first name", function()
    setup(guild())
    W.player = "Anna"
    eq(ns.PlayerName(), "Anna Frost-Forever")
    W.player = "Cel Dru"
end)

test("commands with names that have spaces", function()
    setup(guild())
    ns.Command("ep Lisa Brightwater 50 boss bonus") W.flush()
    eq(note("Lisa Brightwater"), "1050,500")
    ns.Command("gp max -1") W.flush()
    eq(note("Max Ironhide"), "1000,100", "GP never below base")
    ns.Command("ep Tom 10") W.flush()
    eq(note("Tom Hammer"), "200,100", "ambiguous name changes nothing")
    local said = W.printed[#W.printed]
    assert(said:find("Tom Hammer") and said:find("Tom Spark"), "lists both Toms")
    ns.Command("bench add anna frost")
    eq(ns.Bench()[1], "Anna Frost-Forever")
    ns.Command("bench remove Anna")
    eq(#ns.Bench(), 0)
    ns.Command("check Ben Swift")
    assert(W.printed[#W.printed]:find("Ben Swift has 0 EP"), W.printed[#W.printed])
end)

test("linking alts with two part names", function()
    setup(guild())
    ns.Command("alt Ben Swift Anna Frost") W.flush()
    eq(note("Ben Swift"), "@Anna Frost", "alt note keeps the space")
    ns.RebuildFromRoster() W.flush()
    eq(select(4, ns.GetPoints("Ben Swift")), "Anna Frost-Forever")
    ns.Command("unalt Ben") W.flush()
    eq(note("Ben Swift"), "0,100")
    ns.Command("alt Ben, Anna") W.flush()
    eq(note("Ben Swift"), "@Anna Frost", "comma and first names")
end)

test("bids, whispers, rolls and raid EP with two part names", function()
    setup(guild())
    W.inRaid = true
    W.raid = { "Cel Dru", "Lisa Brightwater", "Tom Spark", "Some Stranger" }
    local count, skipped = ns.AwardEP(ns.RaidAndBench(), 100, "Raid night")
    W.flush()
    eq(count, 3) eq(#skipped, 1)
    eq(note("Tom Hammer"), "300,100", "alt in raid gives EP to the main")
    ns.StartAuction(W.link(40, "Cloak"))
    ns.Fire("CHAT_MSG_WHISPER", "ms", "Lisa Brightwater-Forever")
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "B^" .. ns.auction.id .. "^MS", "WHISPER", "Tom Spark-Forever")
    eq(ns.auction.bids["Lisa Brightwater-Forever"].spec, "MS")
    eq(ns.auction.bids["Tom Spark-Forever"].spec, "MS")
    set("Tom Hammer", "1100,500") -- Tom Hammer ties with Lisa
    ns.CloseBidding()
    ns.Fire("CHAT_MSG_SYSTEM", "Tom Spark rolls 90 (1-100)")
    ns.Fire("CHAT_MSG_SYSTEM", "Lisa Brightwater rolls 30 (1-100)")
    eq(ns.SortedBids(ns.auction)[1].name, "Tom Spark-Forever")
    ns.Award("Tom Spark-Forever")
    W.flush()
    eq(note("Tom Hammer"), "1100,600", "main pays for the alt")
    local won
    for _, c in ipairs(W.chat) do if c.msg:find("Tom Spark %(alt of Tom Hammer%) wins") then won = true end end
    assert(won, "announcement names the alt and the main")
    noErrors()
end)

test("loot master whispers keep the name the game used", function()
    setup(guild())
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "A^123456^30^100^1^" .. W.link(41, "Ring"), "RAID", "Lisa Brightwater")
    local inc = ns.incoming["123456"]
    eq(inc.owner, "Lisa Brightwater-Forever")
    eq(inc.ownerRaw, "Lisa Brightwater")
    W.comms = {}
    ns.SendBid(inc, "MS")
    eq(W.comms[1].target, "Lisa Brightwater")
end)

-- a fake of the game's menu system that remembers what the menu contains
local function fakeMenu()
    local menu = { items = {} }
    local root = {
        CreateTitle = function(_, t) table.insert(menu.items, { title = t }) end,
        CreateDivider = function() table.insert(menu.items, { divider = true }) end,
        CreateButton = function(_, t, fn) table.insert(menu.items, { text = t, fn = fn }) end,
    }
    _G.MenuUtil = {
        CreateContextMenu = function(owner, gen)
            menu.items = {}
            menu.owner = owner
            gen(owner, root)
        end,
    }
    return menu
end

test("minimap button opens the standings and the menu", function()
    setup(guild())
    local b = ns.minimapButton
    assert(b, "button created on load")
    local click = b:GetScript("OnClick")
    click(b, "LeftButton")
    -- the standings window is open now, a second click closes it
    click(b, "LeftButton")
    local menu = fakeMenu()
    click(b, "RightButton")
    local texts = {}
    for _, item in ipairs(menu.items) do if item.text then texts[item.text] = item.fn end end
    assert(texts["Start raid, give on time EP (25)"] and texts["Loot Master"], "raid entries for editors")
    assert(texts["Sync now"] and texts["Settings"], "entries for everyone")
    for _, gone in ipairs({ "Standings", "Bench", "History", "Weekly decay", "Edit target", "Hide minimap button" }) do
        assert(not texts[gone], gone .. " is in the window, not in the menu")
    end
    local count = 0
    for _, item in ipairs(menu.items) do if item.text then count = count + 1 end end
    eq(count, 6, "short menu for editors")
    -- every entry runs without errors
    W.inRaid = true W.raid = { "Cel Dru", "Lisa Brightwater" }
    for _, item in ipairs(menu.items) do
        if item.fn and item.text ~= "Undo last change" then
            item.fn() W.flush()
        end
    end
    eq(note("Lisa Brightwater"), "1025,500", "start raid from the menu gives the on time EP")
    menu = fakeMenu()
    click(b, "RightButton")
    texts = {}
    for _, item in ipairs(menu.items) do if item.text then texts[item.text] = item.fn end end
    texts["End raid, give raid EP (100)"]() W.flush()
    eq(note("Lisa Brightwater"), "1125,500", "end raid from the menu gives the raid EP")
    texts["Undo last change"]() W.flush()
    eq(note("Lisa Brightwater"), "1025,500", "undo from the menu takes back the raid EP")
    noErrors()
end)

test("members see no officer entries in the menu", function()
    setup(guild())
    W.canEdit = false
    local menu = fakeMenu()
    ns.OpenMenu(ns.minimapButton)
    local count = 0
    for _, item in ipairs(menu.items) do
        assert(not (item.text or ""):find("raid EP"), "editor entry shown to a member")
        assert(item.text ~= "Loot Master", "Loot Master shown to a member")
        if item.text then count = count + 1 end
    end
    eq(count, 3, "members get sync, the rules and the settings")
end)

test("menu falls back to the window without a menu system", function()
    setup(guild())
    _G.MenuUtil = nil
    ns.OpenMenu(ns.minimapButton)
    noErrors()
end)

test("minimap button can be hidden, shown and dragged", function()
    setup(guild())
    ns.SetMinimapShown(false) -- the checkbox in the settings
    eq(ns.minimapButton:IsShown(), false, "hidden")
    eq(RedGuildForeverDB.minimap.hide, true)
    ns.Command("minimap")
    eq(ns.minimapButton:IsShown(), true, "shown again")
    -- drag to the right side of the minimap
    _G.Minimap.GetCenter = function() return 100, 100 end
    _G.Minimap.GetEffectiveScale = function() return 1 end
    _G.GetCursorPosition = function() return 200, 100 end
    local b = ns.minimapButton
    b:GetScript("OnDragStart")(b)
    b:GetScript("OnUpdate")(b)
    b:GetScript("OnDragStop")(b)
    near(RedGuildForeverDB.minimap.angle, 0, "angle")
    noErrors()
end)

test("addon list next to the minimap", function()
    setup(guild())
    RedGuildForever_OnAddonCompartmentClick("RedGuildForever", "LeftButton")
    local menu = fakeMenu()
    RedGuildForever_OnAddonCompartmentClick("RedGuildForever", "RightButton", ns.minimapButton)
    assert(#menu.items > 0, "menu opened")
    RedGuildForever_OnAddonCompartmentEnter("RedGuildForever", ns.minimapButton)
    RedGuildForever_OnAddonCompartmentLeave()
    local toc = io.open("RedGuildForever.toc"):read("*a")
    assert(toc:find("AddonCompartmentFunc: RedGuildForever_OnAddonCompartmentClick", 1, true), "toc entry")
    noErrors()
end)

test("never writes in guild chat, also not after the decay", function()
    setup(guild())
    StaticPopupDialogs["REDGUILDFOREVER_DECAY"].OnAccept()
    W.flush()
    eq(note("Lisa Brightwater"), "900,450", "decay ran")
    eq(ns.SendChat("hello", "GUILD"), false, "guild chat blocked")
    eq(ns.SendChat("hello", "OFFICER"), false, "officer chat blocked")
    noErrors()
end)

test("officers edit points in the editor", function()
    setup(guild())
    assert(ns.OpenEditor("Lisa"), "opens with the first name")
    local e = ns.editor
    eq(e.target, "Lisa Brightwater-Forever")
    eq(e.ep:GetText(), "1000") eq(e.gp:GetText(), "500")
    eq(e.save:IsEnabled(), false, "nothing changed yet")
    e.ep:SetText("1200") e.UpdatePreview()
    e.gp:SetText("50")   e.UpdatePreview() -- below the base
    assert(e.preview:GetText():find("can not go below 100"), e.preview:GetText())
    e.reason:SetText("missed raid fix")
    e.save:Click()
    W.flush()
    eq(note("Lisa Brightwater"), "1200,100", "saved with GP floor")
    eq(e.ep:GetText(), "1200", "editor reloaded")
    local log = ns.Log()
    assert(log[#log].label:find("missed raid fix"), "reason in history")
    e.undo:Click()
    W.flush()
    eq(note("Lisa Brightwater"), "1000,500", "undo from the editor")
    noErrors()
end)

test("editor quick buttons, alts and bench", function()
    setup(guild())
    ns.OpenEditor("Anna Frost")
    local e = ns.editor
    e.UpdatePreview()
    -- quick buttons sit next to the EP box, +100 adds to the box
    e.ep:SetText("500")
    e.ep:SetText(tostring(tonumber(e.ep:GetText()) + 100)) e.UpdatePreview()
    e.save:Click() W.flush()
    eq(note("Anna Frost"), "600,200")
    -- an alt edits the points of its main
    ns.OpenEditor("Tom Spark")
    assert(e.sub:GetText():find("Alt of Tom Hammer"), e.sub:GetText())
    e.ep:SetText("250") e.UpdatePreview()
    e.save:Click() W.flush()
    eq(note("Tom Hammer"), "250,100", "main changed")
    eq(note("Tom Spark"), "@Tom Hammer", "alt note kept")
    -- make the alt a main again, then link Ben to Anna by typing
    e.unlink:Click() W.flush()
    eq(note("Tom Spark"), "0,100")
    ns.OpenEditor("Ben Swift")
    e.mainBox:SetText("anna")
    e.link:Click() W.flush()
    eq(note("Ben Swift"), "@Anna Frost")
    -- bench toggle
    ns.OpenEditor("Max Ironhide")
    eq(e.benchButton:GetText(), "Add to bench")
    e.benchButton:Click()
    eq(ns.Bench()[1], "Max Ironhide-Forever")
    eq(e.benchButton:GetText(), "Remove from bench")
    e.benchButton:Click()
    eq(#ns.Bench(), 0)
    noErrors()
end)

test("members cannot open the editor", function()
    setup(guild())
    W.canEdit = false
    eq(ns.OpenEditor("Lisa"), false)
    ns.Command("edit Lisa")
    noErrors()
end)

test("loot master gets the bid popup and can bid himself", function()
    setup(guild())
    W.inRaid = true
    W.raid = { "Cel Dru", "Lisa Brightwater" }
    local shown
    ns.On("RGF_INCOMING_AUCTION", function(inc) shown = inc end)
    ns.StartAuction(W.link(50, "Shiny Boots"))
    assert(shown, "popup for the loot master without waiting for the server")
    eq(shown.owner, "Cel Dru-Forever")
    ns.SendBid(shown, "MS")
    eq(ns.auction.bids["Cel Dru-Forever"].spec, "MS", "own bid recorded")
    -- the echo of his own message must not reset the bid
    W.deliver(ns, "Cel Dru")
    eq(shown.myBid, "MS", "bid kept after echo")
    ns.SetAuctionTier("boss")
    eq(shown.price, 150, "own popup gets the new price")
    local closed
    ns.On("RGF_INCOMING_CLOSED", function(inc) closed = inc end)
    ns.Award("Cel Dru-Forever")
    eq(closed, shown, "own popup closes after the award")
    noErrors()
end)

test("loot master overview shows answers, passes and missing players", function()
    setup(guild())
    W.inRaid = true
    W.raid = { "Cel Dru", "Lisa Brightwater", "Max Ironhide", "Anna Frost", "Ben Swift" }
    ns.StartAuction(W.link(51, "Gloves"))
    ns.RecordBid("Lisa Brightwater", "MS")
    ns.RecordBid("Max Ironhide", "MS")
    ns.RecordBid("Anna Frost", "OS")
    ns.RecordBid("Ben Swift", "PASS")
    local o = ns.AuctionOverview(ns.auction)
    eq(#o.ms, 2) eq(#o.os, 1) eq(#o.passed, 1)
    eq(#o.waiting, 1, "the loot master himself has not answered")
    eq(o.waiting[1], "Cel Dru-Forever")
    eq(o.winner.name, "Max Ironhide-Forever", "highest priority")
    -- changing your mind moves you between sections
    ns.RecordBid("Ben Swift", "MS")
    o = ns.AuctionOverview(ns.auction)
    eq(#o.passed, 0) eq(#o.ms, 3)
    -- custom price for this item
    assert(ns.SetAuctionPrice(42))
    eq(ns.auction.tier, "custom")
    ns.Award("Max Ironhide")
    W.flush()
    eq(note("Max Ironhide"), "1000,142", "custom price charged")
    noErrors()
end)

test("points live in the save file per guild, never in officer notes", function()
    setup(guild())
    ns.AwardEP({ "Lisa Brightwater" }, 100, "Raid night")
    W.flush()
    local data = RedGuildForeverDB.guilds["Redemption-Forever"]
    assert(data, "data for the guild")
    local ev = select(2, next(data.events))
    eq(ev.k, "P") eq(ev.ch[1].n, "Lisa Brightwater-Forever") eq(ev.ch[1].ep, 100)
    eq(ev.t, W.server, "server time of the change")
    eq(ev.by, "Cel Dru-Forever", "who changed it")
    eq(data.players["Lisa Brightwater-Forever"].ep, 1000, "the starting points stay")
    eq(note("Lisa Brightwater"), "1100,500", "points are the start plus the changes")
    for _, r in ipairs(W.roster) do eq(r[3], "", "officer note untouched") end
    -- another guild has its own data
    W.guildName = "Other Guild"
    eq(ns.HasData(), false)
    W.guildName = "Redemption"
    eq(ns.HasData(), true)
end)

test("without loaded data officers cannot change anything until sync or start fresh", function()
    setup({ { "Cel Dru", 0, "", "DRUID" }, { "Lisa Brightwater", 2, "", "PRIEST" } })
    ns.Data().started = nil
    eq(ns.HasData(), false)
    eq(ns.Adjust("Lisa Brightwater", 100, 0), nil, "blocked")
    assert(W.printed[#W.printed]:find("no EPGP data loaded yet"), W.printed[#W.printed])
    ns.Command("fresh")
    eq(W.popup, "REDGUILDFOREVER_FRESH", "asks before starting fresh")
    StaticPopupDialogs["REDGUILDFOREVER_FRESH"].OnAccept()
    eq(ns.HasData(), true)
    assert(ns.Adjust("Lisa Brightwater", 100, 0))
    eq(note("Lisa Brightwater"), "100,100")
end)

test("who may edit, guild leader, officer ranks and the guild info setting", function()
    setup(guild())
    W.rank = 0 eq(ns.CanEdit(), true, "guild leader")
    W.rank = 1 eq(ns.CanEdit(), true, "officer rank 1")
    W.rank = 2 eq(ns.CanEdit(), false, "rank 2 by default")
    W.guildInfo = "Welcome!\nEPGP officers 2"
    eq(ns.CanEdit(), true, "rank 2 after the guild leader allowed it")
    eq(ns.IsOfficer("Lisa Brightwater"), true, "Lisa is rank 2")
    W.rank = 3 eq(ns.CanEdit(), false)
end)

-- collect the data messages one editor would send with everything it has
local function dataMessages()
    W.comms = {}
    assert(ns.SendAllData(), "data sent")
    W.flush()
    local list = W.comms
    W.comms = {}
    return list
end

local function deliverFrom(list, sender)
    for _, c in ipairs(list) do
        ns.Fire("CHAT_MSG_ADDON", c.prefix, c.msg, c.channel, sender .. "-Forever")
    end
end

-- an editor sends these entries as one transfer
local function transferFrom(sender, entries, mode)
    local s = sender .. "-Forever"
    local textValue = table.concat(entries, ";")
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "H^77^" .. (mode or "L") .. "^-^-^-^-", "GUILD", s)
    local count = 0
    for i = 1, #textValue, 200 do
        count = count + 1
        ns.Fire("CHAT_MSG_ADDON", ns.prefix, "D^77^" .. count .. "^" .. textValue:sub(i, i + 199), "GUILD", s)
    end
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "E^77^" .. count, "GUILD", s)
end

------------------------------------------------------------------------
-- Several computers in one guild. Each has its own addon and save file,
-- messages go from one to the others.
------------------------------------------------------------------------
local function useComputer(c)
    _G.RedGuildForeverDB = c.db
    _G.RedGuildForeverBackup = c.backup
    _G.RedGuildForever = c.ns
    W.player, W.rank = c.name, c.rank
    W.context = c
end

local function network()
    _G.RedGuildForeverBackup = _G.RedGuildForeverBackup or {}
    local me = { name = W.player, rank = W.rank or 0, db = _G.RedGuildForeverDB, backup = _G.RedGuildForeverBackup, ns = ns }
    W.switch = useComputer
    W.context = me
    W.flush()
    W.comms = {}
    return me
end

-- another player logs in with the addon, copy = start with our starting points
local function addComputer(name, rank, copy)
    local back = W.context
    local base = {}
    for full, e in pairs(ns.RealData().players) do
        base[full] = { ep = e.ep, gp = e.gp, main = e.main, t = e.t }
    end
    local c = { name = name, rank = rank, ns = {}, db = {}, backup = {} }
    _G.RedGuildForeverDB = c.db
    _G.RedGuildForeverBackup = c.backup
    W.player, W.rank, W.context = name, rank, c
    W.load(c.ns)
    if copy then
        for full, e in pairs(base) do c.ns.Base()[full] = e end
        c.ns.RealData().started = true
        c.ns.Invalidate()
    end
    c.ns.RebuildFromRoster()
    useComputer(back)
    return c
end

-- deliver every message until nothing moves anymore. lose(c) drops a message.
local function deliverAll(computers, lose)
    local sent = {}
    for _ = 1, 500 do
        W.flush()
        local list = W.comms
        if #list == 0 then break end
        W.comms = {}
        local back = W.context
        for _, c in ipairs(list) do
            table.insert(sent, c)
            if not (lose and lose(c)) then
                for _, other in ipairs(computers) do
                    if other ~= c.from and (c.channel ~= "WHISPER" or c.target == other.name) then
                        useComputer(other)
                        other.ns.Fire("CHAT_MSG_ADDON", c.prefix, c.msg, c.channel, c.from.name .. "-Forever")
                    end
                end
            end
        end
        useComputer(back)
    end
    return sent
end

-- the points of a player on one computer, in the "ep,gp" style
local function noteOn(c, name)
    local back = W.context
    useComputer(c)
    local result = note(name)
    useComputer(back)
    return result
end

local function on(c, fn)
    local back = W.context
    useComputer(c)
    local r = fn()
    useComputer(back)
    return r
end

test("changes made at the same time on two computers both count", function()
    setup(guild())
    W.guildInfo = "EPGP officers 2" -- Anna Frost is rank 2 and an editor
    local me = network()
    local anna = addComputer("Anna Frost", 2, true)
    local computers = { me, anna }
    deliverAll(computers)
    -- both are offline from each other, for example in two different raids
    W.blockAddon = true
    ns.BeginAction("Lisa wins a ring", { kind = "loot", item = 30 })
    ns.Adjust("Lisa Brightwater", 0, 150)
    ns.EndAction()
    on(anna, function() return ns.AwardEP({ "Lisa Brightwater", "Max Ironhide" }, 100, "Raid night", "raid") end)
    W.flush()
    W.comms = {}
    eq(note("Lisa Brightwater"), "1000,650", "our change")
    eq(noteOn(anna, "Lisa Brightwater"), "1100,500", "Anna's change")
    -- back online, one sync later both computers have both changes
    W.blockAddon = false
    ns.Sync(true)
    deliverAll(computers)
    eq(note("Lisa Brightwater"), "1100,650", "both changes count on our computer")
    eq(noteOn(anna, "Lisa Brightwater"), "1100,650", "and on Anna's")
    eq(note("Max Ironhide"), "1100,100")
    eq(#ns.Log(), #on(anna, ns.Log), "the history is shared too")
    noErrors()
end)

test("a new computer gets everything and members never send", function()
    setup(guild())
    W.guildInfo = "EPGP officers 2"
    local me = network()
    ns.AwardEP({ "Lisa Brightwater", "Tom Spark" }, 100, "Raid night", "raid")
    ns.SetAlt("Ben Swift", "Max Ironhide")
    ns.BenchAdd("Anna Frost")
    StaticPopupDialogs["REDGUILDFOREVER_DECAY"].OnAccept()
    W.flush()
    W.comms = {}
    local ben = addComputer("Ben Swift", 3) -- rank 3, a member with an empty save file
    local sent = deliverAll({ me, ben })
    for _, name in ipairs({ "Lisa Brightwater", "Tom Hammer", "Max Ironhide", "Anna Frost" }) do
        eq(noteOn(ben, name), note(name), name .. " the same on Ben's computer")
    end
    eq(noteOn(ben, "Ben Swift"), "@Max Ironhide", "alt link arrived")
    eq(on(ben, ns.Bench)[1], "Anna Frost-Forever", "the bench is shared")
    for _, c in ipairs(sent) do
        if c.from == ben then assert(c.msg:match("^Q%^"), "a member only asks, sent " .. c.msg) end
    end
    noErrors()
end)

test("sync sends only what is missing", function()
    setup(guild())
    W.guildInfo = "EPGP officers 2"
    local me = network()
    local anna = addComputer("Anna Frost", 2, true)
    local computers = { me, anna }
    deliverAll(computers)
    -- the same data on both computers, a sync sends nothing but the questions
    ns.Sync(true)
    local sent = deliverAll(computers)
    for _, c in ipairs(sent) do assert(c.msg:match("^Q%^"), "nothing to send, sent " .. c.msg:sub(1, 30)) end
    -- one new change goes out by itself, as a small live transfer
    ns.Adjust("Lisa Brightwater", 10, 0)
    sent = deliverAll(computers)
    assert(#sent <= 4, "only the new change, " .. #sent .. " messages")
    eq(noteOn(anna, "Lisa Brightwater"), "1010,500")
    noErrors()
end)

test("a lost piece is asked for again", function()
    setup(guild())
    W.guildInfo = "EPGP officers 2"
    local me = network()
    local anna = addComputer("Anna Frost", 2, true)
    local computers = { me, anna }
    deliverAll(computers)
    local lost = false
    ns.Adjust("Lisa Brightwater", 25, 0)
    deliverAll(computers, function(c)
        if not lost and c.from == me and c.msg:match("^D%^") then lost = true return true end
    end)
    assert(lost, "a piece was dropped")
    -- the live transfer was incomplete, Anna asks again and gets it
    eq(noteOn(anna, "Lisa Brightwater"), "1025,500", "arrived on the second try")
    noErrors()
end)

test("a big guild goes out in small messages, a few per second", function()
    local roster = {}
    for i = 1, 400 do table.insert(roster, { "Player Number" .. i, 3, (i * 7) .. "," .. (100 + i), "WARRIOR" }) end
    table.insert(roster, 1, { "Cel Dru", 0, "", "DRUID" })
    table.insert(roster, 2, { "Anna Frost", 2, "", "MAGE" })
    setup(roster)
    W.guildInfo = "EPGP officers 2"
    local me = network()
    for i = 1, 60 do ns.Adjust("Player Number" .. i, i, 0) end
    W.flush()
    W.comms = {}
    local anna = addComputer("Anna Frost", 2)
    local start = W.now
    on(anna, function() return ns.Sync(true) end)
    local sent = deliverAll({ me, anna }) -- the mock refuses messages over 255 bytes
    assert(#sent > 40, "many messages, " .. #sent)
    assert(W.now - start >= #sent - 20, "about one message per second after the first few")
    eq(W.throttled, 0, "the game never had to refuse a message")
    eq(noteOn(anna, "Player Number60"), (420 + 60) .. ",160", "everything arrived")
    noErrors()
end)

test("data from members and blocked messages", function()
    setup(guild())
    set("Lisa Brightwater", "1000,500")
    transferFrom("Ben Swift", { "!P,abc123,1760000500,Ben Swift,,,Lisa Brightwater:5000:0,fake" })
    eq(note("Lisa Brightwater"), "1000,500", "Ben is a member, ignored")
    -- blocked messages wait and go out later
    W.flush()
    W.comms = {}
    W.blockAddon = true
    ns.Adjust("Lisa Brightwater", 1, 0)
    W.now = W.now + 0.5
    eq(#W.comms, 0, "nothing could go out")
    W.blockAddon = false
    W.flush()
    assert(#W.comms > 0, "sent when it works again")
end)

test("the sync button asks everyone and editors answer", function()
    setup(guild())
    W.comms = {}
    ns.Command("sync")
    W.flush()
    assert(W.comms[1].msg:match("^Q%^%d+%^%d+="), "asks with a digest " .. W.comms[1].msg)
    -- someone with an empty save file asks, we answer with everything
    W.comms = {}
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "Q^5^" .. ns.SyncCutoff() .. "=", "GUILD", "Ben Swift-Forever")
    W.flush()
    assert(W.comms[1].msg:match("^H%^%d+%^R%^5%^"), "answers the request " .. W.comms[1].msg)
    noErrors()
end)

test("backup export and import", function()
    setup(guild())
    ns.Adjust("Lisa Brightwater", 50, 0)
    local backup = ns.ExportText()
    assert(backup:match("^RGFEPGP2;Redemption%-Forever;"), backup:sub(1, 40))
    wipe(ns.Base()) wipe(ns.Data().events) ns.Invalidate()
    eq(note("Lisa Brightwater"), nil)
    local changes = ns.ImportText(backup)
    eq(changes, 6, "all players and the change back")
    eq(note("Lisa Brightwater"), "1050,500")
    eq(note("Tom Spark"), "@Tom Hammer")
    -- pasted with line breaks still works, and nothing is counted twice
    eq(ns.ImportText(backup:sub(1, 60) .. "\n" .. backup:sub(61)), 0)
    eq(note("Lisa Brightwater"), "1050,500")
    -- a backup of version 1.7
    wipe(ns.Base()) wipe(ns.Data().events) ns.Invalidate()
    eq(ns.ImportText("RGFEPGP1;Redemption-Forever;1;Lisa Brightwater,900,300,5;Tom Spark>Tom Hammer,5"), 2)
    eq(note("Lisa Brightwater"), "900,300")
    eq(select(2, ns.ImportText("hello")), "this is not a Red Guild EPGP backup")
    eq(select(2, ns.ImportText(backup:gsub("Redemption", "Other"))), "this backup belongs to Other-Forever")
    W.canEdit = false
    eq(select(2, ns.ImportText(backup)), "only the guild leader and editors can import")
end)

test("one time import of the old officer notes", function()
    setup({ { "Cel Dru", 0, "", "DRUID" }, { "Lisa Brightwater", 2, "", "PRIEST" }, { "Tom Spark", 2, "", "MAGE" } })
    wipe(ns.Players())
    ns.Data().started = nil
    W.roster[2][3] = "800,300 tank"
    W.roster[3][3] = "@Lisa Brightwater"
    eq(ns.ImportOfficerNotes(), 2)
    eq(note("Lisa Brightwater"), "800,300")
    eq(note("Tom Spark"), "@Lisa Brightwater")
    eq(ns.HasData(), true)
    eq(ns.ImportOfficerNotes(), 0, "does not overwrite data a second time")
end)

test("sync tab builds and shows the backup", function()
    setup(guild())
    ns.ToggleStandings(ns.TAB.data)
    ns.ToggleStandings(1)
    ns.ToggleStandings(ns.TAB.data)
    noErrors()
end)

test("corpse loot is listed, the window opens by itself only with the setting", function()
    setup(guild())
    W.inRaid = true
    local epic, junk = W.link(60, "Epic Helm"), W.link(61, "Gray Rag")
    W.loot = { { link = epic, quality = 4 }, { link = junk, quality = 0 } }
    ns.Fire("LOOT_OPENED")
    eq(#ns.lootSeen, 1, "only good items")
    eq(ns.lootSeen[1].onCorpse, true)
    eq(ns.picker, nil, "by default the window stays closed, you open it yourself")
    ns.Fire("LOOT_CLOSED")
    -- the setting in the Settings tab turns it on
    local view = ns.OpenSettings("settings")
    eq(view.autoLoot:GetChecked(), false, "off by default")
    view.autoLoot:SetChecked(true)
    view.autoLoot:Click()
    eq(ns.Setting("autoOpenLoot"), true)
    local epic2 = W.link(64, "Epic Gloves")
    W.loot = { { link = epic2, quality = 4 } }
    ns.Fire("LOOT_OPENED")
    assert(ns.picker and ns.picker:IsShown(), "window opened by itself")
    eq(ns.pickerState.link, epic2, "first corpse item is chosen")
    ns.Fire("LOOT_CLOSED")
    eq(ns.lootSeen[1].onCorpse, false, "still listed after closing the loot")
    -- opening the same corpse again does not add it twice
    ns.Fire("LOOT_OPENED")
    eq(#ns.lootSeen, 2)
    noErrors()
end)

test("loot window does not pop up when alone", function()
    setup(guild())
    W.loot = { { link = W.link(62, "Epic Boots"), quality = 4 } }
    ns.Fire("LOOT_OPENED")
    eq(ns.picker, nil, "no window when solo")
    eq(#ns.lootSeen, 1, "but the item is remembered")
end)

test("drag an item from the bags and start real bidding", function()
    setup(guild())
    W.inRaid = true
    W.raid = { "Cel Dru", "Lisa Brightwater" }
    ns.OpenPicker(false)
    local p = ns.picker
    W.cursor = W.link(63, "Dragged Ring")
    p.slot:GetScript("OnReceiveDrag")(p.slot)
    eq(ns.pickerState.link, W.link(63, "Dragged Ring"))
    eq(W.cursor, nil, "cursor cleared")
    p.tierButtons.boss:Click()
    eq(ns.pickerState.tier, "boss")
    p.start:Click()
    assert(ns.auction and not ns.auction.test, "real auction")
    eq(ns.auction.tier, "boss")
    eq(p:IsShown(), true, "the same window stays and shows the bids")
    eq(ns.pickerState.link, nil, "the slot is free for the next item")
    assert(p.primary:GetText():find("^Close bids now"), p.primary:GetText())
    local sent
    for _, c in ipairs(W.comms) do if c.msg:match("^A%^") then sent = true end end
    assert(sent, "raid got the auction")
    noErrors()
end)

-- the real data as text, to prove test mode never touches it
local function realSnapshot()
    local parts = {}
    for name, e in pairs(ns.RealData().players) do
        table.insert(parts, name .. "=" .. tostring(e.ep) .. "/" .. tostring(e.gp) .. "/" .. tostring(e.main) .. "/" .. tostring(e.t))
    end
    table.sort(parts)
    local bench, events = {}, 0
    for name, e in pairs(ns.RealData().bench) do table.insert(bench, name .. tostring(e.on)) end
    for _ in pairs(ns.RealData().events) do events = events + 1 end
    table.sort(bench)
    return table.concat(parts, ";") .. "|bench=" .. table.concat(bench, ",") .. "|events=" .. events .. "|log=" .. #RedGuildForeverDB.log
end

test("test mode is a sandbox for the whole addon", function()
    setup(guild())
    local before = realSnapshot()
    -- turn it on with the checkbox in the Settings tab
    local view = ns.OpenSettings("settings")
    view.test:SetChecked(true)
    view.test:Click()
    eq(ns.IsTest(), true)
    W.comms, W.chat = {}, {} -- only what happens from now on counts
    local raid = ns.RaidMembers()
    assert(#raid > 1, "simulated raid with guild members")
    eq(raid[1], "Cel Dru-Forever", "you are in it")
    eq(note("Lisa Brightwater"), "1000,500", "test data starts as a copy")

    -- every officer function works on the copy
    ns.Command("raid") W.flush()
    ns.Command("ontime") W.flush()
    ns.Command("bench add Anna") W.flush()
    ns.SetExactPoints("Max Ironhide", 2000, 300, "test edit")
    ns.SetAlt("Ben Swift", "Anna Frost")
    StaticPopupDialogs["REDGUILDFOREVER_DECAY"].OnAccept()
    ns.Command("undo")
    eq(note("Max Ironhide"), "2000,300", "edit in test data")

    -- bidding with the simulated raid, from the Loot Master button
    ns.OpenLootMaster()
    W.cursor = W.link(70, "Sandbox Sword")
    ns.picker.slot:GetScript("OnReceiveDrag")(ns.picker.slot)
    ns.picker.start:Click()
    local a = ns.auction
    assert(a and a.test, "auction in test mode")
    ns.SendBid(ns.incoming[a.id], "MS")
    W.flush()
    local o = ns.AuctionOverview(a)
    assert(#o.ms + #o.os + #o.passed > 1, "the simulated raid answered")
    local winner = ns.SortedBids(a)[1]
    local main = ns.MainOf(winner.name)
    local _, gpBefore = ns.GetPoints(main)
    ns.Award(winner.name) W.flush()
    local _, gpAfter = ns.GetPoints(main)
    if winner.spec == "MS" then assert(gpAfter > gpBefore, "GP charged in the test data") end

    -- sync is simulated
    ns.Command("sync") W.flush()
    assert(ns.syncInfo.from["Simulated Editor-Forever"], "simulated officer")

    -- nothing left this computer
    for _, c in ipairs(W.comms) do error("test mode sent an addon message " .. c.msg) end
    for _, c in ipairs(W.chat) do error("test mode wrote in " .. c.channel .. " " .. c.msg) end
    eq(realSnapshot(), before, "real data untouched while testing")

    -- turn it off again, the real data is back
    ns.SetTestMode(false)
    eq(ns.IsTest(), false)
    eq(note("Max Ironhide"), "1000,100", "real data again")
    eq(#ns.Bench(), 0, "real bench")
    eq(realSnapshot(), before, "real data untouched after testing")
    eq(ns.Undo(), nil, "test changes cannot be undone into the real data")
    noErrors()
end)

test("test mode keeps its data until reset", function()
    setup(guild())
    ns.SetTestMode(true)
    ns.SetExactPoints("Lisa Brightwater", 5, 100)
    ns.SetTestMode(false)
    ns.SetTestMode(true)
    eq(note("Lisa Brightwater"), "5,100", "test data kept")
    ns.ResetTestData()
    eq(note("Lisa Brightwater"), "1000,500", "reset copies the real data again")
end)

test("members can use every officer tool in test mode only", function()
    setup(guild())
    W.canEdit = false
    eq(ns.CanEdit(), false)
    ns.SetTestMode(true)
    eq(ns.CanEdit(), true, "officer tools in test mode")
    assert(ns.Adjust("Lisa Brightwater", 50, 0))
    ns.SetTestMode(false)
    eq(ns.CanEdit(), false)
    eq(note("Lisa Brightwater"), "1000,500")
end)

test("simulated players roll by themselves on a tie", function()
    setup(guild())
    set("Tom Hammer", "1000,500")
    ns.SetTestMode(true)
    ns.StartAuction(W.link(71, "Tie Ring"), "normal")
    local a = ns.auction
    wipe(a.bids)
    ns.RecordBid("Tom Hammer", "MS")
    ns.RecordBid("Lisa Brightwater", "MS")
    local seq, i = { 30, 70 }, 0
    local realRandom = math.random
    math.random = function(x, y) if x == 1 and y == 100 then i = i + 1 return seq[i] end return realRandom(x, y) end
    ns.CloseBidding()
    W.flush()
    math.random = realRandom
    eq(#ns.TiedForFirst(a), 0, "tie solved by simulated rolls")
    eq(ns.SortedBids(a)[1].roll, 70)
    noErrors()
end)

test("test mode cannot be switched during real bidding", function()
    setup(guild())
    W.inRaid = true
    ns.StartAuction(W.link(72, "Real Helm"))
    eq(ns.SetTestMode(true), false)
    eq(ns.IsTest(), false)
    ns.Award(nil)
    ns.SetTestMode(true)
    eq(ns.IsTest(), true)
end)

test("real messages from other players are ignored in test mode", function()
    setup(guild())
    W.guildInfo = "EPGP officers 2"
    set("Lisa Brightwater", "7777,100")
    local fromAnna = dataMessages()
    set("Lisa Brightwater", "1000,500")
    ns.SetTestMode(true)
    deliverFrom(fromAnna, "Anna Frost")
    eq(note("Lisa Brightwater"), "1000,500", "test data not changed by real sync")
    ns.SetTestMode(false)
    eq(note("Lisa Brightwater"), "1000,500", "real data not changed while testing")
end)

test("Loot Master button, settings and test mode in the menu", function()
    setup(guild())
    local menu = fakeMenu()
    ns.OpenMenu(ns.minimapButton)
    local texts = {}
    for _, item in ipairs(menu.items) do if item.text then texts[item.text] = item.fn end end
    assert(texts["Loot Master"], "Loot Master for officers")
    assert(texts["Settings"], "Settings for everyone")
    assert(not texts["|cffff8040Turn test mode off|r"], "no test entry while it is off")
    texts["Loot Master"]()
    assert(ns.lootFrame:IsShown(), "opens the loot window when nothing runs")
    ns.StartAuction(W.link(73, "Running Item"))
    ns.lootFrame:Hide()
    texts["Loot Master"]()
    eq(ns.lootFrame:IsShown(), true, "opens it again with the running bidding")
    eq(ns.lootFrame.item:GetText(), W.link(73, "Running Item"))
    ns.Award(nil)
    ns.SetTestMode(true)
    ns.OpenMenu(ns.minimapButton)
    texts = {}
    for _, item in ipairs(menu.items) do if item.text then texts[item.text] = item.fn end end
    assert(texts["|cffff8040Turn test mode off|r"], "quick way out of test mode")
    texts["|cffff8040Turn test mode off|r"]()
    eq(ns.IsTest(), false)
    ns.Command("test")
    eq(ns.IsTest(), true, "/rgf test toggles")
    noErrors()
end)

test("own name when the game returns first and last name separately", function()
    setup(guild())
    W.units.player = { "Cel", "Dru" }
    eq(ns.PlayerName(), "Cel Dru-Forever", "not Cel-Dru")
    eq(ns.ShortName(ns.PlayerName()), "Cel Dru")
    -- raid EP reaches your own character
    W.inRaid = true
    W.raid = { "Cel Dru" }
    ns.AwardEP(ns.RaidMembers(), 100, "Raid night")
    eq(note("Cel Dru"), "100,100")
    -- your own bid is listed under your real name
    ns.StartAuction(W.link(80, "Own Bid Helm"))
    ns.SendBid(ns.incoming[ns.auction.id], "MS")
    assert(ns.auction.bids["Cel Dru-Forever"], "own bid under Cel Dru")
    eq(ns.auction.bids["Cel-Dru-Forever"], nil)
    -- the standings window shows your priority
    ns.ToggleStandings(1)
    noErrors()
end)

test("own name is right even before the guild roster loaded", function()
    setup({})
    W.units.player = { "Cel", "Dru" }
    eq(ns.PlayerName(), "Cel Dru-Forever")
end)

test("targets and party members with first and last name", function()
    setup(guild())
    W.units.target = { "Anna", "Frost" }
    ns.ToggleStandings(ns.TAB.raid)
    ns.Command("edit")
    eq(ns.editor.target, "Anna Frost-Forever", "edit target")
    ns.BenchAdd(UnitIsPlayer("target") and ns.UnitFullName("target"))
    eq(ns.Bench()[1], "Anna Frost-Forever", "bench target")
    -- a group without raid, party members come from UnitName too
    W.inRaid = false
    _G.IsInGroup = function() return true end
    _G.GetNumGroupMembers = function() return 2 end
    W.units.party1 = { "Lisa", "Brightwater" }
    local list = ns.RaidMembers()
    eq(list[2], "Lisa Brightwater-Forever")
    noErrors()
end)

test("a real realm is still a realm", function()
    setup(guild())
    W.realms = { "Forever", "Otherrealm" }
    W.units.target = { "Some Stranger", "Otherrealm" }
    eq(ns.UnitFullName("target"), "Some Stranger-Otherrealm")
    W.units.target = { "Some", "Stranger" }
    eq(ns.UnitFullName("target"), "Some Stranger-Forever", "unknown second part is a last name")
end)

test("names written with a dash find the guild member", function()
    setup(guild())
    eq(ns.FindMember("Cel-Dru"), "Cel Dru-Forever")
    eq(ns.FindMember("Lisa-Brightwater-Forever"), "Lisa Brightwater-Forever")
    eq(ns.Resolve("Cel-Dru"), "Cel Dru-Forever")
    -- a whisper or addon message from "Cel-Dru" counts as Cel Dru
    W.inRaid = true
    ns.StartAuction(W.link(81, "Dash Ring"))
    ns.Fire("CHAT_MSG_WHISPER", "ms", "Lisa-Brightwater")
    assert(ns.auction.bids["Lisa Brightwater-Forever"], "whisper bid matched")
end)

-- type into a settings box like a player would
local function typeInto(box, value)
    box:SetText(value)
    box:GetScript("OnTextChanged")(box, true)
end

-- the view with the guild rules, in the Rules tab
local function settingsView()
    return ns.OpenSettings("rules")
end

test("rules start with the rule book values", function()
    setup(guild())
    eq(ns.Setting("baseGP"), 100) eq(ns.Setting("raidEP"), 100) eq(ns.Setting("onTimeEP"), 25)
    eq(ns.Setting("decayPercent"), 10) eq(ns.Setting("minEP"), 300) eq(ns.Setting("bidSeconds"), 30)
    local t = ns.Setting("tiers")
    eq(t.normal, 100) eq(t.boss, 150) eq(t.rare, 200)
    eq(ns.SlotMultiplier("INVTYPE_2HWEAPON"), 2)
    eq(ns.SlotMultiplier("INVTYPE_FINGER"), 0.75)
    eq(ns.SlotMultiplier(""), 1, "no slot")
    eq(ns.SlotMultiplier("INVTYPE_TABARD"), 0, "tabards stay free")
    eq(ns.OffSpecCost(300), 0, "off spec free by default")
end)

test("officers change prices in the settings and every price follows", function()
    setup(guild())
    W.itemSlots = { [90] = "INVTYPE_2HWEAPON", [91] = "INVTYPE_FINGER" }
    local view = settingsView()
    eq(view.ruleBoxes.tier_boss:GetText(), "150", "box shows the current value")
    eq(view.save:IsEnabled(), false, "nothing to save yet")
    typeInto(view.ruleBoxes.tier_boss, "175")
    typeInto(view.ruleBoxes.mult_twohand, "2,5") -- a comma works like a dot
    eq(view.save:IsEnabled(), true)
    assert(view.preview:GetText():find("438 GP"), view.preview:GetText())
    view.save:Click()
    assert(view.status:GetText():find("Saved 2 changes"), view.status:GetText())
    eq(ns.ItemPrice(W.link(90, "Axe"), "boss"), 438, "175 x 2.5")
    eq(ns.ItemPrice(W.link(91, "Ring"), "normal"), 75, "unchanged rules stay")
    local r = ns.Data().rules.tier_boss
    eq(r.v, 175) eq(r.t, W.server) eq(r.by, "Cel Dru-Forever")
    local log = ns.Log()
    assert(log[#log].label:find("Item from the end boss 150 to 175"), log[#log].label)
    eq(view.ruleBoxes.mult_twohand:GetText(), "2.5", "box shows the saved value")
    noErrors()
end)

test("wrong values are refused and nothing is saved", function()
    setup(guild())
    local view = settingsView()
    typeInto(view.ruleBoxes.baseGP, "0")
    typeInto(view.ruleBoxes.raidEP, "120")
    view.save:Click()
    assert(view.status:GetText():find("between 1 and 100000"), view.status:GetText())
    eq(ns.Setting("baseGP"), 100, "base GP unchanged, never 0")
    eq(ns.Setting("raidEP"), 100, "nothing saved when one value is wrong")
    eq(select(2, ns.SetRules({ decayPercent = "abc" })), "Weekly decay in percent must be a number")
    eq(select(2, ns.SetRules({ decayPercent = 150 })), "Weekly decay in percent must be between 0 and 100")
    view.discard:Click()
    eq(view.ruleBoxes.baseGP:GetText(), "100", "discard shows the saved values again")
end)

test("EP, decay, new member limit and bidding time follow the rules", function()
    setup(guild())
    assert(ns.SetRules({ raidEP = 150, onTimeEP = 10, decayPercent = 50, minEP = 100, bidSeconds = 45 }))
    W.inRaid = true
    W.raid = { "Cel Dru", "Lisa Brightwater" }
    ns.Command("raid") ns.Command("ontime") W.flush()
    eq(note("Lisa Brightwater"), "1160,500")
    eq(ns.IsNewMember("Tom Hammer"), false, "200 EP is no longer new with a limit of 100")
    ns.Decay() W.flush()
    eq(note("Lisa Brightwater"), "580,250", "50 percent decay")
    ns.StartAuction(W.link(92, "Timer Helm"))
    eq(ns.auction.endsAt - W.now, 45, "45 seconds to bid")
    noErrors()
end)

test("off spec can cost a part of the price", function()
    setup(guild())
    W.itemSlots = { [93] = "INVTYPE_CHEST" }
    assert(ns.SetRules({ offSpecPercent = 50 }))
    eq(ns.OffSpecCost(150), 75)
    W.inRaid = true
    ns.StartAuction(W.link(93, "Robe"), "normal")
    ns.RecordBid("Lisa Brightwater", "OS")
    ns.Award("Lisa Brightwater") W.flush()
    eq(note("Lisa Brightwater"), "1000,575", "half of 150")
    local said
    for _, c in ipairs(W.chat) do if c.msg:find("for off spec for 75 GP") then said = true end end
    assert(said, "announcement names the off spec price")
    noErrors()
end)

test("members can look at the rules but not change them", function()
    setup(guild())
    W.canEdit = false
    local view = settingsView()
    eq(view.ruleBoxes.tier_boss:IsEnabled(), false, "boxes locked")
    eq(view.defaults:IsEnabled(), false)
    assert(view.status:GetText():find("Only the guild leader and editors"), view.status:GetText())
    eq(ns.SetRules({ raidEP = 500 }), nil)
    eq(ns.Setting("raidEP"), 100)
end)

test("rules travel with sync, the newest change wins", function()
    setup(guild())
    W.guildInfo = "EPGP officers 2" -- Anna Frost counts as officer
    -- Anna changed the end boss price, we changed raid EP later
    assert(ns.SetRules({ tier_boss = 180 }))
    local fromAnna = dataMessages()
    ns.Data().rules = {}
    W.server = W.server + 10
    assert(ns.SetRules({ raidEP = 120 }))
    local changed
    ns.On("RGF_RULES_CHANGED", function() changed = true end)
    deliverFrom(fromAnna, "Anna Frost")
    eq(ns.Setting("tiers").boss, 180, "Anna's price arrived")
    eq(ns.Data().rules.tier_boss.by, "Anna Frost-Forever")
    eq(ns.Setting("raidEP"), 120, "our newer change stays")
    assert(changed, "settings page is told")
    noErrors()
end)

test("rules from sync outside the limits or from members are ignored", function()
    setup(guild())
    W.guildInfo = "EPGP officers 2"
    transferFrom("Anna Frost", { "#baseGP,0," .. (W.server + 5), "#unknown,5," .. (W.server + 5), "#raidEP,140," .. (W.server + 5) })
    eq(ns.Setting("baseGP"), 100, "a base GP of 0 is refused")
    eq(ns.Data().rules.unknown, nil)
    eq(ns.Setting("raidEP"), 140, "the valid rule arrives")
    -- Ben is rank 3, not an officer
    transferFrom("Ben Swift", { "#raidEP,999," .. (W.server + 50) })
    eq(ns.Setting("raidEP"), 140)
end)

test("fixed item prices are shared and clearing them too", function()
    setup(guild())
    W.guildInfo = "EPGP officers 2"
    W.itemSlots = { [94] = "INVTYPE_HAND" }
    local gloves = W.link(94, "Gloves")
    ns.Command("price " .. gloves .. " 250")
    eq(ns.ItemPrice(gloves), 250)
    local withPrice = dataMessages()
    W.server = W.server + 5
    ns.Command("price " .. gloves .. " clear")
    eq(ns.ItemPrice(gloves), 100, "normal price again")
    local cleared = dataMessages()
    -- another computer gets the price, then the clearing
    ns.Data().rules = {}
    deliverFrom(withPrice, "Anna Frost")
    eq(ns.ItemPrice(gloves), 250)
    deliverFrom(cleared, "Anna Frost")
    eq(ns.ItemPrice(gloves), 100, "clearing arrived")
    noErrors()
end)

test("fixed prices from older versions move into the guild rules", function()
    setup(guild())
    W.itemSlots = { [95] = "INVTYPE_HAND" }
    RedGuildForeverDB.priceOverrides[95] = 333
    ns.RebuildFromRoster()
    eq(ns.ItemPrice(W.link(95, "Old Gloves")), 333)
    eq(next(RedGuildForeverDB.priceOverrides), nil, "old list emptied")
    assert(ns.RealData().rules["item:95"].t, "time stamp for sync")
end)

test("rule changes in test mode stay in the test data", function()
    setup(guild())
    ns.SetTestMode(true)
    local view = settingsView()
    typeInto(view.ruleBoxes.raidEP, "999")
    view.save:Click()
    assert(view.status:GetText():find("test data"), view.status:GetText())
    eq(ns.Setting("raidEP"), 999)
    ns.SetTestMode(false)
    eq(ns.Setting("raidEP"), 100, "real rules untouched")
    eq(view.ruleBoxes.raidEP:GetText(), "100", "page shows the real rules again")
end)

test("reset to defaults asks first and is shared", function()
    setup(guild())
    assert(ns.SetRules({ tier_rare = 400, mult_small = 1 }))
    local view = settingsView()
    view.defaults:Click()
    eq(W.popup, "REDGUILDFOREVER_RESET_RULES")
    W.server = W.server + 1
    StaticPopupDialogs["REDGUILDFOREVER_RESET_RULES"].OnAccept()
    eq(ns.Setting("tiers").rare, 200) eq(ns.Setting("mult_small"), 0.75)
    eq(ns.Data().rules.tier_rare.t, W.server, "new time stamp, so sync passes the reset on")
    eq(view.ruleBoxes.tier_rare:GetText(), "200")
end)

test("rules are part of the backup", function()
    setup(guild())
    assert(ns.SetRules({ tier_boss = 160, mult_large = 1.25 }))
    local backup = ns.ExportText()
    ns.Data().rules = {}
    eq(ns.Setting("tiers").boss, 150)
    assert(ns.ImportText(backup))
    eq(ns.Setting("tiers").boss, 160)
    eq(ns.Setting("mult_large"), 1.25)
end)

test("members cannot change points", function()
    setup(guild())
    W.canEdit = false
    eq(ns.Adjust("Lisa Brightwater", 100, 0), nil)
    eq(ns.StartAuction(W.link(20, "Wand")), false)
    W.flush()
    eq(note("Lisa Brightwater"), "1000,500")
end)

------------------------------------------------------------------------
-- Editors picked by the guild leader
------------------------------------------------------------------------
local function syncFrom(sender, entries) transferFrom(sender, entries) end

test("the guild leader picks editors of any rank and the rank rule stops counting", function()
    setup(guild())
    W.guildInfo = "EPGP officers 2"
    eq(ns.IsEditor("Anna Frost"), true, "rank rule before the list is used")
    eq(ns.EditorsInUse(), false)
    W.rank = 0
    assert(ns.SetEditor("Ben Swift", true))
    eq(ns.EditorsInUse(), true)
    eq(ns.IsEditor("Ben Swift"), true, "rank 3 is an editor now")
    eq(ns.IsEditor("Anna Frost"), false, "the rank rule does not count anymore")
    eq(ns.IsEditor("Cel Dru"), true, "the guild leader always edits")
    eq(select(2, ns.SetEditor("Cel Dru", true)), "Cel Dru is the guild leader and can always edit")
    eq(select(2, ns.SetEditor("Ben Swift", true)), "Ben Swift is already an editor")
    -- an editor without officer rank can change data
    ns.EditorList()["Cel Dru-Forever"] = { on = true, t = W.server }
    W.rank = 4
    eq(ns.CanEdit(), true, "rank 4 editor")
    assert(ns.Adjust("Lisa Brightwater", 50, 0), "editor changes points")
    eq(ns.CanManageEditors(), false, "only the guild leader manages the list")
    eq(select(2, ns.SetEditor("Anna Frost", true)), "only the guild leader can add or remove editors")
    -- taking it away
    W.rank = 0
    assert(ns.SetEditor("Ben Swift", false))
    eq(ns.IsEditor("Ben Swift"), false)
    eq(ns.EditorsInUse(), true, "a removed editor keeps the list in use")
    eq(#ns.Editors(), 1)
    noErrors()
end)

test("starting the list from the current officer ranks", function()
    setup(guild())
    W.guildInfo = "EPGP officers 2"
    W.rank = 0
    eq(ns.AddRankEditors(), 5, "every rank 1 and 2 member")
    eq(ns.IsEditor("Anna Frost"), true)
    eq(ns.IsEditor("Ben Swift"), false, "rank 3 stays out")
    eq(ns.AddRankEditors(), 0, "nothing twice")
end)

test("the editor list travels with sync, only changes by the guild leader count", function()
    setup(guild())
    W.guildInfo = "EPGP officers 2" -- Anna counts as editor while the list is empty
    local t = W.server + 10
    syncFrom("Anna Frost", {
        "@Ben Swift,1," .. t .. ",Cel Dru",    -- made by the guild leader, Anna passes it on
        "@Tom Hammer,1," .. t .. ",Anna Frost", -- Anna made herself a list, not allowed
        "Lisa Brightwater,1234,500," .. t,
    })
    eq(ns.IsEditor("Ben Swift"), true, "change by the guild leader accepted")
    eq(ns.EditorList()["Tom Hammer-Forever"], nil, "change by an editor ignored")
    eq(note("Lisa Brightwater"), "1234,500", "points from Anna merged")
    eq(ns.IsEditor("Anna Frost"), false, "the list counts now")
    -- Anna is no editor anymore, Ben is
    syncFrom("Anna Frost", { "Max Ironhide,9999,100," .. (t + 5) })
    eq(note("Max Ironhide"), "1000,100", "data from a former editor ignored")
    syncFrom("Ben Swift", { "Max Ironhide,1500,100," .. (t + 5) })
    eq(note("Max Ironhide"), "1500,100", "rank 3 editor sends data")
    -- our own list goes out with our data and comes back from the backup
    W.rank = 0
    local backup = ns.ExportText()
    assert(backup:find("@Ben Swift,1," .. t .. ",Cel Dru", 1, true), backup)
    ns.Data().editors = {}
    assert(ns.ImportText(backup))
    eq(ns.IsEditor("Ben Swift"), true, "restored from the backup")
    noErrors()
end)

test("editor commands and the editor section in the settings", function()
    setup(guild())
    W.rank = 0
    ns.Command("editor add Ben")
    assert(W.printed[#W.printed]:find("Ben Swift is now an editor"), W.printed[#W.printed])
    ns.Command("editors")
    assert(W.printed[#W.printed]:find("Ben Swift"), W.printed[#W.printed])
    local view = ns.OpenSettings("settings")
    eq(view.addEditor:IsEnabled(), true, "leader can add")
    assert(view.editorList:GetText():find("Ben Swift"), view.editorList:GetText())
    view.editorBox:SetText("Anna")
    view.addEditor:Click()
    eq(ns.IsEditor("Anna Frost"), true, "added in the settings")
    view.editorBox:SetText("Anna")
    view.removeEditor:Click()
    eq(ns.IsEditor("Anna Frost"), false, "removed in the settings")
    W.rank = 3
    ns.Command("editor add Anna")
    assert(W.printed[#W.printed]:find("only the guild leader"), W.printed[#W.printed])
    ns.RefreshSettings()
    eq(view.addEditor:IsEnabled(), false, "locked for everyone else")
    noErrors()
end)

test("the Data tab has sync, decay and backup, the bottom strip only raid buttons", function()
    setup(guild())
    ns.ToggleStandings(ns.TAB.data)
    local f = ns.mainFrame
    assert(f, "window built")
    local page = f.pages[ns.TAB.data]
    eq(page.decay:IsShown(), true, "decay for editors with data")
    eq(page.notes:IsShown(), false, "old notes import only without data")
    eq(page.fresh:IsShown(), false)
    page.decay:Click()
    eq(W.popup, "REDGUILDFOREVER_DECAY", "decay asks first")
    W.canEdit = false
    ns.ToggleStandings(1) ns.ToggleStandings(ns.TAB.data)
    eq(page:IsShown(), false, "members do not get the Data tab")
    eq(f.selectedTab, ns.TAB.standings, "they stay on the standings")
    eq(f.lootMaster:IsShown(), false)
    noErrors()
end)

test("undo works after a reload and for changes of other editors", function()
    setup(guild())
    W.guildInfo = "EPGP officers 2"
    local me = network()
    local anna = addComputer("Anna Frost", 2, true)
    local computers = { me, anna }
    ns.AwardEP({ "Lisa Brightwater" }, 100, "Raid night", "raid")
    deliverAll(computers)
    -- a reload: a fresh addon on the same save file still knows the change
    local again = addComputer("Cel Dru", 0)
    again.db = me.db
    on(again, function()
        ns.Invalidate()
        local done = ns.Undo()
        assert(done and done.label:find("Raid night"), "undone after the reload")
    end)
    useComputer(me) ns.Invalidate()
    eq(note("Lisa Brightwater"), "1000,500")
    -- Anna undoes a change of ours from the History tab, the undo is shared
    ns.Adjust("Max Ironhide", 0, 200)
    deliverAll(computers)
    on(anna, function()
        ns.ToggleStandings(ns.TAB.history)
        local log = ns.Log()
        local id = log[#log].id
        eq(log[#log].label, "Max Ironhide +200 GP", "our Max change is the newest")
        assert(ns.UndoEvent(id), "undo from the history")
        eq(ns.Log()[#ns.Log() - 1].undone, true, "marked as undone")
    end)
    deliverAll(computers)
    eq(note("Max Ironhide"), "1000,100", "undone on our computer too")
    eq(ns.UndoEvent(ns.Log()[1].id), nil, "an undo cannot be undone twice")
    noErrors()
end)

test("raid EP and on time EP count once per night, also with two raids", function()
    setup(guild())
    W.guildInfo = "EPGP officers 2"
    local me = network()
    local anna = addComputer("Anna Frost", 2, true)
    local computers = { me, anna }
    ns.BenchAdd("Ben Swift")
    deliverAll(computers)
    -- two raids at the same time, the bench is shared
    W.inRaid = true
    W.raid = { "Cel Dru", "Lisa Brightwater" }
    ns.Command("raid")
    deliverAll(computers)
    W.raid = { "Anna Frost", "Max Ironhide", "Tom Spark" }
    on(anna, function() ns.Command("raid") end)
    deliverAll(computers)
    eq(note("Ben Swift"), "100,100", "the bench got raid EP once")
    deliverAll(computers)
    eq(note("Lisa Brightwater"), "1100,500")
    eq(note("Max Ironhide"), "1100,100")
    eq(note("Tom Hammer"), "300,100", "the alt Tom Spark gave EP to the main")
    -- the same raid twice by mistake
    W.raid = { "Cel Dru", "Lisa Brightwater" }
    ns.Command("raid")
    eq(note("Lisa Brightwater"), "1100,500", "not twice")
    assert(W.printed[#W.printed]:find("already got raid night EP tonight"), W.printed[#W.printed])
    -- on time is its own kind, and the next night counts again
    ns.Command("ontime")
    eq(note("Lisa Brightwater"), "1125,500")
    W.server = W.server + 13 * 3600
    ns.Command("raid")
    eq(note("Lisa Brightwater"), "1225,500", "next night")
    noErrors()
end)

test("an alt brings its points to the main, undo takes them back", function()
    setup(guild())
    set("Ben Swift", "300,250")
    assert(ns.SetAlt("Ben Swift", "Max Ironhide"))
    eq(note("Max Ironhide"), "1300,250", "EP and the GP above the start move over")
    eq(note("Ben Swift"), "@Max Ironhide")
    assert(ns.Undo())
    eq(note("Max Ironhide"), "1000,100", "the link is undone")
    eq(note("Ben Swift"), "300,250", "Ben has his own points again")
    noErrors()
end)

------------------------------------------------------------------------
-- Whispers and automatic backups
------------------------------------------------------------------------
local function whisper(text, from)
    W.chat = {}
    ns.Fire("CHAT_MSG_WHISPER", text, (from or "Ben Swift") .. "-Forever")
    local answers = {}
    for _, c in ipairs(W.chat) do
        if c.channel == "WHISPER" then table.insert(answers, c.msg) end
    end
    W.now = W.now + 3 -- the next whisper is not too fast
    return answers, table.concat(answers, " | ")
end

test("whisper commands for players without the addon", function()
    setup(guild())
    local _, a = whisper("!ep", "Lisa Brightwater")
    eq(a, "Lisa Brightwater: 1000 EP, 500 GP, priority 2.00, place 3 of 4.")
    _, a = whisper("!ep max")
    assert(a:find("^Max Ironhide: 1000 EP, 100 GP, priority 10.00, place 1 of 4"), a)
    _, a = whisper("!ep Tom")
    assert(a:find("More than one player matches Tom: Tom Hammer, Tom Spark"), a)
    _, a = whisper("!EP Tom Spark")
    assert(a:find("uses the points of Tom Hammer"), a)
    assert(a:find("New member until 300 EP"), a)
    _, a = whisper("!ep", "Ben Swift")
    assert(a:find("^Ben Swift: 0 EP, 100 GP, priority 0.00"), a)
    _, a = whisper("!top")
    eq(a, "Top 4: 1. Max Ironhide 10.00, 2. Anna Frost 2.50, 3. Lisa Brightwater 2.00, 4. Tom Hammer 2.00")
    _, a = whisper("!top mages")
    eq(a, "Top 1 mages: 1. Anna Frost 2.50")
    _, a = whisper("!top bards")
    eq(a, "I do not know the class bards.")
    _, a = whisper("!bid")
    eq(a, "No bidding is open right now.")
    _, a = whisper("!help")
    assert(a:find("!ep") and a:find("ms, os or pass"), a)
    -- not a command, and too fast after the last one
    local list = whisper("hello there")
    eq(#list, 0)
    whisper("!ep")
    W.now = W.now - 3
    list = whisper("!ep")
    eq(#list, 0, "one answer every two seconds")
    -- in test mode real whispers get no answer
    ns.SetTestMode(true)
    list = whisper("!ep", "Max Ironhide")
    eq(#list, 0)
    noErrors()
end)

test("whisper bids always get an answer, and the winner a whisper", function()
    setup(guild())
    W.inRaid = true
    W.raid = { "Cel Dru", "Lisa Brightwater", "Max Ironhide" }
    local _, a = whisper("ms", "Lisa Brightwater")
    eq(a, "No bidding is open right now. Wait for the announcement in raid chat.")
    local list = whisper("+", "Lisa Brightwater")
    eq(#list, 0, "a + for a raid invite gets no answer")
    ns.StartAuction(W.link(50, "Ring of Answers"))
    _, a = whisper("!bid")
    assert(a:find("Ring of Answers%]|h|r for 100 GP, 30 seconds left") and a:find("Whisper me ms, os or pass"), a)
    _, a = whisper("MS ", "Lisa Brightwater")
    assert(a:find("Got your main spec bid"), a)
    ns.CloseBidding()
    _, a = whisper("os", "Max Ironhide")
    assert(a:find("is closed already"), a)
    W.chat = {}
    ns.Award("Lisa Brightwater")
    local told
    for _, c in ipairs(W.chat) do
        if c.channel == "WHISPER" and c.target == "Lisa Brightwater" then told = c.msg end
    end
    eq(told, "You got " .. W.link(50, "Ring of Answers") .. " for 100 GP. Your priority is now 1.67 (1000 EP, 600 GP).")
    noErrors()
end)

test("automatic backups, and the newest comes back when the save file is empty", function()
    setup(guild())
    eq(ns.AutoBackup("test"), true, "first backup")
    eq(ns.AutoBackup("test"), false, "nothing changed, no second copy")
    for i = 1, 4 do
        ns.Adjust("Lisa Brightwater", i, 0)
        assert(ns.AutoBackup("test"))
    end
    eq(#RedGuildForeverBackup.list, 3, "the newest three are kept")
    -- changes and logging out make a backup by themselves
    ns.Adjust("Lisa Brightwater", 100, 0)
    ns.Fire("PLAYER_LOGOUT")
    local newest = ns.LatestAutoBackup()
    assert(newest.text:find("Lisa Brightwater:100:0"), "the newest change is in it")
    -- the main save file comes back empty
    RedGuildForeverDB.guilds = {}
    ns.Invalidate()
    eq(ns.HasData(), false)
    ns.RebuildFromRoster()
    eq(ns.HasData(), true, "restored by itself")
    eq(note("Lisa Brightwater"), "1110,500")
    assert(W.printed[#W.printed - 0]:find("automatic backup") or W.printed[#W.printed - 1]:find("automatic backup"), W.printed[#W.printed])
    noErrors()
end)

------------------------------------------------------------------------
-- Several items at once, raid nights and loot lists
------------------------------------------------------------------------
local function raidChat()
    local lines = {}
    for _, c in ipairs(W.chat) do if c.channel == "RAID" then table.insert(lines, c.msg) end end
    return table.concat(lines, " | ")
end

test("bidding on several items at once", function()
    setup(guild())
    W.inRaid = true
    W.raid = { "Cel Dru", "Lisa Brightwater", "Max Ironhide", "Anna Frost" }
    W.itemSlots = { [81] = "INVTYPE_FINGER", [82] = "INVTYPE_HEAD", [83] = "INVTYPE_HAND" }
    W.chat = {}
    eq(ns.StartAuctions({ { W.link(81, "Ring A"), "normal" }, { W.link(82, "Helm B"), "boss" }, { W.link(83, "Gloves C"), "normal" } }), 3)
    local chat = raidChat()
    assert(chat:find("Bids open for 1%. .-Ring A.- 75 GP, 2%. .-Helm B.- 225 GP, 3%. .-Gloves C.- 100 GP"), chat)
    assert(chat:find("whisper me ms 1, os 3 or pass 1 with the number"), chat)
    eq(select(2, chat:gsub("Bids open", "")), 1, "one announcement")
    for _, c in ipairs(W.chat) do assert(#c.msg <= 255, "raid line too long") end
    eq(#ns.OpenAuctions(), 3)
    -- a whisper without a number is not clear
    local _, a = whisper("ms", "Lisa Brightwater")
    assert(a:find("Several items are open: 1 .-Ring A.-, 2 .-Helm B.-, 3 .-Gloves C"), a)
    _, a = whisper("ms 2", "Lisa Brightwater")
    assert(a:find("Got your main spec bid for .-Helm B"), a)
    _, a = whisper("os 3", "Max Ironhide")
    assert(a:find("off spec bid for .-Gloves C"), a)
    -- an addon bid goes to the right item
    local helm = ns.auctions[2]
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "B^" .. helm.id .. "^MS", "WHISPER", "Max Ironhide-Forever")
    eq(helm.bids["Max Ironhide-Forever"].spec, "MS")
    eq(ns.auctions[1].bids["Max Ironhide-Forever"], nil, "not on the ring")
    -- the Loot Master window switches between the items
    ns.OpenLootMaster()
    local lm = ns.lootFrame
    local row = lm.items:Row(2)
    eq(row.auction, helm, "the items are listed on the left")
    row:Click()
    eq(ns.auction, helm, "a click shows the helm")
    eq(lm.item:GetText(), helm.link)
    -- all close after the bidding time, awarding one shows the next
    W.flush()
    eq(#ns.OpenAuctions(), 0, "closed by the timer")
    ns.Award("Max Ironhide")
    eq(note("Max Ironhide"), "1000,325", "the helm costs the end boss price")
    eq(#ns.auctions, 2)
    eq(ns.auction, ns.auctions[1], "the next item is shown")
    -- a new item gets the free number
    local new = ns.StartAuction(W.link(84, "Cloak D"))
    eq(new.n, 2, "number 2 is free again")
    ns.CancelAllAuctions()
    eq(#ns.auctions, 0)
    noErrors()
end)

test("ties on two items at once, each roll counts once", function()
    setup(guild())
    set("Tom Hammer", "1000,500") -- ties with Lisa
    W.inRaid = true
    W.raid = { "Cel Dru", "Lisa Brightwater", "Tom Hammer" }
    ns.StartAuctions({ { W.link(85, "Belt E") }, { W.link(86, "Boots F") } })
    for _, a in ipairs(ns.auctions) do
        ns.RecordBid("Lisa Brightwater", "MS", a)
        ns.RecordBid("Tom Hammer", "MS", a)
    end
    W.flush()
    local belt, boots = ns.auctions[1], ns.auctions[2]
    assert(belt.rollsOpen and boots.rollsOpen, "both need rolls")
    ns.Fire("CHAT_MSG_SYSTEM", "Lisa Brightwater rolls 90 (1-100)")
    ns.Fire("CHAT_MSG_SYSTEM", "Tom Hammer rolls 10 (1-100)")
    eq(belt.bids["Lisa Brightwater-Forever"].roll, 90)
    eq(boots.bids["Lisa Brightwater-Forever"].roll, nil, "the first roll is for the first item")
    ns.Fire("CHAT_MSG_SYSTEM", "Lisa Brightwater rolls 5 (1-100)")
    ns.Fire("CHAT_MSG_SYSTEM", "Tom Hammer rolls 60 (1-100)")
    eq(ns.SortedBids(belt)[1].name, "Lisa Brightwater-Forever")
    eq(ns.SortedBids(boots)[1].name, "Tom Hammer-Forever")
    noErrors()
end)

test("bid cards: one per item, stacked, with the priority after a win", function()
    setup(guild())
    W.canEdit = false
    W.rank = 5
    W.player = "Lisa Brightwater" -- 1000 EP, 500 GP
    ns.RebuildFromRoster()
    local a1 = "A^111111^30^100^1^" .. W.link(87, "First")
    local a2 = "A^222222^30^500^2^" .. W.link(88, "Second")
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, a1, "RAID", "Anna Frost")
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, a2, "RAID", "Anna Frost")
    local c1, c2 = ns.bidCards[1], ns.bidCards[2]
    assert(c1:IsShown() and c2:IsShown(), "both items have a card at once")
    eq(c1.inc.id, "111111") eq(c2.inc.id, "222222")
    assert(c1.item:GetText():find("^1%. "), "numbered when several are open")
    -- what a win would cost: 1000 / 500 = 2.00 now, 1000 / 600 = 1.67 after the first item
    assert(c1.note:GetText():find("100 GP%.  Your priority |cffffd1002%.00|r, after a win |cffffd1001%.67|r"), c1.note:GetText())
    assert(c2.note:GetText():find("after a win |cffffd1001%.00|r"), c2.note:GetText())
    -- answering one card keeps the other
    W.comms = {}
    c1.ms:Click()
    eq(W.comms[1].msg, "B^111111^MS")
    eq(ns.bidCards[1].inc.id, "222222", "the second item moves down")
    eq(ns.bidCards[2]:IsShown(), false)
    ns.bidCards[1].pass:Click()
    eq(ns.bidCards[1]:IsShown(), false, "nothing left")
    eq(#W.comms, 1, "a pass without a bid sends nothing")
    -- the key bindings answer the first card
    ns.Command("rebid")
    eq(ns.bidCards[1].inc.id, "111111")
    assert(ns.AnswerFirstBid("OS"))
    eq(W.comms[#W.comms].msg, "B^111111^OS")
    -- without addon messages the whisper names the item number
    W.blockAddon = true
    W.chat = {}
    ns.SendBid(ns.incoming["222222"], "OS")
    eq(W.chat[1].msg, "os 2")
    noErrors()
end)

test("an item the character cannot use, and cards that remember their place", function()
    setup(guild())
    W.canEdit = false
    W.rank = 5
    _G.C_PlayerInfo = { CanUseItem = function(id) return id ~= 90 end }
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "A^313131^30^100^1^" .. W.link(90, "Plate Helm"), "RAID", "Anna Frost")
    local c = ns.bidCards[1]
    eq(c.ms:IsEnabled(), false, "main spec is greyed out")
    eq(c.os:IsEnabled(), true)
    assert(c.note:GetText():find("You cannot use this item"), c.note:GetText())
    eq(ns.AnswerFirstBid("MS"), false, "the key does nothing either")
    -- drag the card somewhere else, the place is saved
    c:GetScript("OnDragStart")(c)
    local mover = c:GetParent()
    eq(RedGuildForeverDB.positions and RedGuildForeverDB.positions.bid, nil, "default place at first")
    mover:ClearAllPoints()
    mover:SetPoint("CENTER", UIParent, "CENTER", 120, -40)
    c:GetScript("OnDragStop")(c)
    eq(table.concat(RedGuildForeverDB.positions.bid, ","), "CENTER,120,-40")
    ns.Command("resetpos")
    eq(next(RedGuildForeverDB.positions), nil, "back to the start")
    eq(select(1, mover:GetPoint()), "BOTTOM")
    noErrors()
end)

test("Start Bidding can open all items of the corpse at once", function()
    setup(guild())
    W.inRaid = true
    W.raid = { "Cel Dru", "Lisa Brightwater" }
    _G.IsInGroup = function() return true end
    W.loot = { { link = W.link(91, "Epic One"), quality = 4 }, { link = W.link(92, "Rare Two"), quality = 3 },
        { link = W.link(93, "Green Three"), quality = 2 } }
    ns.Fire("LOOT_OPENED")
    ns.OpenPicker()
    local p = ns.picker
    assert(p:IsShown(), "opened by hand")
    eq(p.startAll:GetText(), "Bid on all 2", "rare and better items")
    p.startAll:Click()
    eq(#ns.OpenAuctions(), 2)
    eq(ns.auctions[1].link, W.link(91, "Epic One"), "in the order of the corpse")
    eq(p:IsShown(), true, "the window stays and shows the first item")
    eq(ns.auction, ns.auctions[1])
    noErrors()
end)

test("a raid night with start, end, leavers and the loot list", function()
    setup(guild())
    W.inRaid = true
    W.raid = { "Cel Dru", "Lisa Brightwater", "Max Ironhide" }
    ns.BenchAdd("Ben Swift")
    ns.ToggleStandings(ns.TAB.raid)
    local page = ns.mainFrame.pages[ns.TAB.raid]
    eq(page.toggle:GetText(), "Start raid")
    page.toggle:Click()
    assert(ns.Session(), "raid running")
    eq(note("Lisa Brightwater"), "1025,500", "on time EP at the start")
    eq(note("Ben Swift"), "25,100", "and for the bench")
    eq(page.toggle:GetText(), "End raid")
    -- Tom joins later, Max leaves early
    W.raid = { "Cel Dru", "Lisa Brightwater", "Max Ironhide", "Tom Spark" }
    ns.Fire("GROUP_ROSTER_UPDATE")
    W.raid = { "Cel Dru", "Lisa Brightwater", "Tom Spark" }
    ns.Fire("GROUP_ROSTER_UPDATE")
    -- loot during the raid
    ns.StartAuction(W.link(94, "Raid Gloves"))
    ns.RecordBid("Tom Spark", "MS")
    ns.Award("Tom Spark")
    ns.StartAuction(W.link(95, "Raid Ring"))
    ns.Award("Lisa Brightwater")
    page.toggle:Click()
    eq(ns.Session(), nil, "raid finished")
    eq(note("Lisa Brightwater"), "1125,600", "raid EP at the end")
    eq(note("Tom Hammer"), "300,200", "the alt in the raid gave EP to the main")
    eq(note("Max Ironhide"), "1025,100", "Max left early, only the on time EP")
    eq(W.popup, "REDGUILDFOREVER_LEAVERS", "asks about the players who left")
    StaticPopupDialogs["REDGUILDFOREVER_LEAVERS"].OnAccept()
    eq(note("Max Ironhide"), "1125,100", "Max gets it after the question")
    -- the loot list
    local loot = ns.RaidLoot(ns.LastSession())
    eq(#loot, 2)
    eq(loot[1].name, "Lisa Brightwater-Forever", "newest first")
    local textValue = ns.RaidLootText()
    assert(textValue:find("4 players, 2 items"), textValue)
    assert(textValue:find("Raid Gloves  Tom Spark  100 GP\nRaid Ring  Lisa Brightwater  100 GP"), textValue)
    page.copy:Click()
    eq(ns.copyFrame.box:GetText(), textValue, "copy window for Discord")
    -- loot of a player, the alt counts for the main
    local items = ns.LootOf("Tom Hammer")
    eq(#items, 1) eq(items[1].name, "Tom Spark-Forever")
    local _, a = whisper("!loot Tom Hammer")
    assert(a:find("^Tom Hammer: %d%d%.%d%d%. .-Raid Gloves.- 100 GP"), a)
    -- an undone award leaves the list
    ns.Command("undo")
    eq(#ns.RaidLoot(ns.LastSession()), 2, "undo took back the leavers EP first")
    ns.Command("undo") ns.Command("undo") -- the raid EP, then the ring
    eq(#ns.RaidLoot(ns.LastSession()), 1, "the undone ring is gone")
    ns.ToggleStandings(1)
    noErrors()
end)

test("the weekly decay reminds when it is due and warns before a second one", function()
    setup(guild())
    W.guildInfo = "EPGP officers 2"
    eq(ns.DecayDue(), false, "no changes yet, nothing is due")
    ns.Adjust("Lisa Brightwater", 10, 0)
    W.server = W.server + 8 * 86400
    eq(ns.DecayDue(), true, "a week after the first change")
    W.printed = {}
    ns.Fire("RGF_READY") W.flush()
    local said
    for _, p in ipairs(W.printed) do if p:find("the weekly decay is due, there was none yet") then said = true end end
    assert(said, "reminder after login")
    eq(ns.RemindDecay(), false, "only once per session")
    -- the decay, then a second one by mistake on another computer
    ns.Command("decay")
    eq(W.popup, "REDGUILDFOREVER_DECAY")
    StaticPopupDialogs["REDGUILDFOREVER_DECAY"].OnAccept()
    eq(ns.DecayDue(), false, "done for this week")
    W.server = W.server + 2 * 86400
    ns.Command("decay")
    eq(W.popup, "REDGUILDFOREVER_DECAY_AGAIN", "warns, the last one was two days ago")
    ns.ToggleStandings(ns.TAB.data)
    assert(ns.mainFrame.pages[ns.TAB.data].state:GetText():find("Last decay on %d%d%.%d%d%. by Cel Dru"), ns.mainFrame.pages[ns.TAB.data].state:GetText())
    W.server = W.server + 6 * 86400
    ns.Command("decay")
    eq(W.popup, "REDGUILDFOREVER_DECAY", "a week later it asks normally")
    noErrors()
end)

test("standings search, class filter and the Discord text", function()
    setup(guild())
    ns.ToggleStandings(ns.TAB.standings)
    local page = ns.mainFrame.pages[ns.TAB.standings]
    eq(#page.shown, 4)
    page.search:SetText("to")
    page.search:GetScript("OnTextChanged")(page.search)
    eq(#page.shown, 1, "Tom Hammer")
    eq(page.shown[1].name, "Tom Hammer-Forever")
    page.search:SetText("")
    page.search:GetScript("OnTextChanged")(page.search)
    -- without a menu system the class button steps through the classes
    _G.MenuUtil = nil
    ns.SetStandingsClass("MAGE")
    eq(#page.shown, 1) eq(page.shown[1].name, "Anna Frost-Forever")
    eq(page.class:GetText(), "Mage")
    page.discord:Click()
    local textValue = ns.copyFrame.box:GetText()
    assert(textValue:find("^Standings of Redemption on %d%d%.%d%d%.%d%d%d%d, Mage\n1%. Anna Frost  2%.50  %(500 EP, 200 GP%)"), textValue)
    ns.SetStandingsClass(nil)
    ns.Command("discord")
    assert(ns.copyFrame.box:GetText():find("4%. Tom Hammer  2%.00  %(200 EP, 100 GP%) new"), ns.copyFrame.box:GetText())
    noErrors()
end)

test("a popup shows the winner for a few seconds and can be turned off", function()
    setup(guild())
    W.inRaid = true
    W.raid = { "Cel Dru", "Lisa Brightwater", "Max Ironhide" }
    -- another loot master awards two items, the raid gets the popup
    local ring, helm = W.link(96, "Winner Ring"), W.link(97, "Winner Helm")
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "A^333333^30^75^1^" .. ring, "RAID", "Anna Frost")
    W.timers = {}
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "C^333333^Lisa Brightwater-Forever^75^MS^" .. ring, "RAID", "Anna Frost")
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "C^444444^Cel Dru-Forever^0^OS^" .. helm, "RAID", "Anna Frost")
    local f = ns.winnerFrame
    assert(f and f:IsShown(), "popup shown")
    eq(f.title:GetText(), "Lisa Brightwater wins")
    eq(f.item:GetText(), ring)
    eq(f.detail:GetText(), "Main spec, 75 GP")
    -- after five seconds the next winner, also for an item we had no bid popup for
    eq(#W.timers, 1)
    eq(W.timers[1].due - W.now, 5, "stays five seconds")
    local t = table.remove(W.timers, 1)
    t.fn()
    eq(f.title:GetText(), "You win")
    eq(f.detail:GetText(), "Off spec, free")
    f:Click()
    eq(f:IsShown(), false, "a click closes it")
    -- the loot master sees it for his own award, once
    ns.StartAuction(W.link(98, "Own Item"))
    ns.RecordBid("Max Ironhide", "MS")
    W.comms = {}
    ns.Award("Max Ironhide")
    eq(f:IsShown(), true)
    eq(f.title:GetText(), "Max Ironhide wins")
    local sent
    for _, c in ipairs(W.comms) do if c.msg:match("^C%^%d+%^Max Ironhide%-Forever%^100%^MS%^|c") then sent = true end end
    assert(sent, "the raid is told the winner, the price and the item")
    W.deliver(ns)
    W.flush()
    eq(f:IsShown(), false, "gone by itself, and not shown twice")
    -- nothing for the bank
    ns.StartAuction(W.link(99, "Bank Item"))
    ns.Award(nil)
    eq(f:IsShown(), false)
    -- turned off in the settings
    local view = ns.OpenSettings("settings")
    eq(view.showWinner:GetChecked(), true, "on by default")
    view.showWinner:SetChecked(false)
    view.showWinner:Click()
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "C^555555^Lisa Brightwater-Forever^75^MS^" .. ring, "RAID", "Anna Frost")
    eq(f:IsShown(), false, "no popup when it is turned off")
    noErrors()
end)

test("the game's message allowance: sync never blocks an auction", function()
    setup(guild())
    W.inRaid = true
    W.raid = { "Cel Dru", "Lisa Brightwater" }
    W.flush()
    W.comms = {}
    -- a long sync transfer starts, only a part of the allowance is used at once
    for i = 1, 40 do ns.SendComm("X^" .. i, "GUILD", nil, true) end
    eq(#W.comms, 7, "ten are allowed at once, three stay free for auctions")
    assert(ns.QueuedMessages() > 30, "the rest waits")
    -- an auction still goes out right away
    ns.StartAuction(W.link(71, "Urgent Ring"))
    local out
    for _, c in ipairs(W.comms) do if c.msg:match("^A%^") then out = true end end
    assert(out, "the auction went out at once")
    ns.CancelAllAuctions()
    W.flush()
    eq(ns.QueuedMessages(), 0, "everything is out in the end")
    eq(W.throttled, 0, "and the game never refused a message")
    noErrors()
end)

test("during a boss fight messages wait, bids fall back to a whisper", function()
    setup(guild())
    W.inRaid = true
    W.raid = { "Cel Dru", "Lisa Brightwater" }
    W.flush()
    W.comms = {}
    W.lockdown = true
    local a = ns.StartAuction(W.link(72, "Locked Ring"))
    eq(#W.comms, 0, "the game takes no addon messages now")
    eq(ns.QueuedMessages(), 1, "the auction waits")
    -- a raider's bid cannot wait, it goes as a normal whisper
    W.chat = {}
    ns.SendBid({ id = "999999", owner = "Anna Frost-Forever", ownerRaw = "Anna Frost", n = 1 }, "MS")
    eq(W.chat[1].msg, "ms 1")
    -- the fight is over
    W.lockdown = false
    W.now = W.now + 3
    local t = table.remove(W.timers, 1)
    while t and #W.comms == 0 do t.fn() t = table.remove(W.timers, 1) end
    assert(W.comms[1] and W.comms[1].msg:match("^A%^" .. a.id), "sent after the fight")
    ns.CancelAllAuctions()
    noErrors()
end)

test("/rgf check reports the game version and missing functions", function()
    setup(guild())
    _G.GetBuildInfo = function() return "1.60.1", "70888", "Nov 4 2026", 16001 end
    _G.GetItemInfoInstant = nil
    W.printed = {}
    local needed = ns.SelfCheck()
    eq(#needed, 0, "the simulated game has everything: " .. table.concat(needed, ", "))
    assert(W.printed[1]:find("game 1.60.1 %(build 70888, interface 16001%)"), W.printed[1])
    assert(W.printed[2]:find("game functions the addon needs are there"), W.printed[2])
    -- a function that is gone shows up by name
    local keep = _G.GetLootSlotLink
    _G.GetLootSlotLink = nil
    needed = ns.SelfCheck()
    eq(needed[1], "GetLootSlotLink")
    _G.GetLootSlotLink = keep
    ns.Command("check")
    assert(W.printed[#W.printed]:find("guild Redemption%-Forever, you can edit, 5 players, 0 changes"), W.printed[#W.printed])
end)

test("settings and rules are in the game's Options, not in the addon window", function()
    setup(guild())
    -- two pages under AddOns: the settings, and the guild rules below them
    eq(W.categories[1].name, "Red Guild EPGP")
    eq(W.categories[1].addon, true, "listed under AddOns")
    eq(W.categories[2].name, "Guild rules")
    eq(W.categories[2].parent, W.categories[1], "a page below the settings")
    local view = ns.OpenSettings("settings")
    eq(W.openedCategory, W.categories[1], "the game's Options open on our page")
    assert(view.test and view.showWinner and view.editorBox, "test mode, interface and editors")
    eq(next(view.ruleBoxes), nil, "no rules on the settings page")
    local rules = ns.OpenSettings("rules")
    eq(W.openedCategory, W.categories[2])
    assert(rules.ruleBoxes.raidEP, "the rules page has the rules")
    eq(rules.test, nil)
    -- commands and the minimap menu lead there
    W.openedCategory = nil
    ns.Command("settings")
    eq(W.openedCategory, W.categories[1])
    ns.Command("rules")
    eq(W.openedCategory, W.categories[2])
    local menu = fakeMenu()
    ns.OpenMenu(ns.minimapButton)
    W.openedCategory = nil
    for _, item in ipairs(menu.items) do if item.text == "Settings" then item.fn() end end
    eq(W.openedCategory, W.categories[1])
    for _, item in ipairs(menu.items) do if item.text == "Guild rules" then item.fn() end end
    eq(W.openedCategory, W.categories[2])
    -- the addon window only has the four tabs for the game itself
    ns.ToggleStandings(ns.TAB.data)
    eq(#ns.mainFrame.pages, 5)
    eq(ns.TAB.settings, nil) eq(ns.TAB.rules, nil)
    -- during a fight the game refuses to open the Options, the addon says where to click
    _G.Settings.OpenToCategory = function() error("blocked in combat") end
    ns.Command("rules")
    assert(W.printed[#W.printed]:find("open the game's Options, then AddOns, then Red Guild EPGP, Guild rules"), W.printed[#W.printed])
end)

test("a game without the Options API gets a small settings window", function()
    setup(guild())
    _G.Settings = nil
    ns.optionViews.settings, ns.optionViews.rules = nil, nil
    local fresh = {}
    W.install() W.reset()
    W.player = "Cel Dru"
    W.roster = guild()
    _G.Settings = nil
    W.load(fresh)
    fresh.RebuildFromRoster()
    local view = fresh.OpenSettings("rules")
    assert(view and view.ruleBoxes.raidEP, "rules in an own window")
    assert(fresh.OpenSettings("settings").test, "settings in an own window")
end)

test("the bid popup closes after Main Spec or Off Spec, /rgf rebid brings it back", function()
    setup(guild())
    W.canEdit = false
    W.rank = 5
    local ring = W.link(89, "Closing Ring")
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "A^121212^30^100^1^" .. ring, "RAID", "Anna Frost")
    local p = ns.bidPopup
    eq(p:IsShown(), true)
    W.comms, W.printed = {}, {}
    p.ms:Click()
    eq(p:IsShown(), false, "gone after the bid")
    eq(W.comms[1].msg, "B^121212^MS", "the bid was sent")
    assert(W.printed[#W.printed]:find("you bid main spec on .-Closing Ring.-/rgf rebid"), W.printed[#W.printed])
    -- a price change does not bring it back
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "P^121212^150", "RAID", "Anna Frost")
    eq(p:IsShown(), false)
    -- changing the bid
    ns.Command("rebid")
    eq(p:IsShown(), true, "shown again")
    eq(p.inc.id, "121212")
    eq(p.inc.price, 150, "with the new price")
    W.comms = {}
    p.os:Click()
    eq(W.comms[1].msg, "B^121212^OS")
    eq(p:IsShown(), false, "and gone again")
    -- nothing open anymore
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "C^121212^", "RAID", "Anna Frost")
    ns.Command("rebid")
    assert(W.printed[#W.printed]:find("no bidding is open right now"), W.printed[#W.printed])
    eq(p:IsShown(), false)
    noErrors()
end)

test("one loot window: next step button, full list, confirmation, Alt click", function()
    setup(guild())
    W.inRaid = true
    W.raid = { "Cel Dru", "Lisa Brightwater", "Max Ironhide", "Anna Frost" }
    _G.IsInGroup = function() return true end
    local ring, helm = W.link(51, "One Window Ring"), W.link(52, "One Window Helm")
    -- Alt click in the bags chooses the item and opens the window
    eq(ns.AltClickItem("not a link"), false)
    assert(ns.AltClickItem(ring), "Alt click takes the item")
    local f = ns.lootFrame
    eq(f:IsShown(), true)
    eq(ns.pickerState.link, ring)
    eq(f.primary:GetText(), "Start bidding", "the big button is the next step")
    eq(f.closeBids:IsEnabled(), false, "nothing to close yet")
    f.primary:Click()
    local a = ns.auction
    assert(a and a.link == ring, "bidding started with one click")
    assert(f.primary:GetText():find("^Close bids now"), f.primary:GetText())
    -- bids come in, the full list is always there
    ns.RecordBid("Lisa Brightwater", "MS")
    ns.RecordBid("Max Ironhide", "MS")
    ns.RecordBid("Anna Frost", "OS")
    local names = {}
    for i = 1, 8 do
        local row = f.list:Row(i)
        local bid = rawget(row, "bid")
        if row:IsShown() and bid then table.insert(names, ns.ShortName(bid.name)) end
    end
    eq(table.concat(names, ","), "Max Ironhide,Lisa Brightwater,Anna Frost", "everyone in the list, best first")
    -- a second item while the first runs: the left side lists both
    assert(ns.AltClickItem(helm))
    eq(f.items:Row(1).auction, a, "the running bidding first")
    eq(f.items:Row(2).item.link, helm, "then the item that waits")
    eq(f.primary:GetText(), "Start bidding")
    f.items:Row(1):Click()
    f.primary:Click() -- Close bids now
    eq(a.open, false)
    eq(f.primary:GetText(), "Award to Max Ironhide  (main spec, 100 GP)", "the winner is one click away")
    -- awarding asks first
    W.popup = nil
    f.primary:Click()
    eq(W.popup, "REDGUILDFOREVER_AWARD", "asks before the award")
    eq(note("Max Ironhide"), "1000,100", "nothing given yet")
    StaticPopupDialogs["REDGUILDFOREVER_AWARD"].OnAccept()
    eq(note("Max Ironhide"), "1000,200", "given after the yes")
    -- anyone in the list can get it instead, and the question can be turned off
    ns.SetSetting("confirmAward", false)
    f.items:Row(1):Click() -- the helm that waits
    eq(ns.pickerState.link, helm)
    f.primary:Click()
    local b = ns.auction
    eq(b.link, helm)
    ns.RecordBid("Lisa Brightwater", "OS", b)
    ns.CloseBidding(b)
    local lisaRow
    for i = 1, 6 do
        local row = f.list:Row(i)
        local bid = rawget(row, "bid")
        if bid and bid.name == "Lisa Brightwater-Forever" then lisaRow = row end
    end
    lisaRow.award:Click()
    eq(#ns.auctions, 0, "awarded right away without the question")
    eq(f:IsShown(), false, "nothing left to do, the window closes")
    -- members and solo players get no Alt click
    W.canEdit = false
    eq(ns.AltClickItem(ring), false)
    noErrors()
end)

test("a calmer main window: members see the standings only, your own row, bars and tooltips", function()
    setup(guild())
    ns.ToggleStandings(ns.TAB.standings)
    local f = ns.mainFrame
    local page = f.pages[ns.TAB.standings]
    -- editors have all four tabs
    for i = 1, 5 do eq(f.Tabs[i]:IsShown(), true, "tab " .. i .. " for editors") end
    -- your own row, also when the list is filtered to something else
    eq(page.mine.entry.name, "Cel Dru-Forever")
    assert(page.mine.cells.name:GetText():find("Cel Dru  |cffffd100%(you%)"), page.mine.cells.name:GetText())
    ns.Adjust("Cel Dru", 400, 0)
    eq(page.mine.cells.ep:GetText(), 400)
    eq(page.mine.cells.place:GetText(), 2, "second place: 4.00, behind Max with 10.00")
    ns.SetStandingsClass("MAGE")
    eq(#page.shown, 1)
    eq(page.mine.entry.name, "Cel Dru-Forever", "still there with a class filter")
    eq(page.list:Row(1).cells.place:GetText(), 3, "Anna keeps her real place in a filtered list")
    ns.SetStandingsClass(nil)
    -- the bar: the best priority is full, the others a part of it
    eq(page.list:Row(1).entry.name, "Max Ironhide-Forever")
    eq(page.list:Row(1).barShare, 1)
    near(page.list:Row(2).barShare, 0.4, "Cel Dru has 4.00 of 10.00")
    -- the buttons say what they do
    eq(f.raidEP:GetText(), "+100 EP raid")
    eq(f.ontime:GetText(), "+25 EP on time")
    assert(ns.SetRules({ raidEP = 120 }))
    eq(f.raidEP:GetText(), "+120 EP raid", "follows the guild rules")
    -- and their tooltips say who gets it
    W.inRaid = true
    W.raid = { "Cel Dru", "Lisa Brightwater" }
    ns.BenchAdd("Max Ironhide")
    local lines = {}
    _G.GameTooltip.AddLine = function(_, line) table.insert(lines, line) end
    f.raidEP:GetScript("OnEnter")(f.raidEP)
    eq(lines[1], "3 players get 120 EP: Cel Dru, Lisa Brightwater, Max Ironhide")
    ns.Command("raid")
    lines = {}
    f.raidEP:GetScript("OnEnter")(f.raidEP)
    eq(lines[1], "0 players get 120 EP: nobody")
    eq(lines[2], "Already got it tonight: Cel Dru, Lisa Brightwater, Max Ironhide")
    -- members: no tabs, always the standings
    W.canEdit = false
    ns.ToggleStandings(ns.TAB.history)
    eq(f.selectedTab, ns.TAB.standings)
    eq(f.Tabs[ns.TAB.standings]:IsShown(), true)
    eq(f.Tabs[ns.TAB.loot]:IsShown(), true, "members get the loot history too")
    for i = 3, 5 do eq(f.Tabs[i]:IsShown(), false, "no tab " .. i .. " for members") end
    eq(f.pages[ns.TAB.history]:IsShown(), false)
    eq(f.standingsButtons:IsShown(), false)
    noErrors()
end)

test("welcome on the first login only, key bindings and a quieter chat", function()
    setup(guild())
    -- setup ran the timers of the first login
    assert(ns.welcomeFrame and ns.welcomeFrame:IsShown(), "welcome shown on the first login")
    assert(ns.welcomeFrame.body:GetText():find("You are an editor"), "editors get their own line")
    eq(RedGuildForeverDB.welcomed, true)
    ns.welcomeFrame.ok:Click()
    eq(ns.welcomeFrame:IsShown(), false)
    -- the next login stays quiet
    ns.Fire("RGF_READY") W.flush()
    eq(ns.welcomeFrame:IsShown(), false, "only once")
    ns.Command("welcome")
    eq(ns.welcomeFrame:IsShown(), true, "/rgf welcome shows it again")
    ns.welcomeFrame:Hide()
    -- key bindings: the names exist for every binding in Bindings.xml
    local xml = io.open("Bindings.xml"):read("*a")
    local count = 0
    for name in xml:gmatch('name="([A-Z_]+)"') do
        count = count + 1
        assert(_G["BINDING_NAME_" .. name], "a name for the key binding " .. name)
    end
    eq(count, 5)
    assert(_G.BINDING_HEADER_REDGUILDFOREVER, "a heading in the key binding settings")
    for _, file in ipairs(W.tocFiles()) do assert(file ~= "Bindings.xml", "the game loads Bindings.xml by itself") end
    RedGuildForever_Binding("toggle")
    eq(ns.mainFrame:IsShown(), true, "the key opens the standings")
    RedGuildForever_Binding("toggle")
    eq(ns.mainFrame:IsShown(), false)
    W.inRaid = true
    W.raid = { "Cel Dru", "Lisa Brightwater" }
    RedGuildForever_Binding("loot")
    eq(ns.lootFrame:IsShown(), true, "the key opens the loot window")
    -- bidding by key, and the rebid hint only once
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "A^414141^30^100^1^" .. W.link(53, "Key Ring"), "RAID", "Anna Frost")
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "A^424242^30^100^2^" .. W.link(54, "Key Helm"), "RAID", "Anna Frost")
    W.comms, W.printed = {}, {}
    RedGuildForever_Binding("ms")
    eq(W.comms[1].msg, "B^414141^MS")
    RedGuildForever_Binding("os")
    eq(W.comms[2].msg, "B^424242^OS")
    local hints = 0
    for _, p in ipairs(W.printed) do if p:find("/rgf rebid") then hints = hints + 1 end end
    eq(hints, 1, "the hint about changing a bid comes once")
    -- a manual sync prints one line, the result
    W.printed = {}
    ns.Command("sync") W.flush()
    eq(#W.printed, 1)
    assert(W.printed[1]:find("sync done"), W.printed[1])
    noErrors()
end)

test("loot history: who bid and who got it, apart from the EPGP history", function()
    setup(guild())
    W.inRaid = true
    W.raid = { "Cel Dru", "Lisa Brightwater", "Max Ironhide", "Anna Frost", "Tom Hammer" }
    set("Tom Hammer", "1000,500") -- ties with Lisa
    ns.SetSetting("confirmAward", false)
    local ring, helm, junk = W.link(31, "History Ring"), W.link(32, "History Helm"), W.link(33, "History Junk")
    -- a ring with a tie, Lisa wins the roll
    ns.StartAuction(ring)
    ns.RecordBid("Lisa Brightwater", "MS")
    ns.RecordBid("Tom Hammer", "MS")
    ns.RecordBid("Anna Frost", "OS")
    ns.RecordBid("Max Ironhide", "PASS")
    ns.CloseBidding()
    ns.Fire("CHAT_MSG_SYSTEM", "Lisa Brightwater rolls 77 (1-100)")
    ns.Fire("CHAT_MSG_SYSTEM", "Tom Hammer rolls 12 (1-100)")
    ns.Award("Lisa Brightwater")
    W.server = W.server + 60
    -- a helm for off spec, and junk nobody wants
    ns.StartAuction(helm)
    ns.RecordBid("Anna Frost", "OS")
    ns.Award("Anna Frost")
    W.server = W.server + 60
    ns.StartAuction(junk)
    ns.Award(nil)

    local list = ns.LootHistory()
    eq(#list, 3)
    eq(list[1].itemName, "History Junk", "newest first")
    eq(list[1].winner, nil, "nobody took it")
    local l = list[3]
    eq(l.winner, "Lisa Brightwater-Forever") eq(l.cost, 100) eq(l.spec, "MS")
    eq(#l.bids, 4, "everyone who answered")
    eq(l.bids[1].n, "Lisa Brightwater-Forever") eq(l.bids[1].s, "MS") eq(l.bids[1].roll, 77)
    near(l.bids[1].pr, 2.0, "the priority before she paid")
    eq(l.bids[2].n, "Tom Hammer-Forever") eq(l.bids[2].roll, 12)
    eq(l.bids[3].s, "OS") eq(l.bids[4].s, "PASS")

    -- filters
    eq(#ns.FilterLoot(list, { text = "helm" }), 1, "by item")
    eq(#ns.FilterLoot(list, { text = "tom" }), 1, "by a bidder who did not win")
    eq(#ns.FilterLoot(list, { text = "anna" }), 2, "as bidder and as winner")
    eq(#ns.FilterLoot(list, { mine = true }), 0, "we did not bid")
    W.server = W.server + 8 * 86400
    eq(#ns.FilterLoot(ns.LootHistory(), { days = 7 }), 0, "older than a week")
    eq(#ns.FilterLoot(ns.LootHistory(), { days = 30 }), 3)

    -- the Loot history tab
    ns.ToggleStandings(ns.TAB.loot)
    local page = ns.mainFrame.pages[ns.TAB.loot]
    eq(#page.shown, 3)
    eq(page.list:Row(1).cells.winner:GetText(), "|cff999999Bank or disenchant|r")
    eq(page.list:Row(3).cells.bids:GetText(), 3, "three wanted the ring")
    page.list:Row(3):Click()
    local d = page.detail
    eq(d.title:GetText(), ring)
    assert(d.sub:GetText():find("Won by |cffffffffLisa Brightwater|r for 100 GP, main spec"), d.sub:GetText())
    eq(d.list:Row(1).cells.name:GetText(), "Lisa Brightwater")
    eq(d.list:Row(1).cells.note:GetText(), "|cffffd100Winner|r")
    eq(d.list:Row(1).cells.roll:GetText(), 77)
    eq(d.list:Row(2).cells.pr:GetText(), "2.00")
    eq(d.list:Row(4).cells.spec:GetText(), "|cff999999Pass|r")
    -- search and time in the tab
    page.search:SetText("helm")
    page.search:GetScript("OnTextChanged")(page.search)
    eq(#page.shown, 1)
    eq(d.title:GetText(), helm, "the detail follows the list")
    page.search:SetText("")
    page.search:GetScript("OnTextChanged")(page.search)
    page.period:Click()
    eq(page.period:GetText(), "Last 7 days")
    eq(#page.shown, 0)
    eq(d:IsShown(), false)
    page.period:Click() page.period:Click()
    eq(page.period:GetText(), "All time")
    -- take an award back from the loot history
    page.list:Row(3):Click()
    eq(note("Lisa Brightwater"), "1000,600")
    d.undo:Click()
    eq(note("Lisa Brightwater"), "1000,500", "the GP are back")
    eq(page.list:Row(3).cells.spec:GetText(), "|cff808080taken back|r", "the item stays, marked")
    eq(d.undo:IsShown(), false)

    -- the EPGP history has no loot, unless asked for
    ns.AwardEP({ "Lisa Brightwater" }, 100, "Raid night", "raid")
    ns.ToggleStandings(ns.TAB.history)
    local h = ns.mainFrame.pages[ns.TAB.history]
    eq(h.shownCount, 2, "the raid EP and the undo, no loot awards")
    h.withLoot:SetChecked(true) h.withLoot:Click()
    eq(h.shownCount, 4, "with the two awards")
    h.search:SetText("raid night")
    h.search:GetScript("OnTextChanged")(h.search)
    eq(h.shownCount, 1)

    -- loot records travel with sync and the backup, and change no points
    local backup = ns.ExportText()
    assert(backup:find("!L,%x+,%d+,Cel Dru,31,Lisa Brightwater,100,MS,%x+,Lisa Brightwater:MS:2.00:77/Tom Hammer:MS:2.00:12/Anna Frost:OS:2.50:/Max Ironhide:PASS:10.00:,"), "the record with its bids is in the backup")
    local before = note("Anna Frost")
    wipe(ns.Data().events) ns.Invalidate()
    assert(ns.ImportText(backup))
    eq(#ns.LootHistory(), 3, "back from the backup")
    eq(ns.LootHistory()[3].bids[1].roll, 77)
    eq(note("Anna Frost"), before)
    noErrors()
end)

test("loot records are not sent to versions that do not know them", function()
    setup(guild())
    W.inRaid = true
    W.raid = { "Cel Dru", "Lisa Brightwater" }
    ns.SetSetting("confirmAward", false)
    ns.StartAuction(W.link(34, "Record Ring"))
    ns.RecordBid("Lisa Brightwater", "MS")
    ns.Award("Lisa Brightwater")
    W.flush()
    local cutoff = ns.SyncCutoff()
    local digest = ns.SyncDigest(cutoff)
    assert(digest:find("V3:0:0"), "our digest carries the version mark")
    local lootKey = digest:match("(L%d+):1:")
    assert(lootKey, "loot records have their own bucket: " .. digest)
    -- version 2.3 asks: same points, no version mark, no loot bucket
    local old = digest:gsub(",?" .. lootKey .. ":%d+:%d+", ""):gsub(",?V3:0:0", "")
    W.comms = {}
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "Q^7^" .. cutoff .. "=" .. old, "GUILD", "Ben Swift-Forever")
    W.flush()
    eq(#W.comms, 0, "nothing to send to the older version")
    -- a current version without the record gets it
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "Q^8^" .. cutoff .. "=" .. old .. ",V3:0:0", "GUILD", "Ben Swift-Forever")
    W.flush()
    local sent
    for _, c in ipairs(W.comms) do if c.msg:find("!L,", 1, true) then sent = true end end
    assert(sent, "the loot record goes to a version that knows it")
    noErrors()
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
