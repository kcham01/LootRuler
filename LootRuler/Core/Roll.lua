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
--   BID   a GDKP auction: everyone bids gold by typing an amount in raid chat; each bid must be at least
--         roll.inc more than the highest (the first at least roll.min). The highest bid when time is up wins.
--         Bids are entries of kind "BID" with n = the gold.
--   PR    on the guild's priority list (the session uses them): the best priority here gets it; when several
--         share it, just they roll (/roll, 1-100), and one alone gets it with no roll (who: names, n: the
--         priority)
-- Each player's first roll that counts is the one that counts, but in an SR roll each reserve they still have on the item
-- is a roll: with three reserves left on it they may /roll three times, and their highest counts (R.rollsFor).
--
-- Extra roll types (the loot master's own, Settings: rollKinds): a roll open to everyone can have up to
-- R.MAX_EXTRA more, each a /roll 1-hi with a name ("Transmog", /roll 98). They rank after off spec, in the order
-- they're listed. roll.xk holds them ({ { n = name, hi = top } }); their kinds are "X1", "X2"... A win on one is
-- recorded as off spec with its name (older versions read it as off spec).
--
-- The +1 rule (when the session has it on): every item won on a main spec roll is a +1, and among main spec
-- rolls, players with fewer +1s win over players with more, whatever they rolled. roll.po holds the +1s of
-- everyone in the group when the roll started (name, lower case -> count).
local _, LR = ...
local U, S = LR.U, LR.Session
local R = {}
LR.Roll = R

R.KINDS = { SR = { 1, 100, 1 }, MS = { 1, 100, 2 }, OS = { 1, 99, 3 }, BR = { 1, 100, 2 },
  BID = { 0, 0, 4 } }   -- range low, high, rank (lower wins); BID: a bid in an auction (no roll)
R.LABEL = { SR = "SR", MS = "MS", OS = "OS", HR = "HR", BR = "BR", BID = "bid" }
R.MAX_BID = 1000000
-- BR, a boosted roll (guild points, Core/Book.lua): a main spec roll moved up by the player's points, 1+p to
-- 100+p (roll.bp: name, lower case -> points). It ranks with main spec rolls, so the higher number wins.
R.WHY = {
  late = "after the roll closed",
  again = "rolled again",
  lower = "not their best roll",
  range = "wrong roll",
  notReserved = "didn't reserve it",
  notTied = "wasn't in the tie",
  notFirst = "isn't first on the priority list",
  auction = "a /roll in an auction",
  low = "less than the lowest bid",
  high = "more gold than there is",
  raised = "bid again",
  banned = "bids not taken",
  hard = "it's hard reserved",
}

R.MAX_EXTRA = 4
R.EXTRA_NAME = 16

--- a list of extra roll types, checked (from settings or a message): { { n = name, hi = top } }, or nil when none.
--- Each top is 2-98 (99 and 100 are off spec and main spec) and used once; names are plain and short.
function R.checkKinds(list)
  if type(list) ~= "table" then return nil end
  local out, used = {}, {}
  for _, x in ipairs(list) do
    if #out >= R.MAX_EXTRA then break end
    local n, hi = type(x) == "table" and x.n, type(x) == "table" and tonumber(x.hi)
    if type(n) == "string" then n = n:gsub("[|%c]", ""):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, R.EXTRA_NAME) end
    if type(n) == "string" and n ~= "" and hi and hi == math.floor(hi) and hi >= 2 and hi <= 98 and not used[hi] then
      used[hi] = true
      out[#out + 1] = { n = n, hi = hi }
    end
  end
  return #out > 0 and out or nil
end

--- a list of extra roll types with one more: the new list, or nil and why not (for people)
function R.addKind(list, name, hi)
  list = R.checkKinds(list) or {}
  name = type(name) == "string" and name:gsub("[|%c]", ""):gsub("^%s+", ""):gsub("%s+$", "") or ""
  hi = tonumber(hi)
  if name == "" then return nil, "Give it a name." end
  if #name > R.EXTRA_NAME then return nil, ("Keep the name to %d letters."):format(R.EXTRA_NAME) end
  if #list >= R.MAX_EXTRA then return nil, ("That's %d already: take one off first."):format(R.MAX_EXTRA) end
  if not hi or hi ~= math.floor(hi) or hi < 2 or hi > 98 then return nil, "Pick a number from 2 to 98 (100 is main spec, 99 off spec)." end
  for _, x in ipairs(list) do
    if x.hi == hi then return nil, ("/roll %d is %s already."):format(hi, x.n) end
    if x.n:lower() == name:lower() then return nil, ("There's one called %s already."):format(x.n) end
  end
  list[#list + 1] = { n = name, hi = hi }
  return list
end

--- an extra roll type in a roll ("X2" -> its { n, hi }), or nil
function R.extra(roll, kind)
  local i = type(kind) == "string" and tonumber(kind:match("^X(%d)$"))
  return i and roll.xk and roll.xk[i] or nil
end

--- a kind's range and rank in a roll: lo, hi, rank (lower wins), or nil when the roll has no such kind
function R.kind(roll, kind)
  local k = R.KINDS[kind]
  if k then return k[1], k[2], k[3] end
  local x = R.extra(roll, kind)
  if x then return 1, x.hi, 10 + tonumber(kind:sub(2)) end
end
local function rank(roll, kind) return select(3, R.kind(roll, kind)) or 99 end

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
    tie = plan.tie, po = plan.po, bp = plan.bp, xk = plan.xk, min = plan.min, inc = plan.inc, strict = plan.strict, nb = plan.nb,
    entries = {}, rolled = {}, passed = {} }
end

--- a player's boosted roll range in a roll, or nil when they have no points
function R.boostRange(roll, player)
  local p = roll.bp and roll.bp[key(player)]
  if not p or p <= 0 then return nil end
  return 1 + p, 100 + p
end

--- a player's +1s in a roll (0 when the +1 rule is off)
function R.plusOnes(roll, player) return roll.po and roll.po[key(player)] or 0 end

--- what a roll counts as, for people: "MS", "MS +1", "SR 2"...
function R.label(roll, e)
  local x = R.extra(roll, e.kind)
  local l = x and x.n or R.LABEL[e.kind] or tostring(e.kind)
  local po = (e.kind == "MS" or e.kind == "BR") and R.plusOnes(roll, e.p) or 0
  return po > 0 and (l .. " +" .. po) or l
end

--- whether a player may roll in this roll at all
function R.canRoll(roll, player)
  if roll.mode == "HR" then return false, "hard" end
  if roll.mode == "SR" and not inList(roll.who, player) then return false, "notReserved" end
  if roll.mode == "TIE" and not inList(roll.who, player) then return false, "notTied" end
  if roll.mode == "PR" and not inList(roll.who, player) then return false, "notFirst" end
  return true
end

--- the ranges a player may roll with: { kind, ... } (most wanted first)
function R.options(roll, player)
  if not R.canRoll(roll, player) then return {} end
  if roll.mode == "OPEN" then
    local out = R.boostRange(roll, player) and { "MS", "BR", "OS" } or { "MS", "OS" }
    for i in ipairs(roll.xk or {}) do out[#out + 1] = "X" .. i end
    return out
  end
  if roll.mode == "SR" then return { "SR" } end
  if roll.mode == "TIE" then return { roll.tie } end
  if roll.mode == "PR" then return { "MS" } end
  if roll.mode == "BID" then return { "BID" } end         -- (a bid, typed: a /roll doesn't count)
  return {}
end

--- how many rolls a player may make in this roll: one for each reserve they have left on the item (SR), else one
function R.rollsFor(roll, player)
  if roll.mode ~= "SR" then return 1 end
  for _, w in ipairs(roll.who) do
    if type(w) == "table" and U.samePlayer(w[1], player) then return math.max(1, math.min(10, tonumber(w[2]) or 1)) end
  end
  return 1
end
--- how many of their rolls a player still has (0 once they've rolled them all)
function R.rollsLeft(roll, player)
  roll.used = roll.used or {}
  return math.max(0, R.rollsFor(roll, player) - (roll.used[key(player)] or 0))
end

--- what a roll of lo-hi counts as for this player, or nil and why not
local function kindOf(roll, player, lo, hi)
  if roll.mode == "BID" then return nil, "auction" end
  local ok, why = R.canRoll(roll, player)
  if not ok then return nil, why end
  for _, kind in ipairs(R.options(roll, player)) do
    local a, b = R.kind(roll, kind)
    if kind == "BR" then a, b = R.boostRange(roll, player) end
    if lo == a and hi == b then return kind end
  end
  return nil, "range"
end

--- adds a roll someone made (from the game's "Name rolls 57 (1-100)" message); late: it came after the roll
--- closed. Returns the entry: { p = name, n = roll, lo, hi, kind (nil when it doesn't count), why }
function R.add(roll, player, n, lo, hi, late)
  local e = { p = U.full(player), n = n, lo = lo, hi = hi, seq = #roll.entries + 1 }
  local kind, why = kindOf(roll, player, lo, hi)
  local k = key(player)
  roll.used = roll.used or {}
  if late then why, kind = "late", nil
  elseif kind and R.rollsLeft(roll, player) == 0 then why, kind = "again", nil end
  e.kind, e.why = kind, kind and nil or why
  if kind then
    roll.used[k] = (roll.used[k] or 0) + 1
    if R.rollsFor(roll, player) > 1 then e.try = roll.used[k] end            -- (roll 2 of 3)
    -- one of several: only their best counts; the others stay in the list as lower
    local best = roll.rolled[k]
    if best and best.n >= n then
      e.kind, e.why = nil, "lower"
    else
      if best then best.kind, best.why = nil, "lower" end
      roll.rolled[k] = e
    end
  end
  table.insert(roll.entries, e)
  return e
end

function R.pass(roll, player) roll.passed[key(player)] = U.full(player) end

---------------------------------------------------------------------- auctions (GDKP)
--- the lowest bid that counts now
function R.nextBid(roll) return roll.top and (roll.top.n + (roll.inc or 1)) or (roll.min or 1) end
--- the highest bid (an entry), or nil
function R.topBid(roll) return roll.top end

--- a bid of g gold from a player; late: after the auction closed. Returns the entry (kind "BID" when it counts)
function R.bid(roll, player, g, late)
  g = math.floor(tonumber(g) or 0)
  local e = { p = U.full(player), n = g, seq = #roll.entries + 1 }
  if roll.mode ~= "BID" then e.why = "notAuction"
  elseif roll.nb and roll.nb[key(player)] then e.why = "banned"
  elseif late then e.why = "late"
  elseif g < R.nextBid(roll) then e.why = "low"
  elseif g > R.MAX_BID then e.why = "high"
  else
    local old = roll.rolled[key(player)]
    if old then old.kind, old.why = nil, "raised" end
    e.kind = "BID"
    roll.rolled[key(player)] = e
    roll.top = e
  end
  table.insert(roll.entries, e)
  return e
end

--- the organiser stopped taking a player's bids (GDKP: their bids don't count tonight): their bids in this auction stop
--- counting, and the highest bid is the best of everyone else's again. Returns whether anything changed.
function R.ban(roll, player)
  local k = key(player)
  roll.nb = roll.nb or {}
  if roll.nb[k] then return false end
  roll.nb[k] = U.full(player)
  for _, e in ipairs(roll.entries) do
    if e.kind == "BID" and key(e.p) == k then e.kind, e.why = nil, "banned" end
  end
  roll.rolled[k] = nil
  if roll.top and key(roll.top.p) == k then
    local best
    for _, e in ipairs(roll.entries) do
      if e.kind == "BID" and (not best or e.n > best.n or (e.n == best.n and e.seq < best.seq)) then best = e end
    end
    roll.top = best
  end
  return true
end

--- max bids ("bid for me up to 800g"), kept by the loot master's addon: maxes = { [key] = { p, g, at } }.
--- Bids for them as little as it takes to keep them on top, up to their max; when two maxes meet, the higher
--- one wins at the lower one's max (or just above the other's bid), and an equal one goes to whoever set it
--- first. Returns the bids it made (entries).
function R.resolve(roll, maxes)
  local made = {}
  if roll.mode ~= "BID" then return made end
  for _ = 1, 40 do
    local top = roll.top
    local need = R.nextBid(roll)
    local best
    for k, m in pairs(maxes) do
      if not (top and key(top.p) == k) and m.g >= need and not (roll.nb and roll.nb[k]) then
        if not best or m.g > best.g or (m.g == best.g and m.at < best.at) then best = m end
      end
    end
    if not best then break end
    local mine = top and maxes[key(top.p)]
    local topMax = mine and mine.g or (top and top.n) or 0
    local e
    if top and mine and (topMax > best.g or (topMax == best.g and mine.at <= best.at)) then
      -- the leader's own max holds: they match the challenger's max, which then can't be beaten by enough
      e = R.bid(roll, top.p, best.g)
      if not e.kind then break end
      e.auto = true
      made[#made + 1] = e
      -- (the challenger is out: their max is below the next bid now)
    else
      -- the challenger goes just above the leader's max (or their bid), up to their own max
      e = R.bid(roll, best.p, math.min(best.g, math.max(need, topMax + (roll.inc or 1))))
      if not e.kind then break end
      e.auto = true
      made[#made + 1] = e
    end
  end
  return made
end

--- the gold in a chat line that's a bid: "150", "150g", "150 gold", "bid 150", "1.5k"; nil otherwise.
--- strict: only "bid 150" (and "bid 150g"...) counts
function R.parseBid(text, strict)
  local t = U.trim(tostring(text or "")):lower():gsub(",", "")
  if strict and not t:find("^bid") then return nil end
  t = t:gsub("^bid%s*", ""):gsub("%s*gold$", ""):gsub("%s*g$", "")
  local n, k = t:match("^(%d+%.?%d*)%s*(k?)$")
  n = tonumber(n)
  if not n then return nil end
  if k == "k" then n = n * 1000 end
  if n < 1 or n > R.MAX_BID then return nil end
  return math.floor(n)
end

--- the rolls that count, best first; the ones that don't after them
function R.standings(roll)
  local good, bad = {}, {}
  local ranks, plus = {}, {}        -- (worked out once for each roll, not in every comparison)
  for _, e in ipairs(roll.entries) do
    if e.kind then
      good[#good + 1] = e
      local r = rank(roll, e.kind)
      ranks[e] = r
      plus[e] = r == 2 and R.plusOnes(roll, e.p) or 0     -- main spec and boosted: fewer +1s first
    else bad[#bad + 1] = e end
  end
  table.sort(good, function(a, b)
    local ra, rb = ranks[a], ranks[b]
    if ra ~= rb then return ra < rb end
    local pa, pb = plus[a], plus[b]
    if pa ~= pb then return pa < pb end
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
    if rank(roll, e.kind) == rank(roll, top.kind) and e.n == top.n and (rank(roll, e.kind) ~= 2 or R.plusOnes(roll, e.p) == R.plusOnes(roll, top.p)) then
      tied[#tied + 1] = e.p
    else break end
  end
  if #tied > 1 then return top, tied end
  return top
end

--- everyone who may roll and hasn't rolled or passed yet (only known for SR and TIE rolls)
function R.waiting(roll)
  if roll.mode ~= "SR" and roll.mode ~= "TIE" and roll.mode ~= "PR" then return nil end
  local out = {}
  for _, w in ipairs(roll.who) do
    local name = type(w) == "table" and w[1] or w
    if R.rollsLeft(roll, name) > 0 and not roll.passed[key(name)] then out[#out + 1] = name end
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
