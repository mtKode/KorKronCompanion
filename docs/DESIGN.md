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
- **Campaign**: one outing, the size the guild reports at (one post per night, "Time: 20:15 - 21:00"). Engagements
  less than `campaignGap` (30 min) apart, in any zone, are one campaign, so a wipe, corpse run and regroup stays in
  it. Skirmishes (a stray hit, no kills) never join or bridge a campaign. Nothing is stored: campaigns are grouped from the log when needed (`Campaign.lua`), and a campaign view looks
  like an engagement (summed damage and healing, enemies, kills, deaths, leaders), so the battle card and report texts
  serve both. Its account is kept on its first fight (`campaignDescription`). `/kkc card` opens the latest campaign;
  each fight can still be reported on its own from the Battles list, where fights are listed under their campaign.
- **Notable**: an engagement worth bothering you about. It needs at least one of: a kill, a guildie death, 2+ enemy
  players, or 20+ s of PvP combat. One stray hit from a passing rogue is logged as *minor* and never notifies.
- **First into battle**: the guildie whose engagement started first (ties: alphabetical). They're named in the
  reports and are the only one prompted by default. This is *not* the guild's event initiator, who gathered the group
  in Discord; the addon can't know that, and the report is posted by hand anyway. (In code: `KKC.Initiator`.)
- **Members and leaders**: when each segment ends, the group is read once. Every guildie in the party or raid is a
  member, near you or not: the meter and kill events only see what happens close to you, and a guildie at the far end
  of the camp must still be on the report. Their damage and healing show when the meter caught them. Non-guild group
  members are only counted. Whoever is party or raid leader (or raid assistant) is kept in `e.leaders`, and the report
  gets `Leaders:` / `Assists:` lines for Nazgrel, which asks who led.
- **Attackers you never target**: while in combat, enemy players on nearby nameplates who target you or a groupmate
  join the fight (when the client hides their target, being in combat near you is enough). Otherwise a hunter shooting
  you as you run would be in no source at all.
- **Kills are a minimum**: only killing blows your own client hears about count, so reports say "at least 10 slain"
  (`KKC.SlainText`). Guild sync would merge every guildie's view for exact numbers.
- **Ambush / struck first**: an auto attack, auto shot or spell cast while targeting an enemy player within 5 s before
  entering combat means *you* struck first. The fight counts as an ambush when the guildie first into battle didn't
  strike first. It's only counted (the chronicle's first-blow tile, two Ledger tracks): reports, the card and toasts
  stay neutral ("Clashed with 5 Alliance at Tarren Mill"), since it's often a guess and "Ambushed!" everywhere read
  like spam in testing.
- **Kills**: the first live test logged 22 battles and 0 kills from honor messages alone, which this client doesn't
  give addons reliably. `PARTY_KILL` (attackerGUID, targetGUID: killing blows by anyone in your group) is now the main
  source, as in Overlord. Per enemy the highest of killing blows, honor kills and meter deaths counts, so one death is
  never counted twice; a victim the client keeps secret still counts as slain (`unnamedKills`). Your own blows feed the
  War Ledger.
- **Card emphasis**: the card is the officers' proof of who of ours fought. Up to 13 warriors get one wide column
  (with TRP3 titles); more get two columns (26 names). Enemies are only tallied by race, in the card and the text.

## Data flow

```
in combat:   target/mouseover/nameplate sightings  ─┐
             killing blows (PARTY_KILL), honor kills ├─► current segment
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

Tracking always runs in the background; this only decides whether you're told. Reporting is done from the hall
(`/kkc`), when you choose.

Setting `notify`: `off` | `quiet` (one chat line, the default) | `toast` (a note on screen) | `prompt` (open the card).
- No popups by default. The 0.1 default `toast` is turned into `quiet` once (schema 2).
- Never anything during combat.
- Only notable engagements, and only for the guildie first into battle (`promptAll` for everyone).
- Minor engagements are kept in the log and never announced.

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

## The Hall of the Kor'kron (Hub.lua)

The main window (`/kkc`). Overlord style: dark parchment-textured panel in the faction's colors, war-table border,
faction banner and emblem, inset boxes, icon buttons. Sections on the left:

| Section | Contents |
|---|---|
| **Chronicle** | Your battles over Today / This week / Last week / This month / Last month / All time: four tiles (battles, foes slain, Kor'kron fallen, first blow ours/theirs), the details (contested ground, fought beside, most slain, by race and class, greatest battle, deadliest blades, most mending), the battles themselves. Scribe chronicle (copy) and Sound the horn (one line to guild chat). |
| **Battles** | Every battle you fought, newest first, 19 a page; skirmishes on request. Click one for its battle card. |
| **From the field** | The same chronicle over the guild feed (guildies' battles you weren't in). Copy only, never shared. Says so when guild sync is off. |
| **War Ledger** | Tiered challenges, Legacy style: total slain, unique foes, battles fought, first blows, ambushes weathered, each enemy race, each class. A row shows the next tier with a progress bar. |
| **Settings** | Announcing battles, who is told, guild sync, a test battle, diagnostics. |

Weeks and days follow the server's reset (`C_DateAndTime.GetWeeklyResetStartTime`, Wednesday on EU); months are
calendar months (local time).

**In the Legacy window:** our own side tab under Blizzard's three (the `common-sidetab` art, faction banner icon).
Clicking it lays the same hall over the Legacy content, without its own border, banner and crest. Blizzard's tabs and
closing the window take it away again. Blizzard's frames are only hooked (`HookScript`), never changed, so this can't
taint them. The Legacy window loads on demand, so the tab is attached on `ADDON_LOADED` of `Blizzard_LegacySystem`.

**Factions:** the Horde gets red and iron (Horde war table, Horde emblem and banner, "Lok'tar ogar!"); the Alliance
gets blue and gold (Alliance war table, emblem and banner, "For the Alliance!"). The battle card and toast follow
the same theme.

The feed: several guildies reporting the same fight merge into one entry (same zone and time rules as your own
fights). A report that lands in the feed while you're still fighting moves to your own battle once that exists
(within 10 min).

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
See the README. `/kkc` opens the hall; `/kkc debug` gives the API and restriction report.

## Later
1. **A real Legacy category**: Blizzard's Legacy list is built from achievement categories and every row expects a real
   achievement; inserting ours into it would risk tainting. The side tab avoids that. Revisit only if it's wanted.
2. Call to arms button, nemesis / kill-on-sight list.
3. Killer from death recap (`C_DeathRecap`) for "who killed me".
4. Optional companion Discord bot that reads shared lines from the bridge channel.
