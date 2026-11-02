--[[
  What the player sees: a small toast after a notable engagement, the battle card (screenshot proof of who was there),
  the war chronicle (day/week summaries) and the copy box. All of it is dressed as Horde war-table parchment
  (Theme.lua), with in-character labels and plain explanations in the button tooltips.

  Nothing ever shows during combat. By default only the guildie first into battle gets the toast; everyone else's
  addon just shares its data, and they can open the card from /kkc log.
]]

local _, KKC = ...
local UI = {}
KKC.UI = UI
local Theme = KKC.Theme

local SKULL = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:13|t"

-- A movable war-table window. Returns the frame and its banner title text.
local function panel(name, w, h, title)
    local f = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(w, h)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.banner = Theme.WarFrame(f, title)
    if name then tinsert(UISpecialFrames, name) end -- Esc closes it
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -12, -12)
    close:SetFrameLevel(f:GetFrameLevel() + 10)
    f.close = close
    f:Hide()
    return f
end

-- ------------------------------------------------------------------------------------------------
-- Copy box: text pre-selected, Ctrl+C closes it
-- ------------------------------------------------------------------------------------------------

local copyFrame
function UI.ShowCopy(body, title, hint)
    if not copyFrame then
        local f = panel("KorKronCompanionCopy", 540, 380)
        f:SetPoint("CENTER", 0, 40)
        f.title = Theme.Text(f, 20, "CENTER", true)
        f.title:SetPoint("TOP", 0, -26)
        f.hint = Theme.Text(f, 11, "CENTER")
        f.hint:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
        f.hint:SetWidth(470)
        local divider = Theme.Divider(f, 300)
        divider:SetPoint("TOP", f.hint, "BOTTOM", 0, -2)
        local scroll = CreateFrame("ScrollFrame", "KorKronCompanionCopyScroll", f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 30, -96)
        scroll:SetPoint("BOTTOMRIGHT", -48, 30)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetTextColor(unpack(Theme.INK_RGB))
        edit:SetWidth(450)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        -- Typing would change the text; put it back instead (edit the account on the battle card).
        edit:SetScript("OnTextChanged", function(self, user) if user then self:SetText(f.body or ""); self:HighlightText() end end)
        edit:SetScript("OnKeyDown", function(_, key)
            if key == "C" and IsControlKeyDown() then
                C_Timer.After(0.1, function() f:Hide(); KKC.say("the report is copied. Carry it to the war table.") end)
            end
        end)
        scroll:SetScrollChild(edit)
        f.edit = edit
        copyFrame = f
    end
    copyFrame.body = body
    copyFrame.title:SetText(Theme.BLOOD .. (title or "Battle Report") .. "|r")
    copyFrame.hint:SetText(hint or "Press Ctrl+C, then paste it into the battle report post.")
    copyFrame.edit:SetText(body)
    copyFrame:Show()
    copyFrame.edit:SetFocus()
    copyFrame.edit:HighlightText()
end

-- ------------------------------------------------------------------------------------------------
-- Battle card
-- ------------------------------------------------------------------------------------------------

local card
local ROWS = 14
local ROW_TOP, ROW_STEP = -150, 17

local function discordLine()
    local D = C_Discord
    if not (D and D.GetGuildLinkStatus) then return "" end
    local linked, channel = KKC.try(D.GetGuildLinkStatus)
    if KKC.readable(linked) and linked then
        local where = (KKC.readable(channel) and channel and channel ~= "") and (" #" .. channel) or ""
        return Theme.SOFT .. "Word sent to the guild reaches Discord" .. where .. "|r"
    end
    return Theme.SOFT .. "Guild chat is not linked to Discord|r"
end

local function makeRows(parent, x, width)
    local rows = {}
    for i = 1, ROWS do
        local y = ROW_TOP - (i - 1) * ROW_STEP
        local left = Theme.Text(parent, 13)
        left:SetPoint("TOPLEFT", x, y)
        left:SetWidth(width - 92) -- long names end in "..." instead of running into the numbers
        left:SetWordWrap(false)
        local right = Theme.Text(parent, 11, "RIGHT")
        right:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y - 1)
        right:SetWidth(90)
        rows[i] = { left = left, right = right }
    end
    return rows
