-- Throws random and broken input at LootRuler's rules, in the test stand-in (tests/wow/server.lua), and checks that
-- nothing errors and that what the rules promise always holds:
--   1. the session's rules:   thousands of random changes (reserves, hard reserves, extras, locking, awards, drops,
--                             GDKP, settings), sensible and nonsense. After each: no error, the session is valid, nobody
--                             is over their limit, no doubles unless allowed, nothing soft reserved that's hard reserved,
--                             and the changes sent (S.diff / S.patch) and the whole copy sent rebuild it exactly.
--   2. rolls:                 random rolls, passes, bids and max bids; the result is always the best that counts.
--   3. the GDKP split:        random pots, cuts, bonuses, roles, rules and payouts set by hand: nobody gets less than
--                             nothing, and no more is paid out than the pot (plus gold put in).
--   4. text in:               every parser LootRuler has (softres.it and Gargul exports, spreadsheets, priority lists,
--                             wishlists, "Name,Number" lists, prices, sign-up lists, item notes, bids) with random and
--                             broken text. No errors; raid chat lines never over 255 characters.
--   5. the guild book:        random changes and copies merged in any order end up the same.
--   lua5.1 tools/fuzz.lua [rounds]     build/fuzz.txt
-- Not part of CI. A line starting "PROBLEM" is something to fix.
package.path = "./tests/?.lua;./tests/wow/?.lua;" .. package.path
local Server = require("server")

local ROUNDS = tonumber(arg and arg[1]) or 300
math.randomseed(20261028)
os.execute("mkdir -p build")

