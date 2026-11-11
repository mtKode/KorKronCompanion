--[[
  War Ledger: your own running PvP totals per character (slain by race, by class, by name) and milestones.
  Only kills you got yourself count (your killing blows and honor kills), so syncing with guildies never counts a
  kill twice.
  The Hall of the Kor'kron (Hub.lua) shows them as tiered challenges, Legacy style: Ledger.Tracks().
]]

local _, KKC = ...
local Ledger = {}
KKC.Ledger = Ledger

local MILESTONES = { 10, 50, 100, 250, 500, 1000 }

local RACE_TITLES = {
    ["Human"] = "Scourge of Stormwind",
    ["Night Elf"] = "Bane of Darnassus",
    ["Dwarf"] = "Breaker of Ironforge",
    ["Gnome"] = "Gnomeregan's Ruin",
    ["Orc"] = "Bane of Orgrimmar",
    ["Troll"] = "Jungle Purger",
    ["Tauren"] = "Mulgore Hunter",
    ["Undead"] = "Grave Returner",
}

local CLASS_TITLES = {
    PALADIN = "Lightbreaker", PRIEST = "Faithbreaker", MAGE = "Spellbreaker", WARRIOR = "Shieldbreaker",
    ROGUE = "Shadowhunter", WARLOCK = "Felbane", HUNTER = "Huntsbane", DRUID = "Grovebane", SHAMAN = "Stormbreaker",
}

local function charKey() return (KKC.me() or "?") .. "-" .. (GetRealmName() or "") end

function Ledger.Mine()
    local key = charKey()
    local l = KKC.db.ledger[key]
    if not l then
        l = { total = 0, engagements = 0, fallen = 0, race = {}, class = {}, enemy = {} }
        KKC.db.ledger[key] = l
    end
    return l
end

local function crossed(before, after)
    for i = #MILESTONES, 1, -1 do
        local m = MILESTONES[i]
        if before < m and after >= m then return m end
    end
end

local function add(map, key, n, title)
    if not key then return end
    local before = map[key] or 0
    map[key] = before + n
    local m = crossed(before, map[key])
    if m and title then KKC.say(("%sLedger:|r %d %s slain - |cffffd100%s|r"):format(KKC.GOLD, m, key, title)) end
end

-- Called once per engagement when it closes.
function Ledger.Record(e)
    if e.test or e.ledgered then return end
    e.ledgered = true
    local l = Ledger.Mine()
    l.engagements = l.engagements + 1
    for name, n in pairs(e.ownKills or {}) do
        local en = e.enemies[name] or {}
        local before = l.total
        l.total = l.total + n
        local m = crossed(before, l.total)
        if m then KKC.say(("%sLedger:|r %d enemies slain in total."):format(KKC.GOLD, m)) end
        add(l.enemy, name, n)
        add(l.race, en.race, n, en.race and RACE_TITLES[en.race])
        if en.class then
            local before = l.class[en.class] or 0
            l.class[en.class] = before + n
            local cm = crossed(before, l.class[en.class])
            if cm then
                KKC.say(("%sLedger:|r %d %s slain - |cffffd100%s|r"):format(KKC.GOLD, cm, KKC.className(en.class) .. "s", CLASS_TITLES[en.class] or "Champion"))
            end
        end
    end
    local me = e.members and e.members[KKC.me()]
    if me and me.died then l.fallen = l.fallen + 1 end
end

