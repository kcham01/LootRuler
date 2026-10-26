-- Bag checks: whoever runs loot asks the group how many of some items each player carries (flasks, keys, an attunement
-- item), and every LootRuler in the group answers by whisper with its player's bags and bank. Players without the
-- addon can't be asked: the report says so, and one raid line can name who's missing what. A player can switch
-- answering off (Settings: answerBagChecks).
--
-- Messages (on top of Core/Net.lua's):
--   K  loot runner -> group    { k, i = item ids (Bags.MAX at most) }: "how many of these do you have?"
--   J  raider -> loot runner   { k, c = { [id] = how many } }: the answer, by whisper
-- Older versions don't know them and don't answer: the report lists them as not answering.
local _, LR = ...
local U = LR.U
local Net = LR.Net

local Bags = {}
LR.Bags = Bags

Bags.MAX = 10
Bags.WAIT = 5              -- seconds to wait for answers before the report says who didn't answer
local MAX_COUNT = 100000

--- how many of an item I carry: bags and bank
function Bags.count(id)
  if not (C_Item and C_Item.GetItemCount) then return 0 end
  return tonumber(C_Item.GetItemCount(id, true)) or 0
end

--- the check I asked last: { k, ids, at, answers = { ["Name-Realm"] = { [id] = n } }, done = waited long enough }
Bags.last = nil

--- asks the group about up to Bags.MAX items; returns the check, or nil and why not
function Bags.ask(ids)
  if not LR.canRunLoot() then return nil, "Only the raid leader, an assistant or the master looter can ask." end
  local list, seen = {}, {}
  for _, id in ipairs(ids or {}) do
    if type(id) == "number" and id > 0 and not seen[id] and #list < Bags.MAX then seen[id] = true list[#list + 1] = id end
  end
  if #list == 0 then return nil, "Pick at least one item." end
  local check = { k = U.me() .. ":bags:" .. U.now(), ids = list, at = GetTime(), answers = {} }
  Bags.last = check
  -- mine, straight away
  local mine = {}
  for _, id in ipairs(list) do mine[id] = Bags.count(id) end
  check.answers[U.me()] = mine
  local ch = LR.groupChannel()
  if ch then Net.send({ t = "K", k = check.k, i = list }, ch) end
  if LR.Practice.on then LR.Practice.answerBags(check) end
  C_Timer.After(Bags.WAIT, function() if Bags.last == check then check.done = true LR.changed("bags") end end)
  LR.changed("bags")
  return check
end

--- an answer came in (or a pretend one, in a practice raid)
function Bags.answered(check, player, counts)
  if Bags.last ~= check then return end
  local c = {}
  for _, id in ipairs(check.ids) do
    local n = counts[id]
    c[id] = type(n) == "number" and math.max(0, math.min(MAX_COUNT, math.floor(n))) or 0
  end
  check.answers[U.full(player)] = c
  LR.changed("bags")
end

--- the report: everyone in the group, their counts (nil: couldn't be asked, or didn't answer), and what each lacks
--- { { name, class, counts or nil, why = "none" (no LootRuler) / "waiting" / "silent" } }
function Bags.report(check)
  check = check or Bags.last
  local out = {}
  if not check then return out end
  for _, m in ipairs(LR.roster()) do
    local name = U.full(m.name)
    local counts = check.answers[name]
    local why
    if not counts then
      if not LR.versionOf(name) and not LR.Practice.isPretend(name) then why = "none"
      elseif check.done then why = "silent" else why = "waiting" end
    end
    out[#out + 1] = { name = name, class = m.class, counts = counts, why = why }
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

--- who answered and has none of each item: { [id] = { names } }
function Bags.missing(check)
  check = check or Bags.last
  local out = {}
  if not check then return out end
  for _, id in ipairs(check.ids) do
    out[id] = {}
    for _, r in ipairs(Bags.report(check)) do
      if r.counts and (r.counts[id] or 0) == 0 then table.insert(out[id], r.name) end
    end
  end
  return out
end

--- one raid line for each item someone lacks: "Missing [Flask]: Ann, Bob."; returns how many lines
function Bags.postMissing(check)
  check = check or Bags.last
  local ch = LR.groupChannel()
  if not check or not ch then return 0 end
  local n = 0
  for _, id in ipairs(check.ids) do
    local who = Bags.missing(check)[id]
    if #who > 0 then
      local text = ("%s Missing %s: %s."):format(LR.TAG, LR.itemLink(id), table.concat(U.map(who, U.short), ", "))
      for _, line in ipairs(U.chatLines(text, 255)) do LR.say(line, ch) end
      n = n + 1
    end
  end
  return n
end

---------------------------------------------------------------------- answering
local answered = {}        -- check key -> true (each is answered once)

Net.handlers.K = function(msg, channel, sender)
  if channel == "WHISPER" or type(msg.k) ~= "string" or #msg.k > 120 or type(msg.i) ~= "table" then return end
  if U.samePlayer(sender, U.me()) or not LR.canRunLoot(sender) or answered[msg.k] then return end
  if not LR.db.settings.answerBagChecks then return end
  answered[msg.k] = true
  local c, n = {}, 0
  for _, id in ipairs(msg.i) do
    if type(id) == "number" and id > 0 and id % 1 == 0 then
      n = n + 1
      if n > Bags.MAX then break end
      c[id] = Bags.count(id)
    end
  end
  Net.send({ t = "J", k = msg.k, c = c }, "WHISPER", sender)
end

Net.handlers.J = function(msg, channel, sender)
  local check = Bags.last
  if channel ~= "WHISPER" or not check or msg.k ~= check.k or type(msg.c) ~= "table" then return end
  if not LR.inGroup(sender) then return end
  local c = {}
  for _, id in ipairs(check.ids) do c[id] = msg.c[id] end
  Bags.answered(check, sender, c)
end
