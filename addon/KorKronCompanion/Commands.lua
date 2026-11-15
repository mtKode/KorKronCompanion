--[[
  /kkc                 open (or close) the Hall of the Kor'kron
  /kkc log [all]       recent battles in chat (all: with skirmishes)
  /kkc card [n]        battle card for battle n (default: the latest notable one, or its whole campaign)
  /kkc campaign [n]    campaign card for outing n (default: the latest): every fight of one night as one report
  /kkc copy [n]        report text straight to the copy box (default like card)
  /kkc day | week | lastweek | month | lastmonth    the hall's chronicle for that period
  /kkc battles | ledger | settings                  the hall on that section
  /kkc guild [n]       the hall's From the field section, or the battle card of guild feed battle n
  /kkc notify off|quiet|toast|prompt     how you're told about a battle (default quiet: one chat line)
  /kkc all on|off      notify you even when you're not the initiator
  /kkc sync on|off     share battles with guildies over hidden guild messages (off by default)
  /kkc rollcall        a roll call of the guild in your group now, on a sheet beside the raid panel (for Print Screen)
  /kkc rollcall report on|off   roll calls in the report text too (off: just on the battle card)
  /kkc minimap on|off  show or hide the minimap button (left click: the hall, right click: the latest report)
  /kkc ledger chat     your War Ledger totals in chat
  /kkc test            a made-up engagement to preview the toast, card and texts
  /kkc close           close the open engagement now instead of waiting
  /kkc debug           which game APIs and restrictions this client has (post the output)
  /kkc reset           wipe the log (the ledger stays)
]]

local _, KKC = ...

-- Battle n of the log; without n the latest notable battle, or the whole campaign it belongs to (one report per
-- outing is what the guild posts).
local function pick(n)
    local log = KKC.db.log
    n = tonumber(n)
    if n then return log[n] end
    local latest
    for _, e in ipairs(log) do if not e.minor then latest = e; break end end
    latest = latest or log[1]
    return latest and (KKC.Campaign.Of(latest) or latest)
end

local function yesNo(v)
    if v == nil then return "nil" end
    if not KKC.readable(v) then return "|cffffd100secret|r" end
    return v and "|cff60ff60yes|r" or "|cffff6060no|r"
end

