-- The roll window every raider with LootRuler gets when the loot master rolls an item out: the game's own
-- group loot frame (item slot, name plate, dice and coin, timer bar), with what LootRuler knows underneath:
-- who reserved it, whether you may roll, the highest roll so far, and who it went to.
--   dice  main spec: /roll (1-100), or your reserve on a reserved item
--   coin  off spec: /roll 99
--   green dice  a boosted roll: /roll 1+points to 100+points, spending your guild points if you win (boosted
--         rolls on, and you have points)
--   x     pass
-- Only what you may roll with can be clicked; the buttons just /roll, so the loot master's addon (or anyone
-- reading chat) counts them like any other roll.
local _, LR = ...
local U, K, R = LR.U, LR.K, LR.Roll
local UI = LR.UI

local W, H = 256, 98
local BAR = 140               -- the timer bar's width (it stops short of the coin)
local MAX = 4
local HIDE_AFTER = 8          -- a finished roll's window goes this long after it's over

local frames = {}             -- shown and spare windows
local anchor

local function modifiedClick(link)
  if IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(link) return true end
  if IsModifiedClick and IsModifiedClick("DRESSUP") and DressUpItemLink then DressUpItemLink(link) return true end
  return false
end
UI.modifiedClick = modifiedClick

--- the name and quality colour of a link ("|cffa335ee|Hitem:...|h[Name]|h|r")
function LR.linkParts(link, id)
  local hex = tostring(link or ""):match("|c%x%x(%x%x%x%x%x%x)")
  local name = tostring(link or ""):match("|h%[(.-)%]|h")
  return name or LR.itemName(id), hex or LR.qualityHex(id)
end

---------------------------------------------------------------------- what the window says
local function me() return U.me() end

--- the line under the timer for an auction
local function bidStatus(copy)
  local G = LR.Gdkp
  local top = R.topBid(copy)
  if copy.state == "awarded" or (copy.state == "closed" and copy.winner) then
    local who, g = copy.winner or (top and top.p), copy.winN or (top and top.n)
    if not who then return "Nobody bid." end
    if U.samePlayer(who, me()) then return ("|cff1eff00It's yours, for %s!|r"):format(G.gold(g)) end
    return ("Sold to %s for %s."):format(U.short(who), G.gold(g))
  end
  if copy.state == "closed" then return "Nobody bid." end
  if copy.state == "cancelled" then return "Called off." end
  local max = copy.myMax and (" Your max: " .. G.gold(copy.myMax) .. ".") or ""
  if top and U.samePlayer(top.p, me()) then return ("|cff1eff00You have the highest bid: %s.|r%s"):format(G.gold(top.n), max) end
  local how = copy.strict and "Type \"bid\" and an amount in raid chat, or click." or "Type a bid in raid chat, or click."
  if top then return ("Highest bid: %s, %s. %s%s"):format(U.short(top.p), G.gold(top.n), how, max) end
  return ("Bids start at %s. %s"):format(G.gold(copy.min or 0), how)
end

