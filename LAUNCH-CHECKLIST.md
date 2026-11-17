# Launch checklist (v0.1)

Everything was written while the beta was closed. It was syntax-checked and run against a mocked WoW API (fights, honor
kills, meter read, sync between guildies, texts), but never in the real client. Go through this on launch night.
Run `/kkc debug` first and keep its output.

## 1. Install and load
- [ ] `.\install-addon.ps1` (links `addon\KorKronCompanion` into `_forever_\Interface\AddOns`).
- [ ] The addon is listed and **not** "out of date". The TOC says `## Interface: 16001`. If `/kkc debug` shows another
      interface number, update the TOC.
- [ ] No Lua error at login. Install BugSack/BugGrabber if errors are hidden.

## 2. `/kkc debug`
- [ ] `damage meter: yes`. If no, write down the reason it gives. Without the meter we lose damage/healing and the
      enemy list from it; honor kills and targets still work.
- [ ] `honor kill patterns: 4`.
- [ ] `names:` line: `full = [First Surname]`. After a kill and a guildie sync, the `raw names seen` line shows how
      honor messages, the meter and addon senders write double names. `KKC.short` (Core.lua) assumes
      "First Surname", "First Surname-Realm" or the link form "First-Surname". If any shows something else, fix it
      there, or the same guildie will show up twice.
- [ ] `restrictions active now` out of combat: ideally `none`. A `Map` restriction in open world zones would be bad news.
- [ ] Discord line shows your server and channel once the bridge is linked (Horde PvP link bug: see the Blizzard forum thread).

## 3. Preview without PvP
- [ ] `/kkc test`: the toast ("Ambushed!" on a parchment note with the Horde emblem) appears top center and
      disappears after 25 s.
- [ ] Battle card **look**: Horde war-table border with spiked corners, parchment page, "Battle Report" on the red
      Horde banner above the frame, faint Horde emblem behind the text, ornate dividers. If something shows as a
      green box or is missing, note which part. Each asset falls back on its own (Theme.lua).
- [ ] Titles use the Morpheus font. Ink text is readable on the parchment, including darkened class colors (Priest,
      Rogue and Mage are the ones to check).
- [ ] The close button sits inside the corner art, not on top of the spikes. If not, move it (`panel()` in UI.lua).
- [ ] Battle card: skulls and the damage/mend columns line up, and nothing overlaps.
- [ ] Button tooltips ("Scribe report", "Sound the horn", "Capture likeness") explain what each one does.
- [ ] With Total RP 3: a guildie with a TRP3 title shows it before their name ("Blood Guard Grukk ..."). The
      character name itself stays, because the officers need it.
- [ ] **Screenshot** hides the buttons and saves to `_forever_\Screenshots`.
- [ ] **Copy report**: Ctrl+C works and the paste looks right in Discord.
- [ ] Don't press **Share to guild** on the test card unless you want it in guild chat.

## 4. Real fight (2+ guildies with the addon)
- [ ] Kill an Alliance player and get the honor message: the enemy shows with a skull and `/kkc ledger` counts it.
- [ ] **Meter check (most important):** compare the card's damage/heal with the built-in meter's "Current" after one
      fight. If the card shows more after several fights close together, the meter's Current session isn't per fight
      and `Tracker.lua readMeter` must switch to sessions by ID (`GetAvailableCombatSessions`).
- [ ] Enemies you only damaged (no kill) show up. That's the meter's EnemyDamageTaken list; confirm it lists enemies,
      not your own group.
- [ ] Your guildie appears on your card (sync) and the same initiator shows on both clients.
- [ ] After a fight, `/kkc debug` → `guild sync: N sent, 0 refused …`. The report reaches the other client within
      about 10 s. If messages show as refused (code 3 or 8), or are sent but never arrive, note it: the server may be
      dropping our guild messages (see "Sync protocol" in docs/DESIGN.md).
- [ ] Overlord still syncs normally with Kor'kron Companion running alongside it (its network dot stays green).
- [ ] Only the initiator gets the toast. Nobody gets one for a stray hit (`/kkc log all` shows it as minor).
- [ ] Nothing pops up in combat.

- [ ] Open on an enemy player: card says "We struck first". Get jumped while not attacking: "Ambush", and the
      description starts with "Ambushed by". If casts at range don't count (cast time over 5 s before combat), raise
      `OPEN_WINDOW` in Tracker.lua.
- [ ] After a fight, `/dump KorKronCompanionDB.log[1].map, KorKronCompanionDB.log[1].x` shows numbers. Nil means
      the client hides the position and heatmaps won't be possible.

## 4a. The Hall of the Kor'kron
- [ ] `/kkc` opens the hall: dark parchment texture, war-table border in your faction's style, banner title, crest,
      guild name and your name at the top. The section buttons on the left switch pages.
