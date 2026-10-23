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

local lead = srv:client({ name = "Lead", class = "PALADIN", guild = "Kings" })
local ann = srv:client({ name = "Ann", class = "PRIEST", guild = "Kings" })
local bob = srv:client({ name = "Bob", class = "MAGE", realm = "Faerlina" })
local pug = srv:player({ name = "Pug", class = "WARRIOR" })
for _, p in ipairs({ lead, ann }) do
  p.G.C_Item.GetItemIconByID = function(id) return ICONS[id] and ("Interface\\Icons\\" .. ICONS[id]) or 134400 end
  p.M.describeLink = function(link)
    local id = tonumber(link:match("item:(%d+)"))
    local it = DATA.ITEMS[id]
    if not it then return nil end
    local hex = QHEX[it[2]] or "ffffff"
    return { { it[1], tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }, { "Item Level " .. it[6], 1, 0.82, 0 } }
  end
end
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
local function shot(name, who)
  who = who or lead
  shotN = shotN + 1
  local f = assert(io.open(("build/shots/%02d-%s.json"):format(shotN, name), "w"))
  f:write(json({ w = 1280, h = 800, ops = who.M.render() }))
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
  M.click(rowFor("Signet of Unshakable Faith"), "LeftButton")
  srv:tick(1)
  check("a third is refused, with a message", #LR.Session.reservesOf(s, "Lead-Dreamscythe") == 2 and visible("You have no reserves left."))
  shot("reserve")
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
  check("who hasn't reserved", visible("haven't reserved anything yet") and visible("nothing reserved"))
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
  M, G, LR = lead.M, lead.G, lead.LR
  srv:tick(8)
  s = LR.current()
  check("they're sent when the leader is back", not ann.LR.pending(ann.LR.current()) and LR.Session.reservesOf(s, "Ann-Dreamscythe")[2] == 28529)
  ann.LR.UI.go("session")
  check("raiders see the session's rules", visible("Session by Lead", ann))
  shot("raider-session", ann)
end)

run("ending", function()
  G.SlashCmdList.LOOTRULER("")
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
