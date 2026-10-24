-- GDKP: items are auctioned for gold instead of rolled for, the gold goes into a pot, and at the end the pot
-- is split between everyone who came (after the organiser's cut and any bonuses). This file is the rules and
-- the money, with no game calls (tested on its own in tests/rolls.lua). The auctions are rolls of mode "BID"
-- (Core/Roll.lua, Core/Rolls.lua); a sale is an award of kind "BID" whose r is the price.
--
-- A session with GDKP on has s.gdkp = true and s.gk:
--   min      the lowest first bid (gold)            inc   each bid at least this much more (gold)
--   cut      the organiser's cut (percent)          bonus "Name-Realm" -> extra gold out of the pot (tanks, healers...)
--   seen     "Name-Realm" -> true: everyone who was in the group (their share)
--   out      "Name-Realm" -> true: left out of the split by the leader
--   paid     "Name-Realm" -> gold handed over in trades: what they gave the organiser, less what they got
--   prices   item id -> its lowest first bid, when it isn't min
--   rp       role -> the cut each player in it gets, as a percent of the pot ({ tank = 2, healer = 1 })
--   role     "Name-Realm" -> "tank" / "healer": who's in which role (the leader picks)
--   strict   bids must start with "bid" ("bid 150"), so someone saying "500" in raid chat doesn't bid
-- Addons can't put gold in a trade, so LootRuler says who owes what and counts what changes hands.
local _, LR = ...
local U, S = LR.U, LR.Session

local G = {}
LR.Gdkp = G

G.DEFAULTS = { min = 100, inc = 10, cut = 10 }
G.MAX_GOLD = 10000000
G.MAX_PEOPLE = 80

local function num(v, lo, hi) v = tonumber(v) return v and v >= lo and v <= hi and v or nil end

--- turns GDKP on or off for a session (its settings stay, in case it's turned on again)
function G.set(s, on, now)
  on = on and true or false
  if (s.gdkp or false) == on then return false end
  s.gdkp = on
  if on then
    s.gk = s.gk or { min = G.DEFAULTS.min, inc = G.DEFAULTS.inc, cut = G.DEFAULTS.cut, bonus = {}, seen = {}, out = {}, paid = {}, prices = {} }
    s.prio = nil                -- an auction decides, not priority lists
  end
  S.bump(s, now)
  return true
end

--- changes one of min, inc, cut
function G.option(s, key, value, now)
  local limits = { min = { 0, G.MAX_GOLD }, inc = { 1, G.MAX_GOLD }, cut = { 0, 100 } }
  if not s.gk or not limits[key] then return false end
  value = num(value, limits[key][1], limits[key][2])
  if not value or s.gk[key] == value then return false end
  s.gk[key] = math.floor(value)
  S.bump(s, now)
  return true
end

G.ROLES = { { "tank", "Tanks", "tank" }, { "healer", "Healers", "healer" } }
local ROLE = { tank = true, healer = true }
G.MAX_ROLE_PCT = 10

--- the cut every player in a role gets (a percent of the pot each; 0: none)
function G.setRoleCut(s, role, pct, now)
  pct = tonumber(pct)
  if not s.gk or not ROLE[role] or not pct or pct < 0 or pct > G.MAX_ROLE_PCT then return false end
  s.gk.rp = s.gk.rp or {}
  if (s.gk.rp[role] or 0) == pct then return false end
  s.gk.rp[role] = pct > 0 and pct or nil
  S.bump(s, now)
  return true
end

--- puts a player in a role (nil: none)
function G.setRole(s, player, role, now)
  if not s.gk or (role ~= nil and not ROLE[role]) then return false end
  player = U.full(player)
  s.gk.role = s.gk.role or {}
  if s.gk.role[player] == role then return false end
  s.gk.role[player] = role
  S.bump(s, now)
  return true
end

--- whether a bid has to start with "bid"
function G.setStrict(s, on, now)
  if not s.gk then return false end
  on = on and true or nil
  if s.gk.strict == on then return false end
  s.gk.strict = on
  S.bump(s, now)
  return true
end

--- the lowest first bid for an item
function G.minFor(s, id) return (s.gk and s.gk.prices[id]) or (s.gk and s.gk.min) or G.DEFAULTS.min end
function G.setPrice(s, id, gold, now)
  if not s.gk then return false end
  s.gk.prices[id] = num(gold, 0, G.MAX_GOLD) and math.floor(gold) or nil
  S.bump(s, now)
  return true
end

--- everyone in the group now counts for a share (the leader calls this as the group changes)
function G.saw(s, names, now)
  if not s.gdkp then return false end
  local added, n = false, 0
  for _ in pairs(s.gk.seen) do n = n + 1 end
  for _, name in ipairs(names) do
    name = U.full(name)
    if not s.gk.seen[name] and n < G.MAX_PEOPLE then s.gk.seen[name] = true n = n + 1 added = true end
  end
  if added then S.bump(s, now) end
  return added
end

function G.setOut(s, player, out, now)
  player = U.full(player)
  if (s.gk.out[player] or false) == (out and true or false) then return false end
  s.gk.out[player] = out and true or nil
  S.bump(s, now)
  return true
end

function G.setBonus(s, player, gold, now)
  player = U.full(player)
  gold = num(gold, 0, G.MAX_GOLD)
  if not gold then return false end
  s.gk.bonus[player] = gold > 0 and math.floor(gold) or nil
  S.bump(s, now)
  return true
end

--- gold changed hands with a player: + they gave the organiser gold, - the organiser gave them gold
function G.paid(s, player, gold, now)
  player = U.full(player)
  gold = tonumber(gold)
  if not s.gk or not gold or gold == 0 then return false end
  s.gk.paid[player] = (s.gk.paid[player] or 0) + gold
  if math.abs(s.gk.paid[player]) < 0.0001 then s.gk.paid[player] = nil end
  S.bump(s, now)
  return true
end

---------------------------------------------------------------------- the pot
--- what was sold: { { i = item, p = buyer, g = gold }, ... }
function G.sales(s)
  local out = {}
  for _, w in ipairs(s.won or {}) do
    if w.k == "BID" and tonumber(w.r) then out[#out + 1] = { i = w.i, p = w.p, g = tonumber(w.r) } end
  end
  return out
end

function G.pot(s)
  local n = 0
  for _, x in ipairs(G.sales(s)) do n = n + x.g end
  return n
end

--- who the pot is split between: everyone who was in the group, and everyone who bought something, but not
--- anyone the leader left out
function G.players(s)
  local set = {}
  for name in pairs(s.gk and s.gk.seen or {}) do set[name] = true end
  for _, x in ipairs(G.sales(s)) do set[x.p] = true end
  local out = {}
  for name in pairs(set) do if not (s.gk and s.gk.out[name]) then out[#out + 1] = name end end
  table.sort(out)
  return out
end

--- the split: { pot, cut (the organiser's), bonuses, share (each player's), players, rows = { name -> { spent,
--- bonus, gets (share + bonus), paid, owed } } }. owed > 0: the organiser gives them that much; < 0: they give
--- the organiser that much. Shares are whole gold; what's left over by rounding stays with the organiser.
function G.split(s)
  local pot = G.pot(s)
  local gk = s.gk or {}
  local cut = math.floor(pot * (gk.cut or 0) / 100)
  local players = G.players(s)
  local bonuses = 0
  for name, b in pairs(gk.bonus or {}) do if not (gk.out and gk.out[name]) then bonuses = bonuses + b end end
  bonuses = math.min(bonuses, pot - cut)
  -- cuts by role: a percent of the pot for each player in the role (tanks, healers), out of what's left
  local rolePay, roles = {}, 0
  for name, role in pairs(gk.role or {}) do
    local pct = gk.rp and gk.rp[role] or 0
    if pct > 0 and not (gk.out and gk.out[name]) then
      rolePay[name] = math.floor(pot * pct / 100)
      roles = roles + rolePay[name]
    end
  end
  if roles > pot - cut - bonuses then         -- (never more than there is: each is cut down to fit)
    local scale = roles > 0 and (pot - cut - bonuses) / roles or 0
    roles = 0
    for name, g in pairs(rolePay) do rolePay[name] = math.floor(g * scale) roles = roles + rolePay[name] end
  end
  local rest = pot - cut - bonuses - roles
  local share = #players > 0 and math.floor(rest / #players) or 0
  local rows = {}
  local spent = {}
  for _, x in ipairs(G.sales(s)) do spent[x.p] = (spent[x.p] or 0) + x.g end
  local everyone = {}
  for _, p in ipairs(players) do everyone[p] = true end
  for p in pairs(spent) do everyone[p] = true end
  for p in pairs(gk.paid or {}) do everyone[p] = true end
  for p in pairs(everyone) do
    local inSplit = not (gk.out and gk.out[p])
    local bonus = inSplit and (gk.bonus and gk.bonus[p]) or 0
    local roleCut = inSplit and rolePay[p] or 0
    local gets = inSplit and (share + bonus + roleCut) or 0
    local paid = gk.paid and gk.paid[p] or 0
    rows[p] = { spent = spent[p] or 0, bonus = bonus, role = gk.role and gk.role[p], roleCut = roleCut, gets = gets, paid = paid,
      owed = gets - (spent[p] or 0) + paid, out = not inSplit }
  end
  return { pot = pot, cut = cut, bonuses = bonuses, roles = roles, share = share, players = players, rows = rows }
end

--- who still owes the organiser or is owed by them: { { name, owed } }, biggest first (not the organiser)
function G.unsettled(s)
  local out = {}
  if not s.gdkp or not s.gk then return out end
  for name, row in pairs(G.split(s).rows) do
    if math.abs(row.owed) >= 0.01 and not U.samePlayer(name, s.leader) then out[#out + 1] = { name, row.owed } end
  end
  table.sort(out, function(a, b) return math.abs(a[2]) > math.abs(b[2]) end)
  return out
end

--- "1,250g" (whole gold; silver and copper as "12g 50s" when there are any)
function G.gold(g)
  g = tonumber(g) or 0
  local neg = g < 0
  g = math.abs(g)
  local whole = math.floor(g + 0.00005)
  local silver = math.floor((g - whole) * 100 + 0.5)
  local s = tostring(whole):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return (neg and "-" or "") .. s .. "g" .. (silver > 0 and (" " .. silver .. "s") or "")
end

--- a session's GDKP part, from another player, checked
function G.valid(gk)
  if gk == nil then return true end
  if type(gk) ~= "table" then return false end
  for _, k in ipairs({ "min", "inc", "cut" }) do if type(gk[k]) ~= "number" then return false end end
  if gk.strict ~= nil and type(gk.strict) ~= "boolean" then return false end
  local function map(t, keyType, valType)
    if type(t) ~= "table" then return false end
    local n = 0
    for k, v in pairs(t) do
      n = n + 1
      if n > 500 or type(k) ~= keyType or type(v) ~= valType then return false end
    end
    return true
  end
  if gk.rp ~= nil and not map(gk.rp, "string", "number") then return false end
  if gk.role ~= nil and not map(gk.role, "string", "string") then return false end
  return map(gk.bonus, "string", "number") and map(gk.seen, "string", "boolean") and map(gk.out, "string", "boolean")
    and map(gk.paid, "string", "number") and map(gk.prices, "number", "number")
end
