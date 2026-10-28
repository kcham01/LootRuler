-- Pushes LootRuler past an ordinary raid night, in the test stand-in (tests/wow/server.lua), and writes what held and
-- what didn't:
--   1. broken messages:   every kind of addon message LootRuler takes, taken from a real night and broken in
--                         thousands of ways (wrong types, missing fields, huge lists, deep tables), sent by a raider,
--                         by someone outside the group and by the leader. Nothing may throw a Lua error, and nothing
--                         from someone who isn't the leader may change the leader's session.
--   1b. broken whispers:   every !lr command with nonsense after it, by whisper and in raid chat, from a pug, a raider
--                         and someone outside the group, and raid chat lines made to look like the game's or Gargul's.
--   2. the biggest raid:  40 players with 10 reserves each, all on one item (a roll for each reserve: 390 /rolls),
--                         then every raider's 10 reserves on different items, on the leader's screens.
--   3. a long night:      past the most drops a session keeps (S.MAX_DROPS), every one given out: the session's size,
--                         what a late award costs, the Loot tab, then 30 past raids like it.
--   4. chat floods:       hundreds of raid chat lines during an auction, and Gargul's lines typed by a raider.
--   lua5.1 tools/stress.lua            build/stress.txt
--   lua5.1 tools/stress.lua --quick    fewer messages and players
-- Not part of CI (it takes about a minute). A line starting "PROBLEM" is something to fix.
package.path = "./tests/?.lua;./tests/wow/?.lua;" .. package.path
local Server = require("server")

local QUICK = false
for _, a in ipairs(arg) do if a == "--quick" then QUICK = true end end
math.randomseed(7)
os.execute("mkdir -p build")

