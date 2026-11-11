--[[
  Engagement tracking without the combat log (addons can't read it on Forever).

  Segment     = one stretch of combat (PLAYER_REGEN_DISABLED -> PLAYER_REGEN_ENABLED).
  Engagement  = PvP segments merged while the gap between them stays under settings.mergeGap.

  Sources:
    - honor kill messages (CHAT_MSG_COMBAT_HONOR_GAIN): who died with honor credit
    - target / focus during combat: enemy players you went for
    - the built-in damage meter, read 1 s after combat ends (it is secret while in combat): enemy players damaged,
      damage and healing per ally, deaths
    - target / mouseover / nameplates at any time: race, class, guild and level for names we see later
]]

local _, KKC = ...
local T = {}
KKC.Tracker = T

local seg        -- open combat segment
local lastSeg    -- the segment that just ended, until its meter read is done
local eng        -- open engagement
local closeTimer

-- ------------------------------------------------------------------------------------------------
-- Honor kill messages
-- ------------------------------------------------------------------------------------------------

-- "%s dies (Honorable Kill: %s). You gain %d Honor." -> "^(.-) dies %(Honorable Kill: (.-)%)%. You gain (%d+) Honor%.$"
local function toPattern(fmt)
    fmt = fmt:gsub("%%%d?%$?s", "\1"):gsub("%%%d?%$?d", "\2")
    fmt = fmt:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    fmt = fmt:gsub("\1", "(.-)"):gsub("\2", "(%%d+)")
    return "^" .. fmt .. "$"
end

local honorPatterns
local function getHonorPatterns()
    if not honorPatterns then
        honorPatterns = {}
        -- Longest first, so the plain form doesn't swallow the bonus forms.
        for _, key in ipairs({ "COMBATLOG_HONORGAIN_EXHAUSTION1", "COMBATLOG_HONORGAIN_NO_RANK_EXHAUSTION1",
                               "COMBATLOG_HONORGAIN", "COMBATLOG_HONORGAIN_NO_RANK" }) do
            if type(_G[key]) == "string" then honorPatterns[#honorPatterns + 1] = toPattern(_G[key]) end
        end
    end
    return honorPatterns
end

function T.HonorPatternCount() return #getHonorPatterns() end

function T.ParseHonor(text)
    if not KKC.readable(text) or type(text) ~= "string" then return nil end
    for _, p in ipairs(getHonorPatterns()) do
        local victim = text:match(p)
        if victim and victim ~= "" then
            KKC.raw.honor = victim
            return KKC.short(victim) or victim
        end
    end
end

-- ------------------------------------------------------------------------------------------------
-- What we know about enemy players we have seen (any time), by name
-- ------------------------------------------------------------------------------------------------

local seen, seenCount = {}, 0

-- GUID -> full name ("First Surname") of players seen on a unit or in the meter. Kill events only give a GUID, and
-- on Forever the name the client gives for a GUID is the first name alone, so kills are named through this.
local guidNames, guidCount = {}, 0
local function noteGUID(guid, name)
    if not (KKC.readable(guid) and type(guid) == "string" and name) then return end
    if not guidNames[guid] then
        if guidCount > 1000 then guidNames, guidCount = {}, 0 end
        guidCount = guidCount + 1
    end
    guidNames[guid] = name
end

local function remember(unit)
    local isPlayer = KKC.try(UnitIsPlayer, unit)
    local canAttack = KKC.try(UnitCanAttack, "player", unit)
    if not (KKC.readable(isPlayer) and isPlayer and KKC.readable(canAttack) and canAttack) then return end
    local name = KKC.unitName(unit)
    if not name then return end
    noteGUID(KKC.try(UnitGUID, unit), name)
    local info = seen[name]
    if not info then
        if seenCount > 500 then seen, seenCount = {}, 0 end
        info = {}
        seen[name] = info
        seenCount = seenCount + 1
    end
    local race = KKC.try(UnitRace, unit)
    if KKC.readable(race) then info.race = race end
    local _, class = KKC.try(UnitClass, unit)
    if KKC.readable(class) then info.class = class end
    local level = KKC.try(UnitLevel, unit)
    if KKC.readable(level) then info.level = level end
    local guild = KKC.try(GetGuildInfo, unit)
    if KKC.readable(guild) then info.guild = guild end
    return name
end

local function enrich(en)
    local info = seen[en.name]
    if not info then return end
    en.race = en.race or info.race
    en.class = en.class or info.class
    en.level = en.level or info.level
    en.guild = en.guild or info.guild
end

-- ------------------------------------------------------------------------------------------------
-- Segments
-- ------------------------------------------------------------------------------------------------

local function newSegment()
    local _, instanceType = IsInInstance()
    return {
        start = KKC.now(), enemies = {}, allies = {}, hk = {}, meterDeaths = {}, pvp = false,
        pk = {}, myPk = {}, unnamedKills = 0, -- killing blows by name (the group's, yours) and unnamed ones
        kills = {},                           -- PARTY_KILL as it came: { guid, name, mine }, named after the meter read
        -- World PvP only: battlegrounds, arenas and dungeons are ignored.
        skip = instanceType ~= nil and instanceType ~= "none",
    }
end

-- Map and position (0-1 map coordinates, 3 decimals) for later statistics such as a heatmap. Nil parts when hidden.
local function where()
    local M = C_Map
    if not M then return end
    local map = KKC.try(M.GetBestMapForUnit, "player")
    if not (KKC.readable(map) and type(map) == "number") then return end
    local pos = KKC.try(M.GetPlayerMapPosition, map, "player")
    local x, y
    if pos and KKC.readable(pos) and pos.GetXY then x, y = KKC.try(pos.GetXY, pos) end
    if KKC.readable(x) and KKC.readable(y) and type(x) == "number" and type(y) == "number" then
        return map, math.floor(x * 1000 + 0.5) / 1000, math.floor(y * 1000 + 0.5) / 1000
    end
    return map
end

-- Did we open the fight? An attack, auto shot or cast while targeting an enemy player just before combat starts
-- means we struck first; entering combat without one means they hit us (an ambush).
local OPEN_WINDOW = 5
local lastOffense = -100

local function noteOffense()
    local isPlayer = KKC.try(UnitIsPlayer, "target")
    local canAttack = KKC.try(UnitCanAttack, "player", "target")
    if KKC.readable(isPlayer) and isPlayer and KKC.readable(canAttack) and canAttack then lastOffense = GetTime() end
end

local function enemyOf(s, name)
    local en = s.enemies[name]
    if not en then
        en = { name = name, kills = 0 }
        s.enemies[name] = en
    end
    return en
end

local function allyOf(s, name)
    local a = s.allies[name]
    if not a then
        a = { name = name }
        s.allies[name] = a
    end
    return a
end

local function isPlayerGUID(guid)
    return KKC.readable(guid) and type(guid) == "string" and guid:find("^Player%-") ~= nil
end

-- "leader", "assist" or nil: the unit's role in leading the party or raid.
local function leadRole(unit)
    local lead = KKC.try(UnitIsGroupLeader, unit)
    if KKC.readable(lead) and lead then return "leader" end
    local assist = KKC.try(UnitIsGroupAssistant, unit)
    if KKC.readable(assist) and assist then return "assist" end
end

-- Who is in your party or raid right now: guild membership, class and lead role per name. Empty when solo.
local function groupInfo()
    local info = {}
    local raid = IsInRaid()
    local n = GetNumGroupMembers() or 0
    local last = raid and n or (n - 1)
    for i = 1, math.max(last, 0) do
        local unit = (raid and "raid" or "party") .. i
        local name = KKC.unitName(unit)
        if name then
            local inGuild = KKC.try(UnitIsInMyGuild, unit)
            local _, class = KKC.try(UnitClass, unit)
            info[name] = { guild = KKC.readable(inGuild) and inGuild or false, class = KKC.readable(class) and class or nil,
                lead = leadRole(unit) }
        end
    end
    -- In a party the units above don't include you; in a raid they do.
    local me = KKC.me()
    if n > 0 and me and not info[me] then info[me] = { guild = true, class = KKC.myClass(), lead = leadRole("player") } end
    return info
end

-- The built-in meter's current session, one list per meter type. Nil when it isn't available or still secret.
local function meterSources(kind)
    local DM = C_DamageMeter
    if not (DM and Enum and Enum.DamageMeterSessionType and Enum.DamageMeterType and Enum.DamageMeterType[kind]) then return nil end
    local session = KKC.try(DM.GetCombatSessionFromType, Enum.DamageMeterSessionType.Current, Enum.DamageMeterType[kind])
    if not KKC.readableTable(session) or not KKC.readableTable(session.combatSources) then return nil end
    return session.combatSources
end

local function readMeter(s)
    local myFaction = UnitFactionGroup("player")
    local me = KKC.me()

    -- Enemy players your side damaged.
    for _, src in ipairs(meterSources("EnemyDamageTaken") or {}) do
        if KKC.readableTable(src) and isPlayerGUID(src.sourceGUID) and KKC.readable(src.name) then
            KKC.raw.meter = src.name
            local name = KKC.short(src.name)
            noteGUID(src.sourceGUID, name)
            local faction = KKC.readable(src.factionGroup) and src.factionGroup or nil
            if name and name ~= me and faction ~= myFaction and not (s.group and s.group[name]) then
                local en = enemyOf(s, name)
                if KKC.readable(src.classFilename) then en.class = src.classFilename end
                local _, _, race = KKC.try(GetPlayerInfoByGUID, src.sourceGUID)
                if KKC.readable(race) and race then en.race = race end
                s.pvp = true
                s.meterRead = true
            end
        end
    end

    -- Damage and healing per ally (you and your group).
    for kind, field in pairs({ DamageDone = "dmg", HealingDone = "heal" }) do
        for _, src in ipairs(meterSources(kind) or {}) do
            if KKC.readableTable(src) and KKC.readable(src.name) and (src.isLocalPlayer or isPlayerGUID(src.sourceGUID)) then
                local name = src.isLocalPlayer and me or KKC.short(src.name)
                if name and not s.enemies[name] then
                    local a = allyOf(s, name)
                    if KKC.readable(src.classFilename) then a.class = src.classFilename end
                    if KKC.readable(src.totalAmount) then a[field] = (a[field] or 0) + (tonumber(src.totalAmount) or 0) end
                    s.meterRead = true
                end
            end
        end
    end

    -- Deaths: enemies count as slain (when the honor message didn't say so), allies as fallen.
    for _, src in ipairs(meterSources("Deaths") or {}) do
        if KKC.readableTable(src) and KKC.readable(src.name) then
            local name = src.isLocalPlayer and me or KKC.short(src.name)
            if name and s.enemies[name] then
                s.meterDeaths[name] = (s.meterDeaths[name] or 0) + 1
            elseif name and (name == me or (s.group and s.group[name])) then
                allyOf(s, name).died = true
            end
        end
    end
end

-- ------------------------------------------------------------------------------------------------
-- Engagements
-- ------------------------------------------------------------------------------------------------

local function memberOf(e, name)
    local m = e.members[name]
    if not m then
        m = { name = name }
        e.members[name] = m
    end
    return m
end

local function newEngagement(start)
    local me = KKC.me()
    return {
        id = me .. "-" .. start, owner = me, start = start, stop = start,
        zone = GetRealZoneText() or "", subzone = GetSubZoneText() or "",
        pvpSeconds = 0, allies = 0,
        enemies = {}, members = {}, ownKills = {}, reports = {},
    }
end

local function scheduleClose()
    if closeTimer then closeTimer:Cancel() end
    closeTimer = C_Timer.NewTimer(KKC.settings().mergeGap, function()
        closeTimer = nil
        if seg then return scheduleClose() end -- fighting again (PvE or not): wait until it's over
        T.CloseEngagement()
    end)
end

function T.CloseEngagement()
    local e = eng
    if not e then return end
    eng = nil
    if closeTimer then closeTimer:Cancel(); closeTimer = nil end
    e.minor = not KKC.IsNotable(e)
    table.insert(KKC.db.log, 1, e)
    KKC.Prune(KKC.db.log, "log")
    KKC.Ledger.Record(e)
    KKC.Fire("EngagementClosed", e)
end

local function addToEngagement(s)
    if eng and s.start - eng.stop > KKC.settings().mergeGap then T.CloseEngagement() end
    if not eng then
        eng = newEngagement(s.start)
        -- The first segment says who struck first and where it happened.
        eng.opened, eng.map, eng.x, eng.y = s.opened, s.map, s.x, s.y
    end
    local e = eng
    e.stop = math.max(e.stop, s.stop or s.start)
    e.pvpSeconds = e.pvpSeconds + math.max(1, (s.stop or s.start) - s.start)

    for name, en in pairs(s.enemies) do
        local target = e.enemies[name] or { name = name, kills = 0 }
        e.enemies[name] = target
        target.class = target.class or en.class
        target.race = target.race or en.race
        -- The same death can come from several sources: count it once.
        target.kills = target.kills + math.max(s.hk[name] or 0, s.pk[name] or 0, s.meterDeaths[name] or 0)
        enrich(target)
    end
    local own = {}
    for name, n in pairs(s.hk) do own[name] = n end
    for name, n in pairs(s.myPk) do own[name] = math.max(own[name] or 0, n) end
    for name, n in pairs(own) do e.ownKills[name] = (e.ownKills[name] or 0) + n end
    e.unnamedKills = (e.unnamedKills or 0) + s.unnamedKills

    local me = KKC.me()
    local mine = memberOf(e, me)
    mine.class, mine.reported = KKC.myClass(), true
    if s.selfDied then mine.died = true end

    local others = 0
    for name, a in pairs(s.allies) do
        local g = s.group and s.group[name]
        if name == me or (g and g.guild) then
            local m = memberOf(e, name)
            m.class = m.class or a.class or (g and g.class)
            m.dmg = (m.dmg or 0) + (a.dmg or 0)
            m.heal = (m.heal or 0) + (a.heal or 0)
            if a.died then m.died = true end
        end
    end
    -- Everyone of the guild in the party or raid fought, near you or not: the meter only sees what happens close to
    -- you, so a guildie at the far end of the camp would otherwise drop off the report. Others are only counted.
    for name, g in pairs(s.group or {}) do
        if g.guild or name == me then
            local m = memberOf(e, name)
            m.class = m.class or g.class
        else
            others = others + 1
        end
    end
    e.allies = math.max(e.allies or 0, others)

    -- Who led the group in any of the engagement's fights. A leader stays a leader even if they handed it on.
    for name, g in pairs(s.group or {}) do
        if g.lead then
            e.leaders = e.leaders or {}
            if e.leaders[name] ~= "leader" then e.leaders[name] = g.lead end
        end
    end

    scheduleClose()
    KKC.Fire("EngagementUpdated", e)
end

-- The name the client gives for a GUID (on Forever the first name alone), cleaned.
local function victimName(guid)
    if not isPlayerGUID(guid) then return nil end
    if guidNames[guid] then return guidNames[guid] end
    local name = UnitNameFromGUID and KKC.try(UnitNameFromGUID, guid)
    if not (KKC.readable(name) and type(name) == "string" and name ~= "" and name ~= UNKNOWNOBJECT) then
        name = select(6, KKC.try(GetPlayerInfoByGUID, guid))
    end
    if KKC.readable(name) and type(name) == "string" and name ~= "" and name ~= UNKNOWNOBJECT then
        KKC.raw.kill = name
        return KKC.short(name)
    end
end

-- The full name a killing blow's victim goes by in this segment: the GUID seen on a unit or in the meter, else the
-- one enemy whose name starts with the first name the client gave ("Morgan" -> "Morgan Ashford"), else that name.
local function fullName(s, guid)
    local name = guidNames[guid]
    if name then return name end
    local first = victimName(guid)
    if not first then return nil end
    local match
    for known in pairs(s.enemies) do
        if known == first then return known end
        if known:sub(1, #first + 1) == first .. " " then
            if match then return first end -- two "Morgan ..." in the fight: can't tell which
            match = known
        end
    end
    return match or first
end

local function nameKills(s)
    for _, k in ipairs(s.kills) do
        local name = k.guid and fullName(s, k.guid)
        if name then
            local en = enemyOf(s, name)
            local _, class, race = KKC.try(GetPlayerInfoByGUID, k.guid)
            if KKC.readable(class) and class then en.class = en.class or class end
            if KKC.readable(race) and race then en.race = en.race or race end -- the display name ("Night Elf")
            s.pk[name] = (s.pk[name] or 0) + 1
            if k.mine then s.myPk[name] = (s.myPk[name] or 0) + 1 end
        else
            s.unnamedKills = s.unnamedKills + 1
        end
    end
end

local function finishSegment(s)
    if s.finished then return end
    s.finished = true
    if lastSeg == s then lastSeg = nil end
    if s.skip then return end
    s.group = groupInfo()
    pcall(readMeter, s)
    pcall(nameKills, s)
    if s.pvp then addToEngagement(s) end
end

-- ------------------------------------------------------------------------------------------------
-- Events
-- ------------------------------------------------------------------------------------------------

KKC.On("PLAYER_REGEN_DISABLED", function()
    if seg then return end
    seg = newSegment()
    seg.opened = GetTime() - lastOffense <= OPEN_WINDOW
    seg.map, seg.x, seg.y = where()
end)

KKC.On("PLAYER_ENTER_COMBAT", noteOffense)     -- auto attack on
KKC.On("START_AUTOREPEAT_SPELL", noteOffense)  -- auto shot / wand
KKC.On("UNIT_SPELLCAST_SENT", function(unit) if unit == "player" then noteOffense() end end)

KKC.On("PLAYER_REGEN_ENABLED", function()
    local s = seg
    seg = nil
    if not s then return end
    s.stop = KKC.now()
    if lastSeg then finishSegment(lastSeg) end
    lastSeg = s
    C_Timer.After(1, function() finishSegment(s) end) -- the meter stops being secret once we're out of combat
end)

-- The segment a late event belongs to: the open one, or the one that just ended.
local function activeSegment() return seg or lastSeg end

KKC.On("CHAT_MSG_COMBAT_HONOR_GAIN", function(text)
    local victim = T.ParseHonor(text)
    if not victim then return end
    remember("target") -- often the victim; fills race/class while it's still targeted
    local s = activeSegment()
    if s then
        enemyOf(s, victim)
        s.hk[victim] = (s.hk[victim] or 0) + 1
        s.pvp = true
    else
        -- A kill out of combat (a DoT finishing them, say): a one-moment segment of its own.
        s = newSegment()
        s.stop = s.start
        enemyOf(s, victim)
        s.hk[victim] = 1
        s.pvp = true
        finishSegment(s)
    end
end)

-- Killing blows by you or your group on enemy players. On this client the honor message is unreliable for
-- addons (Overlord found the same), so PARTY_KILL (attackerGUID, targetGUID) is the main source of kills. Either GUID
-- can be secret: a kill whose victim can't be named still counts towards the slain total.
KKC.On("PARTY_KILL", function(attacker, target)
    if KKC.readable(target) and not isPlayerGUID(target) then return end -- an NPC
    local mine = KKC.readable(attacker) and attacker == KKC.try(UnitGUID, "player")
    local s = activeSegment()
    local lone = not s
    if lone then s = newSegment(); s.stop = s.start end -- a kill out of combat: a one-moment segment of its own
    s.pvp = true
    -- Named when the segment ends: by then the meter has told us the victim's full name.
    s.kills[#s.kills + 1] = { guid = KKC.readable(target) and target or nil, mine = mine }
    if lone then finishSegment(s) end
end)

KKC.On("PLAYER_DEAD", function()
    local s = activeSegment()
    if s then
        s.selfDied = true
    elseif eng then
        memberOf(eng, KKC.me()).died = true
    end
end)

-- Enemy players you target or focus during combat take part in the fight.
local function engageUnit(unit)
    local name = remember(unit)
    if name and seg then
        enemyOf(seg, name)
        seg.pvp = true
    end
end

-- Enemies who attack you without you ever targeting or hitting them (a hunter shooting you as you run) appear in no
-- other source: while you're in combat, enemy players on nearby nameplates who target you or a groupmate join the
-- fight. When the client hides who they target, being in combat near you is enough (lax on purpose).
local function attacksUs(unit)
    local target = unit .. "target"
    local isMe = KKC.try(UnitIsUnit, target, "player")
    if KKC.readable(isMe) then
        if isMe then return true end
        local party = KKC.try(UnitInParty, target)
        local raid = KKC.try(UnitInRaid, target)
        return (KKC.readable(party) and party) or (KKC.readable(raid) and raid ~= nil and raid ~= false) or false
    end
    local fighting = KKC.try(UnitAffectingCombat, unit)
    return KKC.readable(fighting) and fighting or false
end

local scanning = false
local function scanPlates()
    if not seg then scanning = false; return end
    for i = 1, 40 do
        local unit = "nameplate" .. i
        local exists = KKC.try(UnitExists, unit)
        if KKC.readable(exists) and exists and attacksUs(unit) then engageUnit(unit) end
    end
    C_Timer.After(1, scanPlates)
end

KKC.On("PLAYER_REGEN_DISABLED", function()
    if scanning then return end
    scanning = true
    C_Timer.After(0.2, scanPlates)
end)

KKC.On("PLAYER_TARGET_CHANGED", function() engageUnit("target") end)
KKC.On("PLAYER_FOCUS_CHANGED", function() engageUnit("focus") end)
KKC.On("UPDATE_MOUSEOVER_UNIT", function() remember("mouseover") end)
KKC.On("NAME_PLATE_UNIT_ADDED", function(unit) remember(unit) end)

KKC.On("PLAYER_LOGOUT", function()
    if lastSeg then finishSegment(lastSeg) end
    T.CloseEngagement()
end)

-- ------------------------------------------------------------------------------------------------
-- Lookups for sync and the UI
-- ------------------------------------------------------------------------------------------------

function T.Open() return eng end

-- The engagement (open or logged) that a guildie's report belongs to: same zone, overlapping time.
function T.Fits(e, start, stop, zone)
    local gap = KKC.settings().mergeGap
    return e and not e.test and e.zone == zone and start <= e.stop + gap and stop >= e.start - gap
end

function T.Match(start, stop, zone)
    if T.Fits(eng, start, stop, zone) then return eng end
    for i = 1, math.min(20, #KKC.db.log) do
        if T.Fits(KKC.db.log[i], start, stop, zone) then return KKC.db.log[i] end
    end
end

-- A made-up engagement to preview the toast, battle card and texts (/kkc test).
function T.TestEngagement()
    local now, me = KKC.now(), KKC.me()
    local e = newEngagement(now - 200)
    e.stop, e.pvpSeconds, e.test, e.allies = now - 20, 164, true, 1
    e.zone, e.subzone = "Hillsbrad Foothills", "Tarren Mill"
    e.members[me] = { name = me, class = KKC.myClass(), dmg = 18450, heal = 2100, reported = true }
    e.members["Grukk"] = { name = "Grukk", class = "WARRIOR", dmg = 22310, heal = 0, died = true, reported = true }
    e.members["Zhara"] = { name = "Zhara", class = "PRIEST", dmg = 3020, heal = 26800, reported = true }
    e.members["Morth"] = { name = "Morth", class = "ROGUE", dmg = 15770, heal = 0 }
    e.enemies["Valandris"] = { name = "Valandris", class = "PALADIN", race = "Human", kills = 2 }
    e.enemies["Sylvaria"] = { name = "Sylvaria", class = "DRUID", race = "Night Elf", kills = 1 }
    e.enemies["Thorgrim"] = { name = "Thorgrim", class = "HUNTER", race = "Dwarf", kills = 1 }
    e.enemies["Fizzlebang"] = { name = "Fizzlebang", class = "MAGE", race = "Gnome", kills = 1 }
    e.enemies["Aldric"] = { name = "Aldric", class = "PRIEST", race = "Human", kills = 0 }
    e.enemies["Kaelen"] = { name = "Kaelen", class = "ROGUE", race = "Night Elf", kills = 0 }
    e.reports["Grukk"] = e.start + 4
    e.leaders = { Grukk = "leader", [me] = "assist" }
    e.opened = false -- the Alliance struck first
    e.opens = { Grukk = true }
    return e
end
