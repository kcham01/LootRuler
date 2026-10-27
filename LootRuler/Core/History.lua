-- Past raids: when a session ends (or a raider's copy of it is closed by its leader, or it's forgotten after
-- a week), what it gave out is kept here, so the loot list, the export and a GDKP's payouts outlive it. Kept
-- per character, the most recent first, at most History.MAX raids.
--
-- An entry is a frozen copy of the session (archived = true, no reserves), so everything that reads a
-- session (exports, the GDKP split, the payouts sheet) reads it too. A GDKP organiser can still finish the
-- payouts on one: gold that changes hands in a trade counts, as it did during the raid.
local _, LR = ...
local U, S = LR.U, LR.Session

local H = {}
LR.History = H

H.MAX = 30
H.MAX_WON = 300
H.PAY_DAYS = 14          -- a GDKP's payouts are looked for in trades this long after it ended

local function list()
  LR.db.history = LR.db.history or {}
  return LR.db.history
end

--- whether there's anything worth keeping: loot given out (a GDKP's sales are too), and not in a practice raid
local function worth(s) return s and not s.practice and #(s.won or {}) > 0 end

--- keeps a session that's ending; returns the entry (nil when there was nothing to keep)
function H.archive(s, now)
  if not worth(s) then return nil end
  H.remove(s.id)
  local won = {}
  for i, w in ipairs(s.won or {}) do
    if i > H.MAX_WON then break end
    won[i] = U.copy(w)
  end
  local drops = {}
  for i, d in ipairs(s.drops or {}) do
    if i > S.MAX_DROPS then break end
    drops[i] = { k = d.k, i = d.i, b = d.b, at = d.at, n = d.n }
  end
  local e = {
    id = s.id, rev = s.rev, leader = s.leader, raid = s.raid, raidName = s.raidName, sr = s.sr, any = s.any,
    created = s.created, updated = now, ended = now, archived = true, hr = {}, res = {},
    won = won, drops = drops, gdkp = s.gdkp or nil, gk = s.gk and U.copy(s.gk) or nil, plusOne = s.plusOne or nil,
    att = s.att and U.copy(s.att) or nil,
  }
  local h = list()
  table.insert(h, 1, e)
  while #h > H.MAX do table.remove(h) end
  LR.changed("history")
  return e
end

function H.find(id) for _, e in ipairs(list()) do if e.id == id then return e end end end
function H.remove(id)
  local h = list()
  for i = #h, 1, -1 do if h[i].id == id then table.remove(h, i) end end
  LR.changed("history")
end
function H.all() return list() end

---------------------------------------------------------------------- fairness: who got what, over time
--- every player's loot across past raids (and the session on now), since a time (0: all of it):
--- { { p, items = { { i, k, at, raid, de, g } }, kinds = { MS, OS, SR, HR, BID, DE }, gold, raids, last } }, most items first.
--- raids: how many of those raids they came to (in the group while it ran, or won something in it)
function H.fairness(since, current)
  since = since or 0
  local rows, order = {}, {}
  local function row(p)
    local k = LR.Roll.key(p)
    if not rows[k] then
      rows[k] = { p = U.full(p), items = {}, kinds = {}, gold = 0, raids = 0, last = 0, seenIn = {} }
      order[#order + 1] = rows[k]
    end
    return rows[k]
  end
  local entries = {}
  for _, e in ipairs(list()) do entries[#entries + 1] = e end
  if current and not current.archived and not current.practice then entries[#entries + 1] = current end
  for _, e in ipairs(entries) do
    local when = e.ended or e.updated or e.created or 0
    if when >= since then
      local raid = LR.raidOf(e).name
      local function came(p) local r = row(p) if not r.seenIn[e.id] then r.seenIn[e.id] = true r.raids = r.raids + 1 end return r end
      for _, n in ipairs(e.att or {}) do came(n) end
      for n in pairs(e.gk and e.gk.seen or {}) do came(n) end
      for _, w in ipairs(e.won or {}) do
        local r = came(w.p)
        local kind = w.de and "DE" or w.k
        r.kinds[kind] = (r.kinds[kind] or 0) + 1
        if w.k == "BID" then r.gold = r.gold + (tonumber(w.r) or 0) end
        table.insert(r.items, { i = w.i, k = kind, at = w.at or when, raid = raid, g = w.k == "BID" and tonumber(w.r) or nil })
        r.last = math.max(r.last, w.at or when)
      end
    end
  end
  for _, r in ipairs(order) do
    r.seenIn = nil
    table.sort(r.items, function(a, b) return a.at > b.at end)
  end
  table.sort(order, function(a, b)
    if #a.items ~= #b.items then return #a.items > #b.items end
    if a.raids ~= b.raids then return a.raids > b.raids end
    return a.p < b.p
  end)
  return order
end

--- "3 MS, 1 OS, 1 SR" (the kinds a player won, in a set order)
H.KIND_ORDER = { { "SR", "SR" }, { "HR", "HR" }, { "MS", "MS" }, { "OS", "OS" }, { "BID", "bought" }, { "DE", "to disenchant" } }
function H.kindsText(kinds)
  local parts = {}
  for _, x in ipairs(H.KIND_ORDER) do if (kinds[x[1]] or 0) > 0 then parts[#parts + 1] = kinds[x[1]] .. " " .. x[2] end end
  for k, n in pairs(kinds) do
    local known = false
    for _, x in ipairs(H.KIND_ORDER) do if x[1] == k then known = true end end
    if not known then parts[#parts + 1] = n .. " " .. k end          -- (a kind a newer version knows)
  end
  return table.concat(parts, ", ")
end

--- whether a saved entry has the right shape (checked when loaded, like a session from someone else)
function H.valid(e)
  return type(e) == "table" and e.archived == true and type(e.ended) == "number" and S.valid(e)
end

--- my GDKP, not long over, in which a player still owes me or is owed: the entry, else nil
function H.owing(player, now)
  for _, e in ipairs(list()) do
    if e.gdkp and e.gk and LR.isLeader(e) and (now or U.now()) - e.ended < H.PAY_DAYS * 86400 then
      local row = LR.Gdkp.split(e).rows[U.full(player)]
      if row and math.abs(row.owed) >= 0.01 then return e end
    end
  end
end

--- what an item sold for in past GDKPs (and the raid going now), most recent first: { gold, ... }
function H.prices(id, current)
  local out = {}
  local function add(s)
    if not (s and s.gdkp) then return end
    for i = #(s.won or {}), 1, -1 do
      local w = s.won[i]
      if w.i == id and w.k == "BID" and tonumber(w.r) then out[#out + 1] = tonumber(w.r) end
    end
  end
  add(current)
  for _, e in ipairs(list()) do add(e) end
  return out
end

--- what an item usually sells for: the average of its last few sales, and how many there were (nil when none)
function H.usualPrice(id, current)
  local p = H.prices(id, current)
  if #p == 0 then return nil end
  local n, sum = math.min(#p, 5), 0
  for i = 1, n do sum = sum + p[i] end
  return math.floor(sum / n + 0.5), #p
end
