--[[
  Roll calls: who of the guild is in your party or raid, taken every 10 minutes while you're in a group (and when a
  fight starts and ends). Officers asked for a raid-panel screenshot about every 50 minutes as proof of who was there;
  this is the same record, taken more often and stricter: a guildmate only counts as present when online and in your
  zone (the raid panel can't tell someone fighting in Hillsbrad from someone idling in Orgrimmar).

  Stored newest first in KKC.db.rollcalls:
    { t, zone, raid, size, others, present = { [name] = class }, away = { [name] = "Orgrimmar" | "offline" }, shot }
  shot: a screenshot was taken while the roll call sheet was open. A guildmate missing who was present at the roll call
  before gets a second look 90 seconds later: leaving the raid for a moment and rejoining doesn't count as absent.

    RollCall.Take(manual)      record one now (manual: always, even right after the last one)
    RollCall.For(e)            the roll calls during an engagement or campaign view (oldest first)
    RollCall.Attendance(e)     { calls, names = { [name] = { name, class, count, first, last, share } } } or nil
    RollCall.ShowSheet()       a roll call now, on a sheet beside the raid panel, ready for Print Screen
]]

local _, KKC = ...
local RollCall = {}
KKC.RollCall = RollCall

local INTERVAL = 600     -- seconds between roll calls while in a group
local MIN_GAP = 120      -- a fight starting or ending takes one too, but not closer than this to the last
local RECHECK = 90       -- seconds: someone missing who was there last time gets a second look (left and rejoined)
local BEFORE, AFTER = 600, 300 -- roll calls this long before a battle's start and after its end still belong to it
local KEEP = { days = 120, max = 3000 }

local function list() return KKC.db.rollcalls end

local function inWorld()
    local _, kind = IsInInstance()
    return kind == nil or kind == "none"
end

-- Where a group member is: (zone name or nil when unknown, online or nil when unknown).
local function placeOf(unit, raidIndex)
    if raidIndex and GetRaidRosterInfo then
        local name, _, _, _, _, _, zone, online = KKC.try(GetRaidRosterInfo, raidIndex)
        if name ~= nil then
            local known = nil -- true / false / nil (unknown); "x and false or nil" would always give nil
            if KKC.readable(online) then known = online and true or false end
            return KKC.readable(zone) and zone or nil, known
        end
    end
    local connected, online = KKC.try(UnitIsConnected, unit), nil
    if KKC.readable(connected) then online = connected and true or false end
    -- A party member's map against ours: the same map means the same zone.
    local M = C_Map
    if M and M.GetBestMapForUnit then
        local theirs, mine = KKC.try(M.GetBestMapForUnit, unit), KKC.try(M.GetBestMapForUnit, "player")
        if KKC.readable(theirs) and KKC.readable(mine) and theirs and mine then
            return theirs == mine and GetRealZoneText() or "elsewhere", online
        end
    end
    return nil, online
end

-- One roll call of the group as it is now. Nil when solo or inside an instance.
function RollCall.Snapshot()
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if n == 0 or not inWorld() then return nil end
    local raid = IsInRaid()
    local here = GetRealZoneText and GetRealZoneText() or nil
    local call = { t = KKC.now(), zone = here, raid = raid or nil, size = n, others = 0, present = {}, away = {} }
    local me = KKC.me()
    if me then call.present[me] = KKC.myClass() or true end
    local last = raid and n or (n - 1)
    for i = 1, math.max(last, 0) do
        local unit = (raid and "raid" or "party") .. i
        local name = KKC.unitName(unit)
        if name and name ~= me then
            local zone, online = placeOf(unit, raid and i or nil)
            local inGuild = KKC.try(UnitIsInMyGuild, unit)
            if KKC.readable(inGuild) and inGuild then
                if online == false then
                    call.away[name] = "offline"
                elseif zone and here and zone ~= here then
                    call.away[name] = zone
                else
                    local _, class = KKC.try(UnitClass, unit)
                    call.present[name] = KKC.readable(class) and class or true
                end
            elseif online ~= false then
                call.others = call.others + 1
            end
        end
    end
    return call
end

local lastTaken = 0

