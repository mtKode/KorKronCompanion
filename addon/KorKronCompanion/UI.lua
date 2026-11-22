--[[
  What the player sees: a small toast after a notable engagement, the battle card (screenshot proof of who was there),
  the war chronicle (day/week summaries) and the copy box. All of it is dressed as Horde war-table parchment
  (Theme.lua), with in-character labels and plain explanations in the button tooltips.

  Nothing ever shows during combat. By default only the guildie first into battle gets the toast; everyone else's
  addon just shares its data, and they can open the card from /kkc log.
]]

local ADDON, KKC = ...
local UI = {}
KKC.UI = UI
local Theme = KKC.Theme

local SKULL = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:13|t"

-- A movable window: a dark sheet like the hall's book (dark = "sheet": the battle card, the scribe window), or the
-- dark hall's frame (dark = true).
local function panel(name, w, h, title, dark)
    local f = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(w, h)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if dark == "sheet" then
        f.banner = Theme.SheetFrame(f, title)
    else
        local parts = Theme.DarkFrame(f, title)
        f.banner = parts.title
    end
    if name then tinsert(UISpecialFrames, name) end -- Esc closes it
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", dark == "sheet" and -18 or -12, dark == "sheet" and -18 or -12)
    close:SetFrameLevel(f:GetFrameLevel() + 10)
    close:SetScript("OnClick", function() f:Hide() end) -- the stock handler didn't close our windows on this client
    f.close = close
    f:Hide()
    return f
end

-- ------------------------------------------------------------------------------------------------
-- Copy box: text pre-selected, Ctrl+C closes it
-- ------------------------------------------------------------------------------------------------

local copyFrame
function UI.ShowCopy(body, title, hint, post)
    if not copyFrame then
        -- Dark like the hall's book: light text on a dark page reads well, and it's what you copy from.
        local f = panel("KorKronCompanionCopy", 580, 440, nil, "sheet")
        f:SetPoint("CENTER", 0, 40)
        f:SetFrameStrata("FULLSCREEN_DIALOG") -- always above the battle card it was opened from
        f.title = Theme.SheetTitle(f, 22, "CENTER")
        f.title:SetPoint("TOP", 0, -32)
        f.hint = Theme.LightText(f, 12, "CENTER", false, true)
        f.hint:SetTextColor(0.72, 0.64, 0.50)
        f.hint:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
        f.hint:SetWidth(480)
        local rule = Theme.Rule(f, 480, true)
        rule:SetPoint("TOP", f.hint, "BOTTOM", 0, -10)
        -- The text on a dark panel like the book's boxes, with Close under it.
        local box = Theme.SheetPanel(f)
        box:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", -14, -8)
        box:SetPoint("BOTTOMRIGHT", -36, 70)
        local scroll = CreateFrame("ScrollFrame", "KorKronCompanionCopyScroll", box, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 10, -10)
        scroll:SetPoint("BOTTOMRIGHT", -30, 10)
        local done = Theme.HallButton(f, "Close", 160, 32, nil, nil, function() f:Hide() end)
        done.kkSheet = true
        done:SetSelected(false)
        f.done = done
        -- A battle report can also go to guild or officer chat, line by line, for the guild's Discord bridge.
        local function postButton(label, channel, tip)
            local b
            b = Theme.HallButton(f, label, 150, 32, nil, tip, function() UI.PostClick(b) end)
            b.kkSheet = true
            b:SetSelected(false)
            b.baseLabel, b.channel = label, channel
            return b
        end
        f.guildPost = postButton("Guild chat", "GUILD",
            "Post the report in guild chat, a line every 1.5 seconds (your guild's Discord bridge passes it on). Click twice.")
        f.officerPost = postButton("Officer chat", "OFFICER",
            "Post the report in officer chat, a line every 1.5 seconds. Needs officer chat rights; reaches Discord only if the bridge reads officer chat. Click twice.")
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(true)
        edit:SetFontObject(ChatFontNormal)
        Theme.Font(edit, 14)
        edit:SetTextColor(0.92, 0.87, 0.79)
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
    -- post: the battle (or outing) whose report this is; it can go to chat. Otherwise only Close.
    local f = copyFrame
    f.post = post
    f.lines = post and KKC.Report.ChatLines(post)
    f.done:ClearAllPoints()
    if post then
        f.guildPost:SetPoint("BOTTOMLEFT", (580 - 426) / 2, 30) -- 150 + 150 + 110 and two gaps of 8
        f.officerPost:SetPoint("LEFT", f.guildPost, "RIGHT", 8, 0)
        f.done:SetWidth(110)
        f.done:SetPoint("LEFT", f.officerPost, "RIGHT", 8, 0)
        local can = not post.feed and not post.test -- only your own, real battles
        for _, b in ipairs({ f.guildPost, f.officerPost }) do
            b.armed = nil
            if not (UI.posting and UI.posting.button == b) then b:SetLabel(b.baseLabel) end
            b:SetEnabled(can)
            b:Show()
        end
    else
        f.guildPost:Hide()
        f.officerPost:Hide()
        f.done:SetWidth(160)
        f.done:SetPoint("BOTTOM", 0, 30)
    end
    copyFrame.title:SetText(title or "Battle Report")
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
local CARD_W = 780
local ROWS = 13
local ROW_TOP, ROW_STEP = -212, 20

