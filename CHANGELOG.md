# Changelog

What's changed in LootRuler, newest first. The version stays **1.0.0-beta** until it has been tried in a real raid; then
it becomes 1.0.0. Each line links the pull request it came from.

## 1.0.0-beta (not released yet: being tested)

### Easier on the eye (27 October 2026)

From the owner's in-game screenshots.

- Section titles fit on their gold plate, however long ("Need and Greed (group loot)" ran off it).
  ([#103](https://github.com/kcham01/LootRuler/pull/103))
- Every item search says what to type inside the box, as the Reserve tab's does ("Search Karazhan"), instead of in a line
  under it. ([#104](https://github.com/kcham01/LootRuler/pull/104))
- On / off switches are tick boxes, the game's own, in place of "[x]" and "[ ]" in their words.
  ([#105](https://github.com/kcham01/LootRuler/pull/105))
- The softres.it import is easier to reach: first on the Session tab (with the raid's link), on the Reserves tab's raid
  leader box, and as "Open and import from softres.it" when opening reserves. It was at the bottom of the Session tab,
  next to End session. ([#106](https://github.com/kcham01/LootRuler/pull/106))
- The Settings tab's sections open and close with a click, under three headings (for everyone, running loot, this window).
  Each says what's in it, like "Auto-roll: no rules yet", so the tab is a short list to start with; "Open all" shows
  everything. The long "Running loot" section is now four: rolling out loot, giving out and trading, raiders without
  LootRuler, and auctions. ([#107](https://github.com/kcham01/LootRuler/pull/107))
- Saying trades nearby has its own switch (Settings, "Giving out and trading"). A trade goes to one place only: the group
  when you're in one, /s when you're not. ([#108](https://github.com/kcham01/LootRuler/pull/108))
- A session's loot list only takes loot from inside its raid: a session left open no longer collects another raid's loot.
  Going into a different raid, or into its raid on a new lockout, asks whether to start a new session there (it can be
  switched off). ([#111](https://github.com/kcham01/LootRuler/pull/111))
- "Open a trade with the winner" is off to start with (Settings, "Giving out and trading"). Settings you already saved
  stay as they are. ([#110](https://github.com/kcham01/LootRuler/pull/110))
- Picking a disenchanter tells the raid who it is ("Dan is the disenchanter: items nobody wants go to them."), and taking
  them off says so too. ([#109](https://github.com/kcham01/LootRuler/pull/109))

### Faster (26 October 2026)

A benchmark of a 40-player raid night ([#89](https://github.com/kcham01/LootRuler/pull/89)) found where the loot runner's
addon worked hardest, and seven fixes followed. Nothing looks different; it all happens sooner and with less work. The
numbers are in [docs/benchmark.md](docs/benchmark.md).

- Opening reserves reaches every raider in 0.1 seconds, where it took 5.8 in a 40-player raid.
  ([#92](https://github.com/kcham01/LootRuler/pull/92), [#93](https://github.com/kcham01/LootRuler/pull/93))
- Rolling out loot: the loot runner's addon does about a third of the work it did, and its longest pause during a roll went
  from 36 ms to 12 ms. ([#91](https://github.com/kcham01/LootRuler/pull/91), [#94](https://github.com/kcham01/LootRuler/pull/94))
- While people reserve, the loot runner's addon does about half the work and makes far less garbage for the game to clean up.
  ([#90](https://github.com/kcham01/LootRuler/pull/90))
- Raiders' addons do about a quarter of the work while the raid forms: someone joining no longer sends the whole session to
  everyone. ([#92](https://github.com/kcham01/LootRuler/pull/92))
- Guild members outside the raid hear changes up to 5 seconds after raiders do, while the leader is in a group.
  ([#92](https://github.com/kcham01/LootRuler/pull/92))
- Several auctions at once send fewer updates when bids come in fast. ([#96](https://github.com/kcham01/LootRuler/pull/96))
- Finished timer bars stop redrawing every frame. ([#95](https://github.com/kcham01/LootRuler/pull/95))

### Added: reserves

- Reserve any item by its link, and raids LootRuler doesn't know yet (a new one, or *WoW: Forever*'s).
  ([#2](https://github.com/kcham01/LootRuler/pull/2))
- `!lr` in raid chat, so a whole pug can reserve without whispering. ([#5](https://github.com/kcham01/LootRuler/pull/5))
- Extra reserves for tanks, healers or anyone the leader picks. ([#19](https://github.com/kcham01/LootRuler/pull/19))
- Reserve several items for a player in one go. ([#30](https://github.com/kcham01/LootRuler/pull/30))
- softres.it: importing an updated sheet updates the reserves, without ever giving extra ones; names on the sheet find
  the right character, accents and other realms included; spreadsheets too, and the softres.it link posted in raid chat.
  ([#27](https://github.com/kcham01/LootRuler/pull/27), [#31](https://github.com/kcham01/LootRuler/pull/31),
  [#41](https://github.com/kcham01/LootRuler/pull/41), [#59](https://github.com/kcham01/LootRuler/pull/59))
- Hand the reserves to someone else, or take them over when the leader is gone. ([#34](https://github.com/kcham01/LootRuler/pull/34))
- Remind who hasn't reserved, in raid chat, and tell people who join. ([#35](https://github.com/kcham01/LootRuler/pull/35))
- Only the group can reserve (the leader's choice). ([#39](https://github.com/kcham01/LootRuler/pull/39))
- Swap requests: once reserves are locked, a raider asks to swap one, and the leader allows or refuses it.
  ([#87](https://github.com/kcham01/LootRuler/pull/87))
- Clear the reserves of players who aren't in the group, in one click. ([#88](https://github.com/kcham01/LootRuler/pull/88))

### Added: running the raid

- Raid setup: paste who's coming, invite them, say who's missing, sort the groups (`/lr raid`). ([#53](https://github.com/kcham01/LootRuler/pull/53))
- Your raid's name, message and icon, shown to raiders. ([#84](https://github.com/kcham01/LootRuler/pull/84))
- Bag checks: ask the group how many of some items they carry (`/lr bags`). ([#82](https://github.com/kcham01/LootRuler/pull/82))
- Raid gear: what everyone wears, best item level first (`/lr gear`). ([#83](https://github.com/kcham01/LootRuler/pull/83))
- Who has LootRuler, and which version (`/lr versions`). ([#3](https://github.com/kcham01/LootRuler/pull/3), [#52](https://github.com/kcham01/LootRuler/pull/52))
- When you become the master looter: open the loot master window, and tell the raid how to roll.
  ([#64](https://github.com/kcham01/LootRuler/pull/64))

### Added: rolling out loot

- The +1 rule: players who've won roll after those who haven't. ([#6](https://github.com/kcham01/LootRuler/pull/6))
- A disenchanter: items nobody wants go to them in one click. ([#7](https://github.com/kcham01/LootRuler/pull/7))
- Ctrl+Alt+click any item to roll it out. ([#13](https://github.com/kcham01/LootRuler/pull/13))
- See who reserved an item while it's rolled for, and in the game's loot window. ([#32](https://github.com/kcham01/LootRuler/pull/32))
- Undo an award, then give it to someone else or roll it again; change an award afterwards.
  ([#37](https://github.com/kcham01/LootRuler/pull/37), [#70](https://github.com/kcham01/LootRuler/pull/70))
- Roll windows for Gargul's rolls, for raiders without Gargul. ([#43](https://github.com/kcham01/LootRuler/pull/43))
- A corpse's loot posted in raid chat, with who reserved each item. ([#44](https://github.com/kcham01/LootRuler/pull/44))
- Give an item to someone without a roll. ([#45](https://github.com/kcham01/LootRuler/pull/45))
- "Your item is up": a message, a sound and a flashing icon when your reserve or wishlisted item is rolled out.
  ([#48](https://github.com/kcham01/LootRuler/pull/48), [#72](https://github.com/kcham01/LootRuler/pull/72))
- Everyone's rolls in the roll window. ([#49](https://github.com/kcham01/LootRuler/pull/49))
- Roll types of your own, like Transmog (`/roll 98`). ([#50](https://github.com/kcham01/LootRuler/pull/50))
- Item notes ("Warrior > Rogue") and thatsmybis wishlists, shown with the loot.
  ([#55](https://github.com/kcham01/LootRuler/pull/55), [#56](https://github.com/kcham01/LootRuler/pull/56))
- What everyone wears in that slot, beside their roll, including raiders without LootRuler.
  ([#63](https://github.com/kcham01/LootRuler/pull/63), [#69](https://github.com/kcham01/LootRuler/pull/69))
- Roll window options: skip what your class can't use, close after rolling, size. ([#61](https://github.com/kcham01/LootRuler/pull/61))
- Loot council: a council votes on who gets each item. ([#85](https://github.com/kcham01/LootRuler/pull/85))

### Added: less clicking

- Loot rules for the master looter: greens to the disenchanter, patterns to you, everything below epic in turn, pick up the
  gold. ([#10](https://github.com/kcham01/LootRuler/pull/10), [#58](https://github.com/kcham01/LootRuler/pull/58))
- Auto-roll: each raider's own rules for roll windows. ([#11](https://github.com/kcham01/LootRuler/pull/11))
- Need and Greed by your own rules, for group loot. ([#57](https://github.com/kcham01/LootRuler/pull/57))
- Your reserves where you see items: loot windows glow, tooltips say who reserved it. ([#12](https://github.com/kcham01/LootRuler/pull/12))

### Added: trading and keeping track

- Trade announcements: the raid hears what the loot master trades, stacks and enchants included.
  ([#9](https://github.com/kcham01/LootRuler/pull/9), [#36](https://github.com/kcham01/LootRuler/pull/36))
- Trades when you're not in a group are said nearby (/s) while you lead reserves: in a dungeon or raid straight away,
  elsewhere with one click on "Say it" (the game only lets addons /say on a click there).
  ([#102](https://github.com/kcham01/LootRuler/pull/102))
- Open a trade with the winner, with their item put in. ([#47](https://github.com/kcham01/LootRuler/pull/47))
- A warning before the 2 hours to trade an item run out; trade timers on screen; post what you hold (`/lr held`).
  ([#38](https://github.com/kcham01/LootRuler/pull/38), [#51](https://github.com/kcham01/LootRuler/pull/51),
  [#74](https://github.com/kcham01/LootRuler/pull/74))
- When the game won't hand an item over (full bags, too far away), the award is taken back and the loot master told why.
  ([#67](https://github.com/kcham01/LootRuler/pull/67))
- Loot given out without LootRuler: asked whether to record it. Group loot wins can count as given out.
  ([#65](https://github.com/kcham01/LootRuler/pull/65), [#73](https://github.com/kcham01/LootRuler/pull/73))
- Export who won what (spreadsheet, thatsmybis, DFT, or your own layout), for one raid or several, or post it in raid chat.
  ([#8](https://github.com/kcham01/LootRuler/pull/8), [#54](https://github.com/kcham01/LootRuler/pull/54))
- Who got what, in guild chat too. ([#60](https://github.com/kcham01/LootRuler/pull/60))
- Past raids: what each raid gave out, kept after it ends (`/lr history`). ([#20](https://github.com/kcham01/LootRuler/pull/20))
- Who got what over time, and how many raids they came to (`/lr fair`). ([#86](https://github.com/kcham01/LootRuler/pull/86))

### Added: GDKP

- Auctions bid on in raid chat, the pot, the organiser's cut, bonuses and payouts. ([#16](https://github.com/kcham01/LootRuler/pull/16))
- A switch so only "bid 150" counts as a bid. ([#18](https://github.com/kcham01/LootRuler/pull/18))
- Max bids ("bid for me up to 800g"). ([#21](https://github.com/kcham01/LootRuler/pull/21))
- Cuts for tanks and healers. ([#22](https://github.com/kcham01/LootRuler/pull/22))
- Change or take back a sale, starting bids in and out, payouts filled in at the mailbox. ([#62](https://github.com/kcham01/LootRuler/pull/62))
- For bidders: outbid alerts, a final call, the pot after each sale, and what's up next. ([#71](https://github.com/kcham01/LootRuler/pull/71))
- Pot rules of your own: named cuts, as a percent or as gold, for the players you pick. ([#78](https://github.com/kcham01/LootRuler/pull/78))
- Bookkeeping: gold in or out by hand, a ledger, and payouts out to a spreadsheet and back in. ([#79](https://github.com/kcham01/LootRuler/pull/79))
- Bidding ahead on items still waiting in the auction queue. ([#80](https://github.com/kcham01/LootRuler/pull/80))
- Several auctions at once: up to 12 items, numbered, ending together (`/lr batch`). ([#81](https://github.com/kcham01/LootRuler/pull/81))

### Added: guilds

- Boosted rolls with points per raid, and the guild book they live in. ([#14](https://github.com/kcham01/LootRuler/pull/14))
- Priority lists, kept in the game like a DFT sheet. ([#15](https://github.com/kcham01/LootRuler/pull/15))
- +1s and boosted roll points from Gargul, and back. ([#23](https://github.com/kcham01/LootRuler/pull/23))
- Alts share their main's points, as in Gargul. ([#24](https://github.com/kcham01/LootRuler/pull/24))

### Added: settings and trying it out

- A Settings tab with every option in one place. ([#4](https://github.com/kcham01/LootRuler/pull/4))
- A Test tab: pretend rolls and messages, only on your screen. ([#40](https://github.com/kcham01/LootRuler/pull/40))
- A practice raid of made-up players, to try everything on your own (`/lr say` for its raid chat). ([#77](https://github.com/kcham01/LootRuler/pull/77))
- A first-time tour, what's new after an update, and settings profiles. ([#66](https://github.com/kcham01/LootRuler/pull/66))
- One switch for LootRuler's sounds, and which channel they play on. ([#75](https://github.com/kcham01/LootRuler/pull/75))

### Fixed

- The softres.it import box (and the other boxes you paste lists into) could not be typed in. The cursor is now in the
  import box as soon as it opens, ready for Ctrl+V; a click anywhere in a box puts the cursor in it; nothing in the window
  can cover it; and it takes an export of any length. ([#101](https://github.com/kcham01/LootRuler/pull/101))
- Every login showed an error: LootRuler listened for the game's "disenchant roll" question, which TBC doesn't have (it
  came with Wrath). It now asks the game first, and the Need / Greed rules only offer Disenchant where the game has it.
  ([#100](https://github.com/kcham01/LootRuler/pull/100))
- "Forget it" on someone else's session (and the x beside one in the list) gave an error instead of forgetting it.
  ([#100](https://github.com/kcham01/LootRuler/pull/100))
- A GDKP session can't be ended by mistake while gold is still owed. ([#17](https://github.com/kcham01/LootRuler/pull/17))
- Re-importing an updated softres.it sheet didn't apply changed picks. ([#27](https://github.com/kcham01/LootRuler/pull/27))
- Closing a roll window left the strip of reservers on screen. ([#42](https://github.com/kcham01/LootRuler/pull/42))
- Renaming a misspelt softres.it name that had extra reserves lost all its reserves; saved data of the wrong kind wasn't
  checked when loading. ([#76](https://github.com/kcham01/LootRuler/pull/76))
- Two raid chat lines were reworded in LootRuler's own words. ([#68](https://github.com/kcham01/LootRuler/pull/68))

### Works with every version

Older and newer versions of LootRuler work together, so raiders don't have to update. Only the leader's addon decides
what's allowed, and players without LootRuler can do everything by typing. ([#2](https://github.com/kcham01/LootRuler/pull/2),
[#3](https://github.com/kcham01/LootRuler/pull/3))

### The first version (23 October 2026)

Soft and hard reserves inside the game, with `!lr` whispers for players without the addon, softres.it import and handing
the reserves to Gargul; every raid up to Zul'Aman with its loot in kill order; roll windows and the loot master window; and
the raid's loot list with trade help.
