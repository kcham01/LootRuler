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
  if w.k == "BID" then return "bought for " .. LR.Gdkp.gold(w.r) end
  if w.xn then return w.xn .. (w.r and (" " .. w.r) or "") end
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
    if runner and (state == "corpse" or state == "held") then GameTooltip:AddLine("Click to give it to someone without a roll.", 0.7, 0.7, 0.7) GameTooltip:Show() end
    if leader and (state == "given" or state == "toTrade") then GameTooltip:AddLine("Click to change who got it, or how.", 0.7, 0.7, 0.7) GameTooltip:Show() end
    if leader then GameTooltip:AddLine("Right-click to take it off the loot list.", 0.7, 0.7, 0.7) GameTooltip:Show() end
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnClick", function(_, button)
    if UI.modifiedClick(LR.itemLink(d.i)) then return end
    -- an item still to give out: give it to someone without a roll (the loot master)
    if button == "LeftButton" and runner and (state == "corpse" or state == "held") and not rolling(d.i) then
      local slot
      for sl, k in pairs(Drops.slotKeys) do if k == d.k and Rolls.lootOpen then slot = sl end end
      UI.giveSheet({ id = d.i, link = slot and GetLootSlotLink(slot) or LR.itemLink(d.i), slot = slot, drop = d.k })
      return
    end
    -- given out: change who got it, or how (a mistake)
    if button == "LeftButton" and leader and (state == "given" or state == "toTrade") then
      local _, idx = S.dropWin(s, d.k)
      if idx then UI.editAwardSheet(s, idx) end
      return
    end
    if button == "RightButton" and leader then
      UI.confirm("Take it off the loot list", LR.itemName(d.i) .. " comes off the raid's loot list (it didn't really drop, or it's there twice).", "Take it off", function()
        LR.removeDrop(s, d.k)
      end)
    end
  end)
  f:place(b, 36)
  f:gap(2)
end

