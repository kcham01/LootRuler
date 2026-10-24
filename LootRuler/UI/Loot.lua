-- The Loot tab: everything that has dropped this raid, boss by boss, for the whole raid to see: who reserved
-- it, whether it's still to be rolled for, who won it and who has it. The loot master can roll anything on
-- it out from here, straight away or at the end of the raid, and sees what they still have to trade (the
-- game allows 2 hours). It's the session's list, so it goes when the session ends.
local _, LR = ...
local U, K, S, R = LR.U, LR.K, LR.Session, LR.Roll
local UI = LR.UI
local Rolls, Drops = LR.Rolls, LR.Drops

--- "1h 32m", "12m"
function UI.duration(secs)
  secs = math.max(0, math.floor(secs or 0))
  local h, m = math.floor(secs / 3600), math.floor(secs % 3600 / 60)
  if h > 0 then return ("%dh %02dm"):format(h, m) end
  if m > 0 then return m .. "m" end
  return "under a minute"
end

local function who(name, s) return U.classText(U.short(name), LR.classOf(name) or (s.res[name] and s.res[name].c)) end
local function how(w)
  if w.de then return "to disenchant" end
  if w.br then return "boosted roll" .. (w.r and (" " .. w.r) or "") end
  return w.k == "HR" and "hard reserved" or ((R.LABEL[w.k] or tostring(w.k)) .. (w.r and (" " .. w.r) or ""))
end

--- whether an item is being rolled for right now
local function rolling(id)
  for _, k in ipairs(Rolls.order) do
    local c = Rolls.seen[k]
    if c and c.id == id and c.state == "open" then return true end
  end
  local mine = Rolls.mine()
  return mine and mine.id == id and mine.state == "open"
end

--- the line under a drop's name
function UI.dropLine(s, d)
  local state, w = S.dropState(s, d)
  local left = Drops.tradeLeft(d)
  local trade = left and (left > 0 and (UI.duration(left) .. " to trade") or "|cffff5a4atoo late to trade|r")
  if state == "given" and w.de then return "Disenchanted by " .. who(w.p, s) end
  if state == "given" then return "Won by " .. who(w.p, s) .. " (" .. how(w) .. ")" end
  if state == "toTrade" then
    return "Won by " .. who(w.p, s) .. " (" .. how(w) .. "); " .. U.short(d.h) .. " has it to trade" .. (trade and (", " .. trade) or "")
  end
  if rolling(d.i) and state ~= "looted" then return "|cffffd100Being rolled for now|r" end
  local reserved = UI.whoLine(s, d.i, 3)
  local res = s.hr[d.i] and ("|cffff5a4aHard reserved|r" .. (s.hr[d.i].f ~= "" and (" for " .. s.hr[d.i].f) or ""))
    or (reserved and ("SR: " .. reserved)) or "Not reserved"
  if state == "looted" then return "Looted by " .. who(d.h, s) end
  if state == "held" then return U.short(d.h) .. " has it, to roll out" .. (trade and (" (" .. trade .. ")") or "") .. ". " .. res end
  return "On the corpse. " .. res
end

local function badge(s, d)
  local state, w = S.dropState(s, d)
  local me = U.me()
  if w and U.samePlayer(w.p, me) then return "|cff1eff00Yours|r" end
  if state == "looted" and U.samePlayer(d.h, me) then return "|cff1eff00Yours|r" end
  if state == "given" or state == "toTrade" or state == "looted" then return "" end
  if s.hr[d.i] then return "|cffff5a4aHR|r" end
  if S.claims(s, me, d.i) > 0 then return "|cffffd100Reserved|r" end
  return ""
end

--- rolls a drop out (the loot master)
local function rollOut(s, d)
  local slot
  for sl, k in pairs(Drops.slotKeys) do if k == d.k and Rolls.lootOpen then slot = sl end end
  local link = slot and GetLootSlotLink(slot) or LR.itemLink(d.i)
  local roll, why = Rolls.start(d.i, { drop = d.k, slot = slot, link = link })
  if not roll then UI.toast(why) return end
  UI.masterDraw()
