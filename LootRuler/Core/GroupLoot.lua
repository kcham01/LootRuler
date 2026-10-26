-- Group loot rules: a player's own rules for the game's Need / Greed windows (group loot, round robin, free for
-- all), like "greed on green items" or "need on this item". When the game asks, LootRuler rolls what the first rule
-- that matches says, and tells the player. Off until the player turns it on (Settings tab), and so is skipping the
-- game's "this item will bind to you" question for a roll a rule made. Nothing else is ever rolled or confirmed.
--
-- A rule: { what = "item:<id>" / "q2" / "q3" / "q4" / "recipe" / "gem" / "trade" (Core/AutoLoot.lua's), act = "need" /
--           "greed" / "de" (disenchant) / "pass" }
local _, LR = ...
local U = LR.U

local G = {}
LR.GroupLoot = G

G.ACTS = { { "need", "Need", 1 }, { "greed", "Greed", 2 }, { "de", "Disenchant", 3 }, { "pass", "Pass", 0 } }
local ACT = {}
for _, a in ipairs(G.ACTS) do ACT[a[1]] = a end
G.MAX_RULES = 40

--- what a rule does, for people
function G.actText(act) return ACT[act] and ACT[act][2] or tostring(act) end

--- rules saved, checked
function G.check(rules)
  return U.filter(type(rules) == "table" and rules or {}, function(r)
    return type(r) == "table" and type(r.what) == "string" and #r.what <= 20 and ACT[r.act] ~= nil
  end)
end

--- the first rule for an item (of quality q), or nil
function G.ruleFor(rules, id, q)
  for _, r in ipairs(rules or {}) do
    if LR.AutoLoot.matches(r, id, q) then return r end
  end
end

--- the game's roll type for a rule, or nil when that roll can't be made on this item (need, greed, disenchant
--- allowed: from GetLootRollItemInfo)
function G.rollType(act, canNeed, canGreed, canDE)
  if act == "need" then return canNeed and 1 or nil end
  if act == "greed" then return canGreed and 2 or nil end
  if act == "de" then return canDE and 3 or nil end
  if act == "pass" then return 0 end
end

local rolledByRule = {}        -- roll id -> roll type: rolls a rule made (only those are confirmed)

--- the game asks for a roll on an item (START_LOOT_ROLL): what my rules say, rolled. Returns the act, or nil.
function G.onRoll(rollID)
  local set = LR.db.settings
  if not set.groupLoot then return nil end
  local _, name, _, quality, _, canNeed, canGreed, canDE = GetLootRollItemInfo(rollID)
  local link = GetLootRollItemLink(rollID)
  local id = tonumber(tostring(link or ""):match("item:(%d+)"))
  if not id then return nil end
  local rule = G.ruleFor(set.groupLootRules, id, quality)
  if not rule then return nil end
  local kind = G.rollType(rule.act, canNeed, canGreed, canDE)
  if not kind then
    LR.print(("your rule says %s on %s, but the game doesn't allow that here: roll yourself."):format(G.actText(rule.act), link or name or "?"))
    return nil
  end
  rolledByRule[rollID] = kind
  RollOnLoot(rollID, kind)
  LR.print(("%s on %s for you (your rule: %s)."):format(G.actText(rule.act), link or name or "?", LR.AutoLoot.whatText(rule.what)))
  return rule.act
end

--- the game asks "this item will bind to you" (CONFIRM_LOOT_ROLL / CONFIRM_DISENCHANT_ROLL): only for a roll one of my
--- rules made, and only when that's switched on, it's answered yes
function G.onConfirm(rollID, kind)
  if not LR.db.settings.groupLootConfirm or rolledByRule[rollID] ~= kind then return false end
  ConfirmLootRoll(rollID, kind)
  if StaticPopup_Hide then StaticPopup_Hide("CONFIRM_LOOT_ROLL", rollID) end
  return true
end

local events = CreateFrame("Frame")
events:RegisterEvent("START_LOOT_ROLL")
events:RegisterEvent("CONFIRM_LOOT_ROLL")
events:RegisterEvent("CONFIRM_DISENCHANT_ROLL")
events:SetScript("OnEvent", function(_, event, rollID, kind)
  if not LR.db or type(rollID) ~= "number" then return end
  if event == "START_LOOT_ROLL" then G.onRoll(rollID)
  else G.onConfirm(rollID, tonumber(kind)) end
end)

--- adds a rule (first match wins, so a rule for one item goes first)
function G.add(what, act)
  local rules = LR.db.settings.groupLootRules
  if #rules >= G.MAX_RULES or not ACT[act] then return false end
  if tostring(what):match("^item:") then table.insert(rules, 1, { what = what, act = act })
  else rules[#rules + 1] = { what = what, act = act } end
  return true
end
function G.remove(i) table.remove(LR.db.settings.groupLootRules, i) end
