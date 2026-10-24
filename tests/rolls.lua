-- The rules of rolling for an item on their own (Core/Roll.lua), and loot given out on the session.
--   lua5.1 tests/rolls.lua
local failed, passed = 0, 0
local function check(name, ok, detail)
  if ok then passed = passed + 1 else failed = failed + 1 end
  print((ok and "ok   " or "FAIL ") .. name .. ((not ok and detail ~= nil) and ("  " .. tostring(detail)) or ""))
end

local LR = {}
local env = setmetatable({ bit = require("bit"), GetRealmName = function() return "Dreamscythe" end,
  GetNormalizedRealmName = function() return "Dreamscythe" end, RAID_CLASS_COLORS = {} }, { __index = _G })
for _, f in ipairs({ "Data/Loot.lua", "Core/Util.lua", "Core/Loot.lua", "Core/Session.lua", "Core/Roll.lua" }) do
  local chunk = assert(loadfile("LootRuler/" .. f))
  setfenv(chunk, env)
  chunk("LootRuler", LR)
end
local U, S, R = LR.U, LR.Session, LR.Roll

local WATCH, BROOCH, HANDWRAPS = 28528, 28530, 28507
local ANN, BOB, CARA, DAN = "Ann-Dreamscythe", "Bob-Faerlina", "Cara-Dreamscythe", "Dan-Dreamscythe"
local roster = { { name = ANN }, { name = BOB }, { name = DAN } }   -- Cara isn't here

local s = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 100)
S.set(s, ANN, "PRIEST", { WATCH, WATCH }, false, 101)
S.set(s, BOB, "MAGE", { WATCH }, false, 102)
S.set(s, CARA, "DRUID", { WATCH, BROOCH }, false, 103)
S.setHR(s, HANDWRAPS, "Dan", "healer", 104)

