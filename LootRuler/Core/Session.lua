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
--              d = the drop it was (its key, when known), de = to disenchant, br = won with a boosted roll (k "MS"),
--              xn = won on one of the loot master's own roll types, by its name (k "OS") }
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
--   go       only players in the group can reserve for themselves (the leader can still add for anyone, and imports
--            still come in); nil or false: anyone the session reaches can (guild members before the raid forms)
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
  HARD_RESERVED = "It's hard reserved, so it can't be soft reserved.",
  TOO_MANY = "You have no reserves left.",
  DUPLICATE = "You can only reserve an item once in this raid.",
  NOT_RESERVED = "You haven't reserved that item.",
  BAD_COUNT = "That's not a number of reserves this addon allows.",
  PRIO_ONLY = "This raid goes by the guild's priority lists, not reserves.",
  GDKP = "This raid auctions its loot for gold (GDKP): there are no reserves.",
  GROUP_ONLY = "Only players in the group can reserve. Ask for an invite first.",
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

---------------------------------------------------------------------- who can reserve
--- whether a player may change their reserves to items: when only the group can reserve, someone outside it can
--- take reserves back but not add any. inGroup: whether they're in the group (the game says so)
function S.groupOk(s, player, items, inGroup)
  if not s.go or inGroup then return true end
  local have = {}
  for _, id in ipairs(S.reservesOf(s, player)) do have[id] = (have[id] or 0) + 1 end
  for _, id in ipairs(items) do
    if (have[id] or 0) > 0 then have[id] = have[id] - 1 else return false, "GROUP_ONLY" end
  end
  return true
end
--- switches "only players in the group can reserve" on or off
function S.setGroupOnly(s, on, now)
  on = on and true or false
  if (s.go or false) == on then return false end
  s.go = on
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

--- every reserved item: id -> { { name, count } ... } (names sorted). Kept from one call to the next until the reserves
--- change, so looking up one item at a time (S.byItem(s)[id]) is cheap: don't change what it returns.
local byItemKept = setmetatable({}, { __mode = "k" })     -- session -> { res, lists, counts, n, out }
--- whether what was kept still matches: every change to a player's reserves puts a new list in s.res, or changes its length
local function stillSame(k, s)
  if k.res ~= s.res then return false end
  local n = 0
  for player, r in pairs(s.res) do
    n = n + 1
    if k.lists[player] ~= r.i or k.counts[player] ~= #r.i then return false end
  end
  return n == k.n
end
function S.byItem(s)
  local k = byItemKept[s]
  if k and stillSame(k, s) then return k.out end
  local out = {}
  k = { res = s.res, lists = {}, counts = {}, n = 0, out = out }
  for player, r in pairs(s.res) do
    k.lists[player], k.counts[player], k.n = r.i, #r.i, k.n + 1
    local n = {}
    for _, id in ipairs(r.i) do n[id] = (n[id] or 0) + 1 end
    for id, c in pairs(n) do
      out[id] = out[id] or {}
      table.insert(out[id], { player, c })
    end
  end
  for _, list in pairs(out) do table.sort(list, function(a, b) return a[1] < b[1] end) end
  byItemKept[s] = k
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

--- the session's softres.it page (posted in raid chat for players to reserve there); nil or "" takes it off
S.LINK_MAX = 100
function S.okLink(url) return type(url) == "string" and #url <= S.LINK_MAX and url:match("^https://softres%.it/[%w%-/]+$") ~= nil end
function S.setLink(s, url, now)
  url = url and U.trim(url) or ""
  if url ~= "" and not S.okLink(url) then return false end
  if (s.url or "") == url then return false end
  s.url = url ~= "" and url or nil
  bump(s, now)
  return true
end

---------------------------------------------------------------------- reserves of players who aren't here
--- who has reserves but isn't in the group: inGroup(name) says who is. Sorted names.
function S.absent(s, inGroup)
  local out = {}
  for name, r in pairs(s.res) do if #(r.i or {}) > 0 and not inGroup(name) then out[#out + 1] = name end end
  table.sort(out)
  return out
