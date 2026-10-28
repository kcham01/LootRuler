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
srv.where = Server.PLACES.Karazhan          -- (in Karazhan, where most sessions here are: loot is only listed inside a session's raid)
-- every item is loaded in these clients: names and links from the data, icons from Wowhead's names
local DATA = {}
do
  local env = setmetatable({}, { __index = _G })
  local chunk = assert(loadfile("LootRuler/Data/Loot.lua"))
  setfenv(chunk, env)
  chunk("LootRuler", DATA)
end
local QHEX = { [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }
local EXTRA = { [30183] = { "Nether Vortex", 4, 7 }, [21877] = { "Netherweave Cloth", 1, 7, 5 } }    -- (not in the loot lists; class 7: trade goods, subclass 5: cloth)
srv.itemInfo = function(id)
  local it = DATA.ITEMS[id]
  local x = EXTRA[id]
  if x then return { name = x[1], quality = x[2], class = x[3], subclass = x[4], link = ("|cff%s|Hitem:%d::::::::70:::::|h[%s]|h|r"):format(QHEX[x[2]] or "ffffff", id, x[1]) } end
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
-- tick boxes (K.setTick): the one with these words, on or off as asked (any when nil)
local function tickFor(label, on, p)
  local found
  local function walk(f)
    for _, c in ipairs(f._children or {}) do
      if c.check and c.box and c.text and c:IsVisible() and (p or lead).M.plain(c.text:GetText() or "") == label and (on == nil or c.on == on) then found = found or c end
      walk(c)
    end
  end
  walk(root(p))
  return found
end
local function ticked(label, p) local t = tickFor(label, nil, p) if t then return t.on end end
local function clickTick(label, on, p)
  local t = tickFor(label, on, p)
  if not t then error("no tick box " .. label, 2) end
  (p or lead).M.click(t)
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
  clickText("Open all")
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
  check("it can open and import from softres.it in one go", visible("Open and import from softres.it"))
  clickText("Open and import from softres.it")
  srv:tick(2)
  local s = LR.current()
  check("the import box is up as soon as reserves are open", s and visible("Bring in reserves from softres.it"))
  LR.UI.closeTop()
  srv:tick(0.3)
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
  check("the loot list: each boss, closed, with how many items", visible("Attumen the Huntsman") and visible("Moroes") and visible("Open all")
    and not visible("Royal Cloak of Arathi Kings"))
  shot("reserve-bosses")
  clickText("Moroes")
  check("a boss opens with a click", visible("Royal Cloak of Arathi Kings") and not visible("Fiery Warhorse's Reins"))
  clickText("Moroes")
  check("and closes again", not visible("Royal Cloak of Arathi Kings"))
  clickText("Open all")
  check("\"Open all\" opens every boss", visible("Royal Cloak of Arathi Kings") and visible("Fiery Warhorse's Reins"))
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
  local pickBox
  local function walkPick(f) for _, c in ipairs(f._children) do if c._type == "EditBox" and c:IsVisible() then pickBox = c end walkPick(c) end end
  walkPick(root())
  check("its search box says what to type, inside the box (like the Reserve tab's)", pickBox and pickBox.hint:IsVisible()
    and pickBox.hint:GetText() == "Search Karazhan" and not visible("Pick one, or search by name."))
  shot("pick")
  M.click(pickBox)
  M.type("pocket")
  srv:tick(0.3)
  walkPick(root())
  check("typing hides it", not pickBox.hint:IsVisible() and visible("Moroes' Lucky Pocket Watch") and not visible("Prince Malchezaar"))
  pickBox:SetText("") pickBox._scripts.OnTextChanged(pickBox, true)
  srv:tick(0.3)
  walkPick(root())
  check("and an empty box shows it again", pickBox.hint:IsVisible())
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
  check("only the group can reserve, to start with", ticked("Only the group can reserve") == true and s.go == true)
  check("one reserve win each is off to start with", ticked("One reserve win each") == false and not s.ow)
  clickTick("One reserve win each", false)
  check("and a click switches it on", s.ow == true and ticked("One reserve win each") == true)
  clickTick("One reserve win each", true)
  clickTick("Lock by itself", false)
  check("lock by itself: pick when", visible("Lock reserves by themselves") and visible("In 15 min"))
  shot("auto-lock")
  clickText("In 15 min")
  check("the Session tab says when, and the raid will be told", s.al and math.abs(s.al - (LR.U.now() + 900)) < 5
    and visible("Reserves lock by themselves at") and visible("(in 15 minutes)") and ticked("Lock by itself") == true)
  clickTick("Lock by itself", true)
  check("a click takes it off", s.al == nil and not visible("Reserves lock by themselves at"))
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
  check("by item: each boss with reserves, closed, saying how many", visible("Hard reserves") and visible("Moroes")
    and visible("2 items, 2 reserves") and not visible("Brooch of Unquenchable Fury"))
  clickText("Moroes")
  check("a boss opens to its reserved items", visible("Brooch of Unquenchable Fury"))
  clickText("Moroes")
  check("and closes", not visible("Brooch of Unquenchable Fury"))
  clickText("Open all")
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
  local function top(text) local x = find(text)[1] return x and M.rect(x.fs).t end
  check("softres.it comes first on the Session tab", top("Reserves made on softres.it come in here") and top("Reserved so far")
    and top("Reserves made on softres.it come in here") > top("Reserved so far"))
  clickText("Import from softres.it")
  local box
  local function walk(f) for _, c in ipairs(f._children) do if c._type == "EditBox" and c:IsVisible() and not box then box = c end walk(c) end end
  walk(root())
  check("the cursor is in the box as soon as it opens, ready to paste", M.focus == box)
  local memo = box:GetParent():GetParent():GetParent()          -- (box < scroll child < scroll area < the memo)
  check("the box is drawn above the frames it sits in, so nothing covers it",
    box:GetFrameLevel() > box:GetParent():GetFrameLevel() and box:GetParent():GetFrameLevel() > memo:GetFrameLevel()
    and memo:GetFrameLevel() > memo:GetParent():GetFrameLevel())
  M.type("abc")
  check("typing goes in", box:GetText() == "abc")
  box:ClearFocus()
  M.click(memo)
  check("a click anywhere in the box (not just on a line of text) puts the cursor back", M.focus == box)
  box:SetText(site) box._scripts.OnTextChanged(box, true)       -- (Ctrl+V: the whole export at once)
  check("it goes in whole: the box has no letter limit (an export is thousands of letters)", #box:GetText() == #site and box._max == 0)
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
  -- the export brought its softres.it page: one click posts it
  check("the softres.it link came with the export", s.url == "https://softres.it/raid/x1" and visible("Post the softres.it link"))
  local before = #srv.chat
  clickText("Post the softres.it link")
  srv:tick(1)
  check("posted in raid chat", srv.chat[before + 1] and srv.chat[before + 1].text:find("Reserve on softres.it", 1, true) ~= nil)
  check("once imported, it says import again", visible("Import again") and visible("Import again whenever the sheet changes"))
  clickText("Reserves")
  check("the Reserves tab can import too", visible("Import from softres.it again"))
  clickText("Import from softres.it again")
  check("the same box", visible("Bring in reserves from softres.it"))
  LR.UI.closeTop()
  srv:tick(0.3)
  clickText("Session")
  -- a spreadsheet works too
  clickText("Import again")
  local first
  local function walk2(f) for _, c in ipairs(f._children) do if c._type == "EditBox" and c:IsVisible() and not first then first = c end walk2(c) end end
  walk2(root())
  first:SetText("Name,ItemId\nKel,28524\nKel,28477") first._scripts.OnTextChanged(first, true)
  shot("import-csv")
  clickText("Import")
  srv:tick(2)
  check("a spreadsheet's reserves come in", #LR.Session.reservesOf(s, "Kel-Dreamscythe") == 2)
  LR.UI.closeAll()
  LR.leaderRemove(s, "Kel-Dreamscythe", 28524)
  LR.leaderRemove(s, "Kel-Dreamscythe", 28477)
  srv:tick(2)
end)

run("a raider's window", function()
  ann.G.SlashCmdList.LOOTRULER("")
  srv:tick(0.3)
  check("Ann's window shows the session", visible("Karazhan", ann) and visible("By Lead", ann))
  clickText("Open all", nil, ann)
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
  srv:tick(1)
  local pu = ann.G.LootRulerPickedUp
  check("raiders get a small note of what was picked up, with who reserved it", pu and pu:IsShown()
    and #ann.M.findText("Picked up", true, pu) > 0 and #ann.M.findText("Hard reserved for Ann", true, pu) > 0)
  shot("picked-up", ann, { "LootRulerPickedUp" })
  -- giving one out without a roll: the panel's Give
  local giveBtn
  for _, x in ipairs(M.findText("Give", true, panel)) do if M.plain(x.fs:GetText()) == "Give" and x.clickable then giveBtn = giveBtn or x.clickable end end
  check("each item in the panel can be given out without a roll", giveBtn ~= nil)
  M.click(giveBtn)
  srv:tick(0.3)
  check("a sheet to pick who and how", visible("Pick who gets it and how") and visible("Main spec") and visible("Off spec") and visible("Bob-Faerlina"))
  clickText("Bob-Faerlina")
  check("picking someone names the button", visible("Give to Bob-Faerlina"))
  LR.UI.win:SetFrameStrata("HIGH")
  shot("give")
  LR.UI.closeAll()
  LR.UI.win:Hide()
  -- roll out the cloak Ann and the leader reserved (Ann wears an old one)
  ann.M.player.links = { [15] = "|cff0070dd|Hitem:28672::::::::70:::::|h[Drape of the Dark Reavers]|h|r" }
  pug.links = { [15] = "|cffa335ee|Hitem:28570::::::::70:::::|h[Shadow-Cloak of Dalaran]|h|r" }      -- (no addon: inspected)
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
  local list = mine.list:IsShown() and mine.list:GetText() or ""
  check("Ann's window lists the rolls that count, best first", list:find("1. ", 1, true) and list:find("Ann", 1, true) and list:find("88", 1, true)
    and list:find("41", 1, true) and list:find("Ann", 1, true) < list:find("41", 1, true), list)
  check("but not a roll from someone who didn't reserve it", not list:find("99", 1, true), list)
  check("the window grows to fit it", mine:GetHeight() > 100, mine:GetHeight())
  shot("roll-list", ann, { "LootRulerRollFrame1" })
  srv:tick(3)
  check("everyone who reserved it rolled: it closes", roll.state == "closed")
  check("Ann is picked to get it", #M.findText("Give to Ann", true, G.LootRulerMasterFrame) > 0)
  check("and the loot master sees the cloak she wears now", roll.gear and roll.gear["ann-dreamscythe"] ~= nil)
  check("and what Pug wears, though he has no LootRuler", roll.gear and roll.gear["pug-dreamscythe"] ~= nil)
  check("a Confirm button beside rolling it again: the raid hasn't heard who won yet", #M.findText("Confirm Ann", true, G.LootRulerMasterFrame) > 0
    and #M.findText("Let everyone roll", true, G.LootRulerMasterFrame) > 0)
  shot("loot-master", lead, { "LootStandIn", "LootRulerLootPanel", "LootRulerMasterFrame" })
  local annWin
  for _, f in ipairs(ann.LR.UI.rollFrames()) do if f:IsShown() then annWin = f end end
  check("Ann's window waits for the loot master to confirm", annWin and M.plain(annWin.status:GetText()):find("The loot master confirms the winner", 1, true) ~= nil,
    annWin and M.plain(annWin.status:GetText()))
  M.click(M.findText("Confirm Ann", true, G.LootRulerMasterFrame)[1].clickable)
  srv:tick(1)
  check("confirmed: the button says so", #M.findText("Confirmed: Ann", true, G.LootRulerMasterFrame) > 0)
  check("and Ann's window says she won", annWin and M.plain(annWin.status:GetText()):find("You win with 88", 1, true) ~= nil,
    annWin and M.plain(annWin.status:GetText()))
  shot("confirm-winner", lead, { "LootRulerMasterFrame" })
  M.click(M.findText("Give to Ann", true, G.LootRulerMasterFrame)[1].clickable)
  srv:tick(1)
  check("given to Ann", srv.given and srv.given[1].id == 28529 and s.won and s.won[1].p == "Ann-Dreamscythe" and s.won[1].k == "SR")
  check("with an Undo, for a mistake", #M.findText("Undo", true, G.LootRulerMasterFrame) > 0)
  shot("given", lead, { "LootStandIn", "LootRulerLootPanel", "LootRulerMasterFrame" })
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
  local f1, f2 = bob.G.LootRulerRollFrame1, bob.G.LootRulerRollFrame2
  local _, _, _, _, y1 = f1:GetPoint(1)
  local _, _, _, _, y2 = f2:GetPoint(1)
  check("stacked windows don't overlap", math.abs(y2 - y1) >= f1:GetHeight(), ("%s %s %s"):format(y1, y2, f1:GetHeight()))
  shot("roll-windows", bob, { "LootRulerRollFrame1", "LootRulerRollFrame2" })
  LR.Rolls.cancel()
  srv:closeLoot(lead)
  srv:tick(1)
  check("the panel goes with the loot window", not panel:IsShown())
  srv:tick(9)                                -- finished roll windows go after a few seconds
  LR.UI.show("reserves")
  srv:tick(0.3)
  check("a reserve that's won its item shows it on the Reserves tab", visible("Ann (won)"))
  srv:lootTo(bob, 30183, 2)
  srv:lootTo(ann, 30183, 4)
  srv:lootTo(ann, 21877, 4)                  -- (cloth isn't counted)
  srv:tick(1)
  LR.UI.go("loot")
  srv:tick(0.3)
  check("everything else that dropped is counted below", visible("Everything else that dropped") and visible("Nether Vortex")
    and visible("Looted by Bob-Faerlina (2), Ann (4)") and visible("x6") and not visible("Netherweave Cloth"))
  check("the Loot tab lists what dropped, boss by boss", visible("4 items dropped, 1 given out, 3 still to roll for") and visible("Moroes"))
  check("with who won what", visible("Won by Ann (SR 88)"))
  check("and what's still on the corpse, and who reserved it", visible("On the corpse. Hard reserved for Ann") and visible("On the corpse. SR: Pug"))
  check("the loot master can roll things out from it", #find("Roll") >= 3)
  shot("loot-tab")
  do        -- (scrolled down: everything else that dropped)
    local function scrollers(fr, out) for _, c in ipairs(fr._children) do if c._type == "ScrollFrame" and c:IsVisible() then out[#out + 1] = c end scrollers(c, out) end return out end
    local sf = scrollers(G.LootRulerFrame, {})[1]
    sf:SetVerticalScroll(sf:GetVerticalScrollRange())
    shot("loot-tab-counted")
    sf:SetVerticalScroll(0)
  end
  clickText("Roll")
  local fromTab = LR.Rolls.mine()
  check("its Roll button rolls that item out", fromTab and fromTab.state == "open" and fromTab.drop ~= nil)
  LR.Rolls.cancel()
  srv:tick(1)
  local function said(text) for _, l in ipairs(M.chat) do if l:find(text, 1, true) then return true end end return false end
  G.SlashCmdList.LOOTRULER("roll 28530")
  check("/lr roll [item] rolls one out too", LR.Rolls.mine() and LR.Rolls.mine().id == 28530 and LR.Rolls.mine().state == "open")
  LR.Rolls.cancel()
  srv:tick(1)
  G.SlashCmdList.LOOTRULER("roll brooch of unquench")
  check("or by its name", LR.Rolls.mine() and LR.Rolls.mine().id == 28530 and LR.Rolls.mine().state == "open")
  LR.Rolls.cancel()
  srv:tick(1)
  G.SlashCmdList.LOOTRULER("roll")
  check("on its own it says how", said("/lr roll [item]: shift-click an item into it, or type its name"))
  srv:tick(9)
  LR.UI.go("loot")
  srv:tick(0.3)
  -- a given item: click it to change who got it, or how
  M.click(rowFor("Royal Cloak of Arathi Kings"))
  check("click a given item: change who got it, or how", visible("Change the award") and visible("Their reserve") and visible("Someone else..."))
  clickText("Main spec")
  shot("change-award")
  clickText("Save")
  srv:tick(1)
  check("changed: main spec now, and the reserve counts again", s.won[1].k == "MS" and LR.Session.claims(s, "Ann-Dreamscythe", 28529) > 0)
  M.click(rowFor("Royal Cloak of Arathi Kings"))
  clickText("Their reserve")
  clickText("Save")
  srv:tick(1)
  check("and back", s.won[1].k == "SR")
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
  -- every section starts closed: its name and a line saying what's in it, under three headings
  check("sections start closed: their names, and what's in each", visible("Roll windows", ann) and visible("What pops up when loot is rolled out", ann)
    and visible("For everyone", ann) and visible("Running loot", ann) and visible("This window, and more", ann)
    and visible("Rolling out loot", ann) and visible("Giving out and trading", ann) and visible("Auctions (GDKP)", ann)
    and not visible("Show roll windows", ann) and visible("Click a section to open it.", ann))
  check("with what's in them now", visible("Rolls or passes for you on items you pick: no rules yet.", ann)
    and visible("Off: your rules for the game's Need / Greed rolls (no rules yet).", ann))
  shot("settings", ann)
  clickText("Roll windows", nil, ann)
  check("a click opens one", visible("Show roll windows", ann) and not visible("Seconds to roll:", ann) and ann.LR.db.ui.settingsOpen["Roll windows"] == true)
  clickText("Roll windows", nil, ann)
  check("and closes it", not visible("Show roll windows", ann) and ann.LR.db.ui.settingsOpen["Roll windows"] == nil)
  clickText("Open all", nil, ann)
  check("every option is on the Settings tab", visible("Show roll windows", ann) and visible("Seconds to roll:", ann)
    and visible("Put won items in trades for me", ann) and visible("Hide !lr messages in my chat", ann) and visible("!lr in raid chat", ann) and visible("Minimap button", ann)
    and ticked("Say my trades nearby when I'm not in a group", ann) == true)
  check("opening a trade with the winner is off to start with", ticked("Open a trade with the winner", ann) == false and not ann.LR.db.settings.autoTrade)
  check("each says what it does", visible("Leaves out items other players reserved", ann))
  -- every section's title fits on its gold plate, long or short
  local plates, short, longest = 0, 0, ""
  local function walkPlates(fr)
    for _, c in ipairs(fr._children or {}) do
      if c.plate and c.plateL and c.title and c:IsVisible() and (c.title:GetText() or "") ~= "" then
        plates = plates + 1
        if c.plate:GetWidth() < c.title:GetStringWidth() + 8 then short = short + 1 end
        if #c.title:GetText() > #longest then longest = c.title:GetText() end
      end
      walkPlates(c)
    end
  end
  ann.LR.UI.openSheet("Plates", function(sf)
    for _, t in ipairs({ "Need and Greed (group loot), with a longer title", "Item notes", "x" }) do sf:panel(t, function(p) p:note("Inside.") end) end
  end)
  srv:tick(0.3)
  walkPlates(ann.LR.UI.topSheet())
  ann.LR.UI.closeTop()
  check("switches are tick boxes, not [x] in the words", not visible("[x]", ann) and not visible("[  ]", ann)
    and ticked("Show roll windows", ann) == true and tickFor("Show roll windows", true, ann).check:IsShown()
    and ticked("Only for items I can roll on", ann) == false and not tickFor("Only for items I can roll on", false, ann).check:IsShown())
  check("every section's title fits on its plate", plates == 3 and short == 0 and #longest >= 25, plates .. " " .. short .. " " .. longest)
  clickText("Only for items I can roll on", nil, ann)
  check("an option switches", ann.LR.db.settings.rollOnlyMine == true and ticked("Only for items I can roll on", ann) == true)
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
  -- the loot master's own roll types
  clickText("Add Transmog (/roll 98)", nil, ann)
  local kinds = ann.LR.db.settings.rollKinds
  check("Transmog in one click", #kinds == 1 and kinds[1].n == "Transmog" and kinds[1].hi == 98 and visible("/roll 98. Counts after off spec.", ann))
  check("and only once", not visible("Add Transmog (/roll 98)", ann))
  clickText("Add a roll type", nil, ann)
  local boxes = {}
  local function edits(fr) for _, c in ipairs(fr._children) do if c._type == "EditBox" and c:IsVisible() then boxes[#boxes + 1] = c end edits(c) end end
  edits(ann.LR.UI.topSheet())
  boxes[1]:SetText("Alt") boxes[1]._scripts.OnTextChanged(boxes[1], true)
  boxes[2]:SetText("98") boxes[2]._scripts.OnTextChanged(boxes[2], true)
  clickText("Add it", nil, ann)
  check("a number that's taken is refused, and says why", visible("/roll 98 is Transmog already.", ann) and #ann.LR.db.settings.rollKinds == 1)
  boxes = {}
  edits(ann.LR.UI.topSheet())
  boxes[2]:SetText("97") boxes[2]._scripts.OnTextChanged(boxes[2], true)
  clickText("Add it", nil, ann)
  kinds = ann.LR.db.settings.rollKinds
  check("a name and a number of my own", #kinds == 2 and kinds[2].n == "Alt" and kinds[2].hi == 97 and visible("/roll 97. Counts after Transmog.", ann))
  local rt = ann.M.findText("/roll 98. Counts after off spec.", true, ann.G.LootRulerFrame)[1]
  sf:SetVerticalScroll(math.min(sf:GetVerticalScrollRange(), math.max(0, sf:GetVerticalScroll() + (sf:GetTop() or 0) - (rt.fs:GetTop() or 0) - 150)))
  shot("roll-types", ann)
  sf:SetVerticalScroll(0)
  clickText("Try the roll window", nil, ann)
  local shown = false
  for _, fr in ipairs(ann.LR.UI.rollFrames()) do if fr:IsShown() and fr.copy.test then shown = fr end end
  check("the pretend roll window shows", shown)
  check("with a button for each roll type", shown and shown.extras[1]:IsShown() and shown.extras[2]:IsShown() and shown.extras[2].text:GetText() == "Alt (97)")
  shot("roll-types-window", ann, { shown and shown:GetName() or "LootRulerRollFrame1" })
  ann.M.click(shown.extras[2])
  local mineE = shown.copy.rolled[ann.LR.Roll.key(ann.LR.U.me())]
  check("its button rolls 1-97, as Alt", mineE and mineE.kind == "X2" and mineE.hi == 97 and ann.LR.Roll.label(shown.copy, mineE) == "Alt")
  check("the window lists it by name", shown.list:GetText():find("Alt", 1, true) ~= nil, shown.list:GetText())
  shown._scripts.OnDragStart(shown)
  shown._scripts.OnDragStop(shown)
  check("dragging a roll window keeps where it was put", type(ann.LR.db.ui.rollPoint) == "table" and ann.LR.db.ui.rollPoint[1] ~= nil)
  ann.LR.UI.show("settings")
  srv:tick(0.3)
  clickText("Put windows back", nil, ann)
  check("Put windows back forgets it", ann.LR.db.ui.rollPoint == nil and ann.LR.db.ui.masterPoint == nil)
  ann.M.click(rowFor("Transmog", ann).act)
  kinds = ann.LR.db.settings.rollKinds
  check("a roll type can be taken off", #kinds == 1 and kinds[1].n == "Alt" and visible("/roll 97. Counts after off spec.", ann))
  ann.LR.db.settings.rollKinds = {}
  local before = #ann.M.chat
  ann.G.SlashCmdList.LOOTRULER("help")
  check("/lr help lists the commands", #ann.M.chat > before + 5 and ann.M.chat[#ann.M.chat]:find("/lr minimap", 1, true))
  ann.G.SlashCmdList.LOOTRULER("settings")
  check("/lr settings opens the tab", ann.LR.UI.tab == "settings")
  srv:tick(0.3)
  check("sections stay open as they were left", visible("Show roll windows", ann))
  clickText("Close all", nil, ann)
  check("close all", not visible("Show roll windows", ann) and next(ann.LR.db.ui.settingsOpen) == nil)
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
  -- giving an item out without a roll: straight to the disenchanter
  LR.UI.giveSheet({ id = 28570, link = LR.itemLink(28570) })
  check("the give sheet offers the disenchanter", visible("Disenchant"))
  clickText("Disenchant")
  srv:tick(1)
  local w = s.won[#s.won]
  check("Disenchant gives it to Ann to disenchant", w and w.i == 28570 and w.p == "Ann-Dreamscythe" and w.de == true)
  LR.unaward(s, #s.won)
  srv:tick(1)
  LR.Rolls.dismiss()
  LR.UI.show("session")
  srv:tick(0.3)
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
  clickTick("Boosted rolls for this guild", false)
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
  clickTick("Boosted rolls", false)
  srv:tick(1)
  check("on for the session", s5.boost == true)
  clickText("Give raid points")
  check("it asks first, and says who gets what", visible("2 players from the guild in the group get 10 points each."))
  clickText("Give points")
  srv:tick(1)
  check("raid points given", LR.Book.points(LR.book(), "Ann-Dreamscythe") == 35 and LR.Book.points(LR.book(), "Lead-Dreamscythe") == 10)
  check("the bench, in the Boosted rolls panel", visible("The bench") and visible("Bench players"))
  srv:tick(5)                                -- (the points' toast goes, for a clear picture)
  clickText("Bench players")
  check("who sat out: tick names, or type them", visible("Who came but sat out?") and visible("Or type names"))
  do
    local box
    local function walk(fr) for _, c in ipairs(fr._children or {}) do if c._type == "EditBox" and c:IsVisible() then box = c end walk(c) end end
    walk(LR.UI.topSheet())
    M.click(box)
    M.type("Benny, Bea")
  end
  shot("bench")
  clickText("Save")
  srv:tick(1)
  check("the bench is kept, and the Session tab says who", s5.bn and #s5.bn == 2 and visible("2 players: Bea, Benny."))
  clickText("Change the bench")
  clickTick("Bea", true)
  clickText("Save")
  srv:tick(1)
  check("unticking takes them off", s5.bn and #s5.bn == 1 and s5.bn[1]:find("Benny", 1, true))
  LR.setBench(s5, {})
  srv:tick(1)
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
  -- an item's tooltip shows its priority list
  local brooch = rowFor("Brooch of Unquenchable Fury")
  brooch._scripts.OnEnter(brooch)
  local tipText = {}
  for _, l in ipairs(G.GameTooltip._lines or {}) do tipText[#tipText + 1] = l[1] end
  check("an item's tooltip shows its priority list", table.concat(tipText, " | "):find("Priority list: 1. Ann, Lead, 2. Bob", 1, true) ~= nil, table.concat(tipText, " | "))
  if brooch._scripts.OnLeave then brooch._scripts.OnLeave(brooch) end
  clickText("Copy out", 2)                -- (the first is the points')
  check("Copy out opens the lists to copy, as Gargul's CSV", visible("Priority lists, to copy") and visible("Gargul's CSV: Gargul's thatsmybis importer reads it"))
  local memo
  local function walkMemo(f) for _, c in ipairs(f._children or {}) do if c._type == "EditBox" and c:IsVisible() then memo = memo or c end walkMemo(c) end end
  walkMemo(LR.UI.topSheet())
  check("with every list in it", memo and memo:GetText():find("28530", 1, true) and memo:GetText():find("28528", 1, true), memo and memo:GetText())
  shot("guild-priority-export")
  LR.UI.closeTop()
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
  clickTick("GDKP auctions", false)
  srv:tick(1)
  check("on: the GDKP panel, for raiders too", s7.gdkp and visible("Bids start at:") and visible("Your cut:") and ann.LR.current().gdkp)
  clickText("250g")
  srv:tick(1)
  check("the leader picks where bids start", s7.gk.min == 250)
  -- two sales, by bids typed in raid chat
  for _, x in ipairs({ { 28525, ann, "300" }, { 28530, bob, "1.5k" } }) do
    if x[1] == 28525 then LR.Rolls.queue = { { id = 28528 }, { id = 28529 } } end      -- (two more to come: shown as next)
    LR.Rolls.start(x[1], {})
    LR.Rolls.queue = {}
    srv:tick(0.5)
    srv:chatMessage(x[2], x[3], "RAID")
    srv:tick(0.5)
    if x[1] == 28525 then
      local fr
      for _, f in ipairs(bob.LR.UI.rollFrames()) do if f:IsShown() and f.copy and f.copy.id == 28525 then fr = f end end
      check("an auction's roll window: the bids to click, and the highest", fr and fr.dice.label:GetText() == "310g" and fr.status:GetText():find("Highest bid: Ann-Dreamscythe, 300g", 1, true))
      check("and what's up next", fr.note:GetText():find("Next:", 1, true) ~= nil)
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
  clickTick("Bids start with \"bid\"", false)
  srv:tick(1)
  check("the leader can make bids start with \"bid\"", s7.gk.strict == true)
  shot("gdkp-panel")
  -- the sales: change a price, or take one back
  clickText("Sales (2)")
  check("every sale listed", visible("Sales") and visible("Ann for 300g") and visible("Bob-Faerlina for 1,500g"))
  M.click(rowFor("Bob-Faerlina for 1,500g").act)
  local box
  local function walk(fr) for _, c in ipairs(fr._children) do if c._type == "EditBox" and c:IsVisible() then box = c end walk(c) end end
  walk(LR.UI.topSheet())
  box:SetText("1400") box._scripts.OnTextChanged(box, true)
  clickText("Save")
  srv:tick(1)
  check("a price changed: the pot with it", LR.Gdkp.pot(s7) == 1700 and visible("Bob-Faerlina for 1,400g"))
  shot("gdkp-sales")
  LR.gdkpSalePrice(s7, (function() for i, w in ipairs(s7.won) do if w.k == "BID" and w.r == 1400 then return i end end end)(), 1500)
  LR.UI.closeAll()
  -- starting bids in and out
  LR.UI.go("session")
  clickText("Starting bids in and out")
  local memo
  local function walk2(fr) for _, c in ipairs(fr._children) do if c._type == "EditBox" and c:IsVisible() and c._multi then memo = c end walk2(c) end end
  walk2(LR.UI.topSheet())
  memo:SetText("28525: 800\n28530: 1000") memo._scripts.OnTextChanged(memo, true)
  clickText("Bring them in")
  srv:tick(1)
  local outBox
  local function walk3(fr) for _, c in ipairs(fr._children) do if c._type == "EditBox" and c:IsVisible() and c._multi and not outBox then outBox = c end walk3(c) end end
  walk3(LR.UI.topSheet())
  check("starting bids brought in, and copied out", LR.Gdkp.minFor(s7, 28525) == 800 and outBox and outBox:GetText():find("28525: 800", 1, true) ~= nil)
  shot("gdkp-prices")
  LR.UI.closeAll()
  -- payouts by mail: at a mailbox, filled in for you to send
  M.openMail()
  LR.UI.go("session")
  clickText("Payouts")
  check("at the mailbox: a payout to mail", visible("Mail Lead") == false and (visible("Mail ") and visible("still to mail")))
  shot("gdkp-mail")
  LR.UI.closeAll()
  G.SendMailFrame:Hide()
  -- bookkeeping: gold put in by hand, the ledger, the payouts out and in
  LR.UI.go("session")
  clickText("Gold in or out")
  local edits = {}
  local function walk4(fr) for _, c in ipairs(fr._children or {}) do if c._type == "EditBox" and c:IsVisible() and not c._multi then edits[#edits + 1] = c end walk4(c) end end
  walk4(LR.UI.topSheet())
  edits[1]:SetText("200") edits[1]._scripts.OnTextChanged(edits[1], true)
  edits[2]:SetText("vendor greys") edits[2]._scripts.OnTextChanged(edits[2], true)
  clickText("Put in the pot")
  srv:tick(1)
  check("gold put in the pot by hand, with what for", LR.Gdkp.pot(s7) == 2000 and visible("+200g") and visible("vendor greys"))
  shot("gdkp-gold")
  LR.UI.closeAll()
  clickText("Ledger")
  check("the ledger: every sale, the gold put in, and payments", visible("Ledger") and visible("bought") and visible("Put in the pot: 200g (vendor greys)"))
  shot("gdkp-ledger")
  LR.UI.closeAll()
  clickText("Payouts")
  clickText("Copy out")
  local out
  local function walk5(fr) for _, c in ipairs(fr._children or {}) do if c._type == "EditBox" and c:IsVisible() and c._multi then out = c end walk5(c) end end
  walk5(LR.UI.topSheet())
  check("the payouts copied out, for a spreadsheet", out and out:GetText():find("^Name,Bought,Payout,Paid,Owed") ~= nil)
  clickText("Name,Gold")
  out = nil
  walk5(LR.UI.topSheet())
  check("or as Name,Gold lines", out and out:GetText():find("Ann,", 1, true) ~= nil and not out:GetText():find("Bought", 1, true))
  LR.UI.closeTop()
  clickText("Bring in payouts")
  local into
  walk5 = function(fr) for _, c in ipairs(fr._children or {}) do if c._type == "EditBox" and c:IsVisible() and c._multi then into = c end walk5(c) end end
  walk5(LR.UI.topSheet())
  into:SetText("Ann,500") into._scripts.OnTextChanged(into, true)
  clickText("Bring them in")
  srv:tick(1)
  check("payouts brought in: set by hand, the rest split", s7.gk.fixed and s7.gk.fixed["Ann-Dreamscythe"] == 500 and visible("payout set by hand 500g"))
  shot("gdkp-payouts-set")
  clickText("Back to an even split")
  srv:tick(1)
  check("and back to an even split", s7.gk.fixed == nil)
  LR.UI.closeAll()
  -- someone who won't pay: their bids aren't taken for the rest of tonight (right-click them in the loot master window)
  LR.gdkpStrict(s7, false)
  srv:tick(1)
  LR.Rolls.start(28529, {})
  srv:tick(0.5)
  srv:chatMessage(ann, "300", "RAID")
  srv:chatMessage(pug, "900", "RAID")
  srv:tick(0.5)
  LR.UI.showMaster()
  srv:tick(0.3)
  local mf = G.LootRulerMasterFrame
  check("the organiser's master window says a bidder can be right-clicked", #M.findText("Right-click a bidder to stop taking their bids tonight.", true, mf) > 0)
  local pugRow
  for _, x in ipairs(M.findText("Pug", true, mf)) do if x.frame._kind == "rollrow" then pugRow = x.frame end end
  for _, fr in ipairs(LR.UI.rollFrames()) do if fr.copy then fr.copy.closedByMe = true end end      -- (my own roll window: out of the picture)
  LR.UI.rollWindows()
  M.click(pugRow, "RightButton")
  srv:tick(0.3)
  check("right-click a bidder: asked first", visible("Stop taking their bids?") and visible("Pug's bids won't count for the rest of tonight's auctions"))
  shot("no-bids")
  clickText("Stop taking them")
  srv:tick(1)
  check("his bid stops counting: Ann's 300g is the highest again", LR.Rolls.mine().top and LR.Rolls.mine().top.p == "Ann-Dreamscythe")
  LR.Rolls.cancel()
  srv:tick(1)
  LR.Rolls.dismiss()
  LR.UI.go("session")
  srv:tick(0.3)
  check("the GDKP panel lists him, to take him back", visible("Bids not taken from:") and visible("Pug  x"))
  shot("gdkp-no-bids")
  clickText("Pug  x")
  srv:tick(1)
  check("a click takes his bids again", s7.gk.nb == nil and not visible("Bids not taken from:"))
  LR.gdkpRemoveAdd(s7, 1)
  LR.endSession(s7)
  srv:tick(1)
  LR.UI.go("reserve")
end)

run("bidding ahead", function()
  local sa = LR.startSession("Karazhan", 2, true, false)
  LR.setGdkp(sa, true)
  srv:tick(1)
  LR.Rolls.enqueue({ { id = 28525 }, { id = 28530 }, { id = 28528 } })
  srv:tick(1)
  local fr
  for _, x in ipairs(ann.LR.UI.rollFrames()) do if x:IsShown() and x.copy and x.copy.id == 28525 then fr = x end end
  check("an auction with more to come: Ann's window offers to bid ahead", fr and fr.extras[2]:IsShown() and M.plain(fr.extras[2].text:GetText()) == "Bid ahead")
  shot("bid-ahead-window", ann, { fr and fr:GetName() or "LootRulerRollFrame1" })
  -- any amount: a box for the gold, typed in raid chat like the window's two bids
  check("and to bid any amount", fr.extras[1]:IsShown() and M.plain(fr.extras[1].text:GetText()) == "Bid an amount")
  ann.M.click(fr.extras[1])
  srv:tick(0.3)
  check("a box for the gold, saying the least that counts", visible("Bid on Signet of Unshakable Faith", ann) and visible("The lowest bid that counts now", ann))
  local amountBox
  local function findBox(f) for _, c in ipairs(f._children or {}) do if c._type == "EditBox" and c:IsVisible() then amountBox = c end findBox(c) end end
  findBox(ann.LR.UI.topSheet())
  amountBox:SetText("10") amountBox._scripts.OnTextChanged(amountBox, true)
  clickText("Bid", 1, ann)
  srv:tick(0.3)
  check("too little isn't typed: she's told the least, and asked again", #ann.M.findText("The lowest bid that counts now is", true, ann.G.LootRulerFrame) > 0
    and visible("Bid on Signet", ann) and (LR.Rolls.current.top == nil or LR.Rolls.current.top.n ~= 10))
  findBox(ann.LR.UI.topSheet())
  amountBox:SetText("777") amountBox._scripts.OnTextChanged(amountBox, true)
  srv:tick(4)                -- (the toast goes)
  fr:ClearAllPoints() fr:SetPoint("TOPLEFT", ann.G.UIParent, "TOPLEFT", 760, -60)       -- (beside the box, for the picture)
  shot("bid-amount", ann)
  clickText("Bid", 1, ann)
  srv:tick(1)
  local cur = LR.Rolls.current
  check("her amount is typed in raid chat and counts", cur and cur.top and cur.top.p == "Ann-Dreamscythe" and cur.top.n == 777)
  ann.LR.UI.win:Hide()
  srv:tick(0.5)
  ann.M.click(fr.extras[2])
  srv:tick(0.3)
  check("it lists what's coming up", visible("Bid ahead", ann) and visible("Brooch of Unquenchable Fury", ann) and visible("Moroes' Lucky Pocket Watch", ann)
    and visible("No bid ahead yet", ann))
  clickText("Bid", 1, ann)
  local box
  local function walk(f) for _, c in ipairs(f._children or {}) do if c._type == "EditBox" and c:IsVisible() then box = c end walk(c) end end
  walk(ann.LR.UI.topSheet())
  box:SetText("900") box._scripts.OnTextChanged(box, true)
  clickText("Save", nil, ann)
  srv:tick(1)
  check("her bid ahead goes to the loot master", LR.Rolls.aheadCount(28530) == 1 and ann.LR.Rolls.myAhead[28530] == 900
    and visible("Your bid ahead: up to 900g", ann))
  shot("bid-ahead", ann)
  ann.LR.UI.closeAll()
  ann.LR.UI.win:Hide()
  LR.Rolls.clearQueue()
  LR.Rolls.cancel()
  srv:tick(1)
  LR.Rolls.dismiss()
  LR.endSession(sa)
  srv:tick(10)
end)

run("several auctions at once", function()
  local sb = LR.startSession("Karazhan", 2, true, false)
  LR.setGdkp(sb, true)
  srv:tick(1)
  srv:openLoot(lead, { { 28525, 4 }, { 28530, 4 }, { 28528, 4 } })
  srv:tick(0.5)
  LR.UI.show("session")
  srv:tick(0.3)
  clickText("Auction several at once")
  check("pick what goes up together, and for how long", visible("Auction several at once") and ticked("Signet of Unshakable Faith") == true and visible("Auction 3 together"))
  shot("batch-sheet")
  clickTick("Moroes' Lucky Pocket Watch", true)
  check("one less", visible("Auction 2 together"))
  clickTick("Moroes' Lucky Pocket Watch", false)
  clickText("Auction 3 together")
  srv:tick(1)
  local batch = LR.Batch.current
  check("it starts", batch and batch.state == "open" and #batch.items == 3)
  srv:chatMessage(pug, "#2 600", "RAID")
  srv:tick(1)
  local bw = ann.G.LootRulerBatchFrame
  check("Ann's window: every item, the highest bid, a button for each", bw and bw:IsShown() and #ann.M.findText("Highest: Pug, 600g", true, bw) > 0)
  shot("batch-window", ann, { "LootRulerBatchFrame" })
  check("any amount on any item: pick it, then the gold", #ann.M.findText("Bid an amount", true, bw) > 0)
  ann.M.click(ann.M.findText("Bid an amount", true, bw)[1].clickable)
  srv:tick(0.3)
  check("each item with the least that counts", visible("Which item?", ann) and visible("Lowest bid now: ", ann))
  clickText("Bid", 2, ann)
  srv:tick(0.3)
  local bbox
  local function findB(f) for _, c in ipairs(f._children or {}) do if c._type == "EditBox" and c:IsVisible() then bbox = c end findB(c) end end
  findB(ann.LR.UI.topSheet())
  bbox:SetText("950") bbox._scripts.OnTextChanged(bbox, true)
  clickText("Bid", 1, ann)
  srv:tick(1)
  check("typed with the item's number, and it counts", batch.items[2].top and batch.items[2].top.p == "Ann-Dreamscythe" and batch.items[2].top.n == 950)
  ann.LR.UI.win:Hide()
  check("the loot master's has more time, close and call off", #M.findText("Close now", true, G.LootRulerBatchFrame) > 0 and #M.findText("Call off", true, G.LootRulerBatchFrame) > 0)
  shot("batch-master", lead, { "LootRulerBatchFrame" })
  G.LootRulerBatchFrame.close:Click()
  check("its x hides it; the auction goes on", not G.LootRulerBatchFrame:IsShown() and batch.state == "open")
  G.SlashCmdList.LOOTRULER("batch")
  check("/lr batch brings it back", G.LootRulerBatchFrame:IsShown())
  LR.Batch.cancel()
  srv:tick(1)
  check("called off: nothing sold", batch.state == "cancelled" and #(sb.won or {}) == 0)
  srv:closeLoot(lead)
  LR.UI.closeAll()
  LR.endSession(sb)
  srv:tick(2)
  LR.UI.show("reserve")
end)

run("a bag check", function()
  ann.LR.db.settings.answerBagChecks = true
  bob.LR.db.settings.answerBagChecks = true
  srv:giveItem(ann, 28528, 2)
  local sbag = LR.startSession("Karazhan", 2, true, false)
  srv:tick(1)
  LR.UI.show("loot")
  srv:tick(0.3)
  clickText("Bag check")
  check("pick the items to ask about", visible("Ask everyone in the group with LootRuler") and visible("No items yet."))
  clickText("Add an item")
  local box
  local function walk(f) for _, c in ipairs(f._children or {}) do if c._type == "EditBox" and c:IsVisible() then box = c end walk(c) end end
  walk(LR.UI.topSheet())
  box:SetText("pocket watch") box._scripts.OnTextChanged(box, true)
  srv:tick(0.3)
  M.click(rowFor("Moroes' Lucky Pocket Watch"))
  srv:tick(0.3)
  check("an item picked", visible("Moroes' Lucky Pocket Watch") and visible("Ask the group"))
  clickText("Ask the group")
  srv:tick(2)
  check("the report: Ann has two, Bob none, Pug can't be asked", visible("Bag check") and visible("No LootRuler: can't be asked.") and visible("none"))
  shot("bag-check")
  LR.UI.closeAll()
  LR.endSession(sbag)
  srv:tick(1)
  LR.UI.go("reserve")
end)

run("the gear overview", function()
  ann.links = { [1] = "|cffa335ee|Hitem:28423::::::::70:::::|h[Helm]|h|r", [5] = "|cffa335ee|Hitem:28530::::::::70:::::|h[Brooch]|h|r",
    [16] = "|cffa335ee|Hitem:28525::::::::70:::::|h[Signet]|h|r" }
  pug.links = { [1] = "|cffa335ee|Hitem:28528::::::::70:::::|h[Watch]|h|r" }
  M.player.links = { [3] = "|cffa335ee|Hitem:28529::::::::70:::::|h[Cloak]|h|r" }
  local sg = LR.startSession("Karazhan", 2, true, false)
  srv:tick(1)
  LR.UI.show("loot")
  srv:tick(0.3)
  clickText("Raid gear")
  srv:tick(12)
  check("everyone, with their item level and when it was read", visible("Raid gear") and visible("item level 115") and visible("just now") and visible("(inspected)"))
  shot("raid-gear")
  local annRow = rowFor("Ann")
  M.click(annRow.act)
  srv:tick(0.3)
  check("a click shows what they wear, slot by slot", visible("Head") and visible("Chest") and visible("Main hand") and visible("[Helm]") == false
    and visible("Helm") and visible("Nothing in: Neck, Shoulder"))
  shot("raid-gear-player")
  LR.UI.closeAll()
  ann.links, pug.links, M.player.links = nil, nil, nil
  LR.endSession(sg)
  srv:tick(1)
  LR.UI.go("reserve")
end)

run("the organiser's branding", function()
  local sbr = LR.startSession("Karazhan", 2, true, false)
  srv:tick(1)
  LR.UI.go("session")
  srv:tick(0.3)
  check("the Session tab has the raid's name", visible("Your raid's name") and visible("Icon:"))
  local boxes = {}
  local function walk(f) for _, c in ipairs(f._children or {}) do if c._type == "EditBox" and c:IsVisible() and not c._multi then boxes[#boxes + 1] = c end walk(c) end end
  walk(G.LootRulerFrame)
  local nameBox, msgBox
  for _, b in ipairs(boxes) do
    if math.abs(b:GetWidth() - 240) < 1 then nameBox = b elseif b:GetWidth() > 300 then msgBox = msgBox or b end
  end
  nameBox:SetText("<Kings> Karazhan") nameBox._scripts.OnTextChanged(nameBox, true)
  msgBox:SetText("Sign up on our Discord: kings-guild") msgBox._scripts.OnTextChanged(msgBox, true)
  clickText("Dragon")
  clickText("Save")
  srv:tick(1)
  check("saved: name, message and icon", sbr.br and sbr.br.n == "<Kings> Karazhan" and sbr.br.m == "Sign up on our Discord: kings-guild" and sbr.br.i == 3)
  check("the window's header shows it", visible("<Kings> Karazhan - 2 reserves each"))
  local function scrollers(fr, out) for _, c in ipairs(fr._children) do if c._type == "ScrollFrame" and c:IsVisible() then out[#out + 1] = c end scrollers(c, out) end return out end
  local sf = scrollers(G.LootRulerFrame, {})[1]
  local panelText = M.findText("Your raid's name", true, G.LootRulerFrame)[1]
  sf:SetVerticalScroll(math.min(sf:GetVerticalScrollRange(), math.max(0, sf:GetVerticalScroll() + (sf:GetTop() or 0) - (panelText.fs:GetTop() or 0) - 20)))
  shot("brand")
  sf:SetVerticalScroll(0)
  ann.LR.UI.show("reserve")
  srv:tick(0.3)
  check("raiders see the name and message", visible("<Kings> Karazhan: Sign up on our Discord: kings-guild", ann))
  shot("brand-raider", ann)
  ann.LR.UI.win:Hide()
  LR.endSession(sbr)
  srv:tick(1)
  local nextOne = LR.startSession("Karazhan", 2, true, false)
  srv:tick(2)
  check("the next session starts with it", nextOne.br and nextOne.br.n == "<Kings> Karazhan")
  check("raiders are told whose raid it is", (function() for _, l in ipairs(ann.M.chat) do if l:find("opened soft reserves for Karazhan (<Kings> Karazhan)", 1, true) then return true end end end)())
  LR.setBrand(nextOne, nil)
  LR.endSession(nextOne)
  srv:tick(1)
  LR.UI.go("reserve")
end)

run("a loot council", function()
  local slc = LR.startSession("Karazhan", 2, true, false)
  srv:tick(1)
  LR.UI.go("session")
  srv:tick(0.3)
  check("the Session tab has the loot council", visible("Loot council") and visible("Off: nobody on the council, so rolls decide."))
  clickTick("Ann", false)
  clickTick("Lead", false)
  srv:tick(1)
  check("pick who's on it", slc.lc and #slc.lc == 2 and visible("On: 2 players on the council."))
  local function scrollers(fr, out) for _, c in ipairs(fr._children) do if c._type == "ScrollFrame" and c:IsVisible() then out[#out + 1] = c end scrollers(c, out) end return out end
  local sf = scrollers(G.LootRulerFrame, {})[1]
  local head = M.findText("Loot council", true, G.LootRulerFrame)[1]
  sf:SetVerticalScroll(math.min(sf:GetVerticalScrollRange(), math.max(0, sf:GetVerticalScroll() + (sf:GetTop() or 0) - (head.fs:GetTop() or 0) - 20)))
  shot("council-setup")
  sf:SetVerticalScroll(0)
  LR.UI.win:Hide()
  local lr = LR.Rolls.start(28525, { secs = 10 })
  srv:tick(0.5)
  srv:roll(pug, 1, 100, 77)
  srv:roll(bob, 1, 99, 55)
  srv:tick(1)
  local af
  for _, x in ipairs(ann.LR.UI.rollFrames()) do if x:IsShown() and x.copy and x.copy.id == 28525 then af = x end end
  check("a council member's window has a vote button", af and af.extras[1]:IsShown() and M.plain(af.extras[1].text:GetText()) == "Council: vote")
  ann.M.click(af.extras[1])
  srv:tick(0.3)
  check("it lists who rolled, with how", visible("Loot council: Signet of Unshakable Faith", ann) and visible("Pug", ann) and visible("MS 77", ann))
  local vb
  for _, h in ipairs(ann.M.findText("Vote", true, ann.LR.UI.topSheet())) do if h.clickable and ann.M.plain(h.fs:GetText()) == "Vote" then vb = vb or h.clickable end end
  ann.M.click(vb)
  srv:tick(3)
  check("her vote goes in", next(lr.votes or {}) ~= nil and visible("Your vote", ann))
  shot("council-vote", ann)
  ann.LR.UI.closeAll()
  ann.LR.UI.win:Hide()
  srv:tick(12)
  check("the loot master sees the votes and the choice", #M.findText("Their choice:", true, G.LootRulerMasterFrame) > 0 and #M.findText("1 vote", true, G.LootRulerMasterFrame) > 0)
  shot("council-master", lead, { "LootRulerMasterFrame" })
  LR.Rolls.cancel()
  LR.Rolls.dismiss()
  LR.setCouncil(slc, nil)
  LR.endSession(slc)
  srv:tick(10)
  LR.UI.show("reserve")
end)

run("who got what, over time", function()
  LR.UI.show("loot")
  srv:tick(0.3)
  clickText("Award history")
  srv:tick(0.3)
  clickText("Who got what, over time")
  check("everyone's loot over past raids, most first", visible("Who got what, over time") and visible("4 weeks") and visible("Everything")
    and #LR.History.fairness(0) > 0)
  shot("fairness")
  local first = LR.History.fairness(LR.U.now() - 28 * 86400, LR.current())[1]
  check("each with what they won and how many raids", first and visible(LR.U.short(first.p)) and visible(LR.U.plural(first.raids, "raid"), nil) ~= nil)
  local r = rowFor(LR.U.short(first.p))
  M.click(r.act)
  srv:tick(0.3)
  check("a click lists their items", visible(LR.U.plural(#first.items, "item") .. " in "))
  shot("fairness-player")
  LR.UI.closeAll()
  LR.UI.go("reserve")
end)

run("swap requests", function()
  local ssw = LR.startSession("Karazhan", 2, true, false)
  srv:tick(1)
  LR.leaderAdd(ssw, "Ann-Dreamscythe", "PRIEST", 28528)
  LR.setLocked(ssw, true)
  srv:tick(2)
  ann.LR.UI.show("reserve")
  srv:tick(0.3)
  check("locked: Ann can ask to swap one", visible("Ask to swap one", ann))
  clickText("Ask to swap one", nil, ann)
  check("she picks the reserve to give up", visible("Swap a reserve", ann) and visible("Moroes' Lucky Pocket Watch", ann))
  clickText("Swap", nil, ann)
  srv:tick(0.3)
  check("then the item she'd like", visible("Swap Moroes' Lucky Pocket Watch for which item?", ann))
  ann.M.click(rowFor("Signet of Unshakable Faith", ann))
  srv:tick(2)
  check("asked: she's waiting", visible("You asked to swap", ann) and #LR.Swap.pending(ssw) == 1)
  shot("swap-ask", ann)
  ann.LR.UI.win:Hide()
  LR.UI.show("reserves")
  srv:tick(0.3)
  check("the leader sees it, to allow or refuse", visible("Swap requests (1)") and visible("Allow") and visible("No"))
  shot("swap-requests")
  clickText("Allow")
  srv:tick(2)
  check("allowed: swapped", LR.Session.reservesOf(ssw, "Ann-Dreamscythe")[1] == 28525 and not visible("Swap requests (1)"))
  LR.endSession(ssw)
  srv:tick(1)
  LR.UI.go("reserve")
end)

run("clearing reserves of players not in the group", function()
  local sab = LR.startSession("Karazhan", 2, true, false)
  srv:tick(1)
  LR.leaderAdd(sab, "Ann-Dreamscythe", "PRIEST", 28528)
  LR.leaderAdd(sab, "Gone-Dreamscythe", "WARRIOR", 28525)
  srv:tick(2)
  LR.UI.show("reserves")
  srv:tick(0.3)
  check("the leader sees how many have left", visible("Clear reserves of players not in the group (1)"))
  clickText("Clear reserves of players not in the group (1)")
  check("and who, before anything goes", visible("Clear their reserves") and visible("Gone: not in the group") and visible("Clear 1"))
  shot("clear-absent")
  clickText("Clear 1")
  srv:tick(2)
  check("their reserves go; Ann keeps hers", #LR.Session.reservesOf(sab, "Gone-Dreamscythe") == 0 and #LR.Session.reservesOf(sab, "Ann-Dreamscythe") == 1)
  check("and the button says nobody's left", visible("Clear reserves of players not in the group") and not visible("Clear reserves of players not in the group (1)"))
  LR.endSession(sab)
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
  clickTick("Ann", false)
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

run("award history", function()
  LR.UI.go("loot")
  clickText("This raid")
  srv:tick(0.3)
  check("the Loot tab opens on this raid's loot, with the award history beside it", visible("Award history") and not visible("Everything given out in your raids"))
  clickText("Award history")
  srv:tick(0.3)
  local all = LR.UI.awardHistory()
  local today = os.date("%A, %B %d", all[1].at)
  check("the award history: a date for each day loot was given out, newest first, open", visible("Everything given out in your raids")
    and visible(today) and rowFor(LR.itemName(all[1].w.i)) ~= nil, today)
  local first = LR.itemName(all[1].w.i)
  -- an award from three days before: a date of its own, closed to start with
  local old = all[#all]
  old.w.at = old.at - 3 * 86400
  LR.UI.render()
  srv:tick(0.3)
  local oldDay = os.date("%A, %B %d", old.w.at)
  check("each day is its own date; only the newest starts open", visible(oldDay) and visible(today) and not rowFor(LR.itemName(old.w.i)), oldDay)
  shot("award-history")
  clickText(today)
  srv:tick(0.3)
  check("a date closes with a click, and stays closed", not rowFor(first) and LR.db.ui.historyOpen[os.date("%Y-%m-%d", all[1].at)] == false)
  clickText(today)
  srv:tick(0.3)
  check("and opens again", rowFor(first) ~= nil)
  check("the award history has the export, who got what, and past raids", visible("Export") and visible("Who got what, over time")
    and visible(("Past raids (%d)"):format(#LR.History.all())))
end)

run("past raids", function()
  LR.UI.go("loot")
  clickText("Award history")
  srv:tick(0.3)
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
  -- several raids at once, in your own layout
  clickText("Export several raids")
  clickText("Everything")
  local total = 0
  for _, e in ipairs(LR.History.all()) do total = total + #(e.won or {}) end
  check("every past raid's loot, oldest first", visible(("%s from %s, oldest first."):format(LR.U.plural(total, "item"), LR.U.plural(n, "raid"))), total)
  clickText("Your own")
  check("your own layout: the fields it can fill in", visible("{date}") and visible("{raid}") and visible("Each line"))
  local edits = {}
  local function walk(fr) for _, c in ipairs(fr._children) do if c._type == "EditBox" and c:IsVisible() then edits[#edits + 1] = c end walk(c) end end
  walk(LR.UI.topSheet())
  local line, head
  for _, e in ipairs(edits) do if e._multi then else if not line then line = e else head = e end end end
  line:SetText("{raid}: {player} got {item} ({how})") line._scripts.OnTextChanged(line, true)
  head:SetText("Loot from our raids") head._scripts.OnTextChanged(head, true)
  clickText("Show it")
  local memo
  edits = {}
  walk(LR.UI.topSheet())
  for _, e in ipairs(edits) do if e._multi then memo = e end end
  local text = memo and memo:GetText() or ""
  check("written your way, for every raid", text:find("^Loot from our raids\n") ~= nil and text:find("Karazhan: ", 1, true) ~= nil and text:find(" got ", 1, true) ~= nil, text)
  check("and kept for next time", LR.db.settings.exportTemplate == "{raid}: {player} got {item} ({how})")
  shot("export-raids")
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
  -- pot rules of my own
  clickText("Pot rules (0)")
  check("pot rules: none yet, and how they work", visible("Your pot rules") and visible("None yet.") and visible("Add a rule"))
  clickText("Add a rule")
  check("adding one opens it", visible("A pot rule") and visible("Percent of the pot:") and visible("Who gets it") and #s10.gk.rules == 1)
  local box
  local function walk(fr) for _, c in ipairs(fr._children or {}) do if c._type == "EditBox" and c:IsVisible() then box = box or c end walk(c) end end
  walk(LR.UI.topSheet())
  box:SetText("Raid leader") box._scripts.OnTextChanged(box, true) box._scripts.OnEnterPressed(box)
  srv:tick(0.3)
  clickText("5%")
  clickTick("Lead", false)
  srv:tick(0.5)
  local r1 = s10.gk.rules[1]
  check("named, a percent, and who gets it", r1.n == "Raid leader" and r1.pct == 5 and r1.to[1] == "Lead-Dreamscythe" and ticked("Lead") == true)
  shot("pot-rule")
  clickText("Done")
  check("listed with what it pays", visible("Raid leader") and visible("5% of the pot each: Lead"))
  shot("pot-rules")
  LR.UI.closeAll()
  check("the GDKP panel counts them", visible("Pot rules (1)"))
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
  -- the leader leaves; Ann is the master looter (an assistant isn't offered it)
  srv:setAssist(bob, true)
  srv:setMasterLooter(ann)
  srv:leaveGroup(lead)
  srv:tick(6)
  clickText("Not now", nil, ann)             -- (becoming master looter asks first)
  ann.LR.UI.show("session")
  srv:tick(0.3)
  check("the master looter is offered the reserves", visible("Nobody's running the reserves", ann) and visible("Take over the reserves", ann)
    and visible("Hand them to someone else", ann))
  bob.LR.UI.show("session")
  srv:tick(0.3)
  check("an assistant isn't", not visible("Take over the reserves", bob))
  bob.LR.UI.win:Hide()
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
  srv:setAssist(bob, false)
  srv:setMasterLooter(nil)
  srv:tick(5)
  ann.LR.endSession(ann.LR.session(s5.id))
  srv:tick(2)
  ann.LR.UI.win:Hide()
  LR.UI.go("reserve")
end)

run("the Test tab", function()
  LR.UI.go("settings")
  clickText("Open all")
  local tabShown = function()
    for _, x in ipairs(M.findText("Test", true, G.LootRulerFrame)) do if M.plain(x.fs:GetText()) == "Test" and x.clickable and x.clickable:IsShown() then return true end end
    return false
  end
  local ts = LR.startSession("Karazhan", 2, true, false)
  srv:tick(1)
  check("the Test tab is hidden to start with", not tabShown())
  clickTick("Show the Test tab", false)
  check("switched on in Settings, it's there", tabShown())
  clickText("Test")
  check("pretend rolls, messages and names", visible("Pretend rolls") and visible("Pretend messages") and visible("Names from softres.it"))
  -- eight made-up players reserved it, and me (the practice raid's two steppers come first)
  clickText("+", 3) clickText("+", 3)
  check("how many reserved it can be changed", visible("8"))
  local chatBefore, rolledBefore = #srv.chat, #(M.rolled or {})
  local annRolls = #ann.LR.Rolls.order
  clickText("LootRuler roll: reserved")
  srv:tick(0.5)
  local strip = G.LootRulerReserveStrip
  local names = strip and M.plain(strip.names:GetText()) or ""
  check("a pretend reserved roll: the window and the strip with every name", strip and strip:IsShown() and names:find("Arthas", 1, true)
    and names:find("Valeera", 1, true) and names:find("Malfurion", 1, true) and not names:find("+", 1, true), names)
  local fr
  for _, x in ipairs(LR.UI.rollFrames()) do if x:IsShown() and x.copy and x.copy.test then fr = x end end
  shot("test-roll", lead, { "LootRulerReserveStrip", fr and fr:GetName() or "LootRulerRollFrame1" })
  M.click(fr.dice)
  srv:tick(0.5)
  check("its dice roll here, not with /roll", fr.copy.rolled[LR.Roll.key(LR.U.me())] ~= nil and #(M.rolled or {}) == rolledBefore)
  check("nothing reaches chat or anyone else", #srv.chat == chatBefore and #ann.LR.Rolls.order == annRolls)
  srv:tick(25)
  check("the strip goes when the pretend roll ends", not strip:IsShown())
  -- closing the pretend roll's window with its x takes the strip with it, though the roll is still on
  clickText("LootRuler roll: reserved")
  srv:tick(0.5)
  local fr2
  for _, x in ipairs(LR.UI.rollFrames()) do if x:IsShown() and x.copy and x.copy.test and x.copy.state == "open" then fr2 = x end end
  check("a second pretend roll shows the strip", fr2 and strip:IsShown())
  M.click(fr2.pass)
  srv:tick(0.3)
  check("its x closes the window, and the strip goes with it", not fr2:IsShown() and not strip:IsShown() and fr2.copy == nil)
  srv:tick(25)
  clickText("Gargul roll")
  srv:tick(0.5)
  check("a pretend Gargul roll shows the strip", strip:IsShown() and M.plain(strip.names:GetText()):find("Thrall", 1, true))
  local gf
  for _, x in ipairs(LR.UI.rollFrames()) do if x:IsShown() and x.copy and x.copy.gargul then gf = x end end
  check("and a roll window, as raiders without Gargul get", gf ~= nil and gf.dice:IsEnabled() and M.plain(gf.status:GetText()):find("You reserved this", 1, true))
  shot("test-gargul", lead, { "LootRulerReserveStrip", gf and gf:GetName() or "LootRulerRollFrame1" })
  srv:tick(25)
  check("and it goes too", not strip:IsShown())
  local n = #M.notices
  clickText("The 2 hours running out")
  check("the trade warning, on screen only", #M.notices == n + 1 and M.notices[#M.notices]:find("14 minutes left to trade", 1, true) and #srv.chat == chatBefore)
  clickText("The reminder")
  check("the reminder, shown not posted", (function() for _, l in ipairs(M.chat) do if l:find("(pretend, not posted)", 1, true) then return true end end end)()
    and #srv.chat == chatBefore)
  for _, rf in ipairs(LR.UI.rollFrames()) do rf:Hide() end      -- (the pretend Gargul roll's window, for a clear picture)
  clickText("Changing raids")
  check("changing raids: the question, as it would come", visible("You're in Black Temple, but your session is for Karazhan.") and visible("Start Black Temple"))
  shot("new-raid")
  clickText("Start Black Temple")
  check("pretend: nothing changes", LR.current().raid == "Karazhan"
    and (function() for _, l in ipairs(M.chat) do if l:find("(pretend) A new session for Black Temple", 1, true) then return true end end end)())
  clickText("Test")
  clickText("A trade out of a group")
  local say = G.LootRulerSay
  check("a trade out of a group: the Say it button", say:IsShown() and #M.findText("to Thrall.", true, say) > 0)
  M.click(say.say)
  check("shown, not said", (function() for _, l in ipairs(M.chat) do if l:find("(pretend, not said)", 1, true) then return true end end end)()
    and #srv.chat == chatBefore and not say:IsShown())
  local box
  local function walk(fr2) for _, c in ipairs(fr2._children or {}) do if c._type == "EditBox" and c:IsVisible() then box = c end walk(c) end end
  walk(G.LootRulerFrame)
  M.click(box)
  M.type("bøb")
  srv:tick(0.5)
  check("a softres.it name to try: who it goes to", visible("Bøb goes to Bob-Faerlina"))
  shot("test-tab")
  LR.UI.go("settings")
  clickTick("Show the Test tab", true)
  check("switched off, it's gone", not tabShown())
  LR.endSession(ts)
  srv:tick(1)
  LR.UI.go("reserve")
end)

run("the practice raid", function()
  -- on my own: the others carry on without me
  srv:setGroup({ ann, bob, pug }, ann, true)
  lead.inGroup = false
  srv:rosterChanged()
  srv:tick(2)
  LR.db.settings.testTab = true
  LR.UI.show("test")
  srv:tick(0.3)
  check("the Test tab offers a practice raid", visible("Practice raid") and visible("Start the practice raid") and visible("Pretend players"))
  clickText("+")
  check("how many pretend players", visible("9"))
  shot("practice-start")
  local chatBefore = #srv.chat
  clickText("Start the practice raid")
  srv:tick(1)
  local ps = LR.current()
  check("it starts: a practice session with nine pretend players", ps and ps.practice and #LR.roster() == 10 and visible("On: Karazhan with 9 pretend players"))
  check("the window says it's practice", #M.findText("Practice: Karazhan", true, G.LootRulerFrame) > 0)
  clickText("They reserve")
  srv:tick(12)
  local reserved = 0
  for _, x in ipairs(LR.Practice.players) do reserved = reserved + #LR.Session.reservesOf(ps, x.name) end
  check("they reserve", reserved == 18, reserved)
  LR.UI.go("reserves")
  srv:tick(0.3)
  clickText("Open all")
  check("the Reserves tab lists them", visible("Arthas") and visible("Jaina"))
  shot("practice-reserves")
  LR.UI.go("test")
  clickText("A boss drops loot")
  srv:tick(0.5)
  check("a boss drops loot into my bags (and something to count)", #ps.drops == 4)
  -- (one pretend player reserves the first item twice: two rolls, the best counts)
  local twice = LR.Practice.players[1]
  LR.Session.set(ps, twice.name, twice.class, { ps.drops[1].i, ps.drops[1].i }, true, LR.U.now())
  clickText("Roll out the next item")
  srv:tick(8)
  local pr = LR.Rolls.mine()
  check("the next item is rolled out, and the pretend players roll", pr and pr.id == ps.drops[1].i and next(pr.rolled) ~= nil)
  check("a player who reserved it twice rolls twice: the loot master sees their best, and of how many",
    #M.findText("(best of 2)", true, G.LootRulerMasterFrame) > 0 and #M.findText("lower roll not listed", true, G.LootRulerMasterFrame) > 0)
  LR.UI.win:Hide()
  shot("practice-roll", lead, { "LootRulerMasterFrame" })
  srv:tick(20)
  check("it closes", pr.state == "closed")
  LR.Rolls.cancel()
  LR.Rolls.dismiss()
  check("nothing was said in chat", #srv.chat == chatBefore, #srv.chat - chatBefore)
  LR.UI.show("test")
  srv:tick(0.3)
  clickText("End the practice raid")
  srv:tick(0.5)
  check("ending it forgets it", not LR.Practice.on and LR.db.sessions[ps.id] == nil and visible("Start the practice raid"))
  LR.db.settings.testTab = false
  LR.UI.win:Hide()
  srv:setGroup({ lead, ann, bob, pug }, lead, true)
  srv:setMasterLooter(lead)
  srv:tick(2)
end)

run("item notes", function()
  LR.UI.go("settings")
  srv:tick(0.3)
  check("an Item notes panel on the Settings tab", visible("Item notes") and visible("Add a note"))
  clickText("Add a note")
  local edits = {}
  local function walk(fr) for _, c in ipairs(fr._children) do if c._type == "EditBox" and c:IsVisible() then edits[#edits + 1] = c end walk(c) end end
  walk(LR.UI.topSheet())
  M.click(edits[1])
  G.ChatEdit_InsertLink(srv.itemInfo(28525).link)
  srv:tick(0.3)
  edits = {}
  walk(LR.UI.topSheet())
  edits[2]:SetText("Warrior > Rogue") edits[2]._scripts.OnTextChanged(edits[2], true)
  clickText("Save")
  check("a note on an item", LR.noteFor(28525) == "Warrior > Rogue" and visible("Warrior > Rogue"))
  clickText("Bring in or copy out")
  check("copied out, one a line", visible("28525: Warrior > Rogue"))
  local memo
  edits = {}
  walk(LR.UI.topSheet())
  for _, e in ipairs(edits) do if e._multi then memo = e end end
  memo:SetText("28530: Tanks first\nnot a note\n28525: Warrior > Paladin") memo._scripts.OnTextChanged(memo, true)
  clickText("Bring them in")
  check("brought in: new notes, and changed ones replaced", LR.noteFor(28530) == "Tanks first" and LR.noteFor(28525) == "Warrior > Paladin")
  shot("item-notes-io")
  LR.UI.closeAll()
  -- a pretend roll on an item with a note shows it
  local copy = LR.UI.testRoll({ quiet = true })
  copy.note = "Warrior > Paladin"
  LR.UI.rollWindows()
  local fr
  for _, x in ipairs(LR.UI.rollFrames()) do if x:IsShown() and x.copy == copy then fr = x end end
  check("a roll window shows the note", fr and fr.note:IsShown() and fr.note:GetText() == "Note: Warrior > Paladin")
  shot("roll-note", lead, { fr and fr:GetName() or "LootRulerRollFrame1" })
  copy.closedByMe = true
  LR.UI.rollWindows()
  for id in pairs(LR.db.notes) do LR.setNote(id, nil) end
end)

run("a burst of rolls redraws the windows a few times, not once a roll", function()
  local draws, rollDraws = 0, 0
  local masterDraw, rollWindows = LR.UI.masterDraw, LR.UI.rollWindows
  LR.UI.masterDraw = function(...) draws = draws + 1 return masterDraw(...) end
  LR.UI.rollWindows = function(...) rollDraws = rollDraws + 1 return rollWindows(...) end
  srv:tick(1)
  draws, rollDraws = 0, 0
  for _ = 1, 40 do LR.changed("roll") LR.changed("rolls") srv:tick(0.05, 0.05) end
  srv:tick(1)
  check("40 rolls in two seconds redraw the loot master window about once a quarter second", draws >= 2 and draws <= 10, draws)
  check("and roll windows the same", rollDraws >= 2 and rollDraws <= 10, rollDraws)
  draws = 0
  LR.changed("roll")
  check("one on its own still shows at once", draws == 1, draws)
  LR.UI.masterDraw, LR.UI.rollWindows = masterDraw, rollWindows
end)

run("a roll for each reserve", function()
  srv:tick(6)                -- (the last message goes)
  local copy = LR.UI.testRoll({ quiet = true, mode = "SR", mine = 2, reservers = 2 })
  LR.UI.rollWindows()
  local fr
  for _, x in ipairs(LR.UI.rollFrames()) do if x:IsShown() and x.copy == copy then fr = x end end
  check("two reserves: the window says I roll twice", fr and M.plain(fr.status:GetText()):find("You reserved this 2 times: you roll 2 times, your best counts", 1, true) ~= nil,
    fr and M.plain(fr.status:GetText()))
  M.click(fr.dice)
  srv:tick(0.3)
  check("after one, it offers the second", fr.dice:IsEnabled() and M.plain(fr.status:GetText()):find("1 roll left (one for each reserve)", 1, true) ~= nil,
    M.plain(fr.status:GetText()))
  shot("roll-twice", lead, { fr:GetName() })
  M.click(fr.dice)
  srv:tick(0.3)
  check("after both, my best counts and there are no more", not fr.dice:IsEnabled() and M.plain(fr.status:GetText()):find("Your best:", 1, true) ~= nil)
  copy.closedByMe = true
  LR.UI.rollWindows()
end)

run("thatsmybis wishlists", function()
  LR.UI.go("settings")
  srv:tick(6)                -- (the last message goes)
  clickText("Bring in wishlists")
  local memo
  local function walk(fr) for _, c in ipairs(fr._children) do if c._type == "EditBox" and c:IsVisible() and c._multi then memo = c end walk(c) end end
  walk(LR.UI.topSheet())
  memo:SetText('{"wishlists":{"28525":["ann|1|2|0","bob-faerlina|2|2|0","zed|3|2|0"],"28530":["pug|1|2|0"]}}') memo._scripts.OnTextChanged(memo, true)
  clickText("Read it")
  check("what's in it, before bringing it in", visible("2 items on wishlists, 4 places."))
  shot("wishlists")
  clickText("Bring them in")
  check("brought in", LR.db.wish[28525] and #LR.db.wish[28525] == 3 and visible("2 items on wishlists (4 places)."))
  local copy = LR.UI.testRoll({ quiet = true })
  copy.wish = LR.wishFor(28525, true)
  LR.UI.rollWindows()
  local fr
  for _, x in ipairs(LR.UI.rollFrames()) do if x:IsShown() and x.copy == copy then fr = x end end
  check("a roll window says who in the group wishlisted it", fr and fr.note:GetText() == "Wishlist: Ann (1), Bob-Faerlina (2)", fr and fr.note:GetText())
  shot("roll-wishlist", lead, { fr and fr:GetName() or "LootRulerRollFrame1" })
  copy.closedByMe = true
  LR.UI.rollWindows()
  clickText("Forget them")
  clickText("Forget")
  check("and forgotten", next(LR.db.wish) == nil)
end)

run("becoming the master looter", function()
  local was = srv.masterLooter
  srv:setMasterLooter(nil)
  srv:tick(1)
  srv:setMasterLooter(lead)
  srv:tick(1)
  check("asked what to do", visible("You're the master looter") and visible("Tell the raid") and visible("Open the loot master window"))
  shot("master-looter")
  clickText("Not now")
  srv:setMasterLooter(was)
  srv:tick(1)
  LR.UI.closeAll()
end)

run("loot given out without LootRuler", function()
  local rs = LR.current() or LR.startSession("Karazhan", 2, true, false)
  srv:tick(1)
  srv:openLoot(lead, { { 28530, 4 } })
  srv:tick(0.5)
  local idx
  for i = 1, 40 do local n = G.GetMasterLootCandidate(1, i) if n and n:find("Ann", 1, true) then idx = i end end
  G.GiveMasterLoot(1, idx)
  srv:tick(1)
  check("given with the game's loot menu: record it?", visible("Record it?") and visible("Main spec") and visible("Leave it"))
  shot("record-it")
  clickText("Leave it")
  srv:closeLoot(lead)
  srv:tick(1)
  LR.UI.closeAll()
end)

run("roll window options", function()
  LR.UI.go("settings")
  srv:tick(6)
  check("told when I'm outbid, to start with", ticked("Tell me when I'm outbid") == true)
  check("sounds: on, and on the main channel, to start with", ticked("LootRuler's sounds") == true and visible("Play them on:") and LR.db.settings.soundChannel == "Master")
  clickText("Effects")
  check("the channel can be changed", LR.db.settings.soundChannel == "SFX")
  do
    local function scrollers(fr, out) for _, c in ipairs(fr._children) do if c._type == "ScrollFrame" and c:IsVisible() then out[#out + 1] = c end scrollers(c, out) end return out end
    local sf = scrollers(G.LootRulerFrame, {})[1]
    local at = M.findText("Play them on:", true, G.LootRulerFrame)[1]
    if sf and at then sf:SetVerticalScroll(math.min(sf:GetVerticalScrollRange(), math.max(0, sf:GetVerticalScroll() + sf:GetTop() - at.fs:GetTop() - 150))) end
    shot("sounds")
    if sf then sf:SetVerticalScroll(0) end
  end
  clickText("Main")
  check("and when my item is up, wishlisted ones too", visible("have on your thatsmybis wishlist is rolled out"))
  check("new options, off to start with", ticked("Not for items my class can't use") == false and ticked("Close the window once I've rolled") == false and visible("Size:"))
  clickText("Bigger")
  check("bigger roll windows", LR.db.settings.rollScale == 1.3)
  local copy = LR.UI.testRoll({ quiet = true })
  local fr
  for _, x in ipairs(LR.UI.rollFrames()) do if x:IsShown() and x.copy == copy then fr = x end end
  check("the window is bigger", fr and fr:GetScale() == 1.3)
  shot("roll-options")
  clickText("Normal")
  check("and back", fr:GetScale() == 1)
  copy.closedByMe = true
  LR.UI.rollWindows()
end)

run("more loot rules", function()
  LR.UI.go("settings")
  srv:tick(6)
  check("picking up the gold is its own switch, off to start with", ticked("Pick up the gold") == false)
  check("counting group loot wins is off to start with", ticked("Count group loot wins as given out") == false and not LR.db.settings.recordGroupWins)
  check("telling the guild who got what is off to start with", ticked("Tell my guild who got what") == false and not LR.db.settings.awardGuild)
  do
    local function scrollers(fr, out) for _, c in ipairs(fr._children) do if c._type == "ScrollFrame" and c:IsVisible() then out[#out + 1] = c end scrollers(c, out) end return out end
    local sf = scrollers(G.LootRulerFrame, {})[1]
    local at = M.findText("Tell my guild who got what", true, G.LootRulerFrame)[1]
    if sf and at then sf:SetVerticalScroll(math.min(sf:GetVerticalScrollRange(), math.max(0, sf:GetVerticalScroll() + sf:GetTop() - at.fs:GetTop() - 200))) end
    shot("running-loot")
    if sf then sf:SetVerticalScroll(0) end
  end
  clickText("Add a rule")
  clickText("Anything below epic")
  clickText("Everyone in turn")
  check("in turn, by quality range", visible("Anything below epic will go to everyone in turn."))
  shot("loot-rule-turns")
  clickText("Add the rule")
  clickText("Add a rule")
  clickText("Gems")
  clickText("Nobody: leave it")
  clickText("Add the rule")
  local rules = LR.db.settings.autoLootRules
  check("both listed", rules[#rules - 1].to == "rr" and rules[#rules].to == "skip" and visible("Goes to everyone in turn") and visible("Goes to nobody: it's left where it is"))
  table.remove(rules) table.remove(rules)
end)

run("need and greed rules", function()
  LR.UI.go("settings")
  srv:tick(6)                -- (the last message goes)
  check("off to start with", ticked("Roll Need / Greed by my rules") == false and not LR.db.settings.groupLoot)
  clickText("Add a Need / Greed rule")
  clickText("Uncommon (green) items")
  check("TBC's Need / Greed windows have no Disenchant roll, so it isn't offered", visible("Need") and visible("Pass") and not visible("Disenchant"))
  clickText("Greed")
  check("it says what the rule does", visible("Uncommon (green) items: Greed."))
  shot("group-rule")
  clickText("Add the rule")
  check("the rule is listed", #LR.db.settings.groupLootRules == 1 and visible("Greed"))
  clickText("Roll Need / Greed by my rules")
  check("switched on", LR.db.settings.groupLoot == true)
  M.click(rowFor("Uncommon (green) items").act)
  check("a rule can be removed", #LR.db.settings.groupLootRules == 0)
  clickText("Roll Need / Greed by my rules")
end)

run("raid setup", function()
  G.SlashCmdList.LOOTRULER("raid")
  srv:tick(0.3)
  check("/lr raid: paste who's coming", visible("Raid setup") and visible("Paste who's coming") and visible("No names yet."))
  local memo
  local function walk(fr) for _, c in ipairs(fr._children) do if c._type == "EditBox" and c:IsVisible() and c._multi then memo = c end walk(c) end end
  walk(LR.UI.topSheet())
  memo:SetText("Group 1\nLead\nAnn (Holy Priest)\nBob-Faerlina\nGroup 2: Kel, Mira\n1. Tor - Fury Warrior")
  memo._scripts.OnTextChanged(memo, true)
  clickText("Read the list")
  srv:tick(0.3)
  check("who's here and who's missing", visible("6 names on the list: 3 here, 3 not in the group.") and visible("Not here: Kel, Mira, Tor"))
  check("and who's here but not on the list", visible("In the group, not on the list: Pug"))
  check("the leader can invite, say who's missing and sort", visible("Invite 3") and visible("Say who's missing") and visible("Sort into groups"))
  check("the list is kept", LR.db.ui.lineup:find("Kel, Mira", 1, true) ~= nil)
  shot("raid-setup")
  clickText("Invite 3")
  check("invites go out", srv.invites and #srv.invites >= 3 and srv.invites[#srv.invites].name == "Tor")
  srv.invites = {}
  LR.UI.closeAll()
  LR.UI.go("session")
  srv:tick(0.3)
  check("on the Session tab too", visible("Raid setup"))
end)

run("who has LootRuler", function()
  G.SlashCmdList.LOOTRULER("versions")
  srv:tick(0.5)
  check("/lr versions: everyone in the group, and their version", visible("Who has LootRuler") and visible("in the group have LootRuler")
    and visible("no LootRuler") and visible(LR.VERSION))
  check("without it is fine: they whisper and /roll", visible("still reserve by whispering"))
  shot("versions")
  clickText("Ask again")
  srv:tick(3)
  check("asking again keeps it up to date", visible("Who has LootRuler"))
  LR.UI.closeAll()
  LR.UI.go("settings")
  clickText("Who has LootRuler")
  check("also on the Settings tab", visible("in the group have LootRuler"))
  LR.UI.closeAll()
end)

run("trade timers", function()
  check("off to start with", not LR.db.settings.tradeTimers)
  LR.db.settings.tradeTimers = true
  local ts = LR.startSession("Karazhan", 2, true, false)
  srv:tick(1)
  for _, id in ipairs({ 28762, 28767, 28745 }) do srv:lootTo(lead, id) end
  srv:tick(1)
  local function drop(id) for _, d in ipairs(ts.drops or {}) do if d.i == id then return d end end end
  check("the items in the loot master's bags are on the list", drop(28762) and drop(28767) and drop(28745))
  LR.Rolls.give(28767, LR.U.full("Ann"), "MS", { link = srv:link(28767), drop = drop(28767).k })
  srv:tick(1)
  LR.Rolls.dismiss()
  drop(28745).ht = LR.U.now() - (LR.Drops.TRADE_SECONDS - 12 * 60)
  drop(28767).ht = LR.U.now() - (LR.Drops.TRADE_SECONDS - 25 * 60)
  LR.UI.tradeTimers()
  local tw = G.LootRulerTimers
  local function onTimers(text) return #M.findText(text, true, tw) > 0 end
  local order = {}
  for _, c in ipairs(tw._children) do if c:IsShown() and c.x then order[#order + 1] = { c.x.d.i, select(5, c:GetPoint(1)) } end end
  table.sort(order, function(a, b) return a[2] > b[2] end)
  check("a bar for each, the soonest to run out first", tw:IsShown() and onTimers("To trade (3)") and onTimers("> Ann") and onTimers("12m")
    and #order == 3 and order[1][1] == 28745 and order[2][1] == 28767)
  check("with a button to post the list", tw.post and tw.post:IsShown())
  shot("trade-timers", lead, { "LootRulerTimers" })
  local row
  for _, c in ipairs(tw._children) do if c:IsShown() and c.x and c.x.d.i == 28762 then row = c end end
  M.click(row, "RightButton")
  srv:tick(0.3)
  check("right-click: give it without a roll", visible("Give [") or visible("Pick who gets it and how"))
  LR.UI.closeAll()
  LR.endSession(ts)
  srv:tick(1)
  check("it goes with the session", not tw:IsShown())
end)

run("saying trades nearby", function()
  local link = srv:link(28762)
  LR.UI.sayPrompt({ LR.TAG .. " Traded " .. link .. " to Ann.", LR.TAG .. " Bob traded me 250g." })
  local box = G.LootRulerSay
  local function onBox(text) return #M.findText(text, true, box) > 0 end
  check("the trades, and a button to say them", box:IsShown() and onBox("Say these 2 trades nearby?") and onBox("to Ann.")
    and onBox("Bob traded me 250g.") and onBox("Say it") and onBox("Not now"))
  check("without LootRuler's tag on screen", not onBox(LR.TAG))
  shot("say-trades", lead, { "LootRulerSay" })
  M.click(box.no)
  check("Not now: gone", not box:IsShown())
end)

run("a new player's first look", function()
  local neo = srv:client({ name = "Neo", class = "WARRIOR", newPlayer = true })
  srv:tick(7)
  check("a new player isn't told what's new (there's the tour)", not neo.M.chat[#neo.M.chat] or not neo.M.chat[#neo.M.chat]:find("updated to", 1, true))
  neo.G.SlashCmdList.LOOTRULER("")
  srv:tick(0.3)
  check("the first time the window opens: the tour", visible("Welcome to LootRuler", neo) and visible("1 of 5", neo))
  shot("tour", neo)
  for _ = 1, 4 do clickText("Next", nil, neo) end
  check("five short pages", visible("Make it yours", neo) and visible("5 of 5", neo))
  clickText("Done", nil, neo)
  neo.LR.UI.win:Hide()
  neo.G.SlashCmdList.LOOTRULER("")
  srv:tick(0.3)
  check("only the first time", not visible("Welcome to LootRuler", neo))
  neo.LR.UI.win:Hide()
  -- someone updating from an earlier version is told once what's new
  local old = srv:client({ name = "Olde", class = "MAGE" }, { settings = { rollSeconds = 30 }, sessions = {}, ui = {} })
  srv:tick(7)
  check("someone who updated hears once what's new", old.M.chat[#old.M.chat]:find("updated to " .. old.LR.VERSION, 1, true) ~= nil and old.LR.db.settings.rollSeconds == 30)
  old.G.SlashCmdList.LOOTRULER("whatsnew")
  check("and /lr whatsnew lists it", visible("What's new", old) and visible("Roll types of your own", old))
  shot("whats-new", old)
  old.LR.UI.closeAll()
  old.LR.UI.win:Hide()
end)

run("settings profiles", function()
  LR.UI.go("settings")
  srv:tick(6)
  clickText("Save these settings as...")
  local box
  local function walk(fr) for _, c in ipairs(fr._children) do if c._type == "EditBox" and c:IsVisible() then box = c end walk(c) end end
  walk(LR.UI.topSheet())
  box:SetText("Raiding") box._scripts.OnTextChanged(box, true)
  clickText("Save")
  check("saved under a name", LR.db.profiles.Raiding and LR.db.profiles.Raiding.rollSeconds == LR.db.settings.rollSeconds and visible("In use"))
  local was = LR.db.settings.rollSeconds
  LR.db.settings.rollSeconds = 45
  LR.saveProfile("Running loot")
  LR.useProfile("Raiding")
  check("switching puts those settings back", LR.db.settings.rollSeconds == was)
  LR.useProfile("Running loot")
  check("and the other way", LR.db.settings.rollSeconds == 45)
  LR.UI.render()
  srv:tick(0.3)
  do
    local function scrollers(fr, out) for _, c in ipairs(fr._children) do if c._type == "ScrollFrame" and c:IsVisible() then out[#out + 1] = c end scrollers(c, out) end return out end
    local sf = scrollers(G.LootRulerFrame, {})[1]
    local at = M.findText("Save these settings as...", true, G.LootRulerFrame)[1]
    if sf and at then sf:SetVerticalScroll(math.min(sf:GetVerticalScrollRange(), math.max(0, sf:GetVerticalScroll() + sf:GetTop() - at.fs:GetTop() - 300))) end
    shot("profiles")
    if sf then sf:SetVerticalScroll(0) end
  end
  LR.useProfile("Raiding")
  LR.deleteProfile("Raiding") LR.deleteProfile("Running loot")
  check("profiles can be deleted", next(LR.db.profiles) == nil)
end)

run("someone else's reserves don't take over", function()
  local mine = LR.startSession("Karazhan", 2, true, false)
  srv:tick(2)
  check("the raid leader's reserves show by themselves", ann.LR.current() and ann.LR.current().id == mine.id)
  ann.LR.UI.closeAll()
  local other = bob.LR.startSession("GruulsLair", 1, true, false)
  srv:tick(2)
  local sheet = ann.LR.UI.topSheet()
  check("a raider opens reserves too: Ann is asked, and still sees the leader's", sheet and ann.M.plain(sheet.title:GetText()) == "Join their reserves?"
    and visible("Bob-Faerlina is running LootRuler reserves for", ann) and ann.LR.current().id == mine.id)
  shot("join-reserves", ann)
  clickText("Not now", nil, ann)
  srv:tick(0.5)
  check("not now: she stays on the leader's", ann.LR.current().id == mine.id and ann.LR.session(other.id) ~= nil)
  bob.LR.endSession(other)
  LR.endSession(mine)
  srv:tick(2)
  ann.LR.UI.win:Hide()
end)

run("a raider forgets a session", function()
  local fs = LR.startSession("Karazhan", 2, true, false)
  srv:tick(2)
  check("Ann has the leader's session", ann.LR.session(fs.id) ~= nil)
  ann.LR.UI.show("session")
  srv:tick(0.3)
  clickText("Forget it", nil, ann)
  check("she's asked first", visible("Forget the session", ann))
  clickText("Forget", nil, ann)
  srv:tick(0.3)
  check("then it's gone from her addon, with no error", ann.LR.session(fs.id) == nil and (ann.LR.current() == nil or ann.LR.current().id ~= fs.id)
    and #ann.M.errors == 0, table.concat(ann.M.errors, " | "))
  check("and stays with its leader", LR.session(fs.id) ~= nil)
  check("the leader can't forget their own", not LR.forget(fs) and LR.session(fs.id) ~= nil)
  LR.publish(fs, true)
  srv:tick(3)
  check("it comes back when the leader sends it again", ann.LR.session(fs.id) ~= nil)
  ann.LR.UI.win:Hide()
  LR.endSession(fs)
  srv:tick(2)
  LR.UI.go("reserve")
end)

run("no button runs past its panel", function()
  -- every red button on every tab (and the Test tab's long rows) stays inside the frame it's laid out in
  local s4 = LR.startSession("Karazhan", 2, true, false)
  srv:tick(1)
  LR.db.settings.testTab = true
  local bad = {}
  local function walk(fr)
    for _, c in ipairs(fr._children or {}) do
      if c:IsVisible() then
        if c._kind == "button" then
          local r, pr = M.rect(c), M.rect(c:GetParent())
          if r and pr and (r.r > pr.r + 1 or r.l < pr.l - 1) then bad[#bad + 1] = M.plain(c:GetText() or "?") end
        end
        walk(c)
      end
    end
  end
  for _, t in ipairs({ "reserve", "reserves", "loot", "session", "guild", "settings", "test" }) do
    LR.UI.go(t)
    srv:tick(0.3)
    if t == "settings" then clickText("Open all") end
    walk(G.LootRulerFrame)
  end
  check("every button fits", #bad == 0, table.concat(bad, ", "))
  check("the Test tab's messages wrap onto two lines", (function()
    local a, b
    for _, x in ipairs(find("The 2 hours running out")) do if x.clickable then a = M.rect(x.clickable) end end
    for _, x in ipairs(find("A trade out of a group")) do if x.clickable then b = M.rect(x.clickable) end end
    return a and b and b.t < a.b
  end)())
  local function scrollers(fr, out) for _, c in ipairs(fr._children) do if c._type == "ScrollFrame" and c:IsVisible() then out[#out + 1] = c end scrollers(c, out) end return out end
  local sf = scrollers(G.LootRulerFrame, {})[1]
  sf:SetVerticalScroll(sf:GetVerticalScrollRange())
  shot("test-tab-buttons")
  sf:SetVerticalScroll(0)
  LR.endSession(s4)
  srv:tick(1)
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
