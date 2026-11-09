# Kor'kron Companion: design

A WoW: Forever addon for a world PvP guild. It quietly logs PvP engagements, merges what every guildie with the addon
saw, and turns notable fights into a **battle card** (screenshot proof of who was there) and a **copy box** with the
battle report text already filled in. Small fights can be shared to guild chat, which the built-in Discord bridge
carries to Discord.

Status: v0.1 written before launch (beta closed). Nothing has run in game yet. See [LAUNCH-CHECKLIST.md](../LAUNCH-CHECKLIST.md).

## Constraints (Forever client 1.60.1, checked against Blizzard's UI source on the `forever` branch)

The client is SoD-era content on a modern (Midnight-style) API with addon restrictions.

| Source | Status | Use |
|---|---|---|
| `COMBAT_LOG_EVENT_UNFILTERED` / `CombatLogGetCurrentEventInfo` | **Not usable.** The event is restricted and the getter doesn't exist. | None. The design does not depend on the combat log. |
| `C_DamageMeter` (built-in meter) | `SecretWhenInCombat`: readable **out of combat** | After each fight: damage, healing, deaths, enemy damage taken (names, class, faction, GUID). |
| `CHAT_MSG_COMBAT_HONOR_GAIN` | Not marked secret | Honorable kills: who died. Every group member who gets credit sees the same kill. |
| `UnitName/GUID/Race/Class` on target, mouseover, nameplates | May be secret while "unit identity restricted" | Spotting enemy players. Every value is checked with `issecretvalue` and skipped if hidden. |
| `C_ChatInfo.SendAddonMessage` (GUILD) | Allowed, unless in chat lockdown | Syncing between guildies. Only sent out of combat. |
| `SendChatMessage(..., "GUILD")` | Restricted for macros; fine from a button click | "Share to guild" button. |
| `C_Discord.GetGuildLinkStatus` | Available | Shows whether guild chat goes to Discord. |
| `C_RestrictedActions.IsAddOnRestrictionActive` | Available | Debug output; restrictions (Combat, Map, Chat…) |
| `Screenshot()` | Available | Screenshot button on the battle card. |

**Consequence:** the addon can't tell *who* landed a killing blow. It knows who died with honor credit (honor messages),
who fought (meter, sightings, sync) and damage/healing totals (meter). The battle report says "slain", not
"killed by X".

## Concepts

- **Segment**: one stretch of combat (`PLAYER_REGEN_DISABLED` → `PLAYER_REGEN_ENABLED`). PvP if an enemy player was
  seen, an honor kill came in, or the meter lists an enemy player.
- **Engagement**: PvP segments merged while the gap between them is under `mergeGap` (60 s). It closes when
  `mergeGap` passes with no new PvP combat.
- **Notable**: an engagement worth bothering you about. It needs at least one of: a kill, a guildie death, 2+ enemy
  players, or 20+ s of PvP combat. One stray hit from a passing rogue is logged as *minor* and never notifies.
- **First into battle**: the guildie whose engagement started first (ties: alphabetical). They're named in the
  reports and are the only one prompted by default. This is *not* the guild's event initiator, who gathered the group
  in Discord; the addon can't know that, and the report is posted by hand anyway. (In code: `KKC.Initiator`.)
- **Ambush / struck first**: an auto attack, auto shot or spell cast while targeting an enemy player within 5 s before
  entering combat means *you* struck first. The fight counts as an ambush when the guildie first into battle didn't
  strike first. That changes the wording ("Ambushed by 5 Alliance at Tarren Mill…") and is counted in war reports.

## Data flow

```
in combat:   target/mouseover/nameplate sightings  ─┐
             honor-kill messages                    ├─► current segment
out of combat (+1 s):  damage meter "Current" read ─┘
                                 │
                          engagement (merge segments, 60 s gap)
                                 │ closes
        ┌────────────────────────┼─────────────────────────┐
  broadcast own summary     receive guildies' summaries   decide notable / initiator
  (GUILD addon msg)         (overlapping time + zone →     │
                             merge)                        ▼
                                              notify (per setting) → battle card → copy box / share / screenshot
```

### Merging rules (several guildies saw the same fight)
- Same fight = same zone and time ranges overlapping, allowing for `mergeGap`.
- Participants = union of senders, grouped guildies and guildies in the meter.
- Kills per enemy = **max** over reports, not the sum. Everyone in the group gets the same honor kill, so adding
  them up would double count.
- Enemies = union by name. Race and class come from whichever report has them.
- Damage/healing per guildie: a guildie's own report wins over someone else's meter.