-- (No Discord line here: every C_Discord function but IsEnabled is restricted to Blizzard's UI. Calling
-- GetGuildLinkStatus from the card is what raised the "blocked from an action" popup.)

-- One line per person: the name, then up to two right-aligned columns that never wrap (damage and mend for
-- guildies; enemies use only the last one, for their skulls).
local MEND_W, DMG_W, GAP = 86, 52, 6

local function cell(parent, size, justify, width)
    local fs = Theme.SheetText(parent, size, justify)
    fs:SetWidth(width)
    fs:SetWordWrap(false)
    return fs
end

local function makeRows(parent, x, width, twoColumns, lastWidth)
    local rows = {}
    lastWidth = lastWidth or MEND_W
    local nameWidth = width - lastWidth - GAP - (twoColumns and (DMG_W + GAP) or 0)
    for i = 1, ROWS do
        local y = ROW_TOP - (i - 1) * ROW_STEP
        local row = {}
        row.name = cell(parent, 15, "LEFT", nameWidth) -- long names end in "..." instead of running into the numbers
        row.name:SetPoint("TOPLEFT", x, y)
        row.last = cell(parent, 14, "RIGHT", lastWidth)
        row.last:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
        if twoColumns then
            row.first = cell(parent, 14, "RIGHT", DMG_W)
            row.first:SetPoint("TOPRIGHT", row.last, "TOPLEFT", -GAP, 0)
        end
        rows[i] = row
    end
    return rows
end

local function setRow(row, name, first, last)
    row.name:SetText(name or "")
    if row.first then row.first:SetText(first or "") end
    row.last:SetText(last or "")
end

