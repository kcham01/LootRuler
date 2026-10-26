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
| `tests/` | `session.lua`, `rolls.lua` (rules), `raid.lua`, `loot.lua`, `guild.lua`, `gdkp.lua` (whole raids), `gargul.lua` (the reserves handed to Gargul, without Gargul), `ui.lua` |
| `tests/wow/mock.lua` | A strict stand-in for the game client; `server.lua` runs many clients side by side |
| `tools/` | `check_api.lua` (only what the client has), `render.mjs` (pictures), `gen_loot.py`, `art.mjs` |
| `ci/` | `build.sh` (everything CI runs), `publish.sh` (results branch) |

## Working rules

- **Commits are the owner's.** Author and committer: `Jamesthefishguy <94383428+kcham01@users.noreply.github.com>`.
  No other authors, co-author lines or signatures in commits or pull requests.
- **Names are one plain word:** every commit message and pull request title (for example "Give", "Strip").
  The pull request's description says what changed.
- **Never push to `main`.** One branch and one pull request per feature. The owner reviews and merges.
- **A pull request says** what changed for players (in plain words, not code words), how it was tested, and
  shows pictures of anything on screen (from `build/shots`).
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
  invites or anything else on the player's behalf.
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

## How to check your work

```sh
lua5.1 tests/session.lua && lua5.1 tests/rolls.lua && lua5.1 tests/raid.lua && lua5.1 tests/loot.lua && lua5.1 tests/guild.lua && lua5.1 tests/gdkp.lua
lua5.1 tests/gargul.lua
lua5.1 tools/check_api.lua <wow-ui-source checkout, branch classic_anniversary>
lua5.1 tests/ui.lua && node tools/render.mjs build/shots   # PW_CHROMIUM=<chromium> if Playwright's isn't installed
```

CI (`.github/workflows/build.yml`) runs all of it on every pull request and on `main`. Pull requests get the
pictures and the zip as a download on the run; `main` publishes them to the `results` branch, which the
README's download link points at. Pictures are published numbered and under their name alone
(`results/shots/loot-master.png`): the README links the names, so adding a screen doesn't move its pictures.

The mock is strict on purpose: a method the client doesn't have is an error, and `check_api.lua` checks the
mock and the addon against Blizzard's own interface code. When the addon needs a new game function, add it to
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
- **Opening a trade with the winner** (`Drops.openTrade`, `LR.unitOf`, setting `autoTrade`, on to start with): an award
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
- **Trade timers** (`UI/Timers.lua`, `Drops.holding`, setting `tradeTimers`, on to start with): a window listing the loot master's
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
- **Next:** the roadmap and the follow-ups are done. Bump `LR.VERSION` and the TOC to 1.0.0 once the owner has
  tried it in the game. Keep an eye on WoW: Forever's new raids.
- **Known issues and notes from the owner's testing** (add to this list; fix in a later session):
  - (fixed in #27) Re-importing an updated softres.it sheet didn't apply changed picks.
  - (fixed, owner's test) Closing a roll window with its x left the strip of reservers on screen until the roll
    ended (seen with a pretend reserved roll on the Test tab). The strip now goes with the window, and with the
    loot master window when it's hidden.
  - Not yet tried in the real game: everything is tested in the stand-in only. Keep the version at 1.0.0-beta
    until the owner's in-game test passes, then bump `LR.VERSION` and the TOC to 1.0.0.
  - softres.it names must match characters exactly (other realms need "-Realm"); a typo becomes a phantom player.
    (Mostly fixed: capitals, accents and a missing realm are matched; a typo is listed with a one-click fix.)
  - Party (5-man) master loot is coded and unit-tested but has had less whole-group testing than raids.
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
