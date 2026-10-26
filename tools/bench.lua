-- How much work LootRuler does in a 40-player raid, measured in the test stand-in (tests/wow/server.lua): the
-- leader and 29 raiders run the addon, 10 more don't (they whisper and type in raid chat). It plays a raid night
-- through, moment by moment, and for each one writes down:
--   - work:     Lua instructions run in LootRuler's own code (and its libraries), per player, counted by sampling
--               every 1,000 instructions. Within about 2% between runs, so it can be compared between versions; the
--               stand-in's own code isn't counted.
--   - time:     CPU time on this computer, per player (it includes the stand-in, so only compare it with itself)
--   - garbage:  memory made and thrown away, per player (what makes the game's garbage collector pause)
--   - network:  addon messages (each up to 255 characters, as the game sends them) and chat lines, with their size,
--               by kind of message; and for session changes, how long until every raider's addon has the change
--   - screen:   frames made, and OnUpdate scripts running (work every frame)
-- and at the end: memory per player, the saved data's size, and the slowest functions.
--   lua5.1 tools/bench.lua             build/bench.txt (to read) and build/bench.json (numbers, for comparing)
--   lua5.1 tools/bench.lua --quick     fewer players, to try it out
-- Not part of CI: the stand-in isn't the game, so the numbers say where the work is, not how fast the game runs it.
package.path = "./tests/?.lua;./tests/wow/?.lua;" .. package.path
local Server = require("server")

local QUICK, COUNT_PASS = false, false
for _, a in ipairs(arg) do
  if a == "--quick" then QUICK = true end
  if a == "--count" then COUNT_PASS = true end
end
local ADDON_PLAYERS, PLAIN_PLAYERS = QUICK and 9 or 29, QUICK and 5 or 10
math.randomseed(1)
os.execute("mkdir -p build")

---------------------------------------------------------------------- who is measured, and how
-- Each client's events, ticks, clicks and typing run through a wrapper that notes whose code is running (active),
-- and the CPU time and memory made while it runs. In the counting pass (a second run of this file, --count) a hook
-- counts instructions every STEP and gives them to whoever is running and to the function running.
local STEP = 1000
local PER_SAMPLE = STEP     -- real instructions a sample stands for (the hook's own use up part of each count: measured below)
local active
local hot = {}             -- "file:line" of a function -> instructions (the whole night)
local hotNow = {}          -- the same, for the moment being measured
local function newStat() return { cpu = 0, alloc = 0, instr = 0, calls = 0, longest = 0 } end

-- garbage, split between LootRuler's code and the stand-in's (which draws, keeps frames...: the game does that in C).
-- Memory made since the last hook goes to the code running now (close enough over many samples), less what the
-- hook itself makes (measured below).
local made = { addon = 0, standin = 0 }
local lastCount, HOOK_COST = 0, 0
local function hook()
  if not active then lastCount = collectgarbage("count") return end
  local info = debug.getinfo(2, "S")
  local src = info.source
  local now = collectgarbage("count")
  local d = now - lastCount - HOOK_COST
  lastCount = now
  local mine = src:find("LootRuler/", 1, true) ~= nil
  if d > 0 then
    if mine then made.addon = made.addon + d else made.standin = made.standin + d end
  end
  if mine then
    active.stat.instr = active.stat.instr + PER_SAMPLE
    local key = src:gsub("^@%./", ""):gsub("^@", "") .. ":" .. info.linedefined
    hot[key] = (hot[key] or 0) + PER_SAMPLE
    hotNow[key] = (hotNow[key] or 0) + PER_SAMPLE
  end
end

local function measured(p, f)
  return function(...)
    if active then return f(...) end              -- (already counted: an event fired from inside another)
    active = p
    local c0, m0 = os.clock(), collectgarbage("count")
    local r = { pcall(f, ...) }
    local dt = os.clock() - c0
    p.stat.cpu = p.stat.cpu + dt
    if dt > p.stat.longest then p.stat.longest = dt end
    p.stat.alloc = p.stat.alloc + math.max(0, collectgarbage("count") - m0)
    p.stat.calls = p.stat.calls + 1
    active = nil
    if not r[1] then error(r[2], 0) end
    return unpack(r, 2, table.maxn(r))
  end
end

local function watch(p)
  p.stat = newStat()
  for _, k in ipairs({ "fire", "tick", "click", "type" }) do p.M[k] = measured(p, p.M[k]) end
  p.timers = 0
  local after = p.G.C_Timer.After
  p.G.C_Timer.After = function(d, fn) p.timers = p.timers + 1 return after(d, fn) end
end
--- runs fn as p (an action of theirs: a click in code, a slash command)
local function as(p, fn, ...) return measured(p, fn)(...) end

---------------------------------------------------------------------- the network, as the server sees it
local net = { addon = {}, chat = {} }
local srv = Server.new(".")
local addonMessage, chatMessage = srv.addonMessage, srv.chatMessage
srv.addonMessage = function(self, from, prefix, text, channel, target)
  table.insert(net.addon, { from = from, prefix = prefix, text = text, channel = channel, at = self.clock })
  return addonMessage(self, from, prefix, text, channel, target)
end
srv.chatMessage = function(self, from, text, channel, target)
  table.insert(net.chat, { from = from, text = text, channel = channel })
  return chatMessage(self, from, text, channel, target)
end

---------------------------------------------------------------------- the raid
local DATA = {}
do
  local chunk = assert(loadfile("LootRuler/Data/Loot.lua"))
  setfenv(chunk, setmetatable({}, { __index = _G }))
  chunk("LootRuler", DATA)
end
srv.itemInfo = function(id)
  local it = DATA.ITEMS and DATA.ITEMS[id]
  if not it then return nil end
  return { name = it[1], quality = it[2], link = ("|cffa335ee|Hitem:%d::::::::70:::::|h[%s]|h|r"):format(id, it[1]) }
end

local NAMES = { "Aldric", "Brenna", "Caius", "Delia", "Eamon", "Fiora", "Gideon", "Hesper", "Isolde", "Jorah", "Kaelen",
  "Liora", "Magnus", "Nerys", "Orrin", "Perrin", "Quilla", "Rowan", "Sabine", "Tobias", "Ursula", "Vesper", "Wren", "Xander",
  "Ysolde", "Zarek", "Alaric", "Brielle", "Cedric", "Dorian", "Elowen", "Fenwick", "Garrick", "Halden", "Ilsa", "Jasper",
  "Kestrel", "Lucan", "Marisol" }
local CLASSES = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "DRUID", "HUNTER", "WARLOCK", "PALADIN", "SHAMAN" }

local load = {}            -- what loading the addon costs one player
local lead
do
  collectgarbage("collect")
  local m0, c0 = collectgarbage("count"), os.clock()
  lead = srv:client({ name = "Lead", class = "PALADIN", guild = "Kings", rank = 0 })
  load.cpu = os.clock() - c0
  collectgarbage("collect")
  load.mem = collectgarbage("count") - m0
end
local players, raiders, pugs = { lead }, {}, {}
for i = 1, ADDON_PLAYERS do
  local p = srv:client({ name = NAMES[i], class = CLASSES[(i - 1) % #CLASSES + 1], realm = i % 5 == 0 and "Faerlina" or nil,
    guild = i % 2 == 0 and "Kings" or nil })
  raiders[#raiders + 1] = p
  players[#players + 1] = p
end
for i = 1, PLAIN_PLAYERS do
  local p = srv:player({ name = NAMES[ADDON_PLAYERS + i], class = CLASSES[i % #CLASSES + 1] })
  pugs[#pugs + 1] = p
  players[#players + 1] = p
end
for _, p in ipairs(players) do if p.client then watch(p) end end
local LR = lead.LR
local U, S = LR.U, LR.Session
local function full(p) return Server.full(p) end

if COUNT_PASS then
  -- what one call of the hook makes in memory, with nothing else running
  collectgarbage("stop")
  local fake = { stat = newStat() }
  active = fake
  local m0 = collectgarbage("count")
  for _ = 1, 10000 do lastCount = collectgarbage("count") hook() end
  HOOK_COST = (collectgarbage("count") - m0) / 10000
  collectgarbage("restart")
  -- how many real instructions a sample stands for: a loop of a known length, named like LootRuler's code
  local loop = loadstring("local n = ... for i = 1, n do end", "@LootRuler/calibration")
  local N = 2e7
  fake.stat = newStat()
  debug.sethook(hook, "", STEP)
  loop(N)
  debug.sethook()
  PER_SAMPLE = N / (fake.stat.instr / STEP)
  active, hot = nil, {}
  debug.sethook(hook, "", STEP)
end

-- Karazhan's epics
local ITEMS = {}
for _, r in ipairs(LR.RAIDS) do
  if r.key == "Karazhan" then
    local seen = {}
    for _, b in ipairs(r.bosses) do
      for _, id in ipairs(b.items) do
        local it = DATA.ITEMS[id]
        if it and it[2] == 4 and not seen[id] then seen[id] = true ITEMS[#ITEMS + 1] = id end
      end
    end
  end
end

---------------------------------------------------------------------- moments
local results = {}

local function decodeAll(list)
  -- AceComm sends a long message in parts (first "\001", then "\002"s, last "\003"); put them back together
  local kinds, parts = {}, {}
  for _, m in ipairs(list) do
    if m.prefix == LR.PREFIX then
      local key = full(m.from) .. "|" .. m.channel
      local c, rest = m.text:match("^([\001-\003])(.*)$")
      local whole
      if c == "\001" then parts[key] = { rest } elseif c == "\002" then table.insert(parts[key] or {}, rest)
      elseif c == "\003" then
        local t = parts[key] or {}
        t[#t + 1] = rest
        whole = table.concat(t)
        parts[key] = nil
      else whole = m.text end
      local k = kinds._last or {}
      if whole then
        local msg = LR.Net.decode(whole)
        local t = msg and msg.t or "?"
        k = kinds[t] or { n = 0, parts = 0, bytes = 0, biggest = 0 }
        kinds[t] = k
        k.n = k.n + 1
        k.biggest = math.max(k.biggest, #whole)
        if m.from == lead then k.ch = k.ch or {} k.ch[m.channel] = (k.ch[m.channel] or 0) + 1 end
      end
      kinds._pending = (kinds._pending or 0) + #m.text
      kinds._parts = (kinds._parts or 0) + 1
      if whole then
        k.parts = k.parts + kinds._parts
        k.bytes = k.bytes + kinds._pending
        kinds._parts, kinds._pending = 0, 0
      end
    end
  end
  kinds._parts, kinds._pending, kinds._last = nil, nil, nil
  return kinds
end

local function onUpdates(p)
  local n = 0
  for _, f in ipairs(p.M.allFrames()) do if f._scripts.OnUpdate and f:IsVisible() then n = n + 1 end end
  return n
end

local function moment(name, about, fn)
  collectgarbage("collect")
  collectgarbage("stop")
  for _, p in ipairs(players) do if p.client then p.stat = newStat() p.timers = 0 p.frames0 = p.M.frameCount() end end
  net.addon, net.chat = {}, {}
  hotNow = {}
  made.addon, made.standin, lastCount = 0, 0, collectgarbage("count")
  local mem0, clock0, wall0 = collectgarbage("count"), srv.clock, os.clock()
  local extra = fn() or {}
  local r = { name = name, about = about, wall = os.clock() - wall0, seconds = srv.clock - clock0, extra = extra }
  collectgarbage("restart")
  r.made = collectgarbage("count") - mem0
  collectgarbage("collect")
  r.kept = collectgarbage("count") - mem0
  local others = { cpu = 0, alloc = 0, instr = 0, timers = 0, frames = 0, n = 0, maxInstr = 0, longest = 0 }
  for _, p in ipairs(raiders) do
    others.n = others.n + 1
    others.cpu, others.alloc, others.instr = others.cpu + p.stat.cpu, others.alloc + p.stat.alloc, others.instr + p.stat.instr
    others.maxInstr = math.max(others.maxInstr, p.stat.instr)
    others.longest = math.max(others.longest, p.stat.longest)
    others.timers, others.frames = others.timers + p.timers, others.frames + (p.M.frameCount() - p.frames0)
  end
  r.lead = { longest = lead.stat.longest, cpu = lead.stat.cpu, alloc = lead.stat.alloc, instr = lead.stat.instr, timers = lead.timers, frames = lead.M.frameCount() - lead.frames0,
    onUpdate = onUpdates(lead) }
  r.raider = { longest = others.longest, cpu = others.cpu / others.n, alloc = others.alloc / others.n, instr = others.instr / others.n, maxInstr = others.maxInstr,
    timers = others.timers / others.n, frames = others.frames / others.n, onUpdate = onUpdates(raiders[1]) }
  -- the network
  local sent = { leadMsgs = 0, leadBytes = 0, otherMsgs = 0, otherBytes = 0, byChannel = {} }
  for _, m in ipairs(net.addon) do
    local mine = m.from == lead
    sent[mine and "leadMsgs" or "otherMsgs"] = sent[mine and "leadMsgs" or "otherMsgs"] + 1
    sent[mine and "leadBytes" or "otherBytes"] = sent[mine and "leadBytes" or "otherBytes"] + #m.text
    if mine then sent.byChannel[m.channel] = (sent.byChannel[m.channel] or 0) + 1 end
  end
  sent.kinds = decodeAll(net.addon)
  local chat = { lead = 0, leadBytes = 0, others = 0, byChannel = {} }
  for _, c in ipairs(net.chat) do
    if c.from == lead then chat.lead = chat.lead + 1 chat.leadBytes = chat.leadBytes + #c.text
      chat.byChannel[c.channel] = (chat.byChannel[c.channel] or 0) + 1
    else chat.others = chat.others + 1 end
  end
  r.addon, r.chat = sent, chat
  r.hot = hotNow
  r.split = { addon = made.addon, standin = made.standin }
  results[#results + 1] = r
  io.stderr:write(("  %-34s %6.2fs\n"):format(name, r.wall))
  return r
end

--- lets time pass in small steps until cond() holds (or max seconds); returns the seconds it took, or nil
local function untilAll(cond, max)
  local t = 0
  while t < (max or 60) do
    if cond() then return t end
    srv:tick(0.1)
    t = t + 0.1
  end
  return cond() and t or nil
end
local function everyoneHas(test)
  return function()
    for _, p in ipairs(raiders) do if not test(p) then return false end end
    return true
  end
end

---------------------------------------------------------------------- the night
io.stderr:write(COUNT_PASS and "counting instructions:\n" or "measuring:\n")
srv:tick(6)

local s
moment("forming the raid", "40 players join one at a time, with reserves already open (each join is a roster change for everyone)", function()
  srv:setGroup({ lead }, lead, true)
  srv:setMasterLooter(lead)
  srv:tick(1)
  s = as(lead, LR.startSession, "Karazhan", 2, true, true)
  srv:tick(2)
  for i = 2, #players do
    table.insert(srv.group.members, players[i])
    players[i].inGroup = true
    srv:rosterChanged()
    srv:tick(0.5)
  end
  srv:tick(5)
  return { rosterChanges = #players - 1 }
end)

moment("opening reserves", "the leader opens soft reserves again (a fresh session) for the whole raid", function()
  as(lead, LR.endSession, s)
  srv:tick(2)
  s = as(lead, LR.startSession, "Karazhan", 2, true, true)
  local secs = untilAll(everyoneHas(function(p) local c = p.LR.current() return c and c.id == s.id end), 30)
  srv:tick(3)
  return { everyoneHasIt = secs }
end)

moment("reserving", "every raider with the addon picks 2 items; the 10 without whisper \"!lr <item>\" twice", function()
  for i, p in ipairs(raiders) do
    as(p, p.LR.reserve, p.LR.current(), ITEMS[(i * 3) % #ITEMS + 1])
    as(p, p.LR.reserve, p.LR.current(), ITEMS[(i * 7 + 1) % #ITEMS + 1])
    srv:tick(0.3)
  end
  for i, p in ipairs(pugs) do
    srv:whisper(p, lead, "!lr " .. srv:link(ITEMS[(i * 5) % #ITEMS + 1]))
    srv:tick(0.3)
    srv:whisper(p, lead, "!lr " .. srv:link(ITEMS[(i * 11 + 2) % #ITEMS + 1]))
    srv:tick(0.3)
  end
  local total = (#raiders + #pugs) * 2
  local secs = untilAll(everyoneHas(function(p)
    local c, n = p.LR.current(), 0
    for _, r in pairs(c and c.res or {}) do n = n + #(r.i or {}) end
    return n >= total
  end), 60)
  srv:tick(3)
  local n = 0
  for _, r in pairs(s.res) do n = n + #(r.i or {}) end
  return { reserves = n, everyoneAgrees = secs }
end)

moment("lock and post", "the leader locks reserves and posts the rules in raid chat", function()
  as(lead, LR.setLocked, s, true)
  as(lead, LR.Whisper.announce, s)
  local secs = untilAll(everyoneHas(function(p) return p.LR.current() and p.LR.current().locked end), 30)
  srv:tick(3)
  return { everyoneHasIt = secs }
end)

local function rollOut(id, slot)
  local roll = as(lead, LR.Rolls.start, id, { link = srv:link(id), slot = slot, secs = 15 })
  srv:tick(1)
  for _, p in ipairs(players) do
    if p ~= lead then srv:roll(p, 1, 100) srv:tick(0.1) end
  end
  srv:tick(20)
  if roll and roll.state ~= "awarded" then
    local w = roll.top and roll.top.p
    if not w then for _, e in pairs(roll.rolled or {}) do if e.kind then w = e.p break end end end
    if w then as(lead, LR.Rolls.award, w) end
  end
  srv:tick(3)
  return roll
end

moment("a boss dies", "the loot master opens the corpse (5 epics): the loot is posted, then one item is rolled out and everyone rolls", function()
  srv:target(lead, "Prince Malchezaar")
  srv:openLoot(lead, { { ITEMS[1], 4 }, { ITEMS[2], 4 }, { ITEMS[3], 4 }, { ITEMS[4], 4 }, { ITEMS[5], 4 } })
  srv:tick(2)
  local roll = rollOut(ITEMS[1], 1)
  local n = 0
  for _ in pairs(roll and roll.rolled or {}) do n = n + 1 end
  return { rollsThatCount = n }
end)

moment("rolling out the rest", "the other 4 items, one after another, everyone rolling on each", function()
  for i = 2, 5 do rollOut(ITEMS[i], i) end
  srv:closeLoot(lead)
  srv:tick(2)
end)

moment("idle for a minute", "nothing happens for 60 seconds (between pulls), with the trade timers up", function()
  srv:tick(60, 0.5)
end)

moment("the leader's screens", "the leader opens each tab of the window and the Reserves tab both ways (80 reserves)", function()
  local UI = LR.UI
  local tabs = { "reserve", "reserves", "loot", "session", "settings", "guild" }
  local t = {}
  for _, tab in ipairs(tabs) do
    local c0 = os.clock()
    as(lead, UI.show, tab)
    as(lead, UI.render)
    t[tab] = os.clock() - c0
  end
  for _ = 1, 10 do as(lead, UI.render) end
  srv:tick(1)
  as(lead, function() UI.win:Hide() end)
  return { tabs = t }
end)

moment("a GDKP auction", "the same raid as a GDKP: one item auctioned, 25 bids typed in raid chat (bidding war)", function()
  as(lead, LR.setGdkp, s, true)
  srv:tick(2)
  local roll = as(lead, LR.Rolls.start, ITEMS[6], { link = srv:link(ITEMS[6]), secs = 30 })
  srv:tick(1)
  local bid = 100
  for i = 1, 25 do
    local p = players[(i * 7) % #players + 1]
    if p == lead then p = players[2] end
    bid = bid + 50
    srv:chatMessage(p, tostring(bid), "RAID")
    srv:tick(0.4)
  end
  srv:tick(45)
  return { sold = roll and roll.state == "awarded" }
end)

moment("five auctions at once", "a batch of 5 items, 40 bids by number in raid chat", function()
  local items = {}
  for i = 7, 11 do items[#items + 1] = { id = ITEMS[i], link = srv:link(ITEMS[i]) } end
  local batch = as(lead, LR.Batch.start, items, 30)
  srv:tick(1)
  for i = 1, 40 do
    local p = players[(i * 5) % #players + 1]
    if p == lead then p = players[3] end
    srv:chatMessage(p, ("#%d %d"):format((i % 5) + 1, 200 + i * 20), "RAID")
    srv:tick(0.3)
  end
  srv:tick(60)
  return { done = batch and batch.state ~= "open" }
end)

moment("the pot", "splitting the pot (the leader's split, worked out 50 times: the GDKP tab redraws it)", function()
  for _ = 1, 50 do as(lead, LR.Gdkp.split, s) end
end)

moment("ending the raid", "the leader ends the session: it's kept as a past raid", function()
  as(lead, LR.Gdkp.settleAll or function() end, s)
  as(lead, function() if LR.Gdkp.unsettled then LR.endSession(s) else LR.endSession(s) end end)
  srv:tick(3)
end)

-- the leader's saved file, with 30 past raids like this one
local function serialize(v, out)
  local t = type(v)
  if t == "table" then
    out[#out + 1] = "{"
    for k, x in pairs(v) do serialize(k, out) out[#out + 1] = "=" serialize(x, out) out[#out + 1] = "," end
    out[#out + 1] = "}"
  elseif t == "string" then out[#out + 1] = ("%q"):format(v)
  else out[#out + 1] = tostring(v) end
  return out
end
local savedOne = #table.concat(serialize(lead.G.LootRulerDB, {}))
do
  local past = LR.History.all()
  local one = past[1]
  if one then
    for i = 2, 30 do
      local c = U.copy(one)
      c.id = one.id .. ":" .. i
      c.started = (c.started or 0) - i * 7 * 86400
      table.insert(past, c)
    end
  end
end
local savedFull = #table.concat(serialize(lead.G.LootRulerDB, {}))

moment("past raids", "who got what over time, across 30 past raids (the fairness window), worked out 10 times", function()
  for _ = 1, 10 do as(lead, LR.History.fairness, 0, nil) end
end)

local reload
moment("a reload", "the leader reloads with 30 past raids saved: the saved file is read and checked", function()
  local db = srv:logout(lead)
  srv:tick(1)
  collectgarbage("collect")
  local c0 = os.clock()
  srv:login(lead, db)
  reload = os.clock() - c0
  watch(lead)
  lead.frames0 = lead.M.frameCount()
  srv:tick(6)
  return {}
end)

if COUNT_PASS then
  debug.sethook()
  local out = assert(io.open("build/bench-count.lua", "w"))
  out:write("return {\n")
  for _, r in ipairs(results) do
    out:write(("  { name = %q, lead = %d, raider = %d, maxRaider = %d, addonKB = %d, standinKB = %d, hot = {"):format(r.name, r.lead.instr,
      math.floor(r.raider.instr), r.raider.maxInstr, r.split.addon, r.split.standin))
    local top = {}
    for key, n in pairs(r.hot) do top[#top + 1] = { key, n } end
    table.sort(top, function(a, b) return a[2] > b[2] end)
    for i = 1, math.min(6, #top) do out:write(("{ %q, %d }, "):format(top[i][1], top[i][2])) end
    out:write("} },\n")
  end
  out:write("  moments = {\n")
  for _, r in ipairs(results) do
    local all = 0
    for _, n in pairs(r.hot) do all = all + n end
    out:write(("    [%q] = { all = %d },\n"):format(r.name, all))
  end
  out:write("  },\n")
  out:write("  hot = {\n")
  for k, n in pairs(hot) do out:write(("    [%q] = %d,\n"):format(k, n)) end
  out:write("  },\n}\n")
  out:close()
  os.exit(0)
end

---------------------------------------------------------------------- the counting pass, then the report
io.stderr:write("counting instructions (a second run):\n")
assert(os.execute("lua5.1 tools/bench.lua --count" .. (QUICK and " --quick" or "")) == 0, "the counting pass failed")
local counted = dofile("build/bench-count.lua")
for i, r in ipairs(results) do
  local c = counted[i]
  if c and c.name == r.name then
    r.lead.instr, r.raider.instr, r.raider.maxInstr, r.top = c.lead, c.raider, c.maxRaider, c.hot
    r.split = { addon = c.addonKB, standin = c.standinKB }
  end
end

-- each function's name, from its first line
local function nameOf(key)
  local file, line = key:match("^(.*):(%d+)$")
  line = tonumber(line)
  if line == 0 then return file .. " (the file itself)" end
  local n = 0
  for l in io.lines(file) do
    n = n + 1
    if n == line then
      local name = l:match("function%s+([%w_.:]+)") or l:match("([%w_.]+)%s*=%s*function") or l:match("local%s+function%s+([%w_]+)")
      return ("%s:%d %s"):format(file:gsub("^LootRuler/", ""), line, name or "(a function)")
    end
  end
  return key
end

local function kb(n) return ("%.0f KB"):format(n) end
local function ms(n) return ("%.1f ms"):format(n * 1000) end
local function k(n) if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end if n >= 1e3 then return ("%.0fk"):format(n / 1e3) end return tostring(math.floor(n)) end

local lines = {}
local function say(fmt, ...) lines[#lines + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
say("LootRuler benchmark: a raid of %d (%d with LootRuler, %d without), in the test stand-in", #players, 1 + #raiders, #pugs)
say("Work is Lua instructions in LootRuler's own code (within about 2% between runs). Time is CPU time here, stand-in included.")
say("Garbage is memory made and thrown away. Messages are addon messages as sent (255 characters at most each).")
say("")
say("Loading the addon: %s and %s for one player.", ms(load.cpu), kb(load.mem))
say("")
for _, r in ipairs(results) do
  say("== %s", r.name)
  say("   %s", r.about)
  say("   leader:  work %s, time %s (longest at once %s), garbage %s, timers %d, new frames %d, OnUpdate running %d",
    k(r.lead.instr), ms(r.lead.cpu), ms(r.lead.longest), kb(r.lead.alloc), r.lead.timers, r.lead.frames, r.lead.onUpdate)
  say("   raider:  work %s (most %s), time %s (longest at once, anyone %s), garbage %s, timers %.0f, new frames %.0f, OnUpdate running %d",
    k(r.raider.instr), k(r.raider.maxInstr), ms(r.raider.cpu), ms(r.raider.longest), kb(r.raider.alloc), r.raider.timers, r.raider.frames, r.raider.onUpdate)
  say("   network: the leader sent %d messages (%s), everyone else %d (%s); chat lines: the leader %d, others %d",
    r.addon.leadMsgs, kb(r.addon.leadBytes / 1024), r.addon.otherMsgs, kb(r.addon.otherBytes / 1024), r.chat.lead, r.chat.others)
  local chans = {}
  for ch, n in pairs(r.addon.byChannel) do chans[#chans + 1] = ("%s %d"):format(ch:lower(), n) end
  table.sort(chans)
  if #chans > 0 then say("   the leader's messages by channel: %s", table.concat(chans, ", ")) end
  local kinds = {}
  for t, x in pairs(r.addon.kinds) do kinds[#kinds + 1] = { t = t, x = x } end
  table.sort(kinds, function(a, b) return a.x.bytes > b.x.bytes end)
  if #kinds > 0 then
    local parts = {}
    for _, e in ipairs(kinds) do
      local ch = {}
      for c, n in pairs(e.x.ch or {}) do ch[#ch + 1] = c:lower() .. " " .. n end
      table.sort(ch)
      parts[#parts + 1] = ("%s x%d (%d parts, %s, biggest %d%s)"):format(e.t, e.x.n, e.x.parts, kb(e.x.bytes / 1024), e.x.biggest,
        #ch > 0 and ("; the leader's: " .. table.concat(ch, ", ")) or "")
    end
    say("   by kind: %s", table.concat(parts, "; "))
  end
  local ex = {}
  for key, v in pairs(r.extra) do
    if type(v) == "table" then
      local p = {}
      for a, b in pairs(v) do p[#p + 1] = a .. " " .. ms(b) end
      table.sort(p)
      ex[#ex + 1] = key .. ": " .. table.concat(p, ", ")
    else ex[#ex + 1] = key .. " = " .. (type(v) == "number" and ("%.1f"):format(v) or tostring(v)) end
  end
  table.sort(ex)
  if #ex > 0 then say("   %s", table.concat(ex, "; ")) end
  if r.top and #r.top > 0 then
    local all = (counted.moments[r.name] or {}).all or 0
    local p = {}
    for _, e in ipairs(r.top) do p[#p + 1] = ("%s %.0f%%"):format((nameOf(e[1])), e[2] * 100 / math.max(1, all)) end
    say("   busiest: %s", table.concat(p, ", "))
  end
  if r.split and r.split.addon + r.split.standin > 0 then
    say("   garbage, everyone together: %s by LootRuler's own code, %s by the stand-in (drawing and frames: C in the game)",
      kb(r.split.addon), kb(r.split.standin))
  end
  say("   whole raid: %s of game time, %s here; memory made %s, kept %s", ("%.0fs"):format(r.seconds), ("%.2fs"):format(r.wall), kb(r.made), kb(r.kept))
  say("")
end

collectgarbage("collect")
local perPlayer = collectgarbage("count") / (1 + #raiders)
say("Memory now: %s per player with LootRuler (the stand-in's share included).", kb(perPlayer))
say("The leader's saved file: %s after one raid, %s with 30 past raids; reloading with it: %s.", kb(savedOne / 1024), kb(savedFull / 1024), ms(reload or 0))
say("")
say("Where the work is (every player together, the whole night): the 25 busiest functions")
local list = {}
for key, n in pairs(counted.hot) do list[#list + 1] = { key = key, n = n } end
table.sort(list, function(a, b) return a.n > b.n end)
local total = 0
for _, e in ipairs(list) do total = total + e.n end
for i = 1, math.min(25, #list) do say("  %5.1f%%  %s", list[i].n * 100 / total, nameOf(list[i].key)) end
local byFile = {}
for _, e in ipairs(list) do local f = e.key:match("^(.*):%d+$") byFile[f] = (byFile[f] or 0) + e.n end
local files = {}
for f, n in pairs(byFile) do files[#files + 1] = { f = f, n = n } end
table.sort(files, function(a, b) return a.n > b.n end)
say("")
say("By file:")
for i = 1, math.min(15, #files) do say("  %5.1f%%  %s", files[i].n * 100 / total, files[i].f:gsub("^LootRuler/", "")) end

local text = table.concat(lines, "\n") .. "\n"
local f = assert(io.open("build/bench.txt", "w"))
f:write(text)
f:close()
-- the numbers, for comparing two runs
local j = { "[" }
for i, r in ipairs(results) do
  j[#j + 1] = ('{"name":%q,"leadWork":%d,"raiderWork":%d,"leadMsgs":%d,"leadBytes":%d,"otherMsgs":%d,"otherBytes":%d,"leadChat":%d,"leadGarbageKB":%.0f,"raiderGarbageKB":%.0f}%s')
    :format(r.name, r.lead.instr, r.raider.instr, r.addon.leadMsgs, r.addon.leadBytes, r.addon.otherMsgs, r.addon.otherBytes, r.chat.lead,
      r.lead.alloc, r.raider.alloc, i < #results and "," or "")
end
j[#j + 1] = "]"
f = assert(io.open("build/bench.json", "w"))
f:write(table.concat(j, "\n"))
f:close()
print(text)
