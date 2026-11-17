--[[
  Campaigns: a night of world PvP as one report. The guild posts one battle report per outing (usually an hour or
  more: "Time: 20:15 - 21:00"), not one per skirmish, and a wipe, corpse run and regroup splits a fight into several
  engagements anyway.

  Nothing is stored for this: campaigns are grouped from the log whenever they're needed, so they work for battles
  logged before this existed. Engagements stay the unit of the statistics and the War Ledger; a campaign is a view.

    Campaign.Group(list)   newest-first engagements -> newest-first campaigns { fights (newest first), start, stop, id }
    Campaign.View(c)       an engagement-shaped table for the battle card and the report texts (campaign = true)
    Campaign.Latest()      the view of the newest campaign with two or more fights, or nil
]]

local _, KKC = ...
local Campaign = {}
KKC.Campaign = Campaign

-- Fights closer together than this (end of one to start of the next) are one campaign. An outing is usually an hour
-- or more with lulls in between; separate evenings never come this close.
function Campaign.Gap() return KKC.settings().campaignGap or 1800 end

function Campaign.Group(list)
    local out, current = {}, nil
    local gap = Campaign.Gap()
    for _, e in ipairs(list or {}) do
        if e.test then -- never part of anything
        elseif e.minor then
            -- A skirmish (a stray hit, no kills) stands alone: it never joins a campaign or bridges two fights into
            -- one, so a brush with a passer-by can't turn a single battle into a "campaign".
            out[#out + 1] = { fights = { e }, start = e.start, stop = e.stop or e.start }
        else
            -- The list is newest first: e is older than everything in current.
            if current and current.start - (e.stop or e.start) <= gap then
                current.fights[#current.fights + 1] = e
                current.start = math.min(current.start, e.start)
            else
                current = { fights = { e }, start = e.start, stop = e.stop or e.start }
                out[#out + 1] = current
            end
        end
    end
    for _, c in ipairs(out) do
        c.oldest = c.fights[#c.fights]
        c.id = c.oldest.id
        c.minor = true
        for _, e in ipairs(c.fights) do if not e.minor then c.minor = false end end
    end
    return out
end

function Campaign.View(c)
    local first = c.oldest
    local v = {
        campaign = true, anchor = first, id = "campaign-" .. tostring(c.id), owner = first.owner,
        start = c.start, stop = c.stop, zone = first.zone, subzone = first.subzone,
        fights = #c.fights, pvpSeconds = 0, allies = 0, ambushes = 0, struck = 0, minor = c.minor,
        enemies = {}, members = {}, ownKills = {}, reports = {}, leaders = nil, leadFights = {},
        places = {}, zones = {}, description = first.campaignDescription,
    }
    v.reports = first.reports -- first into battle: whoever opened the campaign's first fight
    v.fightList = c.fights    -- newest first; the synchronization report goes through them (KKC.Host)
    v.opened, v.opens, v.feed = first.opened, first.opens, first.feed
    local seenPlace, seenZone = {}, {}
    for i = #c.fights, 1, -1 do -- oldest first, so places come in the order they were fought over
        local e = c.fights[i]
        v.pvpSeconds = v.pvpSeconds + (e.pvpSeconds or 0)
        v.unnamedKills = (v.unnamedKills or 0) + (e.unnamedKills or 0)
        v.allies = math.max(v.allies, e.allies or 0)
        local ambushed = KKC.Ambushed(e)
        if ambushed then v.ambushes = v.ambushes + 1 elseif ambushed == false then v.struck = v.struck + 1 end
        local zone = e.zone or "?"
        if not seenPlace[zone] then
            seenPlace[zone] = { zone = zone, subs = {}, seen = {} }
            v.places[#v.places + 1] = seenPlace[zone]
        end
        local sub = e.subzone
        if sub and sub ~= "" and sub ~= zone and not seenPlace[zone].seen[sub] then
            seenPlace[zone].seen[sub] = true
            table.insert(seenPlace[zone].subs, sub)
        end
        local short = e.zone or "?" -- the title names whole zones; the subzones are in the report's Location line
        if not seenZone[short] then seenZone[short] = true; v.zones[#v.zones + 1] = short end
        for name, m in pairs(e.members or {}) do
            local t = v.members[name] or { name = name }
            v.members[name] = t
            t.class = t.class or m.class
            t.dmg = (t.dmg or 0) + (m.dmg or 0)
            t.heal = (t.heal or 0) + (m.heal or 0)
            if m.died then t.died = true; t.deaths = (t.deaths or 0) + 1 end
            if m.reported then t.reported = true end
            if not m.outside then t.inRaid = true end
        end
        for name, en in pairs(e.enemies or {}) do
            local t = v.enemies[name] or { name = name, kills = 0 }
            v.enemies[name] = t
            t.class, t.race = t.class or en.class, t.race or en.race
            t.nemesis = t.nemesis or en.nemesis
            t.kills = t.kills + (en.kills or 0)
        end
        for name, n in pairs(e.ownKills or {}) do v.ownKills[name] = (v.ownKills[name] or 0) + n end
        for name, role in pairs(e.leaders or {}) do
            v.leaders = v.leaders or {}
            if v.leaders[name] ~= "leader" then v.leaders[name] = role end
            if role == "leader" then v.leadFights[name] = (v.leadFights[name] or 0) + 1 end -- picks the main leader
        end
    end
    -- "Hillsbrad Foothills - Tarren Mill, Southshore; Alterac Mountains"
    local location = {}
    for _, p in ipairs(v.places) do
        location[#location + 1] = #p.subs > 0 and (p.zone .. " - " .. table.concat(p.subs, ", ")) or p.zone
    end
    v.location = table.concat(location, "; ")
    -- In your raid in any of the fights: one of yours. Only ever outside it: seen alongside (Stats).
    for _, t in pairs(v.members) do t.outside = not t.inRaid or nil end
    v.attendance = KKC.RollCall and KKC.RollCall.Attendance(v)
    for name, a in pairs(v.attendance and v.attendance.names or {}) do
        if not v.members[name] then v.members[name] = { name = name, class = a.class, dmg = 0, heal = 0, rollOnly = true } end
        v.members[name].outside = nil -- at a roll call of your raid
    end
    return v
end

-- What an outing is called: a campaign with guildies, a lone patrol on your own. Returns the name and its lowercase.
function Campaign.Name(view)
    if KKC.count(view.members) <= 1 then return "Lone Patrol", "lone patrol" end
    return "Campaign", "campaign"
end

-- The campaign an engagement belongs to (as a view), when it has two or more fights.
function Campaign.Of(e)
    for _, c in ipairs(Campaign.Group(KKC.db.log)) do
        for _, f in ipairs(c.fights) do
            if f == e then return #c.fights > 1 and Campaign.View(c) or nil end
        end
    end
end

function Campaign.Latest()
    local c = Campaign.Group(KKC.db.log)[1]
    if c and #c.fights > 1 then return Campaign.View(c) end
end

-- The same campaign again, rebuilt from the log (after another fight joined it).
function Campaign.Refresh(view)
    for _, c in ipairs(Campaign.Group(KKC.db.log)) do
        for _, f in ipairs(c.fights) do
            if f == view.anchor then return Campaign.View(c) end
        end
    end
    return view
end