print("== how an item is rolled for")
local p = R.plan(s, WATCH, roster)
check("reserved by people here: only they roll", p.mode == "SR" and #p.who == 2 and p.who[1][1] == ANN and p.who[1][2] == 2 and p.who[2][1] == BOB)
check("reservers who aren't in the group are left out, and named", #p.away == 1 and p.away[1] == CARA)
p = R.plan(s, BROOCH, roster)
check("reserved only by someone who isn't here: everyone rolls", p.mode == "OPEN" and p.away[1] == CARA)
p = R.plan(s, 28525, roster)
check("nobody reserved it: everyone rolls", p.mode == "OPEN" and #p.away == 0)
p = R.plan(s, HANDWRAPS, roster)
check("hard reserved: nobody rolls", p.mode == "HR" and p.f == "Dan" and p.n == "healer")
check("no soft reserves open: everyone rolls", R.plan(nil, WATCH, roster).mode == "OPEN")

print("== an open roll")
local roll = R.new("k1", 28525, R.plan(s, 28525, roster))
check("main spec and off spec", table.concat(R.options(roll, DAN), ",") == "MS,OS")
R.add(roll, "Dan", 40, 1, 100)
R.add(roll, "Bob-Faerlina", 95, 1, 99)
R.add(roll, "Ann", 60, 1, 100)
R.add(roll, "Ann", 99, 1, 100)
R.add(roll, "Cara", 100, 1, 50)
local good, bad = R.standings(roll)
check("main spec beats a higher off spec roll", good[1].p == ANN and good[1].n == 60 and good[2].p == DAN and good[3].p == BOB and good[3].kind == "OS")
check("only the first roll counts", #good == 3 and bad[1].p == ANN and bad[1].why == "again")
check("a roll of the wrong range doesn't count", bad[2].p == CARA and bad[2].why == "range")
local top, tied = R.result(roll)
check("the winner", top.p == ANN and not tied)
check("everyone who may roll isn't known for an open roll", R.waiting(roll) == nil)

print("== a soft reserved item")
roll = R.new("k2", WATCH, R.plan(s, WATCH, roster))
check("a reserver rolls 1-100", table.concat(R.options(roll, ANN), ",") == "SR")
check("someone who didn't reserve it can't roll", #R.options(roll, DAN) == 0 and select(2, R.canRoll(roll, DAN)) == "notReserved")
R.add(roll, "Dan", 100, 1, 100)
R.add(roll, "Bob-Faerlina", 12, 1, 100)
check("their roll doesn't count", (R.result(roll)).p == BOB)
check("waiting for Ann", #R.waiting(roll) == 1 and R.waiting(roll)[1] == ANN)
R.pass(roll, "Ann")
check("nobody left to wait for once Ann passes", #R.waiting(roll) == 0)
R.add(roll, "Ann", 12, 1, 100)
top, tied = R.result(roll)
check("a tie", tied and #tied == 2 and tied[1] == BOB and tied[2] == ANN, tied and table.concat(tied, ","))
R.add(roll, "Bob-Faerlina", 50, 1, 100, true)
check("a roll after the close is late", select(2, R.standings(roll))[2].why == "late")

print("== a tie, rolled again")
roll = R.new("k3", WATCH, { mode = "TIE", who = { ANN, BOB }, tie = "SR" })
check("only the tied players", #R.options(roll, DAN) == 0 and R.options(roll, ANN)[1] == "SR")
R.add(roll, "Ann", 70, 1, 100)
R.add(roll, "Dan", 99, 1, 100)
check("they roll the way they did before, still for the reserve", (R.result(roll)).p == ANN and (R.result(roll)).kind == "SR")
roll = R.new("k4", 28525, { mode = "TIE", who = { ANN, BOB }, tie = "OS" })
R.add(roll, "Ann", 70, 1, 100)
R.add(roll, "Bob-Faerlina", 20, 1, 99)
check("an off spec tie is rolled with /roll 99", (R.result(roll)).p == BOB)

print("== loot given out")
check("Ann has two reserves on the watch to claim", S.claims(s, ANN, WATCH) == 2)
S.award(s, WATCH, ANN, "SR", 88, 110)
check("winning it uses one up", S.claims(s, ANN, WATCH) == 1 and S.srWins(s, ANN, WATCH) == 1)
S.award(s, WATCH, BOB, "SR", 70, 111)
p = R.plan(s, WATCH, roster)
check("when another drops, Bob has nothing left to claim and Ann still has one", p.mode == "SR" and #p.who == 1 and p.who[1][1] == ANN and p.who[1][2] == 1)
S.award(s, WATCH, ANN, "SR", 50, 112)
check("once Ann's both are used up, everyone rolls", R.plan(s, WATCH, roster).mode == "OPEN")
S.award(s, 28525, DAN, "MS", 40, 113)
check("winning on a main spec roll doesn't use up a reserve", S.claims(s, DAN, 28525) == 0 and #S.winners(s, 28525) == 1)
check("the record keeps who and how", s.won[1].p == ANN and s.won[1].k == "SR" and s.won[1].r == 88)
check("a session with loot given out is still valid", S.valid(s))
local rev = s.rev
S.unaward(s, 3, 114)
check("a mistake can be taken back", #s.won == 3 and S.claims(s, ANN, WATCH) == 1 and s.rev == rev + 1)
check("and something nonsensical isn't recorded", not S.award(s, WATCH, ANN, "BEST", 1, 115))
local bad1 = U.copy(s) bad1.won = { { i = "x", p = ANN, k = "SR" } }
check("a session with a broken record isn't trusted", not S.valid(bad1))

print("== the raid's drops")
local s2 = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 200)
S.set(s2, ANN, "PRIEST", { WATCH }, false, 201)
local LEAD = "Lead-Dreamscythe"
check("a drop goes on the list", S.addDrop(s2, { k = "a", i = WATCH, b = "Moroes", at = 202, by = LEAD, src = "g1" }, 202) and #s2.drops == 1)
check("the same drop again doesn't", not S.addDrop(s2, { k = "a", i = WATCH, b = "Moroes" }, 203) and #s2.drops == 1)
S.addDrop(s2, { k = "b", i = WATCH, b = "Moroes", by = LEAD }, 204)
check("still on the corpse", S.dropState(s2, s2.drops[1]) == "corpse")
local rev = s2.rev
check("who has it is brought up to date", S.addDrop(s2, { k = "a", i = WATCH, h = LEAD, ht = 205 }, 205) and s2.drops[1].h == LEAD and s2.rev == rev + 1)
check("the loot master holding it, to roll out", S.dropState(s2, s2.drops[1]) == "held")
S.award(s2, WATCH, ANN, "SR", 80, 206)
check("an award goes to the first drop nobody's won", s2.won[1].d == "a" and #S.openDrops(s2, WATCH) == 1 and S.openDrops(s2, WATCH)[1].k == "b")
check("won, and the loot master still has it to trade", S.dropState(s2, s2.drops[1]) == "toTrade")
S.addDrop(s2, { k = "a", i = WATCH, h = ANN }, 207)
check("traded: given", S.dropState(s2, s2.drops[1]) == "given")
S.award(s2, WATCH, BOB, "SR", 30, 208, "b")
check("an award can name its drop", s2.won[2].d == "b" and S.dropState(s2, s2.drops[2]) == "given")
S.addDrop(s2, { k = "c", i = BROOCH, h = DAN, by = LEAD }, 209)
check("someone else looted it, not through LootRuler", S.dropState(s2, s2.drops[3]) == "looted")
S.addDrop(s2, { k = "d", i = BROOCH, h = DAN }, 210)
check("with no loot master (group loot) whoever has it looted it", S.dropState(s2, s2.drops[4]) == "looted")
check("a session with drops is valid", S.valid(s2))
check("a drop off the list keeps its award, unlinked", S.removeDrop(s2, "b", 211) and #s2.drops == 3 and s2.won[2].d == nil)
local bad2 = U.copy(s2) bad2.drops = { { k = 1, i = WATCH, b = "" } }
check("a broken drop isn't trusted", not S.valid(bad2))
check("names from the loot message", ("Bob receives loot: [X]."):match(U.pattern("%s receives loot: %s.")) == "Bob")
check("the x2 kind", select(3, ("You receive loot: [X]x2."):match(U.pattern("You receive loot: %sx%d."))) == nil
  and select(2, ("You receive loot: [X]x2."):match(U.pattern("You receive loot: %sx%d."))) == "2")

print("== reading roll messages")
local parse = R.parser("%s rolls %d (%d-%d)")
local name, n, lo, hi = parse("Bob-Faerlina rolls 57 (1-100)")
check("English", name == "Bob-Faerlina" and n == 57 and lo == 1 and hi == 100)
check("other lines aren't rolls", parse("Bob has come online.") == nil and parse("Bob rolls 57 (1-100) and more") == nil)
local de = R.parser("%1$s würfelt. Ergebnis: %2$d (%3$d-%4$d)")
name, n, lo, hi = de("Bob würfelt. Ergebnis: 3 (1-99)")
check("a translation with numbered places", name == "Bob" and n == 3 and hi == 99)
check("names for chat", R.names({ { ANN, 2 }, { BOB, 1 }, { DAN, 1 } }, 2) == "Ann x2, Bob-Faerlina, +1")

print(("passed %d"):format(passed))
print(("errors %d"):format(failed))
os.exit(failed == 0 and 0 or 1)
