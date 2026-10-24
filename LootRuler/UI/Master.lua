-- The loot master's side of rolling out loot:
--   the loot panel   beside the game's loot window (master loot): every item worth rolling for, who
--                    reserved it, and a click to roll it out
--   the loot master  the roll that's on: the timer, every roll as it comes in (the ones that count first,
--   window           best first), who's still to roll, then who to give it to
-- Plus the "Rolling out loot" settings on the Session tab.
local _, LR = ...
local U, K, S, R = LR.U, LR.K, LR.Session, LR.Roll
local UI = LR.UI
local Rolls = LR.Rolls

local MW = 300
local master, panel

---------------------------------------------------------------------- a row in the list of rolls
K.define("rollrow", function()
  local b = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
  b:SetBackdrop(K.FLAT)
  b:SetHeight(20)
  b.rank = K.fs(b, "GameFontNormalSmall")
  b.rank:SetPoint("LEFT", 6, 0)
  b.rank:SetWidth(16)
  b.rank:SetJustifyV("MIDDLE")
  b.name = K.fs(b, "GameFontHighlight")
  b.name:SetPoint("LEFT", 24, 0)
  b.name:SetJustifyV("MIDDLE")
  b.name:SetWordWrap(false)
  b.kind = K.fs(b, "GameFontNormalSmall")
  b.kind:SetJustifyH("RIGHT")
  b.kind:SetJustifyV("MIDDLE")
  b.num = K.fs(b, "GameFontHighlightLarge")
  b.num:SetJustifyH("RIGHT")
  b.num:SetJustifyV("MIDDLE")
  b.num:SetPoint("RIGHT", -6, 0)
  b.num:SetWidth(36)
  b.kind:SetPoint("RIGHT", b.num, "LEFT", -4, 0)
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  return b
end, function(b)
  b.rank:SetText("") b.name:SetText("") b.kind:SetText("") b.num:SetText("")
  b.num:SetTextColor(1, 1, 1) b.kind:SetTextColor(K.rgb(K.GOLD)) b.rank:SetTextColor(K.rgb(K.GOLD))
  b:SetBackdropColor(0, 0, 0, 0.35) b:SetBackdropBorderColor(0.42, 0.33, 0.19, 0.5)
  b:Enable()
end)

---------------------------------------------------------------------- the loot master window
local function selectedPlayer(roll)
  if roll.pick then return roll.pick end
  if roll.mode == "HR" then
    local f = roll.f or ""
    for _, m in ipairs(LR.roster()) do
      if f ~= "" and (U.samePlayer(m.name, f) or U.bare(m.name):lower() == U.bare(f):lower()) then return m.name end
    end
    return nil
  end
  local top, tied = R.result(roll)
  if top and not tied then return top.p end
end

