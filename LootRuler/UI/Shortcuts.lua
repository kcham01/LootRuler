-- Shortcut keys: click an item with a modifier held, anywhere the game lets you link it (bags, the loot
-- window, chat links), to roll it out. Ctrl+Alt by default, which neither the game (Shift links, Ctrl tries
-- on) nor Gargul (Alt, Alt+Shift, Ctrl+Shift) uses. Only does anything for whoever may roll loot out.
local _, LR = ...
local U = LR.U
local UI = LR.UI

UI.SHORTCUTS = {
  { "ctrlalt", "Ctrl+Alt+click" },
  { "alt", "Alt+click (Gargul uses it too)" },
  { "off", "Off" },
}

--- whether the keys held right now are the roll-out shortcut
function UI.shortcutHeld()
  local which = LR.db and LR.db.settings.rollShortcut
  local ctrl, alt, shift = IsControlKeyDown(), IsAltKeyDown(), IsShiftKeyDown()
  if which == "ctrlalt" then return ctrl and alt and not shift end
  if which == "alt" then return alt and not ctrl and not shift end
  return false
end

--- an item was clicked with modifiers: roll it out if that's the shortcut
function UI.shortcutClick(link)
  if not LR.db or not link or not UI.shortcutHeld() then return false end
  local id = tonumber(tostring(link):match("|Hitem:(%d+)"))
  if not id or not LR.canRunLoot() then return false end
  -- from the open loot window: that slot (so it can be handed over there)
  local slot
  for _, it in ipairs(LR.Rolls.loot()) do if it.id == id then slot = it.slot break end end
  local roll, why = LR.Rolls.start(id, { link = link, slot = slot })
  if not roll then LR.print(why) return true end
  if UI.masterDraw then UI.masterDraw() end
  return true
end

if HandleModifiedItemClick then
  hooksecurefunc("HandleModifiedItemClick", function(link) UI.shortcutClick(link) end)
end