local lines, problems = {}, {}
local function say(fmt, ...)
  local t = select("#", ...) > 0 and fmt:format(...) or fmt
  lines[#lines + 1] = t
  io.stderr:write(t, "\n")
end
local seenProblem = {}
local function problem(fmt, ...)
  local t = fmt:format(...)
  local key = t:sub(1, 120)
  if seenProblem[key] then seenProblem[key] = seenProblem[key] + 1 return end
  seenProblem[key] = 1
  problems[#problems + 1] = t
  say("PROBLEM: " .. t)
end
local function section(name) say("") say("== " .. name) end

---------------------------------------------------------------------- the stand-in, with the loot data
local DATA = {}
do
  local chunk = assert(loadfile("LootRuler/Data/Loot.lua"))
  setfenv(chunk, setmetatable({}, { __index = _G }))
  chunk("LootRuler", DATA)
end
local srv = Server.new(".")
srv.where = Server.PLACES.Karazhan
srv.itemInfo = function(id)
  local it = DATA.ITEMS and DATA.ITEMS[id]
  if not it then return nil end
  return { name = it[1], quality = it[2], link = ("|cffa335ee|Hitem:%d::::::::70:::::|h[%s]|h|r"):format(id, it[1]) }
end
local lead = srv:client({ name = "Lead", class = "PALADIN", guild = "Kings", rank = 0 })
srv:tick(6)
local LR = lead.LR
local S, R, U, G, B = LR.Session, LR.Roll, LR.U, LR.Gdkp, LR.Book

local KARA = {}
for _, r in ipairs(LR.RAIDS) do
  if r.key == "Karazhan" then
    for _, b in ipairs(r.bosses) do for _, id in ipairs(b.items) do KARA[#KARA + 1] = id end end
  end
end
local OTHER = { 28830, 30480, 19866, 32385, 1, 999999, 0, -5 }      -- (another raid's, a mount, nonsense)
local PLAYERS = { "Ann-Dreamscythe", "Bob-Faerlina", "Cid-Dreamscythe", "Dan-Dreamscythe", "Øyvind-Dreamscythe",
  "Lead-Dreamscythe", "ann-dreamscythe", "Eve", "Zed-Gehennas" }

---------------------------------------------------------------------- random values
local function pick(list) return list[math.random(#list)] end
local function keysOf(t) local out = {} for k in pairs(t) do out[#out + 1] = k end table.sort(out, function(a, b) return tostring(a) < tostring(b) end) return out end
local function chance(p) return math.random() < p end
local JUNK_STRINGS = { "", " ", "|", "||", "%", "%s%d", "\0", "|Hitem:28528::::::::70:::::|h[x]|h|r", ("x"):rep(300),
  ("é"):rep(50), "nil", "-", "Ann-", "-Realm", "\n\n", "1e309", "0x10", "  Ann  " }
local junk
junk = function(depth)
  depth = depth or 0
  local r = math.random(12)
  if r == 1 then return nil
  elseif r == 2 then return chance(0.5)
  elseif r == 3 then return pick({ 0, -1, 1, 2.5, 1e308, -1e308, math.huge, -math.huge, 2 ^ 53, 300, 1000 })
  elseif r == 4 then return 0 / 0
  elseif r <= 7 then return pick(JUNK_STRINGS)
  elseif r <= 9 then return pick(PLAYERS)
  elseif depth < 3 then
    local t = {}
    for i = 1, math.random(0, 5) do
      if chance(0.5) then t[i] = junk(depth + 1) else local k = junk(depth + 1) if k ~= nil and k == k then t[k] = junk(depth + 1) end end
    end
    return t
  end
  return pick(KARA)
end
local ODD_NUMBERS = { 0, -1, 2.5, 1e308, -1e308, math.huge, 2 ^ 53, 1000, 7 }
local ODD_NAMES = { "", " ", "Ann-", "-Realm", ("x"):rep(300), "  Ann  ", "|cffff0000Ann|r", "Ann-Dreamscythe-Extra", "%s", "Øyvind" }
local function item(p) if chance(p or 0.85) then return pick(KARA) end if chance(0.6) then return pick(OTHER) end return pick(ODD_NUMBERS) end
local function player(p) if chance(p or 0.9) then return pick(PLAYERS) end return pick(ODD_NAMES) end
local function count(p) if chance(p or 0.85) then return math.random(0, 6) end return pick(ODD_NUMBERS) end
local function str(p) if chance(p or 0.8) then return pick({ "GM", "Raid leader", "repairs", "Join us" }) end return pick(ODD_NAMES) end
local function items(n)
  local t = {}
  for i = 1, n or math.random(0, 6) do t[i] = item() end
  return t
end

---------------------------------------------------------------------- checks
local NOW = 1800000000
local function call(what, fn, ...)
  local ok, a, b, c = pcall(fn, ...)
  if not ok then problem("%s threw: %s", what, tostring(a)) return nil, "threw" end
  return a, b, c
end
local function copy(t) return U.copy(t) end
local LibSerialize = lead.G.LibStub("LibSerialize")

--- what the session's rules promise, after every change
local roundBroken = false
local function where(a, b, path)
  path = path or "s"
  if a == b then return nil end
  if type(a) ~= "table" or type(b) ~= "table" then return path .. ": " .. tostring(a) .. " / " .. tostring(b) end
  for k, v in pairs(a) do local w = where(v, b[k], path .. "." .. tostring(k)) if w then return w end end
  for k, v in pairs(b) do if a[k] == nil then return path .. "." .. tostring(k) .. ": nil / " .. tostring(v) end end
end
local function promises(s, what)
  local vok, vwhy = pcall(S.valid, copy(s))
  if not vok or not vwhy then problem("the leader's own session isn't valid after %s", what) roundBroken = true return end
  for p, r in pairs(s.res or {}) do
    local list = r.i or {}
    if #list > S.limit(s, p) then problem("%s has %d reserves, over their limit of %d (after %s)", tostring(p), #list, S.limit(s, p), what) end
    if not s.dupes then
      local seen = {}
      for _, id in ipairs(list) do
        if seen[id] then problem("%s has %s twice with doubles off (after %s)", tostring(p), tostring(id), what) end
        seen[id] = true
      end
    end
    for _, id in ipairs(list) do
      if s.hr[id] then problem("%s soft reserved %s, which is hard reserved (after %s)", tostring(p), tostring(id), what) end
      if type(id) ~= "number" then problem("a reserve that isn't an item number: %s (after %s)", tostring(id), what) end
    end
    if #list == 0 then problem("%s is listed with no reserves (after %s)", tostring(p), what) end
  end
  -- byItem agrees with each player's list
  local by = call("S.byItem", S.byItem, s) or {}
  local n1, n2 = 0, 0
  for _, r in pairs(s.res or {}) do n1 = n1 + #(r.i or {}) end
  for _, who in pairs(by) do for _, w in ipairs(who) do n2 = n2 + (type(w) == "table" and (w[2] or 1) or 1) end end
  if n1 ~= n2 then problem("S.byItem counts %d reserves, the lists have %d (after %s)", n2, n1, what) end
  -- the whole copy, over the wire
  local wire = LibSerialize:Serialize({ t = "T", s = s })
  local okd, back = LibSerialize:Deserialize(wire)
  if not okd or not S.same(back.s, s) then problem("the session doesn't come back the same over the wire (after %s): %s", what, tostring(okd and where(s, back.s))) roundBroken = true end
end

local function diffPatch(prev, s, what)
  local ch = call("S.diff", S.diff, prev, s)
  if ch == nil then
    if not S.same(prev, s) then problem("S.diff says nothing changed, but it did (after %s)", what) end
    return
  end
  local wire = LibSerialize:Serialize(ch)
  local _, ch2 = LibSerialize:Deserialize(wire)
  local patched = call("S.patch", S.patch, copy(prev), ch2)
  if not patched or not S.same(patched, s) then problem("the changes sent don't rebuild the session (after %s): %s", what, tostring(patched and where(s, patched))) roundBroken = true end
end

---------------------------------------------------------------------- 1. the session's rules
section("1. the session's rules: random changes")
local OPS
OPS = {
  { "set", function(s) return S.set(s, player(), pick({ "MAGE", "PRIEST", nil, "NOTACLASS" }), items(), chance(0.3), NOW) end },
  { "add", function(s) return S.add(s, player(), pick({ "MAGE", nil }), item(), chance(0.3), NOW) end },
  { "remove", function(s) return S.remove(s, player(), item(), chance(0.3), NOW) end },
  { "setHR", function(s) return S.setHR(s, item(), player(), str(), NOW) end },
  { "clearHR", function(s) return S.clearHR(s, item(), NOW) end },
  { "setExtra", function(s) return S.setExtra(s, player(), count(), NOW) end },
  { "configure", function(s) return S.configure(s, count(), chance(0.5), NOW) end },
  { "setAny", function(s) return S.setAny(s, chance(0.5), NOW) end },
  { "setLocked", function(s) return S.setLocked(s, chance(0.5), NOW) end },
  { "setGroupOnly", function(s) return S.setGroupOnly(s, chance(0.5), NOW) end },
  { "addDrop", function(s)
    local d = chance(0.85) and { k = "d" .. math.random(1, 40), i = item(), b = "Moroes", by = player(), h = chance(0.5) and player() or nil,
      n = chance(0.2) and pick(ODD_NUMBERS) or nil, at = NOW } or { k = 5 }
    return S.addDrop(s, d, NOW)
  end },
  { "removeDrop", function(s) return S.removeDrop(s, "d" .. math.random(1, 40), NOW) end },
  { "award", function(s)
    return S.award(s, item(), player(), pick({ "SR", "MS", "OS", "HR", "BID", "X1" }), chance(0.8) and math.random(1, 100) or pick(ODD_NUMBERS),
      NOW, chance(0.5) and ("d" .. math.random(1, 40)) or nil, chance(0.1), chance(0.1), chance(0.1) and "Transmog" or nil)
  end },
  { "unaward", function(s) return S.unaward(s, chance(0.9) and math.random(0, #(s.won or {}) + 1) or pick(ODD_NUMBERS), NOW) end },
  { "editAward", function(s) return S.editAward(s, chance(0.9) and math.random(0, #(s.won or {}) + 1) or pick(ODD_NUMBERS), player(), pick({ "SR", "MS", "OS", "DE", "HR", "x" }), NOW) end },
  { "setLink", function(s) return S.setLink(s, chance(0.5) and ("https://softres.it/raid/" .. math.random(1000)) or pick(ODD_NAMES), NOW) end },
  { "setBrand", function(s) return S.setBrand(s, { n = str(), m = str(), i = chance(0.8) and math.random(0, 20) or pick(ODD_NUMBERS) }, NOW) end },
  { "setBench", function(s) return S.setBench(s, { player(), player() }, NOW) end },
  { "setOneWin", function(s) return S.setOneWin(s, chance(0.5), NOW) end },
  { "setDisenchanter", function(s) return S.setDisenchanter(s, player(), NOW) end },
  { "setPlusOne", function(s) return S.setPlusOne(s, chance(0.5), NOW) end },
  { "setPrio", function(s) return S.setPrio(s, pick({ nil, "both", "only", "x", 5 }), NOW) end },
  { "setBoost", function(s) return S.setBoost(s, chance(0.5), NOW) end },
  { "adjustPlusOne", function(s) return S.adjustPlusOne(s, player(), chance(0.8) and pick({ 1, -1, 2 }) or pick(ODD_NUMBERS), NOW) end },
  { "setPlusOnes", function(s) return S.setPlusOnes(s, player(), count(), NOW) end },
  { "setAutoLock", function(s) return S.setAutoLock(s, chance(0.7) and (NOW + math.random(-100, 4000)) or pick(ODD_NUMBERS), NOW) end },
  { "saw", function(s) return S.saw(s, { player(), player(), player() }, NOW) end },
  { "handTo", function(s) return S.handTo(s, chance(0.8) and player() or nil, NOW) end },
  { "clearAbsent", function(s) return S.clearAbsent(s, function(p) return p ~= "Bob-Faerlina" end, NOW) end },
  { "gdkp", function(s) return G.set(s, chance(0.5), NOW) end },
  { "gdkpOption", function(s) return G.option(s, pick({ "min", "inc", "cut", "strict", "x" }), chance(0.8) and math.random(0, 500) or pick(ODD_NUMBERS), NOW) end },
  { "gdkpBonus", function(s) return G.setBonus(s, player(), chance(0.8) and math.random(0, 500) or pick(ODD_NUMBERS), NOW) end },
  { "gdkpPaid", function(s) return G.paid(s, player(), chance(0.8) and math.random(-500, 5000) or pick(ODD_NUMBERS), NOW, pick({ "trade", "mail", "hand", nil })) end },
  { "gdkpRole", function(s) return G.setRole(s, player(), pick({ "tank", "healer", nil, "x" }), NOW) end },
  { "gdkpRoleCut", function(s) return G.setRoleCut(s, pick({ "tank", "healer", "x" }), chance(0.8) and math.random(0, 60) or pick(ODD_NUMBERS), NOW) end },
  { "gdkpAddGold", function(s) return G.addGold(s, chance(0.8) and math.random(-2000, 2000) or pick(ODD_NUMBERS), str(), NOW) end },
  { "gdkpFixed", function(s) return G.setFixed(s, player(), chance(0.8) and math.random(0, 3000) or pick(ODD_NUMBERS), NOW) end },
  { "gdkpRule", function(s)
    local r = math.random(4)
    if r == 1 then return G.addRule(s, str(), NOW)
    elseif r == 2 then return G.editRule(s, math.random(0, 4), { pct = chance(0.8) and math.random(0, 50) or pick(ODD_NUMBERS), g = chance(0.8) and math.random(0, 500) or pick(ODD_NUMBERS), n = str() }, NOW)
    elseif r == 3 then return G.ruleTo(s, math.random(0, 4), player(), chance(0.5), NOW)
    else return G.removeRule(s, math.random(0, 4), NOW) end
  end },
  { "gdkpOut", function(s) return G.setOut(s, player(), chance(0.5), NOW) end },
  { "gdkpNoBids", function(s) return G.setNoBids(s, player(), chance(0.5), NOW) end },
  { "gdkpPrice", function(s) return G.setPrice(s, item(), chance(0.8) and math.random(0, 9999) or pick(ODD_NUMBERS), NOW) end },
  { "gdkpSaw", function(s) return G.saw(s, { player(), player() }, NOW) end },
}

local function newSession(seed)
  local raid = chance(0.85) and "Karazhan" or LR.CUSTOM
  local s = S.new("Lead-Dreamscythe", raid, math.random(1, 4), chance(0.5), NOW + seed, raid == LR.CUSTOM and "Our raid" or nil, chance(0.2))
  return s
end

local opsRun = 0
for round = 1, ROUNDS do
  local s = newSession(round)
  roundBroken = false
  local trail = {}
  for step = 1, 60 do
    local op = pick(OPS)
    local prev = copy(s)
    NOW = NOW + 1
    trail[#trail + 1] = op[1]
    call("S." .. op[1], op[2], s)
    opsRun = opsRun + 1
    promises(s, op[1])
    diffPatch(prev, s, op[1])
    if roundBroken then say("   (round %d, after: %s)", round, table.concat(trail, " ", math.max(1, #trail - 5))) break end
  end
end
say("%d random changes on %d sessions", opsRun, ROUNDS)

---------------------------------------------------------------------- 1b. sessions that pass S.valid must work everywhere
section("1b. what S.valid lets through works everywhere")
do
  local okCount = 0
  for round = 1, ROUNDS * 4 do
    local s = newSession(round)
    for _ = 1, 20 do call("op", pick(OPS)[2], s) end
    -- break one part of it
    local t = copy(s)
    local keys = keysOf(t)
    for _ = 1, math.random(1, 3) do
      local k = pick(keys)
      if chance(0.5) then t[k] = junk()
      elseif type(t[k]) == "table" then
        local sub = keysOf(t[k])
        local key = junk()
        if #sub > 0 then t[k][pick(sub)] = junk() elseif key ~= nil and key == key then t[k][key] = junk() end
      end
    end
    local good = call("S.valid", S.valid, t)
    if good then
      okCount = okCount + 1
      local v = type(good) == "table" and good or t
      call("S.byItem", S.byItem, v)
      call("S.players", S.players, v)
      for _, p in ipairs(PLAYERS) do call("S.claims", S.claims, v, p, pick(KARA)) call("S.limit", S.limit, v, p) end
      call("S.openDrops", S.openDrops, v, pick(KARA))
      for _, d in ipairs(type(v.drops) == "table" and v.drops or {}) do call("S.dropState", S.dropState, v, d) end
      call("R.plan", R.plan, v, pick(KARA), LR.roster())
      call("Export.text", LR.Export.text, v, pick({ "csv", "tmb", "dft", "own" }))
      call("Gargul.data", LR.Gargul.data, v)
      if v.gk then call("Gdkp.split", G.split, v) call("Gdkp.ledger", G.ledger, v) call("Gdkp.payoutsText", G.payoutsText, v) end
    end
  end
  say("%d broken sessions that S.valid let through, used every way", okCount)
end

---------------------------------------------------------------------- 1c. broken copies sent by the leader, on a raider's screens
section("1c. broken sessions from the leader, drawn on a raider's screen")
do
  local ann = srv:client({ name = "Ann", class = "PRIEST" })
  srv:setGroup({ lead, ann }, lead, true)
  srv:setMasterLooter(lead)
  srv:tick(3)
  local LibDeflate = lead.G.LibStub("LibDeflate")
  local function send(msg)
    local text = LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(LibSerialize:Serialize(msg)))
    local pos = 1
    if #text <= 255 then srv:addonMessage(lead, "LootRuler", text, "RAID") return end
    while pos <= #text do
      local chunk = text:sub(pos, pos + 253)
      srv:addonMessage(lead, "LootRuler", (pos == 1 and "\001" or (pos + 254 > #text and "\003" or "\002")) .. chunk, "RAID")
      pos = pos + 254
    end
  end
  local tabs = { "reserve", "reserves", "loot", "session", "guild", "settings" }
  local base
  local function sheets()
    -- the Loot tab's other page, and the GDKP sheets, on the raider's screen
    ann.LR.db.ui.lootPage = "history" ann.LR.UI.show("loot") srv:tick(0.1) ann.LR.db.ui.lootPage = "raid"
    local cur = ann.LR.session(base.id)
    if cur and cur.gk then
      for _, name in ipairs({ "ledgerSheet", "payoutsOutSheet", "potRulesSheet", "goldInOutSheet", "salesSheet" }) do
        if ann.LR.UI[name] then pcall(ann.LR.UI[name], cur) srv:tick(0.1) ann.LR.UI.closeAll() end
      end
    end
  end
  local drawn = 0
  base = lead.LR.startSession("Karazhan", 2, true, false)
  srv:tick(2)
  for round = 1, math.floor(ROUNDS / 2) do
    local t = copy(base)
    for _ = 1, 25 do call("op", pick(OPS)[2], t) end
    local keys = keysOf(t)
    for _ = 1, math.random(0, 2) do
      local k = pick(keys)
      if k ~= "id" and k ~= "leader" then
        if type(t[k]) == "table" and chance(0.6) then
          local sub = keysOf(t[k])
          if #sub > 0 then t[k][pick(sub)] = junk() end
        else t[k] = junk() end
      end
    end
    t.rev = base.rev + round * 10
    t.leader, t.id = base.leader, base.id
    send({ t = "T", v = 1, s = t })
    srv:tick(0.5)
    if ann.LR.session(base.id) then
      for _, tab in ipairs(tabs) do ann.LR.UI.show(tab) srv:tick(0.1) end
      sheets()
      drawn = drawn + 1
    end
    if #ann.M.errors > 0 then
      problem("a raider's LootRuler errored on a session from the leader: %s", tostring(ann.M.errors[1]))
      ann.M.errors = {}
    end
  end
  ann.LR.UI.win:Hide()
  say("%d broken sessions from the leader taken and drawn on every tab", drawn)
  if #lead.M.errors > 0 then problem("the leader's LootRuler errored: %s", tostring(lead.M.errors[1])) lead.M.errors = {} end
  lead.LR.endSession(base)
  srv:tick(2)
end

---------------------------------------------------------------------- 1d. raiders' reserve messages with odd item numbers
section("1d. reserves sent with odd item numbers, any item allowed")
do
  local ann = srv:client({ name = "Anna", class = "PRIEST" })
  srv:setGroup({ lead, ann }, lead, true)
  srv:tick(3)
  local s = lead.LR.startSession("Karazhan", 3, true, false)
  lead.LR.Session.setAny(s, true, U.now())
  lead.LR.leaderChanged(s)
  srv:tick(2)
  for _ = 1, ROUNDS do
    local list = {}
    for i = 1, math.random(1, 4) do list[i] = pick({ 0 / 0, math.huge, -math.huge, 1e308, 2 ^ 53, 2147483648, -1, 0, 2.5, pick(KARA), 99999 }) end
    ann.LR.Net.send({ t = "P", id = s.id, i = list, c = "PRIEST" }, "WHISPER", U.full("Lead"))
    srv:tick(0.3)
  end
  srv:tick(2)
  for _, id in ipairs(S.reservesOf(s, U.full("Anna"))) do
    if id ~= id or id > LR.MAX_ITEM_ID or id <= 0 or id % 1 ~= 0 then problem("a reserve on item %s got in", tostring(id)) end
  end
  promises(s, "odd item numbers")
  for _, tab in ipairs({ "reserve", "reserves", "loot" }) do ann.LR.UI.show(tab) lead.LR.UI.show(tab) srv:tick(0.1) end
  for _, p in ipairs({ lead, ann }) do if #p.M.errors > 0 then problem("%s's LootRuler errored: %s", p.name, tostring(p.M.errors[1])) p.M.errors = {} end end
  lead.LR.endSession(s)
  srv:tick(2)
  say("%d reserve messages with odd item numbers", ROUNDS)
end

---------------------------------------------------------------------- 2. rolls
section("2. rolls: random rolls, passes and bids")
do
  local n = 0
  for round = 1, ROUNDS * 3 do
    local s = newSession(round)
    for _ = 1, 15 do call("op", pick(OPS)[2], s) end
    local id = pick(KARA)
    local roster = {}
    for _, p in ipairs(PLAYERS) do roster[#roster + 1] = { name = p, class = "MAGE", online = true } end
    local plan = call("R.plan", R.plan, s, id, roster)
    if plan then
      local mode = chance(0.2) and "BID" or plan.mode
      local roll = call("R.new", R.new, "k" .. round, id, chance(0.8) and plan or { mode = mode })
      if roll then
        if mode == "BID" then roll.mode, roll.min, roll.inc = "BID", math.random(0, 100), math.random(1, 50) end
        for _ = 1, math.random(0, 30) do
          local who = player()
          local r = math.random(5)
          if r <= 3 then call("R.add", R.add, roll, who, math.random(1, 100), pick({ 1, 1, 1, 0, 2 }), pick({ 100, 100, 99, 98, 101, 200 }), chance(0.05))
          elseif r == 4 then call("R.pass", R.pass, roll, who)
          else call("R.bid", R.bid, roll, who, chance(0.9) and math.random(0, 5000) or junk(), chance(0.05)) end
        end
        if mode == "BID" and chance(0.5) then
          local maxes = {}
          for _ = 1, math.random(1, 4) do maxes[R.key(pick(PLAYERS))] = { p = pick(PLAYERS), g = math.random(0, 6000) } end
          call("R.resolve", R.resolve, roll, maxes)
        end
        local good, bad = call("R.standings", R.standings, roll)
        local top, tied = call("R.result", R.result, roll)
        call("R.waiting", R.waiting, roll)
        if good and top and good[1] and not tied and good[1].p ~= top.p then
          problem("R.result says %s won, but %s is first in the standings (%s roll)", tostring(top.p), tostring(good[1].p), tostring(roll.mode))
        end
        if top and roll.rolled and roll.mode ~= "BID" and not roll.rolled[R.key(top.p)] then
          problem("R.result's winner %s has no roll that counts (%s)", tostring(top.p), tostring(roll.mode))
        end
        n = n + 1
      end
    end
  end
  say("%d random rolls and auctions", n)
end

---------------------------------------------------------------------- 3. the GDKP split
section("3. the GDKP split")
do
  local n = 0
  for round = 1, ROUNDS * 3 do
    local s = newSession(round)
    G.set(s, true, NOW)
    for _ = 1, math.random(1, 30) do
      local op = pick(OPS)
      if op[1]:match("^gdkp") or chance(0.3) then call(op[1], op[2], s) end
    end
    for _ = 1, math.random(0, 8) do
      S.award(s, pick(KARA), pick(PLAYERS), "BID", math.random(0, 20000), NOW)
    end
    G.saw(s, PLAYERS, NOW)
    local split = call("Gdkp.split", G.split, s)
    if split then
      n = n + 1
      local pot = (call("Gdkp.pot", G.pot, s) or 0)
      local paidOut = 0
      for _, row in ipairs(split.rows or {}) do
        local g = tonumber(row.total or row.g or row.gold or 0) or 0
        if g ~= g then problem("a payout that isn't a number (%s)", tostring(row.p)) g = 0 end
        if g < -0.01 then problem("%s is paid %s: less than nothing (pot %s)", tostring(row.p), tostring(g), tostring(pot)) end
        paidOut = paidOut + g
      end
      if paidOut > pot + 1 and pot >= 0 then
        problem("the split pays out %.2f, more than the pot of %.2f", paidOut, pot)
      end
      call("Gdkp.ledger", G.ledger, s)
      call("Gdkp.payoutsText", G.payoutsText, s)
      call("Gdkp.unsettled", G.unsettled, s)
    end
  end
  say("%d random pots split", n)
end

---------------------------------------------------------------------- 4. text in
section("4. text in: every parser, with random and broken text")
do
  local LibDeflate = lead.G.LibStub("LibDeflate")
  local real = {}
  do
    local s = newSession(1)
    for _ = 1, 30 do call("op", pick(OPS)[2], s) end
    real[#real + 1] = LR.Gargul.export(s)
    real[#real + 1] = "name,class,itemId\nAnn,PRIEST,28528\nBob,MAGE,28530\n"
    real[#real + 1] = "Ann,30\nBob,15\n"
  end
  local function randomText()
    local r = math.random(9)
    if r == 1 then return pick(JUNK_STRINGS) end
    if r == 2 then local t = {} for i = 1, math.random(1, 400) do t[i] = string.char(math.random(0, 255)) end return table.concat(t) end
    if r == 3 then local x = pick(real) return x:sub(1, math.random(0, #x)) end                        -- cut short
    if r == 4 then local x = pick(real) local i = math.random(1, #x) return x:sub(1, i - 1) .. string.char(math.random(32, 126)) .. x:sub(i + 1) end
    if r == 5 then return pick(PLAYERS) .. "," .. tostring(junk()) .. "\n" .. pick(PLAYERS) .. ";" .. math.random(-5, 99999) end
    if r == 6 then return "Group 1\n" .. pick(PLAYERS) .. " tank\n" .. pick(PLAYERS) .. ", " .. pick(PLAYERS) .. "\nGroup 9\nx" end
    if r == 7 then
      local ok, j = pcall(U.toJSON, { softreserves = { { name = pick(ODD_NAMES), items = { { id = item() } } }, { name = pick(PLAYERS), items = { { id = item() }, { id = item() } } } },
        hardreserves = { { id = item() } }, metadata = { id = pick(ODD_NAMES) } })
      return ok and U.b64encode(LibDeflate:CompressZlib(j)) or "x"
    end
    if r == 8 then return ("bid " .. math.random(-10, 1e6)) .. pick({ "", "g", "k", " gold", "#2 300", ".5" }) end
    return pick(real)
  end
  local P, L, N = LR.Prio, LR.Lineup, LR.Notes
  local n = 0
  for _ = 1, ROUNDS * 20 do
    local text = randomText()
    call("Gargul.decode", LR.Gargul.decode, text)
    call("Gargul.fromCSV", LR.Gargul.fromCSV, text)
    local s = newSession(1)
    call("Gargul.importInto", LR.Gargul.importInto, s, text, LR.roster())
    promises(s, "a softres.it import")
    call("Prio.parse", P.parse, text)
    call("Prio.parse inflate", P.parse, text, function(x) return LibDeflate:DecompressDeflate(x) end)
    call("Prio.wishlists", P.wishlists, text)
    local counts = call("Prio.parseCounts", P.parseCounts, text, math.random(0, 100))
    if type(counts) == "table" then
      local gs = newSession(2)
      G.set(gs, true, NOW)
      call("Gdkp.setFixedAll", G.setFixedAll, gs, counts, NOW)
      for _, x in ipairs(counts) do call("S.setPlusOnes", S.setPlusOnes, gs, x.p, x.n, NOW) call("Book.setPoints", B.setPoints, B.new("Kings"), x.p, x.n, NOW) end
      promises(gs, "pasted Name,Number lines")
      call("Gdkp.split", G.split, gs)
    end
    local prices = call("Gdkp.parsePrices", G.parsePrices, text)
    if type(prices) == "table" then local gs = newSession(3) G.set(gs, true, NOW) call("Gdkp.setPrices", G.setPrices, gs, prices, NOW) promises(gs, "pasted prices") end
    local plan = call("Lineup.parse", LR.Lineup.parse, text)
    if type(plan) == "table" then
      local roster = {}
      for i, p in ipairs(PLAYERS) do roster[i] = { name = p, group = math.random(1, 8), index = i } end
      call("Lineup.compare", LR.Lineup.compare, plan, roster)
      -- sorting finishes: at most one move for each player, never going round in circles
      local moves = 0
      while moves <= #roster + 1 do
        local mv = call("Lineup.nextMove", LR.Lineup.nextMove, plan, roster)
        if not mv then break end
        call("Lineup.apply", LR.Lineup.apply, roster, mv)
        moves = moves + 1
      end
      if moves > #roster then problem("sorting the raid into groups didn't finish (%d moves for %d players)", moves, #roster) end
    end

    call("Notes.parse", N.parse, text)
    call("R.parseBid", R.parseBid, text, chance(0.5))
    call("Batch.parse", LR.Batch.parse, text, chance(0.5), math.random(0, 10))
    call("U.fromJSON", U.fromJSON, text)
    call("U.nameKey", U.nameKey, text)
    call("Gargul.rollFromChat", LR.Gargul.rollFromChat, text)
    call("Gargul.rollEndFromChat", LR.Gargul.rollEndFromChat, text)
    local parts = call("U.chatLines", U.chatLines, text .. " " .. text, 255)
    for _, l in ipairs(parts or {}) do
      if #l > 255 then problem("U.chatLines made a line of %d characters", #l) end
    end
    n = n + 1
  end
  say("%d random texts through every parser", n)
end

---------------------------------------------------------------------- 4b. whispers and raid chat, from players with and without LootRuler
section("4b. !lr commands with random text, by whisper and in raid chat")
do
  local pug = srv:player({ name = "Pug", class = "WARRIOR" })
  local s = lead.LR.startSession("Karazhan", 2, true, false)
  srv:setGroup({ lead, pug }, lead, true)
  srv:tick(2)
  local COMMANDS = { "", "remove", "clear", "list", "swap", "bid", "max", "pot", "prio", "vote", "help", "check", "x", "hr", "all" }
  local sent = 0
  for round = 1, ROUNDS * 4 do
    local text = ("!lr " .. pick(COMMANDS) .. " " .. (chance(0.5) and tostring(junk()) or ("|cffa335ee|Hitem:" .. tostring(item()) .. "::::::::70:::::|h[x]|h|r"))):sub(1, 255)
    if chance(0.5) then srv:whisper(pug, lead, text) else srv:chatMessage(pug, text, "RAID") end
    sent = sent + 1
    if round % 50 == 0 then
      srv:tick(1)
      if chance(0.3) then lead.LR.setLocked(s, not s.locked) end
    end
  end
  srv:tick(3)
  if #lead.M.errors > 0 then problem("the leader's LootRuler errored on an !lr line: %s", tostring(lead.M.errors[1])) lead.M.errors = {} end
  promises(s, "random !lr lines")
  for _, l in ipairs(srv.chat) do if #l.text > 255 then problem("a chat line of %d characters: %s", #l.text, l.text:sub(1, 60)) end end
  say("%d random !lr lines", sent)
  lead.LR.endSession(s)
  srv:tick(2)
end

---------------------------------------------------------------------- 5. the guild book
section("5. the guild book: copies merged in any order agree")
do
  local n = 0
  for round = 1, ROUNDS do
    local changes = {}
    local book = B.new("Kings")
    local t = 1700000000
    for _ = 1, 40 do
      t = t + math.random(0, 2)
      local r = math.random(5)
      local c
      if r == 1 then call("setPoints", B.setPoints, book, player(), count(0.9) and math.random(0, 200) or junk(), t)
      elseif r == 2 then
        local list = {}
        for i = 1, (chance(0.1) and math.random(90, 160) or math.random(0, 6)) do list[i] = { p = chance(0.95) and pick(PLAYERS) or pick(ODD_NAMES) .. i, n = math.random(1, 5) } end
        call("setPrio", B.setPrio, book, item(), list, t)
      elseif r == 3 then call("setAlt", B.setAlt, book, player(), player(), t)
      elseif r == 4 then call("unlinkAlt", B.unlinkAlt, book, player(), t)
      else call("received", B.received, book, item(), player(), t) end
      changes[#changes + 1] = copy(book)
    end
    if not call("B.validBook", B.validBook, copy(book)) then problem("the guild book isn't valid after random changes") end
    -- a damaged saved book is mended, keeping every good entry
    local broken = copy(book)
    for _ = 1, 3 do local part = pick({ "points", "prio", "alts" }) local k = pick(keysOf(broken[part])) if k then broken[part][k] = junk() end end
    local fixed = call("B.repair", B.repair, broken, "Kings")
    if not fixed or not B.validBook(fixed) then problem("a damaged guild book isn't mended into a valid one") end
    -- merge the copies into two empty books, in two orders: they must agree
    local a, b = B.new("Kings"), B.new("Kings")
    for i = 1, #changes do call("B.merge", B.merge, a, copy(changes[i]), true, t) end
    for i = #changes, 1, -1 do call("B.merge", B.merge, b, copy(changes[i]), true, t) end
    for _, bk in ipairs({ a, b }) do for id in pairs(bk.prio) do B.prio(bk, id) end end      -- (lists are read sorted)
    if not S.same(a.p or a.points, b.p or b.points) or not S.same(a.prio or a.pr, b.prio or b.pr) or not S.same(a.alts, b.alts) then
      problem("the guild book ends up different depending on the order copies arrive (round %d)", round)
    end
    n = n + 1
  end
  say("%d guild books, merged in two orders", n)
end

---------------------------------------------------------------------- the end
if #lead.M.errors > 0 then problem("the leader's LootRuler errored: %s", tostring(lead.M.errors[1])) end
say("")
if #problems == 0 then say("No problems found.") else
  say("%d problems:", #problems)
  for _, p in ipairs(problems) do say("  %s (%dx)", p, seenProblem[p:sub(1, 120)] or 1) end
end
local f = assert(io.open("build/fuzz.txt", "w"))
f:write(table.concat(lines, "\n"), "\n")
f:close()
os.exit(#problems == 0 and 0 or 1)