local function top(map, n, label)
    local list = {}
    for k, v in pairs(map) do list[#list + 1] = { k = k, v = v } end
    table.sort(list, function(a, b) if a.v ~= b.v then return a.v > b.v end return a.k < b.k end)
    local out = {}
    for i = 1, math.min(n, #list) do out[#out + 1] = (label and label(list[i].k) or list[i].k) .. " " .. list[i].v end
    return #out > 0 and table.concat(out, ", ") or "none yet"
end

function Ledger.Print()
    local l = Ledger.Mine()
    KKC.say(("War Ledger for %s: %d slain (%d unique), %d engagements, fallen %d times."):format(
        KKC.me(), l.total, KKC.count(l.enemy), l.engagements, l.fallen))
    KKC.say("  By race: " .. top(l.race, 8))
    KKC.say("  By class: " .. top(l.class, 9, KKC.className))
    KKC.say("  Most slain: " .. top(l.enemy, 5))
end

-- ------------------------------------------------------------------------------------------------
-- Challenges for the War Ledger page: each track has tiers; a row shows the next tier to earn.
-- ------------------------------------------------------------------------------------------------

local RACES = {
    Alliance = { "Human", "Dwarf", "Night Elf", "Gnome" },   -- the foes of a Horde player
    Horde = { "Orc", "Undead", "Tauren", "Troll" },
}
local PLURAL = {
    ["Human"] = "Humans", ["Dwarf"] = "Dwarves", ["Night Elf"] = "Night Elves", ["Gnome"] = "Gnomes",
    ["Orc"] = "Orcs", ["Undead"] = "Undead", ["Tauren"] = "Tauren", ["Troll"] = "Trolls",
}
local RACE_ICONS = {
    ["Human"] = "INV_Misc_Head_Human_01", ["Dwarf"] = "INV_Misc_Head_Dwarf_01", ["Night Elf"] = "INV_Misc_Head_Elf_02",
    ["Gnome"] = "INV_Misc_Head_Gnome_01", ["Orc"] = "INV_Misc_Head_Orc_01", ["Undead"] = "INV_Misc_Head_Undead_01",
    ["Tauren"] = "INV_Misc_Head_Tauren_01", ["Troll"] = "INV_Misc_Head_Troll_01",
}
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local ICON = "Interface\\Icons\\"

-- tiers: { { goal, title }, ... } -> the row for the next tier (or the last one, complete).
local function track(icon, tiers, value, describe)
    local done = 0
    for i, t in ipairs(tiers) do if value >= t[1] then done = i end end
    local current = tiers[math.min(done + 1, #tiers)]
    return {
        icon = ICON .. icon, title = current[2], text = describe(current[1]),
        value = value, goal = current[1], tier = done, tiers = #tiers, complete = done == #tiers,
    }
end

-- Counts from your own battles in the log (all characters' logs share the file; only this character's count).
local function fromLog()
    local me, c = KKC.me(), { struck = 0, weathered = 0, battles = 0 }
    for _, e in ipairs(KKC.db.log) do
        if e.owner == me and not e.test and not e.minor then
            c.battles = c.battles + 1
            local ambushed = KKC.Ambushed(e)
            if ambushed == false then c.struck = c.struck + 1 end
            if ambushed and KKC.Stats(e).kills > 0 then c.weathered = c.weathered + 1 end
        end
    end
    return c
end

function Ledger.Tracks()
    local l, c = Ledger.Mine(), fromLog()
    local own = UnitFactionGroup("player") or "Horde"
    local foe = KKC.enemyFaction()
    local list = {}
    local function add(row) list[#list + 1] = row end

    add(track("Ability_Warrior_BattleShout", {
        { 10, "Blooded" }, { 50, "Veteran of the Front" }, { 100, "Champion of the " .. own },
        { 250, "Scourge of the " .. foe }, { 500, "Warbringer" }, { 1000, "Legend of the " .. own },
    }, l.total, function(g) return ("Slay %d enemy players."):format(g) end))
    add(track("INV_Misc_Spyglass_03", {
        { 10, "Many Faces" }, { 25, "Known to the Enemy" }, { 50, "A Name They Whisper" }, { 100, "A Name They Fear" },
    }, KKC.count(l.enemy), function(g) return ("Slay %d different enemy players."):format(g) end))
    add(track(own == "Horde" and "INV_BannerPVP_01" or "INV_BannerPVP_02", {
        { 5, "Called to Arms" }, { 25, "Seasoned Warrior" }, { 100, "Hardened by War" }, { 250, "Born for Battle" },
    }, c.battles, function(g) return ("Fight %d battles of note."):format(g) end))
    add(track("Ability_Rogue_Ambush", {
        { 5, "The First Blow" }, { 25, "Strike from the Shadows" }, { 100, "Master of the Hunt" },
    }, c.struck, function(g) return ("Strike first in %d battles."):format(g) end))
    add(track("Ability_Warrior_DefensiveStance", {
        { 3, "Unbroken" }, { 10, "Turned the Tide" }, { 25, "Iron Will" },
    }, c.weathered, function(g) return ("Be ambushed and still slay the enemy, %d times."):format(g) end))

    local races, listed = {}, {}
    for _, r in ipairs(RACES[foe] or {}) do races[#races + 1] = r; listed[r] = true end
    for r in pairs(l.race) do if not listed[r] then races[#races + 1] = r end end -- races this list doesn't know yet
    for _, r in ipairs(races) do
        local plural = PLURAL[r] or r
        add(track(RACE_ICONS[r] or "INV_Misc_QuestionMark", {
            { 10, "First Blood: " .. plural }, { 50, "Hunter of " .. plural }, { 100, RACE_TITLES[r] or ("Bane of the " .. plural) },
            { 250, "Scourge of the " .. plural },
        }, l.race[r] or 0, function(g) return ("Slay %d %s."):format(g, plural) end))
    end
    for _, cl in ipairs(CLASSES) do
        local name = KKC.className(cl) or cl
        add(track("ClassIcon_" .. cl:sub(1, 1) .. cl:sub(2):lower(), {
            { 10, name .. "-slayer" }, { 50, "Bane of " .. name .. "s" }, { 100, CLASS_TITLES[cl] or (name .. "breaker") },
        }, l.class[cl] or 0, function(g) return ("Slay %d %ss."):format(g, name) end))
    end
    return list
end
