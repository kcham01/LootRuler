-- Whole raid nights played only through the window, as players would: every step a click on a screen (or, for players
-- without LootRuler, a whisper, a /roll or a line in raid chat), from opening reserves to ending the session. Run in
-- every theme (UI/Kit.lua, K.THEMES): a theme changes only the look, so every journey must work the same in each.
--   lua5.1 tests/journeys.lua
package.path = "./tests/?.lua;./tests/wow/?.lua;" .. package.path
local Server = require("server")

local failed, passed = 0, 0
local theme = "?"
local function check(name, ok, detail)
  if ok then passed = passed + 1 else failed = failed + 1 end
  print((ok and "ok   " or "FAIL ") .. "[" .. theme .. "] " .. name .. ((not ok and detail ~= nil) and ("  " .. tostring(detail)) or ""))
end
local function section(name) print("== [" .. theme .. "] " .. name) end

local DATA = {}
do
  local chunk = assert(loadfile("LootRuler/Data/Loot.lua"))
  setfenv(chunk, setmetatable({}, { __index = _G }))
  chunk("LootRuler", DATA)
end
local WATCH, SIGNET, HANDWRAPS = 28528, 28525, 28507

local function journeys(themeKey)
  theme = themeKey
  local srv = Server.new(".")
  srv.where = Server.PLACES.Karazhan
  srv.itemInfo = function(id)
    local it = DATA.ITEMS[id]
    if not it then return nil end
    return { name = it[1], quality = it[2], link = ("|cffa335ee|Hitem:%d::::::::70:::::|h[%s]|h|r"):format(id, it[1]) }
  end
  local function saved() return { settings = { theme = themeKey } } end
  local lead = srv:client({ name = "Lead", class = "PALADIN" }, saved())
  local ann = srv:client({ name = "Ann", class = "PRIEST" }, saved())
  local bob = srv:client({ name = "Bob", class = "MAGE", realm = "Faerlina" }, saved())
  local pug = srv:player({ name = "Pug", class = "WARRIOR" })
  srv:setGroup({ lead, ann, bob, pug }, lead, true)
  srv:setMasterLooter(lead)
  srv:tick(6)
  check("every player's LootRuler is in the theme", lead.LR.K.T.key == themeKey and ann.LR.K.T.key == themeKey)

  local function full(p) return Server.full(p) end
  local function root(p) return p.LR.UI.topSheet() or p.G.LootRulerFrame end
  local function find(p, text, where) return p.M.findText(text, true, where or root(p)) end
  local function visible(p, text, where) return #find(p, text, where) > 0 end
  -- clicks the button (or row) with exactly these words, else the first that has them
  local function click(p, text, where)
    local exact, any
    for _, x in ipairs(find(p, text, where)) do
      if x.clickable and x.clickable:IsVisible() then
        any = any or x.clickable
        if p.M.plain(x.fs:GetText()) == text then exact = exact or x.clickable end
      end
    end
    local b = exact or any
    if not b then error("[" .. theme .. "] nothing to click: " .. text, 2) end
    p.M.click(b)
    srv:tick(0.3)
    return b
  end
  local function rowFor(p, name)
    for _, x in ipairs(find(p, name)) do if x.frame._kind == "item" then return x.frame end end
  end
  local function frameFor(p, id)
    local frames = p.LR.UI.rollFrames()
    for i = #frames, 1, -1 do local f = frames[i] if f:IsShown() and f.copy and f.copy.id == id then return f end end
  end
  local function chat(text, channel)
    for i = #srv.chat, 1, -1 do
      local m = srv.chat[i]
      if m.text:find(text, 1, true) and (not channel or m.channel == channel) then return m end
    end
  end
  local function archived(p, id) for _, h in ipairs(p.LR.db.history or {}) do if h.id == id then return true end end return false end
  local function whisperTo(p, text) for i = #p.inbox, 1, -1 do if p.inbox[i].text:find(text, 1, true) then return p.inbox[i] end end end
  local function paste(p, text)
    local box
    local function walk(f) for _, c in ipairs(f._children) do if c._type == "EditBox" and c:IsVisible() and c._multi and not box then box = c end walk(c) end end
    walk(root(p))
    box:SetText(text) box._scripts.OnTextChanged(box, true)
    srv:tick(0.5)
  end
  local function endSession(p)
    p.LR.UI.go("session")
    srv:tick(0.3)
    click(p, "End session")
    check("ending asks first, yes or no", visible(p, "Yes") and visible(p, "No"))
    click(p, "Yes")
    srv:tick(2)
  end
  local site = lead.LR.Gargul.encode({ metadata = { id = "j1" }, hardreserves = {}, softreserves = {
    { name = "Ann", class = "priest", items = { { id = WATCH } } },
    { name = "Bob", class = "mage", items = { { id = SIGNET } } } } })

  ------------------------------------------------------------------------------------------------ a soft reserve night
  section("a soft reserve night, start to end")
  lead.LR.UI.show("session")
  srv:tick(0.3)
  check("no session yet: the form to open one, the raid picked", visible(lead, "Open reserves") and visible(lead, "Karazhan") and visible(lead, "you're in it"))
  click(lead, "Open reserves")
  srv:tick(2)
  local s = lead.LR.current()
  check("the leader opens reserves from the form", s and lead.LR.isLeader(s) and s.raid == "Karazhan")
  check("raiders' LootRuler has it", ann.LR.current() and ann.LR.current().id == s.id and bob.LR.current() and bob.LR.current().id == s.id)
  click(lead, "Tell the raid how to reserve")
  check("the raid is told how to reserve", chat("!reserve", "RAID") ~= nil)

  ann.LR.UI.show("reserve")
  srv:tick(0.3)
  click(ann, "Open all")
  local row = rowFor(ann, "Moroes' Lucky Pocket Watch")
  check("Ann sees the loot list, with a Reserve button on each item", row and row.act:IsShown())
  ann.M.click(row.act)
  srv:tick(2)
  check("Ann reserves with a click: the leader has it", lead.LR.Session.reservesOf(s, full(ann))[1] == WATCH)
  bob.LR.UI.show("reserve")
  srv:tick(0.3)
  click(bob, "Open all")
  bob.M.click(rowFor(bob, "Signet of Unshakable Faith").act)
  srv:tick(2)
  check("Bob too", lead.LR.Session.reservesOf(s, full(bob))[1] == SIGNET)
  srv:whisper(pug, lead, "!reserve " .. srv:link(WATCH))
  srv:tick(1)
  check("Pug, without the addon, reserves by whisper", lead.LR.Session.reservesOf(s, full(pug))[1] == WATCH and whisperTo(pug, "Moroes' Lucky Pocket Watch") ~= nil)
  ann.M.click(rowFor(ann, "Moroes' Lucky Pocket Watch").x:IsShown() and rowFor(ann, "Moroes' Lucky Pocket Watch").x or rowFor(ann, "Moroes' Lucky Pocket Watch").act)

  lead.LR.UI.go("reserves")
  srv:tick(0.3)
  check("the Reserved tab says how it stands", visible(lead, "in the group reserved"))
  click(lead, "Lock reserves")
  srv:tick(1)
  check("the leader locks them from the bar under the list", s.locked and ann.LR.current().locked)

  srv:openLoot(lead, { { WATCH, 4 }, { SIGNET, 4 } })
  srv:tick(0.5)
  local panel = lead.G.LootRulerLootPanel
  check("the loot panel opens with the corpse's loot", panel and panel:IsShown())
  click(lead, "Moroes' Lucky Pocket Watch", panel)
  srv:tick(0.5)
  local roll = lead.LR.Rolls.mine()
  check("a click rolls it out to its reservers", roll and roll.id == WATCH and roll.mode == "SR")
  srv:willRoll(ann, 90)
  local fa = frameFor(ann, WATCH)
  check("Ann's roll window pops up", fa ~= nil and fa.dice:IsEnabled())
  ann.M.click(fa.dice)
  srv:roll(pug, 1, 100, 40)
  srv:tick(25)
  check("the roll closes", roll.state == "closed")
  click(lead, "Give to Ann", lead.G.LootRulerMasterFrame)
  srv:tick(1)
  check("the loot master gives it out with a click", srv.given and srv.given[#srv.given].id == WATCH and srv.given[#srv.given].to == ann)
  check("and the raid hears who won", chat("Ann has won") ~= nil)
  srv:tick(9)
  click(lead, "Close", lead.G.LootRulerMasterFrame)
  click(lead, "Signet of Unshakable Faith", panel)
  srv:tick(0.5)
  srv:willRoll(bob, 70)
  bob.M.click(frameFor(bob, SIGNET).dice)
  srv:tick(25)
  click(lead, "Give to Bob", lead.G.LootRulerMasterFrame)
  srv:tick(1)
  check("Bob's reserve too", srv.given[#srv.given].id == SIGNET and srv.given[#srv.given].to == bob)
  srv:tick(9)
  click(lead, "Close", lead.G.LootRulerMasterFrame)
  srv:closeLoot(lead)
  lead.LR.UI.go("loot")
  srv:tick(0.3)
  check("the Loot tab lists who won what", visible(lead, "Won by Ann") and visible(lead, "Won by Bob"))
  ann.LR.UI.go("loot")
  srv:tick(0.3)
  check("raiders see the same", visible(ann, "Won by Ann") and visible(ann, "Won by Bob"))
  endSession(lead)
  check("the session ends everywhere, and is kept under past raids", lead.LR.current() == nil and ann.LR.current() == nil
    and archived(lead, s.id))

  ------------------------------------------------------------------------------------------------ softres.it
  section("a raid that reserved on softres.it")
  lead.LR.UI.go("session")
  srv:tick(0.3)
  click(lead, "Import from softres.it")
  srv:tick(1)
  s = lead.LR.current()
  check("one click opens reserves and the import box", s and visible(lead, "Bring in reserves from softres.it"))
  paste(lead, site)
  check("what the sheet brings is shown first", visible(lead, "2 players, 2 reserves"))
  click(lead, "Bring them in")
  srv:tick(2)
  check("the sheet's reserves are in, for raiders too", lead.LR.Session.reservesOf(s, full(ann))[1] == WATCH
    and ann.LR.Session.reservesOf(ann.LR.current(), full(bob))[1] == SIGNET)
  lead.LR.UI.closeAll()
  lead.LR.UI.go("session")
  srv:tick(0.3)
  check("the link to post comes with it", visible(lead, "Post the link in raid chat"))
  click(lead, "Post the link in raid chat")
  check("posted", chat("softres.it/raid/j1", "RAID") ~= nil)

  ------------------------------------------------------------------------------------------------ handing over
  section("handing the reserves over")
  click(lead, "Hand over the reserves")
  check("it asks who", visible(lead, "Who runs the reserves now?") and visible(lead, "Ann"))
  click(lead, "Ann")
  srv:tick(3)
  check("Ann's LootRuler takes them over", ann.LR.isLeader(ann.LR.current()) and lead.LR.current().leader == full(ann))
  ann.LR.UI.show("session")
  srv:tick(0.3)
  check("Ann gets the leader's Session tab", visible(ann, "Hand over the reserves") and visible(ann, "End session"))
  endSession(ann)
  check("she can end it", ann.LR.current() == nil and lead.LR.current() == nil)
  ann.LR.UI.win:Hide()

  ------------------------------------------------------------------------------------------------ GDKP
  section("a GDKP night")
  lead.LR.UI.go("session")
  srv:tick(0.3)
  click(lead, "Open reserves")
  srv:tick(1)
  s = lead.LR.current()
  click(lead, "GDKP auction")
  srv:tick(1)
  check("one click makes it a GDKP", s.gdkp and ann.LR.current().gdkp)
  srv:openLoot(lead, { { WATCH, 4 }, { SIGNET, 4 } })
  srv:tick(0.5)
  panel = lead.G.LootRulerLootPanel
  click(lead, "Auction them all", panel)
  srv:tick(0.5)
  roll = lead.LR.Rolls.mine()
  check("the auction starts from the loot panel", roll and roll.mode == "BID" and roll.state == "open")
  fa = frameFor(ann, WATCH)
  check("Ann's auction window, with one button to bid", fa and fa.bid:IsShown() and fa.bid:IsEnabled())
  ann.M.click(fa.bid)
  srv:tick(0.5)
  check("her click bids", roll.top and roll.top.p == full(ann))
  srv:chatMessage(pug, "500", "RAID")
  srv:tick(0.5)
  check("Pug bids in raid chat", roll.top.p == full(pug) and roll.top.n == 500)
  srv:tick(40)
  check("sold to the highest bid, and given out", roll.state == "awarded" and roll.winner == full(pug) and srv.given[#srv.given].to == pug)
  roll = lead.LR.Rolls.mine()
  check("the next one comes up by itself", roll and roll.id == SIGNET and roll.state == "open")
  bob.M.click(frameFor(bob, SIGNET).bid)
  srv:tick(40)
  check("Bob buys it with one click", roll.state == "awarded" and roll.winner == full(bob))
  srv:closeLoot(lead)
  lead.LR.UI.go("session")
  srv:tick(0.3)
  check("the Session tab shows the pot", visible(lead, "500g"))
  click(lead, "End session")
  check("gold still owed: it says so before ending", visible(lead, "Gold is still owed"))
  click(lead, "End it")
  srv:tick(2)
  check("ended anyway, kept under past raids to finish the payouts", lead.LR.current() == nil and archived(lead, s.id))

  ------------------------------------------------------------------------------------------------ a private session
  section("a private session (the loot master doesn't use LootRuler)")
  bob.LR.UI.show("session")
  srv:tick(0.3)
  click(bob, "Private session")
  srv:tick(0.5)
  local pv = bob.LR.privateSession()
  check("Bob opens a private session from the form", pv ~= nil and visible(bob, "Only on your screen"))
  click(bob, "Import from softres.it")
  paste(bob, site)
  click(bob, "Bring them in")
  srv:tick(1)
  check("he brings the sheet in, only for himself", bob.LR.Session.reservesOf(pv, full(ann))[1] == WATCH and lead.LR.session(pv.id) == nil)
  bob.LR.UI.closeAll()
  endSession(bob)
  check("and ends it: it's forgotten", bob.LR.privateSession() == nil)

  ------------------------------------------------------------------------------------------------ the practice raid
  section("trying it all on your own: the practice raid")
  srv:setGroup({ lead, ann, pug }, lead, true)
  bob.inGroup = false
  srv:rosterChanged()
  srv:tick(2)
  bob.LR.UI.go("settings")
  srv:tick(0.3)
  click(bob, "Testing")
  click(bob, "Show the Test tab")
  check("the Test tab is switched on in Settings", bob.LR.db.settings.testTab == true)
  click(bob, "Test")
  click(bob, "Start the practice raid")
  srv:tick(1)
  local ps = bob.LR.current()
  check("a practice raid starts, with pretend players", ps and ps.practice and #bob.LR.Practice.players > 0)
  click(bob, "They reserve")
  srv:tick(12)
  local P = bob.LR.Practice
  check("before reserves are locked, nobody can ask to swap", not find(bob, "A raider asks to swap")[1].clickable:IsEnabled()
    and visible(bob, "A swap is asked for once the reserves are locked"))
  bob.LR.UI.go("reserves")
  srv:tick(0.3)
  click(bob, "Lock reserves")
  srv:tick(3)
  bob.LR.UI.go("test")
  srv:tick(0.3)
  click(bob, "A raider asks to swap")
  srv:tick(2)
  local asks = bob.LR.Swap.pending(ps)
  check("a raider asks to swap a reserve, on purpose", #asks >= 1)
  bob.LR.UI.go("reserves")
  srv:tick(0.3)
  check("the Reserved tab lists the swap requests", visible(bob, "Swap requests") and visible(bob, "Allow"))
  local who, to = asks[1].p, asks[1].to
  click(bob, "Allow")
  srv:tick(1)
  check("allowing one swaps their reserve", bob.LR.U.indexOf(bob.LR.Session.reservesOf(ps, who), to) ~= nil)
  bob.LR.UI.go("test")
  srv:tick(0.3)
  click(bob, "A raider leaves")
  local gone = P.gone[#P.gone]
  check("a raider leaves the group, keeping their reserves", gone and not bob.LR.inGroup(gone.name) and #bob.LR.Session.reservesOf(ps, gone.name) > 0)
  check("and can be brought back", visible(bob, "Bring " .. bob.LR.U.short(gone.name) .. " back"))
  bob.LR.UI.go("reserves")
  srv:tick(0.3)
  check("the Reserved tab says they've left, with the button to clear them", visible(bob, "has reserves but isn't in the group") and visible(bob, "Clear their reserves"))
  click(bob, "Clear their reserves")
  click(bob, "Clear 1")
  srv:tick(1)
  check("clearing takes their reserves off", #bob.LR.Session.reservesOf(ps, gone.name) == 0 and not visible(bob, "isn't in the group"))
  bob.LR.UI.go("test")
  srv:tick(0.3)
  click(bob, "Bring " .. bob.LR.U.short(gone.name) .. " back")
  check("they're back in the group", bob.LR.inGroup(gone.name) and #P.gone == 0)
  bob.LR.UI.go("reserves")
  srv:tick(0.3)
  click(bob, "Unlock reserves")
  srv:tick(1)
  bob.LR.UI.go("test")
  srv:tick(0.3)
  click(bob, "A boss drops loot")
  srv:tick(0.5)
  check("they reserve, and a boss drops loot", #ps.drops > 0 and #bob.LR.Session.players(ps) > 0)
  click(bob, "Roll out the next item")
  srv:tick(25)
  local pr = bob.LR.Rolls.mine()
  check("the next item is rolled out, and the pretend players roll", pr and next(pr.rolled) ~= nil and pr.state == "closed")
  bob.LR.Rolls.dismiss()
  bob.LR.UI.show("test")
  srv:tick(0.3)
  click(bob, "End the practice raid")
  srv:tick(0.5)
  check("and ends it: nothing is kept", not bob.LR.Practice.on and bob.LR.current() == nil)

  for _, p in ipairs({ lead, ann, bob }) do
    check(p.name .. ": no Lua errors", #p.M.errors == 0, table.concat(p.M.errors, " | "))
  end
end

for _, key in ipairs({ "classic", "elvui" }) do journeys(key) end
print(("passed %d"):format(passed))
print(("errors %d"):format(failed))
os.exit(failed == 0 and 0 or 1)
