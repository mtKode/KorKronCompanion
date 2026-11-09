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

local WIDTH, HEIGHT = 900, 590
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

local function headline(e)
    local tags = {}
    local ambushed = KKC.Ambushed(e)
    if ambushed then tags[#tags + 1] = "|cffff6050ambush|r" elseif ambushed == false then tags[#tags + 1] = "struck first" end
    if e.minor then tags[#tags + 1] = Theme.DIM .. "skirmish|r" end
    if e.feed then tags[#tags + 1] = Theme.DIM .. "by " .. (KKC.Initiator(e) or "?") .. "|r" end
    return KKC.Report.Headline(e) .. (#tags > 0 and ("  " .. Theme.DIM .. "~|r " .. table.concat(tags, ", ")) or "")
end

-- A clickable battle row: "Wed 21:14   Tarren Mill - 4 against 6, 5 slain  ~ ambush". Click: the battle card.
local function battleRow(parent, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 20)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    local F = Theme.F()
    hl:SetColorTexture(F.accent[1], F.accent[2], F.accent[3], 0.22)
    b.when = Theme.LightText(b, 12)
    b.when:SetPoint("LEFT", 4, 0)
    b.when:SetWidth(96)
    b.what = Theme.LightText(b, 12)
    b.what:SetPoint("LEFT", 104, 0)
    b.what:SetPoint("RIGHT", -4, 0)
    b.what:SetWordWrap(false)
    b:SetScript("OnClick", function(self) if self.engagement then KKC.UI.ShowCard(self.engagement) end end)
    function b:Set(e)
        self.engagement = e
        if not e then return self:Hide() end
        self.when:SetText(Theme.DIM .. date("%a %d %b %H:%M", e.start) .. "|r")
        self.what:SetText(headline(e))
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
local CHRONICLE_ROWS = 4

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
        b:SetPoint("TOPLEFT", (i - 1) * 105, 0)
        p.periods[i] = b
    end

    p.heading = Theme.LightText(p, 19, "LEFT", true)
    p.heading:SetPoint("TOPLEFT", 2, -36)
    p.span = Theme.LightText(p, 11)
    p.span:SetPoint("TOPLEFT", p.heading, "BOTTOMLEFT", 0, -2)

    p.tiles = {}
    for i, t in ipairs(TILES) do
        local box = Theme.Inset(p)
        box:SetSize(152, 58)
        box:SetPoint("TOPLEFT", (i - 1) * 160, -84)
        box.value = Theme.LightText(box, 22, "CENTER", true)
        box.value:SetPoint("TOP", 0, -8)
        box.label = Theme.LightText(box, 11, "CENTER")
        box.label:SetPoint("BOTTOM", 0, 8)
        box.label:SetText(Theme.DIM .. t.label .. "|r")
        p.tiles[t.key] = box
    end

    local details = Theme.Inset(p)
    details:SetPoint("TOPLEFT", 0, -152)
    details:SetPoint("TOPRIGHT", 0, -152)
    details:SetHeight(180)
    p.body = Theme.LightText(details, 12)
    p.body:SetPoint("TOPLEFT", 12, -10)
    p.body:SetPoint("RIGHT", -12, 0)
    p.body:SetSpacing(4)
    p.body:SetJustifyV("TOP")

    p.listHeader = Theme.LightText(p, 15, "LEFT", true)
    p.listHeader:SetPoint("TOPLEFT", 2, -342)
    p.rows = {}
    for i = 1, CHRONICLE_ROWS do
        local r = battleRow(p, 630)
        r:SetPoint("TOPLEFT", 0, -362 - (i - 1) * 21)
        p.rows[i] = r
    end

    p.copy = Theme.HallButton(p, "Scribe chronicle", 150, 26, "Interface\\Icons\\INV_Scroll_03",
        "Copy this chronicle as text, to paste in Discord or keep.", function()
            if p.data then KKC.UI.ShowCopy(p.text, p.title, "Ctrl+C, then paste it wherever the tale should be told.") end
        end)
    p.copy:SetPoint("BOTTOMLEFT", 0, 0)
    if not guild then
        p.share = Theme.HallButton(p, "Sound the horn", 150, 26, "Interface\\Icons\\INV_Misc_Horn_01",
            "Post a one-line summary of these battles in guild chat (and Discord, if guild chat is linked).", function()
                if p.data then KKC.UI.SendGuild(KKC.Summary.ShareLine(p.data, p.label)) end
            end)
        p.share:SetPoint("LEFT", p.copy, "RIGHT", 8, 0)
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
        self.body:SetText(body)
        self.tiles.battles.value:SetText(data.engagements)
        self.tiles.kills.value:SetText(data.kills)
        self.tiles.fallen.value:SetText(data.fallen)
        self.tiles.blow.value:SetText(("%d / %d"):format(data.struck, data.ambushed))
        if self.share then self.share:SetEnabled(data.engagements > 0) end

        local rows = {}
        for _, e in ipairs(data.list) do if not e.minor then rows[#rows + 1] = e end end
        for _, e in ipairs(data.list) do if e.minor and #rows < CHRONICLE_ROWS then rows[#rows + 1] = e end end
        local more = #rows > CHRONICLE_ROWS and (Theme.DIM .. ("  (%d more under Battles)"):format(#rows - CHRONICLE_ROWS) .. "|r") or ""
        self.listHeader:SetText(#rows > 0 and ("Battles" .. more) or "")
        for i, r in ipairs(self.rows) do r:Set(rows[i]) end
    end
    return p
end

-- ------------------------------------------------------------------------------------------------
-- Battles: the whole log, paged
-- ------------------------------------------------------------------------------------------------

local BATTLE_ROWS = 19

local function buildBattles(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()
    p:Hide()
    p.page, p.showMinor = 1, false

    p.heading = Theme.LightText(p, 19, "LEFT", true)
    p.heading:SetPoint("TOPLEFT", 2, -2)
    p.heading:SetText("Battles")
    p.sub = Theme.LightText(p, 11)
    p.sub:SetPoint("TOPLEFT", p.heading, "BOTTOMLEFT", 0, -2)

    local box = Theme.Inset(p)
    box:SetPoint("TOPLEFT", 0, -44)
    box:SetPoint("BOTTOMRIGHT", 0, 34)
    p.rows = {}
    for i = 1, BATTLE_ROWS do
        local r = battleRow(box, 610)
        r:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 21)
        p.rows[i] = r
    end

    p.newer = Theme.HallButton(p, "< Newer", 100, 26, nil, nil, function() p.page = p.page - 1; p:Refresh() end)
    p.newer:SetPoint("BOTTOMLEFT", 0, 0)
    p.older = Theme.HallButton(p, "Older >", 100, 26, nil, nil, function() p.page = p.page + 1; p:Refresh() end)
    p.older:SetPoint("LEFT", p.newer, "RIGHT", 8, 0)
    p.pageText = Theme.LightText(p, 12)
    p.pageText:SetPoint("LEFT", p.older, "RIGHT", 12, 0)
    p.minor = Theme.HallButton(p, "Show skirmishes", 150, 26, nil,
        "Also list the passing skirmishes (a stray hit, no kills): they are kept but never announced.", function()
            p.showMinor = not p.showMinor
            p.page = 1
            p:Refresh()
        end)
    p.minor:SetPoint("BOTTOMRIGHT", 0, 0)

    function p:Refresh()
        local list = {}
        for _, e in ipairs(KKC.db.log) do
            if self.showMinor or not e.minor then list[#list + 1] = e end
        end
        local pages = math.max(1, math.ceil(#list / BATTLE_ROWS))
        self.page = math.max(1, math.min(self.page, pages))
        for i, r in ipairs(self.rows) do r:Set(list[(self.page - 1) * BATTLE_ROWS + i]) end
        self.newer:SetEnabled(self.page > 1)
        self.older:SetEnabled(self.page < pages)
        self.pageText:SetText(Theme.DIM .. ("Page %d of %d"):format(self.page, pages) .. "|r")
        self.minor:SetSelected(self.showMinor)
        self.sub:SetText(Theme.DIM .. (#list > 0 and ("%d battles recorded. Click one to read its report."):format(#list)
            or "No battles recorded yet. The blades stay sheathed... for now.") .. "|r")
    end
    return p
end

-- ------------------------------------------------------------------------------------------------
-- War Ledger: tiered challenges, Legacy style
-- ------------------------------------------------------------------------------------------------

local LEDGER_ROWS = 6

local function buildLedger(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()
    p:Hide()
    p.page = 1

    p.heading = Theme.LightText(p, 19, "LEFT", true)
    p.heading:SetPoint("TOPLEFT", 2, -2)
    p.heading:SetText("War Ledger")
    p.sub = Theme.LightText(p, 11)
    p.sub:SetPoint("TOPLEFT", p.heading, "BOTTOMLEFT", 0, -2)

    p.rows = {}
    for i = 1, LEDGER_ROWS do
        local row = Theme.Inset(p)
        row:SetPoint("TOPLEFT", 0, -44 - (i - 1) * 64)
        row:SetPoint("RIGHT", 0, 0)
        row:SetHeight(58)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(40, 40)
        row.icon:SetPoint("LEFT", 9, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.title = Theme.LightText(row, 15, "LEFT", true)
        row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 12, -2)
        row.text = Theme.LightText(row, 12)
        row.text:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
        row.bar = Theme.Bar(row, 180, 16)
        row.bar:SetPoint("RIGHT", -14, 4)
        row.tier = Theme.LightText(row, 11, "CENTER")
        row.tier:SetPoint("TOP", row.bar, "BOTTOM", 0, -3)
        p.rows[i] = row
    end

    p.prev = Theme.HallButton(p, "< Previous", 110, 26, nil, nil, function() p.page = p.page - 1; p:Refresh() end)
    p.prev:SetPoint("BOTTOMLEFT", 0, 0)
    p.next = Theme.HallButton(p, "Next >", 110, 26, nil, nil, function() p.page = p.page + 1; p:Refresh() end)
    p.next:SetPoint("LEFT", p.prev, "RIGHT", 8, 0)
    p.pageText = Theme.LightText(p, 12)
    p.pageText:SetPoint("LEFT", p.next, "RIGHT", 12, 0)

    function p:Refresh()
        local tracks = KKC.Ledger.Tracks()
        local l = KKC.Ledger.Mine()
        self.sub:SetText(Theme.DIM .. ("%s: %d slain, %d unique foes, fallen %d times. Only honor kills you earned yourself count.")
            :format(KKC.me() or "?", l.total, KKC.count(l.enemy), l.fallen) .. "|r")
        local pages = math.max(1, math.ceil(#tracks / LEDGER_ROWS))
        self.page = math.max(1, math.min(self.page, pages))
        for i, row in ipairs(self.rows) do
            local t = tracks[(self.page - 1) * LEDGER_ROWS + i]
            if t then
                row.icon:SetTexture(t.icon)
                row.icon:SetDesaturated(t.tier == 0)
                row.title:SetText(t.complete and (Theme.GOLD .. t.title .. "|r") or t.title)
                row.text:SetText(t.text)
                row.bar:SetProgress(t.value, t.goal)
                row.tier:SetText(Theme.DIM .. (t.complete and "Every tier earned" or ("Tier %d of %d"):format(t.tier + 1, t.tiers)) .. "|r")
                row:Show()
            else
                row:Hide()
            end
        end
        self.prev:SetEnabled(self.page > 1)
        self.next:SetEnabled(self.page < pages)
        self.pageText:SetText(Theme.DIM .. ("Page %d of %d"):format(self.page, pages) .. "|r")
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
    local heading = Theme.LightText(p, 19, "LEFT", true)
    heading:SetPoint("TOPLEFT", 2, -2)
    heading:SetText("Settings")

    local y = -44
    local function row(title, buttonLabel, onClick)
        local box = Theme.Inset(p)
        box:SetPoint("TOPLEFT", 0, y)
        box:SetPoint("RIGHT", 0, 0)
        box:SetHeight(64)
        box.title = Theme.LightText(box, 15, "LEFT", true)
        box.title:SetPoint("TOPLEFT", 14, -10)
        box.title:SetText(title)
        box.text = Theme.LightText(box, 12)
        box.text:SetPoint("TOPLEFT", box.title, "BOTTOMLEFT", 0, -4)
        box.text:SetPoint("RIGHT", -190, 0)
        box.button = Theme.HallButton(box, buttonLabel, 160, 26, nil, nil, onClick)
        box.button:SetPoint("RIGHT", -14, 0)
        y = y - 72
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
    p.test.text:SetText(Theme.DIM .. "A made-up ambush at Tarren Mill, to see the note and the battle card without a fight.|r")
    p.debug = row("Diagnostics", "Print to chat", function() SlashCmdList.KORKRONCOMPANION("debug") end)
    p.debug.text:SetText(Theme.DIM .. "What this game client allows the addon (meter, names, sync). Send it along if something looks wrong.|r")

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
    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", -12, -12)
    f.close:SetFrameLevel(f:GetFrameLevel() + 10)

    -- Who's speaking: the faction crest, the guild and the character.
    f.crest = f:CreateTexture(nil, "ARTWORK")
    f.crest:SetSize(46, 46)
    f.crest:SetPoint("TOPLEFT", 26, -24)
    if not Theme.Atlas(f.crest, Theme.F().emblem) then f.crest:SetTexture(Theme.F().icon) end
    f.who = Theme.LightText(f, 19, "LEFT", true)
    f.who:SetPoint("TOPLEFT", f.crest, "TOPRIGHT", 10, -4)
    f.sub = Theme.LightText(f, 12)
    f.sub:SetPoint("TOPLEFT", f.who, "BOTTOMLEFT", 0, -3)

    f.nav = {}
    for i, s in ipairs(SECTIONS) do
        local b = Theme.HallButton(f, s.label, NAV_W, 34, s.icon, s.tip, function() Hub.Select(s.key) end)
        b:SetPoint("TOPLEFT", 22, -84 - (i - 1) * 40)
        b.key = s.key
        f.nav[i] = b
    end
    local motto = Theme.LightText(f, 13, "CENTER", true)
    motto:SetPoint("BOTTOMLEFT", 22, 26)
    motto:SetWidth(NAV_W)
    motto:SetText(Theme.DIM .. (UnitFactionGroup("player") == "Alliance" and "For the Alliance!" or "Lok'tar ogar!") .. "|r")

    f.content = CreateFrame("Frame", nil, f)
    f.content:SetPoint("TOPLEFT", 22 + NAV_W + 16, -84)
    f.content:SetPoint("BOTTOMRIGHT", -24, 22)
    f.pages = {}
    for key, builder in pairs(BUILDERS) do f.pages[key] = builder(f.content) end

    f:SetScript("OnHide", function() if tab then tab.selected:Hide() end end)
    return f
end

local function refreshHeader()
    local guild = IsInGuild() and GetGuildInfo("player")
    hall.who:SetText(KKC.readable(guild) and guild or "Hall of the Kor'kron")
    local l = KKC.Ledger.Mine()
    hall.sub:SetText(Theme.DIM .. ("%s  ~  %d slain  ~  %d battles of note"):format(KKC.me() or "?", l.total, l.engagements) .. "|r")
end

function Hub.Refresh()
    if not (hall and hall:IsShown()) then return end
    refreshHeader()
    for _, b in ipairs(hall.nav) do b:SetSelected(b.key == current.section) end
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
    if not hall.docked then placeAlone(hall) end
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
    hall:SetFrameStrata(L:GetFrameStrata())
    -- Above Legacy's pages (they sit at frame level 100), so their buttons can't be clicked through ours.
    hall:SetFrameLevel(math.max(L:GetFrameLevel(), 100) + 20)
    setChrome(false)
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