local lines, problems = {}, {}
local function say(fmt, ...)
  local t = select("#", ...) > 0 and fmt:format(...) or fmt
  lines[#lines + 1] = t
  io.stderr:write(t, "\n")
end
local function problem(fmt, ...)
  local t = fmt:format(...)
  problems[#problems + 1] = t
  say("PROBLEM: " .. t)
end
local function section(name) say("") say("== " .. name) end

local DATA = {}
do
  local chunk = assert(loadfile("LootRuler/Data/Loot.lua"))
  setfenv(chunk, setmetatable({}, { __index = _G }))
  chunk("LootRuler", DATA)
end
local ITEMS = {}                   -- Karazhan's epics (filled from the first client's raid lists)
local function fillItems(LR)
  if #ITEMS > 0 then return end
  local seen = {}
  for _, r in ipairs(LR.RAIDS) do
    if r.key == "Karazhan" then
      for _, b in ipairs(r.bosses) do
        for _, id in ipairs(b.items) do
          local it = DATA.ITEMS[id]
          if it and it[2] == 4 and not seen[id] then seen[id] = true ITEMS[#ITEMS + 1] = id end
        end
      end
    end
  end
end

local NAMES = { "Aldric", "Brenna", "Caius", "Delia", "Eamon", "Fiora", "Gideon", "Hesper", "Isolde", "Jorah", "Kaelen",
  "Liora", "Magnus", "Nerys", "Orrin", "Perrin", "Quilla", "Rowan", "Sabine", "Tobias", "Ursula", "Vesper", "Wren", "Xander",
  "Ysolde", "Zarek", "Alaric", "Brielle", "Cedric", "Dorian", "Elowen", "Fenwick", "Garrick", "Halden", "Ilsa", "Jasper",
  "Kestrel", "Lucan", "Marisol", "Nolan" }
local CLASSES = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "DRUID", "HUNTER", "WARLOCK", "PALADIN", "SHAMAN" }

--- a raid in Karazhan: the leader (master looter), nAddon raiders with LootRuler, nPlain without; all in the group
local function newRaid(nAddon, nPlain, o)
  o = o or {}
  local srv = Server.new(".")
  srv.where = Server.PLACES.Karazhan
  srv.itemInfo = function(id)
    local it = DATA.ITEMS and DATA.ITEMS[id]
    if not it then return nil end
    return { name = it[1], quality = it[2], link = ("|cffa335ee|Hitem:%d::::::::70:::::|h[%s]|h|r"):format(id, it[1]) }
  end
  local lead = srv:client({ name = "Lead", class = "PALADIN", guild = "Kings", rank = 0 })
  fillItems(lead.LR)
  local raiders, pugs, all = {}, {}, { lead }
  for i = 1, nAddon do
    local p = srv:client({ name = NAMES[i], class = CLASSES[(i - 1) % #CLASSES + 1], guild = i % 2 == 0 and "Kings" or nil })
    raiders[#raiders + 1], all[#all + 1] = p, p
  end
  for i = 1, nPlain do
    local p = srv:player({ name = NAMES[nAddon + i], class = CLASSES[i % #CLASSES + 1] })
    pugs[#pugs + 1], all[#all + 1] = p, p
  end
  srv:tick(6)
  srv:setGroup(all, lead, true)
  srv:setMasterLooter(lead)
  srv:tick(2)
  local s = lead.LR.startSession("Karazhan", o.sr or 2, true, o.guild)
  srv:tick(3)
  return srv, lead, raiders, pugs, s, all
end

local function errorsOf(list)
  local n, first = 0, nil
  for _, p in ipairs(list) do
    if p.client then
      n = n + #p.M.errors
      first = first or p.M.errors[1]
    end
  end
  return n, first
end
local function clearErrors(list) for _, p in ipairs(list) do if p.client then p.M.errors = {} end end end

--- CPU time (ms) and memory made (KB) for fn
local function cost(fn)
  collectgarbage("collect")
  local m0, c0 = collectgarbage("count"), os.clock()
  collectgarbage("stop")
  local r = { fn() }
  local ms, kb = (os.clock() - c0) * 1000, collectgarbage("count") - m0
  collectgarbage("restart")
  return ms, kb, unpack(r)
end

-- a copy of a table, as the session would hold it (for comparing before and after)
local function snapshot(t, seen)
  if type(t) ~= "table" then return t end
  seen = seen or {}
  if seen[t] then return seen[t] end
  local c = {}
  seen[t] = c
  for k, v in pairs(t) do c[snapshot(k, seen)] = snapshot(v, seen) end
  return c
end
local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b or (a ~= a and b ~= b) end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

--- CPU time each client spends in its own events, ticks and clicks (ms; like tools/bench.lua, the stand-in included)
local function account(list)
  for _, p in ipairs(list) do
    if p.client and not p.cpu then
      p.cpu, p.longest = 0, 0
      for _, k in ipairs({ "fire", "tick", "click", "type" }) do
        local f = p.M[k]
        p.M[k] = function(...)
          if p.busy then return f(...) end
          p.busy = true
          local c0 = os.clock()
          local r = { pcall(f, ...) }
          local ms = (os.clock() - c0) * 1000
          p.cpu, p.longest, p.busy = p.cpu + ms, math.max(p.longest, ms), false
          if not r[1] then error(r[2], 0) end
          return unpack(r, 2, table.maxn(r))
        end
      end
    end
  end
end
local function resetCpu(list) for _, p in ipairs(list) do if p.client then p.cpu, p.longest = 0, 0 end end end
local function raiderCpu(list)
  local sum, n, most, longest = 0, 0, 0, 0
  for _, p in ipairs(list) do
    if p.client then sum, n, most, longest = sum + p.cpu, n + 1, math.max(most, p.cpu), math.max(longest, p.longest) end
  end
  return n > 0 and sum / n or 0, most, longest
end

---------------------------------------------------------------------- sending raw messages, as any addon could
local function libs(p) return p.G.LibStub("LibSerialize"), p.G.LibStub("LibDeflate") end
local function pack(p, msg)
  local LibSerialize, LibDeflate = libs(p)
  return LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(LibSerialize:Serialize(msg)))
end
--- sends text in parts as AceComm does (bypassing the sender's own addon and its throttle)
local function sendRaw(srv, from, text, channel, target)
  local prefix = "LootRuler"
  if #text <= 255 then srv:addonMessage(from, prefix, text, channel, target) return 1 end
  local n, pos = 0, 1
  while pos <= #text do
    local chunk = text:sub(pos, pos + 253)
    local mark = pos == 1 and "\001" or (pos + 254 > #text and "\003" or "\002")
    srv:addonMessage(from, prefix, mark .. chunk, channel, target)
    pos, n = pos + 254, n + 1
  end
  return n
end

---------------------------------------------------------------------- 1. broken messages
section("1. broken messages")
do
  local srv, lead, raiders, pugs, s, all = newRaid(4, 1, { guild = true })
  local outsider = srv:client({ name = "Outsider", class = "ROGUE", guild = "Kings" })
  srv:tick(3)
  -- a real night first, recording every message: these are the shapes to break
  local seen = {}
  local addonMessage = srv.addonMessage
  local spool = {}
  srv.addonMessage = function(self, from, prefix, text, channel, target)
    if prefix == "LootRuler" then
      local key = from.name .. channel
      local c, rest = text:match("^([\001-\003])(.*)$")
      local whole
      if c == "\001" then spool[key] = { rest } elseif c == "\002" then table.insert(spool[key] or {}, rest)
      elseif c == "\003" then local t = spool[key] or {} t[#t + 1] = rest whole = table.concat(t) spool[key] = nil
      else whole = text end
      if whole then
        local m = lead.LR.Net.decode(whole)
        if m and not seen[m.t] then seen[m.t] = m end
      end
    end
    return addonMessage(self, from, prefix, text, channel, target)
  end
  local LR = lead.LR
  for i, p in ipairs(raiders) do p.LR.reserve(p.LR.current(), ITEMS[i]) srv:tick(0.5) end
  srv:whisper(pugs[1], lead, "!lr " .. srv:link(ITEMS[6]))
  srv:tick(2)
  LR.setLocked(s, true)
  srv:tick(2)
  srv:openLoot(lead, { { ITEMS[1], 4 }, { ITEMS[2], 4 } })
  srv:tick(2)
  LR.Rolls.start(ITEMS[1], { link = srv:link(ITEMS[1]), slot = 1, secs = 10 })
  srv:tick(1)
  for _, p in ipairs(raiders) do srv:roll(p, 1, 100) end
  srv:tick(15)
  if LR.Rolls.current and LR.Rolls.current.state ~= "awarded" then LR.Rolls.award(raiders[1] and Server.full(raiders[1])) end
  srv:tick(3)
  LR.setCouncil(s, { Server.full(raiders[2]) })
  LR.setGdkp(s, true)
  srv:tick(2)
  LR.Rolls.start(ITEMS[2], { link = srv:link(ITEMS[2]), slot = 2, secs = 20 })
  srv:tick(1)
  srv:chatMessage(raiders[1], "150", "RAID")
  srv:tick(25)
  LR.Bags.ask({ ITEMS[3] })
  srv:tick(3)
  srv.addonMessage = addonMessage
  -- every kind the addon listens for, with the real one where the night made it
  local kinds = {}
  for k in pairs(LR.Net.handlers) do kinds[#kinds + 1] = k end
  kinds[#kinds + 1] = "?"                             -- (one it doesn't know)
  table.sort(kinds)
  local fields = {}                                 -- every field name the night used
  local function harvest(t, depth)
    for k, v in pairs(t) do
      if type(k) == "string" then fields[k] = true end
      if type(v) == "table" and depth < 3 then harvest(v, depth + 1) end
    end
  end
  for _, m in pairs(seen) do harvest(m, 0) end
  local names = {}
  for k in pairs(fields) do names[#names + 1] = k end
  table.sort(names)
  local missing = {}
  for _, k in ipairs(kinds) do if not seen[k] then missing[#missing + 1] = k end end
  say("kinds of message: %d (%s); seen in the night: %d; made up from field names: %s", #kinds, table.concat(kinds, " "),
    #kinds - #missing, #missing > 0 and table.concat(missing, " ") or "none")

  local function deep(n) local t = {} local c = t for _ = 1, n do c.x = {} c = c.x end return t end
  local function list(n, v) local t = {} for i = 1, n do t[i] = v or i end return t end
  local WEIRD = {
    function() return nil end, function() return true end, function() return false end, function() return 0 end,
    function() return -1 end, function() return 1.5 end, function() return 2 ^ 53 end, function() return -2 ^ 31 end,
    function() return 1 / 0 end, function() return "" end, function() return ("x"):rep(3000) end,
    function() return "|cffff0000|Hitem:19019::::|h[Thunderfury]|h|r" end, function() return "Lead" end,
    function() return "Lead-Dreamscythe" end, function() return Server.full(raiders[1]) end, function() return s.id end,
    function() return {} end, function() return { 1, 2, 3 } end, function() return list(2000) end,
    function() return list(200, "Lead") end, function() return deep(40) end, function() return { i = list(50) } end,
    function() return { [Server.full(raiders[1])] = { i = { ITEMS[1] } } } end, function() return { p = "Lead", n = 999999 } end,
    function() return ITEMS[1] end, function() return "1.0.0-beta" end, function() return "99.0.0" end,
  }
  local function weird() return WEIRD[math.random(#WEIRD)]() end
  local function mutate(m)
    local c = snapshot(m)
    for _ = 1, math.random(1, 4) do
      local r = math.random()
      local keys = {}
      for k in pairs(c) do if k ~= "t" then keys[#keys + 1] = k end end
      if r < 0.5 and #keys > 0 then
        local k = keys[math.random(#keys)]
        if type(c[k]) == "table" and math.random() < 0.5 then
          local inner = {}
          for k2 in pairs(c[k]) do inner[#inner + 1] = k2 end
          if #inner > 0 then c[k][inner[math.random(#inner)]] = weird() else c[k][1] = weird() end
        else c[k] = weird() end
      elseif r < 0.8 then c[names[math.random(#names)]] = weird()
      elseif #keys > 0 then c[keys[math.random(#keys)]] = nil end
    end
    if math.random() < 0.05 then c.t = weird() end
    return c
  end

  local N = QUICK and 40 or 250
  -- every trade switch on, for everyone: no message may change a setting, open a trade or put an item in one
  for _, p in ipairs(all) do if p.client then p.LR.db.settings.autoTrade, p.LR.db.settings.tradeHelp = true, true end end
  local setBefore, opened, used = {}, 0, 0
  for _, p in ipairs(all) do
    if p.client then
      setBefore[p] = snapshot(p.LR.db.settings)
      local initiate, use = p.G.InitiateTrade, p.G.C_Container.UseContainerItem
      p.G.InitiateTrade = function(...) opened = opened + 1 return initiate(...) end
      p.G.C_Container.UseContainerItem = function(...) used = used + 1 return use(...) end
    end
  end
  setBefore[outsider] = snapshot(outsider.LR.db.settings)
  local leadBefore = snapshot({ res = s.res, won = s.won, leader = s.leader, locked = s.locked, hr = s.hr, gk = s.gk and { nb = s.gk.nb } })
  local raiderSession = raiders[3].LR.current()
  local sent, parts, worst = 0, 0, { ms = 0 }
  local perKind = {}
  clearErrors(all) clearErrors({ outsider })
  local leadSaid0 = #srv.chat
  local senders = {
    { who = raiders[2], channel = "RAID" },
    { who = outsider, channel = "WHISPER", to = lead },
    { who = outsider, channel = "GUILD" },
    { who = lead, channel = "RAID" },                    -- (raiders' addons must take a broken copy from their leader too)
  }
  for _, kind in ipairs(kinds) do
    local base = seen[kind] or { t = kind }
    local errs0 = errorsOf(all) + errorsOf({ outsider })
    local ms0 = os.clock()
    for i = 1, N do
      local m = mutate(base)
      if not m.t or m.t == base.t then m.t = kind end
      local how = senders[(i % #senders) + 1]
      local ok, text = pcall(pack, lead, m)
      if ok then
        local c0 = os.clock()
        parts = parts + sendRaw(srv, how.who, text, how.channel, how.to and Server.full(how.to))
        srv:pump()
        local ms = (os.clock() - c0) * 1000
        if ms > worst.ms then worst = { ms = ms, kind = kind } end
        sent = sent + 1
      end
      if i % 25 == 0 then srv:tick(1) end
    end
    srv:tick(2)
    local errs, first = errorsOf(all)
    local e2, f2 = errorsOf({ outsider })
    errs, first = errs + e2, first or f2
    perKind[#perKind + 1] = { kind = kind, errors = errs - errs0, ms = (os.clock() - ms0) * 1000 }
    if errs - errs0 > 0 then problem("message %s: %d Lua errors from broken copies (first: %s)", kind, errs - errs0, tostring(first)) end
    clearErrors(all) clearErrors({ outsider })
  end
  srv:tick(10)
  say("sent %d broken messages (%d parts), %d of each kind, from a raider, someone outside the group and the leader", sent, parts, N)
  local rows = {}
  for _, k in ipairs(perKind) do rows[#rows + 1] = ("%s %d ms"):format(k.kind, k.ms) end
  say("time to take them, by kind: %s", table.concat(rows, ", "))
  say("the slowest single message to take: %.1f ms (%s)", worst.ms, tostring(worst.kind))
  local leadAfter = snapshot({ res = s.res, won = s.won, leader = s.leader, locked = s.locked, hr = s.hr, gk = s.gk and { nb = s.gk.nb } })
  -- (a raider may change their own reserves: P from raiders[2] is allowed. Everyone else's must stay.)
  local changed = {}
  for k, v in pairs(leadBefore) do
    if k == "res" then
      for name, r in pairs(v) do if name ~= Server.full(raiders[2]) and not same(r, leadAfter.res[name]) then changed[#changed + 1] = "res:" .. name end end
      for name in pairs(leadAfter.res) do if v[name] == nil and name ~= Server.full(raiders[2]) then changed[#changed + 1] = "res+:" .. name end end
    elseif not same(v, leadAfter[k]) then changed[#changed + 1] = k end
  end
  if #changed > 0 then problem("broken messages from others changed the leader's session: %s", table.concat(changed, ", "))
  else say("the leader's session: unchanged by anyone else's messages (reserves, awards, leader, lock, hard reserves, bids)") end
  local now = raiders[3].LR.current()
  if not now or not lead.LR.U.samePlayer(now.leader, Server.full(lead)) then problem("a raider's window now shows a session not led by the leader")
  else say("raiders' windows: still the leader's session") end
  say("chat lines the leader's addon said while taking them: %d", #srv.chat - leadSaid0)
  local changedSet = 0
  for p, before in pairs(setBefore) do if not same(before, p.LR.db.settings) then changedSet = changedSet + 1 end end
  if changedSet > 0 or opened > 0 or used > 0 then
    problem("broken messages changed %d players' settings, opened %d trades, put %d items in trades", changedSet, opened, used)
  else say("with every trade switch on: no setting changed, no trade opened, no item put in a trade") end
end

---------------------------------------------------------------------- 1b. broken whispers and chat lines
section("1b. broken whispers and chat lines")
do
  local srv, lead, raiders, pugs, s, all = newRaid(3, 2)
  local outsider = srv:player({ name = "Stranger", class = "ROGUE" })
  srv:tick(2)
  local LR = lead.LR
  for i, p in ipairs(raiders) do p.LR.reserve(p.LR.current(), ITEMS[i]) srv:tick(0.3) end
  srv:tick(2)
  local resBefore = snapshot(s.res)
  for _, p in ipairs(all) do if p.client then p.LR.db.settings.autoTrade, p.LR.db.settings.tradeHelp = true, true end end
  local setBefore = {}
  for _, p in ipairs(all) do if p.client then setBefore[p] = snapshot(p.LR.db.settings) end end
  local CMDS = { "", "remove", "clear", "swap", "points", "prio", "vote", "bid", "max", "pot", "list", "help", "?", "give", "award",
    "trade", "lock", "end", "de", "roll", "settings" }
  local ARGS = { "", " 0", " -5", " 999999999", " 1.5k", " #9 300", " #0 1", " Lead", " Stranger", " " .. srv:link(ITEMS[1]),
    " " .. srv:link(ITEMS[1]) .. " " .. srv:link(ITEMS[2]), " |cffff0000|Hitem:0|h[]|h|r", " for", (" x"):rep(100), " %s%d%%", " \0" }
  local sent = 0
  local function burst(who, how)
    for _, c in ipairs(CMDS) do
      for _, a in ipairs(ARGS) do
        local text = ("!lr " .. c .. a):sub(1, 255)
        if how == "WHISPER" then srv:whisper(who, lead, text) else srv:chatMessage(who, text, "RAID") end
        sent = sent + 1
      end
      srv:tick(0.5)
    end
  end
  clearErrors(all)
  local ms = cost(function()
    burst(pugs[1], "WHISPER") burst(pugs[1], "RAID") burst(outsider, "WHISPER") burst(raiders[1], "RAID")
    -- and raid chat lines that look like the game's or Gargul's
    for _, line in ipairs({ "Lead rolls 100 (1-100)", "Aldric rolls 100 (100-100)", " Gargul : Stop your rolls!",
      (" Gargul : %s was awarded to Brenna. Congrats!"):format(srv:link(ITEMS[1])), "#1 999999999", "bid 0", "1.5k", "999999999999" }) do
      srv:chatMessage(raiders[2], line, "RAID") sent = sent + 1
    end
  end)
  srv:tick(120)
  local errs, first = errorsOf(all)
  if errs > 0 then problem("broken whispers and chat lines: %d errors (first: %s)", errs, tostring(first)) end
  local others = 0
  for name, r in pairs(resBefore) do
    if not lead.LR.U.samePlayer(name, Server.full(raiders[1])) and not same(r, s.res[name]) then others = others + 1 end
  end
  if others > 0 then problem("broken whispers changed %d other players' reserves", others) end
  local changedSet = 0
  for p, before in pairs(setBefore) do if not same(before, p.LR.db.settings) then changedSet = changedSet + 1 end end
  if changedSet > 0 then problem("broken whispers changed %d players' settings", changedSet) end
  if #(s.won or {}) > 0 then problem("broken whispers or chat lines made %d winners", #s.won) end
  say("%d broken !lr commands and lookalike lines (by whisper and raid chat, from a pug, a raider and someone outside the group): %.0f ms for the whole raid here", sent, ms)
  say("no errors, nobody else's reserves changed, no setting changed, no winner made: %s", (errs == 0 and others == 0 and changedSet == 0 and #(s.won or {}) == 0) and "yes" or "NO")
end

---------------------------------------------------------------------- 2. the biggest raid
section("2. the biggest raid")
do
  local n = QUICK and 9 or 29
  local srv, lead, raiders, pugs, s, all = newRaid(n, QUICK and 3 or 10, { sr = 10 })
  local LR = lead.LR
  local item = ITEMS[1]
  -- everyone puts all 10 reserves on the same item
  for _, p in ipairs(raiders) do
    p.LR.changeMine(p.LR.current(), function(items) for _ = 1, 10 do items[#items + 1] = item end end, item)
    srv:tick(0.3)
  end
  for _, p in ipairs(pugs) do                        -- (whispers: a few links fit in one line)
    for _ = 1, 5 do srv:whisper(p, lead, "!lr " .. srv:link(item) .. " " .. srv:link(item)) srv:tick(0.3) end
  end
  srv:tick(5)
  local total = 0
  for _, r in pairs(s.res) do total = total + #(r.i or {}) end
  local full = LR.Net.encode(snapshot(s))
  say("%d players, %d reserves, all on one item: a whole copy of the session is %d characters (%d parts)", #all, total, #full, math.ceil(#full / 254))
  srv:openLoot(lead, { { item, 4 } })
  srv:tick(2)
  local roll = LR.Rolls.start(item, { link = srv:link(item), slot = 1, secs = 60 })
  srv:tick(1)
  account(all)
  resetCpu(all)
  local rolls = 0
  local ms = cost(function()
    for _ = 1, 10 do
      for _, p in ipairs(all) do
        if p ~= lead then srv:roll(p, 1, 100) rolls = rolls + 1 srv:tick(0.05) end
      end
    end
  end)
  local avg, most, longest = raiderCpu(raiders)
  say("  the loot master's addon: %.0f ms in all (longest at once %.1f ms); each raider's: %.0f ms (most %.0f, longest at once %.1f ms)",
    lead.cpu, lead.longest, avg, most, longest)
  local counted = 0
  for _ in pairs(roll and roll.rolled or {}) do counted = counted + 1 end
  say("%d /rolls on it (a roll for each reserve): %.0f ms for the whole raid here; %d players have a best roll that counts", rolls, ms, counted)
  if roll and counted < #all - 1 then problem("only %d of %d reservers' rolls counted", counted, #all - 1) end
  local again = 0
  for _, e in ipairs(roll and roll.entries or {}) do if e.why == "again" then again = again + 1 end end
  if again > 0 then problem("%d rolls marked 'again' (past the rolls a player has)", again) end
  local leadMs = cost(function() for _ = 1, 20 do LR.Roll.standings(roll) end end)
  say("working out the standings (%d rolls), 20 times: %.1f ms", rolls, leadMs)
  srv:tick(65)
  -- 400 reserves on 40 items, on the leader's screens
  LR.endSession(s)
  srv:tick(2)
  s = LR.startSession("Karazhan", 10, true)
  srv:tick(2)
  for i, p in ipairs(raiders) do
    p.LR.changeMine(p.LR.current(), function(items) for k = 1, 10 do items[#items + 1] = ITEMS[(i + k) % #ITEMS + 1] end end, ITEMS[1])
    srv:tick(0.3)
  end
  srv:tick(5)
  total = 0
  for _, r in pairs(s.res) do total = total + #(r.i or {}) end
  local UI = LR.UI
  local function tab(name, openAll)
    return cost(function()
      UI.show(name)
      if openAll then
        for _, x in ipairs(lead.M.findText("Open all", true, lead.G.LootRulerFrame)) do
          if x.clickable then lead.M.click(x.clickable) break end
        end
      end
      UI.render()
    end)
  end
  local closedMs = tab("reserves")
  local openMs = tab("reserves", true)
  local reserveMs = tab("reserve", true)
  say("%d reserves: the Reserves tab %.0f ms with bosses closed, %.0f ms with all open; the Reserve tab, all open: %.0f ms", total, closedMs, openMs, reserveMs)
  local errs, first = errorsOf(all)
  if errs > 0 then problem("biggest raid: %d errors (%s)", errs, tostring(first)) end
end

---------------------------------------------------------------------- 3. a long night
section("3. a long night")
do
  local srv, lead, raiders, pugs, s, all = newRaid(QUICK and 5 or 15, 5)
  local LR = lead.LR
  local S = LR.Session
  local maxDrops = S.MAX_DROPS
  local corpses = math.ceil((maxDrops + 20) / 5)
  local firstAward, lastAward
  local given = 0
  for c = 1, corpses do
    srv:target(lead, "Boss " .. c)
    local items = {}
    for k = 1, 5 do items[k] = { ITEMS[(c * 5 + k) % #ITEMS + 1], 4 } end
    srv:openLoot(lead, items)
    srv:tick(0.5)
    for k = 1, 5 do
      local who = Server.full(all[(c + k) % #all + 1])
      local ms = cost(function() LR.Rolls.give(items[k][1], who, "MS", { slot = k }) end)
      given = given + 1
      if given == 1 then firstAward = ms end
      lastAward = ms
      srv:tick(0.2)
    end
    srv:closeLoot(lead)
    srv:tick(0.5)
  end
  srv:tick(10)
  local full = LR.Net.encode(snapshot(s))
  say("%d corpses, %d items given out; the session keeps %d drops (most: %d) and %d awards", corpses, given, #s.drops, maxDrops, #s.won)
  if #s.drops >= maxDrops then say("(%d drops is a safety cap: a real night lists far fewer)", maxDrops) end
  say("a whole copy of the session at the end: %d characters (%d parts, about %d seconds to send at 800 characters a second)",
    #full, math.ceil(#full / 254), math.ceil(#full / 800))
  say("giving out an item: %.1f ms for the first, %.1f ms for the last (the leader's addon, here)", firstAward, lastAward)
  -- (five items given out every 2 seconds is faster than any real loot master: what's still going out has to catch up)
  local behind, waited = 0, 0
  for _, p in ipairs(raiders) do
    local c = p.LR.current()
    if not c or #c.won < #s.won then behind = behind + 1 end
  end
  while waited < 600 do
    local all = true
    for _, p in ipairs(raiders) do local c = p.LR.current() if not c or #c.won < #s.won then all = false break end end
    if all then break end
    srv:tick(1)
    waited = waited + 1
  end
  local r1 = raiders[1].LR.current()
  if not r1 or #r1.won ~= #s.won then problem("after 10 minutes, a raider's copy has %d awards, the leader's %d", r1 and #r1.won or -1, #s.won)
  else say("raiders' copies: %d of %d raiders were behind when the last item went; all had every award %d seconds later", behind, #raiders, waited) end
  local UI = LR.UI
  local lootMs = cost(function() UI.show("loot") UI.render() end)
  say("the Loot tab with %d drops: %.0f ms", #s.drops, lootMs)
  -- 30 past raids like it
  LR.endSession(s)
  srv:tick(3)
  local past = LR.History.all()
  if past[1] then
    for i = 2, 30 do
      local c = snapshot(past[1])
      c.id = c.id .. ":" .. i
      c.ended = (c.ended or 0) - i * 86400 * 3        -- (a raid every three days)
      for _, w in ipairs(c.won or {}) do w.at = (w.at or 0) - i * 86400 * 3 end
      table.insert(past, c)
    end
  end
  local histMs = cost(function()
    LR.db.ui.lootPage = "history"
    UI.show("loot")
    UI.render()
  end)
  local fairMs = cost(function() LR.History.fairness(0, nil) end)
  say("30 past raids of %d awards each: the award history %.0f ms, who got what over time %.0f ms", past[1] and #past[1].won or 0, histMs, fairMs)
  local function size(v, seen)
    if type(v) == "string" then return #v + 3 end
    if type(v) ~= "table" then return #tostring(v) + 1 end
    local n = 2
    for k, x in pairs(v) do n = n + size(k) + size(x) + 2 end
    return n
  end
  say("the saved file with them: about %d KB", math.floor(size(lead.G.LootRulerDB) / 1024))
  local errs, first = errorsOf(all)
  if errs > 0 then problem("long night: %d errors (%s)", errs, tostring(first)) end
end

---------------------------------------------------------------------- 4. chat floods
section("4. chat floods")
do
  local srv, lead, raiders, pugs, s, all = newRaid(QUICK and 5 or 15, 10)
  local LR = lead.LR
  LR.setGdkp(s, true)
  srv:tick(2)
  local roll = LR.Rolls.start(ITEMS[1], { link = srv:link(ITEMS[1]), secs = 30 })
  srv:tick(1)
  local said0 = #srv.chat
  local lines = 0
  local ms = cost(function()
    for i = 1, QUICK and 100 or 600 do
      local p = all[(i % (#all - 1)) + 2]
      local text = i % 3 == 0 and tostring(100 + i * 5) or (i % 3 == 1 and "lol nice pull" or "need heals on 2 pls 100%")
      srv:chatMessage(p, text, "RAID")
      lines = lines + 1
      if i % 20 == 0 then srv:tick(0.5) end
    end
  end)
  srv:tick(40)
  say("%d raid chat lines during an auction (a third of them bids): %.0f ms for the whole raid here; the leader's addon said %d lines; sold: %s",
    lines, ms, #srv.chat - said0 - lines, tostring(roll and roll.state == "awarded"))
  -- Gargul's lines typed by a raider (not the loot runner): nobody's windows should open
  for i = 1, 20 do
    srv:chatMessage(raiders[1], (" Gargul : You have 10 seconds to roll on %s - /roll for MS or /roll 99 for OS"):format(srv:link(ITEMS[i % #ITEMS + 1])), "RAID")
    srv:tick(0.2)
  end
  srv:tick(2)
  local opened = 0
  for _, p in ipairs(raiders) do
    for _, f in ipairs(p.LR.UI.rollFrames()) do if f:IsShown() then opened = opened + 1 end end
  end
  if opened > 0 then problem("Gargul's lines from a raider opened %d roll windows", opened)
  else say("20 of Gargul's roll lines typed by a raider: no roll windows opened") end
  local errs, first = errorsOf(all)
  if errs > 0 then problem("chat floods: %d errors (%s)", errs, tostring(first)) end
end

say("")
say(#problems == 0 and "No problems found." or ("%d problems found."):format(#problems))
local f = assert(io.open("build/stress.txt", "w"))
f:write("LootRuler stress test, in the test stand-in\n", table.concat(lines, "\n"), "\n")
f:close()
