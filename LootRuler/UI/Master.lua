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

local MW = 320
local master, panel

---------------------------------------------------------------------- a row in the list of rolls
K.define("rollrow", function()
  local b = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
  b:SetBackdrop(K.FLAT)
  b:SetHeight(20)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
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
  -- what they wear in that slot now (from their addon): its icon, and the item on hover
  b.gear = CreateFrame("Button", nil, b)
  b.gear:SetSize(16, 16)
  b.gear:SetPoint("RIGHT", b.kind, "LEFT", -6, 0)
  b.gear.icon = b.gear:CreateTexture(nil, "ARTWORK")
  b.gear.icon:SetAllPoints()
  b.gear.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.gear:SetScript("OnEnter", function(self)
    if not self.links then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(self.links[1])
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("What they wear there now." .. (self.links[2] and (" Also: " .. self.links[2]) or ""), 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  b.gear:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  return b
end, function(b)
  b.gear.links = nil b.gear:Hide()
  b.rank:SetText("") b.name:SetText("") b.kind:SetText("") b.num:SetText("")
  b.num:SetTextColor(1, 1, 1) b.kind:SetTextColor(K.rgb(K.GOLD)) b.rank:SetTextColor(K.rgb(K.GOLD))
  b:SetBackdropColor(0, 0, 0, 0.35) b:SetBackdropBorderColor(0.42, 0.33, 0.19, 0.5)
  b:Enable()
end)

---------------------------------------------------------------------- the loot master window
--- a roll nobody rolls in: hard reserved, or one player first on the priority list
local function noRoll(roll) return roll.mode == "HR" or (roll.mode == "PR" and #roll.who == 1) end

local function selectedPlayer(roll)
  if roll.pick then return roll.pick end
  -- a loot council: their choice, when they've made one
  local choice = LR.Council.choice(roll)
  if choice and roll.state == "closed" then return choice end
  if roll.mode == "PR" and #roll.who == 1 then return roll.who[1] end
  if roll.mode == "BID" then local top = R.topBid(roll) return top and top.p end
  if roll.mode == "HR" then
    local f = roll.f or ""
    for _, m in ipairs(LR.roster()) do
      if f ~= "" and (U.samePlayer(m.name, f) or U.foldCase(U.bare(m.name)) == U.foldCase(U.bare(f))) then return m.name end
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
    if UI.reserveStrip then UI.reserveStrip() end
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
    local whole = math.ceil(left)
    if master.shownSecs ~= whole then master.shownSecs = whole master.secs:SetText(whole .. " s left") end
  else
    master.bar.fill:SetWidth(full)
    master.bar.fill:SetVertexColor(0.45, 0.45, 0.45)
    master.shownSecs = nil
    master.secs:SetText(roll.state == "awarded" and "Given out" or noRoll(roll) and "No roll" or "Closed")
    master:SetScript("OnUpdate", nil)                 -- (over: nothing to count down, until the next redraw)
  end
end

local function modeLine(roll)
  if roll.mode == "HR" then
    return "|cffff5a4aHard reserved|r" .. ((roll.f or "") ~= "" and (" for " .. roll.f) or "") .. ((roll.n or "") ~= "" and (": " .. roll.n) or "")
  elseif roll.mode == "SR" then
    return "|cffffd100Soft reserved:|r " .. R.names(roll.who, 6) .. (#roll.away > 0 and ("; " .. R.names(roll.away, 2) .. " isn't here") or "")
  elseif roll.mode == "TIE" then
    return "|cffffd100Tie:|r " .. R.names(roll.who, 6) .. " roll again"
  elseif roll.mode == "BID" then
    return ("|cffffd100Auction:|r bids from %s, each %s more"):format(LR.Gdkp.gold(roll.min), LR.Gdkp.gold(roll.inc))
  elseif roll.mode == "PR" then
    local place = roll.n and LR.Prio.place(roll.n) or "first"
    if #roll.who == 1 then return ("|cff1eff00Priority list:|r %s is %s"):format(U.short(roll.who[1]), place) end
    return ("|cff1eff00Priority list:|r %s share %s, and roll"):format(R.names(roll.who, 6), place)
  end
  return "Everyone rolls: MS beats OS" .. (#roll.away > 0 and ("; reserved by " .. R.names(roll.away, 2) .. ", who isn't here") or "")
end

local function rowFor(f, roll, e, rank, pick)
  local b = K.get(f.owner, "rollrow", f.parent)
  b:SetWidth(f.width)
  local class = LR.classOf(e.p)
  b.rank:SetText(rank and tostring(rank) or "")
  local votes = e.kind and LR.Council.counts(roll)[e.p]
  b.name:SetText(U.classText(U.short(e.p), class) .. (votes and ("  |cff1eff00%s|r"):format(U.plural(votes, "vote")) or ""))
  b.name:SetWidth(f.width - 150)
  local links = roll.gear and roll.gear[R.key(e.p)]
  if links then
    b.gear.links = links
    b.gear.icon:SetTexture(LR.itemIcon(tonumber(links[1]:match("item:(%d+)")) or 0))
    b.gear:Show()
  end
  local num = roll.mode == "BID" and LR.Gdkp.gold(e.n) or tostring(e.n)
  if e.kind then
    local tries = roll.used and roll.used[R.key(e.p)] or 1
    b.kind:SetText(R.label(roll, e) .. (tries > 1 and (" |cff9d9d9d(best of %d)|r"):format(tries) or ""))
    b.num:SetText(num)
  else
    b.kind:SetText(R.WHY[e.why] or e.why or "")
    b.kind:SetTextColor(K.rgb(K.GREY))
    b.num:SetText(num)
    b.num:SetTextColor(K.rgb(K.GREY))
    b.name:SetText("|cff9d9d9d" .. U.short(e.p) .. "|r")
  end
  if pick and U.samePlayer(pick, e.p) and e.kind then
    b:SetBackdropColor(0.35, 0.27, 0.05, 0.9)
    b:SetBackdropBorderColor(1, 0.82, 0, 1)
  end
  local s = Rolls.session()
  local organiser = roll.mode == "BID" and s and s.gdkp and LR.isLeader(s) and not U.samePlayer(e.p, U.me())
  b:SetScript("OnClick", function(_, button)
    -- right-click a bidder: their bids aren't taken for the rest of tonight (the organiser's, optional)
    if button == "RightButton" then
      if organiser and not (roll.nb and roll.nb[R.key(e.p)]) then UI.noBidsSheet(e.p) end
      return
    end
    if e.kind and roll.state == "closed" then roll.pick = e.p UI.masterDraw() end
  end)
  f:place(b, 20)
  f:gap(2)
end

--- asks before the organiser stops taking a player's bids for tonight
function UI.noBidsSheet(player)
  UI.confirm("Stop taking their bids?", ("%s's bids won't count for the rest of tonight's auctions, this one included. The raid is told once. You can take them again on the Session tab."):format(U.short(player)),
    "Stop taking them", function()
      local ok, why = Rolls.noBidsFrom(player, true)
      if not ok and why then UI.toast(why) end
    end)
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
  master:SetScript("OnUpdate", UI.masterTick)        -- (the bar: every frame while the roll is open, then once more)
  -- where it goes: where the loot master put it, else beside the loot panel, else near the middle
  master:ClearAllPoints()
  local pt = LR.db.ui.masterPoint
  if pt then master:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
  elseif panel and panel:IsShown() then master:SetPoint("TOPLEFT", panel, "TOPRIGHT", 4, 0)
  else master:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 540, -120) end
  local name, hex = LR.linkParts(roll.link, roll.id)
  master.item.icon:SetTexture(LR.itemIcon(roll.id))
  master.item.name:SetText("|cff" .. hex .. name .. "|r")
  local council = LR.Council.on(Rolls.session()) and roll.mode ~= "BID" and roll.mode ~= "HR"
  master.item.sub:SetText(modeLine(roll) .. (council and "; |cff1eff00the council picks|r" or ""))
  local f = K.flow("master", master.body, 0, 0, MW - 32)
  local good, bad = R.standings(roll)
  local pick = selectedPlayer(roll)
  local inLoot = Rolls.lootSlot(roll) ~= nil and LR.isMasterLooter()
  local give = inLoot and "Give to " or "Award to "
  local s = Rolls.session()
  local closed = roll.state ~= "open" and roll.state ~= "awarded"
  local function award()
    local ok, note = Rolls.award(pick)
    if ok and note then roll.note = note end
    if not ok then UI.masterNote(note) end
  end
  -- closed, with someone to give it to: the winner first, as a card with the one main button
  local winner = closed and pick and roll.mode ~= "HR"
  if winner then
    local e
    for _, x in ipairs(good) do if U.samePlayer(x.p, pick) then e = x end end
    f:hot(nil, function(p)
      p:text(roll.pick and "YOUR PICK" or (LR.Council.choice(roll) and "THE COUNCIL'S CHOICE") or (roll.mode == "BID" and "HIGHEST BID") or "WINNER",
        { font = "GameFontNormalSmall", color = K.GOLD, gap = 2 })
      local kv = K.get(p.owner, "kv", p.parent)
      kv.k:SetFontObject("GameFontNormalLarge")
      local tries = e and roll.used and roll.used[R.key(e.p)] or 1
      kv.k:SetText(U.classText(U.short(pick), LR.classOf(pick)) .. (e and ("  |cffbdb5a3" .. R.label(roll, e) .. "|r") or "")
        .. (tries > 1 and (" |cff9d9d9d(best of %d)|r"):format(tries) or ""))
      kv.v:SetFontObject("GameFontHighlightLarge")
      kv.v:SetText(e and (roll.mode == "BID" and LR.Gdkp.gold(e.n) or tostring(e.n)) or "")
      kv:SetWidth(p.width)
      p:place(kv, 24)
      local links = roll.gear and roll.gear[R.key(pick)]
      if links then p:note("Wearing: " .. links[1]) end
      p:gap(2)
      p:buttons({ { label = give .. U.short(pick), width = p.width, click = award } }, "left")
    end)
  end
  if not noRoll(roll) then
    if #good == 0 and #bad == 0 then
      if roll.mode == "BID" then f:note(roll.state == "open" and "No bids yet." or "Nobody bid.")
      else f:note(roll.state == "open" and "No rolls yet." or "Nobody rolled.") end
    end
    local others = good
    if winner then
      others = U.filter(good, function(x) return not U.samePlayer(x.p, pick) end)
      if #others > 0 then f:text("Everyone else", { font = "GameFontNormalSmall", color = K.SUB, gap = 2 }) end
    end
    for _, e in ipairs(others) do
      local rank
      for i, x in ipairs(good) do if x == e then rank = i end end
      rowFor(f, roll, e, rank, pick)
    end
    -- (a player's lower rolls on their reserves aren't rows of their own: their best says how many it was the best of)
    local lower = 0
    for _, e in ipairs(bad) do
      if e.why == "lower" then lower = lower + 1 else rowFor(f, roll, e, nil, pick) end
    end
    if lower > 0 then f:note(("%s not listed: with more than one reserve, a player's best roll counts."):format(U.plural(lower, "lower roll"))) end
    local waiting = R.waiting(roll)
    if waiting and #waiting > 0 and roll.state == "open" then
      -- (anyone away first, so they're never cut off by "+N")
      local away = Rolls.away(roll, waiting)
      local list = {}
      for _, name in ipairs(waiting) do if away[R.key(name)] then list[#list + 1] = name end end
      for _, name in ipairs(waiting) do if not away[R.key(name)] then list[#list + 1] = name end end
      local parts = {}
      for i, name in ipairs(list) do
        if i > 8 then parts[#parts + 1] = "+" .. (#list - 8) break end
        local why = away[R.key(name)]
        parts[#parts + 1] = U.short(name) .. (why == "offline" and " (offline)" or why == "left" and " (left the group)" or "")
      end
      f:note("Still to roll: " .. table.concat(parts, ", "))
      if next(away) then f:note("Waiting for someone who's away: wait for them to come back, or click Close now.", K.GOLD) end
    end
    if roll.mode == "BID" and s and s.gdkp and LR.isLeader(s) and #good > 0 then f:note("Right-click a bidder to stop taking their bids tonight.") end
    -- the loot council's votes so far
    if LR.Council.on(s) and LR.Council.votable(roll) then
      local _, voted = LR.Council.counts(roll)
      local choice, top = LR.Council.choice(roll)
      f:note(("Loot council: %d of %d voted.%s"):format(voted, #s.lc, choice and (" Their choice: %s (%s)."):format(U.short(choice), U.plural(top, "vote"))
        or (voted > 0 and " A tie so far." or "")), K.GOLD)
    end
    local passed = {}
    for _, name in pairs(roll.passed) do passed[#passed + 1] = U.short(name) end
    table.sort(passed)
    if #passed > 0 then f:note("Passed: " .. table.concat(passed, ", ")) end
  end
  f:gap(4)
  if roll.state == "open" then
    f:buttons({
      { label = "Close now", click = function() Rolls.stop() end },
      { label = "+10 sec", style = "quiet", width = 70, click = function() Rolls.extend(10) end },
      { label = "Call off", style = "link", danger = true, click = function() Rolls.cancel() end },
    }, "left")
  elseif roll.state == "awarded" then
    local sold = roll.mode == "BID" and not roll.de and R.topBid(roll)
    f:text((sold and "Sold to " or "Given to ") .. U.classText(U.short(roll.winner), LR.classOf(roll.winner))
      .. (roll.de and ", to disenchant." or sold and (" for " .. LR.Gdkp.gold(sold.n) .. ".") or "."), { font = "GameFontNormal" })
    if roll.note then f:note(roll.note, K.GOLD) end
    if s then f:note(LR.isLeader(s) and "It's on the soft reserves' list of loot given out." or "The soft reserves' leader keeps a list of loot given out.") end
    f:buttons({
      { label = "Close", click = function() Rolls.dismiss() end },
      { label = "Undo", style = "link", click = function()
        local ok, note = Rolls.undo()
        if ok then roll.undoNote = note end
        if not ok then UI.masterNote(note) end
        UI.masterDraw()
      end, tip = "Wrong player? Undo, then give it to someone else or roll it again." },
    }, "left")
  else
    local _, tied = R.result(roll)
    if roll.mode == "HR" and not pick then
      f:note("Hard reserved" .. ((roll.f or "") ~= "" and (" for " .. roll.f .. ", who isn't in the group") or "") .. ": give it out yourself, or roll it out anyway.", K.GOLD)
    end
    if roll.undoNote then f:note(roll.undoNote, K.GOLD) end
    if tied and not roll.pick then f:note("A tie: roll it again between them, or click a name to pick.", K.GOLD) end
    local list = {}
    -- a hard reserve's player has no card (nobody rolled): the button is here
    if pick and not winner then list[#list + 1] = { label = give .. U.short(pick), click = award } end
    if tied then list[#list + 1] = { label = "Reroll the tie", style = #list > 0 and "quiet" or nil, click = function() Rolls.again("TIE") end } end
    -- nobody wants it: the disenchanter
    if s and s.de and not noRoll(roll) then
      list[#list + 1] = { label = "Disenchant (" .. U.short(s.de) .. ")", style = (pick or tied) and "quiet" or nil, click = function()
        local ok, note = Rolls.disenchant()
        if ok and note then roll.note = note end
        if not ok then UI.masterNote(note) end
      end }
    end
    if #list > 0 then f:buttons(list, "left") end
    if s and not s.de and not noRoll(roll) and not pick then
      f:note("Nobody to give it to? Pick a disenchanter on the Session tab and it's one click.")
    end
    -- the rarer choices, as links
    local more = { { label = "Give to someone else", style = "link", click = function()
      UI.giveSheet({ id = roll.id, link = roll.link, slot = Rolls.lootSlot(roll), drop = roll.drop })
    end } }
    if roll.mode == "SR" or roll.mode == "HR" or roll.mode == "TIE" or roll.mode == "PR" then
      more[#more + 1] = { label = noRoll(roll) and "Roll it out anyway" or "Let everyone roll", style = "link", click = function() Rolls.again("OPEN") end }
    elseif roll.mode == "BID" then
      more[#more + 1] = { label = "Roll it out instead", style = "link", click = function() Rolls.again("OPEN") end }
    else
      more[#more + 1] = { label = "Roll again", style = "link", click = function() Rolls.again("OPEN") end }
    end
    more[#more + 1] = { label = "Call off", style = "link", danger = true, click = function() Rolls.cancel() end }
    f:buttons(more, "left")
    if pick and not inLoot then
      f:note(LR.isMasterLooter() and "The item isn't in the open loot window: it's marked as theirs, for you to trade it." or "You're not the master looter: it's marked as theirs and announced, for whoever has it to hand it over.")
    end
  end
  -- what's waiting its turn
  if #Rolls.queue > 0 then
    local ahead = 0
    for id in pairs(Rolls.ahead) do ahead = ahead + Rolls.aheadCount(id) end
    f:note(("%s in the queue after this one.%s"):format(U.plural(#Rolls.queue, "more item"),
      ahead > 0 and (" %s placed ahead."):format(U.plural(ahead, "bid")) or ""), K.GOLD)
    f:buttons({ { label = "Stop the queue", style = "link", click = function() Rolls.clearQueue() UI.masterDraw() end } }, "left")
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
  if UI.reserveStrip then UI.reserveStrip() end
  master:Raise()
end

---------------------------------------------------------------------- giving an item out without a roll
--- a sheet to give an item to someone without rolling: who (the players who reserved it first, apart), and how.
--- it: { id, link, slot, drop, to = who's picked to start with }
function UI.giveSheet(it)
  local s = Rolls.session()
  local pick, how = it.to, "MS"
  UI.show()
  local reserved = {}
  for _, w in ipairs(s and S.byItem(s)[it.id] or {}) do if S.claims(s, w[1], it.id) > 0 then reserved[U.foldCase(w[1])] = true end end
  if pick and reserved[U.foldCase(pick)] then how = "SR" end
  UI.openSheet("Give " .. U.plain(it.link or LR.itemLink(it.id)), function(f, h)
    f:note("Pick who gets it and how, without a roll. It goes through master loot if it's in the open loot window, or is marked for you to trade.")
    -- who: the players who reserved it, then everyone else in the group
    local people = LR.roster()
    if #people == 0 then people = { { name = U.me(), class = LR.myClass() } } end
    table.sort(people, function(a, b) return a.name < b.name end)
    local function chip(m)
      local sr = reserved[U.foldCase(m.name)]
      return { label = U.classText(U.short(m.name), m.class) .. (sr and " |cffffd100SR|r" or ""), on = pick and U.samePlayer(pick, m.name),
        click = function() pick = m.name if sr then how = "SR" elseif how == "SR" then how = "MS" end h.redraw(true) end }
    end
    local res, rest = {}, {}
    for _, m in ipairs(people) do
      if reserved[U.foldCase(m.name)] then res[#res + 1] = chip(m) else rest[#rest + 1] = chip(m) end
    end
    if #res > 0 then
      f:text("Reserved it", { font = "GameFontNormalSmall", color = K.GOLD, gap = 2 })
      f:chips(res)
    end
    if #rest > 0 then
      f:text(#res > 0 and "Everyone else" or "Who", { font = "GameFontNormalSmall", color = K.GOLD, gap = 2 })
      f:chips(rest)
    end
    f:gap(2)
    f:row("How", function(r)
      local ways = {}
      if pick and reserved[U.foldCase(pick)] then ways[#ways + 1] = { label = "Their reserve", on = how == "SR", click = function() how = "SR" h.redraw(true) end } end
      ways[#ways + 1] = { label = "Main spec", on = how == "MS", click = function() how = "MS" h.redraw(true) end }
      ways[#ways + 1] = { label = "Off spec", on = how == "OS", click = function() how = "OS" h.redraw(true) end }
      ways[#ways + 1] = { label = "To disenchant", on = how == "DE", click = function()
        how = "DE"
        if not pick and s and s.de then pick = s.de end
        h.redraw(true)
      end }
      r:chips(ways, { gap = 2 })
    end, { lw = 50 })
    if s and s.de and how ~= "DE" then f:note(("%s disenchants: pick To disenchant, then them."):format(U.short(s.de))) end
    f:gap(4)
    local function go(who, kind)
      h.close()
      local ok, note = Rolls.give(it.id, who, kind, it)
      if not ok then UI.toast(note) else UI.masterDraw() if note then UI.masterNote(note) end end
    end
    f:buttons({
      { label = "Cancel", style = "quiet", click = function() h.close() end },
      s and s.de and not pick and { label = "Disenchant", style = "quiet", click = function() go(s.de, "DE") end } or nil,
      { label = pick and ((how == "DE" and "Disenchant: " or "Give to ") .. U.short(pick)) or "Give", disabled = not pick, click = function() go(pick, how) end },
    })
  end)
end

---------------------------------------------------------------------- the loot panel (beside the loot window)
local function lootSub(s, it)
  if not s then return LR.itemKind(it.id) end
  if s.hr[it.id] then return "|cffff5a4aHard reserved|r" .. (s.hr[it.id].f ~= "" and (" for " .. s.hr[it.id].f) or "") end
  if s.gdkp and s.gk then
    local usual, n = LR.History.usualPrice(it.id, s)
    return "Auction: bids from " .. LR.Gdkp.gold(LR.Gdkp.minFor(s, it.id)) .. (usual and (" (sold for " .. LR.Gdkp.gold(usual) .. (n > 1 and " on average" or "") .. " before)") or "")
  end
  local pr = s.prio and LR.Guild.prioPlan(it.id)
  if pr then return ("|cff1eff00Priority %s:|r %s"):format(LR.Prio.place(pr.n), R.names(pr.who, 4)) end
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
  panel.title:SetText(LR.TITLE)
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
  local auction = s and s.gdkp
  f:note(busy and ((auction and "Auctioning " or "Rolling for ") .. U.plain(Rolls.mine().link) .. "...")
    or (auction and "Click an item to auction it, or auction them all one after another." or "Click an item to roll it out, or roll them all out one after another."))
  for _, it in ipairs(Rolls.loot()) do
    local b = K.get(f.owner, "item", f.parent)
    local hr = s and s.hr[it.id]
    K.setItem(b, f.width, LR.itemIcon(it.id), it.link and ("|cff" .. select(2, LR.linkParts(it.link, it.id)) .. select(1, LR.linkParts(it.link, it.id)) .. "|r") or LR.coloredName(it.id),
      lootSub(s, it), hr and "|cffff5a4aHR|r" or "",
      not busy and { text = "Give", width = 40, tip = "Give it to someone without a roll", click = function()
        UI.giveSheet({ id = it.id, link = it.link, slot = it.slot, drop = LR.Drops.forSlot(it.slot) })
      end } or nil)
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
  -- all of them, one after another (the queue)
  local loot = Rolls.loot()
  if #loot > 1 then
    f:buttons({ { label = auction and "Auction them all" or "Roll them all out", click = function()
      local list = {}
      for _, it in ipairs(loot) do list[#list + 1] = { id = it.id, link = it.link, slot = it.slot, drop = LR.Drops.forSlot(it.slot) } end
      Rolls.enqueue(list)
      UI.masterDraw()
    end } }, "left")
    -- a GDKP: all at once, ending together (Core/Batch.lua)
    if auction then f:buttons({ { label = "Auction them together", click = function() UI.batchSheet() end } }, "left") end
  end
  if #Rolls.queue > 0 then f:note(("%s waiting their turn."):format(U.plural(#Rolls.queue, "item")), K.GOLD) end
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
  -- (a roll changes with every /roll: forty in two seconds redraw a few times, not forty)
  if what == "roll" then UI.atMostEvery("master", UI.REDRAW_GAP, function() UI.masterDraw() UI.lootPanel() end)
  elseif what == "loot" or what == "session" or what == "roster" then
    UI.lootPanel()
    -- (someone a roll waits for may have gone offline, or come back)
    if (what == "loot" or what == "roster") and master and master:IsShown() then UI.masterDraw() end
  end
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

---------------------------------------------------------------------- becoming the master looter
-- When I become the master looter, LootRuler asks once what to do (Settings: mlPrompt): open the loot master window,
-- and tell the raid how loot works. Or it tells the raid by itself (Settings: mlAnnounce).
local wasML = nil              -- (nil until the game has settled after logging in: no question for a reload)

--- the raid line: who runs loot, and how to roll (and reserve, while reserves are open)
function UI.masterLooterLine()
  local s = Rolls.session()
  local line = ("%s is the master looter. Items are rolled out in raid chat: /roll for main spec, /roll 99 for off spec."):format(U.short(U.me()))
  if s and not s.gdkp and not s.locked then line = line .. " Reserved items: only those who reserved them roll."
  elseif s and s.gdkp then line = ("%s is the master looter. Items are auctioned: type your bid in raid chat."):format(U.short(U.me())) end
  return line
end
function LR.announceMasterLooter()
  local ch = LR.groupChannel()
  if not ch then return false end
  for _, l in ipairs(U.chatLines(LR.TAG .. " " .. UI.masterLooterLine())) do LR.say(l, ch) end
  return true
end

function UI.masterLooterPrompt()
  UI.show()
  UI.openSheet("You're the master looter", function(f, h)
    f:text("LootRuler can run the loot: roll windows for everyone, reserves, trades and the raid's loot list.")
    f:note("The raid hears: \"" .. UI.masterLooterLine() .. "\"")
    f:gap(6)
    f:buttons({
      { label = "Tell the raid", disabled = LR.groupChannel() == nil, click = function()
        if LR.announceMasterLooter() then UI.toast("Posted in " .. (IsInRaid() and "raid" or "party") .. " chat.") end
      end },
      { label = "Open the loot master window", style = "quiet", click = function() h.close() UI.showMaster() end },
    }, "left")
    f:gap(4)
    local set = LR.db.settings
    f:chips({ { tick = true, label = "Don't ask again", on = not set.mlPrompt, click = function() set.mlPrompt = not set.mlPrompt h.redraw(true) end,
      tip = "Settings tab, Rolling out loot, to ask again." } })
    f:buttons({ { label = "Not now", style = "quiet", click = function() h.close() end } })
  end)
end

local function checkMasterLooter()
  if not LR.db then return end
  local now = IsInGroup() and LR.isMasterLooter() or false
  local before = wasML
  wasML = now
  if before == nil or before or not now then return end
  if LR.db.settings.mlAnnounce then LR.announceMasterLooter() end
  if LR.db.settings.mlPrompt and not InCombatLockdown() then UI.masterLooterPrompt() end
end
local mlEvents = CreateFrame("Frame")
mlEvents:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
mlEvents:RegisterEvent("GROUP_ROSTER_UPDATE")
mlEvents:RegisterEvent("PLAYER_LOGIN")
mlEvents:SetScript("OnEvent", function(_, event)
  if event == "GROUP_ROSTER_UPDATE" then LR.rosterChanged() end   -- (may run before Core/Net.lua's handler)
  if event == "PLAYER_LOGIN" then
    C_Timer.After(5, function() wasML = IsInGroup() and LR.isMasterLooter() or false end)
    return
  end
  if wasML ~= nil then checkMasterLooter() end
end)

---------------------------------------------------------------------- loot given out without LootRuler
-- The master looter gave an item with the game's own loot menu: it's on the raid's loot list as theirs, but not as
-- given out. One question puts it on the list of loot given out (announced like any other award), or leaves it.
function UI.unrecordedPrompt(s, d, who)
  local link = LR.itemLink(d.i)
  LR.print(("%s went to %s outside LootRuler."):format(link, U.short(who)))
  UI.show()
  UI.openSheet("Record it?", function(f, h)
    f:text(("You gave %s to %s with the game's loot menu, so it isn't on the list of loot given out yet."):format(link, U.classText(U.short(who), LR.classOf(who))))
    f:note("Record it and the raid is told, like any item you give out. How did they get it?")
    local kinds = { { "MS", "Main spec" }, { "OS", "Off spec" } }
    if S.claims(s, who, d.i) > 0 then table.insert(kinds, 1, { "SR", "Their reserve" }) end
    kinds[#kinds + 1] = { "DE", "To disenchant" }
    local list = {}
    for _, k in ipairs(kinds) do
      list[#list + 1] = { label = k[2], click = function()
        h.close()
        local ok, why = Rolls.give(d.i, who, k[1], { link = link, drop = d.k })
        UI.toast(ok and ("Recorded: %s to %s."):format(U.plain(link), U.short(who)) or why)
      end }
    end
    f:buttons(list, "left")
    f:buttons({ { label = "Leave it", click = function() h.close() end } })
  end)
end
