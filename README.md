# Kor'kron Companion

WoW: Forever addon for a world PvP guild. It logs PvP engagements quietly, merges what every guildie with the addon
saw, and gives the initiator a battle card (screenshot of who was there) and a copy box with the battle report text
filled in. Small fights can be shared to guild chat, which the Discord bridge carries to Discord.

- Design and API constraints: [docs/DESIGN.md](docs/DESIGN.md)
- First evening after launch: [LAUNCH-CHECKLIST.md](LAUNCH-CHECKLIST.md)

## Install
```
.\install-addon.ps1
```
Links `addon\KorKronCompanion` into `_forever_\Interface\AddOns` (`-Copy` for a plain copy to hand to guildies).

## Commands
| Command | |
|---|---|
| `/kkc` or `/kkc log [all]` | Recent engagements (`all` includes minor ones) |
| `/kkc card [n]` | Battle card (latest notable by default) |
| `/kkc copy [n]` | Battle report text in the copy box |
| `/kkc week` / `day` / `lastweek` | War report window: your fights over that period |
| `/kkc guild [n]` | War report window on the Guild feed tab (fights you weren't in), or feed fight n's card |
| `/kkc notify off\|quiet\|toast\|prompt` | How much it bothers you (default `toast`) |
| `/kkc all on\|off` | Notify you even when you're not the initiator |
| `/kkc ledger` | Your War Ledger totals |
| `/kkc test` | Fake engagement to preview the UI |
| `/kkc close` | Close the open engagement now |
| `/kkc debug` | API and restriction report |
| `/kkc reset` | Clear the log (ledger stays) |

## Files (`addon/KorKronCompanion`)
| File | Role |
|---|---|
| `Core.lua` | Helpers (secret-safe `readable`), names, Total RP 3 titles, saved data, event hub |
| `Theme.lua` | The look: Horde war-table frames, parchment, Morpheus titles, ink colors |
| `Tracker.lua` | Combat segments, honor kills, meter read, engagements |
| `Sync.lua` | Addon messages between guildies, merging reports |
| `Report.lua` | Stats, notable/initiator rules, copy text, share line |
| `Ledger.lua` | Per-character kill totals and milestones |
| `Summary.lua` | Day/week war reports over your log or the guild feed |
| `UI.lua` | Toast, battle card, copy box, notification rules |
| `Commands.lua` | `/kkc` |
