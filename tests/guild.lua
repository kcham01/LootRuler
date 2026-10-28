-- A guild raid, every player's client side by side (tests/wow/server.lua): the guild book (Core/Book.lua,
-- Core/Guild.lua) shared over the guild channel, only the guild master and the ranks they pick changing it,
-- raid points, and boosted rolls, by roll window and by typing /roll, for players with and without the addon.
--   lua5.1 tests/guild.lua
package.path = "./tests/?.lua;./tests/wow/?.lua;" .. package.path
local Server = require("server")

local failed, passed = 0, 0
local function check(name, ok, detail)
  if ok then passed = passed + 1 else failed = failed + 1 end
  print((ok and "ok   " or "FAIL ") .. name .. ((not ok and detail ~= nil) and ("  " .. tostring(detail)) or ""))
end
local function section(name) print("== " .. name) end

local srv = Server.new(".")
local DATA = {}
do
  local chunk = assert(loadfile("LootRuler/Data/Loot.lua"))
  setfenv(chunk, setmetatable({}, { __index = _G }))
  chunk("LootRuler", DATA)
end
srv.itemInfo = function(id)
  local it = DATA.ITEMS[id]
  if not it then return nil end
  return { name = it[1], quality = it[2], link = ("|cffa335ee|Hitem:%d::::::::70:::::|h[%s]|h|r"):format(id, it[1]) }
end

local G = "Night Watch"
local mira = srv:client({ name = "Mira", class = "DRUID", guild = G, rank = 0 })       -- the guild master
local lead = srv:client({ name = "Lead", class = "PALADIN", guild = G, rank = 1 })     -- an officer, running loot
local ann = srv:client({ name = "Ann", class = "PRIEST", guild = G, rank = 3 })
local bob = srv:client({ name = "Bob", class = "MAGE", guild = G, rank = 3 })
local kay = srv:client({ name = "Kay", class = "HUNTER", guild = G, rank = 3 })       -- not in the raid
local zed = srv:client({ name = "Zed", class = "ROGUE" })                              -- not in the guild
local pug = srv:player({ name = "Pug", class = "WARRIOR", guild = G, rank = 4 })      -- in the guild, no addon
srv:setGroup({ lead, ann, bob, zed, pug }, lead, true)
srv:setMasterLooter(lead)
srv:tick(10)

local SIGNET, BROOCH, WATCH = 28525, 28530, 28528
local function full(p) return Server.full(p) end
local function chat(text, channel)
  for i = #srv.chat, 1, -1 do
    local m = srv.chat[i]
    if m.text:find(text, 1, true) and (not channel or m.channel == channel) then return m end
  end
end
local function whisperTo(p, text)
  for i = #p.inbox, 1, -1 do if p.inbox[i].text:find(text, 1, true) then return p.inbox[i] end end
end
local function points(p, who) return p.LR.Book.points(p.LR.book(), full(who)) end
local function frameFor(p, id)
  local frames = p.LR.UI.rollFrames()
  for i = #frames, 1, -1 do
    local f = frames[i]
    if f:IsShown() and f.copy and f.copy.id == id then return f end
  end
end
local function edit(p, fn) return p.LR.Guild.edit(function(book, now) return fn(p.LR.Book, book, now) end) end

section("who may change the guild book")
check("everyone knows their guild", lead.LR.guildName() == G and lead.LR.book().guild == G and zed.LR.book() == nil)
check("the guild master and officers may", mira.LR.canEditBook() and lead.LR.canEditBook() and mira.LR.isGuildMaster())
check("a member may not", not ann.LR.canEditBook() and not ann.LR.Guild.edit(function() end))
check("and knows who may", lead.LR.canEditBook(full(mira)) and not lead.LR.canEditBook(full(ann)))