end

local function dropRow(f, s, d, runner, leader)
  local state = S.dropState(s, d)
  local b = K.get(f.owner, "item", f.parent)
  local act
  if runner and (state == "corpse" or state == "held") and not rolling(d.i) then
    act = { text = "Roll", width = 40, tip = "Roll it out now", click = function() rollOut(s, d) end }
  elseif leader and (state == "given" or state == "toTrade") then
    local _, idx = S.dropWin(s, d.k)
    act = { text = "x", tip = "Take the award off the list (a mistake). The item stays where it is.", click = function()
      local w = s.won[idx]
      UI.confirm("Take the award off", ("%s to %s comes off the list%s."):format(LR.itemName(d.i), U.short(w.p),
        w.k == "SR" and ", and their reserve on it counts again" or ""), "Take it off", function() LR.unaward(s, idx) end)
    end }
  end
  K.setItem(b, f.width, LR.itemIcon(d.i), LR.coloredName(d.i), UI.dropLine(s, d), badge(s, d), act)
  if state == "given" or state == "looted" then b.icon:SetAlpha(0.75) end
  b:SetScript("OnEnter", function(self)
    UI.itemTooltip(self, s, d.i)
    if leader then GameTooltip:AddLine("Right-click to take it off the loot list.", 0.7, 0.7, 0.7) GameTooltip:Show() end
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnClick", function(_, button)
    if UI.modifiedClick(LR.itemLink(d.i)) then return end
    if button == "RightButton" and leader then
      UI.confirm("Take it off the loot list", LR.itemName(d.i) .. " comes off the raid's loot list (it didn't really drop, or it's there twice).", "Take it off", function()
        LR.removeDrop(s, d.k)
      end)
    end
  end)
  f:place(b, 36)
  f:gap(2)
end

