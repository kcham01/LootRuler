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
local function copyOf(p, id)
  for i = #p.LR.Rolls.order, 1, -1 do local c = p.LR.Rolls.seen[p.LR.Rolls.order[i]] if c and c.id == id then return c end end
end
local function noticed(p, text) for _, n in ipairs(p.M.notices or {}) do if n:find(text, 1, true) then return true end end return false end
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
check("raiders see what's coming up next", copyOf(ann, WATCH) and copyOf(ann, WATCH).upNext and copyOf(ann, WATCH).upNext[1] == SIGNET and copyOf(ann, WATCH).upNext.n == 3)
check("in their window", frameFor(ann, WATCH).note:GetText():find("Next:", 1, true) ~= nil and frameFor(ann, WATCH).note:GetText():find("Brooch of Unquenchable Fury", 1, true) ~= nil, frameFor(ann, WATCH).note:GetText())
local fa = frameFor(ann, WATCH)
check("Ann's window: where bids start, big, and one button that bids the least that counts", fa and fa.bid:IsShown() and fa.bid:IsEnabled()
  and fa.bid:GetText() == "Bid 100g" and fa.price:GetText() == "100g" and not fa.dice:IsShown() and fa.extras[1].text:GetText() == "Bid an amount"
  and fa.extras[2].text:GetText() == "Max bid")
ann.M.click(fa.bid)
srv:tick(0.5)
check("clicking types the bid in raid chat", chat("100", "RAID") and chat("100", "RAID").from == full(ann))
check("and it counts", roll.top and roll.top.p == full(ann) and roll.top.n == 100)
check("Ann's window says she's highest, and won't bid against her", fa.status:GetText():find("You have the highest bid.", 1, true) and fa.priceBy:GetText() == "highest, by you" and not fa.bid:IsEnabled())
check("Bob's window has the next amount, and who's highest", frameFor(bob, WATCH).bid:GetText() == "Bid 125g" and frameFor(bob, WATCH).price:GetText() == "100g"
  and frameFor(bob, WATCH).priceBy:GetText():find("highest, by", 1, true) and frameFor(bob, WATCH).priceBy:GetText():find("Ann", 1, true))