section("an officer changes it: everyone in the guild gets the change")
edit(lead, function(B, book, now) return B.setBoost(book, true, 10, now) end)
srv:tick(1)
check("boosted rolls are on for the whole guild", mira.LR.book().boost.on and ann.LR.book().boost.on and kay.LR.book().boost.on)
edit(lead, function(B, book, now) return B.setPoints(book, full(ann), 30, now) end)
srv:tick(1)
check("points spread", points(mira, ann) == 30 and points(kay, ann) == 30 and points(ann, ann) == 30)

section("a member can't change it, even by sending the change themselves")
ann.LR.Net.send({ t = "GB", g = G, c = { points = { [full(ann)] = { n = 900, t = ann.G.GetServerTime() + 100 } } } }, "GUILD")
srv:tick(1)
check("nobody takes it", points(lead, ann) == 30 and points(mira, ann) == 30 and points(kay, ann) == 30)
ann.LR.Net.send({ t = "GB", g = G, c = { editRank = 4, et = ann.G.GetServerTime() + 100 } }, "GUILD")
lead.LR.Net.send({ t = "GB", g = G, c = { editRank = 4, et = lead.G.GetServerTime() + 100 } }, "GUILD")
srv:tick(1)
check("only the guild master says who may edit", mira.LR.book().editRank == 1 and kay.LR.book().editRank == 1)
zed.LR.Net.send({ t = "GB", g = G, c = { points = { [full(zed)] = { n = 50, t = zed.G.GetServerTime() + 100 } } } }, "WHISPER", full(lead))
srv:tick(1)
check("nor someone outside the guild", points(lead, zed) == 0)
lead.LR.Net.send({ t = "GB", g = G, c = { points = "lots" } }, "GUILD")
srv:tick(1)
check("nonsense is ignored", points(kay, ann) == 30 and #kay.M.errors == 0)

section("the raid")
local s = lead.LR.startSession("Karazhan", 2, true, false)
check("the Session tab offers boosted rolls when the guild uses them", lead.LR.UI.boostOn())
lead.LR.setSessionBoost(s, true)
srv:tick(2)
check("the session has them on, for raiders too", s.boost and ann.LR.current().boost)
local who = lead.LR.Guild.raidMembers()
check("who's from the guild in the group (not Zed)", #who == 4, #who)
check("raid points", lead.LR.Guild.raidPoints(s) and lead.LR.Guild.pointsGiven(s))
srv:tick(1)
check("everyone from the guild in the raid gets them", points(lead, ann) == 40 and points(lead, bob) == 10 and points(lead, pug) == 10
  and points(lead, lead) == 10 and points(lead, zed) == 0 and points(lead, kay) == 0)
check("the guild's other copies too", points(kay, bob) == 10 and points(mira, ann) == 40)
check("the raid is told", chat("Raid points: 4 players from Night Watch got 10 points each", "RAID") ~= nil)

section("someone logging in later gets the book")
local neo = srv:client({ name = "Neo", class = "WARLOCK", guild = G, rank = 3 })
srv:tick(12)
check("from an officer, on asking the guild", points(neo, ann) == 40 and neo.LR.book().boost.on, points(neo, ann))

section("a boosted roll")
local Rolls = lead.LR.Rolls
local roll = Rolls.start(SIGNET, {})
srv:tick(0.5)
check("everyone's points go with the roll", roll and roll.bp and roll.bp["ann-dreamscythe"] == 40 and roll.bp["pug-dreamscythe"] == 10)
check("the raid is told how to roll boosted", chat("Boosted rolls (your points are spent if you win): Ann /roll 41 140", "RAID_WARNING") ~= nil
  and chat("Pug /roll 11 110", "RAID_WARNING") ~= nil)
local fa = frameFor(ann, SIGNET)
check("Ann's roll window has a green dice with her points", fa and fa.boost:IsShown() and fa.boost:IsEnabled() and fa.boost.label:GetText() == "+40")
local fz = frameFor(zed, SIGNET)
check("Zed has no points: no green dice", fz and not fz.boost:IsShown())
srv:willRoll(ann, 120)
ann.M.click(fa.boost)
srv:tick(0.3)
check("the green dice rolls 41-140", roll.rolled["ann-dreamscythe"] and roll.rolled["ann-dreamscythe"].kind == "BR" and roll.rolled["ann-dreamscythe"].n == 120)
check("and she can't roll again", not frameFor(ann, SIGNET).boost:IsEnabled() and not frameFor(ann, SIGNET).dice:IsEnabled())
srv:roll(pug, 11, 110, 105)       -- typed, without the addon
srv:willRoll(bob, 100)
bob.M.click(frameFor(bob, SIGNET).dice)
srv:roll(zed, 41, 140, 139)       -- someone else's range
srv:tick(0.3)
check("Pug's typed boosted roll counts", roll.rolled["pug-dreamscythe"] and roll.rolled["pug-dreamscythe"].kind == "BR")
check("Zed's doesn't (it's not his range)", roll.rolled["zed-dreamscythe"] == nil)
srv:tick(22)
local top = lead.LR.Roll.result(roll)
check("the highest number wins", top and top.p == full(ann) and top.kind == "BR")
local ok, note = Rolls.award(full(ann))
srv:tick(1)
check("given out", ok and chat("goes to Ann (BR 120)", "RAID") ~= nil)
check("Ann's points are spent", points(lead, ann) == 0 and note and note:find("Ann's 40 points are spent", 1, true), note)
check("everywhere", points(ann, ann) == 0 and points(mira, ann) == 0 and points(kay, ann) == 0)
local w = s.won[#s.won]
check("it's a main spec win, marked as boosted", w.k == "MS" and w.br == true and w.p == full(ann))

section("a tie with boosted rolls")
roll = Rolls.start(BROOCH, {})
srv:tick(0.5)
srv:willRoll(bob, 105)
bob.M.click(frameFor(bob, BROOCH).boost)
srv:roll(pug, 11, 110, 105)
srv:tick(22)
local _, tied = lead.LR.Roll.result(roll)
check("two boosted rolls of the same number tie", tied and #tied == 2)
roll = Rolls.again("TIE")
srv:tick(0.5)
check("they roll again as plain main spec", roll and roll.mode == "TIE" and roll.tie == "MS" and roll.boosted and roll.boosted["bob-faerlina"] == nil
  and roll.boosted["bob-dreamscythe"] == 10, roll and roll.tie)
srv:willRoll(bob, 70)
bob.M.click(frameFor(bob, BROOCH).dice)
srv:roll(pug, 1, 100, 30)
srv:tick(22)
ok, note = Rolls.award(full(bob))
srv:tick(1)
check("whoever wins the tie still spends their points", ok and points(lead, bob) == 0 and points(kay, bob) == 0 and note:find("Bob's 10 points", 1, true), note)
check("and it's marked boosted", s.won[#s.won].br == true and s.won[#s.won].p == full(bob))

section("undoing a boosted win")
local bobPoints = points(lead, bob)
local okU, noteU = Rolls.undo()
srv:tick(1)
check("taken back: Bob gets his points back, everywhere", okU and points(lead, bob) == bobPoints + 10 and points(kay, bob) == bobPoints + 10
  and noteU and noteU:find("Bob gets their 10 points back", 1, true), noteU)
ok, note = Rolls.award(full(bob))
srv:tick(1)
check("given again: spent again", ok and points(lead, bob) == bobPoints)

section("players without the addon ask")
srv:whisper(pug, lead, "!lr points")
srv:tick(1)
check("Pug hears his points and what to type", whisperTo(pug, "You have 10 points. For a boosted main spec roll, type /roll 11 110.") ~= nil)
srv:whisper(ann, lead, "!lr points")
srv:tick(1)
check("Ann hears she has none now", whisperTo(ann, "You have no points for boosted rolls yet. Each raid with Night Watch is worth 10.") ~= nil)

section("priority lists")
local ROYAL, HANDWRAPS = 28529, 28507
local found = function(p, text, root) return #p.M.findText(text, true, root) > 0 end
local lists = lead.LR.Prio.parse(("%d,Ann,Bob|Pug\n%d,Bob|Pug,Ann\n%d,Kay,Bob"):format(WATCH, ROYAL, HANDWRAPS))
check("an officer brings lists in, for the guild", edit(lead, function(B, book, now) return lead.LR.Prio.apply(book, lists, now) end))
srv:tick(1)
check("everyone in the guild has them", #kay.LR.Book.prio(kay.LR.book(), WATCH) == 3 and #mira.LR.Book.prio(mira.LR.book(), ROYAL) == 3)
check("a member can't change them", not ann.LR.Guild.edit(function(book, now) return ann.LR.Book.setPrio(book, WATCH, {}, now) end))
zed.LR.reserve(zed.LR.current(), WATCH)
zed.LR.reserve(zed.LR.current(), BROOCH)
lead.LR.setSessionPrio(s, "both")
srv:tick(2)
check("the session goes by priority lists, then reserves", ann.LR.current().prio == "both" and lead.LR.Session.claims(s, full(zed), WATCH) == 1)

roll = Rolls.start(WATCH, {})
srv:tick(0.5)
check("first on the list and here: it's theirs, no roll (over Zed's reserve)", roll.mode == "PR" and roll.state == "closed" and #roll.who == 1 and roll.who[1] == full(ann))
check("the raid is told", chat("is first on the priority list, so it goes to them", "RAID_WARNING") ~= nil)
check("the loot master's window says so, with a button", found(lead, "Priority list:", lead.G.LootRulerMasterFrame) and found(lead, "Award to Ann", lead.G.LootRulerMasterFrame))
ok, note = Rolls.award(full(ann))
srv:tick(1)
check("given, and Ann comes off the list", ok and note:find("Ann comes off its priority list", 1, true) and #lead.LR.Book.prio(lead.LR.book(), WATCH) == 2, note)
check("everywhere", #kay.LR.Book.prio(kay.LR.book(), WATCH) == 2 and #ann.LR.Book.prio(ann.LR.book(), WATCH) == 2)

roll = Rolls.start(ROYAL, {})
srv:tick(0.5)
check("two share first place: only they roll", roll.mode == "PR" and roll.state == "open" and #roll.who == 2)
check("the raid is told who", chat("Bob, Pug share the top priority, so only they roll (/roll)", "RAID_WARNING") ~= nil)
local fb, fa2 = frameFor(bob, ROYAL), frameFor(ann, ROYAL)
check("Bob's window lets him roll; Ann's doesn't", fb and fb.dice:IsEnabled() and not fb.coin:IsShown() and fa2 and not fa2.dice:IsEnabled())
check("and says why", fb.status:GetText():find("on the priority list", 1, true) and fa2.status:GetText():find("Priority list: Bob, Pug (1st)", 1, true), fa2 and fa2.status:GetText())
srv:roll(ann, 1, 100, 99)
srv:willRoll(bob, 60)
bob.M.click(fb.dice)
srv:roll(pug, 1, 100, 30)
srv:tick(3)
check("Ann's roll doesn't count; it's over once both have rolled", roll.state == "closed" and roll.rolled["ann-dreamscythe"] == nil and lead.LR.Roll.result(roll).p == full(bob))
ok, note = Rolls.award(full(bob))
srv:tick(1)
check("Bob comes off that list; Pug stays first", #lead.LR.Book.prio(lead.LR.book(), ROYAL) == 2 and lead.LR.Book.prio(lead.LR.book(), ROYAL)[1].p == full(pug))

roll = Rolls.start(HANDWRAPS, {})
srv:tick(0.5)
check("the first on a list who's here (Kay isn't)", roll.mode == "PR" and roll.who[1] == full(bob) and roll.n == 2)
Rolls.cancel()
roll = Rolls.start(BROOCH, {})
srv:tick(0.5)
check("an item with no list goes by reserves", roll.mode == "SR" and roll.who[1][1] == full(zed))
Rolls.cancel()
srv:tick(1)

srv:whisper(pug, lead, "!lr prio")
srv:tick(1)
check("!lr prio: your places", whisperTo(pug, "Your priorities:") and whisperTo(pug, "Your priorities:").text:find("1st", 1, true) and whisperTo(pug, "Your priorities:").text:find("2nd", 1, true))
srv:whisper(pug, lead, "!lr prio " .. srv:link(WATCH))
srv:tick(1)
check("!lr prio [item]: its list", whisperTo(pug, "Priority for") and whisperTo(pug, "Priority for").text:find(": 2. Bob, Pug.", 1, true), whisperTo(pug, "Priority for") and whisperTo(pug, "Priority for").text)

lead.LR.setSessionPrio(s, "only")
srv:tick(2)
check("priority lists only: nobody can reserve", not zed.LR.reserve(zed.LR.current(), SIGNET))
srv:whisper(pug, lead, "!lr " .. srv:link(SIGNET))
srv:tick(1)
check("players without the addon are told", whisperTo(pug, "goes by the guild's priority lists, not reserves") ~= nil)
srv:whisper(pug, lead, "!lr")
srv:tick(1)
check("!lr on its own says so, and how to see their places", whisperTo(pug, "goes by the guild's priority lists, not reserves. \"!lr prio\": your place") ~= nil)
roll = Rolls.start(BROOCH, {})
srv:tick(0.5)
check("reserves don't count: everyone rolls", roll.mode == "OPEN")
Rolls.cancel()
lead.LR.setSessionPrio(s, nil)
srv:tick(1)

section("alts")
local Bk = lead.LR.Book
check("an officer links Bob as Kay's alt", lead.LR.Guild.linkAlt(full(bob), "Kay"))
check("a member can't", not ann.LR.Guild.linkAlt(full(pug), "Ann"))
edit(lead, function(B, book, now) return B.setPoints(book, full(kay), 50, now) end)
srv:tick(1)
check("everyone's copy knows: Bob uses Kay's points", Bk.points(lead.LR.book(), full(bob)) == 50 and kay.LR.Book.points(kay.LR.book(), full(bob)) == 50
  and bob.LR.Book.mainOf(bob.LR.book(), full(bob)) == full(kay))
local AXE = 28767
roll = Rolls.start(AXE, {})
srv:tick(0.5)
check("Bob rolls boosted with Kay's points", roll.bp and roll.bp["bob-dreamscythe"] == 50 and frameFor(bob, AXE) and frameFor(bob, AXE).boost:IsShown())
srv:willRoll(bob, 140)
bob.M.click(frameFor(bob, AXE).boost)
srv:tick(22)
ok, note = Rolls.award(full(bob))
srv:tick(1)
check("he wins: Kay's points are spent", ok and Bk.points(lead.LR.book(), full(kay)) == 0 and kay.LR.Book.points(kay.LR.book(), full(kay)) == 0, note)
check("an officer links Pug as Ann's alt (both in the raid)", lead.LR.Guild.linkAlt("Pug", "Ann"))
srv:tick(1)
local annBefore = Bk.points(lead.LR.book(), full(ann))
lead.LR.Guild.raidPoints(s)
srv:tick(1)
check("raid points: Ann and her alt get them once, Kay through Bob", Bk.points(lead.LR.book(), full(ann)) == annBefore + 10
  and Bk.points(lead.LR.book(), full(kay)) == 10)
srv:whisper(pug, lead, "!lr points")
srv:tick(1)
check("!lr points from an alt says whose they are", whisperTo(pug, ("You're Ann's alt: you share their %d points."):format(annBefore + 10)) ~= nil)
check("unlinking gives Pug his own points again", lead.LR.Guild.unlinkAlt("Pug") and Bk.mainOf(lead.LR.book(), full(pug)) == full(pug))
lists = lead.LR.Prio.parseCounts("Mira,70,Zed,Miraalt")
check("Gargul's export brings alts in", lead.LR.Guild.importPoints(lists))
srv:tick(1)
check("everywhere", Bk.mainOf(kay.LR.book(), full(zed)) == full(mira) and kay.LR.Book.points(kay.LR.book(), "Miraalt") == 70)
check("and writes them back out", lead.LR.Prio.countsText({ { p = full(mira), n = 70, alts = Bk.altsOf(lead.LR.book(), full(mira)) } }) == "Mira,70,Miraalt,Zed")
neo.LR.Guild.query()
srv:tick(6)

section("the guild master picks who may edit")
check("only the guild master can", not lead.LR.Guild.setEditRank(0) and mira.LR.Guild.setEditRank(0))
srv:tick(1)
check("everyone hears it", lead.LR.book().editRank == 0 and kay.LR.book().editRank == 0)
check("officers can't any more", not lead.LR.canEditBook() and not edit(lead, function(B, book, now) return B.setPoints(book, full(bob), 99, now) end))
mira.LR.Guild.setEditRank(1)
srv:tick(1)
check("and can again", lead.LR.canEditBook())

section("running loot without the right to change the book")
srv:setAssist(ann, true)
srv:setMasterLooter(ann)
srv:tick(1)
local ar = ann.LR.Rolls.start(28525, {})
srv:tick(0.5)
srv:roll(pug, 11, 110, 100)                 -- Pug's boosted roll
srv:tick(22)
local okA, noteA = ann.LR.Rolls.award(full(pug))
srv:tick(1)
check("an assistant who isn't an officer: Pug's points stay, and she's told to ask an officer", ar and okA and points(lead, pug) == 10
  and noteA and noteA:find("Ask an officer to take Pug's 10 points", 1, true), noteA)
local okB, noteB = ann.LR.Rolls.undo()
check("taking it back: ask an officer to give them back", okB and noteB and noteB:find("Ask an officer to give Pug their 10 points back", 1, true), noteB)
ann.LR.Rolls.dismiss()
lead.LR.setSessionPrio(s, "both")
srv:tick(1)
local wlist = ann.LR.Book.prio(ann.LR.book(), WATCH) or {}
local first = wlist[1] and wlist[1].p
local okP, noteP = ann.LR.Rolls.give(WATCH, first, "MS", {})
srv:tick(1)
check("an item off a priority list: she's told to ask an officer to take them off", first and okP and noteP
  and noteP:find("Ask an officer to take " .. lead.LR.U.short(first) .. " off its priority list: you can't change the lists.", 1, true)
  and #(lead.LR.Book.prio(lead.LR.book(), WATCH) or {}) == #wlist, noteP)
local okQ, noteQ = ann.LR.Rolls.undo()
check("taking it back says to put them back on if they came off", okQ and noteQ
  and noteQ:find("If " .. lead.LR.U.short(first) .. " came off its priority list, put them back on the Guild tab.", 1, true), noteQ)
ann.LR.Rolls.dismiss()
lead.LR.setSessionPrio(s, nil)
srv:setMasterLooter(lead)
srv:setAssist(ann, false)
srv:tick(1)

section("ending the session")
lead.LR.endSession(s)
srv:tick(2)
check("ended", lead.LR.current() == nil)

section("saved data is checked")
local junk = srv:client({ name = "Old", class = "WARRIOR", guild = G, rank = 3 },
  { guilds = { [G] = { guild = G, points = "lots" }, Other = 5, [7] = {} } })
srv:tick(1)
check("a broken book is mended (and the guild's comes back)", type(junk.LR.db.guilds[G]) == "table" and junk.LR.db.guilds[G].points ~= "lots"
  and junk.LR.Book.validBook(junk.LR.db.guilds[G]))
check("so is anything else that isn't a book", junk.LR.db.guilds.Other == nil and junk.LR.db.guilds[7] == nil)
-- one bad entry costs only that entry: the guild's points and lists stay
local mixed = srv:client({ name = "Mixed", class = "WARRIOR", guild = G, rank = 3 },
  { guilds = { [G] = { guild = G, editRank = 1, et = 0, boost = { on = true, perRaid = 15, t = 5 },
    points = { ["Ann-Dreamscythe"] = { n = 40, t = 1 }, ["Bad-Dreamscythe"] = { n = "x", t = 1 } },
    prio = { [28528] = { list = { { p = "Ann-Dreamscythe", n = 1 } }, t = 1 }, [28530] = "broken" },
    alts = { ["Annalt-Dreamscythe"] = { m = "Ann-Dreamscythe", t = 1 }, ["Odd-Dreamscythe"] = { t = 1 } } } } })
srv:tick(1)
local mb = mixed.LR.db.guilds[G]
check("a book with a few bad entries keeps every good one", mb and mb.points["Ann-Dreamscythe"] and mb.points["Ann-Dreamscythe"].n == 40
  and mb.points["Bad-Dreamscythe"] == nil and mb.prio[28528] and mb.prio[28530] == nil
  and mb.alts["Annalt-Dreamscythe"] and mb.alts["Odd-Dreamscythe"] == nil and mb.boost.perRaid == 15 and mixed.LR.Book.validBook(mb))
-- a priority list longer than a copy may carry is cut to the first 100, so the book stays shareable
do
  local big = {}
  for i = 1, 140 do big[i] = { p = "P" .. i .. "-Dreamscythe", n = i } end
  local bk = mixed.LR.Book.new(G)
  mixed.LR.Book.setPrio(bk, 28528, big, 10)
  check("a priority list keeps at most 100 players", #bk.prio[28528].list == 100 and mixed.LR.Book.validBook(bk))
  check("an alt can't be linked to nobody", mixed.LR.Book.setAlt(bk, "Annalt", "", 11) == nil and mixed.LR.Book.validBook(bk))
end

section("the bench")
do
  local bs = lead.LR.startSession("Karazhan", 2, true, false)
  lead.LR.setSessionBoost(bs, true)
  srv:tick(1)
  check("nobody to start with", bs.bn == nil and #lead.LR.Guild.raidMembers(bs) == #lead.LR.Guild.raidMembers())
  lead.LR.setBench(bs, { full(mira), full(zed) })
  srv:tick(2)
  check("the leader benches Mira (and Zed, who isn't in the guild)", bs.bn and #bs.bn == 2 and ann.LR.current().bn and #ann.LR.current().bn == 2)
  local who, benched = lead.LR.Guild.raidMembers(bs)
  check("raid points go to the bench from the guild too", benched == 1 and lead.LR.U.indexOf(who, full(mira)) ~= nil and not lead.LR.U.indexOf(who, full(zed)))
  local before = points(lead, mira)
  lead.LR.Guild.raidPoints(bs)
  srv:tick(1)
  check("Mira gets the raid's points", points(lead, mira) == before + 10, points(lead, mira))
  check("the raid is told how many were on the bench", chat("got 10 points each for boosted rolls (1 on the bench).", "RAID") ~= nil)
  check("the bench counts as there", lead.LR.Session.cleanAtt(bs.att) and (function() for _, n in ipairs(bs.att) do if n == full(mira) then return true end end end)())
  lead.LR.setBench(bs, {})
  srv:tick(1)
  check("the bench can be emptied", bs.bn == nil)
  bs.bn = { 7, "x" }
  check("a broken bench from a message is cleaned", lead.LR.Session.valid(bs) and #bs.bn == 1)
  lead.LR.endSession(bs)
  srv:tick(1)
end

section("no errors")
local longest = 0
for _, m in ipairs(srv.chat) do longest = math.max(longest, #m.text) end
check("every chat line fits", longest <= 255, longest)
for _, p in ipairs({ mira, lead, ann, bob, kay, zed, neo, junk }) do
  check(p.name .. ": no Lua errors", #p.M.errors == 0, table.concat(p.M.errors, " | "))
end

print(("passed %d"):format(passed))
print(("errors %d"):format(failed))
os.exit(failed == 0 and 0 or 1)
