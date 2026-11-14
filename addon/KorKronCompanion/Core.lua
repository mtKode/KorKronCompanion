--[[
  Kor'kron Companion: shared helpers, saved data and the event hub.

  Forever runs a modern client with addon restrictions: many unit and meter values are "secret" while in combat.
  Never compare, concatenate or index with a value before readable() says it is safe.
]]

local ADDON, KKC = ...
KKC.VERSION = "0.3.0"
KKC.GOLD = "|cffd4af37"
KKC.GREY = "|cff9d9d9d"
KKC.RED = "|cffff6060"
KKC.raw = {} -- last raw names seen per source (honor, meter, sender), for /kkc debug

-- ------------------------------------------------------------------------------------------------
-- Small helpers
-- ------------------------------------------------------------------------------------------------

local function pack(...) return { n = select("#", ...), ... } end

-- Calls f safely; returns its results, or nothing when f is missing or errors.
function KKC.try(f, ...)
    if type(f) ~= "function" then return end
    local r = pack(pcall(f, ...))
    if r[1] then return unpack(r, 2, r.n) end
end

-- True when v is a normal value this addon may use (not nil, not a secret).
function KKC.readable(v)
    if v == nil then return false end
    if issecretvalue and issecretvalue(v) then return false end
    return true
end

-- A table we may iterate (not nil, not secret).
function KKC.readableTable(t)
    if type(t) ~= "table" then return false end
    if issecrettable and issecrettable(t) then return false end
    return KKC.readable(t)
end

-- The first n bytes of s, never ending inside a UTF-8 character ("Järnlykta"): chat refuses broken text.
function KKC.utf8cut(s, n)
    if #s <= n then return s end
    local b = s:byte(n + 1)
    while n > 0 and b and b >= 0x80 and b < 0xC0 do
        n = n - 1
        b = s:byte(n + 1)
    end
    return s:sub(1, n)
end

function KKC.say(msg) DEFAULT_CHAT_FRAME:AddMessage(KKC.GOLD .. "Kor'kron|r: " .. tostring(msg)) end

-- Keep values on one line and free of the sync separator.
function KKC.clean(v)
    v = tostring(v == nil and "" or v)
    return (v:gsub("[\r\n;|]", " "))
end

-- Forever has double names ("Kaiva Embermane"): first name and surname joined by this separator (a space). Nil on
-- clients without surnames.
local function surnameSep()
    local c = Constants and Constants.CharacterNameSeparatorConsts
    return c and c.CHARACTERNAME_SURNAME_SEPARATOR
end

-- Full character name of a unit. On Forever UnitName returns (first name, surname); elsewhere (name, realm).
function KKC.unitName(unit)
    local name, second = KKC.try(UnitName, unit)
    if not KKC.readable(name) or type(name) ~= "string" or name == "" then return nil end
    local sep = surnameSep()
    if sep and KKC.readable(second) and type(second) == "string" and second ~= "" and not name:find(sep, 1, true) then
        name = name .. sep .. second
    end
    return name
end

-- A name from chat, the meter or a message, as the full name without realm:
--   "Kaiva Embermane-Realm" / "Kaiva Embermane" -> "Kaiva Embermane"
--   "Kaiva-Embermane" (the link form, which uses the realm separator) -> "Kaiva Embermane"
--   "Kaiva-Realm" (no surname, our realm) -> "Kaiva"
function KKC.short(name)
    if not KKC.readable(name) or type(name) ~= "string" or name == "" then return nil end
    local base, suffix = name:match("^(.-)%-([^%-]+)$")
    if not base or base == "" then return name end
    local sep = surnameSep()
    if not sep or base:find(sep, 1, true) then return base end
    local realm = (GetRealmName() or ""):gsub("%s", "")
    if suffix == realm then return base end
    return base .. sep .. suffix
end

-- The roleplay title from Total RP 3 ("Blood Guard"), when the addon is loaded and we have that character's profile.
-- Only the title is used: the screenshot must still show the real character names for the officers.
function KKC.rpTitle(name)
    local P = AddOn_TotalRP3 and AddOn_TotalRP3.Player
    if not (P and P.CreateFromNameAndRealm and name) then return nil end
    local realm = (GetRealmName() or ""):gsub("%s", "")
    local ok, player = pcall(P.CreateFromNameAndRealm, name, realm)
    if not ok or not player then return nil end
    local title = KKC.try(player.GetTitle, player)
    if type(title) == "string" and title ~= "" and #title <= 30 then return title end
