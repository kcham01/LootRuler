-- The rules of a soft reserve session. The raid leader's copy is the one that counts; everyone else gets
-- copies of it (Core/Net.lua). Nothing here talks to the game, so it's tested on its own (tests/session.lua).
--
-- A session:
--   id       unique: "<leader>:<time>"
--   rev      goes up by one with every change, so copies can tell which is newer
--   leader   "Name-Realm" of the raid leader who opened it
--   raid     raid key (LR.RAIDS), or LR.CUSTOM for a raid that isn't in the built-in lists
--   raidName the raid's name (so a version that doesn't know the raid can still show it)
--   any      any item may be reserved, not just the raid's own loot (always, for a raid not in the lists)
--   sr       soft reserves each player gets
--   dupes    whether a player may put more than one of their reserves on the same item
--   locked   reserves can't be changed any more (the leader still can)
--   hr       hard reserves: item id -> { f = who it's for (may be ""), n = note (may be "") }
--   res      soft reserves: "Name-Realm" -> { c = class token ("PALADIN", may be nil), i = { item ids } }
--   won      loot given out while the session was open (Core/Rolls.lua), oldest first:
--            { i = item id, p = "Name-Realm", k = "SR" / "MS" / "OS" / "HR" (how it was won), r = the roll, at = time,
--              d = the drop it was (its key, when known), de = to disenchant, br = won with a boosted roll (k "MS") }
--            A reserve that has won its item is used up: it doesn't count when another copy drops.
--   de       the disenchanter ("Name-Realm"): items nobody wants go to them. Their awards are kind "OS" with
--            de = true, so versions that don't know about disenchanting still read them.
--   plusOne  the +1 rule is on: items won on main spec rolls count against the winner in later rolls
--   prio     the guild's priority lists decide loot: "both" (priority lists first, then reserves) or "only"
--            (no reserves); nil: reserves only
--   sx, hx   what the last import from softres.it brought: "Name-Realm" -> items, and hard reserved items
--            (so importing an updated sheet replaces them; Core/Gargul.lua)
--   nm       names on the softres.it sheet that are a character spelled differently: sheet "Name-Realm" -> the
--            character's "Name-Realm" (so later imports go to them too)
--   xr       "Name-Realm" -> extra reserves the leader gave that player (tanks, healers...), on top of sr
--   gdkp     items are auctioned for gold (Core/Gdkp.lua); gk: its settings, who's in the pot, what's been paid
--   boost    boosted rolls are on: guild members roll with their guild points added (Core/Book.lua)
--   po       +1 changes the leader made by hand: "Name-Realm" -> number (added to the counted ones)
--   drops    every item that dropped while the session was open, in order (Core/Drops.lua):
--            { k = key, i = item id, b = boss ("" when not known), at = when it dropped, by = who recorded it (the
--              loot master), src = what it dropped from, h = who has it now (nil: still on the corpse),
--              ht = when it went into h's bags (the game's 2 hours to trade it start then) }
--   next     (while being handed over) "Name-Realm" the leader handed the session to; their addon takes it
--   was      who led the session before, oldest first ("Name-Realm"; the session went on with the same id)
--   created, updated   server times
local _, LR = ...
local U = LR.U
local S = {}
LR.Session = S

S.MIN_SR, S.MAX_SR = 1, 10

--- what each refusal means, for messages
S.WHY = {
  LOCKED = "Reserves are locked.",
  NO_SESSION = "There are no soft reserves open.",
  NOT_IN_RAID = "That item doesn't drop in this raid (the leader can allow any item).",
  HARD_RESERVED = "That item is hard reserved.",
  TOO_MANY = "You have no reserves left.",
  DUPLICATE = "You can only reserve an item once in this raid.",
  NOT_RESERVED = "You haven't reserved that item.",
  BAD_COUNT = "That's not a number of reserves this addon allows.",
  PRIO_ONLY = "This raid goes by the guild's priority lists, not reserves.",
  GDKP = "This raid auctions its loot for gold (GDKP): there are no reserves.",
}