end
--- clears those players' reserves (the leader); returns the names cleared
function S.clearAbsent(s, inGroup, now)
  local cleared = {}
  for _, name in ipairs(S.absent(s, inGroup)) do
    if S.set(s, name, nil, {}, true, now) then
      cleared[#cleared + 1] = name
      if s.sx then s.sx[name] = nil end          -- (what the last import brought them: a new import brings it back)
    end
  end
  return cleared
end

---------------------------------------------------------------------- who came (attendance, for the fairness history)
-- s.att = { "Name-Realm", ... }: everyone who was in the group while the leader ran the session (S.MAX_ATT at most).
-- Older versions don't know it and leave it alone.
S.MAX_ATT = 80
function S.saw(s, names, now)
  s.att = s.att or {}
  local have, added = {}, false
  for _, n in ipairs(s.att) do have[n:lower()] = true end
  for _, n in ipairs(names or {}) do
    n = U.full(n)
    if type(n) == "string" and not have[n:lower()] and #s.att < S.MAX_ATT then s.att[#s.att + 1] = n have[n:lower()] = true added = true end
  end
  if added then bump(s, now) end
  return added
end
--- attendance checked: a list of names, or nil
function S.cleanAtt(list)
  if type(list) ~= "table" then return nil end
  local out = {}
  for _, n in ipairs(list) do
    if type(n) == "string" and #n <= 60 and not n:find("|", 1, true) and #out < S.MAX_ATT then out[#out + 1] = n end
  end
  return #out > 0 and out or nil
end

---------------------------------------------------------------------- the loot council (Core/Council.lua)
S.COUNCIL_MAX = 15
--- the council, checked: a list of names (no two the same, S.COUNCIL_MAX at most), or nil
function S.cleanCouncil(list)
  if type(list) ~= "table" then return nil end
  local out, seen = {}, {}
  for _, n in ipairs(list) do
    if type(n) == "string" and #n <= 60 and not n:find("|", 1, true) and not seen[n:lower()] and #out < S.COUNCIL_MAX then
      seen[n:lower()] = true
      out[#out + 1] = n
    end
  end
  return #out > 0 and out or nil
end

---------------------------------------------------------------------- the organiser's branding
-- s.br = { n = the raid's name ("<Kings> GDKP"), m = a short message ("Sign up on our Discord: ..."), i = an icon (its
-- place in S.BRAND_ICONS) }: raiders see it in their window and the raid hears it when reserves open. Older versions
-- don't know it and leave it alone; a newer version's icon this one doesn't have shows as the raid's own.
S.BRAND_NAME, S.BRAND_MSG = 40, 120
S.BRAND_ICONS = {
  { "Coin", "Interface\\Icons\\INV_Misc_Coin_01" }, { "Gold", "Interface\\Icons\\INV_Misc_Coin_02" },
  { "Dragon", "Interface\\Icons\\INV_Misc_Head_Dragon_01" }, { "Sword", "Interface\\Icons\\INV_Sword_04" },
  { "Shield", "Interface\\Icons\\INV_Shield_06" }, { "Light", "Interface\\Icons\\Spell_Holy_HolyBolt" },
  { "Fire", "Interface\\Icons\\Spell_Fire_Fire" }, { "Shadow", "Interface\\Icons\\Spell_Shadow_ShadowBolt" },
  { "Frost", "Interface\\Icons\\Spell_Frost_FrostBolt02" }, { "Storm", "Interface\\Icons\\Spell_Nature_Lightning" },
  { "Banner", "Interface\\Icons\\Ability_Warrior_BattleShout" }, { "Bag", "Interface\\Icons\\INV_Misc_Bag_10" },
}

local function brandText(text, max)
  if type(text) ~= "string" then return "" end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", ""):gsub("[%c]", " ")
  return U.trim(text):sub(1, max)
end

--- branding checked: { n, m, i } with only what's right in it, or nil when there's nothing
function S.okBrand(br)
  if type(br) ~= "table" then return nil end
  local n, m = brandText(br.n, S.BRAND_NAME), brandText(br.m, S.BRAND_MSG)
  local i = tonumber(br.i)
  i = i and i % 1 == 0 and i >= 1 and i <= 100 and i or nil
  if n == "" and m == "" and not i then return nil end
  return { n = n ~= "" and n or nil, m = m ~= "" and m or nil, i = i }
end
--- the icon's texture (nil: one this version doesn't have)
function S.brandIcon(br) local x = br and br.i and S.BRAND_ICONS[br.i] return x and x[2] or nil end

