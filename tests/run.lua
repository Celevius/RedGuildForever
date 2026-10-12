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
    local players = ns.Players()
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
    ns.RebuildFromRoster()
    W.flush()
end

-- change the saved data of a player directly, like another officer did
local function set(name, value)
    local info = ns.ParseNote(value)
    W.server = W.server + 1
    ns.Players()[ns.FullName(name)] = info.main and { main = info.main, t = W.server }
        or { ep = info.ep, gp = info.gp, t = W.server }
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
    ns.ToggleStandings(2)
    ns.ToggleStandings(3)
    ns.ToggleStandings(1)
    W.canEdit, W.canView = false, false
    ns.RebuildFromRoster() W.flush()
    ns.ToggleStandings(2)
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
    ns.ToggleStandings(3)
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
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "A^123456^30^100^" .. W.link(41, "Ring"), "RAID", "Lisa Brightwater")
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
    assert(texts["Standings"] and texts["Bench"] and texts["History"], "window entries")
    assert(texts["Give raid EP (100)"], "officer entries for officers")
    assert(texts["Hide minimap button"], "hide entry")
    -- every entry runs without errors
    W.inRaid = true W.raid = { "Cel Dru", "Lisa Brightwater" }
    for _, item in ipairs(menu.items) do
        if item.fn and item.text ~= "Hide minimap button" and item.text ~= "Undo last change" then
            item.fn() W.flush()
        end
    end
    eq(note("Lisa Brightwater"), "1125,500", "raid EP and on time EP from the menu")
    eq(W.popup, "REDGUILDFOREVER_DECAY", "decay asks first")
    texts["Undo last change"]() W.flush()
    eq(note("Lisa Brightwater"), "1100,500", "undo from the menu takes back the on time EP")
    noErrors()
end)

test("members see no officer entries in the menu", function()
    setup(guild())
    W.canEdit = false
    local menu = fakeMenu()
    ns.OpenMenu(ns.minimapButton)
    for _, item in ipairs(menu.items) do
        assert(not (item.text or ""):find("raid EP"), "officer entry shown to a member")
    end
end)

test("menu falls back to the window without a menu system", function()
    setup(guild())
    _G.MenuUtil = nil
    ns.OpenMenu(ns.minimapButton)
    noErrors()
end)

test("minimap button can be hidden, shown and dragged", function()
    setup(guild())
    local menu = fakeMenu()
    ns.OpenMenu(ns.minimapButton)
    for _, item in ipairs(menu.items) do if item.text == "Hide minimap button" then item.fn() end end
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
    local log = RedGuildForeverDB.log
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
    local e = data.players["Lisa Brightwater-Forever"]
    eq(e.ep, 1100) eq(e.gp, 500)
    eq(e.t, W.server, "server time of the change")
    eq(e.by, "Cel Dru-Forever", "who changed it")
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

-- collect the data messages one officer would send
local function dataMessages()
    W.comms = {}
    assert(ns.SendData(), "data sent")
    local list = W.comms
    W.comms = {}
    return list
end

local function deliverFrom(list, sender)
    for _, c in ipairs(list) do
        ns.Fire("CHAT_MSG_ADDON", c.prefix, c.msg, c.channel, sender .. "-Forever")
    end
end

test("sync merges the newest change of each player", function()
    setup(guild())
    W.guildInfo = "EPGP officers 2" -- Anna Frost is rank 2 and counts as officer
    -- this is what Anna has, Lisa got loot on her computer
    set("Lisa Brightwater", "1000,700")
    local fromAnna = dataMessages()
    -- our computer has an older Lisa but a newer Max
    ns.Players()["Lisa Brightwater-Forever"].t = W.server - 50
    ns.Players()["Lisa Brightwater-Forever"].gp = 500
    set("Max Ironhide", "1200,100")
    deliverFrom(fromAnna, "Anna Frost")
    eq(note("Lisa Brightwater"), "1000,700", "newer Lisa from Anna wins")
    eq(note("Max Ironhide"), "1200,100", "our newer Max stays")
    eq(note("Tom Spark"), "@Tom Hammer", "alt links come along")
    eq(ns.syncInfo.from["Anna Frost-Forever"], true)
    -- we have something newer, so we answer with our data
    W.flush()
    local answered
    for _, c in ipairs(W.comms) do if c.msg:match("^DB") then answered = true end end
    assert(answered, "sends own data back")
    noErrors()
end)

test("sync from a member who is not an officer is ignored", function()
    setup(guild())
    set("Lisa Brightwater", "99999,100")
    local fake = dataMessages()
    set("Lisa Brightwater", "1000,500")
    deliverFrom(fake, "Ben Swift") -- rank 3
    eq(note("Lisa Brightwater"), "1000,500")
end)

test("members keep a copy and never send data", function()
    setup(guild())
    set("Lisa Brightwater", "1500,500")
    local fromOfficer = dataMessages()
    -- now we are a normal member with old data
    W.canEdit = false
    W.guildInfo = "EPGP officers 2"
    ns.Players()["Lisa Brightwater-Forever"] = { ep = 1000, gp = 500, t = 1 }
    deliverFrom(fromOfficer, "Anna Frost")
    eq(note("Lisa Brightwater"), "1500,500", "member copy updated")
    W.comms = {}
    ns.Sync(true)
    W.flush()
    for _, c in ipairs(W.comms) do
        assert(not c.msg:match("^D[BDE]"), "a member sent data")
    end
    eq(W.comms[1].msg, "SQ", "a member only asks")
end)

test("the sync button asks everyone and officers answer", function()
    setup(guild())
    W.comms = {}
    ns.Command("sync")
    W.flush()
    local asked, sent
    for _, c in ipairs(W.comms) do
        if c.msg == "SQ" then asked = true end
        if c.msg:match("^DB") then sent = true end
    end
    assert(asked and sent, "asks and sends own data")
    -- someone else asks, we answer
    W.comms = {}
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "SQ", "GUILD", "Ben Swift-Forever")
    W.flush()
    sent = false
    for _, c in ipairs(W.comms) do if c.msg:match("^DB") then sent = true end end
    assert(sent, "answers a sync request")
    noErrors()
end)