local function setRows(rows, list, fill)
    local max = #rows
    for i, row in ipairs(rows) do
        local item = list[i]
        if i == max and #list > max then
            setRow(row, Theme.DIM .. ("and %d more"):format(#list - max + 1) .. "|r")
        elseif item then
            setRow(row, fill(item))
        else
            setRow(row)
        end
    end
end

local function buildCard()
    -- 780 wide: Forever names are "First Surname", and a TRP3 title can come in front.
    local f = panel("KorKronCompanionCard", CARD_W, 680, "Battle Report", "sheet") -- room below the names for the foes' line
    f:SetPoint("CENTER", 0, 10)

    -- Everything stays inside the iron border (about 36 px on each side), and the place name starts below the
    -- banner, which hangs about 62 px into the card.
    f.place = Theme.SheetTitle(f, 28, "CENTER")
    f.place:SetPoint("TOP", 0, -68)
    f.when = Theme.SheetText(f, 14, "CENTER")
    f.when:SetPoint("TOP", f.place, "BOTTOM", 0, -4)
    f.size = Theme.SheetText(f, 14, "CENTER")
    f.size:SetPoint("TOP", f.when, "BOTTOM", 0, -4)
    f.size:SetWidth(CARD_W - 80)
    f.first = Theme.SheetText(f, 14, "CENTER")
    f.first:SetPoint("TOP", f.size, "BOTTOM", 0, -3)
    f.first:SetWidth(CARD_W - 80)
    local top = Theme.Rule(f, CARD_W - 100, true)
    top:SetPoint("TOP", f.first, "BOTTOM", 0, -12)

    -- The Kor'kron are what the card is for (the officers' proof of who fought); the enemy is only tallied by race.
    -- Up to 13 warriors: one wide column (with TRP3 titles) and the foes' tally on the right. More: two columns of
    -- warriors across the whole card (26 names, no titles so the names fit) and the tally as one line below them.
    local left, right = 42, 548
    f.membersHeader = Theme.SheetTitle(f, 18)
    f.membersHeader:SetPoint("TOPLEFT", left, ROW_TOP + 26)
    f.enemiesHeader = Theme.SheetTitle(f, 18)
    f.enemiesHeader:SetPoint("TOPLEFT", right, ROW_TOP + 26)
    f.wideRows = makeRows(f, left, right - left - 30, true)
    f.colRows = makeRows(f, left, 336, true)
    for _, row in ipairs(makeRows(f, left + 364, 336, true)) do f.colRows[#f.colRows + 1] = row end
    -- 27 to 39 warriors: three columns of names only, so a big raid still fits one picture.
    f.triRows = {}
    for c = 0, 2 do
        for _, row in ipairs(makeRows(f, left + c * 236, 224, false, 54)) do f.triRows[#f.triRows + 1] = row end
    end
    -- Even more: the mouse wheel scrolls the names (a picture per screenful).
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
        if not self.engagement then return end
        self.memberOffset = (self.memberOffset or 0) - delta * 3
        UI.ShowCard(self.engagement, true)
    end)
    f.foeRows = makeRows(f, right, CARD_W - right - 40, false, 64)
    f.foeLine = Theme.SheetText(f, 14, "CENTER")
    -- With many warriors the foes get a line of their own, set apart from the names by a rule.
    f.foeRule = Theme.Rule(f, CARD_W - 260, true)
    f.foeRule:SetPoint("BOTTOM", 0, 196)
    f.foeLine:SetPoint("BOTTOM", 0, 170)
    f.foeLine:SetWidth(CARD_W - 80)
    f.foeLine:SetWordWrap(false)

    local bottom = Theme.Rule(f, CARD_W - 100, true)
    bottom:SetPoint("BOTTOM", 0, 156)
    f.descLabel = Theme.SheetTitle(f, 18)
    f.descLabel:SetPoint("BOTTOMLEFT", 42, 120)
    f.descLabel:SetText("Account of the battle")

    local box = Theme.SheetPanel(f)
    box:SetPoint("BOTTOMLEFT", 38, 66)
    box:SetPoint("BOTTOMRIGHT", -38, 66)
    box:SetHeight(54)
    local desc = CreateFrame("EditBox", nil, box)
    desc:SetPoint("TOPLEFT", 8, -6)
    desc:SetPoint("BOTTOMRIGHT", -8, 6)
    desc:SetMultiLine(true)
    desc:SetAutoFocus(false)
    desc:SetMaxLetters(400)
    desc:SetFontObject(ChatFontNormal)
    Theme.Font(desc, 15)
    desc:SetTextColor(0.92, 0.87, 0.79)
    desc:SetScript("OnEscapePressed", desc.ClearFocus)
    desc:SetScript("OnTextChanged", function(self, user)
        if not (user and f.engagement) then return end
        f.engagement.description = self:GetText()
        -- A campaign is rebuilt from the log each time: keep its account on its first fight.
        if f.engagement.campaign then f.engagement.anchor.campaignDescription = self:GetText() end
    end)
    f.desc = desc

    local function button(label, width, tip, onClick)
        local b = Theme.HallButton(f, label, width, 30, nil, tip, onClick)
        b.kkSheet = true -- the book's dark button with a tan border
        b:SetSelected(false)
        return b
    end
    f.buttons = {
        button("Scribe report", 160, "Copy the battle report in the guild's template (Date, Start time, Duration, Short description, Kills, leaders, ...) to paste into the Discord post.",
            function() UI.CopyReport(f.engagement) end),
        button("Sound the horn", 160, "Post a one-line account of this battle in guild chat. If guild chat is linked, it reaches Discord too.",
            function() UI.Share(f.engagement) end),
        button("Capture likeness", 160, "Hides these buttons for a few seconds: press Print Screen to save the card as proof of who fought.",
            function() UI.Screenshot() end),
        button("Close", 110, nil, function() f:Hide() end),
    }
    f.hornButton = f.buttons[2] -- Sound the horn: only when switched on in Settings (settings.horn)
    -- Only on an outing with roll calls: shows or hides the roll calls on a side panel beside the card.
    f.rollButton = button("Roll calls", 130, "Show or hide this outing's roll calls beside the card: who was with us at "
        .. "each, who joined and who left, and who joined later or left early.",
        function()
            if not f.engagement then return end
            if KKC.RollCall.SideShown() == f.engagement then KKC.RollCall.HideSide()
            else KKC.RollCall.ShowSide(f.engagement, f) end
            f.rollButton:SetSelected(KKC.RollCall.SideShown() == f.engagement)
        end)
    KKC.RollCall.OnSideHidden(function() f.rollButton:SetSelected(false) end)
    f:SetScript("OnHide", function() KKC.RollCall.HideSide() end) -- the roll calls close with the card
    table.insert(f.buttons, 4, f.rollButton)
    -- Only when other raids at the same battle reported (guild sync): the whole host, raid by raid.
    f.hostButton = button("Multi-raid report", 140, "The multi-raid report: every raid of the guild at this battle, from their guildies' addons (guild sync). Your own report stays your raid's.",
        function() if f.engagement then UI.ShowHost(f.engagement) end end)
    table.insert(f.buttons, 5, f.hostButton)
    -- Full and narrower widths: with both Roll calls and Multi-raid report the row must still fit the card.
    local WIDTHS = { 150, 150, 160, 130, 140, 110 }
    local NARROW = { 120, 124, 136, 96, 132, 80 }
    -- A centered row, clear of the bottom edge, of the buttons this card has.
    function f.layoutButtons()
        local shown, width = {}, -8
        local narrow = f.hasRollCalls and f.hasHost
        for i, b in ipairs(f.buttons) do
            if (b ~= f.rollButton or f.hasRollCalls) and (b ~= f.hostButton or f.hasHost)
                and (b ~= f.hornButton or KKC.settings().horn) then
                b:SetWidth(narrow and NARROW[i] or WIDTHS[i])
                shown[#shown + 1] = b
                width = width + (narrow and NARROW[i] or WIDTHS[i]) + 8
            else
                b:Hide()
            end
        end
        for i, b in ipairs(shown) do
            b:ClearAllPoints()
            if i == 1 then b:SetPoint("BOTTOMLEFT", (CARD_W - width) / 2, 26) else b:SetPoint("LEFT", shown[i - 1], "RIGHT", 8, 0) end
            b:Show()
        end
    end
    f.layoutButtons()
    f.hint = Theme.SheetText(f, 13, "CENTER")
    f.hint:SetPoint("BOTTOM", 0, 34)
    f.hint:Hide()
    return f
end

-- "at least 5 slain" in green, "no kills seen" dim.
local function slain(n) return (n > 0 and Theme.GOOD or Theme.DIM) .. KKC.SlainText(n) .. "|r" end

local function fillCard(e)
    local s = KKC.Stats(e)
    card.engagement = e
    local name, lower = "Battle", "battle"
    if e.campaign then name, lower = KKC.Campaign.Name(e) end
    if card.banner then card.banner:SetText(name == "Battle" and "Battle Report" or (name .. " Report")) end
    card.descLabel:SetText("Account of the " .. lower)
    card.place:SetText(KKC.Report.Place(e))
    local where = (not e.campaign and e.subzone ~= "" and e.subzone ~= e.zone) and (e.zone .. ", ") or ""
    card.when:SetText(Theme.DIM .. where .. date("%A %d %B, %H:%M", e.start) .. " - " .. date("%H:%M", e.stop or e.start) .. "|r")
    local leaders = KKC.Leaders(e)
    local led = #leaders > 0 and ("Led by " .. table.concat(leaders, ", ")) or ""
    -- First into battle only when the addon can tell (guild sync reports, or you alone); else just the leaders.
    local firstIn = KKC.KnownInitiator(e)
    local function opening(extra)
        local parts = {}
        if firstIn then parts[#parts + 1] = "First into battle: " .. firstIn end
        if led ~= "" then parts[#parts + 1] = led end
        if extra then parts[#parts + 1] = extra end
        return table.concat(parts, "  ~  ")
    end
    if e.campaign then
        card.size:SetText(("%d clashes  ~  %d against %s  ~  %s of battle  ~  %s"):format(
            e.fights, s.members, Theme.Foe() .. s.enemies .. "|r", KKC.duration(e.pvpSeconds), slain(s.kills)))
        card.first:SetText(opening())
    else
        card.size:SetText(("%d against %s  ~  %s of battle  ~  %s"):format(
            s.members, Theme.Foe() .. s.enemies .. "|r", KKC.duration(e.pvpSeconds), slain(s.kills)))
        card.first:SetText(opening(e.test and "(a test)" or (e.feed and "word from the field" or nil)))
    end
    card.buttons[2]:SetEnabled(not e.feed and not e.test) -- share only your own, real fights
    card.hasRollCalls = e.attendance ~= nil
    -- The roll calls beside the card follow it to another outing, and close for a battle without them.
    local open = KKC.RollCall.SideShown()
    if open and open ~= e then
        if card.hasRollCalls then KKC.RollCall.ShowSide(e, card) else KKC.RollCall.HideSide() end
    end
    card.rollButton:SetSelected(card.hasRollCalls and KKC.RollCall.SideShown() == e or false)
    card.hasHost = KKC.Host(e) ~= nil
    if not card.capturing then card.layoutButtons() end

    -- As many warriors as possible in one picture: 13 in one wide column (with TRP3 titles), 26 in two columns,
    -- 39 in three (names only). Past that the mouse wheel scrolls them.
    local members = {}
    for _, m in ipairs(KKC.sortedValues(e.members)) do if not m.outside then members[#members + 1] = m end end
    local many = s.members > ROWS
    local layouts = { card.wideRows, card.colRows, card.triRows }
    local use = s.members <= ROWS and 1 or (s.members <= 2 * ROWS and 2 or 3)
    for i, rows in ipairs(layouts) do if i ~= use then setRows(rows, {}, nil) end end
    local rows = layouts[use]
    local offset = math.max(0, math.min(card.memberOffset or 0, #members - #rows))
    card.memberOffset = offset
    local shown = {}
    for i = offset + 1, #members do shown[#shown + 1] = members[i] end
    local scrolls = #members > #rows
    card.membersHeader:SetText(("Warriors of the Kor'kron (%d)"):format(s.members)
        .. (s.alongside > 0 and (Theme.DIM .. ("   + %d outside our raid"):format(s.alongside) .. "|r") or "")
        .. (scrolls and (Theme.DIM .. ("   %d-%d, scroll for more"):format(offset + 1, offset + #rows - (#shown > #rows and 1 or 0)) .. "|r") or ""))
    setRows(rows, shown, function(m)
        local title = not many and KKC.rpTitle(m.name)
        local l = (title and (Theme.DIM .. title .. "|r ") or "") .. Theme.ClassLight(m.class) .. m.name .. "|r"
        -- Our deaths aren't shown on the card (they stay in the data for the summaries); the skull is for foes slain.
        if use == 3 then return l end
        local dmg = (m.dmg or 0) > 0 and KKC.shortNumber(m.dmg) or ""
        local mend = (m.heal or 0) > 0 and (Theme.LIGHT_MEND .. KKC.shortNumber(m.heal) .. " mend|r") or ""
        return l, dmg, mend
    end)

    -- The foes, tallied by race: how many, and how many times they fell.
    local tally = KKC.FoeTally(e)
    local foes = ("Foes of the %s (%d)"):format(UnitFactionGroup("player") or "Horde", s.enemies)
    -- Overlord's Nemeses among them (marked when the battle closed).
    local nemesis = KKC.Overlord and KKC.Overlord.NemesisText(e)
    if nemesis then foes = foes .. "  " .. SKULL .. " Nemesis: " .. nemesis end
    if many then
        local parts = {}
        for _, t in ipairs(tally) do parts[#parts + 1] = t.count .. " " .. t.label end
        card.enemiesHeader:SetText("")
        setRows(card.foeRows, {}, nil)
        card.foeRule:Show()
        card.foeLine:SetText("|cffffd100" .. foes .. ":|r " .. Theme.Foe() .. (#parts > 0 and table.concat(parts, ", ") or "unknown")
            .. "|r  ~  " .. slain(s.kills))
    else
        card.enemiesHeader:SetText(foes)
        card.foeLine:SetText("")
        card.foeRule:Hide()
        setRows(card.foeRows, tally, function(t)
            return Theme.Foe() .. t.count .. "|r  " .. Theme.LIGHT .. t.label .. "|r", nil,
                t.kills > 0 and (SKULL .. (t.kills > 1 and (" x" .. t.kills) or "")) or ""
        end)
    end

    if not card.desc:HasFocus() then card.desc:SetText(e.description or KKC.Report.Description(e)) end
end

function UI.ShowCard(e, keepScroll)
    if not e then return end
    card = card or buildCard()
    if not keepScroll or card.engagement ~= e then card.memberOffset = 0 end
    fillCard(e)
    card:Show()
end

KKC.Listen("EngagementUpdated", function(e)
    if card and card:IsShown() and card.engagement == e then fillCard(e) end
end)

-- A fight that just closed may have joined the campaign on the card.
KKC.Listen("EngagementClosed", function()
    if card and card:IsShown() and card.engagement and card.engagement.campaign then
        fillCard(KKC.Campaign.Refresh(card.engagement))
    end
end)

function UI.CopyReport(e)
    if not e then return end
    UI.ShowCopy(KKC.Report.CopyText(e, e.description), (e.campaign and KKC.Campaign.Name(e) or "Battle") .. " Report",
        "Ctrl+C, then paste it into the post (title: your main's name and surname, attach the card's likeness). Or post it in guild or officer chat for the Discord bridge.", e)
end

function UI.Share(e)
    if not e or e.feed or e.test or not KKC.settings().horn then return end -- the horn is off unless switched on
    local holder = e.campaign and e.anchor or e -- a campaign view is rebuilt each time; remember it on its first fight
    local key = e.campaign and "campaignShared" or "shared"
    if holder[key] then return KKC.say("the horn has already sounded for this " .. (e.campaign and "campaign." or "battle.")) end
    if UI.SendGuild(KKC.Report.ShareLine(e)) then holder[key] = true end
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

-- ------------------------------------------------------------------------------------------------
-- Posting a report to guild or officer chat, a line at a time
-- ------------------------------------------------------------------------------------------------

local LINE_GAP = 1.5 -- seconds between lines: no flood, and the bridge keeps them in order
local CHANNEL_NAME = { GUILD = "guild", OFFICER = "officer" }

local function postStep(p)
    local b = p.button
    if p.done then
        b:SetLabel("Posted")
    elseif p.manual then
        b:SetLabel(("Next line %d/%d"):format(p.i + 1, #p.lines))
    else
        b:SetLabel(("Posting %d/%d"):format(p.i, #p.lines))
    end
end

-- Sends the next line; times the one after unless the game made us go by clicks.
function UI.PostNext()
    local p = UI.posting
    if not p then return end
    if C_ChatInfo.InChatMessagingLockdown and KKC.try(C_ChatInfo.InChatMessagingLockdown) then
        -- Chat is silenced for a moment (an encounter): try again shortly.
        if not p.manual then C_Timer.After(LINE_GAP * 2, function() if UI.posting == p then UI.PostNext() end end) end
        return
    end
    p.i = p.i + 1
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    send(p.lines[p.i], p.channel)
    if p.i >= #p.lines then
        p.done = true
        UI.posting = nil
        local holder = p.engagement.campaign and p.engagement.anchor or p.engagement
        holder.posted = holder.posted or {}
        holder.posted[p.channel] = true
        KKC.say(("the report is posted in %s chat (%d lines)."):format(CHANNEL_NAME[p.channel], #p.lines))
    elseif not p.manual then
        C_Timer.After(LINE_GAP, function() if UI.posting == p and not p.manual then UI.PostNext() end end)
    end
    postStep(p)
end

-- If this client won't let a timer send chat, the line didn't go out: the rest go one per click.
local function onBlocked(culprit, func)
    local p = UI.posting
    if p and not p.manual and type(culprit) == "string" and culprit:find(ADDON, 1, true)
        and tostring(func):find("SendChatMessage", 1, true) then
        p.manual = true
        p.i = math.max(0, p.i - 1)
        postStep(p)
        KKC.say("the game wants a click for each line: press the button for the next one.")
    end
end
KKC.On("ADDON_ACTION_BLOCKED", onBlocked)
KKC.On("ADDON_ACTION_FORBIDDEN", onBlocked)

-- A click on Guild chat / Officer chat in the copy window: the first arms it, the second posts.
function UI.PostClick(b)
    local p, f = UI.posting, copyFrame
    if p then
        if p.button == b and p.manual then return UI.PostNext() end
        return KKC.say("still posting the last report.")
    end
    if not (f and f.post and f.lines and #f.lines > 0) then return end
    if not IsInGuild() then return KKC.say("you march with no guild.") end
    if not b.armed then
        local holder = f.post.campaign and f.post.anchor or f.post
        local again = holder.posted and holder.posted[b.channel]
        b.armed = true
        b:SetLabel((again and "Again? %d lines" or "Post %d lines?"):format(#f.lines))
        C_Timer.After(4, function()
            if b.armed then b.armed = nil; b:SetLabel(b.baseLabel) end
        end)
        return
    end
    b.armed = nil
    UI.posting = { lines = f.lines, i = 0, channel = b.channel, button = b, engagement = f.post }
    UI.PostNext() -- the first line goes with the click itself
end

-- ------------------------------------------------------------------------------------------------
-- Synchronization report: every raid of the guild at one battle (guild sync)
-- ------------------------------------------------------------------------------------------------

local hostFrame
function UI.ShowHost(e)
    local text = KKC.HostText(e, true)
    if not text then return KKC.say("no other raid reported this battle (that needs guild sync and the addon in each raid).") end
    if not hostFrame then
        local f = panel("KorKronCompanionHost", 560, 600, nil, "sheet")
        f:SetPoint("CENTER", 0, 20)
        f:SetFrameStrata("FULLSCREEN_DIALOG") -- above the battle card it was opened from
        f.heading = Theme.SheetTitle(f, 22, "CENTER")
        f.heading:SetPoint("TOP", 0, -32)
        f.sub = Theme.SheetText(f, 12, "CENTER")
        f.sub:SetPoint("TOP", f.heading, "BOTTOM", 0, -6)
        f.sub:SetWidth(470)
        local box = Theme.SheetPanel(f)
        box:SetPoint("TOPLEFT", 36, -96)
        box:SetPoint("BOTTOMRIGHT", -36, 72)
        local scroll = CreateFrame("ScrollFrame", "KorKronCompanionHostScroll", box, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 10, -10)
        scroll:SetPoint("BOTTOMRIGHT", -30, 10)
        local body = CreateFrame("Frame", nil, scroll)
        body:SetSize(440, 10)
        scroll:SetScrollChild(body)
        f.text = Theme.SheetText(body, 13)
        f.text:SetPoint("TOPLEFT")
        f.text:SetWidth(440)
        f.text:SetSpacing(3)
        f.body = body
        local copy = Theme.HallButton(f, "Copy text", 160, 32, nil, "The synchronization report as text, to paste where the guild keeps its stats.",
            function() if f.engagement then
                UI.ShowCopy((KKC.HostText(f.engagement, false)), f.heading:GetText(), "Ctrl+C, then paste it wherever the guild keeps its tallies.")
            end end)
        copy.kkSheet = true
        copy:SetSelected(false)
        copy:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 30)
        local done = Theme.HallButton(f, "Close", 160, 32, nil, nil, function() f:Hide() end)
        done.kkSheet = true
        done:SetSelected(false)
        done:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 30)
        hostFrame = f
    end
    local f = hostFrame
    f.engagement = e
    f.heading:SetText(e.campaign and "Campaign Synchronization Report" or "Battle Synchronization Report")
    f.sub:SetText(Theme.DIM .. "Every raid of the guild at this battle, from their guildies' addons. Your battle report stays your own raid's.|r")
    f.text:SetText(text)
    f.body:SetHeight(math.max(10, (f.text:GetStringHeight() or 0) + 10))
    f:Show()
end

-- Hide the buttons for a few seconds so a Print Screen shows only the card. Addons may not take screenshots
-- themselves on this client (calling Screenshot() was blocked), but the player's own key press always works.
local CAPTURE_SECONDS = 5

function UI.Screenshot()
    if not card or card.capturing then return end
    card.capturing = true
    for _, b in ipairs(card.buttons) do b:Hide() end
    card.close:Hide()
    card.desc:ClearFocus()
    card.hint:SetText(Theme.DIM .. "Press Print Screen now|r")
    card.hint:Show()
    -- The hint itself would show in the picture: fade it out before the player presses the key.
    C_Timer.After(1.2, function() card.hint:Hide() end)
    C_Timer.After(CAPTURE_SECONDS, function()
        card.layoutButtons()
        card.close:Show()
        card.capturing = false
    end)
end

KKC.On("SCREENSHOT_SUCCEEDED", function()
    if card and card.capturing then KKC.say("the likeness is captured (Screenshots folder of the game).") end
end)

-- The day / week / month summaries live in the Hall of the Kor'kron now (Hub.lua).
-- tab: "mine" | "guild", period: "day" | "week" | "lastweek" | "month" | "lastmonth" | "all"
function UI.ShowSummary(tab, period)
    KKC.Hub.Show(tab == "guild" and "field" or "chronicle", period)
end

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
    if not Theme.Atlas(icon, Theme.F().emblem) then icon:SetTexture(Theme.F().icon) end
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
    toast.title:SetText(Theme.BLOOD .. "Blood has been spilled|r")
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

-- Who is told of a battle (unless everyone is, settings.promptAll): in a raid, its leader, who writes the report; outside
-- a raid (alone or a party of up to five), whoever fought, since nobody else will. (Being first into battle was the
-- rule, but with patient guild sync the other reports come minutes later, so everyone thought they were first.)
function UI.Told(e)
    if (e.groupSize or 0) <= 5 or not e.raidLeader then return true end
    return e.raidLeader == KKC.me()
end

function UI.Notify(e, force)
    if not e or e.notified then return end
    if not e.test then e.minor = not KKC.IsNotable(e) end
    local set = KKC.settings()
    if not force then
        if e.minor or set.notify == "off" then return end
        if not set.promptAll and not UI.Told(e) then return end
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
