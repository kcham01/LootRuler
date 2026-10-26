-- Fairness on screen (Core/History.lua's H.fairness): everyone's loot across past raids and the session on now, most
-- items first, with how many raids they came to; a click lists their items. From the Loot tab or /lr fair.
local _, LR = ...
local U, K = LR.U, LR.K
local UI = LR.UI
local H = LR.History

local RANGES = { { 28, "4 weeks" }, { 91, "3 months" }, { 0, "Everything" } }
local range = 28

--- "today", "3 days ago"
local function ago(at)
  local d = math.floor(math.max(0, U.now() - (at or 0)) / 86400)
  if d == 0 then return "today" end
  return d == 1 and "yesterday" or (d .. " days ago")
end

--- one player's items, newest first
local function playerSheet(r)
  UI.openSheet(U.short(r.p), function(f, h)
    f:note(("%s in %s."):format(U.plural(#r.items, "item"), U.plural(r.raids, "raid")))
    for _, x in ipairs(r.items) do
      local b = K.get(f.owner, "item", f.parent)
      local how = H.kindsText({ [x.k] = 1 }):gsub("^1 ", "")
      K.setItem(b, f.width, LR.itemIcon(x.i), LR.coloredName(x.i), ("%s, %s%s"):format(x.raid, ago(x.at), x.g and (", " .. LR.Gdkp.gold(x.g)) or ""),
        "|cff9d9d9d" .. how .. "|r")
      f:place(b, 36)
      f:gap(2)
    end
  end, { full = true })
end

function UI.fairSheet()
  UI.show()
  UI.openSheet("Who got what, over time", function(f, h)
    local chips = { { plain = true, label = "Over:" } }
    for _, x in ipairs(RANGES) do
      chips[#chips + 1] = { label = x[2], on = range == x[1], click = function() range = x[1] h.redraw(true) end }
    end
    f:chips(chips, { gap = 2 })
    f:note("Everyone's loot from your past raids and the one on now, most items first, with how many of those raids they came to.")
    local rows = H.fairness(range > 0 and (U.now() - range * 86400) or 0, LR.current())
    if #rows == 0 then f:note("No raids in that time.") end
    for _, r in ipairs(rows) do
      local b = K.get(f.owner, "item", f.parent)
      local sub = #r.items > 0 and ("%s, in %s. Last %s"):format(H.kindsText(r.kinds), U.plural(r.raids, "raid"), ago(r.last))
        or ("nothing yet, in %s"):format(U.plural(r.raids, "raid"))
      K.setItem(b, f.width, LR.LOGO, U.classText(U.short(r.p), LR.classOf(r.p)), sub, ("|cffffd100%d|r"):format(#r.items),
        #r.items > 0 and { text = "...", width = 30, tip = "Their items", click = function() playerSheet(r) end } or nil)
      f:place(b, 36)
      f:gap(2)
    end
  end, { full = true })
end
