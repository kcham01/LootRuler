-- A five-player party with master loot, every client running LootRuler side by side (tests/wow/server.lua),
-- plus a pug without it: the master looter isn't the party's leader, so everyone's addon has to find them
-- by their place in the party. Reserves, a roll in party chat and the handout all work as they do in a raid.
--   lua5.1 tests/party.lua
package.path = "./tests/?.lua;./tests/wow/?.lua;" .. package.path
local Server = require("server")

local failed, passed = 0, 0
local function check(name, ok, detail)
  if ok then passed = passed + 1 else failed = failed + 1 end
  print((ok and "ok   " or "FAIL ") .. name .. ((not ok and detail ~= nil) and ("  " .. tostring(detail)) or ""))
end
local function section(name) print("== " .. name) end

local srv = Server.new(".")
local lead = srv:client({ name = "Lead", class = "PALADIN" })
local ann = srv:client({ name = "Ann", class = "PRIEST" })
local bob = srv:client({ name = "Bob", class = "MAGE", realm = "Faerlina" })
local dan = srv:client({ name = "Dan", class = "ROGUE" })
local pug = srv:player({ name = "Pug", class = "WARRIOR" })
srv:setGroup({ lead, ann, bob, dan, pug }, lead, false)
srv:setMasterLooter(ann)
srv:tick(6)

local WATCH, SIGNET = 28528, 28525
local function full(p) return Server.full(p) end
local function chat(text, channel)
  for i = #srv.chat, 1, -1 do
    local m = srv.chat[i]
    if m.text:find(text, 1, true) and (not channel or m.channel == channel) then return m end
  end
end
local function frameFor(p, id)
  local frames = p.LR.UI.rollFrames()
  for i = #frames, 1, -1 do
    local f = frames[i]
    if f:IsShown() and f.copy and f.copy.id == id then return f end
  end
end

section("who runs the loot")
check("it's a party, not a raid", not lead.G.IsInRaid() and lead.G.IsInGroup())
check("everyone's addon finds the master looter by their place in the party",
  lead.LR.masterLooter() == full(ann) and bob.LR.masterLooter() == full(ann) and dan.LR.masterLooter() == full(ann))
check("the master looter finds themselves", ann.LR.masterLooter() == full(ann) and ann.LR.isMasterLooter())
check("so they may roll loot out", ann.LR.canRunLoot() and not dan.LR.canRunLoot())
check("messages go to the party", lead.LR.groupChannel() == "PARTY")

section("reserves")
local s = lead.LR.startSession("Karazhan", 1, false, false)
srv:tick(2)
bob.LR.reserve(bob.LR.current(), WATCH)
srv:tick(2)
check("Bob's reserve reaches the leader", #lead.LR.Session.reservesOf(s, full(bob)) == 1)
check("and the master looter", #ann.LR.Session.reservesOf(ann.LR.current(), full(bob)) == 1)
srv:whisper(pug, lead, "!lr " .. srv:link(SIGNET))
srv:tick(1)
check("Pug reserves by whisper", #lead.LR.Session.reservesOf(s, full(pug)) == 1)
srv:tick(2)

section("rolling it out")
srv:openLoot(ann, { { WATCH, 4 }, { SIGNET, 4 } })
srv:tick(0.5)
local Rolls = ann.LR.Rolls
local roll = Rolls.start(WATCH, { link = ann.G.GetLootSlotLink(1), slot = 1 })
srv:tick(0.5)
check("the master looter rolls out Bob's reserve", roll and roll.mode == "SR" and #roll.who == 1)
check("the party is told", chat("is soft reserved by Bob-Faerlina", "PARTY") ~= nil)
check("everyone with the addon gets a window", frameFor(bob, WATCH) and frameFor(dan, WATCH) and frameFor(lead, WATCH))
srv:willRoll(bob, 30)
bob.M.click(frameFor(bob, WATCH).dice)
srv:tick(3)
check("Bob rolls and it closes early", roll.state == "closed" and (ann.LR.Roll.result(roll)).p == full(bob))
check("the award goes through master loot", Rolls.award(full(bob)) and srv.given and srv.given[1].id == WATCH and srv.given[1].to == bob)
srv:tick(2)
check("the leader's list has it", s.won and s.won[1] and s.won[1].p == full(bob) and s.won[1].k == "SR")
check("and the party hears it", chat(" has won ", "PARTY") ~= nil and chat(" has won ", "PARTY").text:find("Bob", 1, true) ~= nil)
Rolls.dismiss()

section("a player without the addon rolls in chat")
roll = Rolls.start(SIGNET, { link = ann.G.GetLootSlotLink(2), slot = 2 })
srv:tick(0.5)
check("Pug's reserve: only he rolls", roll.mode == "SR" and #roll.who == 1)
srv:roll(pug, 1, 100, 12)
srv:tick(3)
check("his /roll counts, and it closes early", roll.state == "closed" and (ann.LR.Roll.result(roll)).p == full(pug))
Rolls.award(full(pug))
srv:tick(2)
check("it goes to him", srv.given[2] and srv.given[2].id == SIGNET and srv.given[2].to == pug)
check("every client's copy of the session agrees", #bob.LR.current().won == 2 and #dan.LR.current().won == 2)

section("no errors")
for _, p in ipairs({ lead, ann, bob, dan }) do check(p.name .. " had no errors", #p.M.errors == 0, p.M.errors[1]) end

print(("passed %d"):format(passed))
print(("errors %d"):format(failed))
os.exit(failed == 0 and 0 or 1)
