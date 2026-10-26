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
check("Ann's window bids the least that counts, or a jump", fa and fa.dice:IsEnabled() and fa.dice.label:GetText() == "100g" and fa.coin.label:GetText() == "200g")
ann.M.click(fa.dice)
srv:tick(0.5)
check("clicking types the bid in raid chat", chat("100", "RAID") and chat("100", "RAID").from == full(ann))
check("and it counts", roll.top and roll.top.p == full(ann) and roll.top.n == 100)
check("Ann's window says she's highest, and won't bid against her", fa.status:GetText():find("You have the highest bid: 100g", 1, true) and not fa.dice:IsEnabled())
check("Bob's window has the next amounts", frameFor(bob, WATCH).dice.label:GetText() == "125g" and frameFor(bob, WATCH).status:GetText():find("Highest bid: Ann-Dreamscythe, 100g", 1, true))
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
lead.LR.gdkpRole(s, full(bob), nil)
lead.LR.gdkpRoleCut(s, "tank", 0)
srv:tick(1)
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
check("the window says so", fd and fd.status:GetText():find("Type \"bid\" and an amount", 1, true))
dan.M.click(fd.dice)
srv:tick(0.5)
check("and its button types \"bid\" too", chat("bid 325", "RAID") and roll.top.p == full(dan) and roll.top.n == 325)
Rolls.cancel()
srv:tick(1)

section("max bids")
lead.LR.gdkpStrict(s, false)
srv:tick(1)
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
say(bob, "900")
srv:tick(1)
check("Bob bids under Dan's max: it answers", roll.top.p == full(dan) and roll.top.n == 925)
say(bob, "1000")
srv:tick(1)
check("Bob bids over it: Bob is highest", roll.top.p == full(bob) and roll.top.n == 1000)
Rolls.cancel()
srv:tick(1)

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

section("no errors")
local longest = 0
for _, m in ipairs(srv.chat) do longest = math.max(longest, #m.text) end
check("every chat line fits", longest <= 255, longest)
for _, p in ipairs({ lead, ann, bob, dan, old }) do
  check(p.name .. ": no Lua errors", #p.M.errors == 0, table.concat(p.M.errors, " | "))
end

print(("passed %d"):format(passed))
print(("errors %d"):format(failed))
os.exit(failed == 0 and 0 or 1)