--- a new session. raidKey: a built-in raid, or LR.CUSTOM with name (a raid that isn't in the lists).
function S.new(leader, raidKey, sr, dupes, now, name, any)
  local known = LR.raid(raidKey)
  assert(known or raidKey == LR.CUSTOM, "unknown raid " .. tostring(raidKey))
  name = known and known.name or U.trim(name or ""):sub(1, 40)
  return {
    id = leader .. ":" .. now, rev = 1, leader = leader, raid = raidKey, raidName = name ~= "" and name or "Raid",
    any = (any or not known) and true or false,
    sr = sr, dupes = dupes and true or false, locked = false,
    hr = {}, res = {}, created = now, updated = now,
  }
end

local function bump(s, now)
  s.rev = s.rev + 1
  s.updated = now or s.updated
end
S.bump = bump

--- how many reserves a player gets: everyone's, plus any extra the leader gave them
function S.limit(s, player)
  local extra = player and s.xr and s.xr[U.full(player)] or 0
  return s.sr + extra
end
function S.extra(s, player) return s.xr and s.xr[U.full(player)] or 0 end

--- whether a list of item ids is allowed for one player; false, reason, item id when not. lenient: leave
--- which items are allowed to the leader's addon (a raider's addon checking before it asks)
function S.check(s, items, lenient, player)
  if #items > S.limit(s, player) then return false, "TOO_MANY" end
  local seen = {}
  for _, id in ipairs(items) do
    if not LR.allowedItem(s, id, lenient) then return false, "NOT_IN_RAID", id end
    if s.hr[id] then return false, "HARD_RESERVED", id end
    if seen[id] and not s.dupes then return false, "DUPLICATE", id end
    seen[id] = true
  end
  return true
end

function S.reservesOf(s, player)
  local r = s.res[player]
  return r and r.i or {}
end

--- replaces a player's reserves. byLeader: the leader is making the change (allowed while locked).
--- Returns true (changed or not), or false and the reason.
function S.set(s, player, class, items, byLeader, now)
  if s.locked and not byLeader then return false, "LOCKED" end
  if s.prio == "only" and #items > 0 and not byLeader then return false, "PRIO_ONLY" end
  if s.gdkp and #items > 0 and not byLeader then return false, "GDKP" end
  local ok, why, id = S.check(s, items, nil, player)
  if not ok then return false, why, id end
  local cur = s.res[player]
  if #items == 0 then
    if cur then s.res[player] = nil bump(s, now) end
    return true
  end
  local same = cur and U.sameList(cur.i, items) and (class == nil or cur.c == class)
  if not same then
    s.res[player] = { c = class or (cur and cur.c), i = U.copy(items) }
    bump(s, now)
  end
  return true
end

