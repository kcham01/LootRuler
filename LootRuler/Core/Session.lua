-- The rules of a soft reserve session. The raid leader's copy is the one that counts; everyone else gets
-- copies of it (Core/Net.lua). Nothing here talks to the game, so it's tested on its own (tests/session.lua).
--
-- A session:
--   id       unique: "<leader>:<time>"
--   rev      goes up by one with every change, so copies can tell which is newer
--   leader   "Name-Realm" of the raid leader who opened it
--   raid     raid key (LR.RAIDS)
--   sr       soft reserves each player gets
--   dupes    whether a player may put more than one of their reserves on the same item
--   locked   reserves can't be changed any more (the leader still can)
--   hr       hard reserves: item id -> { f = who it's for (may be ""), n = note (may be "") }
--   res      soft reserves: "Name-Realm" -> { c = class token ("PALADIN", may be nil), i = { item ids } }
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
  NOT_IN_RAID = "That item doesn't drop in this raid.",
  HARD_RESERVED = "That item is hard reserved.",
  TOO_MANY = "You have no reserves left.",
  DUPLICATE = "You can only reserve an item once in this raid.",
  NOT_RESERVED = "You haven't reserved that item.",
  BAD_COUNT = "That's not a number of reserves this addon allows.",
}

function S.new(leader, raidKey, sr, dupes, now)
  assert(LR.raid(raidKey), "unknown raid " .. tostring(raidKey))
  return {
    id = leader .. ":" .. now, rev = 1, leader = leader, raid = raidKey,
    sr = sr, dupes = dupes and true or false, locked = false,
    hr = {}, res = {}, created = now, updated = now,
  }
end

local function bump(s, now)
  s.rev = s.rev + 1
  s.updated = now or s.updated
end

--- whether a list of item ids is allowed for one player; false, reason, item id when not
function S.check(s, items)
  if #items > s.sr then return false, "TOO_MANY" end
  local seen = {}
  for _, id in ipairs(items) do
    if not LR.raidHas(s.raid, id) then return false, "NOT_IN_RAID", id end
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
  local ok, why, id = S.check(s, items)
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
  if not LR.raidHas(s.raid, id) then return false, "NOT_IN_RAID", id end
  if s.hr[id] then return false, "HARD_RESERVED", id end
  if #items >= s.sr then return false, "TOO_MANY", id end
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
  if not LR.raidHas(s.raid, id) then return false, "NOT_IN_RAID", id end
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

--- changes how many reserves each player gets and whether they can double up. Lists over the new limit lose
--- their last picks, and doubled-up picks go when doubling is switched off; returns the players affected.
function S.configure(s, sr, dupes, now)
  sr = tonumber(sr)
  if not sr or sr % 1 ~= 0 or sr < S.MIN_SR or sr > S.MAX_SR then return false, "BAD_COUNT" end
  local touched = {}
  s.sr, s.dupes = sr, dupes and true or false
  for player, r in pairs(s.res) do
    local keep, seen = {}, {}
    for _, id in ipairs(r.i) do
      if #keep < sr and (s.dupes or not seen[id]) then keep[#keep + 1] = id end
      seen[id] = true
    end
    if #keep ~= #r.i then touched[#touched + 1] = player r.i = keep end
  end
  table.sort(touched)
  bump(s, now)
  return true, touched
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
  for player, r in pairs(s.res) do out[#out + 1] = { name = player, class = r.c, items = r.i, left = s.sr - #r.i } end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

--- a session from another player, checked before it's trusted: right shape, known raid, sane numbers
function S.valid(t)
  if type(t) ~= "table" or type(t.id) ~= "string" or type(t.leader) ~= "string" or type(t.rev) ~= "number" then return false end
  if not LR.raid(t.raid) or type(t.sr) ~= "number" or t.sr < S.MIN_SR or t.sr > S.MAX_SR then return false end
  if type(t.hr) ~= "table" or type(t.res) ~= "table" then return false end
  for id, h in pairs(t.hr) do if type(id) ~= "number" or type(h) ~= "table" then return false end end
  for name, r in pairs(t.res) do
    if type(name) ~= "string" or type(r) ~= "table" or type(r.i) ~= "table" then return false end
    for _, id in ipairs(r.i) do if type(id) ~= "number" then return false end end
  end
  return true
end
