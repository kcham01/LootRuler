-- The session rules on their own (Core/Session.lua), plus the item lookups and Gargul strings.
--   lua5.1 tests/session.lua
package.path = "./tests/?.lua;" .. package.path
local failed, passed = 0, 0
local function check(name, ok, detail)
  if ok then passed = passed + 1 else failed = failed + 1 end
  if not ok then print("FAIL " .. name .. (detail and ("  " .. tostring(detail)) or "")) end
end

-- the files that don't need the game, in a plain environment
local LR = {}
local env = setmetatable({ bit = require("bit"), GetRealmName = function() return "Dreamscythe" end,
  GetNormalizedRealmName = function() return "Dreamscythe" end, RAID_CLASS_COLORS = {} }, { __index = _G })
for _, f in ipairs({ "Data/Loot.lua", "Core/Util.lua", "Core/Loot.lua", "Core/Session.lua", "Core/Lineup.lua" }) do
  local chunk = assert(loadfile("LootRuler/" .. f))
  setfenv(chunk, env)
  chunk("LootRuler", LR)
end
local U, S = LR.U, LR.Session

-- the loot data
check("every raid up to Zul'Aman", #LR.RAIDS == 16 and LR.raid("MoltenCore") and LR.raid("ZulAman") and not LR.raid("SunwellPlateau") and not LR.raid("Naxxramas"))
check("Hakkar's off-hand blade is Mandokir's", LR.raidHas("Zul'Gurub", 19866) and #LR.dropsFrom("Zul'Gurub", 19866) == 1 and LR.dropsFrom("Zul'Gurub", 19866)[1] == "Bloodlord Mandokir")
check("boss heads, one for each faction", LR.forFaction(18423, "Alliance") and not LR.forFaction(18423, "Horde") and LR.forFaction(18422, "Horde"))
check("cloth isn't for a paladin", LR.usableBy(28507, "PALADIN") and not LR.forClass(28507, "PALADIN") and LR.forClass(28518, "PALADIN"))
local kara = LR.raid("Karazhan")
check("Karazhan bosses in order", kara.bosses[1].name == "Attumen the Huntsman" and kara.bosses[#kara.bosses].name == "Trash")
check("Dragonspine Trophy drops from Gruul", LR.raidHas("GruulsLair", 28830) and U.indexOf(LR.dropsFrom("GruulsLair", 28830), "Gruul the Dragonkiller"))
check("no Badge of Justice", not LR.raidHas("ZulAman", 29434))
check("tier tokens are class items", not LR.usableBy(29760, "WARRIOR") and LR.usableBy(29761, "WARRIOR"),
  LR.ITEMS[29760][1] .. " / " .. LR.ITEMS[29761][1])
check("plate for plate wearers", LR.usableBy(28518, "PALADIN") and not LR.usableBy(28518, "MAGE"))
check("recipes for everyone", LR.usableBy(22559, "MAGE"))
check("Magtheridon's Head by faction", LR.forFaction(32385, "Alliance") and not LR.forFaction(32385, "Horde") and LR.forFaction(32386, "Horde"))
check("item kinds", LR.itemKind(28518) == "Plate Hands" and LR.itemKind(28830) == "Trinket", LR.itemKind(28518) .. ", " .. LR.itemKind(28830))
check("mounts and quest items say so", LR.itemKind(30480) == "Mount" and LR.itemKind(18423) == "Quest item", LR.itemKind(30480) .. ", " .. LR.itemKind(18423))
check("find by name", LR.findItem("GruulsLair", "dragonspine trophy") == 28830)
check("find by part of the name", LR.findItem("GruulsLair", "dragonspine") == 28830)
check("find by link", LR.findItem("GruulsLair", "|cffa335ee|Hitem:28830::::::::70:::::|h[Dragonspine Trophy]|h|r") == 28830)
local id, close, linked = LR.findItem("Karazhan", "|cffa335ee|Hitem:28830::::::::70:::::|h[Dragonspine Trophy]|h|r")
check("a link from another raid", id == nil and linked == 28830)
local _, many = LR.findItem("Karazhan", "bracers")
check("an unclear name lists the matches", #many > 1)
local g1, gl = LR.findItem("BlackTemple", "Warglaive of Azzinoth")
check("two items with one name ask which", g1 == nil and #gl == 2)
check("the other faction's head is skipped", LR.findItem("MagtheridonsLair", "magtheridon's head", "Horde") == 32386)

-- sessions
local s = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 1000)
check("new session", s.rev == 1 and s.sr == 2 and s.dupes and not s.locked and s.id == "Lead-Dreamscythe:1000")
local A, B = "Ann-Dreamscythe", "Bob-Faerlina"
check("reserve", S.add(s, A, "PRIEST", 28530) and #S.reservesOf(s, A) == 1 and s.rev == 2)
check("double up", S.add(s, A, "PRIEST", 28530) and #S.reservesOf(s, A) == 2)
local ok, why = S.add(s, A, "PRIEST", 28770)
check("no more than the limit", not ok and why == "TOO_MANY")
ok, why = S.add(s, A, "PRIEST", 28830)
check("only this raid's items", not ok and why == "NOT_IN_RAID")
check("take one back", S.remove(s, A, 28530) and #S.reservesOf(s, A) == 1)
ok, why = S.remove(s, A, 28770)
check("can't take back what isn't reserved", not ok and why == "NOT_RESERVED")
check("set a list", S.set(s, B, "MAGE", { 28770, 28762 }) and #S.reservesOf(s, B) == 2)
local rev = s.rev
check("setting the same list changes nothing", S.set(s, B, "MAGE", { 28770, 28762 }) and s.rev == rev)
ok, why = S.set(s, B, "MAGE", { 28770, 28762, 28530 })
check("lists over the limit are refused", not ok and why == "TOO_MANY")

-- hard reserves
local lost
ok, lost = S.setHR(s, 28770, "Lead", "for the tank")
check("hard reserve takes soft reserves away", ok and #lost == 1 and lost[1] == B and #S.reservesOf(s, B) == 1)
ok, why = S.add(s, A, "PRIEST", 28770)
check("hard reserved items can't be reserved", not ok and why == "HARD_RESERVED")
check("lift a hard reserve", S.clearHR(s, 28770) and S.add(s, A, "PRIEST", 28770))

-- options
S.set(s, A, "PRIEST", { 28530, 28530 })
local touched
ok, touched = S.configure(s, 2, false)
check("switching doubling off removes doubled picks", ok and #touched == 1 and #S.reservesOf(s, A) == 1)
ok, why = S.add(s, A, "PRIEST", 28530)
check("then the same item twice is refused", not ok and why == "DUPLICATE")
S.configure(s, 1, false)
check("fewer reserves trims lists", #S.reservesOf(s, B) == 1 and #S.reservesOf(s, A) == 1)
ok, why = S.configure(s, 0, true)
check("reserves each must be 1-10", not ok and why == "BAD_COUNT")
S.configure(s, 2, true)

-- locking
check("lock", S.setLocked(s, true) and s.locked)
ok, why = S.add(s, A, "PRIEST", 28762)
check("locked: raiders can't change", not ok and why == "LOCKED")
check("locked: the leader can", S.add(s, A, "PRIEST", 28762, true))
S.setLocked(s, false)

-- views
local by = S.byItem(s)
check("by item", by[28762] and #by[28762] == 2)
check("players", #S.players(s) == 2 and S.players(s)[1].name == A)
check("valid copy", S.valid(U.copy(s)))
local bad = U.copy(s) bad.sr = 99
check("a copy with nonsense is refused", not S.valid(bad))
local more = U.copy(s) more.sr = 12
check("a newer version allowing more reserves than this one offers is fine", S.valid(more))
local newKind = U.copy(s) newKind.won = { { i = 28528, p = A, k = "DE" } } newKind.somethingNew = { 1, 2 }
check("so are kinds of award and fields this version doesn't know", S.valid(newKind))
check("versions in order", U.compareVersions("1.0.0-beta", "1.0.0") == -1 and U.compareVersions("1.2.0", "1.10.0") == -1
  and U.compareVersions("1.1.0-beta", "1.0.9") == 1 and U.compareVersions("2.0.0", "2.0.0") == 0)
bad = U.copy(s) bad.res[A].i[1] = "x"
check("a copy with a bad item is refused", not S.valid(bad))
local newer = U.copy(s) newer.raid = "Naxxramas" newer.raidName = "Naxxramas"
check("a copy for a raid this version doesn't know is kept (a newer version's)", S.valid(newer) and LR.raidOf(newer).name == "Naxxramas" and LR.raidOf(newer).custom)
bad = U.copy(s) bad.raid = 5
check("a copy with a raid that isn't a name is refused", not S.valid(bad))

print("== any item, and raids that aren't in the lists")
local DRAGONSPINE = 28830
local kz = S.new("Lead-Dreamscythe", "Karazhan", 2, false, 300)
check("a raid in the lists is named from them", kz.raidName == "Karazhan" and not kz.any)
check("its own loot only, unless the leader says so", not S.add(kz, A, "PRIEST", DRAGONSPINE, false, 301) and select(2, S.check(kz, { DRAGONSPINE })) == "NOT_IN_RAID")
check("a raider's addon leaves that to the leader's", S.check(kz, { DRAGONSPINE }, true))
check("the leader allows any item", S.setAny(kz, true, 302) and S.add(kz, A, "PRIEST", DRAGONSPINE, false, 303))
local bd = S.new("Lead-Dreamscythe", LR.CUSTOM, 3, false, 304, "  Barrow Deeps  ")
check("a raid that isn't in the lists, by name", bd.raid == LR.CUSTOM and bd.raidName == "Barrow Deeps" and bd.any and LR.raidOf(bd).name == "Barrow Deeps")
check("any item can be reserved for it", S.add(bd, A, "PRIEST", 123456, false, 305) and S.setHR(bd, 98765, "Ann", "", 306))
check("and it stays that way", not S.setAny(bd, false, 307) and bd.any)
check("but not something that isn't an item", not S.add(bd, A, "PRIEST", 1.5, false, 308) and not S.add(bd, A, "PRIEST", -3, false, 309))
check("it's a valid session", S.valid(bd))
check("item ids from links, item strings and numbers", LR.idFrom("|cffa335ee|Hitem:28830::::|h[Dragonspine Trophy]|h|r") == 28830
  and LR.idFrom("item:123") == 123 and LR.idFrom(" 456 ") == 456 and LR.idFrom("[789]") == 789 and LR.idFrom("watch") == nil)

print("== extra reserves")
local xs = S.new("Lead-Dreamscythe", "Karazhan", 1, true, 600)
check("one each", S.add(xs, A, "PRIEST", 28525, false, 601) and not S.add(xs, A, "PRIEST", 28530, false, 602) and S.limit(xs, A) == 1)
check("the leader gives Ann two more", S.setExtra(xs, A, 2, 603) and S.limit(xs, A) == 3 and S.extra(xs, A) == 2 and S.limit(xs, B) == 1)
check("so she can reserve three", S.add(xs, A, "PRIEST", 28530, false, 604) and S.add(xs, A, "PRIEST", 28528, false, 605)
  and not S.add(xs, A, "PRIEST", 28529, false, 606))
check("what she has left", S.players(xs)[1].left == 0)
check("a sane number only", not S.setExtra(xs, A, 9, 607) and not S.setExtra(xs, A, 1.5, 607) and not S.setExtra(xs, A, 2, 607))
local changed, lost = S.setExtra(xs, A, 1, 608)
check("fewer extras: her last pick goes", changed and lost and #S.reservesOf(xs, A) == 2 and S.reservesOf(xs, A)[2] == 28530)
check("it's a valid session", S.valid(xs))
xs.xr[A] = "lots"
check("but not with nonsense in it", not S.valid(xs))
xs.xr[A] = 1
S.configure(xs, 2, true, 609)
check("changing everyone's count keeps the extra", S.limit(xs, A) == 3)

print("== priority lists instead of reserves")
local ps = S.new("Lead-Dreamscythe", "Karazhan", 2, false, 400)
check("reserves to start with", ps.prio == nil and S.add(ps, A, "PRIEST", 28525, false, 401))
check("priority lists, then reserves: reserving still works", S.setPrio(ps, "both", 402) and ps.prio == "both" and S.add(ps, A, "PRIEST", 28530, false, 403))
check("priority lists only: nobody reserves", S.setPrio(ps, "only", 404) and not S.add(ps, A, "PRIEST", 28528, false, 405)
  and select(2, S.add(ps, A, "PRIEST", 28528, false, 405)) == "PRIO_ONLY")
check("taking reserves back still works", S.set(ps, A, "PRIEST", {}, false, 406))
check("nothing else is a way to decide loot", S.setPrio(ps, "nonsense", 407) and ps.prio == nil)
ps.prio = "auction"
check("a way this version doesn't know is kept", S.valid(ps))
ps.prio = 5
check("but not nonsense", not S.valid(ps))

-- names with letters beyond A-Z: the game's lower() only changes A-Z
check("small letters, accented ones too", U.foldCase("ØYVIND-Dreamscythe") == "øyvind-dreamscythe" and U.foldCase("Ghost") == "ghost")
check("Russian names too", U.foldCase("ЁЛКА") == "ёлка")
check("the same character, whatever the capitals", U.samePlayer("ghØst", "Ghøst-Dreamscythe") and U.samePlayer("ÆSIR", "Æsir"))
check("an accent makes a different character", not U.samePlayer("Ghost", "Ghøst"))
check("a name the way the game writes it", U.capitalize("ghØst") == "Ghøst" and U.capitalize("øyvind") == "Øyvind" and U.capitalize("élise") == "Élise",
  U.capitalize("ghØst") .. " " .. U.capitalize("øyvind"))
check("the realm is left as it is", U.capitalize("ølaf-Area52") == "Ølaf-Area52" and U.capitalize("ann-Faerlina") == "Ann-Faerlina")
check("a letter with no capital stays", U.capitalize("ßam") == "ßam" and U.capitalize("") == "")
check("names matched with accents put aside", U.nameKey("Ghøst") == "ghost" and U.nameKey("GHÖST") == "ghost" and U.nameKey("Æsir") == "aesir"
  and U.nameKey("Strauß") == "strauss")
check("how far apart two spellings are", U.distance("ghost", "ghots") == 2 and U.distance("ghøst", "ghost") == 1 and U.distance("ann", "ann") == 0
  and U.distance("", "ann") == 3)
-- what a softres.it import matched (Core/Gargul.lua): checked like everything else in a session
local ns = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 500)
ns.nm = { ["Ghost-Dreamscythe"] = "Ghøst-Dreamscythe" }
check("matched names are fine", S.valid(ns))
ns.nm = { ["Ghost-Dreamscythe"] = 5 }
check("matched names must be names", not S.valid(ns))
ns.nm = "Ghost"
check("and a list of them", not S.valid(ns))

-- only the group can reserve
local gs = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 800)
S.set(gs, "Out-Dreamscythe", nil, { 28528, 28525 }, true, 801)
check("off: anyone may reserve", S.groupOk(gs, "Out-Dreamscythe", { 28528, 28525, 28529 }, false))
check("switched on", S.setGroupOnly(gs, true, 802) and gs.go == true and not S.setGroupOnly(gs, true, 803))
check("someone in the group may", S.groupOk(gs, "In-Dreamscythe", { 28528 }, true))
check("someone outside it can't add", select(2, S.groupOk(gs, "Out-Dreamscythe", { 28528, 28525, 28529 }, false)) == "GROUP_ONLY"
  and not S.groupOk(gs, "Out-Dreamscythe", { 28528, 28529 }, false))
check("but can take reserves back", S.groupOk(gs, "Out-Dreamscythe", { 28525 }, false) and S.groupOk(gs, "Out-Dreamscythe", {}, false))
check("it's part of a valid session", S.valid(gs))
gs.go = "yes"
check("and must be on or off", not S.valid(gs))

-- finding an award (to undo it)
local fa = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 700)
S.award(fa, 28528, "Ann-Dreamscythe", "MS", 50, 701)
S.award(fa, 28528, "Bob-Faerlina", "OS", 20, 702)
S.award(fa, 28528, "Ann-Dreamscythe", "SR", 80, 703)
check("an award is found: the latest for that player and item", S.findAward(fa, 28528, "ann-dreamscythe") == 3 and S.findAward(fa, 28528, "Bob-Faerlina") == 2)
check("none for someone who didn't win it", S.findAward(fa, 28528, "Cara-Dreamscythe") == nil and S.findAward(fa, 28525, "Ann-Dreamscythe") == nil)

-- a new leader for a session
local hs = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 600)
S.set(hs, "Ann-Dreamscythe", "PRIEST", { 28528 }, false, 601)
local rev = hs.rev
check("the leader hands it to someone", S.handTo(hs, "Ann", 602) and hs.next == "Ann-Dreamscythe" and hs.rev == rev + 1)
check("not to themselves", not S.handTo(hs, "Lead-Dreamscythe", 603))
check("and can take the offer back", S.handTo(hs, nil, 604) and hs.next == nil and not S.handTo(hs, nil, 605))
S.handTo(hs, "Ann", 606)
check("the new leader takes it on: the old one is remembered", S.newLeader(hs, "Ann", 607) and hs.leader == "Ann-Dreamscythe"
  and hs.was[1] == "Lead-Dreamscythe" and hs.next == nil)
check("everything in it stays", S.reservesOf(hs, "Ann-Dreamscythe")[1] == 28528 and hs.id == "Lead-Dreamscythe:600")
check("it's still a valid session", S.valid(hs))
check("a copy naming a new leader counts when it was handed to them", S.newLeaderOk({ next = "Bob-Faerlina" }, "Bob-Faerlina", false, false, false))
check("or they lead or assist the group, and its leader is away", S.newLeaderOk({}, "Bob-Faerlina", true, true, false))
check("or it was ours and they lead or assist, with a newer copy", S.newLeaderOk({}, "Bob-Faerlina", false, true, true, false, true))
check("or it was ours, and their newer copy carried on from us", S.newLeaderOk({}, "Bob-Faerlina", false, false, true, true, true))
check("an old copy never takes ours back, whoever sends it", not S.newLeaderOk({}, "Bob-Faerlina", false, true, true, true, false))
check("not when its leader is here", not S.newLeaderOk({}, "Bob-Faerlina", false, true, false))
check("who led it before", S.ledBy(hs, "Lead-Dreamscythe") and not S.ledBy(hs, "Bob-Faerlina"))
check("not from just anyone", not S.newLeaderOk({}, "Bob-Faerlina", true, false, false) and not S.newLeaderOk({ next = "Ann-Dreamscythe" }, "Bob-Faerlina", true, false, false))
hs.was = { 5 }
check("who led it must be names", not S.valid(hs))
hs.was, hs.next = nil, 7
check("and who it's handed to", not S.valid(hs))

-- raid setup: who's coming, pasted from anywhere
do
  local Ln = LR.Lineup
  local function names(list) local o = {} for _, e in ipairs(list) do o[#o + 1] = e.name .. (e.group and (":" .. e.group) or "") end return table.concat(o, " ") end
  check("one name per line", names(Ln.parse("Ann\nbob\n\nCara-Faerlina\n")) == "Ann Bob Cara-Faerlina", names(Ln.parse("Ann\nbob\n\nCara-Faerlina\n")))
  check("or with commas", names(Ln.parse("Ann, Bob,Cara ; Dan")) == "Ann Bob Cara Dan")
  check("numbered, with class and spec", names(Ln.parse("1. Ann (Holy Priest)\n2) Bob - Fury Warrior\nPriest - Cara\n@Dan tank")) == "Ann Bob Cara Dan",
    names(Ln.parse("1. Ann (Holy Priest)\n2) Bob - Fury Warrior\nPriest - Cara\n@Dan tank")))
  check("a spreadsheet's columns", names(Ln.parse("Ann\tPriest\tHealer\nBob\tWarrior\tTank")) == "Ann Bob")
  check("letters beyond A-Z", names(Ln.parse("øyvind\nGhøst")) == "Øyvind Ghøst")
  check("each name once", names(Ln.parse("Ann\nANN\nann")) == "Ann")
  check("groups", names(Ln.parse("Group 1\nAnn\nBob\nGroup 2: Cara, Dan\nG3:\nEve")) == "Ann:1 Bob:1 Cara:2 Dan:2 Eve:3",
    names(Ln.parse("Group 1\nAnn\nBob\nGroup 2: Cara, Dan\nG3:\nEve")))
  check("nothing that isn't a name", #Ln.parse("Tanks:\nHealers\n123\n--\n") == 0, names(Ln.parse("Tanks:\nHealers\n123\n--\n")))
  local many = {}
  for i = 1, 50 do many[i] = "Name" .. string.char(96 + (i % 26) + 1) .. string.char(96 + math.floor(i / 26) + 1) end
  check("40 at most", #Ln.parse(table.concat(many, "\n")) == 40)
  -- against who's in the group
  local roster = { { name = "Ann-Dreamscythe", group = 1, index = 1 }, { name = "Bob-Faerlina", group = 1, index = 2 },
    { name = "Zed-Dreamscythe", group = 2, index = 3 } }
  local c = Ln.compare(Ln.parse("Ann\nBob\nCara"), roster)
  check("who's here (a name without a realm finds someone from another realm)", #c.here == 2 and c.here[2][2].name == "Bob-Faerlina")
  check("who's missing", #c.missing == 1 and c.missing[1].name == "Cara")
  check("who's here but not on the list", #c.extra == 1 and c.extra[1].name == "Zed-Dreamscythe")
  -- sorting into groups: 10 players in groups 1 and 2, the list wants them swapped round
  local r2, text = {}, { "Group 1" }
  for i = 1, 10 do r2[i] = { name = "P" .. string.char(96 + i) .. "-Dreamscythe", group = i <= 5 and 1 or 2, index = i } end
  for i = 6, 10 do text[#text + 1] = "P" .. string.char(96 + i) end
  text[#text + 1] = "Group 2"
  for i = 1, 5 do text[#text + 1] = "P" .. string.char(96 + i) end
  local plan = Ln.parse(table.concat(text, "\n"))
  local moves = 0
  while true do
    local m = Ln.nextMove(plan, r2)
    if not m or moves > 40 then break end
    Ln.apply(r2, m)
    moves = moves + 1
  end
  local right = true
  for i = 1, 10 do if r2[i].group ~= (i <= 5 and 2 or 1) then right = false end end
  check("full groups are sorted by swapping", right and moves == 5, moves)
  -- a group with room: just moved; players not on the list stay put
  local r3 = { { name = "Ann-Dreamscythe", group = 1, index = 1 }, { name = "Bob-Dreamscythe", group = 1, index = 2 } }
  local m3 = Ln.nextMove(Ln.parse("Group 4: Bob"), r3)
  check("someone wanted in a group with room is moved there", m3 and m3.index == 2 and m3.group == 4 and not m3.with)
  Ln.apply(r3, m3)
  check("and then it's sorted", Ln.nextMove(Ln.parse("Group 4: Bob"), r3) == nil and r3[1].group == 1)
  -- more than five wanted in one group: the sixth is left where they are, and it still ends
  local r4, t4 = {}, { "Group 1" }
  for i = 1, 7 do r4[i] = { name = "Q" .. string.char(96 + i) .. "-Dreamscythe", group = i <= 5 and 2 or 3, index = i } t4[#t4 + 1] = "Q" .. string.char(96 + i) end
  local plan4, n4 = Ln.parse(table.concat(t4, "\n")), 0
  while Ln.nextMove(plan4, r4) and n4 < 50 do Ln.apply(r4, Ln.nextMove(plan4, r4)) n4 = n4 + 1 end
  local in1 = 0
  for _, m in ipairs(r4) do if m.group == 1 then in1 = in1 + 1 end end
  check("a group can't take more than five; it still ends", n4 < 50 and in1 == 5, n4)
end

print(("passed %d"):format(passed))
print(("errors %d"):format(failed))
os.exit(failed == 0 and 0 or 1)
