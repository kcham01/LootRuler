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
local function chatHasLead(text) for _, l in ipairs(lead.M.chat) do if l:find(text, 1, true) then return true end end return false end
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
local function raidLines(text) local n = 0 for _, m in ipairs(srv.chat) do if m.channel == "RAID" and m.text:find(text, 1, true) then n = n + 1 end end return n end
check("the raid hears what's on the corpse, with who reserved it", raidLines("[LootRuler] " .. srv:link(WATCH) .. ": reserved by Ann x2, Bob-Faerlina") == 1)
check("a hard reserve says who it's for", raidLines("[LootRuler] " .. srv:link(HANDWRAPS) .. " (hard reserved for Ann)") == 1)
check("an epic nobody reserved is posted too", raidLines("[LootRuler] " .. srv:link(SIGNET)) >= 1)
check("not the grey", raidLines(srv:link(22829)) == 0)
srv:closeLoot(lead)
srv:openLoot(lead, { { WATCH, 4 }, { SIGNET, 4 }, { HANDWRAPS, 4 }, { 22829, 0 }, { BROOCH, 4 } })
srv:tick(0.5)
check("opening the same corpse again posts nothing new", raidLines("reserved by Ann x2, Bob-Faerlina") == 1 and raidLines("(hard reserved for Ann)") == 1)

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
local function noticed(p, text) for _, n in ipairs(p.M.notices) do if n:find(text, 1, true) then return true end end return false end
check("Ann is told her item is being rolled out, in the middle of the screen", noticed(ann, "You reserved [Moroes' Lucky Pocket Watch]: roll for it now!")
  and ann.M.flashed > 0)