--- who won what, to copy out (a sheet with a choice of formats)
local exportFormat = "csv"
function UI.exportSheet(s)
  UI.openSheet("Export who won what", function(f, h)
    local chips = {}
    for _, x in ipairs(LR.Export.FORMATS) do
      chips[#chips + 1] = { label = x[2], on = exportFormat == x[1], click = function() exportFormat = x[1] h.redraw() end }
    end
    f:chips(chips)
    f:note(({ csv = "For a spreadsheet: paste into Google Sheets or Excel.", tmb = "For thatsmybis.com's loot import.",
      dftus = "For the DFT sheet's import (month/day dates). Disenchanted items are left out.",
      dfteu = "For the DFT sheet's import (day/month dates). Disenchanted items are left out." })[exportFormat])
    local text = LR.Export.text(s, exportFormat)
    local m = K.get(f.owner, "memo", f.parent)
    f:place(m, 200, 0)
    K.setMemo(m, f.width, 200, text)
    f:gap(4)
    f:note("It's all selected: press Ctrl+C to copy it.")
  end)
end

function UI.lootView(f, s)
  if not s then
    f:panel("The raid's loot", function(p)
      p:text("Everything that drops is listed here once soft reserves are open: who reserved it, who won it and who has it. The raid leader opens reserves on the Session tab.")
    end)
    return
  end
  local drops = s.drops or {}
  local runner = LR.canRunLoot()
  local leader = LR.isLeader(s)
  local given, toRoll = 0, 0
  for _, d in ipairs(drops) do
    local state = S.dropState(s, d)
    if state == "given" or state == "toTrade" or state == "looted" then given = given + 1 else toRoll = toRoll + 1 end
  end
  if #drops == 0 then
    f:panel("The raid's loot", function(p)
      p:text("Nothing has dropped yet. Items show up here as the loot master opens corpses (with master loot on), or as people loot them.")
      if runner then p:note("You can roll things out straight away, or keep them in your bags and roll them out from here at the end. The game lets you trade raid loot for 2 hours after you loot it.") end
    end)
  else
    f:note(("%s dropped, %d given out, %d still to roll for."):format(U.plural(#drops, "item"), given, toRoll), toRoll > 0 and K.GOLD or K.GREEN)
  end
  if s.won and #s.won > 0 then
    f:buttons({
      { label = "Export", click = function() UI.exportSheet(s) end },
      (runner or leader) and { label = "Post in raid chat", disabled = LR.groupChannel() == nil, click = function()
        for _, line in ipairs(LR.Export.chat(s)) do LR.say(line, LR.groupChannel()) end
        UI.toast("Posted who won what.")
      end } or nil,
    }, "left")
  end

  -- what the loot master still has to hand over
  local deliver = Drops.toDeliver()
  if #deliver > 0 then
    f:panel("To trade", function(p)
      p:note(LR.db.settings.tradeHelp and "Open a trade with the winner and LootRuler puts their items in." or "Trade these to their winners.")
      for _, x in ipairs(deliver) do
        local d, winner = x[1], x[2]
        local b = K.get(p.owner, "item", p.parent)
        local left = Drops.tradeLeft(d)
        K.setItem(b, p.width, LR.itemIcon(d.i), LR.coloredName(d.i), "For " .. who(winner, s),
          left and (left > 0 and UI.duration(left) or "|cffff5a4alate|r") or "")
        b:SetScript("OnEnter", function(self) UI.itemTooltip(self, s, d.i) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p:place(b, 36)
        p:gap(2)
      end
      p:chips({ { label = (LR.db.settings.tradeHelp and "[x] " or "[  ] ") .. "Put won items in trades for me", on = LR.db.settings.tradeHelp,
        click = function() LR.db.settings.tradeHelp = not LR.db.settings.tradeHelp UI.render() end } })
    end)
  end

  -- boss by boss, in the order they died
  local order, byBoss = {}, {}
  for _, d in ipairs(drops) do
    local b = d.b ~= "" and d.b or "Other loot"
    if not byBoss[b] then byBoss[b] = {} order[#order + 1] = b end
    table.insert(byBoss[b], d)
  end
  for _, boss in ipairs(order) do
    local hd = K.get(f.owner, "head", f.parent)
    hd.text:SetText(boss)
    local n = #byBoss[boss]
    hd.right:SetText(U.plural(n, "item"))
    hd:SetWidth(f.width)
    f:place(hd, 22)
    f:gap(3)
    for _, d in ipairs(byBoss[boss]) do dropRow(f, s, d, runner, leader) end
    f:gap(6)
  end

  -- loot given out that isn't on the list (rolled out from bags before it was seen dropping)
  local others = {}
  for i, w in ipairs(s.won or {}) do if not w.d or not S.drop(s, w.d) then others[#others + 1] = { w, i } end end
  if #others > 0 then
    local hd = K.get(f.owner, "head", f.parent)
    hd.text:SetText("Also given out")
    hd:SetWidth(f.width)
    f:place(hd, 22)
    f:gap(3)
    for _, x in ipairs(others) do
      local w, idx = x[1], x[2]
      local b = K.get(f.owner, "item", f.parent)
      K.setItem(b, f.width, LR.itemIcon(w.i), LR.coloredName(w.i), "Won by " .. who(w.p, s) .. " (" .. how(w) .. ")",
        U.samePlayer(w.p, U.me()) and "|cff1eff00Yours|r" or "",
        leader and { text = "x", tip = "Take the award off the list (a mistake).", click = function()
          UI.confirm("Take the award off", ("%s to %s comes off the list."):format(LR.itemName(w.i), U.short(w.p)), "Take it off", function() LR.unaward(s, idx) end)
        end } or nil)
      b:SetScript("OnEnter", function(self) UI.itemTooltip(self, s, w.i) end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      f:place(b, 36)
      f:gap(2)
    end
  end
end