local function build()
  master = CreateFrame("Frame", "LootRulerMasterFrame", UIParent, "BackdropTemplate")
  master:SetSize(MW, 200)
  master:SetBackdrop(K.ROCK)
  master:SetFrameStrata("HIGH")
  master:SetToplevel(true)
  master:SetClampedToScreen(true)
  master:SetMovable(true)
  master:EnableMouse(true)
  master:RegisterForDrag("LeftButton")
  master:SetScript("OnDragStart", function(self) self:StartMoving() end)
  master:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    LR.db.ui.masterPoint = { point, relPoint, x, y }
  end)
  master.close = CreateFrame("Button", nil, master, "UIPanelCloseButton")
  master.close:SetPoint("TOPRIGHT", -4, -4)
  master.close:SetScript("OnClick", function()
    local roll = Rolls.mine()
    if roll and roll.state ~= "open" then Rolls.dismiss() elseif roll then master.hiddenFor = roll.k end
    master:Hide()
  end)
  K.tooltipOn(master.close, function(tt)
    local roll = Rolls.mine()
    tt:SetText(roll and roll.state == "open" and "Hide (the roll goes on: /lr master brings this back)" or "Close", 1, 1, 1, 1, true)
  end)

  master.title = K.fs(master, "GameFontNormal")
  master.title:SetPoint("TOPLEFT", 18, -16)
  master.title:SetText("Loot master")
  master.item = CreateFrame("Button", nil, master, "BackdropTemplate")
  master.item:SetSize(MW - 36, 44)
  master.item:SetPoint("TOPLEFT", 16, -34)
  K.iconParts(master.item)
  K.placeIcon(master.item, 0, 0, 40)
  master.item.name = K.fs(master.item, "GameFontNormal")
  master.item.name:SetPoint("TOPLEFT", 46, -3)
  master.item.name:SetWidth(MW - 84)
  master.item.name:SetWordWrap(false)
  master.item.sub = K.fs(master.item, "GameFontHighlightSmall")
  master.item.sub:SetPoint("TOPLEFT", 46, -19)
  master.item.sub:SetWidth(MW - 84)
  master.item.sub:SetWordWrap(true)
  master.item:SetScript("OnEnter", function(self)
    local roll = Rolls.mine()
    if not roll then return end
    UI.itemTooltip(self, Rolls.session(), roll.id)
  end)
  master.item:SetScript("OnLeave", function() GameTooltip:Hide() end)
  master.item:SetScript("OnClick", function() local roll = Rolls.mine() if roll then UI.modifiedClick(roll.link) end end)

  master.bar = CreateFrame("Frame", nil, master, "BackdropTemplate")
  master.bar:SetSize(MW - 90, 12)
  master.bar:SetPoint("TOPLEFT", 18, -84)
  master.bar:SetBackdrop(K.FLAT)
  master.bar:SetBackdropColor(0, 0, 0, 1)
  master.bar:SetBackdropBorderColor(0.42, 0.33, 0.19, 1)
  master.bar.fill = master.bar:CreateTexture(nil, "ARTWORK")
  master.bar.fill:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
  master.bar.fill:SetPoint("TOPLEFT", 1, -1)
  master.bar.fill:SetPoint("BOTTOMLEFT", 1, 1)
  master.secs = K.fs(master, "GameFontHighlightSmall")
  master.secs:SetPoint("LEFT", master.bar, "RIGHT", 8, 0)
  master.secs:SetJustifyV("MIDDLE")

  master.body = CreateFrame("Frame", nil, master)
  master.body:SetPoint("TOPLEFT", 16, -104)
  master.body:SetSize(MW - 32, 10)
  master:SetScript("OnUpdate", function() UI.masterTick() end)
  master:Hide()
  tinsert(UISpecialFrames, "LootRulerMasterFrame")
end

function UI.masterTick()
  local roll = Rolls.mine()
  if not roll or not master:IsShown() then return end
  local full = MW - 92
  if roll.state == "open" then
    local left = math.max(0, roll.ends - GetTime())
    master.bar.fill:SetWidth(math.max(1, full * math.min(1, left / roll.secs)))
    master.bar.fill:SetVertexColor(1, left <= 5 and 0.35 or 1, 0)
    master.secs:SetText(math.ceil(left) .. " s left")
  else
    master.bar.fill:SetWidth(full)
    master.bar.fill:SetVertexColor(0.45, 0.45, 0.45)
    master.secs:SetText(roll.state == "awarded" and "Given out" or roll.mode == "HR" and "No roll" or "Closed")
  end
end

