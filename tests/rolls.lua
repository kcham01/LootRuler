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
for _, f in ipairs({ "Data/Loot.lua", "Core/Util.lua", "Core/Loot.lua", "Core/Session.lua", "Core/Roll.lua", "Core/Export.lua", "Core/Book.lua", "Core/Prio.lua", "Core/Gdkp.lua", "Core/Notes.lua" }) do
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

print("== one reserve win each")
local ow = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 200)
S.set(ow, ANN, "PRIEST", { WATCH, BROOCH }, false, 201)
S.set(ow, BOB, "MAGE", { BROOCH }, false, 202)
check("off to start with", not ow.ow and S.setOneWin(ow, true, 203) and ow.ow == true and not S.setOneWin(ow, true, 204))
S.award(ow, WATCH, ANN, "SR", 80, 205)
check("once Ann wins a reserve, her other one stops counting", S.claims(ow, ANN, BROOCH) == 0 and S.claims(ow, BOB, BROOCH) == 1)
p = R.plan(ow, BROOCH, roster)
check("so only Bob rolls for the brooch as a reserve", p.mode == "SR" and #p.who == 1 and p.who[1][1] == BOB)
S.award(ow, 28525, ANN, "MS", 40, 206)
check("a main spec win doesn't count as a reserve win", S.srWinsAll(ow, ANN) == 1 and S.srWinsAll(ow, BOB) == 0)
S.setOneWin(ow, false, 207)
check("switched off, her other reserve counts again", ow.ow == nil and S.claims(ow, ANN, BROOCH) == 1)
ow.ow = "yes"
check("saved or sent wrong, it's dropped, not trusted", S.valid(ow) and ow.ow == nil)
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

print("== changing an award (a mistake)")
do
  local es = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 600)
  S.set(es, ANN, "PRIEST", { WATCH }, false, 601)
  S.award(es, WATCH, ANN, "SR", 80, 602)
  check("a reserve that won is used up", S.claims(es, ANN, WATCH) == 0)
  check("changed to main spec: the reserve counts again, and it's a +1", S.editAward(es, 1, ANN, "MS", 603) and S.claims(es, ANN, WATCH) == 1 and S.plusOnes(es, ANN) == 1)
  check("given to someone else", S.editAward(es, 1, BOB, "OS", 604) and es.won[1].p == BOB and es.won[1].k == "OS" and S.plusOnes(es, ANN) == 0)
  check("to disenchant", S.editAward(es, 1, DAN, "DE", 605) and es.won[1].k == "OS" and es.won[1].de == true)
  check("nothing changed: nothing to send", not S.editAward(es, 1, DAN, "DE", 606))
  check("not to nonsense", not S.editAward(es, 1, DAN, "XX", 607) and not S.editAward(es, 9, DAN, "MS", 607))
  S.award(es, 28525, BOB, "BID", 500, 608)
  check("a sale isn't changed here (its price is, on the GDKP panel)", not S.editAward(es, 2, ANN, "MS", 609))
  check("still a good session", S.valid(es))
end

print("== the +1 rule")
roll = R.new("p1", 28525, { mode = "OPEN", po = { [ANN:lower()] = 1 } })
R.add(roll, "Ann", 90, 1, 100)
R.add(roll, "Dan", 40, 1, 100)
R.add(roll, "Bob-Faerlina", 99, 1, 99)
check("a main spec roll with fewer +1s wins over a higher one with more", (R.result(roll)).p == DAN)
check("off spec rolls still come after main spec", select(1, R.standings(roll))[3].p == BOB)
check("the +1 shows with the roll", R.label(roll, roll.rolled[ANN:lower()]) == "MS +1" and R.label(roll, roll.rolled[DAN:lower()]) == "MS")
roll = R.new("p2", 28525, { mode = "OPEN", po = { [ANN:lower()] = 1 } })
R.add(roll, "Ann", 50, 1, 100)
R.add(roll, "Dan", 50, 1, 100)
check("equal rolls aren't a tie when the +1s differ", select(2, R.result(roll)) == nil and (R.result(roll)).p == DAN)
local s3 = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 400)
S.award(s3, 28525, ANN, "MS", 80, 401)
S.award(s3, 28528, ANN, "SR", 70, 402)
S.award(s3, 28530, ANN, "OS", 30, 403)
check("only main spec wins are +1s", S.plusOnes(s3, ANN) == 1)
check("the leader can give one", S.adjustPlusOne(s3, ANN, 1, 404) and S.plusOnes(s3, ANN) == 2)
check("or take one off", S.adjustPlusOne(s3, "Ann", -1, 405) and S.plusOnes(s3, ANN) == 1)
check("never below none", S.adjustPlusOne(s3, ANN, -1, 406) and not S.adjustPlusOne(s3, ANN, -1, 407) and S.plusOnes(s3, ANN) == 0)
check("the table for a roll", next(S.plusOneTable(s3, { ANN, DAN })) == nil and S.adjustPlusOne(s3, DAN, 1, 408) and S.plusOneTable(s3, { ANN, DAN })[DAN:lower()] == 1)
check("a session with +1s is valid", S.setPlusOne(s3, true, 409) and S.valid(s3))

print("== the disenchanter")
local s4 = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 500)
check("the leader picks a disenchanter", S.setDisenchanter(s4, "Dan", 501) and s4.de == DAN)
S.award(s4, 28525, DAN, "OS", nil, 502, nil, true)
check("a disenchanted item is an off spec award marked to disenchant (older versions read it as off spec)", s4.won[1].k == "OS" and s4.won[1].de == true)
check("it isn't a +1", S.plusOnes(s4, DAN) == 0)
check("and shows as disenchanted", S.winners(s4, 28525)[1][2] == "DE")
check("nobody", S.setDisenchanter(s4, nil, 503) and s4.de == nil)
local bad3 = U.copy(s4) bad3.de = 5
check("a broken disenchanter isn't trusted", not S.valid(bad3))

