-- A whole raid, with every player's client running LootRuler side by side (tests/wow/server.lua): the
-- leader opens reserves, raiders reserve in the addon and by whisper, the leader hard reserves, changes
-- the rules, goes offline and comes back, guild members reserve before the group is made, reserves are
-- locked and the session is ended. Checks that every client ends up agreeing with the leader.
--   lua5.1 tests/raid.lua
package.path = "./tests/?.lua;./tests/wow/?.lua;" .. package.path
local Server = require("server")

local failed, passed = 0, 0
local function check(name, ok, detail)
  if ok then passed = passed + 1 else failed = failed + 1 end
  print((ok and "ok   " or "FAIL ") .. name .. ((not ok and detail ~= nil) and ("  " .. tostring(detail)) or ""))
end
local function section(name) print("== " .. name) end

local srv = Server.new(".")
local lead = srv:client({ name = "Lead", class = "PALADIN", guild = "Kings" })
local ann = srv:client({ name = "Ann", class = "PRIEST", guild = "Kings" })
local bob = srv:client({ name = "Bob", class = "MAGE", realm = "Faerlina" })
local cara = srv:client({ name = "Cara", class = "DRUID", guild = "Kings" })
local pug = srv:player({ name = "Pug", class = "WARRIOR" })
srv:tick(6)

local function full(p) return Server.full(p) end
local function cur(p) return p.LR.current() end
local function picks(p) return p.LR.myPicks(cur(p)) end
--- Pug whispers the leader; returns everything whispered back (long answers come in several lines)
local function ask(text)
  local n = #pug.inbox
  srv:whisper(pug, lead, text)
  srv:tick(1)
  local out = {}
  for i = n + 1, #pug.inbox do out[#out + 1] = pug.inbox[i].text end
  return table.concat(out, " ")
end
local function chatHas(p, text)
  for _, line in ipairs(p.M.chat) do if line:find(text, 1, true) then return true end end
  return false
end
local function same(a, b) return table.concat(a, ",") == table.concat(b, ",") end
local U = lead.LR.U

-- Karazhan items used below
local WATCH, BROOCH, TRINKET_DRAGONSPINE, HANDWRAPS, SIGNET, ROYAL = 28528, 28530, 28830, 28507, 28525, 28529

section("opening reserves")
srv:setGroup({ lead, ann, bob, pug }, lead, true)
srv:tick(3)
local s = lead.LR.startSession("Karazhan", 2, true, true)
srv:tick(2)
check("the leader has a session", lead.LR.isLeader(cur(lead)) and cur(lead).raid == "Karazhan")
check("raiders in the group get it", cur(ann) and cur(ann).id == s.id and cur(bob) and cur(bob).id == s.id)
check("and are told in chat", chatHas(ann, "Lead opened soft reserves for Karazhan: 2 reserves each"))
check("a raider on another realm gets it too", cur(bob) and cur(bob).leader == full(lead))
check("guild members outside the group see it", cara.LR.session(s.id) ~= nil)
check("but don't make it their current one until they're grouped", cur(cara) == nil)

