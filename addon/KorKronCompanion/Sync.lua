--[[
  Sharing engagements between guildies with the addon (hidden addon messages on the GUILD channel).

  When a notable engagement closes, each client sends what it saw, packed into at most four messages:
    H;eid;start;stop;zone;subzone;pvpSeconds;class;opened;map;x;y;leader;size   header (eid = owner-start;
                                                       opened 1/0/empty = struck first / hit first / unknown;
                                                       leader, size: the sender's party or raid, telling raids apart)
    E;eid;name,CLASS,race,kills/name,CLASS,race,kills/...           enemies, most kills first (up to two messages)
    P;eid;name,CLASS,dmg,heal,died/...                              guildies, the sender first (one message)
    R;eid;name,c/name,c/...                                         the raid's guildies, c = class number (up to
                                                                    four messages; one client per raid sends it)
  Receivers merge a report into their own engagement when the zone matches and the times overlap; reports about
  fights they weren't in go to the guild feed (KKC.db.feed).
  Kills per enemy merge as the maximum (everyone in a group gets the same honor kill); a guildie's own damage and
  healing win over what someone else's meter said. Unknown kinds are ignored, so later versions can add more.
  Several raids at one battle: a report from another raid (another leader) does not join your fight. It is kept
  beside it in e.raids[leader], for the battle's synchronization report (KKC.Host): every leader still writes the
  report of their own raid.

  Since Forever's launch the servers are strict about addon messages (what Overlord Forever, which syncs over the
  same channels, found the hard way):
    - custom channels are refused, so only GUILD is used;
    - many guild messages from one player can get all of that player's later addon messages dropped, while
      SendAddonMessage still answers success;
    - SendAddonMessage answers an Enum.SendAddonMessageResult; a throttled message was NOT sent.
  So guild messages here are kept rare: minor engagements are never sent, one client spends at most one message per
  TOKEN_SEC (BURST at once), nothing goes out while the guild is busy with our prefix, a refused message is retried
  later instead of lost, and nothing is sent or read inside an instance or in combat.
]]

local _, KKC = ...
local S = {}
KKC.Sync = S

local PREFIX = "KKC2" -- KKC1 (v0.1, one message per enemy) is not understood any more
local SEP = ";"
local LIMIT = 250 -- bytes per message (the server allows 255)

local OUT = {
    TOKEN_SEC = 15,      -- one message per 15 s per client on average...
    BURST = 4,           -- ...but one engagement (up to 4 messages) can go out at once
    GUILD_PER_MIN = 12,  -- hold back while the guild already carries this many of our messages a minute
    TTL = 300,           -- a message still waiting after 5 minutes is given up
    OUTBOX_MAX = 16,
    JITTER = 6,          -- guildies in the same fight close it at the same moment: spread their reports
}
local INTAKE_PER_MIN = 8 -- more than this from one sender in a minute is not ours to read

-- Results that mean "not sent, try again later": throttles, lockdown, a general error.
local RETRY_CODES = { [3] = true, [8] = true, [9] = true, [11] = true }
local NOT_IN_GUILD = 10

S.stats = { ok = 0, refused = 0, dropped = 0 }

-- ------------------------------------------------------------------------------------------------
-- Sending
-- ------------------------------------------------------------------------------------------------

local outbox = {}       -- { msg, at }
local heard = {}        -- GetTime() of every message with our prefix heard on GUILD (our own echo included)
local tokens, tokenAt = OUT.BURST, nil
local pumpTimer

local function inInstance() return (IsInInstance()) == true end

local function guildLoad()
    local now = GetTime()
    while heard[1] and now - heard[1] > 60 do table.remove(heard, 1) end
    return #heard
end

local function refill()
    local now = GetTime()
    if tokenAt then tokens = math.min(OUT.BURST, tokens + (now - tokenAt) / OUT.TOKEN_SEC) end
    tokenAt = now
end

local function blocked()
    if not IsInGuild() then return true end
    if InCombatLockdown() or inInstance() then return true end
    return C_ChatInfo.InChatMessagingLockdown and KKC.try(C_ChatInfo.InChatMessagingLockdown) or false
end