local noticesBefore = #ann.M.notices
say(pug, "150")
srv:tick(0.5)
check("Pug types a bid without the addon", roll.top.p == full(pug) and roll.top.n == 150 and frameFor(ann, WATCH).copy.top.n == 150)
check("Ann had the highest bid: she's told she's outbid, and by how much to win it back", #ann.M.notices == noticesBefore + 1
  and ann.M.notices[#ann.M.notices]:find("Outbid on [Moroes' Lucky Pocket Watch]: Pug bid 150g. Bid 175g or more", 1, true) ~= nil, ann.M.notices[#ann.M.notices])
check("nobody else is", not noticed(bob, "Outbid"))
say(bob, "160")
srv:tick(0.5)
check("too little: it doesn't count, and Bob is told", roll.top.p == full(pug) and whisperTo(bob, "The lowest bid now is 175g.") ~= nil)
say(dan, "gg nice")
srv:tick(0.3)
check("chat that isn't a bid is left alone", #roll.entries == 3)
srv:whisper(dan, lead, "!lr bid 200")
srv:tick(0.5)
check("Dan bids by whisper", roll.top.p == full(dan) and roll.top.n == 200 and whisperTo(dan, "Your bid of 200g") ~= nil)
srv:tick(roll.ends - lead.G.GetTime() - 9.5)
check("a final call with 10 seconds left, with the highest bid", chat("Final call for ", "RAID_WARNING") and chat(": 200g by Dan. 10 seconds.", "RAID_WARNING"))
srv:tick(roll.ends - lead.G.GetTime() - 2)
say(pug, "1.2k")
srv:tick(0.5)
check("a bid at the last moment gives everyone a few seconds more", roll.state == "open" and roll.top.n == 1200 and roll.ends - lead.G.GetTime() > 6)
srv:tick(12)
check("sold to the highest bid", roll.state == "awarded" and roll.winner == full(pug) and chat("Sold: ", "RAID") and chat("to Pug for 1,200g.", "RAID"))
check("with the pot so far", chat("to Pug for 1,200g. Pot: 1,200g so far.", "RAID") ~= nil)
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
srv:whisper(pug, lead, "!lr")
srv:tick(1)
check("!lr on its own says how bidding works", whisperTo(pug, "auctions its loot for gold (GDKP). When an item is up, type your bid in raid chat") ~= nil)

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
-- the organiser enchants Pug's item for 10g: that's for the enchant, not the pot
local item = srv:giveItem(pug, 28477, 1)
srv:openTrade(lead, pug)
srv:tick(0.5)
srv:tradeToEnchant(pug, item)
srv:setTradeMoney(pug, 10 * 10000)
srv:enchantInTrade(lead, "Enchant Bracer - Superior Healing")
srv:tick(0.5)
srv:completeTrade(lead)
srv:tick(1)
check("gold paid for an enchant doesn't count towards the pot", math.abs(G.split(s).rows[full(pug)].owed) < 0.01 and lead.LR.current().gk.paid[full(pug)] == 894)
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

section("changing a sale, and starting bids in and out")
local saleAt
for i, w in ipairs(s.won) do if w.k == "BID" and w.p == full(pug) then saleAt = i end end
check("a sale's price can be changed: the pot changes with it", lead.LR.gdkpSalePrice(s, saleAt, 1100) and G.pot(s) == 1600)
srv:tick(1)
check("raiders' copies agree", G.pot(ann.LR.current()) == 1600)
check("a raider can't change it", not ann.LR.gdkpSalePrice(ann.LR.current(), saleAt, 1))
lead.LR.gdkpSalePrice(s, saleAt, 1200)
srv:tick(1)
check("bringing in starting bids", lead.LR.gdkpPrices(s, (G.parsePrices("28525: 800\n28528,1,500g"))) and G.minFor(s, 28525) == 800 and G.minFor(s, 28528) == 1500)
srv:tick(1)
check("raiders' copies have them", G.minFor(ann.LR.current(), 28525) == 800)
lead.LR.gdkpPrice(s, 28525, nil) lead.LR.gdkpPrice(s, 28528, nil)

section("payouts by mail")
local queue = lead.LR.Pot.toMail(s)
check("who's still owed, the most first", #queue == 1 and queue[1][1] == full(dan) and queue[1][2] == 306)
check("not before a mailbox is open", not lead.LR.Pot.fillMail(s, full(dan), 306))
lead.M.openMail()
check("at the mailbox: the mail is filled in", lead.LR.Pot.fillMail(s, full(dan), 306) and lead.G.SendMailNameEditBox:GetText() == "Dan"
  and lead.G.SendMailSubjectEditBox:GetText() == "GDKP payout: Karazhan" and lead.G.GetSendMailMoney() == 306 * 10000)
check("nothing is sent until the organiser presses Send", #lead.M.mailed == 0)
lead.G.SendMail(lead.G.SendMailNameEditBox:GetText(), lead.G.SendMailSubjectEditBox:GetText(), "")
srv:tick(1)
check("once it's sent, Dan's gold counts as paid", #lead.M.mailed == 1 and math.abs(G.split(s).rows[full(dan)].owed) < 0.01 and #lead.LR.Pot.toMail(s) == 0)
lead.G.SendMail("Ann", "hello", "")
srv:tick(1)
check("an ordinary mail with no gold counts for nothing", math.abs(G.split(s).rows[full(ann)].owed) < 0.01)
lead.LR.gdkpPaid(s, full(dan), 306)            -- (back as it was, for what follows)
srv:tick(1)

section("tanks and healers")
check("only the leader sets role cuts", not ann.LR.gdkpRoleCut(ann.LR.current(), "tank", 5))
lead.LR.gdkpRoleCut(s, "tank", 2)
lead.LR.gdkpRole(s, full(bob), "tank")
srv:tick(1)
local rsplit = G.split(s)
check("Bob tanks: 2% of the pot on top of his share", rsplit.rows[full(bob)].roleCut == 34 and rsplit.share == 299 and ann.LR.current().gk.role[full(bob)] == "tank")
srv:whisper(bob, lead, "!lr pot")
srv:tick(1)
check("he's told", whisperTo(bob, "Your share is 333g (with a 34g tank cut), you've had 306g, so Lead gives you 27g.") ~= nil)
check("the raid's summary says so", lead.LR.Pot.summary(s)[1]:find("tank and healer cuts 34g", 1, true) ~= nil)
lead.LR.gdkpRoleCut(s, "healer", 10)
lead.LR.gdkpRole(s, full(ann), "healer")
lead.LR.gdkpBonus(s, full(lead), 1500)
srv:tick(1)
rsplit = G.split(s)
local paid = rsplit.cut
for _, row in pairs(rsplit.rows) do paid = paid + (row.roleCut or 0) end
for _, row in pairs(rsplit.rows) do paid = paid + (row.bonus or 0) end
-- 1,700g: 170g to the organiser and a 1,500g bonus leave 30g for cuts of 170g (healer) and 34g (tank)
check("cuts that would come to more than the pot are cut down to fit", rsplit.rows[full(ann)].roleCut == 25 and rsplit.rows[full(bob)].roleCut == 5
  and paid <= rsplit.pot and rsplit.share == 0, rsplit.rows[full(ann)].roleCut .. " " .. rsplit.rows[full(bob)].roleCut .. " " .. paid)
lead.LR.gdkpBonus(s, full(lead), 0)
lead.LR.gdkpRole(s, full(ann), nil)
lead.LR.gdkpRoleCut(s, "healer", 0)
srv:tick(1)
lead.LR.gdkpRole(s, full(bob), nil)
lead.LR.gdkpRoleCut(s, "tank", 0)
srv:tick(1)

section("pot rules of my own")
check("only the leader adds a rule", not ann.LR.gdkpAddRule(ann.LR.current(), "Mine"))
lead.LR.gdkpAddRule(s, "Raid leader")
lead.LR.gdkpEditRule(s, 1, { pct = 5 })
lead.LR.gdkpRuleTo(s, 1, full(lead), true)
lead.LR.gdkpAddRule(s, "Pumper")
lead.LR.gdkpEditRule(s, 2, { g = 100 })
lead.LR.gdkpRuleTo(s, 2, full(bob), true)
srv:tick(1)
local rsplit2 = G.split(s)
-- 1,700g: 170g cut, 85g raid leader, 100g pumper; 1,345g split five ways
check("the rules come out of the pot before the split", rsplit2.rules == 185 and rsplit2.share == 269 and rsplit2.rows[full(bob)].ruleCut == 100)
check("raiders' copies have them", ann.LR.current().gk.rules and #ann.LR.current().gk.rules == 2 and G.split(ann.LR.current()).share == 269)
srv:whisper(bob, lead, "!lr pot")
srv:tick(1)
check("Bob is told his share includes it", whisperTo(bob, "Your share is 369g (with 100g for Pumper), you've had 306g, so Lead gives you 63g.") ~= nil)
check("the raid's summary names each rule", lead.LR.Pot.summary(s)[1]:find("Raid leader 85g, Pumper 100g. Split 5 ways: 269g each.", 1, true) ~= nil, lead.LR.Pot.summary(s)[1])
lead.LR.gdkpRemoveRule(s, 2)
lead.LR.gdkpRemoveRule(s, 1)
srv:tick(1)
check("taken away, the split is as it was", G.split(s).share == 306 and ann.LR.current().gk.rules == nil)

section("bookkeeping")
local led = G.ledger(s)
local kinds = {}
for _, e in ipairs(led) do kinds[e.kind] = (kinds[e.kind] or 0) + 1 end
check("the ledger has the sales, the trades and the mail", kinds.sale == 2 and (kinds.trade or 0) >= 2 and kinds.mail == 1, (kinds.trade or 0) .. " " .. (kinds.mail or 0))
lead.LR.gdkpAddGold(s, 100, "vendor greys")
srv:tick(1)
check("gold put in by hand: the pot and the split grow, for raiders too", G.pot(s) == 1800 and ann.LR.current().gk.adds and G.pot(ann.LR.current()) == 1800)
check("the raid's summary says so", lead.LR.Pot.summary(s)[1]:find("from 2 items (100g added by hand)", 1, true) ~= nil, lead.LR.Pot.summary(s)[1])
lead.LR.gdkpFixedAll(s, lead.LR.Prio.parseCounts("Dan,500", G.MAX_GOLD))
srv:tick(1)
srv:whisper(dan, lead, "!lr pot")
srv:tick(1)
check("a payout set by hand: Dan is told it", whisperTo(dan, "Your payout is 500g (set by Lead)") ~= nil)
check("everyone else splits the rest", G.split(s).sharers == 4 and G.split(s).rows[full(dan)].gets == 500)
lead.LR.gdkpFixedAll(s, {})
lead.LR.gdkpRemoveAdd(s, 1)
srv:tick(1)
check("back as it was", G.pot(s) == 1700 and G.split(s).share == 306 and not s.gk.fixed)
check("back to an even split", G.split(s).share == 306)

section("bids that must start with \"bid\"")
lead.LR.gdkpStrict(s, true)
srv:tick(1)
roll = Rolls.start(SIGNET, {})
srv:tick(0.5)
check("the raid is told to type \"bid\"", chat("Type your bid in raid chat (\"bid 100\")", "RAID_WARNING") ~= nil)
say(pug, "500")
srv:tick(0.5)
check("just a number doesn't count", roll.top == nil)
say(pug, "bid 300")
srv:tick(0.5)
check("\"bid 300\" does", roll.top and roll.top.n == 300)
local fd = frameFor(dan, SIGNET)
check("the window says so", fd and fd.status:GetText():find("type \"bid\" and an amount", 1, true))
dan.M.click(fd.bid)
srv:tick(0.5)
check("and its button types \"bid\" too", chat("bid 325", "RAID") and roll.top.p == full(dan) and roll.top.n == 325)
Rolls.cancel()
srv:tick(1)

section("bids not taken")
lead.LR.gdkpStrict(s, false)
srv:tick(1)
;(function()                                 -- (its own function: locals)
  local r = Rolls.start(28477, {})                -- (Harbinger Bands)
  srv:tick(0.5)
  say(ann, "200")
  say(pug, "500")
  srv:tick(0.5)
  check("Pug bids highest", r.top and r.top.p == full(pug) and r.top.n == 500, r.mode .. " " .. tostring(r.min) .. " " .. tostring(r.top and r.top.p))
  check("only the organiser can stop taking someone's bids", not ann.LR.Rolls.noBidsFrom(full(pug), true))
  local before = #srv.chat
  check("the organiser stops taking Pug's bids", Rolls.noBidsFrom(full(pug), true))
  srv:tick(1)
  check("his bid goes: Ann's is the highest again", r.top and r.top.p == full(ann) and r.top.n == 200)
  local told = 0
  for i = before + 1, #srv.chat do if srv.chat[i].text:find("Pug's bids aren't taken for the rest of tonight.", 1, true) then told = told + 1 end end
  check("the raid is told, once", told == 1)
  local fd = frameFor(dan, 28477)
  check("raiders' windows follow", fd and fd.copy.top and fd.copy.top.p == full(ann) and fd.copy.nb and fd.copy.nb[lead.LR.Roll.key(full(pug))])
  say(pug, "900")
  srv:whisper(pug, lead, "!lr bid 950")
  srv:tick(0.5)
  check("his bids in raid chat or by whisper don't count", r.top.p == full(ann) and r.top.n == 200)
  check("it's kept for the GDKP, and shared", s.gk.nb and s.gk.nb[1] == full(pug) and dan.LR.current().gk.nb and dan.LR.current().gk.nb[1] == full(pug))
  Rolls.cancel()
  srv:tick(1)
  local r2 = Rolls.start(SIGNET, {})
  srv:tick(0.5)
  say(pug, "300")
  srv:tick(0.5)
  check("the next auction leaves him out too", r2.top == nil)
  check("taken again", Rolls.noBidsFrom(full(pug), false) and chat("Pug's bids count again.", "RAID") ~= nil)
  srv:tick(1)
  say(pug, "300")
  srv:tick(0.5)
  check("his bids count again", r2.top and r2.top.p == full(pug))
  Rolls.cancel()
  srv:tick(1)
end)()

section("max bids")
local ROYAL = 28529
roll = Rolls.start(ROYAL, {})
srv:tick(0.5)
check("the raid is told how to bid up to a max", chat("To bid up to a max, whisper Lead \"!lr max 800\".", "RAID_WARNING") ~= nil)
ann.G.SlashCmdList.LOOTRULER("max 800")
srv:tick(1)
check("Ann's max: LootRuler opens the bidding for her, at the start", roll.top and roll.top.p == full(ann) and roll.top.n == 100 and roll.top.auto)
check("she's told, and the raid hears where it is", whisperTo(ann, "Your max bid of 800g") and chat("Highest bid: Ann, 100g (bid for them by their max bid)", "RAID"))
check("nobody else sees her max", (frameFor(bob, ROYAL).copy.myMax == nil) and frameFor(ann, ROYAL).copy.myMax == 800
  and frameFor(bob, ROYAL).copy.top.n == 100)
say(pug, "300")
srv:tick(1)
check("Pug bids 300: her max answers, just above", roll.top.p == full(ann) and roll.top.n == 325)
srv:whisper(dan, lead, "!lr max 1000")
srv:tick(1)
check("Dan's higher max (by whisper) beats hers, just above it", roll.top.p == full(dan) and roll.top.n == 825 and whisperTo(dan, "Your max bid of 1,000g is in"))
srv:whisper(ann, lead, "!lr max 700")
srv:tick(1)
check("a max can't go down, or below the lowest bid", whisperTo(ann, "at least the lowest bid now, 850g") ~= nil)
srv:whisper(bob, lead, "!lr bid 900")
srv:tick(1)
check("Bob bids under Dan's max: it answers", roll.top.p == full(dan) and roll.top.n == 925)
check("and Bob's whisper says a max beat him", whisperTo(bob, "Someone's max bid beat yours: the highest is 925g.") ~= nil)
say(bob, "1000")
srv:tick(1)
check("Bob bids over it: Bob is highest", roll.top.p == full(bob) and roll.top.n == 1000)
local function leadSaid(text) for _, l in ipairs(lead.M.chat) do if l:find(text, 1, true) then return true end end return false end
lead.G.SlashCmdList.LOOTRULER("max 900")
srv:tick(1)
check("the loot master's own max goes in on their own addon; too low is refused", leadSaid("at least the lowest bid now")
  and Rolls.openAuction().myMax == nil and roll.top.p == full(bob))
lead.G.SlashCmdList.LOOTRULER("max 2000")
srv:tick(1)
check("a high enough one bids for them", leadSaid("your max bid of 2,000g is in.") and roll.top.p == full(lead) and roll.top.n == 1025
  and Rolls.openAuction().myMax == 2000)
Rolls.cancel()
srv:tick(1)

section("bidding ahead")
lead.LR.heardFrom("Oldie-Dreamscythe", "1.0.0-beta", 1)
check("what another addon can do: an older one can take a session, not bids ahead", lead.LR.canLead("Oldie") and not lead.LR.hasFeature("Oldie", lead.LR.FEATURE_AHEAD)
  and lead.LR.hasFeature(full(ann), lead.LR.FEATURE_AHEAD))
local potBefore = G.pot(s)
Rolls.enqueue({ { id = SIGNET, link = srv:link(SIGNET) }, { id = ROYAL, link = srv:link(ROYAL) } })
srv:tick(1)
roll = Rolls.mine()
check("an auction with another to come", roll and roll.id == SIGNET and #Rolls.queue == 1)
local fa2 = frameFor(ann, SIGNET)
check("raiders' windows offer to bid ahead, under bidding an amount and a max", fa2 and fa2.extras[3]:IsShown() and fa2.extras[3].text:GetText() == "Bid ahead"
  and fa2.extras[1].text:GetText() == "Bid an amount")
check("Ann bids ahead from her window", ann.LR.Rolls.bidAhead(copyOf(ann, SIGNET), ROYAL, 900))
srv:tick(1)
check("the loot master's addon has it, and she's told", Rolls.ahead[ROYAL] and Rolls.ahead[ROYAL][lead.LR.Roll.key(full(ann))].g == 900
  and whisperTo(ann, "Your bid ahead of up to 900g on [Royal Cloak of Arathi Kings] is in") ~= nil)
check("her window counts it", frameFor(ann, SIGNET).extras[3].text:GetText() == "Bid ahead (1)")
srv:whisper(pug, lead, "!lr bid 700 " .. srv:link(ROYAL))
srv:tick(1)
check("Pug bids ahead by whisper", Rolls.aheadCount(ROYAL) == 2 and whisperTo(pug, "Your bid ahead of up to 700g on") ~= nil)
srv:whisper(pug, lead, "!lr bid 0 " .. srv:link(ROYAL))
srv:tick(1)
check("0 takes it back", Rolls.aheadCount(ROYAL) == 1 and whisperTo(pug, "is taken back.") ~= nil)
srv:whisper(pug, lead, "!lr max 700 " .. srv:link(ROYAL))
srv:whisper(dan, lead, "!lr bid 1 " .. srv:link(ROYAL))
srv:whisper(bob, lead, "!lr bid 300 " .. srv:link(BROOCH))
srv:tick(1)
check("too little isn't taken", whisperTo(dan, "start at") ~= nil and Rolls.aheadCount(ROYAL) == 2)
check("nor an item that isn't coming up", whisperTo(bob, "That item isn't coming up: bid when it's auctioned.") ~= nil)
check("the loot master sees how many", found(lead, "2 bids placed ahead.", lead.G.LootRulerMasterFrame))
Rolls.cancel()
srv:tick(1)
Rolls.dismiss()
srv:tick(1)
roll = Rolls.mine()
-- (Ann's, the first in, opens the bidding; Pug's 700 can't beat her 900, so she holds at 700, as max bids do)
check("when it comes up, the bids ahead bid, as little as it takes", roll and roll.id == ROYAL and roll.top and roll.top.p == full(ann)
  and roll.top.n == 700, roll and roll.top and (roll.top.p .. " " .. roll.top.n))
check("and Ann's window knows her max", copyOf(ann, ROYAL) and copyOf(ann, ROYAL).myMax == 900 and ann.LR.Rolls.myAhead[ROYAL] == nil)
Rolls.cancel()
srv:tick(1)
Rolls.dismiss()
Rolls.clearQueue()
check("nothing sold: the pot is as it was", G.pot(s) == potBefore)

section("several auctions at once")
local Bt = lead.LR.Batch
local function reads(text, n, g, strict) local a, b = Bt.parse(text, strict) return a == n and b == g end
check("reading a bid with an item's number", reads("#2 300", 2, 300) and reads("2: 1.5k", 2, 1500) and reads("300 on 2", 2, 300)
  and reads("bid 300 for #3", 3, 300) and reads("bid #1 250g", 1, 250))
check("and what isn't one", Bt.parse("300") == nil and Bt.parse("#9 300", false, 3) == nil and Bt.parse("#2 lots") == nil and Bt.parse("#2 300", true) == nil
  and reads("bid #2 300", 2, 300, true))
local potBatch, wonBefore = G.pot(s), #s.won
srv:openLoot(lead, { { SIGNET, 4 }, { BROOCH, 4 }, { WATCH, 4 } })
srv:tick(0.5)
srv.zLinks = {}                  -- (each batch message the loot master sends: whether it carried the items' links)
do
  local addonMessage = srv.addonMessage
  srv.addonMessage = function(self, from, prefix, text, channel, target)
    local m = from == lead and channel == "RAID" and lead.LR.Net.decode(text)
    if m and m.t == "Z" then srv.zLinks[#srv.zLinks + 1] = m.it[1].l ~= nil end
    return addonMessage(self, from, prefix, text, channel, target)
  end
  srv.restoreAddonMessage = function() srv.addonMessage = addonMessage end
end
local batch = Bt.start(Bt.candidates(), 30)
srv:tick(1)
check("three items up at once, from the loot window", batch and #batch.items == 3 and batch.items[2].id == BROOCH and batch.items[2].min == 500)
check("the raid hears each with its number, and how to bid", chat("Auction of 3 items: #1 ", "RAID_WARNING") and chat("Type the item's number and your bid in raid chat: \"#1 ", "RAID_WARNING"))
check("raiders get a window with all three", ann.LR.Batch.open() and #ann.LR.Batch.open().items == 3 and ann.G.LootRulerBatchFrame and ann.G.LootRulerBatchFrame:IsShown())
check("no single roll while it's on", not Rolls.start(28529, {}))
say(pug, "#1 300")
srv:tick(0.5)
check("Pug bids by number in raid chat (no addon)", batch.items[1].top and batch.items[1].top.p == full(pug) and batch.items[1].top.n == 300)
srv:whisper(bob, lead, "!lr max #2 800")
srv:tick(1)
check("Bob sets a max on #2 by whisper; it opens the bidding for him", whisperTo(bob, "Your max bid of 800g on #2 is in") and batch.items[2].top and batch.items[2].top.p == full(bob))
say(dan, "550 on 2")
srv:tick(1)
check("Dan bids on #2: Bob's max answers", batch.items[2].top.p == full(bob) and batch.items[2].top.n == 575)
srv:whisper(dan, lead, "!lr bid #1 10")
srv:tick(1)
check("too little: Dan is told the lowest", whisperTo(dan, "The lowest bid on #1 now is") ~= nil)
local acopy = ann.LR.Batch.open()
check("Ann's window shows who's highest", acopy.items[1].top and acopy.items[1].top.p == full(pug) and acopy.items[2].top.n == 575)
srv.restoreAddonMessage()
check("the batch went out several times, with the items' links only in the first", #srv.zLinks >= 3 and srv.zLinks[1] == true
  and srv.zLinks[2] == false and srv.zLinks[#srv.zLinks] == false, table.concat(lead.LR.U.map(srv.zLinks, tostring), ","))
check("and raiders' windows keep the links", acopy.items[2].link and acopy.items[2].link:find("Hitem:" .. BROOCH, 1, true) ~= nil)
ann.LR.Batch.myMax(acopy, 1, 50)
srv:tick(1)
check("a max from her window goes to the loot master's addon, which answers", whisperTo(ann, "A max bid on #1 has to be at least the lowest bid now") ~= nil)
local endsWas = batch.ends
check("+10 sec gives everyone more time", Bt.extend(10) and batch.ends >= endsWas + 10)
check("the auction window's bar runs while it's on", ann.G.LootRulerBatchFrame._scripts.OnUpdate ~= nil)
srv:tick(1)
check("and the raid hears it", chat("10 more seconds to bid in the auction.", "RAID") ~= nil)
ann.LR.Batch.bid(acopy, 1, 325)
srv:tick(1)
check("her window's button types the bid in raid chat", chat("#1 325", "RAID") and batch.items[1].top.p == full(ann))
check("Pug, outbid, would be told if he had the addon; Ann's copy knows it's hers", acopy.items[1].top.p == full(ann))
srv:tick(batch.ends - lead.G.GetTime() - 2)
say(pug, "#1 400")
srv:tick(0.5)
check("a bid at the last moment gives everyone a few seconds more", batch.state == "open" and batch.ends - lead.G.GetTime() > 6)
srv:tick(12)
check("it ends: the items with bids are sold", batch.state == "closed" and #s.won == wonBefore + 2 and s.won[#s.won].k == "BID")
check("each handed out through master loot", (function()
  local got = {}
  for _, g in ipairs(srv.given) do got[g.id] = g.to end
  return got[SIGNET] == pug and got[BROOCH] == bob
end)())
check("the raid hears each sale, and what didn't sell", chat("to Pug for 400g.", "RAID") and chat("to Bob-Faerlina for 575g.", "RAID") and chat("Nobody bid on #3 ", "RAID"))
check("raiders' windows say so", ann.LR.Batch.seen[batch.k].state == "closed" and ann.LR.Batch.seen[batch.k].items[2].top.p == full(bob))
srv:tick(0.2)
check("and their bars stop: nothing runs every frame", ann.G.LootRulerBatchFrame:IsShown() and ann.G.LootRulerBatchFrame._scripts.OnUpdate == nil
  and lead.G.LootRulerBatchFrame._scripts.OnUpdate == nil)
check("the pot has both", G.pot(s) == potBatch + 975)
srv:closeLoot(lead)
srv:tick(5)

-- a busy moment: the loot master's sending is backed up, and bids come in fast
do
  srv:openLoot(lead, { { HANDWRAPS, 4 }, { WATCH, 4 } })
  srv:tick(0.5)
  local busy = Bt.start(Bt.candidates(), 60)
  srv:tick(3)
  local zs, parts = 0, {}
  local real = srv.addonMessage
  srv.addonMessage = function(self, from, prefix, text, channel, target)
    if from == lead and prefix == lead.LR.PREFIX then
      local c, rest = text:match("^([\001-\003])(.*)$")
      local whole
      if c == "\001" then parts[channel] = { rest } elseif c == "\002" then table.insert(parts[channel], rest)
      elseif c == "\003" then table.insert(parts[channel], rest) whole = table.concat(parts[channel]) else whole = text end
      local msg = whole and lead.LR.Net.decode(whole)
      if msg and msg.t == "Z" then zs = zs + 1 end
    end
    return real(self, from, prefix, text, channel, target)
  end
  local seed = 5
  for _ = 1, 20 do
    local pad = {}
    for k = 1, 400 do seed = (seed * 1103515245 + 12345) % 2147483648 pad[k] = string.char(33 + seed % 90) end
    lead.LR.Net.send({ t = "ZZ", pad = table.concat(pad) }, "RAID")      -- (a kind nobody knows: ignored)
  end
  for i = 1, 10 do
    say(i % 2 == 0 and pug or bob, ("#1 %d"):format(100 + i * 50))
    srv:tick(0.35)
  end
  srv:tick(20)
  srv.addonMessage = real
  check("ten fast bids while the loot master's sending is backed up: fewer updates of the batch go out", zs > 0 and zs < 10, zs)
  local acopy2 = ann.LR.Batch.seen[busy.k]
  check("and raiders end up with the newest bids", acopy2 and acopy2.items[1].top and acopy2.items[1].top.n == 600 and acopy2.items[1].top.p == busy.items[1].top.p)
  Bt.cancel()
  srv:tick(2)
  srv:closeLoot(lead)
  srv:tick(2)
end
for i = #s.won, wonBefore + 1, -1 do lead.LR.unaward(s, i) end
srv:tick(10)
check("(taken back, for what follows)", G.pot(s) == potBatch)

section("ending")
lead.LR.endSession(s)
srv:tick(2)
check("ended", lead.LR.current() == nil and ann.LR.current() == nil)

section("past raids")
local H = lead.LR.History
local past = H.all()[1]
check("the raid is kept, with its sales", past and past.id == s.id and past.archived and #G.sales(past) == 2 and G.pot(past) == 1700)
check("raiders keep it too", ann.LR.History.all()[1] and ann.LR.History.all()[1].id == s.id)
check("Dan is still owed his share", G.split(past).rows[full(dan)].owed == 306 and H.owing(full(dan)) == past)
srv:whisper(dan, lead, "!lr pot")
srv:tick(1)
check("!lr pot still answers after the raid", whisperTo(dan, "Lead gives you 306g") ~= nil)
srv:openTrade(lead, dan)
srv:tick(0.5)
check("a trade with Dan: what to give him, from which raid", lead.M.chat[#lead.M.chat]:find("put 306g in the trade for Dan (their payout (from Karazhan", 1, true), lead.M.chat[#lead.M.chat])
srv:setTradeMoney(lead, 306 * 10000)
srv:tick(0.5)
srv:completeTrade(lead)
srv:tick(1)
check("the gold counts on the past raid", math.abs(G.split(past).rows[full(dan)].owed) < 0.01 and H.owing(full(dan)) == nil)

section("what items usually sell for")
local s2 = lead.LR.startSession("Karazhan", 2, true, false)
lead.LR.setGdkp(s2, true)
srv:tick(1)
check("a past sale's price", H.usualPrice(WATCH, s2) == 1200 and H.usualPrice(SIGNET, s2) == nil)
srv:openLoot(lead, { { WATCH, 4 }, { SIGNET, 4 } })
srv:tick(0.5)
check("the loot panel says what it sold for before", found(lead, "(sold for 1,200g before)", lead.G.LootRulerLootPanel))
srv:closeLoot(lead)
lead.LR.endSession(s2)
srv:tick(1)
check("a raid that gave nothing out isn't kept", H.all()[1].id == s.id)

section("saved past raids are checked")
local old = srv:client({ name = "Old", class = "WARRIOR" }, { history = { { archived = true, ended = 5, id = "x" }, "junk", past } })
srv:tick(1)
check("broken ones are thrown away", #old.LR.History.all() == 1 and old.LR.History.all()[1].id == s.id)

section("who's in the pot goes out slowly")
do
  local cs = lead.LR.current()
  if cs and lead.LR.isLeader(cs) then lead.LR.endSession(cs) srv:tick(2) end
  local gs = lead.LR.startSession("Karazhan", 2, true, false)
  lead.LR.setGdkp(gs, true)
  srv:tick(3)
  local late = srv:player({ name = "Latecomer", class = "PRIEST" })
  table.insert(srv.group.members, late)
  late.inGroup = true
  srv:rosterChanged()
  srv:tick(2)
  check("someone joins: they're in the pot on the organiser's screen at once", gs.gk.seen[full(late)] == true)
  check("raiders hear it a little later, not at once", not ann.LR.session(gs.id).gk.seen[full(late)])
  srv:tick(10)
  check("within a few seconds", ann.LR.session(gs.id).gk.seen[full(late)] == true)
  srv:leaveGroup(late)
  lead.LR.endSession(gs)
  srv:tick(2)
end

section("no errors")
local longest = 0
for _, m in ipairs(srv.chat) do longest = math.max(longest, #m.text) end
check("every chat line fits", longest <= 255, longest)

section("odd values (found by tools/fuzz.lua)")
do
  local LS = lead.LR.Session
  local plain = LS.new(full(lead), "Karazhan", 2, true, 100)
  check("GDKP changes on a session that isn't GDKP are refused, not errors", G.setOut(plain, "Ann", true, 101) == false
    and G.setBonus(plain, "Ann", 5, 101) == false and G.setRole(plain, "Ann", "tank", 101) == false and G.paid(plain, "Ann", 5, 101) == false)
  local g = LS.new(full(lead), "Karazhan", 2, true, 100)
  G.set(g, true, 101)
  check("a blank name is refused everywhere", G.setOut(g, "", true, 102) == false and G.setBonus(g, "", 5, 102) == false
    and G.setRole(g, "", "tank", 102) == false and G.setFixed(g, "", 5, 102) == false and G.paid(g, "", 5, 102) == false)
  check("a payment that isn't a number of gold is refused", G.paid(g, "Ann", 0 / 0, 102) == false and G.paid(g, "Ann", math.huge, 102) == false)
  check("and the session is still valid", LS.valid(lead.LR.U.copy(g)))
  -- times the game can't show come out blank, not as an error
  local U = lead.LR.U
  check("U.clock: a real time, and blank for one the game can't show", U.clock(1800000000) ~= "" and U.clock(1e308) == "" and U.clock(0 / 0) == ""
    and U.clock(-5) == "" and U.clock("x") == "")
end
for _, p in ipairs({ lead, ann, bob, dan, old }) do
  check(p.name .. ": no Lua errors", #p.M.errors == 0, table.concat(p.M.errors, " | "))
end

print(("passed %d"):format(passed))
print(("errors %d"):format(failed))
os.exit(failed == 0 and 0 or 1)
