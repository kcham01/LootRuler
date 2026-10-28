# LootRuler: notes for whoever works on this repo

Read this first. It says how the project is built and checked, the rules every change follows, and where
the work stands. Keep it up to date: when a feature lands or a plan changes, change the roadmap at the end in
the same pull request.

## What it is

A World of Warcraft addon for **TBC Anniversary** (client interface `20506`, the modern Classic engine) that
runs raid loot inside the game: soft reserves, rolling items out with roll windows, the raid's loot list,
trading won items, and handing reserves to Gargul. The aim is to do everything Gargul does, without a website,
for pugs and for guilds. *World of Warcraft: Forever* (Classic+, from November 2026) is a target too: its new
raids' loot isn't known in advance, so nothing may depend on the built-in loot lists.

## How it's laid out

| Path | What |
| --- | --- |
| `LootRuler/LootRuler.toc` | Load order. Every new file goes here. |
| `LootRuler/Init.lua` | The shared namespace `LR`, and a map of the files |
| `LootRuler/Data/Loot.lua` | Generated loot lists (`tools/gen_loot.py`); never edit by hand |
| `LootRuler/Core/*.lua` | Rules and networking. `Session.lua`, `Roll.lua` and `Book.lua` make no game calls (tested on their own). `Book.lua` is the guild book (points, priority lists), `Guild.lua` shares it. `Gdkp.lua` is GDKP's money (no game calls), `Pot.lua` does it in the game. |
| `LootRuler/UI/*.lua` | The window (`Main.lua`, a tab per file), roll windows (`RollFrame.lua`), loot master (`Master.lua`) |
| `LootRuler/Libs` | Bundled libraries (LibStub, AceComm, LibSerialize, LibDeflate); don't change them |
| `tests/` | `session.lua`, `rolls.lua` (rules), `raid.lua`, `loot.lua`, `party.lua`, `guild.lua`, `gdkp.lua` (whole raids and parties), `practice.lua` (the practice raid), `gargul.lua` (the reserves handed to Gargul, without Gargul), `ui.lua` |
| `tests/wow/mock.lua` | A strict stand-in for the game client; `server.lua` runs many clients side by side |
| `tools/` | `check_api.lua` (only what the client has), `render.mjs` (pictures), `coverage.lua` (what no test reaches), `bench.lua` (a 40-player raid's work, messages and memory), `gen_loot.py`, `art.mjs` |
| `ci/` | `build.sh` (everything CI runs), `publish.sh` (results branch) |

## Working rules

- **Commits are the owner's.** Author and committer: `Jamesthefishguy <94383428+kcham01@users.noreply.github.com>`.
  No other authors, co-author lines or signatures in commits or pull requests.
- **Names are one plain word:** every commit message and pull request title (for example "Give", "Strip").
  The pull request's description says what changed.
- **Never push to `main`.** One branch and one pull request per feature. The owner reviews and merges.
- **A pull request says** what changed for players (in plain words, not code words), how it was tested, and
  shows pictures of anything on screen (from `build/shots`). Anything players notice also gets a line in
  `CHANGELOG.md` (under the version being worked on, linking the pull request), in the same pull request.
- **Every change keeps every test passing**, and new behaviour gets new tests: rules in `tests/rolls.lua` or
  `tests/session.lua`, anything between players in a whole-raid test, anything on screen in `tests/ui.lua`
  with a picture.
- **Plain English** in everything players read: short sentences, no jargon, no internal names.
- **Never copy other projects' code or art.** Gargul is "All Rights Reserved": nothing from it goes into this
  repository, the zip, the tests or CI (not even downloaded to test against). Work alongside it only by calling
  its functions in the game, and by writing and reading text layouts (softres.it's, Gargul's import boxes) with
  LootRuler's own code. Anything else reused must have a licence that allows it (GPL-2.0 compatible), be
  credited in the README, and keep its licence file (`LootRuler/Libs/*`).

## Design rules (every feature)

1. **Only the person running loot needs LootRuler.** Their addon does the tracking, sorting and giving out.
2. **Anything you can click, you can type.** Players without the addon whisper (`!lr ...`), `/roll`, or type in
   raid chat, and get the same result.
3. **The raid hears it in plain words.** Every announcement is one short line that tells someone without the
   addon exactly what to do. Never over 255 characters (use `U.chatLines`).
4. **Advanced features are off until a leader turns them on.** A pug leader sees reserves and rolling; GDKP,
   priority lists and points appear only when switched on.
5. **No loot list needed.** Any item can be reserved or rolled out by its link. The built-in lists help
   (search, boss names, tooltips) but never decide what's allowed. Older and newer versions keep working
   together.

## Security rules

- **Every addon message is untrusted.** Check its shape and types before using it (`Session.valid`, the checks
  at the top of each handler); cap list lengths; ignore unknown message types.
- **The sender is who the game says sent it**, never a name inside the message. Changes to a session only
  count from its leader; rolls and loot only from the leader, an assistant or the master looter
  (`LR.canRunLoot`). The leader's addon is the only one that decides.
- **Handlers run in `pcall`**, so one bad message can't break the addon.
- **Never run received text as code** (`loadstring` and friends are banned).
- **Never use a bag item unless the trade window is open** (`C_Container.UseContainerItem` equips it otherwise).
- **Don't touch protected functions** or anything that needs a hardware click; don't auto-accept trades,
  invites or anything else on the player's behalf. The one exception, asked for by the owner: a player's own
  Need / Greed rules may answer the game's "this item will bind to you" for the rolls those rules made, only when
  the player has switched that on (`groupLootConfirm`, off to start with).
- **Saved data is checked when loaded**, like messages are.

## Versions

Players don't update their addons, so every version has to work with every other:
- Change messages by **adding** fields and message types, never by changing what an old one means.
  `v` stays 1 (the first release drops anything higher); a message only newer versions can handle carries
  `mv` (the oldest protocol that understands it) and older ones leave it alone (`Core/Net.lua`, at the top).
- **Keep what you don't understand**: a raid, a kind of award or a field this version doesn't know is shown
  as it is or ignored, never a reason to throw a whole session away (`Session.valid`).
- Only the leader's addon decides what's allowed, so raiders' older data can't block anything.
- Every message carries the sender's version (`av`): players are told once when someone has a newer one,
  and the leader sees who in the group has no LootRuler at all (they whisper instead).

## Speed rules

- **No work every frame** except timer bars that are on screen. Use events and `C_Timer`.
- **Redraw only on change**, and batch bursts (`UI.renderSoon`). Screens get widgets from the pool
  (`K.get` / `K.release`); the UI test checks that redrawing doesn't leak frames.
- **Debounce network sends** (`LR.publish`); don't resend what hasn't changed.
- **Look things up once**: build indexes (`raid.has`) instead of scanning lists in loops; no string building
  inside `OnUpdate`.
- **The group is kept** (`LR.roster`, `LR.inGroup`): read once, until the game says it changed. A new handler for
  `GROUP_ROSTER_UPDATE` (or any event that changes who's in the group) calls `LR.rosterChanged()` first: the game
  doesn't say which addon frame hears an event first. `S.byItem` is kept too: don't change what it returns.

## How to check your work

```sh
lua5.1 tests/session.lua && lua5.1 tests/rolls.lua && lua5.1 tests/raid.lua && lua5.1 tests/loot.lua && lua5.1 tests/party.lua && lua5.1 tests/practice.lua && lua5.1 tests/guild.lua && lua5.1 tests/gdkp.lua
lua5.1 tests/gargul.lua
lua5.1 tools/check_api.lua <wow-ui-source checkout, branch classic_anniversary>
lua5.1 tests/ui.lua && node tools/render.mjs build/shots   # PW_CHROMIUM=<chromium> if Playwright's isn't installed
lua5.1 tools/coverage.lua                                   # functions no test reaches: build/coverage.txt
lua5.1 tools/bench.lua                                      # a 40-player raid, measured: build/bench.txt (about a minute)
```

`tools/bench.lua` plays a raid night for 40 players (30 with LootRuler) in the stand-in and writes, moment by moment, the
Lua instructions run in LootRuler's code (sampled; within about 2% between runs), CPU time, garbage, addon messages
by kind and size, how long until every raider has a change, and the busiest functions. Not part of CI. What the last
run found, and ideas: `docs/benchmark.md`.

`tools/coverage.lua` runs the tests with a line hook and lists every function no test runs (`build/coverage.lines` has
every line that ran). Not part of CI; run it after a feature lands and add tests for anything new it lists. Only
`UI.masterNote` (a one-line print) isn't reached now. **A function no test reaches gets a test, not deleted**: the Coverage
pull request (#76) deleted `LR.forget` as unreached while two buttons still called it, and the owner's first in-game test hit it.

CI (`.github/workflows/build.yml`) runs all of it on every pull request and on `main`. Pull requests get the
pictures and the zip as a download on the run; `main` publishes them to the `results` branch, which the
README's download link points at. Pictures are published numbered and under their name alone
(`results/shots/loot-master.png`): the README links the names, so adding a screen doesn't move its pictures.

The mock is strict on purpose: a method the client doesn't have is an error, and `check_api.lua` checks the
mock and the addon against Blizzard's own interface code, and every event the addon registers against the client's own
list (registering one the client doesn't have is an error in the game; the mock's `M.MISSING_EVENTS` refuses the known ones). When the addon needs a new game function, add it to
the mock (and to `tests/wow/server.lua` if it involves other players), never loosen the checks.

## Next up (hand-off note)

Start here in a new session; rewrite this section at the end of each piece of work.

- **Open pull requests** are stacked, each built on the one before, so they merge in order (one per feature).
- **Decided for the guild features:** officer ranks (picked by the guild master) edit priority lists; a
  player who gets an item they had priority on comes off that item's list; boosted roll points are earned
  per raid attended. Both live in a "guild book" shared over the guild channel.
- **The guild book** (`Core/Book.lua`, `Core/Guild.lua`, `UI/Guild.lua`): every entry carries the time it changed
  and copies merge entry by entry, newest first, so officers' copies agree without one overwriting another. Changes
  go over the guild channel (`GB`); someone logging in asks (`GQ`) and editors answer by whisper. A change only
  counts if the game's guild list says its sender's rank may edit; only the guild master changes who may.
- **Boosted rolls** are kind `BR` in a roll (a main spec roll moved up by the player's points, `roll.bp`), and an
  award of kind `MS` with `br = true` on the session, so older versions read it as main spec.
- **Priority lists** are roll mode `PR` (`Guild.prioPlan`): the best place here gets the item with no roll (like
  `HR`), or the players sharing it roll. Sessions choose with `s.prio` (nil, "both", "only"). Formats in and out
  are in `Core/Prio.lua` (Gargul's CSV, DFT, thatsmybis).
- **GDKP** is roll mode `BID` (`R.bid`, `R.parseBid`): bids are entries of kind `BID` with `n` = gold, typed in raid
  chat (`Rolls.onChat`), whispered (`!lr bid`) or clicked (the window just types the amount). A sale is an award
  of kind `BID` with `r` = the price. Session settings and who's in the pot are `s.gk` (`Core/Gdkp.lua`); trades
  count the gold that changes hands (`Core/Drops.lua`). `Rolls.queue` puts items up one after another (any mode).
- **Ending a GDKP session** with gold still owed (`Gdkp.unsettled`) asks first: ending it loses the list.
- **Bids that must start with "bid"** (`s.gk.strict`, sent as `sb`): `R.parseBid(text, strict)`.
- **Extra reserves** (`s.xr`, `S.limit`, `S.setExtra`): a player's limit is `s.sr` plus their extra. Older raiders'
  addons check against `s.sr` only, so they can't use an extra from the addon, but can by whisper.
- **Past raids** (`Core/History.lua`): a session that ends (or is closed by its leader, or forgotten after a week) is
  kept as a frozen copy (`archived = true`), so exports, the GDKP split and the payouts sheet read it like a
  session. Trades and `!lr pot` find a past GDKP still owing (`History.owing`). Kept per character, 30 at most.
- **Max bids** (`R.resolve`): kept only by the loot master's addon (`roll.maxes`, sent as `M` or whispered `!lr max`);
  it bids for them as little as it takes, says where the bidding ended up, and resends `R` so windows update.
- **Cuts by role** (`s.gk.rp`: role -> percent of the pot each; `s.gk.role`: player -> "tank"/"healer"): paid out of
  the pot after the organiser's cut and bonuses, before the even split; scaled down if they'd ever be more than is left.
- **Alts** (`book.alts`: alt -> { m = main or "", t }): `B.points`/`B.setPoints` go through `B.mainOf`, so an alt rolls
  with and spends its main's points; raid points go to each main once. Linking an alt takes its own alts along.
  Older versions don't know links (an alt shows its own points there). Gargul's "Name,Points,Alt,Alt" keeps them.
- **softres.it imports** (`Gargul.importInto`): the session remembers what the last import brought (`s.sx`, `s.hx`),
  so importing an updated sheet replaces those (swaps, removals) and leaves reserves made only in LootRuler alone; an
  item reserved in both places counts once and from then on follows the sheet. Nobody passes their limit: picks they
  already had go in before new ones, a pick that has already won its item stays (`used`), the rest are skipped (`over`).
- **From Gargul:** +1s and boosted roll points as "Name,Number" lines (`Prio.parseCounts`, `Prio.countsText`), read
  straight from a loaded Gargul (`Gargul.counts`, its own export) or pasted. +1s set with `S.setPlusOnes`.
- **Reserving for someone** (Reserves > By player > "Add a reserve for ..."): `UI.pickItem(s, title, nil, filter, many)`
  with `many = { player, class }` stays open, counts what's left in its title, and a second click on an item added
  there takes it off. Every other picker (hard reserves) still closes on the first click.
- **Names from softres.it** (`Gargul.importInto`, `Gargul.findPlayer`): each name on the sheet is matched to a character
  in the group (or one who reserved in LootRuler) with `U.nameKey` (capitals and accents put aside; the letters are a
  table in `Core/Util.lua`), and the reserve is stored under the game's spelling. Everything else, older versions and
  Gargul included, then compares names exactly. A name that could be two characters is never guessed: the leader
  picks (`Gargul.unmatched`, `LR.matchName`, the import summary and the Reserves tab). `s.nm` remembers matches for
  re-imports; `Gargul.recheck` runs when someone joins. `U.samePlayer` ignores capitals in any letters (`U.foldCase`),
  not accents: Ghost and Ghøst are two characters. `R.key` is unchanged (its keys go over the network).
- **Who reserved it, on screen** (`UI/ReserveStrip.lua`, `UI/Highlight.lua`): a click-through strip above the roll window
  (or the loot master window) lists every reserver of the item being rolled for, in full; it follows the roll on now
  (LootRuler's, or Gargul's in `Gargul.roll`). Gargul's rolls are read from raid chat with LootRuler's own patterns
  for Gargul's English lines (`Gargul.ROLL_LINES`, `Gargul.END_LINES`); they also end when the item is looted or time
  runs out. Other languages aren't read yet. The game's loot window gets "SR"/"HR" on the icon and the names under
  the item's name (as many as fit). Switches: `reserveStrip`, `lootTags`. The test server now has the game's class colours.
- **A new leader for a session** (`S.handTo`, `S.newLeader`, `S.newLeaderOk`; `LR.handOver`, `LR.takeOver`, `LR.passOn`, `LR.adopt`):
  the leader hands it on (`s.next`; that player's addon takes it), or the raid leader / an assistant takes it over
  while its leader is out of the group or offline. Same id, so everything stays; `s.was` lists who led it. A raider's
  addon now only accepts a copy naming a different leader by those rules (before, any sender could claim a session
  with a higher rev), and a session's own leader yields only to a newer copy. Messages carry `fl` (what the
  sender's addon can do; 1 = can take a session) so only able players are offered (`LR.canLead`). Older versions
  still follow whoever sends the newest copy.
- **Reminders** (`Whisper.notReserved`, `Whisper.remind`): one raid line naming who in the group hasn't reserved, with
  how to. `remindOnJoin` (off to start with): people who join while reserves are open, batched for `Whisper.JOIN_WAIT`
  seconds, hear it if they still haven't reserved.
- **Trades** (`Drops.tradeItems`, `Drops.tradeLine`): items are `{ link, how many }` (a stack says "x3"); an enchant cast on the
  item in the trade's "will not be traded" slot (`TRADE_ENCHANT_SLOT`) is `trade.enchant` and gets its own line, also as
  a note to an enchanter who isn't running loot. Gold in an enchant trade isn't a GDKP payment. The test server can
  put stacks (`giveItem`) and enchant in trades (`tradeToEnchant`, `enchantInTrade`).
- **Undoing an award** (`Rolls.undo`, `S.findAward`): the loot master's roll goes back to "closed" (rolls kept), raiders get
  `X` "closed" (old versions too) and the leader `X` "undone" to take it off `s.won`; boosted points are given back.
  The queue's next-item timer skips an undone award.
- **Trade time warnings** (`Drops.tradeWarnings`, `Drops.WARN_AT`, setting `tradeWarn`, on to start with): checked every 30
  seconds; items the loot master holds ("held" or "toTrade") warn once at 15 and once at 5 minutes left, in chat and as
  the game's middle-of-the-screen message (`RaidNotice_AddMessage`, only on their screen).
- **Only the group can reserve** (`s.go`, `S.groupOk`, `S.setGroupOnly`, `LR.setGroupOnly`): on for new sessions; the
  leader's addon refuses new reserves from outside the group (picks `P`, whispers) with `GROUP_ONLY`, while taking
  reserves back, the leader's own adds and imports still work. Switch it off for guild members to reserve pre-raid.
- **The Test tab** (`UI/Test.lua`, setting `testTab`, off to start with): pretend rolls (`UI.testRoll(opts)`, `UI.testGargul`,
  made-up players in `UI.PRETEND`), the trade warning, the reminder line and a softres.it name check, all only on this
  screen. A pretend roll (`copy.test`) rolls locally in `Rolls.roll`, never with the game's /roll.
- **Roll windows for Gargul's rolls** (`Rolls.followGargul`, `Rolls.gargulEnded`, setting `gargulWindows`, on to start with):
  Gargul's start line makes a roll copy (`copy.gargul`, mode SR from this session's reserves, else OPEN) shown like
  LootRuler's, unless the player's own Gargul is loaded (it shows its own; they still get the strip). Its buttons
  just /roll (assumed main spec 1-100, off spec 99: Gargul's defaults, which its loot master can change). "Stop your
  rolls!" closes it, "[item] was awarded to X" gives the winner.
- **Posting a corpse's loot** (`Drops.announce`, setting `announceLoot`, on to start with): the first time the loot master
  opens a corpse, each epic or better item, and anything reserved, gets one raid line with who reserved it.
- **Giving an item without a roll** (`Rolls.give`, `UI.giveSheet`): the loot panel's Give, or clicking an item still to
  give out on the Loot tab. It's a closed roll (`roll.given`) awarded straight away through `Rolls.award`, so it's
  recorded, announced, undoable and traded like any other award. Kinds: MS, OS, SR (their reserve), or disenchant.
- **Opening a trade with the winner** (`Drops.openTrade`, `LR.unitOf`, setting `autoTrade`, off to start with since #110): an award
  of an item in the loot master's bags opens a trade (`InitiateTrade`, after `CheckInteractDistance`), and trade help
  puts the item in; too far away, the winner is whispered; in combat, the loot master is told. Never accepts a trade.
- **Telling a raider their item is up** (`UI.reservedAlert`, setting `reservedAlert`, on to start with): a roll (LootRuler's or
  Gargul's) on an item they reserved or share the top of the priority list for: a chat line, the middle-of-the-screen
  message, a ready-check sound and the game's icon flashing (`FlashClientIcon`). Once per roll.
- **Everyone's rolls in the roll window** (`rollList` in `UI/RollFrame.lua`, setting `rollList`, on to start with): the best five rolls
  that count (`R.standings`), with class colours and kind, under the timer; the window grows to fit and stacked windows
  move down. Timer bars only rebuild their text when the second changes.
- **Roll types of the loot master's own** (`R.checkKinds`, `R.addKind`, `R.kind`, `R.extra`; setting `rollKinds`, empty to start with):
  a roll open to everyone carries them as `roll.xk` ({ n = name, hi }), kinds "X1".."X4", ranked after off spec in that order.
  A tie on one is rolled again the same way. A win on one is an award of kind `OS` with `xn` = its name (`X` messages carry
  `xn`), so older versions read it as off spec. Older raiders' windows don't show the buttons, and count those rolls as
  wrong rolls on their own screen; the loot master's addon decides. The Test tab's pretend roll shows them.
- **Trade timers** (`UI/Timers.lua`, `Drops.holding`, setting `tradeTimers`, off to start with since #120): a window listing the loot master's
  held and to-trade items, soonest first, with a bar of the 2 hours; click rolls out (held) or `Drops.openTrade` (won), right-click
  `UI.giveSheet`. Redrawn on session, loot and roll changes, and every 15 seconds while it's up (no `OnUpdate`). Its x hides
  it until a new item comes in. Saved position: `db.ui.timersPoint`.
- **Who has LootRuler** (`LR.versionList`, `LR.tellOutdated`, `UI.versionSheet`, `/lr versions`): everyone in the group with the
  version we last heard (older first, then none). "Ask again" is `LR.query()`: every version answers `Q` with `V`, so no new
  message was needed. Whispers to older versions go once per player and version.
- **Raid setup** (`Core/Lineup.lua`: `parse`, `compare`, `nextMove`, no game calls; `UI/Lineup.lua`: `LR.inviteMissing`,
  `LR.postMissing`, `LR.sortGroups`, `UI.lineupSheet`, `/lr raid`): the first name-like word of each line or comma-separated
  part is the name (class, spec and role words skipped); "Group N" lines set groups. Invites only go out
  (`C_PartyInfo.InviteUnit`); a party that would pass five becomes a raid first (`ConvertToRaid`) and the rest are invited on
  the next roster change. Sorting makes one move (`SetRaidSubgroup` / `SwapRaidSubgroup`) every half second, each putting one
  player where the list wants them for good, and stops if the game didn't make a move (combat). The list is kept in
  `db.ui.lineup`. The test server now has invites (`Server:acceptInvite`), raid groups and `srv.inCombat`.
- **Exports of your own, and of several raids** (`E.FIELDS`, `E.fill`, `E.entriesOf`, `E.write`; settings `exportTemplate`,
  `exportHeader`; `UI.exportManySheet`): format "own" fills `{field}`s per item (unknown ones stay as typed); past raids and
  the session on now go out as one list between two times, oldest first, each entry carrying its session (`e.s`, `e.n`).
- **Item notes** (`Core/Notes.lua`: `clean`, `check`, `parse`, `text`, no game calls; `db.notes`, `LR.noteFor`, `LR.setNote`;
  `UI.noteSheet`, `UI.notesSheet`): the loot master's own, kept on their character. A roll carries its note (`roll.note`,
  sent as `nt`, cleaned of links and colours on arrival); the raid line ends "Note: ...", roll windows show it under the
  status, tooltips show the viewer's own notes. Older versions ignore `nt`.
- **thatsmybis wishlists** (`Prio.wishlists`, `Prio.checkWish`, `db.wish`, `LR.wishFor`, `LR.wishLine`, `UI.wishSheet`): the
  download's type-2 entries, kept by whoever runs loot. A roll carries the wishlisters in the group (`roll.wish`, sent as
  `wl`, checked on arrival), named as the game names them; anyone given the item this session is left out. Shown in the
  raid line ("Wishlisted: ..."), the roll window (with the note), the corpse loot post and tooltips. Older versions ignore `wl`.
- **Need and Greed rules** (`Core/GroupLoot.lua`, settings `groupLoot`, `groupLootRules`, `groupLootConfirm`, all off or empty):
  on `START_LOOT_ROLL` the first rule matching the item (`AutoLoot.matches`: an item, a quality or a kind) is rolled with
  `RollOnLoot` if `GetLootRollItemInfo` allows it, else the player is told. `CONFIRM_LOOT_ROLL` is answered (`ConfirmLootRoll`)
  only for a roll a rule made, with that switched on. TBC has no Disenchant roll: `GroupLoot.HAS_DE` (`C_EventUtils.IsEventValid`)
  decides whether "Disenchant" is offered (`GroupLoot.choices()`) and `CONFIRM_DISENCHANT_ROLL` registered. The mock has `M.groupRoll`.
- **More loot rules** (`Core/AutoLoot.lua`): kinds `q0`, `q1`, `lt3`, `lt4` (below rare / epic); `to = "rr"` (each in turn: the
  group by name, after `A.lastInTurn`) and `to = "skip"` (matched, nothing done, no later rule). Setting `lootGold` (off)
  takes money slots with `LootSlot` when the master looter opens a corpse. Need / Greed rules get the new kinds too.
  The test server has money in corpses (`{ "money", copper }`).
- **Spreadsheet imports and the softres.it link** (`Gargul.fromCSV`, `Gargul.csvFields`; `G.decode` reads CSV when the text has
  commas, semicolons or tabs): the header's name and item id columns (and class), or lines of a name and an item number,
  become the same data as an export, so re-importing and name matching work the same. `s.url` (`S.okLink`: https://softres.it/
  only; `S.valid` drops any other), set from an export's `metadata.id` or typed in the import sheet; `LR.postLink`.
- **Who got what, in guild chat** (setting `awardGuild`, off; `toGuild` in `Core/Rolls.lua`): the award line (and an undo) also goes
  to GUILD, prefixed with the raid's name. Chat goes through ChatThrottleLib, so tests wait a few seconds for it.
- **Roll window options** (settings `rollHideUnusable`, `rollCloseAfter`, off; `rollScale`, `UI.ROLL_SIZES`): `wanted` leaves out open
  rolls on known items the class can't use; `UI.afterMyRoll` closes the window 1.5 seconds after a click roll; frames get
  `SetScale`. The stand-in doesn't draw scale, so pictures show windows at their normal size.
- **GDKP extras** (`Gdkp.setSalePrice`, `Gdkp.parsePrices`, `Gdkp.pricesText`, `Gdkp.setPrices`; `LR.gdkpSalePrice`, `LR.gdkpPrices`;
  `UI.salesSheet`, `UI.pricesSheet`; `Pot.toMail`, `Pot.fillMail`): payouts by mail fill in the game's Send Mail tab (the
  client restricts `SendMail`, so the organiser presses Send); a post-hook on `SendMail` matches it to the payout filled in,
  and `MAIL_SEND_SUCCESS` counts the gold in the mail as paid. Not done: several auctions at once (the loot master has one
  roll at a time, `Rolls.current`; it needs its own design).
- **Gear comparison** (`LR.wornIn`, `Rolls.sendGear`, message `W` = { k, e = links }, setting `shareGear`, on): a raider's addon
  whispers the loot master the links in the item's slots (two for rings, trinkets, one-hands) once per roll; the loot master
  keeps them as `roll.gear` (only from the group, for the roll on now, links only, two at most). Shown as an icon on the
  loot master's row and "You have:" in the raider's window. Not for auctions. The mock gives gear with `M.player.links`;
  the picture renderer now shows links as their names.
- **Becoming the master looter** (`UI.masterLooterPrompt`, `LR.announceMasterLooter`, `UI.masterLooterLine`; settings `mlPrompt`, on,
  and `mlAnnounce`, off): on `PARTY_LOOT_METHOD_CHANGED` / `GROUP_ROSTER_UPDATE`, a change to being master looter asks (not in
  combat) or posts. Nothing happens for the first 5 seconds after logging in, so a reload doesn't ask again.
- **Loot given out without LootRuler** (`UI.unrecordedPrompt`, setting `remindUnrecorded`, on; `Rolls.handedOut`, `Rolls.justGave`): in
  `Drops.lootMessage`, a drop from my open master loot window that goes to someone else with no award (and that I didn't
  give through LootRuler in the last minute: a raider's copy gets the leader's award later) asks to record it through
  `Rolls.give` (SR / MS / OS / DE), or leave it.
- **Welcome, what's new, profiles** (`UI/Welcome.lua`): a fresh saved file sets `db.ui.toured = false`, and the first window open
  shows `UI.tour` (the test server marks players as toured unless `newPlayer`). `UI.WHATS_NEW` (newest first): after an update
  (`db.ui.seenVersion` differs) one chat line; add the next version's list there when bumping `LR.VERSION`. Profiles are
  `db.profiles` (name -> settings, checked with `LR.checkSettings`, which `loadDB` now uses too); `LR.useProfile` copies one in.
- **Failed handouts** (`Rolls.watchHandout`, `Rolls.handoutError`, `Rolls.handoutFailed`; `Rolls.undo(failed)`): after `GiveMasterLoot`,
  the game's red error (`UI_ERROR_MESSAGE`, matched against GlobalStrings read by name) or the item still being in the slot
  `Rolls.HANDOUT_WAIT` seconds later takes the award back. `LOOT_SLOT_CLEARED` for that slot means it went. The test server
  refuses handouts with `srv.bagsFull[player]` or `srv.lostHandout`.
- **Gear of raiders without LootRuler** (`Rolls.wantGear`, `Rolls.inspectReady`, setting `inspectGear`, on): each roller with no gear
  after `Rolls.INSPECT_WAIT` seconds is queued; one `NotifyInspect` at a time (in range, `CanInspect`, not in combat, not while the
  game's `InspectFrame` is open), read on `INSPECT_READY` into `roll.gear`, then `ClearInspectPlayer`. The test server has inspect
  (`srv.inspects` counts them; `q.links` is a player's gear).
- **Changing an award** (`S.editAward`, `LR.editAward`, `UI.editAwardSheet`; click a given item on the Loot tab): the leader changes `w.p`
  and `w.k` (DE = `OS` with `de`), dropping `br` and `xn`; sales and hard reserves aren't changed here. Everything that reads
  `s.won` (reserves used, +1s, trade help) follows. One raid line says what changed.
- **Bidders' extras** (`Rolls.checkOutbid`, `UI.outbidAlert`, `UI.sound`; `Rolls.upNext`, sent as `qn` = { ids, n }; settings `outbidAlert`,
  `finalCall`, `potAfterSale`, all on): a copy whose top bid was mine and isn't now alerts (chat, middle of the screen, sound); the
  roll window shows "Next:" from `copy.upNext` (any queued roll); the loot master's tick makes a raid warning final call with
  `FINAL_CALL` seconds left on auctions of 20 seconds or more; a sale's line ends "Pot: ... so far."
- **Wishlist alerts** (`UI.reservedAlert`): an open roll whose `copy.wish` names me alerts like a reserve ("It's on your wishlist (3): ...").
- **Group loot wins** (`recordGroupWin` in `Core/Drops.lua`, setting `recordGroupWins`, off): the leader, with no master looter, records an
  epic someone receives as an award (SR when they had a reserve claim on it, else MS) on the drop it was.
- **Posting what I hold** (`Drops.postHolding`, the trade timers' Post button, `/lr held`): one chat line (split by `U.chatLines`)
  of `Drops.holding()` with each item's time left and who it's for.
- **Sounds** (`LR.sound(id, ui)`, settings `sounds`, on, and `soundChannel`, `LR.SOUND_CHANNELS`): every sound goes through it; a window's
  own open and close sounds stay on the effects channel. Use it for any new sound. The mock keeps `M.sounds` ({ id, channel }).
- **Test coverage** (`tools/coverage.lua`): every function but one is reached. The pass found and fixed two bugs: renaming a
  misspelt softres.it name with extra reserves lost all its reserves (`Gargul.rename` now moves the extra first), and saved
  data of the wrong type (`sessions`, `mine`, `ui`, saved picks) is now checked on load. The test server has `cancelTrade`.
- **The practice raid** (`Core/Practice.lua`, the Test tab): `LR.Practice.on` makes `LR.groupChannel()` "RAID", adds the pretend
  players (`Practice.PEOPLE`) to `LR.roster()`, shows every `LR.say` line instead of saying it (`Practice.show`) and drops every
  `Net.send`; `LR.book()` is a copy. The session has `practice = true`: never archived, dropped by `loadDB`, never handed to
  Gargul or mailed, `W.session(sender)` keeps real whispers out of it, ending it ends the practice. Only out of a group; joining
  one ends it. Pretend players act through the real entry points (`Whisper.handle`, `Rolls.onRoll` with `RANDOM_ROLL_RESULT`,
  `Rolls.onChat`, `Net.handlers.N`), answering each roll once (`Practice.react` on "roll" changes); reservers never pass;
  `Practice.tie` makes the next roll a tie. **Every new feature adds itself to the practice raid** (so it can be tried in the game).
- **Pot rules** (`s.gk.rules` = { { n, pct, g, to = names } }, at most `Gdkp.MAX_RULES`; `Gdkp.addRule`, `editRule`, `removeRule`,
  `ruleTo`, `ruleText`; `LR.gdkpAddRule` and friends; `UI.potRulesSheet`): the organiser's own cuts, paid after the cut, bonuses and
  role cuts, before the even split, scaled down to what's left. `split.rules`, `split.ruleTotals`, `row.ruleCut`, `row.ruleNames`;
  `!lr pot` and the raid summary name them. Older versions ignore `rules` (their own screen shows the split without them).
- **GDKP bookkeeping** (`s.gk.adds`, `log`, `fixed`; `Gdkp.addGold`, `removeAdd`, `added`, `paid(..., how)`, `setFixed`, `setFixedAll`,
  `ledger`, `payoutsText`; `UI.goldInOutSheet`, `UI.ledgerSheet`, `UI.payoutsOutSheet`, `UI.payoutsInSheet`): gold put in or taken out
  by hand is in `Gdkp.pot`; every payment is logged with how ("trade", "mail", "hand"), at most `Gdkp.MAX_LOG`; a payout set by hand
  is all that player gets (no share, bonus or cut) and the rest is split between the others (`split.sharers`), scaled to fit.
  "Name,Gold" lines go out and come back in (`Prio.parseCounts`). Older versions ignore all three.
- **Bidding ahead** (`Rolls.ahead` item -> key -> { p, g, at } on the loot master's addon; `Rolls.setAhead`, `aheadCount`,
  `applyAhead`; `Rolls.bidAhead`, `Rolls.myAhead` on a raider's; message `B` = { id, g }; `UI.bidAheadSheet`): on items in the
  queue only, at least the item's starting bid; when its auction starts they become `roll.maxes` and `autoBids` bids. 0 takes
  one back; `clearQueue` forgets them. By whisper: `!lr bid 300 [item]` / `!lr max 800 [item]` (an item on now is an ordinary bid).
  Messages' `fl` is now bits (`LR.hasFeature(name, bit)`: `FEATURE_LEAD` 1, `FEATURE_AHEAD` 2); a raider's window only offers it
  when the loot master's addon has bit 2. The practice raid's pretend players bid ahead by whisper.
- **Several auctions at once** (`Core/Batch.lua`, `UI/Batch.lua`; `Batch.start`, `parse`, `bidText`, `onBid`, `setMax`, `myMax`, `extend`,
  `cancel`, `close`, `candidates`, `follow`; messages `Z` (the batch) and `Y` (a max on item n); `UI.batchSheet`, `UI.batchDraw`,
  `/lr batch`; setting `batchSeconds`): up to `Batch.MAX` items, each an ordinary `BID` roll object (`item.batch` = the batch's key),
  ending together; a late bid on any extends the whole batch. Bids by number in raid chat ("#2 300", "300 on 2", strict "bid #2 300";
  `Rolls.onChat` hands them to `Batch.onChat` first) or whispered (`!lr bid #2 300`, `!lr max #2 800`). At the end each sold item is put
  in `Rolls.current` for a moment and given through `Rolls.award`, so it's recorded, announced, handed out and undoable like any sale;
  failed handouts are watched per loot slot (`Rolls.handouts`). No single roll starts while a batch is on, and none while a queue
  is. Older versions ignore `Z` and bid by chat. The practice raid's pretend players bid by number.
- **The practice raid's raid chat echoes my own lines** (`Practice.show`): in a raid the game shows me my own raid lines and
  LootRuler reads them, so clicked or typed bids count; out of a group the game sends nothing, so the practice raid hands them
  to `Rolls.onChat` / `Whisper.handle` itself. `/lr say <text>` (`Practice.say`) types a practice raid chat line.
- **Bag checks** (`Core/Bags.lua`, `UI/Bags.lua`; `Bags.ask`, `answered`, `report`, `missing`, `postMissing`, `count`; messages `K` (asked,
  to the group) and `J` (the answer, by whisper); setting `answerBagChecks`, on; Loot tab "Bag check", `/lr bags`): up to `Bags.MAX`
  items, counted in bags and bank (`C_Item.GetItemCount(id, true)`; the test server has `p.bank`). Only from someone who may run loot,
  each check answered once. The report lists players without LootRuler (`why = "none"`) and, after `Bags.WAIT` seconds, those who
  didn't answer (`"silent"`). The practice raid's pretend players answer.
- **The gear overview** (`Core/Overview.lua`, `UI/Gear.lua` (not `UI/Overview.lua`, which is the Reserves screen); `Overview.ask`, `got`,
  `list`, `level`, `age`, `clean`, `mine`, `SLOTS`; messages `H` (asked) and `I` (gear, by whisper); Loot tab "Raid gear", `/lr gear`): answered
  when `shareGear` is on; players without LootRuler, and those who don't answer within `Overview.WAIT` seconds, are inspected through the
  roll inspect queue, now general (`Rolls.inspect(player, read, failed)`), when `inspectGear` is on. Answers are checked (item links in real
  slots only). Item level from `C_Item.GetItemInfo(link)` (the test server takes links now). Pretend players send gear from the loot lists.
- **Organiser branding** (`s.br` = { n, m, i }; `S.okBrand`, `S.setBrand`, `S.brandIcon`, `S.BRAND_ICONS` (game icon paths, by place);
  `LR.setBrand`, kept in `db.ui.brand` for the next session; Session tab "Your raid's name"): shown in the window's header (icon and name),
  as a note on raiders' Reserve tab, after `Whisper.announce`'s line, in the "opened soft reserves" note and the batch window's title.
  `S.valid` keeps the session and only the right parts of `br` (a newer version's icon number shows as the raid's own).
- **Loot council** (`Core/Council.lua`; `s.lc` = names, `S.cleanCouncil`, `S.COUNCIL_MAX`; `Council.set`, `on`, `isMember`, `votable`, `vote`,
  `myVote`, `counts`, `choice`; `LR.setCouncil`; messages `C` (a vote, to the loot master) and `L` (the counts, to council members, field `vc`:
  `v` is every message's protocol); `!lr vote Name`; `UI.councilSheet`; Session tab "Loot council"): rolls go on as usual and say who wants it;
  `roll.votes` (voter key -> { v, p }) on the loot master's addon only. The master window shows votes per row, "Their choice" (`selectedPlayer`
  picks it once closed) and "the council picks"; a council member's window stays up after the rolls until it's given out (`copy.council`).
  Votes never go to raid chat. Pretend council members vote in the practice raid.
- **Fairness history** (`History.fairness(since, current)`, `History.kindsText`, `History.KIND_ORDER`; `UI/Fair.lua` `UI.fairSheet`, beside
  "Past raids" on the Loot tab, `/lr fair`): per player, their awards across past raids and the session on now (not a practice one), by kind
  (DE for `de`), gold spent, raids attended, last win. Attendance is `s.att` (`S.saw`, `S.cleanAtt`, `S.MAX_ATT`): the leader's session notes
  everyone in the group when it starts and on each roster change; past raids keep it (and a GDKP's `gk.seen` counts too). Older versions
  ignore `att`.
- **Reserve swap requests** (`Core/Swap.lua`; `Swap.ask`, `allow`, `deny`, `pending`, `request`, `Swap.list` (the leader's, in memory),
  `Swap.mine` (a raider's own, until it's answered); message `S` = { id, f, n }; feature bit `FEATURE_SWAP` 4; `!lr swap [old] [new]` or
  `!lr swap old for new`; `UI.swapSheet` on a locked Reserve tab, "Swap requests" panel on the leader's Reserves tab): only while
  locked, one per player (a new one replaces it), checked like a reserve (`S.set` of the whole new list, so it can't half-happen);
  the answer is whispered. Locking a practice raid makes a pretend player ask.
- **Clearing reserves of players not in the group** (`S.absent(s, inGroup)`, `S.clearAbsent(s, inGroup, now)`; `LR.absent`, `LR.clearAbsent`,
  leader only, in a group or the practice raid): a button on the leader's Reserves tab with the count, after `UI.confirm` naming them.
  Offline members are still in the group. Each is cleared like a reserve taken back (`S.set` with no items) and dropped from `s.sx`, so a
  re-import counts what the sheet gives them as new again.
- **The owner's plan from the Gargul comparison is done:** the practice raid, pot rules, GDKP bookkeeping, bidding ahead, several
  auctions at once, bag checks, the gear overview, branding, loot council, fairness history and swap requests.
- **Clearing reserves of players not in the group** is in (#88). Every planned feature is done.
- **Speed work** (asked for by the owner after the benchmark; `docs/benchmark.md`, "After the speed fixes"): `S.byItem` kept
  between changes (#90); the group kept between roster changes (#91: `LR.rosterChanged`, see "Speed rules"); joins don't send
  the session, a newcomer's `Q` is answered by whisper, the guild's copy at most every `GUILD_EVERY` seconds in a group, pot
  membership published slowly (`LR.publish(s, now, slow)`) (#92); `Net.sendNewest` / `Net.sendSession`: only the newest copy of
  something goes out while one is still going (#93, #96 for batches); `R.standings` works out ranks first (#94); finished
  master / batch bars switch their `OnUpdate` off (#95). Not done: lower priority for session copies (long messages at two
  priorities could interleave and be lost), unpacked tiny messages (older versions unpack everything).
- **Next:** the owner is testing in the game. Bump `LR.VERSION` and the TOC to 1.0.0 once that passes. On hold, from the owner's
  list: a `/lr bug` report box, the winner passing (dropped: the loot master undoes and re-gives), rolls surviving a reload (a loot
  master who drops out just rolls again), a Discord recap, drop history on the Reserve tab, "My night", opening reserves on zoning
  in, splitting the loot list per dungeon run (instance numbers: lockout ids, or the zone part of mobs' GUIDs). Not wanted: less
  contested picks, reading Gargul's reserves. Keep an eye on WoW: Forever's new raids.
- **Only what changed** (#119; message `U` = { id, f, r, c = `S.diff` }, `S.patch`, `S.same`; feature bit `FEATURE_CHANGES` 8;
  `Net.everyoneTakesChanges`): the leader keeps a copy of what it last sent each group channel (`groupSent`) and sends the changes
  when everyone in the group with LootRuler has bit 8; a whole `T` goes first, to the guild, by whisper, from a new leader or one
  handing it on, and every `SESSION_FULL_EVERY` sends. A raider whose copy is older than `f` (or who hasn't got it, or hears it
  from someone who isn't its leader) asks the sender by whispered `Q` (answered with `T`), at most every 10 seconds. The patched
  copy goes through `S.valid` and the same path as `T` (`accept`).
- **From the owner's list** (#110, #113-#118): "Open a trade with the winner" off to start with; button rows wrap (`Flow:buttons`;
  a UI test checks no button runs past its panel on any tab); the leader records loot from the game's loot lines when the master
  looter has no LootRuler (`Drops.writer`); "Picked up" note for raiders (`UI/PickedUp.lua`, setting `pickedUp`); one reserve win
  each (`s.ow`, `S.srWinsAll`, checked in `S.claims`); reserves locking by themselves (`Core/Lock.lua`, `s.al`, `UI.autoLockSheet`;
  warnings `Lock.WARN`, a mark already passed when it was set isn't said late); the bench (`s.bn`, `S.setBench`, `S.cleanBench`,
  `Guild.raidMembers(s)` adds the guild's benched players, `Guild.onlineOutside`, `UI.benchSheet`).
- **Trades out of a group** (`Drops.tradeChannel`, `Drops.sayNearby`, `UI.sayPrompt` in `UI/Say.lua`, `LR.sayNow`): with no group, the
  trade line goes to SAY when I lead a session that hasn't ended (or a past GDKP owes this player). The game blocks addon /say
  outside instances unless a click started it, so there the lines wait on a "Say it" box (said with `LR.sayNow`, not the
  ChatThrottleLib queue); inside one (`IsInInstance`) they're said straight away. The stand-in enforces this: `M.click` sets
  `M.hardware`, the test server errors on SAY / YELL without it unless `p.instance` is set.
- **Polish from the owner's in-game screenshots** (#103-#107): title plates in three pieces sized to the title (`K.fitPlate`);
  text boxes carry their own greyed hint (`K.setHint`, `K.onText`; `UI.searchHint` for item searches); on/off switches are
  tick boxes (`tick = true` in `Flow:chips`, `K.setTick`); the softres.it import is first on the Session tab, on the Reserves
  tab and in the new-session form (`UI.importSheet`); Settings sections fold (`Flow:fold`, `section` in `UI/Settings.lua`,
  open ones kept in `db.ui.settingsOpen`). A new setting goes in a section, and its line should say what's in it now.
  The owner kept: the windows' see-through backgrounds, the size, greyed buttons, and the tabs as they are.
- **Loot only from the session's raid** (#111; `Drops.here(s, where)`, gating `Drops.writer`; `LR.RAID_MAPS`, `LR.raidAt`, `LR.where`;
  `UI/Where.lua`: `UI.newRaidPrompt`, `UI.whereCheck`, setting `raidPrompt`): inside the raid's instance (by `GetInstanceInfo`'s
  instance id), outdoors for world bosses, any raid LootRuler doesn't know for a custom raid; the practice raid anywhere. The
  leader entering another raid, or its raid after the lockout it was for ended (`s.le`, from `GetSavedInstanceInfo` on
  `UPDATE_INSTANCE_INFO`), is asked to start a new session (the old one ends and is archived). The test server has places
  (`Server.PLACES`, `srv.where`, `p.where`, `Server:enter`) and lockouts (`p.saved`); loot and UI tests run in Karazhan.
- **Everything that drops is counted** (#112; `LR.minorLoot(s, id)`, `Drops.corpse()`, drops' `n` = a stack): every listed item on a
  corpse (whatever the loot threshold) and in loot messages goes on the list (since #121, only `LR.listedLoot`). "Minor" items (not in the raid's lists, not worn, not
  a recipe, below epic unless a trade good) are shown counted on the Loot tab ("Everything else that dropped"), and left out of
  announcements, `Drops.holding`, `toDeliver`, trade warnings and group-loot awards. The test server has stacks (`openLoot` items'
  third value, `lootTo(p, id, count)`) and `C_Item.GetItemInfoInstant` (from `srv.itemInfo`'s `equip` and `class`).
- **Only the raid's loot is listed** (#121; `LR.listedLoot(s, id)`, `LR.LISTED_LOOT`, `LR.itemClass` (class, subclass); `Drops.spellCast`,
  `Drops.fromProfession`, `Drops.PROFESSION_SPELLS`): a drop goes on the list only if it's worn, a mount (class 15 subclass 5), a recipe
  (class 9), in the raid's lists (tokens, Magtheridon's Head) or on the owner's list `LR.LISTED_LOOT` (marks, Black Temple gems, Amani
  charms, Karazhan's books...). Add a raid's new non-gear loot there (Forever's too). Loot windows within `Drops.PROFESSION_WAIT` seconds
  of my own Disenchant, Prospecting, gathering, Skinning or Pick Pocket / Lock (`UNIT_SPELLCAST_SUCCEEDED`), or while `IsFishingLoot()`,
  aren't read. The stand-in has `Server:cast(p, spellID)`, `M.fishing` and `srv.itemInfo`'s `subclass`.
- **Bosses that open and close** (#126; `UI.bossFold(f, where, key, name, what, fill, force)`, `UI.bossIsOpen`, `UI.bossChips`;
  `db.ui.bossOpen` "<where>:<raid>:<boss>" -> true, closed to start with; `where` is "reserve" or "reserves"): the Reserve tab's loot list
  (`lootList`, with a session or browsing) and the Reserves tab's soft reserves by item. A search or "Reserved only" opens every
  boss with a match (`force`); the 200-row limit counts only open bosses. Tests that click items open them first ("Open all").
- **Known issues and notes from the owner's testing** (add to this list; fix in a later session):
  - (fixed, owner's in-game test, #122) `Net.lua:195: attempt to index upvalue 'db'` at login: `UPDATE_INSTANCE_INFO` came
    between `ADDON_LOADED` and `PLAYER_LOGIN` (where `LR.loadDB` runs), and `UI/Where.lua` read the session. Every event handler
    that reads saved data returns while `LR.db` is nil. The stand-in fires `o.early` (event names) in that gap; `tests/raid.lua`
    fires every event LootRuler listens for there. A new handler needs the same guard.
  - (fixed, owner's in-game test) The softres.it import box couldn't be typed in. Memos (`K.setEditMemo`) now raise their
    inner frames above the memo (the pool raises only the outer frame), focus on a click anywhere in them, take any length,
    and the import box takes the focus when it opens. The stand-in works out frame levels from parents, so it can't show
    a frame hidden under another: tests check the levels are in order instead.
  - (fixed, owner's first in-game test) "Forget it" on someone else's session (and the x beside one) called `LR.forget`,
    which #76 had deleted. And `CONFIRM_DISENCHANT_ROLL` was registered, which TBC doesn't have: an error at every login.
  - (fixed in #27) Re-importing an updated softres.it sheet didn't apply changed picks.
  - (fixed, owner's test) Closing a roll window with its x left the strip of reservers on screen until the roll
    ended (seen with a pretend reserved roll on the Test tab). The strip now goes with the window, and with the
    loot master window when it's hidden.
  - Not yet tried in the real game: everything is tested in the stand-in only. Keep the version at 1.0.0-beta
    until the owner's in-game test passes, then bump `LR.VERSION` and the TOC to 1.0.0.
  - softres.it names must match characters exactly (other realms need "-Realm"); a typo becomes a phantom player.
    (Mostly fixed: capitals, accents and a missing realm are matched; a typo is listed with a one-click fix.)
  - (tested) Party (5-man) master loot now has its own whole-group test (`tests/party.lua`), with a master looter
    who isn't the party's leader.
- **Feedback this plan follows** (an experienced player and engineer):
  - only the loot runner should need the addon;
  - onboarding a pug must be quick;
  - loot for new raids (Forever) isn't known in advance;
  - players don't update addons;
  - pull requests, not pushes to `main`;
  - write down security and speed rules;
  - keep a hand-off note like this one so each session starts fresh and cheap.

## Roadmap

One pull request per feature, in this order. Mark items done here as they merge.

**Done:** soft reserves (sessions, hard reserves, `!lr` whispers, softres.it import, Gargul export), every raid
up to Zul'Aman, roll windows and the loot master window, the raid's loot list with trade help.

**Groundwork**
- [x] This file, and pull-request checks in CI
- [x] Reserve or roll out any item by link; raids that aren't in the built-in lists (Forever)
- [x] Older and newer versions working together
- [x] A Settings tab: one home for options (`LR.DEFAULTS` in `Core/Net.lua`, `UI/Settings.lua`); new features get
      their on/off switch there

**Pug essentials**
- [x] `!lr` in raid chat as well as by whisper (quick onboarding for a whole pug)
- [x] Plus ones: +1 for each win; players with fewer roll first (a session option; counted from the awards)
- [x] Disenchanter: a "Disenchant" choice when nobody wants an item (awards are kind "OS" with `de = true`)
- [x] Export: who won what, to copy out (CSV, thatsmybis, DFT; `Core/Export.lua`), and posted in raid chat
- [x] Trade announcements: a chat line when an item is traded over (both sides, items and gold)

**Less clicking**
- [x] Auto-loot rules for the loot master (greens to the disenchanter, patterns to me; `Core/AutoLoot.lua`)
- [x] Auto-roll rules for raiders (always pass on X; `Core/AutoRoll.lua`)
- [x] Highlighting reserved items in the game's loot window, and reserves in item tooltips (`UI/Highlight.lua`)
- [x] Shortcut keys that don't clash with Gargul's (Ctrl+Alt+click rolls out; `UI/Shortcuts.lua`)

**Guild features**
- [x] Boosted rolls: attendance points that raise a roll's range (and the guild book they live in)
- [x] Priority lists managed in the game (like DFT): officers edit, kept between raids and shared with the
      guild, update themselves when items are won, `!lr prio` for players without the addon, DFT/TMB import
      and export, and loot rules chosen per session (reserves, priority, or both; `Core/Prio.lua`)

**GDKP**
- [x] Auctions (bid in the addon or by typing an amount in raid chat), prices, a queue, the pot with cuts and
      bonuses, payouts (addons can't put gold in a trade, so it tells each player what they're owed;
      `Core/Gdkp.lua`, `Core/Pot.lua`, `UI/Gdkp.lua`)
