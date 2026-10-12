-- Item prices: base GP by where the item dropped, times a slot multiplier.
-- Both are guild rules, set in the Settings tab and shared with Sync.

local _, ns = ...
ns = ns or _G.RedGuildForever

-- Which multiplier rule each equipment slot uses
ns.slotGroup = {
    INVTYPE_2HWEAPON = "twohand",

    INVTYPE_WEAPON = "large",
    INVTYPE_WEAPONMAINHAND = "large",
    INVTYPE_WEAPONOFFHAND = "large",
    INVTYPE_CHEST = "large",
    INVTYPE_ROBE = "large",
    INVTYPE_LEGS = "large",
    INVTYPE_HEAD = "large",

    INVTYPE_SHOULDER = "medium",
    INVTYPE_HAND = "medium",
    INVTYPE_FEET = "medium",
    INVTYPE_WAIST = "medium",
    INVTYPE_TRINKET = "medium",
    INVTYPE_RANGED = "medium",
    INVTYPE_RANGEDRIGHT = "medium",

    INVTYPE_WRIST = "small",
    INVTYPE_NECK = "small",
    INVTYPE_FINGER = "small",
    INVTYPE_CLOAK = "small",
    INVTYPE_HOLDABLE = "small",
    INVTYPE_SHIELD = "small",
    INVTYPE_THROWN = "small",
    INVTYPE_RELIC = "small",

    INVTYPE_BODY = "cosmetic",
    INVTYPE_TABARD = "cosmetic",
}

-- Shirts and tabards are always free. Items without a slot use the no slot rule.
function ns.SlotMultiplier(equipLoc)
    local group = equipLoc and equipLoc ~= "" and ns.slotGroup[equipLoc] or "noslot"
    if group == "cosmetic" then return 0 end
    return ns.Rule("mult_" .. group) or 1
end

------------------------------------------------------------------------
-- Fixed prices for single items, saved as guild rules "item:12345"
------------------------------------------------------------------------
function ns.ItemOverride(itemID)
    if not itemID then return nil end
    local rules = ns.Data().rules
    local e = rules and rules["item:" .. itemID]
    return e and e.v
end

-- Returns price, multiplier, and whether a fixed price was used.
function ns.ItemPrice(link, tier)
    local itemID, equipLoc = ns.ItemInfo(link)
    local fixed = ns.ItemOverride(itemID)
    if fixed then return fixed, nil, true end
    local tiers = ns.Setting("tiers")
    local base = tiers[tier or "normal"] or tiers.normal
    local mult = ns.SlotMultiplier(equipLoc)
    return ns.Round(base * mult), mult, false
end

local function setOverride(link, gp)
    if not ns.CanChange() then return false end
    local itemID = ns.ItemInfo(link)
    if not itemID then return false end
    local data = ns.Data()
    data.rules = data.rules or {}
    data.rules["item:" .. itemID] = { v = gp, t = ns.Now(), by = ns.PlayerName() }
    ns.Fire("RGF_RULES_CHANGED")
    ns.Fire("RGF_LOCAL_CHANGE")
    return true
end

function ns.SetPriceOverride(link, gp)
    gp = tonumber(gp)
    if not gp or gp < 0 then return false end
    return setOverride(link, math.floor(gp))
end

-- The cleared price keeps its time stamp, so Sync passes the clearing on.
function ns.ClearPriceOverride(link)
    return setOverride(link, nil)
end

-- Fixed prices from version 1.5 and older were saved only on this computer.
-- Move them into the guild rules once, so they are shared.
function ns.MigrateOldOverrides()
    local old = RedGuildForeverDB and RedGuildForeverDB.priceOverrides
    if not old or not next(old) or ns.IsTest() or not ns.GuildKey() then return end
    local data = ns.RealData()
    data.rules = data.rules or {}
    for itemID, gp in pairs(old) do
        local key = "item:" .. itemID
        if not data.rules[key] then
            data.rules[key] = { v = gp, t = ns.Now(), by = ns.PlayerName() }
        end
    end
    wipe(old)
end
