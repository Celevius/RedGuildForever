-- Minimap button and the entry in the game's addon list next to the minimap.
--   Left click   open or close the standings
--   Right click  menu with every action, so nobody needs slash commands
--   Drag         move the button around the minimap

local _, ns = ...
ns = ns or _G.RedGuildForever

local ICON = "Interface\\Icons\\INV_Misc_Coin_02"
local DEFAULT_ANGLE = 200

------------------------------------------------------------------------
-- The menu
------------------------------------------------------------------------
local function sound(kit)
    if PlaySound and SOUNDKIT and SOUNDKIT[kit] then pcall(PlaySound, SOUNDKIT[kit]) end
end

-- Every menu entry, used by the right click menu
function ns.MenuEntries()
    local entries = {
        { title = ns.IsTest() and "Red Guild EPGP  |cffff8040Test mode|r" or "Red Guild EPGP" },
        { text = "Standings", func = function() ns.ToggleStandings(1) end },
        { text = "Bench", func = function() ns.ToggleStandings(2) end },
        { text = "History", func = function() ns.ToggleStandings(3) end },
        { text = "My points", func = function() ns.Command("me") end },
        { text = "Sync with everyone online", func = function() ns.Command("sync") end },
        { text = "Backup and sync", func = function() ns.ToggleStandings(4) end },
    }
    if ns.CanEdit() then
        local more = {
            { divider = true },
            { title = "Officer" },
            { text = "Edit target", func = function() ns.Command("edit") end },
            { text = "Give raid EP (" .. ns.Setting("raidEP") .. ")", func = function() ns.Command("raid") end },
            { text = "Give on time EP (" .. ns.Setting("onTimeEP") .. ")", func = function() ns.Command("ontime") end },
            { text = "Add target to bench", func = function()
                local name, realm = UnitName("target")
                if name and UnitIsPlayer("target") then
                    local ok, full = ns.BenchAdd(realm and realm ~= "" and (name .. "-" .. realm) or name)
                    ns.Print(ok and (ns.ShortName(full) .. " is on the bench") or "already on the bench")
                else
                    ns.Print("target a player first")
                end
            end },
            { text = "Clear bench", func = function() ns.BenchClear() ns.Print("bench cleared") end },
            { text = "Weekly decay", func = function() ns.Command("decay") end },
            { text = "Undo last change", func = function() ns.Command("undo") end },
            { divider = true },
            { title = "Loot" },
            { text = "Loot Master", func = function() ns.OpenLootMaster() end },
        }
        for _, e in ipairs(more) do table.insert(entries, e) end
    end
    table.insert(entries, { divider = true })
    table.insert(entries, { text = "Settings", func = function() ns.ToggleStandings(5) end })
    if ns.IsTest() then
        table.insert(entries, { text = "|cffff8040Turn test mode off|r", func = function() ns.SetTestMode(false) end })
    end
    table.insert(entries, { text = "Hide minimap button", func = function() ns.SetMinimapShown(false) end })
    return entries
end

function ns.OpenMenu(owner)
    local entries = ns.MenuEntries()
    if MenuUtil and MenuUtil.CreateContextMenu then
        local ok = pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
            for _, e in ipairs(entries) do
                if e.title then
                    root:CreateTitle(e.title)
                elseif e.divider then
                    root:CreateDivider()
                else
                    root:CreateButton(e.text, e.func)
                end
            end
        end)
        if ok then return end
    end
    -- no menu system in this client, the window has all actions as buttons
    ns.ToggleStandings(1)
end

