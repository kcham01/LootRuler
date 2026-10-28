# Benchmark notes

First measured on 26 October 2026, on `main` after #88 (every planned feature in). The owner then asked for the speed
work: what was done, and the numbers before and after, are in the next section. The findings after it are as first found.

Run it with `lua5.1 tools/bench.lua` (about a minute; `--quick` for a small raid). It writes `build/bench.txt`.
The stress test, `lua5.1 tools/stress.lua` (about a minute), goes past an ordinary night; it writes `build/stress.txt`.

## The latest version, and a stress test (28 October 2026)

Measured on `main` after #135 (everything through "bids not taken"), against the same night on `main` before #121
(after #120), both run on the same computer. Work is Lua instructions in LootRuler's code:

| Moment | Leader before | Leader now | Longest at once, leader | Each raider | Leader's messages |
| --- | --- | --- | --- | --- | --- |
| Forming the raid (39 joins) | 16.3M | **8.8M** | 18.9 → 5.2 ms | 515k → 516k | 72 → 72 |
| Opening reserves | 524k | 450k | 5.5 → 3.4 ms | 125k → 127k | 6 → 6 |
| Reserving (78 reserves) | 13.7M | **7.1M** | 6.5 → 4.0 ms | 298k → 299k | 65 → 65 |
| Lock and post | 503k | 432k | 4.0 → 2.2 ms | 94k → 93k | 5 → 5 |
| A boss dies (1 roll) | 2.8M | 2.7M | 6.5 → 3.6 ms | 495k → 511k | 13 → 13 |
| Rolling out 4 more | 9.9M | 9.9M | 11.5 → 9.3 ms | 2.0M → 2.0M | 34 → 34 |
| The leader's screens | 581k | **310k** | 5.8 → 2.9 ms | | 0 |
| A GDKP auction (25 bids) | 1.7M | 1.8M | 4.6 → 4.2 ms | 524k → 528k | 16 → 16 |
| Five auctions at once (40 bids) | 5.3M | 5.3M | 5.4 → 7.5 ms | 2.7M → 2.7M | 79 → 79 |

- **Forming the raid and reserving cost the leader half what they did.** The bosses on the Reserve tab start closed (#126),
  so the leader's open window lists boss names until one is opened, and its redraws while people join and reserve are
  cheaper. With every boss open it costs what it did before.
- **Nothing else moved** beyond the 2% the benchmark varies by. The features since #121 (a roll for each reserve, only the
  loot runner runs loot, gear by inspection, bids not taken) added no measurable work to an ordinary night, and no messages.
- Loading the addon: 33 ms and 3.1 MB for one player. Saved file: 5 KB after one raid, 109 KB with 30 past raids.
- Where the work is, over the whole night: unpacking messages (LibDeflate 52%, LibSerialize 9%), then roll standings
  (`Core/Roll.lua`, 12%).

**The stress test** (`tools/stress.lua`) pushes past an ordinary night. What it found:

1. **Broken messages:** 5,750 of them, 250 of each of the 23 kinds LootRuler takes, built from a real night's messages and
   broken (wrong types, missing fields, huge lists, deep tables), sent by a raider, by someone outside the group and by the
   leader. One kind, the leader's answer to a raider's reserves, made a Lua error on the raider's screen: fixed in #136.
   Now none does. Nothing anyone but the leader sent changed the leader's session, and raiders kept the leader's session.
   The slowest single message took 23 ms to throw away.
2. **The biggest raid:** 40 players with 10 reserves each, all on one item, so 390 /rolls (a roll for each reserve). The loot
   master's window drew a row for every roll and was redrawn on each: 5.4 s of work over the roll, 35 ms at the longest
   (two frames). #137 lists each player's best roll once and works out roll counts once: 1.9 s, 13 to 19 ms at the
   longest. The session copy is small (636 characters), and every raider's 10 reserves on different items draw the
   Reserves tab in about 10 ms, bosses open or closed.
3. **A long night:** 320 items from 64 corpses, every one given out.
   - A session keeps at most 300 drops (`S.MAX_DROPS`). A real night never comes near it: only the raid's loot is listed
     (#121), and a session only takes loot inside its own raid, on one lockout (#111), so this is a safety cap, not a limit.
   - A whole copy of the session grows to 7.4 KB (30 parts, about 10 seconds to send). Changes go as small updates (#119),
     but every 25th send, and copies to newcomers and the guild, are whole.
   - Giving out an item costs about 3 ms, late in the night as at the start.
   - Given out five every 2 seconds (far faster than a real loot master), raiders' copies had every award 63 seconds after
     the last one: the send queue (about 800 characters a second) catches up.
   - The Loot tab with 300 drops draws in 56 ms. With 30 past raids of 300 awards each, the award history draws in 68 ms
     (only the open day's items are drawn) and "who got what, over time" in 14 ms. The saved file is then 1.7 MB.
4. **Chat floods:** 600 raid chat lines during an auction (a third of them bids) sold the item right, with 3 lines from the
   leader. Gargul's roll lines typed by a raider (not the loot runner) opened no roll windows (#128).

Two ideas from it were then done, asked for by the owner:

- **Redraw** (#139): roll windows and the loot master window redraw at most every `UI.REDRAW_GAP` (0.25) seconds while rolls
  or bids pour in (`UI.atMostEvery`), instead of on every one.
- **Less** (#140): in a group, the guild's copy of the session goes at most every 30 seconds (was 5), and not at all while
  every guild member who's online is in the group; a batch of auctions carries its items' links in its first message and
  every 10th after it, not in every one.

The same night after each (Lua instructions; "raider" is each raider's LootRuler; messages are the leader's):

| Moment | Leader: #138 → Redraw → Less | Raider: #138 → Redraw → Less | Leader's messages: #138 → Less |
| --- | --- | --- | --- |
| A boss dies (1 roll) | 2.7M → 2.0M → **1.2M** | 511k → 423k → **245k** | 13 → 5 |
| Rolling out 4 more | 10.0M → 6.4M → **4.8M** | 2.1M → 1.4M → **1.0M** | 34 → 16 |
| A GDKP auction (25 bids) | 1.9M → 1.9M → **1.0M** | 528k → 531k → **311k** | 16 → 6 |
| Five auctions at once (40 bids) | 5.3M → 5.3M → **4.0M** | 2.7M → 2.7M → **1.6M** | 79 (14 KB) → 53 (10 KB) |
| Reserving | 7.1M → 7.2M → 6.8M | 299k → 299k → 223k | 65 → 61 |
| Lock and post | 432k → 434k → 86k | 93k → 94k → 17k | 5 → 1 |

In this night every guild member is in the raid, so no guild copies go at all; on a real guild night with members online
outside the raid, they still go, at most every 30 seconds. The stress test's 390-roll case went from 1.9 s of the loot
master's work (after #137) to 1.0 s (after #139).

Still to look at: unpacking messages is still the biggest share of a raider's work; whole session copies to newcomers and
every 25th send are the largest messages left.

## Only what changed (#119)

Raiders get the session's changes (message `U`) instead of a whole copy each time, when everyone in the group with LootRuler
takes them. Measured on 27 October 2026, the same raid before and after (in Karazhan: loot is only listed inside a session's
raid since #111). Work is Lua instructions in LootRuler's code, per raider:

| Moment | Raider before | Raider after | Loot runner's messages |
| --- | --- | --- | --- |
| Lock and post | 238k | 93k (-61%) | 8 (2 KB) -> 5 (1 KB) |
| A boss dies | 811k | 499k (-38%) | 19 (4 KB) -> 13 (3 KB) |
| Rolling out the rest | 2.7M | 2.0M (-26%) | 48 (10 KB) -> 34 (6 KB) |
| A GDKP auction | 888k | 523k (-41%) | 23 (5 KB) -> 16 (3 KB) |
| Five auctions at once | 2.9M | 2.7M (-7%) | 83 (15 KB) -> 79 (14 KB) |
| Reserving | 323k | 299k (-7%) | the raid's copies go as one change |

Forming the raid and opening reserves are unchanged: newcomers get a whole copy by whisper, and a new session goes whole.
The loot runner's own work went down with fewer copies to pack (lock and post: 794k -> 512k). Several auctions at once
mostly send their own batch message (`Z`), which this doesn't change.

## After the speed fixes (#90 to #96)

The first run's findings are below as they were found. Seven fixes came from them, one pull request each:

| Pull request | Finding | What it does |
| --- | --- | --- |
| Index (#90) | 3, 4 | "Who reserved this item?" is kept until someone's reserves change (`S.byItem`) |
| Roster (#91) | 5 | The group is read once and kept until the game says it changed, with a lookup by name |
| Quiet (#92) | 1, 2 | Joins don't send the session; a newcomer's question is answered to them only; the guild's copy goes at most every 5 seconds while in a group; who's in a GDKP pot goes out within 10 seconds |
| Queue (#93) | 2 | While a copy of the session is going out, newer ones wait and only the newest goes |
| Standings (#94) | 6 | Each roll's rank and +1s are worked out once before sorting |
| Bars (#95) | 9 | Finished timer bars stop repainting every frame |
| Bids (#96) | 7 | Several auctions at once: only the newest batch update goes out when sending is backed up |

Tried and dropped: keeping folded names and the realm name (no measurable difference once the group was kept).
Not done: sending session copies at a lower priority than rolls (raiders' addons put long messages back together by
sender and channel, so parts of two long messages at different priorities could take turns and both be lost), and
leaving tiny messages unpacked (finding 8; older versions unpack everything they get).

The same night, before and after (40 players; work in Lua instructions, "longest" is the longest single event on
the leader's addon, garbage is the leader's):

| Moment | Leader's work | Leader's longest | Leader's garbage | Each raider's work | Leader's messages | Everyone has it |
| --- | --- | --- | --- | --- | --- | --- |
| Forming the raid (39 joins) | 19.1M → 17.1M | 12.8 → 20.7 ms* | 104 → 98 MB | 2.3M → 0.5M | 108 (16 KB) → 73 (11 KB) | |
| Opening reserves | 0.5M → 0.5M | 5.9 → 5.6 ms | 1 → 1 MB | 0.8M → 0.1M | 30 (6 KB) → 6 (1 KB) | **5.8 s → 0.1 s** |
| Reserving (78 reserves) | 24.7M → 13.9M | 10.9 → 8.0 ms | 208 → 78 MB | 0.3M → 0.3M | 66 → 66 | 0.3 s → 0.3 s |
| Lock and post | 1.0M → 0.8M | 11.1 → 4.0 ms | 3 → 1 MB | 0.2M → 0.2M | 8 → 8 | 0.5 s → 0.5 s |
| A boss dies (1 roll) | 7.8M → 3.3M | 11.9 → 6.4 ms | 48 → 14 MB | 1.3M → 0.8M | 19 → 19 | |
| Rolling out 4 more | 31.3M → 11.1M | **36.5 → 11.7 ms** | 160 → 43 MB | 5.8M → 2.7M | 50 → 50 | |
| The leader's screens | 1.5M → 0.6M | 10.9 → 4.3 ms | 14 → 6 MB | | 0 | |
| A GDKP auction (25 bids) | 4.0M → 2.3M | 6.4 → 6.7 ms | 12 → 4 MB | 1.3M → 0.9M | 23 → 23 | |
| Five auctions at once (40 bids) | 6.9M → 5.6M | 8.5 → 5.5 ms | 14 → 11 MB | 3.6M → 2.9M | 99 (18 KB) → 83 (15 KB) | |

\* "Longest" is CPU time on the computer running the stand-in. Between runs with no change to that part, it moved
between 12 and 21 ms for this moment; the work count (which doesn't move by more than about 2%) went down.

What's left: about two thirds of all the work in the night is unpacking messages (LibDeflate 55%, LibSerialize 11%),
mostly copies of the whole session sent after each award, and batch updates during auctions. The next step would be
sending only what changed (the first idea under "Sending less" below). It's a new kind of message, so it needs care
for older versions; not started, waiting for the owner.

## What was measured

A raid night for **40 players**, played in the test stand-in: the leader (also the loot master) and 29 raiders run
LootRuler, and 10 more don't (they whisper `!lr` and type bids in raid chat). Half the addon users are in the leader's
guild, and the session is a guild one, so it also goes over the guild channel. The night, moment by moment:

1. **Forming the raid:** reserves are open, and 39 players join one at a time.
2. **Opening reserves:** a fresh session for the whole raid.
3. **Reserving:** each addon user picks 2 items; the 10 without the addon whisper twice (78 reserves).
4. **Lock and post.**
5. **A boss dies:** 5 epics; the loot is posted and one item is rolled out.
6. **Rolling out the rest:** 4 more items, with all 39 raiders rolling on each.
7. **Idle for a minute** between pulls.
8. **The leader's screens:** each tab, with 78 reserves on them.
9. **A GDKP auction** with 25 bids typed in raid chat.
10. **Five auctions at once** with 40 bids by number.
11. **The pot split**, 50 times.
12. **Ending the raid**, then **past raids** (who got what over time, across 30 saved raids) and **a reload** with them.

For each moment it records:

- **Work:** Lua instructions run in LootRuler's code and its libraries, counted by sampling every 1,000 instructions.
  The stand-in's own code isn't counted. Runs agree within about 2%, so this is the number to compare between versions.
- **Time:** CPU time on this computer, including the stand-in. Only compare it with itself.
- **Longest at once:** the longest single event, timer or click. At 60 frames a second, one frame is 16.7 ms.
- **Garbage:** memory made and thrown away (what the game's garbage collector has to clean up). It's split between
  LootRuler's own code and the stand-in's, because the stand-in draws frames in Lua while the game does that in C.
- **Network:** addon messages as the game would send them (255 characters each at most, so one message can take
  several parts), by kind and size. For session changes, it also records how long until every raider's addon has it.
- **Screen:** frames made, timers started, and windows running a script every frame (`OnUpdate`).

## The numbers (40 players)

| Moment | Leader's work | Leader's longest | Each raider's work | Leader's messages | Everyone has it |
| --- | --- | --- | --- | --- | --- |
| Forming the raid (39 joins) | 19.1M | 12.8 ms | 2.3M | 108 (16 KB) | |
| Opening reserves | 0.5M | 5.9 ms | 0.8M | 30 (6 KB) | **5.8 s** |
| Reserving (78 reserves) | 24.7M | 10.9 ms | 0.3M | 66 (6 KB) | 0.3 s |
| Lock and post | 1.0M | 11.1 ms | 0.2M | 8 (2 KB) | 0.5 s |
| A boss dies (1 roll) | 7.8M | 11.9 ms | 1.3M | 19 (4 KB) | |
| Rolling out 4 more | 31.3M | **36.5 ms** | 5.8M | 50 (10 KB) | |
| Idle for a minute | 10k | 0.2 ms | 6k | 0 | |
| The leader's screens | 1.5M | 10.9 ms | | 0 | |
| A GDKP auction (25 bids) | 4.0M | 6.4 ms | 1.3M | 23 (5 KB) | |
| Five auctions at once (40 bids) | 6.9M | 8.5 ms | 3.6M | 99 (18 KB) | |
| The pot split, 50 times | 0.2M | 1.4 ms | | 0 | |
| Past raids (30), 10 times | 1.5M | 2.0 ms | | 0 | |

Also:

- **Loading the addon:** about 30 ms and 3 MB for one player.
- **Saved file:** 5 KB after one raid, and 109 KB with 30 past raids like it. A reload with them took 35 ms here.
- **Idle:** close to nothing. 10k instructions a minute for the leader, no messages.

**Where the work is**, for every player together over the whole night:

| Share | What |
| --- | --- |
| 43% | LibDeflate: unpacking (and packing) addon messages. Unpacking alone is about 39%. |
| 8% | LibSerialize: reading messages after they're unpacked |
| 8% | `LR.roster`: the group list, built again on each call |
| 8% | `S.byItem`: who reserved what, built again for each item looked up |
| 11% | Names: `U.full`, `U.foldCase`, `U.samePlayer`, `U.realm` (mostly called from the two above) |
| 10% | Roll standings: sorting the rolls (`R.standings`, `rank`, `R.kind`, `R.plusOnes`) |

## Findings

Most important first. Each one says what the benchmark showed, why it matters in the game, and where it is in the code.

### 1. Every change sends the whole session to everyone, often twice

- **What it showed:** while 39 players joined, the leader sent the full session 48 times (85 message parts, 13 KB).
  Each join changes the attendance list (`s.att`, for "who got what over time"), and that counts as a session change
  (`Core/Net.lua`, the `"roster"` handler calls `LR.leaderChanged`). With a guild session, every copy goes to both raid
  and guild chat (`publishTo`). Guild members in the raid get both copies and unpack both.
- **Why it matters:** unpacking messages, mostly these session copies, is the biggest single cost for every raider (about
  39% of all the work in the night). Session copies are also most of what the leader's addon sends.
- **The same pattern shows up elsewhere:** each award resends the whole session too, and it grows as loot is given out:
  4 parts for the first roll, up to 5 by the end, and about 1.2 KB by the GDKP auction.

### 2. Old session copies wait in line ahead of new ones

- **What it showed:** reserves opened 5.8 seconds before every raider had the new session. Everywhere else, a change
  reached everyone in under half a second.
- **Why:** the leader's send queue (ChatThrottleLib, about 800 bytes a second) still held six copies of the old session
  from the joins, already out of date. They went out first, 0.6 seconds apart. During the joins the leader averaged about
  580 bytes a second, close to that limit.
- **Why it matters:** in a real raid, a reserve or roll can show up seconds late. If anything else is sending (other
  addons, Gargul, DBM), the shared throttle is fuller still.

### 3. "Who reserved this?" rebuilds the whole list for each item

- **What it showed:** `S.byItem(s)` builds the full item → reservers table every time it's called. Callers use it to
  look up one item: `S.byItem(s)[id]` in `R.plan`, the Reserve tab's rows (`UI/Reserve.lua:185` and `:312`), the loot
  window tags, tooltips, auto-loot rules and the loot master window. It was 37% of all the work while people were
  reserving (nearly all of that moment's work is the leader's), and 48% of drawing the leader's screens.
- **Why it matters:** the cost is the number of items on screen times the number of reserves, so it grows quickly in
  big raids. It also makes a lot of garbage.

### 4. The leader's open window redraws on every reserve

- **What it showed:** with the leader's window open, the reserving moment cost the leader 633 ms and 214 MB of garbage
  (78 reserves). With it closed, 48 ms and 7 MB. About 60% of that garbage is LootRuler's own code, and the rest is the
  stand-in drawing (in the game that part is C, not Lua garbage).
- **Why it matters:** about 2.7 MB of garbage per reserve while the window is open (about 1.6 MB of it LootRuler's).
  The game's collector runs in steps, so this means more time spent collecting rather than one big pause. Batching
  (`UI.renderSoon`) already merges bursts; each redraw is just expensive because of finding 3.

### 5. The group list is read from the game on every call

- **What it showed:** `LR.roster()` builds a fresh list from `GetRaidRosterInfo` each time, and `LR.inGroup(name)` scans
  it. It was 8% of all work, and the busiest function (14% of all the work) while the 4 items were rolled out (each
  `/roll` checks who's in the group). With the name functions it calls, that comes to about 20%. Even when idle it's the busiest function (the trade
  timers check every 30 seconds).
- **Already planned:** keep the roster between roster changes, with a name index.

### 6. Sorting the rolls repeats the same lookups

- **What it showed:** rolling 4 items with 39 rollers each cost the leader 31.3M instructions. The **longest single
  event of the night was 36.5 ms** (more than two frames at 60 fps), during these rolls, in the stand-in. `R.standings`
  calls `rank` → `R.kind` and `R.plusOnes` (which counts the player's wins) inside the sort's comparison, so each
  comparison does it again. It runs after every roll, on the leader's addon and in every raider's roll window.
- **Why it matters:** 40 `/roll`s in two seconds is the busiest moment a loot master's addon has.

### 7. Several auctions at once: every bid resends the whole batch

- **What it showed:** 40 bids sent the batch 42 times (84 parts, about 15 KB). Every raider unpacked each one (3.6M
  instructions each, the most for a raider in any moment after the raid formed).
- **Why it matters:** same as finding 1. It's a smaller message, but it's sent much more often while bids come in.

### 8. Every message is packed, even tiny ones

- **What it showed:** "who has LootRuler?" questions and answers (`Q`, `V`) are 29 characters packed. Packing and
  unpacking a tiny message costs more work than it saves in size.
- **Careful:** older versions unpack everything they receive. Changing how a message is packed would need a new message
  kind or prefix that older versions ignore (see "Versions" in `AGENTS.md`).

### 9. Finished bars keep repainting

- **What it showed:** after a roll or a batch of auctions ends, the loot master window (`UI.masterTick`) and the auction
  window (`UI.batchTick`) stay open. They set the same bar width, colour and text every frame until they're closed. The
  auction window stayed up on raiders' screens even after the session ended.
- **Why it matters:** it's small (a few game calls a frame), but it goes against the speed rule "no work every frame
  except timer bars that are on screen", and it lasts as long as nobody closes the window.

### 10. Small things

- The leader started about 170 one-shot timers (`C_Timer.After`) per roll. That's cheap, but there may be a chain that
  could be one timer.
- Every join makes the new player's addon ask "who has LootRuler?", and everyone answers (45 questions and 30 answers
  while the raid formed).

## What's fine

- **Idle cost** is close to zero, and nothing is sent when nothing happens.
- **Raiders' addons** stay light. Their longest single event was 3.3 ms, and their work is mostly unpacking messages.
- **The GDKP pot split** (about 4,000 instructions each time) and **who got what over time** (about 150k across 30 past
  raids) are cheap.
- **Saved data** stays small, and reloading with 30 past raids is quick.
- **Chat lines** stay under 255 characters (the stand-in would have stopped the run otherwise), and whispers back to
  players without the addon are one line per request.
- **Screens** reuse their frames. Redrawing all tabs 10 more times made no new frames.

## Ideas (brainstorm, not decided)

**Sending less**

- **Send changes, not whole sessions:** a new message kind carrying the session id, its revision and what changed (one
  player's reserves, one award, a setting). Older versions ignore it, and they'd still get a full copy every so often or
  when they ask. If a raider sees a gap in the revisions, it asks for the whole copy. Finding 1 and finding 7 both go.
- **Don't count attendance as a change to send:** keep `s.att` on the leader's addon and send it with the next real
  change, or only when the session ends. Raiders' screens don't show it.
- **One copy per player:** while the group holds the guild members who'd want it, send to the raid only. Send to the guild
  only for guild members not in the group (before the raid), or answer their `GQ`/`Q` by whisper instead.
- **Drop out-of-date copies before they're sent:** LootRuler's own small queue in front of ChatThrottleLib, where a new
  copy of the same session replaces the one still waiting. Messages by priority (rolls and bids first, session copies
  last) was planned already, and it fits here.
- **Leave tiny messages unpacked:** for new kinds only (finding 8), for example a marker character that new versions
  understand.
- **Batches:** send one bid as a small message (item number, bidder, amount) instead of the whole batch.

**Working less**

- **Remember who reserved what:** build `S.byItem` once per session revision (or keep it up to date in `S.set`). Every
  `S.byItem(s)[id]` call stays as it is, but each one becomes a table lookup.
- **Keep the roster:** build it on `GROUP_ROSTER_UPDATE` (and on login), with an index by name. `LR.inGroup` becomes one
  lookup. This was planned already.
- **Sort the rolls once per change:** work out each roll's rank and the player's +1s before sorting, then sort on those.
  Keep the result until the next roll comes in. Roll windows show the top five, so they could reuse it.
- **Names:** cache `U.full` and `U.foldCase` results by name. They're called thousands of times with the same few names.
- **Redraw less:** when the open tab doesn't show what changed, don't redraw it. On the Reserves tab, redraw only the
  row whose reserves changed.
- **Stop finished bars:** clear the `OnUpdate` script when a roll or batch is over, and set it again when one starts.

**Measuring in the game**

- **`/lr perf`:** LootRuler's memory (`UpdateAddOnMemoryUsage`, `GetAddOnMemoryUsage`), and its CPU time when the game's
  script profiling is on (`GetAddOnCPUUsage`; it slows the game, so only for a test), with the messages sent and received
  this session by kind.
- **A busy practice raid:** a button on the Test tab for 40 pretend players who reserve, roll and bid as fast as the
  benchmark does. The owner could then watch `/lr perf` and the frame rate in the real game.
- **The benchmark in CI:** message counts and sizes don't change from run to run, so CI could compare them with a saved
  baseline and fail when a change makes them a lot worse. Work could be checked with a margin (for example 10%).

**To check in the game (the stand-in can't tell)**

- Whether the game throttles addon messages per prefix on this client, as newer clients do. If it does, a burst of
  session copies could be dropped rather than just delayed.
- How long a 40-player `/roll` burst takes on a real loot master's computer, with `/lr perf` and other addons loaded.
- How the garbage from finding 4 feels in a raid (stutters, or nothing noticeable).

## Limits of these numbers

- The stand-in isn't the game. Work counts are exact for LootRuler's Lua, but the game runs the drawing in C, so times
  here are rough. Use them to compare moments with each other, and versions with each other.
- Network timings come from ChatThrottleLib running in the stand-in, with the game's clock. Real servers, other addons'
  messages and lag aren't modelled.
- 30 of 40 players run LootRuler here. A pug with fewer addon users does less unpacking overall, but the leader's work and
  messages stay about the same.