test("a big guild fits in addon messages", function()
    local roster = {}
    for i = 1, 400 do table.insert(roster, { "Player Number" .. i, 3, (i * 7) .. "," .. (100 + i), "WARRIOR" }) end
    table.insert(roster, 1, { "Cel Dru", 0, "", "DRUID" })
    setup(roster)
    assert(ns.SendData()) -- the mock asserts 255 bytes per message
end)

test("backup export and import", function()
    setup(guild())
    local backup = ns.ExportText()
    assert(backup:match("^RGFEPGP1;Redemption%-Forever;"), backup:sub(1, 40))
    wipe(ns.Players())
    eq(note("Lisa Brightwater"), nil)
    local changes = ns.ImportText(backup)
    eq(changes, 5, "all players back")
    eq(note("Lisa Brightwater"), "1000,500")
    eq(note("Tom Spark"), "@Tom Hammer")
    -- pasted with line breaks still works
    wipe(ns.Players())
    eq(ns.ImportText(backup:sub(1, 60) .. "\n" .. backup:sub(61)), 5)
    eq(select(2, ns.ImportText("hello")), "this is not a Red Guild EPGP backup")
    eq(select(2, ns.ImportText(backup:gsub("Redemption", "Other"))), "this backup belongs to Other-Forever")
    W.canEdit = false
    eq(select(2, ns.ImportText(backup)), "only the guild leader and officers can import")
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
    ns.ToggleStandings(4)
    ns.ToggleStandings(1)
    ns.ToggleStandings(4)
    noErrors()
end)

test("corpse loot shows up and opens the window in a group", function()
    setup(guild())
    W.inRaid = true
    local epic, junk = W.link(60, "Epic Helm"), W.link(61, "Gray Rag")
    W.loot = { { link = epic, quality = 4 }, { link = junk, quality = 0 } }
    ns.Fire("LOOT_OPENED")
    eq(#ns.lootSeen, 1, "only good items")
    eq(ns.lootSeen[1].onCorpse, true)
    assert(ns.picker and ns.picker:IsShown(), "window opened by itself")
    eq(ns.pickerState.link, epic, "first corpse item is chosen")
    ns.Fire("LOOT_CLOSED")
    eq(ns.lootSeen[1].onCorpse, false, "still listed after closing the loot")
    -- opening the same corpse again does not add it twice
    ns.Fire("LOOT_OPENED")
    eq(#ns.lootSeen, 1)
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
    eq(p:IsShown(), false, "window closes")
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
    return table.concat(parts, ";") .. "|bench=" .. table.concat(RedGuildForeverDB.bench, ",") .. "|log=" .. #RedGuildForeverDB.log
end

test("test mode is a sandbox for the whole addon", function()
    setup(guild())
    local before = realSnapshot()
    -- turn it on with the checkbox in the Settings tab
    ns.ToggleStandings(5)
    local view = ns.settingsViews[1]
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
    assert(ns.syncInfo.from["Simulated Officer-Forever"], "simulated officer")

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
    assert(ns.picker:IsShown(), "opens Start Bidding when nothing runs")
    ns.StartAuction(W.link(73, "Running Item"))
    ns.picker:Hide()
    texts["Loot Master"]()
    eq(ns.picker:IsShown(), false, "opens the running bidding instead")
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
    ns.ToggleStandings(2)
    ns.Command("edit")
    eq(ns.editor.target, "Anna Frost-Forever", "edit target")
    local menu = fakeMenu()
    ns.OpenMenu(ns.minimapButton)
    for _, item in ipairs(menu.items) do if item.text == "Add target to bench" then item.fn() end end
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

local function settingsView()
    ns.ToggleStandings(5)
    return ns.settingsViews[#ns.settingsViews]
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
    assert(view.status:GetText():find("Only the guild leader and officers"), view.status:GetText())
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
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "DB^5", "GUILD", "Anna Frost-Forever")
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "DD^5^#baseGP,0," .. (W.server + 5) .. ";#unknown,5," .. (W.server + 5) .. ";#raidEP,140," .. (W.server + 5), "GUILD", "Anna Frost-Forever")
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "DE^5", "GUILD", "Anna Frost-Forever")
    eq(ns.Setting("baseGP"), 100, "a base GP of 0 is refused")
    eq(ns.Data().rules.unknown, nil)
    eq(ns.Setting("raidEP"), 140, "the valid rule arrives")
    -- Ben is rank 3, not an officer
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "DB^6", "GUILD", "Ben Swift-Forever")
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "DD^6^#raidEP,999," .. (W.server + 50), "GUILD", "Ben Swift-Forever")
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "DE^6", "GUILD", "Ben Swift-Forever")
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

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