## Notifications (not invasive)

Setting `notify`: `off` | `quiet` (one chat line) | `toast` (default) | `prompt`.
- Never anything during combat.
- The toast shows after the engagement closes, only for notable engagements, only for the initiator (`promptAll` to
  get it as everyone). It disappears by itself after 25 s.
- Everyone else's addon sends its data silently. They can open the card from `/kkc log`.
- Minor engagements are kept in the log and never notify.

## Outputs

**Battle card** (frame): header with zone, date and time, duration and size (`4 v 6`); class-colored Kor'kron
participant list (rule #2 screenshot); enemies with ×kills; damage/healing columns; buttons **Copy report**,
**Share to guild**, **Screenshot**, **Close**. The description box is editable and prefilled with a draft.

**Copy box** text (paste under the battle report title):
```
Date: 2026-11-04
Time: 21:14 - 21:18
Brief Description: Ambushed by 6 Alliance at Tarren Mill. 5 slain, 1 Kor'kron fell.

Location: Hillsbrad Foothills - Tarren Mill
Kor'kron (4): Kaiva, Grukk, Zhara, Morth
Enemies (6): Arthas (Human Paladin) x2, Jaina (Human Mage), ...
Slain: 5 | Fallen: Grukk
```

**Share to guild** (≤255 chars, one line, goes to Discord through the bridge if linked):
`[Kor'kron] Tarren Mill held - 4 against 6 Alliance, 5 slain, Grukk fell in glory.`

## War reports (day / week)

Window `/kkc week` with two tabs:
- **My fights**: built from your own log. This is the report you copy or share. "Fought beside" counts the guildies
  who were in your engagements.
- **Guild feed**: guildies' fights you weren't part of, from synced reports. Several guildies reporting the same
  fight merge into one entry, using the same zone and time rules as your own fights. Read-only: it can be copied but
  not shared, because not everyone runs the addon and the report should be about fights you were part of. A report
  that lands in the feed while you're still fighting moves to your own engagement once that exists (within 10 min).

Periods are Today, This week and Last week. They follow the server's daily and weekly reset
(`C_DateAndTime.GetWeeklyResetStartTime`, so Wednesday on EU). A summary shows engagements (notable), slain, fallen,
fighting time, hot spots, fought beside / Kor'kron in the field, most slain, slain by race and by class, the biggest
fight, and top damage and healing. Fights in the period are listed underneath; click one for its battle card.

Retention: see Storage below. Your own fights are kept for a year, so longer summaries (3 months, a season) can be
built later.

## Look and voice (RP-PvP)

Every window should read like a Kor'kron dispatch, not an addon panel.
- **Frames**: Blizzard's Horde war-table border (the `BFAMissionHorde` nine-slice pieces, defined in Theme.lua), a
  parchment page (`ChromieTime-Parchment`), a faint `HordeEmblem` watermark, the `HordeFrame-Header` banner for
  titles, and `Campaign-QuestLog-LoreDivider` between sections. Every atlas is in the Forever atlas list and is
  checked again at runtime, with a plain fallback.
- **Type**: Morpheus for titles, Friz Quadrata for text, ink browns on parchment, a blood red for headings and
  ambushes. Class colors are darkened so they read on parchment.
- **Voice**: in-character labels ("Warriors of the Kor'kron", "Enemies of the Horde", "Account of the battle",
  "Scribe report", "Sound the horn", "Capture likeness", "War Chronicle", "Word from the Field"). Button tooltips
  say plainly what each one does. Descriptions and share lines vary per battle, picked from the start time so a
  battle always keeps the same wording. The copy text keeps the guild's exact fields (Date / Time / Brief
  Description) so Nazgrel and the officers can read it.
- **Total RP 3**: a guildie's TRP3 title is shown before their character name on the card. RP names aren't used,
  because the screenshot has to show character names.

Guild addons to keep in mind: Total RP 3 (+ Extended) and Overlord Forever (world PvP objectives, fronts,
territory). Overlord could later tag battles with the front or objective they were fought over; its API still needs
checking.

## Sync protocol (prefix `KKC2`, channel GUILD)

Since Forever's launch (2026-11-04) the servers are strict about addon messages. Overlord Forever, which syncs over
the same channels, documents this in its `SyncGuild.lua`:
- custom channels are refused (so we use GUILD only);
- a player who sends many guild addon messages may have every later one dropped, while `SendAddonMessage` still
  answers success;
- `SendAddonMessage` returns `Enum.SendAddonMessageResult`: 0 success, 3 `AddonMessageThrottle`,
  8 `ChannelThrottle`, 11 `AddOnMessageLockdown`, 10 `NotInGuild`, and so on. A throttled message was not sent.
