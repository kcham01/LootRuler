-- Chaos raids: whole raids in the test stand-in (tests/wow/server.lua) where everyone does random things in random
-- order, for hundreds of steps: reserving and taking reserves back (in the addon, by whisper and in raid chat),
-- the leader changing every setting, corpses looted, items rolled out, rolled for, passed on, given out, undone,
-- rolled again, traded; GDKP auctions with bids; imports; raiders and pugs leaving, coming back, going offline,
-- reloading; the leader reloading mid-roll, handing the reserves over, leaving; the raid leader taking over.
-- After every step: no Lua error on anyone's screen, no chat line over 255 characters. Every 30 steps the raid
-- settles, and then: one leader for the session, its copy valid and keeping its promises, and every raider in the
-- group with LootRuler holding the same reserves, hard reserves and loot given out.
--   lua5.1 tools/chaos.lua [raids] [steps]     build/chaos.txt
-- Not part of CI. A line starting "PROBLEM" is something to fix (each comes with its raid's seed and last steps).
package.path = "./tests/?.lua;./tests/wow/?.lua;" .. package.path
local Server = require("server")

local RAIDS = tonumber(arg and arg[1]) or 20
local STEPS = tonumber(arg and arg[2]) or 300
os.execute("mkdir -p build")

local lines, problems, seen = {}, {}, {}
local function say(fmt, ...)
  local t = select("#", ...) > 0 and fmt:format(...) or fmt
  lines[#lines + 1] = t
  io.stderr:write(t, "\n")
end
local trail, seed = {}, 0
local function problem(fmt, ...)
  local t = fmt:format(...)
  local key = t:gsub("%d+", "#"):sub(1, 140)
  seen[key] = (seen[key] or 0) + 1
  if seen[key] > 1 then return end
  problems[#problems + 1] = t
  say("PROBLEM (raid %d): %s", seed, t)
  say("   last steps: %s", table.concat(trail, " | ", math.max(1, #trail - 10)))
end

local DATA = {}
do
  local chunk = assert(loadfile("LootRuler/Data/Loot.lua"))
  setfenv(chunk, setmetatable({}, { __index = _G }))
  chunk("LootRuler", DATA)
end
local function itemInfo(id)
  local it = DATA.ITEMS and DATA.ITEMS[id]
  if not it then return nil end
  return { name = it[1], quality = it[2], link = ("|cffa335ee|Hitem:%d::::::::70:::::|h[%s]|h|r"):format(id, it[1]) }
end
local function pick(list) return list[math.random(#list)] end
local function where(a, b, path)
  if a == b then return nil end
  if type(a) ~= "table" or type(b) ~= "table" then return path .. ": " .. tostring(a) .. " / " .. tostring(b) end
  for k, v in pairs(a) do local w = where(v, b[k], path .. "." .. tostring(k)) if w then return w end end
  for k, v in pairs(b) do if a[k] == nil then return path .. "." .. tostring(k) .. ": nil / " .. tostring(v) end end
end
local function chance(p) return math.random() < p end

local NAMES = { "Aldric", "Brenna", "Caius", "Delia", "Eamon", "Fiora" }
local PUGS = { "Gideon", "Hesper", "Isolde" }
local CLASSES = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "DRUID", "HUNTER", "WARLOCK", "PALADIN", "SHAMAN" }

local totals = { steps = 0, rolls = 0, awards = 0, settles = 0, reloads = 0, handovers = 0, takeovers = 0, trades = 0, auctions = 0 }

local ONLY = tonumber(os.getenv("ONLY") or "")
for r = 1, RAIDS do
 if not ONLY or ONLY == r then
  seed = r
  math.randomseed((tonumber(os.getenv("SEEDBASE")) or 1000) + r)
  trail = {}
  local function step(text) trail[#trail + 1] = text if #trail > 40 then table.remove(trail, 1) end end

  local srv = Server.new(".")
  srv.where = Server.PLACES.Karazhan
  srv.itemInfo = itemInfo
  local lead = srv:client({ name = "Lead", class = "PALADIN", guild = "Kings", rank = 0 })
  local KARA = {}
  for _, rd in ipairs(lead.LR.RAIDS) do
    if rd.key == "Karazhan" then for _, b in ipairs(rd.bosses) do for _, id in ipairs(b.items) do KARA[#KARA + 1] = id end end end
  end
  local raiders, pugs = {}, {}
  for i, n in ipairs(NAMES) do raiders[i] = srv:client({ name = n, class = CLASSES[i], guild = i % 2 == 0 and "Kings" or nil, rank = i == 2 and 1 or 3 }) end
  for i, n in ipairs(PUGS) do pugs[i] = srv:player({ name = n, class = CLASSES[i + 3] }) end
  local outsider = srv:client({ name = "Outsider", class = "MAGE", guild = "Kings", rank = 3 })
  local withAddon = { lead, outsider }
  for _, p in ipairs(raiders) do withAddon[#withAddon + 1] = p end
  local everyone = { lead }
  for _, p in ipairs(raiders) do everyone[#everyone + 1] = p end
  for _, p in ipairs(pugs) do everyone[#everyone + 1] = p end
  srv:tick(6)
  local inGroup = {}
  for _, p in ipairs(everyone) do inGroup[#inGroup + 1] = p end
  local groupLeader = lead
  srv:setGroup(inGroup, lead, true)
  srv:setMasterLooter(lead)
  srv:tick(2)
  for _, p in ipairs(raiders) do if chance(0.3) then p.LR.db.settings.raidCommands = true end end
  lead.LR.db.settings.raidCommands = chance(0.5)
  local s0 = lead.LR.startSession("Karazhan", math.random(1, 3), chance(0.5), chance(0.5))
  local sid = s0.id
  if r % 3 == 0 then lead.LR.setGdkp(s0, true) end          -- (one raid in three auctions its loot)
  srv:tick(3)
  local chatSeen = 0
  local saved = {}                                   -- logged-out clients' saved data
  local function online(p) return p.client and p.LR ~= nil end
  local function holder()
    local out = {}
    for _, p in ipairs(withAddon) do
      if online(p) then
        local s = p.LR.session(sid)
        if s and not s.archived and p.LR.isLeader(s) then out[#out + 1] = p end
      end
    end
    return out
  end
  local function setGroup()
    local list = {}
    for _, p in ipairs(inGroup) do list[#list + 1] = p end
    if #list > 0 then
      local leaderNow = groupLeader
      local ok = false
      for _, p in ipairs(list) do if p == leaderNow then ok = true end end
      if not ok then leaderNow = list[1] groupLeader = leaderNow end
      srv:setGroup(list, leaderNow, true)
    end
  end
  local function removeFrom(p) for i, q in ipairs(inGroup) do if q == p then table.remove(inGroup, i) return true end end end
  local function inG(p) for _, q in ipairs(inGroup) do if q == p then return true end end return false end
  local function boss()
    -- (the one in the group: someone who left it still thinks they run their copy, as they can't hear the raid)
    for _, p in ipairs(holder()) do if inG(p) then return p end end
  end
  local function frameOf(p)
    if not online(p) then return nil end
    for _, f in ipairs(p.LR.UI.rollFrames()) do if f:IsShown() and f.copy then return f end end
  end
  local function master() local ml = srv.masterLooter return ml and online(ml) and ml or nil end

  local ACTIONS = {
    -- reserving
    { 14, "reserve", function()
      local p = pick(raiders)
      if not online(p) then return end
      local s = p.LR.session(sid)
      if s then p.LR.reserve(s, pick(KARA)) step(p.name .. " reserves") end
    end },
    { 6, "unreserve", function()
      local p = pick(raiders)
      if not online(p) then return end
      local s = p.LR.session(sid)
      local picks = s and p.LR.myPicks(s) or {}
      if #picks > 0 then p.LR.unreserve(s, pick(picks)) step(p.name .. " takes a reserve back") end
    end },
    { 10, "pug !lr", function()
      local p = pick(pugs)
      local b = boss()
      if not b or not inG(p) then return end
      local r = math.random(5)
      local text = r <= 2 and ("!lr " .. srv:link(pick(KARA))) or r == 3 and "!lr remove" or r == 4 and "!lr" or ("!lr swap " .. srv:link(pick(KARA)) .. " " .. srv:link(pick(KARA)))
      if chance(0.5) then srv:whisper(p, b, text) else srv:chatMessage(p, text, "RAID") end
      step(p.name .. ": " .. text:gsub("|c%x+|Hitem:(%d+).-|r", "[%1]"))
    end },
    -- the leader's settings
    { 8, "settings", function()
      local b = boss()
      if not b then return end
      local s = b.LR.session(sid)
      local L = b.LR
      local x = math.random(16)
      if x == 1 then L.setLocked(s, not s.locked) step("locked: " .. tostring(s.locked))
      elseif x == 2 then L.configure(s, math.random(1, 4), chance(0.5)) step("reserves each: " .. s.sr)
      elseif x == 3 then L.setExtra(s, pick(raiders).LR and L.U.full(pick(NAMES)) or L.U.full("Aldric"), math.random(0, 3)) step("extra reserves")
      elseif x == 4 then L.setHR(s, pick(KARA), pick({ "", "Aldric" }), "GM") step("hard reserve")
      elseif x == 5 then for id in pairs(s.hr) do L.clearHR(s, id) break end step("hard reserve taken off")
      elseif x == 6 then L.setAny(s, not s.any) step("any item: " .. tostring(s.any))
      elseif x == 7 then L.setGroupOnly(s, not s.go) step("only the group: " .. tostring(s.go))
      elseif x == 8 then L.setPlusOne(s, not s.plusOne) step("+1 rule")
      elseif x == 9 then L.setOneWin(s, not s.ow) step("one reserve win each")
      elseif x == 10 then L.setDisenchanter(s, chance(0.7) and L.U.full(pick(NAMES)) or nil) step("disenchanter")
      elseif x == 11 then L.setCouncil(s, chance(0.6) and { L.U.full(pick(NAMES)), L.U.full(pick(NAMES)) } or {}) step("loot council")
      elseif x == 12 then L.setBrand(s, chance(0.7) and { n = "KARA NIGHT", m = "Join us", i = math.random(1, 10) } or nil) step("raid name")
      elseif x == 13 then L.setAutoLock(s, chance(0.7) and (L.U.now() + math.random(30, 400)) or nil) step("lock by itself")
      elseif x == 14 and chance(0.3) then L.setGdkp(s, not s.gdkp) step("GDKP: " .. tostring(s.gdkp))
      elseif x == 15 then L.setSessionPrio(s, pick({ nil, "both" })) step("priority lists")
      else L.adjustPlusOne(s, L.U.full(pick(NAMES)), pick({ 1, -1 })) step("+1 changed") end
    end },
    -- a softres.it sheet imported (and imported again, changed)
    { 2, "import", function()
      local b = boss()
      if not b then return end
      local rows = { "name,class,itemId" }
      for _ = 1, math.random(1, 8) do rows[#rows + 1] = ("%s,%s,%d"):format(pick({ "Aldric", "Hesper", "isolde", "Nobody", "Brenna" }), pick(CLASSES), pick(KARA)) end
      local s = b.LR.session(sid)
      local ok = pcall(b.LR.Gargul.importInto, s, table.concat(rows, "\n"), b.LR.roster())
      b.LR.leaderChanged(s)
      step("softres.it import")
    end },
    -- loot
    { 8, "corpse", function()
      local ml = master()
      if not ml then return end
      local items = {}
      for i = 1, math.random(1, 4) do items[i] = { pick(KARA), 4 } end
      srv:openLoot(ml, items)
      step(ml.name .. " opens a corpse (" .. #items .. ")")
    end },
    { 10, "roll out", function()
      local ml = master()
      if not ml then return end
      local cur = ml.LR.Rolls.mine()
      if cur and cur.state == "open" then return end
      if cur and cur.state == "closed" and chance(0.8) then return end          -- (give the one closed out first, mostly)
      if cur then ml.LR.Rolls.dismiss() end
      local slot = ml.loot and #ml.loot > 0 and math.random(1, #ml.loot) or nil
      local id = slot and ml.loot[slot] and ml.loot[slot].id or pick(KARA)
      local roll = ml.LR.Rolls.start(id, { slot = slot, link = srv:link(id), secs = pick({ 10, 15, 20 }) })
      if roll then totals.rolls = totals.rolls + 1 if roll.mode == "BID" then totals.auctions = totals.auctions + 1 end end
      step(ml.name .. " rolls out " .. id .. (roll and (" (" .. roll.mode .. ")") or " (refused)"))
    end },
    { 16, "roll", function()
      local p = pick(everyone)
      if not inG(p) then return end
      local ml = master()
      local cur = ml and ml.LR.Rolls.mine()
      if not cur or cur.state ~= "open" then return end
      if cur.mode == "BID" then
        local g = (cur.top and cur.top.n or cur.min or 100) + math.random(-10, 200)
        srv:chatMessage(p, tostring(g), "RAID")
        step(p.name .. " bids " .. g)
      elseif chance(0.15) and frameOf(p) then
        local f = frameOf(p)
        if f.pass and f.pass:IsShown() then p.M.click(f.pass) step(p.name .. " passes") end
      else
        srv:roll(p, 1, pick({ 100, 100, 100, 99, 98 }), math.random(1, 100))
        step(p.name .. " /rolls")
      end
    end },
    { 6, "close", function()
      local ml = master()
      local cur = ml and ml.LR.Rolls.mine()
      if not cur or cur.state ~= "open" then return end
      local x = math.random(4)
      if x == 1 then ml.LR.Rolls.extend(10) step("+10 sec") elseif x == 2 then ml.LR.Rolls.cancel() step("call off") else ml.LR.Rolls.stop() step("close now") end
    end },
    { 18, "award", function()
      local ml = master()
      local cur = ml and ml.LR.Rolls.mine()
      if not cur or cur.state ~= "closed" then return end
      local top, tied = ml.LR.Roll.result(cur)
      local x = math.random(10)
      if tied and x <= 4 then ml.LR.Rolls.again("TIE") step("tie rolled again")
      elseif x == 5 then ml.LR.Rolls.again("OPEN") step("let everyone roll")
      elseif x == 6 and ml.LR.Session and cur.rolled then
        local keys = {}
        for _, e in pairs(cur.rolled) do keys[#keys + 1] = e.p end
        if #keys > 0 then ml.LR.Rolls.award(pick(keys)) totals.awards = totals.awards + 1 step("awarded to a pick") end
      elseif top then ml.LR.Rolls.award(top.p) totals.awards = totals.awards + 1 step("awarded to " .. top.p)
      else ml.LR.Rolls.cancel() step("nobody rolled: called off") end
    end },
    { 3, "undo", function()
      local ml = master()
      local cur = ml and ml.LR.Rolls.mine()
      if cur and cur.state == "awarded" then ml.LR.Rolls.undo() step("undo") end
    end },
    { 3, "give", function()
      local ml = master()
      if not ml then return end
      local cur = ml.LR.Rolls.mine()
      if cur and cur.state == "open" then return end
      if cur then ml.LR.Rolls.dismiss() end
      ml.LR.Rolls.give(pick(KARA), ml.LR.U.full(pick(NAMES)), pick({ "MS", "OS", "SR", "DE" }))
      step("given without a roll")
    end },
    { 3, "trade", function()
      local ml = master()
      local p = pick(raiders)
      if not ml or not online(p) or not inG(p) or ml == p then return end
      srv:openTrade(ml, p)
      srv:tick(0.3)
      if chance(0.5) then srv:setTradeMoney(p, math.random(0, 50000)) end
      if chance(0.8) then srv:completeTrade(ml) totals.trades = totals.trades + 1 step("trade with " .. p.name) else srv:cancelTrade(ml) step("trade cancelled") end
    end },
    -- people coming and going
    { 3, "leave", function()
      local p = pick(chance(0.6) and raiders or pugs)
      if p == groupLeader or not inG(p) then return end
      removeFrom(p)
      srv:leaveGroup(p)
      step(p.name .. " leaves the group")
    end },
    { 4, "join", function()
      local list = {}
      for _, p in ipairs(everyone) do if not inG(p) and (not p.client or online(p)) then list[#list + 1] = p end end
      if #list == 0 then return end
      local p = pick(list)
      inGroup[#inGroup + 1] = p
      setGroup()
      step(p.name .. " joins the group")
    end },
    { 3, "reload", function()
      local p = pick(chance(0.2) and { lead } or raiders)
      if not online(p) then return end
      saved[p] = srv:logout(p)
      totals.reloads = totals.reloads + 1
      step(p.name .. " logs out")
    end },
    { 5, "login", function()
      for p, db in pairs(saved) do
        srv:login(p, db)
        saved[p] = nil
        step(p.name .. " logs back in")
        return
      end
    end },
    -- the reserves change hands
    { 2, "hand over", function()
      local b = boss()
      local p = pick(raiders)
      if not b or b == p or not online(p) or not inG(p) then return end
      local s = b.LR.session(sid)
      local ok = b.LR.handOver(s, p.LR and b.LR.U.full(p.name) or nil)
      if ok then totals.handovers = totals.handovers + 1 end
      step(b.name .. " hands the reserves to " .. p.name .. (ok and "" or " (refused)"))
    end },
    { 2, "new raid leader", function()
      local p = pick(raiders)
      if not online(p) or not inG(p) then return end
      groupLeader = p
      setGroup()
      if chance(0.5) then srv:setMasterLooter(p) end
      step(p.name .. " is raid leader now")
    end },
    { 3, "take over", function()
      for _, p in ipairs(raiders) do
        if online(p) then
          local s = p.LR.session(sid)
          if s and p.LR.mayTakeOver(s) then
            p.LR.takeOver(s)
            totals.takeovers = totals.takeovers + 1
            step(p.name .. " takes the reserves over")
            return
          end
        end
      end
    end },
    { 2, "master looter", function()
      local list = {}
      for _, p in ipairs(inGroup) do if p.client and online(p) then list[#list + 1] = p end end
      if #list == 0 then return end
      local p = pick(list)
      srv:setMasterLooter(p)
      step(p.name .. " is master looter")
    end },
  }
  local weights = 0
  for _, a in ipairs(ACTIONS) do weights = weights + a[1] end
  local function anyAction()
    local x = math.random() * weights
    for _, a in ipairs(ACTIONS) do x = x - a[1] if x <= 0 then return a end end
    return ACTIONS[#ACTIONS]
  end

  local tracing = os.getenv("TRACEP")
  local function hookTrace(p)
    if not tracing or p.name ~= tracing or not online(p) then return end
    local H = p.LR.Net.handlers
    for _, k in ipairs({ "T", "U", "A", "E" }) do
      local orig = H[k]
      if orig and not H["traced" .. k] then
        H["traced" .. k] = true
        H[k] = function(msg, channel, sender)
          local c = p.LR.session(sid)
          local before = c and ("%s/%d"):format(c.leader:sub(1, 5), c.rev) or "-"
          orig(msg, channel, sender)
          local c2 = p.LR.session(sid)
          local s = msg.s
          io.stderr:write(("   [%s] %s from %s (%s) %s -> %s %s\n"):format(p.name, k, tostring(sender):sub(1, 6), channel,
            s and ("%s/%d"):format(s.leader:sub(1, 5), s.rev) or (k == "U" and ("f%s r%s"):format(tostring(msg.f), tostring(msg.r)) or ""),
            before, c2 and ("%s/%d"):format(c2.leader:sub(1, 5), c2.rev) or "-"))
        end
      end
    end
  end
  local function errorsCheck()
    for _, p in ipairs(withAddon) do
      if online(p) and #p.M.errors > 0 then
        problem("%s's LootRuler errored: %s", p.name, tostring(p.M.errors[1]):sub(1, 300))
        p.M.errors = {}
      end
    end
    for i = chatSeen + 1, #srv.chat do
      local m = srv.chat[i]
      if #m.text > 255 then problem("a chat line of %d characters from %s: %s", #m.text, tostring(m.from), m.text:sub(1, 80)) end
    end
    chatSeen = #srv.chat
  end

  local function settle()
    totals.settles = totals.settles + 1
    -- everyone back, the roll on now finished, and time for messages to arrive
    for p, db in pairs(saved) do srv:login(p, db) saved[p] = nil end
    local ml = master()
    local cur = ml and ml.LR.Rolls.mine()
    if cur and cur.state == "open" then ml.LR.Rolls.stop() srv:tick(3) end
    if cur and cur.state == "closed" then
      local top = ml.LR.Roll.result(cur)
      if top then ml.LR.Rolls.award(top.p) totals.awards = totals.awards + 1 end
    end
    -- the raid goes on: whoever runs the reserves in the group sends their copy (as their next change would)
    for _, p in ipairs(holder()) do if inG(p) then p.LR.publish(p.LR.session(sid), true) end end
    srv:tick(40, 0.5)
    -- anyone asked on their Session tab whether someone else runs the reserves now says yes, as players would
    local decided = false
    for _, p in ipairs(withAddon) do
      -- (a player picks once or twice a night, not every time someone says so: following both sides of a fork back
      -- and forth isn't something people do)
      p.followed = p.followed or 0
      if online(p) and p.LR.claim(sid) and p.followed < 2 then
        p.LR.followClaim(sid) p.followed = p.followed + 1 decided = true totals.claims = (totals.claims or 0) + 1
      end
    end
    if decided then srv:tick(40, 0.5) end
    errorsCheck()
    local h = {}
    for _, p in ipairs(holder()) do if inG(p) then h[#h + 1] = p end end
    if #h > 1 then
      local names = {}
      for _, p in ipairs(h) do names[#names + 1] = p.name end
      problem("%d players each think they run the reserves: %s", #h, table.concat(names, ", "))
    end
    local b = h[1]
    if not b then return end
    local s = b.LR.session(sid)
    local S, U = b.LR.Session, b.LR.U
    if not S.valid(U.copy(s)) then problem("the leader's session isn't valid") end
    for p, r in pairs(s.res) do
      if #r.i > S.limit(s, p) then problem("%s has %d reserves, over the limit of %d", p, #r.i, S.limit(s, p)) end
      for _, id in ipairs(r.i) do if s.hr[id] then problem("%s soft reserved a hard reserved item", p) end end
    end
    -- every raider in the group with LootRuler has the same copy (while its leader is in the group to hear from)
    for _, p in ipairs(inG(b) and raiders or {}) do
      if online(p) and inG(p) and p ~= b then
        local c = p.LR.session(sid)
        if not c then
          problem("%s, in the group with LootRuler, has no copy of the reserves", p.name)
        elseif (function()
          -- the same contents (the version number and time aside: a copy one number behind with the same contents
          -- takes the whole copy at the leader's next change)
          local a, b2 = U.copy(c), U.copy(s)
          a.rev, a.updated, b2.rev, b2.updated = nil, nil, nil, nil
          return not S.same(a, b2)
        end)() then
          problem("%s's copy differs from %s's (rev %s / %s; reserves %s, hard %s, given out %s; %s's copy names %s, next %s; leader's was %s)",
            p.name, b.name, tostring(c.rev), tostring(s.rev),
            tostring(S.same(c.res, s.res)), tostring(S.same(c.hr, s.hr)), tostring(S.same(c.won or {}, s.won or {})), p.name, tostring(c.leader),
            tostring(c.next), table.concat(s.was or {}, ",") .. "; first difference " .. tostring(where(c.res, s.res, "res") or where(c.won or {}, s.won or {}, "won") or where(c.hr, s.hr, "hr") or (function() local a, b2 = U.copy(c), U.copy(s) a.rev, a.updated, b2.rev, b2.updated = nil, nil, nil, nil return where(a, b2, "s") end)()))
        end
      end
    end
  end

  for i = 1, STEPS do
    local a = anyAction()
    for _, p in ipairs(raiders) do hookTrace(p) end
    if tracing then
      local tp
      for _, p in ipairs(raiders) do if p.name == tracing then tp = p end end
      local c = tp and online(tp) and tp.LR.session(sid)
      io.stderr:write(("%d %s   [%s holds %s %s/%s]\n"):format(i, a[2], tracing, c and tostring(c):sub(8) or "-", c and c.leader:sub(1, 5) or "-", c and tostring(c.rev) or "-"))
    end
    local ok, err = pcall(a[3])
    if not ok then problem("the chaos script itself failed on %s: %s", a[2], tostring(err)) end
    srv:tick(pick({ 0.1, 0.3, 0.5, 1, 2, 4 }), 0.1)
    errorsCheck()
    totals.steps = totals.steps + 1
    if i % 30 == 0 then settle() end
  end
  settle()
  -- end of the night: the session ends, everyone follows
  local b = boss()
  if b then
    b.LR.endSession(b.LR.session(sid))
    srv:tick(5)
    errorsCheck()
    for _, p in ipairs(raiders) do
      if online(p) and inG(p) then
        local c = p.LR.session(sid)
        if c and not c.ended and not c.archived then problem("%s's copy didn't end with the session", p.name) end
      end
    end
  end
  say("raid %d: %d steps done", r, STEPS)
 end
end

say("")
say("%d steps in %d raids: %d items rolled out (%d auctions), %d given out, %d trades, %d reloads, %d hand-overs, %d take-overs, %d unconfirmed take-overs followed, %d settles",
  totals.steps, RAIDS, totals.rolls, totals.auctions, totals.awards, totals.trades, totals.reloads, totals.handovers, totals.takeovers, totals.claims or 0, totals.settles)
if #problems == 0 then say("No problems found.") else
  say("%d problems:", #problems)
  for _, p in ipairs(problems) do say("  %s (%dx)", p, seen[p:gsub("%d+", "#"):sub(1, 140)] or 1) end
end
local f = assert(io.open("build/chaos.txt", "w"))
f:write(table.concat(lines, "\n"), "\n")
f:close()
os.exit(#problems == 0 and 0 or 1)
