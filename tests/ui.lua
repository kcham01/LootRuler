-- The window, clicked through like a raid leader and a raider would, with the rest of the raid's clients
-- running alongside (tests/wow/server.lua). Checks what appears, that clicks do what they say, that nothing
-- errors or leaks frames, and writes each screen as build/shots/NN-name.json for tools/render.mjs to draw.
--   lua5.1 tests/ui.lua
package.path = "./tests/?.lua;./tests/wow/?.lua;" .. package.path
local Server = require("server")
local ICONS = dofile("tests/fixtures/icons.lua")

local failed, passed = 0, 0
local function check(name, ok, detail)
  if ok then passed = passed + 1 else failed = failed + 1 end
  print((ok and "ok   " or "FAIL ") .. name .. ((not ok and detail ~= nil) and ("  " .. tostring(detail)) or ""))
end
local function run(name, fn)
  print("== " .. name)
  local ok, err = pcall(fn)
  if not ok then check(name, false, err) end
end

local srv = Server.new(".")
-- every item is loaded in these clients: names and links from the data, icons from Wowhead's names
local DATA = {}
do
  local env = setmetatable({}, { __index = _G })
  local chunk = assert(loadfile("LootRuler/Data/Loot.lua"))
  setfenv(chunk, env)
  chunk("LootRuler", DATA)
