--[[
  Engagement summaries and the texts built from them: the battle report copy text, the one-line guild share and a
  draft "Brief Description".

  Engagement fields (built in Tracker.lua, merged in Sync.lua):
    id, owner, start, stop, zone, subzone, pvpSeconds, minor, test, feed (true: a guildie's fight, from the feed)
    map, x, y  map ID and 0-1 position where the first segment started (nil when the client hid it)
    opened     true: you struck first; false: you were hit first; nil: unknown
    opens    [sender] = that guildie's opened flag
    enemies  [name] = { name, class (token), race (display name), kills }
    members  [name] = { name, class, dmg, heal, died, reported }   guildies only (you included)
    ownKills [name] = honor kills you got yourself (feeds the ledger)
    reports  [sender] = start time of that guildie's own engagement (picks who was first into battle)
    allies   number of non-guild allies seen in your group
    unnamedKills  killing blows by the group whose victim couldn't be named (still slain)
    leaders  [name] = "leader" | "assist"   who led your party or raid during the fights (nil when solo or unknown)
]]

local _, KKC = ...
local Report = {}
KKC.Report = Report

function KKC.Stats(e)
    -- kills: named ones per enemy, plus killing blows whose victim the client kept secret.
    local s = { members = KKC.count(e.members), enemies = KKC.count(e.enemies), kills = e.unnamedKills or 0, fallen = {} }
    for _, en in pairs(e.enemies or {}) do s.kills = s.kills + (en.kills or 0) end
    for _, m in pairs(e.members or {}) do
        if m.died then s.fallen[#s.fallen + 1] = m.name end
    end
    table.sort(s.fallen)
    return s
end

-- Kills are a minimum: only the killing blows your own client hears about count, and those far from you may not
-- reach it. "at least 10 slain", or "no kills seen".
function KKC.SlainText(n)
    if (n or 0) > 0 then return ("at least %d slain"):format(n) end
    return "no kills seen"
end

function KKC.IsNotable(e)
    local set, s = KKC.settings(), KKC.Stats(e)
    return s.kills > 0 or #s.fallen > 0 or s.enemies >= set.notableEnemies or (e.pvpSeconds or 0) >= set.notableSeconds
end

-- Group leaders and raid assistants of an engagement, each sorted by name. Two empty lists when nobody led.
function KKC.Leaders(e)
    local leaders, assists = {}, {}
    for name, role in pairs(e.leaders or {}) do
        local list = role == "leader" and leaders or assists
        list[#list + 1] = name
    end
    table.sort(leaders); table.sort(assists)
    return leaders, assists
end

-- The enemy counted by race (or class when the race wasn't seen): { label, count, kills }, most numerous first.
function KKC.FoeTally(e)
    local by, list = {}, {}
    for _, en in pairs(e.enemies or {}) do
        local label = en.race or KKC.className(en.class) or "unknown"
        local t = by[label]
        if not t then
            t = { label = label, count = 0, kills = 0 }
            by[label] = t
            list[#list + 1] = t
        end
        t.count = t.count + 1
        t.kills = t.kills + (en.kills or 0)
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if (a.label == "unknown") ~= (b.label == "unknown") then return b.label == "unknown" end
        return a.label < b.label
    end)
    return list
end

-- Whoever's engagement started first; ties go alphabetically so every client picks the same person.
-- Guild feed entries have no start of their own (it's the earliest report's), so only the reports count there.
function KKC.Initiator(e)
    local best, bestStart
    if not e.feed then best, bestStart = e.owner, e.start end
    for sender, start in pairs(e.reports or {}) do
        if not best or start < bestStart or (start == bestStart and sender < best) then best, bestStart = sender, start end
    end
    return best or e.owner
end

-- true: the enemy struck first (whoever was first into combat entered it without attacking); false: we did;
-- nil: unknown (a report from an older version, or a kill out of combat).
function KKC.Ambushed(e)
    local first = KKC.Initiator(e)
    local opened
    if first == e.owner and not e.feed then opened = e.opened else opened = e.opens and e.opens[first] end
    if opened == nil then return nil end
    return not opened
end

-- "A", "A and B", "A, B and C", "A, B and 2 more".
local function joinPlaces(list)
    if #list <= 1 then return list[1] or "?" end
    if #list == 2 then return list[1] .. " and " .. list[2] end
    if #list == 3 then return list[1] .. ", " .. list[2] .. " and " .. list[3] end
    return list[1] .. ", " .. list[2] .. (" and %d more"):format(#list - 2)
end

function Report.Place(e)
    if e.campaign then return joinPlaces(e.zones) end
    if e.subzone and e.subzone ~= "" and e.subzone ~= e.zone then return e.subzone end
    return e.zone or "?"
end

-- Same engagement, same pick: the wording varies between battles but never changes for one battle.
local function pick(e, list) return list[(math.floor(e.start or 0) % #list) + 1] end

-- The "Brief Description" draft, in the voice of a Kor'kron dispatch. %1 foe, %2 place, %3 slain.
-- Reports leave our own deaths out (they stay in the data and the chronicle's summaries).
local OPENINGS = {
    -- Neutral on purpose: who struck first is still recorded (the chronicle's first-blow count), but it's often a
    -- guess, and "Ambushed!" on every report read like spam.
    clash = { "Clashed with %s at %s.", "Met %s in battle at %s.", "Crossed blades with %s at %s." },
}
local OUTCOMES = {
    slain = { " At least %d slain.", " At least %d fell to our blades.", " At least %d of them will not rise again." },
    driven = { " They were driven off.", " They broke and fled." },
}

local function outcome(e, s)
    if s.kills > 0 then return pick(e, OUTCOMES.slain):format(s.kills) end
    return pick(e, OUTCOMES.driven)
end

local CAMPAIGN = { "A patrol through %s: %s.", "The warband marched on %s: %s.", "We held the field around %s: %s." }
local LONE = { "A lone patrol through %s: %s.", "Alone through %s: %s.", "Scouting %s alone: %s." }

-- "4 clashes with 14 Alliance"
local function campaignClashes(e, s, faction)
    return ("%d clashes with %d %s"):format(e.fights, s.enemies, faction)
end

function Report.Description(e)
    local s, faction, place = KKC.Stats(e), KKC.enemyFaction(), Report.Place(e)
    if e.campaign then
        local lone = KKC.count(e.members) <= 1
        return pick(e, lone and LONE or CAMPAIGN):format(place, campaignClashes(e, s, faction)) .. outcome(e, s)
    end
    local foe = s.enemies == 1 and ("a lone " .. faction) or (s.enemies .. " " .. faction)
    local opening = pick(e, OPENINGS.clash):format(foe, place)
    opening = opening:sub(1, 1):upper() .. opening:sub(2) -- "a lone Alliance fell upon us" starts a sentence
    return opening .. outcome(e, s)
end

-- The main leader and everyone else who led or assisted. In a campaign the main leader is whoever led the most fights
-- (the lead can change hands during a night); ties, and a single fight, go alphabetically.
function KKC.MainLeader(e)
    local leaders, assists = KKC.Leaders(e)
    local counts = e.leadFights or {}
    table.sort(leaders, function(a, b)
        if (counts[a] or 0) ~= (counts[b] or 0) then return (counts[a] or 0) > (counts[b] or 0) end
        return a < b
    end)
    local main = leaders[1]
    local others = {}
    for i = 2, #leaders do others[#others + 1] = leaders[i] end
    for _, name in ipairs(assists) do others[#others + 1] = name end
    return main, others
end

-- "1h 45m", "35m": how long the outing lasted, first blow to last.
local function span(e)
    local min = math.floor(((e.stop or e.start) - e.start) / 60 + 0.5)
    if min < 60 then return math.max(1, min) .. "m" end
    return ("%dh %02dm"):format(math.floor(min / 60), min % 60)
end

-- The ones who stood out, by what the meter saw: the most damage and the most healing among the Kor'kron.
local function distinguished(e)
    if KKC.count(e.members) < 2 then return "" end
    local dmg, heal
    for _, m in pairs(e.members) do
        if (m.dmg or 0) > 0 and (not dmg or m.dmg > dmg.dmg) then dmg = m end
        if (m.heal or 0) > 0 and (not heal or m.heal > heal.heal) then heal = m end
    end
    local out = {}
    if dmg then out[#out + 1] = dmg.name .. " (most damage)" end
    if heal then
        if heal == dmg then out[1] = dmg.name .. " (most damage and healing)" else out[#out + 1] = heal.name .. " (most healing)" end
    end
    return table.concat(out, ", ")
end

-- How it started: who struck first, where, and who of ours was first into battle (for a campaign, its first fight).
local function initiated(e)
    local place = Report.Place(e.campaign and e.anchor or e)
    local first = KKC.Initiator(e) or "?"
    local ambushed = KKC.Ambushed(e)
    if ambushed then
        return ("The %s struck first at %s; %s was first into battle."):format(KKC.enemyFaction(), place, first)
    elseif ambushed == false then
        return ("%s struck first at %s."):format(first, place)
    end
    return ("Fighting broke out at %s; %s was first into battle."):format(place, first)
end

-- The text people paste into the battle report post, in the guild's template (fields that don't apply stay empty,
-- as the template asks), then a few details below it.
function Report.CopyText(e, description)
    local s = KKC.Stats(e)
    local members, foes = {}, {}
    for _, m in ipairs(KKC.sortedValues(e.members)) do members[#members + 1] = m.name end
    -- The enemy only as a tally: the report is about who of ours fought.
    for _, t in ipairs(KKC.FoeTally(e)) do foes[#foes + 1] = t.count .. " " .. t.label end
    local main, others = KKC.MainLeader(e)

    local location = e.zone or "?"
    if e.subzone and e.subzone ~= "" and e.subzone ~= e.zone then location = location .. " - " .. e.subzone end
    if e.campaign then location = e.location end

    local lines = {
        "Date: " .. date("%Y-%m-%d", e.start),
        "Start time: " .. date("%H:%M", e.start),
        "Duration: " .. span(e),
        "Short description: " .. (description or Report.Description(e)),
        "Kills (approximate): " .. (s.kills > 0 and ("at least %d"):format(s.kills) or "none seen"),
        "Main leader: " .. (main or ""),
        "Additional leaders: " .. table.concat(others, ", "),
        "Distinguished participants: " .. distinguished(e),
        "How the event was initiated: " .. initiated(e),
        "",
        "Location: " .. location,
    }
    if e.campaign then lines[#lines + 1] = ("Clashes: %d"):format(e.fights) end
    -- Outings only (Campaign.View): a single fight's roll calls are just its start and end. Off by default: the
    -- roll calls are on the battle card (Roll calls button), and the text stays short enough for one Discord message.
    local att = KKC.settings().rollcallsInReport and e.attendance
    if att then
        -- Who stayed longest first, with how many of the roll calls they were present at.
        local ranked, seen = {}, {}
        for _, a in ipairs(KKC.RollCall.Ranked(att)) do
            ranked[#ranked + 1] = a.name .. " " .. KKC.RollCall.Share(a)
            seen[a.name] = true
        end
        for _, name in ipairs(members) do if not seen[name] then ranked[#ranked + 1] = name .. " (in a fight)" end end
        members = ranked
    end
    lines[#lines + 1] = ("Kor'kron (%d): %s"):format(s.members, table.concat(members, ", "))
    if att then
        local calls = {}
        for _, c in ipairs(att.calls) do
            calls[#calls + 1] = ("%s (%d%s)"):format(date("%H:%M", c.t), KKC.count(c.present), c.shot and ", screenshot" or "")
        end
        lines[#lines + 1] = "Roll calls: " .. table.concat(calls, ", ")
    end
    if (e.allies or 0) > 0 then lines[#lines + 1] = ("Other allies: %d"):format(e.allies) end
    lines[#lines + 1] = ("Enemies: %d %s%s"):format(s.enemies, KKC.enemyFaction(), #foes > 0 and (" (" .. table.concat(foes, ", ") .. ")") or "")
    return table.concat(lines, "\n")
end

-- One line for guild chat (and Discord through the bridge). Max 255 characters.
function Report.ShareLine(e)
    local s, place, faction = KKC.Stats(e), Report.Place(e), KKC.enemyFaction()
    local line
    if e.campaign then
        line = ("[Kor'kron] %s through %s - %d clashes, %d against %d %s, %s."):format(KKC.Campaign.Name(e), place, e.fights, s.members, s.enemies, faction, KKC.SlainText(s.kills))
    elseif s.kills > 0 then
        line = ("[Kor'kron] Blood at %s - %d against %d %s, %s."):format(place, s.members, s.enemies, faction, KKC.SlainText(s.kills))
    else
        line = ("[Kor'kron] Skirmish at %s - %d against %d %s."):format(place, s.members, s.enemies, faction)
    end
    if s.kills > 0 then line = line .. pick(e, { " Lok'tar ogar!", " Blood and thunder!", " For the Horde!" }) end
    if #line > 255 then line = line:sub(1, 252) .. "..." end
    return line
end

-- Short summary for the toast and chat.
function Report.Headline(e)
    local s = KKC.Stats(e)
    local parts = { ("%s - %d against %d"):format(Report.Place(e), s.members, s.enemies) }
    if e.campaign then
        parts[#parts + 1] = ("%d clashes"):format(e.fights)
    end
    if s.kills > 0 then parts[#parts + 1] = s.kills .. "+ slain" end
    if #s.fallen > 0 then parts[#parts + 1] = #s.fallen .. " fallen" end
    return table.concat(parts, ", ")
end