- [ ] Chronicle: the six period buttons fit on one row; the tiles, details and battles don't overlap. "This month"
      says the month's name. The dates line ends with the time of battle; "Kor'kron fallen" shows "(you n)".
      Right page: "Standing of the guilds" on top as a podium (first in the middle, faction emblems, points; our
      guild named below when lower), then the details as sections: a yellow heading (Most slain, Greatest battle...)
      above two columns, names on the left and numbers on the right, a line between sections, scrolling when long.
- [ ] Resizing the hall: the grip in the bottom right corner scales the whole book (0.6 to 1.5 times), the top left
      corner stays put; the size is kept after closing and /reload. Right click on the grip: the usual size.
- [ ] Battles: rows open the battle card; Newer / Older page through. A campaign row has a +/- at its left edge:
      clicking it folds the outing's fights away (and back); clicking the row still opens the outing's card.
      Clicking a day's heading folds the whole day: its diamond dims, "(n battles folded away)"; again to unfold.
- [ ] War Ledger (hall): the same Legacy cards as in the Legacy window, the fun numbers card first (one column on the
      narrower page). Icons show (no green boxes; untouched tracks are grey), bars fill, "Tier 1 of 4". The cards
      scroll (wheel or the small bar on the right) and don't run past the page's bottom.
- [ ] Settings: seven rows on the right (announcing, who is told, guild sync, roll calls in the report, Overlord,
      minimap button, size of the hall), each as tall as its text; each button switches and the text follows.
      Notifications show "Quiet". Who is told: "Raid leaders" (in a raid only its leader gets the notice; alone or
      in a party, whoever fought) or "Everyone".
      Overlord off: no Nemesis marks, the Chronicle says the heralds were sent away. Minimap: the button hides and
      shows. Size: shows the percentage; "Usual size" resets a resized hall. Left page: Show test battle and
      Diagnostics.
- [ ] War Ledger left page, below the totals: deeds done (the bar shows "n / m" tiers) and the three challenges
      closest to glory. Nothing overlaps or runs off the page. "Lok'tar ogar!" sits above the guild's name.
- [ ] Chronicle: Deadliest blades and Most mending show "8.2k a minute  (12 battles)"; someone in only one or two of
      the week's battles isn't ranked.
- [ ] Legacy window (Y), Challenges: "Kor'kron War Ledger" is the last category in the list. Clicking it shows a
      card of fun numbers, then the War Ledger's challenges on Legacy cards (icons, bars, "Tier 1 of 4"). Clicking a
      Blizzard category brings its challenges back; reopening the window shows them too. Searching hides our
      category. Nothing in the Legacy window behaves differently afterwards, and no "blocked" popup appears.
- [ ] War Ledger geography: "Jungle Killer" and the other lands show, with kills from earlier battles already counted
      (filled once from the log). The fun numbers card shows "Bloodiest ground".
- [ ] With Overlord installed: the Chronicle's details end with "Overlord guild rating" (top three, and us if lower),
      once Overlord's leaderboard has loaded. A battle with a Nemesis in it: "Overlord Nemesis:" in the report text
      and a skull with the name in the card's foe heading. Right after login the Chronicle may say Overlord's heralds
      are "still counting the dead" until its leaderboard loads. Without Overlord: one line, "No herald of Overlord
      rides with you...", no Nemesis, no errors.
- [ ] After a real battle: one line in chat, no popup; the battle is in the hall.

## 4b. War reports
- [ ] `/kkc debug` "this week" line: starts at the last weekly reset (Wednesday morning on EU).
- [ ] `/kkc week` after a few fights: text fits in the window (long name lists may wrap into the fight list) and
      clicking a fight opens its card.
- [ ] A fight a guildie had without you shows on the **Guild feed** tab, credited to them, and its card can't be shared.
- [ ] A fight you were both in shows only on **My fights**, never in the feed.

## 5. Bridge
- [ ] **Sound the horn** on a real battle (not the test card, where it's disabled) posts the line in `/g` with no
      "blocked" popup. `SendChatMessage` is flagged `HasRestrictions` (it's fine from a button click in other
      clients). If it's blocked here, the horn has to become "copy the line" instead.
- [ ] The addon can't see whether guild chat is linked to Discord: every `C_Discord` call except `IsEnabled` is
      restricted (calling `GetGuildLinkStatus` raised the earlier popup).
- [ ] **Share to guild** posts one line in `/g`, and it shows up in the linked Discord channel.

## Things to note for v0.2
- Values that came back as secret (in `/kkc debug` or missing names on the card).
- Whether honor messages arrive for every kill your group gets.
- What should be tuned: merge gap (60 s), notable thresholds (20 s, 2 enemies).
