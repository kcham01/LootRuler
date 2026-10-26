-- The practice raid (Core/Practice.lua), on one player's client: pretend players reserve, roll, pass and bid on
-- the real rules, and nothing leaves that client: no chat line, no addon message, nothing kept afterwards.
--   lua5.1 tests/practice.lua
package.path = "./tests/?.lua;./tests/wow/?.lua;" .. package.path
local Server = require("server")

local failed, passed = 0, 0
local function check(name, ok, detail)
  if ok then passed = passed + 1 else failed = failed + 1 end
  print((ok and "ok   " or "FAIL ") .. name .. ((not ok and detail ~= nil) and ("  " .. tostring(detail)) or ""))
end
local function section(name) print("== " .. name) end

local srv = Server.new(".")
local lead = srv:client({ name = "Lead", class = "PALADIN", guild = "Kings", rank = 0 })
local ann = srv:client({ name = "Ann", class = "PRIEST", guild = "Kings" })
srv:tick(6)
local LR = lead.LR
local P, S, Rolls = LR.Practice, LR.Session, LR.Rolls
math.randomseed(7)

-- everything the leader's client sends from here on: chat lines and addon messages
local sent = { chat = 0, addon = 0 }
local addonMessage, chatMessage = srv.addonMessage, srv.chatMessage
function srv:addonMessage(from, ...) if from == lead then sent.addon = sent.addon + 1 end return addonMessage(self, from, ...) end
function srv:chatMessage(from, ...) if from == lead then sent.chat = sent.chat + 1 end return chatMessage(self, from, ...) end
local function shown(text)
  for i = #lead.M.chat, 1, -1 do
    local line = lead.M.chat[i]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if line:find(text, 1, true) then return line end
  end
end

section("only on your own")
srv:setGroup({ lead, ann }, lead, true)
srv:tick(2)
local ok, why = P.canStart()
check("not in a group", not ok and why:find("Leave your group first", 1, true))
srv:setGroup({}, nil, true)
lead.inGroup, ann.inGroup = false, false
srv:rosterChanged()
srv:tick(2)
check("on your own it can start", (P.canStart()))