local pump
local function schedule(delay)
    if pumpTimer then pumpTimer:Cancel() end
    pumpTimer = C_Timer.NewTimer(math.max(0.3, delay), pump)
end

pump = function()
    pumpTimer = nil
    local now = GetTime()
    while outbox[1] and now - outbox[1].at > OUT.TTL do
        table.remove(outbox, 1)
        S.stats.dropped = S.stats.dropped + 1
    end
    if #outbox == 0 then return end
    if blocked() then return schedule(5) end
    refill()
    if tokens < 1 then return schedule((1 - tokens) * OUT.TOKEN_SEC) end
    if guildLoad() >= OUT.GUILD_PER_MIN then return schedule(10) end

    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, outbox[1].msg, "GUILD")
    -- Success is 0 on this client (true or nothing on older ones).
    local sent = ok and (result == nil or result == true or result == 0)
    if sent then
        table.remove(outbox, 1)
        tokens = tokens - 1
        S.stats.ok = S.stats.ok + 1
        return schedule(0.5)
    end
    S.stats.refused = S.stats.refused + 1
    S.stats.lastCode = ok and result or "error"
    if ok and result == NOT_IN_GUILD then
        wipe(outbox)
    elseif ok and RETRY_CODES[result] then
        tokens = 0 -- the server says slow down: wait a full token
        schedule(OUT.TOKEN_SEC)
    else
        table.remove(outbox, 1) -- a bad message stays bad
        schedule(0.5)
    end
end

