--[[
  Day and week summaries ("war reports") over a list of engagements: your own log, or the guild feed (guildies'
  fights you weren't in). Weeks follow the server's weekly reset, days the daily reset.
]]

local _, KKC = ...
local Summary = {}
KKC.Summary = Summary

local DAY, WEEK = 86400, 7 * 86400

local function number(v) return KKC.readable(v) and type(v) == "number" and v or nil end

local function weekStart()
    local now, D = KKC.now(), C_DateAndTime
    local s = D and number(KKC.try(D.GetWeeklyResetStartTime))
    if s and s <= now and s > now - WEEK - 3600 then return s end
    local left = D and number(KKC.try(D.GetSecondsUntilWeeklyReset))
    if left then return now + left - WEEK end
    return now - WEEK
end

local function dayStart()
    local now, D = KKC.now(), C_DateAndTime
    local left = D and number(KKC.try(D.GetSecondsUntilDailyReset))
    if left then return now + left - DAY end
    return now - DAY
end

-- period: "day" | "week" | "lastweek" -> from, to, label
function Summary.Range(period)
    if period == "day" then
        local s = dayStart()
        return s, s + DAY, "Today"
    elseif period == "lastweek" then
        local s = weekStart()
        return s - WEEK, s, "Last week"
    end
    local s = weekStart()
    return s, s + WEEK, "This week"
end

local function bump(map, key, n)
    if key and key ~= "" then map[key] = (map[key] or 0) + (n or 1) end
end

function Summary.Build(list, from, to)
    local me = KKC.me()
    local s = {
        from = from, to = to, engagements = 0, notable = 0, ambushed = 0, struck = 0, kills = 0, fallen = 0, myDeaths = 0, seconds = 0,
        places = {}, members = {}, enemies = {}, races = {}, classes = {}, dmg = {}, heal = {}, list = {},
    }
    local bestScore = -1
    for _, e in ipairs(list or {}) do
        if not e.test and e.start >= from and e.start < to then
            local st = KKC.Stats(e)
            s.engagements = s.engagements + 1
            if not e.minor then s.notable = s.notable + 1 end
            local ambushed = KKC.Ambushed(e)
            if ambushed then s.ambushed = s.ambushed + 1 elseif ambushed == false then s.struck = s.struck + 1 end
            s.kills = s.kills + st.kills
            s.fallen = s.fallen + #st.fallen
            s.seconds = s.seconds + (e.pvpSeconds or 0)
            bump(s.places, KKC.Report.Place(e))
            for name, m in pairs(e.members) do
                if name ~= me then bump(s.members, name) elseif m.died then s.myDeaths = s.myDeaths + 1 end
                if (m.dmg or 0) > 0 then bump(s.dmg, name, m.dmg) end
                if (m.heal or 0) > 0 then bump(s.heal, name, m.heal) end
            end
            for name, en in pairs(e.enemies) do
                local k = en.kills or 0
                if k > 0 then
                    bump(s.enemies, name, k)
                    bump(s.races, en.race, k)
                    bump(s.classes, en.class, k)
                end
            end
            local score = st.members + st.enemies + st.kills * 2
            if score > bestScore then bestScore, s.biggest = score, e end
            s.list[#s.list + 1] = e
        end
    end
    return s
end

-- "Tarren Mill (6), Southshore (4)" from a key -> count map, biggest first.
local function top(map, n, label, suffix)
    local list = {}
    for k, v in pairs(map) do list[#list + 1] = { k = k, v = v } end
    table.sort(list, function(a, b) if a.v ~= b.v then return a.v > b.v end return a.k < b.k end)
    local out = {}
    for i = 1, math.min(n, #list) do
        local v = list[i].v
        out[#out + 1] = (label and label(list[i].k) or list[i].k) .. " " .. (suffix and suffix(v) or v)
    end
    return #out > 0 and table.concat(out, ", ") or "none"
end

local function inParens(v) return "(" .. v .. ")" end
local function times(v) return "x" .. v end
local function plural(n, one, many) return n == 1 and one or many end

-- The chronicle as { label, text } lines (label may be nil), shared by the window and the copy text.
local function chronicle(s, guild)
    local lines = {}
    local function add(label, fmt, ...) lines[#lines + 1] = { label, fmt:format(...) } end
    if guild then add(nil, "Battles fought by guildies with the addon, while you were elsewhere.") end
    if s.engagements == 0 then
        add(nil, "No battles recorded. The blades stay sheathed... for now.")
        return lines
    end
    add("Battles", "%d (%d of note)  ~  %d foes slain  ~  %d Kor'kron fallen  ~  %s of battle",
        s.engagements, s.notable, s.kills, s.fallen, KKC.duration(s.seconds))
    if s.struck + s.ambushed > 0 then
        add("The first blow", "ours %d %s, theirs %d %s", s.struck, plural(s.struck, "time", "times"), s.ambushed, plural(s.ambushed, "time", "times"))
    end
    if not guild and s.myDeaths > 0 then add(nil, "You fell %d %s, and rose again.", s.myDeaths, plural(s.myDeaths, "time", "times")) end
    add("Contested ground", "%s", top(s.places, 4, nil, inParens))
    add(guild and "Kor'kron in the field" or "Fought beside", "%s", top(s.members, 5))
    add("Most slain", "%s", top(s.enemies, 4, nil, times))
    add("Slain by race", "%s", top(s.races, 6))
    add("Slain by class", "%s", top(s.classes, 9, KKC.className))
    if s.biggest then
        local st = KKC.Stats(s.biggest)
        add("Greatest battle", "%s, %s - %d against %d, %d slain", KKC.Report.Place(s.biggest), date("%a %H:%M", s.biggest.start),
            st.members, st.enemies, st.kills)
    end
    add("Deadliest blades", "%s", top(s.dmg, 3, nil, KKC.shortNumber))
    add("Most mending", "%s", top(s.heal, 3, nil, KKC.shortNumber))
    return lines
end

-- Periods run reset to reset (a week ends early on reset day), so the last full day is the one before `to`.
local function span(s)
    local text = date("%a %d %b", s.from)
    if s.to - s.from > DAY then text = text .. " to " .. date("%a %d %b", s.to - DAY) end
    return text
end

local function heading(label, guild) return (guild and "Word from the Field" or "War Chronicle of the Kor'kron") .. " - " .. label end

-- For the window: heading, date span and the body with ink-colored labels.
function Summary.Parts(s, label, guild)
    local T, out = KKC.Theme, {}
    for _, l in ipairs(chronicle(s, guild)) do
        out[#out + 1] = l[1] and (T.BLOOD .. l[1] .. ":|r " .. T.INK .. l[2] .. "|r") or (T.SOFT .. l[2] .. "|r")
    end
    return heading(label, guild), span(s), table.concat(out, "\n")
end

-- Plain text for the copy box.
function Summary.Text(s, label, guild)
    local out = { ("%s (%s)"):format(heading(label, guild):upper(), span(s)) }
    for _, l in ipairs(chronicle(s, guild)) do out[#out + 1] = l[1] and (l[1] .. ": " .. l[2]) or l[2] end
    return table.concat(out, "\n")
end

-- One line for guild chat. Only for your own battles.
function Summary.ShareLine(s, label)
    local line = ("[Kor'kron] %s: %d %s, %d %s slain, %d of ours fell."):format(
        label, s.engagements, plural(s.engagements, "battle", "battles"), s.kills, KKC.enemyFaction(), s.fallen)
    local place, count
    for k, v in pairs(s.places) do if not count or v > count then place, count = k, v end end
    if place and count > 1 then line = line .. (" Most blood spilled at %s (%d)."):format(place, count) end
    if s.kills > 0 then line = line .. " Lok'tar ogar!" end
    if #line > 255 then line = line:sub(1, 252) .. "..." end
    return line
end

