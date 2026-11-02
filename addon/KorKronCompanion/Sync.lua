--[[
  Sharing engagements between guildies with the addon (hidden addon messages on the GUILD channel).

  When an engagement closes, each client sends what it saw:
    H;eid;start;stop;zone;subzone;pvpSeconds;class;nEnemies;opened;map;x;y   header (eid = owner-start;
                                                                 opened 1/0/empty = struck first / hit first / unknown)
    E;eid;name;class;race;kills                                  one per enemy (max 40)
    P;eid;name;class;dmg;heal;died                               one per guildie (max 40)
  Receivers merge a report into their own engagement when the zone matches and the times overlap; reports about
  fights they weren't in go to the guild feed (KKC.db.feed).
  Kills per enemy merge as the maximum (everyone in a group gets the same honor kill); a guildie's own damage and
  healing win over what someone else's meter said. Unknown kinds are ignored, so later versions can add more.
]]

local _, KKC = ...
local S = {}
KKC.Sync = S

local PREFIX = "KKC1"
local SEP = ";"
local MAX_LIST = 40

-- ------------------------------------------------------------------------------------------------
-- Sending: a small queue, one message every 0.3 s, never in combat or chat lockdown
-- ------------------------------------------------------------------------------------------------

local queue, pumping = {}, false

local function canSend()
    if not IsInGuild() then return false end
    if InCombatLockdown() then return false end
    if C_ChatInfo.InChatMessagingLockdown and KKC.try(C_ChatInfo.InChatMessagingLockdown) then return false end
    return true
end

local function pump()
    if #queue == 0 then pumping = false; return end
    if not canSend() then return C_Timer.After(2, pump) end
    KKC.try(C_ChatInfo.SendAddonMessage, PREFIX, table.remove(queue, 1), "GUILD")
    C_Timer.After(0.3, pump)
end

