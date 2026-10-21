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

-- building blocks for the other window files
ns.UI = {
    create = create, sound = sound, classColor = classColor, text = text,
    setPortrait = setPortrait, setTitle = setTitle, window = window, button = button,
    columnHeader = columnHeader, headerRow = headerRow, scrollList = scrollList,
    rowCells = rowCells, checkbox = checkbox, itemButton = itemButton, itemName = itemName,
}

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
    { key = "time", label = "Time", w = 82 },
    { key = "label", label = "Change", w = 250 },
    { key = "by", label = "By", w = 80 },
    { key = "action", label = "", w = 60 },
}

local function showPage(id)
    if not main then return end
    selectTab(main, id)
    for i, page in ipairs(main.pages) do page:SetShown(i == id) end
    main.standingsButtons:SetShown(id == 1 and ns.CanEdit())
    main.benchButtons:SetShown(id == 2 and ns.CanEdit())
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
            if ns.CanEdit() then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Click to edit", 0, 1, 0)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self)
            if self.entry and ns.CanEdit() then ns.OpenEditor(self.entry.name) end
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

-- Data tab: where the data lives, sync, decay, backup, import and start fresh
local function buildSyncPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()

    local title = text(page, "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText("Where the points are saved")
    local info = text(page, "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", 12, -32)
    info:SetWidth(470)
    info:SetWordWrap(true)
    info:SetText("Every player keeps a copy of the points in the addon's save file. Every change is kept, and Sync hands the changes to everyone online, so changes made at the same time in two raids all count. Editors send, everyone else only receives.")

    page.state = text(page, "GameFontHighlight")
    page.state:SetPoint("TOPLEFT", 12, -72)
    page.state:SetWidth(470)
    page.state:SetWordWrap(true)

    page.sync = button(page, "Sync now", 110, function() ns.Sync() end)
    page.sync:SetPoint("TOPLEFT", 10, -106)
    page.fresh = button(page, "Start fresh", 110, function()
        if StaticPopup_Show then StaticPopup_Show("REDGUILDFOREVER_FRESH") end
    end)
    page.fresh:SetPoint("LEFT", page.sync, "RIGHT", 4, 0)
    -- decay only works with data, start fresh and the notes import only without
    page.decay = button(page, "Weekly decay", 120, function() ns.Command("decay") end)
    page.decay:SetPoint("LEFT", page.sync, "RIGHT", 4, 0)
    page.notes = button(page, "Import officer notes", 150, function()
        local n = ns.ImportOfficerNotes()
        ns.Print(n > 0 and ("imported " .. n .. " players from the officer notes") or "no points found in the officer notes")
    end)
    page.notes:SetPoint("LEFT", page.fresh, "RIGHT", 4, 0)

    local backupTitle = text(page, "GameFontNormal")
    backupTitle:SetPoint("TOPLEFT", 12, -144)
    backupTitle:SetText("Backup")
    local backupInfo = text(page, "GameFontHighlightSmall")
    backupInfo:SetPoint("TOPLEFT", 12, -164)
    backupInfo:SetWidth(470)
    backupInfo:SetWordWrap(true)
    backupInfo:SetText("Show backup, then press Ctrl C and keep the text in Discord or a file. To restore, paste a backup here with Ctrl V and click Import backup.")

    local holder = create("Frame", nil, page, "InsetFrameTemplate")
    holder:SetPoint("TOPLEFT", 10, -196)
    holder:SetPoint("BOTTOMRIGHT", -10, 40)
    local scroll = create("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -28, 6)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    box:SetWidth(430)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(box)
    page.box = box

    page.show = button(page, "Show backup", 120, function()
        box:SetText(ns.ExportText())
        box:SetFocus()
        box:HighlightText()
    end)
    page.show:SetPoint("BOTTOMLEFT", 10, 10)
    page.import = button(page, "Import backup", 120, function()
        local changes, err = ns.ImportText(box:GetText())
        if changes then
            ns.Print("backup imported, " .. changes .. " players changed")
            box:SetText("")
        else
            ns.Print(err)
        end
    end)
    page.import:SetPoint("LEFT", page.show, "RIGHT", 4, 0)
    return page
end

local function refreshSyncPage(page)
    local lines = {}
    if not ns.HasData() then
        table.insert(lines, "|cffff8040No data loaded yet.|r Click Sync now to get it from the editors.")
        if ns.CanEdit() then
            table.insert(lines, "If your guild is new, click Start fresh. If you used version 1.3 or older, import the officer notes.")
        end
    else
        local count, changes = 0, 0
        for _ in pairs(ns.Players()) do count = count + 1 end
        for _ in pairs(ns.Data().events or {}) do changes = changes + 1 end
        table.insert(lines, count .. " players and " .. changes .. " changes in the data.")
        local waiting = ns.QueuedMessages and ns.QueuedMessages() or 0
        if waiting > 0 then table.insert(lines, waiting .. " sync messages are still waiting to go out.") end
        if ns.CanEdit() then
            table.insert(lines, "Weekly decay lowers the EP and GP of everyone by " .. ns.Setting("decayPercent") .. " percent, once a week after the last raid.")
        end
    end
    local si = ns.syncInfo or {}
    if si.running then
        table.insert(lines, "Sync is running...")
    elseif si.last then
        local who = {}
        for name in pairs(si.from or {}) do table.insert(who, ns.ShortName(name)) end
        table.sort(who)
        table.insert(lines, "Last sync at " .. date("%H:%M", si.last) .. " with " .. (#who > 0 and table.concat(who, ", ") or "nobody"))
    end
    page.state:SetText(table.concat(lines, "\n"))
    local editor, hasData = ns.CanEdit(), ns.HasData()
    page.fresh:SetShown(editor and not hasData)
    page.notes:SetShown(editor and not hasData)
    page.decay:SetShown(editor and hasData)
    page.import:SetShown(editor)
end

------------------------------------------------------------------------
-- Settings, shown in the Settings tab and in the game's Options under AddOns
------------------------------------------------------------------------
local settingsViews = {}
ns.settingsViews = settingsViews

local GREEN, RED_TEXT = "|cff40ff40", "|cffff5555"

-- read the typed rules, falling back to the saved value for empty boxes
local function typedRule(view, key)
    local box = view.ruleBoxes[key]
    local n = box and ns.CheckRule(key, box:GetText())
    if n == nil then return ns.Rule(key) end
    return n
end

local function fillRules(view)
    view.filling = true
    for key, box in pairs(view.ruleBoxes) do
        box:SetText(ns.FormatNumber(ns.Rule(key)))
    end
    view.filling = false
    view.dirty = false
end

local function updateRulesPreview(view)
    local twohand = ns.Round(typedRule(view, "tier_boss") * typedRule(view, "mult_twohand"))
    local ring = ns.Round(typedRule(view, "tier_normal") * typedRule(view, "mult_small"))
    local os = math.floor(twohand * typedRule(view, "offSpecPercent") / 100 + 0.5)
    view.preview:SetText(string.format(
        "Example, a two handed weapon from the end boss costs |cffffffff%d GP|r, for off spec |cffffffff%s|r. A ring from a normal boss costs |cffffffff%d GP|r.",
        twohand, os > 0 and (os .. " GP") or "nothing", ring))
    local canEdit = ns.CanEdit()
    view.save:SetEnabled(canEdit and view.dirty and true or false)
    view.discard:SetEnabled(view.dirty and true or false)
end

local function saveRules(view)
    local values = {}
    for key, box in pairs(view.ruleBoxes) do values[key] = box:GetText() end
    local changed, err = ns.SetRules(values)
    if not changed then
        view.status:SetText(RED_TEXT .. err .. "|r")
        return false
    end
    for _, box in pairs(view.ruleBoxes) do box:ClearFocus() end
    fillRules(view)
    if changed == 0 then
        view.status:SetText("Nothing changed.")
    elseif ns.IsTest() then
        view.status:SetText(ns.TEST_TAG .. GREEN .. "Saved " .. changed .. (changed == 1 and " change" or " changes") .. " in the test data.|r")
    else
        view.status:SetText(GREEN .. "Saved " .. changed .. (changed == 1 and " change" or " changes") .. ". Sync shares them with the other editors.|r")
    end
    updateRulesPreview(view)
    return true
end
ns.SaveRulesView = saveRules

local function buildSettingsContent(holder, top)
    local view = { ruleBoxes = {}, ruleOrder = {} }

    -- everything sits on a scrolling child, the page is longer than the window
    local scroll = create("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, top or -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    local parent = CreateFrame("Frame", nil, scroll)
    parent:SetWidth(480)
    scroll:SetScrollChild(parent)
    view.scroll = scroll

    local y = -8
    local function heading(label, font)
        local fs = text(parent, font or "GameFontNormal")
        fs:SetPoint("TOPLEFT", 12, y)
        fs:SetText(label)
        y = y - 22
        return fs
    end
    local function paragraph(font, lines)
        local fs = text(parent, font or "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 16, y)
        fs:SetWidth(450)
        fs:SetWordWrap(true)
        y = y - (lines or 1) * 13 - 6
        return fs
    end

    -- Test mode
    heading("Test mode")
    view.test = checkbox(parent, "Test mode", function(checked)
        ns.SetTestMode(checked)
        ns.RefreshSettings()
    end)
    view.test:SetPoint("TOPLEFT", 12, y)
    y = y - 30
    local info = paragraph(nil, 4)
    info:SetText("Try every function alone. The addon works on a copy of your data and rules with a simulated raid. Raid EP, bench, decay, the editor, alts, sync, bidding, rolls, awards and the rules below all work, but nothing is sent to other players and your real data stays as it is.")
    view.raid = paragraph(nil, 3)
    view.reset = button(parent, "Reset test data", 130, function()
        ns.ResetTestData()
        ns.Print(ns.TEST_TAG .. "test data copied again from the real data, new simulated raid")
        ns.RefreshSettings()
    end)
    view.reset:SetPoint("TOPLEFT", 14, y)
    view.newRaid = button(parent, "New simulated raid", 140, function()
        ns.PickTestRaid()
        ns.RefreshSettings()
    end)
    view.newRaid:SetPoint("LEFT", view.reset, "RIGHT", 4, 0)
    y = y - 40

    -- Interface
    heading("Interface")
    view.minimap = checkbox(parent, "Show the minimap button", function(checked)
        ns.SetMinimapShown(checked)
    end)
    view.minimap:SetPoint("TOPLEFT", 12, y)
    y = y - 28
    view.autoLoot = checkbox(parent, "Open Start Bidding when I loot good items in a group", function(checked)
        ns.SetSetting("autoOpenLoot", checked and true or false)
    end)
    view.autoLoot:SetPoint("TOPLEFT", 12, y)
    y = y - 40

    -- Editors
    heading("Editors", "GameFontNormalLarge")
    local editorInfo = paragraph(nil, 3)
    editorInfo:SetText("Editors may change points, run the bidding, award loot and change the rules, whatever their guild rank is. Only the guild leader adds or removes them. Sync shares the list with everyone.")
    view.editorList = paragraph("GameFontHighlight", 3)
    view.editorBox = ns.UIInputBox(parent, 180, false)
    view.editorBox:SetMaxLetters(48)
    view.editorBox:SetPoint("TOPLEFT", 20, y)
    local function changeEditor(on)
        local name = view.editorBox:GetText() or ""
        if name:match("^%s*$") then
            name = UnitIsPlayer and UnitIsPlayer("target") and ns.UnitFullName("target") or ""
        end
        if name:match("^%s*$") then
            view.editorStatus:SetText("|cffff8040Type a name or target the player first.|r")
            return
        end
        local full, matches = ns.FindMember(name, true)
        if not full then
            view.editorStatus:SetText("|cffff8040" .. (matches and ("More than one player matches " .. name .. ", type more of the name.")
                or ("Nobody in the guild is called " .. name .. ".")) .. "|r")
            return
        end
        local ok, result = ns.SetEditor(full, on)
        if ok then
            view.editorBox:SetText("")
            view.editorStatus:SetText(GREEN .. ns.ShortName(result) .. (on and " is now an editor." or " is no editor anymore.") .. "|r")
        else
            view.editorStatus:SetText("|cffff8040" .. result .. "|r")
        end
        ns.RefreshSettings()
    end
    view.editorBox:SetScript("OnEnterPressed", function() changeEditor(true) end)
    view.addEditor = button(parent, "Add", 80, function() changeEditor(true) end)
    view.addEditor:SetPoint("LEFT", view.editorBox, "RIGHT", 6, 0)
    view.removeEditor = button(parent, "Remove", 80, function() changeEditor(false) end)
    view.removeEditor:SetPoint("LEFT", view.addEditor, "RIGHT", 4, 0)
    y = y - 30
    view.rankEditors = button(parent, "Add the current officer ranks", 210, function()
        local count = ns.AddRankEditors()
        view.editorStatus:SetText(GREEN .. "Added " .. count .. (count == 1 and " editor." or " editors.") .. "|r")
        ns.RefreshSettings()
    end)
    view.rankEditors:SetPoint("TOPLEFT", 14, y)
    y = y - 30
    view.editorStatus = paragraph(nil, 2)
    y = y - 10

    -- Guild rules
    heading("Guild rules", "GameFontNormalLarge")
    view.rulesInfo = paragraph(nil, 3)
    view.rulesInfo:SetText("These rules are the same for the whole guild. Sync shares them with every editor, the newest change wins. The guild leader and editors can change them, everyone else can look.")

    for _, def in ipairs(ns.RULES) do
        if def.section then
            y = y - 4
            heading(def.section, "GameFontNormalSmall")
        end
        local label = text(parent, "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", 22, y - 4)
        label:SetWidth(320)
        label:SetText(def.label)
        local box = ns.UIInputBox(parent, 64, not def.decimal)
        box:SetPoint("TOPLEFT", 350, y)
        box:SetScript("OnTextChanged", function()
            if view.filling then return end
            view.dirty = true
            view.status:SetText("")
            updateRulesPreview(view)
        end)
        box:SetScript("OnEnterPressed", function() saveRules(view) end)
        box:SetScript("OnTabPressed", function(self)
            local i = self.ruleIndex % #view.ruleOrder + 1
            view.ruleOrder[i]:SetFocus()
        end)
        local tip = text(parent, "GameFontDisableSmall")
        tip:SetPoint("LEFT", box, "RIGHT", 8, 0)
        tip:SetText("default " .. ns.FormatNumber(def.default))
        view.ruleBoxes[def.key] = box
        table.insert(view.ruleOrder, box)
        box.ruleIndex = #view.ruleOrder
        y = y - 24
    end

    y = y - 6
    view.preview = paragraph(nil, 2)
    view.status = paragraph(nil, 2)
    view.changedBy = paragraph("GameFontDisableSmall", 1)

    view.save = button(parent, "Save rules", 110, function() saveRules(view) end)
    view.save:SetPoint("TOPLEFT", 14, y)
    view.discard = button(parent, "Discard changes", 130, function()
        fillRules(view)
        view.status:SetText("")
        updateRulesPreview(view)
    end)
    view.discard:SetPoint("LEFT", view.save, "RIGHT", 4, 0)
    view.defaults = button(parent, "Reset to defaults", 130, function()
        if StaticPopup_Show then StaticPopup_Show("REDGUILDFOREVER_RESET_RULES") end
    end)
    view.defaults:SetPoint("LEFT", view.discard, "RIGHT", 4, 0)
    y = y - 40

    view.version = paragraph("GameFontDisableSmall")
    view.version:SetText("Red Guild EPGP " .. ns.version)

    parent:SetHeight(-y + 20)
    fillRules(view)
    table.insert(settingsViews, view)
    return view
end

function ns.RefreshSettings()
    local test = ns.IsTest()
    local raidText
    if test then
        local names = {}
        for _, n in ipairs(ns.RaidMembers()) do table.insert(names, ns.ShortName(n)) end
        raidText = ns.TEST_TAG .. "Simulated raid " .. table.concat(names, ", ")
    else
        raidText = "|cff999999Turn on test mode to get a simulated raid.|r"
    end
    local canEdit = ns.CanEdit()
    local canManage = ns.CanManageEditors()

    -- who may edit
    local editorText
    if ns.EditorsInUse() then
        local names = {}
        for _, full in ipairs(ns.Editors()) do table.insert(names, ns.ShortName(full)) end
        editorText = "Editors besides the guild leader: |cffffffff" .. (#names > 0 and table.concat(names, ", ") or "nobody") .. "|r"
    else
        editorText = "The list is still empty, so the old rank rule applies: the guild leader and rank 1 to " .. ns.OfficerRank()
            .. " may edit. Once the guild leader adds the first editor, only the list counts."
    end
    if not canManage then
        editorText = editorText .. "\n|cff999999Only the guild leader can change the list.|r"
    end

    -- who changed the rules last
    local last
    for _, e in pairs(ns.Data().rules or {}) do
        if e.t and (not last or e.t > last.t) then last = e end
    end
    local changedBy = last and last.by
        and ("Rules last changed by " .. ns.ShortName(last.by) .. " on " .. date("%d.%m. %H:%M", last.t))
        or "The rules are still the defaults of the rule book."

    for _, view in ipairs(settingsViews) do
        view.test:SetChecked(test)
        view.raid:SetText(raidText)
        view.reset:SetEnabled(test)
        view.newRaid:SetEnabled(test)
        local mm = RedGuildForeverDB and RedGuildForeverDB.minimap
        view.minimap:SetChecked(not (mm and mm.hide))
        view.autoLoot:SetChecked(ns.Setting("autoOpenLoot") and true or false)

        view.editorList:SetText(editorText)
        view.editorBox:SetEnabled(canManage)
        view.addEditor:SetEnabled(canManage)
        view.removeEditor:SetEnabled(canManage)
        view.rankEditors:SetShown(canManage and not ns.EditorsInUse())

        if not view.dirty then fillRules(view) end
        for _, box in pairs(view.ruleBoxes) do box:SetEnabled(canEdit) end
        view.defaults:SetEnabled(canEdit)
        view.changedBy:SetText(changedBy)
        if not canEdit and (view.status:GetText() or "") == "" then
            view.status:SetText("|cff999999Only the guild leader and editors can change the rules.|r")
        end
        updateRulesPreview(view)
    end
end

local function buildSettingsPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()
    buildSettingsContent(page)
    return page
end

-- the same settings in the game's Options window, under AddOns
local function registerOptions()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local panel = CreateFrame("Frame")
    local title = text(panel, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText("Red Guild EPGP")
    buildSettingsContent(panel, -40)
    panel:SetScript("OnShow", function() ns.RefreshSettings() end)
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Red Guild EPGP")
    if ok and category then
        pcall(Settings.RegisterAddOnCategory, category)
        ns.optionsCategory = category
    end
end
ns.On("RGF_READY", registerOptions)
ns.On("RGF_TEST_MODE", function() ns.RefreshSettings() end)
ns.On("RGF_RULES_CHANGED", function() ns.RefreshSettings() end)
ns.On("RGF_EDITORS_CHANGED", function()
    ns.RefreshSettings()
    if ns.RefreshStandings then ns.RefreshStandings() end
end)

if StaticPopupDialogs then
    StaticPopupDialogs["REDGUILDFOREVER_RESET_RULES"] = {
        text = "Set all guild rules back to the defaults of the rule book?\nFixed prices for single items stay.",
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function()
            local changed, err = ns.ResetRules()
            if changed then
                ns.Print(changed > 0 and "guild rules set back to the defaults" or "the rules already are the defaults")
            else
                ns.Print(err)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

local function buildHistoryPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()
    headerRow(page, historyColumns)
    page.list = scrollList(page, 20, function(row)
        rowCells(row, historyColumns)
        -- every change can be undone, also an old one or one of another editor
        row.undo = button(row, "Undo", 56, function()
            if not row.id then return end
            local done = ns.UndoEvent(row.id)
            if done then ns.Print("undone " .. done.label) end
        end)
        row.undo:SetHeight(18)
        row.undo:SetPoint("RIGHT", -4, 0)
    end)
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
        buildSyncPage(f.Inset),
        buildSettingsPage(f.Inset),
    }

    -- bottom strip, only editors get buttons. Sync runs by itself and is in the Data tab
    f.lootMaster = button(f, "Loot Master", 110, function() ns.OpenLootMaster() end)
    f.lootMaster:SetPoint("BOTTOMLEFT", 6, 4)

    f.standingsButtons = CreateFrame("Frame", nil, f)
    f.standingsButtons:SetSize(1, 22)
    f.standingsButtons:SetPoint("BOTTOMRIGHT", -6, 4)
    local undo = button(f.standingsButtons, "Undo", 70, function() ns.Command("undo") end)
    undo:SetPoint("RIGHT")
    local ontime = button(f.standingsButtons, "On time EP", 96, function() ns.Command("ontime") end)
    ontime:SetPoint("RIGHT", undo, "LEFT", -2, 0)
    local raid = button(f.standingsButtons, "Raid EP", 86, function() ns.Command("raid") end)
    raid:SetPoint("RIGHT", ontime, "LEFT", -2, 0)

    f.benchButtons = CreateFrame("Frame", nil, f)
    f.benchButtons:SetSize(1, 22)
    f.benchButtons:SetPoint("BOTTOMRIGHT", -6, 4)
    local clear = button(f.benchButtons, "Clear bench", 104, function() ns.BenchClear() end)
    clear:SetPoint("RIGHT")
    local add = button(f.benchButtons, "Add target", 104, function()
        local full = UnitIsPlayer("target") and ns.UnitFullName("target")
        if not full then
            ns.Print("target a player first, or type /rgf bench add Name")
            return
        end
        ns.BenchAdd(full)
    end)
    add:SetPoint("RIGHT", clear, "LEFT", -2, 0)

    tabs(f, name, { "Standings", "Bench", "History", "Data", "Settings" }, showPage)
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
        row.remove:SetShown(ns.CanEdit())
        row:Show()
    end
    page.list:SetCount(#list)
end

local function refreshHistoryPage(page)
    local log = ns.Log() or {}
    local canEdit = ns.CanEdit()
    local n = 0
    for i = #log, 1, -1 do
        local e = log[i]
        n = n + 1
        local row = page.list:Row(n)
        row.id = e.id
        row.cells.time:SetText(date("%d.%m. %H:%M", e.time))
        row.cells.label:SetText(e.undone and ("|cff808080" .. e.label .. ", undone|r") or e.label)
        row.cells.by:SetText(ns.ShortName(e.by))
        row.undo:SetShown(canEdit and e.id ~= nil and not e.undo and not e.undone)
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
    elseif tab == 3 then
        refreshHistoryPage(main.pages[3])
    elseif tab == 4 then
        refreshSyncPage(main.pages[4])
    else
        ns.RefreshSettings()
    end
    setTitle(main, ns.IsTest() and "Red Guild EPGP  |cffff8040Test mode|r" or "Red Guild EPGP")
    main.lootMaster:SetShown(ns.CanEdit())

    local me = ns.PlayerName()
    local ep, gp, pr = ns.GetPoints(me)
    main.summary:SetText((ns.IsTest() and ns.TEST_TAG or "") .. "Your priority |cffffffff" .. ns.FormatPR(pr) .. "|r  (" .. ep .. " EP, " .. gp .. " GP)")

    local status
    if not (IsInGuild and IsInGuild()) then
        status = "You are not in a guild"
    elseif tab == 2 then
        status = #ns.Bench() .. " players on the bench"
    elseif tab == 3 then
        status = "Every change of every editor, shared with Sync"
    elseif tab == 4 then
        status = "Sync, decay and backup"
    elseif tab == 5 then
        status = "Settings"
    elseif not ns.HasData() then
        status = "|cffff8040No data yet, click Sync|r"
    else
        status = count .. " players, blue priority means new member"
    end
    main.status:SetText(status)
end

ns.RefreshBench = ns.RefreshStandings

function ns.ToggleStandings(tab)
    main = main or buildMain()
    ns.mainFrame = main
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
        setTitle(f, ns.IsTest() and "Edit Player  |cffff8040Test mode|r" or "Edit Player")
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
    if not ns.CanEdit() then
        ns.Print("only the guild leader and editors can change points")
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
ns.On("RGF_SYNC_DONE", function() ns.RefreshStandings() end)
ns.On("RGF_TEST_MODE", function() ns.RefreshStandings() end)

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
        local osCost = ns.OffSpecCost(ns.auction and ns.auction.price or 0)
        row.cells.pr:SetText(osCost > 0 and (osCost .. " GP") or "free")
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
    setTitle(lm, a.test and "Loot Master  |cffff8040Test mode|r" or "Loot Master")
    local _, _, icon = ns.ItemInfo(a.link)
    setPortrait(lm, icon or ICON_UNKNOWN)
    lm.item:SetText(a.link)
    lm.price:SetText("Main spec costs |cffffffff" .. a.price .. " GP|r, " .. ns.OffSpecText(a.price) .. (a.fixed and ", fixed price" or ""))
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
    setTitle(popup, ns.IsTest() and "Loot Bid  |cffff8040Test mode|r" or "Loot Bid")
    local _, _, icon = ns.ItemInfo(inc.link)
    setPortrait(popup, icon or ICON_UNKNOWN)
    popup.slot:SetItem(inc.link)
    popup.item:SetText(inc.link)
    popup.price:SetText("Main spec |cffffffff" .. inc.price .. " GP|r, " .. ns.OffSpecText(inc.price))

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
    StaticPopupDialogs["REDGUILDFOREVER_FRESH"] = {
        text = "Start with empty EPGP data for this guild?\nOnly do this for a new guild. If editors have data, click Sync instead.",
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function()
            if ns.StartFresh() then ns.Print("started with empty data, you can now give EP") end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
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
