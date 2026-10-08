-- Windows: standings (with Bench and History tabs), loot master window, bid popup.
--
-- Everything is built from Blizzard's own frame templates, so the windows
-- get the Forever artwork and look like the guild or character window.
-- Each template is created safely: if a template is missing in a future
-- client build, we fall back to a simple frame instead of throwing errors.

local _, ns = ...
ns = ns or _G.RedGuildForever

if not CreateFrame then return end

local ICON_STANDINGS = "Interface\\Icons\\INV_Misc_Coin_02"
local ICON_UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"
local ROW_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"

------------------------------------------------------------------------
-- Native building blocks
------------------------------------------------------------------------
local function create(frameType, name, parent, template)
    if template then
        local ok, f = pcall(CreateFrame, frameType, name, parent, template)
        if ok and f then return f, true end
    end
    if frameType == "Frame" then
        local ok, f = pcall(CreateFrame, frameType, name, parent, "BackdropTemplate")
        if ok and f then return f, false end
    end
    return CreateFrame(frameType, name, parent), false
end

local function sound(kit)
    if PlaySound and SOUNDKIT and SOUNDKIT[kit] then pcall(PlaySound, SOUNDKIT[kit]) end
end

local function classColor(classFile)
    if classFile and C_ClassColor and C_ClassColor.GetClassColor then
        local c = C_ClassColor.GetClassColor(classFile)
        if c then return c.r, c.g, c.b end
    end
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        return c.r, c.g, c.b
    end
    return 1, 1, 1
end