function S.setBrand(s, br, now)
  br = S.okBrand(br)
  local same = (br == nil and s.br == nil) or (br and s.br and br.n == s.br.n and br.m == s.br.m and br.i == s.br.i)
  if same then return false end
  s.br = br
  bump(s, now)
  return true
end

--- records that a player was given an item (kind: how they won it, roll: what they rolled, if they did).
--- dropKey: the drop it was; when not given, the first drop of that item nobody has won yet.
function S.award(s, id, player, kind, roll, now, dropKey, de, boosted, xn)
  if type(id) ~= "number" or type(player) ~= "string" or not S.WON_KINDS[kind] then return false end
  local d = dropKey and S.drop(s, dropKey) or S.openDrops(s, id)[1]
  if d and d.i ~= id then d = nil end
  s.won = s.won or {}
  s.won[#s.won + 1] = { i = id, p = player, k = kind, r = tonumber(roll), at = now, d = d and d.k or nil, de = de and true or nil,
    br = boosted and true or nil, xn = type(xn) == "string" and xn or nil }
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

--- changes an award (a mistake): who got it and how ("SR", "MS", "OS", or "DE" to disenchant). What it changes follows
--- by itself: reserves used up, +1s, who has it to trade. A boosted roll's mark goes (points are the guild's call).
function S.editAward(s, index, player, kind, now)
  local w = s.won and s.won[index]
  if not w or type(player) ~= "string" or w.k == "BID" or w.k == "HR" then return false end
  if kind ~= "SR" and kind ~= "MS" and kind ~= "OS" and kind ~= "DE" then return false end
  local k, de = kind == "DE" and "OS" or kind, kind == "DE" or nil
  if U.samePlayer(w.p, player) and w.k == k and (w.de or nil) == de then return false end
  w.p, w.k, w.de, w.br, w.xn = U.full(player), k, de, nil, nil
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

--- how many reserves a player has won, on any item
function S.srWinsAll(s, player)
  local n = 0
  for _, w in ipairs(s.won or {}) do if w.k == "SR" and U.samePlayer(w.p, player) then n = n + 1 end end
  return n
end

--- a player's reserves on an item that haven't won it yet. With one reserve win each (s.ow), none once they've won one.
function S.claims(s, player, id)
  if s.ow and S.srWinsAll(s, player) > 0 then return 0 end
  local n = 0
  for _, x in ipairs(S.reservesOf(s, player)) do if x == id then n = n + 1 end end
  return math.max(0, n - S.srWins(s, player, id))
end

--- when reserves lock by themselves (a server time), or nil (Core/Lock.lua)
function S.setAutoLock(s, at, now)
  at = tonumber(at)
  if s.al == at then return false end
  s.al = at
  bump(s, now)
  return true
end

