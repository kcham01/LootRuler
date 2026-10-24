-- The rules of rolling for an item, with no game calls (tested on their own in tests/rolls.lua). The loot
-- master's addon runs a roll (Core/Rolls.lua); raiders' addons follow along with the same rules, so their
-- roll windows show the same highest roll the loot master sees.
--
-- How an item is rolled for:
--   HR    hard reserved: nobody rolls, the loot master gives it to whoever it's for
--   SR    soft reserved by someone in the group: only they roll (/roll, 1-100); a reserve that has already
--         won this item doesn't count again
--   OPEN  nobody here reserved it: /roll (1-100) for main spec beats /roll 99 for off spec
--   TIE   the highest rolls were equal: just those players roll again, the same way they rolled before
-- Each player's first roll that counts is the one that counts.
--
-- The +1 rule (when the session has it on): every item won on a main spec roll is a +1, and among main spec
-- rolls, players with fewer +1s win over players with more, whatever they rolled. roll.po holds the +1s of
-- everyone in the group when the roll started (name, lower case -> count).
local _, LR = ...
local U, S = LR.U, LR.Session
local R = {}
LR.Roll = R

R.KINDS = { SR = { 1, 100, 1 }, MS = { 1, 100, 2 }, OS = { 1, 99, 3 } }   -- range low, high, and rank (lower wins)
R.LABEL = { SR = "SR", MS = "MS", OS = "OS", HR = "HR" }
R.WHY = {
  late = "after the roll closed",
  again = "rolled again",
  range = "wrong roll",
  notReserved = "didn't reserve it",
  notTied = "wasn't in the tie",
  hard = "it's hard reserved",
}

local function key(name) return (U.full(name) or ""):lower() end
R.key = key

--- a name from a list of who may roll (names, or { name, reserves })
function R.nameOf(w) return type(w) == "table" and w[1] or w end

local function inList(list, name)
  for _, w in ipairs(list or {}) do if U.samePlayer(type(w) == "table" and w[1] or w, name) then return true end end
  return false
end
R.inList = inList