function RollCall.Take(manual)
    if not KKC.db then return end
    local now = KKC.now()
    if not manual and now - lastTaken < MIN_GAP then return end
    local call = RollCall.Snapshot()
    if not call then return end
    lastTaken = now
    local calls = list()
    table.insert(calls, 1, call)
    -- Someone who was present last time and isn't now may only have dropped out of the raid for a moment (to invite,
    -- to reset an instance, a disconnect): look again shortly, and whoever is back by then counts as present.
    local missing = {}
    for name in pairs(calls[2] and calls[2].present or {}) do
        if not call.present[name] then missing[name] = true end
    end
    if next(missing) and C_Timer then
        call.recheck = true
        C_Timer.After(RECHECK, function()
            local again = RollCall.Snapshot()
            for name in pairs(missing) do
                if again and again.present[name] then call.present[name], call.away[name] = again.present[name], nil end
            end
            call.recheck = nil
        end)
    end
    local oldest = now - KEEP.days * 86400
    while #calls > KEEP.max or (#calls > 0 and calls[#calls].t < oldest) do table.remove(calls) end
    KKC.Fire("RollCall", call)
    return call
end

-- Every 10 minutes while in a group. Checked each minute so joining a group starts the clock soon after.
local function tick()
    if KKC.db and KKC.settings().rollcalls ~= false and (GetNumGroupMembers() or 0) > 0 and KKC.now() - lastTaken >= INTERVAL then
        local call = RollCall.Take(false)
        -- One quiet chat line, so a raid-panel screenshot taken now lines up with the record.
        if call and call.raid and KKC.settings().notify ~= "off" then
            KKC.say(("roll call %s: %d of the guild present%s."):format(date("%H:%M", call.t), KKC.count(call.present),
                KKC.count(call.away) > 0 and (", " .. KKC.count(call.away) .. " away") or ""))
        end
    end
    C_Timer.After(60, tick)
end

KKC.Listen("Init", function()
    KKC.db.rollcalls = KKC.db.rollcalls or {}
    if C_Timer then C_Timer.After(60, tick) end
end)
KKC.On("PLAYER_REGEN_DISABLED", function() if KKC.db then RollCall.Take(false) end end)
KKC.Listen("EngagementClosed", function() RollCall.Take(false) end)

-- ------------------------------------------------------------------------------------------------
-- Attendance
-- ------------------------------------------------------------------------------------------------