section("reserving in the addon")
local ok = ann.LR.reserve(cur(ann), WATCH)
check("Ann reserves a watch", ok and same(picks(ann), { WATCH }))
srv:tick(2)
check("the leader has it", same(lead.LR.Session.reservesOf(s, full(ann)), { WATCH }))
check("Ann's pick is confirmed", not ann.LR.pending(cur(ann)))
ann.LR.reserve(cur(ann), WATCH)
srv:tick(2)
check("doubling up is allowed", same(lead.LR.Session.reservesOf(s, full(ann)), { WATCH, WATCH }))
local why
ok, why = ann.LR.reserve(cur(ann), BROOCH)
check("a third reserve is refused before it's sent", not ok and why == "TOO_MANY")
check("Bob sees Ann's reserves", same(bob.LR.Session.reservesOf(cur(bob), full(ann)), { WATCH, WATCH }))
bob.LR.reserve(cur(bob), TRINKET_DRAGONSPINE)
srv:tick(2)
check("items from another raid are refused by the leader's addon (it decides, not the raider's)",
  #lead.LR.Session.reservesOf(s, "Bob-Faerlina") == 0 and #picks(bob) == 0 and not bob.LR.pending(cur(bob)))
check("and Bob is told why", chatHas(bob, "turned down your reserves") and chatHas(bob, "the leader can allow any item"))
bob.LR.reserve(cur(bob), HANDWRAPS)
srv:tick(2)
check("Bob, from another realm, reserves", same(lead.LR.Session.reservesOf(s, "Bob-Faerlina"), { HANDWRAPS }))
check("with his class", s.res["Bob-Faerlina"].c == "MAGE")

section("the leader's own reserves")
lead.LR.reserve(s, ROYAL)
srv:tick(2)
check("the leader reserves like everyone else", same(lead.LR.Session.reservesOf(s, full(lead)), { ROYAL }))
check("and raiders see it", same(ann.LR.Session.reservesOf(cur(ann), full(lead)), { ROYAL }))

section("hard reserves")
lead.LR.setHR(s, HANDWRAPS, "Ann", "healer priority")
srv:tick(2)
check("hard reserving takes Bob's soft reserve away", #lead.LR.Session.reservesOf(s, "Bob-Faerlina") == 0)
check("Bob's addon agrees", #picks(bob) == 0 and not bob.LR.pending(cur(bob)))
check("the leader is told who lost a reserve", chatHas(lead, "lost their reserve on it"))
check("raiders see the hard reserve", cur(bob).hr[HANDWRAPS] and cur(bob).hr[HANDWRAPS].f == "Ann")
ok, why = bob.LR.reserve(cur(bob), HANDWRAPS)
check("and can't reserve it", not ok and why == "HARD_RESERVED")

section("whispers from players without the addon")
local r
r = ask("!lr Dragonspine Trophy")
check("an item from another raid isn't found", r:find("couldn't find", 1, true) ~= nil, r)
r = ask("!lr |cffa335ee|Hitem:28528::::::::70:::::|h[Moroes' Lucky Pocket Watch]|h|r")
check("a linked item is reserved", same(lead.LR.Session.reservesOf(s, full(pug)), { WATCH }), r)
check("and the answer says so", r:find("Reserved", 1, true) and r:find("1 of 2 used", 1, true), r)
check("answers start with the tag", r:sub(1, 11) == "[LootRuler]")
check("Pug's class comes from the raid", s.res[full(pug)].c == "WARRIOR")
r = ask("!lr signet of unshakable")
check("part of a name finds the item", same(lead.LR.Session.reservesOf(s, full(pug)), { WATCH, SIGNET }), r)
r = ask("!lr bracers")
check("an unclear name asks which", r:find("Which one?", 1, true) ~= nil, r)
r = ask("!lr Royal Cloak of Arathi Kings")
check("no reserves left: refused", r:find("no reserves left", 1, true) ~= nil, r)
r = ask("!lr remove signet")
check("remove one", same(lead.LR.Session.reservesOf(s, full(pug)), { WATCH }), r)
r = ask("!lr")
check("!lr on its own lists your reserves", r:find("You have reserved", 1, true) ~= nil, r)
r = ask("!lr |cffa335ee|Hitem:28507::::::::70:::::|h[Handwraps of Flowing Thought]|h|r")
check("hard reserved items can't be whispered for", r:find("hard reserved", 1, true) ~= nil, r)
r = ask("!sr")
check("!sr is left to Gargul", not r:find("LootRuler", 1, true) or r:find("hard reserved", 1, true))
check("every whisper fits in one chat message", (function()
  for _, m in ipairs(srv.chat) do if #m.text > 255 then return false end end
  return true
end)())
check("the leader's chat hides !lr whispers", srv:hidden(lead, "CHAT_MSG_WHISPER", "!lr signet") and not srv:hidden(lead, "CHAT_MSG_WHISPER", "hi"))
check("and the answers", srv:hidden(lead, "CHAT_MSG_WHISPER_INFORM", "[LootRuler] Reserved"))
check("raiders see whispered reserves", same(ann.LR.Session.reservesOf(cur(ann), full(pug)), { WATCH }))

section("+1s in whispers")
lead.LR.setPlusOne(s, true)
srv:tick(1)
r = ask("!lr")
check("with the +1 rule on, !lr says your +1s", r:find("You have 0 +1s", 1, true) ~= nil, r)
lead.LR.setPlusOne(s, false)
srv:tick(1)

section("!lr in raid chat")
local before = #pug.inbox
srv:chatMessage(pug, "!lr remove watch", "RAID")
srv:tick(1)
local answer
for i = before + 1, #pug.inbox do if pug.inbox[i].from == full(lead) and not pug.inbox[i].channel then answer = pug.inbox[i].text end end
check("typed in raid chat, it works like a whisper", #lead.LR.Session.reservesOf(s, full(pug)) == 0, answer)
check("and the answer comes by whisper, not in raid chat", answer and answer:find("Removed", 1, true) ~= nil)
local raidLines = 0
for i = before + 1, #pug.inbox do if pug.inbox[i].channel == "RAID" and pug.inbox[i].from == full(lead) then raidLines = raidLines + 1 end end
check("raid chat isn't flooded with answers", raidLines == 0)
srv:chatMessage(pug, "!lr |cffa335ee|Hitem:28528::::::::70:::::|h[Moroes' Lucky Pocket Watch]|h|r", "RAID")
srv:tick(1)
check("reserving in raid chat", same(lead.LR.Session.reservesOf(s, full(pug)), { WATCH }))
check("raiders with the addon don't see the !lr lines", srv:hidden(ann, "CHAT_MSG_RAID", "!lr watch") and not srv:hidden(ann, "CHAT_MSG_RAID", "pull in 10"))
lead.LR.db.settings.raidCommands = false
srv:chatMessage(pug, "!lr clear", "RAID")
srv:tick(1)
check("the leader can switch it off", same(lead.LR.Session.reservesOf(s, full(pug)), { WATCH }))
lead.LR.db.settings.raidCommands = true
-- a whole pug at once: every answer gets there, spaced out so the leader isn't muted for spam
local crowd = {}
for i = 1, 12 do
  local q = srv:player({ name = "Crowd" .. i, class = "HUNTER" })
  table.insert(srv.group.members, q) q.inGroup = true
  crowd[#crowd + 1] = q
end
srv:rosterChanged()
srv:tick(1)
for _, q in ipairs(crowd) do srv:chatMessage(q, "!lr |cffa335ee|Hitem:28525::::::::70:::::|h[Signet of Unshakable Faith]|h|r", "RAID") end
srv:tick(1)
srv:tick(15)
local answered = 0
for _, q in ipairs(crowd) do for _, m in ipairs(q.inbox) do if m.text:find("Reserved", 1, true) then answered = answered + 1 break end end end
check("twelve people reserving at once all get in", #lead.LR.Session.players(s) >= 12 + 3)
check("and all get an answer", answered == 12, answered)
for _, q in ipairs(crowd) do
  for i, m in ipairs(srv.group.members) do if m == q then table.remove(srv.group.members, i) break end end
  q.inGroup = false
  lead.LR.leaderRemove(s, full(q), 28525)
end
srv:rosterChanged()
srv:tick(2)

section("the leader goes offline")
local leadDB = srv:logout(lead)
srv:tick(1)
ann.LR.unreserve(cur(ann), WATCH)
ann.LR.reserve(cur(ann), BROOCH)
srv:tick(2)
check("Ann's change waits", ann.LR.pending(cur(ann)) and same(picks(ann), { WATCH, BROOCH }))
srv:login(lead, leadDB)
srv:tick(8)
s = lead.LR.session(s.id)
check("the leader's session survives logging out", s and lead.LR.isLeader(s))
check("Ann's change arrives when the leader is back", s and same(lead.LR.Session.reservesOf(s, full(ann)), { WATCH, BROOCH }))
check("and is confirmed", not ann.LR.pending(cur(ann)))

section("reserving before the group is made")
cara.LR.select(s.id)
cara.LR.reserve(cara.LR.session(s.id), ROYAL)
srv:tick(2)
check("a guild member outside the group reserves over the guild channel", same(lead.LR.Session.reservesOf(s, full(cara)), { ROYAL }))
check("and gets the answer", not cara.LR.pending(cara.LR.session(s.id)))
check("with her class", s.res[full(cara)].c == "DRUID")

section("changing the rules")
lead.LR.configure(s, 1, false)
srv:tick(2)
check("fewer reserves trims everyone", #lead.LR.Session.reservesOf(s, full(ann)) == 1 and #lead.LR.Session.reservesOf(s, full(lead)) == 1)
check("raiders' addons agree", #picks(ann) == 1 and cur(ann).sr == 1 and not cur(ann).dupes)

section("locking")
lead.LR.setLocked(s, true)
srv:tick(2)
check("raiders see the lock", cur(ann).locked)
ok, why = ann.LR.reserve(cur(ann), SIGNET)
check("and can't change", not ok and why == "LOCKED")
r = ask("!lr remove watch")
check("whispers can't either", r:find("locked", 1, true) ~= nil, r)
check("the leader still can", lead.LR.leaderRemove(s, full(pug), WATCH))
lead.LR.setLocked(s, false)
srv:tick(2)

section("the wrong people can't change things")
local fake = ann.LR.Net.encode({ t = "T", s = { id = s.id, rev = 999, leader = full(lead), raid = "Karazhan", sr = 5, dupes = true, hr = {}, res = {} } })
srv:addonMessage(ann, "LootRuler", fake, "RAID")
srv:tick(1)
check("a session sent by someone who isn't its leader is ignored", cur(bob).sr == 1 and cur(bob).rev < 999)
local forged = ann.LR.Net.encode({ t = "P", id = s.id, c = "MAGE", i = { SIGNET } })
srv:addonMessage(ann, "LootRuler", forged, "WHISPER", full(lead))
srv:tick(1)
check("picks only ever count for whoever sent them", same(lead.LR.Session.reservesOf(s, full(ann)), { SIGNET }))
check("and a class claimed in a message doesn't beat the raid roster", s.res[full(ann)].c == "PRIEST")
check("Bob's reserves weren't touched", #lead.LR.Session.reservesOf(s, "Bob-Faerlina") == 0)
srv:addonMessage(bob, "LootRuler", "not a real message", "RAID")
srv:tick(1)
check("nonsense is ignored", #lead.M.errors == 0, table.concat(lead.M.errors, " | "))

section("no chatter")
local sent = 0
local orig = srv.addonMessage
srv.addonMessage = function(self, from, ...) sent = sent + 1 return orig(self, from, ...) end
ann.LR.db.mine[s.id].dirty = true                -- as if Ann's last picks were never confirmed
for _ = 1, 10 do srv:rosterChanged() srv:tick(0.3) end
srv.addonMessage = orig
check("group changes don't make raiders resend the same picks over and over", sent <= 6, sent .. " messages")
check("and Ann's picks are confirmed", not ann.LR.pending(cur(ann)))

section("joining late")
local dan = srv:client({ name = "Dan", class = "ROGUE" })
srv:tick(1)
check("not in the group: nothing yet", cur(dan) == nil)
table.insert(srv.group.members, dan) dan.inGroup = true
srv:rosterChanged()
srv:tick(4)
check("joining the group brings the session", cur(dan) and cur(dan).id == s.id and cur(dan).rev == s.rev)

section("the leader's addon decides what can be reserved")
r = ask("!lr |cffa335ee|Hitem:28830::::::::70:::::|h[Dragonspine Trophy]|h|r")
check("a link to another raid's item is refused by whisper, saying why", r:find("only its loot can be reserved", 1, true) ~= nil, r)
lead.LR.setAny(s, true)
srv:tick(2)
check("the leader allows any item; raiders see it", cur(ann).any == true)
r = ask("!lr |cffa335ee|Hitem:28830::::::::70:::::|h[Dragonspine Trophy]|h|r")
check("then a linked item from anywhere is reserved", U.indexOf(lead.LR.Session.reservesOf(s, full(pug)), TRINKET_DRAGONSPINE) ~= nil, r)
lead.LR.leaderRemove(s, full(pug), TRINKET_DRAGONSPINE)
lead.LR.setAny(s, false)
srv:tick(2)
-- Bob's addon is an old version whose Karazhan list doesn't have the signet
local had = bob.LR.RAID_BY_KEY.Karazhan.has[SIGNET]
bob.LR.RAID_BY_KEY.Karazhan.has[SIGNET] = nil
lead.LR.leaderRemove(s, full(ann), SIGNET)
srv:tick(2)
ok = bob.LR.reserve(cur(bob), SIGNET)
srv:tick(2)
check("a raider whose loot list is out of date can still reserve what the leader's allows", ok and U.indexOf(lead.LR.Session.reservesOf(s, "Bob-Faerlina"), SIGNET) ~= nil)
bob.LR.RAID_BY_KEY.Karazhan.has[SIGNET] = had

section("older and newer versions")
check("everyone's addon says which version it is", lead.LR.versionOf(full(ann)) == lead.LR.VERSION and lead.LR.versionOf("Bob-Faerlina") == lead.LR.VERSION)
check("a player without the addon has none", lead.LR.versionOf(full(pug)) == nil)
-- the leader's addon is a newer version that adds things this one doesn't know
local realVersion = lead.LR.VERSION
lead.LR.VERSION = "9.9.9"
s.somethingNew = { "a", "b" }
s.won = { { i = WATCH, p = full(ann), k = "DE", at = 1 } }
s.rev = s.rev + 1
lead.LR.leaderChanged(s)
srv:tick(2)
check("a newer version's session is still taken", cur(ann).rev == s.rev and cur(ann).won[1].k == "DE")
check("and the player is told, once, that there's a newer LootRuler", chatHas(ann, "has a newer LootRuler (9.9.9"))
local told = 0
for _, line in ipairs(ann.M.chat) do if line:find("newer LootRuler", 1, true) then told = told + 1 end end
check("only once", told == 1, told)
ann.LR.UI.show("loot")
ann.LR.UI.show("reserves")
srv:tick(0.5)
check("screens show what they don't know without breaking", #ann.M.errors == 0, table.concat(ann.M.errors, " | "))
ann.LR.UI.win:Hide()
local rev = cur(ann).rev
srv:addonMessage(lead, "LootRuler", lead.LR.Net.encode({ t = "T", s = { id = s.id, rev = 999, leader = full(lead), raid = "Karazhan", sr = 2, hr = {}, res = {} }, mv = 99 }), "RAID")
srv:addonMessage(lead, "LootRuler", lead.LR.Net.encode({ t = "Z", stuff = { 1, 2, 3 } }), "RAID")
srv:tick(1)
check("a message only newer versions can handle is left alone", cur(ann).rev == rev)
check("and a kind of message this version doesn't know is ignored", #ann.M.errors == 0)
lead.LR.VERSION = realVersion
s.somethingNew, s.won = nil, nil
s.rev = s.rev + 1
lead.LR.leaderChanged(s)
srv:tick(2)

section("ending")
lead.LR.endSession(s)
srv:tick(2)
check("the leader's session is gone", lead.LR.session(s.id) == nil)
check("raiders' copies are gone", ann.LR.session(s.id) == nil and bob.LR.session(s.id) == nil and dan.LR.session(s.id) == nil)
check("guild members' too", cara.LR.session(s.id) == nil)
check("and they're told", chatHas(ann, "closed the soft reserves for Karazhan"))
local before = #pug.inbox
r = ask("!lr watch")
check("whispers are left alone once it's over", #pug.inbox == before)

section("no errors")
for _, p in ipairs({ lead, ann, bob, cara, dan }) do
  check(p.name .. ": no Lua errors", #p.M.errors == 0, table.concat(p.M.errors, " | "))
end

section("a raid that isn't in the lists")
local bd = lead.LR.startSession(lead.LR.CUSTOM, 2, false, false, "Barrow Deeps")
srv:tick(2)
check("raiders get it, by name", cur(ann) and cur(ann).id == bd.id and chatHas(ann, "opened soft reserves for Barrow Deeps"))
local FOREVER_ITEM = 45001                       -- an item no loot list has
ok = ann.LR.reserve(cur(ann), FOREVER_ITEM)
srv:tick(2)
check("any item can be reserved", ok and lead.LR.Session.reservesOf(bd, full(ann))[1] == FOREVER_ITEM)
r = ask("!lr |cffa335ee|Hitem:28830::::::::70:::::|h[Dragonspine Trophy]|h|r")
check("by whisper too", lead.LR.Session.reservesOf(bd, full(pug))[1] == TRINKET_DRAGONSPINE, r)
r = ask("!lr dragonspine")
check("by name, once someone has linked it (found, then refused: one per item)", r:find("Dragonspine Trophy", 1, true) ~= nil and r:find("only reserve an item once", 1, true) ~= nil, r)
lead.LR.endSession(bd)
srv:tick(2)

print(("passed %d"):format(passed))
print(("errors %d"):format(failed))
os.exit(failed == 0 and 0 or 1)