local function modeLine(roll)
  if roll.mode == "HR" then
    return "|cffff5a4aHard reserved|r" .. ((roll.f or "") ~= "" and (" for " .. roll.f) or "") .. ((roll.n or "") ~= "" and (": " .. roll.n) or "")
  elseif roll.mode == "SR" then
    return "|cffffd100Soft reserved:|r " .. R.names(roll.who, 6) .. (#roll.away > 0 and ("; " .. R.names(roll.away, 2) .. " isn't here") or "")
  elseif roll.mode == "TIE" then
    return "|cffffd100Tie:|r " .. R.names(roll.who, 6) .. " roll again"
  end
  return "Everyone rolls: MS beats OS" .. (#roll.away > 0 and ("; reserved by " .. R.names(roll.away, 2) .. ", who isn't here") or "")
end

local function rowFor(f, roll, e, rank, pick)
  local b = K.get(f.owner, "rollrow", f.parent)
  b:SetWidth(f.width)
  local class = LR.classOf(e.p)
  b.rank:SetText(rank and tostring(rank) or "")
  b.name:SetText(U.classText(U.short(e.p), class))
  b.name:SetWidth(f.width - 130)
  if e.kind then
    b.kind:SetText(R.LABEL[e.kind])
    b.num:SetText(tostring(e.n))
  else
    b.kind:SetText(R.WHY[e.why] or e.why or "")
    b.kind:SetTextColor(K.rgb(K.GREY))
    b.num:SetText(tostring(e.n))
    b.num:SetTextColor(K.rgb(K.GREY))
    b.name:SetText("|cff9d9d9d" .. U.short(e.p) .. "|r")
  end
  if pick and U.samePlayer(pick, e.p) and e.kind then
    b:SetBackdropColor(0.35, 0.27, 0.05, 0.9)
    b:SetBackdropBorderColor(1, 0.82, 0, 1)
  end
  if e.kind and roll.state == "closed" then
    b:SetScript("OnClick", function() roll.pick = e.p UI.masterDraw() end)
  end
  f:place(b, 20)
  f:gap(2)
end

--- draws the loot master window for the roll that's on (or was last)
function UI.masterDraw()
  local roll = Rolls.mine()
  if not master then
    if not roll then return end
    build()
  end
  K.release("master")
  if not roll then master:Hide() return end
  -- where it goes: where the loot master put it, else beside the loot panel, else near the middle
  master:ClearAllPoints()
  local pt = LR.db.ui.masterPoint
  if pt then master:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
  elseif panel and panel:IsShown() then master:SetPoint("TOPLEFT", panel, "TOPRIGHT", 4, 0)
  else master:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 540, -120) end
  local name, hex = LR.linkParts(roll.link, roll.id)
  master.item.icon:SetTexture(LR.itemIcon(roll.id))
  master.item.name:SetText("|cff" .. hex .. name .. "|r")
  master.item.sub:SetText(modeLine(roll))
  local f = K.flow("master", master.body, 0, 0, MW - 32)
  local good, bad = R.standings(roll)
  local pick = selectedPlayer(roll)
  if roll.mode ~= "HR" then
    if #good == 0 and #bad == 0 then
      f:note(roll.state == "open" and "No rolls yet." or "Nobody rolled.")
    end
    for i, e in ipairs(good) do rowFor(f, roll, e, i, pick) end
    for _, e in ipairs(bad) do rowFor(f, roll, e, nil, pick) end
    local waiting = R.waiting(roll)
    if waiting and #waiting > 0 and roll.state == "open" then f:note("Still to roll: " .. R.names(waiting, 8)) end
    local passed = {}
    for _, name in pairs(roll.passed) do passed[#passed + 1] = U.short(name) end
    table.sort(passed)
    if #passed > 0 then f:note("Passed: " .. table.concat(passed, ", ")) end
  end
  f:gap(4)
  local inLoot = Rolls.lootSlot(roll) ~= nil and LR.isMasterLooter()
  local give = inLoot and "Give to " or "Award to "
  if roll.state == "open" then
    f:buttons({
      { label = "+10 sec", width = 70, click = function() Rolls.extend(10) end },
      { label = "Close now", click = function() Rolls.stop() end },
      { label = "Call off", click = function() Rolls.cancel() end },
    }, "left")
  elseif roll.state == "awarded" then
    f:text("Given to " .. U.classText(U.short(roll.winner), LR.classOf(roll.winner)) .. ".", { font = "GameFontNormal" })
    if roll.note then f:note(roll.note, K.GOLD) end
    if Rolls.session() then f:note(LR.isLeader(Rolls.session()) and "It's on the soft reserves' list of loot given out." or "The soft reserves' leader keeps a list of loot given out.") end
    f:buttons({ { label = "Close", click = function() Rolls.dismiss() end } }, "left")
  else
    local _, tied = R.result(roll)
    if roll.mode == "HR" and not pick then
      f:note("Hard reserved" .. ((roll.f or "") ~= "" and (" for " .. roll.f .. ", who isn't in the group") or "") .. ": give it out yourself, or roll it out anyway.", K.GOLD)
    end
    if tied and not roll.pick then f:note("A tie: roll it again between them, or click a name to pick.", K.GOLD) end
    local list = {}
    if pick then
      list[#list + 1] = { label = give .. U.short(pick), click = function()
        local ok, note = Rolls.award(pick)
        if ok and note then roll.note = note end
        if not ok then UI.masterNote(note) end
      end }
    end
    if tied then list[#list + 1] = { label = "Reroll the tie", click = function() Rolls.again("TIE") end } end
    if #list > 0 then f:buttons(list, "left") end
    local more = {}
    if roll.mode == "SR" or roll.mode == "HR" or roll.mode == "TIE" then
      more[#more + 1] = { label = roll.mode == "HR" and "Roll it out anyway" or "Let everyone roll", click = function() Rolls.again("OPEN") end }
    else
      more[#more + 1] = { label = "Roll again", click = function() Rolls.again("OPEN") end }
    end
    more[#more + 1] = { label = "Call off", click = function() Rolls.cancel() end }
    f:buttons(more, "left")
    if pick and not inLoot then
      f:note(LR.isMasterLooter() and "The item isn't in the open loot window: it's marked as theirs, for you to trade it." or "You're not the master looter: it's marked as theirs and announced, for whoever has it to hand it over.")
    end
  end
  master.body:SetHeight(math.max(1, f.y))
  master:SetHeight(104 + f.y + 14)
  if master.hiddenFor ~= roll.k then master:Show() end
  UI.masterTick()
end

function UI.masterNote(text)
  if text then LR.print(text) end
end

function UI.showMaster()
  if not Rolls.mine() then LR.print("No loot is being rolled out. Open a corpse with master loot on, or /lr roll [item].") return end
  if master then master.hiddenFor = nil end
  UI.masterDraw()
  master:Raise()
end

---------------------------------------------------------------------- the loot panel (beside the loot window)
local function lootSub(s, it)
  if not s then return LR.itemKind(it.id) end
  if s.hr[it.id] then return "|cffff5a4aHard reserved|r" .. (s.hr[it.id].f ~= "" and (" for " .. s.hr[it.id].f) or "") end
  local plan = R.plan(s, it.id, LR.roster())
  if plan.mode == "SR" then return "|cffffd100SR:|r " .. R.names(plan.who, 4) end
  if #plan.away > 0 then return "Reserved by " .. R.names(plan.away, 2) .. " (not here)" end
  local won = S.winners(s, it.id)
  if #won > 0 then return "Nobody's reserve left; " .. U.short(won[#won][1]) .. " has one" end
  return "Nobody reserved it"
end

local function buildPanel()
  panel = CreateFrame("Frame", "LootRulerLootPanel", UIParent, "BackdropTemplate")
  panel:SetSize(300, 120)
  panel:SetBackdrop(K.ROCK)
  panel:SetFrameStrata("HIGH")
  panel:EnableMouse(true)
  panel.title = K.fs(panel, "GameFontNormal")
  panel.title:SetPoint("TOPLEFT", 18, -16)
  panel.title:SetText("LootRuler")
  panel.icon = panel:CreateTexture(nil, "ARTWORK")
  panel.icon:SetTexture(LR.LOGO)
  panel.icon:SetSize(18, 18)
  panel.icon:SetPoint("TOPRIGHT", -16, -13)
  panel.body = CreateFrame("Frame", nil, panel)
  panel.body:SetPoint("TOPLEFT", 16, -36)
  panel.body:SetSize(268, 10)
  panel:Hide()
end

local function panelWanted()
  if not Rolls.lootOpen or not IsInGroup() or not LR.isMasterLooter() then return false end
  return #Rolls.loot() > 0
end

function UI.lootPanel()
  if not panelWanted() then
    if panel then K.release("lootpanel") panel:Hide() end
    return
  end
  if not panel then buildPanel() end
  K.release("lootpanel")
  panel:ClearAllPoints()
  if LootFrame and LootFrame:IsShown() then
    panel:SetPoint("TOPLEFT", LootFrame, "TOPRIGHT", 4, 0)
  else
    panel:SetPoint("LEFT", UIParent, "LEFT", 260, 80)
  end
  local s = Rolls.session()
  local f = K.flow("lootpanel", panel.body, 0, 0, 268)
  local busy = Rolls.mine() and Rolls.mine().state == "open"
  f:note(busy and ("Rolling for " .. U.plain(Rolls.mine().link) .. "...") or "Click an item to roll it out.")
  for _, it in ipairs(Rolls.loot()) do
    local b = K.get(f.owner, "item", f.parent)
    local hr = s and s.hr[it.id]
    K.setItem(b, f.width, LR.itemIcon(it.id), it.link and ("|cff" .. select(2, LR.linkParts(it.link, it.id)) .. select(1, LR.linkParts(it.link, it.id)) .. "|r") or LR.coloredName(it.id),
      lootSub(s, it), hr and "|cffff5a4aHR|r" or "")
    if busy then b:SetAlpha(0.5) end
    b:SetScript("OnClick", function()
      if UI.modifiedClick(it.link) then return end
      local roll, why = Rolls.start(it.id, { link = it.link, slot = it.slot })
      if not roll then LR.print(why) return end
      UI.masterDraw()
    end)
    b:SetScript("OnEnter", function(self) UI.itemTooltip(self, s, it.id) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:place(b, 36)
    f:gap(2)
  end
  f:gap(4)
  local chips = { { plain = true, label = "Seconds:" } }
  local cur = LR.db.settings.rollSeconds or Rolls.DEFAULT_SECONDS
  for _, n in ipairs(Rolls.SECONDS) do
    chips[#chips + 1] = { label = tostring(n), width = 30, on = n == cur, tip = "How long everyone has to roll", click = function() LR.db.settings.rollSeconds = n UI.lootPanel() end }
  end
  f:chips(chips)
  panel.body:SetHeight(math.max(1, f.y))
  panel:SetHeight(36 + f.y + 12)
  panel:Show()
end

LR.onChange(function(what)
  if not LR.db then return end
  if what == "roll" then UI.masterDraw() UI.lootPanel()
  elseif what == "loot" or what == "session" or what == "roster" then UI.lootPanel() if what == "loot" and master and master:IsShown() then UI.masterDraw() end end
end)

--- /lr roll <item link, id or name>
function UI.rollCommand(text)
  text = U.trim(text or "")
  local id = tonumber(text:match("|Hitem:(%d+)")) or tonumber(text:match("^(%d+)$"))
  if not id and text ~= "" then
    local s = Rolls.session()
    local found, close = nil, {}
    if s then found, close = LR.findInSession(s, text, UnitFactionGroup("player")) end
    if not found and #close > 1 then LR.print("Which one? " .. table.concat(U.map(close, function(x) return LR.itemLink(x) end), " ", 1, math.min(#close, 5))) return end
    id = found
  end
  if not id then LR.print("/lr roll [item]: shift-click an item into it, or type its name (items of the soft reserves' raid).") return end
  local link = text:match("|c%x+|Hitem:.-|h|r") or LR.itemLink(id)
  local roll, why = Rolls.start(id, { link = link })
  if not roll then LR.print(why) return end
  UI.masterDraw()
end
