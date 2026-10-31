# Notes: everything from the long build conversation (25 to 28 October 2026)

**This file never goes to `main`.** It lives only on the `buildnotes` branch and its pull request, which stays open as a
draft and is never merged. Read it from there; add to it there.

It covers pull requests #30 to #148: what was added, changed and fixed, what the owner decided, and the dos and don'ts
learned along the way. `AGENTS.md` (on `main`) is still the rulebook and hand-off note; this is the story behind it.

Weak spots that aren't fixed yet are **not** in here (the repository is public). The owner keeps those privately.

---

## Dos and don'ts

### Always
- Read `AGENTS.md` first and follow it.
- One branch and one pull request per feature. Commit messages and pull request titles are one plain word ("Countdown").
- Commits are the owner's: `git -c user.name=Jamesthefishguy -c user.email=94383428+kcham01@users.noreply.github.com commit`.
- Pull request descriptions say what changed for players in plain words, how it was tested, and show pictures
  (`https://raw.githubusercontent.com/kcham01/LootRuler/results/shots/<name>.png`). Each one adds a `CHANGELOG.md` line linking it.
- New behaviour gets tests. Anything on screen gets a `tests/ui.lua` check and a picture.
- **Test everything.** The owner said: "When you're testing the full app you should be testing everything and all features."
  A new feature, setting or command goes into `tests/loot.lua` ("nobody can fake a win") and `tools/stress.lua` as well.
- Every new feature adds itself to the practice raid (Test tab), so it can be tried in the game.
- Every new setting goes in a Settings section, and the section's line says what's in it now.
- Event handlers that read saved data return while `LR.db` is nil (events can come before login).
- Ask before building anything that isn't clearly confirmed. "Note it", "hold off" and "we're still thinking" mean **don't build**.
- When the owner asks a question, answer it before starting work ("Answer my questions before starting").
- Merge only when the owner says so. Wait for CI on each pull request, merge in order, then check `main`'s build and the
  download (`results` branch zip).
- After merging, check the download has the new code.

