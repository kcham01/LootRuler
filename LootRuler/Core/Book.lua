-- The guild book: a guild's LootRuler data that lasts between raids, kept by its officers. Boosted roll
-- points and priority lists live here. Nothing here calls the game (tested on its own in tests/rolls.lua);
-- Core/Guild.lua shares it over the guild channel and decides who may change it.
--
-- Every entry carries when it was last changed (t, server time), so two officers' copies merge entry by
-- entry, newest first, instead of one copy overwriting the other. Something taken away stays as an empty
-- entry with its time, so the taking away spreads too.
--
-- A book:
--   guild      the guild's name
--   editRank   ranks up to this one (0 = the guild master) may change the book; only the guild master
--              changes this (et: when)
--   boost      { on = bool, perRaid = points for each raid, t }
--   points     "Name-Realm" -> { n = points, t }
--   alts       "Alt-Realm" -> { m = "Main-Realm" (or "" when unlinked), t }: an alt rolls with, and spends, its
--              main's points (as Gargul's boosted roll aliases do)
--   prio       item id -> { list = { { p = "Name-Realm", n = priority (1 first), note }, ... }, t }
local _, LR = ...
local U = LR.U

local B = {}
LR.Book = B

B.DEFAULT_PER_RAID = 10
B.MAX_POINTS = 1000

--- when an entry changes: now, or just after its last change (two changes in the same second still spread)
local function stamp(old, now)
  local last = old and old.t or 0
  return now > last and now or last + 0.001
end
B.stamp = stamp

function B.new(guild)
  return { guild = guild, editRank = 1, et = 0, boost = { on = false, perRaid = B.DEFAULT_PER_RAID, t = 0 }, points = {}, prio = {}, alts = {} }
end

---------------------------------------------------------------------- alts
--- the character whose points a player uses: their main when they're a linked alt, else themselves
function B.mainOf(book, player)
  player = U.full(player)
  local e = book.alts and book.alts[player]
  if e and e.m ~= "" then return e.m end
  -- (names typed in another case: "annalt" is Annalt)
  if book.alts then
    for alt, x in pairs(book.alts) do if x.m ~= "" and U.samePlayer(alt, player) then return x.m end end
  end
  return player
end

