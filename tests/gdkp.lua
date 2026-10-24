-- A GDKP raid, every player's client side by side (tests/wow/server.lua), plus a pug without the addon:
-- items auctioned one after another, bids from roll windows, typed in raid chat and whispered, a bid at the
-- last moment, an item nobody bids on, the pot, the cut and the split, gold changing hands in trades, and
-- everyone told what they owe or are owed.
--   lua5.1 tests/gdkp.lua
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
local lead = srv:client({ name = "Lead", class = "PALADIN" })
local ann = srv:client({ name = "Ann", class = "PRIEST" })
local bob = srv:client({ name = "Bob", class = "MAGE", realm = "Faerlina" })
local dan = srv:client({ name = "Dan", class = "ROGUE" })
local pug = srv:player({ name = "Pug", class = "WARRIOR" })
srv:setGroup({ lead, ann, bob, dan, pug }, lead, true)
srv:setMasterLooter(lead)
srv:tick(6)

local WATCH, SIGNET, HANDWRAPS, BROOCH = 28528, 28525, 28507, 28530
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
local function frameFor(p, id)
  local frames = p.LR.UI.rollFrames()
  for i = #frames, 1, -1 do
    local f = frames[i]
    if f:IsShown() and f.copy and f.copy.id == id then return f end
  end
end
local function found(p, text, root) return #p.M.findText(text, true, root) > 0 end
local function clickText(p, text, root)
  for _, hit in ipairs(p.M.findText(text, true, root)) do
    if hit.clickable then return p.M.click(hit.clickable) end
  end
  error("nothing to click: " .. text, 2)
end
local function say(p, text) srv:chatMessage(p, text, "RAID") end
local Rolls = lead.LR.Rolls
local G = lead.LR.Gdkp