local function enqueue(msgs)
    local now = GetTime()
    for _, msg in ipairs(msgs) do outbox[#outbox + 1] = { msg = msg, at = now } end
    while #outbox > OUT.OUTBOX_MAX do
        table.remove(outbox, 1)
        S.stats.dropped = S.stats.dropped + 1
    end
    if not pumpTimer then schedule(0.3) end
end

function S.Pending() return #outbox end

local function field(v) return (tostring(v == nil and "" or v):gsub("[\r\n;|,/]", " ")) end

local function line(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = field((select(i, ...))) end
    return table.concat(parts, SEP):sub(1, LIMIT)
end

-- "E;eid;" followed by as many "a,b,c/d,e,f" entries as fit, over at most maxMsgs messages.
local function packed(kind, eid, entries, maxMsgs)
    local msgs, cur = {}, nil
    local head = kind .. SEP .. field(eid) .. SEP
    for _, values in ipairs(entries) do
        local item = {}
        for i = 1, values.n do item[i] = field(values[i]) end
        local text = table.concat(item, ",")
        if cur and #cur + 1 + #text <= LIMIT then
            cur = cur .. "/" .. text
        else
            if cur then msgs[#msgs + 1] = cur end
            cur = nil
            if #msgs >= maxMsgs then break end
            cur = (head .. text):sub(1, LIMIT)
        end
    end
    if cur then msgs[#msgs + 1] = cur end
    return msgs
end

local function values(...) return { n = select("#", ...), ... } end

-- Class names <-> the one or two digits a roster sends.
local CLASS_LIST = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
    "DEATHKNIGHT", "MONK", "DEMONHUNTER", "EVOKER" }
local CLASS_NUM = {}
for i, c in ipairs(CLASS_LIST) do CLASS_NUM[c] = i end

-- withRoster: add the raid's guildies (R), for a raid that hasn't sent its roster yet.
function S.Messages(e, withRoster)
    local opened = e.opened == true and 1 or (e.opened == false and 0 or "")
    local msgs = { line("H", e.id, e.start, e.stop, e.zone, e.subzone, e.pvpSeconds or 0, KKC.myClass() or "",
        opened, e.map or "", e.x or "", e.y or "", e.raidLeader or "", e.groupSize or 0) }
    local enemies = {}
    for _, en in ipairs(KKC.sortedValues(e.enemies, function(a, b)
        if (a.kills or 0) ~= (b.kills or 0) then return (a.kills or 0) > (b.kills or 0) end
        return a.name < b.name
    end)) do enemies[#enemies + 1] = values(en.name, en.class or "", en.race or "", en.kills or 0) end
    -- You first (your own numbers count most), then whoever did the most.
    local me = KKC.me()
    local members = {}
    for _, m in ipairs(KKC.sortedValues(e.members, function(a, b)
        if (a.name == me) ~= (b.name == me) then return a.name == me end
        local x, y = (a.dmg or 0) + (a.heal or 0), (b.dmg or 0) + (b.heal or 0)
        if x ~= y then return x > y end
        return a.name < b.name
    end)) do
        if not m.outside then
            members[#members + 1] = values(m.name, m.class or "", math.floor(m.dmg or 0), math.floor(m.heal or 0), m.died and 1 or 0)
        end
    end
    for _, msg in ipairs(packed("E", e.id, enemies, 2)) do msgs[#msgs + 1] = msg end
    for _, msg in ipairs(packed("P", e.id, members, 1)) do msgs[#msgs + 1] = msg end
    if withRoster then
        local roster = {}
        for _, m in ipairs(KKC.sortedValues(e.members)) do
            if not m.outside then roster[#roster + 1] = values(m.name, CLASS_NUM[m.class or ""] or "") end
        end
        for _, msg in ipairs(packed("R", e.id, roster, 4)) do msgs[#msgs + 1] = msg end
    end
    return msgs
end

-- Has someone of this raid already sent its roster for this fight? Then one roster is enough.
local rosters = {} -- { leader, zone, start, stop, at } heard from our own raid
local function rosterHeard(e)
    if not e.raidLeader then return false end
    for _, r in ipairs(rosters) do
        if r.leader == e.raidLeader and KKC.Tracker.Fits(e, r.start, r.stop, r.zone) then return true end
    end
    return false
end

-- Only notable engagements are worth a guild message; minor ones stay in your own log.
function S.Broadcast(e)
    if not KKC.settings().sync then return end -- off until guild sync has been tested (/kkc sync on)
    if e.test or e.minor or not IsInGuild() then return end
    -- Decided after the jitter: by then a raidmate's roster may have come in, and ours isn't needed.
    C_Timer.After(1 + math.random() * OUT.JITTER, function()
        local roster = (e.groupSize or 0) > 0 and not rosterHeard(e)
        enqueue(S.Messages(e, roster))
    end)
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

-- Another raid at our battle: kept beside the fight in e.raids[leader], not mixed into our own warriors.
local function raidOf(e, r)
    e.raids = e.raids or {}
    local key = r.leader or r.who
    local raid = e.raids[key]
    if not raid then
        raid = { leader = r.leader, members = {}, enemies = {}, reporters = {} }
        e.raids[key] = raid
    end
    return raid
end

local function mergeRaidEnemy(raid, en)
    local t = raid.enemies[en.name] or { name = en.name, kills = 0 }
    raid.enemies[en.name] = t
    t.class, t.race = t.class or en.class, t.race or en.race
    t.kills = math.max(t.kills or 0, en.kills or 0)
end

local function mergeRaidMember(e, raid, name, class)
    if name == KKC.me() then return end
    if raid.members[name] == nil or raid.members[name] == "" then raid.members[name] = class or "" end
    -- Seen on our meter but of that raid: they go in its report, not ours.
    local m = e.members[name]
    if m and m.outside then e.members[name] = nil end
end

local function mergeRaid(e, r)
    local raid = raidOf(e, r)
    raid.reporters[r.who] = true
    raid.size = math.max(raid.size or 0, r.size or 0)
    raid.start = math.min(raid.start or r.start, r.start)
    raid.stop = math.max(raid.stop or r.stop, r.stop)
    mergeRaidMember(e, raid, r.who, r.class)
    for _, en in pairs(r.enemies) do mergeRaidEnemy(raid, en) end
    for _, p in pairs(r.members) do mergeRaidMember(e, raid, p.name, p.class) end
    for name, class in pairs(r.roster or {}) do mergeRaidMember(e, raid, name, class) end
    changed(e)
end

-- Is the sender in our raid? By its leader; without one (solo, or an older version that doesn't say), by whether we
-- had them in our group. Older versions send no size: their reports merge as they always did.
local function sameRaid(e, r)
    if r.size == nil then return true end
    if r.leader and e.raidLeader then return r.leader == e.raidLeader end
    local m = e.members[r.who]
    return m ~= nil and not m.outside
end

local mergeInto
local function place(e, r)
    r.other = not sameRaid(e, r)
    if r.other then mergeRaid(e, r) else mergeInto(e, r) end
end

function mergeInto(e, r)
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
    place(e, r)
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
    local opened -- nil: unknown
    if f[9] == "1" then opened = true elseif f[9] == "0" then opened = false end
    local r = {
        who = who, start = start, stop = stop, zone = f[5], subzone = f[6] or "", pvpSeconds = tonumber(f[7]) or 0,
        class = nonEmpty(f[8]), at = KKC.now(), enemies = {}, members = {},
        opened = opened,
        map = tonumber(f[10]), x = tonumber(f[11]), y = tonumber(f[12]),
        leader = nonEmpty(f[13]), size = tonumber(f[14]), roster = {},
    }
    reports[f[2]] = r
    local e = KKC.Tracker.Match(start, stop, r.zone)
    if e then
        r.target = e
        place(e, r)
    else
        toFeed(r)
    end
end

-- "a,b,c/d,e,f" -> { {a,b,c}, {d,e,f} }
local function entries(text)
    local list = {}
    for item in ((text or "") .. "/"):gmatch("(.-)/") do
        local v = {}
        for part in (item .. ","):gmatch("(.-),") do v[#v + 1] = part end
        if nonEmpty(v[1]) then list[#list + 1] = v end
    end
    return list
end

function handlers.E(who, f)
    local r = reports[f[2]]
    if not (r and r.who == who) then return end
    local e = destination(r)
    for _, v in ipairs(entries(f[3])) do
        local en = { name = v[1], class = nonEmpty(v[2]), race = nonEmpty(v[3]), kills = tonumber(v[4]) or 0 }
        r.enemies[en.name] = en
        if e and r.other then mergeRaidEnemy(raidOf(e, r), en) elseif e then mergeEnemy(e, en) end
    end
    if e then changed(e) end
end

function handlers.P(who, f)
    local r = reports[f[2]]
    if not (r and r.who == who) then return end
    local e = destination(r)
    for _, v in ipairs(entries(f[3])) do
        local p = { name = v[1], class = nonEmpty(v[2]), dmg = tonumber(v[3]) or 0, heal = tonumber(v[4]) or 0, died = v[5] == "1" }
        r.members[p.name] = p
        if e and r.other then mergeRaidMember(e, raidOf(e, r), p.name, p.class) elseif e then mergeMember(e, who, p) end
    end
    if e then changed(e) end
end

function handlers.R(who, f)
    local r = reports[f[2]]
    if not (r and r.who == who) then return end
    -- A raidmate sent our raid's roster: we needn't send it too.
    if r.leader then rosters[#rosters + 1] = { leader = r.leader, zone = r.zone, start = r.start, stop = r.stop } end
    while #rosters > 20 do table.remove(rosters, 1) end
    local e = destination(r)
    for _, v in ipairs(entries(f[3])) do
        local class = CLASS_LIST[tonumber(v[2] or "") or 0] or ""
        r.roster[v[1]] = class
        if e and r.other then mergeRaidMember(e, raidOf(e, r), v[1], class) end
    end
    if e then changed(e) end
end

local function split(text)
    local f = {}
    for part in (text .. SEP):gmatch("(.-)" .. SEP) do f[#f + 1] = part end
    return f
end

local intake = {} -- sender -> { GetTime() of their recent messages }

local function tooChatty(who)
    local now, list = GetTime(), intake[who] or {}
    intake[who] = list
    while list[1] and now - list[1] > 60 do table.remove(list, 1) end
    list[#list + 1] = now
    return #list > INTAKE_PER_MIN
end

KKC.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix ~= PREFIX or channel ~= "GUILD" then return end
    heard[#heard + 1] = GetTime() -- the guild's load counts everyone, our own echo too
    if not (KKC.db and KKC.settings().sync) then return end
    if inInstance() then return end
    if not (KKC.readable(text) and KKC.readable(sender)) then return end
    KKC.raw.sender = sender
    local who = KKC.short(sender)
    if not who or who == KKC.me() or tooChatty(who) then return end
    local f = split(text)
    local handler = handlers[f[1]]
    if handler and f[2] then handler(who, f) end
end)

KKC.Listen("Init", function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        S.prefixRegistered = KKC.try(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    end
end)
