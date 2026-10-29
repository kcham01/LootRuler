# Changelog

What's changed in LootRuler, newest first. The version stays **1.0.0-beta** until it has been tried in a real raid; then
it becomes 1.0.0. Each line links the pull request it came from.

## 1.0.0-beta (not released yet: being tested)

- A new layout for every tab and window (the owner's picks from the mockups): one red button for the main thing to do on
  each screen, quieter buttons for the rest and plain links for rare or risky ones; content first, with the main actions
  pinned under the list and the rarer ones under "More..."; rules, state and actions apart; shorter explanations.
  - The tabs are called **My reserves** and **Reserved**.
  - **Session tab** (leader): softres.it first, standing out, with four red buttons: import, tell the raid how to
    reserve, hand the reserves over, and "End session"; then "This raid's rules" (how loot goes, reserves each, what
    can be reserved, who can, locking) and "Who gets what" (hard reserves, extra reserves, the disenchanter, the loot
    council), each row's choices lined up; "Your raid" (its name and message, and raid setup), +1s and boosted rolls fold
    away. A private session's top box has "End session" too, and ending asks "Yes" or "No". A hard reserve is lifted
    with an x, and extra reserves say "None" until someone has some. GDKP auctions, priority lists and reserves are one choice, "How loot goes".
  - **Opening reserves**: the raid you're in is picked, in a drop-down like the game's; softres.it or LootRuler side by
    side, with "Private session" under "Open reserves"; raid setup under them. Other options are on the Session tab
    once it's open.
  - **Players who left with reserves** show as a gold line at the top of the Reserved tab, naming them, with "Clear their
    reserves" right there (it's still under More too).
  - **Every x** (taking something off a list, closing a window) is the game's own red close button. Browsing the loot
    picks the raid from a drop-down too.
  - **First screen** (nothing open): running loot (import or open reserves) or just raiding, which says a raider can import
    a softres.it sheet into a private session when the loot master doesn't use LootRuler; then browse any raid's loot.
  - **A raider's Session tab**: how it stands for you in one line, the rules as four small boxes, the leader's message, and
    "Open your own reserves" and "Leave these reserves" (it asks first) as plain buttons.
  - **Reserved** (the old Reserves tab): how they stand in one line (open or locked, how many in the group reserved, Gargul); by item or by
    player with a search; each player in one row, "Change" opening their reserves, extra reserves and +1s; Lock, Post and
    Remind pinned under the list; Gargul, importing again and clearing absent players under More.
  - **My reserves**: the search first, a Reserve button on each item, and your reserves pinned under the list as slots.
  - **Loot tab**: what's to roll out first (Roll, or "Give to Ann" for a hard reserve), then what you have to trade (Open a
    trade), then what's given out (Change); everything else that dropped folds away. "Roll them all out" and "Post in raid
    chat" are pinned under it; the export, bag check and raid gear under More. Taking an award off is in its Change sheet.
  - **GDKP** (Session tab): the pot in one line, what's sold (paid, or owed) and what's still to auction; the rules and cuts
    fold away; Payouts, auctioning several and the ledger pinned under it.
  - **Guild tab**: points or priority lists, with a search; points as a table with the roll to type; the guild's settings
    and alts in sheets.
  - **Settings tab**: the sections down the side and the one picked beside them, a search, and "All settings" on one page.
  - **Test tab**: the practice raid first, with the next step as the red button; pretend rolls, messages and Gargul fold away.
  - **Loot master window**: the winner as a card, with its one red button; everyone else under it; Give to someone else,
    Roll again and Call off as links.
  - **Auction window**: the highest bid, big, and one red "Bid 310g", with Bid an amount and a Max bid beside it.
  - **Several auctions at once**: "Bid 100g" on each item, your highest bid marked; Bid an amount and Max bids (new: a max on
    any of them) as links.
  - **Giving an item out**: who reserved it apart from everyone else, how (their reserve, main spec, off spec, to
    disenchant), Cancel quiet.
  - **softres.it import**: paste, then see what would come in (how many players and reserves, what's skipped, names to
    check, with a click to pick who a name is) before "Bring them in".
  - Pop-ups: Cancel is quiet everywhere, the button that does it is red.
  The roll window, the loot panel and the trade timers are as they were. ([#163](https://github.com/kcham01/LootRuler/pull/163))
- The build makes a test copy beside the addon (`LootRulerTest.zip`): the same LootRuler in its own folder, with its own
  saved sessions and settings, to try a pull request in the game without touching the real one. It talks to the raid as
  LootRuler. Turn on only one of the two (both on, the test copy says so). ([#163](https://github.com/kcham01/LootRuler/pull/163))
- Players without the addon reserve with `!reserve [item]` (by whisper or in raid chat), which reads like what it does;
  `!lr` still works, and every command works after either (`!reserve remove`, `!reserve swap`...), in any capitals. Raid
  lines, answers and the Settings tab now teach `!reserve`. ([#162](https://github.com/kcham01/LootRuler/pull/162))
- Clearer raid chat at the end of a roll (the owner's wording): with 10 seconds left, "You have 10 seconds to roll on
  [item]."; then "5...", "4...", "3...", "2...", "1...". The winner's line now reads "Pug has won [item] (MS roll 85)."
  (or "(hard reserve)", and ", the loot master's pick" when it isn't the best roll).
  ([#161](https://github.com/kcham01/LootRuler/pull/161))
- A private session has "Clear reserves of players not in the group" too, like a session for the group: after importing a
  softres.it sheet, the reserves of anyone not in your group come off in one click (after saying who). It works while
  you're in a group. ([#160](https://github.com/kcham01/LootRuler/pull/160))
- Fixes from whole raids played at random (`tools/chaos.lua`), all about the reserves changing hands while someone's away:
  a raider who was offline or out of the group when they were handed on (or taken over) now catches up, where before they stayed
  on the old leader for good and their reserves went nowhere; a leader who comes back to find the reserves taken over now
  follows the new leader, instead of both running them; a raider's copy could keep a reserve that was taken back (changes
  put onto the wrong copy), and that's fixed too. When nobody who leads the group or is its master looter can confirm a
  take-over, the Session tab says who claims it and lets you follow them (or, as the old leader, let them run it). While the
  reserves are being handed on, changes wait ("try again in a moment"), so none are lost. A loot master who isn't the
  leader no longer keeps a drop the leader never took (say, the master looter changed just then). A leader who comes back
  with an old copy, after the reserves were taken over, can no longer wipe out everything done since (even as the raid
  leader): raiders send them the newer copy instead. A change made before the group is known (reserves locking by
  themselves at login) now reaches the raid as soon as it is. Re-importing a softres.it sheet that only matched items
  already reserved in LootRuler could leave raiders' copies quietly different from the leader's; fixed.
  ([#159](https://github.com/kcham01/LootRuler/pull/159))
- Fixes from a fuzz test (random and broken input everywhere, `tools/fuzz.lua`): a raid chat line with a very long word
  could run past the game's 255 characters; a guild book could be thrown away at login after linking an alt to a blank name
  or bringing in a priority list of more than 100 players (now the list keeps the first 100, and a damaged book keeps every
  good entry); a hard reserve or GDKP log from an odd copy could show a Lua error on a raider's screen; item numbers the
  game can't have are refused. ([#158](https://github.com/kcham01/LootRuler/pull/158))
- Locking reserves by hand now tells the raid, like locking by itself does: "Soft reserves are locked now. Want to swap one?
  Type !lr swap [your item] [new item] in raid chat, or click Ask to swap one in LootRuler." Unlocking says they're open again,
  with how to reserve. ([#155](https://github.com/kcham01/LootRuler/pull/155))
- The loot master window's Confirm button is gone: Award (or Give) already said who won. With "Say the winner when I give
  it out" on (as it starts), nothing is said when rolls close, and the award line is the winner. When it isn't the best roll,
  the line says it was the loot master's pick (or the council's choice). ([#154](https://github.com/kcham01/LootRuler/pull/154))
- When a reserved item's roll is waiting for someone who has gone offline or left the group, the loot master's window
  says so ("Bob (offline)") and their chat is told once. The roll still waits until time runs out: wait for them, or click
  Close now. Someone who comes back can still roll. ([#152](https://github.com/kcham01/LootRuler/pull/152))
- Trades are no longer said nearby (/s) when you're out of a group. The game only lets an addon talk in /s after a click,
  so it needed a "Say it" button every time; that button and its setting are gone. In a group, trades are said in the
  group's chat as before. ([#151](https://github.com/kcham01/LootRuler/pull/151))
- Raid gear and the gear beside each roll say what they really do: everything is read with the game's own inspect, one
  player at a time, and nobody's LootRuler is asked. The list's button is "Inspect again", and the setting is "Inspect raiders'
  gear". (Since #129 nothing was asked of other addons; only the words were left over.) ([#150](https://github.com/kcham01/LootRuler/pull/150))
- A private session, for when you're not running loot and whoever is doesn't have LootRuler: a button beside opening reserves
  on the Session tab. It keeps the raid's loot list (from the game's loot lines and Gargul's awards) and the reserves you
  import, on your screen only. Nothing is sent to anyone or said in chat, and nothing is rolled out from it. Closing it
  forgets it (it isn't kept as a past raid). When the loot master opens LootRuler reserves you're asked to join, and joining
  closes it; so does opening your own. ([#148](https://github.com/kcham01/LootRuler/pull/148))

### Stress test (28 October 2026)

Found by pushing LootRuler well past an ordinary raid night (`tools/stress.lua`).

- Fixed: a broken message from the raid leader's LootRuler could show a Lua error on a raider's screen. It's ignored now.
  ([#136](https://github.com/kcham01/LootRuler/pull/136))
- The loot master's window lists each player's best roll once, with how many it was the best of ("SR (best of 2)"), and one
  line counts the lower rolls, instead of a row for every roll. With lots of doubled reserves on one item it redraws about
  three times faster. ([#137](https://github.com/kcham01/LootRuler/pull/137))
- Roll windows and the loot master's window redraw at most four times a second while rolls or bids pour in, instead of
  on every one. Rolling out loot in a 40-player raid is about a third less work for everyone's LootRuler.
  ([#139](https://github.com/kcham01/LootRuler/pull/139))
- LootRuler sends less while loot is given out: the guild hears changes at most every 30 seconds during a raid (it was 5),
  and not at all while everyone from the guild who's online is in the raid; several auctions at once send their items'
  links only now and then. Raiders' LootRuler does about half the work while items are rolled out and auctioned.
  ([#140](https://github.com/kcham01/LootRuler/pull/140))
- The loot master checks who won before the raid hears it: when rolls close, raid chat says nothing more until the item is
  given out (a Confirm button at first; since #154, Award or Give says it). Raiders' windows wait for it too. Settings,
  "Rolling out loot": switch it off to say the winner as rolls close. ([#142](https://github.com/kcham01/LootRuler/pull/142))
- GDKP: bid any amount from the auction window. "Bid an amount" opens a box for the gold, and the bid is typed in raid chat
  like the window's two buttons (too little, and you're told the least that counts). With several auctions at once, pick
  the item, then the amount. ([#143](https://github.com/kcham01/LootRuler/pull/143))
- A countdown in raid chat for the last five seconds of a roll: "You have 5 seconds to roll on [item]...", "4...", "3...",
  "2...", "1...". Then nothing until the loot master confirms the winner, which is the next line (it no longer says
  "Rolls closed" first). Settings, "Rolling out loot": "Count down the last 5 seconds" (on).
  ([#146](https://github.com/kcham01/LootRuler/pull/146))

### Easier on the eye (27 October 2026)

From the owner's in-game screenshots.

- GDKP: the organiser can stop taking a player's bids for the rest of the night (someone who won't pay), optionally:
  right-click them in the loot master window. Their bids, in raid chat or by whisper, max bids included, don't count, the
  highest bid is the best of everyone else's again, and the raid is told once. The GDKP panel lists them, to take them back.
  ([#131](https://github.com/kcham01/LootRuler/pull/131))
- The guild book can't be locked by a change stamped far in the future (a wrong or tampered clock): a change more than an
  hour ahead counts as made an hour from now, so the next real change still replaces it.
  ([#130](https://github.com/kcham01/LootRuler/pull/130))
- What raiders wear is only ever read by inspecting them, for rolls and for "Raid gear": raiders' LootRuler no longer tells
  the loot master, so nobody can make it up. The "Show the loot master what I wear" setting is gone; your own roll window
  still shows what you have in that slot. ([#129](https://github.com/kcham01/LootRuler/pull/129))
- Only the one holding the loot runs it: with master loot on, the master looter; without it, the raid leader. Assistants
  no longer can (pugs often make everyone one), so nobody else can start rolls or auctions on everyone's screen, or have a
  typed Gargul line ("awarded to", "You have 10 seconds to roll on...") count. Taking over reserves while their leader is
  away is for the raid leader or the master looter. ([#128](https://github.com/kcham01/LootRuler/pull/128))
- Reserves run by someone other than the raid leader or master looter don't take over your window: LootRuler asks "Join
  their reserves?" first (and when you're looking at someone else's). ([#128](https://github.com/kcham01/LootRuler/pull/128))
- Reserving an item more than once is a roll for each reserve: with "x3" on an item you /roll three times when it's rolled
  out, and your highest counts. The raid line says so ("x2 rolls twice, best counts"), and the roll window offers the next
  roll until they're used up ("1 roll left"). Before, more reserves on one item only counted if it dropped again.
  ([#127](https://github.com/kcham01/LootRuler/pull/127))
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
- The bench (Session tab, in Boosted rolls): guild members who came but sat out get the raid's points too, and count as
  there in the fairness history. Tick who's online, or type names. ([#118](https://github.com/kcham01/LootRuler/pull/118))
- Reserves can lock by themselves (Session tab, "Lock by itself"): in 10 to 60 minutes, or at a time you type. The raid is
  told 5, 2 and 1 minute before, with how to reserve, and when they lock. ([#117](https://github.com/kcham01/LootRuler/pull/117))
- "One reserve win each" (Session tab): once a player wins one of their reserves, their other reserves stop counting, so
  loot goes further. The raid is told when it happens. ([#116](https://github.com/kcham01/LootRuler/pull/116))
- Raiders get a small note at the top of the screen when the loot master picks up loot: each item, and who reserved it
  ("Yours", or "SR: Ann, Bob"). It takes no clicks and goes by itself (Settings, "Reserves where you see items").
  ([#115](https://github.com/kcham01/LootRuler/pull/115))
- Loot rolled out with Gargul goes on the Loot tab as given out. When Gargul says in raid chat who an item was awarded to,
  the leader's LootRuler records it: their reserve if they had one on it, off spec if Gargul's line says so, else main
  spec. Both ways of handing it over are followed: given straight from the loot window (the game's loot line says who got
  it), or looted by the loot master and traded over later, which only the two of them see, so Gargul's "I gave [item] to
  Name" marks it handed over. It can be switched off (Settings, "Giving out and trading"). ([#123](https://github.com/kcham01/LootRuler/pull/123))
- When the one holding a won item doesn't have LootRuler, the Loot tab just says who won it ("Won by Ann"), not that it's
  still to trade: a trade is only seen by the two in it, so LootRuler can't tell when it happens.
  ([#123](https://github.com/kcham01/LootRuler/pull/123))
- Fixed: Gargul's "Stop your rolls!" didn't close LootRuler's roll windows. Gargul puts its name in front of its lines
  (" Gargul : Stop your rolls!"), which LootRuler now reads. ([#123](https://github.com/kcham01/LootRuler/pull/123))
- Fixed: an error when logging in or reloading ("Net.lua:195: attempt to index upvalue 'db'"), when the game told LootRuler
  about raid lockouts, the group or the guild before it had read its saved data. ([#122](https://github.com/kcham01/LootRuler/pull/122))
- Bosses open and close on the Reserve and Reserves tabs, like the Settings sections: each shows its name and how many items
  (and, on the Reserves tab, how many reserves) until you click it, with "Open all" and "Close all". Searching, or "Reserved
  only", opens every boss with a match. LootRuler remembers which ones you opened. ([#126](https://github.com/kcham01/LootRuler/pull/126))
- The Loot tab has an "Award history": everything given out in your raids, by date, newest first. Each date opens and closes
  with a click to show what was given out that day, who won it, how, and in which raid. Export, "Who got what, over time" and
  Past raids are there too, instead of at the bottom of the Loot tab. ([#125](https://github.com/kcham01/LootRuler/pull/125))
- Fixed: who reserved an item didn't show in its tooltip in your bags or on a boss's loot window, only in LootRuler's own
  windows. With Gargul loaded, LootRuler leaves the reserves in tooltips to Gargul, so they aren't shown twice.
  ([#124](https://github.com/kcham01/LootRuler/pull/124))
- The Loot tab only lists the raid's loot: gear (and tier tokens), mounts, recipes (plans, schematics, formulas, patterns,
  designs), and a short list of other raid loot: Mark of the Illidari, Heart of Darkness, Black Temple's epic gems, Nether
  Vortex, Vashj's Vial Remnant, Black Sack of Gems, the Amani Charms, Amani Hex Stick, Mojo, Soul Essence and Karazhan's
  library books. Cloth, trade goods, other gems, potions and gold are left out, and so is what anyone gets from a
  profession (disenchanting, gathering, skinning, fishing). ([#121](https://github.com/kcham01/LootRuler/pull/121))
- The loot list works when the master looter doesn't have LootRuler: the leader's LootRuler lists what they give out, from
  the game's own "receives loot" lines (so nothing is counted twice from Gargul's lines). ([#114](https://github.com/kcham01/LootRuler/pull/114))
- A row of buttons too wide for its panel goes on over two lines instead of running past the edge (seen on the Test
  tab). ([#113](https://github.com/kcham01/LootRuler/pull/113))
- The Loot tab lists more than loot to roll for: things like Nether Vortexes are counted at the bottom ("Nether Vortex x3, looted by Ann (2), Bob (1)").
  They're never announced, held for rolling out or reserved. ([#112](https://github.com/kcham01/LootRuler/pull/112))
- A session's loot list only takes loot from inside its raid: a session left open no longer collects another raid's loot.
  Going into a different raid, or into its raid on a new lockout, asks whether to start a new session there (it can be
  switched off). ([#111](https://github.com/kcham01/LootRuler/pull/111))
- "Open a trade with the winner" is off to start with (Settings, "Giving out and trading"). Settings you already saved
  stay as they are. ([#110](https://github.com/kcham01/LootRuler/pull/110)) So are "Put won items in trades for me" and
  "Trade timers on screen". ([#120](https://github.com/kcham01/LootRuler/pull/120))
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
- The raid gets only what changed in the session, not the whole of it each time (when everyone's LootRuler is new enough):
  raiders' addons do 25 to 60% less work while loot is rolled out, given out and sold, and the loot runner sends less.
  ([#119](https://github.com/kcham01/LootRuler/pull/119))

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