print("== exporting who won what")
local s5 = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 1760000000)
S.addDrop(s5, { k = "x1", i = 28525, b = "Moroes", at = 1760000000 }, 1760000000)
S.award(s5, 28525, ANN, "MS", 77, 1760000000)
S.award(s5, 32386, BOB, "SR", 12, 1760000100)
S.award(s5, 28530, DAN, "OS", nil, 1760000200, nil, true)
local csv = LR.Export.text(s5, "csv")
local lines = {}
for l in csv:gmatch("[^\n]+") do lines[#lines + 1] = l end
check("a spreadsheet: a heading and a line each", #lines == 4 and lines[1] == "Date,Time,Item,Item ID,Player,How,Roll,Boss")
check("with the item, player, how, roll and boss", lines[2]:find(",28525,Ann,MS,77,Moroes$") ~= nil, lines[2])
check("a name with a comma is quoted", lines[2]:find('"Signet of Unshakable Faith"', 1, true) or lines[2]:find("Signet of Unshakable Faith,", 1, true))
check("disenchanted", lines[4]:find(",Dan,disenchant,,", 1, true) ~= nil, lines[4])
local tmb = LR.Export.text(s5, "tmb")
check("thatsmybis: its columns, the name without the realm, and Magtheridon's head as TMB knows it",
  tmb:find("^dateTime,character,itemID,offspec,id\n") and tmb:find("\n%d+%-%d+%-%d+,Bob,32385,0,") and tmb:find(",Dan,28530,1,"), tmb)
local dft = LR.Export.text(s5, "dfteu")
check("DFT: date;[item];player, without disenchanted items", select(2, dft:gsub("\n", "\n")) == 1 and dft:find(";%[28525%];Ann%-Dreamscythe") ~= nil, dft)

-- your own layout
local own = LR.Export.text(s5, "own", { header = "When;Who;What;How;Raid", template = "{date};{name};{item} ({id});{how} {roll};{raid} by {leader} {nope}" })
local ol = {}
for l in own:gmatch("[^\n]+") do ol[#ol + 1] = l end
check("your own layout: your first line, then a line each from the template", #ol == 4 and ol[1] == "When;Who;What;How;Raid", own)
check("with every field filled in, and anything else left as it is", ol[2]:find(";Ann;Royal Cloak of Arathi Kings %(28525%);MS 77;Karazhan by Lead {nope}$") ~= nil
  or ol[2]:find(";Ann;.- %(28525%);MS 77;Karazhan by Lead {nope}$") ~= nil, ol[2])
check("no first line when there isn't one", not LR.Export.text(s5, "own", { template = "{player}" }):find("When", 1, true)
  and select(2, LR.Export.text(s5, "own", { template = "{player}" }):gsub("\n", "")) == 2)
-- several raids, between two dates
local s6 = S.new("Bob-Faerlina", "GruulsLair", 2, true, 1760100000)
S.award(s6, 28830, CARA, "MS", 90, 1760100500)
local s7 = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 1750000000)
S.award(s7, 28525, "Eve-Dreamscythe", "MS", 50, 1750000100)
local many = LR.Export.entriesOf({ s6, s5, s7 }, 1755000000, nil)
check("several raids: only between the dates, oldest first", #many == 4 and many[1].w.p == ANN and many[4].w.p == CARA)
local manyText = LR.Export.write(many, "own", { template = "{raid};{player}" })
check("each line says which raid", manyText:find("Karazhan;Ann", 1, true) and manyText:find("Gruul's Lair;Cara", 1, true) and not manyText:find("Eve", 1, true), manyText)
check("thatsmybis ids stay apart for each raid", LR.Export.write(many, "tmb"):find(",%s*" .. s6.id .. ":1") ~= nil or LR.Export.write(many, "tmb"):find(s6.id .. ":1", 1, true) ~= nil)
check("up to a date too", #LR.Export.entriesOf({ s6, s5, s7 }, nil, 1760000150) == 3)

print("== the guild book")
local B = LR.Book
local book = B.new("Night Watch")
check("a new book: nobody has points, officers edit, boosted rolls off", B.points(book, ANN) == 0 and book.editRank == 1 and not book.boost.on)
local c = B.setPoints(book, "Ann", 30, 10)
check("setting points gives the change to send", B.points(book, ANN) == 30 and c.points[ANN].n == 30 and c.points[ANN].t == 10)
check("setting the same points again sends nothing", B.setPoints(book, ANN, 30, 11) == nil)
check("points stay between 0 and the most", B.setPoints(book, DAN, 5000, 12) and B.points(book, DAN) == B.MAX_POINTS
  and B.setPoints(book, DAN, -4, 13) and B.points(book, DAN) == 0)
B.setBoost(book, true, 15, 14)
c = B.raidAttended(book, { ANN, "Bob-Faerlina" }, 20)
check("a raid gives everyone in it the points for a raid", B.points(book, ANN) == 45 and B.points(book, BOB) == 15 and c.points[BOB].n == 15)
check("a boosted roll's range", select(1, B.boostRange(45)) == 46 and select(2, B.boostRange(45)) == 145)
check("points for each raid are kept sane", B.setBoost(book, true, 999, 21).boost.perRaid == 100 and B.setBoost(book, true, 15, 22).boost.perRaid == 15)

-- another officer's copy: merging goes entry by entry, newest first
local other = B.new("Night Watch")
B.setPoints(other, ANN, 5, 30)       -- newer than ours (spent on a win)
B.setPoints(other, BOB, 90, 1)       -- older than ours
check("a change has the right shape", B.valid(c) and B.valid(other))
check("merging takes what's newer", B.merge(book, other) and B.points(book, ANN) == 5 and B.points(book, BOB) == 15)
check("merging the same again changes nothing", not B.merge(book, other))
B.setPoints(other, ANN, 0, 40)
check("points taken away spread too", B.merge(book, { points = { [ANN] = other.points[ANN] } }) and B.points(book, ANN) == 0)
check("only the guild master changes who may edit", not B.merge(book, { editRank = 4, et = 50 }) and book.editRank == 1
  and B.merge(book, { editRank = 2, et = 50 }, true) and book.editRank == 2)
check("an older change of who may edit doesn't count", not B.merge(book, { editRank = 0, et = 49 }, true) and book.editRank == 2)
check("boosted rolls switched off spreads", B.merge(book, { boost = { on = false, perRaid = 10, t = 60 } }) and not book.boost.on)
check("nonsense isn't a change", not B.valid("x") and not B.valid({ points = { [ANN] = { n = "many", t = 1 } } })
  and not B.valid({ prio = { ["x"] = { list = {}, t = 1 } } }) and not B.valid({ boost = { on = true } })
  and not B.valid({ editRank = 1 }))
local huge = { points = {} }
for i = 1, 2001 do huge.points["P" .. i] = { n = 1, t = 1 } end
check("a change can't be endless", not B.valid(huge))
check("a whole saved book is checked", B.validBook(book) and not B.validBook({ guild = "x" }) and not B.validBook(nil))

print("== priority lists (in the guild book)")
c = B.setPrio(book, WATCH, { { p = "Bob-Faerlina", n = 2 }, { p = ANN, n = 1, note = "tank set" }, { p = "Dan", n = 2 }, { p = ANN, n = 3 } }, 70)
local list = B.prio(book, WATCH)
check("a list, best first, each player once", #list == 3 and list[1].p == ANN and list[1].note == "tank set" and list[2].p == BOB and list[3].p == DAN)
local first, n1 = B.first(book, WATCH, { BOB, DAN })
check("whose turn: the best who are here (ties together)", #first == 2 and first[1] == BOB and first[2] == DAN and n1 == 2)
check("nobody on the list here: a free roll", #B.first(book, WATCH, { CARA }) == 0)
check("someone who gets the item comes off its list", B.received(book, WATCH, BOB, 71) and #B.prio(book, WATCH) == 2
  and B.received(book, WATCH, CARA, 72) == nil)
check("everything a player has priority on", #B.prioOf(book, ANN) == 1 and B.prioOf(book, ANN)[1][1] == WATCH)

print("== alts (sharing their main's points)")
local ab = B.new("Night Watch")
B.setPoints(ab, ANN, 40, 1)
B.setPoints(ab, "Annalt", 7, 2)
local link = B.setAlt(ab, "Annalt", "Ann", 3)
check("an alt uses its main's points", link and link.alts["Annalt-Dreamscythe"].m == ANN and B.points(ab, "Annalt") == 40 and B.mainOf(ab, "annalt") == ANN)
check("spending them spends the main's", B.setPoints(ab, "Annalt", 0, 4) and B.points(ab, ANN) == 0 and B.ownPoints(ab, "Annalt") == 7)
B.setPoints(ab, ANN, 20, 5)
B.raidAttended(ab, { ANN, "Annalt", DAN }, 6)
check("a main and their alt in the same raid get its points once", B.points(ab, ANN) == 30 and B.points(ab, DAN) == 10)
check("not an alt of itself, or linked twice", B.setAlt(ab, ANN, "Ann", 7) == nil and B.setAlt(ab, "Annalt", ANN, 7) == nil)
B.setAlt(ab, "Annbank", "Annalt", 8)
check("an alt's alt goes to the main", B.mainOf(ab, "Annbank") == ANN and #B.altsOf(ab, ANN) == 2)
B.setAlt(ab, ANN, DAN, 9)
check("a main made someone's alt takes its alts along", B.mainOf(ab, "Annalt") == DAN and B.mainOf(ab, "Annbank") == DAN and B.mainOf(ab, ANN) == DAN)
check("unlinking: its own points again", B.unlinkAlt(ab, "Annalt", 10) and B.points(ab, "Annalt") == 7 and B.unlinkAlt(ab, "Annalt", 11) == nil)
local other = B.new("Night Watch")
check("links spread like everything else", B.merge(other, { alts = ab.alts }) and B.mainOf(other, ANN) == DAN and B.mainOf(other, "Annalt") == "Annalt-Dreamscythe")
check("and the newest wins", not B.merge(other, { alts = { [ANN] = { m = "", t = 1 } } }) and B.mainOf(other, ANN) == DAN)
check("never an alt of itself, even from someone else", B.merge(other, { alts = { [CARA] = { m = CARA, t = 50 } } }) and B.mainOf(other, CARA) == CARA)
check("nonsense isn't a link", not B.valid({ alts = { [ANN] = { m = 5, t = 1 } } }) and not B.valid({ alts = "x" }) and B.valid({ alts = ab.alts }))
check("a saved book with links is fine", B.validBook(ab))

print("== priority lists in and out")
local P = LR.Prio
local lists, kind = P.parse("28525,ann,bob|cara,dan\n28530,Bob-Faerlina[1],Ann[3]\n\nnot a line")
check("Gargul's CSV, in order, with a shared place", kind == "Gargul's CSV" and #lists[28525] == 4 and lists[28525][1].p == "Ann" and lists[28525][1].n == 1
  and lists[28525][2].n == 2 and lists[28525][3].p == "Cara" and lists[28525][3].n == 2 and lists[28525][4].n == 3)
check("and numbered, with realms", lists[28530][1].p == "Bob-Faerlina" and lists[28530][2].n == 3)
lists, kind = P.parse('"28525^Signet of Unshakable Faith\n1|cffc41e3aAnn|r: :1|\n2|cff3fc7ebBob|r: :2|;28530^Brooch\nFree Roll\n;32386^Head\n1|cffffffffDan|r: :1|"')
check("DFT's export (Free Roll items left out)", kind == "DFT" and lists[28525] and lists[28525][1].p == "Ann" and lists[28525][2].n == 2 and not lists[28530]
  and lists[32386][1].p == "Dan", kind)
local tmbJSON = '{"wishlists":{"28525":["ann|1|1|0","bob|2|1|0","cara|1|2|0"],"28530":["dan|1|2|0"]}}'
lists, kind = P.parse(tmbJSON)
check("thatsmybis: its priorities, not its wishlists", kind == "thatsmybis" and #lists[28525] == 2 and lists[28525][2].p == "Bob" and not lists[28530])
lists = P.parse('{"wishlists":{"28530":["dan|1|2|0"]}}')
check("only wishlists: those", lists and lists[28530][1].p == "Dan")
lists = P.parse(U.b64encode("packed:" .. tmbJSON), function(raw) return raw:match("^packed:(.*)$") end)
check("thatsmybis compressed", lists and #lists[28525] == 2)
local none, why = P.parse("hello there")
check("anything else isn't a list", none == nil and why:find("isn't a priority list", 1, true) ~= nil)
check("an empty paste", P.parse("  ") == nil and P.parse("28525,") == nil)
check("names that can't be names are left out", (P.parse("28525,ann bob,|cff00ff00Cara|r,,x[y]") or {})[28525] and #P.parse("28525,ann bob,|cff00ff00Cara|r,,x[y]")[28525] == 1)
local pbook = B.new("Night Watch")
B.setPrio(pbook, 99999, { { p = ANN, n = 1 } }, 1)
local change = P.apply(pbook, P.parse("28525,ann,bob|cara"), 5, true)
check("bringing lists in replaces them, and clears others when asked", #B.prio(pbook, 28525) == 3 and #B.prio(pbook, 99999) == 0
  and change.prio[99999] and change.prio[28525] and B.valid(change))
check("names get this realm", B.prio(pbook, 28525)[1].p == ANN)
local out = P.export(pbook, "gargul")
check("out as Gargul's CSV", out == "28525,Ann[1],Bob[2],Cara[2]", out)
check("which reads back the same", #P.parse(out)[28525] == 3 and P.parse(out)[28525][3].n == 2)
out = P.export(pbook, "sheet", function() return "Signet, of Faith" end)
check("out for a spreadsheet", out:find("^Item ID,Item,Player,Priority,Note\n28525,\"Signet, of Faith\",Ann,1,") ~= nil, out)
check("places", P.place(1) == "1st" and P.place(2) == "2nd" and P.place(3) == "3rd" and P.place(4) == "4th" and P.place(11) == "11th" and P.place(22) == "22nd")

print("== Gargul's +1s and boosted roll points")
local counts = P.parseCounts('Ann,3\n"Bob-Faerlina",12,Bobalt,Bobalt2\ncara\t5\nDan 7\nnot a line\nAnn,9\nEve,-4')
check("Gargul's lines (and a spreadsheet's)", #counts == 4 and counts[1].p == "Ann" and counts[1].n == 3 and counts[2].p == "Bob-Faerlina"
  and counts[2].n == 12 and counts[3].p == "Cara" and counts[4].n == 7 and #counts[1].alts == 0)
check("with the alts after the number", #counts[2].alts == 2 and counts[2].alts[1] == "Bobalt" and counts[2].alts[2] == "Bobalt2")
check("nothing useful in it", P.parseCounts("hello") == nil and P.parseCounts("") == nil)
check("a limit", #P.parseCounts("Ann,500\nBob,5", 99) == 1)
check("written back out the same way", P.countsText({ { p = BOB, n = 12, alts = { "Bobalt-Dreamscythe" } }, { p = ANN, n = 3 } }) == "Ann,3\nBob,12,Bobalt")
local ps2 = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 800)
S.award(ps2, 28525, ANN, "MS", 50, 801)
check("setting +1s keeps what they won on top", S.setPlusOnes(ps2, ANN, 3, 802) and S.plusOnes(ps2, ANN) == 3
  and S.setPlusOnes(ps2, ANN, 0, 803) and S.plusOnes(ps2, ANN) == 0 and S.setPlusOnes(ps2, BOB, 2, 804) and S.plusOnes(ps2, BOB) == 2)
check("a sane number only", not S.setPlusOnes(ps2, BOB, -1, 805) and not S.setPlusOnes(ps2, BOB, 1.5, 805) and S.valid(ps2))

print("== a priority roll")
roll = R.new("k12", 28525, { mode = "PR", who = { BOB, DAN }, n = 2 })
check("only the players who share the top place roll", table.concat(R.options(roll, BOB), ",") == "MS" and #R.options(roll, ANN) == 0
  and select(2, R.canRoll(roll, ANN)) == "notFirst")
R.add(roll, ANN, 99, 1, 100)
R.add(roll, BOB, 40, 1, 100)
good, bad = R.standings(roll)
check("anyone else's roll doesn't count", #good == 1 and good[1].p == BOB and bad[1].why == "notFirst")
check("who still has to roll", #R.waiting(roll) == 1 and R.waiting(roll)[1] == DAN)

print("== boosted rolls")
local plan = R.plan(nil, 28525, roster)
plan.bp = { [ANN:lower()] = 30, ["dan-dreamscythe"] = 5 }
roll = R.new("k9", 28525, plan)
check("someone with points may roll boosted", table.concat(R.options(roll, ANN), ",") == "MS,BR,OS")
check("someone without points can't", table.concat(R.options(roll, BOB), ",") == "MS,OS" and R.boostRange(roll, BOB) == nil)
R.add(roll, ANN, 120, 31, 130)
R.add(roll, BOB, 99, 1, 100)
R.add(roll, DAN, 12, 6, 105)
R.add(roll, CARA, 140, 31, 130)
good, bad = R.standings(roll)
check("a boosted roll counts as boosted, ranked with main spec by its number", good[1].p == ANN and good[1].kind == "BR" and good[2].p == BOB and good[3].kind == "BR")
check("someone else's range doesn't count", bad[1].p == CARA and bad[1].why == "range")
check("a boosted roll's label", R.label(roll, good[1]) == "BR")
top, tied = R.result(roll)
check("the highest number wins", top.p == ANN and not tied)
roll = R.new("k10", 28525, plan)
R.add(roll, ANN, 100, 31, 130)
R.add(roll, BOB, 100, 1, 100)
top, tied = R.result(roll)
check("a boosted and a main spec roll can tie", tied and #tied == 2)
plan.po = { [ANN:lower()] = 1 }
roll = R.new("k11", 28525, plan)
R.add(roll, ANN, 125, 31, 130)
R.add(roll, BOB, 20, 1, 100)
good = R.standings(roll)
check("with the +1 rule, a +1 still rolls after those without, boosted or not", good[1].p == BOB and good[2].p == ANN and R.label(roll, good[2]) == "BR +1")
check("a boosted win is a main spec win (a +1), marked as boosted", S.award(s5, 28525, CARA, "MS", 110, 1760000300, nil, nil, true)
  and s5.won[#s5.won].br == true and S.valid(s5))

print("== an auction (GDKP)")
roll = R.new("k20", 28525, { mode = "BID", min = 100, inc = 10 })
check("everyone may bid, nobody rolls", table.concat(R.options(roll, CARA), ",") == "BID" and R.add(roll, ANN, 50, 1, 100).kind == nil)
check("the first bid is at least the start", R.nextBid(roll) == 100 and R.bid(roll, ANN, 90).why == "low" and R.bid(roll, ANN, 100).kind == "BID")
check("each bid at least the raise more", R.nextBid(roll) == 110 and R.bid(roll, BOB, 105).why == "low" and R.bid(roll, BOB, 150).kind == "BID")
local again = R.bid(roll, ANN, 200)
good, bad = R.standings(roll)
check("raising your own bid: the old one stops counting", again.kind == "BID" and #good == 2 and good[1].p == ANN and good[1].n == 200 and good[2].n == 150)
check("the bids that didn't count are listed why", #bad == 4 and bad[1].why == "auction" and bad[2].why == "low" and bad[3].why == "raised" and bad[4].why == "low")
top = R.result(roll)
check("the highest bid wins", top.p == ANN and top.n == 200 and R.topBid(roll).n == 200 and R.label(roll, top) == "bid")
check("a bid after it closed doesn't count", R.bid(roll, DAN, 500, true).why == "late" and R.topBid(roll).n == 200)
check("what counts as a bid in chat", R.parseBid("150") == 150 and R.parseBid(" 150g ") == 150 and R.parseBid("150 gold") == 150
  and R.parseBid("bid 200") == 200 and R.parseBid("1.5k") == 1500 and R.parseBid("2k") == 2000 and R.parseBid("1,250") == 1250)
check("with bids that must start with \"bid\", only those count", R.parseBid("bid 150", true) == 150 and R.parseBid("BID 2k", true) == 2000
  and R.parseBid("150", true) == nil and R.parseBid("500 dps lol", true) == nil)
check("and what doesn't", R.parseBid("gg") == nil and R.parseBid("150 for sure") == nil and R.parseBid("0") == nil
  and R.parseBid("lol 5") == nil and R.parseBid("99999999") == nil)

print("== max bids (GDKP)")
roll = R.new("k21", 28525, { mode = "BID", min = 100, inc = 25 })
local maxes = { [ANN:lower()] = { p = ANN, g = 800, at = 1 } }
local made = R.resolve(roll, maxes)
check("a max bid opens at the lowest bid", #made == 1 and roll.top.p == ANN and roll.top.n == 100 and made[1].auto)
R.bid(roll, BOB, 300)
R.resolve(roll, maxes)
check("someone bids: the max bids just above them", roll.top.p == ANN and roll.top.n == 325)
maxes[DAN:lower()] = { p = DAN, g = 1000, at = 2 }
R.resolve(roll, maxes)
check("a higher max beats it, just above the other max", roll.top.p == DAN and roll.top.n == 825)
R.bid(roll, BOB, 900)
R.resolve(roll, maxes)
check("a bid under the max: the max answers", roll.top.p == DAN and roll.top.n == 925)
R.bid(roll, BOB, 1000)
check("a bid over every max wins", #R.resolve(roll, maxes) == 0 and roll.top.p == BOB and roll.top.n == 1000)
roll = R.new("k22", 28525, { mode = "BID", min = 100, inc = 25 })
maxes = { [ANN:lower()] = { p = ANN, g = 500, at = 1 } }
R.resolve(roll, maxes)
maxes[DAN:lower()] = { p = DAN, g = 500, at = 2 }
R.resolve(roll, maxes)
check("equal maxes: whoever set theirs first wins, at that price", roll.top.p == ANN and roll.top.n == 500)
check("nothing to do without maxes, or in a roll", #R.resolve(roll, {}) == 0 and #R.resolve(R.new("k23", 1, { mode = "OPEN" }), maxes) == 0)

print("== the pot (GDKP)")
local Gd = LR.Gdkp
local gs = S.new("Lead-Dreamscythe", "Karazhan", 2, false, 500)
S.add(gs, ANN, "PRIEST", 28525, false, 501)
check("GDKP on: reserves stop counting, nobody can reserve", Gd.set(gs, true, 502) and gs.gdkp and not S.add(gs, BOB, "MAGE", 28530, false, 503)
  and select(2, S.add(gs, BOB, "MAGE", 28530, false, 503)) == "GDKP" and gs.gk.min == 100 and S.valid(gs))
check("its settings", Gd.option(gs, "cut", 20, 504) and Gd.option(gs, "cut", 10, 504) and Gd.option(gs, "inc", 25, 505) and gs.gk.inc == 25 and not Gd.option(gs, "cut", 150, 506)
  and not Gd.option(gs, "nonsense", 5, 506))
check("an item can start higher", Gd.setPrice(gs, 32386, 1000, 507) and Gd.minFor(gs, 32386) == 1000 and Gd.minFor(gs, 28525) == 100)
do
  local prices, bad = Gd.parsePrices("28525: 500\n28530,1,250g\n|cffa335ee|Hitem:28830::::::::70:::::|h[Dragonspine Trophy]|h|r 2000\nwhat\n28531: lots")
  check("starting bids from text: numbers or links, with commas and a g", prices[28525] == 500 and prices[28530] == 1250 and prices[28830] == 2000 and bad == 2)
  local ps = S.new("Lead-Dreamscythe", "Karazhan", 2, false, 500)
  Gd.set(ps, true, 501)
  check("brought in: how many changed", Gd.setPrices(ps, prices, 502) == 3 and Gd.setPrices(ps, prices, 503) == 0 and Gd.minFor(ps, 28530) == 1250)
  check("and written out by item number", Gd.pricesText(ps) == "28525: 500\n28530: 1250\n28830: 2000")
  S.award(ps, 28525, ANN, "BID", 700, 504)
  check("a sale's price can change", Gd.setSalePrice(ps, 1, 650, 505) and Gd.pot(ps) == 650 and not Gd.setSalePrice(ps, 1, 650, 506))
  check("but not to nonsense, nor on something that wasn't sold", not Gd.setSalePrice(ps, 1, -5, 507) and not Gd.setSalePrice(ps, 2, 5, 507))
end
check("everyone in the group gets a share", Gd.saw(gs, { "Lead-Dreamscythe", ANN, BOB, DAN }, 508) and not Gd.saw(gs, { ANN }, 509))
S.award(gs, 28525, ANN, "BID", 1000, 510)
S.award(gs, 28530, BOB, "BID", 600, 511)
S.award(gs, 28528, CARA, "BID", 400, 512)        -- Cara bought something, then left
S.award(gs, 28507, DAN, "OS", nil, 513, nil, true) -- disenchanted: not a sale
local sp = Gd.split(gs)
check("the pot is what was sold", Gd.pot(gs) == 2000 and #Gd.sales(gs) == 3 and sp.pot == 2000)
check("the cut, then an even split between everyone (Cara bought, so she's in)", sp.cut == 200 and #sp.players == 5 and sp.share == 360)
check("who owes and who's owed", sp.rows[ANN].owed == -640 and sp.rows[BOB].owed == -240 and sp.rows[DAN].owed == 360 and sp.rows[CARA].owed == -40)
Gd.setBonus(gs, DAN, 100, 514)
Gd.setOut(gs, CARA, true, 515)
sp = Gd.split(gs)
check("a bonus comes out of the pot first; someone left out gets no share", sp.bonuses == 100 and #sp.players == 4 and sp.share == 425
  and sp.rows[DAN].gets == 525 and sp.rows[CARA].gets == 0 and sp.rows[CARA].owed == -400)
Gd.paid(gs, ANN, 575, 516)
Gd.paid(gs, DAN, -525, 517)
sp = Gd.split(gs)
local rs = S.new("Lead-Dreamscythe", "Karazhan", 2, false, 700)
Gd.set(rs, true, 701)
Gd.saw(rs, { "Lead-Dreamscythe", ANN, BOB, DAN }, 702)
S.award(rs, 28525, BOB, "BID", 1000, 703)
check("tanks and healers get their role's cut", Gd.setRoleCut(rs, "tank", 3, 704) and Gd.setRoleCut(rs, "healer", 2, 705)
  and Gd.setRole(rs, ANN, "healer", 706) and Gd.setRole(rs, DAN, "tank", 707) and not Gd.setRole(rs, DAN, "dps", 707) and not Gd.setRoleCut(rs, "tank", 50, 707))
local rsp = Gd.split(rs)
check("out of the pot, before the even split", rsp.cut == 100 and rsp.roles == 50 and rsp.share == 212 and rsp.rows[DAN].roleCut == 30
  and rsp.rows[DAN].gets == 242 and rsp.rows[ANN].gets == 232 and rsp.rows[ANN].role == "healer")
check("taking someone out of a role", Gd.setRole(rs, DAN, nil, 708) and Gd.split(rs).rows[DAN].roleCut == 0 and Gd.valid(rs.gk) and S.valid(rs))
rs.gk.role[ANN] = 5
check("nonsense roles aren't valid", not Gd.valid(rs.gk))
rs.gk.role[ANN] = "healer"
-- the organiser's own pot rules
local LEAD = "Lead-Dreamscythe"
local ri = Gd.addRule(rs, "|cffff0000Raid leader|r", 709)
check("a rule of my own, named (no colours)", ri == 1 and rs.gk.rules[1].n == "Raid leader" and #rs.gk.rules[1].to == 0)
check("a percent of the pot, for the players picked", Gd.editRule(rs, ri, { pct = 5 }, 710) and Gd.ruleTo(rs, ri, LEAD, true, 711)
  and not Gd.ruleTo(rs, ri, LEAD, true, 711) and Gd.ruleText(rs.gk.rules[1]) == "5% of the pot each")
local rr = Gd.split(rs)
-- 1,000g: 100g to the organiser, 20g healer cut, 50g raid leader rule, 830g split four ways
check("paid out of the pot after the cuts, before the even split", rr.rules == 50 and rr.ruleTotals[1] == 50 and rr.share == 207
  and rr.rows[LEAD].ruleCut == 50 and rr.rows[LEAD].gets == 257 and rr.rows[LEAD].ruleNames[1] == "Raid leader" and rr.rows[BOB].ruleCut == 0)
local r2 = Gd.addRule(rs, "Pumper", 712)
check("gold each, for several players", Gd.editRule(rs, r2, { g = 200 }, 713) and Gd.ruleTo(rs, r2, BOB, true, 714) and Gd.ruleTo(rs, r2, DAN, true, 715)
  and Gd.split(rs).rules == 450 and Gd.split(rs).share == 107 and Gd.split(rs).rows[DAN].ruleCut == 200)
Gd.editRule(rs, r2, { g = 500 }, 716)
rr = Gd.split(rs)
check("never more than is left: made smaller to fit", rr.rules <= 880 and rr.rules > 870 and rr.share >= 0 and rr.rows[BOB].ruleCut < 500
  and rr.rows[LEAD].ruleCut < 50, rr.rules)
check("nonsense isn't taken", not Gd.editRule(rs, r2, { pct = 99 }, 717) and not Gd.editRule(rs, r2, { g = -5 }, 717) and not Gd.editRule(rs, 9, { pct = 1 }, 717))
check("someone left out gets nothing from a rule", Gd.setOut(rs, BOB, true, 718) and Gd.split(rs).rows[BOB].ruleCut == 0)
Gd.setOut(rs, BOB, false, 719)
check("a session with rules is valid", Gd.valid(rs.gk) and S.valid(rs))
check("taking a rule away", Gd.removeRule(rs, r2, 720) and #rs.gk.rules == 1 and Gd.split(rs).rules == 50)
check("no more than ten", (function()
  for i = 2, 10 do Gd.addRule(rs, "R" .. i, 721) end
  return #rs.gk.rules == 10 and Gd.addRule(rs, "Eleven", 722) == nil
end)())
rs.gk.rules[2].to = { 5 }
check("rules with nonsense in them aren't valid", not Gd.valid(rs.gk))
rs.gk.rules[2].to = {}
rs.gk.rules[3].pct = "lots"
check("nor a percent that isn't a number", not Gd.valid(rs.gk))
rs.gk.rules = nil
check("a session without rules (an older version's) is fine", Gd.valid(rs.gk) and Gd.split(rs).rules == 0)
-- bookkeeping: gold by hand, the ledger, payouts set by hand, the payouts as text
check("before: 1,000g, 100g cut, 20g healer cut, 880g four ways", Gd.split(rs).share == 220)
check("gold put in by hand goes in the pot", Gd.addGold(rs, 200, "|cffffffffvendor|r greys", 725) and Gd.pot(rs) == 1200 and Gd.split(rs).share == 264
  and rs.gk.adds[1].n == "vendor greys" and Gd.split(rs).added == 200)
check("and taken out", Gd.addGold(rs, -50, "repairs", 726) and Gd.pot(rs) == 1150 and Gd.added(rs) == 150)
check("nothing, or nonsense, isn't", not Gd.addGold(rs, 0, "x", 727) and not Gd.addGold(rs, "lots", "x", 727))
check("taking one back", Gd.removeAdd(rs, 2, 728) and Gd.pot(rs) == 1200 and not Gd.removeAdd(rs, 5, 728))
check("payments are logged, with how", Gd.paid(rs, BOB, 1000, 730, "trade") and Gd.paid(rs, DAN, -264, 731, "mail") and Gd.paid(rs, ANN, -10, 732)
  and #rs.gk.log == 3 and rs.gk.log[1].w == "trade" and rs.gk.log[2].w == "mail" and rs.gk.log[3].w == "hand")
local led = Gd.ledger(rs)
check("the ledger: the sale, the gold, the payments, oldest first", #led == 5 and led[1].kind == "sale" and led[1].p == BOB and led[1].g == 1000
  and led[2].kind == "add" and led[2].g == 200 and led[3].kind == "trade" and led[4].kind == "mail" and led[5].kind == "hand")
check("a payout set by hand: all they get; the rest is split between the others", Gd.setFixed(rs, DAN, 500, 740)
  and Gd.split(rs).rows[DAN].gets == 500 and Gd.split(rs).rows[DAN].fixed and Gd.split(rs).share == 185 and Gd.split(rs).sharers == 3)
Gd.setFixed(rs, BOB, 900, 741)
local fx = Gd.split(rs)
check("never more than is left: made smaller to fit", fx.fixed <= 1056 and fx.fixed > 1050 and fx.rows[BOB].gets < 900 and fx.share >= 0, fx.fixed)
check("back to a share", Gd.setFixed(rs, BOB, nil, 742) and not Gd.split(rs).rows[BOB].fixed)
check("brought in from lines, replacing the ones before", Gd.setFixedAll(rs, LR.Prio.parseCounts("Ann,300\nLead,100", 10000000), 743) == 2
  and Gd.split(rs).rows[ANN].gets == 300 and not Gd.split(rs).rows[DAN].fixed and Gd.split(rs).sharers == 2)
local cuts = Gd.payoutsText(rs, "cuts")
check("the payouts as Name,Gold lines", cuts:find("Ann,300", 1, true) and cuts:find("Lead,100", 1, true) and cuts:find("Bob-Faerlina,", 1, true))
check("and for a spreadsheet", Gd.payoutsText(rs, "sheet"):find("^Name,Bought,Payout,Paid,Owed\nAnn,0,300,%-10,") ~= nil, Gd.payoutsText(rs, "sheet"))
check("Name,Gold lines come back in the same", (function()
  local before = Gd.split(rs)
  Gd.setFixedAll(rs, LR.Prio.parseCounts(cuts, 10000000), 744)
  local after = Gd.split(rs)
  return after.rows[ANN].gets == before.rows[ANN].gets and after.rows[BOB].gets == before.rows[BOB].gets
end)())
check("it's all valid", Gd.valid(rs.gk) and S.valid(rs))
rs.gk.adds[1].g = "lots"
check("gold by hand with nonsense isn't", not Gd.valid(rs.gk))
rs.gk.adds[1].g = 200
rs.gk.log[1].p = 7
check("nor a log", not Gd.valid(rs.gk))
rs.gk.log[1].p = BOB
rs.gk.fixed[ANN] = "x"
check("nor payouts set by hand", not Gd.valid(rs.gk))
rs.gk.fixed = nil
check("gold handed over counts", sp.rows[ANN].owed == 0 and sp.rows[DAN].owed == 0 and sp.rows[BOB].owed == -175)
check("it's all a valid session", S.valid(gs) and Gd.valid(gs.gk))
local owing = Gd.unsettled(gs)
check("who still owes or is owed, biggest first (not the organiser)", #owing == 2 and owing[1][1] == CARA and owing[1][2] == -400 and owing[2][1] == BOB)
Gd.paid(gs, CARA, 400, 520) Gd.paid(gs, BOB, 175, 521)
check("nobody, once it's all paid", #Gd.unsettled(gs) == 0)
check("nonsense in it isn't", not Gd.valid({ min = 1, inc = 1, cut = 1, bonus = { [ANN] = "lots" }, seen = {}, out = {}, paid = {}, prices = {} })
  and not Gd.valid({ min = "x" }) and not Gd.valid(5))
check("gold for people", Gd.gold(1250) == "1,250g" and Gd.gold(12.5) == "12g 50s" and Gd.gold(-40) == "-40g" and Gd.gold(0) == "0g" and Gd.gold(1234567) == "1,234,567g")
check("GDKP off and on again keeps its settings", Gd.set(gs, false, 518) and not gs.gdkp and Gd.set(gs, true, 519) and gs.gk.inc == 25)

print("== reading roll messages")
local parse = R.parser("%s rolls %d (%d-%d)")
local name, n, lo, hi = parse("Bob-Faerlina rolls 57 (1-100)")
check("English", name == "Bob-Faerlina" and n == 57 and lo == 1 and hi == 100)
check("other lines aren't rolls", parse("Bob has come online.") == nil and parse("Bob rolls 57 (1-100) and more") == nil)
local de = R.parser("%1$s würfelt. Ergebnis: %2$d (%3$d-%4$d)")
name, n, lo, hi = de("Bob würfelt. Ergebnis: 3 (1-99)")
check("a translation with numbered places", name == "Bob" and n == 3 and hi == 99)
check("names for chat", R.names({ { ANN, 2 }, { BOB, 1 }, { DAN, 1 } }, 2) == "Ann x2, Bob-Faerlina, +1")

print("== names with letters beyond A-Z")
do
  local ns = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 100)
  S.set(ns, "ØYVIND-Dreamscythe", "WARRIOR", { WATCH }, false, 101)      -- (typed in capitals somewhere)
  S.set(ns, "Ghost-Dreamscythe", "MAGE", { BROOCH }, false, 102)
  local here = { { name = "Øyvind-Dreamscythe" }, { name = "Ghøst-Dreamscythe" } }
  local pl = R.plan(ns, WATCH, here)
  check("a reserve counts for the character, whatever the capitals", pl.mode == "SR" and #pl.who == 1 and #pl.away == 0)
  local roll = R.new("k", WATCH, pl)
  check("and they may roll", R.canRoll(roll, "Øyvind-Dreamscythe"))
  -- Ghost and Ghøst are two characters: rolling never guesses (an import puts the reserve under the right name)
  local gp = R.plan(ns, BROOCH, here)
  check("an accent apart is someone else: they're away, everyone rolls", gp.mode == "OPEN" and gp.away[1] == "Ghost-Dreamscythe")
  check("so Ghøst can't roll on Ghost's reserve", not R.canRoll(R.new("k2", BROOCH, { mode = "SR", who = { { "Ghost-Dreamscythe", 1 } } }), "Ghøst-Dreamscythe"))
end

print("== the loot master's own roll types")
do
  check("checked: names cleaned, bad tops and repeats dropped, four at most", (function()
    local k = R.checkKinds({ { n = " Transmog|r ", hi = 98 }, { n = "Bad", hi = 99 }, { n = "Dup", hi = 98 }, { n = "", hi = 50 },
      { n = "Alt", hi = 97 }, { n = "Half", hi = 50.5 }, "junk", { n = "Pvp", hi = 96 }, { n = "Fun", hi = 95 }, { n = "Fifth", hi = 94 } })
    return #k == 4 and k[1].n == "Transmogr" and k[1].hi == 98 and k[2].n == "Alt" and k[4].n == "Fun"
  end)())
  check("nothing sensible: none", R.checkKinds({ { n = "x", hi = 100 } }) == nil and R.checkKinds("x") == nil)
  local list, why = R.addKind({}, "Transmog", 98)
  check("adding one", list and #list == 1 and list[1].n == "Transmog")
  list = R.addKind(list, "Alt", 97)
  check("and another", list and #list == 2)
  check("a number that's taken is refused", select(2, R.addKind(list, "Pvp", 98)) == "/roll 98 is Transmog already.")
  check("so is a name that's taken", select(2, R.addKind(list, "alt", 50)) == "There's one called Alt already.")
  check("and 99 or 100", R.addKind(list, "Pvp", 99) == nil and R.addKind(list, "Pvp", 100) == nil and R.addKind(list, "Pvp", 1) == nil)
  check("and no name", select(2, R.addKind(list, "  ", 50)) == "Give it a name.")
  local roll = R.new("x", 28525, { mode = "OPEN", xk = list })
  local o = R.options(roll, ANN)
  check("a roll open to everyone offers them after off spec", o[1] == "MS" and o[2] == "OS" and o[3] == "X1" and o[4] == "X2")
  check("/roll 98 counts as Transmog", R.add(roll, ANN, 97, 1, 98).kind == "X1" and R.label(roll, roll.entries[1]) == "Transmog")
  check("/roll 97 as Alt", R.add(roll, BOB, 90, 1, 97).kind == "X2")
  check("another number doesn't count", R.add(roll, DAN, 50, 1, 96).why == "range")
  check("Transmog wins over Alt, whatever the numbers", R.result(roll).p == ANN)
  R.add(roll, CARA, 2, 1, 99)
  check("off spec wins over both", R.result(roll).p == CARA)
  R.add(roll, "Eve-Dreamscythe", 1, 1, 100)
  check("main spec over everything", R.result(roll).p == "Eve-Dreamscythe")
  local plain = R.new("y", 28525, { mode = "OPEN" })
  check("a roll without them: /roll 98 doesn't count", R.add(plain, ANN, 97, 1, 98).why == "range")
  local sr = R.new("z", WATCH, { mode = "SR", who = { { ANN, 1 } }, xk = list })
  check("a reserved item: only the reserve", #R.options(sr, ANN) == 1 and R.add(sr, ANN, 50, 1, 98).why == "range")
  local tie = R.new("t", 28525, { mode = "TIE", who = { ANN, BOB }, tie = "X1", xk = list })
  check("a tie on Transmog is rolled again as Transmog", R.add(tie, ANN, 40, 1, 98).kind == "X1" and R.add(tie, BOB, 30, 1, 100).why == "range")
  local tied = R.new("u", 28525, { mode = "OPEN", xk = list })
  R.add(tied, ANN, 60, 1, 98) R.add(tied, BOB, 60, 1, 98)
  local _, who = R.result(tied)
  check("two equal Transmog rolls tie", who and #who == 2)
  -- recorded as off spec, with its name, so older versions read it
  local ws = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 100)
  S.award(ws, 28525, ANN, "OS", 97, 200, nil, nil, nil, "Transmog")
  check("won on one: off spec, by its name", ws.won[1].k == "OS" and ws.won[1].xn == "Transmog" and S.valid(ws))
  ws.won[1].xn = { "x" }
  check("a name that isn't text is refused when loaded", not S.valid(ws))
end

print("== thatsmybis wishlists")
do
  local P = LR.Prio
  local wl = P.wishlists('{"wishlists":{"28525":["cara|2|2|0","ann|1|1|0","bob|1|2|0","dan|3|2|0"],"28530":["dan|1|1|0"]}}')
  check("a download's wishlists: type 2, in order, without its priorities", wl and #wl[28525] == 3 and wl[28525][1].p == "Bob" and wl[28525][2].p == "Cara" and not wl[28530])
  check("nothing pasted, or not a download, says so", select(2, P.wishlists("")) ~= nil and select(2, P.wishlists("hello")) ~= nil)
  check("one with no wishlists says so", select(2, P.wishlists('{"wishlists":{"28530":["dan|1|1|0"]}}')) == "That download has no wishlists in it.")
  local saved = P.checkWish({ [28525] = { { p = "Ann", n = 1 }, { p = "bad name|x", n = 2 }, { p = "Bob", n = -1 }, "junk" }, x = {}, [5] = "no" })
  check("saved wishlists are checked", #saved[28525] == 1 and saved[28525][1].p == "Ann" and not saved.x and not saved[5])
end

print("== item notes")
do
  local N = LR.Notes
  check("a note is made safe: no links or colours, one line, trimmed", N.clean("  |cffff0000Warrior|r >\nRogue  ") == "Warrior > Rogue"
  and N.clean("|cffa335ee|Hitem:1|h[Thing]|h|r first") == "[Thing] first")
  check("an empty one is none", N.clean("   ") == nil and N.clean(5) == nil)
  check("and short", #N.clean(string.rep("a", 300)) == N.MAX_LEN)
  local notes, bad = N.parse("28525: Warrior > Rogue\n28530,Tanks first\n|cffa335ee|Hitem:28830::::::::70:::::|h[Dragonspine Trophy]|h|r Hunters\nnonsense\n\n0: zero")
  check("read from text: a number, or a link, then the note", notes[28525] == "Warrior > Rogue" and notes[28530] == "Tanks first" and notes[28830] == "Hunters")
  check("lines that aren't notes are counted", bad == 2, bad)
  check("and written out by item number", N.text(notes) == "28525: Warrior > Rogue\n28530: Tanks first\n28830: Hunters")
  check("saved notes are checked", next(N.check({ ["x"] = "a", [5] = { }, [1.5] = "b", [7] = "ok" })) == 7)
end

print("== sorting a big roll")
do
  -- 300 rolls of every kind, with +1s: the order is the same as comparing everything each time (the old way)
  local big = { entries = {}, po = {}, xk = { { n = "Transmog", hi = 50 } } }
  local kinds = { "MS", "OS", "BR", "SR", "X1" }
  local seed = 11
  local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648 return seed % n end
  for i = 1, 300 do
    local name = "Player" .. string.char(65 + rnd(26)) .. string.char(97 + rnd(26)) .. "-Dreamscythe"
    if rnd(3) == 0 then big.po[R.key(name)] = rnd(3) end
    local kind = rnd(10) == 0 and nil or kinds[rnd(#kinds) + 1]
    big.entries[i] = { p = name, n = rnd(100) + 1, kind = kind, seq = i }
  end
  local function rankOf(kind) return select(3, R.kind(big, kind)) or 99 end
  local want = {}
  for _, e in ipairs(big.entries) do if e.kind then want[#want + 1] = e end end
  table.sort(want, function(a, b)
    local ra, rb = rankOf(a.kind), rankOf(b.kind)
    if ra ~= rb then return ra < rb end
    if ra == 2 then
      local pa, pb = R.plusOnes(big, a.p), R.plusOnes(big, b.p)
      if pa ~= pb then return pa < pb end
    end
    if a.n ~= b.n then return a.n > b.n end
    return a.seq < b.seq
  end)
  local good, bad = R.standings(big)
  local same = #good == #want
  for i = 1, #want do if good[i] ~= want[i] then same = false end end
  check("300 rolls of every kind, with +1s, come out in the same order", same and #good + #bad == 300)
end

print(("passed %d"):format(passed))
print(("errors %d"):format(failed))
os.exit(failed == 0 and 0 or 1)
