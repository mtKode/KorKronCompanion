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

-- "4 clashes with 14 Alliance"
local function campaignClashes(e, s, faction)
    return ("%d clashes with %d %s"):format(e.fights, s.enemies, faction)
end

function Report.Description(e)
    local s, faction, place = KKC.Stats(e), KKC.enemyFaction(), Report.Place(e)
    if e.campaign then
        return pick(e, CAMPAIGN):format(place, campaignClashes(e, s, faction)) .. outcome(e, s)
    end
    local foe = s.enemies == 1 and ("a lone " .. faction) or (s.enemies .. " " .. faction)
    local opening = pick(e, OPENINGS.clash):format(foe, place)
    opening = opening:sub(1, 1):upper() .. opening:sub(2) -- "a lone Alliance fell upon us" starts a sentence
    return opening .. outcome(e, s)
end

-- The text people paste into the battle report post.
function Report.CopyText(e, description)
    local s = KKC.Stats(e)
    local members, foes = {}, {}
    for _, m in ipairs(KKC.sortedValues(e.members)) do members[#members + 1] = m.name end
    -- The enemy only as a tally: the report is about who of ours fought.
    for _, t in ipairs(KKC.FoeTally(e)) do foes[#foes + 1] = t.count .. " " .. t.label end

    local location = e.zone or "?"
    if e.subzone and e.subzone ~= "" and e.subzone ~= e.zone then location = location .. " - " .. e.subzone end
    if e.campaign then location = e.location end

    local lines = {
        "Date: " .. date("%Y-%m-%d", e.start),
        "Time: " .. date("%H:%M", e.start) .. " - " .. date("%H:%M", e.stop or e.start),
        "Brief Description: " .. (description or Report.Description(e)),
        "",
        "Location: " .. location,
    }
    if e.campaign then
        lines[#lines + 1] = ("Clashes: %d"):format(e.fights)
    end
    lines[#lines + 1] = ("Kor'kron (%d): %s"):format(s.members, table.concat(members, ", "))
    local leaders, assists = KKC.Leaders(e)
    if #leaders > 0 then lines[#lines + 1] = "Leaders: " .. table.concat(leaders, ", ") end
    if #assists > 0 then lines[#lines + 1] = "Assists: " .. table.concat(assists, ", ") end
    if (e.allies or 0) > 0 then lines[#lines + 1] = ("Other allies: %d"):format(e.allies) end
    lines[#lines + 1] = ("Enemies: %d %s%s"):format(s.enemies, KKC.enemyFaction(), #foes > 0 and (" (" .. table.concat(foes, ", ") .. ")") or "")
    lines[#lines + 1] = "Slain: " .. (s.kills > 0 and ("at least %d"):format(s.kills) or "none seen")
    lines[#lines + 1] = ("Fighting time: %s | First into battle: %s"):format(KKC.duration(e.pvpSeconds), KKC.Initiator(e) or "?")
    return table.concat(lines, "\n")
end

-- One line for guild chat (and Discord through the bridge). Max 255 characters.
function Report.ShareLine(e)
    local s, place, faction = KKC.Stats(e), Report.Place(e), KKC.enemyFaction()
    local line
    if e.campaign then
        line = ("[Kor'kron] Campaign through %s - %d clashes, %d against %d %s, %s."):format(place, e.fights, s.members, s.enemies, faction, KKC.SlainText(s.kills))
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
