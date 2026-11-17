# Kor'kron Companion: a short guide

The addon quietly logs every world PvP battle you're in and turns it into a battle report for the guild. You don't
have to do anything while you fight. Afterwards, everything is in the **Hall of the Kor'kron**: type `/kkc` or click the
banner by your minimap.

## What it does, and where you find it

| You want to… | Where |
|---|---|
| See your battles this week, this month, all time | Hall → **Chronicle**, pick a period on the left page |
| Find one battle | Hall → **Battles** (periods on the left page): one line per battle, grouped by day. Click a line for its battle card |
| Fold a long list away | Battles: the **+/−** in front of a campaign hides its fights; click a **day's heading** to hide that day |
| Open the battle card of your latest battle | `/kkc card`, or right click the minimap banner |
| Write the guild's battle report | Battle card → **Scribe report**: the report text in the guild's template, ready to copy |
| Post the report in guild or officer chat | In the Scribe report window: **Guild chat** / **Officer chat** (click twice; it posts a line every 1.5 s) |
| Post one line about a battle in guild chat | Off by default. Settings → **Sound the horn**, then Battle card → **Sound the horn** (in the Chronicle: a line about the whole period) |
| A clean screenshot of the card | Battle card → **Capture likeness** hides the buttons for a few seconds; press Print Screen |
| See who came and went through a night | Battle card of a campaign → **Roll calls** shows "joined 19:12" or "left 20:30" after the names (click again to hide). Right click it for the night roll call by roll call |
| See every raid of the guild at one battle | Battle card → **Multi-raid report** (shows only with guild sync, when other raids reported) |
| Take a roll call now | `/kkc rollcall`, or shift click the minimap banner |
| See battles guildies fought without you | Hall → **From the field** (needs guild sync) |
| Your own deeds and challenges | Hall → **War Ledger**, or the Legacy window (Y) → Challenges → **Kor'kron War Ledger** |
| Change how you're told about battles | Hall → **Settings** |

## Settings, in short

- **Your notice of a battle**: how you hear that a battle ended: Off, Quiet (one chat line), Toast (a note on
  screen), Card (the battle card opens). Every battle is logged either way.
- **Which battles you hear of**: *Raids I lead* (and fights outside a raid) or *Every battle*. Only your own notice:
  nothing is sent to anyone.
- **Guild sync**: shares your battles with guildies who have the addon, in hidden messages (never in guild chat).
  Without it, From the field and the Multi-raid report stay empty.
- **Sound the horn**: off by default, so nothing lands in guild chat from a stray click. On, battle cards and the
  Chronicle get a button that posts a one-line account in guild chat.
- **Comings and goings in the report**, **Overlord**, **Minimap button**, **Size of the hall**: each explains itself there.

## How it works

**A battle**
- It starts with the first PvP combat: an enemy player seen, an honor kill, or an enemy on the damage meter. It ends
  after a minute without PvP combat, so fights with short breaks are one battle.
- Notable or skirmish: a battle with a kill, one of ours fallen, 2+ enemies or 20+ seconds of PvP is notable. Anything
  less is a skirmish: kept, never announced or shared.
- Battles less than 30 minutes apart, in any zone, form a campaign: one report for the night.

**Who counts**
- Ours: everyone in your group when a fight starts or ends, near you or not. Better one too many on the report than
  a warrior left off.
- Guildies the meter sees who aren't in your group are listed apart ("seen outside our raid"), not counted as yours:
  they are likely in another raid, whose own report counts them.
- Enemies: players you or your group target or fight, that the meter lists, or that attack you from a nameplate.

**Kills**
- From killing blows by anyone in your group (the game tells the addon), honor kills and meter deaths. Per enemy the
  highest of the three counts, so one death is never counted twice.
- Still a minimum: kills far from you aren't heard, so reports say "at least 10 slain". Guild sync fills in what
  guildies' addons heard.
- The War Ledger counts only your own killing blows, so sharing can never count a kill twice there.
- Damage and healing come from your damage meter. Rankings use damage (healing) a minute of the battles each guildie
  was in, for those in at least 3 battles of the period, so being there often doesn't win by itself.

**Guild sync**
- Hidden addon messages over the guild channel: never in guild chat, never inside instances.
- Nothing is sent during a fight. When it ends, each addon waits its turn: the raid leader after 20–40 seconds,
  assistants after 2–4 minutes, members after 6–14 minutes and only if fewer than two of their raid have reported.
  So a raid usually sends one or two reports per battle, however many have the addon.
- Strictly rate-limited, a few messages per battle; a message that can't go yet waits rather than being lost. A report
  takes minutes to arrive, on purpose.
- A guildie's report is the same battle as yours when the times overlap and it was in the same zone, or your paths
  came within 300 yards (paths are recorded every 20 seconds, so fights on a zone border and long chases match).
  - Same battle, same raid: merged into your battle card. Names count once, kills take the highest view, your own
    numbers stay.
  - Same battle, another raid: under **Multi-raid report**.
  - Not your battle: under **From the field**.
- Only guildies online with the addon and sync on receive it; nothing is kept for those who log in later.

**Overlord** (only with that addon installed): read only. Nemesis marks are set when a battle ends; the standing of
the guilds is Overlord's own rating. Nothing is sent to it.

## Words that may not be obvious

| Word | Meaning |
|---|---|
| **Battle** | One fight: from the first PvP hit until a minute without combat |
| **Notable** | A battle worth reporting: a kill, one of ours fell, 2+ enemies, or 20+ seconds of PvP. Others are… |
| **Skirmish** | …a passing hit with no kills. Kept, never announced; Battles → **Show skirmishes** lists them |
| **Campaign** (outing) | Several battles less than 30 minutes apart, as one report for the night |
| **Battle card** | The sheet of one battle or campaign: who fought, the foes, the numbers, and its buttons |
| **First into battle** | The guildie whose fight started first. Named in the report, nothing more |
| **First blow, ours / theirs** | Who struck first: we did, or they ambushed us |
| **Kor'kron fallen** | Deaths on our side. "(you 25)" is how many of them were yours |
| **Roll call** | A list of the guild in your group (online, wherever they are), taken every 10 minutes. A campaign only notes from them who joined later or left early |
| **Guildies seen outside our raid** | Guildies the meter saw fighting who weren't in your group: likely another raid's, so not counted as yours |
| **From the field** | Guildies' battles that you weren't in (guild sync) |
| **Multi-raid report** | Every raid of the guild at one battle, each from its own addon users (guild sync) |
| **Contested ground** | Where you fought most in the period |
| **Deadliest blades / Most mending** | Damage / healing **a minute** of the battles each guildie was in, for those in 3+ battles of the period (not totals, so being there often doesn't win it) |
| **War Ledger** | Your own kills and challenges with tiers (Jungle Killer, Hunter of Humans…). Only your own killing blows count |
| **Tier** | A step of a challenge: slay 10, then 50, then 100… "Tier 2 of 4" is the step you're working on |
| **Nemesis** | One of Overlord's five most wanted enemies of the week (needs the Overlord addon), marked with a skull |
| **Standing of the guilds** | Overlord's guild rating for all of Forever, shown on top of the Chronicle (needs Overlord) |

## Commands worth knowing

`/kkc` the hall · `/kkc card` latest battle card · `/kkc rollcall` a roll call now · `/kkc test` a made-up battle to try
it all · `/kkc debug` what your client allows (send it along if something looks wrong). The rest: see the README.
