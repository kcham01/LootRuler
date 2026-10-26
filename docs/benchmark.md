# Benchmark notes

Measured on 26 October 2026, on `main` after #88 (every planned feature in). Nothing in the addon was changed because
of these notes: they're findings and ideas for the owner to choose from.

Run it with `lua5.1 tools/bench.lua` (about a minute; `--quick` for a small raid). It writes `build/bench.txt`.

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
