--[[
  A light look at the Overlord addon, when it is installed: nothing more than reading what it already shows.
    - Nemesis: when a battle closes, foes on Overlord's Nemesis list (its five most wanted enemies of the week) are
      marked (en.nemesis), for the report and the battle card. Marked then, since the list changes every week.
    - Top guilds: Overlord's guild rating (points from kills, zones, outposts and keeps), shown in the Chronicle.
  No dependency: Overlord's global table is read only at the moment we need it, every call guarded, and anything
  missing (not installed, a renamed function, its leaderboard still building after login) just means nothing is
  shown. Nothing is sent, saved or changed in Overlord. Its functions aren't a published API, so an Overlord update
  may switch this off quietly. (Overlord's license is All Rights Reserved: call it, never copy its code.)
]]

local _, KKC = ...
local O = {}
KKC.Overlord = O

-- Overlord's global, unless switched off in the settings (KKC.settings().overlord == false).
local function off() return KKC.settings and KKC.settings().overlord == false end
local function overlord() return not off() and type(Overlord) == "table" and Overlord or nil end

-- Is this enemy on Overlord's Nemesis list right now?
local function wanted(name)
    local ov = overlord()
    local mw = ov and ov.MostWanted
    if type(mw) ~= "table" or type(mw.IsWanted) ~= "function" then return false end
    local ok, hit = pcall(mw.IsWanted, mw, name)
    return ok and hit and true or false
end

-- Called when a battle closes (Tracker), before it is announced.
function O.MarkNemeses(e)
    if not (e and e.enemies and overlord()) then return end
    for name, en in pairs(e.enemies) do
        if type(name) == "string" and wanted(name) then en.nemesis = true end
    end
end

-- The Nemeses of a battle: { { name, slain }, ... }, slain ones first.
function O.Nemeses(e)
    local out = {}
    for name, en in pairs(e and e.enemies or {}) do
        if en.nemesis then out[#out + 1] = { name = name, slain = (en.kills or 0) > 0 } end
    end
    table.sort(out, function(a, b) if a.slain ~= b.slain then return a.slain end return a.name < b.name end)
    return out
end

-- "Valandris (slain), Morgan" or nil.
function O.NemesisText(e)
    local list = O.Nemeses(e)
    if #list == 0 then return nil end
    local parts = {}
    for _, n in ipairs(list) do parts[#parts + 1] = n.name .. (n.slain and " (slain)" or "") end
    return table.concat(parts, ", ")
end

-- Why there is no rating to show: "absent" (Overlord not installed), "waiting" (its leaderboard is still being built,
-- as after login), "unreadable" (Overlord is there but not as we know it: an update changed it). Nil: it can be read.
function O.RatingStatus()
    if off() then return "off" end
    local ov = overlord()
    if not ov then return "absent" end
    local lb = ov.Leaderboard
    if type(lb) ~= "table" then return "unreadable" end
    local cache = rawget(lb, "_displayCache")
    if cache == nil then return "waiting" end
    if type(cache) ~= "table" then return "unreadable" end
    local rows = cache.sortedGuildRating
    if rows == nil or (type(rows) == "table" and #rows == 0) then return "waiting" end
    if type(rows) ~= "table" or type(rows[1]) ~= "table" or type(rows[1].guild) ~= "string" then return "unreadable" end
    return nil
end

-- The Chronicle's line when the rating can't be shown: in the hall's voice, not a diagnostic.
local QUIET = {
    absent = "No herald of Overlord rides with you, so the standing of the guilds goes unheard.",
    off = "You have sent Overlord's heralds away (Settings), so the standing of the guilds goes unheard.",
    waiting = "Overlord's heralds are still counting the dead. The standing of the guilds will follow.",
    unreadable = "Overlord's ledger is written in a hand we can no longer read. The standing of the guilds stays unknown.",
}
function O.QuietLine(status) return QUIET[status] end

-- Overlord's guild rating, top n: { { rank, guild, points, faction, mine }, ... }, plus our guild's row when it is
-- further down. Nil when Overlord isn't there or its leaderboard isn't built yet.
function O.TopGuilds(n)
    local ov = overlord()
    local lb = ov and ov.Leaderboard
    local cache = type(lb) == "table" and rawget(lb, "_displayCache")
    local rows = type(cache) == "table" and cache.sortedGuildRating
    if type(rows) ~= "table" or #rows == 0 then return nil end
    local myGuild = IsInGuild() and KKC.try(GetGuildInfo, "player")
    myGuild = KKC.readable(myGuild) and type(myGuild) == "string" and myGuild:lower() or nil
    local out, found = {}, false
    for i, row in ipairs(rows) do
        if i > 500 then break end
        if type(row) == "table" and type(row.guild) == "string" and tonumber(row.points) then
            local mine = myGuild ~= nil and row.guild:lower() == myGuild
            found = found or mine
            if i <= n or mine then
                out[#out + 1] = { rank = i, guild = row.guild, points = tonumber(row.points), faction = row.faction, mine = mine }
            end
        end
        if i >= n and (found or not myGuild) then break end
    end
    return #out > 0 and out or nil
end

-- "Overlord guild rating: 1. Name 1,250  2. ...  ...  12. Our guild 300" for the Chronicle, or nil.
function O.TopGuildsText(n)
    local top = O.TopGuilds(n or 3)
    if not top then return nil end
    local parts = {}
    for _, g in ipairs(top) do
        local name = g.guild
        if g.faction == "Horde" then name = "|cffd04a3a" .. name .. "|r"
        elseif g.faction == "Alliance" then name = "|cff4a8ad0" .. name .. "|r" end
        if g.mine then name = name .. " (us)" end
        parts[#parts + 1] = ("%d. %s  %s"):format(g.rank, name, BreakUpLargeNumbers and BreakUpLargeNumbers(g.points) or g.points)
    end
    return parts
end