check("Dan, who didn't reserve it, isn't", not noticed(dan, "You reserved Moroes' Lucky Pocket Watch"))
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
lead.LR.db.settings.autoTrade = false            -- (here the winners open the trades; it's opened for them further down)
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
lead.LR.db.settings.autoTrade = true
-- giving out an item from the loot master's bags opens the trade for them
local CHAIN, RING = 28763, 28764
srv:lootTo(lead, CHAIN)
srv:lootTo(lead, RING)
srv:tick(1)
local function heldKey(id) for i = #s.drops, 1, -1 do local d = s.drops[i] if d.i == id and d.h == full(lead) then return d.k end end end
local okT, noteT = Rolls.give(CHAIN, full(ann), "MS", { drop = heldKey(CHAIN) })
srv:tick(1)
check("giving out an item in my bags opens a trade with the winner", okT and lead.trading == ann and noteT:find("A trade with Ann is opening", 1, true), noteT)
check("and trade help puts it in", #lead.tradeItems == 1 and lead.tradeItems[1].id == CHAIN)
srv:completeTrade(lead)
srv:tick(1)
check("Ann has it", (function() for _, it in pairs(ann.bags) do if it.id == CHAIN then return true end end end)())
Rolls.dismiss()
srv.farAway = { [dan] = true }
local okF, noteF = Rolls.give(RING, full(dan), "MS", { drop = heldKey(RING) })
srv:tick(1)
check("too far away: no trade, and they're whispered to come", okF and lead.trading == nil and noteF:find("too far away", 1, true)
  and chat("I have " .. srv:link(RING) .. " for you. Come close and open a trade with me when you can.", "WHISPER") ~= nil, noteF)
srv.farAway = nil
Rolls.dismiss()
srv:openTrade(lead, dan)
srv:tick(1)
srv:completeTrade(lead)
srv:tick(1)
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
-- a stack: how many
local DUST = 22445                          -- (a stack of something, not raid loot)
local _, dustSlot = srv:giveItem(lead, DUST, 3)
srv:openTrade(lead, ann)
srv:tick(0.5)
lead.G.C_Container.UseContainerItem(0, dustSlot)
srv:tick(0.5)
srv:completeTrade(lead)
srv:tick(1)
check("a stack says how many", chat("Traded " .. srv:link(DUST) .. " x3 to Ann.", "RAID") ~= nil)
-- an enchant: the loot master enchants Ann's item in the "will not be traded" slot, and she pays 5g
local bracers = srv:giveItem(ann, 28477, 1)
srv:openTrade(lead, ann)
srv:tick(0.5)
srv:tradeToEnchant(ann, bracers)
srv:setTradeMoney(ann, 50000)
srv:enchantInTrade(lead, "Enchant Bracer - Superior Healing")
srv:tick(0.5)
srv:completeTrade(lead)
srv:tick(1)
check("an enchant for a player: what, on which item, and what they paid",
  chat("Enchanted Ann's " .. srv:link(28477) .. " (Enchant Bracer - Superior Healing) for 5g.", "RAID") ~= nil)
check("the enchanted item stays theirs", (function() for _, it in pairs(ann.bags) do if it == bracers then return true end end end)())
check("Ann's side says it the other way round", chat("Lead enchanted my " .. srv:link(28477) .. " (Enchant Bracer - Superior Healing) for 5g.", "RAID") ~= nil)
-- someone not running loot enchants: not in raid chat, but a note in their own chat
local dagger = srv:giveItem(bob, 28524, 1)
local before = #srv.chat
srv:openTrade(dan, bob)
srv:tick(0.5)
srv:tradeToEnchant(bob, dagger)
srv:setTradeMoney(bob, 20000)
srv:enchantInTrade(dan, "Enchant Weapon - Major Spellpower")
srv:tick(0.5)
srv:completeTrade(dan)
srv:tick(1)
local danSaid = false
for _, l in ipairs(dan.M.chat) do if l:find("Enchanted Bob-Faerlina's", 1, true) and l:find("for 2g", 1, true) then danSaid = true end end
check("an enchanter who isn't running loot gets a note of it", danSaid)
check("and the raid isn't told", #srv.chat == before)
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
-- Ann's own Need / Greed rules (off until she turns them on)
local GL = ann.LR.GroupLoot
local GREEN, BLUE, BOUND = 1001, 1002, 1003
local function gl(id, name, q) return ("|cff1eff00|Hitem:%d::::::::70:::::|h[%s]|h|r"):format(id, name) end
ann.LR.db.settings.groupLootRules = {}
GL.add("q2", "greed")
GL.add("item:" .. BLUE, "need")
GL.add("q3", "pass")
check("a rule for one item goes before the others", ann.LR.db.settings.groupLootRules[1].what == "item:" .. BLUE)
ann.M.groupRoll(1, gl(GREEN, "Green Thing"), 2)
check("switched off, nothing is rolled", ann.M.lootRolled[1] == nil)
ann.LR.db.settings.groupLoot = true
ann.M.groupRoll(2, gl(GREEN, "Green Thing"), 2)
check("on: a green item is greeded", ann.M.lootRolled[2] == 2 and ann.M.chat[#ann.M.chat]:find("Greed on", 1, true) ~= nil, ann.M.chat[#ann.M.chat])
ann.M.groupRoll(3, gl(BLUE, "Blue Thing"), 3)
check("the item with its own rule is needed", ann.M.lootRolled[3] == 1)
ann.M.groupRoll(4, gl(1004, "Other Blue"), 3)
check("other blues are passed", ann.M.lootRolled[4] == 0)
ann.M.groupRoll(5, gl(1005, "Purple"), 4)
check("an item no rule is about is left alone", ann.M.lootRolled[5] == nil)
ann.M.groupRoll(6, gl(BLUE, "Blue Thing"), 3, { need = false })
check("a need the game won't allow isn't made: she's told to roll herself", ann.M.lootRolled[6] == nil and ann.M.chat[#ann.M.chat]:find("roll yourself", 1, true) ~= nil)
-- an item that binds when picked up: the game asks first
ann.M.groupRoll(7, gl(GREEN, "Green Thing"), 2, { bop = true })
check("binds when picked up: the game's question is left to her", ann.M.lootRolled[7] == 2 and ann.M.lootConfirmed[7] == nil)
ann.LR.db.settings.groupLootConfirm = true
ann.M.groupRoll(8, gl(GREEN, "Green Thing"), 2, { bop = true })
check("with that switched on, it's answered yes for her rule's roll", ann.M.lootConfirmed[8] == 2 and #ann.M.popupsHidden > 0)
ann.M.fire("CONFIRM_LOOT_ROLL", 5, 1)
check("never for a roll she made herself", ann.M.lootConfirmed[5] == nil)
ann.LR.db.settings.groupLoot, ann.LR.db.settings.groupLootConfirm = false, false

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
-- leaving an item alone, a range of qualities, and everyone in turn
lead.LR.AutoLoot.add("item:28570", "skip")
lead.LR.AutoLoot.add("lt4", "rr")
set.autoLoot = true
given = #srv.given
srv:openLoot(lead, { { 28570, 3 }, { 30001, 2 }, { 30002, 3 }, { 30003, 1 }, { 30004, 4 }, { "money", 1234567 } })
srv:tick(3)
check("an item a rule leaves alone stays, though a later rule would match it", gotItem(28570) == nil)
check("anything below epic goes to everyone in turn, by name", gotItem(30001) == ann and gotItem(30002) == bob,
  tostring(gotItem(30001) and gotItem(30001).name) .. " " .. tostring(gotItem(30002) and gotItem(30002).name))
check("an epic isn't below epic", gotItem(30004) == nil)
check("(a common item is under the master loot threshold: the game lets anyone take it)", gotItem(30003) == nil)
check("the gold is left until that's switched on", (lead.money or 0) == 0)
srv:closeLoot(lead)
set.lootGold = true
srv:openLoot(lead, { { 30005, 2 }, { "money", 1234567 } })
srv:tick(3)
check("then the loot master picks it up", lead.money == 1234567)
check("and the turn carries on from where it was", gotItem(30005) and gotItem(30005).name == "Dan", gotItem(30005) and gotItem(30005).name)
srv:closeLoot(lead)
set.autoLoot, set.lootGold = false, false
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

section("undoing an award")
local CLOAK = 28570                       -- (nobody reserved it: everyone rolls)
local function wonCloak() return wonBy(lead.LR.current(), CLOAK) end
local wonBefore = wonCloak()
local function plus(x) return wonBefore ~= "" and (wonBefore .. "," .. x) or x end
srv:openLoot(lead, { { CLOAK, 4 } })
srv:tick(0.5)
local ur = Rolls.start(CLOAK, { link = srv:link(CLOAK), slot = 1 })
srv:tick(0.5)
srv:roll(dan, 1, 100, 77)
srv:roll(bob, 1, 100, 52)
srv:tick(1)
Rolls.stop()
srv:tick(1)
local okA = Rolls.award(full(dan))                  -- the loot master meant Bob
srv:tick(2)
local function cloakDrop() return lead.LR.Session.drop(s, ur.drop) end
check("given to Dan by mistake (it's in his bags)", okA and wonCloak() == plus(full(dan) .. ":MS") and cloakDrop().h == full(dan))
check("the loot master window offers to undo it", found(lead, "Undo", lead.G.LootRulerMasterFrame))
clickText(lead, "Undo", lead.G.LootRulerMasterFrame)
srv:tick(2)
check("undone: off the list of loot given out, for everyone", wonCloak() == wonBefore and wonBy(ann.LR.current(), CLOAK) == wonBefore)
check("the roll is back as it closed, rolls and all", ur.state == "closed" and ur.winner == nil and ur.rolled[lead.LR.Roll.key(full(bob))] ~= nil)
check("raiders' windows say so too", copyOf(ann, CLOAK).state == "closed" and copyOf(ann, CLOAK).winner == nil)
check("the raid hears it, and Dan is asked to trade it on", chat("isn't Dan's after all. Dan, please trade it to whoever gets it.", "RAID") ~= nil)
check("the loot master is told Dan has it", found(lead, "Dan has it already", lead.G.LootRulerMasterFrame))
ur.pick = full(bob)
Rolls.award(full(bob))
srv:tick(2)
check("then given to the right player", wonCloak() == plus(full(bob) .. ":MS") and Rolls.mine().state == "awarded")
check("nothing to undo once it's closed", (function() Rolls.dismiss() return not Rolls.undo() end)())
-- an assistant runs the roll: the leader's addon takes the award off its list when she undoes it
srv:setAssist(ann, true)
local SHAWL = 28766
local wonShawl = function() return wonBy(lead.LR.current(), SHAWL) end
local shawlBefore = wonShawl()
local ar = ann.LR.Rolls.start(SHAWL, { link = srv:link(SHAWL) })
srv:tick(0.5)
srv:roll(dan, 1, 100, 40)
srv:tick(1)
ann.LR.Rolls.stop()
srv:tick(1)
ann.LR.Rolls.award(full(dan))
srv:tick(2)
check("an assistant gives one out: the leader records it", ar and wonShawl() == (shawlBefore ~= "" and (shawlBefore .. ",") or "") .. full(dan) .. ":MS")
ann.LR.Rolls.undo()
srv:tick(2)
check("she undoes it: the leader takes it off", wonShawl() == shawlBefore)
ann.LR.Rolls.dismiss()
srv:closeLoot(lead)
srv:tick(1)

section("giving an item out without a roll")
local HANDS, TALISMAN, STAFF = 28771, 28772, 28773       -- (Prince Malchezaar's)
lead.LR.leaderAdd(s, full(bob), "MAGE", STAFF)        -- Bob reserved the staff
srv:tick(1)
srv:openLoot(lead, { { HANDS, 4 }, { TALISMAN, 4 }, { STAFF, 4 } })
srv:tick(0.5)
local givenBefore = #srv.given
local okG, noteG = Rolls.give(HANDS, full(dan), "OS", { link = srv:link(HANDS), slot = 1 })
srv:tick(1)
check("given to Dan without a roll, through master loot", okG and srv.given[#srv.given].id == HANDS and srv.given[#srv.given].to == dan, noteG)
check("recorded like a won roll", wonBy(s, HANDS):find(full(dan) .. ":OS", 1, true) ~= nil)
check("the raid hears it", chat("goes to Dan (off spec, given out without a roll).", "RAID") ~= nil)
check("raiders' addons have it", wonBy(ann.LR.current(), HANDS):find(full(dan) .. ":OS", 1, true) ~= nil)
Rolls.dismiss()
local claimsBefore = lead.LR.Session.claims(s, full(bob), STAFF)
Rolls.give(STAFF, full(bob), "SR", { link = srv:link(STAFF), slot = 3 })
srv:tick(1)
check("given to a reserver on their reserve: it's used up", claimsBefore == 1 and lead.LR.Session.claims(s, full(bob), STAFF) == 0
  and chat("goes to Bob-Faerlina (their reserve, given out without a roll).", "RAID") ~= nil)
check("it can be undone like any award", Rolls.undo() and lead.LR.Session.claims(s, full(bob), STAFF) == 1)
Rolls.dismiss()
Rolls.start(TALISMAN, { link = srv:link(TALISMAN), slot = 2 })
srv:tick(0.5)
local okBusy, whyBusy = Rolls.give(TALISMAN, full(dan), "MS", { slot = 2 })
check("not while a roll is on", not okBusy and whyBusy:find("Finish the roll", 1, true) ~= nil)
Rolls.cancel()
srv:tick(0.5)
local okRaider = bob.LR.Rolls.give(TALISMAN, full(bob), "MS", { slot = 2 })
check("only whoever runs loot can give items out", not okRaider)
srv:closeLoot(lead)
srv:tick(1)

section("who got what, in guild chat too")
lead.guild = "Kings"
srv:openLoot(lead, { { HANDS, 4 } })
srv:tick(0.5)
local guildBefore = 0
for _, c in ipairs(srv.chat) do if c.channel == "GUILD" then guildBefore = guildBefore + 1 end end
Rolls.give(HANDS, full(bob), "MS", { link = srv:link(HANDS), slot = 1 })
srv:tick(1)
local function guildLines() local n = 0 for _, c in ipairs(srv.chat) do if c.channel == "GUILD" then n = n + 1 end end return n end
check("off to start with: nothing in guild chat", guildLines() == guildBefore)
Rolls.undo()
srv:tick(1)
Rolls.dismiss()
lead.LR.db.settings.awardGuild = true
Rolls.give(HANDS, full(bob), "MS", { link = srv:link(HANDS), slot = 1 })
srv:tick(10)                              -- (chat is sent a little at a time)
check("on: the guild hears who got what, with the raid", chat("Karazhan: ", "GUILD") ~= nil and chat("goes to Bob-Faerlina (main spec, given out without a roll).", "GUILD") ~= nil)
Rolls.undo()
srv:tick(10)
check("and when it's taken back", chat("Undone:", "GUILD") ~= nil)
Rolls.dismiss()
lead.guild = nil
lead.LR.db.settings.awardGuild = false
srv:closeLoot(lead)
srv:tick(1)

section("what everyone wears there now")
local RING = 28510                              -- Spectral Band of Innervation: a ring
local OLD = "|cff0070dd|Hitem:12345::::::::70:::::|h[Old Ring]|h|r"
local OLD2 = "|cff0070dd|Hitem:12346::::::::70:::::|h[Other Ring]|h|r"
ann.M.player.links = { [11] = OLD, [12] = OLD2 }
srv:openLoot(lead, { { RING, 4 } })
srv:tick(0.5)
local gr = Rolls.start(RING, { link = srv:link(RING), slot = 1 })
srv:tick(1)
check("Ann's addon tells the loot master which rings she wears", gr.gear and gr.gear["ann-dreamscythe"] and gr.gear["ann-dreamscythe"][1] == OLD
  and gr.gear["ann-dreamscythe"][2] == OLD2)
check("Bob wears none: nothing", not gr.gear["bob-faerlina"])
check("her own window shows them", frameFor(ann, RING) and frameFor(ann, RING).note:GetText():find("You have:", 1, true) ~= nil)
srv:willRoll(ann, 30)
ann.M.click(frameFor(ann, RING).dice)
srv:tick(0.5)
local shown = false
for _, x in ipairs(lead.M.findText("Ann", true, lead.G.LootRulerMasterFrame)) do
  local row = x.frame
  if row.gear and row.gear:IsShown() and row.gear.links and row.gear.links[1] == OLD then shown = true end
end
check("and the loot master's window shows it beside her roll", shown)
-- what doesn't count: someone outside the group, or another roll
local stranger = srv:player({ name = "Stranger", class = "MAGE" })
srv:addonMessage(stranger, "LootRuler", lead.LR.Net.encode({ t = "W", k = gr.k, e = { OLD } }), "WHISPER", full(lead))
srv:addonMessage(bob, "LootRuler", lead.LR.Net.encode({ t = "W", k = "another", e = { OLD } }), "WHISPER", full(lead))
srv:addonMessage(bob, "LootRuler", lead.LR.Net.encode({ t = "W", k = gr.k, e = { "not a link", OLD } }), "WHISPER", full(lead))
srv:tick(0.5)
check("from outside the group, or for another roll: ignored; and only links are kept",
  not gr.gear["stranger-dreamscythe"] and #gr.gear["bob-faerlina"] == 1)
Rolls.cancel()
srv:tick(0.5)
Rolls.dismiss()
ann.LR.db.settings.shareGear = false
gr = Rolls.start(RING, { link = srv:link(RING), slot = 1 })
srv:tick(1)
check("switched off: not told, though her own window still shows it", not (gr.gear and gr.gear["ann-dreamscythe"]) and frameFor(ann, RING).note:GetText():find("You have:", 1, true) ~= nil)
Rolls.cancel()
srv:tick(0.5)
Rolls.dismiss()
srv:closeLoot(lead)
ann.LR.db.settings.shareGear = true
ann.M.player.links = nil
srv:tick(1)

section("becoming the master looter")
local function sheetTitle(p) local sh = p.LR.UI.topSheet() return sh and sh.title:GetText() end
local asked, wrongly = false, false
for _, e in ipairs(ann.LR.UI.openSheets()) do
  if e.s.title:GetText() == "You're the master looter" then asked = true end
  if e.s.title:GetText() == "Record it?" then wrongly = true end
end
check("Ann was asked when she was master looter, earlier", asked)
check("and not asked to record the item she gave out through LootRuler", not wrongly)
ann.LR.UI.closeAll()
lead.LR.UI.closeAll()
srv:setMasterLooter(nil)
srv:tick(1)
srv:setMasterLooter(lead)
srv:tick(1)
check("the loot master is asked what to do", sheetTitle(lead) == "You're the master looter")
check("raiders aren't", sheetTitle(ann) ~= "You're the master looter")
local mlBefore = #srv.chat
clickText(lead, "Tell the raid", lead.LR.UI.topSheet())
srv:tick(1)
check("one click tells the raid who runs loot and how to roll", srv.chat[mlBefore + 1] and srv.chat[mlBefore + 1].text:find("Lead is the master looter. Items are rolled out in raid chat", 1, true) ~= nil)
clickText(lead, "Don't ask again", lead.LR.UI.topSheet())
check("it can stop asking", lead.LR.db.settings.mlPrompt == false)
lead.LR.UI.closeAll()
lead.LR.db.settings.mlAnnounce = true
srv:setMasterLooter(nil)
srv:tick(1)
mlBefore = #srv.chat
srv:setMasterLooter(lead)
srv:tick(1)
check("or tell the raid by itself, without asking", sheetTitle(lead) == nil and srv.chat[mlBefore + 1] and srv.chat[mlBefore + 1].text:find("is the master looter", 1, true) ~= nil)
lead.LR.db.settings.mlAnnounce, lead.LR.db.settings.mlPrompt = false, true
lead.LR.UI.win:Hide()

section("loot given out without LootRuler")
lead.LR.UI.closeAll()
srv:openLoot(lead, { { 30010, 4 }, { 30011, 4 } })
srv:tick(0.5)
-- the loot master uses the game's own loot menu
local function candidateIndex(slot, p) for i = 1, 40 do local n = lead.G.GetMasterLootCandidate(slot, i) if n and n:find(p.name, 1, true) then return i end end end
lead.G.GiveMasterLoot(1, candidateIndex(1, bob))
srv:tick(1)
local function sheetTitle2(p) local sh = p.LR.UI.topSheet() return sh and sh.title:GetText() end
check("the loot master is asked whether to record it", sheetTitle2(lead) == "Record it?")
check("with how they got it", #lead.M.findText("Off spec", true, lead.LR.UI.topSheet()) > 0 and #lead.M.findText("Leave it", true, lead.LR.UI.topSheet()) > 0)
clickText(lead, "Off spec", lead.LR.UI.topSheet())
srv:tick(1)
local recorded
for _, w in ipairs(s.won) do if w.i == 30010 and w.p == full(bob) and w.k == "OS" then recorded = true end end
check("recorded as off spec, and the raid is told", recorded and chat("goes to Bob-Faerlina (off spec, given out without a roll).") ~= nil)
Rolls.dismiss()
lead.G.GiveMasterLoot(2, candidateIndex(2, ann))
srv:tick(1)
clickText(lead, "Leave it", lead.LR.UI.topSheet())
local left = true
for _, w in ipairs(s.won) do if w.i == 30011 then left = false end end
check("or left off the list", left and sheetTitle2(lead) ~= "Record it?")
srv:closeLoot(lead)
lead.LR.UI.closeAll()
lead.LR.UI.win:Hide()
srv:tick(1)

section("when the game won't hand an item over")
srv:openLoot(lead, { { 30020, 4 }, { 30021, 4 } })
srv:tick(0.5)
srv.bagsFull = { [bob] = true }
local hr1 = Rolls.give(30020, full(bob), "MS", { link = srv:link(30020), slot = 1 })
srv:tick(1)
local function onList(id) for _, w in ipairs(s.won) do if w.i == id then return w.p end end end
check("Bob's bags are full: the award is taken back", hr1 and Rolls.mine().state == "closed" and onList(30020) == nil)
check("the raid hears it's still to give out", chat("couldn't go to Bob-Faerlina (their bags are full): it's still to give out.") ~= nil)
check("and the loot master why", lead.M.chat[#lead.M.chat]:find("their bags are full", 1, true) ~= nil)
check("raiders' copies don't have it either", (function() for _, w in ipairs(ann.LR.current().won or {}) do if w.i == 30020 then return false end end return true end)())
srv.bagsFull = nil
Rolls.dismiss()
Rolls.give(30020, full(ann), "MS", { link = srv:link(30020), slot = 1 })
srv:tick(3)
check("given to someone else instead, it stays given", onList(30020) == full(ann))
Rolls.dismiss()
-- the game says nothing, but the item is still there a moment later
srv.lostHandout = true
Rolls.give(30021, full(dan), "OS", { link = srv:link(30021), slot = 2 })
srv:tick(3)
check("an item still in the corpse after a moment: taken back too", onList(30021) == nil and chat("couldn't go to Dan (the game didn't hand it over)") ~= nil)
srv.lostHandout = nil
Rolls.dismiss()
srv:closeLoot(lead)
srv:tick(10)                     -- (what was sent goes out a little at a time)

section("roll window options")
local bobWindows = bob.LR.db.settings.rollWindow
bob.LR.db.settings.rollWindow = true
bob.LR.db.settings.rollHideUnusable = true
ann.LR.db.settings.rollCloseAfter = true
srv:openLoot(lead, { { HANDS, 4 } })
srv:tick(0.5)
Rolls.start(HANDS, { link = srv:link(HANDS), slot = 1 })
srv:tick(0.5)
check("a mage who leaves out what they can't use gets no window for a mace", frameFor(bob, HANDS) == nil and copyOf(bob, HANDS) ~= nil)
check("a priest gets one", frameFor(ann, HANDS) ~= nil)
srv:willRoll(ann, 42)
ann.M.click(frameFor(ann, HANDS).dice)
srv:tick(0.5)
check("she rolls, and the window stays a moment", Rolls.mine().rolled["ann-dreamscythe"] ~= nil and frameFor(ann, HANDS) ~= nil)
srv:tick(2)
check("then it goes, as she likes it, while the roll goes on", frameFor(ann, HANDS) == nil and Rolls.mine().state == "open")
Rolls.cancel()
srv:tick(0.5)
Rolls.dismiss()
srv:closeLoot(lead)
bob.LR.db.settings.rollWindow, bob.LR.db.settings.rollHideUnusable = bobWindows, false
ann.LR.db.settings.rollCloseAfter = false
srv:tick(1)

section("the loot master's own roll types")
lead.LR.db.settings.rollKinds = { { n = "Transmog", hi = 98 } }
srv:openLoot(lead, { { TALISMAN, 4 } })
srv:tick(0.5)
roll = Rolls.start(TALISMAN, { link = srv:link(TALISMAN), slot = 1 })
srv:tick(0.5)
check("raid chat says how to roll for it", chat("/roll 99 for off spec, /roll 98 for Transmog.", "RAID_WARNING") ~= nil)
local ft = frameFor(ann, TALISMAN)
check("Ann's window has a Transmog button", ft and ft.extras[1]:IsShown() and ft.extras[1]:IsEnabled() and ft.extras[1].text:GetText() == "Transmog (98)",
  ft and ft.extras[1].text:GetText())
srv:willRoll(ann, 70)
ann.M.click(ft.extras[1])
srv:roll(pug, 1, 98, 90)
srv:tick(0.3)
check("her button rolls 1-98, and it counts as Transmog", roll.rolled["ann-dreamscythe"] and roll.rolled["ann-dreamscythe"].kind == "X1"
  and roll.rolled["ann-dreamscythe"].hi == 98)
check("so does a /roll 98 typed by someone without the addon", roll.rolled["pug-dreamscythe"] and roll.rolled["pug-dreamscythe"].kind == "X1")
check("and she can't roll again", not frameFor(ann, TALISMAN).extras[1]:IsEnabled())
check("raiders see it by its name", status(ann, TALISMAN):find("Pug 90 (Transmog)", 1, true) ~= nil, status(ann, TALISMAN))
srv:tick(22)
check("the result says Transmog", chat("Pug wins with 90 (Transmog)") ~= nil)
clickText(lead, "Give to Pug", lead.G.LootRulerMasterFrame)
srv:tick(1)
check("given: off spec on the list, by its name", wonBy(s, TALISMAN):find(full(pug) .. ":OS", 1, true) ~= nil and s.won[#s.won].xn == "Transmog")
check("and the raid hears it", chat("goes to Pug (Transmog 90)") ~= nil)
check("raiders' copies have its name", ann.LR.current().won[#ann.LR.current().won].xn == "Transmog")
Rolls.dismiss()
srv:closeLoot(lead)
lead.LR.db.settings.rollKinds = {}
srv:tick(1)

section("item notes")
lead.LR.setNote(TALISMAN, "Hunters > Rogues")
-- and thatsmybis wishlists: Bob first, someone who isn't here, then Ann
lead.LR.db.wish = { [TALISMAN] = { { p = "Bob", n = 1 }, { p = "Nobody", n = 2 }, { p = "Ann", n = 3 } } }
local postedBefore = #srv.chat
srv:openLoot(lead, { { TALISMAN, 4 } })
srv:tick(0.5)
local posted = false
for i = postedBefore + 1, #srv.chat do if srv.chat[i].text:find("wishlisted by Bob-Faerlina (1), Ann (3)", 1, true) then posted = true end end
check("the loot post says who in the group wishlisted it", posted)
local nroll = Rolls.start(TALISMAN, { link = srv:link(TALISMAN), slot = 1 })
srv:tick(0.5)
check("rolling it out says the note in raid chat", chat("Note: Hunters > Rogues.", "RAID_WARNING") ~= nil)
local fn = frameFor(ann, TALISMAN)
check("and everyone's roll window shows it", fn and fn.note:IsShown() and fn.note:GetText():find("^Note: Hunters > Rogues\n") ~= nil, fn and fn.note:GetText())
check("raiders don't keep it as their own note", ann.LR.noteFor(TALISMAN) == nil)
local tips = lead.LR.UI.tooltipLines(s, TALISMAN)
check("the loot master sees it in the item's tooltip", tips[1] and tips[1][1] == "LootRuler note: Hunters > Rogues")
check("and the whole wishlist", tips[2] and tips[2][1] == "LootRuler wishlist: Bob (1), Nobody (2), Ann (3)", tips[2] and tips[2][1])
check("raid chat says who in the group wishlisted it", chat("Note: Hunters > Rogues. Wishlisted: Bob-Faerlina (1), Ann (3).", "RAID_WARNING") ~= nil)
check("so does the roll window", fn.note:GetText():find("Wishlist: Bob-Faerlina (1), Ann (3)", 1, true) ~= nil, fn.note:GetText())
Rolls.cancel()
srv:tick(0.5)
Rolls.dismiss()
-- a roll from the loot master with a note carrying colours and links: shown as plain text
local fake = lead.LR.Net.encode({ t = "R", k = "fake:1", id = TALISMAN, s = 20, left = 20, m = "OPEN", w = {}, nt = "|cffff0000Free|r |Hitem:1|h[loot]|h\nfor all" })
srv:addonMessage(lead, "LootRuler", fake, "RAID")
srv:tick(0.5)
check("a note from a message is made safe first", ann.LR.Rolls.seen["fake:1"] and ann.LR.Rolls.seen["fake:1"].note == "Free [loot] for all",
  ann.LR.Rolls.seen["fake:1"] and ann.LR.Rolls.seen["fake:1"].note)
srv:addonMessage(lead, "LootRuler", lead.LR.Net.encode({ t = "X", k = "fake:1", e = "cancelled" }), "RAID")
-- once Bob has it, he's off what's said
s.won[#s.won + 1] = { i = TALISMAN, p = "Bob-Faerlina", k = "MS", at = 1 }
check("whoever has been given it is left out", lead.LR.wishLine(lead.LR.wishFor(TALISMAN, true)) == "Ann (3)")
table.remove(s.won)
lead.LR.db.wish = {}
srv:closeLoot(lead)
lead.LR.setNote(TALISMAN, "")
srv:tick(1)
check("an empty note takes it off", lead.LR.noteFor(TALISMAN) == nil)

section("the 2 hours to trade running out")
local HELD, OWED = 28762, 28767
srv:lootTo(lead, HELD)
srv:lootTo(lead, OWED)
srv:tick(1)
local function heldDrop(id) for i = #s.drops, 1, -1 do local d = s.drops[i] if d.i == id and d.h == full(lead) then return d end end end
Rolls.start(OWED, { link = srv:link(OWED), drop = heldDrop(OWED).k })
srv:tick(0.5)
srv:roll(bob, 1, 100, 60)
srv:tick(1)
Rolls.stop()
srv:tick(1)
Rolls.award(full(bob))
srv:tick(1)
Rolls.dismiss()
local function notices() return table.concat(lead.M.notices, " | ") end
local n0 = #lead.M.notices
srv:tick(31)
check("nothing to warn about with plenty of time left", #lead.M.notices == n0)
-- 14 minutes left on both
for _, id in ipairs({ HELD, OWED }) do heldDrop(id).ht = lead.LR.U.now() - (lead.LR.Drops.TRADE_SECONDS - 14 * 60) end
srv:tick(31)
local said = table.concat({ unpack(lead.M.notices, n0 + 1) }, " | ")
check("15 minutes before: which item, who it's for, and how long is left", said:find("14 minutes left to trade [The Decapitator] to Bob-Faerlina.", 1, true) ~= nil, said)
check("and an item not rolled out yet says so", said:find("14 minutes left to roll out and trade [Adornment of Stolen Souls]: nobody has won it yet.", 1, true) ~= nil, said)
check("in the middle of the screen and in chat", #lead.M.notices == n0 + 2 and chatHasLead("left to trade"))
srv:tick(31)
check("once, not every check", #lead.M.notices == n0 + 2)
for _, id in ipairs({ HELD, OWED }) do heldDrop(id).ht = lead.LR.U.now() - (lead.LR.Drops.TRADE_SECONDS - 4 * 60) end
srv:tick(31)
check("and again at 5 minutes", #lead.M.notices == n0 + 4 and lead.M.notices[#lead.M.notices]:find("4 minutes left", 1, true) ~= nil, notices())
check("only on the loot master's screen", not noticed(ann, "left to trade") and not noticed(bob, "left to trade"))
lead.LR.db.settings.tradeWarn = false
srv:lootTo(lead, 28745)
srv:tick(1)
heldDrop(28745).ht = lead.LR.U.now() - (lead.LR.Drops.TRADE_SECONDS - 10 * 60)
srv:tick(31)
check("it can be turned off", #lead.M.notices == n0 + 4)
lead.LR.db.settings.tradeWarn = true

section("trade timers on screen")
local tw = lead.G.LootRulerTimers
local function timerRows()
  local out = {}
  for _, c in ipairs(tw._children) do if c:IsShown() and c.x then out[#out + 1] = c end end
  table.sort(out, function(a, b) return select(5, a:GetPoint(1)) > select(5, b:GetPoint(1)) end)
  return out
end
lead.LR.UI.tradeTimers()
local tr = timerRows()
local held0 = #lead.LR.Drops.holding()
check("the loot master sees a bar for each item they hold", tw and tw:IsShown() and #tr == held0 and #tr >= 3, tw and #tr)
check("the soonest to run out first", tr[1] and tr[1].x.left <= tr[2].x.left and tr[2].x.left <= tr[3].x.left)
local byId = {}
for _, r in ipairs(tr) do byId[r.x.d.i] = r end
check("a won item says who it's for", byId[OWED] and byId[OWED].name:GetText():find("Bob", 1, true) ~= nil and byId[OWED].x.state == "toTrade",
  byId[OWED] and byId[OWED].name:GetText())
check("with the time left", byId[OWED].time:GetText():match("^%dm$") ~= nil, byId[OWED].time:GetText())
check("raiders don't get it", not ann.G.LootRulerTimers or not ann.G.LootRulerTimers:IsShown())
-- clicking one not rolled out yet rolls it out
lead.M.click(byId[HELD])
srv:tick(0.5)
local tRoll = Rolls.mine()
check("click: it's rolled out", tRoll and tRoll.id == HELD and tRoll.state == "open" and tRoll.drop == byId[HELD].x.d.k)
Rolls.cancel()
srv:tick(0.5)
Rolls.dismiss()
-- clicking a won one opens a trade with the winner
lead.M.click(byId[OWED])
srv:tick(0.5)
check("click on a won one: a trade with the winner opens", lead.G.TradeFrame:IsShown() and lead.trading == bob)
srv:tick(1)
srv:completeTrade(lead)
srv:tick(1)
local stillThere = false
for _, r in ipairs(timerRows()) do if r.x.d.i == OWED then stillThere = true end end
check("once it's traded, its bar goes", #timerRows() == held0 - 1 and not stillThere, #timerRows())
-- the x hides it until another item comes in
lead.M.click(tw.close)
lead.LR.UI.tradeTimers()
check("the x hides it", not tw:IsShown())
srv:lootTo(lead, 28750)
srv:tick(1)
check("until another item comes in", tw:IsShown() and #timerRows() == held0)
lead.LR.db.settings.tradeTimers = false
lead.LR.UI.tradeTimers()
check("it can be turned off", not tw:IsShown())
lead.LR.db.settings.tradeTimers = true

section("ending the session")
lead.LR.endSession(s)
srv:tick(2)
check("the loot list goes with it, everywhere", lead.LR.current() == nil and ann.LR.current() == nil and bob.LR.current() == nil)
local kept = lead.LR.History.all()[1]
check("but it's kept under past raids, for the leader and raiders", kept and kept.id == s.id and #kept.won == #s.won and #kept.won > 0
  and ann.LR.History.all()[1] and ann.LR.History.all()[1].id == s.id)
check("and still exports", lead.LR.Export.text(kept, "csv"):find("Signet of Unshakable Faith", 1, true) ~= nil)

section("softres.it names spelled differently from the characters")
-- Ghøst (no addon) is in the raid; the sheet says "Ghost". Kåre isn't here yet; the sheet says "Kare".
local ghost = srv:player({ name = "Ghøst", class = "MAGE" })
local kare = srv:player({ name = "Kåre", class = "HUNTER" })
table.insert(srv.group.members, ghost) ghost.inGroup = true
srv:rosterChanged()
local sn = lead.LR.startSession("Karazhan", 2, true, false)
srv:tick(2)
local sum = lead.LR.Gargul.importInto(sn, lead.LR.Gargul.encode({ metadata = { id = "n1" }, hardreserves = {}, softreserves = {
  { name = "Ghost", class = "mage", items = { { id = ROYAL } } },
  { name = "kare", class = "hunter", items = { { id = BROOCH } } } } }))
srv:tick(2)
local S = lead.LR.Session
check("the reserve goes under the character's own spelling", S.reservesOf(sn, "Ghøst-Dreamscythe")[1] == ROYAL and #S.reservesOf(sn, "Ghost-Dreamscythe") == 0
  and #sum.matched == 1)
check("raiders' addons have it that way too", S.reservesOf(ann.LR.current(), "Ghøst-Dreamscythe")[1] == ROYAL)
check("Kare isn't here yet: kept as the sheet has it", S.reservesOf(sn, "Kare-Dreamscythe")[1] == BROOCH and #sum.missing == 1)
local roll = Rolls.start(ROYAL, { link = srv:link(ROYAL) })
srv:tick(1)
check("the item is rolled for by the reserve, not opened to everyone", roll and roll.mode == "SR" and #roll.who == 1 and roll.who[1][1] == "Ghøst-Dreamscythe"
  and #roll.away == 0)
check("raiders' windows say it's reserved", copyOf(ann, ROYAL) and copyOf(ann, ROYAL).mode == "SR")
srv:roll(ghost, 1, 100, 64)
srv:roll(dan, 1, 100, 99)
srv:tick(1)
Rolls.stop()
srv:tick(1)
local top = lead.LR.Roll.result(Rolls.mine())
check("Ghøst's roll counts, and someone who didn't reserve it doesn't", top and top.p == "Ghøst-Dreamscythe" and top.n == 64)
Rolls.dismiss()
-- Kåre joins: the sheet's "Kare" is him
table.insert(srv.group.members, kare) kare.inGroup = true
srv:rosterChanged()
srv:tick(3)
check("someone joining gets the reserves the sheet spelled without the accent", S.reservesOf(sn, "Kåre-Dreamscythe")[1] == BROOCH and #S.reservesOf(sn, "Kare-Dreamscythe") == 0)
check("raiders' addons hear about it", S.reservesOf(ann.LR.current(), "Kåre-Dreamscythe")[1] == BROOCH)

section("who reserved it, for everyone")
-- seven players reserved the signet: six here, one not
for _, x in ipairs({ { "Lead-Dreamscythe", "PALADIN" }, { "Ann-Dreamscythe", "PRIEST" }, { "Bob-Faerlina", "MAGE" }, { "Pug-Dreamscythe", "WARRIOR" },
  { "Ghøst-Dreamscythe", "MAGE" }, { "Kåre-Dreamscythe", "HUNTER" }, { "Cara-Dreamscythe", "DRUID" } }) do
  lead.LR.leaderAdd(sn, x[1], x[2], SIGNET)
end
srv:tick(2)
-- the game's loot window, on Dan's screen (he reserved nothing)
srv:openLoot(dan, { { SIGNET, 4 }, { BROOCH, 4 }, { HANDWRAPS, 4 } })
lead.LR.setHR(sn, HANDWRAPS, "Ann", "")
srv:tick(2)
for i = 1, 3 do dan.G.LootFrame_UpdateButton(i) end
local b1, b2, b3 = dan.G.LootButton1, dan.G.LootButton2, dan.G.LootButton3
check("the loot window marks a reserved item for everyone", b1.lrTag and b1.lrTag:IsShown() and dan.M.plain(b1.lrTag:GetText()) == "SR"
  and not (b1.lrGlow and b1.lrGlow:IsShown()))
check("with who reserved it, as many as fit", dan.M.plain(b1.lrWho:GetText()):find("^Ann") ~= nil and dan.M.plain(b1.lrWho:GetText()):find("+%d$") ~= nil,
  dan.M.plain(b1.lrWho:GetText()))
check("one reserver: their name", dan.M.plain(b2.lrWho:GetText()) == "Kåre", dan.M.plain(b2.lrWho:GetText()))
check("a hard reserve says who for", dan.M.plain(b3.lrTag:GetText()) == "HR" and dan.M.plain(b3.lrWho:GetText()) == "For Ann")
check("the item's name moves up to make room", dan.G.LootButton1Text:GetHeight() == 25)
dan.LR.db.settings.lootTags = false
dan.G.LootFrame_UpdateButton(1)
check("which can be turned off, and the name goes back", not b1.lrTag:IsShown() and dan.G.LootButton1Text:GetHeight() == 38)
dan.LR.db.settings.lootTags = true
srv:closeLoot(dan)
lead.LR.clearHR(sn, HANDWRAPS)
-- the strip, while it's rolled for: everyone, in full (the loot window only has room for a name or two)
local strip = function(p) return p.G.LootRulerReserveStrip end
check("no strip before a roll", not (strip(dan) and strip(dan):IsShown()))
Rolls.start(SIGNET, { link = srv:link(SIGNET) })
srv:tick(1)
local names = strip(dan) and dan.M.plain(strip(dan).names:GetText()) or ""
check("a roll starts: the strip lists everyone who reserved it", strip(dan) and strip(dan):IsShown()
  and names:find("Ann, Bob-Faerlina, Ghøst, Kåre, Lead, Pug", 1, true) ~= nil and not names:find("+", 1, true), names)
check("and who isn't here", names:find("Not here: Cara", 1, true) ~= nil)
check("the loot master sees it too", strip(lead) and strip(lead):IsShown())
check("with roll windows off, the strip still shows (it has its own switch)", strip(dan):IsShown() and frameFor(dan, SIGNET) == nil)
check("Ann sees her roll window and the strip", frameFor(ann, SIGNET) ~= nil and strip(ann) and strip(ann):IsShown())
ann.M.click(frameFor(ann, SIGNET).pass)
srv:tick(0.5)
check("she closes the roll window with its x: the strip goes too, while the roll goes on", not strip(ann):IsShown() and strip(lead):IsShown()
  and strip(dan):IsShown() and Rolls.mine().state == "open")
lead.M.click(lead.G.LootRulerMasterFrame.close)
srv:tick(0.5)
check("the loot master hides their window: the strip goes", not strip(lead):IsShown())
lead.LR.UI.showMaster()
srv:tick(0.5)
check("and comes back with it (/lr master)", strip(lead):IsShown())
Rolls.cancel()
srv:tick(1)
check("the roll ends: the strip goes", not strip(dan):IsShown() and not strip(lead):IsShown())
-- a roll Gargul runs: read from its line in raid chat
local gargulSays = function(text) dan.M.fire("CHAT_MSG_RAID_WARNING", text, "Lead-Dreamscythe") end
gargulSays("You have 20 seconds to roll on " .. srv:link(SIGNET))
check("a Gargul roll shows the strip too", strip(dan):IsShown() and dan.M.plain(strip(dan).names:GetText()):find("Kåre", 1, true) ~= nil)
gargulSays("10 seconds to roll")
check("its countdown leaves it up", strip(dan):IsShown())
gargulSays("Stop your rolls!")
check("\"Stop your rolls!\" takes it down", not strip(dan):IsShown())
gargulSays("You have 20 seconds to roll on " .. srv:link(SIGNET))
gargulSays(srv:link(SIGNET) .. " was awarded to Ann. Congrats!")
check("so does the item being given out", not strip(dan):IsShown())
gargulSays("You have 20 seconds to roll on " .. srv:link(SIGNET))
dan.M.fire("CHAT_MSG_LOOT", "Ann receives loot: " .. srv:link(SIGNET) .. ".")
check("and it goes when someone loots the item", not strip(dan):IsShown())
gargulSays("You have 20 seconds to roll on " .. srv:link(SIGNET))
srv:tick(25)
check("or when its time is up", not strip(dan):IsShown() and dan.LR.Gargul.roll == nil)
-- a raider without Gargul gets a roll window for Gargul's roll, like one of LootRuler's
local function annSays(text) ann.M.fire("CHAT_MSG_RAID_WARNING", text, "Lead-Dreamscythe") end
local OPENITEM = 28745                     -- (nobody reserved it: everyone rolls)
annSays("You have 20 seconds to roll on " .. srv:link(OPENITEM))
srv:tick(0.5)
local gw = frameFor(ann, OPENITEM)
check("Gargul rolls an item: Ann (no Gargul) gets a roll window for it", gw ~= nil and gw.copy.gargul and gw.dice:IsEnabled() and gw.coin:IsShown())
srv:willRoll(ann, 55)
ann.M.click(gw.dice)
srv:tick(1)
check("its dice just /roll (1-100), for Gargul to count", status(ann, OPENITEM):find("You rolled 55", 1, true) ~= nil
  and gw.copy.rolled[ann.LR.Roll.key(full(ann))].n == 55, status(ann, OPENITEM))
srv:roll(bob, 1, 100, 77)
srv:tick(1)
check("everyone's /rolls show in it", status(ann, OPENITEM):find("77", 1, true) ~= nil, status(ann, OPENITEM))
annSays("Stop your rolls!")
srv:tick(0.5)
check("Gargul stops the rolls: the window says Gargul gives it out", status(ann, OPENITEM):find("Gargul gives it out", 1, true) ~= nil, status(ann, OPENITEM))
annSays(srv:link(OPENITEM) .. " was awarded to Bob-Faerlina. Congrats!")
srv:tick(0.5)
check("and who it went to", status(ann, OPENITEM):find("Given to Bob-Faerlina", 1, true) ~= nil, status(ann, OPENITEM))
-- a reserved item: only the reservers roll, as with LootRuler's rolls
annSays("You have 20 seconds to roll on " .. srv:link(SIGNET))
srv:tick(0.5)
local gs = frameFor(ann, SIGNET)
check("on a reserved item, its window says who reserved it, and Ann can roll (she did)", gs and gs.copy.mode == "SR" and gs.dice:IsEnabled())
check("and she's told it's her item, for Gargul's rolls too", noticed(ann, "You reserved [Signet of Unshakable Faith]: roll for it now!"))
check("with the strip of reservers", strip(ann):IsShown())
ann.M.click(gs.pass)
srv:tick(0.3)
check("closing the window takes the strip too", not strip(ann):IsShown())
annSays("Stop your rolls!")
srv:tick(0.5)
-- a raider with Gargul: Gargul shows its own window, so LootRuler only shows the strip
ann.G.Gargul = {}
annSays("You have 20 seconds to roll on " .. srv:link(SIGNET))
srv:tick(0.5)
check("someone with Gargul gets no second window, just the strip", (frameFor(ann, SIGNET) == nil or not frameFor(ann, SIGNET).copy.gargul or frameFor(ann, SIGNET).copy.state ~= "open") and strip(ann):IsShown())
annSays("Stop your rolls!")
srv:tick(0.5)
ann.G.Gargul = nil
ann.LR.db.settings.gargulWindows = false
annSays("You have 20 seconds to roll on " .. srv:link(OPENITEM))
srv:tick(0.5)
check("switched off: no window", frameFor(ann, OPENITEM) == nil or frameFor(ann, OPENITEM).copy.state ~= "open")
annSays("Stop your rolls!")
ann.LR.db.settings.gargulWindows = true
srv:tick(0.5)
dan.LR.db.settings.reserveStrip = false
gargulSays("You have 20 seconds to roll on " .. srv:link(SIGNET))
check("the strip can be turned off", not strip(dan):IsShown())
dan.LR.db.settings.reserveStrip = true
dan.LR.Gargul.endRoll()

lead.LR.endSession(sn)
srv:tick(2)

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