local function text(parent, font, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function setPortrait(f, icon)
    if f.SetPortraitToAsset then
        if pcall(f.SetPortraitToAsset, f, icon) then return end
    end
    local tex = f.portrait or (f.PortraitContainer and f.PortraitContainer.portrait)
    if tex then
        if SetPortraitToTexture then
            pcall(SetPortraitToTexture, tex, icon)
        else
            pcall(tex.SetTexture, tex, icon)
        end
    end
end

local function setTitle(f, title)
    if f.SetTitle then
        if pcall(f.SetTitle, f, title) then return end
    end
    local fs = (f.TitleContainer and f.TitleContainer.TitleText) or f.TitleText
    if fs then fs:SetText(title) return end
    if not f.fallbackTitle then
        f.fallbackTitle = text(f, "GameFontNormal", "CENTER")
        f.fallbackTitle:SetPoint("TOP", 0, -6)
    end
    f.fallbackTitle:SetText(title)
end

-- A window like the guild or character frame: portrait circle, title bar,
-- close button, inset content area and a strip for buttons at the bottom.
local function window(name, width, height, title, portrait)
    local f, native = create("Frame", name, UIParent, "ButtonFrameTemplate")
    if not native then
        f, native = create("Frame", name, UIParent, "PortraitFrameTemplate")
    end
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    if native then
        setTitle(f, title)
        setPortrait(f, portrait)
    else
        -- very old or unknown client: simple dark window with a close button
        f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24,
            insets = { left = 6, right = 6, top = 6, bottom = 6 } })
        setTitle(f, title)
        local close = create("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
        close:SetScript("OnClick", function() f:Hide() end)
    end

    -- the content area, ButtonFrameTemplate already brings one
    if not (native and type(f.Inset) == "table" and f.Inset.SetPoint) then
        f.Inset = create("Frame", nil, f, "InsetFrameTemplate")
        f.Inset:SetPoint("TOPLEFT", 4, -60)
        f.Inset:SetPoint("BOTTOMRIGHT", -6, 26)
    end

    f:Hide()
    f:HookScript("OnShow", function() sound("IG_CHARACTER_INFO_OPEN") end)
    f:HookScript("OnHide", function() sound("IG_CHARACTER_INFO_CLOSE") end)

    if UISpecialFrames then table.insert(UISpecialFrames, name) end
    return f
end

-- The red buttons like "Guild Settings"
local function button(parent, label, width, onClick)
    local b = create("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(label)
    b:SetScript("OnClick", function(self, ...)
        sound("U_CHAT_SCROLL_BUTTON")
        onClick(self, ...)
    end)
    return b
end

-- Column header like "Lvl Class Name Zone Rank Note" in the guild window
local function columnHeader(parent, label, width, onClick)
    local h, native = create("Button", nil, parent, "WhoFrameColumnHeaderTemplate")
    h:SetHeight(24)
    if native and WhoFrameColumn_SetWidth then
        pcall(WhoFrameColumn_SetWidth, h, width)
    else
        h:SetWidth(width)
    end
    if GameFontHighlightSmall then h:SetNormalFontObject(GameFontHighlightSmall) end
    h:SetText(label)
    if onClick then
        h:SetScript("OnClick", function()
            sound("U_CHAT_SCROLL_BUTTON")
            onClick()
        end)
    else
        h:EnableMouse(false)
    end
    return h
end

local function headerRow(parent, columns, onSort)
    local prev
    local headers = {}
    for _, c in ipairs(columns) do
        local h = columnHeader(parent, c.label, c.w, onSort and c.sort and function() onSort(c.sort) end)
        if prev then
            h:SetPoint("LEFT", prev, "RIGHT", -2, 0)
        else
            h:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -4)
        end
        headers[c.key] = h
        prev = h
    end
    return headers
end

-- Scrolling list of rows, rows highlight on mouse over like the guild list
local function scrollList(parent, rowHeight, buildRow)
    local scroll = create("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)
    local rows = {}
    function scroll:Row(i)
        if not rows[i] then
            local row = CreateFrame("Button", nil, content)
            row:SetHeight(rowHeight)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
            row:SetPoint("RIGHT", content, "RIGHT")
            local stripe = row:CreateTexture(nil, "BACKGROUND")
            stripe:SetAllPoints()
            stripe:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0)
            pcall(row.SetHighlightTexture, row, ROW_HIGHLIGHT, "ADD")
            buildRow(row)
            rows[i] = row
        end
        return rows[i]
    end
    function scroll:SetCount(n)
        for i = n + 1, #rows do rows[i]:Hide() end
        content:SetHeight(math.max(1, n * rowHeight))
    end
    return scroll
end

-- Cells laid out under the column headers
local function rowCells(row, columns, font)
    row.cells = {}
    local x = 6
    for _, c in ipairs(columns) do
        if c.key ~= "action" then
            local fs = text(row, font or "GameFontHighlightSmall", c.justify)
            fs:SetPoint("LEFT", x, 0)
            fs:SetWidth(c.w - 10)
            row.cells[c.key] = fs
        end
        x = x + c.w - 2
    end
end

-- Tabs at the bottom like Character, Reputation, Currency
local function tabs(f, name, labels, onSelect)
    f.Tabs = {}
    local prev
    for i, label in ipairs(labels) do
        local tab, native = create("Button", name .. "Tab" .. i, f, "PanelTabButtonTemplate")
        tab:SetID(i)
        if not native then
            if GameFontNormalSmall then tab:SetNormalFontObject(GameFontNormalSmall) end
            tab:SetSize(100, 26)
        end
        tab:SetText(label)
        if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
        if prev then
            tab:SetPoint("TOPLEFT", prev, "TOPRIGHT", 3, 0)
        else
            tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 11, 2)
        end
        tab:SetScript("OnClick", function(self)
            sound("IG_CHARACTER_INFO_TAB")
            onSelect(self:GetID())
        end)
        f.Tabs[i] = tab
        prev = tab
    end
    f.numTabs = #labels
    if PanelTemplates_SetNumTabs then pcall(PanelTemplates_SetNumTabs, f, #labels) end
end

local function selectTab(f, id)
    f.selectedTab = id
    if PanelTemplates_SetTab then pcall(PanelTemplates_SetTab, f, id) end
end

local function checkbox(parent, label, onClick)
    local cb = create("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    local fs = cb.Text or cb.text
    if not fs then
        fs = text(cb, "GameFontNormalSmall")
        fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    end
    fs:SetText(label)
    cb:SetScript("OnClick", function(self)
        sound(self:GetChecked() and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
        onClick(self:GetChecked())
    end)
    return cb
end

-- Item button with the quality colored border, like in bags and loot
local function itemButton(parent, size)
    local b, native = create("Button", nil, parent, "ItemButtonTemplate")
    b:SetSize(size, size)
    if not native then
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
    end
    b:SetScript("OnEnter", function(self)
        if self.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if self.link and IsModifiedClick and HandleModifiedItemClick then
            pcall(HandleModifiedItemClick, self.link)
        end
    end)
    function b:SetItem(link)
        self.link = link
        local _, _, icon = ns.ItemInfo(link)
        icon = icon or ICON_UNKNOWN
        if SetItemButtonTexture then
            pcall(SetItemButtonTexture, self, icon)
        elseif self.icon then
            self.icon:SetTexture(icon)
        end
        local quality
        if C_Item and C_Item.GetItemQualityByID then
            local ok, q = pcall(C_Item.GetItemQualityByID, link)
            if ok then quality = q end
        end
        if SetItemButtonQuality then pcall(SetItemButtonQuality, self, quality, link) end
    end
    return b
end

local function itemName(link)
    return link and link:match("%[(.-)%]") or "?"
end

------------------------------------------------------------------------
-- Standings window with tabs Standings, Bench, History
------------------------------------------------------------------------
local main
local showAll = false
local sortKey, sortDesc = "pr", true

local standingsColumns = {
    { key = "name", label = "Name", w = 170, sort = "name" },
    { key = "ep", label = "EP", w = 74, justify = "RIGHT", sort = "ep" },
    { key = "gp", label = "GP", w = 74, justify = "RIGHT", sort = "gp" },
    { key = "pr", label = "Priority", w = 84, justify = "RIGHT", sort = "pr" },
    { key = "alts", label = "Alts", w = 58, justify = "RIGHT", sort = "alts" },
}

local benchColumns = {
    { key = "name", label = "Benched players", w = 330 },
    { key = "action", label = "", w = 110 },
}

local historyColumns = {
    { key = "time", label = "Time", w = 90 },
    { key = "label", label = "Change", w = 260 },
    { key = "by", label = "By", w = 110 },
}

local function showPage(id)
    if not main then return end
    selectTab(main, id)
    for i, page in ipairs(main.pages) do page:SetShown(i == id) end
    main.standingsButtons:SetShown(id == 1 and ns.CanEditNotes())
    main.benchButtons:SetShown(id == 2 and ns.CanEditNotes())
    main.showAll:SetShown(id == 1)
    ns.RefreshStandings()
end

local function buildStandingsPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()
    headerRow(page, standingsColumns, function(key)
        if sortKey == key then
            sortDesc = not sortDesc
        else
            sortKey, sortDesc = key, key ~= "name"
        end
        ns.RefreshStandings()
    end)
    page.list = scrollList(page, 18, function(row)
        rowCells(row, standingsColumns)
        row:SetScript("OnEnter", function(self)
            if not self.entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(ns.ShortName(self.entry.name), classColor(self.entry.class))
            GameTooltip:AddDoubleLine("Effort Points", self.entry.ep, nil, nil, nil, 1, 1, 1)
            GameTooltip:AddDoubleLine("Gear Points", self.entry.gp, nil, nil, nil, 1, 1, 1)
            GameTooltip:AddDoubleLine("Priority", ns.FormatPR(self.entry.pr), nil, nil, nil, 1, 1, 1)
            local alts = ns.AltsOf(self.entry.name)
            if #alts > 0 then
                local names = {}
                for _, a in ipairs(alts) do table.insert(names, ns.ShortName(a)) end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Alts " .. table.concat(names, ", "), 1, 1, 1, true)
            end
            if self.entry.ep < ns.Setting("minEP") then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("New member until " .. ns.Setting("minEP") .. " EP", 0.4, 0.78, 1, true)
            end
            if ns.CanEditNotes() then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Click to edit", 0, 1, 0)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self)
            if self.entry and ns.CanEditNotes() then ns.OpenEditor(self.entry.name) end
        end)
    end)
    page.list:SetPoint("TOPLEFT", 4, -30)
    page.list:SetPoint("BOTTOMRIGHT", -26, 4)
    return page
end

local function buildBenchPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()
    headerRow(page, benchColumns)
    page.list = scrollList(page, 22, function(row)
        rowCells(row, benchColumns)
        row.remove = button(row, "Remove", 90, function() ns.BenchRemove(row.name) end)
        row.remove:SetHeight(20)
        row.remove:SetPoint("RIGHT", -4, 0)
    end)
    page.list:SetPoint("TOPLEFT", 4, -30)
    page.list:SetPoint("BOTTOMRIGHT", -26, 30)
    page.hint = text(page, "GameFontDisableSmall", "CENTER")
    page.hint:SetPoint("BOTTOM", 0, 10)
    page.hint:SetText("Benched players get the same EP as the raid.")
    return page
end

local function buildHistoryPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()
    headerRow(page, historyColumns)
    page.list = scrollList(page, 18, function(row) rowCells(row, historyColumns) end)
    page.list:SetPoint("TOPLEFT", 4, -30)
    page.list:SetPoint("BOTTOMRIGHT", -26, 4)
    return page
end

local function buildMain()
    local name = "RedGuildForeverFrame"
    local f = window(name, 520, 500, "Red Guild EPGP", ICON_STANDINGS)

    -- line next to the portrait, like "Level 11 Druid"
    f.summary = text(f, "GameFontNormal")
    f.summary:SetPoint("TOPLEFT", 66, -32)
    f.summary:SetWidth(300)
    f.status = text(f, "GameFontDisableSmall")
    f.status:SetPoint("TOPLEFT", f.summary, "BOTTOMLEFT", 0, -3)
    f.status:SetWidth(300)

    f.showAll = checkbox(f, "Show everyone", function(checked)
        showAll = checked and true or false
        ns.RefreshStandings()
    end)
    f.showAll:SetPoint("TOPRIGHT", -110, -30)

    f.pages = {
        buildStandingsPage(f.Inset),
        buildBenchPage(f.Inset),
        buildHistoryPage(f.Inset),
    }

    -- bottom strip
    f.refresh = button(f, "Refresh", 90, function()
        ns.RequestRoster()
        if ns.CanViewNotes() then ns.QueueBroadcast(0) else ns.SendComm("SR", "GUILD") end
    end)
    f.refresh:SetPoint("BOTTOMLEFT", 6, 4)

    f.standingsButtons = CreateFrame("Frame", nil, f)
    f.standingsButtons:SetSize(1, 22)
    f.standingsButtons:SetPoint("BOTTOMRIGHT", -6, 4)
    local undo = button(f.standingsButtons, "Undo", 70, function() ns.Command("undo") end)
    undo:SetPoint("RIGHT")
    local decay = button(f.standingsButtons, "Decay", 80, function() ns.Command("decay") end)
    decay:SetPoint("RIGHT", undo, "LEFT", -2, 0)
    local ontime = button(f.standingsButtons, "On time EP", 96, function() ns.Command("ontime") end)
    ontime:SetPoint("RIGHT", decay, "LEFT", -2, 0)
    local raid = button(f.standingsButtons, "Raid EP", 86, function() ns.Command("raid") end)
    raid:SetPoint("RIGHT", ontime, "LEFT", -2, 0)

    f.benchButtons = CreateFrame("Frame", nil, f)
    f.benchButtons:SetSize(1, 22)
    f.benchButtons:SetPoint("BOTTOMRIGHT", -6, 4)
    local clear = button(f.benchButtons, "Clear bench", 104, function() ns.BenchClear() end)
    clear:SetPoint("RIGHT")
    local add = button(f.benchButtons, "Add target", 104, function()
        local unitName, realm = UnitName("target")
        if not unitName or not UnitIsPlayer("target") then
            ns.Print("target a player first, or type /rgf bench add Name")
            return
        end
        ns.BenchAdd(realm and realm ~= "" and (unitName .. "-" .. realm) or unitName)
    end)
    add:SetPoint("RIGHT", clear, "LEFT", -2, 0)

    tabs(f, name, { "Standings", "Bench", "History" }, showPage)
    f:HookScript("OnShow", function() showPage(f.selectedTab or 1) end)
    return f
end

local function sortedStandings()
    local list = ns.Standings(showAll)
    table.sort(list, function(a, b)
        local x, y = a[sortKey], b[sortKey]
        if sortKey == "name" then x, y = ns.ShortName(x), ns.ShortName(y) end
        if x ~= y then
            if sortDesc then return x > y end
            return x < y
        end
        return a.name < b.name
    end)
    return list
end

local function refreshStandingsPage(page)
    local list = sortedStandings()
    local minEP = ns.Setting("minEP")
    for i, e in ipairs(list) do
        local row = page.list:Row(i)
        row.entry = e
        row.cells.name:SetText(ns.ShortName(e.name))
        row.cells.name:SetTextColor(classColor(e.class))
        row.cells.ep:SetText(e.ep)
        row.cells.gp:SetText(e.gp)
        row.cells.pr:SetText(ns.FormatPR(e.pr))
        if e.ep < minEP then
            row.cells.pr:SetTextColor(0.4, 0.78, 1)
        else
            row.cells.pr:SetTextColor(1, 0.82, 0)
        end
        row.cells.alts:SetText(e.alts > 0 and e.alts or "")
        row:Show()
    end
    page.list:SetCount(#list)
    return #list
end

local function refreshBenchPage(page)
    local list = ns.Bench()
    for i, name in ipairs(list) do
        local row = page.list:Row(i)
        row.name = name
        row.cells.name:SetText(ns.ShortName(name))
        local m = ns.members[name]
        row.cells.name:SetTextColor(classColor(m and m.class))
        row.remove:SetShown(ns.CanEditNotes())
        row:Show()
    end
    page.list:SetCount(#list)
end

local function refreshHistoryPage(page)
    local log = RedGuildForeverDB and RedGuildForeverDB.log or {}
    local n = 0
    for i = #log, 1, -1 do
        local e = log[i]
        n = n + 1
        local row = page.list:Row(n)
        row.cells.time:SetText(date("%d.%m. %H:%M", e.time))
        row.cells.label:SetText(e.label)
        row.cells.by:SetText(ns.ShortName(e.by))
        row:Show()
    end
    page.list:SetCount(n)
end

function ns.RefreshStandings()
    if not main or not main:IsShown() then return end
    local tab = main.selectedTab or 1
    local count = 0
    if tab == 1 then
        count = refreshStandingsPage(main.pages[1])
    elseif tab == 2 then
        refreshBenchPage(main.pages[2])
    else
        refreshHistoryPage(main.pages[3])
    end

    local me = ns.PlayerName()
    local ep, gp, pr = ns.GetPoints(me)
    main.summary:SetText("Your priority |cffffffff" .. ns.FormatPR(pr) .. "|r  (" .. ep .. " EP, " .. gp .. " GP)")

    local status
    if not (IsInGuild and IsInGuild()) then
        status = "You are not in a guild"
    elseif tab == 2 then
        status = #ns.Bench() .. " players on the bench"
    elseif tab == 3 then
        status = "Changes made by officers on this computer"
    elseif ns.CanViewNotes() then
        status = count .. " players, blue priority means new member"
    elseif ns.synced.from then
        status = count .. " players, sent by " .. ns.ShortName(ns.synced.from) .. " at " .. date("%H:%M", ns.synced.at)
    else
        status = "Waiting for an officer to send the standings"
    end
    main.status:SetText(status)
end

ns.RefreshBench = ns.RefreshStandings

function ns.ToggleStandings(tab)
    main = main or buildMain()
    if tab then
        main.selectedTab = tab
        if main:IsShown() then showPage(tab) return end
    end
    main:SetShown(not main:IsShown())
end

function ns.ToggleBench()
    ns.ToggleStandings(2)
end

ns.On("RGF_POINTS_CHANGED", function() ns.RefreshStandings() end)

------------------------------------------------------------------------
-- Player editor for the guild leader and officers
-- Opens from a click on a player in the standings, the menu or /rgf edit.
------------------------------------------------------------------------
local editor

local function smallButton(parent, label, onClick)
    local b = button(parent, label, 46, onClick)
    b:SetHeight(20)
    return b
end

local function boxNumber(box)
    return tonumber(box:GetText()) or 0
end

local function buildEditor()
    local f = window("RedGuildForeverEditFrame", 400, 430, "Edit Player", ICON_STANDINGS)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")

    f.name = text(f, "GameFontNormalLarge")
    f.name:SetPoint("TOPLEFT", 66, -30)
    f.name:SetWidth(300)
    f.sub = text(f, "GameFontHighlightSmall")
    f.sub:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -3)
    f.sub:SetWidth(300)

    local inset = f.Inset
    local function label(textValue, y)
        local fs = text(inset, "GameFontNormal")
        fs:SetPoint("TOPLEFT", 14, y)
        fs:SetText(textValue)
        return fs
    end
    local function rowLabel(textValue, y)
        local fs = text(inset, "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 20, y)
        fs:SetText(textValue)
        return fs
    end

    -- Points
    label("Points", -12)
    rowLabel("Effort Points", -40)
    f.ep = ns.UIInputBox(inset, 70, true)
    f.ep:SetPoint("TOPLEFT", 130, -36)
    rowLabel("Gear Points", -68)
    f.gp = ns.UIInputBox(inset, 70, true)
    f.gp:SetPoint("TOPLEFT", 130, -64)

    local function bump(box, amount)
        box:SetText(tostring(math.max(0, boxNumber(box) + amount)))
        f.UpdatePreview()
    end
    local prev = f.ep
    for _, amount in ipairs({ -100, 25, 100 }) do
        local b = smallButton(inset, (amount > 0 and "+" or "") .. amount, function() bump(f.ep, amount) end)
        b:SetPoint("LEFT", prev, "RIGHT", prev == f.ep and 10 or 2, 0)
        prev = b
    end
    prev = f.gp
    for _, amount in ipairs({ -100, 50, 100 }) do
        local b = smallButton(inset, (amount > 0 and "+" or "") .. amount, function() bump(f.gp, amount) end)
        b:SetPoint("LEFT", prev, "RIGHT", prev == f.gp and 10 or 2, 0)
        prev = b
    end

    f.preview = text(inset, "GameFontHighlightSmall")
    f.preview:SetPoint("TOPLEFT", 20, -94)
    f.preview:SetWidth(340)

    rowLabel("Reason", -122)
    f.reason = ns.UIInputBox(inset, 220, false)
    f.reason:SetMaxLetters(40)
    f.reason:SetPoint("TOPLEFT", 130, -118)

    f.save = button(inset, "Save points", 120, function() f.Save() end)
    f.save:SetPoint("TOPLEFT", 126, -144)

    function f.UpdatePreview()
        local ep, gp = boxNumber(f.ep), math.max(boxNumber(f.gp), ns.Setting("baseGP"))
        local cur = f.current
        local changed = cur and (ep ~= cur.ep or gp ~= cur.gp)
        local line = "Priority |cffffd100" .. ns.FormatPR(ep / gp) .. "|r"
        if changed then line = line .. "  (now " .. ns.FormatPR(cur.pr) .. ")" end
        if boxNumber(f.gp) < ns.Setting("baseGP") then
            line = line .. "  |cffff8040GP can not go below " .. ns.Setting("baseGP") .. "|r"
        end
        f.preview:SetText(line)
        f.save:SetEnabled(changed and true or false)
    end
    f.ep:SetScript("OnTextChanged", function() f.UpdatePreview() end)
    f.gp:SetScript("OnTextChanged", function() f.UpdatePreview() end)

    function f.Save()
        if not f.target then return end
        ns.SetExactPoints(f.target, boxNumber(f.ep), boxNumber(f.gp), f.reason:GetText())
        f.reason:SetText("")
        f.ep:ClearFocus()
        f.gp:ClearFocus()
        f.Load(f.target)
    end
    f.ep:SetScript("OnEnterPressed", function() f.Save() end)
    f.gp:SetScript("OnEnterPressed", function() f.Save() end)
    f.reason:SetScript("OnEnterPressed", function() f.Save() end)

    -- Alt
    label("Alt", -184)
    f.altText = text(inset, "GameFontHighlightSmall")
    f.altText:SetPoint("TOPLEFT", 20, -210)
    f.altText:SetWidth(340)
    f.mainLabel = rowLabel("Main character", -238)
    f.mainBox = ns.UIInputBox(inset, 150, false)
    f.mainBox:SetMaxLetters(40)
    f.mainBox:SetPoint("TOPLEFT", 130, -234)
    f.link = button(inset, "Link as alt", 100, function()
        local main = ns.TypedMember and ns.TypedMember(f.mainBox:GetText())
        if main and ns.SetAlt(f.target, main) then
            f.mainBox:SetText("")
            f.mainBox:ClearFocus()
            f.Load(f.target)
        end
    end)
    f.link:SetPoint("LEFT", f.mainBox, "RIGHT", 6, 0)
    f.mainBox:SetScript("OnEnterPressed", function() f.link:Click() end)
    f.unlink = button(inset, "Make main again", 140, function()
        if ns.UnsetAlt(f.target) then f.Load(f.target) end
    end)
    f.unlink:SetPoint("TOPLEFT", 126, -232)

    -- Bench
    label("Bench", -274)
    f.benchText = text(inset, "GameFontHighlightSmall")
    f.benchText:SetPoint("TOPLEFT", 20, -300)
    f.benchButton = button(inset, "Add to bench", 140, function()
        if f.onBench then ns.BenchRemove(f.target) else ns.BenchAdd(f.target) end
        f.Load(f.target)
    end)
    f.benchButton:SetPoint("TOPLEFT", 126, -296)

    -- bottom strip
    f.undo = button(f, "Undo last change", 140, function()
        ns.Command("undo")
        if f.target then f.Load(f.target) end
    end)
    f.undo:SetPoint("BOTTOMLEFT", 6, 4)
    f.close = button(f, "Close", 90, function() f:Hide() end)
    f.close:SetPoint("BOTTOMRIGHT", -6, 4)

    function f.Load(name)
        f.target = name
        local m = ns.members[name]
        local ep, gp, pr, main = ns.GetPoints(name)
        f.current = { ep = ep, gp = gp, pr = pr }
        f.name:SetText(ns.ShortName(name))
        f.name:SetTextColor(classColor(m and m.class))
        local alts = ns.AltsOf(main or name)
        local sub
        if main and main ~= name then
            sub = "Alt of " .. ns.ShortName(main) .. ", points are shared with the main"
        elseif #alts > 0 then
            sub = "Main with " .. #alts .. (#alts == 1 and " alt" or " alts")
        else
            sub = "Main"
        end
        if ep < ns.Setting("minEP") then sub = sub .. ", |cff66c7ffnew member|r" end
        f.sub:SetText(sub)

        if not f.ep:HasFocus() then f.ep:SetText(tostring(ep)) end
        if not f.gp:HasFocus() then f.gp:SetText(tostring(gp)) end
        f.UpdatePreview()

        local isAlt = main and main ~= name
        f.unlink:SetShown(isAlt and true or false)
        f.mainLabel:SetShown(not isAlt)
        f.mainBox:SetShown(not isAlt)
        f.link:SetShown(not isAlt)
        if isAlt then
            f.altText:SetText(ns.ShortName(name) .. " uses the points of " .. ns.ShortName(main) .. ".")
        elseif #alts > 0 then
            local names = {}
            for _, a in ipairs(alts) do table.insert(names, ns.ShortName(a)) end
            f.altText:SetText("Alts " .. table.concat(names, ", ") .. ". To link this player as an alt, unlink these first.")
        else
            f.altText:SetText("Type the main to share points with it.")
        end

        f.onBench = false
        for _, b in ipairs(ns.Bench()) do if b == name then f.onBench = true end end
        f.benchText:SetText(f.onBench and "On the bench" or "Not on the bench")
        f.benchButton:SetText(f.onBench and "Remove from bench" or "Add to bench")
    end

    return f
end

function ns.OpenEditor(name)
    if not ns.CanEditNotes() then
        ns.Print("only the guild leader and officers who can edit officer notes can change points")
        return false
    end
    local full = ns.FindMember(name)
    if not full then
        ns.Print((name or "?") .. " is not in the guild")
        return false
    end
    editor = editor or buildEditor()
    ns.editor = editor
    editor.Load(full)
    editor:Show()
    return true
end

local function refreshEditor()
    if editor and editor:IsShown() and editor.target then editor.Load(editor.target) end
end
ns.On("RGF_POINTS_CHANGED", refreshEditor)
ns.On("RGF_BENCH_CHANGED", refreshEditor)
ns.On("RGF_BENCH_CHANGED", function() ns.RefreshStandings() end)

------------------------------------------------------------------------
-- Loot master window
-- Shows at a glance who wants the item for main spec, who for off spec,
-- who passed and who has not answered yet. The winner is marked.
------------------------------------------------------------------------
local lm

local bidColumns = {
    { key = "name", label = "Name", w = 168 },
    { key = "spec", label = "Answer", w = 76 },
    { key = "ep", label = "EP", w = 56, justify = "RIGHT" },
    { key = "gp", label = "GP", w = 56, justify = "RIGHT" },
    { key = "pr", label = "Priority", w = 70, justify = "RIGHT" },
    { key = "roll", label = "Roll", w = 44, justify = "RIGHT" },
    { key = "action", label = "", w = 86 },
}

local SECTION_COLORS = {
    MS = { 0.25, 1, 0.25 },
    OS = { 0.4, 0.78, 1 },
    PASS = { 0.6, 0.6, 0.6 },
    WAIT = { 1, 0.5, 0.25 },
}

local function inputBox(parent, width, numeric)
    local box = create("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 20)
    box:SetAutoFocus(false)
    if numeric then box:SetNumeric(true) end
    box:SetMaxLetters(7)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end
ns.UIInputBox = inputBox

local function buildLootMaster()
    local f = window("RedGuildForeverLootFrame", 580, 520, "Loot Master", ICON_UNKNOWN)
    f:ClearAllPoints()
    f:SetPoint("RIGHT", UIParent, "RIGHT", -80, 20)

    f.item = text(f, "GameFontNormalLarge")
    f.item:SetPoint("TOPLEFT", 66, -30)
    f.item:SetWidth(420)
    f.price = text(f, "GameFontHighlightSmall")
    f.price:SetPoint("TOPLEFT", f.item, "BOTTOMLEFT", 0, -3)
    f.price:SetWidth(420)

    f.slot = itemButton(f, 37)
    f.slot:SetPoint("TOPRIGHT", -14, -27)

    -- price row
    local tierLabel = text(f.Inset, "GameFontNormalSmall")
    tierLabel:SetPoint("TOPLEFT", 10, -12)
    tierLabel:SetText("Drops from")
    f.tierButtons = {}
    local prev = tierLabel
    for _, tier in ipairs(ns.defaults.tierOrder) do
        local b = button(f.Inset, ns.defaults.tierNames[tier], 100, function() ns.SetAuctionTier(tier) end)
        b:SetPoint("LEFT", prev, "RIGHT", prev == tierLabel and 8 or 2, 0)
        f.tierButtons[tier] = b
        prev = b
    end
    local priceLabel = text(f.Inset, "GameFontNormalSmall")
    priceLabel:SetPoint("LEFT", prev, "RIGHT", 12, 0)
    priceLabel:SetText("Price")
    f.priceBox = inputBox(f.Inset, 46, true)
    f.priceBox:SetPoint("LEFT", priceLabel, "RIGHT", 8, 0)
    local function setPrice()
        if ns.SetAuctionPrice(f.priceBox:GetText()) then f.priceBox:ClearFocus() end
    end
    f.priceBox:SetScript("OnEnterPressed", setPrice)
    f.priceSet = button(f.Inset, "Set", 44, setPrice)
    f.priceSet:SetPoint("LEFT", f.priceBox, "RIGHT", 4, 0)

    f.state = text(f.Inset, "GameFontNormal")
    f.state:SetPoint("TOPLEFT", 10, -42)
    f.state:SetWidth(540)
    f.counts = text(f.Inset, "GameFontHighlightSmall")
    f.counts:SetPoint("TOPLEFT", 10, -60)
    f.counts:SetWidth(540)

    local listHolder = CreateFrame("Frame", nil, f.Inset)
    listHolder:SetPoint("TOPLEFT", 0, -74)
    listHolder:SetPoint("BOTTOMRIGHT")
    headerRow(listHolder, bidColumns)
    f.list = scrollList(listHolder, 22, function(row)
        rowCells(row, bidColumns)
        row.section = text(row, "GameFontNormal")
        row.section:SetPoint("LEFT", 6, 0)
        row.section:SetWidth(400)
        row.sectionLine = row:CreateTexture(nil, "BACKGROUND")
        row.sectionLine:SetPoint("BOTTOMLEFT", 2, 1)
        row.sectionLine:SetPoint("BOTTOMRIGHT", -2, 1)
        row.sectionLine:SetHeight(1)
        row.sectionLine:SetColorTexture(1, 0.82, 0, 0.35)
        row.winner = text(row, "GameFontNormalSmall", "RIGHT")
        row.winner:SetPoint("RIGHT", -74, 0)
        row.winner:SetText("|cff40ff40Winner|r")
        row.award = button(row, "Award", 66, function()
            if row.bid then ns.Award(row.bid.name) end
        end)
        row.award:SetHeight(20)
        row.award:SetPoint("RIGHT", -2, 0)
    end)
    f.list:SetPoint("TOPLEFT", 4, -30)
    f.list:SetPoint("BOTTOMRIGHT", -26, 4)

    f.closeBids = button(f, "Close bids", 100, function() ns.CloseBidding() end)
    f.closeBids:SetPoint("BOTTOMLEFT", 6, 4)
    f.rolls = button(f, "Ask for rolls", 110, function() ns.RequestRolls() end)
    f.rolls:SetPoint("LEFT", f.closeBids, "RIGHT", 2, 0)
    f.cancel = button(f, "Cancel", 80, function() ns.CancelAuction() end)
    f.cancel:SetPoint("BOTTOMRIGHT", -6, 4)
    f.bank = button(f, "Bank or Disenchant", 140, function() ns.Award(nil) end)
    f.bank:SetPoint("RIGHT", f.cancel, "LEFT", -2, 0)

    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.25 then return end
        elapsed = 0
        local a = ns.auction
        if a and a.open then
            local left = math.max(0, math.ceil(a.endsAt - GetTime()))
            f.state:SetText("Bidding is open, |cffffffff" .. left .. "|r seconds left")
        end
    end)
    return f
end

local function showSection(row, label, count, key)
    row.bid = nil
    for _, cell in pairs(row.cells) do cell:SetText("") end
    local c = SECTION_COLORS[key]
    row.section:SetText(label .. "  |cffffffff" .. count .. "|r")
    row.section:SetTextColor(c[1], c[2], c[3])
    row.section:Show()
    row.sectionLine:Show()
    row.winner:Hide()
    row.award:Hide()
    row:Show()
end

local function showBid(row, b, isWinner, canAward)
    row.bid = b
    row.section:Hide()
    row.sectionLine:Hide()
    local label = ns.ShortName(b.name)
    if b.main and b.main ~= b.name then label = label .. " |cff999999(" .. ns.ShortName(b.main) .. ")|r" end
    row.cells.name:SetText(label)
    local m = ns.members[b.name]
    row.cells.name:SetTextColor(classColor(m and m.class))
    local c = SECTION_COLORS[b.spec] or SECTION_COLORS.PASS
    row.cells.spec:SetText(b.spec == "MS" and "Main Spec" or (b.spec == "OS" and "Off Spec" or "Pass"))
    row.cells.spec:SetTextColor(c[1], c[2], c[3])
    row.cells.ep:SetText(b.ep)
    row.cells.gp:SetText(b.gp)
    if b.spec == "MS" then
        row.cells.pr:SetText(ns.FormatPR(b.pr))
        if b.newcomer then row.cells.pr:SetTextColor(0.4, 0.78, 1) else row.cells.pr:SetTextColor(1, 0.82, 0) end
    elseif b.spec == "OS" then
        row.cells.pr:SetText("free")
        row.cells.pr:SetTextColor(0.7, 0.7, 0.7)
    else
        row.cells.pr:SetText("")
    end
    row.cells.roll:SetText(b.roll or (b.wantsRoll and "..." or ""))
    row.winner:SetShown(isWinner)
    row.award:SetShown(canAward)
    row:Show()
end

local function showWaiting(row, name)
    row.bid = nil
    row.section:Hide()
    row.sectionLine:Hide()
    row.cells.name:SetText(ns.ShortName(name))
    local m = ns.members[name]
    local r, g, b = classColor(m and m.class)
    row.cells.name:SetTextColor(r * 0.6, g * 0.6, b * 0.6)
    row.cells.spec:SetText("No answer")
    row.cells.spec:SetTextColor(SECTION_COLORS.WAIT[1], SECTION_COLORS.WAIT[2], SECTION_COLORS.WAIT[3])
    row.cells.ep:SetText("")
    row.cells.gp:SetText("")
    row.cells.pr:SetText("")
    row.cells.roll:SetText("")
    row.winner:Hide()
    row.award:Hide()
    row:Show()
end

function ns.RefreshLootMaster()
    local a = ns.auction
    if not a then
        if lm then lm:Hide() end
        return
    end
    lm = lm or buildLootMaster()
    if not lm:IsShown() then lm:Show() end
    local _, _, icon = ns.ItemInfo(a.link)
    setPortrait(lm, icon or ICON_UNKNOWN)
    lm.item:SetText(a.link)
    lm.price:SetText("Main spec costs |cffffffff" .. a.price .. " GP|r, off spec is free" .. (a.fixed and ", fixed price" or ""))
    lm.slot:SetItem(a.link)
    for tier, b in pairs(lm.tierButtons) do
        b:SetEnabled(not a.fixed and tier ~= a.tier)
    end
    if not lm.priceBox:HasFocus() then lm.priceBox:SetText(tostring(a.price)) end

    local o = ns.AuctionOverview(a)
    local tied = ns.TiedForFirst(a)
    if not a.open then
        if #o.all == 0 then
            lm.state:SetText("Bidding is closed. Nobody wants it, give it to the bank or disenchant it.")
        elseif #tied > 0 then
            lm.state:SetText("Bidding is closed. |cffff8040Tie for first place|r, waiting for /roll.")
        else
            lm.state:SetText("Bidding is closed. Award the item to the winner.")
        end
    end
    lm.counts:SetText(string.format(
        "|cff40ff40Main Spec %d|r     |cff66c7ffOff Spec %d|r     |cff999999Pass %d|r     |cffff8040No answer %d|r",
        #o.ms, #o.os, #o.passed, #o.waiting))

    local n = 0
    local function nextRow()
        n = n + 1
        return lm.list:Row(n)
    end
    local winner = (#tied == 0) and o.winner or nil
    local sections = {
        { key = "MS", label = "Main Spec", list = o.ms },
        { key = "OS", label = "Off Spec", list = o.os },
        { key = "PASS", label = "Passed", list = o.passed },
    }
    for _, sec in ipairs(sections) do
        if #sec.list > 0 then
            showSection(nextRow(), sec.label, #sec.list, sec.key)
            for _, b in ipairs(sec.list) do
                showBid(nextRow(), b, b == winner, sec.key ~= "PASS")
            end
        end
    end
    if #o.waiting > 0 then
        showSection(nextRow(), "No answer yet", #o.waiting, "WAIT")
        for _, name in ipairs(o.waiting) do showWaiting(nextRow(), name) end
    end
    lm.list:SetCount(n)
    lm.closeBids:SetEnabled(a.open)
    lm.rolls:SetEnabled(not a.open and #tied > 0)
end

ns.On("RGF_AUCTION_CHANGED", function() ns.RefreshLootMaster() end)

------------------------------------------------------------------------
-- Bid popup for raiders, inspired by the Need or Greed loot roll
------------------------------------------------------------------------
local popup

local function buildPopup()
    local f = window("RedGuildForeverBidFrame", 380, 214, "Loot Bid", ICON_UNKNOWN)
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    f:SetFrameStrata("DIALOG")

    f.item = text(f, "GameFontNormal")
    f.item:SetPoint("TOPLEFT", 66, -32)
    f.item:SetWidth(290)
    f.price = text(f, "GameFontHighlightSmall")
    f.price:SetPoint("TOPLEFT", f.item, "BOTTOMLEFT", 0, -3)
    f.price:SetWidth(290)

    f.slot = itemButton(f.Inset, 40)
    f.slot:SetPoint("TOPLEFT", 12, -12)

    f.mine = text(f.Inset, "GameFontHighlight")
    f.mine:SetPoint("TOPLEFT", f.slot, "TOPRIGHT", 10, -2)
    f.mine:SetWidth(280)
    f.note = text(f.Inset, "GameFontNormalSmall")
    f.note:SetPoint("TOPLEFT", f.mine, "BOTTOMLEFT", 0, -4)
    f.note:SetWidth(280)

    -- timer bar like the loot roll frame
    f.timer = CreateFrame("StatusBar", nil, f.Inset)
    f.timer:SetPoint("BOTTOMLEFT", 12, 12)
    f.timer:SetPoint("BOTTOMRIGHT", -12, 12)
    f.timer:SetHeight(10)
    f.timer:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    f.timer:SetStatusBarColor(1, 0.82, 0)
    f.timer:SetMinMaxValues(0, 1)
    local bg = f.timer:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    f.timerText = text(f.Inset, "GameFontDisableSmall", "CENTER")
    f.timerText:SetPoint("BOTTOM", f.timer, "TOP", 0, 3)

    f.ms = button(f, "Main Spec", 112, function() ns.SendBid(f.inc, "MS") end)
    f.ms:SetPoint("BOTTOMLEFT", 6, 4)
    f.pass = button(f, "Pass", 112, function()
        if f.inc and f.inc.myBid then ns.SendBid(f.inc, "PASS") end
        f:Hide()
    end)
    f.pass:SetPoint("BOTTOMRIGHT", -6, 4)
    f.os = button(f, "Off Spec", 112, function() ns.SendBid(f.inc, "OS") end)
    f.os:SetPoint("LEFT", f.ms, "RIGHT", 6, 0)
    f.os:SetPoint("RIGHT", f.pass, "LEFT", -6, 0)

    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.1 or not f.inc then return end
        elapsed = 0
        local total = f.inc.duration or 30
        local left = f.inc.endsAt - GetTime()
        f.timer:SetValue(math.max(0, left / total))
        if left <= 0 then
            f.timerText:SetText("Bidding closed, waiting for the loot master")
            f.ms:SetEnabled(false)
            f.os:SetEnabled(false)
        else
            f.timerText:SetText(math.ceil(left) .. " seconds")
        end
    end)
    return f
end

ns.On("RGF_INCOMING_AUCTION", function(inc)
    popup = popup or buildPopup()
    popup.inc = inc
    local _, _, icon = ns.ItemInfo(inc.link)
    setPortrait(popup, icon or ICON_UNKNOWN)
    popup.slot:SetItem(inc.link)
    popup.item:SetText(inc.link)
    popup.price:SetText("Main spec |cffffffff" .. inc.price .. " GP|r, off spec is free")

    local me = ns.PlayerName()
    local ep, gp, pr, mainName = ns.GetPoints(me)
    popup.mine:SetText("Your priority |cffffd100" .. ns.FormatPR(pr) .. "|r")
    local note = ep .. " EP, " .. gp .. " GP"
    if mainName and mainName ~= me then note = note .. ", points of " .. ns.ShortName(mainName) end
    if ep < ns.Setting("minEP") then note = note .. ", |cff66c7ffnew member|r" end
    popup.note:SetText(note)

    local open = GetTime() < inc.endsAt
    popup.ms:SetEnabled(open)
    popup.os:SetEnabled(open)
    popup.ms:SetText(inc.myBid == "MS" and "|cff40ff40Main Spec|r" or "Main Spec")
    popup.os:SetText(inc.myBid == "OS" and "|cff40ff40Off Spec|r" or "Off Spec")
    if not popup:IsShown() then
        popup:Show()
        sound("RAID_WARNING")
    end
end)

ns.On("RGF_INCOMING_CLOSED", function(inc)
    if popup and popup.inc == inc then popup:Hide() end
end)

------------------------------------------------------------------------
-- Decay confirmation, the normal Blizzard yes or no dialog
------------------------------------------------------------------------
if StaticPopupDialogs then
    StaticPopupDialogs["REDGUILDFOREVER_DECAY"] = {
        text = "Shrink all EP and GP by %s percent?\nDo this once a week.",
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function()
            local n = ns.Decay()
            ns.Print("decay done for " .. n .. " players")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end