--- changes an award: who got it, and how
function UI.editAwardSheet(s, index)
  local w = s.won and s.won[index]
  if not w then return end
  local who, how = w.p, w.de and "DE" or w.k
  UI.openSheet("Change the award", function(f, h)
    f:text(("%s went to %s."):format(LR.itemLink(w.i), U.classText(U.short(w.p), LR.classOf(w.p))))
    f:gap(4)
    f:text("Who has it?", { font = "GameFontNormal", color = K.GOLD, gap = 2 })
    f:chips({ { label = U.short(who), on = true, click = function() end },
      { label = "Someone else...", click = function() UI.pickPlayer("Who has it?", function(name) who = name h.redraw(true) end) end } })
    f:text("How did they get it?", { font = "GameFontNormal", color = K.GOLD, gap = 2 })
    local kinds = {}
    for _, k in ipairs({ { "SR", "Their reserve" }, { "MS", "Main spec" }, { "OS", "Off spec" }, { "DE", "To disenchant" } }) do
      kinds[#kinds + 1] = { label = k[2], on = how == k[1], click = function() how = k[1] h.redraw(true) end }
    end
    f:chips(kinds)
    f:note("The raid is told. Reserves used, +1s and who has it to trade follow the change.")
    f:buttons({ { label = "Cancel", click = function() h.close() end },
      { label = "Save", click = function()
        if LR.editAward(s, index, who, how) then UI.toast("Changed.") end
        h.close()
      end } })
  end)
end

--- who won what, to copy out (a sheet with a choice of formats)
local exportFormat = "csv"
--- the choice of format (and, for your own, its template); returns the format and its options
local function formatPicker(f, h)
  local set = LR.db.settings
  local chips = {}
  for _, x in ipairs(LR.Export.FORMATS) do
    chips[#chips + 1] = { label = x[2], on = exportFormat == x[1], click = function() exportFormat = x[1] h.redraw() end }
  end
  f:chips(chips)
  f:note(({ csv = "For a spreadsheet: paste into Google Sheets or Excel.", tmb = "For thatsmybis.com's loot import.",
    dftus = "For the DFT sheet's import (month/day dates). Disenchanted items are left out.",
    dfteu = "For the DFT sheet's import (day/month dates). Disenchanted items are left out.",
    own = "Write how each line looks. These are filled in for each item: " .. table.concat(U.map(LR.Export.FIELDS, function(x) return "{" .. x[1] .. "}" end), " ") .. "." })[exportFormat])
  if exportFormat ~= "own" then return exportFormat end
  for _, box in ipairs({ { "exportTemplate", "Each line" }, { "exportHeader", "First line (optional, like column names)" } }) do
    f:text(box[2], { font = "GameFontNormalSmall", color = K.GOLD, gap = 2 })
    local e = K.get(f.owner, "edit", f.parent)
    f:place(e, 22, 6, f.width - 12)
    e:SetMaxLetters(LR.Export.MAX_TEMPLATE)
    e:SetText(set[box[1]])
    e:SetScript("OnTextChanged", function(self, user) if user then set[box[1]] = self:GetText() end end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() h.redraw(true) end)
    f:gap(4)
  end
  f:buttons({ { label = "Show it", click = function() h.redraw(true) end } }, "left")
  return exportFormat, { template = set.exportTemplate, header = set.exportHeader }
end

local function exportBox(f, text)
  local m = K.get(f.owner, "memo", f.parent)
  f:place(m, 200, 0)
  K.setMemo(m, f.width, 200, text)
  f:gap(4)
  f:note("It's all selected: press Ctrl+C to copy it.")
end

function UI.exportSheet(s)
  UI.openSheet("Export who won what", function(f, h)
    local format, opts = formatPicker(f, h)
    exportBox(f, LR.Export.text(s, format, opts))
  end)
end

--- who won what in several raids (past raids, and the one on now), from a number of days ago
local exportDays = 30
local DAYS = { { 7, "Last 7 days" }, { 30, "Last 30 days" }, { 90, "Last 90 days" }, { 0, "Everything" } }
function UI.exportManySheet()
  UI.openSheet("Export several raids", function(f, h)
    local chips = {}
    for _, x in ipairs(DAYS) do chips[#chips + 1] = { label = x[2], on = exportDays == x[1], click = function() exportDays = x[1] h.redraw() end } end
    f:chips(chips)
    local sessions, seen = {}, {}
    local cur = LR.current()
    if cur and #(cur.won or {}) > 0 then sessions[1] = cur seen[cur.id] = true end
    for _, e in ipairs(LR.History.all()) do if not seen[e.id] then sessions[#sessions + 1] = e seen[e.id] = true end end
    local entries = LR.Export.entriesOf(sessions, exportDays > 0 and (U.now() - exportDays * 86400) or nil)
    local raids = {}
    for _, e in ipairs(entries) do raids[e.s.id] = true end
    f:note(("%s from %s, oldest first."):format(U.plural(#entries, "item"), U.plural(#U.keys(raids), "raid")), K.GOLD)
    local format, opts = formatPicker(f, h)
    exportBox(f, LR.Export.write(entries, format, opts))
  end)
end

---------------------------------------------------------------------- past raids (Core/History.lua)
--- one past raid: what it gave out, the export, and (a GDKP of mine) the payouts
function UI.pastRaidSheet(e)
  UI.openSheet(LR.raidOf(e).name .. ", " .. date("%b %d", e.ended), function(f, h)
    f:note(("Led by %s. Ended %s."):format(U.short(e.leader), date("%b %d, %H:%M", e.ended)))
    if e.gdkp and e.gk then
      local split = LR.Gdkp.split(e)
      f:kv({ { "Pot", LR.Gdkp.gold(split.pot) }, { "Split " .. #split.players .. " ways", LR.Gdkp.gold(split.share) .. " each" } })
      local owing = LR.Gdkp.unsettled(e)
      if LR.isLeader(e) and #owing > 0 then f:note(("%s still to settle: trades with them count, as during the raid."):format(U.plural(#owing, "player")), K.GOLD) end
    end
    f:gap(4)
    local list = {}
    if #(e.won or {}) > 0 then list[#list + 1] = { label = "Export", click = function() UI.exportSheet(e) end } end
    if e.gdkp and e.gk and LR.isLeader(e) then list[#list + 1] = { label = "Payouts", click = function() UI.payoutSheet(e) end } end
    list[#list + 1] = { label = "Forget it", click = function()
      UI.confirm("Forget this raid", "It's only removed from your own list of past raids.", "Forget", function() h.close() LR.History.remove(e.id) end)
    end }
    f:buttons(list, "left")
    f:gap(4)
    if #(e.won or {}) == 0 then f:note("Nothing was given out.") end
    for _, w in ipairs(e.won or {}) do
      local b = K.get(f.owner, "item", f.parent)
      K.setItem(b, f.width, LR.itemIcon(w.i), LR.coloredName(w.i), who(w.p, e) .. "  -  " .. how(w), "")
      b:SetScript("OnEnter", function(self) UI.itemTooltip(self, nil, w.i) end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      f:place(b, 36)
      f:gap(2)
    end
  end, { full = true })
end

--- every past raid, newest first
function UI.historySheet()
  UI.openSheet("Past raids", function(f, h)
    local all = LR.History.all()
    if #all == 0 then f:note("None yet. When a raid's soft reserves end, what it gave out is kept here.") return end
    f:note(("Raids you were in that gave loot out (up to the last %d), kept on this character. Click one for its loot."):format(LR.History.MAX))
    f:buttons({ { label = "Export several raids", click = function() UI.exportManySheet() end } }, "left")
    for _, e in ipairs(all) do
      local b = K.get(f.owner, "item", f.parent)
      local badge = ""
      if e.gdkp and e.gk then
        badge = "|cffffd100" .. LR.Gdkp.gold(LR.Gdkp.pot(e)) .. "|r"
        if LR.isLeader(e) and #LR.Gdkp.unsettled(e) > 0 then badge = badge .. " |cffff5a4aunpaid|r" end
      end
      K.setItem(b, f.width, LR.raidIcon(e.raid), LR.raidOf(e).name, ("%s - by %s - %s given out"):format(date("%b %d", e.ended), U.short(e.leader),
        U.plural(#(e.won or {}), "item")), badge)
      b:SetScript("OnClick", function() UI.pastRaidSheet(e) end)
      f:place(b, 36)
      f:gap(2)
    end
  end, { full = true })
end

local function pastRaids(f)
  local n = #LR.History.all()
  if n > 0 then
    f:gap(4)
    f:buttons({
      { label = ("Past raids (%d)"):format(n), click = function() UI.historySheet() end },
      { label = "Who got what, over time", click = function() UI.fairSheet() end },
    }, "left")
  end
end

function UI.lootView(f, s)
  if not s then
    f:panel("The raid's loot", function(p)
      p:text("Everything that drops is listed here once soft reserves are open: who reserved it, who won it and who has it. The raid leader opens reserves on the Session tab.")
    end)
    pastRaids(f)
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
  if runner or leader then
    f:buttons({
      { label = "Bag check", click = function() UI.bagCheckSheet() end },
      { label = "Raid gear", click = function() UI.gearSheet() end },
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
      p:chips({ { tick = true, label = "Put won items in trades for me", on = LR.db.settings.tradeHelp,
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
  pastRaids(f)
end
