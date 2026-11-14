--[[
  The Hall of the Kor'kron: the addon's main window (Overlord style: dark parchment, faction accents).

    Chronicle       your battles over a day, week, month or all time: tiles, details, the battles themselves
    Battles         every battle you fought, newest first; click one for its battle card
    From the field  guildies' battles you weren't in (the guild feed; needs guild sync)
    War Ledger      your deeds as tiered challenges, Legacy style
    Settings        notifications, guild sync, a test battle, diagnostics

  One frame, two places: on its own (/kkc), or docked inside Forever's Legacy window behind our own side tab. When
  docked it is simply laid over the Legacy content; Blizzard's frames are never changed, only hooked (HookScript), so
  the addon can't taint them into blocked-action errors.
]]

local _, KKC = ...
local Hub = {}
KKC.Hub = Hub
local Theme = KKC.Theme

-- On its own the hall is an open book with two equal pages; docked it fills the Legacy window.
local WIDTH, HEIGHT = 1000, 680
local SPINE = WIDTH / 2
local PAGE_L, PAGE_R = 44, SPINE + 26 -- where text starts on the left and the right page
local PAGE_W = SPINE - 26 - 44 - 18  -- text width on a page (430)
local NAV_W = 196
local hall, tab
local current = { section = "chronicle", period = "week" }

local SECTIONS = {
    { key = "chronicle", label = "Chronicle", icon = "Interface\\Icons\\INV_Misc_Book_09",
      tip = "Your battles over a day, a week, a month or all time." },
    { key = "battles", label = "Battles", icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
      tip = "Every battle you fought, newest first. Click one to read its report." },
    { key = "field", label = "From the field", icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
      tip = "Battles guildies with the addon fought without you. Needs guild sync (Settings)." },
    { key = "ledger", label = "War Ledger", icon = "Interface\\Icons\\INV_Scroll_03",
      tip = "Your deeds as challenges: foes slain, by race and by class." },
    { key = "settings", label = "Settings", icon = "Interface\\Icons\\Trade_Engineering",
      tip = "Notifications, guild sync, a test battle and diagnostics." },
}

