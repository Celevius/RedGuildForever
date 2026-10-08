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
end

-- fresh addon with a guild roster
local ns
local function setup(roster)
    W.install()
    W.reset()
    W.roster = roster
    W.raid, W.inRaid = {}, false
    W.canEdit, W.canView = true, true
    W.itemSlots = {}
    ns = {}
    W.load(ns)
    ns.RebuildFromRoster()
    W.flush()
end

local function guild()
    return {
        { "Celery", 0, "", "DRUID" },
        { "Tom", 2, "200,100", "WARRIOR" },
        { "Lisa", 2, "1000,500", "PRIEST" },
        { "Max", 2, "1000,100", "PALADIN" },
        { "Ben", 3, "", "ROGUE" },
        { "Anna", 2, "500,200", "MAGE" },
        { "Tommage", 2, "@Tom", "MAGE" },
    }
end

local function note(name)
    for _, r in ipairs(W.roster) do if r[1] == name then return r[3] end end
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

test("officer notes parse and format", function()
    setup(guild())
    local p = ns.ParseNote("1250,300 tank")
    eq(p.ep, 1250) eq(p.gp, 300) eq(p.rest, " tank")
    eq(ns.ParseNote("@Thrall").main, "Thrall-Forever")
    eq(ns.ParseNote("just text").ep, nil)
    eq(ns.FormatNote(1250, 300, " tank"), "1250,300 tank")
    eq(#ns.FormatNote(123456, 123456, string.rep("x", 40)), 31, "note length")
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
    local _, _, pr = ns.GetPoints("Tom") near(pr, 2, "Tom")
    _, _, pr = ns.GetPoints("Lisa") near(pr, 2, "Lisa")
    _, _, pr = ns.GetPoints("Max") near(pr, 10, "Max")
    local ep, gp
    ep, gp, pr = ns.GetPoints("Ben")
    eq(ep, 0) eq(gp, 100) eq(pr, 0)
    eq(ns.IsNewMember("Tom"), true, "Tom is new")
    eq(ns.IsNewMember("Lisa"), false, "Lisa is not new")
end)

test("alts share the points of their main", function()
    setup(guild())
    local ep, gp, pr, main = ns.GetPoints("Tommage")
    eq(main, "Tom-Forever") eq(ep, 200) eq(gp, 100) near(pr, 2)
    eq(#ns.AltsOf("Tom-Forever"), 1)
end)

test("sword auction, Max wins and drops to 3.33", function()
    setup(guild())
    W.itemSlots = { [10] = "INVTYPE_WEAPON" }
    local sword = W.link(10, "Sword")
    ns.SetPriceOverride(sword, 200)
    W.inRaid = true
    assert(ns.StartAuction(sword))
    W.deliver(ns) -- popup for the loot master too
    ns.RecordBid("Tom", "MS")
    ns.RecordBid("Lisa", "MS")
    ns.RecordBid("Max", "MS")
    local list = ns.SortedBids(ns.auction)
    eq(list[1].name, "Max-Forever", "first")
    ns.CloseBidding()
    eq(#ns.TiedForFirst(ns.auction), 0, "no tie")
    assert(ns.Award("Max"))
    W.flush()
    eq(note("Max"), "1000,300")
    local _, _, pr = ns.GetPoints("Max")
    near(pr, 3.33, "Max after sword")
    noErrors()
end)

test("tie between Tom and Lisa is decided by /roll", function()
    setup(guild())
    W.itemSlots = { [11] = "INVTYPE_FINGER" }
    W.inRaid = true
    ns.StartAuction(W.link(11, "Ring"))
    ns.RecordBid("Tom", "MS")
    ns.RecordBid("Lisa", "MS")
    -- Tom is a new member (200 EP), so Lisa wins without a roll
    eq(ns.SortedBids(ns.auction)[1].name, "Lisa-Forever", "Lisa before new member Tom")
    eq(#ns.TiedForFirst(ns.auction), 0)
    -- make Tom a regular with the same priority as Lisa
    W.roster[2][3] = "400,200"
    ns.RebuildFromRoster() W.flush()
    eq(#ns.TiedForFirst(ns.auction), 2, "tie")
    ns.CloseBidding() -- asks for rolls
    assert(ns.auction.rollsOpen, "rolls open")
    ns.Fire("CHAT_MSG_SYSTEM", "Tom rolls 40 (1-100)")
    ns.Fire("CHAT_MSG_SYSTEM", "Tom rolls 99 (1-100)") -- second roll ignored
    ns.Fire("CHAT_MSG_SYSTEM", "Lisa rolls 77 (1-100)")
    ns.Fire("CHAT_MSG_SYSTEM", "Max rolls 100 (1-100)") -- not a bidder
    eq(#ns.TiedForFirst(ns.auction), 0, "tie solved")
    eq(ns.SortedBids(ns.auction)[1].name, "Lisa-Forever", "highest roll")
    noErrors()
end)

test("new member Ben loses to Lisa even with higher priority", function()
    setup(guild())
    W.roster[3][3] = "1000,900"  -- Lisa priority 1.11
    W.roster[5][3] = "125,100"   -- Ben priority 1.25 but new
    ns.RebuildFromRoster() W.flush()
    W.inRaid = true
    ns.StartAuction(W.link(12, "Ring"))
    ns.RecordBid("Ben", "MS")
    ns.RecordBid("Lisa", "MS")
    eq(ns.SortedBids(ns.auction)[1].name, "Lisa-Forever")
    ns.RecordBid("Lisa", "PASS")
    eq(ns.SortedBids(ns.auction)[1].name, "Ben-Forever", "Ben when nobody else wants it")
end)

test("off spec is free and main spec goes first", function()
    setup(guild())
    W.inRaid = true
    ns.StartAuction(W.link(13, "Staff"))
    ns.RecordBid("Lisa", "OS")
    ns.RecordBid("Ben", "MS")
    eq(ns.SortedBids(ns.auction)[1].name, "Ben-Forever", "main spec first even for a new member")
    ns.RecordBid("Ben", "PASS")
    ns.Award("Lisa")
    W.flush()
    eq(note("Lisa"), "1000,500", "Lisa GP unchanged")
end)

test("alt loot costs the main", function()
    setup(guild())
    W.itemSlots = { [14] = "INVTYPE_CLOAK" }
    W.inRaid = true
    ns.StartAuction(W.link(14, "Cloak"))
    ns.RecordBid("Tommage", "MS")
    ns.Award("Tommage")
    W.flush()
    eq(note("Tom"), "200,175", "Tom pays 75 GP")
    eq(note("Tommage"), "@Tom", "alt note untouched")
end)

test("raid EP goes to raid and bench, each player once", function()
    setup(guild())
    W.inRaid = true
    W.raid = { "Celery", "Lisa", "Tommage", "Stranger-Otherrealm" }
    ns.BenchAdd("Anna")
    ns.BenchAdd("Tom") -- Tom is in the raid on his alt
    local count, skipped = ns.AwardEP(ns.RaidAndBench(), 100, "Raid night")
    W.flush()
    eq(count, 4, "players")
    eq(#skipped, 1, "stranger skipped")
    eq(note("Lisa"), "1100,500")
    eq(note("Tom"), "300,100", "Tom only once")
    eq(note("Anna"), "600,200", "bench same EP")
    eq(note("Celery"), "100,100", "new note created")
end)

test("weekly decay keeps GP at the base", function()
    setup(guild())
    W.roster[4][3] = "1000,105"
    ns.RebuildFromRoster() W.flush()
    ns.Decay()
    W.flush()
    eq(note("Lisa"), "900,450")
    eq(note("Max"), "900,100", "GP floor")
    eq(note("Tommage"), "@Tom", "alts untouched")
end)

test("undo reverts the last action", function()
    setup(guild())
    ns.AwardEP({ "Lisa", "Max" }, 100, "Raid night")
    W.flush()
    eq(note("Lisa"), "1100,500")
    ns.Undo()
    W.flush()
    eq(note("Lisa"), "1000,500")
    eq(note("Max"), "1000,100")
    eq(ns.Undo(), nil, "nothing left")
end)

test("link and unlink alts", function()
    setup(guild())
    assert(ns.SetAlt("Ben", "Anna"))
    W.flush()
    eq(note("Ben"), "@Anna")
    ns.RebuildFromRoster() W.flush()
    eq(select(4, ns.GetPoints("Ben")), "Anna-Forever")
    eq(ns.SetAlt("Lisa", "Tommage"), false, "cannot link to an alt")
    assert(ns.UnsetAlt("Ben"))
    W.flush()
    eq(note("Ben"), "0,100")
end)

test("whisper bids for players without the addon", function()
    setup(guild())
    W.inRaid = true
    ns.StartAuction(W.link(15, "Boots"))
    ns.Fire("CHAT_MSG_WHISPER", "  MS ", "Lisa-Forever")
    ns.Fire("CHAT_MSG_WHISPER", "os", "Tom-Forever")
    ns.Fire("CHAT_MSG_WHISPER", "hello", "Max-Forever")
    eq(ns.auction.bids["Lisa-Forever"].spec, "MS")
    eq(ns.auction.bids["Tom-Forever"].spec, "OS")
    eq(ns.auction.bids["Max-Forever"], nil)
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
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "B^" .. id .. "^MS", "WHISPER", "Max-Forever")
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "B^000000^MS", "WHISPER", "Lisa-Forever")
    eq(ns.auction.bids["Max-Forever"].spec, "MS")
    eq(ns.auction.bids["Lisa-Forever"], nil, "wrong auction id ignored")
end)

test("raider popup receives auction with item link", function()
    setup(guild())
    W.inRaid = true
    local link = W.link(17, "Shoulders")
    ns.StartAuction(link)
    W.deliver(ns, "Celery")
    local got
    for _, inc in pairs(ns.incoming) do got = inc end
    assert(got, "incoming auction")
    eq(got.link, link)
    eq(got.price, 100)
    ns.Award(nil)
    W.deliver(ns, "Celery")
    eq(next(ns.incoming), nil, "closed")
    noErrors()
end)

test("standings sync for players without officer note access", function()
    setup(guild())
    ns.BroadcastStandings()
    local sent = W.comms
    -- now become a normal member who cannot read notes
    W.canView, W.canEdit = false, false
    ns.RebuildFromRoster() W.flush()
    W.comms = sent
    W.deliver(ns, "Celery")
    eq(ns.synced.from, "Celery-Forever")
    local ep, gp, pr = ns.GetPoints("Max")
    eq(ep, 1000) eq(gp, 100) near(pr, 10)
    eq(select(4, ns.GetPoints("Tommage")), "Tom-Forever", "alt link synced")
    eq(#ns.Standings(), 4)
end)

test("sync from a non officer is ignored", function()
    setup(guild())
    W.canView = false
    ns.RebuildFromRoster() W.flush()
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "SB^1", "GUILD", "Ben-Forever")
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "SD^1^Ben,99999,100", "GUILD", "Ben-Forever")
    ns.Fire("CHAT_MSG_ADDON", ns.prefix, "SE^1", "GUILD", "Ben-Forever")
    eq(ns.synced.from, nil)
end)

test("big guild standings fit in addon messages", function()
    local roster = {}
    for i = 1, 400 do table.insert(roster, { "Player" .. i, 3, (i * 7) .. "," .. (100 + i), "WARRIOR" }) end
    setup(roster)
    assert(ns.BroadcastStandings()) -- the mock asserts 255 bytes per message
end)

test("roll pattern works with other client languages", function()
    setup(guild())
    _G.RANDOM_ROLL_RESULT = "%s würfelt. Ergebnis %d (%d-%d)"
    local loader = assert(loadfile("Auction.lua"))
    loader("RedGuildForever", ns)
    local name, roll, low, high = ns.ParseRoll("Lisa würfelt. Ergebnis 42 (1-100)")
    eq(name, "Lisa") eq(roll, 42) eq(low, 1) eq(high, 100)
end)

test("slash commands run without errors", function()
    setup(guild())
    W.inRaid = true
    W.raid = { "Celery", "Lisa" }
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
    W.raid = { "Celery", "Lisa", "Max" }
    ns.BenchAdd("Anna")
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
    W.roster[2][3] = "1000,500" -- Tom ties with Lisa
    ns.RebuildFromRoster() W.flush()
    ns.Command("bid " .. W.link(30, "Helm of Testing") .. " boss")
    W.deliver(ns, "Celery")
    ns.RecordBid("Tom", "MS")
    ns.RecordBid("Lisa", "MS")
    ns.RecordBid("Max", "OS")
    local inc
    for _, i in pairs(ns.incoming) do inc = i end
    ns.SendBid(inc, "MS")
    ns.SetAuctionTier("rare")
    ns.CloseBidding()
    ns.Fire("CHAT_MSG_SYSTEM", "Tom rolls 12 (1-100)")
    ns.Fire("CHAT_MSG_SYSTEM", "Lisa rolls 88 (1-100)")
    ns.Award("Lisa")
    W.deliver(ns, "Celery")
    W.flush()
    ns.ToggleStandings(3)
    noErrors()
end)

test("members cannot change points", function()
    setup(guild())
    W.canEdit = false
    eq(ns.Adjust("Lisa", 100, 0), nil)
    eq(ns.StartAuction(W.link(20, "Wand")), false)
    W.flush()
    eq(note("Lisa"), "1000,500")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
