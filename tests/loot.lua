-- Rolling out loot in a whole raid, every player's client running LootRuler side by side (tests/wow/
-- server.lua), plus a pug without it: the loot master opens a corpse, rolls items out, raiders roll from
-- their roll windows (and the pug by typing /roll), reserved items are only rolled for by the players who
-- reserved them, ties are rolled again, hard reserved items are given straight out, and the items go
-- to the winners through master loot and onto the soft reserves' list of loot given out.
--   lua5.1 tests/loot.lua
package.path = "./tests/?.lua;./tests/wow/?.lua;" .. package.path
local Server = require("server")

local failed, passed = 0, 0
local function check(name, ok, detail)
  if ok then passed = passed + 1 else failed = failed + 1 end
  print((ok and "ok   " or "FAIL ") .. name .. ((not ok and detail ~= nil) and ("  " .. tostring(detail)) or ""))
end
local function section(name) print("== " .. name) end

local srv = Server.new(".")
-- items as the game knows them: names and links from the data
local DATA = {}
do
  local chunk = assert(loadfile("LootRuler/Data/Loot.lua"))
  setfenv(chunk, setmetatable({}, { __index = _G }))
  chunk("LootRuler", DATA)
end
local QHEX = { [0] = "9d9d9d", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }
srv.itemInfo = function(id)
  local it = DATA.ITEMS[id]
  if not it then return { name = "Grey thing", quality = 0, link = ("|cff9d9d9d|Hitem:%d::::::::70:::::|h[Grey thing]|h|r"):format(id) } end
  return { name = it[1], quality = it[2], link = ("|cff%s|Hitem:%d::::::::70:::::|h[%s]|h|r"):format(QHEX[it[2]] or "ffffff", id, it[1]) }
end
local lead = srv:client({ name = "Lead", class = "PALADIN" })
local ann = srv:client({ name = "Ann", class = "PRIEST" })
local bob = srv:client({ name = "Bob", class = "MAGE", realm = "Faerlina" })
local dan = srv:client({ name = "Dan", class = "ROGUE" })
local pug = srv:player({ name = "Pug", class = "WARRIOR" })
srv:setGroup({ lead, ann, bob, dan, pug }, lead, true)
srv:setMasterLooter(lead)
srv:tick(6)

local WATCH, SIGNET, HANDWRAPS, ROYAL, BROOCH = 28528, 28525, 28507, 28529, 28530
local function full(p) return Server.full(p) end
local function chat(text, channel)
  for i = #srv.chat, 1, -1 do
    local m = srv.chat[i]
    if m.text:find(text, 1, true) and (not channel or m.channel == channel) then return m end
  end
end
local function frameFor(p, id)       -- the newest window for an item
  local frames = p.LR.UI.rollFrames()
  for i = #frames, 1, -1 do
    local f = frames[i]
    if f:IsShown() and f.copy and f.copy.id == id then return f end
  end
end
local function copyOf(p, id)
  for i = #p.LR.Rolls.order, 1, -1 do
    local c = p.LR.Rolls.seen[p.LR.Rolls.order[i]]
    if c and c.id == id then return c end
  end
end
local function status(p, id) local f = frameFor(p, id) return f and f.status:GetText() or "" end
--- whether some text is on screen (inside root), and clicking it
local function found(p, text, root) return #p.M.findText(text, true, root) > 0 end
local function clickText(p, text, root)
  for _, hit in ipairs(p.M.findText(text, true, root)) do
    if hit.clickable then return p.M.click(hit.clickable) end
  end
  error("nothing to click: " .. text, 2)
