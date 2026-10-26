-- The gear overview on screen (Core/Overview.lua; this file is UI/Gear.lua): everyone in the group with their average item level, how many items
-- that's from and when it was read; a click shows what they wear, slot by slot. From the Loot tab ("Raid gear") or /lr gear.
local _, LR = ...
local U, K, R = LR.U, LR.K, LR.Roll
local UI = LR.UI
local O = LR.Overview

local open                 -- the overview sheet's handle, while it's open (redrawn as gear comes in)

local WHY = { far = "too far away to inspect", gone = "can't be inspected now", silent = "didn't answer", off = "inspecting is switched off in Settings" }

--- one player's gear, slot by slot
local function playerSheet(name)
  UI.openSheet(U.short(name), function(f, h)
    local d = O.data[R.key(name)]
    if not d then f:note("Not read yet.") return end
    local level, items = O.level(d.slots)
    f:note(("%s, %s. Read %s%s."):format(level and ("item level " .. level) or "item level unknown", U.plural(items, "item"), O.age(d.at),
      d.how == "inspect" and " (inspected)" or ""))
    local empty = {}
    for _, slot in ipairs(O.SLOTS) do
      local l = d.slots[slot]
      if l then
        local id = tonumber(l:match("item:(%d+)"))
        local name, hex = LR.linkParts(l, id)             -- (the link's own name, for an item the lists don't know)
        local b = K.get(f.owner, "item", f.parent)
        local lvl = C_Item and C_Item.GetItemInfo and select(4, C_Item.GetItemInfo(l))
        K.setItem(b, f.width, LR.itemIcon(id), "|cff" .. hex .. name .. "|r", O.SLOT_NAME[slot], lvl and ("|cff9d9d9d" .. lvl .. "|r") or "")
        b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT") GameTooltip:SetHyperlink(l) GameTooltip:Show() end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f:place(b, 36)
        f:gap(2)
      elseif not U.indexOf(empty, O.SLOT_NAME[slot]) then
        empty[#empty + 1] = O.SLOT_NAME[slot]
      end
    end
    if #empty > 0 then f:note("Nothing in: " .. table.concat(empty, ", ") .. ".") end
  end, { full = true })
end

--- everyone in the group
function UI.gearSheet(ask)
  if ask ~= false then
    local ok, why = O.ask()
    if not ok then UI.toast(why) end
  end
  UI.show()
  UI.openSheet("Raid gear", function(f, h)
    open = h
    f:note("What everyone wears, best item level first. Players with LootRuler send theirs; anyone else is inspected when they're close.")
    for _, r in ipairs(O.list()) do
      local sub
      if r.d and r.items == 0 then
        sub = ("nothing worn, %s"):format(O.age(r.d.at))
      elseif r.d then
        sub = ("%s, %s, %s%s"):format(r.level and ("item level " .. r.level) or "item level unknown", U.plural(r.items, "item"), O.age(r.d.at),
          r.d.how == "inspect" and " (inspected)" or "")
      else
        sub = "|cff9d9d9d" .. (r.why and ("Not read: " .. WHY[r.why]) or "Asking...") .. "|r"
      end
      local b = K.get(f.owner, "item", f.parent)
      K.setItem(b, f.width, LR.LOGO, U.classText(U.short(r.name), r.class or LR.classOf(r.name)), sub, r.level and ("|cffffd100" .. r.level .. "|r") or "",
        r.d and { text = "...", width = 30, tip = "What they wear", click = function() playerSheet(r.name) end } or nil)
      f:place(b, 36)
      f:gap(2)
    end
    f:gap(6)
    f:buttons({ { label = "Ask again", click = function()
      local ok, why = O.ask()
      if not ok then UI.toast(why) end
      h.redraw(true)
    end } }, "left")
  end, { full = true, onClose = function() open = nil end })
end

LR.onChange(function(what)
  if what == "gear" and open then open.redraw(true) end
end)
