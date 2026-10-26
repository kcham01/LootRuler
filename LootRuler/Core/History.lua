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
    drops[i] = { k = d.k, i = d.i, b = d.b, at = d.at }
  end
  local e = {
    id = s.id, rev = s.rev, leader = s.leader, raid = s.raid, raidName = s.raidName, sr = s.sr, any = s.any,
    created = s.created, updated = now, ended = now, archived = true, hr = {}, res = {},
    won = won, drops = drops, gdkp = s.gdkp or nil, gk = s.gk and U.copy(s.gk) or nil, plusOne = s.plusOne or nil,
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