end

function KKC.now() return GetServerTime and GetServerTime() or time() end

function KKC.me() return KKC.unitName("player") end

function KKC.myClass() return select(2, UnitClass("player")) end

-- The faction we fight: Alliance for a Horde guild.
function KKC.enemyFaction()
    local f = UnitFactionGroup("player")
    if f == "Horde" then return "Alliance" elseif f == "Alliance" then return "Horde" end
    return "enemy"
end

function KKC.classColor(token)
    local c = token and ((C_ClassColor and KKC.try(C_ClassColor.GetClassColor, token)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]))
    if c and c.GenerateHexColor then return "|c" .. c:GenerateHexColor() end
    if c and c.colorStr then return "|c" .. c.colorStr end
    return "|cffffffff"
end

function KKC.className(token)
    return token and ((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or token) or nil
end

function KKC.shortNumber(n)
    n = tonumber(n) or 0
    if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end
    if n >= 1e4 then return ("%.0fk"):format(n / 1e3) end
    if n >= 1e3 then return ("%.1fk"):format(n / 1e3) end
    return tostring(math.floor(n + 0.5))
end

function KKC.duration(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    if sec < 60 then return sec .. "s" end
    return ("%dm %02ds"):format(math.floor(sec / 60), sec % 60)
end

-- Sorted list of a name-keyed table's values.
function KKC.sortedValues(t, cmp)
    local list = {}
    for _, v in pairs(t or {}) do list[#list + 1] = v end
    table.sort(list, cmp or function(a, b) return (a.name or "") < (b.name or "") end)
    return list
end

function KKC.count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

-- ------------------------------------------------------------------------------------------------
-- Saved data
-- ------------------------------------------------------------------------------------------------

KKC.defaults = {
    settings = {
        sync = false,           -- share engagements with guildies over GUILD addon messages (/kkc sync on)
        notify = "quiet",       -- off | quiet (one chat line) | toast | prompt; tracking runs either way
        promptAll = false,      -- true: notify everyone, not just the initiator
        mergeGap = 60,          -- seconds out of combat before an engagement closes
        notableSeconds = 20,    -- this much PvP combat makes an engagement notable
        notableEnemies = 2,     -- or this many enemy players
        campaignGap = 1800,     -- fights closer than this (seconds) are one campaign: one report for the outing
        minimap = { hide = false, angle = 200 }, -- the minimap button (Minimap.lua): hidden?, where on the edge (degrees)
        rollcalls = true,       -- a roll call of the guild in your group every 10 minutes (RollCall.lua)
        rollcallsInReport = false, -- the report text ranks the roster by roll calls and lists them (longer to paste)
    },
    rollcalls = {}, -- who of the guild was in your group when, newest first (RollCall.lua)
    log = {},   -- your engagements, newest first
    feed = {},  -- guildies' fights you weren't in, newest first
    ledger = {},
}

-- Stored data format version. Bump it and add a step in migrate() when stored fields change meaning, so long-term
-- statistics (a 3-month or season summary) can always read old records.
KKC.SCHEMA = 4

-- How long engagements are kept: your own fights a year (long-term statistics), the guild feed four months.
local KEEP = { log = { days = 365, max = 3000 }, feed = { days = 120, max = 1500 } }

-- Trim a newest-first engagement list by its limits.
function KKC.Prune(list, kind)
    local keep = KEEP[kind] or KEEP.feed
    local oldest = KKC.now() - keep.days * 86400
    while #list > keep.max or (#list > 0 and (list[#list].stop or 0) < oldest) do table.remove(list) end
end

-- Runtime-only flags that don't belong in stored records.
local TRANSIENT = { "notified" }

local function migrate(db)
    db.schema = db.schema or 1
    -- 2: no popups by default. A "toast" saved by 0.1 was the old default, not a choice: make it one chat line.
    if db.schema < 2 then
        if db.settings.notify == "toast" then db.settings.notify = "quiet" end
        db.schema = 2
    end
    -- 3: (was the report paper's default; that setting is gone, the card is a dark sheet now)
    if db.schema < 3 then
        db.schema = 3
    end
    -- 4: the first kill tracking (9 Nov) named victims by first name only and stored race tokens. Fold each such kill
    -- into the one full-name enemy it belongs to ("Morgan" -> "Morgan Ashford"), and use display race names.
    if db.schema < 4 then
        local RACES = { NightElf = "Night Elf", Scourge = "Undead" }
        for _, list in ipairs({ db.log, db.feed }) do
            for _, e in ipairs(list) do
                local enemies = e.enemies or {}
                for name, en in pairs(enemies) do
                    if RACES[en.race] then en.race = RACES[en.race] end
                    if not name:find(" ", 1, true) and (en.kills or 0) > 0 then
                        local match, count = nil, 0
                        for other in pairs(enemies) do
                            if other:sub(1, #name + 1) == name .. " " then match, count = other, count + 1 end
                        end
                        if count == 1 then
                            local full = enemies[match]
                            full.kills = (full.kills or 0) + en.kills
                            full.class, full.race = full.class or en.class, full.race or RACES[en.race] or en.race
                            if e.ownKills and e.ownKills[name] then
                                e.ownKills[match] = (e.ownKills[match] or 0) + e.ownKills[name]
                                e.ownKills[name] = nil
                            end
                            enemies[name] = nil -- removing the current key during pairs() is allowed in Lua
                        end
                    end
                end
            end
        end
        for _, l in pairs(db.ledger or {}) do
            for token, label in pairs(RACES) do
                if l.race and l.race[token] then
                    l.race[label] = (l.race[label] or 0) + l.race[token]
                    l.race[token] = nil
                end
            end
        end
        db.schema = 4
    end
    for _, list in ipairs({ db.log, db.feed }) do
        for _, e in ipairs(list) do
            for _, k in ipairs(TRANSIENT) do e[k] = nil end
        end
    end
end

local function applyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            applyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function KKC.settings() return KKC.db.settings end

-- ------------------------------------------------------------------------------------------------
-- Event hub: modules call KKC.On(event, fn); several modules can listen to the same event.
-- ------------------------------------------------------------------------------------------------

local handlers = {}
local hub = CreateFrame("Frame")
KKC.hub = hub

function KKC.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        pcall(hub.RegisterEvent, hub, event) -- some events don't exist on every client
    end
    table.insert(handlers[event], fn)
end

hub:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok and KKC.debugErrors then KKC.say(KKC.RED .. event .. ":|r " .. tostring(err)) end
    end
end)

-- Everyone in your guild by name, from the guild roster: tells a guildmate when the unit can't (outside your group,
-- or the guild flag unreadable). Asked for at login; the game sends updates as people come and go.
local guildNames = {}
local function readRoster()
    local n = KKC.try(GetNumGuildMembers)
    if not (KKC.readable(n) and type(n) == "number" and n > 0) then return end
    local names = {}
    for i = 1, n do
        local name = KKC.try(GetGuildRosterInfo, i)
        if KKC.readable(name) and type(name) == "string" then
            local short = KKC.short(name)
            if short then names[short] = true end
        end
    end
    guildNames = names
end
function KKC.IsGuildmate(name) return name ~= nil and guildNames[name] == true end
KKC.On("GUILD_ROSTER_UPDATE", readRoster)
KKC.On("PLAYER_ENTERING_WORLD", function()
    if IsInGuild() then KKC.try((C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster) end
end)

-- Internal callbacks between modules ("EngagementClosed", "EngagementUpdated", ...).
local callbacks = {}
function KKC.Listen(name, fn)
    callbacks[name] = callbacks[name] or {}
    table.insert(callbacks[name], fn)
end
function KKC.Fire(name, ...)
    for _, fn in ipairs(callbacks[name] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok and KKC.debugErrors then KKC.say(KKC.RED .. name .. ":|r " .. tostring(err)) end
    end
end

-- When the game blocks something this addon tried, say which function it was (the popup doesn't).
local function onBlocked(culprit, func)
    if type(culprit) == "string" and culprit:find(ADDON, 1, true) then
        KKC.say(KKC.RED .. "the game blocked|r " .. tostring(func) .. KKC.RED .. ". Please send this line to the addon author.|r")
    end
end
KKC.On("ADDON_ACTION_BLOCKED", onBlocked)
KKC.On("ADDON_ACTION_FORBIDDEN", onBlocked)

KKC.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    KorKronCompanionDB = KorKronCompanionDB or {}
    applyDefaults(KorKronCompanionDB, KKC.defaults)
    KKC.db = KorKronCompanionDB
    migrate(KKC.db)
    KKC.Fire("Init")
end)