--- the line under the timer, for a raider's copy of a roll
function UI.rollStatus(copy)
  if copy.mode == "BID" then return bidStatus(copy) end
  local mine = copy.rolled[R.key(me())]
  local top, tied = R.result(copy)
  local function who(e) return U.samePlayer(e.p, me()) and "you" or U.short(e.p) end
  if copy.state == "awarded" then
    if copy.winner and U.samePlayer(copy.winner, me()) then return "|cff1eff00It's yours!|r" end
    return copy.winner and ("Given to " .. U.short(copy.winner) .. ".") or "Given out."
  end
  if copy.state == "closed" then
    if tied then return ("Tied at %d: %s. The loot master decides."):format(top.n, R.names(tied)) end
    if top then
      if U.samePlayer(top.p, me()) then return ("|cff1eff00You win with %d (%s).|r"):format(top.n, R.label(copy, top)) end
      return ("%s wins with %d (%s)."):format(U.short(top.p), top.n, R.label(copy, top))
    end
    return "Rolls closed. Nobody rolled."
  end
  if copy.state == "cancelled" then return "Called off." end
  local highest = top and ((tied and "Tied at " or "Highest: ") .. (tied and (top.n .. " (" .. R.names(tied, 3) .. ")") or (who(top) .. " " .. top.n .. " (" .. R.label(copy, top) .. ")"))) or nil
  if mine then
    local line = ("You rolled %d (%s)."):format(mine.n, R.label(copy, mine))
    if top and top == mine and not tied then return line .. " |cff1eff00That's the highest.|r" end
    return line .. (highest and (" " .. highest .. ".") or "")
  end
  if copy.passedByMe then return "You passed." .. (highest and (" " .. highest .. ".") or "") end
  if copy.mode == "SR" then
    if R.inList(copy.who, me()) then
      local others = U.filter(copy.who, function(w) return not U.samePlayer(R.nameOf(w), me()) end)
      return "|cffffd100You reserved this.|r " .. (#others > 0 and ("Also reserved by " .. R.names(others, 3) .. ".") or "Nobody else did.")
    end
    return "Reserved by " .. R.names(copy.who, 4) .. ": only they roll."
  end
  if copy.mode == "TIE" then
    local others = U.filter(copy.who, function(w) return not U.samePlayer(R.nameOf(w), me()) end)
    return "A tie: you and " .. R.names(others, 3) .. " roll again."
  end
  if copy.mode == "PR" then
    local place = copy.n and (LR.Prio.place(copy.n) .. " ") or ""
    if R.inList(copy.who, me()) then
      local others = U.filter(copy.who, function(w) return not U.samePlayer(R.nameOf(w), me()) end)
      return ("|cff1eff00You're %son the priority list|r, with %s: you roll for it."):format(place, R.names(others, 3))
    end
    return ("Priority list: %s (%s) roll for this."):format(R.names(copy.who, 4), place ~= "" and U.trim(place) or "first")
  end
  if highest then return highest .. "." end
  local it = LR.ITEMS[copy.id]
  if it and not LR.usableBy(copy.id, LR.myClass()) then return "|cff9d9d9dYour class can't use this.|r" end
  local lo = R.boostRange(copy, me())
  if lo and copy.mode == "OPEN" then return ("Dice: main spec. Green dice: boosted (%d points). Coin: off spec."):format(lo - 1) end
  return "Dice: main spec. Coin: off spec."
end

--- what each button does for me now: kind ("SR" / "MS" / "OS") or false, and why not
local function buttonsFor(copy)
  local opts = R.options(copy, me())
  local can = {}
  for _, k in ipairs(opts) do can[k] = true end
  local rolledAlready = copy.rolled[R.key(me())] ~= nil or copy.passedByMe or copy.state ~= "open"
  local dice = (can.SR and "SR") or (can.MS and "MS") or (copy.mode == "TIE" and copy.tie ~= "OS" and can[copy.tie] and copy.tie) or false
  local coin = can.OS and "OS" or false
  local boost = can.BR and "BR" or false
  if rolledAlready then dice, coin, boost = false, false, false end
  return dice, coin, boost
end

---------------------------------------------------------------------- the frame
local function setButton(b, enabled)
  if enabled then b:Enable() b:SetAlpha(1) else b:Disable() b:SetAlpha(0.35) end
  if b.tex then b.tex:SetDesaturated(not enabled) end
end

local function rollButton(f, kind)
  local b = CreateFrame("Button", nil, f)
  b:SetSize(32, 32)
  local dice = kind ~= "coin"
  local up = dice and "Interface\\Buttons\\UI-GroupLoot-Dice-Up" or "Interface\\Buttons\\UI-GroupLoot-Coin-Up"
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetTexture(up)
  b.tex:SetAllPoints()
  b:SetHighlightTexture(dice and "Interface\\Buttons\\UI-GroupLoot-Dice-Highlight" or "Interface\\Buttons\\UI-GroupLoot-Coin-Highlight", "ADD")
  b:SetPushedTexture(dice and "Interface\\Buttons\\UI-GroupLoot-Dice-Down" or "Interface\\Buttons\\UI-GroupLoot-Coin-Down")
  b:SetMotionScriptsWhileDisabled(true)
  b.label = K.fs(b, "GameFontNormalSmall")
  b.label:SetJustifyH("RIGHT")
  b.label:SetJustifyV("MIDDLE")
  b.label:SetPoint("RIGHT", b, "LEFT", -1, 0)
  if kind == "boost" then
    b.tex:SetVertexColor(0.45, 1, 0.45)
    -- the points, on the dice (there's no room beside it)
    b.label:SetFontObject("GameFontNormalSmall")
    b.label:ClearAllPoints()
    b.label:SetPoint("BOTTOM", b, "BOTTOM", 0, 1)
    b.label:SetJustifyH("CENTER")
  end
  return b
end

local function makeFrame(i)
  local f = CreateFrame("Frame", "LootRulerRollFrame" .. i, UIParent, "BackdropTemplate")
  f:SetSize(W, H)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() anchor:StartMoving() end)
  f:SetScript("OnDragStop", function()
    anchor:StopMovingOrSizing()
    local point, _, relPoint, x, y = anchor:GetPoint()
    LR.db.ui.rollPoint = { point, relPoint, x, y }
  end)

  f.slot = f:CreateTexture(nil, "ARTWORK")
  f.slot:SetTexture("Interface\\Buttons\\UI-EmptySlot")
  f.slot:SetSize(64, 64)
  f.slot:SetPoint("TOPLEFT", 3, -3)
  f.plate = f:CreateTexture(nil, "ARTWORK")
  f.plate:SetTexture("Interface\\MerchantFrame\\UI-Merchant-LabelSlots")
  f.plate:SetSize(128, 64)
  f.plate:SetPoint("LEFT", f.slot, "RIGHT", -9, -10)
  f.name = K.fs(f, "GameFontNormalSmall")
  f.name:SetSize(98, 30)
  f.name:SetJustifyV("MIDDLE")
  f.name:SetPoint("LEFT", f.slot, "RIGHT", -5, 5)
  f.dragon = f:CreateTexture(nil, "OVERLAY")
  f.dragon:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Gold-Dragon")
  f.dragon:SetSize(120, 120)
  f.dragon:SetPoint("TOPLEFT", -30, 15)
  f.corner = f:CreateTexture(nil, "OVERLAY")
  f.corner:SetSize(32, 32)
  f.corner:SetPoint("TOPRIGHT", -6, -7)

  f.item = CreateFrame("Button", nil, f)
  f.item:SetSize(34, 34)
  f.item:SetPoint("TOPLEFT", f.slot, "TOPLEFT", 15, -15)
  f.item.icon = f.item:CreateTexture(nil, "ARTWORK")
  f.item.icon:SetAllPoints()
  f.item:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  f.item:SetScript("OnEnter", function(self)
    local copy = f.copy
    if not copy then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(copy.link)
    if copy.mode == "SR" then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Soft reserved by", 1, 0.82, 0)
      for _, w in ipairs(copy.who) do GameTooltip:AddLine(R.names({ w }), 1, 1, 1) end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Rolled out by " .. U.short(copy.by), 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  f.item:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.item:SetScript("OnClick", function() if f.copy then modifiedClick(f.copy.link) end end)

  f.pass = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.pass:SetPoint("TOPRIGHT", f.corner, "TOPRIGHT", 5, 5)
  f.pass:SetScript("OnClick", function()
    local copy = f.copy
    if copy and IsShiftKeyDown() then UI.alwaysDo(copy, "pass") end
    if copy and copy.state == "open" and not copy.rolled[R.key(me())] then LR.Rolls.pass(copy) end
    if copy then copy.closedByMe = true end
    UI.rollWindows()
  end)
  K.tooltipOn(f.pass, function(tt)
    local copy = f.copy
    tt:SetText((copy and copy.state == "open" and not copy.rolled[R.key(me())]) and "Pass" or "Close", 1, 1, 1)
  end)

  f.dice = rollButton(f, "dice")
  f.dice:SetPoint("TOPRIGHT", -37, -14)
  f.coin = rollButton(f, "coin")
  f.coin:SetPoint("TOP", f.dice, "BOTTOM", -2, 2)
  f.boost = rollButton(f, "boost")
  f.boost:SetPoint("RIGHT", f.dice, "LEFT", -2, 0)
  for _, b in ipairs({ f.dice, f.coin, f.boost }) do
    b:SetScript("OnClick", function(self)
      if f.copy and self.kind == "BID" then
        -- shift-click: a max bid instead (LootRuler bids for me, up to it)
        if IsShiftKeyDown() then
          local copy = f.copy
          UI.show()
          UI.goldSheet("Max bid for " .. U.plain(copy.link), "LootRuler bids for you, as little as it takes to keep you on top, up to this. Nobody else sees it.",
            copy.myMax or self.amount, function(g)
              local ok, why = LR.Rolls.myMax(copy, g)
              if not ok then UI.toast(why) end
            end)
          return
        end
        LR.Rolls.bid(f.copy, self.amount)
        return
      end
      if f.copy and self.kind then
        if IsShiftKeyDown() and self ~= f.boost then UI.alwaysDo(f.copy, self.kind == "OS" and "OS" or "MS") end
        LR.Rolls.roll(f.copy, self.kind)
        UI.rollWindows()
      end
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.tipTitle or "", 1, 1, 1)
      if self.tip then GameTooltip:AddLine(self.tip, 1, 0.82, 0, true) end
      if self ~= f.boost and self.kind ~= "BID" then GameTooltip:AddLine("Shift-click: always do this for this item.", 0.5, 0.8, 1, true) end
      if self.kind == "BID" then GameTooltip:AddLine("Shift-click: a max bid (LootRuler bids for you, up to it).", 0.5, 0.8, 1, true) end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end

  -- the timer bar, as the game draws it
  f.bar = CreateFrame("Frame", nil, f)
  f.bar:SetSize(BAR, 10)
  f.bar:SetPoint("TOPLEFT", f.slot, "BOTTOMLEFT", 13, 10)
  f.bar.bg = f.bar:CreateTexture(nil, "BACKGROUND")
  f.bar.bg:SetAllPoints()
  f.bar.bg:SetColorTexture(0, 0, 0, 1)
  f.bar.fill = f.bar:CreateTexture(nil, "BORDER")
  f.bar.fill:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
  f.bar.fill:SetPoint("TOPLEFT")
  f.bar.fill:SetPoint("BOTTOMLEFT")
  f.bar.fill:SetWidth(BAR)
  f.bar.border = f.bar:CreateTexture(nil, "ARTWORK")
  f.bar.border:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-BarBorder")
  f.bar.border:SetSize(BAR + 4, 20)
  f.bar.border:SetPoint("TOP", 0, 5)
  -- the seconds left, on the bar
  f.secs = f.bar:CreateFontString(nil, "OVERLAY")
  f.secs:SetFontObject("GameFontHighlightSmall")
  f.secs:SetJustifyH("CENTER")
  f.secs:SetJustifyV("MIDDLE")
  f.secs:SetAllPoints()

  f.status = K.fs(f, "GameFontHighlightSmall")
  f.status:SetWidth(W - 28)
  f.status:SetPoint("TOPLEFT", 14, -72)
  f.status:SetWordWrap(true)

  f:SetScript("OnUpdate", function(self) UI.rollTick(self) end)
  f:Hide()
  return f
end

local function fill(f, copy)
  f.copy = copy
  local name, hex = LR.linkParts(copy.link, copy.id)
  local q = LR.ITEMS[copy.id] and LR.quality(copy.id) or (hex == "ff8000" and 5 or hex == "a335ee" and 4 or 3)
  local epic = q >= 4
  f:SetBackdrop(epic and {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
    tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } } or {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
  f.corner:SetTexture(epic and "Interface\\DialogFrame\\UI-DialogBox-Gold-Corner" or "Interface\\DialogFrame\\UI-DialogBox-Corner")
  f.dragon:SetShown(epic)
  f.item.icon:SetTexture(LR.itemIcon(copy.id))
  f.name:SetText("|cff" .. hex .. name .. "|r")

  if copy.mode == "BID" then
    -- an auction: the dice bids the least that counts, the coin a bigger jump; both just type it in raid chat
    local top = R.topBid(copy)
    local a1 = R.nextBid(copy)
    local a2 = a1 + 4 * (copy.inc or 1)
    local can = copy.state == "open" and not (top and U.samePlayer(top.p, me()))
    f.dice.kind, f.coin.kind, f.boost.kind = can and "BID" or nil, can and "BID" or nil, nil
    f.dice.amount, f.coin.amount = a1, a2
    setButton(f.dice, can)
    setButton(f.coin, can)
    f.dice:Show() f.coin:Show() f.boost:Hide()
    f.coin:ClearAllPoints()
    f.coin:SetPoint("TOP", f.dice, "BOTTOM", -2, 2)
    f.name:SetWidth(98)
    f.dice.label:SetText(copy.state == "open" and LR.Gdkp.gold(a1) or "")
    f.coin.label:SetText(copy.state == "open" and LR.Gdkp.gold(a2) or "")
    f.dice.tipTitle, f.coin.tipTitle = "Bid " .. LR.Gdkp.gold(a1), "Bid " .. LR.Gdkp.gold(a2)
    local word = copy.strict and "bid " or ""
    f.dice.tip = ("Types \"%s%d\" in raid chat: the least that beats the highest bid."):format(word, a1)
    f.coin.tip = ("Types \"%s%d\" in raid chat. Any other amount: type it yourself."):format(word, a2)
    f.status:SetText(UI.rollStatus(copy))
    return
  end
  f.dice.amount, f.coin.amount = nil, nil
  local dice, coin, boost = buttonsFor(copy)
  local opts = R.options(copy, me())
  f.dice.kind, f.coin.kind, f.boost.kind = dice or nil, coin or nil, boost or nil
  setButton(f.dice, dice ~= false)
  setButton(f.coin, coin ~= false)
  setButton(f.boost, boost ~= false)
  -- the green dice: only for someone who has points, while the roll is open to everyone
  local lo, hi = R.boostRange(copy, me())
  local boosted = copy.mode == "OPEN" and lo ~= nil
  f.boost:SetShown(boosted)
  f.name:SetWidth(boosted and 86 or 98)
  if boosted then
    f.boost.label:SetText("+" .. (lo - 1))
    f.boost.tipTitle = "Boosted roll"
    f.boost.tip = ("/roll %d %d: main spec, with your %d guild points added. If you win, the points are spent."):format(lo, hi, lo - 1)
  end
  f.coin:SetShown(copy.mode == "OPEN" or (copy.mode == "TIE" and copy.tie == "OS"))
  if copy.mode == "TIE" and copy.tie == "OS" then
    f.dice:Hide()
    f.coin:ClearAllPoints()
    f.coin:SetPoint("TOPRIGHT", -37, -14)
  else
    f.dice:Show()
    f.coin:ClearAllPoints()
    f.coin:SetPoint("TOP", f.dice, "BOTTOM", -2, 2)
  end
  local srMine = copy.mode == "SR" and #opts > 0
  -- (beside a green dice there's no room for the label: the line underneath says which is which)
  f.dice.label:SetText(boosted and "" or srMine and "SR" or copy.mode == "SR" and "" or copy.mode == "TIE" and R.LABEL[copy.tie] or "MS")
  f.coin.label:SetText("OS")
  f.dice.tipTitle = srMine and "Roll for your reserve" or "Main spec"
  f.coin.tipTitle = "Off spec"
  f.coin.tip = "/roll 99. Main spec rolls win over off spec."
  if copy.mode == "SR" and not srMine then
    f.dice.tipTitle = "Soft reserved"
    f.dice.tip = "Only " .. R.names(copy.who, 4) .. " roll for this."
  elseif copy.mode == "TIE" then
    f.dice.tipTitle = "Roll again"
    f.dice.tip = "/roll, for the tie."
  elseif copy.mode == "PR" then
    f.dice.tipTitle = "Priority"
    f.dice.tip = "Only " .. R.names(copy.who, 4) .. ", who share the top priority, roll for this."
  else
    f.dice.tip = "/roll" .. (srMine and ": only players who reserved it roll." or " (1-100).")
  end
  if copy.rolled[R.key(me())] then f.dice.tip = "You've rolled." f.coin.tip = "You've rolled." f.boost.tip = "You've rolled." end
  f.status:SetText(UI.rollStatus(copy))
end

--- the timer bar and the seconds left (every frame)
function UI.rollTick(f)
  local copy = f.copy
  if not copy then return end
  local t = GetTime()
  if copy.state == "open" then
    local left = math.max(0, (copy.ends or t) - t)
    local frac = copy.secs > 0 and math.min(1, left / copy.secs) or 0
    f.bar.fill:SetWidth(math.max(1, BAR * frac))
    f.bar.fill:SetVertexColor(1, left <= 5 and 0.35 or 1, 0)
    f.secs:SetText(math.ceil(left) .. " sec")
  else
    f.bar.fill:SetWidth(BAR)
    f.bar.fill:SetVertexColor(0.45, 0.45, 0.45)
    f.secs:SetText("")
    if copy.endedAt and t - copy.endedAt > HIDE_AFTER and f:IsShown() then copy.closedByMe = true UI.rollWindows() end
  end
end

--- shift-click on a button: remember it as my rule for the item (Core/AutoRoll.lua)
function UI.alwaysDo(copy, action)
  LR.AutoRoll.set(copy.id, action)
  LR.print(("from now on, LootRuler will %s on %s for you. (Settings tab, Auto-roll, to change it.)"):format(
    action == "pass" and "pass" or ("roll " .. (action == "OS" and "off spec" or "main spec")), copy.link))
end

---------------------------------------------------------------------- which windows are up
local function wanted(copy)
  if copy.hidden or copy.closedByMe or copy.state == "cancelled" then return false end
  if not LR.db.settings.rollWindow then return false end
  if LR.db.settings.rollOnlyMine and #R.options(copy, me()) == 0 then return false end
  return true
end

--- where roll windows go (the top of the first one): the player can drag it
function UI.rollAnchor()
  if not anchor then
    anchor = CreateFrame("Frame", "LootRulerRollAnchor", UIParent)
    anchor:SetSize(W, 1)
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    local pt = LR.db.ui.rollPoint
    if pt then anchor:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else anchor:SetPoint("TOP", UIParent, "CENTER", 0, -120) end
  end
  return anchor
end

--- shows a window for every roll that wants one (newest last), up to four
function UI.rollWindows()
  UI.rollAnchor()
  local show = {}
  for _, k in ipairs(LR.Rolls.order) do
    local copy = LR.Rolls.seen[k]
    if copy and wanted(copy) then show[#show + 1] = copy end
  end
  while #show > MAX do table.remove(show, 1) end
  for i = 1, math.max(#show, #frames) do
    local copy = show[i]
    if copy then
      frames[i] = frames[i] or makeFrame(i)
      local f = frames[i]
      f:ClearAllPoints()
      f:SetPoint("TOP", anchor, "TOP", 0, -(i - 1) * (H + 4))
      fill(f, copy)
      f:Show()
      UI.rollTick(f)
    elseif frames[i] then
      frames[i].copy = nil
      frames[i]:Hide()
    end
  end
  if UI.reserveStrip then UI.reserveStrip() end      -- (the strip goes with its window)
end

--- roll windows (and the loot master window) back where they start
function UI.resetPositions()
  if anchor then
    anchor:ClearAllPoints()
    anchor:SetPoint("TOP", UIParent, "CENTER", 0, -120)
  end
  if UI.masterDraw then UI.masterDraw() end
end

--- a roll started or changed (Core/Rolls.lua)
function UI.rollWindow(copy)
  local fresh = not copy.shownOnce
  copy.shownOnce = true
  if fresh and wanted(copy) then PlaySound(SOUNDKIT.RAID_WARNING or 8959, "Master") end
  UI.rollWindows()
end
function UI.rollEnded(copy) UI.rollWindows() end
function UI.rollFrames() return frames end

LR.onChange(function(what)
  if what == "rolls" and LR.db then UI.rollWindows() end
end)

-- made-up players for pretend rolls (the Test tab), with their classes
UI.PRETEND = { { "Arthas", "PALADIN" }, { "Jaina", "MAGE" }, { "Thrall", "SHAMAN" }, { "Sylvanas", "HUNTER" }, { "Øyvind", "WARRIOR" },
  { "Valeera", "ROGUE" }, { "Malfurion", "DRUID" }, { "Anduin", "PRIEST" }, { "Kael", "WARLOCK" }, { "Tyrande", "PRIEST" },
  { "Muradin", "WARRIOR" }, { "Alleria", "HUNTER" } }
--- the first n made-up players: who (names, with reserves), and their classes
function UI.pretendPlayers(n)
  local who, classes = {}, {}
  for i = 1, math.min(n or 0, #UI.PRETEND) do
    local name = UI.PRETEND[i][1] .. "-" .. U.realm()
    who[#who + 1] = { name, 1 }
    classes[name] = UI.PRETEND[i][2]
  end
  return who, classes
end
--- the item pretend rolls are for: the first of the session's raid, else Dragonspine Trophy
function UI.pretendItem()
  local s = LR.current()
  local raid = s and LR.raidOf(s)
  return raid and raid.order and raid.order[1] or 28830
end

--- a pretend roll, only on this screen, to see the window (and move it): /lr test, and the Test tab.
--- opts: { mode = "OPEN" / "SR", reservers = how many made-up players reserved it, mine = I reserved it too, secs }
function UI.testRoll(opts)
  opts = opts or {}
  local id = UI.pretendItem()
  local k = "test:" .. GetTime()
  local who, classes = {}, nil
  if opts.mode == "SR" then
    who, classes = UI.pretendPlayers(opts.reservers or 3)
    if opts.mine then table.insert(who, 1, { U.me(), 1 }) end
  end
  local copy = R.new(k, id, { mode = opts.mode or "OPEN", who = who })
  copy.by = U.me()
  copy.link = LR.itemLink(id)
  copy.classes = classes
  local secs = opts.secs or 20
  copy.secs, copy.ends, copy.state, copy.test = secs, GetTime() + secs, "open", true
  LR.Rolls.seen[k] = copy
  table.insert(LR.Rolls.order, k)
  if not opts.quiet then LR.print("a pretend roll window, only on your screen. Drag it to where you'd like roll windows to be.") end
  UI.rollWindow(copy)
  LR.changed("rolls")
  C_Timer.After(secs, function()
    if copy.state == "open" then copy.state = "closed" copy.endedAt = GetTime() UI.rollWindows() LR.changed("rolls") end
  end)
  return copy
end

--- a pretend Gargul roll: the strip shows, as it would for Gargul's line in raid chat (nothing is said in chat)
function UI.testGargul(reservers, secs)
  local id = UI.pretendItem()
  local roll = LR.Gargul.startRoll(id, LR.itemLink(id), secs or 20, GetTime())
  roll.who, roll.classes, roll.test = UI.pretendPlayers(reservers or 3)
  roll.test = true
  LR.changed("gargul")
  C_Timer.After(secs or 20, function() if LR.Gargul.roll == roll then LR.Gargul.endRoll() end end)
  return roll
end
