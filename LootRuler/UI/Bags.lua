-- Bag checks on screen (Core/Bags.lua): pick the items, ask the group, and the report of who has how many, with who
-- couldn't be asked. From the Loot tab ("Bag check") or /lr bags.
local _, LR = ...
local U, K = LR.U, LR.K
local UI = LR.UI
local Bags = LR.Bags

local picked = {}          -- the items to ask about, in order
local report               -- the report sheet's handle, while it's open (redrawn as answers come in)

--- the report: everyone in the group, with their counts
function UI.bagReportSheet()
  UI.openSheet("Bag check", function(f, h)
    report = h
    local check = Bags.last
    if not check then f:note("Nothing asked yet.") return end
    local names = {}
    for i, id in ipairs(check.ids) do names[#names + 1] = ("%d. %s"):format(i, LR.coloredName(id)) end
    f:text(table.concat(names, "   "), { font = "GameFontHighlightSmall", gap = 6 })
    local missing = 0
    for _, r in ipairs(Bags.report(check)) do
      local sub
      if r.counts then
        local parts = {}
        for i, id in ipairs(check.ids) do
          local n = r.counts[id] or 0
          if n == 0 then missing = missing + 1 end
          parts[#parts + 1] = ("%d: %s"):format(i, n == 0 and "|cffff5a4anone|r" or ("|cff1eff00" .. n .. "|r"))
        end
        sub = table.concat(parts, "   ")
      elseif r.why == "none" then sub = "|cff9d9d9dNo LootRuler: can't be asked.|r"
      elseif r.why == "waiting" then sub = "|cff9d9d9dAsking...|r"
      else sub = "|cff9d9d9dNo answer (an older LootRuler, or they've switched answering off).|r" end
      local b = K.get(f.owner, "item", f.parent)
      K.setItem(b, f.width, LR.LOGO, U.classText(U.short(r.name), r.class or LR.classOf(r.name)), sub, "")
      f:place(b, 36)
      f:gap(2)
    end
    f:gap(6)
    f:buttons({
      { label = "Say who's missing", disabled = missing == 0 or LR.groupChannel() == nil, click = function()
        local n = Bags.postMissing(check)
        UI.toast(n > 0 and ("Posted %s."):format(U.plural(n, "line")) or "Nobody is missing anything.")
      end },
      { label = "Ask again", style = "quiet", click = function()
        local ok, why = Bags.ask(check.ids)
        if not ok then UI.toast(why) end
        h.redraw(true)
      end },
    }, "left")
    f:note("Bags and bank. Only players with LootRuler can be asked: anyone without it, ask in raid chat.")
  end, { full = true, onClose = function() report = nil end })
end

--- picking what to ask about
function UI.bagCheckSheet()
  UI.show()
  UI.openSheet("Bag check", function(f, h)
    f:note(("Ask everyone in the group with LootRuler how many of some items they carry (a flask, a key, an attunement item). Up to %d items."):format(Bags.MAX))
    for i, id in ipairs(picked) do
      local b = K.get(f.owner, "item", f.parent)
      K.setItem(b, f.width, LR.itemIcon(id), LR.coloredName(id), "", "", { text = "x", tip = "Take it off", click = function() table.remove(picked, i) h.redraw(true) end })
      f:place(b, 36)
      f:gap(2)
    end
    if #picked == 0 then f:note("No items yet.") end
    f:gap(4)
    f:buttons({
      { label = "Add an item", style = "quiet", disabled = #picked >= Bags.MAX, click = function()
        UI.pickAnyItem("Which item?", function(id)
          if not U.indexOf(picked, id) then picked[#picked + 1] = id end
          h.redraw(true)
        end)
      end },
      { label = "Ask the group", disabled = #picked == 0, click = function()
        local ok, why = Bags.ask(picked)
        if not ok then UI.toast(why) return end
        h.close()
        UI.bagReportSheet()
      end },
    }, "left")
  end, { full = true })
end

LR.onChange(function(what)
  if what == "bags" and report then report.redraw(true) end
end)
