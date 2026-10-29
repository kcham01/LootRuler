-- Reserve swap requests: once reserves are locked, a raider asks the leader to swap one of their reserves for another
-- item (their Reserve tab, or a whisper: "!lr swap [old] [new]", "!lr swap old for new"). The leader sees the requests on
-- the Reserves tab and allows or refuses each; either way the raider is told by whisper. A swap is checked like any
-- reserve (hard reserves, one each per item, the raid's loot) and can't half-happen. One request per player at a time.
--
-- Messages (on top of Core/Net.lua's):
--   S  raider -> leader   { id = session, f = the reserve to give up, n = the item they'd like instead } (answered by whisper)
-- Older leaders don't know it: a raider's addon only offers it when the leader's says it takes swaps (fl, Core/Net.lua).
local _, LR = ...
local U, S = LR.U, LR.Session
local Net = LR.Net

local Sw = { list = {}, mine = {} }
LR.Swap = Sw

--- the leader's requests waiting for a session: { { p, from, to, at } }
function Sw.pending(s)
  local out = {}
  for _, r in ipairs(Sw.list) do if r.sid == s.id then out[#out + 1] = r end end
  return out
end

local function tell(player, text)
  if U.samePlayer(player, U.me()) then LR.print(text) return end
  LR.say(LR.TAG .. " " .. text, "WHISPER", player)
end

--- a request comes in (the leader's addon); returns true, or false and why not (said back to them by the caller)
function Sw.ask(s, player, from, to)
  player = U.full(player)
  if not (s and LR.isLeader(s)) then return false, "Only the leader takes swap requests." end
  if not s.locked then return false, "Reserves aren't locked: change your reserves yourself." end
  if type(from) ~= "number" or type(to) ~= "number" or from == to then return false, "Say the reserve you'd give up and the item you'd like instead." end
  if not U.indexOf(S.reservesOf(s, player), from) then return false, ("You haven't reserved %s."):format(LR.itemLink(from)) end
  if not LR.allowedItem(s, to) then return false, ("%s doesn't drop in %s."):format(LR.itemLink(to), LR.raidOf(s).name) end
  if s.hr[to] then return false, ("%s is hard reserved."):format(LR.itemLink(to)) end
  for i = #Sw.list, 1, -1 do
    if Sw.list[i].sid == s.id and U.samePlayer(Sw.list[i].p, player) then table.remove(Sw.list, i) end   -- (one each: the new one counts)
  end
  table.insert(Sw.list, { sid = s.id, p = player, from = from, to = to, at = U.now() })
  if not U.samePlayer(player, U.me()) then
    LR.print(("%s asks to swap %s for %s: allow it on the All reserves tab."):format(U.short(player), LR.itemLink(from), LR.itemLink(to)))
  end
  LR.changed("swaps")
  return true
end

--- the leader allows a request: the swap is made as one change, or refused if it breaks the rules now
function Sw.allow(s, r)
  local items = U.copy(S.reservesOf(s, r.p))
  local i = U.indexOf(items, r.from)
  local why
  if not i then why = "they don't have that reserve any more"
  else
    items[i] = r.to
    local ok, w = S.set(s, r.p, s.res[r.p] and s.res[r.p].c or LR.classOf(r.p), items, true, U.now())
    if ok then
      LR.leaderChanged(s)
    else why = S.WHY[w] or tostring(w) end
  end
  for j = #Sw.list, 1, -1 do if Sw.list[j] == r then table.remove(Sw.list, j) end end
  if why then
    tell(r.p, ("Your swap of %s for %s couldn't be made: %s."):format(LR.itemLink(r.from), LR.itemLink(r.to), why:gsub("%.$", "")))
    LR.changed("swaps")
    return false, why
  end
  tell(r.p, ("Your swap is done: %s instead of %s."):format(LR.itemLink(r.to), LR.itemLink(r.from)))
  LR.changed("swaps")
  return true
end

--- the leader says no
function Sw.deny(s, r)
  for j = #Sw.list, 1, -1 do if Sw.list[j] == r then table.remove(Sw.list, j) end end
  tell(r.p, ("%s said no to swapping %s for %s."):format(U.short(s.leader), LR.itemLink(r.from), LR.itemLink(r.to)))
  LR.changed("swaps")
  return true
end

--- I ask (my Reserve tab): to the leader's addon, or my own when I'm the leader
function Sw.request(s, from, to)
  if not s or not s.locked then return false, "Reserves aren't locked: change your reserves yourself." end
  if LR.isLeader(s) then return Sw.ask(s, U.me(), from, to) end
  local m = LR.inGroup(s.leader)
  if not (m and m.online) then return false, ("%s isn't in the group right now."):format(U.short(s.leader)) end
  if not LR.hasFeature(s.leader, LR.FEATURE_SWAP) then
    return false, ("%s's LootRuler is too old for swap requests: whisper them \"!lr swap\" with both items."):format(U.short(s.leader))
  end
  Net.send({ t = "S", id = s.id, f = from, n = to }, "WHISPER", s.leader)
  Sw.mine[s.id] = { from = from, to = to }
  LR.changed("swaps")
  return true
end

Net.handlers.S = function(msg, channel, sender)
  if channel ~= "WHISPER" or type(msg.id) ~= "string" then return end
  local s = LR.session(msg.id)
  if not (s and LR.isLeader(s)) then return end
  local ok, why = Sw.ask(s, sender, tonumber(msg.f), tonumber(msg.n))
  tell(sender, ok and ("Your swap request is in: %s for %s. %s decides."):format(LR.itemLink(tonumber(msg.f)), LR.itemLink(tonumber(msg.n)), U.short(U.me())) or why)
end

-- a request I made is answered (or the session changes): forget it once my reserves show the swap, or it's unlocked
LR.onChange(function(what)
  if what ~= "session" then return end
  for sid, r in pairs(Sw.mine) do
    local s = LR.session(sid)
    if not s or not s.locked or U.indexOf(S.reservesOf(s, U.me()), r.to) then Sw.mine[sid] = nil end
  end
end)