- `CHAT_MSG_ADDON` is suspended inside instances.

So guild messages are kept rare:
- **Only notable engagements** are sent. Minor ones stay in your own log.
- **At most 4 messages per engagement**, packed: 1 header, up to 2 enemy messages (most kills first) and 1 guildie
  message. Whatever doesn't fit in 250 bytes is left out.
- **Per client: a token bucket**, burst 4, then one message per 15 s. A random 1–7 s delay spreads the reports of
  guildies who leave the same fight together.
- **Guild-wide: hold back** while 12 or more `KKC2` messages were heard in the last minute (our own echo included).
- **The result is checked.** Throttle, lockdown or error means retry after a full token; NotInGuild clears the queue.
  A message still waiting after 5 minutes is given up. `/kkc debug` shows sent / refused / given up / waiting.
- **Nothing is sent** in combat, in an instance, or during chat lockdown. Nothing is read in an instance.
- **Receivers read at most 8 messages a minute** from one sender.

Lines are `;`-separated (shown with `|` below). List entries are `,`-separated and joined with `/`.
- `H|eid|start|stop|zone|subzone|pvpSeconds|class|opened|map|x|y` engagement header (eid = `sender-start`,
  opened `1`/`0`/empty)
- `E|eid|name,CLASS,race,kills/...` enemies
- `P|eid|name,CLASS,dmg,heal,died/...` guildies

`KKC1` (v0.1, one message per enemy and per guildie) is no longer read. Unknown kinds are ignored, so later
versions can add more.

## Storage (SavedVariables `KorKronCompanionDB`)
The file is `WTF\Account\<account>\SavedVariables\KorKronCompanion.lua`, a plain Lua table written at logout or
`/reload`. Outside tools can read it directly (the same way WoW Oracle reads its addon's data), so long-term
statistics don't have to be computed in game.

- `schema`: format version (1). Bump it and add a step in `migrate()` (Core.lua) whenever a stored field changes
  meaning.
- `settings`: notify, promptAll, mergeGap, notable thresholds.
- `log`: your engagements, newest first, minor ones included (flagged). Kept 365 days / max 3000. It's account-wide;
  `owner` says which of your characters fought.
- `feed`: guildies' fights you weren't in. Kept 120 days / max 1500.
- `ledger`: per character, slain by race, by class, by enemy name, and totals. Updated from your own honor kills only,
  so syncing never counts a kill twice. It can be rebuilt from `log`.

One engagement record (both lists), everything needed for later statistics:

| Field | Meaning |
|---|---|
| `id`, `owner` | `owner-start`; the character it belongs to (feed: first into battle) |
| `start`, `stop` | Server time (epoch seconds) |
| `zone`, `subzone` | Display names (client language) |
| `map`, `x`, `y` | Map ID and 0-1 position where it started, for heatmaps (nil if the client hid it) |
| `pvpSeconds` | Seconds of actual fighting |
| `minor`, `feed` | Not notable; from the guild feed |
| `opened`, `opens[name]` | Struck first (true/false/nil), yours and per guildie |
| `reports[name]` | Each guildie's combat start (decides first into battle) |
| `members[name]` | Guildies: `class`, `dmg`, `heal`, `died`, `reported` |
| `enemies[name]` | `class` (token), `race`, `kills`, sometimes `guild` and `level` |
| `ownKills[name]` | Your own honor kills (ledger) |
| `allies` | Non-guild allies in your group |

Size: roughly 1 KB per engagement, so a busy year comes to a few MB. That's fine for SavedVariables.

Gaps a long-term report can't fill: fights where nobody had the addon, killing blows (no combat log), and enemies
known only by name when nobody targeted them.

## Commands
`/kkc` (log in chat) · `/kkc card [n]` · `/kkc week|day|lastweek` · `/kkc guild [n]` · `/kkc notify off|quiet|toast|prompt` · `/kkc ledger` · `/kkc test` (fake
engagement to preview the UI) · `/kkc debug` (API and restriction report for launch night) · `/kkc reset`.

## Later
1. **Legacy panel**: Forever's Legacy system (`Blizzard_LegacySystem`) is a ScrollBox data provider on top of
   achievements. Injecting a "Kor'kron War Ledger" category looks possible. Investigate after launch.
2. Patrol mode (one recap per outing), call to arms button, nemesis / kill-on-sight list.
3. Killer from death recap (`C_DeathRecap`) for "who killed me".
4. Optional companion Discord bot that reads shared lines from the bridge channel.