--- a main's alts (names), sorted
function B.altsOf(book, main)
  main = U.full(main)
  local out = {}
  for alt, e in pairs(book.alts or {}) do if e.m ~= "" and U.samePlayer(e.m, main) then out[#out + 1] = alt end end
  table.sort(out)
  return out
end

--- links an alt to a main (an alt of an alt is linked to the top main; a main's own alts follow it).
--- Returns the change, or nil and why not.
function B.setAlt(book, alt, main, now)
  alt, main = U.full(alt), B.mainOf(book, main)
  if U.samePlayer(alt, main) then return nil, "That's the same character." end
  book.alts = book.alts or {}
  local change = { alts = {} }
  -- whatever was linked to the alt now goes with it, to the main
  for _, a in ipairs(B.altsOf(book, alt)) do
    book.alts[a] = { m = main, t = stamp(book.alts[a], now) }
    change.alts[a] = book.alts[a]
  end
  local cur = book.alts[alt]
  if cur and cur.m ~= "" and U.samePlayer(cur.m, main) and not next(change.alts) then return nil, "It's linked already." end
  book.alts[alt] = { m = main, t = stamp(cur, now) }
  change.alts[alt] = book.alts[alt]
  return change
end

--- unlinks an alt: it has its own points again. Returns the change, or nil.
function B.unlinkAlt(book, alt, now)
  alt = U.full(alt)
  local cur = book.alts and book.alts[alt]
  if not cur or cur.m == "" then return nil end
  book.alts[alt] = { m = "", t = stamp(cur, now) }
  return { alts = { [alt] = book.alts[alt] } }
end

---------------------------------------------------------------------- points
--- a player's points (their main's, for a linked alt)
function B.points(book, player)
  local e = book.points[B.mainOf(book, player)]
  return e and e.n or 0
end

--- a character's own points, even when it's an alt (shown when it's unlinked again)
function B.ownPoints(book, player)
  local e = book.points[U.full(player)]
  return e and e.n or 0
end

--- sets a player's points (their main's, for a linked alt; 0 to MAX_POINTS); returns the change to send, or
--- nil when nothing changed
function B.setPoints(book, player, n, now)
  n = math.max(0, math.min(B.MAX_POINTS, math.floor(tonumber(n) or 0)))
  player = B.mainOf(book, player)
  if B.points(book, player) == n then return nil end
  book.points[player] = { n = n, t = stamp(book.points[player], now) }
  return { points = { [player] = book.points[player] } }
end

--- gives every player in a list the points for a raid; returns the change
function B.raidAttended(book, players, now)
  local change = { points = {} }
  local done = {}
  for _, p in ipairs(players) do
    p = B.mainOf(book, p)
    -- (a main and an alt both here get the raid's points once)
    if not done[p:lower()] then
      done[p:lower()] = true
      local n = math.min(B.MAX_POINTS, B.points(book, p) + (book.boost.perRaid or B.DEFAULT_PER_RAID))
      book.points[p] = { n = n, t = stamp(book.points[p], now) }
      change.points[p] = book.points[p]
    end
  end
  return change
end

function B.setBoost(book, on, perRaid, now)
  book.boost = { on = on and true or false, perRaid = math.max(1, math.min(100, math.floor(tonumber(perRaid) or B.DEFAULT_PER_RAID))), t = stamp(book.boost, now) }
  return { boost = book.boost }
end

--- a boosted roll's range for a number of points: everyone's 1-100 moved up by the points
function B.boostRange(points) return 1 + points, 100 + points end

---------------------------------------------------------------------- priority lists
--- an item's priority list, best first: { { p, n, note } }
function B.prio(book, id)
  local e = book.prio[id]
  local list = e and e.list or {}
  table.sort(list, function(a, b) if a.n ~= b.n then return a.n < b.n end return a.p < b.p end)
  return list
end

--- replaces an item's list; returns the change
function B.setPrio(book, id, list, now)
  local clean = {}
  local seen = {}
  for _, x in ipairs(list or {}) do
    if type(x) == "table" and type(x.p) == "string" and not seen[U.full(x.p):lower()] then
      seen[U.full(x.p):lower()] = true
      clean[#clean + 1] = { p = U.full(x.p), n = math.max(1, math.floor(tonumber(x.n) or 1)), note = type(x.note) == "string" and x.note:sub(1, 60) or nil }
    end
  end
  book.prio[id] = { list = clean, t = stamp(book.prio[id], now) }
  return { prio = { [id] = book.prio[id] } }
end

--- someone got an item they had priority on: they come off its list. Returns the change, or nil.
function B.received(book, id, player, now)
  local list = B.prio(book, id)
  local keep = {}
  for _, x in ipairs(list) do if not U.samePlayer(x.p, player) then keep[#keep + 1] = x end end
  if #keep == #list then return nil end
  return B.setPrio(book, id, keep, now)
end

--- whose turn an item is: the players with the best priority who are here (names), or {} for a free roll
function B.first(book, id, here)
  local best, out = nil, {}
  for _, x in ipairs(B.prio(book, id)) do
    local present = not here
    for _, m in ipairs(here or {}) do if U.samePlayer(m, x.p) then present = true break end end
    if present then
      if not best then best = x.n end
      if x.n == best then out[#out + 1] = x.p else break end
    end
  end
  return out, best
end

--- every item a player has priority on: { { id, n } }
function B.prioOf(book, player)
  local out = {}
  for id, e in pairs(book.prio) do
    for _, x in ipairs(e.list or {}) do if U.samePlayer(x.p, player) then out[#out + 1] = { id, x.n } end end
  end
  table.sort(out, function(a, b) return a[2] < b[2] end)
  return out
end

---------------------------------------------------------------------- sharing
--- whether a book (or a change) from another player has the right shape; caps sizes
function B.valid(c)
  if type(c) ~= "table" then return false end
  if c.points ~= nil then
    if type(c.points) ~= "table" then return false end
    local n = 0
    for p, e in pairs(c.points) do
      n = n + 1
      if n > 2000 or type(p) ~= "string" or type(e) ~= "table" or type(e.n) ~= "number" or type(e.t) ~= "number" then return false end
    end
  end
  if c.prio ~= nil then
    if type(c.prio) ~= "table" then return false end
    local n = 0
    for id, e in pairs(c.prio) do
      n = n + 1
      if n > 2000 or type(id) ~= "number" or type(e) ~= "table" or type(e.t) ~= "number" or type(e.list) ~= "table" or #e.list > 100 then return false end
      for _, x in ipairs(e.list) do if type(x) ~= "table" or type(x.p) ~= "string" or type(x.n) ~= "number" then return false end end
    end
  end
  if c.alts ~= nil then
    if type(c.alts) ~= "table" then return false end
    local n = 0
    for a, e in pairs(c.alts) do
      n = n + 1
      if n > 2000 or type(a) ~= "string" or type(e) ~= "table" or type(e.m) ~= "string" or type(e.t) ~= "number" then return false end
    end
  end
  if c.boost ~= nil and (type(c.boost) ~= "table" or type(c.boost.t) ~= "number") then return false end
  if c.editRank ~= nil and (type(c.editRank) ~= "number" or type(c.et) ~= "number") then return false end
  return true
end

--- whether saved data is a whole book (checked when loaded)
function B.validBook(book)
  return type(book) == "table" and type(book.guild) == "string" and type(book.points) == "table" and type(book.prio) == "table"
    and type(book.boost) == "table" and type(book.editRank) == "number" and type(book.et) == "number" and B.valid(book)
end

--- merges a change (or a whole book) into a book, entry by entry, the newer one winning. fromGM: the sender is
--- the guild master (only they change who may edit). Returns whether anything changed.
function B.merge(book, c, fromGM)
  local changed = false
  for p, e in pairs(c.points or {}) do
    p = U.full(p)
    local mine = book.points[p]
    if not mine or e.t > mine.t then book.points[p] = { n = math.max(0, math.min(B.MAX_POINTS, math.floor(e.n))), t = e.t } changed = true end
  end
  book.alts = book.alts or {}
  for a, e in pairs(c.alts or {}) do
    a = U.full(a)
    local mine = book.alts[a]
    if not mine or e.t > mine.t then
      -- (never an alt of itself)
      book.alts[a] = { m = (e.m ~= "" and not U.samePlayer(e.m, a)) and U.full(e.m) or "", t = e.t }
      changed = true
    end
  end
  for id, e in pairs(c.prio or {}) do
    local mine = book.prio[id]
    if not mine or e.t > mine.t then
      local list = {}
      for _, x in ipairs(e.list) do list[#list + 1] = { p = U.full(x.p), n = math.max(1, math.floor(x.n)), note = type(x.note) == "string" and x.note:sub(1, 60) or nil } end
      book.prio[id] = { list = list, t = e.t }
      changed = true
    end
  end
  if c.boost and c.boost.t > (book.boost.t or 0) then
    local per = math.floor(tonumber(c.boost.perRaid) or B.DEFAULT_PER_RAID)
    book.boost = { on = c.boost.on == true, perRaid = math.max(1, math.min(100, per)), t = c.boost.t }
    changed = true
  end
  if fromGM and c.editRank and c.et > (book.et or 0) then
    book.editRank, book.et = math.max(0, math.floor(c.editRank)), c.et
    changed = true
  end
  return changed
end