------------------------------------------------------------------------
-- Tooltip
------------------------------------------------------------------------
function ns.ShowTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("Red Guild EPGP")
    if ns.IsTest() then GameTooltip:AddLine("Test mode is on, nothing is sent", 1, 0.5, 0.25) end
    local ep, gp, pr = ns.GetPoints(ns.PlayerName())
    GameTooltip:AddDoubleLine("Your priority", ns.FormatPR(pr), nil, nil, nil, 1, 1, 1)
    GameTooltip:AddDoubleLine("EP and GP", ep .. " / " .. gp, nil, nil, nil, 1, 1, 1)
    if ep < ns.Setting("minEP") then
        GameTooltip:AddLine("New member until " .. ns.Setting("minEP") .. " EP", 0.4, 0.78, 1)
    end
    local benched = #ns.Bench()
    if benched > 0 then
        GameTooltip:AddDoubleLine("On the bench", benched, nil, nil, nil, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffffd100Left click|r open standings", 1, 1, 1)
    GameTooltip:AddLine("|cffffd100Right click|r menu", 1, 1, 1)
    if owner == ns.minimapButton then
        GameTooltip:AddLine("|cffffd100Drag|r move this button", 1, 1, 1)
    end
    GameTooltip:Show()
end

------------------------------------------------------------------------
-- Minimap button
------------------------------------------------------------------------
local function settings()
    RedGuildForeverDB.minimap = RedGuildForeverDB.minimap or { angle = DEFAULT_ANGLE, hide = false }
    return RedGuildForeverDB.minimap
end

local function place(button)
    local angle = math.rad(settings().angle or DEFAULT_ANGLE)
    local radius = 80
    if Minimap and Minimap.GetWidth then
        local w = Minimap:GetWidth()
        if type(w) == "number" and w > 0 then radius = w / 2 + 5 end
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function dragUpdate(button)
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    if type(mx) ~= "number" or type(cx) ~= "number" or type(scale) ~= "number" then return end
    cx, cy = cx / scale, cy / scale
    local atan2 = math.atan2 or _G.atan2
    settings().angle = math.deg(atan2(cy - my, cx - mx)) % 360
    place(button)
end

local function buildButton()
    if not (CreateFrame and Minimap) then return nil end
    local b = CreateFrame("Button", "RedGuildForeverMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = b:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture(ICON)
    b.icon:SetSize(17, 17)
    b.icon:SetPoint("TOPLEFT", 7, -6)
    b.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(self, mouse)
        GameTooltip:Hide()
        if mouse == "RightButton" then
            sound("IG_MAINMENU_OPEN")
            ns.OpenMenu(self)
        else
            ns.ToggleStandings(1)
        end
    end)
    b:SetScript("OnMouseDown", function(self) self.icon:SetTexCoord(0, 1, 0, 1) end)
    b:SetScript("OnMouseUp", function(self) self.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95) end)
    b:SetScript("OnEnter", function(self) ns.ShowTooltip(self) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", dragUpdate)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    end)

    place(b)
    return b
end

function ns.SetMinimapShown(show)
    settings().hide = not show
    if show then
        ns.minimapButton = ns.minimapButton or buildButton()
        if ns.minimapButton then ns.minimapButton:Show() end
    elseif ns.minimapButton then
        ns.minimapButton:Hide()
        ns.Print("minimap button hidden. Type /rgf minimap to show it again, or use the addon list next to the minimap")
    end
end

-- the button turns orange while test mode is on
local function tint()
    local b = ns.minimapButton
    if not (b and b.icon) then return end
    if ns.IsTest() then
        b.icon:SetVertexColor(1, 0.55, 0.25)
    else
        b.icon:SetVertexColor(1, 1, 1)
    end
end

ns.On("RGF_READY", function()
    if not settings().hide then ns.SetMinimapShown(true) end
    tint()
    if ns.IsTest() then
        ns.After(5, function()
            ns.Print(ns.TEST_TAG .. "test mode is still on. Turn it off in the settings before a real raid")
        end)
    end
end)
ns.On("RGF_TEST_MODE", tint)

------------------------------------------------------------------------
-- Addon list next to the minimap (the toc file points to these)
------------------------------------------------------------------------
function RedGuildForever_OnAddonCompartmentClick(_, mouse, menuButton)
    if mouse == "RightButton" then
        ns.OpenMenu(menuButton or UIParent)
    else
        ns.ToggleStandings(1)
    end
end

function RedGuildForever_OnAddonCompartmentEnter(_, menuButton)
    if menuButton then ns.ShowTooltip(menuButton) end
end

function RedGuildForever_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
