-- Item prices: base GP by tier times a slot multiplier.

local _, ns = ...
ns = ns or _G.RedGuildForever

-- Slot multipliers from the rule book
ns.slotMultiplier = {
    INVTYPE_2HWEAPON = 2,

    INVTYPE_WEAPON = 1.5,
    INVTYPE_WEAPONMAINHAND = 1.5,
    INVTYPE_WEAPONOFFHAND = 1.5,
    INVTYPE_CHEST = 1.5,
    INVTYPE_ROBE = 1.5,
    INVTYPE_LEGS = 1.5,
    INVTYPE_HEAD = 1.5,

    INVTYPE_SHOULDER = 1,
    INVTYPE_HAND = 1,
    INVTYPE_FEET = 1,
    INVTYPE_WAIST = 1,
    INVTYPE_TRINKET = 1,
    INVTYPE_RANGED = 1,
    INVTYPE_RANGEDRIGHT = 1,

    INVTYPE_WRIST = 0.75,
    INVTYPE_NECK = 0.75,
    INVTYPE_FINGER = 0.75,
    INVTYPE_CLOAK = 0.75,
    INVTYPE_HOLDABLE = 0.75,
    INVTYPE_SHIELD = 0.75,
    INVTYPE_THROWN = 0.75,
    INVTYPE_RELIC = 0.75,

    INVTYPE_BODY = 0,
    INVTYPE_TABARD = 0,
}

ns.slotNames = {
    [2] = "Two handed weapon",
    [1.5] = "Weapon, chest, legs or head",
    [1] = "Shoulders, hands, feet, waist, trinket or ranged",
    [0.75] = "Wrist, neck, ring, cloak or off hand",
    [0] = "Cosmetic",
}

-- Items without a gear slot (tokens, recipes, quest items) count as x1.
function ns.SlotMultiplier(equipLoc)
    if not equipLoc or equipLoc == "" then return 1 end
    local m = ns.slotMultiplier[equipLoc]
    if m == nil then return 1 end
    return m
end

-- Returns price, multiplier, and whether a fixed override was used.
function ns.ItemPrice(link, tier)
    local itemID, equipLoc = ns.ItemInfo(link)
    local overrides = RedGuildForeverDB and RedGuildForeverDB.priceOverrides
    if itemID and overrides and overrides[itemID] then
        return overrides[itemID], nil, true
    end
    local tiers = ns.Setting("tiers")
    local base = tiers[tier or "normal"] or tiers.normal
    local mult = ns.SlotMultiplier(equipLoc)
    return ns.Round(base * mult), mult, false
end

function ns.SetPriceOverride(link, gp)
    local itemID = ns.ItemInfo(link)
    if not itemID then return false end
    RedGuildForeverDB.priceOverrides[itemID] = gp
    return true
end