--- adds one reserve on an item for a player
function S.add(s, player, class, id, byLeader, now)
  local items = U.copy(S.reservesOf(s, player))
  if s.locked and not byLeader then return false, "LOCKED" end
  if s.prio == "only" and not byLeader then return false, "PRIO_ONLY" end
  if s.gdkp and not byLeader then return false, "GDKP" end
  if not LR.allowedItem(s, id) then return false, "NOT_IN_RAID", id end
  if s.hr[id] then return false, "HARD_RESERVED", id end
  if #items >= S.limit(s, player) then return false, "TOO_MANY", id end
  if not s.dupes and U.indexOf(items, id) then return false, "DUPLICATE", id end
  items[#items + 1] = id
  return S.set(s, player, class, items, byLeader, now)
end

--- takes one reserve on an item away from a player
function S.remove(s, player, id, byLeader, now)
  if s.locked and not byLeader then return false, "LOCKED" end
  local items = U.copy(S.reservesOf(s, player))
  local i = U.indexOf(items, id)
  if not i then return false, "NOT_RESERVED", id end
  table.remove(items, i)
  local cur = s.res[player]
  if #items == 0 then s.res[player] = nil else s.res[player] = { c = cur.c, i = items } end
  bump(s, now)
  return true
end

--- hard reserves an item (for someone, with a note: both optional). Soft reserves on it are taken away;
--- returns the players who lost one.
function S.setHR(s, id, forWho, note, now)
  if not LR.allowedItem(s, id) then return false, "NOT_IN_RAID", id end
  s.hr[id] = { f = U.trim(forWho or ""), n = U.trim(note or "") }
  local lost = {}
  for player, r in pairs(s.res) do
    local keep = U.filter(r.i, function(x) return x ~= id end)
    if #keep ~= #r.i then
      lost[#lost + 1] = player
      if #keep == 0 then s.res[player] = nil else r.i = keep end
    end
  end
  table.sort(lost)
  bump(s, now)
  return true, lost
end

function S.clearHR(s, id, now)
  if not s.hr[id] then return false end
  s.hr[id] = nil
  bump(s, now)
  return true
end

---------------------------------------------------------------------- a new leader
--- the leader hands the session to someone; their addon takes it over when it hears (nil: the offer is taken back)
function S.handTo(s, player, now)
  player = player and U.full(player) or nil
  if player and U.samePlayer(player, s.leader) then return false end
  if s.next == player then return false end
  s.next = player
  bump(s, now)
  return true
end

--- someone else leads the session from now on (it was handed to them, or they took it over); everything in it
--- stays, and the old leader goes on the list of who led it
function S.newLeader(s, player, now)
  player = U.full(player)
  if not player or U.samePlayer(player, s.leader) then return false end
  s.was = s.was or {}
  s.was[#s.was + 1] = s.leader
  while #s.was > 10 do table.remove(s.was, 1) end
  s.leader = player
  s.next = nil
  bump(s, now)
  return true
end

--- whether a copy of a session that names a different leader may replace the one we have: it was handed to
--- them, or they took it over. gone: our copy's leader isn't in the group (or is offline); boss: the one who sent
--- it leads or assists the group (the game says so); ours: we lead it; fromUs: their copy says it carried on
--- from us; newer: their copy is newer than ours. When it's ours, only a newer copy can take it from us (we were
--- away, and it was taken over, or taken over and handed on): an old copy someone kept never wins it back.
function S.newLeaderOk(known, leader, gone, boss, ours, fromUs, newer)
  if known.next and U.samePlayer(known.next, leader) then return true end
  if ours then return (newer and (boss or fromUs)) and true or false end
  return (boss and gone) and true or false
end
--- whether a session says it was led by a player before
function S.ledBy(s, player)
  for _, name in ipairs(s.was or {}) do if U.samePlayer(name, player) then return true end end
  return false
end

S.MAX_EXTRA = 5

--- gives a player extra reserves (0 takes them away; their last picks over the new limit go). Returns whether
--- anything changed, and whether they lost reserves.
function S.setExtra(s, player, n, now)
  n = tonumber(n)
  if not n or n % 1 ~= 0 or n < 0 or n > S.MAX_EXTRA then return false end
  player = U.full(player)
  if S.extra(s, player) == n then return false end
  s.xr = s.xr or {}
  s.xr[player] = n > 0 and n or nil
  local lost = false
  local r = s.res[player]
  if r and #r.i > S.limit(s, player) then
    while #r.i > S.limit(s, player) do table.remove(r.i) end
    lost = true
  end
  bump(s, now)
  return true, lost
end

--- changes how many reserves each player gets and whether they can double up. Lists over the new limit lose
--- their last picks, and doubled-up picks go when doubling is switched off; returns the players affected.
function S.configure(s, sr, dupes, now)
  sr = tonumber(sr)
  if not sr or sr % 1 ~= 0 or sr < S.MIN_SR or sr > S.MAX_SR then return false, "BAD_COUNT" end
  local touched = {}
  s.sr, s.dupes = sr, dupes and true or false
  for player, r in pairs(s.res) do
    local keep, seen = {}, {}
    local limit = S.limit(s, player)
    for _, id in ipairs(r.i) do
      if #keep < limit and (s.dupes or not seen[id]) then keep[#keep + 1] = id end
      seen[id] = true
    end
    if #keep ~= #r.i then touched[#touched + 1] = player r.i = keep end
  end
  table.sort(touched)
  bump(s, now)
  return true, touched
end

--- whether any item may be reserved (a raid that isn't in the lists always allows any)
function S.setAny(s, any, now)
  any = (any or not LR.raid(s.raid)) and true or false
  if s.any == any then return false end
  s.any = any
  bump(s, now)
  return true
end

function S.setLocked(s, locked, now)
  locked = locked and true or false
  if s.locked == locked then return false end
  s.locked = locked
  bump(s, now)
  return true
end

--- every reserved item: id -> { { name, count } ... } (names sorted)
function S.byItem(s)
  local out = {}
  for player, r in pairs(s.res) do
    local n = {}
    for _, id in ipairs(r.i) do n[id] = (n[id] or 0) + 1 end
    for id, c in pairs(n) do
      out[id] = out[id] or {}
      table.insert(out[id], { player, c })
    end
  end
  for _, list in pairs(out) do table.sort(list, function(a, b) return a[1] < b[1] end) end
  return out
end

--- players (sorted) and how many reserves each has left
function S.players(s)
  local out = {}
  for player, r in pairs(s.res) do out[#out + 1] = { name = player, class = r.c, items = r.i, left = S.limit(s, player) - #r.i } end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

---------------------------------------------------------------------- loot given out
S.WON_KINDS = { SR = true, MS = true, OS = true, HR = true, BID = true }

--- records that a player was given an item (kind: how they won it, roll: what they rolled, if they did).
--- dropKey: the drop it was; when not given, the first drop of that item nobody has won yet.
function S.award(s, id, player, kind, roll, now, dropKey, de, boosted)
  if type(id) ~= "number" or type(player) ~= "string" or not S.WON_KINDS[kind] then return false end
  local d = dropKey and S.drop(s, dropKey) or S.openDrops(s, id)[1]
  if d and d.i ~= id then d = nil end
  s.won = s.won or {}
  s.won[#s.won + 1] = { i = id, p = player, k = kind, r = tonumber(roll), at = now, d = d and d.k or nil, de = de and true or nil,
    br = boosted and true or nil }
  bump(s, now)
  return true
end

--- takes back a record of loot given out (a mistake), by its place in the list
function S.unaward(s, index, now)
  if not s.won or not s.won[index] then return false end
  table.remove(s.won, index)
  bump(s, now)
  return true
end

--- the place in the list of loot given out of a player's latest award of an item (from a drop, when known), or nil
function S.findAward(s, id, player, dropKey)
  for i = #(s.won or {}), 1, -1 do
    local w = s.won[i]
    if w.i == id and U.samePlayer(w.p, player) and (not dropKey or not w.d or w.d == dropKey) then return i end
  end
end

--- how many times a player has won an item on a soft reserve
function S.srWins(s, player, id)
  local n = 0
  for _, w in ipairs(s.won or {}) do
    if w.i == id and w.k == "SR" and U.samePlayer(w.p, player) then n = n + 1 end
  end
  return n
end

--- a player's reserves on an item that haven't won it yet
function S.claims(s, player, id)
  local n = 0
  for _, x in ipairs(S.reservesOf(s, player)) do if x == id then n = n + 1 end end
  return math.max(0, n - S.srWins(s, player, id))
end

--- who has been given an item: { { name, kind }, ... } in the order it was given
function S.winners(s, id)
  local out = {}
  for _, w in ipairs(s.won or {}) do if w.i == id then out[#out + 1] = { w.p, w.de and "DE" or w.k } end end
  return out
end

--- who disenchants (nil: nobody)
function S.setDisenchanter(s, player, now)
  player = type(player) == "string" and player ~= "" and U.full(player) or nil
  if s.de == player then return false end
  s.de = player
  bump(s, now)
  return true
end

---------------------------------------------------------------------- +1s
--- whether the +1 rule is on
function S.setPlusOne(s, on, now)
  on = on and true or false
  if (s.plusOne or false) == on then return false end
  s.plusOne = on
  bump(s, now)
  return true
end

--- how loot is decided: nil (reserves), "both" (the guild's priority lists, then reserves) or "only"
function S.setPrio(s, mode, now)
  if mode ~= "both" and mode ~= "only" then mode = nil end
  if s.prio == mode then return false end
  s.prio = mode
  bump(s, now)
  return true
end

--- whether boosted rolls are on (players with guild points can roll 1+points to 100+points on main spec)
function S.setBoost(s, on, now)
  on = on and true or false
  if (s.boost or false) == on then return false end
  s.boost = on
  bump(s, now)
  return true
end

--- a player's +1s: an item won on a main spec roll is one, plus the leader's changes by hand (never below 0)
function S.plusOnes(s, player)
  local n = 0
  for _, w in ipairs(s.won or {}) do if w.k == "MS" and U.samePlayer(w.p, player) then n = n + 1 end end
  for name, d in pairs(s.po or {}) do if U.samePlayer(name, player) then n = n + d end end
  return math.max(0, n)
end

--- the leader gives a player a +1 (delta 1) or takes one off (delta -1)
function S.adjustPlusOne(s, player, delta, now)
  if type(player) ~= "string" or (delta ~= 1 and delta ~= -1) then return false end
  if delta < 0 and S.plusOnes(s, player) == 0 then return false end
  s.po = s.po or {}
  local key = U.full(player)
  for name in pairs(s.po) do if U.samePlayer(name, player) then key = name end end
  s.po[key] = (s.po[key] or 0) + delta
  if s.po[key] == 0 then s.po[key] = nil end
  bump(s, now)
  return true
end

--- sets a player's +1s to a number (brought in from Gargul, say): the change is kept on top of what they won
function S.setPlusOnes(s, player, n, now)
  n = tonumber(n)
  if type(player) ~= "string" or not n or n < 0 or n > 99 or n % 1 ~= 0 then return false end
  local won = 0
  for _, w in ipairs(s.won or {}) do if w.k == "MS" and U.samePlayer(w.p, player) then won = won + 1 end end
  s.po = s.po or {}
  for name in pairs(s.po) do if U.samePlayer(name, player) then s.po[name] = nil end end
  if n - won ~= 0 then s.po[U.full(player)] = n - won end
  bump(s, now)
  return true
end

--- everyone's +1s, for a roll (lower-case names; only those with any)
function S.plusOneTable(s, names)
  local out = {}
  for _, name in ipairs(names) do
    local n = S.plusOnes(s, name)
    if n > 0 then out[U.full(name):lower()] = n end
  end
  return out
end

---------------------------------------------------------------------- the raid's drops
S.MAX_DROPS = 300

function S.drop(s, k)
  for _, d in ipairs(s.drops or {}) do if d.k == k then return d end end
end

--- the last award of a drop, or nil
function S.dropWin(s, k)
  local won = s.won or {}
  for i = #won, 1, -1 do if won[i].d == k then return won[i], i end end
end

--- drops of an item that nobody has won yet, in the order they dropped
function S.openDrops(s, id)
  local out = {}
  for _, d in ipairs(s.drops or {}) do if d.i == id and not S.dropWin(s, d.k) then out[#out + 1] = d end end
  return out
end

local function str(v) return type(v) == "string" and v or nil end

--- adds a drop, or brings a known one (same key) up to date with who has it now. Returns whether anything changed.
function S.addDrop(s, d, now)
  if type(d) ~= "table" or type(d.k) ~= "string" or type(d.i) ~= "number" then return false end
  local known = S.drop(s, d.k)
  if known then
    local h = str(d.h)
    if not h or h == known.h then return false end
    known.h, known.ht = h, tonumber(d.ht) or known.ht
    bump(s, now)
    return true
  end
  s.drops = s.drops or {}
  if #s.drops >= S.MAX_DROPS then return false end
  s.drops[#s.drops + 1] = { k = d.k, i = d.i, b = str(d.b) or "", at = tonumber(d.at) or now, by = str(d.by), src = str(d.src),
    h = str(d.h), ht = tonumber(d.ht) }
  bump(s, now)
  return true
end

--- takes a drop off the list (a mistake); an award for it stays, without the link to it
function S.removeDrop(s, k, now)
  for i, d in ipairs(s.drops or {}) do
    if d.k == k then
      table.remove(s.drops, i)
      for _, w in ipairs(s.won or {}) do if w.d == k then w.d = nil end end
      bump(s, now)
      return true
    end
  end
  return false
end

--- where a drop is: "corpse" (nobody has it yet), "held" (the loot master has it, to roll out), "looted" (someone
--- else has it, not through LootRuler), "toTrade" (won, and the loot master still has it to trade), "given".
--- Also the award, when there is one.
function S.dropState(s, d)
  local w = S.dropWin(s, d.k)
  if w then
    if d.h and not U.samePlayer(d.h, w.p) and (not d.by or U.samePlayer(d.h, d.by)) then return "toTrade", w end
    return "given", w
  end
  if not d.h then return "corpse" end
  if d.by and U.samePlayer(d.h, d.by) then return "held" end
  return "looted"
end

--- a session from another player, checked before it's trusted: right shape, known raid, sane numbers
function S.valid(t)
  if type(t) ~= "table" or type(t.id) ~= "string" or type(t.leader) ~= "string" or type(t.rev) ~= "number" then return false end
  -- a raid this version doesn't know (a newer version's, or one the leader named) is fine: it's shown by name
  if type(t.raid) ~= "string" or (t.raidName ~= nil and type(t.raidName) ~= "string") then return false end
  -- a newer version may allow more reserves than this one offers: only nonsense is refused
  if type(t.sr) ~= "number" or t.sr < S.MIN_SR or t.sr > 40 or t.sr % 1 ~= 0 then return false end
  if type(t.hr) ~= "table" or type(t.res) ~= "table" then return false end
  if t.won ~= nil then
    if type(t.won) ~= "table" then return false end
    for _, w in ipairs(t.won) do
      -- a kind this version doesn't know (a newer version's) is kept and shown as it is
      if type(w) ~= "table" or type(w.i) ~= "number" or type(w.p) ~= "string" or type(w.k) ~= "string" or #w.k > 12 then return false end
    end
  end
  if t.de ~= nil and type(t.de) ~= "string" then return false end
  if t.next ~= nil and type(t.next) ~= "string" then return false end
  if t.was ~= nil then
    if type(t.was) ~= "table" or #t.was > 20 then return false end
    for _, name in ipairs(t.was) do if type(name) ~= "string" then return false end end
  end
  if t.xr ~= nil then
    if type(t.xr) ~= "table" then return false end
    local n = 0
    for name, x in pairs(t.xr) do
      n = n + 1
      if n > 80 or type(name) ~= "string" or type(x) ~= "number" or x < 0 or x > 40 then return false end
    end
  end
  if t.boost ~= nil and type(t.boost) ~= "boolean" then return false end
  -- what an import from softres.it brought (Core/Gargul.lua): players' items, and hard reserves
  if t.sx ~= nil then
    if type(t.sx) ~= "table" then return false end
    local n = 0
    for name, ids in pairs(t.sx) do
      n = n + 1
      if n > 200 or type(name) ~= "string" or type(ids) ~= "table" or #ids > 50 then return false end
      for _, id in ipairs(ids) do if type(id) ~= "number" then return false end end
    end
  end
  if t.nm ~= nil then
    if type(t.nm) ~= "table" then return false end
    local n = 0
    for from, to in pairs(t.nm) do
      n = n + 1
      if n > 200 or type(from) ~= "string" or type(to) ~= "string" then return false end
    end
  end
  if t.hx ~= nil then
    if type(t.hx) ~= "table" or #t.hx > 200 then return false end
    for _, id in ipairs(t.hx) do if type(id) ~= "number" then return false end end
  end
  if t.gdkp ~= nil and type(t.gdkp) ~= "boolean" then return false end
  if LR.Gdkp and not LR.Gdkp.valid(t.gk) then return false end
  -- (a way of deciding loot this version doesn't know is kept, and treated as reserves)
  if t.prio ~= nil and (type(t.prio) ~= "string" or #t.prio > 12) then return false end
  if t.po ~= nil then
    if type(t.po) ~= "table" then return false end
    for name, n in pairs(t.po) do if type(name) ~= "string" or type(n) ~= "number" then return false end end
  end
  if t.drops ~= nil then
    if type(t.drops) ~= "table" or #t.drops > S.MAX_DROPS then return false end
    for _, d in ipairs(t.drops) do
      if type(d) ~= "table" or type(d.k) ~= "string" or type(d.i) ~= "number" or type(d.b) ~= "string" then return false end
    end
  end
  for id, h in pairs(t.hr) do if type(id) ~= "number" or type(h) ~= "table" then return false end end
  for name, r in pairs(t.res) do
    if type(name) ~= "string" or type(r) ~= "table" or type(r.i) ~= "table" then return false end
    for _, id in ipairs(r.i) do if type(id) ~= "number" then return false end end
  end
  return true
end