--- how an item should be rolled for: { mode, who = { { name, reserves } } (SR), away = { names } (reserved
--- by people who aren't in the group, or have nothing left to claim), f / n (HR: for whom, note) }
--- roster: { { name = "Name-Realm" } } (LR.roster()); s may be nil (no soft reserves open)
function R.plan(s, id, roster)
  if s and s.hr[id] then return { mode = "HR", f = s.hr[id].f, n = s.hr[id].n, who = {}, away = {} } end
  local who, away = {}, {}
  if s then
    for _, w in ipairs(S.byItem(s)[id] or {}) do
      local left = S.claims(s, w[1], id)
      local here = false
      for _, m in ipairs(roster or {}) do if U.samePlayer(m.name, w[1]) then here = true break end end
      if left > 0 and here then who[#who + 1] = { w[1], left } elseif left > 0 then away[#away + 1] = w[1] end
    end
  end
  if #who > 0 then return { mode = "SR", who = who, away = away } end
  return { mode = "OPEN", who = {}, away = away }
end

--- a new roll (the loot master's, or a raider's copy of it)
function R.new(k, id, plan)
  return { k = k, id = id, mode = plan.mode, who = plan.who or {}, away = plan.away or {}, f = plan.f, n = plan.n,
    tie = plan.tie, po = plan.po, entries = {}, rolled = {}, passed = {} }
end

--- a player's +1s in a roll (0 when the +1 rule is off)
function R.plusOnes(roll, player) return roll.po and roll.po[key(player)] or 0 end

--- what a roll counts as, for people: "MS", "MS +1", "SR 2"...
function R.label(roll, e)
  local l = R.LABEL[e.kind] or tostring(e.kind)
  local po = e.kind == "MS" and R.plusOnes(roll, e.p) or 0
  return po > 0 and (l .. " +" .. po) or l
end

--- whether a player may roll in this roll at all
function R.canRoll(roll, player)
  if roll.mode == "HR" then return false, "hard" end
  if roll.mode == "SR" and not inList(roll.who, player) then return false, "notReserved" end
  if roll.mode == "TIE" and not inList(roll.who, player) then return false, "notTied" end
  return true
end

--- the ranges a player may roll with: { kind, ... } (most wanted first)
function R.options(roll, player)
  if not R.canRoll(roll, player) then return {} end
  if roll.mode == "OPEN" then return { "MS", "OS" } end
  if roll.mode == "SR" then return { "SR" } end
  if roll.mode == "TIE" then return { roll.tie } end
  return {}
end

--- what a roll of lo-hi counts as for this player, or nil and why not
local function kindOf(roll, player, lo, hi)
  local ok, why = R.canRoll(roll, player)
  if not ok then return nil, why end
  for _, kind in ipairs(R.options(roll, player)) do
    local r = R.KINDS[kind]
    if lo == r[1] and hi == r[2] then return kind end
  end
  return nil, "range"
end

--- adds a roll someone made (from the game's "Name rolls 57 (1-100)" message); late: it came after the roll
--- closed. Returns the entry: { p = name, n = roll, lo, hi, kind (nil when it doesn't count), why }
function R.add(roll, player, n, lo, hi, late)
  local e = { p = U.full(player), n = n, lo = lo, hi = hi, seq = #roll.entries + 1 }
  local kind, why = kindOf(roll, player, lo, hi)
  if late then why, kind = "late", nil
  elseif kind and roll.rolled[key(player)] then why, kind = "again", nil end
  e.kind, e.why = kind, kind and nil or why
  if kind then roll.rolled[key(player)] = e end
  table.insert(roll.entries, e)
  return e
end

function R.pass(roll, player) roll.passed[key(player)] = U.full(player) end

--- the rolls that count, best first; the ones that don't after them
function R.standings(roll)
  local good, bad = {}, {}
  for _, e in ipairs(roll.entries) do
    if e.kind then good[#good + 1] = e else bad[#bad + 1] = e end
  end
  table.sort(good, function(a, b)
    local ra, rb = R.KINDS[a.kind][3], R.KINDS[b.kind][3]
    if ra ~= rb then return ra < rb end
    if a.kind == "MS" then
      local pa, pb = R.plusOnes(roll, a.p), R.plusOnes(roll, b.p)
      if pa ~= pb then return pa < pb end
    end
    if a.n ~= b.n then return a.n > b.n end
    return a.seq < b.seq
  end)
  table.sort(bad, function(a, b) return a.seq < b.seq end)
  return good, bad
end

--- the winner (an entry) and, when the best rolls are equal, everyone who tied (names)
function R.result(roll)
  local good = R.standings(roll)
  local top = good[1]
  if not top then return nil end
  local tied = { top.p }
  for i = 2, #good do
    local e = good[i]
    if e.kind == top.kind and e.n == top.n and (e.kind ~= "MS" or R.plusOnes(roll, e.p) == R.plusOnes(roll, top.p)) then
      tied[#tied + 1] = e.p
    else break end
  end
  if #tied > 1 then return top, tied end
  return top
end

--- everyone who may roll and hasn't rolled or passed yet (only known for SR and TIE rolls)
function R.waiting(roll)
  if roll.mode ~= "SR" and roll.mode ~= "TIE" then return nil end
  local out = {}
  for _, w in ipairs(roll.who) do
    local name = type(w) == "table" and w[1] or w
    if not roll.rolled[key(name)] and not roll.passed[key(name)] then out[#out + 1] = name end
  end
  return out
end

--- "Name rolls 57 (1-100)" as a pattern, from the game's own (translated) RANDOM_ROLL_RESULT; returns a
--- function that gives name, roll, low, high for a chat line, or nil
function R.parser(format)
  local p = U.pattern(format or "%s rolls %d (%d-%d)")
  return function(line)
    local name, n, lo, hi = tostring(line or ""):match(p)
    if not name then return nil end
    return name, tonumber(n), tonumber(lo), tonumber(hi)
  end
end

--- the people a roll is for, as a short line: "Ann, Bob x2, +3"
function R.names(list, limit)
  local parts = {}
  for i, w in ipairs(list or {}) do
    if limit and i > limit then parts[#parts + 1] = "+" .. (#list - limit) break end
    local name, n = type(w) == "table" and w[1] or w, type(w) == "table" and w[2] or 1
    parts[#parts + 1] = U.short(name) .. ((n or 1) > 1 and (" x" .. n) or "")
  end
  return table.concat(parts, ", ")
end
