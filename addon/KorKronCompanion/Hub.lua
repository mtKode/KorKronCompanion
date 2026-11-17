--[[
  The Hall of the Kor'kron: the addon's main window (Overlord style: dark parchment, faction accents).

    Chronicle       your battles over a day, week, month or all time: tiles, details, the battles themselves
    Battles         every battle you fought, newest first; click one for its battle card
    From the field  guildies' battles you weren't in (the guild feed; needs guild sync)
    War Ledger      your deeds as tiered challenges, Legacy style
    Settings        notifications, guild sync, comings and goings in the report, a test battle, diagnostics

  On its own (/kkc and the minimap button). The War Ledger also shows inside Forever's Legacy window, as one of its
  challenge categories (LegacyLedger.lua). The hall's "dark" layout (setLook(false), Layout(book = false)) was for
  the hall docked in that window behind a side tab; the tab is gone, the layout code stays for now.
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
local hall
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
    -- A battle more raids of the guild fought in (guild sync): "3 raids".
    local host = KKC.Host(e)
    local raids = host and (Theme.DIM .. "~|r " .. Theme.HALL_GOLD .. #host.raids .. " raids|r") or nil
    -- A campaign's row is marked by its card and its +/-, its name and end are in the tooltip: the row keeps the room for
    -- the numbers (with "Campaign" and "~ until 21:10" too they were cut off).
    if e.campaign then return colored(e) .. (raids and ("  " .. raids) or "") end
    local tags = {}
    if host then tags[#tags + 1] = Theme.HALL_GOLD .. #host.raids .. " raids|r" end
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
    -- A campaign's +/- at its left edge: folds its fights away or shows them again (b.onToggle, set by the list).
    b.toggle = CreateFrame("Button", nil, b)
    b.toggle:SetSize(14, 14)
    b.toggle:SetPoint("LEFT", 3, 0)
    b.toggle:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
    b.toggle:SetScript("OnClick", function() if b.onToggle and b.engagement then b.onToggle(b.engagement) end end)
    b.toggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(b.collapsed and "Show this outing's fights" or "Fold this outing's fights away", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    b.toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b.toggle:Hide()
    b:SetScript("OnClick", function(self)
        if self.engagement then KKC.UI.ShowCard(self.engagement)
        elseif self.dayKey and self.onDayToggle then self.onDayToggle(self.dayKey) end
    end)
    -- What a click opens, under the mouse.
    b:SetScript("OnEnter", function(self)
        local e = self.engagement
        if not e and self.dayKey then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.collapsed and "Show this day's battles" or "Fold this day's battles away", 1, 0.82, 0)
            GameTooltip:Show()
            return
        end
        if not e then return end
        self.arrow:SetTextColor(1, 0.82, 0)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(e.campaign and (KKC.Campaign.Name(e) .. ": " .. KKC.Report.Place(e)) or KKC.Report.Place(e), 1, 0.82, 0)
        if e.campaign then
            GameTooltip:AddLine(("%s to %s, %d clashes"):format(date("%H:%M", e.start), date("%H:%M", e.stop), e.fights or 0), 0.8, 0.8, 0.8)
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
    -- heading ("WEDNESDAY 11 NOVEMBER"). collapsed: a campaign or day whose battles are folded away (a campaign's +/-
    -- shows +, a day's diamond dims). dayKey: the day a heading folds; folded: how many battles it holds.
    function b:Set(e, inCampaign, day, collapsed, dayKey, folded)
        e, day = e or nil, day or nil -- false on an empty row
        self.engagement, self.inCampaign, self.collapsed, self.dayKey = e, inCampaign, collapsed, day and dayKey or nil
        local folds = e and e.campaign and true or false
        self.toggle:SetShown(folds)
        if folds then
            self.toggle:SetNormalTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
            self.toggle:SetPushedTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Down" or "Interface\\Buttons\\UI-MinusButton-Down")
        end
        if not (e or day) then return self:Hide() end
        self:EnableMouse(true) -- a battle opens its card, a day's heading folds the day
        self.arrow:SetShown(e ~= nil)
        local card = e and e.campaign and Theme.book
        for _, t in ipairs({ self.card, self.shadow }) do t:SetShown(card or false) end
        self.diamond:SetShown(day ~= nil)
        self.diamond:SetAlpha(collapsed and 0.4 or 1)
        self.day:SetText(day and (day .. (collapsed and folded and (Theme.DIM .. ("   (%d %s folded away)"):format(folded,
            folded == 1 and "battle" or "battles") .. "|r") or "")) or "")
        if day then
            self.when:SetText("")
            self.what:SetText("")
        else
            self.when:SetText(Theme.DIM .. ((inCampaign or e.campaign) and "      " or "  ") .. date("%H:%M", e.start) .. "|r")
            self.what:SetText((inCampaign and "    " or "") .. headline(e))
        end
        self:Show()
    end
    return b
end

-- ------------------------------------------------------------------------------------------------
-- Chronicle (and From the field, which is the same page over the guild feed)
-- ------------------------------------------------------------------------------------------------

-- The Chronicle's details as sections (Summary.Sections): a heading in the game's yellow, then its entries in two
-- columns, the name on the left and the number on the right, a thin line between sections. A note (a plain sentence)
-- runs across the width. Scrolls when longer than its frame.
local ENTRY_H, HEAD_H = 17, 20
local function sectionList(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(400, 10)
    scroll:SetScrollChild(child)
    local pools = { head = {}, name = {}, value = {}, note = {}, line = {}, divider = {} }
    local used = {}
    local function take(kind, make)
        used[kind] = (used[kind] or 0) + 1
        local r = pools[kind][used[kind]]
        if not r then r = make(); pools[kind][used[kind]] = r end
        r:ClearAllPoints()
        r:Show()
        return r
    end
    local function text(size, justify, title)
        return function()
            local fs = Theme.LightText(child, size, justify, title)
            fs:SetWordWrap(false)
            return fs
        end
    end
    local function line()
        local t = child:CreateTexture(nil, "ARTWORK")
        t:SetHeight(1)
        t:SetColorTexture(0.62, 0.52, 0.36, 0.25)
        return t
    end
    local function height(fs, fallback)
        local h = KKC.try(fs.GetStringHeight, fs)
        return type(h) == "number" and h > 0 and h or fallback
    end

    function scroll:Set(sections)
        self.sections = sections
        local w = KKC.try(self.GetWidth, self)
        w = type(w) == "number" and w > 0 and w or 400
        child:SetWidth(w)
        used = {}
        -- Two halves split by a thin upright line in the middle of the page: names centered in the left half,
        -- their numbers centered in the right one.
        local mid = math.floor(w / 2)
        local y = 4
        for i, sec in ipairs(sections) do
            if i > 1 then
                local l = take("line", line)
                l:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y - 4)
                l:SetPoint("TOPRIGHT", child, "TOPLEFT", w, -y - 4)
                y = y + 10
            end
            if sec.note then
                local fs = take("note", function()
                    local n = Theme.LightText(child, 12)
                    n:SetJustifyV("TOP")
                    return n
                end)
                fs:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y)
                fs:SetWidth(w - 8)
                fs:SetText(Theme.DIM .. sec.note .. "|r")
                y = y + height(fs, 16) + 4
            else
                -- The heading in the plain font (the decorative one is for headers that carry no data), in yellow.
                local head = take("head", text(13, "CENTER"))
                head:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y)
                head:SetWidth(w - 8)
                head:SetText(Theme.HALL_GOLD .. sec.title .. "|r")
                y = y + HEAD_H
                local first = y
                for _, e in ipairs(sec.entries) do
                    local name = take("name", text(12, "CENTER"))
                    name:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y)
                    name:SetWidth(mid - 4 - 10)
                    name:SetText(e[1])
                    local value = take("value", text(12, "CENTER"))
                    value:SetPoint("TOPLEFT", child, "TOPLEFT", mid + 10, -y)
                    value:SetWidth(w - mid - 10 - 4)
                    value:SetText(e[2])
                    y = y + ENTRY_H
                end
                if #sec.entries > 0 then
                    local d = take("divider", function()
                        local t = child:CreateTexture(nil, "ARTWORK")
                        t:SetWidth(1)
                        t:SetColorTexture(0.62, 0.52, 0.36, 0.35)
                        return t
                    end)
                    d:SetPoint("TOP", child, "TOPLEFT", mid, -first + 1)
                    d:SetPoint("BOTTOM", child, "TOPLEFT", mid, -y + 3)
                end
            end
        end
        for kind, pool in pairs(pools) do
            for i = (used[kind] or 0) + 1, #pool do pool[i]:Hide() end
        end
        child:SetHeight(y + 6)
        KKC.try(self.SetVerticalScroll, self, 0)
    end
    scroll:SetScript("OnSizeChanged", function(self) if self.sections then self:Set(self.sections) end end)
    return scroll
end

-- The standing of the guilds, Overlord's rating as a podium: the first in the middle and a little higher, the second
-- and third beside it, each under its faction's emblem. Our guild further down gets a line below; without a rating to
-- read, one quiet line in the hall's voice (KKC.Overlord.QuietLine).
local STANDING_H = 142
local PODIUM = { { x = 0, y = -40, size = 46 }, { x = -1, y = -50, size = 38 }, { x = 1, y = -50, size = 38 } }
local function ordinal(n)
    local tens, ones = n % 100, n % 10
    local suffix = (tens >= 11 and tens <= 13) and "th" or (ones == 1 and "st" or ones == 2 and "nd" or ones == 3 and "rd" or "th")
    return n .. suffix
end
local function points(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end
local function standingBox(parent)
    local box = Theme.Inset(parent, true)
    box:SetHeight(STANDING_H)
    box.title = Theme.LightText(box, 15, "CENTER", true)
    box.title:SetPoint("TOP", 0, -9)
    box.title:SetText("Standing of the guilds")
    box.source = Theme.LightText(box, 10, "CENTER")
    box.source:SetPoint("TOP", box.title, "BOTTOM", 0, -2) -- where the standing comes from, under the title
    box.slots = {}
    for i, place in ipairs(PODIUM) do
        local slot = CreateFrame("Frame", nil, box)
        slot:SetSize(140, 84)
        slot.place = place
        slot.emblem = slot:CreateTexture(nil, "ARTWORK")
        slot.emblem:SetSize(place.size, place.size)
        slot.emblem:SetPoint("TOP", 0, 0)
        slot.rank = slot:CreateFontString(nil, "OVERLAY")
        Theme.Font(slot.rank, i == 1 and 17 or 15, false, "OUTLINE") -- data: the plain font
        slot.rank:SetTextColor(1, 0.82, 0.25)
        slot.rank:SetPoint("BOTTOMRIGHT", slot.emblem, "BOTTOMRIGHT", 8, -2)
        slot.name = Theme.LightText(slot, i == 1 and 14 or 13, "CENTER", false, true)
        slot.name:SetPoint("TOP", slot.emblem, "BOTTOM", 0, -3)
        slot.name:SetWidth(140)
        slot.name:SetWordWrap(false)
        slot.points = Theme.LightText(slot, 11, "CENTER")
        slot.points:SetPoint("TOP", slot.name, "BOTTOM", 0, -2)
        box.slots[i] = slot
    end
    box.note = Theme.LightText(box, 11, "CENTER")
    box.note:SetPoint("BOTTOMLEFT", 12, 8)
    box.note:SetPoint("BOTTOMRIGHT", -12, 8)
    box.quiet = Theme.LightText(box, 12, "CENTER")
    box.quiet:SetPoint("LEFT", 24, -8)
    box.quiet:SetPoint("RIGHT", -24, -8)

    function box:Refresh()
        local w = KKC.try(self.GetWidth, self)
        w = type(w) == "number" and w > 0 and w or PAGE_W
        local O = KKC.Overlord
        local top = O and O.TopGuilds(3)
        local status = not top and O and (O.RatingStatus() or "unreadable")
        self.source:SetText(top and (Theme.DIM .. "all of Forever, from Overlord|r") or "")
        self.quiet:SetText(status and (Theme.DIM .. O.QuietLine(status) .. "|r") or "")
        for i, slot in ipairs(self.slots) do
            local g = top and top[i]
            if g and g.rank == i then
                slot:ClearAllPoints()
                slot:SetPoint("TOP", self, "TOP", slot.place.x * w / 3, slot.place.y)
                if not Theme.Atlas(slot.emblem, g.faction == "Alliance" and "AllianceEmblem" or "HordeEmblem") then
                    slot.emblem:SetTexture(g.faction == "Alliance" and "Interface\\Icons\\INV_BannerPVP_02" or "Interface\\Icons\\INV_BannerPVP_01")
                end
                slot.rank:SetText(i)
                local color = g.faction == "Alliance" and "|cff6fa8ff" or g.faction == "Horde" and "|cffff6a52" or "|cffffffff"
                slot.name:SetText(color .. g.guild .. "|r")
                slot.points:SetText(Theme.DIM .. points(g.points) .. " points|r")
                slot:Show()
            else
                slot:Hide()
            end
        end
        local ours
        for _, g in ipairs(top or {}) do if g.mine and g.rank > 3 then ours = g end end
        self.note:SetText(ours and (Theme.DIM .. ("%s stand %s, with %s points."):format(ours.guild, ordinal(ours.rank), points(ours.points)) .. "|r") or "")
    end
    return box
end

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
    -- Above the details, on your own Chronicle: the standing of the guilds (Overlord).
    if not guild then p.standing = standingBox(p) end
    local details = Theme.Inset(p)
    p.details = details
    p.rows = sectionList(details)
    p.rows:SetPoint("TOPLEFT", 10, -8)
    p.rows:SetPoint("BOTTOMRIGHT", -30, 8)

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

    -- The two buttons share the page's width; Scribe chronicle alone fills it (From the field, or with the horn off).
    function p:SizeButtons()
        local horn = self.share and KKC.settings().horn
        if self.share then self.share:SetShown(horn and true or false) end
        if self.book then
            -- Side by side over the page's width; alone, Scribe chronicle just as wide as its icon and words, in the
            -- middle.
            for _, b in ipairs({ self.copy, self.share }) do b:SetSize(211, 32) end
            if not horn then
                local tw = KKC.try(self.copy.label.GetStringWidth, self.copy.label)
                self.copy:SetWidth(30 + (type(tw) == "number" and tw > 0 and tw or 110) + 16)
            end
            if self.side then
                self.copy:ClearAllPoints()
                if horn then
                    self.copy:SetPoint("BOTTOMLEFT", self.side, "BOTTOMLEFT", 0, 0)
                else
                    self.copy:SetPoint("BOTTOM", self.side, "BOTTOMLEFT", PAGE_W / 2, 0)
                end
            end
        end
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
        if self.standing then
            self.standing:SetShown(book)
            self.standing:ClearAllPoints()
            self.standing:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -4)
            self.standing:SetPoint("RIGHT", self, "RIGHT", 0, 0)
        end
        if book then
            self.details:SetPoint("TOPLEFT", self, "TOPLEFT", 0, self.standing and -(STANDING_H + 12) or -4)
            self.details:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 4)
            self.side = side
            self.book = true
            self:SizeButtons()
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
        local heading, span = KKC.Summary.Parts(data, label, guild, true)
        self.heading:SetText(heading)
        -- How long the fighting took goes with the dates (the tally has the rest of the "Battles" line).
        if (data.seconds or 0) > 0 then span = span .. "  ~  " .. KKC.duration(data.seconds) .. " of battle" end
        self.span:SetText(Theme.DIM .. span .. "|r")
        if self.standing then self.standing:Refresh() end
        -- The details as sections (Summary.Sections; the tally on the left page has the battles and the first blow).
        if guild and not KKC.settings().sync then
            self.rows:Set({ { note = "Guild sync is off, so no word comes from the field. Turn it on under Settings to "
                .. "hear of battles guildies with the addon fight without you." } })
        else
            self.rows:Set(KKC.Summary.Sections(data, guild))
        end
        self.tiles.battles.value:SetText(data.engagements)
        self.tiles.kills.value:SetText(Theme.GOOD .. data.kills .. "|r")
        self.tiles.fallen.value:SetText(Theme.BAD .. data.fallen .. "|r")
        self.tiles.blow.value:SetText(("%s%d|r / %s%d|r"):format(Theme.GOOD, data.struck, Theme.BAD, data.ambushed))
        if self.share then self.share:SetEnabled(data.engagements > 0) end
        self:SizeButtons()
        self.tally:Set({
            { "Battles", data.engagements .. Theme.DIM .. "  (" .. data.notable .. " of note)|r" },
            { "Foes slain", Theme.GOOD .. data.kills .. "|r" },
            { "Kor'kron fallen", Theme.BAD .. data.fallen .. "|r" .. ((not guild and (data.myDeaths or 0) > 0)
                and (Theme.DIM .. ("  (you %d)"):format(data.myDeaths) .. "|r") or "") },
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
    p.collapsed = {} -- campaign ids folded away (until /reload)
    p.collapsedDays = {} -- days ("2026-11-14") folded away

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
        r.onToggle = function(e)
            p.collapsed[e.id] = not p.collapsed[e.id] or nil
            p:Refresh()
        end
        r.onDayToggle = function(key)
            p.collapsedDays[key] = not p.collapsedDays[key] or nil
            p:Refresh()
        end
        p.rows[i] = r
    end

    scrollable(box, p)
    p.box = box
    -- Above the list in the book: the rows are what you click.
    p.hint = Theme.LightText(p, 12, "LEFT")
    dim(p.hint, "Click a battle for its battle card, a campaign for the whole outing.")
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
            self.hint:SetWidth(PAGE_W - 8)
            self.hint:SetWordWrap(false)
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
                list[#list + 1] = { day = date("%A %d %B", t):upper(), key = key }
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
                local view = KKC.Campaign.View(c)
                local folded = self.collapsed[view.id] and true or false
                list[#list + 1] = { e = view, collapsed = folded }
                if not folded then
                    for _, e in ipairs(fights) do list[#list + 1] = { e = e, inCampaign = true } end
                end
            elseif #fights > 0 then
                list[#list + 1] = { e = fights[1] }
            end
        end
        -- Folded days: their heading stays, with how many battles are under it; the rest is left out.
        local shown, heading = {}, nil
        for _, item in ipairs(list) do
            if item.day then
                heading = item
                item.collapsed = self.collapsedDays[item.key] and true or false
                item.folded = 0
                shown[#shown + 1] = item
            elseif heading and heading.collapsed then
                -- Count fights: a campaign's own rows, or its clashes when the campaign is folded too.
                if not (item.e and item.e.campaign) then heading.folded = heading.folded + 1
                elseif item.collapsed then heading.folded = heading.folded + (item.e.fights or 0) end
            else
                shown[#shown + 1] = item
            end
        end
        list = shown
        local visible = fit(self.box, 8, 8, 21, 18, BATTLE_ROWS)
        self.visible = visible
        local offset = clamp(self, #list, visible)
        for i, r in ipairs(self.rows) do
            local item = i <= visible and list[offset + i]
            r:Set(item and item.e, item and item.inCampaign, item and item.day, item and item.collapsed,
                item and item.key, item and item.folded)
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
-- War Ledger: the Legacy window's cards (LegacyLedger.lua): the fun numbers, then the tiered challenges
-- ------------------------------------------------------------------------------------------------

local CARD_GAP = 6

local function buildLedger(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()
    p:Hide()
    p:SetScript("OnSizeChanged", function(self) if self:IsShown() then self:Refresh() end end)

    p.heading = Theme.LightText(p, 19, "LEFT", true)
    p.heading:SetText("War Ledger")
    p.sub = Theme.LightText(p, 11)

    -- All the cards in one column that scrolls (wheel or the small bar on the right).
    p.scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    p.child = CreateFrame("Frame", nil, p.scroll)
    p.child:SetSize(400, 10)
    p.scroll:SetScrollChild(p.child)
    p.cards = {}

    local function card(i)
        local f = p.cards[i]
        if not f then
            f = CreateFrame("Frame", nil, p.child)
            KKC.LegacyLedger.Cards.Build(f)
            p.cards[i] = f
        end
        return f
    end

    -- The left page: where you stand in the Ledger (Ledger.Standing). Data in the plain font, the labels dim.
    local st = {}
    p.standing = st
    local function label(text)
        local fs = Theme.LightText(p, 12)
        fs:SetText(Theme.DIM .. text .. "|r")
        return fs
    end
    st.deedsLabel = label("Deeds done (tiers earned of all)")
    st.bar = Theme.Bar(p, PAGE_W, 14) -- shows "16 / 107" itself
    st.closestLabel = label("Closest to glory")
    st.rows = {}
    for i = 1, 3 do
        local r = {}
        r.icon = p:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(24, 24)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.name = Theme.LightText(p, 13, "LEFT")
        r.name:SetWidth(PAGE_W - 120)
        r.name:SetWordWrap(false)
        r.progress = Theme.LightText(p, 12, "RIGHT")
        st.rows[i] = r
    end
    local stParts = { st.deedsLabel, st.bar, st.closestLabel }
    for _, r in ipairs(st.rows) do stParts[#stParts + 1] = r.icon; stParts[#stParts + 1] = r.name; stParts[#stParts + 1] = r.progress end

    -- Book: heading, totals and your standing on the left page; the cards fill the right page.
    function p:Layout(book, side)
        layoutHeading(self, book, side, self.sub, -2)
        for _, part in ipairs(stParts) do part:SetShown(book) end
        if book then
            -- One under the other, starting under the totals line, so nothing can land on anything else.
            at(st.deedsLabel, "TOPLEFT", self.sub, "BOTTOMLEFT", 0, -16)
            at(st.bar, "TOPLEFT", st.deedsLabel, "BOTTOMLEFT", 0, -6)
            at(st.closestLabel, "TOPLEFT", st.bar, "BOTTOMLEFT", 0, -14)
            for i, r in ipairs(st.rows) do
                at(r.icon, "TOPLEFT", st.closestLabel, "BOTTOMLEFT", 0, -6 - (i - 1) * 27)
                at(r.name, "LEFT", r.icon, "RIGHT", 10, 0)
                at(r.progress, "RIGHT", r.icon, "LEFT", PAGE_W, 0) -- at the page's right edge
            end
        end
        local top, bottom = book and 4 or 44, book and 4 or 8
        self.scroll:ClearAllPoints()
        self.scroll:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -top)
        self.scroll:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -24, bottom) -- the bar sits in those 24
    end

    function p:Refresh()
        local C = KKC.LegacyLedger and KKC.LegacyLedger.Cards
        if not C then return end
        local l = KKC.Ledger.Mine()
        self.sub:SetText(Theme.DIM .. ("%s: %d slain, %d unique foes, fallen %d times. Only your own killing blows count.")
            :format(KKC.me() or "?", l.total, KKC.count(l.enemy), l.fallen) .. "|r")
        local tracks = KKC.Ledger.Tracks()
        local items = { { summary = KKC.Ledger.Highlights() } }
        for _, t in ipairs(tracks) do items[#items + 1] = { track = t } end
        self.items = items
        -- Your standing, on the left page.
        local standing = KKC.Ledger.Standing(tracks)
        st.bar:SetProgress(standing.earned, math.max(standing.total, 1))
        st.closestLabel:SetShown(#standing.closest > 0 and st.deedsLabel:IsShown())
        for i, r in ipairs(st.rows) do
            local t = standing.closest[i]
            local show = t ~= nil and st.deedsLabel:IsShown()
            r.icon:SetShown(show); r.name:SetShown(show); r.progress:SetShown(show)
            if t then
                r.icon:SetTexture(t.icon)
                r.name:SetText(t.title)
                r.progress:SetText(Theme.DIM .. ("%d / %d"):format(t.value, t.goal) .. "|r")
            end
        end
        local w = KKC.try(self.scroll.GetWidth, self.scroll)
        local width = type(w) == "number" and w > 0 and w or 406
        self.child:SetWidth(width)
        local y = 0
        for i, item in ipairs(items) do
            local h = item.summary and C.SummaryHeight(#item.summary, width) or C.HEIGHT
            local f = card(i)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, -y)
            f:SetSize(width, h)
            if item.summary then C.Summary(f, item.summary, width) else C.Challenge(f, item.track, width) end
            f:Show()
            y = y + h + CARD_GAP
        end
        for i = #items + 1, #self.cards do self.cards[i]:Hide() end
        self.child:SetHeight(math.max(y, 10))
    end
    return p
end

-- ------------------------------------------------------------------------------------------------
-- Settings
-- ------------------------------------------------------------------------------------------------

-- Your own notice when a battle ends (settings.notify): only you see it, nothing is sent. Every battle is logged in the
-- hall either way.
local NOTIFY = {
    off = "Off: you get no notice when a battle ends. Every battle is still logged and can be read here in the hall "
        .. "at any time.",
    quiet = "Quiet: one line in your chat when a battle ends, with /kkc card to open its report. Nothing pops up.",
    toast = "Toast: a small note with a sound at the top of your screen when a battle ends. It goes away by itself.",
    prompt = "Card: the battle card opens by itself when a battle ends, ready for a screenshot or to copy the report.",
}
local NOTIFY_LABEL = { off = "Off", quiet = "Quiet", toast = "Toast", prompt = "Card" }
local NOTIFY_ORDER = { "toast", "quiet", "prompt", "off" }

local function buildSettings(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()
    p:Hide()
    p.heading = Theme.LightText(p, 19, "LEFT", true)
    p.heading:SetText("Settings")
    p.intro = Theme.LightText(p, 12)
    dim(p.intro, "How you hear of battles, what is shared with the guild and read from Overlord, and how the hall "
        .. "looks. Each button switches its setting; the text under it says what the setting does as it is now.")

    -- The settings in one column that scrolls when they don't all fit. Each row: its title with the button beside it,
    -- then what the setting does now, across the whole row.
    p.scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    p.child = CreateFrame("Frame", nil, p.scroll)
    p.child:SetSize(400, 10)
    p.scroll:SetScrollChild(p.child)
    p.rowList = {}
    local function row(title, buttonLabel, onClick)
        local box = Theme.Inset(p.child)
        p.rowList[#p.rowList + 1] = box
        box.title = Theme.LightText(box, 15, "LEFT", true)
        box.title:SetPoint("TOPLEFT", 14, -12)
        box.title:SetText(title)
        box.button = Theme.HallButton(box, buttonLabel, 150, 26, nil, nil, onClick)
        box.button:SetPoint("TOPRIGHT", -12, -8)
        box.text = Theme.LightText(box, 12)
        box.text:SetPoint("TOPLEFT", 14, -42)
        box.text:SetPoint("RIGHT", -14, 0)
        box.text:SetJustifyV("TOP")
        box.text:SetSpacing(2)
        return box
    end
    local function flip(key) return function() KKC.settings()[key] = not KKC.settings()[key]; p:Refresh() end end

    p.notify = row("Your notice of a battle", "Change", function()
        local set = KKC.settings()
        local i = 1
        for k, v in ipairs(NOTIFY_ORDER) do if v == set.notify then i = k end end
        set.notify = NOTIFY_ORDER[i % #NOTIFY_ORDER + 1]
        p:Refresh()
    end)
    p.all = row("Which battles you hear of", "Change", flip("promptAll"))
    p.sync = row("Guild sync", "Change", flip("sync"))
    p.rollReport = row("Comings and goings in the report", "Change", flip("rollcallsInReport"))
    p.horn = row("Sound the horn", "Change", flip("horn"))
    p.overlord = row("Overlord", "Change", function()
        local set = KKC.settings()
        -- On unless switched off (nil: on).
        if set.overlord == false then set.overlord = nil else set.overlord = false end
        p:Refresh()
        Hub.Refresh()
    end)
    p.minimap = row("Minimap button", "Change", function()
        local m = KKC.settings().minimap
        m.hide = not m.hide
        if KKC.MinimapButton then KKC.MinimapButton.Refresh() end
        p:Refresh()
    end)
    p.size = row("Size of the hall", "Usual size", function()
        KKC.settings().hallScale = nil
        if hall then hall:SetScale(1) end
        p:Refresh()
    end)

    -- On the left page: a test battle and the diagnostics, with what they are for.
    p.extras = Theme.LightText(p, 12)
    dim(p.extras, "A made-up battle at Tarren Mill shows the note and the battle card without a fight. Diagnostics "
        .. "prints what this game client allows the addon (meter, names, sync, Overlord); send it along if something "
        .. "looks wrong.")
    p.test = Theme.HallButton(p, "Show test battle", 150, 26, "Interface\\Icons\\INV_Sword_04",
        "A made-up battle at Tarren Mill.", function() SlashCmdList.KORKRONCOMPANION("test") end)
    p.debug = Theme.HallButton(p, "Diagnostics", 150, 26, "Interface\\Icons\\INV_Misc_Spyglass_02",
        "Prints the diagnostics to chat.", function() SlashCmdList.KORKRONCOMPANION("debug") end)

    -- Book: heading, introduction and the two extras on the left page, the settings on the right.
    function p:Layout(book, side)
        layoutHeading(self, book, side, self.intro, -2)
        self.intro:SetShown(book)
        self.extras:SetShown(book)
        local top = book and 4 or 44
        self.scroll:ClearAllPoints()
        self.scroll:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -top)
        self.scroll:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -24, book and 4 or 34) -- the bar sits in those 24
        self:Stack()
        if book then
            at(self.test, "BOTTOMLEFT", side, "BOTTOMLEFT", 0, 0)
            at(self.debug, "LEFT", self.test, "RIGHT", 8, 0)
            for _, b in ipairs({ self.test, self.debug }) do b:SetSize(211, 32) end
            at(self.extras, "BOTTOMLEFT", self.test, "TOPLEFT", 0, 12)
            self.extras:SetWidth(PAGE_W)
        else
            for _, b in ipairs({ self.test, self.debug }) do b:SetSize(150, 26) end
            at(self.test, "BOTTOMLEFT", self, "BOTTOMLEFT", 0, 0)
            at(self.debug, "LEFT", self.test, "RIGHT", 8, 0)
        end
    end

    -- Each row as tall as its explanation, one under the other in the scrolling column.
    function p:Stack()
        local w = KKC.try(self.scroll.GetWidth, self.scroll)
        w = type(w) == "number" and w > 0 and w or 406
        self.child:SetWidth(w)
        local y = 0
        for _, box in ipairs(self.rowList) do
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, -y)
            box:SetWidth(w)
            local h = KKC.try(box.text.GetStringHeight, box.text)
            local height = (type(h) == "number" and h or 30) + 54
            box:SetHeight(height)
            y = y + height + 6
        end
        self.child:SetHeight(math.max(y, 10))
    end

    local function onOff(box, on, onText, offText, onLabel, offLabel)
        box.text:SetText(Theme.DIM .. (on and onText or offText) .. "|r")
        box.button:SetLabel(on and (onLabel or "On") or (offLabel or "Off"))
        box.button:SetSelected(on and true or false)
    end

    function p:Refresh()
        local set = KKC.settings()
        self.notify.text:SetText(Theme.DIM .. NOTIFY[set.notify] .. "|r")
        self.notify.button:SetLabel(NOTIFY_LABEL[set.notify] or set.notify)
        onOff(self.all, set.promptAll,
            "Every battle: you get the notice above for every battle you fought in, in your own raid or someone "
                .. "else's. Only your own notice: nothing is sent to anyone.",
            "Raids I lead: you get the notice above for the battles you would write up: raids you lead, and every "
                .. "fight outside a raid. In someone else's raid its leader writes it, so you're left in peace. Only "
                .. "your own notice: nothing is sent to anyone.", "Every battle", "Raids I lead")
        if set.notify == "off" then
            self.all.text:SetText(Theme.DIM .. "Your notice is off (above), so you hear of no battle at all. When it's "
                .. "on, this decides which battles it covers. Only your own notice: nothing is sent to anyone.|r")
        end
        onOff(self.sync, set.sync,
            "On: after a notable battle your addon shares it with guildies who have the addon too, in hidden addon "
                .. "messages that never show in guild chat. Their battles come back to you: in your own battle cards "
                .. "when you fought together, under From the field when you didn't. It goes slowly on purpose, a few "
                .. "messages a battle, so the guild channel is never flooded.",
            "Off: nothing is sent or read. Your battles stay your own and From the field stays empty. Turn it on when "
                .. "your guildies use the addon too.")
        onOff(self.rollReport, set.rollcallsInReport,
            "On: the report of a campaign adds who joined later and who left early, with the time of the roll call "
                .. "that noticed it (roll calls are taken every 10 minutes). One or two lines more to paste.",
            "Off: the report lists the Kor'kron by name only. The battle card still notes who joined later or left "
                .. "early, and its Roll calls button shows the night roll call by roll call.")
        onOff(self.horn, set.horn,
            "On: battle cards and the Chronicle get a Sound the horn button. One click posts a one-line account of the "
                .. "battle in guild chat (and to Discord, if guild chat is linked there).",
            "Off: no Sound the horn buttons, so nothing goes into guild chat from a stray click. Reports are still "
                .. "shared the usual way: Scribe report, then paste.")
        local overlordOn = set.overlord ~= false
        local installed = type(Overlord) == "table"
        onOff(self.overlord, overlordOn,
            (installed and "On" or "On, but you don't have Overlord installed") .. ": when the Overlord addon is "
                .. "there, two things are read from it. Foes on its Nemesis list are marked on your battles, and the "
                .. "Chronicle shows its standing of the guilds. Nothing is sent, and nothing in Overlord is changed.",
            "Off: Overlord is left alone even when it is installed: no Nemesis marks, no standing of the guilds.")
        onOff(self.minimap, not set.minimap.hide,
            "Shown: the banner by your minimap. Left click opens this hall, right click the report of your latest "
                .. "battle; drag it to move it around the minimap.",
            "Hidden: no button by your minimap. Open the hall with /kkc.", "Shown", "Hidden")
        local scale = set.hallScale or 1
        local pct = math.floor(scale * 100 + 0.5)
        self.size.text:SetText(Theme.DIM .. (pct == 100 and "The hall is at its usual size. " or
            ("The hall is at %d%% of its usual size. "):format(pct)) .. "Drag the grip in its bottom right corner to "
            .. "make it bigger or smaller" .. (pct == 100 and "." or "; this button puts it back.") .. "|r")
        self.size.button:SetEnabled(math.abs(scale - 1) > 0.005)
        self:Stack()
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
    f:SetScale(KKC.settings().hallScale or 1)
    f:SetPoint("CENTER", 0, 10)
    f:SetFrameStrata("HIGH")
end

-- Resizing: a grip in the bottom right corner scales the whole book, since its two pages are laid out for these
-- proportions. Dragged with the top left corner held in place; the size is kept (settings.hallScale). Right click:
-- back to the usual size.
local MIN_SCALE, MAX_SCALE = 0.6, 1.5
local function resizeGrip(f)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(18, 18)
    grip:SetPoint("BOTTOMRIGHT", -8, 8)
    grip:SetFrameLevel(f:GetFrameLevel() + 30)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:RegisterForClicks("RightButtonUp")
    grip:SetScript("OnClick", function()
        KKC.settings().hallScale = nil
        placeAlone(f)
    end)
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local s = f:GetScale()
        local left, top = f:GetLeft(), f:GetTop()
        if not (left and top) then return end
        left, top = left * s, top * s -- in UIParent's units
        grip:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local u = UIParent:GetEffectiveScale()
            x, y = x / u, y / u
            local scale = math.max((x - left) / WIDTH, (top - y) / HEIGHT)
            scale = math.max(MIN_SCALE, math.min(MAX_SCALE, scale))
            f:SetScale(scale)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
        end)
    end)
    grip:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        grip:SetScript("OnUpdate", nil)
        KKC.settings().hallScale = f:GetScale()
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Drag to resize the hall", 1, 0.82, 0)
        GameTooltip:AddLine("Right click: the usual size.", 1, 1, 1)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return grip
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
    f.grip = resizeGrip(f)
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
    f.name = Theme.LightText(f, 17, "CENTER") -- in the book: your name, over your totals (f.sub)
    f.sub = Theme.LightText(f, 12)

    f.nav = {}
    for i, s in ipairs(SECTIONS) do
        local b = Theme.HallButton(f, s.label, NAV_W, 34, s.icon, s.tip, function() Hub.Select(s.key) end)
        b.key = s.key
        Theme.LinkStyle(b)
        f.nav[i] = b
    end
    -- Ribbon bookmarks hanging out of the bottom of the book, one per section (the book only). War-worn: dark, dull
    -- colors (dried blood, moss, faded blue, dull purple, ash) on a cloth grain (our page texture, tinted), grimier
    -- towards the end, a stain, and a frayed end of uneven threads instead of a clean cut.
    local RIBBONS = { { 0.36, 0.08, 0.06 }, { 0.17, 0.24, 0.12 }, { 0.14, 0.18, 0.28 }, { 0.26, 0.15, 0.28 }, { 0.26, 0.25, 0.23 } }
    local TORN = 16 -- the last pixels of a ribbon: its torn (or cut) end
    local CUT = { [2] = 1, [5] = -1 } -- these two were slashed by a blade, slanting opposite ways; the rest are torn
    f.ribbons = {}
    for i, s in ipairs(SECTIONS) do
        -- Each ribbon worn in its own way: random, but the same on every login (seeded by the ribbon).
        local seed = i * 7919 + 104729
        local function rnd(a, b)
            seed = (seed * 9301 + 49297) % 233280
            return a + math.floor(seed / 233280 * (b - a + 1))
        end
        local r = CreateFrame("Button", nil, f)
        r:SetSize(18, 52)
        r:SetFrameLevel(f:GetFrameLevel() + 3)
        local c = RIBBONS[i]
        local body = r:CreateTexture(nil, "ARTWORK")
        body:SetPoint("TOPLEFT")
        body:SetPoint("BOTTOMRIGHT", 0, TORN)
        body:SetTexture(Theme.MEDIA .. "Page")
        body:SetTexCoord(0.1 * i, 0.1 * i + 0.08, 0.2, 0.6) -- a different stretch of grain on each
        body:SetVertexColor(c[1] * 1.6, c[2] * 1.6, c[3] * 1.6)
        -- Grime gathering towards the end.
        local grime = r:CreateTexture(nil, "ARTWORK", nil, 1)
        grime:SetAllPoints(body)
        grime:SetColorTexture(1, 1, 1, 1)
        if not (grime.SetGradient and CreateColor and pcall(grime.SetGradient, grime, "VERTICAL",
            CreateColor(0.05, 0.03, 0.02, 0.55), CreateColor(0.05, 0.03, 0.02, 0))) then
            grime:SetColorTexture(0, 0, 0, 0.2)
        end
        local edge = r:CreateTexture(nil, "ARTWORK", nil, 2)
        edge:SetPoint("TOPLEFT")
        edge:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT")
        edge:SetWidth(2)
        edge:SetColorTexture(1, 1, 1, 0.06)
        -- A mark of battle, a different kind on each, built from small pieces of the cloth's own grain (not flat
        -- squares): spattered blood, a scuff, a scorch, a patch rubbed pale.
        local function piece(w, h, x, y, rr, gg, bb, a, angle)
            local t = r:CreateTexture(nil, "ARTWORK", nil, 3)
            t:SetSize(w, h)
            t:SetPoint("CENTER", body, "TOP", x, y)
            t:SetTexture(Theme.MEDIA .. "Page")
            local u, v = rnd(0, 80) / 100, rnd(0, 80) / 100
            t:SetTexCoord(u, u + 0.06, v, v + 0.06)
            t:SetVertexColor(rr, gg, bb, a)
            if angle and t.SetRotation then t:SetRotation(angle) end
            return t
        end
        local function spatter(n, y0)
            for _ = 1, n do
                local d = rnd(1, 4)
                piece(d, d, rnd(-6, 6), y0 - rnd(0, 12), rnd(30, 45) / 100, 0.04, 0.03, rnd(50, 85) / 100, rnd(0, 6) / 4)
            end
        end
        local function scuff(y0)
            local angle = (rnd(0, 1) == 0 and 1 or -1) * rnd(50, 80) / 100
            piece(rnd(10, 16), 1, rnd(-2, 2), y0, 0.9, 0.85, 0.75, 0.22, angle) -- the scraped, lighter line
            piece(rnd(8, 13), 1, rnd(-2, 2), y0 - 2, 0.05, 0.03, 0.02, 0.45, angle) -- its shadow
        end
        local function scorch(y0)
            for k = 1, 4 do
                local sz = rnd(4, 9) - k
                piece(sz + 2, sz, rnd(-3, 3), y0 - rnd(-2, 2), 0.06, 0.04, 0.02, 0.18 + k * 0.08, rnd(0, 6) / 4)
            end
        end
        local function rubbed(y0)
            for _ = 1, 3 do
                piece(rnd(5, 9), rnd(4, 7), rnd(-3, 3), y0 - rnd(0, 6), 0.85, 0.8, 0.7, rnd(10, 18) / 100, rnd(0, 6) / 4)
            end
        end
        local y0 = -rnd(10, 26)
        local kind = ({ "spatter", "scuff", "scorch", "rubbed", "both" })[i] or "spatter"
        if kind == "spatter" then spatter(rnd(5, 8), y0)
        elseif kind == "scuff" then scuff(y0)
        elseif kind == "scorch" then scorch(y0)
        elseif kind == "rubbed" then rubbed(y0)
        else spatter(rnd(3, 4), y0); scuff(y0 - rnd(6, 12)) end
        -- A blade-cut end on some: one clean slash across the end, the cloth running out to a point on one side
        -- (a column a pixel wide each, a little uneven, as cloth doesn't cut perfectly straight).
        local cut = CUT[i]
        if cut then
            for col = 0, 17 do
                local share = cut > 0 and (col + 1) / 18 or (18 - col) / 18
                local len = math.max(0, math.floor(TORN * share) + rnd(-1, 0))
                if len > 0 then
                    local strip = r:CreateTexture(nil, "ARTWORK")
                    strip:SetSize(1, len)
                    strip:SetPoint("TOPLEFT", body, "BOTTOMLEFT", col, 0)
                    strip:SetTexture(Theme.MEDIA .. "Page")
                    strip:SetTexCoord(0.1 * i + col / 250, 0.1 * i + (col + 1) / 250, 0.6, 0.65)
                    strip:SetVertexColor(c[1] * 1.35, c[2] * 1.35, c[3] * 1.35)
                end
            end
        end
        -- Otherwise the torn end: the cloth gives out in strips of uneven width and length (one may be torn away
        -- entirely), and loose threads of every length hang from them at odd places and angles.
        local x, strips = 0, {}
        while not cut and x < 18 do
            local w = math.min(rnd(3, 8), 18 - x)
            local len = rnd(0, 6) == 0 and 0 or rnd(2, TORN - 2)
            if len > 0 then
                local strip = r:CreateTexture(nil, "ARTWORK")
                strip:SetSize(w, len)
                strip:SetPoint("TOPLEFT", body, "BOTTOMLEFT", x, 0)
                strip:SetTexture(Theme.MEDIA .. "Page")
                strip:SetTexCoord(0.1 * i + x / 250, 0.1 * i + (x + w) / 250, 0.6, 0.65)
                local shade = rnd(70, 95) / 100 * 1.6 -- darker at the end, each strip its own
                strip:SetVertexColor(c[1] * shade, c[2] * shade, c[3] * shade)
            end
            strips[#strips + 1] = { x = x, w = w, len = len }
            x = x + w
        end
        for _ = 1, cut and 0 or rnd(4, 9) do
            local st = strips[rnd(1, #strips)]
            local thread = r:CreateTexture(nil, "ARTWORK")
            thread:SetSize(rnd(1, 2), rnd(2, 11))
            thread:SetPoint("TOPLEFT", body, "BOTTOMLEFT", st.x + rnd(0, math.max(st.w - 1, 0)), -math.max(st.len - 1, 0))
            thread:SetTexture(Theme.MEDIA .. "Page")
            local shade = rnd(55, 100) / 100 * 1.4
            thread:SetVertexColor(c[1] * shade, c[2] * shade, c[3] * shade, rnd(55, 95) / 100)
            if thread.SetRotation then thread:SetRotation((rnd(0, 60) - 30) / 100) end
        end
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(body)
        hl:SetColorTexture(1, 1, 1, 0.1)
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
    for _, r in ipairs({ f.crest, f.who, f.name, f.sub, f.content, f.motto, f.side, f.title }) do r:ClearAllPoints() end
    if book then
        -- Left page, top to bottom: who you are, the battle cry, the contents, then the open section's own controls.
        -- Right page: the section itself. The window's name is on the banner over the spine; the guild's name as the
        -- left page's heading said much the same twice.
        local mid = 26 + (SPINE - 26) / 2
        f.crest:Hide()
        f.who:Hide()
        f.title:Hide()
        -- Your name, larger, then your totals and the battle cry, evenly spaced down to the rule. (The cry at the
        -- page's bottom ran into the section's text, at its top into the book's edge.)
        f.name:Show()
        f.name:SetPoint("TOP", f, "TOPLEFT", mid, -38)
        f.name:SetWidth(PAGE_W)
        f.sub:SetPoint("TOP", f.name, "BOTTOM", 0, -5)
        f.sub:SetWidth(PAGE_W)
        f.sub:SetJustifyH("CENTER")
        f.motto:SetPoint("TOP", f.sub, "BOTTOM", 0, -6)
        f.motto:SetWidth(PAGE_W)
        f.rules[1]:SetPoint("TOP", f, "TOPLEFT", mid, -98)
        -- The contents in one column, like a book's table of contents.
        -- Big entries, close together, filling the space between the two rules.
        for i, b in ipairs(f.nav) do
            b:ClearAllPoints()
            b:SetSize(PAGE_W - 40, 42)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", PAGE_L + 16, -108 - (i - 1) * 45) -- room for the diamond in front
            navSize(b, 34, 16)
        end
        f.rules[2]:SetPoint("TOP", f, "TOPLEFT", mid, -338)
        f.side:SetPoint("TOPLEFT", f, "TOPLEFT", PAGE_L, -352)
        f.side:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", PAGE_L + PAGE_W, 44)
        f.content:SetPoint("TOPLEFT", f, "TOPLEFT", PAGE_R, -34)
        f.content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -44, 30)
        -- "Hall of the Kor'kron" on the faction's banner, smaller, on the book's top edge over the spine: what the
        -- window is called (the guide says "the hall"). At full size it hung over both pages' text.
        local b = f.chrome.banner
        if b then
            local scale = 0.75
            b:SetScale(scale)
            b:ClearAllPoints()
            b:SetPoint("TOP", f, "TOP", 0, 46 / scale)
            b:SetFrameLevel(f:GetFrameLevel() + 40)
            b:Show()
            -- Readable over the banner's art: a heavier outline, a shadow, a lighter gold, and a soft dark band
            -- behind the words.
            local t = f.chrome.title
            if t then
                Theme.Font(t, 25, true, "OUTLINE")
                t:SetShadowColor(0, 0, 0, 1)
                t:SetShadowOffset(2, -2)
                t:SetTextColor(1, 0.82, 0) -- the game's yellow
                if not b.backing then
                    -- Two halves, each dark in the middle and fading out towards its end.
                    local function half(fromRight)
                        local h = b:CreateTexture(nil, "ARTWORK", nil, 2)
                        h:SetPoint("TOP", t, "TOP", 0, 5)
                        h:SetPoint("BOTTOM", t, "BOTTOM", 0, -5)
                        if fromRight then
                            h:SetPoint("LEFT", t, "CENTER", 0, 0)
                            h:SetPoint("RIGHT", t, "RIGHT", 24, 0)
                        else
                            h:SetPoint("LEFT", t, "LEFT", -24, 0)
                            h:SetPoint("RIGHT", t, "CENTER", 0, 0)
                        end
                        h:SetColorTexture(1, 1, 1, 1)
                        local ok = false
                        if h.SetGradient and CreateColor then
                            local dark, clear = CreateColor(0, 0, 0, 0.6), CreateColor(0, 0, 0, 0)
                            ok = pcall(h.SetGradient, h, "HORIZONTAL", fromRight and dark or clear, fromRight and clear or dark)
                        end
                        if not ok then h:SetColorTexture(0, 0, 0, 0.5) end -- no gradients here: a plain band
                        return h
                    end
                    b.backing = { half(false), half(true) }
                    function b.backing:Show() for _, h in ipairs(self) do h:Show() end end
                    function b.backing:Hide() for _, h in ipairs(self) do h:Hide() end end
                end
                b.backing:Show()
            end
        end
    else
        f.title:Hide()
        f.who:Show()
        f.name:Hide()
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
        local b = f.chrome.banner
        if b then
            if b.backing then b.backing:Hide() end
            b:SetScale(1)
            b:ClearAllPoints()
            b:SetPoint("TOP", f, "TOP", 0, 46)
            b:SetShown(not f.docked)
        end
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
    -- You, all time on this character: your name in your class's color, then your own kills, battles of note and falls
    -- (as the War Ledger counts them).
    local l = KKC.Ledger.Mine()
    local _, class = UnitClass("player")
    local sep = Theme.DIM .. "  ~  |r"
    hall.name:SetText(Theme.ClassLight(class) .. (KKC.me() or "?") .. "|r")
    hall.sub:SetText(Theme.DIM .. "All time:  |r"
        .. Theme.GOOD .. l.total .. " slain|r" .. sep .. Theme.HALL_GOLD .. KKC.Ledger.NotableBattles() .. " battles|r"
        .. sep .. Theme.BAD .. l.fallen .. " fallen|r")
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
