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

section("players without the addon ask")
srv:whisper(pug, lead, "!lr points")
srv:tick(1)
check("Pug hears his points and what to type", whisperTo(pug, "You have 10 points. For a boosted main spec roll, type /roll 11 110.") ~= nil)
srv:whisper(ann, lead, "!lr points")
srv:tick(1)
check("Ann hears she has none now", whisperTo(ann, "You have no points for boosted rolls yet. Each raid with Night Watch is worth 10.") ~= nil)

section("the guild master picks who may edit")
check("only the guild master can", not lead.LR.Guild.setEditRank(0) and mira.LR.Guild.setEditRank(0))
srv:tick(1)
check("everyone hears it", lead.LR.book().editRank == 0 and kay.LR.book().editRank == 0)
check("officers can't any more", not lead.LR.canEditBook() and not edit(lead, function(B, book, now) return B.setPoints(book, full(bob), 99, now) end))
mira.LR.Guild.setEditRank(1)
srv:tick(1)
check("and can again", lead.LR.canEditBook())

section("ending the session")
lead.LR.endSession(s)
srv:tick(2)
check("ended", lead.LR.current() == nil)

section("saved data is checked")
local junk = srv:client({ name = "Old", class = "WARRIOR", guild = G, rank = 3 },
  { guilds = { [G] = { guild = G, points = "lots" }, Other = 5, [7] = {} } })
srv:tick(1)
check("a broken book is thrown away (and the guild's comes back)", type(junk.LR.db.guilds[G]) ~= "table" or junk.LR.db.guilds[G].points ~= "lots")
check("so is anything else that isn't a book", junk.LR.db.guilds.Other == nil and junk.LR.db.guilds[7] == nil)

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
