-- Auto-roll: a raider's own rules for roll windows. "Always pass on this item", "always roll main spec on
-- that one", and "pass on anything my class can't use". When the loot master rolls something out, LootRuler
-- does what the rule says (a /roll, or a pass) and says so. Rules are the player's own (saved per account),
-- made on the Settings tab or by shift-clicking a roll window's button.
local _, LR = ...
local U, R = LR.U, LR.Roll

local A = {}
LR.AutoRoll = A

A.ACTIONS = { pass = "Pass", MS = "Main spec", OS = "Off spec" }

--- what to do about a roll on its own, or nil: "pass", "MS", "OS" (and why, for the message)
function A.decide(copy)
  local set = LR.db.settings
  local me = U.me()
  local rule = set.autoRollRules[copy.id]
  if rule then
    if rule == "pass" then return "pass", "your rule for it" end
    -- a rule to roll only applies when that's a roll I may make here
    for _, k in ipairs(R.options(copy, me)) do
      if k == rule or (rule == "MS" and (k == "SR" or k == copy.tie)) then return k, "your rule for it" end
    end
    return nil
  end
  if set.autoPassUnusable and copy.mode == "OPEN" and LR.ITEMS[copy.id] and not LR.usableBy(copy.id, LR.myClass()) then
    return "pass", "your class can't use it"
  end
end

--- a new roll: do what the rules say, a moment after the window shows
function A.consider(copy)
  if copy.autoDone or copy.state ~= "open" or copy.test then return end
  local action, why = A.decide(copy)
  if not action then return end
  copy.autoDone = true
  C_Timer.After(0.5, function()
    if copy.state ~= "open" or copy.rolled[R.key(U.me())] or copy.passedByMe then return end
    if action == "pass" then
      LR.Rolls.pass(copy)
      copy.closedByMe = true
      LR.print(("passed on %s for you (%s)."):format(copy.link, why))
    else
      LR.Rolls.roll(copy, action)
      LR.print(("rolled %s on %s for you (%s)."):format(R.LABEL[action] or action, copy.link, why))
    end
    copy.auto = action
    LR.changed("rolls")
  end)
end

--- sets (or clears, with nil) the rule for an item
function A.set(id, action)
  if type(id) ~= "number" then return end
  LR.db.settings.autoRollRules[id] = A.ACTIONS[action] and action or nil
end