local function debug()
    local version, build, _, interface = GetBuildInfo()
    KKC.say(("Kor'kron Companion %s on %s (%s), interface %s"):format(KKC.VERSION, tostring(version), tostring(build), tostring(interface)))

    local available, reason
    if C_DamageMeter and C_DamageMeter.IsDamageMeterAvailable then available, reason = KKC.try(C_DamageMeter.IsDamageMeterAvailable) end
    KKC.say(("  damage meter: %s %s"):format(yesNo(available), KKC.readable(reason) and reason or ""))
    KKC.say("  meter enums: " .. yesNo(Enum and Enum.DamageMeterType ~= nil and Enum.DamageMeterSessionType ~= nil))
    if C_CombatLog and C_CombatLog.IsCombatLogRestricted then
        KKC.say("  combat log restricted: " .. yesNo(KKC.try(C_CombatLog.IsCombatLogRestricted)))
    end
    KKC.say("  CombatLogGetCurrentEventInfo: " .. yesNo(type(CombatLogGetCurrentEventInfo) == "function"))
    KKC.say("  issecretvalue: " .. yesNo(type(issecretvalue) == "function"))

    local RA = C_RestrictedActions
    if RA and RA.IsAddOnRestrictionActive and Enum and Enum.AddOnRestrictionType then
        local active = {}
        for name, value in pairs(Enum.AddOnRestrictionType) do
            if KKC.try(RA.IsAddOnRestrictionActive, value) then active[#active + 1] = name end
        end
        KKC.say("  restrictions active now: " .. (#active > 0 and table.concat(active, ", ") or "none"))
    end

    KKC.say(("  honor kill patterns: %d (should be 4)"):format(KKC.Tracker.HonorPatternCount()))
    -- World positions: what matches a battle over a zone's border (KKC.Near).
    do
        local map = C_Map and KKC.try(C_Map.GetBestMapForUnit, "player")
        local pos = KKC.readable(map) and type(map) == "number" and KKC.try(C_Map.GetPlayerMapPosition, map, "player")
        local x, y
        if pos and KKC.readable(pos) and pos.GetXY then x, y = KKC.try(pos.GetXY, pos) end
        local w = KKC.readable(x) and type(x) == "number" and KKC.WorldPos(map, x, y)
        KKC.say("  world position: " .. (w and ("yes (continent %d, %.0f, %.0f yards)"):format(w[1], w[2], w[3])
            or ("no" .. (type(x) == "number" and " (map position readable, world position not)" or " (map position hidden)"))))
    end
    KKC.say("  in guild: " .. yesNo(IsInGuild()) .. ", addon prefix registered: " .. tostring(KKC.Sync.prefixRegistered))
    local st = KKC.Sync.stats
    KKC.say(("  guild sync %s: %d sent, %d refused%s, %d given up, %d waiting to send, %d fights waiting their turn, %d left to raidmates"):format(KKC.settings().sync and "on" or "off", st.ok, st.refused,
        st.lastCode and (" (last code " .. tostring(st.lastCode) .. ")") or "", st.dropped, KKC.Sync.Pending(), KKC.Sync.Waiting(), st.quiet or 0))
    KKC.say("  chat lockdown: " .. yesNo(C_ChatInfo.InChatMessagingLockdown and KKC.try(C_ChatInfo.InChatMessagingLockdown)))

    -- Only IsEnabled: every other C_Discord function (the guild link status too) is restricted to Blizzard's UI.
    local D = C_Discord
    KKC.say("  Discord integration enabled: " .. yesNo(D and D.IsEnabled and KKC.try(D.IsEnabled)))

    local first, second = UnitName("player")
    KKC.say(("  names: UnitName = [%s] [%s], full = [%s], regional unique: %s"):format(tostring(first), tostring(second),
        tostring(KKC.me()), yesNo(RegionalUniqueNamesEnabled and KKC.try(RegionalUniqueNamesEnabled))))
    KKC.say(("  raw names seen: honor [%s], kill [%s], meter [%s], addon sender [%s]"):format(
        tostring(KKC.raw.honor or "-"), tostring(KKC.raw.kill or "-"), tostring(KKC.raw.meter or "-"), tostring(KKC.raw.sender or "-")))

    local open = KKC.Tracker.Open()
    KKC.say(("  open engagement: %s, logged: %d, guild feed: %d"):format(open and KKC.Report.Headline(open) or "none", #KKC.db.log, #KKC.db.feed))
    local from, to = KKC.Summary.Range("week")
    KKC.say(("  this week: %s to %s"):format(date("%a %d %b %H:%M", from), date("%a %d %b %H:%M", to)))
    KKC.debugErrors = true
    KKC.say("  errors inside the addon are printed to chat from now on (until /reload).")
end

local commands = {}

commands.log = function(arg) KKC.UI.PrintLog(arg == "all") end

commands.card = function(arg)
    local e = pick(arg)
    if not e then return KKC.say("nothing logged yet. Try |cffffd100/kkc test|r.") end
    KKC.UI.ShowCard(e)
end

commands.copy = function(arg)
    local e = pick(arg)
    if not e then return KKC.say("nothing logged yet.") end
    KKC.UI.CopyReport(e)
end

commands.campaign = function(arg)
    local list = KKC.Campaign.Group(KKC.db.log)
    local c = list[tonumber(arg) or 1]
    if not c then return KKC.say("no campaign " .. (arg ~= "" and arg or "") .. " yet.") end
    KKC.UI.ShowCard(KKC.Campaign.View(c))
end

commands.minimap = function(arg)
    local m = KKC.settings().minimap
    if arg == "on" then m.hide = false elseif arg == "off" then m.hide = true end
    KKC.MinimapButton.Refresh()
    KKC.say("minimap button: |cffffd100" .. (m.hide and "hidden" or "shown") .. "|r (/kkc minimap on|off)")
end

commands.hall = function() KKC.Hub.Toggle() end
commands.rollcall = function(arg)
    -- /kkc rollcall report on|off: roll calls in the report text; otherwise a roll call now.
    local what, value = (arg or ""):match("^(%S+)%s*(%S*)")
    if what == "report" then
        if value == "on" then KKC.settings().rollcallsInReport = true elseif value == "off" then KKC.settings().rollcallsInReport = false end
        return KKC.say("roll calls in the report text: |cffffd100" .. (KKC.settings().rollcallsInReport and "on" or "off") .. "|r")
    end
    KKC.RollCall.ShowSheet()
end
for _, period in ipairs({ "day", "week", "lastweek", "month", "lastmonth" }) do
    commands[period] = function() KKC.Hub.Show("chronicle", period) end
end
commands.summary = commands.week
commands.battles = function() KKC.Hub.Show("battles") end
commands.settings = function() KKC.Hub.Show("settings") end

commands.guild = function(arg)
    local n = tonumber(arg)
    if not n then return KKC.UI.ShowSummary("guild", "week") end
    local e = KKC.db.feed[n]
    if not e then return KKC.say("no guild feed fight " .. n .. ".") end
    KKC.UI.ShowCard(e)
end

commands.notify = function(arg)
    local valid = { off = true, quiet = true, toast = true, prompt = true }
    if valid[arg] then KKC.settings().notify = arg end
    KKC.say("notify: |cffffd100" .. KKC.settings().notify .. "|r (off, quiet = one chat line, toast, prompt = open the card)")
end

commands.all = function(arg)
    if arg == "on" then KKC.settings().promptAll = true elseif arg == "off" then KKC.settings().promptAll = false end
    KKC.say("notify when not the initiator: " .. (KKC.settings().promptAll and "on" or "off"))
end

commands.sync = function(arg)
    if arg == "on" then KKC.settings().sync = true elseif arg == "off" then KKC.settings().sync = false end
    KKC.say("guild sync: |cffffd100" .. (KKC.settings().sync and "on" or "off") .. "|r"
        .. (KKC.settings().sync and " (notable battles are shared with guildies who run the addon)" or " (nothing is sent or read)"))
end

commands.ledger = function(arg)
    if arg == "chat" then return KKC.Ledger.Print() end
    KKC.Hub.Show("ledger")
end

commands.test = function()
    local e = KKC.Tracker.TestEngagement()
    KKC.UI.Notify(e, true)
end

commands.close = function()
    if not KKC.Tracker.Open() then return KKC.say("no open engagement.") end
    KKC.Tracker.CloseEngagement()
end

commands.debug = debug

commands.reset = function()
    wipe(KKC.db.log)
    KKC.say("log cleared.")
end

SLASH_KORKRONCOMPANION1 = "/kkc"
SLASH_KORKRONCOMPANION2 = "/korkron"
SlashCmdList.KORKRONCOMPANION = function(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    local fn = commands[cmd ~= "" and cmd or "hall"]
    if fn then return fn(arg) end
    KKC.say("commands: (none) opens the hall, log, card [n], campaign [n], copy [n], day, week, lastweek, month, lastmonth, battles, ledger, "
        .. "settings, guild [n], sync on|off, minimap on|off, notify off|quiet|toast|prompt, all on|off, test, close, debug, reset")
end
