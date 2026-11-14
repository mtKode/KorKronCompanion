# Kor'kron Companion

WoW: Forever addon for a world PvP guild. It logs PvP battles quietly in the background and keeps them in the
**Hall of the Kor'kron**: a chronicle per day, week or month, every battle with its battle card (a screenshot of who
was there) and the battle report text ready to paste, and a War Ledger of your deeds. Nothing pops up unless you ask
for it. Guild sync (sharing battles with guildies who run the addon) is off until it has been tested.

- Design and API constraints: [docs/DESIGN.md](docs/DESIGN.md)
- First evening after launch: [LAUNCH-CHECKLIST.md](LAUNCH-CHECKLIST.md)

## Install
Copy `addon\KorKronCompanion` into `World of Warcraft\_forever_\Interface\AddOns`. (`install-addon.ps1` in a local
checkout links it instead; it's not tracked in git.)

## Commands
| Command | |
|---|---|
| `/kkc` | Open or close the Hall of the Kor'kron (also the minimap button, and a side tab in the Legacy window) |
| `/kkc day` / `week` / `lastweek` / `month` / `lastmonth` | The hall's Chronicle for that period |
| `/kkc battles` / `ledger` / `settings` | The hall on that section |
| `/kkc guild [n]` | The hall's From the field section, or guild feed battle n's card |
| `/kkc card [n]` / `copy [n]` | Battle card / report text for battle n (default: the latest notable battle's whole campaign) |
| `/kkc campaign [n]` | Campaign card for outing n: every fight less than 30 min apart as one report |
| `/kkc log [all]` / `ledger chat` | Recent battles / War Ledger totals in chat |
| `/kkc notify off\|quiet\|toast\|prompt` | How you're told about a battle (default `quiet`: one chat line) |
| `/kkc all on\|off` | Tell you even when you weren't first into battle |
| `/kkc sync on\|off` | Share battles with guildies (default off) |
| `/kkc rollcall` | A roll call now on a sheet beside the raid panel, for a Print Screen (also shift click on the minimap button) |
| `/kkc minimap on\|off` | Show or hide the minimap button (left click: the hall, right click: the latest report, drag to move) |
| `/kkc test` | A made-up battle to preview the note and the card |
| `/kkc close` | Close the open battle now |
| `/kkc debug` | API and restriction report |
| `/kkc reset` | Clear the log (the ledger stays) |

## Files (`addon/KorKronCompanion`)
| File | Role |
|---|---|
| `Core.lua` | Helpers (secret-safe `readable`), names, Total RP 3 titles, saved data and migrations, event hub |
| `Theme.lua` | The look per faction: the book, the sheets (battle card, scribe window), the dark hall, buttons, bars |
| `Tracker.lua` | Combat segments, honor kills, meter read, battles |
| `Sync.lua` | Guild sync between guildies (rate-limited, off by default) |
| `Report.lua` | Stats, notable / first-into-battle rules, report text, share line |
| `Ledger.lua` | Per-character kill totals and the War Ledger challenge tracks |
| `Summary.lua` | Chronicles over a period (day, week, calendar month, all time) |
| `UI.lua` | Toast, battle card, copy box, notification rules |
| `Hub.lua` | The Hall of the Kor'kron and its Legacy side tab |
| `RollCall.lua` | Roll calls of the guild in your group every 10 minutes, attendance per outing, the roll call sheet |
| `Minimap.lua` | The minimap button |
| `Media/` | The addon's own textures (`tools/make_textures.py` makes them) |
| `Commands.lua` | `/kkc` |