--- the bench: players who came but sat out (names, at most S.BENCH_MAX). They get raid points and count as there.
S.BENCH_MAX = 40
function S.cleanBench(list)
  if type(list) ~= "table" then return nil end
  local out, seen = {}, {}
  for _, name in ipairs(list) do
    if type(name) == "string" and name ~= "" and #name <= 64 and not seen[name:lower()] and #out < S.BENCH_MAX then
      seen[name:lower()] = true
      out[#out + 1] = name
    end
  end
  return #out > 0 and out or nil
end
function S.setBench(s, list, now)
  s.bn = S.cleanBench(list)
  if s.bn then S.saw(s, s.bn, now) end          -- (benched players count as there: Fairness history)
  bump(s, now)
  return true
end

--- one reserve win each: once a player wins one of their reserves, the rest stop counting
function S.setOneWin(s, on, now)
  on = on and true or nil
  if s.ow == on then return false end
  s.ow = on
  bump(s, now)
  return true
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
  local n = tonumber(d.n)
  s.drops[#s.drops + 1] = { k = d.k, i = d.i, b = str(d.b) or "", at = tonumber(d.at) or now, by = str(d.by), src = str(d.src),
    h = str(d.h), ht = tonumber(d.ht), n = n and n > 1 and math.min(math.floor(n), 1000) or nil }   -- (n: a stack of them)
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

---------------------------------------------------------------------- sending only what changed (Core/Net.lua: U)
--- whether two values are the same, all the way down
local function same(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
S.same = same

--- what changed from one copy of a session to the next, field by field: { field = { v = its new value } (a plain value),
--- { x = true } (gone), or { s = { key = new entry }, d = { keys gone } } (a table: only the entries that changed) }.
--- nil when nothing did.
function S.diff(old, new)
  local ch, any = {}, false
  for k, v in pairs(new) do
    local o = old[k]
    if not same(o, v) then
      any = true
      if type(o) == "table" and type(v) == "table" then
        local set, del = {}, {}
        for ik, iv in pairs(v) do if not same(o[ik], iv) then set[ik] = iv end end
        for ik in pairs(o) do if v[ik] == nil then del[#del + 1] = ik end end
        ch[k] = { s = set, d = #del > 0 and del or nil }
      else
        ch[k] = { v = v }
      end
    end
  end
  for k in pairs(old) do if new[k] == nil then any = true ch[k] = { x = true } end end
  return any and ch or nil
end

--- a session with changes (S.diff's) put in: a new copy (the fields that didn't change are shared with base), or nil when
--- the changes aren't the right shape. The result still has to pass S.valid, like a whole copy.
S.PATCH_MAX = 2000
function S.patch(base, ch)
  if type(base) ~= "table" or type(ch) ~= "table" then return nil end
  local t, n = {}, 0
  for k, v in pairs(base) do t[k] = v end
  for k, c in pairs(ch) do
    n = n + 1
    if n > 100 or type(k) ~= "string" or type(c) ~= "table" then return nil end
    if c.x then
      t[k] = nil
    elseif c.s ~= nil then
      if type(c.s) ~= "table" or type(base[k]) ~= "table" then return nil end
      local inner, m = {}, 0
      for ik, iv in pairs(base[k]) do inner[ik] = iv end
      for ik, iv in pairs(c.s) do
        m = m + 1
        if m > S.PATCH_MAX then return nil end
        inner[ik] = iv
      end
      if c.d ~= nil then
        if type(c.d) ~= "table" or #c.d > S.PATCH_MAX then return nil end
        for _, ik in ipairs(c.d) do inner[ik] = nil end
      end
      t[k] = inner
    else
      t[k] = c.v
    end
  end
  return t
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
      if w.xn ~= nil and (type(w.xn) ~= "string" or #w.xn > 32) then return false end
    end
  end
  if t.de ~= nil and type(t.de) ~= "string" then return false end
  if t.url ~= nil and not S.okLink(t.url) then t.url = nil end      -- (a link that isn't softres.it's is dropped)
  if t.br ~= nil then t.br = S.okBrand(t.br) end                    -- (branding: only what's right in it is kept)
  if t.lc ~= nil then t.lc = S.cleanCouncil(t.lc) end               -- (the loot council: names only)
  if t.att ~= nil then t.att = S.cleanAtt(t.att) end                -- (who came: names only)
  if t.next ~= nil and type(t.next) ~= "string" then return false end
  if t.go ~= nil and type(t.go) ~= "boolean" then return false end
  if t.le ~= nil and type(t.le) ~= "number" then t.le = nil end       -- (when its raid's lockout ends: UI/Where.lua)
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
  if t.ow ~= nil and type(t.ow) ~= "boolean" then t.ow = nil end    -- (one reserve win each)
  if t.pv ~= nil and t.pv ~= true then t.pv = nil end                -- (my private session: Core/Net.lua)
  if t.al ~= nil and type(t.al) ~= "number" then t.al = nil end      -- (when reserves lock by themselves)
  if t.bn ~= nil then t.bn = S.cleanBench(t.bn) end                   -- (the bench: names only)
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
      if d.n ~= nil and (type(d.n) ~= "number" or d.n < 1 or d.n > 1000) then d.n = nil end
    end
  end
  for id, h in pairs(t.hr) do if type(id) ~= "number" or type(h) ~= "table" then return false end end
  for name, r in pairs(t.res) do
    if type(name) ~= "string" or type(r) ~= "table" or type(r.i) ~= "table" then return false end
    for _, id in ipairs(r.i) do if type(id) ~= "number" then return false end end
  end
  return true
end
