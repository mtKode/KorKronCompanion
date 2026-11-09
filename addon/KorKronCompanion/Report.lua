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
    leaders  [name] = "leader" | "assist"   who led your party or raid during the fights (nil when solo or unknown)
]]

local _, KKC = ...
local Report = {}
KKC.Report = Report

function KKC.Stats(e)
    local s = { members = KKC.count(e.members), enemies = KKC.count(e.enemies), kills = 0, fallen = {} }
    for _, en in pairs(e.enemies or {}) do s.kills = s.kills + (en.kills or 0) end
    for _, m in pairs(e.members or {}) do
        if m.died then s.fallen[#s.fallen + 1] = m.name end
    end
    table.sort(s.fallen)
    return s
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

local function fallenText(fallen)
    if #fallen == 0 then return nil end
    if #fallen == 1 then return fallen[1] end
    return #fallen .. " Kor'kron"
end

-- Same engagement, same pick: the wording varies between battles but never changes for one battle.
local function pick(e, list) return list[(math.floor(e.start or 0) % #list) + 1] end

-- The "Brief Description" draft, in the voice of a Kor'kron dispatch. %1 foe, %2 place, %3 slain, %4 fallen.
local OPENINGS = {
    ambush = { "Ambushed by %s at %s.", "%s fell upon us at %s.", "Set upon by %s near %s." },
    struck = { "We struck %s at %s.", "Fell upon %s at %s.", "Brought the fight to %s at %s." },
    clash = { "Clashed with %s at %s.", "Met %s in battle at %s." },
}
local OUTCOMES = {
    clean = { " %d slain, no Kor'kron lost.", " %d slain and every Kor'kron still standing.", " %d fell to our blades; we lost none." },
    bloody = { " %d slain, %d Kor'kron fell.", " %d slain at the cost of %d of ours." },
    lost = { " %s fell before they could be driven off.", " %s fell; the field was theirs this time." },
    driven = { " They were driven off.", " They broke and fled." },
}

local function outcome(e, s)
    if s.kills > 0 and #s.fallen == 0 then return pick(e, OUTCOMES.clean):format(s.kills) end
    if s.kills > 0 then return pick(e, OUTCOMES.bloody):format(s.kills, #s.fallen) end
    if #s.fallen > 0 then return pick(e, OUTCOMES.lost):format(fallenText(s.fallen)) end
    return pick(e, OUTCOMES.driven)
end

local CAMPAIGN = { "A patrol through %s: %s.", "The warband marched on %s: %s.", "We held the field around %s: %s." }

local function times(n)
    if n == 1 then return "once" elseif n == 2 then return "twice" end
    return n .. " times"
end

-- "4 clashes with 14 Alliance, ambushed twice and striking first once"
local function campaignClashes(e, s, faction)
    local text = ("%d clashes with %d %s"):format(e.fights, s.enemies, faction)
    local parts = {}
    if (e.ambushes or 0) > 0 then parts[#parts + 1] = "ambushed " .. times(e.ambushes) end
    if (e.struck or 0) > 0 then parts[#parts + 1] = "striking first " .. times(e.struck) end
    if #parts > 0 then text = text .. ", " .. table.concat(parts, " and ") end
    return text
end

function Report.Description(e)
    local s, faction, place = KKC.Stats(e), KKC.enemyFaction(), Report.Place(e)
    if e.campaign then
        return pick(e, CAMPAIGN):format(place, campaignClashes(e, s, faction)) .. outcome(e, s)
    end
    local foe = s.enemies == 1 and ("a lone " .. faction) or (s.enemies .. " " .. faction)
    local ambushed = KKC.Ambushed(e)
    local kind = ambushed and "ambush" or (ambushed == false and "struck" or "clash")
    local opening = pick(e, OPENINGS[kind]):format(foe, place)
    opening = opening:sub(1, 1):upper() .. opening:sub(2) -- "a lone Alliance fell upon us" starts a sentence
    return opening .. outcome(e, s)
end

local function enemyLabel(en)
    local what = table.concat({ en.race or "", KKC.className(en.class) or "" }, " "):gsub("^%s+", ""):gsub("%s+$", "")
    local label = en.name
    if what ~= "" then label = label .. " (" .. what .. ")" end
    if (en.kills or 0) > 1 then label = label .. " x" .. en.kills end
    return label
end

local function nameList(list, max)
    local out = {}
    for i, v in ipairs(list) do
        if i > max then out[#out + 1] = ("+%d more"):format(#list - max); break end
        out[#out + 1] = v
    end
    return table.concat(out, ", ")
end

-- The text people paste into the battle report post.
function Report.CopyText(e, description)
    local s = KKC.Stats(e)
    local members, enemies = {}, {}
    for _, m in ipairs(KKC.sortedValues(e.members)) do members[#members + 1] = m.name end
    for _, en in ipairs(KKC.sortedValues(e.enemies, function(a, b)
        if (a.kills or 0) ~= (b.kills or 0) then return (a.kills or 0) > (b.kills or 0) end
        return a.name < b.name
    end)) do enemies[#enemies + 1] = enemyLabel(en) end

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
        lines[#lines + 1] = ("Clashes: %d (ambushed %d, struck first %d)"):format(e.fights, e.ambushes or 0, e.struck or 0)
    end
    lines[#lines + 1] = ("Kor'kron (%d): %s"):format(s.members, nameList(members, 40))
    local leaders, assists = KKC.Leaders(e)
    if #leaders > 0 then lines[#lines + 1] = "Leaders: " .. table.concat(leaders, ", ") end
    if #assists > 0 then lines[#lines + 1] = "Assists: " .. table.concat(assists, ", ") end
    if (e.allies or 0) > 0 then lines[#lines + 1] = ("Other allies: %d"):format(e.allies) end
    lines[#lines + 1] = ("Enemies (%d): %s"):format(s.enemies, s.enemies > 0 and nameList(enemies, 30) or "unknown")
    local fallen = {}
    for _, name in ipairs(s.fallen) do
        local deaths = e.members[name] and e.members[name].deaths or 1
        fallen[#fallen + 1] = deaths > 1 and (name .. " x" .. deaths) or name
    end
    lines[#lines + 1] = ("Slain: %d | Fallen: %s"):format(s.kills, #fallen > 0 and table.concat(fallen, ", ") or "none")
    local ambushed -- a campaign's openings are on its Clashes line
    if not e.campaign then ambushed = KKC.Ambushed(e) end
    local opener = ambushed and (" | Struck first: " .. KKC.enemyFaction()) or (ambushed == false and " | Struck first: Kor'kron" or "")
    lines[#lines + 1] = ("Fighting time: %s | First into battle: %s%s"):format(KKC.duration(e.pvpSeconds), KKC.Initiator(e) or "?", opener)
    return table.concat(lines, "\n")
end

-- One line for guild chat (and Discord through the bridge). Max 255 characters.
function Report.ShareLine(e)
    local s, place, faction = KKC.Stats(e), Report.Place(e), KKC.enemyFaction()
    local line
    if e.campaign then
        line = ("[Kor'kron] Campaign through %s - %d clashes, %d against %d %s, %d slain"):format(place, e.fights, s.members, s.enemies, faction, s.kills)
        line = line .. (#s.fallen > 0 and (", %s fell in glory."):format(fallenText(s.fallen)) or ", none of ours lost.")
    elseif KKC.Ambushed(e) then
        local outcome = s.kills > 0 and (", %d slain"):format(s.kills) or ""
        if #s.fallen > 0 then outcome = outcome .. (", %s fell in glory"):format(fallenText(s.fallen)) end
        line = ("[Kor'kron] Ambushed at %s - %d %s fell on %d of us%s."):format(place, s.enemies, faction, s.members, outcome)
    elseif s.kills > 0 and #s.fallen == 0 then
        line = ("[Kor'kron] %s held - %d against %d %s, %d slain, none of ours fell."):format(place, s.members, s.enemies, faction, s.kills)
    elseif s.kills > 0 then
        line = ("[Kor'kron] Blood at %s - %d against %d %s, %d slain, %s fell in glory."):format(place, s.members, s.enemies, faction, s.kills, fallenText(s.fallen))
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
    elseif KKC.Ambushed(e) then parts[#parts + 1] = "ambush" end
    if s.kills > 0 then parts[#parts + 1] = s.kills .. " slain" end
    if #s.fallen > 0 then parts[#parts + 1] = #s.fallen .. " fallen" end
    return table.concat(parts, ", ")
end
