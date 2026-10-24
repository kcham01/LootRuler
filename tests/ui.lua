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
  M.click(rowFor("Shadow-Cloak of Dalaran"))
  srv:tick(2)
  check("the leader adds one for him", LR.Session.reservesOf(s, "Bob-Faerlina")[1] == 28570)
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
  local site = LR.Gargul.encode({ metadata = { id = "x1" }, softreserves = { { name = "Zed", class = "rogue", items = { { id = 28524 } } } }, hardreserves = {} })
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