function RollCall.For(e)
    local out = {}
    if not (e and e.start and KKC.db and KKC.db.rollcalls) then return out end
    local from, to = e.start - BEFORE, (e.stop or e.start) + AFTER
    for i = #KKC.db.rollcalls, 1, -1 do -- oldest first
        local c = KKC.db.rollcalls[i]
        if c.t >= from and c.t <= to then out[#out + 1] = c end
    end
    return out
end

-- Who was present at how many of the roll calls. share: 0-1.
function RollCall.Attendance(e)
    if e.feed then return nil end -- a guildie's fight: their roll calls aren't ours
    local calls = RollCall.For(e)
    if #calls == 0 then return nil end
    local names = {}
    for _, c in ipairs(calls) do
        for name, class in pairs(c.present) do
            local a = names[name] or { name = name, count = 0, first = c.t }
            names[name] = a
            a.count, a.last = a.count + 1, c.t
            if type(class) == "string" then a.class = class end
        end
    end
    for _, a in pairs(names) do a.share = a.count / #calls end
    return { calls = calls, names = names }
end

-- "100%", "67%"
function RollCall.Share(a) return ("%d%%"):format(math.floor(a.share * 100 + 0.5)) end

-- Present guildmates by attendance: most roll calls first, then by name.
function RollCall.Ranked(att)
    return KKC.sortedValues(att.names, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
end

-- ------------------------------------------------------------------------------------------------
-- The roll call sheet: a roll call now, beside the raid panel, for a Print Screen
-- ------------------------------------------------------------------------------------------------

local sheet
local function buildSheet()
    local Theme = KKC.Theme
    local f = CreateFrame("Frame", "KorKronCompanionRollCall", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(420, 520)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetPoint("LEFT", UIParent, "LEFT", 440, 0) -- right of the raid panel
    tinsert(UISpecialFrames, "KorKronCompanionRollCall")
    f.banner = Theme.SheetFrame(f, "Roll Call")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -18, -18)
    close:SetFrameLevel(f:GetFrameLevel() + 10)
    close:SetScript("OnClick", function() f:Hide() end)
    f.close = close
    f.when = Theme.SheetText(f, 14, "CENTER")
    f.when:SetPoint("TOP", 0, -62)
    f.where = Theme.SheetText(f, 13, "CENTER")
    f.where:SetPoint("TOP", f.when, "BOTTOM", 0, -4)
    local rule = Theme.Rule(f, 340, true)
    rule:SetPoint("TOP", f.where, "BOTTOM", 0, -10)
    f.head = Theme.SheetTitle(f, 17)
    f.head:SetPoint("TOPLEFT", 36, -124)
    f.names = {}
    for i = 1, 40 do
        local fs = Theme.SheetText(f, 12)
        fs:SetWidth(170)
        fs:SetWordWrap(false)
        fs:SetPoint("TOPLEFT", 36 + math.floor((i - 1) / 20) * 180, -150 - ((i - 1) % 20) * 15)
        f.names[i] = fs
    end
    f.away = Theme.SheetText(f, 12)
    f.away:SetPoint("BOTTOMLEFT", 36, 58)
    f.away:SetPoint("RIGHT", -36, 0)
    f.away:SetWordWrap(true)
    f.hint = Theme.SheetText(f, 13, "CENTER")
    f.hint:SetPoint("BOTTOM", 0, 32)
    f:Hide()
    f:SetScript("OnHide", function() f.waiting = nil end)
    return f
end

local function fillSheet(call)
    local Theme = KKC.Theme
    sheet.call = call
    sheet.when:SetText(date("%A %d %B %Y, %H:%M", call.t))
    sheet.where:SetText(Theme.DIM .. (call.zone or "?") .. "  ~  " .. (call.raid and "raid" or "party") .. " of " .. call.size
        .. (call.others > 0 and (", " .. call.others .. " from outside the guild") or "") .. "|r")
    local names = {}
    for name, class in pairs(call.present) do names[#names + 1] = { name = name, class = type(class) == "string" and class or nil } end
    table.sort(names, function(a, b) return a.name < b.name end)
    sheet.head:SetText(("Present of the guild (%d)"):format(#names))
    for i, fs in ipairs(sheet.names) do
        local n = names[i]
        if i == #sheet.names and #names > #sheet.names then
            fs:SetText(Theme.DIM .. ("and %d more"):format(#names - i + 1) .. "|r")
        else
            fs:SetText(n and (Theme.ClassLight(n.class) .. n.name .. "|r") or "")
        end
    end
    local away = {}
    for name, where in pairs(call.away) do away[#away + 1] = name .. " (" .. where .. ")" end
    table.sort(away)
    sheet.away:SetText(#away > 0 and (Theme.DIM .. "Away: |r" .. table.concat(away, ", ")) or "")
end

-- The game's own raid panel, when the client lets an addon open it (never in combat).
local function openRaidPanel()
    if InCombatLockdown() then return false end
    if RaidFrame and RaidFrame.IsShown and RaidFrame:IsShown() then return true end
    if ToggleRaidFrame then return pcall(ToggleRaidFrame) end
    if ToggleFriendsFrame then return pcall(ToggleFriendsFrame, 3) end
    return false
end

function RollCall.ShowSheet()
    local call = RollCall.Take(true)
    if not call then return KKC.say("a roll call needs a party or raid (and not inside an instance).") end
    sheet = sheet or buildSheet()
    fillSheet(call)
    local opened = openRaidPanel()
    sheet.hint:SetText(KKC.Theme.DIM .. (opened and "Press Print Screen now" or "Open the raid panel, then press Print Screen") .. "|r")
    sheet.hint:Show()
    sheet.close:Hide() -- out of the picture; Esc or a click on the sheet's X after the screenshot closes it
    sheet.waiting = true
    sheet:Show()
    C_Timer.After(1.5, function() if sheet.waiting then sheet.hint:Hide() end end)
    C_Timer.After(20, function() if sheet:IsShown() then sheet.close:Show() end end)
end

KKC.On("SCREENSHOT_SUCCEEDED", function()
    if not (sheet and sheet:IsShown() and sheet.waiting) then return end
    sheet.waiting = nil
    sheet.call.shot = true
    sheet.close:Show()
    KKC.say(("roll call %s saved with its screenshot (Screenshots folder of the game)."):format(date("%H:%M", sheet.call.t)))
end)