### Never
- Never push to `main`. Never force-push or delete remote branches (blocked; use merges, and ask the owner to delete).
- No co-author lines, signatures or mentions of AI in commits, pull requests or files. (The tool adds a footer to pull
  request bodies that can't be removed; the owner knows.)
- **Never copy Gargul's code or art.** Reading it to compare is allowed (the owner said so), copying never. Nothing from
  Gargul goes in the repository, the zip, tests or CI.
- Never write unfixed weak spots in the repository, pull requests or commit messages. Tell the owner instead.
- Never delete a function just because no test reaches it: add a test (#76 deleted `LR.forget` while buttons still used it).
- Never auto-accept trades, invites or anything else for the player. Never touch protected functions.
- Don't make changes after a benchmark until the owner says so: write notes and ideas first.
- Don't say "wait" in raid chat when waiting on the loot master (the owner's countdown rule, below).

---

## What the owner decided

### Built at the owner's request
- Multi-select reserve picker; softres.it names matched to characters (accents, capitals, missing realm).
- Handing the reserves over, or taking them over when the leader is gone, with a manual pick of who.
- Reminders for who hasn't reserved (button; on join, off to start with).
- Trades: stack counts ("x3") and enchants with what was paid.
- A Test tab in the addon, to try everything in the game; later a full practice raid.
- Only the group can reserve (anyone outside can't put in a reserve).
- Warn before the 2 hours to trade run out, with who it's for.
- Undo an award and give it again or roll again.
- Re-importing a changed softres.it sheet applies the changes and never gives extra reserves.
- Roll windows for Gargul's rolls (detected from raid chat).
- The whole Gargul comparison list, built one by one, merging every three (#43 to #75), then the second list (#77 to #89).
- Speed work after the benchmark (#90 to #97).
- Trades out of a group said with /s, with a switch, and never both /raid and /s.
- Picking a disenchanter tells the raid.
- Polish from the owner's screenshots: title plates, hints in boxes, tick boxes, the softres.it import easier to reach,
  Settings sections that fold.
- The loot list only from the session's raid, and only the raid's loot: gear, mounts, recipes, and the owner's own list
  (Mark of the Illidari, Black Temple gems, Nether Vortex, Vashj's Vial Remnant, Black Sack of Gems, Amani charms, Amani Hex
  Stick, Mojo, Soul Essence, Karazhan's books). Cloth, gold, potions and profession loot never show.
- The loot list works when the loot master doesn't have LootRuler (from the game's loot lines).
- "Picked up" note for raiders when the loot master loots (as small and unobtrusive as possible).
- Reserves locking by themselves, with 5, 2 and 1 minute warnings and "locked now" (optional).
- One reserve win each (optional), the bench (optional).
- Gargul's awards recorded on the Loot tab; trades nobody else can see just say "Won by ...".
- Award history by date, as a page inside the Loot tab, dates as drop-downs.
- Bosses as drop-downs on the Reserve and Reserves tabs.
- One roll for each reserve: x3 on an item means three /rolls, the best counts (how softres.it does it).
- Only the loot master (or the raid leader without master loot) runs loot; Gargul's lines only count from them; reserves
  opened by anyone else ask "Join their reserves?" first.
- Gear only by inspecting (no addon reports).
- Guild book times capped; an optional button to stop taking a bidder's bids.
- Nothing can trick LootRuler into thinking someone won; raiders can't trigger trades or change settings.
- Confirm the winner: a button beside "roll again" that says the winner in raid chat.
- "Bid an amount" for GDKP bidders.
- The countdown, exactly: "You have 5 seconds to roll on [item]...", "4...", "3...", "2...", "1...", then **nothing** until the
  loot master confirms, and the next line is the winner.
- Private session (#148): a button beside opening reserves; only on your screen; cleared when closed; joining someone's
  reserves through the join box closes it.

### Owner's choices on details
- Keep: the windows' see-through backgrounds, the size, grey buttons, the tabs as they are.
- Off to start with: "Open a trade with the winner" (#110), "Put won items in trades for me" and "Trade timers on screen"
  (#120). These toggles being off is enough for now (no click-only trade change).
- The exploit notes in the repository list only protections, never open weak spots.
- A winner can't "pass" to the next person: the loot master undoes and gives it again.
- A loot master who disconnects: items are just rolled again (no rolls surviving a reload).
- Whisper spam: left alone for now.
- Private sessions are forgotten when closed, and stay out of past raids and award history.

### On hold (say go before building)
- Trades said nearby (/s) any time out of a group, off to start with. (#144 built it by mistake; the owner closed it.)
- Opening trades only from a click.
- A `/lr bug` report box, a Discord recap, drop history on the Reserve tab, "My night", opening reserves on zoning in,
  splitting the loot list per dungeon run (instance numbers), translations (if it gets widely used).

### Not wanted
- Less contested picks; reading Gargul's reserves from chat; the winner passing; a full one-button rehearsal (the Test tab
  replaced it).

---

## Everything built, by pull request

All merged unless marked.

### Reserves and softres.it
- #30 reserve several items for a player in one go
- #31 match softres.it names to the group's characters
- #39 only the group can reserve
- #41 re-importing a changed sheet never gives extra reserves
- #59 spreadsheet imports and the softres.it link
- #87 swap requests (after locking)
- #88 clear the reserves of players not in the group
- #101 the import box could be typed in again
- #106 the softres.it import easier to reach
- #116 one reserve win each
- #117 reserves lock by themselves, with warnings
- #126 bosses open and close
- #127 one roll for each reserve

### Running the raid
- #34 hand the reserves over, or take them over
- #35 reminders for who hasn't reserved
- #52 who has LootRuler, and which version
- #53 raid setup: paste a list, invite, sort groups
- #64 when you become the master looter
- #66 first-time tour, what's new, settings profiles
- #84 your raid's name, message and icon
- #118 the bench
- #128 only the loot holder runs loot; "Join their reserves?"
- #148 private session (open)

### Rolling out loot
- #32 who reserved it, while it's rolled for and in the loot window
- #37 undo an award; #70 change an award afterwards
- #43 roll windows for Gargul's rolls
- #45 give an item without a roll
- #48 "your item is up" alerts; #72 for wishlists too
- #49 everyone's rolls in the roll window
- #50 roll types of your own (Transmog /roll 98)
- #55 item notes; #56 thatsmybis wishlists
- #61 roll window options
- #63 / #69 gear beside each roll (inspecting raiders without LootRuler)
- #67 failed handouts take the award back
- #85 loot council
- #129 gear only by inspecting
- #137 the loot master's window lists each player's best roll once
- #142 confirm the winner
- #146 the countdown

### The loot list and trades
- #36 stack counts and enchants in trade lines
- #38 / #51 / #74 trade time warnings, trade timers, posting what you hold
- #44 a corpse's loot posted in raid chat
- #47 open a trade with the winner; #110 / #120 off to start with
- #65 / #73 loot given out without LootRuler; group loot wins
- #82 bag checks; #83 raid gear overview
- #102 / #108 trades said nearby out of a group, with its own switch
- #111 loot only from the session's raid
- #112 everything that drops counted; #121 only the raid's loot listed
- #114 the loot list without a LootRuler loot master
- #115 "picked up" note for raiders
- #123 Gargul's awards recorded; "Won by" for trades nobody can see
- #125 award history by date
- #144 trades nearby any time (closed by the owner: on hold)

### GDKP
- #62 change a sale, starting bids, payouts by mail
- #71 bidders' extras (outbid alert, what's next, final call)
- #78 pot rules; #79 bookkeeping (gold in and out, ledger, payouts sheet)
- #80 bidding ahead; #81 several auctions at once
- #131 stop taking a bidder's bids (optional)
- #143 bid an amount

### Guild
- #60 who got what, in guild chat
- #86 fairness history (who got what over time)

### Settings, polish and wording
- #57 Need and Greed rules; #58 more loot rules
- #68 two raid lines reworded in LootRuler's own words
- #75 sounds: one switch and a channel
- #103 title plates fit; #104 hints in boxes; #105 tick boxes; #107 Settings sections fold; #113 button rows wrap
- #109 picking a disenchanter tells the raid
- #124 reserves in bag and loot window tooltips; no clash with Gargul's

### Speed
- #90 reserve index kept; #91 the group kept between changes; #92 / #93 fewer session copies
- #94 standings worked out first; #95 finished bars stop redrawing; #96 fewer batch updates; #97 benchmark notes
- #119 only what changed is sent; #139 redraw at most four times a second; #140 send less (guild copies, batch links)

### Tests, tools and notes
- #33 README pictures that stay put
- #40 the Test tab; #77 the practice raid
- #42 the reserves strip goes with its window
- #46 docs; #98 / #135 README brought up to date; #99 changelog
- #76 coverage: every function reached
- #134 `docs/exploits.md` (protections only; #132 and #133 were closed and replaced)
- #138 the stress test (`tools/stress.lua`)
- #141 / #145 nobody can fake a win; trades and settings can't be triggered by raiders
- #147 notes tidy (open)

---

## Fixes (bugs found and fixed)

From the owner's in-game testing:
- `UI/Setup.lua:492` error: "Forget it" called `LR.forget`, which #76 had deleted (#100).
- `CONFIRM_DISENCHANT_ROLL` registered on TBC, which doesn't have it: an error at every login (#100).
- The softres.it import box couldn't be typed in (#101).
- Closing a roll window left the strip of reservers on screen (#42).
- `Net.lua:195 attempt to index upvalue 'db'` at login: an event came before the saved data was loaded (#122).
- Arcane dust, cloth and gold showed on the Loot tab (#121).
- Loot rolled out with Gargul didn't show who won it (#123).
- Reserves weren't in bag or boss loot window tooltips (#124).

Found by tests, the coverage pass and the stress test:
- Renaming a misspelt softres.it name with extra reserves lost all its reserves; saved data of the wrong type wasn't
  checked on load (#76).
- A broken answer message could show a Lua error on a raider's screen (#136).
- The loot master's window was slow with many doubled reserves on one item (#137).
- The countdown's first line looked like Gargul's start line, so raiders got Gargul roll windows (#146).
- A private session and a real one opened in the same second got the same id (fixed before #148 went up).
- A session from someone else claiming to be private or a practice raid was taken as one (#148).

---

## Mistakes made, so they aren't repeated
- **#144 was built without a go.** The owner said "hold off" and it was misread. When unsure, ask.
- **#76 deleted a function no test reached,** but two buttons still used it. Add a test instead.
- **The README gallery was rebuilt with no pictures:** `tests/ui.lua` deletes the old pictures, so render after the last
  test run, before building the gallery.
- **Exploit notes were first written as a public list of weak spots** (#132). The owner asked why; they were replaced by a
  protections-only list (#134).
- **Force push and branch deletes are blocked.** Conflicts between stacked branches are fixed by merging, never rewriting.
  One automatic merge dropped an `end` in a test file: always run every suite after a merge.
- **A loot test with hundreds of whispers delayed raid lines** (the chat throttle). Put bursts at the end of a test section.
- **`tostring()` of a function that returns nothing errors** in Lua 5.1: wrap it, `tostring((f()))`.
- **Two sessions created in the same second share an id** (`leader:time`). Anything that makes a second session at once
  needs its own id.

---

## How to work on it

```sh
for t in session rolls raid loot party practice guild gdkp gargul ui; do lua5.1 tests/$t.lua | tail -1; done
lua5.1 tools/check_api.lua <wow-ui-source, classic_anniversary>
rm -rf build/shots; lua5.1 tests/ui.lua; node tools/render.mjs build/shots   # pictures (PW_CHROMIUM=<chrome> if needed)
lua5.1 tools/coverage.lua      # every function reached? build/coverage.txt
lua5.1 tools/bench.lua         # a 40-player raid measured: build/bench.txt
lua5.1 tools/stress.lua        # broken messages, biggest raid, long night, floods: "PROBLEM" lines (--quick for a short run)
```

- `tests/loot.lua`'s main part is at Lua's 200-local limit: wrap new sections in `;(function() ... end)()`.
- `srv:tick(sec)` steps 0.1 s; pass a smaller step for finer timing. Re-login a test player with `srv:login(p, saved)`.
- CI runs on pull requests **into main** and on `main`. A pull request stacked on another branch gets no run until it's
  retargeted; start one by hand with `gh workflow run build.yml --ref <branch>`.
- `main` pushes that only touch README, docs or AGENTS skip CI. The `results` branch holds the zip and the pictures.
- Pull requests are made with `gh api repos/kcham01/LootRuler/pulls -f title=... -f head=... -f base=... -F body=@file`
  (GitHub's GraphQL isn't available here).
- Merging stacked pull requests: retarget each to `main` in order, wait for its CI, merge, then check `main`'s build.

## Where things stand (28 October 2026)
- Open: #147 Tidy (notes only) and #148 Private (built on #147). Merge #147 first.
- The owner is testing in the game. After that passes: bump `LR.VERSION` and the TOC to 1.0.0, and add the version's list
  to `UI.WHATS_NEW`.
- Old branches from the closed #132 and #133 can be deleted on GitHub by the owner.
