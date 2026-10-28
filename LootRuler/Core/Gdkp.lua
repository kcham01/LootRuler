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
--   rules    the organiser's own pot rules, in order: { { n = name, pct = percent of the pot, g = gold, to = { names } } };
--            each player named gets pct of the pot and g gold (older versions don't know them and leave them alone)
--   adds     gold put in the pot (or taken out) by hand: { { g = gold (- taken out), n = what for, at = when } }
--   log      every payment, in order: { { p = player, g = gold (as in paid), at = when, w = "trade" / "mail" / "hand" } }
--   fixed    "Name-Realm" -> their whole payout, set by hand (brought in from a spreadsheet): the rest is split evenly
--            between everyone else. Older versions don't know adds, log or fixed (their screens show the plain split).
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

---------------------------------------------------------------------- the organiser's own pot rules
G.MAX_RULES, G.MAX_RULE_PCT, G.MAX_RULE_TO, G.MAX_RULE_NAME = 10, 50, 40, 24

--- a rule's name, cleaned (no colours or links), or nil
local function ruleName(text)
  text = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", "")
  text = U.trim(text):sub(1, G.MAX_RULE_NAME)
  return text ~= "" and text or nil
end

--- adds a rule (nobody in it yet); returns its place, or nil
function G.addRule(s, name, now)
  if not s.gk then return nil end
  s.gk.rules = s.gk.rules or {}
  if #s.gk.rules >= G.MAX_RULES then return nil end
  table.insert(s.gk.rules, { n = ruleName(name) or ("Rule " .. (#s.gk.rules + 1)), to = {} })
  S.bump(s, now)
  return #s.gk.rules
end

--- changes a rule: { n = name, pct = percent of the pot (0 to G.MAX_RULE_PCT), g = gold }; returns whether it changed
function G.editRule(s, index, fields, now)
  local r = s.gk and s.gk.rules and s.gk.rules[index]
  if not r or type(fields) ~= "table" then return false end
  local changed = false
  if fields.n ~= nil then
    local n = ruleName(fields.n)
    if n and n ~= r.n then r.n = n changed = true end
  end
  if fields.pct ~= nil then
    local pct = num(fields.pct, 0, G.MAX_RULE_PCT)
    pct = pct and pct > 0 and pct or nil
    if pct ~= r.pct and (pct or fields.pct == 0) then r.pct = pct changed = true end
  end
  if fields.g ~= nil then
    local g = num(fields.g, 0, G.MAX_GOLD)
    g = g and g > 0 and math.floor(g) or nil
    if g ~= r.g and (g or fields.g == 0) then r.g = g changed = true end
  end
  if changed then S.bump(s, now) end
  return changed
end

--- takes a rule away
function G.removeRule(s, index, now)
  if not (s.gk and s.gk.rules and s.gk.rules[index]) then return false end
  table.remove(s.gk.rules, index)
  if #s.gk.rules == 0 then s.gk.rules = nil end
  S.bump(s, now)
  return true
end

--- puts a player in a rule, or takes them out
function G.ruleTo(s, index, player, on, now)
  local r = s.gk and s.gk.rules and s.gk.rules[index]
  if not r then return false end
  player = U.full(player)
  local i = U.indexOf(r.to, player)
  if on and not i and #r.to < G.MAX_RULE_TO then table.insert(r.to, player)
  elseif not on and i then table.remove(r.to, i)
  else return false end
  S.bump(s, now)
  return true
end

--- a rule in words: "5% of the pot and 100g each"
function G.ruleText(r)
  local parts = {}
  if r.pct then parts[#parts + 1] = r.pct .. "% of the pot" end
  if r.g then parts[#parts + 1] = G.gold(r.g) end
  if #parts == 0 then return "nothing yet" end
  return table.concat(parts, " and ") .. " each"
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

--- players whose bids aren't taken tonight (the organiser's call: someone who won't pay): names, at most G.MAX_NOBID
G.MAX_NOBID = 40
function G.setNoBids(s, player, on, now)
  if not s.gk or type(player) ~= "string" then return false end
  local list, at = s.gk.nb or {}, nil
  for i, name in ipairs(list) do if U.samePlayer(name, player) then at = i end end
  if on and not at then
    if #list >= G.MAX_NOBID then return false end
    list[#list + 1] = U.full(player)
  elseif not on and at then
    table.remove(list, at)
  else return false end
  s.gk.nb = #list > 0 and list or nil
  S.bump(s, now)
  return true
end
--- whose bids aren't taken, for a roll: name (lower case) -> name; nil when nobody's
function G.noBids(s)
  if not (s and s.gk and s.gk.nb) then return nil end
  local out = {}
  for _, name in ipairs(s.gk.nb) do out[LR.Roll.key(name)] = name end
  return out
end

--- the lowest first bid for an item
function G.minFor(s, id) return (s.gk and s.gk.prices[id]) or (s.gk and s.gk.min) or G.DEFAULTS.min end
function G.setPrice(s, id, gold, now)
  if not s.gk then return false end
  s.gk.prices[id] = num(gold, 0, G.MAX_GOLD) and math.floor(gold) or nil
  S.bump(s, now)
  return true
end

--- a sale's price changed (a mistake, or a discount): index is its place in s.won
function G.setSalePrice(s, index, gold, now)
  local w = s.won and s.won[index]
  gold = num(gold, 0, G.MAX_GOLD)
  if not w or w.k ~= "BID" or not gold or tonumber(w.r) == math.floor(gold) then return false end
  w.r = math.floor(gold)
  S.bump(s, now)
  return true
end

--- starting bids from text, one item a line: its number or link, then the gold ("28525: 500", "28525,500g").
--- Returns item id -> gold, and how many lines weren't understood.
function G.parsePrices(text)
  local out, bad = {}, 0
  for line in tostring(text or ""):gmatch("[^\r\n]+") do
    if line:find("%S") then
      local id, g = line:match("item:(%d+)[^|]*|h[^|]*|h|r%s*[:,;=%-]?%s*([%d%.,]+)%s*[gG]?%s*$")
      if not id then id, g = line:match("^%s*(%d+)%s*[:,;=%-]%s*([%d%.,]+)%s*[gG]?%s*$") end
      g = g and tonumber((g:gsub(",", "")))
      if id and tonumber(id) > 0 and g and g >= 0 and g <= G.MAX_GOLD then out[tonumber(id)] = math.floor(g) else bad = bad + 1 end
    end
  end
  return out, bad
end

--- the starting bids as text, one a line, by item number
function G.pricesText(s)
  local ids = {}
  for id in pairs(s.gk and s.gk.prices or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  local lines = {}
  for _, id in ipairs(ids) do lines[#lines + 1] = id .. ": " .. s.gk.prices[id] end
  return table.concat(lines, "\n")
end

--- several starting bids at once (from G.parsePrices); returns how many changed
function G.setPrices(s, prices, now)
  if not s.gk then return 0 end
  local n = 0
  for id, g in pairs(prices) do
    if s.gk.prices[id] ~= g then s.gk.prices[id] = g n = n + 1 end
  end
  if n > 0 then S.bump(s, now) end
  return n
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

G.MAX_LOG, G.MAX_ADDS, G.MAX_NOTE = 300, 100, 40

--- gold changed hands with a player: + they gave the organiser gold, - the organiser gave them gold.
--- how: "trade", "mail" or "hand" (marked as settled), for the ledger
function G.paid(s, player, gold, now, how)
  player = U.full(player)
  gold = tonumber(gold)
  if not s.gk or not gold or gold == 0 then return false end
  s.gk.paid[player] = (s.gk.paid[player] or 0) + gold
  if math.abs(s.gk.paid[player]) < 0.0001 then s.gk.paid[player] = nil end
  s.gk.log = s.gk.log or {}
  table.insert(s.gk.log, { p = player, g = gold, at = now, w = (how == "trade" or how == "mail") and how or "hand" })
  while #s.gk.log > G.MAX_LOG do table.remove(s.gk.log, 1) end
  S.bump(s, now)
  return true
end

local function note(text)
  text = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", "")
  return U.trim(text):sub(1, G.MAX_NOTE)
end

--- gold put in the pot by hand (vendor money, a donation), or taken out (repairs: a negative amount), with what for
function G.addGold(s, gold, what, now)
  gold = tonumber(gold)
  if not s.gk or not gold or gold == 0 or math.abs(gold) > G.MAX_GOLD then return false end
  s.gk.adds = s.gk.adds or {}
  if #s.gk.adds >= G.MAX_ADDS then return false end
  table.insert(s.gk.adds, { g = math.floor(gold), n = note(what), at = now })
  S.bump(s, now)
  return true
end
function G.removeAdd(s, index, now)
  if not (s.gk and s.gk.adds and s.gk.adds[index]) then return false end
  table.remove(s.gk.adds, index)
  if #s.gk.adds == 0 then s.gk.adds = nil end
  S.bump(s, now)
  return true
end
--- the gold put in (or taken out) by hand, in all
function G.added(s)
  local n = 0
  for _, a in ipairs(s.gk and s.gk.adds or {}) do n = n + a.g end
  return n
end

--- a player's whole payout set by hand (nil: back to their share of the split)
function G.setFixed(s, player, gold, now)
  if not s.gk then return false end
  player = U.full(player)
  gold = gold ~= nil and num(gold, 0, G.MAX_GOLD) or nil
  gold = gold and math.floor(gold) or nil
  s.gk.fixed = s.gk.fixed or {}
  if s.gk.fixed[player] == gold then return false end
  s.gk.fixed[player] = gold
  if not next(s.gk.fixed) then s.gk.fixed = nil end
  S.bump(s, now)
  return true
end
--- payouts set by hand from "Name,Gold" lines ({ { p, n } }, Prio.parseCounts); replaces any set before. Returns how many.
function G.setFixedAll(s, list, now)
  if not s.gk then return 0 end
  s.gk.fixed = nil
  local n = 0
  for _, x in ipairs(list or {}) do
    if n < G.MAX_PEOPLE and G.setFixed(s, x.p, x.n, now) then n = n + 1 end
  end
  S.bump(s, now)
  return n
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

--- the pot: what was sold, and gold put in (or taken out) by hand; never below nothing
function G.pot(s)
  local n = 0
  for _, x in ipairs(G.sales(s)) do n = n + x.g end
  return math.max(0, n + G.added(s))
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

--- the split: { pot, cut (the organiser's), bonuses, roles, rules (the organiser's own rules; ruleTotals: rule's place ->
--- gold), share (each player's), players, rows = { name -> { spent, bonus, roleCut, ruleCut, ruleNames, gets (share and
--- the rest), paid, owed } } }. owed > 0: the organiser gives them that much; < 0: they give
--- the organiser that much. Shares are whole gold; what's left over by rounding stays with the organiser.
function G.split(s)
  local pot = G.pot(s)
  local gk = s.gk or {}
  local cut = math.floor(pot * (gk.cut or 0) / 100)
  local players = G.players(s)
  -- a payout set by hand is all that player gets: no share, bonus or cut on top
  local fixed = gk.fixed or {}
  local function counts(name) return not (gk.out and gk.out[name]) and not fixed[name] end
  local bonuses = 0
  for name, b in pairs(gk.bonus or {}) do if counts(name) then bonuses = bonuses + b end end
  bonuses = math.min(bonuses, pot - cut)
  -- cuts by role: a percent of the pot for each player in the role (tanks, healers), out of what's left
  local rolePay, roles = {}, 0
  for name, role in pairs(gk.role or {}) do
    local pct = gk.rp and gk.rp[role] or 0
    if pct > 0 and counts(name) then
      rolePay[name] = math.floor(pot * pct / 100)
      roles = roles + rolePay[name]
    end
  end
  if roles > pot - cut - bonuses then         -- (never more than there is: each is cut down to fit)
    local scale = roles > 0 and (pot - cut - bonuses) / roles or 0
    roles = 0
    for name, g in pairs(rolePay) do rolePay[name] = math.floor(g * scale) roles = roles + rolePay[name] end
  end
  -- the organiser's own rules: each player named gets the rule's percent of the pot and its gold, out of what's left
  local rulePay, ruleNames, rules, ruleTotals = {}, {}, 0, {}
  for i, r in ipairs(gk.rules or {}) do
    for _, name in ipairs(r.to or {}) do
      local g = math.floor(pot * (r.pct or 0) / 100) + (r.g or 0)
      if g > 0 and counts(name) then
        rulePay[name] = (rulePay[name] or 0) + g
        ruleNames[name] = ruleNames[name] or {}
        table.insert(ruleNames[name], r.n)
        ruleTotals[i] = (ruleTotals[i] or 0) + g
        rules = rules + g
      end
    end
  end
  local left = pot - cut - bonuses - roles
  if rules > left then                        -- (never more than there is: each is cut down to fit)
    local scale = rules > 0 and left / rules or 0
    rules = 0
    for name, g in pairs(rulePay) do rulePay[name] = math.floor(g * scale) rules = rules + rulePay[name] end
    for i, g in pairs(ruleTotals) do ruleTotals[i] = math.floor(g * scale) end
  end
  local rest = pot - cut - bonuses - roles - rules
  -- payouts set by hand, out of what's left (made smaller if they'd be more); everyone else splits the rest
  local fixedPay, fixedTotal, sharers = {}, 0, 0
  for _, p in ipairs(players) do
    if fixed[p] then fixedPay[p] = fixed[p] fixedTotal = fixedTotal + fixed[p] else sharers = sharers + 1 end
  end
  if fixedTotal > rest then
    local scale = fixedTotal > 0 and rest / fixedTotal or 0
    fixedTotal = 0
    for p, g in pairs(fixedPay) do fixedPay[p] = math.floor(g * scale) fixedTotal = fixedTotal + fixedPay[p] end
  end
  rest = rest - fixedTotal
  local share = sharers > 0 and math.floor(rest / sharers) or 0
  local rows = {}
  local spent = {}
  for _, x in ipairs(G.sales(s)) do spent[x.p] = (spent[x.p] or 0) + x.g end
  local everyone = {}
  for _, p in ipairs(players) do everyone[p] = true end
  for p in pairs(spent) do everyone[p] = true end
  for p in pairs(gk.paid or {}) do everyone[p] = true end
  for p in pairs(everyone) do
    local inSplit = not (gk.out and gk.out[p])
    local isFixed = inSplit and fixedPay[p] ~= nil
    local bonus = (inSplit and not isFixed) and (gk.bonus and gk.bonus[p]) or 0
    local roleCut = inSplit and rolePay[p] or 0
    local ruleCut = inSplit and rulePay[p] or 0
    local gets = isFixed and fixedPay[p] or (inSplit and (share + bonus + roleCut + ruleCut) or 0)
    local paid = gk.paid and gk.paid[p] or 0
    rows[p] = { spent = spent[p] or 0, bonus = bonus, role = gk.role and gk.role[p], roleCut = roleCut, ruleCut = ruleCut,
      ruleNames = ruleCut > 0 and ruleNames[p] or nil, fixed = isFixed or nil, gets = gets, paid = paid,
      owed = gets - (spent[p] or 0) + paid, out = not inSplit }
  end
  return { pot = pot, cut = cut, bonuses = bonuses, roles = roles, rules = rules, ruleTotals = ruleTotals, fixed = fixedTotal, sharers = sharers,
    added = G.added(s), share = share, players = players, rows = rows }
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

---------------------------------------------------------------------- the ledger, and the payouts as text
--- everything the gold did, oldest first: { at, kind = "sale" / "add" / "trade" / "mail" / "hand", p, g, i (sales), n (adds) }
function G.ledger(s)
  local out = {}
  for _, w in ipairs(s.won or {}) do
    if w.k == "BID" and tonumber(w.r) then out[#out + 1] = { at = w.at or 0, kind = "sale", p = w.p, g = tonumber(w.r), i = w.i } end
  end
  for _, a in ipairs(s.gk and s.gk.adds or {}) do out[#out + 1] = { at = a.at or 0, kind = "add", g = a.g, n = a.n } end
  for _, x in ipairs(s.gk and s.gk.log or {}) do out[#out + 1] = { at = x.at or 0, kind = x.w, p = x.p, g = x.g } end
  -- (sorted by time; same time: the order they were made in)
  for i, e in ipairs(out) do e.seq = i end
  table.sort(out, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.seq < b.seq end)
  return out
end

--- the payouts as text: "sheet" (a spreadsheet: Name,Bought,Payout,Paid,Owed) or "cuts" ("Name,Gold" lines of each
--- payout, which bring back in as payouts set by hand)
function G.payoutsText(s, format)
  local split = G.split(s)
  local names = {}
  for name, row in pairs(split.rows) do if not row.out then names[#names + 1] = name end end
  table.sort(names)
  local lines = {}
  if format == "cuts" then
    for _, name in ipairs(names) do lines[#lines + 1] = ("%s,%d"):format(U.short(name), split.rows[name].gets) end
  else
    lines[1] = "Name,Bought,Payout,Paid,Owed"
    for _, name in ipairs(names) do
      local r = split.rows[name]
      local function amount(v) return (("%.2f"):format(v):gsub("%.00$", "")) end
      lines[#lines + 1] = ("%s,%d,%d,%s,%s"):format(U.short(name), r.spent, r.gets, amount(r.paid), amount(r.owed))
    end
  end
  return table.concat(lines, "\n")
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
  if gk.nb ~= nil then
    if type(gk.nb) ~= "table" or #gk.nb > G.MAX_NOBID then return false end
    for _, name in ipairs(gk.nb) do if type(name) ~= "string" or #name > 60 then return false end end
  end
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
  if gk.fixed ~= nil and not map(gk.fixed, "string", "number") then return false end
  if gk.adds ~= nil then
    if type(gk.adds) ~= "table" or #gk.adds > G.MAX_ADDS then return false end
    for _, a in ipairs(gk.adds) do
      if type(a) ~= "table" or type(a.g) ~= "number" or math.abs(a.g) > G.MAX_GOLD or (a.n ~= nil and type(a.n) ~= "string")
        or (a.at ~= nil and type(a.at) ~= "number") then return false end
    end
  end
  if gk.log ~= nil then
    if type(gk.log) ~= "table" or #gk.log > G.MAX_LOG then return false end
    for _, x in ipairs(gk.log) do
      if type(x) ~= "table" or type(x.p) ~= "string" or type(x.g) ~= "number" or (x.at ~= nil and type(x.at) ~= "number")
        or (x.w ~= nil and type(x.w) ~= "string") then return false end
    end
  end
  if gk.rules ~= nil then
    if type(gk.rules) ~= "table" or #gk.rules > G.MAX_RULES then return false end
    for _, r in ipairs(gk.rules) do
      if type(r) ~= "table" or type(r.n) ~= "string" or #r.n > 40 or type(r.to) ~= "table" or #r.to > G.MAX_RULE_TO then return false end
      if r.pct ~= nil and (type(r.pct) ~= "number" or r.pct < 0 or r.pct > 100) then return false end
      if r.g ~= nil and (type(r.g) ~= "number" or r.g < 0 or r.g > G.MAX_GOLD) then return false end
      for _, name in ipairs(r.to) do if type(name) ~= "string" then return false end end
    end
  end
  return map(gk.bonus, "string", "number") and map(gk.seen, "string", "boolean") and map(gk.out, "string", "boolean")
    and map(gk.paid, "string", "number") and map(gk.prices, "number", "number")
end
