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
check("the item goes to Dan", srv.given[4] and srv.given[4].id == ROYAL and srv.given[4].to == dan)
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