end

local function setRows(rows, list, fill)
    for i, row in ipairs(rows) do
        local item = list[i]
        if i == ROWS and #list > ROWS then
            row.left:SetText(Theme.SOFT .. ("and %d more"):format(#list - ROWS + 1) .. "|r")
            row.right:SetText("")
        elseif item then
            local l, r = fill(item)
            row.left:SetText(l)
            row.right:SetText(r or "")
        else
            row.left:SetText("")
            row.right:SetText("")
        end
    end
end

local function buildCard()
    local f = panel("KorKronCompanionCard", 660, 580, "Battle Report") -- wide: Forever names are "First Surname"
    f:SetPoint("CENTER", 0, 10)

    f.place = Theme.Text(f, 22, "CENTER", true)
    f.place:SetPoint("TOP", 0, -48)
    f.when = Theme.Text(f, 12, "CENTER")
    f.when:SetPoint("TOP", f.place, "BOTTOM", 0, -4)
    f.size = Theme.Text(f, 12, "CENTER")
    f.size:SetPoint("TOP", f.when, "BOTTOM", 0, -4)
    local top = Theme.Divider(f, 420)
    top:SetPoint("TOP", f.size, "BOTTOM", 0, -2)

    f.membersHeader = Theme.Text(f, 16, "LEFT", true)
    f.membersHeader:SetPoint("TOPLEFT", 32, -128)
    f.enemiesHeader = Theme.Text(f, 16, "LEFT", true)
    f.enemiesHeader:SetPoint("TOPLEFT", 344, -128)
    f.memberRows = makeRows(f, 32, 292)
    f.enemyRows = makeRows(f, 344, 284)

    local bottom = Theme.Divider(f, 420)
    bottom:SetPoint("BOTTOM", 0, 140)
    f.descLabel = Theme.Text(f, 15, "LEFT", true)
    f.descLabel:SetPoint("BOTTOMLEFT", 34, 116)
    f.descLabel:SetText(Theme.BLOOD .. "Account of the battle|r")

    local box = CreateFrame("Frame", nil, f)
    box:SetPoint("BOTTOMLEFT", 30, 60)
    box:SetPoint("BOTTOMRIGHT", -30, 60)
    box:SetHeight(52)
    local boxBg = box:CreateTexture(nil, "BACKGROUND")
    boxBg:SetAllPoints()
    boxBg:SetColorTexture(0.30, 0.17, 0.06, 0.10)
    local desc = CreateFrame("EditBox", nil, box)
    desc:SetPoint("TOPLEFT", 6, -5)
    desc:SetPoint("BOTTOMRIGHT", -6, 5)
    desc:SetMultiLine(true)
    desc:SetAutoFocus(false)
    desc:SetMaxLetters(400)
    desc:SetFontObject(ChatFontNormal)
    desc:SetTextColor(unpack(Theme.INK_RGB))
    desc:SetScript("OnEscapePressed", desc.ClearFocus)
    desc:SetScript("OnTextChanged", function(self, user)
        if user and f.engagement then f.engagement.description = self:GetText() end
    end)
    f.desc = desc

    f.discord = Theme.Text(f, 11, "CENTER")
    f.discord:SetPoint("BOTTOM", 0, 44)

    f.buttons = {
        Theme.Button(f, "Scribe report", 124, "Copy the battle report text (Date, Time, Brief Description and the details) to paste into the Discord post.",
            function() UI.CopyReport(f.engagement) end),
        Theme.Button(f, "Sound the horn", 124, "Post a one-line account of this battle in guild chat. If guild chat is linked, it reaches Discord too.",
            function() UI.Share(f.engagement) end),
        Theme.Button(f, "Capture likeness", 130, "Take a screenshot of this card, without the buttons, to attach to the battle report as proof of who fought.",
            function() UI.Screenshot() end),
        Theme.Button(f, "Close", 90, nil, function() f:Hide() end),
    }
    f.buttons[1]:SetPoint("BOTTOMLEFT", 30, 16)
    for i = 2, #f.buttons do f.buttons[i]:SetPoint("LEFT", f.buttons[i - 1], "RIGHT", 8, 0) end
    return f
end

local function fillCard(e)
    local s = KKC.Stats(e)
    card.engagement = e
    card.place:SetText(Theme.BLOOD .. KKC.Report.Place(e) .. "|r")
    local where = (e.subzone ~= "" and e.subzone ~= e.zone) and (e.zone .. ", ") or ""
    card.when:SetText(Theme.SOFT .. where .. date("%A %d %B, %H:%M", e.start) .. " - " .. date("%H:%M", e.stop or e.start) .. "|r")
    local ambushed = KKC.Ambushed(e)
    local opening = ambushed and (Theme.BLOOD .. "Ambushed|r  ~  ") or (ambushed == false and "We struck first  ~  " or "")
    card.size:SetText(("%s%d against %d  ~  %s of battle  ~  %d slain  ~  first into battle: %s%s"):format(
        opening, s.members, s.enemies, KKC.duration(e.pvpSeconds), s.kills, KKC.Initiator(e) or "?",
        e.test and "  ~  (a test)" or (e.feed and "  ~  word from the field" or "")))
    card.buttons[2]:SetEnabled(not e.feed and not e.test) -- share only your own, real fights

    card.membersHeader:SetText(Theme.BLOOD .. ("Warriors of the Kor'kron (%d)"):format(s.members) .. "|r")
    setRows(card.memberRows, KKC.sortedValues(e.members), function(m)
        local title = KKC.rpTitle(m.name)
        local l = (title and (Theme.SOFT .. title .. "|r ") or "") .. Theme.ClassInk(m.class) .. m.name .. "|r"
            .. (m.died and (" " .. SKULL) or "")
        local parts = {}
        if (m.dmg or 0) > 0 then parts[#parts + 1] = KKC.shortNumber(m.dmg) end
        if (m.heal or 0) > 0 then parts[#parts + 1] = Theme.MEND .. KKC.shortNumber(m.heal) .. " mend|r" end
        return l, table.concat(parts, "  ")
    end)

    card.enemiesHeader:SetText(Theme.BLOOD .. ("Enemies of the Horde (%d)"):format(s.enemies) .. "|r")
    setRows(card.enemyRows, KKC.sortedValues(e.enemies, function(a, b)
        if (a.kills or 0) ~= (b.kills or 0) then return (a.kills or 0) > (b.kills or 0) end
        return a.name < b.name
    end), function(en)
        local l = Theme.ClassInk(en.class) .. en.name .. "|r" .. (en.race and (Theme.SOFT .. "  " .. en.race .. "|r") or "")
        local r = (en.kills or 0) > 0 and (SKULL .. (en.kills > 1 and (" x" .. en.kills) or "")) or ""
        return l, r
    end)

    if not card.desc:HasFocus() then card.desc:SetText(e.description or KKC.Report.Description(e)) end
    card.discord:SetText(discordLine())
end

function UI.ShowCard(e)
    if not e then return end
    card = card or buildCard()
    fillCard(e)
    card:Show()
end

KKC.Listen("EngagementUpdated", function(e)
    if card and card:IsShown() and card.engagement == e then fillCard(e) end
end)

function UI.CopyReport(e)
    if not e then return end
    UI.ShowCopy(KKC.Report.CopyText(e, e.description), "Battle Report",
        "Ctrl+C, then paste it into the post. Title: your main's name and surname. Attach the captured likeness of the card.")
end

function UI.Share(e)
    if not e or e.feed or e.test then return end
    if e.shared then return KKC.say("the horn has already sounded for this battle.") end
    if UI.SendGuild(KKC.Report.ShareLine(e)) then e.shared = true end
end

function UI.SendGuild(line)
    if not IsInGuild() then KKC.say("you march with no guild."); return false end
    if C_ChatInfo.InChatMessagingLockdown and KKC.try(C_ChatInfo.InChatMessagingLockdown) then
        KKC.say("guild chat is silenced right now, try again in a moment.")
        return false
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    send(line, "GUILD")
    return true
end

-- Hide the buttons for one frame so the screenshot shows only the card.
function UI.Screenshot()
    if not card then return end
    for _, b in ipairs(card.buttons) do b:Hide() end
    card.close:Hide()
    card.desc:ClearFocus()
    C_Timer.After(0.05, function()
        Screenshot()
        C_Timer.After(0.6, function()
            for _, b in ipairs(card.buttons) do b:Show() end
            card.close:Show()
        end)
    end)
end

-- ------------------------------------------------------------------------------------------------
-- War chronicle: day / week summaries, "My battles" and "Word from the field" (guild feed) tabs
-- ------------------------------------------------------------------------------------------------

local summary
local FIGHT_ROWS = 8
local TABS = {
    { key = "mine", label = "My battles", tip = "Battles you fought in. This is the chronicle you can share." },
    { key = "guild", label = "From the field", tip = "Battles guildies with the addon fought without you." },
}
local PERIODS = { { key = "day", label = "Today" }, { key = "week", label = "This week" }, { key = "lastweek", label = "Last week" } }

local function pressed(buttons, key)
    for _, b in ipairs(buttons) do
        if b.key == key then b:LockHighlight() else b:UnlockHighlight() end
    end
end

local function buildSummary()
    local f = panel("KorKronCompanionSummary", 660, 660, "War Chronicle")
    f:SetPoint("CENTER", 0, 0)
    f.tab, f.period = "mine", "week"

    f.tabButtons, f.periodButtons = {}, {}
    for i, t in ipairs(TABS) do
        local b = Theme.Button(f, t.label, 116, t.tip, function() f.tab = t.key; UI.RefreshSummary() end)
        b.key = t.key
        b:SetPoint("TOPLEFT", 32 + (i - 1) * 122, -52)
        f.tabButtons[i] = b
    end
    for i, p in ipairs(PERIODS) do
        local b = Theme.Button(f, p.label, 86, "Weeks and days follow the server's reset.", function() f.period = p.key; UI.RefreshSummary() end)
        b.key = p.key
        b:SetPoint("TOPRIGHT", -32 - (#PERIODS - i) * 90, -52)
        f.periodButtons[i] = b
    end

    f.heading = Theme.Text(f, 18, "CENTER", true)
    f.heading:SetPoint("TOP", 0, -88)
    f.span = Theme.Text(f, 11, "CENTER")
    f.span:SetPoint("TOP", f.heading, "BOTTOM", 0, -2)
    local divider = Theme.Divider(f, 420)
    divider:SetPoint("TOP", f.span, "BOTTOM", 0, -2)

    f.body = Theme.Text(f, 13)
    f.body:SetPoint("TOPLEFT", 34, -150)
    f.body:SetWidth(592)
    f.body:SetSpacing(4)

    -- The battle list follows the text, so long name lists (double names wrap) push it down instead of overlapping.
    f.fightsHeader = Theme.Text(f, 15, "LEFT", true)
    f.fightsHeader:SetPoint("TOPLEFT", f.body, "BOTTOMLEFT", 0, -14)
    f.fights = {}
    for i = 1, FIGHT_ROWS do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(592, 18)
        b:SetPoint("TOPLEFT", f.fightsHeader, "BOTTOMLEFT", 0, -4 - (i - 1) * 19)
        local label = Theme.Text(b, 12)
        label:SetPoint("LEFT", 4, 0)
        label:SetWidth(584)
        label:SetWordWrap(false)
        b:SetFontString(label)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b:SetScript("OnClick", function(self) if self.engagement then UI.ShowCard(self.engagement) end end)
        f.fights[i] = b
    end

    f.copy = Theme.Button(f, "Scribe chronicle", 130, "Copy this chronicle as text, to paste in Discord or keep.",
        function() if f.data then UI.ShowCopy(f.text, f.label, "Ctrl+C, then paste it wherever the tale should be told.") end end)
    f.copy:SetPoint("BOTTOMLEFT", 30, 16)
    f.share = Theme.Button(f, "Sound the horn", 124, "Post a one-line summary of your battles in guild chat (and Discord, if linked).",
        function() if f.data and f.tab == "mine" then UI.SendGuild(KKC.Summary.ShareLine(f.data, f.periodLabel)) end end)
    f.share:SetPoint("LEFT", f.copy, "RIGHT", 8, 0)
    local done = Theme.Button(f, "Close", 90, nil, function() f:Hide() end)
    done:SetPoint("BOTTOMRIGHT", -30, 16)
    return f
end

function UI.RefreshSummary()
    local f = summary
    if not (f and f:IsShown()) then return end
    pressed(f.tabButtons, f.tab)
    pressed(f.periodButtons, f.period)
    local guild = f.tab == "guild"
    local from, to, label = KKC.Summary.Range(f.period)
    local data = KKC.Summary.Build(guild and KKC.db.feed or KKC.db.log, from, to)
    f.data, f.periodLabel = data, label
    f.text = KKC.Summary.Text(data, label, guild)
    f.label = (guild and "Word from the Field - " or "War Chronicle - ") .. label
    local heading, span, body = KKC.Summary.Parts(data, label, guild)
    f.heading:SetText(Theme.BLOOD .. heading .. "|r")
    f.span:SetText(Theme.SOFT .. span .. "|r")
    f.body:SetText(body)
    f.share:SetEnabled(not guild and data.engagements > 0)

    -- Notable battles first in time order; minor ones only if there's room.
    local rows = {}
    for _, e in ipairs(data.list) do if not e.minor then rows[#rows + 1] = e end end
    for _, e in ipairs(data.list) do if e.minor and #rows < FIGHT_ROWS then rows[#rows + 1] = e end end
    f.fightsHeader:SetText(#rows > 0 and (Theme.BLOOD .. "Battles|r" .. Theme.SOFT .. "  (click to read the report)|r") or "")
    for i, b in ipairs(f.fights) do
        local e = rows[i]
        b.engagement = e
        if e then
            local who = guild and (Theme.SOFT .. "  - " .. (KKC.Initiator(e) or "?") .. "|r") or ""
            b:SetText(date("%a %H:%M", e.start) .. "  " .. KKC.Report.Headline(e)
                .. (e.minor and (Theme.SOFT .. " (skirmish)|r") or "") .. who)
            b:Show()
        else
            b:Hide()
        end
    end
end

-- tab: "mine" | "guild", period: "day" | "week" | "lastweek"
function UI.ShowSummary(tab, period)
    summary = summary or buildSummary()
    summary.tab = tab or summary.tab
    summary.period = period or summary.period
    summary:Show()
    UI.RefreshSummary()
end

KKC.Listen("EngagementClosed", function() UI.RefreshSummary() end)
KKC.Listen("FeedUpdated", function() UI.RefreshSummary() end)

-- ------------------------------------------------------------------------------------------------
-- Toast: a small parchment note, top center
-- ------------------------------------------------------------------------------------------------

local toast, toastTimer

local function buildToast()
    local f = CreateFrame("Frame", "KorKronCompanionToast", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(400, 86)
    f:SetPoint("TOP", 0, -140)
    f:SetFrameStrata("MEDIUM")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 4, -4)
    bg:SetPoint("BOTTOMRIGHT", -4, 4)
    if not Theme.Atlas(bg, "ChromieTime-Parchment") then bg:SetColorTexture(0.84, 0.74, 0.55, 1) end
    if f.SetBackdrop then
        f:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16 })
        f:SetBackdropBorderColor(0.45, 0.28, 0.12)
    end
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(58, 58)
    icon:SetPoint("LEFT", 12, 0)
    if not Theme.Atlas(icon, "HordeEmblem") then icon:SetTexture("Interface\\Icons\\INV_BannerPVP_01") end
    f.title = Theme.Text(f, 17, "LEFT", true)
    f.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 2)
    f.title:SetText(Theme.BLOOD .. "Blood has been spilled|r")
    f.body = Theme.Text(f, 12)
    f.body:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
    f.body:SetWidth(300)
    f.body:SetWordWrap(false)
    local open = Theme.Button(f, "Read the report", 120, "Open the battle card for this battle.",
        function() f:Hide(); UI.ShowCard(f.engagement) end)
    open:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, -6)
    local later = Theme.Button(f, "Let it pass", 96, "Hide this note. The battle stays in /kkc log.", function() f:Hide() end)
    later:SetPoint("LEFT", open, "RIGHT", 6, 0)
    return f
end

function UI.ShowToast(e)
    toast = toast or buildToast()
    toast.engagement = e
    toast.title:SetText(Theme.BLOOD .. (KKC.Ambushed(e) and "Ambushed!" or "Blood has been spilled") .. "|r")
    toast.body:SetText(KKC.Report.Headline(e))
    toast:Show()
    if toastTimer then toastTimer:Cancel() end
    toastTimer = C_Timer.NewTimer(25, function() toast:Hide() end)
    if PlaySound and SOUNDKIT and SOUNDKIT.UI_BATTLEGROUND_COUNTDOWN_FINISHED then
        KKC.try(PlaySound, SOUNDKIT.UI_BATTLEGROUND_COUNTDOWN_FINISHED)
    end
end

-- ------------------------------------------------------------------------------------------------
-- When to tell the player
-- ------------------------------------------------------------------------------------------------

local waiting -- an engagement to announce once combat is over

function UI.Notify(e, force)
    if not e or e.notified then return end
    if not e.test then e.minor = not KKC.IsNotable(e) end
    local set = KKC.settings()
    if not force then
        if e.minor or set.notify == "off" then return end
        if KKC.Initiator(e) ~= KKC.me() and not set.promptAll then return end
    end
    if InCombatLockdown() then waiting = e; return end
    e.notified = true
    if set.notify == "quiet" and not force then
        KKC.say("blood has been spilled: " .. KKC.Report.Headline(e) .. ". |cffffd100/kkc card|r to read the report.")
    elseif set.notify == "prompt" and not force then
        UI.ShowCard(e)
    else
        UI.ShowToast(e)
    end
end

-- Give guildies' reports a few seconds to arrive, so the initiator and the numbers are right.
KKC.Listen("EngagementClosed", function(e)
    C_Timer.After(6, function() UI.Notify(e) end)
end)

KKC.On("PLAYER_REGEN_ENABLED", function()
    if not waiting then return end
    local e = waiting
    waiting = nil
    C_Timer.After(3, function() UI.Notify(e) end)
end)

-- ------------------------------------------------------------------------------------------------
-- Log in chat
-- ------------------------------------------------------------------------------------------------

function UI.PrintLog(showMinor)
    local log, shown = KKC.db.log, 0
    if #log == 0 then return KKC.say("no battles recorded yet. The blades stay sheathed.") end
    KKC.say("Recent battles (|cffffd100/kkc card N|r reads a report, |cffffd100/kkc week|r the chronicle):")
    for i, e in ipairs(log) do
        if showMinor or not e.minor then
            shown = shown + 1
            KKC.say(("  %d. %s  %s%s"):format(i, date("%m-%d %H:%M", e.start), KKC.Report.Headline(e), e.minor and (KKC.GREY .. " (skirmish)|r") or ""))
            if shown >= 10 then break end
        end
    end
    if shown == 0 then KKC.say("  only passing skirmishes so far: |cffffd100/kkc log all|r") end
end