-- Texts written once when the hall is built, in the dim color: rewritten when the look changes (dark <-> book).
local dimTexts = {}
local function dim(fs, text)
    fs.dimText = text
    dimTexts[#dimTexts + 1] = fs
    fs:SetText(Theme.DIM .. text .. "|r")
end
local function redrawDim()
    for _, fs in ipairs(dimTexts) do fs:SetText(Theme.DIM .. fs.dimText .. "|r") end
end

-- A battle in one colored line: the place in blue, the enemy count in their faction's color, kills green, our losses
-- red, the rest dim. "Tarren Mill - 4 against 6, 5+ slain, 1 fallen".
local function colored(e)
    local st = KKC.Stats(e)
    local parts = { Theme.PLACE .. KKC.Report.Place(e) .. "|r" .. Theme.DIM .. " - |r" .. st.members .. Theme.DIM
        .. " against |r" .. Theme.Foe() .. st.enemies .. "|r" }
    if e.campaign then parts[#parts + 1] = Theme.DIM .. e.fights .. " clashes|r" end
    if st.kills > 0 then parts[#parts + 1] = Theme.GOOD .. st.kills .. "+ slain|r" end
    if #st.fallen > 0 then parts[#parts + 1] = Theme.BAD .. #st.fallen .. " fallen|r" end
    return table.concat(parts, Theme.DIM .. ", |r")
end

local function headline(e)
    if e.campaign then
        return Theme.HALL_GOLD .. KKC.Campaign.Name(e) .. "|r  " .. colored(e) .. "  " .. Theme.DIM .. "~ until " .. date("%H:%M", e.stop) .. "|r"
    end
    local tags = {}
    if e.minor then tags[#tags + 1] = Theme.DIM .. "skirmish|r" end
    if e.feed then tags[#tags + 1] = Theme.DIM .. "by " .. (KKC.Initiator(e) or "?") .. "|r" end
    return colored(e) .. (#tags > 0 and ("  " .. Theme.DIM .. "~|r " .. table.concat(tags, ", ")) or "")
end

-- How many rows of `step` pixels fit in `frame` between `top` and `bottom` pixels of margin. Fonts and the docked
-- Legacy window change the space, so lists are fitted to it instead of assuming a size. `fallback` before layout.
local function fit(frame, top, bottom, step, fallback, max)
    local h = KKC.try(frame.GetHeight, frame)
    if type(h) ~= "number" or h <= 0 then return fallback end
    return math.max(1, math.min(max, math.floor((h - top - bottom) / step)))
end

-- The mouse wheel moves a list three rows at a time (p.offset), and a resize refits it.
local function scrollable(frame, p)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) p.offset = (p.offset or 0) - delta * 3; p:Refresh() end)
    p:SetScript("OnSizeChanged", function(self) if self:IsShown() then self:Refresh() end end)
end

-- Clamp p.offset to a list of `total` items showing `visible` at a time; returns the offset.
local function clamp(p, total, visible)
    p.offset = math.max(0, math.min(p.offset or 0, total - visible))
    return p.offset
end

-- Text that scrolls (wheel or the bar) when it is longer than its box.
local function scrollText(parent, size)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(400, 10)
    scroll:SetScrollChild(child)
    local fs = Theme.LightText(child, size)
    fs:SetPoint("TOPLEFT", 0, 0)
    fs:SetJustifyV("TOP")
    fs:SetSpacing(4)
    local function relayout()
        local w = KKC.try(scroll.GetWidth, scroll)
        if type(w) == "number" and w > 0 then child:SetWidth(w); fs:SetWidth(w) end
        local h = KKC.try(fs.GetStringHeight, fs)
        child:SetHeight((type(h) == "number" and h or 0) + 8)
    end
    scroll:SetScript("OnSizeChanged", relayout)
    function scroll:SetBody(text)
        fs:SetText(text)
        relayout()
        KKC.try(self.SetVerticalScroll, self, 0)
    end
    scroll.text = fs
    return scroll
end

-- Puts a region at one anchor, dropping the old ones.
local function at(region, point, rel, relPoint, x, y)
    region:ClearAllPoints()
    region:SetPoint(point, rel, relPoint, x or 0, y or 0)
end

-- The period buttons: one row of six above the section when docked; two rows of three on the left page in the book.
local function layoutPeriods(p, book, side, y)
    for i, b in ipairs(p.periods) do
        if book then
            b:SetSize(138, 32)
            at(b, "TOPLEFT", side, "TOPLEFT", ((i - 1) % 3) * 146, y - math.floor((i - 1) / 3) * 36)
        else
            b:SetSize(100, 24)
            at(b, "TOPLEFT", p, "TOPLEFT", (i - 1) * 105, 0)
        end
    end
end

-- A section's heading and the line under it: on the left page in the book, at the top of the section when docked.
local function layoutHeading(p, book, side, sub, dockedY)
    if book then at(p.heading, "TOPLEFT", side, "TOPLEFT", 0, 0) else at(p.heading, "TOPLEFT", p, "TOPLEFT", 2, dockedY) end
    if sub then
        at(sub, "TOPLEFT", p.heading, "BOTTOMLEFT", 0, -3)
        sub:SetWidth(book and PAGE_W or 640)
    end
end

-- A written tally for the book's left page, like a ledger: a label on the left, the number on the right, a faint line
-- between the rows. (Tiles in a grid read as buttons.) t:Set({ { "Battles", "12" }, ... }) fills it.
local TALLY_ROW = 24
local function tally(parent, rows)
    local t = CreateFrame("Frame", nil, parent)
    t:SetSize(PAGE_W, rows * TALLY_ROW)
    t.rows = {}
    for i = 1, rows do
        local r = {}
        local y = -(i - 1) * TALLY_ROW
        r.label = Theme.LightText(t, 13)
        r.label:SetPoint("LEFT", t, "TOPLEFT", 4, y - TALLY_ROW / 2)
        r.value = Theme.LightText(t, 16, "RIGHT", true)
        r.value:SetPoint("RIGHT", t, "TOPRIGHT", -4, y - TALLY_ROW / 2)
        if i < rows then
            r.line = t:CreateTexture(nil, "ARTWORK")
            r.line:SetHeight(1)
            r.line:SetPoint("TOPLEFT", t, "TOPLEFT", 0, y - TALLY_ROW)
            r.line:SetPoint("TOPRIGHT", t, "TOPLEFT", PAGE_W, y - TALLY_ROW)
            r.line:SetColorTexture(0.62, 0.52, 0.36, 0.25)
        end
        t.rows[i] = r
    end
    function t:Set(items)
        for i, r in ipairs(self.rows) do
            local item = items[i]
            r.label:SetText(item and (Theme.DIM .. item[1] .. "|r") or "") -- not dim(): that keeps every call
            r.value:SetText(item and item[2] or "")
        end
    end
    return t
end

-- A clickable battle row: "Wed 21:14   Tarren Mill - 4 against 6, 5 slain". Click: the battle card.
local function battleRow(parent, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 20)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    local F = Theme.F()
    hl:SetColorTexture(F.accent[1], F.accent[2], F.accent[3], 0.22)
    b.when = Theme.LightText(b, 12)
    b.when:SetPoint("LEFT", 4, 0)
    b.when:SetWidth(64)
    b.when:SetWordWrap(false)
    b.what = Theme.LightText(b, 12)
    b.what:SetPoint("LEFT", 70, 0)
    b.what:SetPoint("RIGHT", -20, 0)
    b.what:SetWordWrap(false)
    -- A small arrow at the end of each battle: it opens something (gold under the mouse).
    b.arrow = Theme.LightText(b, 14, "RIGHT", false, true)
    b.arrow:SetPoint("RIGHT", -5, 0)
    b.arrow:SetText(">")
    b.arrow:SetTextColor(0.70, 0.62, 0.48)
    -- A day's heading in the diary: a diamond and the date.
    b.diamond = b:CreateTexture(nil, "ARTWORK")
    b.diamond:SetSize(7, 7)
    b.diamond:SetPoint("LEFT", 6, 0)
    b.diamond:SetColorTexture(1, 0.82, 0, 1)
    if b.diamond.SetRotation then b.diamond:SetRotation(math.pi / 4) end
    b.day = Theme.LightText(b, 13, "LEFT", true)
    b.day:SetPoint("LEFT", 20, 0)
    -- A campaign in the book: a slightly lighter card on the page.
    b.shadow = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.shadow:SetPoint("TOPLEFT", 3, -1)
    b.shadow:SetPoint("BOTTOMRIGHT", 3, -3)
    b.shadow:SetColorTexture(0, 0, 0, 0.45)
    b.card = b:CreateTexture(nil, "BACKGROUND", nil, 2)
    b.card:SetPoint("TOPLEFT", 0, 1)
    b.card:SetPoint("BOTTOMRIGHT", 0, -1)
    b.card:SetColorTexture(0.24, 0.17, 0.10, 0.95)
    b:SetScript("OnClick", function(self) if self.engagement then KKC.UI.ShowCard(self.engagement) end end)
    -- What a click opens, under the mouse.
    b:SetScript("OnEnter", function(self)
        local e = self.engagement
        if not e then return end
        self.arrow:SetTextColor(1, 0.82, 0)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(e.campaign and (KKC.Campaign.Name(e) .. ": " .. KKC.Report.Place(e)) or KKC.Report.Place(e), 1, 0.82, 0)
        if e.campaign then
            GameTooltip:AddLine("Click: the battle card for the whole outing, one report for the night (with its roll calls).", 1, 1, 1, true)
        elseif self.inCampaign then
            GameTooltip:AddLine("Click: the battle card for just this fight. The row above it is the whole outing.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Click: the battle card for this fight.", 1, 1, 1, true)
        end
        GameTooltip:AddLine("On the card: Scribe report copies the report text, Capture likeness is for the screenshot.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self.arrow:SetTextColor(0.70, 0.62, 0.48)
        GameTooltip:Hide()
    end)
    -- A diary line: the time, then the battle. inCampaign: a fight under its campaign, indented. day: instead a day's
    -- heading ("WEDNESDAY 11 NOVEMBER").
    function b:Set(e, inCampaign, day)
        self.engagement, self.inCampaign = e, inCampaign
        if not (e or day) then return self:Hide() end
        self:EnableMouse(e ~= nil) -- a day's heading isn't clickable, so it doesn't light up either
        self.arrow:SetShown(e ~= nil)
        local card = e and e.campaign and Theme.book
        for _, t in ipairs({ self.card, self.shadow }) do t:SetShown(card or false) end
        self.diamond:SetShown(day ~= nil)
        self.day:SetText(day or "")
        if day then
            self.when:SetText("")
            self.what:SetText("")
        else
            self.when:SetText(Theme.DIM .. (inCampaign and "      " or "  ") .. date("%H:%M", e.start) .. "|r")
            self.what:SetText((inCampaign and "    " or "") .. headline(e))
        end
        self:Show()
    end
    return b
end

-- ------------------------------------------------------------------------------------------------
-- Chronicle (and From the field, which is the same page over the guild feed)
-- ------------------------------------------------------------------------------------------------

local TILES = {
    { key = "battles", label = "Battles" },
    { key = "kills", label = "Foes slain" },
    { key = "fallen", label = "Kor'kron fallen" },
    { key = "blow", label = "First blow (ours / theirs)" },
}

local function buildChronicle(parent, guild)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()
    p:Hide()

    p.periods = {}
    for i, per in ipairs(KKC.Summary.PERIODS) do
        local b = Theme.HallButton(p, per.label, 100, 24, nil, nil, function()
            current.period = per.key
            Hub.Refresh()
        end)
        b.key = per.key
        p.periods[i] = b
    end

    p.heading = Theme.LightText(p, 19, "LEFT", true)
    p.span = Theme.LightText(p, 11)

    p.tiles = {}
    for i, t in ipairs(TILES) do
        local box = Theme.Inset(p, true) -- no dividers: four tiles in a grid were a thicket of lines
        box.index = i
        box.value = Theme.LightText(box, 22, "CENTER", true)
        box.value:SetPoint("TOP", 0, -4)
        box.label = Theme.LightText(box, 11, "CENTER")
        box.label:SetPoint("BOTTOM", 0, 5)
        dim(box.label, t.label)
        p.tiles[t.key] = box
    end

    p.tally = tally(p, 4)

    -- The details take all the room down to the buttons and scroll when a long week doesn't fit. (Its battles are
    -- under Battles: a list here too didn't fit.)
    local details = Theme.Inset(p)
    p.details = details
    p.body = scrollText(details, 12)
    p.body:SetPoint("TOPLEFT", 12, -10)
    p.body:SetPoint("BOTTOMRIGHT", -30, 8)

    p.copy = Theme.HallButton(p, "Scribe chronicle", 150, 26, "Interface\\Icons\\INV_Scroll_03",
        "Copy this chronicle as text, to paste in Discord or keep.", function()
            if p.data then KKC.UI.ShowCopy(p.text, p.title, "Ctrl+C, then paste it wherever the tale should be told.") end
        end)
    if not guild then
        p.share = Theme.HallButton(p, "Sound the horn", 150, 26, "Interface\\Icons\\INV_Misc_Horn_01",
            "Post a one-line summary of these battles in guild chat (and Discord, if guild chat is linked).", function()
                if p.data then KKC.UI.SendGuild(KKC.Summary.ShareLine(p.data, p.label)) end
            end)
        p.share:SetPoint("LEFT", p.copy, "RIGHT", 8, 0)
    end

    -- Book: heading, periods, the tiles in a 2 x 2 grid and the buttons on the left page; the details fill the
    -- right page. Docked: periods, heading, a row of tiles, the details and the buttons, top to bottom.
    function p:Layout(book, side)
        layoutHeading(self, book, side, self.span, -36)
        layoutPeriods(self, book, side, -44)
        self.tally:SetShown(book)
        at(self.tally, "TOPLEFT", side, "TOPLEFT", 0, -120)
        for _, box in pairs(self.tiles) do
            local i = box.index
            box:SetShown(not book)
            if not book then
                box:SetSize(152, 58)
                at(box, "TOPLEFT", self, "TOPLEFT", (i - 1) * 160, -84)
            end
        end
        self.details:ClearAllPoints()
        if book then
            self.details:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -4)
            self.details:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 4)
            at(self.copy, "BOTTOMLEFT", side, "BOTTOMLEFT", 0, 0)
            -- The two buttons share the page's width (just one, filling it, on From the field).
            for _, b in ipairs({ self.copy, self.share }) do b:SetSize(self.share and 211 or PAGE_W, 32) end
        else
            for _, b in ipairs({ self.copy, self.share }) do b:SetSize(150, 26) end
            self.details:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -152)
            self.details:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 34)
            at(self.copy, "BOTTOMLEFT", self, "BOTTOMLEFT", 0, 0)
        end
    end

    function p:Refresh()
        for _, b in ipairs(self.periods) do b:SetSelected(b.key == current.period) end
        local from, to, label = KKC.Summary.Range(current.period)
        local data = KKC.Summary.Build(guild and KKC.db.feed or KKC.db.log, from, to)
        self.data, self.label = data, label
        self.text = KKC.Summary.Text(data, label, guild)
        self.title = (guild and "Word from the Field - " or "War Chronicle - ") .. label
        local heading, span, body = KKC.Summary.Parts(data, label, guild, true)
        self.heading:SetText(heading)
        self.span:SetText(Theme.DIM .. span .. "|r")
        if guild and not KKC.settings().sync then
            body = Theme.DIM .. "Guild sync is off, so no word comes from the field. Turn it on under Settings to hear "
                .. "of battles guildies with the addon fight without you.|r"
        end
        self.body:SetBody(body)
        self.tiles.battles.value:SetText(data.engagements)
        self.tiles.kills.value:SetText(Theme.GOOD .. data.kills .. "|r")
        self.tiles.fallen.value:SetText(Theme.BAD .. data.fallen .. "|r")
        self.tiles.blow.value:SetText(("%s%d|r / %s%d|r"):format(Theme.GOOD, data.struck, Theme.BAD, data.ambushed))
        if self.share then self.share:SetEnabled(data.engagements > 0) end
        self.tally:Set({
            { "Battles", data.engagements .. Theme.DIM .. "  (" .. data.notable .. " of note)|r" },
            { "Foes slain", Theme.GOOD .. data.kills .. "|r" },
            { "Kor'kron fallen", Theme.BAD .. data.fallen .. "|r" },
            { "First blow, ours / theirs", ("%s%d|r / %s%d|r"):format(Theme.GOOD, data.struck, Theme.BAD, data.ambushed) },
        })

    end
    return p
end

-- ------------------------------------------------------------------------------------------------
-- Battles: the whole log, paged
-- ------------------------------------------------------------------------------------------------

local BATTLE_ROWS = 30 -- built; as many as fit are shown

local function buildBattles(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()
    p:Hide()
    p.offset, p.showMinor = 0, false

    -- The same periods as the Chronicle (and the same choice: switching sections keeps it).
    p.periods = {}
    for i, per in ipairs(KKC.Summary.PERIODS) do
        local b = Theme.HallButton(p, per.label, 100, 24, nil, nil, function()
            current.period = per.key
            p.offset = 0
            Hub.Refresh()
        end)
        b.key = per.key
        p.periods[i] = b
    end

    p.heading = Theme.LightText(p, 19, "LEFT", true)
    p.sub = Theme.LightText(p, 11)

    local box = Theme.Inset(p)
    p.rows = {}
    for i = 1, BATTLE_ROWS do
        local r = battleRow(box, 610)
        r:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 21)
        p.rows[i] = r
    end

    scrollable(box, p)
    p.box = box
    -- Above the list in the book: the rows are what you click.
    p.hint = Theme.LightText(p, 12, "LEFT")
    dim(p.hint, "Click a battle to open its battle card. A campaign row opens the whole outing.")
    p.newer = Theme.HallButton(p, "< Newer", 100, 26, nil, nil, function() p.offset = p.offset - (p.visible or 10); p:Refresh() end)
    p.older = Theme.HallButton(p, "Older >", 100, 26, nil, nil, function() p.offset = p.offset + (p.visible or 10); p:Refresh() end)
    p.older:SetPoint("LEFT", p.newer, "RIGHT", 8, 0)
    p.pageText = Theme.LightText(p, 12)
    p.tally = tally(p, 3)
    p.minor = Theme.HallButton(p, "Show skirmishes", 150, 26, nil,
        "Also list the passing skirmishes (a stray hit, no kills): they are kept but never announced.", function()
            p.showMinor = not p.showMinor
            p.offset = 0
            p:Refresh()
        end)

    -- Book: heading, periods, the skirmish toggle and the paging on the left page; the list fills the right page.
    function p:Layout(book, side)
        layoutHeading(self, book, side, self.sub, -36)
        layoutPeriods(self, book, side, -52)
        self.box:ClearAllPoints()
        if book then
            at(self.hint, "TOPLEFT", self, "TOPLEFT", 4, -4)
            self.hint:Show()
            self.box:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -22)
            self.box:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 4)
            -- Bottom row, like the periods: newer, older, skirmishes; where you are in the list just above.
            for i, b in ipairs({ self.newer, self.older, self.minor }) do
                b:SetSize(138, 32)
                at(b, "BOTTOMLEFT", side, "BOTTOMLEFT", (i - 1) * 146, 0)
            end
            at(self.pageText, "BOTTOM", side, "BOTTOM", 0, 38)
            self.pageText:SetJustifyH("CENTER")
            at(self.tally, "TOPLEFT", side, "TOPLEFT", 0, -126)
        else
            self.hint:Hide() -- docked, the line under the heading says it
            for _, b in ipairs({ self.newer, self.older }) do b:SetSize(100, 26) end
            self.minor:SetSize(150, 26)
            at(self.older, "LEFT", self.newer, "RIGHT", 8, 0)
            at(self.pageText, "LEFT", self.older, "RIGHT", 12, 0)
            self.pageText:SetJustifyH("LEFT")
            self.box:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -78)
            self.box:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 34)
            at(self.minor, "BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
            at(self.newer, "BOTTOMLEFT", self, "BOTTOMLEFT", 0, 0)
        end
        for _, r in ipairs(self.rows) do r:SetWidth(book and PAGE_W - 16 or 610) end
        self.tally:SetShown(book)
    end

    function p:Refresh()
        for _, b in ipairs(self.periods) do b:SetSelected(b.key == current.period) end
        local from, to, label = KKC.Summary.Range(current.period)
        if self.period ~= current.period then self.period, self.offset = current.period, 0 end
        self.heading:SetText("Battles - " .. label)
        -- A campaign (two or more fights in one outing) gets its own row, its fights listed under it. Campaigns are
        -- grouped over the whole log, so one that crosses midnight or the weekly reset isn't cut in two.
        -- Written like a diary: a heading for each day, then that day's campaigns and battles with their times.
        local list, battles, lastDay = {}, 0, nil
        local campaigns, slain, fallen = 0, 0, 0
        local function dayOf(t)
            local key = date("%Y-%m-%d", t)
            if key ~= lastDay then
                lastDay = key
                list[#list + 1] = { day = date("%A %d %B", t):upper() }
            end
        end
        for _, c in ipairs(KKC.Campaign.Group(KKC.db.log)) do
            local fights = {}
            for _, e in ipairs(c.fights) do
                if (self.showMinor or not e.minor) and e.start >= from and e.start < to then fights[#fights + 1] = e end
            end
            battles = battles + #fights
            for _, e in ipairs(fights) do
                local st = KKC.Stats(e)
                slain, fallen = slain + st.kills, fallen + #st.fallen
            end
            if #c.fights > 1 and #fights > 0 then campaigns = campaigns + 1 end
            if #fights > 0 then dayOf(fights[#fights].start) end
            if #c.fights > 1 and #fights > 0 then
                list[#list + 1] = { e = KKC.Campaign.View(c) }
                for _, e in ipairs(fights) do list[#list + 1] = { e = e, inCampaign = true } end
            elseif #fights > 0 then
                list[#list + 1] = { e = fights[1] }
            end
        end
        local visible = fit(self.box, 8, 8, 21, 18, BATTLE_ROWS)
        self.visible = visible
        local offset = clamp(self, #list, visible)
        for i, r in ipairs(self.rows) do
            local item = i <= visible and list[offset + i]
            r:Set(item and item.e, item and item.inCampaign, item and item.day)
        end
        self.newer:SetEnabled(offset > 0)
        self.older:SetEnabled(offset + visible < #list)
        self.pageText:SetText(Theme.DIM .. (#list > 0 and ("%d-%d of %d  (mouse wheel scrolls)"):format(offset + 1,
            math.min(#list, offset + visible), #list) or "") .. "|r")
        self.minor:SetSelected(self.showMinor)
        self.tally:Set({
            { "Battles", battles .. (campaigns > 0 and (Theme.DIM .. "  (" .. campaigns .. " outings)|r") or "") },
            { "Foes slain, at least", Theme.GOOD .. slain .. "|r" },
            { "Kor'kron fallen", Theme.BAD .. fallen .. "|r" },
        })
        self.sub:SetText(Theme.DIM .. (#list > 0 and ("%d battles. Click one in the list to open its battle card; a campaign row opens the whole outing."):format(battles)
            or "No battles in this time. The blades stay sheathed... for now.") .. "|r")
    end
    return p
end

-- ------------------------------------------------------------------------------------------------
-- War Ledger: tiered challenges, Legacy style
-- ------------------------------------------------------------------------------------------------

local LEDGER_ROWS = 10 -- built; as many as fit are shown

local function buildLedger(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()
    p:Hide()
    p.offset = 0
    scrollable(p, p)

    p.heading = Theme.LightText(p, 19, "LEFT", true)
    p.heading:SetText("War Ledger")
    p.sub = Theme.LightText(p, 11)

    p.rows = {}
    for i = 1, LEDGER_ROWS do
        local row = Theme.Inset(p)
        row:SetHeight(58)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(40, 40)
        row.icon:SetPoint("LEFT", 9, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.title = Theme.LightText(row, 15, "LEFT", true)
        row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 12, -2)
        row.bar = Theme.Bar(row, 160, 16)
        row.bar:SetPoint("RIGHT", -14, 4)
        row.title:SetPoint("RIGHT", row.bar, "LEFT", -10, 0)
        row.title:SetWordWrap(false)
        row.text = Theme.LightText(row, 12)
        row.text:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
        row.text:SetPoint("RIGHT", row.bar, "LEFT", -10, 0)
        row.tier = Theme.LightText(row, 11, "CENTER")
        row.tier:SetPoint("TOP", row.bar, "BOTTOM", 0, -3)
        p.rows[i] = row
    end

    p.prev = Theme.HallButton(p, "< Previous", 110, 26, nil, nil, function() p.offset = p.offset - (p.visible or 6); p:Refresh() end)
    p.next = Theme.HallButton(p, "Next >", 110, 26, nil, nil, function() p.offset = p.offset + (p.visible or 6); p:Refresh() end)
    p.next:SetPoint("LEFT", p.prev, "RIGHT", 8, 0)
    p.pageText = Theme.LightText(p, 12)
    p.pageText:SetPoint("LEFT", p.next, "RIGHT", 12, 0)

    -- Book: heading, totals and paging on the left page; the challenges fill the right page.
    function p:Layout(book, side)
        layoutHeading(self, book, side, self.sub, -2)
        self.top, self.bottom = book and 4 or 44, book and 4 or 34
        for i, row in ipairs(self.rows) do
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -self.top - (i - 1) * 64)
            row:SetPoint("RIGHT", self, "RIGHT", 0, 0)
        end
        at(self.prev, "BOTTOMLEFT", book and side or self, "BOTTOMLEFT", 0, 0)
    end

    function p:Refresh()
        local tracks = KKC.Ledger.Tracks()
        local l = KKC.Ledger.Mine()
        self.sub:SetText(Theme.DIM .. ("%s: %d slain, %d unique foes, fallen %d times. Only your own killing blows count.")
            :format(KKC.me() or "?", l.total, KKC.count(l.enemy), l.fallen) .. "|r")
        local visible = fit(self, self.top or 44, self.bottom or 34, 64, 6, LEDGER_ROWS)
        self.visible = visible
        local offset = clamp(self, #tracks, visible)
        for i, row in ipairs(self.rows) do
            local t = i <= visible and tracks[offset + i]
            if t then
                row.icon:SetTexture(t.icon)
                row.icon:SetDesaturated(t.tier == 0)
                -- Done: gold in the dark hall (in the book every title is already the game's yellow).
                row.title:SetText((t.complete and not Theme.book) and (Theme.HALL_GOLD .. t.title .. "|r") or t.title)
                row.text:SetText(t.text)
                row.bar:SetProgress(t.value, t.goal)
                row.tier:SetText(Theme.DIM .. (t.complete and "Every tier earned" or ("Tier %d of %d"):format(t.tier + 1, t.tiers)) .. "|r")
                row:Show()
            else
                row:Hide()
            end
        end
        self.prev:SetEnabled(offset > 0)
        self.next:SetEnabled(offset + visible < #tracks)
        self.pageText:SetText(Theme.DIM .. ("%d-%d of %d challenges"):format(offset + 1, math.min(#tracks, offset + visible), #tracks) .. "|r")
    end
    return p
end

-- ------------------------------------------------------------------------------------------------
-- Settings
-- ------------------------------------------------------------------------------------------------

local NOTIFY = {
    off = "Off: never announce a battle.",
    quiet = "Quiet: one line in chat.",
    toast = "Toast: a small note at the top of the screen.",
    prompt = "Prompt: open the battle card straight away.",
}
local NOTIFY_ORDER = { "toast", "quiet", "prompt", "off" }

local function buildSettings(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()
    p:Hide()
    p.heading = Theme.LightText(p, 19, "LEFT", true)
    p.heading:SetText("Settings")
    p.intro = Theme.LightText(p, 12)
    dim(p.intro, "How you hear of battles, what is shared with the guild, and "
        .. "a test battle to see it all without a fight.")

    p.rowList = {}
    local function row(title, buttonLabel, onClick)
        local box = Theme.Inset(p)
        p.rowList[#p.rowList + 1] = box
        box.title = Theme.LightText(box, 15, "LEFT", true)
        box.title:SetPoint("TOPLEFT", 14, -8)
        box.title:SetText(title)
        box.text = Theme.LightText(box, 12)
        box.text:SetPoint("TOPLEFT", box.title, "BOTTOMLEFT", 0, -4)
        box.text:SetPoint("RIGHT", -190, 0)
        box.button = Theme.HallButton(box, buttonLabel, 160, 26, nil, nil, onClick)
        box.button:SetPoint("RIGHT", -14, 0)
        return box
    end

    p.notify = row("Announcing battles", "Change", function()
        local set = KKC.settings()
        local i = 1
        for k, v in ipairs(NOTIFY_ORDER) do if v == set.notify then i = k end end
        set.notify = NOTIFY_ORDER[i % #NOTIFY_ORDER + 1]
        p:Refresh()
    end)
    p.all = row("Who is told", "Change", function()
        KKC.settings().promptAll = not KKC.settings().promptAll
        p:Refresh()
    end)
    p.sync = row("Guild sync", "Change", function()
        KKC.settings().sync = not KKC.settings().sync
        p:Refresh()
    end)
    p.test = row("A test battle", "Show test battle", function() SlashCmdList.KORKRONCOMPANION("test") end)
    dim(p.test.text, "A made-up battle at Tarren Mill, to see the note and the battle card without a fight.")
    p.debug = row("Diagnostics", "Print to chat", function() SlashCmdList.KORKRONCOMPANION("debug") end)
    dim(p.debug.text, "What this game client allows the addon (meter, names, sync). Send it along if something looks wrong.")

    -- Book: heading and a short introduction on the left page, the settings on the right (taller rows: the page is
    -- narrower, so their explanations take more lines). Docked: six rows of 58 still fit the Legacy window.
    function p:Layout(book, side)
        layoutHeading(self, book, side, self.intro, -2)
        self.intro:SetShown(book)
        local top, height, step = book and 4 or 44, book and 72 or 58, book and 78 or 64
        for i, box in ipairs(self.rowList) do
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -top - (i - 1) * step)
            box:SetPoint("RIGHT", self, "RIGHT", 0, 0)
            box:SetHeight(height)
        end
    end

    function p:Refresh()
        local set = KKC.settings()
        self.notify.text:SetText(Theme.DIM .. NOTIFY[set.notify] .. "|r")
        self.notify.button:SetLabel(set.notify:sub(1, 1):upper() .. set.notify:sub(2))
        self.all.text:SetText(Theme.DIM .. (set.promptAll and "Everyone who fought is told about a battle."
            or "Only the guildie first into battle is told (they write the report).") .. "|r")
        self.all.button:SetLabel(set.promptAll and "Everyone" or "First into battle")
        self.sync.text:SetText(Theme.DIM .. (set.sync
            and "On: notable battles are shared with guildies who run the addon, a few hidden guild messages each."
            or "Off: nothing is sent or read. Battles stay in your own chronicle.") .. "|r")
        self.sync.button:SetLabel(set.sync and "On" or "Off")
        self.sync.button:SetSelected(set.sync)
    end
    return p
end

-- ------------------------------------------------------------------------------------------------
-- The hall
-- ------------------------------------------------------------------------------------------------

local BUILDERS = {
    chronicle = function(parent) return buildChronicle(parent, false) end,
    battles = buildBattles,
    field = function(parent) return buildChronicle(parent, true) end,
    ledger = buildLedger,
    settings = buildSettings,
}

local function placeAlone(f)
    f:SetParent(UIParent)
    f:ClearAllPoints()
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER", 0, 10)
    f:SetFrameStrata("HIGH")
end

local function build()
    local f = CreateFrame("Frame", "KorKronCompanionHall", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not self.docked then self:StartMoving() end end)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    placeAlone(f)
    tinsert(UISpecialFrames, "KorKronCompanionHall") -- Esc closes it
    f:Hide()

    f.chrome = Theme.DarkFrame(f, "Hall of the Kor'kron")
    -- On its own the hall is a book: the contents (the sections) on the left page, the chosen one on the right.
    f.book = Theme.BookFrame(f, SPINE)
    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", -12, -12)
    f.close:SetFrameLevel(f:GetFrameLevel() + 10)
    f.close:SetScript("OnClick", function() f:Hide() end) -- the stock handler didn't close our window

    -- Who's speaking: the faction crest, the guild and the character.
    f.crest = f:CreateTexture(nil, "ARTWORK")
    f.crest:SetSize(46, 46)
    f.crest:SetPoint("TOPLEFT", 26, -24)
    if not Theme.Atlas(f.crest, Theme.F().emblem) then f.crest:SetTexture(Theme.F().icon) end
    f.who = Theme.LightText(f, 19, "LEFT", true)
    f.sub = Theme.LightText(f, 12)

    f.nav = {}
    for i, s in ipairs(SECTIONS) do
        local b = Theme.HallButton(f, s.label, NAV_W, 34, s.icon, s.tip, function() Hub.Select(s.key) end)
        b.key = s.key
        Theme.LinkStyle(b)
        f.nav[i] = b
    end
    -- Ribbon bookmarks hanging out of the bottom of the book, one per section (the book only).
    local RIBBONS = { { 0.55, 0.10, 0.07 }, { 0.20, 0.38, 0.16 }, { 0.18, 0.28, 0.50 }, { 0.40, 0.20, 0.48 }, { 0.38, 0.37, 0.35 } }
    f.ribbons = {}
    for i, s in ipairs(SECTIONS) do
        local r = CreateFrame("Button", nil, f)
        r:SetSize(18, 52)
        r:SetFrameLevel(f:GetFrameLevel() + 3)
        local c = RIBBONS[i]
        local body = r:CreateTexture(nil, "ARTWORK")
        body:SetAllPoints()
        body:SetColorTexture(c[1], c[2], c[3], 1)
        local edge = r:CreateTexture(nil, "ARTWORK", nil, 1)
        edge:SetPoint("TOPLEFT")
        edge:SetPoint("BOTTOMLEFT")
        edge:SetWidth(3)
        edge:SetColorTexture(1, 1, 1, 0.15)
        -- The swallowtail end: a diamond in the cover's color cut into the bottom.
        local notch = r:CreateTexture(nil, "ARTWORK", nil, 2)
        notch:SetSize(12, 12)
        notch:SetPoint("CENTER", r, "BOTTOM", 0, 0)
        notch:SetColorTexture(0.11, 0.06, 0.03, 1)
        if notch.SetRotation then notch:SetRotation(math.pi / 4) end
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.15)
        r.key = s.key
        r:SetScript("OnClick", function() Hub.Select(s.key) end)
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(s.label, 1, 0.82, 0)
            GameTooltip:AddLine(s.tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.ribbons[i] = r
    end
    -- The book's left page: dividers around the contents, and the area below them for the open section's controls.
    f.rules = { Theme.Rule(f, PAGE_W, true), Theme.Rule(f, PAGE_W, true) }
    f.side = CreateFrame("Frame", nil, f)
    local motto = Theme.LightText(f, 13, "CENTER", true)
    f.motto = motto
    dim(motto, UnitFactionGroup("player") == "Alliance" and "For the Alliance!" or "Lok'tar ogar!")

    f.content = CreateFrame("Frame", nil, f)
    f.title = f:CreateFontString(nil, "OVERLAY") -- the guild's name on the book's left page
    f.title:SetJustifyH("CENTER")
    Theme.BookTitle(f.title, 24)
    f.pages = {}
    for key, builder in pairs(BUILDERS) do f.pages[key] = builder(f.content) end

    f:SetScript("OnHide", function() if tab then tab.selected:Hide() end end)
    return f
end

-- A contents entry's icon and label size (bigger in the book).
local function navSize(b, icon, font)
    if b.icon then
        b.icon:SetSize(icon, icon)
        b.label:SetPoint("LEFT", 12 + icon, 0)
    end
    Theme.Font(b.label, font)
    b.label.kkSize = font
end

-- The book on its own, the dark hall when docked in the Legacy window (a book inside that window looked odd).
local function setLook(book)
    local f = hall
    for _, r in ipairs({ f.crest, f.who, f.sub, f.content, f.motto, f.side, f.title }) do r:ClearAllPoints() end
    if book then
        -- Left page, top to bottom: the guild's name, who you are, the contents (two columns), then the open
        -- section's own controls. Right page: the section itself. (The hall's banner hung over both pages' tops.)
        local mid = 26 + (SPINE - 26) / 2
        f.crest:Hide()
        f.who:Hide()
        f.title:Show()
        f.title:SetPoint("TOP", f, "TOPLEFT", mid, -40)
        f.title:SetWidth(PAGE_W)
        f.sub:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
        f.sub:SetWidth(PAGE_W)
        f.sub:SetJustifyH("CENTER")
        f.rules[1]:SetPoint("TOP", f, "TOPLEFT", mid, -96)
        -- The contents in one column, like a book's table of contents.
        -- Big entries, close together, filling the space between the two rules.
        for i, b in ipairs(f.nav) do
            b:ClearAllPoints()
            b:SetSize(PAGE_W - 40, 42)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", PAGE_L + 16, -106 - (i - 1) * 45) -- room for the diamond in front
            navSize(b, 34, 16)
        end
        f.rules[2]:SetPoint("TOP", f, "TOPLEFT", mid, -336)
        f.side:SetPoint("TOPLEFT", f, "TOPLEFT", PAGE_L, -350)
        f.side:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", PAGE_L + PAGE_W, 66)
        f.motto:SetPoint("BOTTOM", f, "BOTTOMLEFT", mid, 40)
        f.motto:SetWidth(PAGE_W)
        f.content:SetPoint("TOPLEFT", f, "TOPLEFT", PAGE_R, -48)
        f.content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -44, 44)
        if f.chrome.banner then f.chrome.banner:Hide() end
    else
        f.title:Hide()
        f.who:Show()
        f.crest:SetShown(not f.docked)
        f.crest:SetPoint("TOPLEFT", 26, -24)
        f.who:SetPoint("TOPLEFT", f.crest, "TOPRIGHT", 10, -4)
        f.sub:SetPoint("TOPLEFT", f.who, "BOTTOMLEFT", 0, -3)
        f.sub:SetWidth(0)
        f.sub:SetJustifyH("LEFT")
        for i, b in ipairs(f.nav) do
            b:ClearAllPoints()
            b:SetSize(NAV_W, 34)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -84 - (i - 1) * 40)
            navSize(b, 26, 13)
        end
        f.side:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        f.side:SetSize(1, 1)
        f.content:SetPoint("TOPLEFT", f, "TOPLEFT", 22 + NAV_W + 16, -84)
        f.content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 22)
        f.motto:SetPoint("BOTTOM", f, "BOTTOMLEFT", 22 + NAV_W / 2, 26)
        f.motto:SetWidth(NAV_W)
        if f.chrome.banner then f.chrome.banner:SetShown(not f.docked) end
    end
    for _, r in ipairs(f.rules) do r:SetShown(book) end
    for i, r in ipairs(f.ribbons) do
        r:SetShown(book)
        at(r, "TOP", f, "BOTTOMLEFT", SPINE - 30 - (#f.ribbons - i) * 26, 32)
    end
    for _, t in ipairs(f.chrome.dark) do t:SetShown(not book) end
    if f.chrome.border then f.chrome.border:SetShown(not book and not f.docked) end -- the book has its own leather edge
    for _, t in ipairs(f.book) do t:SetShown(book) end
    Theme.SetBook(book)
    redrawDim()
    for _, page in pairs(f.pages) do page:Layout(book, f.side) end
end

local function refreshHeader()
    local guild = IsInGuild() and GetGuildInfo("player")
    hall.who:SetText(KKC.readable(guild) and guild or "Hall of the Kor'kron")
    hall.title:SetText(KKC.readable(guild) and guild or "Hall of the Kor'kron")
    local l = KKC.Ledger.Mine()
    hall.sub:SetText(Theme.DIM .. ("%s  ~  %d slain  ~  %d battles of note"):format(KKC.me() or "?", l.total, l.engagements) .. "|r")
end

function Hub.Refresh()
    if not (hall and hall:IsShown()) then return end
    refreshHeader()
    for _, b in ipairs(hall.nav) do b:SetSelected(b.key == current.section) end
    for _, r in ipairs(hall.ribbons) do r:SetHeight(r.key == current.section and 66 or 52) end -- the open one hangs lower
    for key, page in pairs(hall.pages) do page:SetShown(key == current.section) end
    hall.pages[current.section]:Refresh()
end

function Hub.Select(section, period)
    if hall and hall.pages[section] then current.section = section end
    if period then current.period = period end
    Hub.Refresh()
end

-- On its own, in the middle of the screen.
function Hub.Show(section, period)
    hall = hall or build()
    if not hall.docked then placeAlone(hall); setLook(true) end
    hall:Show()
    Hub.Select(section or current.section, period)
end

function Hub.Toggle()
    if hall and hall:IsShown() then hall:Hide() else Hub.Show() end
end

KKC.Listen("EngagementClosed", Hub.Refresh)
KKC.Listen("FeedUpdated", Hub.Refresh)

-- ------------------------------------------------------------------------------------------------
-- Docked in the Legacy window, behind our own side tab
-- ------------------------------------------------------------------------------------------------

local function setChrome(shown)
    local c = hall.chrome
    if c.border then c.border:SetShown(shown) end
    if c.banner then c.banner:SetShown(shown) end
    hall.close:SetShown(shown)
    hall.crest:SetShown(shown) -- the Legacy window has its own portrait there
end

function Hub.Dock()
    local L = LegacySystemFrame
    if not L then return Hub.Show() end
    hall = hall or build()
    hall.docked = true
    hall:SetParent(L)
    hall:ClearAllPoints()
    hall:SetPoint("TOPLEFT", L, "TOPLEFT", 2, -22)
    hall:SetPoint("BOTTOMRIGHT", L, "BOTTOMRIGHT", -2, 2)
    -- Above everything on Legacy's pages (the pages sit at level 100, their cards and bars a little higher), but
    -- below the window's portrait (level 400). The deepest level actually used is measured, since whichever page was
    -- open last stays shown underneath. Only reading levels, never changing Blizzard's frames.
    local top = math.max(L:GetFrameLevel(), 100)
    local function deepest(frame, depth)
        if depth > 8 then return end
        top = math.max(top, frame:GetFrameLevel())
        for _, child in ipairs({ frame:GetChildren() }) do deepest(child, depth + 1) end
    end
    for _, page in ipairs(type(L.Pages) == "table" and L.Pages or {}) do pcall(deepest, page, 0) end
    local container = type(L.PortraitContainer) == "table" and L.PortraitContainer
    local portrait = container and container:GetFrameLevel() or 400
    if top + 40 < portrait then
        hall:SetFrameStrata(L:GetFrameStrata())
        hall:SetFrameLevel(top + 10)
    else
        hall:SetFrameStrata("HIGH") -- no room under the portrait: a layer above the whole window instead
    end
    setChrome(false)
    setLook(false)
    hall:Show()
    if tab then tab.selected:Show() end
    Hub.Refresh()
end

function Hub.Undock()
    if not (hall and hall.docked) then return end
    hall.docked = false
    hall:Hide()
    setChrome(true)
    placeAlone(hall)
end

local function makeTab(L)
    local last = L.Tabs and L.Tabs[#L.Tabs]
    if not last then return end
    local t = CreateFrame("Button", nil, L)
    local bg = t:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("CENTER")
    if Theme.Atlas(bg, "common-sidetab", true) then
        t:SetSize(bg:GetWidth(), bg:GetHeight())
    else
        t:SetSize(43, 55)
        bg:SetAllPoints()
        bg:SetColorTexture(0.1, 0.05, 0.03, 0.9)
    end
    local icon = t:CreateTexture(nil, "ARTWORK")
    icon:SetSize(30, 30)
    icon:SetPoint("CENTER", -2, 0)
    icon:SetTexture(Theme.F().icon)
    if t.CreateMaskTexture then
        local mask = t:CreateMaskTexture()
        if mask and Theme.Atlas(mask, "common-sidetab-mask", true) then
            mask:SetPoint("CENTER")
            icon:AddMaskTexture(mask)
        end
    end
    t.selected = t:CreateTexture(nil, "OVERLAY")
    t.selected:SetPoint("CENTER")
    if not Theme.Atlas(t.selected, "common-sidetab-selected", true) then
        t.selected:SetAllPoints()
        t.selected:SetColorTexture(1, 0.8, 0.3, 0.25)
    end
    t.selected:Hide()
    local hover = t:CreateTexture(nil, "HIGHLIGHT")
    hover:SetPoint("CENTER")
    if not Theme.Atlas(hover, "common-sidetab-hover", true) then
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.15)
    end
    t:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -2)
    t:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        Hub.Dock()
    end)
    t:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Hall of the Kor'kron", 1, 0.82, 0)
        GameTooltip:AddLine("Your battles, the war chronicle and the War Ledger.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Blizzard's own tabs and closing the window take the hall away again. HookScript only listens.
    for _, other in ipairs(L.Tabs) do
        other:HookScript("OnMouseUp", function(_, button) if button == "LeftButton" then Hub.Undock() end end)
    end
    L:HookScript("OnHide", Hub.Undock)
    return t
end

local function attach()
    if tab or not LegacySystemFrame then return end
    tab = makeTab(LegacySystemFrame)
end

-- The Legacy window loads on demand.
KKC.On("ADDON_LOADED", function(name) if name == "Blizzard_LegacySystem" then attach() end end)
KKC.Listen("Init", function()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and KKC.try(C_AddOns.IsAddOnLoaded, "Blizzard_LegacySystem")
    if loaded then attach() end
end)