end
local function wonBy(s, id)
  local out = {}
  for _, w in ipairs(s.won or {}) do if w.i == id then out[#out + 1] = w.p .. ":" .. w.k end end
  return table.concat(out, ",")
end

-- soft reserves: Ann twice and Bob once on the watch; the handwraps hard reserved for Ann
local s = lead.LR.startSession("Karazhan", 2, true, false)
srv:tick(2)
ann.LR.reserve(ann.LR.current(), WATCH) ann.LR.reserve(ann.LR.current(), WATCH)
bob.LR.reserve(bob.LR.current(), WATCH)
lead.LR.setHR(s, HANDWRAPS, "Ann", "healer")
srv:tick(3)
check("the reserves are in", lead.LR.Session.claims(s, full(ann), WATCH) == 2 and lead.LR.Session.claims(s, full(bob), WATCH) == 1)
local Rolls = lead.LR.Rolls
local function dropOf(id, n)
  local seen = 0
  for _, d in ipairs(s.drops or {}) do if d.i == id then seen = seen + 1 if seen == (n or 1) then return d end end end
end
local function stateOf(id, n) return lead.LR.Session.dropState(s, dropOf(id, n)) end

section("the loot window")
srv:openLoot(lead, { { WATCH, 4 }, { SIGNET, 4 }, { HANDWRAPS, 4 }, { 22829, 0 }, { BROOCH, 4 } })
srv:tick(0.5)
local loot = Rolls.loot()
check("what's worth rolling for is listed (not the grey)", #loot == 4 and loot[1].id == WATCH and loot[4].id == BROOCH, #loot)
local panel = lead.G.LootRulerLootPanel
check("the loot panel opens beside the loot window", panel and panel:IsShown() and select(2, panel:GetPoint()) == lead.G.LootFrame)
check("it says who reserved what", found(lead, "SR: Ann x2, Bob-Faerlina", panel) and found(lead, "Hard reserved for Ann", panel))
check("raiders don't get one", not ann.G.LootRulerLootPanel)

section("an item nobody reserved")
clickText(lead, "Signet of Unshakable Faith", panel)
srv:tick(0.5)
local roll = Rolls.mine()
check("clicking it in the panel rolls it out", roll and roll.id == SIGNET and roll.mode == "OPEN" and roll.state == "open" and roll.slot == 2)
check("raid chat tells everyone what to roll", chat("/roll for main spec, /roll 99 for off spec", "RAID_WARNING") ~= nil)
check("everyone with the addon gets a roll window", frameFor(ann, SIGNET) and frameFor(bob, SIGNET) and frameFor(dan, SIGNET))
check("the loot master too", frameFor(lead, SIGNET) ~= nil)
local fa = frameFor(ann, SIGNET)
check("dice and coin can both be clicked", fa.dice:IsEnabled() and fa.coin:IsEnabled() and fa.coin:IsShown())
check("the window shows the item", fa.name:GetText():find("Signet", 1, true) and fa.item.icon:GetTexture() ~= nil)
check("the loot master's window opens", lead.G.LootRulerMasterFrame:IsShown())
srv:willRoll(ann, 60)
ann.M.click(fa.dice)
srv:tick(0.3)
check("the dice /rolls for main spec", roll.rolled["ann-dreamscythe"] and roll.rolled["ann-dreamscythe"].kind == "MS" and roll.rolled["ann-dreamscythe"].n == 60)
check("Ann's window says what she rolled", status(ann, SIGNET):find("You rolled 60 (MS)", 1, true) ~= nil, status(ann, SIGNET))
check("and she can't roll twice", not frameFor(ann, SIGNET).dice:IsEnabled())
srv:roll(pug, 1, 100, 85)
srv:willRoll(bob, 95)
bob.M.click(frameFor(bob, SIGNET).coin)
srv:roll(dan, 1, 50, 49)
srv:tick(0.3)
check("a player without the addon rolls in chat and it counts", roll.rolled["pug-dreamscythe"] and roll.rolled["pug-dreamscythe"].n == 85)
check("Bob's coin rolls off spec", roll.rolled["bob-faerlina"] and roll.rolled["bob-faerlina"].kind == "OS")
local good, bad = lead.LR.Roll.standings(roll)
check("main spec first, best first", good[1].p == full(pug) and good[2].p == full(ann) and good[3].p == full(bob))
check("a roll of the wrong range doesn't count", bad[1] and bad[1].p == full(dan) and bad[1].why == "range")
check("raiders see the same highest roll", status(dan, SIGNET):find("Highest: Pug 85 (MS)", 1, true) ~= nil, status(dan, SIGNET))
check("the loot master's window lists the rolls", found(lead, "Pug", lead.G.LootRulerMasterFrame))
srv:tick(22)
check("the roll closes when the time's up", roll.state == "closed")
check("five seconds' warning was given", chat("5 seconds left to roll") ~= nil)
check("and the result", chat("Pug wins with 85 (MS)") ~= nil)
check("raiders' windows say who won", status(ann, SIGNET):find("Pug wins with 85", 1, true) ~= nil, status(ann, SIGNET))
srv:roll(dan, 1, 100, 100)
srv:tick(0.3)
check("a roll after it closed is listed as late", select(2, lead.LR.Roll.standings(roll))[2].why == "late")
check("and doesn't change the winner", (lead.LR.Roll.result(roll)).p == full(pug))
clickText(lead, "Give to Pug", lead.G.LootRulerMasterFrame)
srv:tick(1)
check("Give hands it over through master loot", srv.given and srv.given[1] and srv.given[1].id == SIGNET and srv.given[1].to == pug)
check("and says so", chat("goes to Pug (MS 85)") ~= nil)
check("it's on the list of loot given out", wonBy(s, SIGNET) == full(pug) .. ":MS")
check("raiders' copies of the session have it", wonBy(ann.LR.current(), SIGNET) == full(pug) .. ":MS")
check("their windows say who has it", status(bob, SIGNET):find("Given to Pug", 1, true) ~= nil, status(bob, SIGNET))
srv:tick(9)
check("and go away after a few seconds", frameFor(ann, SIGNET) == nil and frameFor(bob, SIGNET) == nil)
check("the item has gone from the panel", not found(lead, "Signet of Unshakable Faith", panel))
clickText(lead, "Close", lead.G.LootRulerMasterFrame)
check("the loot master closes their window", not lead.G.LootRulerMasterFrame:IsShown() and Rolls.mine() == nil)

section("a soft reserved item")
roll = Rolls.start(WATCH, { link = lead.G.GetLootSlotLink(1), slot = 1 })
srv:tick(0.5)
check("only the reservers roll", roll.mode == "SR" and #roll.who == 2)
check("chat says who", chat("is soft reserved by Ann x2, Bob-Faerlina: only they roll", "RAID_WARNING") ~= nil)
local fd = frameFor(dan, WATCH)
check("Dan's window shows, but he can't roll", fd and not fd.dice:IsEnabled() and not fd.coin:IsShown())
check("and says why", status(dan, WATCH):find("Reserved by Ann x2, Bob-Faerlina: only they roll", 1, true) ~= nil, status(dan, WATCH))
fa = frameFor(ann, WATCH)
check("Ann's window lets her roll for her reserve", fa.dice:IsEnabled() and fa.dice.kind == "SR" and not fa.coin:IsShown())
check("and says she reserved it", status(ann, WATCH):find("You reserved this", 1, true) ~= nil)
srv:roll(dan, 1, 100, 99)
srv:willRoll(ann, 40)
ann.M.click(fa.dice)
srv:tick(0.5)
check("Dan's roll doesn't count", roll.rolled["dan-dreamscythe"] == nil and (lead.LR.Roll.result(roll)).p == full(ann))
bob.M.click(frameFor(bob, WATCH).pass)
srv:tick(0.5)
check("Bob passes: the loot master hears it", roll.passed["bob-faerlina"] ~= nil)
check("and his window goes", frameFor(bob, WATCH) == nil)
srv:tick(2.5)
check("everyone who may roll has rolled or passed: it closes early", roll.state == "closed" and (lead.LR.Roll.result(roll)).p == full(ann))
local ok = Rolls.award(full(ann))
srv:tick(1)
check("given to Ann for her reserve", ok and srv.given[2].id == WATCH and srv.given[2].to == ann and wonBy(s, WATCH) == full(ann) .. ":SR")
check("which uses up one of her two", lead.LR.Session.claims(s, full(ann), WATCH) == 1)
local plan = lead.LR.Roll.plan(s, WATCH, lead.LR.roster())
check("if another drops, Ann's other reserve and Bob's still count", plan.mode == "SR" and #plan.who == 2)
Rolls.dismiss()

section("a hard reserved item")
roll = Rolls.start(HANDWRAPS, { link = lead.G.GetLootSlotLink(3), slot = 3 })
srv:tick(0.5)
check("isn't rolled for", roll.mode == "HR" and roll.state == "closed" and frameFor(ann, HANDWRAPS) == nil)
check("the loot master's window offers it to Ann", found(lead, "Give to Ann", lead.G.LootRulerMasterFrame))
clickText(lead, "Give to Ann", lead.G.LootRulerMasterFrame)
srv:tick(1)
check("and hands it over", srv.given[3].id == HANDWRAPS and srv.given[3].to == ann and wonBy(s, HANDWRAPS) == full(ann) .. ":HR")
check("saying so", chat("goes to Ann (hard reserved)") ~= nil)
Rolls.dismiss()

section("a tie")
srv:willRoll(ann, 77) srv:willRoll(bob, 77) srv:willRoll(dan, 12)
roll = Rolls.start(BROOCH, { link = lead.G.GetLootSlotLink(5), slot = 5, secs = 10 })
srv:tick(0.3)
ann.M.click(frameFor(ann, BROOCH).dice)
bob.M.click(frameFor(bob, BROOCH).dice)
dan.M.click(frameFor(dan, BROOCH).dice)
srv:tick(13)
check("tied rolls are found", roll.state == "closed" and roll.tied and #roll.tied == 2)
check("and announced", chat("tied at 77") ~= nil)
check("raiders see the tie", status(dan, BROOCH):find("Tied at 77", 1, true) ~= nil, status(dan, BROOCH))
check("there's no winner to give it to yet", not found(lead, "Give to", lead.G.LootRulerMasterFrame))
clickText(lead, "Reroll the tie", lead.G.LootRulerMasterFrame)
srv:tick(0.5)
local tie = Rolls.mine()
check("the reroll is just for the tied players", tie.mode == "TIE" and tie.k ~= roll.k and #tie.who == 2)
check("they get a window for it", frameFor(ann, BROOCH) and frameFor(ann, BROOCH).copy.mode == "TIE" and frameFor(bob, BROOCH))
check("Dan doesn't", not (frameFor(dan, BROOCH) and frameFor(dan, BROOCH).copy.mode == "TIE"))
check("chat says so", chat("Tie for") and chat("Ann, Bob-Faerlina roll again") ~= nil)
srv:willRoll(ann, 30) srv:willRoll(bob, 31)
ann.M.click(frameFor(ann, BROOCH).dice)
bob.M.click(frameFor(bob, BROOCH).dice)
srv:roll(dan, 1, 100, 100)
srv:tick(3)
check("Bob wins the reroll (and it's over as soon as they've both rolled)", tie.state == "closed" and (lead.LR.Roll.result(tie)).p == full(bob))
check("Dan's roll didn't count", tie.rolled["dan-dreamscythe"] == nil)

section("someone out of range")
srv.farAway = { [bob] = true }
ok, why = Rolls.award(full(bob))
srv:tick(1)
check("isn't on the master loot list: it's marked as theirs to trade", ok and why and why:find("trade it", 1, true) and #srv.given == 3)
check("and still recorded", wonBy(s, BROOCH) == "Bob-Faerlina:MS")
srv.farAway = nil
Rolls.dismiss()

section("the +1 rule")
lead.LR.setPlusOne(s, true)
srv:tick(2)
local LS = lead.LR.Session
check("main spec wins so far are +1s", LS.plusOnes(s, full(pug)) == 1 and LS.plusOnes(s, full(ann)) == 0)
roll = Rolls.start(SIGNET, { secs = 10 })
srv:tick(0.5)
check("the announcement says +1s roll after", chat("anyone with a +1 rolls after those without") ~= nil)
srv:roll(pug, 1, 100, 99)
srv:willRoll(ann, 20)
ann.M.click(frameFor(ann, SIGNET).dice)
srv:tick(0.5)
check("Ann (no +1) beats Pug's 99 (+1)", (lead.LR.Roll.result(roll)).p == full(ann))
check("raiders' windows agree", status(dan, SIGNET):find("Highest: Ann 20 (MS)", 1, true) ~= nil, status(dan, SIGNET))
check("the loot master sees the +1", found(lead, "MS +1", lead.G.LootRulerMasterFrame))
Rolls.cancel()
srv:tick(0.5)
lead.LR.adjustPlusOne(s, full(ann), 1)
srv:tick(2)
check("the leader gives Ann a +1; raiders see it", LS.plusOnes(s, full(ann)) == 1 and ann.LR.Session.plusOnes(ann.LR.current(), full(ann)) == 1)
lead.LR.adjustPlusOne(s, full(ann), -1)
lead.LR.setPlusOne(s, false)
srv:tick(2)

section("the disenchanter")
lead.LR.setDisenchanter(s, full(dan))
srv:tick(2)
check("raiders know who disenchants", ann.LR.current().de == full(dan))
srv:openLoot(lead, { { 28570, 4 } })
srv:tick(0.5)
roll = Rolls.start(28570, { slot = 1, secs = 5 })
srv:tick(8)
check("nobody rolled", roll.state == "closed" and lead.LR.Roll.result(roll) == nil)
check("the loot master's window offers it to the disenchanter", found(lead, "Disenchant (Dan)", lead.G.LootRulerMasterFrame))
clickText(lead, "Disenchant (Dan)", lead.G.LootRulerMasterFrame)
srv:tick(1)
check("it goes to Dan through master loot", srv.given[#srv.given].id == 28570 and srv.given[#srv.given].to == dan)
check("the raid is told", chat("to be disenchanted") ~= nil)
check("the list says disenchanted", s.won[#s.won].de == true and ann.LR.U.plain(ann.LR.UI.dropLine(ann.LR.current(), dropOf(28570))):find("Disenchanted by Dan", 1, true) ~= nil)
check("no +1 for it", lead.LR.Session.plusOnes(s, full(dan)) == 0)
Rolls.dismiss()
srv:closeLoot(lead)
srv:tick(0.5)

section("raid warnings or plain raid chat")
lead.LR.db.settings.raidWarning = false
roll = Rolls.start(SIGNET, { secs = 10 })
srv:tick(0.5)
check("with raid warnings off, a roll is announced in plain raid chat", chat("Roll for", "RAID") ~= nil and srv.chat[#srv.chat].channel == "RAID")
Rolls.cancel()
srv:tick(0.5)
lead.LR.db.settings.raidWarning = true

section("calling it off")
roll = Rolls.start(ROYAL, { secs = 15 })
srv:tick(0.5)
check("an item from the bags (not the loot window) can be rolled out", roll and roll.state == "open" and frameFor(ann, ROYAL))
Rolls.cancel()
srv:tick(0.5)
check("calling it off closes everyone's window", frameFor(ann, ROYAL) == nil and frameFor(bob, ROYAL) == nil)
check("and says so", chat("is called off") ~= nil)

section("who may roll loot out")
local r2, no = dan.LR.Rolls.start(ROYAL)
check("a raider can't", r2 == nil and no:find("Only the raid leader", 1, true))
local fake = dan.LR.Net.encode({ t = "R", k = "Dan:1:1", id = ROYAL, s = 20, left = 20, m = "OPEN", w = {} })
srv:addonMessage(dan, "LootRuler", fake, "RAID")
srv:tick(0.5)
check("and a roll sent by one is ignored", copyOf(ann, ROYAL) == nil or copyOf(ann, ROYAL).k ~= "Dan:1:1")
srv:setAssist(ann, true)
srv:setMasterLooter(ann)
srv:closeLoot(lead)
srv:tick(1)
check("the loot window closing takes the panel away", not lead.G.LootRulerLootPanel:IsShown())
srv:openLoot(ann, { { ROYAL, 4 } })
srv:tick(0.5)
check("the new master looter gets the panel", ann.G.LootRulerLootPanel and ann.G.LootRulerLootPanel:IsShown())
srv:willRoll(dan, 50)
roll = ann.LR.Rolls.start(ROYAL, { link = ann.G.GetLootSlotLink(1), slot = 1, secs = 5 })
srv:tick(0.3)
check("an assistant running loot rolls things out", roll and frameFor(dan, ROYAL) and frameFor(lead, ROYAL))
dan.M.click(frameFor(dan, ROYAL).dice)
srv:tick(8)
ann.LR.Rolls.award(full(dan))
srv:tick(2)
check("the item goes to Dan", srv.given[#srv.given].id == ROYAL and srv.given[#srv.given].to == dan)
check("and the soft reserves' leader records it", wonBy(s, ROYAL) == full(dan) .. ":MS")

section("settings")
ann.LR.db.settings.rollOnlyMine = true
srv:setMasterLooter(lead)
srv:openLoot(lead, { { WATCH, 4 } })
srv:tick(0.5)
Rolls.start(WATCH, { slot = 1 })
srv:tick(0.5)
check("'only items I can roll on' still shows Ann a reserved item she can roll on", frameFor(ann, WATCH) ~= nil)
dan.LR.db.settings.rollOnlyMine = true
dan.LR.UI.rollWindows()
check("and hides one Dan can't", frameFor(dan, WATCH) == nil)
dan.LR.db.settings.rollWindow = false
bob.LR.db.settings.rollWindow = false
bob.LR.UI.rollWindows()
check("roll windows can be turned off", frameFor(bob, WATCH) == nil)
Rolls.cancel()
srv:tick(1)

section("the raid's loot list")
check("everything from the first corpse is on it, in order", s.drops and s.drops[1].i == WATCH and s.drops[2].i == SIGNET and s.drops[3].i == HANDWRAPS and s.drops[4].i == BROOCH)
check("not the grey", dropOf(22829) == nil)
check("with the boss it dropped from", dropOf(WATCH).b == "Moroes")
check("and who has it now (master loot)", dropOf(SIGNET).h == full(pug) and dropOf(WATCH).h == full(ann) and dropOf(HANDWRAPS).h == full(ann))
check("the awards are tied to the drops", stateOf(SIGNET) == "given" and select(2, stateOf(SIGNET)).p == full(pug))
check("an assistant running loot writes it down for the leader", dropOf(ROYAL) and dropOf(ROYAL).h == full(dan) and stateOf(ROYAL) == "given")
check("raiders have the same list", #ann.LR.current().drops == #s.drops and #bob.LR.current().drops == #s.drops)
local count = #s.drops
srv:closeLoot(lead)
srv:openLoot(lead, { { WATCH, 4 } })
srv:tick(1)
check("opening a corpse again doesn't list its items twice", #s.drops == count, #s.drops .. " vs " .. count)
srv:closeLoot(lead)

section("rolling out at the end of the raid")
local PAULDRONS, SHOULDERS = 28612, 28647
srv:target(lead, "The Curator")
srv:openLoot(lead, { { PAULDRONS, 4 }, { SHOULDERS, 4 } })
srv:tick(1)
check("a new boss's loot is listed under it", dropOf(PAULDRONS) and dropOf(PAULDRONS).b == "The Curator" and dropOf(SHOULDERS).b == "The Curator")
local function selfIndex(slot)
  for i = 1, 40 do local n = lead.G.GetMasterLootCandidate(slot, i) if n == "Lead" then return i end end
end
lead.G.GiveMasterLoot(1, selfIndex(1))
lead.G.GiveMasterLoot(2, selfIndex(2))
srv:tick(1)
check("the loot master keeps both, to roll out later", stateOf(PAULDRONS) == "held" and stateOf(SHOULDERS) == "held")
check("the trade clock starts", dropOf(PAULDRONS).ht and lead.LR.Drops.tradeLeft(dropOf(PAULDRONS)) > 7000)
check("raiders see who has them", ann.LR.UI.dropLine(ann.LR.current(), dropOf(PAULDRONS)):find("Lead has it, to roll out", 1, true) ~= nil,
  ann.LR.UI.dropLine(ann.LR.current(), dropOf(PAULDRONS)))
srv:closeLoot(lead)
srv:target(lead, nil)
srv:tick(60)
roll = Rolls.start(PAULDRONS, { drop = dropOf(PAULDRONS).k })
srv:tick(0.5)
check("rolled out from the list, an hour later", roll and roll.drop == dropOf(PAULDRONS).k and frameFor(ann, PAULDRONS))
srv:willRoll(ann, 70)
ann.M.click(frameFor(ann, PAULDRONS).dice)
srv:tick(22)
local note
ok, note = Rolls.award(full(ann))
srv:tick(1)
check("won by Ann: the loot master still has it to trade", stateOf(PAULDRONS) == "toTrade")
check("and is told to trade it", note and note:find("Open a trade with Ann", 1, true))
check("the list says so", ann.LR.UI.dropLine(ann.LR.current(), dropOf(PAULDRONS)):find("Lead has it to trade", 1, true) ~= nil)
check("the loot master has one to hand over", #lead.LR.Drops.toDeliver() == 1)
Rolls.dismiss()
roll = Rolls.start(SHOULDERS, { drop = dropOf(SHOULDERS).k })
srv:tick(0.5)
srv:roll(bob, 1, 100, 40)                       -- (Bob turned his roll windows off: he types /roll)
srv:tick(22)
Rolls.award(full(bob))
srv:tick(1)
Rolls.dismiss()
srv:openTrade(lead, ann)
srv:tick(1)
check("Ann opens a trade: her item goes in, and only hers", #lead.tradeItems == 1 and lead.tradeItems[1].id == PAULDRONS)
srv:completeTrade(lead)
srv:tick(1)
check("the trade goes through: Ann has it", stateOf(PAULDRONS) == "given" and dropOf(PAULDRONS).h == full(ann))
check("in her bags", ann.bags[1] and ann.bags[1].id == PAULDRONS or (function() for _, it in pairs(ann.bags) do if it.id == PAULDRONS then return true end end end)())
lead.LR.db.settings.tradeHelp = false
srv:openTrade(lead, bob)
srv:tick(1)
check("with trade help off, nothing is put in", #lead.tradeItems == 0)
srv:completeTrade(lead)
lead.LR.db.settings.tradeHelp = true
srv:openTrade(bob, lead)
srv:tick(1)
check("it doesn't matter who opens the trade", #lead.tradeItems == 1 and lead.tradeItems[1].id == SHOULDERS)
srv:completeTrade(lead)
srv:tick(1)
check("Bob has his", stateOf(SHOULDERS) == "given" and dropOf(SHOULDERS).h == full(bob))
check("the raid is told what the loot master traded", chat("Traded |cffa335ee|Hitem:28647", "RAID") ~= nil and chat("to Bob-Faerlina.", "RAID") ~= nil)
srv:lootTo(lead, 28670)
srv:tick(1)
srv:openTrade(lead, ann)
srv:tick(0.5)
lead.G.C_Container.UseContainerItem(0, (function() for slot, it in pairs(lead.bags) do if it.id == 28670 then return slot end end end)())
srv:setTradeMoney(ann, 1505000)
srv:tick(0.5)
srv:completeTrade(lead)
srv:tick(1)
check("an item for gold: both sides are said", chat("to Ann for 150g 50s.", "RAID") ~= nil)
lead.LR.db.settings.tradeAnnounce = false
local lines = #srv.chat
srv:openTrade(lead, ann)
srv:setTradeMoney(ann, 10000)
srv:tick(0.5)
srv:completeTrade(lead)
srv:tick(1)
local fromLead = 0
for i = lines + 1, #srv.chat do if srv.chat[i].from == full(lead) then fromLead = fromLead + 1 end end
check("it can be turned off (Ann, an assistant, still says what she got)", fromLead == 0 and chat("Traded 1g to Lead.", "RAID") ~= nil)
lead.LR.db.settings.tradeAnnounce = true
check("nothing left to hand over", #lead.LR.Drops.toDeliver() == 0)

section("group loot")
srv:setMasterLooter(nil)
srv:tick(1)
local DRAPE = 28672
srv:lootTo(bob, DRAPE)
srv:lootTo(dan, 22829)
srv:tick(1)
check("an epic someone loots goes on the list", dropOf(DRAPE) and dropOf(DRAPE).h == full(bob) and stateOf(DRAPE) == "looted" and dropOf(DRAPE).b == "Shade of Aran")
check("a grey doesn't", dropOf(22829) == nil)

section("loot rules (master looter)")
srv:setMasterLooter(lead)
srv:tick(1)
local set = lead.LR.db.settings
lead.LR.AutoLoot.add("q2", "de")
lead.LR.AutoLoot.add("recipe", "me")
lead.LR.AutoLoot.add("item:28528", full(bob))          -- the watch: but Ann reserved it, so it's rolled for
local given = #srv.given
srv:openLoot(lead, { { 22545, 2 }, { 23809, 3 }, { WATCH, 4 }, { 28570, 4 } })
srv:tick(2)
check("rules do nothing until they're switched on", #srv.given == given)
srv:closeLoot(lead)
set.autoLoot = true
srv:openLoot(lead, { { 22545, 2 }, { 23809, 3 }, { WATCH, 4 }, { 28570, 4 } })
srv:tick(2)
local function gotItem(id) for i = given + 1, #srv.given do if srv.given[i].id == id then return srv.given[i].to end end end
check("the green goes to the disenchanter (the first rule that matches decides)", gotItem(22545) == dan)
check("the pattern goes to the loot master", gotItem(23809) == lead)
check("a reserved item is never handed out by a rule", gotItem(WATCH) == nil)
check("nor anything no rule matches", gotItem(28570) == nil)
check("the raid is told", chat("Handed out by the loot rules:") ~= nil)
check("the disenchanted green is on the list of loot given out", (function()
  for _, w in ipairs(s.won) do if w.i == 22545 and w.de and w.p == full(dan) then return true end end end)())
srv:closeLoot(lead)
set.autoLoot = false
set.autoLootRules = {}

section("auto-roll (each raider's own rules)")
dan.LR.db.settings.autoPassUnusable = true
roll = Rolls.start(28503, { secs = 10 })                -- Whirlwind Bracers: plate, a rogue can't wear it
srv:tick(1.5)
check("Dan passes on plate he can't use, on his own", roll.passed["dan-dreamscythe"] ~= nil and frameFor(dan, 28503) == nil)
check("and is told", (function() for _, l in ipairs(dan.M.chat) do if l:find("passed on", 1, true) and l:find("can't use it", 1, true) then return true end end end)())
Rolls.cancel()
srv:tick(0.5)
ann.LR.AutoRoll.set(SIGNET, "pass")
bob.LR.AutoRoll.set(SIGNET, "OS")
roll = Rolls.start(SIGNET, { secs = 10 })
srv:tick(1.5)
check("Ann's rule passes for her", roll.passed["ann-dreamscythe"] ~= nil)
check("Bob's rolls off spec for him (even with his roll windows off)", roll.rolled["bob-faerlina"] ~= nil and roll.rolled["bob-faerlina"].kind == "OS")
Rolls.cancel()
srv:tick(0.5)
ann.LR.AutoRoll.set(SIGNET, nil)
-- shift-clicking a roll window's button keeps it as a rule
roll = Rolls.start(28570, { secs = 10 })
srv:tick(0.5)
ann.G.IsShiftKeyDown = function() return true end
ann.M.click(frameFor(ann, 28570).dice)
ann.G.IsShiftKeyDown = function() return false end
srv:tick(0.5)
check("shift-clicking the dice rolls and remembers it", roll.rolled["ann-dreamscythe"] ~= nil and ann.LR.db.settings.autoRollRules[28570] == "MS")
Rolls.cancel()
srv:tick(0.5)

section("reserves where you see items")
srv:openLoot(ann, { { WATCH, 4 }, { SIGNET, 4 } })
for i = 1, 2 do ann.G.LootFrame_UpdateButton(i) end
local g1, g2 = ann.G.LootButton1.lrGlow, ann.G.LootButton2.lrGlow
check("the game's loot window glows on an item Ann reserved", g1 and g1:IsShown())
check("not on one she didn't", not (g2 and g2:IsShown()))
srv:closeLoot(ann)
ann.M.lootRolls = { [7] = srv:link(WATCH) }
ann.G.GroupLootFrame1.rollID = 7
ann.G.GroupLootFrame_OnShow(ann.G.GroupLootFrame1)
check("so does a need/greed window", ann.G.GroupLootFrame1.IconFrame.lrGlow and ann.G.GroupLootFrame1.IconFrame.lrGlow:IsShown())
local function tooltipHas(p, text)
  p.G.GameTooltip:SetOwner(p.G.UIParent)
  p.G.GameTooltip:SetHyperlink(srv:link(WATCH))
  for _, l in ipairs(p.G.GameTooltip._lines) do if tostring(l[1]):find(text, 1, true) then return true end end
  return false
end
check("item tooltips say who reserved it", tooltipHas(dan, "LootRuler: soft reserved by"))
check("and who it went to", tooltipHas(dan, "LootRuler: given to Ann"))
dan.LR.db.settings.tooltipInfo = false
check("which can be turned off", not tooltipHas(dan, "LootRuler:"))
dan.LR.db.settings.tooltipInfo = true

section("shortcut keys")
local function holding(p, ctrl, alt, shift)
  p.G.IsControlKeyDown = function() return ctrl end
  p.G.IsAltKeyDown = function() return alt end
  p.G.IsShiftKeyDown = function() return shift end
end
holding(lead, true, true, false)
lead.G.HandleModifiedItemClick(srv:link(28570))
srv:tick(0.5)
check("Ctrl+Alt+click on an item rolls it out", Rolls.mine() and Rolls.mine().id == 28570 and Rolls.mine().state == "open")
Rolls.cancel()
holding(lead, false, true, false)
lead.G.HandleModifiedItemClick(srv:link(28570))
srv:tick(0.5)
check("Alt alone doesn't (that's Gargul's)", Rolls.mine() == nil)
lead.LR.db.settings.rollShortcut = "alt"
lead.G.HandleModifiedItemClick(srv:link(28570))
srv:tick(0.5)
check("unless it's picked in Settings", Rolls.mine() and Rolls.mine().id == 28570)
Rolls.cancel()
lead.LR.db.settings.rollShortcut = "ctrlalt"
holding(lead, false, false, false)
holding(dan, true, true, false)
dan.G.HandleModifiedItemClick(srv:link(28570))
srv:tick(0.5)
check("a raider's shortcut does nothing", dan.LR.Rolls.mine() == nil)
holding(dan, false, false, false)

section("ending the session")
lead.LR.endSession(s)
srv:tick(2)
check("the loot list goes with it, everywhere", lead.LR.current() == nil and ann.LR.current() == nil and bob.LR.current() == nil)

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
