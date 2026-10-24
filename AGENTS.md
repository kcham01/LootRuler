# LootRuler: notes for whoever works on this repo (people and AI agents)

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
  No AI author, no `Co-Authored-By` lines, no "generated with" lines, in commits or pull requests.
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
README's download link points at.

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
  so importing an updated sheet replaces those (swaps, removals) and leaves reserves made in LootRuler alone; an
  item reserved in both places counts once. (Before this, re-importing skipped changed picks: the old ones stayed.)
- **From Gargul:** +1s and boosted roll points as "Name,Number" lines (`Prio.parseCounts`, `Prio.countsText`), read
  straight from a loaded Gargul (`Gargul.counts`, its own export) or pasted. +1s set with `S.setPlusOnes`.
- **Next:** the roadmap and the follow-ups are done. Bump `LR.VERSION` and the TOC to 1.0.0 once the owner has
  tried it in the game. Keep an eye on WoW: Forever's new raids.
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