end
local QHEX = { [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }
srv.itemInfo = function(id)
  local it = DATA.ITEMS[id]
  if not it then return nil end
  return { name = it[1], quality = it[2], link = ("|cff%s|Hitem:%d::::::::70:::::|h[%s]|h|r"):format(QHEX[it[2]] or "ffffff", id, it[1]) }
end

local lead = srv:client({ name = "Lead", class = "PALADIN", guild = "Kings", rank = 1 })   -- an officer
local ann = srv:client({ name = "Ann", class = "PRIEST", guild = "Kings" })
local bob = srv:client({ name = "Bob", class = "MAGE", realm = "Faerlina" })
local pug = srv:player({ name = "Pug", class = "WARRIOR" })
local function icons(p)
  p.G.C_Item.GetItemIconByID = function(id) return ICONS[id] and ("Interface\\Icons\\" .. ICONS[id]) or 134400 end
  p.M.describeLink = function(link)
    local id = tonumber(link:match("item:(%d+)"))
    local it = DATA.ITEMS[id]
    if not it then return nil end
    local hex = QHEX[it[2]] or "ffffff"
    return { { it[1], tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }, { "Item Level " .. it[6], 1, 0.82, 0 } }
  end
end
for _, p in ipairs({ lead, ann, bob }) do icons(p) end
srv:setGroup({ lead, ann, bob, pug }, lead, true)
srv:tick(6)

-- a stand-in for Gargul on the leader's client: records what it's given
local gargulGot = {}
lead.G.Gargul = { SoftRes = { import = function(_, str, show) gargulGot[#gargulGot + 1] = { str = str, show = show } return true end },
  PlusOnes = { getPlusOnes = function() return 0 end } }

local M, G, LR = lead.M, lead.G, lead.LR

-- screens for the renderer
local function json(v)
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "boolean" then return v and "true" or "false" end
  if t == "number" then return (v ~= v or v == math.huge or v == -math.huge) and "0" or string.format("%.4f", v):gsub("%.?0+$", "") end
  if t == "string" then return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"' end
  local isList = #v > 0 or next(v) == nil
  local out = {}
  if isList then for i = 1, #v do out[i] = json(v[i]) end return "[" .. table.concat(out, ",") .. "]" end
  for k, x in pairs(v) do out[#out + 1] = json(tostring(k)) .. ":" .. json(x) end
  return "{" .. table.concat(out, ",") .. "}"
end
os.execute("mkdir -p build/shots && rm -f build/shots/*.json build/shots/*.png")
local shotN = 0
local function shot(name, who, focus)
  who = who or lead
  shotN = shotN + 1
  local f = assert(io.open(("build/shots/%02d-%s.json"):format(shotN, name), "w"))
  f:write(json({ w = 1280, h = 800, ops = who.M.render(), focus = focus }))
  f:close()
end

local function root(p) p = p or lead return p.LR.UI.topSheet() or p.G.LootRulerFrame end
local function find(text, p) return (p or lead).M.findText(text, true, root(p)) end
local function visible(text, p) return #find(text, p) > 0 end
local function clickText(text, nth, p)
  local list = find(text, p)
  local exact, clickable = {}, {}
  for _, x in ipairs(list) do
    if x.clickable then
      clickable[#clickable + 1] = x
      if (p or lead).M.plain(x.fs:GetText()) == text then exact[#exact + 1] = x end
    end
  end
  local pick = (#exact > 0 and exact or clickable)[nth or 1]
  if not pick or not pick.clickable then error("nothing clickable with text " .. text, 2) end
  (p or lead).M.click(pick.clickable)
  srv:tick(0.3)
end
local function rowFor(name, p)
  local any
  for _, x in ipairs(find(name, p)) do
    if x.frame._kind == "item" then
      if x.frame._scripts.OnClick then return x.frame end
      any = any or x.frame
    end
  end
  return any
end

run("opening the window", function()
  G.SlashCmdList.LOOTRULER("")
  srv:tick(0.3)
  check("/lr opens the window", G.LootRulerFrame:IsShown())
  check("nothing open yet", visible("No soft reserves open"))
  check("the minimap button", G.LootRulerMinimapButton ~= nil)
  check("loot to browse without a session", visible("Browse the loot") and visible("Attumen the Huntsman"))
  shot("empty")
end)

run("browsing the loot", function()
  clickText("Molten Core")
  check("an original raid", visible("Ragnaros") and visible("Lucifron"))
  check("for my class: a paladin sees plate, not cloth", visible("Lawbringer Helm") and not visible("Robes of Prophecy"))
  clickText("Search every raid")
  check("searching every raid wants some letters", visible("Type at least two letters"))
  local box
  local function walk(f) for _, c in ipairs(f._children) do if c._type == "EditBox" and c:IsVisible() then box = c end walk(c) end end
  walk(G.LootRulerFrame)
  M.click(box)
  M.type("ashkandi", function() srv:tick(0.2) end)
  check("finds a sword in Blackwing Lair", visible("Ashkandi, Greatsword of the Brotherhood") and visible("Blackwing Lair"))
  shot("browse")
  box:SetText("") box._scripts.OnTextChanged(box, true) box._scripts.OnEnterPressed(box)
  srv:tick(0.3)
  clickText("Karazhan")
end)

run("opening reserves", function()
  clickText("Session")
  check("the setup form", visible("Open soft reserves") and visible("Black Temple"))
  clickText("Karazhan")
  shot("new-session")
  clickText("Open reserves")
  srv:tick(2)
  local s = LR.current()
  check("a Karazhan session with 2 each", s and s.raid == "Karazhan" and s.sr == 2 and s.dupes and s.guild)
  check("the session panel", visible("Your session") and visible("Hard reserves"))
  check("raiders have it", ann.LR.current() and ann.LR.current().id == s.id)
end)

local s = LR.current()

run("raiders reserve", function()
  ann.LR.reserve(ann.LR.current(), 28528)
  ann.LR.reserve(ann.LR.current(), 28528)
  bob.LR.reserve(bob.LR.current(), 28507)
  srv:whisper(pug, lead, "!lr |cffa335ee|Hitem:28530::::::::70:::::|h[Brooch of Unquenchable Fury]|h|r")
  srv:tick(2)
  check("everyone's reserves reach the leader", #LR.Session.players(s) == 3)
end)

run("the leader reserves", function()
  clickText("Reserve")
  check("the loot list", visible("Attumen the Huntsman") and visible("Moroes"))
  check("Usable by me hides what a paladin can't use", not visible("Steelhawk Crossbow") and visible("Royal Cloak of Arathi Kings"))
  local row = rowFor("Royal Cloak of Arathi Kings")
  M.click(row, "LeftButton")
  srv:tick(1)
  check("click to reserve", LR.Session.reservesOf(s, "Lead-Dreamscythe")[1] == 28529)
  check("it's at the top", visible("Your reserves") and #find("Royal Cloak of Arathi Kings") >= 2)
  check("the count", visible("1 / 2"))
  M.click(rowFor("Royal Cloak of Arathi Kings"), "RightButton")
  srv:tick(1)
  check("right-click takes it back", #LR.Session.reservesOf(s, "Lead-Dreamscythe") == 0)
  M.click(rowFor("Royal Cloak of Arathi Kings"), "LeftButton")
  M.click(rowFor("Moroes' Lucky Pocket Watch"), "LeftButton")
  srv:tick(1)
  check("a second reserve", #LR.Session.reservesOf(s, "Lead-Dreamscythe") == 2)
  check("who else reserved it shows", visible("Ann x2"))
  shot("reserve")
  M.click(rowFor("Signet of Unshakable Faith"), "LeftButton")
  srv:tick(1)
  check("a third is refused, with a message", #LR.Session.reservesOf(s, "Lead-Dreamscythe") == 2 and visible("You have no reserves left."))
  srv:tick(3)
end)

run("searching", function()
  clickText("For my class")
  check("all items with the filter off", visible("Steelhawk Crossbow"))
  local box
  local function walk(f) for _, c in ipairs(f._children) do if c._type == "EditBox" and c:IsVisible() then box = c end walk(c) end end
  walk(G.LootRulerFrame)
  M.click(box)
  M.type("sword", function() srv:tick(0.2) end)
  check("search keeps every key", box:GetText() == "sword", box:GetText())
  check("and filters", not visible("Royal Cloak of Arathi Kings", lead) or visible("Your reserves"))
  shot("search")
  box:SetText("") box._scripts.OnTextChanged(box, true) box._scripts.OnEnterPressed(box)
  srv:tick(0.3)
  clickText("For my class")
end)

run("hard reserves", function()
  clickText("Session")
  clickText("Add a hard reserve")
  check("the item picker", visible("Hard reserve an item") and visible("Prince Malchezaar"))
  shot("pick")
  M.click(rowFor("Moroes' Lucky Pocket Watch"))
  srv:tick(0.3)
  check("the hard reserve panel", visible("For (optional)") and visible("Soft reserved by"))
  local boxes = {}
  local function walk(f) for _, c in ipairs(f._children) do if c._type == "EditBox" and c:IsVisible() then boxes[#boxes + 1] = c end walk(c) end end
  walk(root())
  M.click(boxes[1])
  M.type("Ann")
  M.click(boxes[2])
  M.type("healer prio")
  shot("hard-reserve")
  clickText("Hard reserve")
  srv:tick(2)
  check("hard reserved, for Ann", s.hr[28528] and s.hr[28528].f == "Ann" and s.hr[28528].n == "healer prio")
  check("soft reserves on it were taken away", #LR.Session.reservesOf(s, "Ann-Dreamscythe") == 0 and #LR.Session.reservesOf(s, "Lead-Dreamscythe") == 1)
  check("it's listed", visible("For Ann"))
  check("raiders see it", ann.LR.current().hr[28528] ~= nil)
  shot("session")
end)

run("the reserves list", function()
  clickText("Reserves")
  check("leader tools", visible("Send to Gargul") and visible("Copy for Gargul") and visible("Lock reserves"))
  check("with a reminder for who hasn't reserved, and how many", visible("Remind who hasn't reserved (1)"))
  local n = #srv.chat
  clickText("Remind who hasn't reserved (1)")
  srv:tick(1)
  check("one click tells the raid", #srv.chat == n + 1 and srv.chat[#srv.chat].text:find("Not reserved yet: Ann.", 1, true) ~= nil, srv.chat[#srv.chat].text)
  check("by item", visible("Brooch of Unquenchable Fury") and visible("Hard reserves"))
  shot("reserves")
  clickText("By player")
  check("by player", visible("Pug") and visible("Bob-Faerlina"))
  check("who hasn't reserved", (visible("haven't reserved anything yet") or visible("hasn't reserved anything yet")) and visible("nothing reserved"))
  check("and who doesn't have LootRuler (they whisper)", visible("1 player in the group doesn't have LootRuler") and visible("no addon"))
  shot("by-player")
  -- take Bob's reserve away
  M.click(rowFor("Handwraps of Flowing Thought").act)
  srv:tick(2)
  check("the leader takes a reserve away", #LR.Session.reservesOf(s, "Bob-Faerlina") == 0)
  check("Bob's addon agrees", #bob.LR.myPicks(bob.LR.current()) == 0)
  clickText("Add a reserve for Bob-Faerlina")
  local sheet = LR.UI.topSheet()
  check("the picker says how many he has left", visible("(2 of 2 left)") and visible("This stays open until you're done"))
  M.click(rowFor("Shadow-Cloak of Dalaran"))
  srv:tick(2)
  check("the leader adds one for him", LR.Session.reservesOf(s, "Bob-Faerlina")[1] == 28570)
  check("the picker stays open, and says what was added", LR.UI.topSheet() == sheet and visible("Added for Bob-Faerlina") and visible("(1 of 2 left)"))
  -- far down the list: picking there keeps the list where it was
  sheet.scroll:SetVerticalScroll(600)
  M.click(rowFor("Ruby Drape of the Mysticant"))
  srv:tick(2)
  check("a second pick, for the same player", #LR.Session.reservesOf(s, "Bob-Faerlina") == 2 and visible("(0 of 2 left)"))
  check("the list didn't jump back to the top", sheet.scroll:GetVerticalScroll() == 600, sheet.scroll:GetVerticalScroll())
  M.click(rowFor("Harbinger Bands"))
  srv:tick(2)
  check("it stops at his limit", #LR.Session.reservesOf(s, "Bob-Faerlina") == 2 and visible("has no reserves left"))
  sheet.scroll:SetVerticalScroll(0)
  shot("reserve-for-player")
  M.click(rowFor("Ruby Drape of the Mysticant"))
  srv:tick(2)
  check("clicking one again takes it off", #LR.Session.reservesOf(s, "Bob-Faerlina") == 1 and visible("Took") and visible("(1 of 2 left)"))
  check("Bob's addon agrees", bob.LR.myPicks(bob.LR.current())[1] == 28570 and #bob.LR.myPicks(bob.LR.current()) == 1)
  clickText("Done")
  check("Done closes it", LR.UI.topSheet() == nil)
  clickText("By item")
end)

run("Gargul", function()
  clickText("Copy for Gargul")
  check("the Gargul text to copy", visible("Copy for Gargul") and #find("Gargul's soft-reserve importer") > 0)
  shot("copy")
  LR.UI.closeAll()
  clickText("Send to Gargul")
  check("Gargul gets the reserves", #gargulGot == 1 and gargulGot[1].show == true)
  local data = LR.Gargul.decode(gargulGot[1].str)
  check("all of them", data and #data.softreserves == 3 and #data.hardreserves == 1)
  check("the list says Gargul is up to date", visible("Gargul has the reserves as they are now."))
  clickText("Lock reserves")
  srv:tick(2)
  check("locking sends them again", #gargulGot == 2 and s.locked)
  check("raiders see the lock", ann.LR.current().locked)
  clickText("Unlock reserves")
  srv:tick(2)
end)

run("softres.it import", function()
  -- Zed isn't in the group yet; "Pùg" is Pug with an accent; "Bobb" is a typo for Bob (from another realm)
  local site = LR.Gargul.encode({ metadata = { id = "x1" }, hardreserves = {}, softreserves = {
    { name = "Zed", class = "rogue", items = { { id = 28524 } } },
    { name = "Pùg", class = "warrior", items = { { id = 28477 } } },
    { name = "Bobb", class = "mage", items = { { id = 28766 } } } } })
  clickText("Session")
  clickText("Import from softres.it")
  local box
  local function walk(f) for _, c in ipairs(f._children) do if c._type == "EditBox" and c:IsVisible() then box = c end walk(c) end end
  walk(root())
  M.click(box)
  box:SetText(site) box._scripts.OnTextChanged(box, true)
  shot("import")
  clickText("Import")
  srv:tick(2)
  check("reserves from softres.it are added", LR.Session.reservesOf(s, "Zed-Dreamscythe")[1] == 28524)
  check("a name spelled with an accent goes to the player in the group", LR.U.indexOf(LR.Session.reservesOf(s, "Pug-Dreamscythe"), 28477)
    and #LR.Session.reservesOf(s, "Pùg-Dreamscythe") == 0)
  check("the summary says so", visible("From softres.it") and visible("Pùg is Pug"))
  check("and asks about a name nobody has, with a click to fix it", visible("Nobody in the group is called Bobb") and visible("Bobb -> Bob-Faerlina"))
  check("and lists who isn't here yet", visible("Not in the group yet: Zed"))
  shot("import-names")
  LR.UI.closeAll()
  -- the Reserves tab asks too, under the name
  clickText("Reserves")
  clickText("By player")
  check("the Reserves tab offers the same fix", visible("Bobb -> Bob-Faerlina"))
  shot("import-names-by-player")
  clickText("Bobb -> Bob-Faerlina")
  srv:tick(2)
  check("one click moves the reserve to Bob", LR.Session.reservesOf(s, "Bob-Faerlina")[2] == 28766 and #LR.Session.reservesOf(s, "Bobb-Dreamscythe") == 0
    and LR.Session.reservesOf(bob.LR.current(), "Bob-Faerlina")[2] == 28766)
  check("and the question goes away", not visible("Bobb -> Bob-Faerlina"))
  LR.leaderRemove(s, "Bob-Faerlina", 28766)
  LR.leaderRemove(s, "Pug-Dreamscythe", 28477)
  srv:tick(2)
  clickText("By item")
  clickText("Session")
end)

run("a raider's window", function()
  ann.G.SlashCmdList.LOOTRULER("")
  srv:tick(0.3)
  check("Ann's window shows the session", visible("Karazhan", ann) and visible("By Lead", ann))
  ann.M.click(rowFor("Garona's Signet Ring", ann))
  srv:tick(1)
  check("Ann reserves from her window", ann.LR.myPicks(ann.LR.current())[1] == 28649 and LR.Session.reservesOf(s, "Ann-Dreamscythe")[1] == 28649)
  check("the hard reserve shows", visible("HR", ann))
  shot("raider", ann)
  local db = srv:logout(lead)
  srv:tick(1)
  ann.M.click(rowFor("Moroes' Lucky Pocket Watch", ann))
  ann.M.click(rowFor("Royal Cloak of Arathi Kings", ann))
  srv:tick(1)
  check("hard reserved: refused", ann.LR.myPicks(ann.LR.current())[2] == 28529)
  check("with the leader away the picks wait", ann.LR.pending(ann.LR.current()) and visible("NOT SENT YET", ann))
  shot("raider-waiting", ann)
  srv:login(lead, db)
  icons(lead)
  M, G, LR = lead.M, lead.G, lead.LR
  srv:tick(8)
  s = LR.current()
  check("they're sent when the leader is back", not ann.LR.pending(ann.LR.current()) and LR.Session.reservesOf(s, "Ann-Dreamscythe")[2] == 28529)
  ann.LR.UI.go("session")
  check("raiders see the session's rules", visible("Session by Lead", ann))
  shot("raider-session", ann)
end)

run("rolling out loot", function()
  -- the game's loot window, as a stand-in for the pictures (the panel sits beside it)
  local lf = G.CreateFrame("Frame", "LootStandIn", G.LootFrame, "BackdropTemplate")
  lf:SetAllPoints()
  lf:SetBackdrop(LR.K.ROCK)
  local t = lf:CreateFontString(nil, "OVERLAY") t:SetFontObject("GameFontNormal") t:SetPoint("TOPLEFT", 18, -16) t:SetText("Items")
  local items = { { 28529, 4 }, { 28525, 4 }, { 28528, 4 }, { 28530, 4 } }
  for i, it in ipairs(items) do
    local ic = lf:CreateTexture(nil, "ARTWORK") ic:SetSize(34, 34) ic:SetPoint("TOPLEFT", 18, -40 - (i - 1) * 42) ic:SetTexture(G.C_Item.GetItemIconByID(it[1]))
    local n = lf:CreateFontString(nil, "OVERLAY") n:SetFontObject("GameFontNormalSmall") n:SetPoint("LEFT", ic, "RIGHT", 6, 0) n:SetWidth(126)
    n:SetText(srv.itemInfo(it[1]).link:gsub("|H.-|h%[(.-)%]|h", "%1"))
  end
  srv:setMasterLooter(lead)
  if LR.UI.win then LR.UI.win:Hide() end
  if ann.LR.UI.win then ann.LR.UI.win:Hide() end
  srv:openLoot(lead, items)
  srv:tick(0.5)
  local panel = G.LootRulerLootPanel
  check("the loot panel beside the loot window", panel and panel:IsShown() and #M.findText("Click an item to roll it out", true, panel) > 0)
  check("with who reserved what", #M.findText("SR: Ann, Lead", true, panel) > 0 and #M.findText("Hard reserved for Ann", true, panel) > 0, s.res["Lead-Dreamscythe"] and s.res["Lead-Dreamscythe"].i[1])
  shot("loot-panel", lead, { "LootStandIn", "LootRulerLootPanel" })
  -- roll out the cloak Ann and the leader reserved
  local hit
  for _, x in ipairs(M.findText("Royal Cloak of Arathi Kings", true, panel)) do if x.clickable then hit = x.clickable end end
  M.click(hit)
  srv:tick(0.5)
  local roll = LR.Rolls.mine()
  check("clicking it rolls it out, for the reservers", roll and roll.mode == "SR" and roll.id == 28529)
  local mine
  for _, f in ipairs(ann.LR.UI.rollFrames()) do if f:IsShown() then mine = f end end
  check("Ann's roll window", mine and mine.dice:IsEnabled() and mine.status:GetText():find("You reserved this", 1, true), mine and mine.status:GetText())
  srv:willRoll(ann, 88)
  srv:tick(2)
  shot("roll-window", ann, { "LootRulerRollFrame1" })
  ann.M.click(mine.dice)
  srv:roll(pug, 1, 100, 99)
  srv:willRoll(lead, 41)
  for _, f in ipairs(LR.UI.rollFrames()) do if f:IsShown() then M.click(f.dice) end end
  srv:tick(1)
  check("the loot master sees the rolls", #M.findText("Ann", true, G.LootRulerMasterFrame) > 0 and #M.findText("didn't reserve it", true, G.LootRulerMasterFrame) > 0)
  srv:tick(3)
  check("everyone who reserved it rolled: it closes", roll.state == "closed")
  check("Ann is picked to get it", #M.findText("Give to Ann", true, G.LootRulerMasterFrame) > 0)
  shot("loot-master", lead, { "LootStandIn", "LootRulerLootPanel", "LootRulerMasterFrame" })
  M.click(M.findText("Give to Ann", true, G.LootRulerMasterFrame)[1].clickable)
  srv:tick(1)
  check("given to Ann", srv.given and srv.given[1].id == 28529 and s.won and s.won[1].p == "Ann-Dreamscythe" and s.won[1].k == "SR")
  -- the next item: nobody reserved it, so everyone rolls; Bob sees both windows
  M.click(M.findText("Close", true, G.LootRulerMasterFrame)[1].clickable)
  for _, x in ipairs(M.findText("Signet of Unshakable Faith", true, panel)) do if x.clickable then hit = x.clickable end end
  M.click(hit)
  srv:tick(0.5)
  srv:roll(pug, 1, 100, 57)
  srv:tick(4)
  local shown = 0
  for _, f in ipairs(bob.LR.UI.rollFrames()) do if f:IsShown() then shown = shown + 1 end end
  check("Bob sees the finished roll and the new one", shown == 2)
  shot("roll-windows", bob, { "LootRulerRollFrame1", "LootRulerRollFrame2" })
  LR.Rolls.cancel()
  srv:closeLoot(lead)
  srv:tick(1)
  check("the panel goes with the loot window", not panel:IsShown())
  srv:tick(9)                                -- finished roll windows go after a few seconds
  LR.UI.show("reserves")
  srv:tick(0.3)
  check("a reserve that's won its item shows it on the Reserves tab", visible("Ann (won)"))
  LR.UI.go("loot")
  srv:tick(0.3)
  check("the Loot tab lists what dropped, boss by boss", visible("4 items dropped, 1 given out, 3 still to roll for") and visible("Moroes"))
  check("with who won what", visible("Won by Ann (SR 88)"))
  check("and what's still on the corpse, and who reserved it", visible("On the corpse. Hard reserved for Ann") and visible("On the corpse. SR: Pug"))
  check("the loot master can roll things out from it", #find("Roll") >= 3)
  shot("loot-tab")
  clickText("Export")
  check("export who won what", visible("Export who won what") and visible("Spreadsheet (CSV)"))
  clickText("thatsmybis")
  local box
  local function walk(fr) for _, c in ipairs(fr._children) do if c._type == "EditBox" and c:IsVisible() and c._multi then box = c end walk(c) end end
  walk(root())
  check("in thatsmybis' format", box and box:GetText():find("^dateTime,character,itemID,offspec,id") ~= nil and box:GetText():find(",Ann,28529,0,", 1, true) ~= nil, box and box:GetText())
  shot("export")
  LR.UI.closeAll()
  local before = #pug.inbox
  clickText("Post in raid chat")
  srv:tick(1)
  check("and post it in raid chat for everyone", #pug.inbox > before and pug.inbox[#pug.inbox].text:find("Loot given out:", 1, true) ~= nil)
  ann.LR.UI.show("loot")
  srv:tick(0.3)
  check("raiders see the same list", visible("Won by Ann (SR 88)", ann) and visible("Yours", ann))
  check("but can't roll from it", not visible("Roll", ann) or #ann.M.findText("Roll", true, ann.G.LootRulerFrame) == #ann.M.findText("Rolling out loot", true, ann.G.LootRulerFrame))
  shot("loot-tab-raider", ann)
  ann.LR.UI.win:Hide()
  M.click(rowFor("Royal Cloak of Arathi Kings").act)
  srv:tick(0.3)
  clickText("Take it off")
  srv:tick(2)
  check("the leader can take a mistake off the list (Ann still has the item)", #s.won == 0 and visible("Looted by Ann"))
  check("raiders' copies agree", #(ann.LR.current().won or {}) == 0)
  LR.UI.win:Hide()
end)

run("who reserved it, while it's rolled for", function()
  -- seven players without the addon join, and all reserve the brooch: more than the roll window has room for
  local extra = {}
  for _, x in ipairs({ { "Rhonin", "MAGE" }, { "Valeera", "ROGUE" }, { "Øyvind", "WARRIOR" }, { "Tyrande", "PRIEST" },
    { "Turalyon", "PALADIN" }, { "Alleria", "HUNTER" }, { "Muradin", "WARRIOR" } }) do
    local p = srv:player({ name = x[1], class = x[2] })
    table.insert(srv.group.members, p) p.inGroup = true
    extra[#extra + 1] = p
  end
  srv:rosterChanged()
  srv:tick(1)
  for _, p in ipairs(extra) do LR.leaderAdd(s, p.name .. "-Dreamscythe", p.class, 28530) end
  srv:tick(2)
  -- the game's loot window on Ann's screen: every reserved item says who
  local back = ann.G.CreateFrame("Frame", "AnnLootBack", ann.G.UIParent, "BackdropTemplate")
  back:SetPoint("TOPLEFT", ann.G.LootButton1, "TOPLEFT", -14, 14)
  back:SetSize(200, 150)
  back:SetFrameStrata("LOW")
  back:SetBackdrop(LR.K.ROCK)
  srv:openLoot(ann, { { 28530, 4 }, { 28528, 4 }, { 28766, 4 } })
  for i = 1, 3 do ann.G.LootFrame_UpdateButton(i) end
  local b1, b2 = ann.G.LootButton1, ann.G.LootButton2
  check("the loot window marks reserved items, with who", b1.lrTag and b1.lrTag:IsShown() and ann.M.plain(b1.lrWho:GetText()):find("+", 1, true) ~= nil
    and ann.M.plain(b2.lrTag:GetText()) == "HR")
  shot("loot-window-reserves", ann, { "AnnLootBack" })
  srv:closeLoot(ann)
  back:Hide()
  -- rolling it out: the strip over the roll window has every name
  LR.Rolls.start(28530, { link = srv.itemInfo(28530).link })
  srv:tick(1)
  local strip = ann.G.LootRulerReserveStrip
  local names = strip and ann.M.plain(strip.names:GetText()) or ""
  check("a strip over the roll window lists everyone who reserved it", strip and strip:IsShown()
    and names:find("Muradin", 1, true) and names:find("Øyvind", 1, true) and names:find("Valeera", 1, true) and not names:find("+", 1, true), names)
  shot("reserve-strip", ann, { "LootRulerReserveStrip", "LootRulerRollFrame1" })
  LR.Rolls.cancel()
  srv:tick(1)
  check("and goes when the roll ends", not strip:IsShown())
  for _, p in ipairs(extra) do LR.leaderRemove(s, p.name .. "-Dreamscythe", 28530) srv:leaveGroup(p) end
  srv:tick(10)
end)

run("settings", function()
  ann.LR.UI.show("settings")
  srv:tick(0.3)
  check("every option is on the Settings tab", visible("Show roll windows", ann) and visible("Seconds to roll:", ann)
    and visible("Put won items in trades for me", ann) and visible("Hide !lr messages in my chat", ann) and visible("!lr in raid chat", ann) and visible("Minimap button", ann))
  check("each says what it does", visible("Leaves out items other players reserved", ann))
  shot("settings", ann)
  clickText("Only for items I can roll on", nil, ann)
  check("an option switches", ann.LR.db.settings.rollOnlyMine == true and visible("[x] Only for items I can roll on", ann))
  clickText("Only for items I can roll on", nil, ann)
  clickText("30", nil, ann)
  check("seconds to roll", ann.LR.db.settings.rollSeconds == 30)
  clickText("Minimap button", nil, ann)
  check("the minimap button can be hidden", not ann.G.LootRulerMinimapButton:IsShown() and ann.LR.db.ui.hideMinimap)
  clickText("Minimap button", nil, ann)
  check("and shown again", ann.G.LootRulerMinimapButton:IsShown())
  clickText("Add an item rule", nil, ann)
  check("an auto-roll rule: shift-click the item in", visible("Add an auto-roll rule", ann))
  local box
  local function walk(fr) for _, c in ipairs(fr._children) do if c._type == "EditBox" and c:IsVisible() then box = c end walk(c) end end
  walk(ann.LR.UI.topSheet())
  ann.M.click(box)
  ann.G.ChatEdit_InsertLink(srv.itemInfo(28530).link)
  srv:tick(0.3)
  clickText("Always pass", nil, ann)
  clickText("Add the rule", nil, ann)
  check("the rule is listed", ann.LR.db.settings.autoRollRules[28530] == "pass" and visible("Always: Pass", ann))
  clickText("Add a rule", nil, ann)
  check("a loot rule: which items, then who gets them", visible("Which items?", ann) and visible("Who gets them?", ann))
  clickText("Uncommon (green) items", nil, ann)
  clickText("The disenchanter", nil, ann)
  check("it says what the rule will do", visible("Uncommon (green) items will go to the disenchanter", ann))
  clickText("Add the rule", nil, ann)
  check("the rule is listed", #ann.LR.db.settings.autoLootRules == 1 and visible("Goes to the disenchanter", ann))
  clickText("Hand out loot by my rules", nil, ann)
  -- scroll down to the rules for the picture
  local function scrollers(fr, out) for _, c in ipairs(fr._children) do if c._type == "ScrollFrame" and c:IsVisible() then out[#out + 1] = c end scrollers(c, out) end return out end
  local sf = scrollers(ann.G.LootRulerFrame, {})[1]
  sf:SetVerticalScroll(sf:GetVerticalScrollRange())
  shot("loot-rules", ann)
  sf:SetVerticalScroll(0)
  clickText("Hand out loot by my rules", nil, ann)
  clickText("Try the roll window", nil, ann)
  local shown = false
  for _, fr in ipairs(ann.LR.UI.rollFrames()) do if fr:IsShown() and fr.copy.test then shown = true end end
  check("the pretend roll window shows", shown)
  local before = #ann.M.chat
  ann.G.SlashCmdList.LOOTRULER("help")
  check("/lr help lists the commands", #ann.M.chat > before + 5 and ann.M.chat[#ann.M.chat]:find("/lr minimap", 1, true))
  ann.G.SlashCmdList.LOOTRULER("settings")
  check("/lr settings opens the tab", ann.LR.UI.tab == "settings")
  ann.LR.UI.win:Hide()
end)

run("the +1 rule", function()
  LR.UI.show("session")
  srv:tick(0.3)
  clickText("+1 rule")
  srv:tick(1)
  check("the leader turns the +1 rule on", s.plusOne == true and ann.LR.current().plusOne == true)
  LR.UI.go("reserves")
  clickText("By player")
  check("+1 buttons for each player", #find("+1") > 0 and #find("-1") > 0)
  local plusButtons = {}
  for _, x in ipairs(find("+1")) do if x.clickable and M.plain(x.fs:GetText()) == "+1" then plusButtons[#plusButtons + 1] = x.clickable end end
  M.click(plusButtons[1])
  srv:tick(1)
  local given = 0
  for name in pairs(s.po or {}) do given = given + 1 end
  check("giving someone a +1 shows next to their name", given == 1 and visible("+1"))
  shot("plus-ones")
  LR.UI.go("session")
  clickText("+1 rule")
  srv:tick(1)
  LR.UI.go("reserves")
  clickText("By item")
  LR.UI.win:Hide()
end)

run("the disenchanter", function()
  LR.UI.show("session")
  srv:tick(0.3)
  check("the Session tab has a disenchanter panel", visible("Disenchanter") and visible("Pick a disenchanter"))
  clickText("Pick a disenchanter")
  check("pick from the group", visible("Who disenchants?") and visible("Ann"))
  clickText("Ann")
  srv:tick(1)
  check("Ann disenchants; raiders know", s.de == "Ann-Dreamscythe" and ann.LR.current().de == "Ann-Dreamscythe" and visible("disenchants what nobody wants"))
  clickText("Nobody")
  srv:tick(1)
  check("and nobody again", s.de == nil)
  LR.UI.win:Hide()
end)

run("telling the raid how to SR without the addon", function()
  LR.UI.show("session")
  srv:tick(0.3)
  local before = #pug.inbox
  clickText("Tell the raid how to SR without the addon")
  srv:tick(1)
  local got = pug.inbox[#pug.inbox]
  check("the raid gets the how-to", #pug.inbox == before + 1 and got.channel == "RAID"
    and got.text == "Type !lr [linked item] in raid chat to SR if you do not have the LootRuler addon.", got and got.text)
  check("and the leader is told it went", visible("Posted in raid chat."))
end)

run("ending", function()
  LR.UI.show()
  srv:tick(0.3)
  LR.UI.go("session")
  clickText("End session")
  check("asks first", visible("End the session"))
  clickText("End it")
  srv:tick(2)
  check("the session is gone everywhere", LR.current() == nil and ann.LR.current() == nil)
  check("back to the setup form", visible("Open soft reserves"))
end)

run("Escape and panels", function()
  LR.UI.go("session")
  local s2 = LR.startSession("GruulsLair", 1, false, false)
  srv:tick(1)
  LR.UI.render()
  clickText("Add a hard reserve")
  check("a panel is open", LR.UI.topSheet() ~= nil)
  G.LootRulerEscapeCatcher:Hide()
  srv:tick(0.1)
  check("Escape closes the panel, not the window", LR.UI.topSheet() == nil and G.LootRulerFrame:IsShown())
  LR.endSession(s2)
end)

run("a raid that isn't in the lists", function()
  LR.UI.show("session")
  srv:tick(0.3)
  clickText("Another raid")
  check("it asks for the raid's name", visible("Raid name"))
  local box
  local function walk(f) for _, c in ipairs(f._children) do if c._type == "EditBox" and c:IsVisible() then box = c end walk(c) end end
  walk(G.LootRulerFrame)
  M.click(box)
  M.type("Barrow Deeps")
  clickText("Open reserves")
  srv:tick(2)
  local s4 = LR.current()
  check("a session for it, where any item can be reserved", s4 and s4.raid == LR.CUSTOM and s4.raidName == "Barrow Deeps" and s4.any)
  check("raiders have it, by name", ann.LR.current() and ann.LR.current().raidName == "Barrow Deeps")
  LR.UI.go("reserve")
  check("the Reserve tab says how", visible("isn't in LootRuler's loot lists, so any item can be reserved"))
  -- shift-click an item (here Dragonspine Trophy, from another raid) while the search box has the focus
  box = nil
  walk(G.LootRulerFrame)
  M.click(box)
  G.ChatEdit_InsertLink(srv.itemInfo(28830).link)
  srv:tick(0.5)
  check("a shift-clicked item goes in the box and shows up", visible("Linked item") and visible("Dragonspine Trophy"))
  shot("any-item")
  M.click(rowFor("Dragonspine Trophy"))
  srv:tick(1)
  check("click it to reserve it", LR.Session.reservesOf(s4, "Lead-Dreamscythe")[1] == 28830)
  LR.endSession(s4)
  srv:tick(1)
  LR.UI.q = ""
end)

run("the guild and boosted rolls", function()
  LR.UI.show("guild")
  srv:tick(0.3)
  check("guild members get a Guild tab", visible("Boosted rolls for this guild") and visible("Who can change this"))
  check("players outside a guild don't", (function() bob.LR.UI.show() srv:tick(0.3) local none = not visible("Guild", bob) bob.LR.UI.win:Hide() return none end)())
  clickText("[  ] Boosted rolls for this guild")
  srv:tick(1)
  check("an officer turns boosted rolls on, for the whole guild", LR.book().boost.on and ann.LR.book().boost.on)
  clickText("Give a player points")
  check("a sheet to give someone points", visible("Player") and visible("Points"))
  local boxes = {}
  local function walkEdits(f) for _, c in ipairs(f._children or {}) do if c._type == "EditBox" and c:IsVisible() then boxes[#boxes + 1] = c end walkEdits(c) end end
  walkEdits(LR.UI.topSheet())
  boxes[1]:SetText("Ann") boxes[1]._scripts.OnTextChanged(boxes[1], true)
  boxes[2]:SetText("25") boxes[2]._scripts.OnTextChanged(boxes[2], true)
  clickText("Save")
  srv:tick(1)

  check("the points are saved and shared", LR.Book.points(LR.book(), "Ann-Dreamscythe") == 25 and ann.LR.Book.points(ann.LR.book(), "Ann-Dreamscythe") == 25)
  check("the list shows them, with the roll to type", visible("/roll 26 125") and visible("Edit"))
  local s5 = LR.startSession("Karazhan", 2, true, false)
  srv:tick(1)
  LR.UI.go("session")
  check("the Session tab offers boosted rolls", visible("Boosted rolls"))
  clickText("[  ] Boosted rolls")
  srv:tick(1)
  check("on for the session", s5.boost == true)
  clickText("Give raid points")
  check("it asks first, and says who gets what", visible("2 players from the guild in the group get 10 points each."))
  clickText("Give points")
  srv:tick(1)
  check("raid points given", LR.Book.points(LR.book(), "Ann-Dreamscythe") == 35 and LR.Book.points(LR.book(), "Lead-Dreamscythe") == 10)
  LR.UI.go("guild")
  shot("guild")
  ann.LR.UI.show("guild")
  srv:tick(0.3)
  check("a member sees their points, and can't change anything", visible("35 (a boosted roll is 36 to 135)", ann) and not visible("Edit", ann)
    and not visible("Give a player points", ann))
  ann.LR.UI.win:Hide()
  LR.Rolls.start(28525, {})
  srv:tick(0.5)
  local fr
  for _, x in ipairs(ann.LR.UI.rollFrames()) do if x:IsShown() and x.copy and x.copy.id == 28525 then fr = x end end
  check("Ann's roll window has a green dice for her points", fr and fr.boost:IsShown() and fr.boost.label:GetText() == "+35")
  check("and says so", fr and fr.status:GetText():find("Green dice: boosted (35 points)", 1, true) ~= nil)
  shot("boosted-roll", ann, { fr:GetName() })
  LR.Rolls.cancel()
  srv:tick(1)
  LR.UI.go("session")
  clickText("End session")
  check("ending says the points were given, so it just asks", visible("End it") and not visible("Give points and end"))
  clickText("Cancel")
  LR.Book.setPoints(LR.book(), "Ann-Dreamscythe", 35, 0)
  LR.db.ui.pointsGiven = {}
  clickText("End session")
  check("without points given, it offers to give them", visible("Give points and end") and visible("This raid's points haven't been given yet"))
  clickText("Give points and end")
  srv:tick(1)
  check("points given and the session ended", LR.current() == nil and LR.Book.points(LR.book(), "Ann-Dreamscythe") == 45)
  check("/lr guild opens the tab", (function() G.SlashCmdList.LOOTRULER("guild") return LR.UI.tab == "guild" end)())
  LR.UI.go("reserve")
end)

run("priority lists", function()
  local function edits()
    local boxes = {}
    local function walkEdits(f) for _, c in ipairs(f._children or {}) do if c._type == "EditBox" and c:IsVisible() then boxes[#boxes + 1] = c end walkEdits(c) end end
    walkEdits(LR.UI.topSheet())
    return boxes
  end
  local function type(box, text) box:SetText(text) box._scripts.OnTextChanged(box, true) srv:tick(0.3) end
  LR.UI.go("guild")
  check("the Guild tab has priority lists", visible("Priority lists") and visible("Add an item") and visible("Bring in"))
  clickText("Add an item")
  type(edits()[1], "signet of unsh")
  check("search any raid's loot for the item", visible("Signet of Unshakable Faith"))
  M.click(rowFor("Signet of Unshakable Faith"))
  srv:tick(0.3)
  check("its list opens", visible("Priority list") and visible("Add a player"))
  -- the boxes by their width: the name, the place, the note
  local function box(w) for _, e in ipairs(edits()) do if math.abs(e:GetWidth() - w) < 1 then return e end end end
  local wide = 0
  for _, e in ipairs(edits()) do wide = math.max(wide, e:GetWidth()) end
  type(box(150), "Ann")
  type(box(50), "1")
  type(box(wide), "tank set")
  clickText("Add")
  type(box(150), "Lead")
  clickText("Add")
  srv:tick(1)
  local list = LR.Book.prio(LR.book(), 28525)
  check("players go on the list, and it's shared", #list == 2 and list[1].p == "Ann-Dreamscythe" and list[1].note == "tank set" and list[2].n == 2
    and #ann.LR.Book.prio(ann.LR.book(), 28525) == 2)
  check("each with their place", visible("1st") and visible("2nd") and visible("tank set"))
  shot("priority-list")
  clickText("Done")
  clickText("Bring in")
  type(edits()[1], "28530,Ann|Lead,Bob\n28528,Lead")
  check("it reads what's pasted, and says what it found", visible("Gargul's CSV: 2 items, 4 places on them."))
  clickText("Bring them in")
  srv:tick(1)
  check("the lists are in", #LR.Book.prio(LR.book(), 28530) == 3 and #LR.Book.prio(LR.book(), 28528) == 1)
  srv:tick(4)
  check("the Guild tab lists them", visible("Brooch of Unquenchable Fury") and visible("1. Ann, Lead, 2. Bob"))
  shot("guild-priority")
  local s6 = LR.startSession("Karazhan", 2, true, false)
  srv:tick(1)
  LR.UI.go("session")
  check("the Session tab asks what loot goes by", visible("Loot goes by:") and visible("Priority lists, then reserves"))
  clickText("Priority lists, then reserves")
  srv:tick(1)
  check("priority lists, then reserves", s6.prio == "both" and ann.LR.current().prio == "both")
  LR.Rolls.start(28530, {})
  srv:tick(0.5)
  local fr
  for _, x in ipairs(ann.LR.UI.rollFrames()) do if x:IsShown() and x.copy and x.copy.id == 28530 then fr = x end end
  check("Ann shares first place with Lead: her window lets her roll", fr and fr.dice:IsEnabled() and fr.status:GetText():find("You're 1st on the priority list", 1, true), fr and fr.status:GetText())
  shot("priority-roll", ann, { fr:GetName() })
  LR.Rolls.cancel()
  srv:tick(1)
  clickText("Priority lists only")
  check("switching to priority lists only asks first when there are reserves", s6.prio == "only" or visible("Switch"))
  if visible("Switch") then clickText("Switch") end
  srv:tick(1)
  ann.LR.UI.show("reserve")
  srv:tick(0.3)
  check("raiders see their places instead of reserves", visible("goes by the guild's priority lists, not reserves", ann) and visible("You're 1st", ann))
  ann.LR.UI.win:Hide()
  LR.endSession(s6)
  srv:tick(1)
  LR.UI.go("reserve")
end)

run("GDKP", function()
  local s7 = LR.startSession("Karazhan", 2, true, false)
  srv:tick(1)
  LR.UI.go("session")
  check("the Session tab offers GDKP auctions", visible("GDKP auctions"))
  clickText("[  ] GDKP auctions")
  srv:tick(1)
  check("on: the GDKP panel, for raiders too", s7.gdkp and visible("Bids start at:") and visible("Your cut:") and ann.LR.current().gdkp)
  clickText("250g")
  srv:tick(1)
  check("the leader picks where bids start", s7.gk.min == 250)
  -- two sales, by bids typed in raid chat
  for _, x in ipairs({ { 28525, ann, "300" }, { 28530, bob, "1.5k" } }) do
    LR.Rolls.start(x[1], {})
    srv:tick(0.5)
    srv:chatMessage(x[2], x[3], "RAID")
    srv:tick(0.5)
    if x[1] == 28525 then
      local fr
      for _, f in ipairs(bob.LR.UI.rollFrames()) do if f:IsShown() and f.copy and f.copy.id == 28525 then fr = f end end
      check("an auction's roll window: the bids to click, and the highest", fr and fr.dice.label:GetText() == "310g" and fr.status:GetText():find("Highest bid: Ann-Dreamscythe, 300g", 1, true))
      shot("auction-window", bob, { fr:GetName() })
      LR.UI.showMaster()
      shot("auction-master", lead, { "LootRulerMasterFrame" })
    end
    LR.Rolls.stop()
    srv:tick(1)
  end
  check("both sold", #LR.Gdkp.sales(s7) == 2 and LR.Gdkp.pot(s7) == 1800)
  LR.Rolls.dismiss()
  srv:tick(10)                       -- (the finished auctions' windows go)
  LR.UI.go("session")
  check("the pot on the Session tab", visible("1,800g") and visible("Payouts"))
  clickText("Payouts")
  check("the payouts sheet: the pot, the split, and who owes what", visible("Split 4 ways") and visible("owes") and visible("gets"))
  shot("payouts")
  clickText("...", 1)
  check("a player's options", visible("Give a bonus") and visible("Leave out of the split"))
  LR.UI.closeAll()
  ann.LR.UI.show("session")
  srv:tick(0.3)
  check("a raider sees the pot and their own payout", visible("1,800g", ann) and visible("GDKP: You bought 300g", ann))
  ann.LR.UI.go("reserve")
  check("and no reserves", visible("auctions its loot for gold: nobody reserves anything", ann) and visible("POT", ann))
  ann.LR.UI.win:Hide()
  LR.UI.go("session")
  clickText("End session")
  check("ending a GDKP with gold still owed asks first, and says who", visible("Gold is still owed") and visible("Bob-Faerlina: they give you 1,095g") and visible("Keep it open") and visible("kept under Past raids"))
  shot("gdkp-end")
  clickText("Keep it open")
  check("keeping it open keeps it", LR.current() == s7)
  -- (pictures are numbered in order: new ones go last, so the README's links stay right)
  clickText("[  ] Bids start with \"bid\"")
  srv:tick(1)
  check("the leader can make bids start with \"bid\"", s7.gk.strict == true)
  shot("gdkp-panel")
  LR.endSession(s7)
  srv:tick(1)
  LR.UI.go("reserve")
end)

run("extra reserves", function()
  local s8 = LR.startSession("Karazhan", 1, true, false)
  srv:tick(1)
  LR.UI.go("session")
  check("the Session tab offers extra reserves", visible("Extra reserves") and visible("Give extra reserves"))
  clickText("Give extra reserves")
  check("pick players and how many more", visible("Extra each:") and visible("Ann"))
  clickText("[  ] Ann")
  clickText("+2")
  shot("extra-reserves")
  clickText("Save for 1 player")
  srv:tick(1)
  check("Ann gets two more, and her addon knows", LR.Session.extra(s8, "Ann-Dreamscythe") == 2 and ann.LR.Session.limit(ann.LR.current(), "Ann-Dreamscythe") == 3)
  check("the Session tab lists it", visible("Ann +2"))
  ann.LR.UI.show("reserve")
  srv:tick(0.3)
  check("Ann sees three reserves, and why", visible("3 reserves left of 3.", ann) and visible("gave you 2 extra reserves", ann) and visible("0 / 3", ann))
  ann.LR.UI.win:Hide()
  LR.UI.go("reserves")
  clickText("By player")
  check("the leader sees it by player", visible("+2 extra") and visible("Extra reserves: 2"))
  clickText("By item")
  LR.endSession(s8)
  srv:tick(1)
  LR.UI.go("reserve")
end)

run("past raids", function()
  LR.UI.go("loot")
  local n = #LR.History.all()
  check("the Loot tab has past raids", n > 0 and visible(("Past raids (%d)"):format(n)))
  clickText(("Past raids (%d)"):format(n))
  check("each with its date, leader and what it gave out", visible("Past raids") and visible("by Lead") and visible("unpaid"))
  shot("past-raids")
  M.click(rowFor("Karazhan"))
  srv:tick(0.3)
  check("one raid: its loot, the export, and a GDKP's payouts", visible("Export") and visible("Payouts") and visible("Forget it") and visible("bought for 300g"))
  clickText("Payouts")
  check("the payouts still work after the raid", visible("Split 4 ways") and visible("owes 1,095g"))
  LR.UI.closeAll()
  G.SlashCmdList.LOOTRULER("history")
  check("/lr history opens them", LR.UI.tab == "loot" and visible("Past raids"))
  LR.UI.closeAll()
  LR.UI.go("reserve")
end)

run("max bids", function()
  local s9 = LR.startSession("Karazhan", 2, true, false)
  LR.setGdkp(s9, true)
  srv:tick(1)
  LR.Rolls.start(28525, {})
  srv:tick(0.5)
  local fr
  for _, f in ipairs(bob.LR.UI.rollFrames()) do if f:IsShown() and f.copy and f.copy.id == 28525 then fr = f end end
  bob.G.IsShiftKeyDown = function() return true end
  bob.M.click(fr.dice)
  bob.G.IsShiftKeyDown = function() return false end
  srv:tick(0.3)
  check("shift-click a bid: a max bid", visible("Max bid for", bob) and visible("Nobody else sees it.", bob))
  fr:Hide() shot("max-bid", bob) fr:Show()        -- (the roll window sits over the sheet in the picture)
  local box
  local function walkEdits(f) for _, c in ipairs(f._children or {}) do if c._type == "EditBox" and c:IsVisible() then box = c end walkEdits(c) end end
  walkEdits(bob.LR.UI.topSheet())
  box:SetText("900") box._scripts.OnTextChanged(box, true)
  clickText("Save", nil, bob)
  srv:tick(1)
  check("it goes to the loot master's addon, and bids for Bob", LR.Rolls.current.top and LR.Rolls.current.top.p == "Bob-Faerlina" and fr.copy.myMax == 900)
  check("Bob's window says his max", fr.status:GetText():find("Your max: 900g", 1, true))
  bob.LR.UI.win:Hide()
  LR.Rolls.cancel()
  srv:tick(1)
  LR.setGdkp(s9, false)
  LR.endSession(s9)
  srv:tick(1)
end)

run("tanks and healers in a GDKP", function()
  local s10 = LR.startSession("Karazhan", 2, true, false)
  LR.setGdkp(s10, true)
  srv:tick(1)
  LR.UI.go("session")
  check("role cuts on the GDKP panel", visible("Tanks each get:") and visible("Healers each get:") and visible("Tanks and healers"))
  clickText("2%", 1)
  srv:tick(0.5)
  check("the leader picks the tanks' cut", s10.gk.rp and s10.gk.rp.tank == 2)
  clickText("Tanks and healers")
  check("each player, tank or healer", visible("Pick who tanks and who heals") and visible("Ann") and visible("Healer"))
  local hit
  for _, x in ipairs(find("Tank")) do if x.clickable and M.plain(x.fs:GetText()) == "Tank" then hit = x.clickable break end end
  M.click(hit)
  srv:tick(0.5)
  local tanks = 0
  for _, r in pairs(s10.gk.role or {}) do if r == "tank" then tanks = tanks + 1 end end
  check("clicking Tank puts them in the role", tanks == 1)
  shot("tanks-and-healers")
  LR.UI.closeAll()
  LR.setGdkp(s10, false)
  LR.endSession(s10)
  srv:tick(1)
  LR.UI.go("reserve")
end)

run("+1s and boosted roll points from Gargul", function()
  -- Gargul's own exports, as the stand-in gives them
  local before = G.Gargul
  G.Gargul = { PlusOnes = { getPlusOnes = function() return 0 end, export = function() return "Ann,2\nBob-Faerlina,1\n" end },
    BoostedRolls = { export = function() return "Ann,40,Annalt\nPug,15,\n" end } }
  LR.UI.go("guild")
  clickText("Bring in from Gargul")
  check("points: read straight from Gargul", visible("Read them from Gargul"))
  clickText("Read them from Gargul")
  check("it says what it found", visible("2 players, from Ann to Pug."))
  shot("from-gargul")
  clickText("Bring them in")
  srv:tick(1)
  check("the points are in, and shared", LR.Book.points(LR.book(), "Ann-Dreamscythe") == 40 and LR.Book.points(LR.book(), "Pug-Dreamscythe") == 15
    and ann.LR.Book.points(ann.LR.book(), "Ann-Dreamscythe") == 40)
  clickText("Copy out")
  local function memoText()
    local out
    local function walk(f) for _, c in ipairs(f._children or {}) do if c._type == "EditBox" and c:IsVisible() then out = c:GetText() end walk(c) end end
    walk(LR.UI.topSheet())
    return out or ""
  end
  check("and copied out for Gargul", visible("Boosted roll points") and memoText():find("Ann,40", 1, true) and memoText():find("Pug,15", 1, true), memoText())
  LR.UI.closeAll()
  local s11 = LR.startSession("Karazhan", 2, true, false)
  srv:tick(1)
  LR.UI.go("session")
  check("no +1s panel until the +1 rule is on", not visible("Everyone's +1s are on the Reserves tab"))
  LR.setPlusOne(s11, true)
  srv:tick(1)
  clickText("Bring in from Gargul")
  clickText("Read them from Gargul")
  clickText("Bring them in")
  srv:tick(1)
  check("+1s are in, for raiders' addons too", LR.Session.plusOnes(s11, "Ann-Dreamscythe") == 2 and LR.Session.plusOnes(s11, "Bob-Faerlina") == 1
    and ann.LR.Session.plusOnes(ann.LR.current(), "Ann-Dreamscythe") == 2)
  clickText("Copy out")
  check("and copied back out", memoText():find("Ann,2", 1, true) and memoText():find("Bob,1", 1, true), memoText())
  LR.UI.closeAll()
  LR.endSession(s11)
  srv:tick(1)
  G.Gargul = before
  LR.UI.go("reserve")
end)

run("alts", function()
  LR.UI.go("guild")
  -- Ann has points from the Gargul import above: her Edit opens her points, and her alts
  local annRow
  for _, x in ipairs(find("Ann")) do if x.frame._kind == "item" and M.plain(x.fs:GetText()) == "Ann" and x.frame.act:IsShown() then annRow = x.frame end end
  M.click(annRow.act)
  srv:tick(0.3)
  check("a player's points sheet has their alts", visible("Points for Ann") and visible("Alts") and visible("Link this alt"))
  local box
  local function walk(f) for _, c in ipairs(f._children or {}) do if c._type == "EditBox" and c:IsVisible() and math.abs(c:GetWidth() - 150) < 1 then box = c end walk(c) end end
  walk(LR.UI.topSheet())
  check("the alt from Gargul's export is there already", visible("Annalt") and visible("Unlink"))
  box:SetText("Annbank") box._scripts.OnTextChanged(box, true)
  clickText("Link this alt")
  srv:tick(1)
  check("an officer links another, for the whole guild", LR.Book.mainOf(LR.book(), "Annbank") == "Ann-Dreamscythe" and ann.LR.Book.mainOf(ann.LR.book(), "Annbank") == "Ann-Dreamscythe")
  check("it's listed too", visible("Annbank") and #LR.Book.altsOf(LR.book(), "Ann") == 2)
  shot("alts")
  LR.UI.closeAll()
  check("the points list shows them under Ann", visible("alts: Annalt, Annbank"))
  LR.UI.go("reserve")
end)

run("a new leader for the reserves", function()
  local s5 = LR.startSession("Karazhan", 2, true, false)
  srv:tick(2)
  check("the leader can hand the reserves over", (function() LR.UI.go("session") return visible("Hand the reserves over") end)())
  -- the leader leaves; Ann assists the raid
  srv:setAssist(ann, true)
  srv:leaveGroup(lead)
  srv:tick(2)
  ann.LR.UI.show("session")
  srv:tick(0.3)
  check("an assistant is offered the reserves", visible("Nobody's running the reserves", ann) and visible("Take over the reserves", ann)
    and visible("Hand them to someone else", ann))
  shot("take-over", ann)
  clickText("Hand them to someone else", nil, ann)
  check("the replacement picker lists who can take them", visible("Who runs the reserves now?", ann) and visible("Bob-Faerlina", ann) and not visible("Pug", ann))
  shot("hand-over", ann)
  ann.LR.UI.closeAll()
  clickText("Take over the reserves", nil, ann)
  srv:tick(3)
  check("Ann takes them over", ann.LR.isLeader(ann.LR.session(s5.id)) and bob.LR.session(s5.id).leader == "Ann-Dreamscythe")
  check("and her Session tab is the leader's now", visible("Hand the reserves over", ann))
  -- back as it was: the leader rejoins and takes the group back
  srv:setGroup({ lead, ann, bob, pug }, lead, true)
  srv:setAssist(ann, false)
  srv:tick(5)
  ann.LR.endSession(ann.LR.session(s5.id))
  srv:tick(2)
  ann.LR.UI.win:Hide()
  LR.UI.go("reserve")
end)

run("no leaks", function()
  local s3 = LR.startSession("BlackTemple", 2, true, false)
  srv:tick(1)
  for _, t in ipairs({ "Reserve", "Reserves", "Session" }) do clickText(t) end
  local before = M.frameCount()
  for _ = 1, 15 do for _, t in ipairs({ "Reserve", "Reserves", "Session" }) do clickText(t) end end
  check("redrawing reuses frames", M.frameCount() - before < 5, ("%d frames before, %d after 45 redraws"):format(before, M.frameCount()))
  if M.frameCount() - before >= 5 then
    local kinds = {}
    for _, f in ipairs(M.allFrames()) do local k = f._kind or f._type kinds[k] = (kinds[k] or 0) + 1 end
    for k, n in pairs(kinds) do print("   ", k, n) end
  end
  LR.endSession(s3)
end)

local clashes = M.layerClashes()
check("nothing drawn level with a backdrop", #clashes == 0, table.concat(clashes, ", "))
for _, p in ipairs({ lead, ann, bob }) do
  if p.M then check(p.name .. ": no Lua errors", #p.M.errors == 0, table.concat(p.M.errors, " | ")) end
end
print(("passed %d"):format(passed))
print(("errors %d"):format(failed))
os.exit(failed == 0 and 0 or 1)
