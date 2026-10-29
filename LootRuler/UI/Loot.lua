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
    -- (a trade is only seen by the two in it: when whoever has it hasn't got LootRuler, it can't be followed, so just the winner)
    if not LR.versionOf(d.h) then return "Won by " .. who(w.p, s) .. " (" .. how(w) .. ")" end
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

UI.rollingNow = rolling

--- rolls a drop out (the loot master)
local function rollOut(s, d)
  local slot
  for sl, k in pairs(Drops.slotKeys) do if k == d.k and Rolls.lootOpen then slot = sl end end
  local link = slot and GetLootSlotLink(slot) or LR.itemLink(d.i)
  local roll, why = Rolls.start(d.i, { drop = d.k, slot = slot, link = link })
  if not roll then UI.toast(why) return end
  UI.masterDraw()
end
UI.rollOut = rollOut

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
    f:buttons({ { label = "Cancel", style = "quiet", click = function() h.close() end },
      { label = "Save", click = function()
        if LR.editAward(s, index, who, how) then UI.toast("Changed.") end
        h.close()
      end } })
    -- a mistake: off the list of loot given out (the item stays where it is)
    f:buttons({ { label = "Take the award off", style = "link", danger = true, click = function()
      h.close()
      UI.confirm("Take the award off", ("%s to %s comes off the list%s. The item stays where it is."):format(LR.itemName(w.i), U.short(w.p),
        w.k == "SR" and ", and their reserve on it counts again" or ""), "Take it off", function() LR.unaward(s, index) end)
    end } }, "left")
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
  UI.openSheet(LR.raidOf(e).name .. ", " .. U.clock(e.ended, "%b %d"), function(f, h)
    f:note(("Led by %s. Ended %s."):format(U.short(e.leader), U.clock(e.ended, "%b %d, %H:%M")))
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
      K.setItem(b, f.width, LR.raidIcon(e.raid), LR.raidOf(e).name, ("%s - by %s - %s given out"):format(U.clock(e.ended, "%b %d"), U.short(e.leader),
        U.plural(#(e.won or {}), "item")), badge)
      b:SetScript("OnClick", function() UI.pastRaidSheet(e) end)
      f:place(b, 36)
      f:gap(2)
    end
  end, { full = true })
end

---------------------------------------------------------------------- award history, by date
--- every award in the session on now (not a practice one) and in past raids: { w, s = its session, at }, newest first
function UI.awardHistory()
  local out, seen = {}, {}
  local function add(e)
    if not e or e.practice or e.pv or seen[e.id] then return end
    seen[e.id] = true
    for _, w in ipairs(e.won or {}) do out[#out + 1] = { w = w, s = e, at = w.at or e.ended or e.created or 0 } end
  end
  add(LR.current())
  for _, e in ipairs(LR.History.all()) do add(e) end
  table.sort(out, function(a, b) return a.at > b.at end)
  return out
end

--- which dates are open (saved, per character): "2026-10-28" -> true / false; the newest is open until it's closed
local function openDays()
  if type(LR.db.ui.historyOpen) ~= "table" then LR.db.ui.historyOpen = {} end
  return LR.db.ui.historyOpen
end

--- the Loot tab's "Award history": a date for each day something was given out, newest first, that opens to its items
local function historyView(f)
  local all = UI.awardHistory()
  f:note(("Everything given out in your raids, by date. Kept on this character for your last %d raids."):format(LR.History.MAX))
  local n = #LR.History.all()
  f:buttons({
    { label = "Export", style = "quiet", click = function() UI.exportManySheet() end },
    { label = "Who got what, over time", style = "quiet", click = function() UI.fairSheet() end },
    n > 0 and { label = ("Past raids (%d)"):format(n), style = "quiet", click = function() UI.historySheet() end } or nil,
  }, "left")
  f:gap(4)
  if #all == 0 then f:note("Nothing given out yet. Once items are won, they're listed here under the day they were given out.") return end
  local days, byDay = {}, {}
  for _, x in ipairs(all) do
    local day = U.clock(x.at, "%Y-%m-%d")
    if not byDay[day] then byDay[day] = {} days[#days + 1] = day end
    table.insert(byDay[day], x)
  end
  local open = openDays()
  for i, day in ipairs(days) do
    local list = byDay[day]
    local raids, seen = {}, {}
    for _, x in ipairs(list) do
      local name = LR.raidOf(x.s).name
      if not seen[name] then seen[name] = true raids[#raids + 1] = name end
    end
    local isOpen = open[day]
    if isOpen == nil then isOpen = i == 1 end
    f:fold(U.clock(list[1].at, "%A, %B %d") ~= "" and U.clock(list[1].at, "%A, %B %d") or "Some time", ("%s: %s"):format(U.plural(#list, "item"), table.concat(raids, ", ")), isOpen,
      function() open[day] = not isOpen UI.render() end,
      function(p)
        for _, x in ipairs(list) do
          local w = x.w
          local b = K.get(p.owner, "item", p.parent)
          K.setItem(b, p.width, LR.itemIcon(w.i), LR.coloredName(w.i),
            ("Won by %s (%s) - %s, %s"):format(who(w.p, x.s), how(w), LR.raidOf(x.s).name, U.clock(x.at, "%H:%M")),
            U.samePlayer(w.p, U.me()) and "|cff1eff00Yours|r" or "")
          b:SetScript("OnEnter", function(self) UI.itemTooltip(self, nil, w.i) end)
          b:SetScript("OnLeave", function() GameTooltip:Hide() end)
          b:SetScript("OnClick", function() UI.modifiedClick(LR.itemLink(w.i)) end)
          p:place(b, 36)
          p:gap(2)
        end
      end)
  end
end

--- the line under an item on the Loot tab's lists: which boss, then how it stands
local function bossOf(d) return d.b ~= "" and d.b or nil end
local function withBoss(d, text) local b = bossOf(d) return b and (b .. "  -  " .. text) or text end

--- the slot an item is in, while my loot window is open on it
local function slotOf(d)
  for sl, k in pairs(Drops.slotKeys) do if k == d.k and Rolls.lootOpen then return sl end end
end

--- one item on the Loot tab: what to do with it now (Roll, Give to..., Open a trade, Change) on its button
local function lootRow(f, s, d, runner, leader, group)
  local state, w = S.dropState(s, d)
  local b = K.get(f.owner, "item", f.parent)
  local act, sub
  if group == "roll" then
    local hr = s.hr[d.i]
    local reserved = UI.whoLine(s, d.i, 3)
    if rolling(d.i) then sub = "|cffffd100Being rolled for now|r"
    else
      sub = hr and ("|cffff5a4ahard reserved|r" .. (hr.f ~= "" and (" for " .. hr.f) or "")) or (reserved and ("SR: " .. reserved)) or "not reserved"
      if state == "held" then sub = sub .. "  -  " .. (U.samePlayer(d.h, U.me()) and "in your bags" or (U.short(d.h) .. " has it")) end
    end
    sub = withBoss(d, sub)
    if runner and not rolling(d.i) then
      local to = hr and hr.f ~= "" and LR.inGroup(hr.f)
      if to then
        act = { text = "Give to " .. U.short(to.name), width = math.min(110, 40 + #U.short(to.name) * 7), click = function()
          UI.giveSheet({ id = d.i, link = slotOf(d) and GetLootSlotLink(slotOf(d)) or LR.itemLink(d.i), slot = slotOf(d), drop = d.k, to = to.name })
        end }
      else
        act = { text = s.gdkp and "Auction" or "Roll", width = s.gdkp and 62 or 46, tip = "Roll it out now", click = function() rollOut(s, d) end }
      end
    end
  elseif group == "trade" then
    local left = Drops.tradeLeft(d)
    sub = withBoss(d, "won by " .. who(w.p, s) .. " (" .. how(w) .. ")" .. (left and (left > 0 and ("  -  " .. UI.duration(left) .. " left") or "  -  |cffff5a4atoo late to trade|r") or ""))
    if U.samePlayer(d.h, U.me()) and not U.samePlayer(w.p, U.me()) then
      act = { text = "Open a trade", width = 92, click = function()
        local ok, why = Drops.openTrade(w.p)
        if not ok then UI.toast(((UI.TRADE_WHY or {})[why] or why):format(U.short(w.p))) end
      end }
    end
  else
    sub = UI.dropLine(s, d)
    if leader and (state == "given" or state == "toTrade") then
      local _, idx = S.dropWin(s, d.k)
      act = { text = "Change", width = 58, tip = "Change who got it, or how", click = function() if idx then UI.editAwardSheet(s, idx) end end }
    end
  end
  K.setItem(b, f.width, LR.itemIcon(d.i), LR.coloredName(d.i), sub, act and "" or badge(s, d), act)
  if group == "given" then b.icon:SetAlpha(0.75) b:SetAlpha(0.85) end
  b:SetScript("OnEnter", function(self)
    UI.itemTooltip(self, s, d.i)
    if runner and group == "roll" then GameTooltip:AddLine("Click to give it to someone without a roll.", 0.7, 0.7, 0.7) GameTooltip:Show() end
    if leader then GameTooltip:AddLine("Right-click to take it off the loot list.", 0.7, 0.7, 0.7) GameTooltip:Show() end
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnClick", function(_, button)
    if UI.modifiedClick(LR.itemLink(d.i)) then return end
    -- an item still to give out: give it to someone without a roll (the loot master)
    if button == "LeftButton" and runner and group == "roll" and not rolling(d.i) then
      UI.giveSheet({ id = d.i, link = slotOf(d) and GetLootSlotLink(slotOf(d)) or LR.itemLink(d.i), slot = slotOf(d), drop = d.k })
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

function UI.lootView(f, s)
  -- this raid's loot, or the award history (kept per character)
  if LR.db.ui.lootPage ~= "history" then LR.db.ui.lootPage = "raid" end
  f:chips({
    { label = "This raid", on = LR.db.ui.lootPage == "raid", click = function() LR.db.ui.lootPage = "raid" UI.render() end },
    { label = "Award history", on = LR.db.ui.lootPage == "history", click = function() LR.db.ui.lootPage = "history" UI.render() end },
  })
  f:gap(4)
  if LR.db.ui.lootPage == "history" then historyView(f) return end
  if not s then
    f:panel("The raid's loot", function(p)
      p:text("Everything that drops is listed here once soft reserves are open: who reserved it, who won it and who has it. The raid leader opens reserves on the Session tab.")
    end)
    return
  end
  -- the loot to roll for, and everything else that dropped (counted: LR.minorLoot)
  local runner = LR.canRunLoot() and not s.pv          -- (nothing is rolled out from a private session)
  local leader = LR.isLeader(s)
  local toRoll, toTrade, given, minor = {}, {}, {}, {}
  for _, d in ipairs(s.drops or {}) do
    if LR.minorLoot(s, d.i) then minor[#minor + 1] = d
    else
      local state = S.dropState(s, d)
      if state == "corpse" or state == "held" then toRoll[#toRoll + 1] = d
      elseif state == "toTrade" and U.samePlayer(d.h, U.me()) and LR.versionOf(d.h) then toTrade[#toTrade + 1] = d
      else given[#given + 1] = d end
    end
  end
  if #toRoll + #toTrade + #given + #minor == 0 then
    f:panel("The raid's loot", function(p)
      p:text("Nothing has dropped yet. Items show up here as the loot master opens corpses (with master loot on), or as people loot them.")
      if runner then p:note("You can roll things out straight away, or keep them in your bags and roll them out from here at the end. The game lets you trade raid loot for 2 hours after you loot it.") end
    end)
  end

  -- what to do now first: what's still to roll out, then what I have to trade, then what's done
  if #toRoll > 0 then
    f:heading(s.gdkp and "To auction" or "To roll out", U.plural(#toRoll, "item"))
    for _, d in ipairs(toRoll) do lootRow(f, s, d, runner, leader, "roll") end
    f:gap(6)
  end
  if #toTrade > 0 then
    local soonest
    for _, d in ipairs(toTrade) do local l = Drops.tradeLeft(d) if l and (not soonest or l < soonest) then soonest = l end end
    f:heading("To trade", U.plural(#toTrade, "item") .. (soonest and (", " .. UI.duration(soonest) .. " left") or ""))
    for _, d in ipairs(toTrade) do lootRow(f, s, d, runner, leader, "trade") end
    f:chips({ { tick = true, label = "Put won items in trades for me", on = LR.db.settings.tradeHelp,
      click = function() LR.db.settings.tradeHelp = not LR.db.settings.tradeHelp UI.render() end } })
    f:gap(2)
  end
  -- loot given out that isn't on the list (rolled out from bags before it was seen dropping)
  local others = {}
  for i, w in ipairs(s.won or {}) do if not w.d or not S.drop(s, w.d) then others[#others + 1] = { w, i } end end
  if #given + #others > 0 then
    f:heading("Given out", U.plural(#given + #others, "item"))
    for _, d in ipairs(given) do lootRow(f, s, d, runner, leader, "given") end
    for _, x in ipairs(others) do
      local w, idx = x[1], x[2]
      local b = K.get(f.owner, "item", f.parent)
      K.setItem(b, f.width, LR.itemIcon(w.i), LR.coloredName(w.i), "Won by " .. who(w.p, s) .. " (" .. how(w) .. ")",
        U.samePlayer(w.p, U.me()) and "|cff1eff00Yours|r" or "",
        leader and { text = "x", tip = "Take the award off the list (a mistake).", click = function()
          UI.confirm("Take the award off", ("%s to %s comes off the list."):format(LR.itemName(w.i), U.short(w.p)), "Take it off", function() LR.unaward(s, idx) end)
        end } or nil)
      b.icon:SetAlpha(0.75) b:SetAlpha(0.85)
      b:SetScript("OnEnter", function(self) UI.itemTooltip(self, s, w.i) end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      f:place(b, 36)
      f:gap(2)
    end
    f:gap(6)
  end

  -- everything else that dropped, counted, folded: one row per item, with who looted how many
  if #minor > 0 then
    local order, by = {}, {}
    for _, d in ipairs(minor) do
      local x = by[d.i]
      if not x then x = { id = d.i, n = 0, who = {}, whoOrder = {}, left = 0 } by[d.i] = x order[#order + 1] = x end
      local n = d.n or 1
      x.n = x.n + n
      if d.h then
        if not x.who[d.h] then x.who[d.h] = 0 x.whoOrder[#x.whoOrder + 1] = d.h end
        x.who[d.h] = x.who[d.h] + n
      else x.left = x.left + n end
    end
    local what = {}
    for i, x in ipairs(order) do
      if i > 3 then what[#what + 1] = "..." break end
      what[#what + 1] = LR.itemName(x.id) .. " x" .. x.n
    end
    if type(LR.db.ui.minorOpen) ~= "boolean" then LR.db.ui.minorOpen = false end
    f:fold("Everything else that dropped", table.concat(what, ", "), LR.db.ui.minorOpen, function() LR.db.ui.minorOpen = not LR.db.ui.minorOpen UI.render() end, function(p)
      for _, x in ipairs(order) do
        local parts = {}
        for i, name in ipairs(x.whoOrder) do
          if i > 4 then parts[#parts + 1] = ("%d more"):format(#x.whoOrder - 4) break end
          parts[#parts + 1] = who(name, s) .. (x.who[name] > 1 and (" (" .. x.who[name] .. ")") or "")
        end
        local line = #parts > 0 and ("Looted by " .. table.concat(parts, ", ")) or ""
        if x.left > 0 then line = line .. (line ~= "" and "; " or "") .. x.left .. " on the corpse" end
        local b = K.get(p.owner, "item", p.parent)
        K.setItem(b, p.width, LR.itemIcon(x.id), LR.coloredName(x.id), line, "|cffffffffx" .. x.n .. "|r")
        b:SetScript("OnEnter", function(self) UI.itemTooltip(self, s, x.id) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function() UI.modifiedClick(LR.itemLink(x.id)) end)
        p:place(b, 36)
        p:gap(2)
      end
    end)
  end

  -- the loot master's actions, pinned under the list
  local canRoll = U.filter(toRoll, function(d) return not rolling(d.i) and not s.hr[d.i] end)
  local won = s.won and #s.won > 0
  local more = {
    won and { label = "Export who won what", click = function() UI.exportSheet(s) end } or false,
    (runner or leader) and { label = "Bag check", click = function() UI.bagCheckSheet() end, note = "Who has an item in their bags (or bank)." } or false,
    (runner or leader) and { label = "Raid gear", click = function() UI.gearSheet() end, note = "Everyone's gear, by inspecting." } or false,
  }
  if runner and not s.pv then
    UI.pin({
      { label = s.gdkp and "Auction them all" or "Roll them all out", disabled = #canRoll == 0, click = function()
        local items = {}
        for _, d in ipairs(canRoll) do items[#items + 1] = { id = d.i, link = slotOf(d) and GetLootSlotLink(slotOf(d)) or LR.itemLink(d.i), slot = slotOf(d), drop = d.k } end
        Rolls.enqueue(items)
        UI.masterDraw()
      end, tip = "One after another, in the order they dropped. Hard reserved items wait for you to give them out." },
      { label = "Post in raid chat", style = "quiet", disabled = not won or LR.groupChannel() == nil, click = function()
        for _, line in ipairs(LR.Export.chat(s)) do LR.say(line, LR.groupChannel()) end
        UI.toast("Posted who won what.")
      end, tip = "Who won what, in a few raid lines." },
    }, more)
  elseif leader or won then
    UI.pin({
      won and { label = "Export who won what", style = "quiet", click = function() UI.exportSheet(s) end } or nil,
      leader and not s.pv and won and { label = "Post in raid chat", style = "quiet", disabled = LR.groupChannel() == nil, click = function()
        for _, line in ipairs(LR.Export.chat(s)) do LR.say(line, LR.groupChannel()) end
        UI.toast("Posted who won what.")
      end } or nil,
    }, leader and { more[2], more[3] } or nil)
  end
end