section("a GDKP raid")
local s = lead.LR.startSession("Karazhan", 2, true, false)
lead.LR.setHR(s, HANDWRAPS, "Ann", "she's our healer")
lead.LR.setGdkp(s, true)
srv:tick(2)
check("GDKP is on, for raiders too", s.gdkp and ann.LR.current().gdkp and ann.LR.current().gk.min == 100)
check("everyone in the group is in the split", #G.players(s) == 5)
check("nobody can reserve", not ann.LR.reserve(ann.LR.current(), WATCH))
srv:whisper(pug, lead, "!lr " .. srv:link(WATCH))
srv:tick(1)
check("players without the addon are told", whisperTo(pug, "auctions its loot for gold (GDKP)") ~= nil)
lead.LR.gdkpOption(s, "inc", 25)
lead.LR.gdkpPrice(s, BROOCH, 500)
srv:tick(1)
check("the leader changes the raise and an item's start", s.gk.inc == 25 and G.minFor(s, BROOCH) == 500 and ann.LR.current().gk.inc == 25)

section("auctioning everything, one after another")
srv:openLoot(lead, { { WATCH, 4 }, { SIGNET, 4 }, { HANDWRAPS, 4 }, { BROOCH, 4 } })
srv:tick(0.5)
local panel = lead.G.LootRulerLootPanel
check("the loot panel says each is auctioned, and from how much", found(lead, "Auction: bids from 100g", panel) and found(lead, "Auction: bids from 500g", panel)
  and found(lead, "Hard reserved for Ann", panel))
clickText(lead, "Auction them all", panel)
srv:tick(0.5)
local roll = Rolls.mine()
check("the first one is up", roll and roll.id == WATCH and roll.mode == "BID" and roll.state == "open" and #Rolls.queue == 3)
check("the raid is told how to bid", chat("Auction: ", "RAID_WARNING") and chat("Bids start at 100g, each at least 25g more than the last. Type your bid in raid chat (just the number).", "RAID_WARNING"))
local fa = frameFor(ann, WATCH)
check("Ann's window bids the least that counts, or a jump", fa and fa.dice:IsEnabled() and fa.dice.label:GetText() == "100g" and fa.coin.label:GetText() == "200g")
ann.M.click(fa.dice)
srv:tick(0.5)
check("clicking types the bid in raid chat", chat("100", "RAID") and chat("100", "RAID").from == full(ann))
check("and it counts", roll.top and roll.top.p == full(ann) and roll.top.n == 100)
check("Ann's window says she's highest, and won't bid against her", fa.status:GetText():find("You have the highest bid: 100g", 1, true) and not fa.dice:IsEnabled())
check("Bob's window has the next amounts", frameFor(bob, WATCH).dice.label:GetText() == "125g" and frameFor(bob, WATCH).status:GetText():find("Highest bid: Ann-Dreamscythe, 100g", 1, true))
say(pug, "150")
srv:tick(0.5)
check("Pug types a bid without the addon", roll.top.p == full(pug) and roll.top.n == 150 and frameFor(ann, WATCH).copy.top.n == 150)
say(bob, "160")
srv:tick(0.5)
check("too little: it doesn't count, and Bob is told", roll.top.p == full(pug) and whisperTo(bob, "The lowest bid now is 175g.") ~= nil)
say(dan, "gg nice")
srv:tick(0.3)
check("chat that isn't a bid is left alone", #roll.entries == 3)
srv:whisper(dan, lead, "!lr bid 200")
srv:tick(0.5)
check("Dan bids by whisper", roll.top.p == full(dan) and roll.top.n == 200 and whisperTo(dan, "Your bid of 200g") ~= nil)
srv:tick(roll.ends - lead.G.GetTime() - 2)
say(pug, "1.2k")
srv:tick(0.5)
check("a bid at the last moment gives everyone a few seconds more", roll.state == "open" and roll.top.n == 1200 and roll.ends - lead.G.GetTime() > 6)
srv:tick(12)
check("sold to the highest bid", roll.state == "awarded" and roll.winner == full(pug) and chat("Sold: ", "RAID") and chat("to Pug for 1,200g.", "RAID"))
check("given through master loot", srv.given and srv.given[#srv.given].id == WATCH and srv.given[#srv.given].to == pug)
check("and on the list of loot given out", s.won[#s.won].k == "BID" and s.won[#s.won].r == 1200 and s.won[#s.won].p == full(pug))
check("raiders' windows say who bought it", frameFor(ann, WATCH).status:GetText():find("Sold to Pug for 1,200g", 1, true))

srv:tick(4)
roll = Rolls.mine()
check("the next one starts on its own", roll and roll.id == SIGNET and roll.state == "open" and #Rolls.queue == 2)
srv:tick(25)
check("nobody bids: it isn't sold, and the next one starts", chat("Nobody bid on", "RAID") and Rolls.mine() and Rolls.mine().id == HANDWRAPS)
roll = Rolls.mine()
check("a hard reserved item isn't auctioned", roll.mode == "HR" and roll.state == "closed")
Rolls.award(full(ann))
srv:tick(4)
roll = Rolls.mine()
check("then the last one, from its own start", roll and roll.id == BROOCH and roll.min == 500)
say(ann, "450")
say(ann, "500")
srv:tick(25)
check("sold", roll.state == "awarded" and roll.winner == full(ann) and #Rolls.queue == 0)
check("the loot master's window says so", found(lead, "Sold to Ann for 500g.", lead.G.LootRulerMasterFrame))
srv:closeLoot(lead)

section("the pot")
local split = G.split(s)
check("the pot is what was sold", split.pot == 1700 and #G.sales(s) == 2)
check("10% to the organiser, the rest split five ways", split.cut == 170 and split.share == 306 and #split.players == 5)
check("Pug owes, Bob is owed", split.rows[full(pug)].owed == -894 and split.rows[full(bob)].owed == 306 and split.rows[full(ann)].owed == -194)
srv:whisper(pug, lead, "!lr pot")
srv:tick(1)
check("!lr pot tells Pug what he owes", whisperTo(pug, "GDKP: You bought 1,200g, your share is 306g, so you give Lead 894g.") ~= nil)

section("payouts in trades")
srv:openTrade(lead, pug)
srv:tick(0.5)
check("a trade with Pug: the organiser is told what he owes", lead.M.chat[#lead.M.chat]:find("Pug owes you 894g", 1, true))
srv:setTradeMoney(pug, 894 * 10000)
srv:tick(0.5)
srv:completeTrade(lead)
srv:tick(1)
check("the gold counts: Pug is settled", math.abs(G.split(s).rows[full(pug)].owed) < 0.01 and ann.LR.current().gk.paid[full(pug)] == 894)
srv:openTrade(bob, lead)
srv:tick(0.5)
check("a trade with Bob: what to give him", lead.M.chat[#lead.M.chat]:find("put 306g in the trade for Bob", 1, true))
srv:setTradeMoney(lead, 306 * 10000)
srv:tick(0.5)
srv:completeTrade(lead)
srv:tick(1)
check("Bob is settled", math.abs(G.split(s).rows[full(bob)].owed) < 0.01)
lead.LR.gdkpPaid(s, full(ann), 194)
srv:tick(1)
check("marked settled by hand (gold sent by mail)", math.abs(G.split(s).rows[full(ann)].owed) < 0.01)

section("telling everyone")
check("the pot in raid chat", lead.LR.Pot.post(s))
srv:tick(1)
check("one short line", chat("GDKP pot: 1,700g from 2 items. Lead's cut: 170g (10%). Split 5 ways: 306g each.", "RAID") ~= nil)
check("everyone whispered their payout", lead.LR.Pot.whisperAll(s) == 4)
srv:tick(2)
check("settled players hear so", whisperTo(pug, "you're all settled") and whisperTo(dan, "Lead gives you 306g"))

section("ending")
lead.LR.endSession(s)
srv:tick(2)
check("ended", lead.LR.current() == nil and ann.LR.current() == nil)

section("no errors")
local longest = 0
for _, m in ipairs(srv.chat) do longest = math.max(longest, #m.text) end
check("every chat line fits", longest <= 255, longest)
for _, p in ipairs({ lead, ann, bob, dan }) do
  check(p.name .. ": no Lua errors", #p.M.errors == 0, table.concat(p.M.errors, " | "))
end

print(("passed %d"):format(passed))
print(("errors %d"):format(failed))
os.exit(failed == 0 and 0 or 1)
