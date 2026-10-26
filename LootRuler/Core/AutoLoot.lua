-- Auto-loot: the master looter's rules for loot nobody needs to roll for, applied when a corpse is opened.
-- "Green items to the disenchanter", "recipes and patterns to me", "this item to Ann". The first rule that
-- matches an item decides. An item anyone has soft or hard reserved is never handed out by a rule: it's
-- rolled for as usual. Off until the loot master turns it on (Settings tab).
--
-- A rule: { what = "q0".."q4" (a quality: poor to epic) / "lt3" / "lt4" (anything below rare, below epic) / "recipe" /
--           "gem" / "trade" / "item:<id>", to = "de" (the disenchanter) / "me" / "Name-Realm" / "rr" (everyone in
--           the group in turn) / "skip" (left where it is: nothing else is done with it) }
-- Picking up the gold (setting lootGold) is its own switch.
local _, LR = ...
local U, S = LR.U, LR.Session
local Rolls = LR.Rolls

local A = {}
LR.AutoLoot = A

A.WHAT = {
  { "q0", "Poor (grey) items" },
  { "q1", "Common (white) items" },
  { "q2", "Uncommon (green) items" },
  { "q3", "Rare (blue) items" },
  { "q4", "Epic (purple) items" },
  { "recipe", "Recipes and patterns" },
  { "gem", "Gems" },
  { "trade", "Trade goods" },
  { "lt3", "Anything below rare" },
  { "lt4", "Anything below epic" },
}
local WHAT_NAME = {}
for _, w in ipairs(A.WHAT) do WHAT_NAME[w[1]] = w[2] end
local CLASS_OF = { recipe = 9, gem = 3, trade = 7 }

--- an item's class (9 recipe, 3 gem, 7 trade goods, ...), from the loot lists or the game
function LR.itemClass(id)
  local it = LR.ITEMS[id]
  if it then return it[4] end
  if C_Item and C_Item.GetItemInfoInstant then
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(id)
    return classID
  end
end

--- what a rule is about, for people
function A.whatText(what)
  local id = tonumber(tostring(what):match("^item:(%d+)$"))
  if id then return LR.itemLink(id) end
  return WHAT_NAME[what] or tostring(what)
end
function A.toText(to, s)
  if to == "de" then return "the disenchanter" .. ((s and s.de) and (" (" .. U.short(s.de) .. ")") or "") end
  if to == "me" then return "me" end
  if to == "rr" then return "everyone in turn" end
  if to == "skip" then return "nobody: it's left where it is" end
  return U.short(to)
end

--- whether a rule is about an item (of quality q)
function A.matches(rule, id, q)
  local what = rule.what
  local item = tonumber(tostring(what):match("^item:(%d+)$"))
  if item then return item == id end
  local quality = tonumber(tostring(what):match("^q(%d)$"))
  if quality then return q == quality end
  local below = tonumber(tostring(what):match("^lt(%d)$"))
  if below then return q ~= nil and q < below end
  if CLASS_OF[what] then return LR.itemClass(id) == CLASS_OF[what] end
  return false
end

--- who a rule gives an item to ("Name-Realm"), or nil when it can't (no disenchanter, say)
-- round robin: who had the last item, by name; the next is whoever comes after them in the group, by name
A.lastInTurn = nil
--- whose turn it is in the group (by name, after whoever had the last one), or nil out of a group
function A.nextInTurn()
  local names = {}
  for _, m in ipairs(LR.roster()) do if m.online ~= false then names[#names + 1] = m.name end end
  if #names == 0 then return nil end
  table.sort(names)
  for _, n in ipairs(names) do if A.lastInTurn and n > A.lastInTurn then return n end end
  return names[1]
end

function A.target(rule, s)
  if rule.to == "skip" then return nil end
  if rule.to == "rr" then return A.nextInTurn() end
  if rule.to == "de" then return s and s.de end
  if rule.to == "me" then return U.me() end
  return type(rule.to) == "string" and U.full(rule.to) or nil
end

--- whether an item is spoken for: someone reserved it (soft or hard) and it hasn't gone to them
local function spokenFor(s, id)
  if not s then return false end
  if s.hr[id] then return true end
  -- someone here is on the guild's priority list for it (when the session goes by them)
  if s.prio and LR.Guild and LR.Guild.prioPlan(id) then return true end
  for _, w in ipairs(S.byItem(s)[id] or {}) do if S.claims(s, w[1], id) > 0 then return true end end
  return false
end
A.spokenFor = spokenFor

--- the first rule for an item in a loot slot, and who it goes to; nil when none applies
function A.ruleFor(rules, s, id, q)
  if spokenFor(s, id) then return nil end
  for _, rule in ipairs(rules or {}) do
    if A.matches(rule, id, q) then
      local to = A.target(rule, s)
      if to then return rule, to end
      return nil                 -- the first matching rule decides, even when it can't be followed
    end
  end
end

--- the open loot window: hands out what the rules say, one item at a time
function A.apply()
  local set = LR.db.settings
  if not Rolls.lootOpen or not IsInGroup() or not LR.isMasterLooter() then return end
  -- the gold, when that's on (the game shares it out)
  if set.lootGold then
    for slot = 1, GetNumLootItems() do
      if GetLootSlotType(slot) == 2 then LootSlot(slot) end
    end
  end
  if not set.autoLoot then return end
  local s = Rolls.session()
  local jobs = {}
  for _, it in ipairs(Rolls.loot()) do
    local rule, to = A.ruleFor(set.autoLootRules, s, it.id, it.quality)
    if rule then
      if rule.to == "rr" then A.lastInTurn = to end      -- (each in turn: the next item goes to the next player)
      jobs[#jobs + 1] = { slot = it.slot, id = it.id, link = it.link, to = to, de = rule.to == "de" }
    end
  end
  local given = {}
  local function step(i)
    local job = jobs[i]
    if not job then
      if #given > 0 then
        Rolls.say("Handed out by the loot rules: " .. table.concat(given, ", ") .. ".")
      end
      return
    end
    if Rolls.lootOpen and LootSlotHasItem(job.slot) then
      local idx
      for c = 1, 40 do
        local name = GetMasterLootCandidate(job.slot, c)
        if name and U.samePlayer(U.full(name), job.to) then idx = c break end
      end
      if idx then
        GiveMasterLoot(job.slot, idx)
        given[#given + 1] = job.link .. " to " .. U.short(job.to) .. (job.de and " (disenchant)" or "")
        -- the disenchanter's items go on the list of loot given out, like a Disenchant click
        if job.de and s and LR.isLeader(s) and S.award(s, job.id, job.to, "OS", nil, U.now(), LR.Drops.forSlot(job.slot), true) then
          LR.leaderChanged(s)
        end
      else
        LR.print(("couldn't give %s to %s by the loot rules (not on the loot list: too far away?)."):format(job.link, U.short(job.to)))
      end
    end
    C_Timer.After(0.2, function() step(i + 1) end)
  end
  if #jobs > 0 then C_Timer.After(0.3, function() step(1) end) end
end

--- adds a rule (a new one for the same thing replaces the old one); removes one by its place
function A.add(what, to)
  local rules = LR.db.settings.autoLootRules
  for i = #rules, 1, -1 do if rules[i].what == what then table.remove(rules, i) end end
  rules[#rules + 1] = { what = what, to = to }
end
function A.remove(i) table.remove(LR.db.settings.autoLootRules, i) end
