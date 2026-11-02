--[[
  War Ledger: your own running PvP totals per character (slain by race, by class, by name) and milestones.
  Only honor kills you got yourself count, so syncing with guildies never counts a kill twice.
  Later this is meant to show up as a category in Forever's Legacy panel (see docs/DESIGN.md).
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