local function send(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = KKC.clean((select(i, ...))) end
    local msg = table.concat(parts, SEP)
    if #msg > 250 then msg = msg:sub(1, 250) end
    queue[#queue + 1] = msg
    if not pumping then
        pumping = true
        C_Timer.After(0.3, pump)
    end
end

function S.Broadcast(e)
    if e.test or not IsInGuild() then return end
    local enemies = KKC.sortedValues(e.enemies)
    local n = math.min(#enemies, MAX_LIST)
    local opened = e.opened == true and 1 or (e.opened == false and 0 or "")
    send("H", e.id, e.start, e.stop, e.zone, e.subzone, e.pvpSeconds or 0, KKC.myClass() or "", n,
        opened, e.map or "", e.x or "", e.y or "")
    for i = 1, n do
        local en = enemies[i]
        send("E", e.id, en.name, en.class or "", en.race or "", en.kills or 0)
    end
    for i, m in ipairs(KKC.sortedValues(e.members)) do
        if i > MAX_LIST then break end
        send("P", e.id, m.name, m.class or "", math.floor(m.dmg or 0), math.floor(m.heal or 0), m.died and 1 or 0)
    end
end

KKC.Listen("EngagementClosed", S.Broadcast)

-- ------------------------------------------------------------------------------------------------
-- Receiving. A report merges into our own engagement when it fits one (same zone, overlapping time). Otherwise it goes
-- into the guild feed (fights we weren't in), where reports from several guildies about the same fight merge too.
-- Reports are kept for a while: one that arrives while we're still fighting moves from the feed to our engagement as
-- soon as that exists.
-- ------------------------------------------------------------------------------------------------

local KEEP = 600 -- seconds a report can still move from the feed to an engagement of ours
local reports = {} -- eid -> { who, start, stop, zone, subzone, pvpSeconds, class, at, enemies = {}, members = {}, target, feed }

local function nonEmpty(v) if v and v ~= "" then return v end end

local function changed(e)
    if e.feed then
        e.minor = not KKC.IsNotable(e)
        KKC.Fire("FeedUpdated", e)
        return
    end
    if e.minor ~= nil and not e.test then e.minor = not KKC.IsNotable(e) end
    KKC.Fire("EngagementUpdated", e)
end

local function mergeEnemy(e, en)
    local mine = e.enemies[en.name] or { name = en.name, kills = 0 }
    e.enemies[en.name] = mine
    mine.class = mine.class or en.class
    mine.race = mine.race or en.race
    mine.kills = math.max(mine.kills or 0, en.kills or 0)
end

local function mergeMember(e, who, p)
    if p.name == KKC.me() then return end -- nobody else speaks for you
    local m = e.members[p.name] or { name = p.name }
    e.members[p.name] = m
    m.class = m.class or p.class
    if p.name == who then
        m.dmg, m.heal, m.reported = p.dmg, p.heal, true
    elseif not m.reported then
        m.dmg = math.max(m.dmg or 0, p.dmg)
        m.heal = math.max(m.heal or 0, p.heal)
    end
    if p.died then m.died = true end
end

local function mergeInto(e, r)
    e.reports[r.who] = r.start
    e.opens = e.opens or {}
    e.opens[r.who] = r.opened
    if not e.map and r.map then e.map, e.x, e.y = r.map, r.x, r.y end
    if e.feed then
        e.start, e.stop = math.min(e.start, r.start), math.max(e.stop, r.stop)
        e.owner = KKC.Initiator(e)
        if e.subzone == "" then e.subzone = r.subzone end
    end
    local m = e.members[r.who] or { name = r.who }
    e.members[r.who] = m
    m.class = m.class or r.class
    m.reported = true
    e.pvpSeconds = math.max(e.pvpSeconds or 0, r.pvpSeconds)
    for _, en in pairs(r.enemies) do mergeEnemy(e, en) end
    for _, p in pairs(r.members) do mergeMember(e, r.who, p) end
    changed(e)
end

local function removeFromFeed(entry)
    for i, e in ipairs(KKC.db.feed) do
        if e == entry then table.remove(KKC.db.feed, i); break end
    end
end

-- A fight of ours after all: the report (and the feed entry it made) moves over.
local function adopt(e, r)
    if r.feed then
        removeFromFeed(r.feed)
        r.feed = nil
    end
    r.target = e
    mergeInto(e, r)
end

local function toFeed(r)
    for i = 1, math.min(30, #KKC.db.feed) do
        local f = KKC.db.feed[i]
        if KKC.Tracker.Fits(f, r.start, r.stop, r.zone) then
            r.feed = f
            return mergeInto(f, r)
        end
    end
    local f = {
        id = r.who .. "-" .. r.start, owner = r.who, start = r.start, stop = r.stop, zone = r.zone, subzone = r.subzone or "",
        pvpSeconds = 0, allies = 0, feed = true, enemies = {}, members = {}, ownKills = {}, reports = {},
    }
    table.insert(KKC.db.feed, 1, f)
    KKC.Prune(KKC.db.feed, "feed")
    r.feed = f
    mergeInto(f, r)
end

-- Our engagement changed or closed: pick up reports about it that went to the feed.
local function adoptWaiting(e)
    if e.test then return end
    local now = KKC.now()
    for eid, r in pairs(reports) do
        if now - r.at > KEEP then
            reports[eid] = nil
        elseif not r.target and KKC.Tracker.Fits(e, r.start, r.stop, r.zone) then
            adopt(e, r)
        end
    end
end

local adopting
local function onOurs(e)
    if adopting then return end -- mergeInto fires EngagementUpdated itself
    adopting = true
    pcall(adoptWaiting, e)
    adopting = false
end
KKC.Listen("EngagementUpdated", onOurs)
KKC.Listen("EngagementClosed", onOurs)

local function destination(r) return r.target or r.feed end

local handlers = {}

function handlers.H(who, f)
    local start, stop = tonumber(f[3]), tonumber(f[4])
    if not (start and stop) then return end
    local opened -- nil: unknown (older version)
    if f[10] == "1" then opened = true elseif f[10] == "0" then opened = false end
    local r = {
        who = who, start = start, stop = stop, zone = f[5], subzone = f[6] or "", pvpSeconds = tonumber(f[7]) or 0,
        class = nonEmpty(f[8]), at = KKC.now(), enemies = {}, members = {},
        opened = opened,
        map = tonumber(f[11]), x = tonumber(f[12]), y = tonumber(f[13]),
    }
    reports[f[2]] = r
    local e = KKC.Tracker.Match(start, stop, r.zone)
    if e then
        r.target = e
        mergeInto(e, r)
    else
        toFeed(r)
    end
end

function handlers.E(who, f)
    local r, name = reports[f[2]], nonEmpty(f[3])
    if not (r and name and r.who == who) then return end
    local en = { name = name, class = nonEmpty(f[4]), race = nonEmpty(f[5]), kills = tonumber(f[6]) or 0 }
    r.enemies[name] = en
    local e = destination(r)
    if e then mergeEnemy(e, en); changed(e) end
end

function handlers.P(who, f)
    local r, name = reports[f[2]], nonEmpty(f[3])
    if not (r and name and r.who == who) then return end
    local p = { name = name, class = nonEmpty(f[4]), dmg = tonumber(f[5]) or 0, heal = tonumber(f[6]) or 0, died = f[7] == "1" }
    r.members[name] = p
    local e = destination(r)
    if e then mergeMember(e, who, p); changed(e) end
end

local function split(text)
    local f = {}
    for part in (text .. SEP):gmatch("(.-)" .. SEP) do f[#f + 1] = part end
    return f
end

KKC.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix ~= PREFIX or channel ~= "GUILD" then return end
    if not (KKC.readable(text) and KKC.readable(sender)) then return end
    KKC.raw.sender = sender
    local who = KKC.short(sender)
    if not who or who == KKC.me() then return end
    local f = split(text)
    local handler = handlers[f[1]]
    if handler and f[2] then handler(who, f) end
end)

KKC.Listen("Init", function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        S.prefixRegistered = KKC.try(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    end
end)