section("starting")
local historyBefore = #(LR.db.history or {})
local realBook = LR.book()
realBook.boost = realBook.boost or {}
local s = P.start({ raid = "Karazhan", players = 8, sr = 2 })
srv:tick(1)
sent.chat, sent.addon = 0, 0              -- (from here on, nothing may go out)
check("a practice session, mine, of the raid picked", s and s.practice and LR.current() == s and LR.isLeader(s) and s.raid == "Karazhan" and s.sr == 2)
check("eight pretend players are in the group", #LR.roster() == 9 and LR.inGroup("Jaina") and LR.classOf("Jaina") == "MAGE")
check("what the raid would hear goes to raid chat, which is only shown", LR.groupChannel() == "RAID")
check("I can run the loot", LR.canRunLoot())
check("the guild book is a copy", LR.book() ~= realBook and LR.book().guild == realBook.guild)

section("reserves")
local n = P.reserve()
srv:tick(n * 0.4 + 3)
local reserved = 0
for _, x in ipairs(P.players) do reserved = reserved + #S.reservesOf(s, x.name) end
check("the pretend players reserve, by whisper and in raid chat", n == 16 and reserved == 16, reserved)
check("their whispers are answered, on my screen only", shown("(whisper to") and shown("[LootRuler] Reserved") ~= nil)
check("and their lines show too", shown("whispers: !lr") ~= nil)
check("everyone reserved all they could: nothing more", P.reserve() == 0)

section("loot and a reserved roll")
local drops = P.drop(3)
srv:tick(1)
check("a boss drops loot into my bags", #drops == 3 and #s.drops == 3 and s.drops[1].h == LR.U.me())
check("the raid would hear what dropped, with who reserved it", shown("(raid) [LootRuler]") and shown("reserved by") ~= nil)
local roll = P.rollNext()
srv:tick(0.5)
check("rolling out the next item", roll and roll.state == "open" and roll.drop == drops[1].k)
check("its roll window shows", (function() for _, f in ipairs(LR.UI.rollFrames()) do if f:IsShown() and f.copy and f.copy.k == roll.k then return true end end end)())
srv:tick(25)
local top = LR.Roll.result(roll)
check("the pretend players who may roll do; it closes", roll.state == "closed" and top ~= nil, roll.state)
check("only reservers rolled a reserved item", roll.mode ~= "SR" or (function()
  for k in pairs(roll.rolled) do if not S.claims(s, roll.rolled[k].p or k, roll.id) then return false end end return true end)())
check("their rolls show as the game's roll lines", shown("rolls ") ~= nil)
local okA, note = Rolls.award(top.p)
srv:tick(2)
check("giving it out", okA and s.won and #s.won == 1 and s.won[1].p == top.p, note)
check("the award line shows as raid chat", shown("goes to " .. LR.U.short(top.p)) ~= nil)
Rolls.dismiss()

section("a tie")
P.tie = true
local nobody
for _, id in ipairs(LR.raidOf(s).order) do if not S.byItem(s)[id] and not s.hr[id] then nobody = id break end end
roll = Rolls.start(nobody, {})
srv:tick(0.5)
check("an item nobody reserved: everyone may roll", roll and roll.mode == "OPEN")
srv:tick(25)
local _, tied = LR.Roll.result(roll)
check("asked for a tie: two of them tie", roll.state == "closed" and tied and #tied == 2, roll.state)
local again = Rolls.again("TIE")
srv:tick(25)
local _, tied2 = LR.Roll.result(again)
check("rolled again, only the tied players roll", again and again.mode == "TIE" and again.state == "closed" and LR.Roll.result(again) ~= nil
  and (function() for k in pairs(again.rolled) do if not LR.U.indexOf(LR.U.map(tied, LR.Roll.key), k) then return false end end return true end)())
Rolls.cancel()
Rolls.dismiss()
srv:tick(1)

section("an auction")
LR.setGdkp(s, true)
srv:tick(1)
local two = P.drop(2)
Rolls.enqueue({ { id = two[1].i, drop = two[1].k }, { id = two[2].i, drop = two[2].k } })
roll = Rolls.mine()
srv:tick(0.5)
check("in a GDKP, the next item is auctioned", roll and roll.mode == "BID")
srv:tick(90)
check("the pretend players bid against each other", roll.state ~= "open" and roll.top ~= nil and #roll.entries >= 2, roll.state .. " " .. tostring(roll.top))
check("one of them bids by a max, by whisper", shown("whispers: !lr max") ~= nil)
check("and one bids ahead on what's next", shown("whispers: !lr bid") ~= nil and shown("Your bid ahead of up to") ~= nil)
check("it's sold, and the pot has it", s.won[#s.won].k == "BID" and LR.Gdkp.pot(s) > 0)
srv:tick(4)
local nextRoll = Rolls.mine()
check("the next one comes up, with the bid ahead in it", nextRoll and nextRoll.id == two[2].i and nextRoll.mode == "BID" and nextRoll.top ~= nil)
Rolls.cancel()
srv:tick(1)
Rolls.dismiss()
Rolls.clearQueue()

section("several auctions at once")
local three = P.drop(3)
local B = LR.Batch
local batch = B.start(B.candidates(), 30)
srv:tick(0.5)
check("the items I hold go up together", batch and #batch.items >= 3 and batch.state == "open")
check("my own raid line counts as it would in a raid (/lr say)", P.say("#1 60000") and batch.items[1].top and batch.items[1].top.p == LR.U.me())
for _ = 1, 40 do if batch.state ~= "open" then break end srv:tick(5) end
local bids = 0
for _, item in ipairs(batch.items) do bids = bids + #item.entries end
check("the pretend players bid by number", bids > 1 and shown("(raid): #") ~= nil, bids)
check("it ends, and what had bids is sold (mine to me)", batch.state == "closed" and s.won[#s.won].k == "BID"
  and (function() for _, w in ipairs(s.won) do if w.r == 60000 and LR.U.samePlayer(w.p, LR.U.me()) then return true end end end)())

section("a bag check")
local bc = LR.Bags.ask({ 28528, 22861 })
srv:tick(4)
local answers = 0
for _ in pairs(bc.answers) do answers = answers + 1 end
check("the pretend players answer a bag check", answers == #P.players + 1 and shown("answered the bag check") ~= nil)
check("everyone in the report has counts", (function() for _, r in ipairs(LR.Bags.report(bc)) do if not r.counts then return false end end return true end)())

section("the gear overview")
check("asking for everyone's gear", LR.Overview.ask())
srv:tick(4)
local withGear = 0
for _, x in ipairs(P.players) do if LR.Overview.data[LR.Roll.key(x.name)] then withGear = withGear + 1 end end
check("the pretend players send made-up gear from the loot lists", withGear == #P.players and shown("sent their gear") ~= nil)

section("the guild book is a copy")
local points = LR.Book.points(realBook, "Jaina")
LR.Guild.edit(function(book, t) return LR.Book.setPoints(book, "Jaina", 50, t) end)
check("changes go to the copy", LR.Book.points(LR.book(), "Jaina") == 50 and LR.Book.points(realBook, "Jaina") == points)

section("nothing left the client")
check("no chat line was said", sent.chat == 0, sent.chat)
check("no addon message was sent", sent.addon == 0, sent.addon)

section("real whispers don't reach it")
srv:whisper(ann, lead, "!lr " .. srv:link(28528))
srv:tick(1)
check("a real player's !lr doesn't reserve in the practice raid", #S.reservesOf(s, LR.U.full("Ann")) == 0)

section("Gargul")
check("its reserves aren't handed to Gargul", select(2, LR.Gargul.send(s)) == "A practice raid's reserves aren't handed to Gargul.")

section("ending")
LR.endSession(s)
check("/lr say is only for a practice raid", not P.say("300"))
srv:tick(1)
check("ending its session ends it: no session, no pretend players", not P.on and LR.db.sessions[s.id] == nil and #LR.roster() == 1 and not LR.inGroup("Jaina"))
check("not kept under past raids", #(LR.db.history or {}) == historyBefore)
check("the real guild book has its own points", LR.book() == realBook and LR.Book.points(realBook, "Jaina") == points)
check("raid chat is real again (none: on my own)", LR.groupChannel() == nil)

section("a reload in the middle")
s = P.start({ players = 4 })
srv:tick(1)
local db = srv:logout(lead)
srv:login(lead, db)
srv:tick(6)
LR = lead.LR
check("a practice raid isn't kept over a reload", not LR.Practice.on and (function()
  for _, x in pairs(LR.db.sessions) do if x.practice then return false end end return true end)())

section("joining a group ends it")
P = LR.Practice
P.start({ players = 4 })
srv:tick(1)
srv:setGroup({ lead, ann }, lead, true)
srv:tick(2)
check("ends on joining a group", not P.on and LR.current() == nil or (LR.current() and not LR.current().practice))
check("and says so", shown("you joined a group, so the practice raid is over") ~= nil)

section("no errors")
check("none", #lead.M.errors == 0, lead.M.errors[1])

print(("passed %d"):format(passed))
print(("errors %d"):format(failed))
os.exit(failed == 0 and 0 or 1)
