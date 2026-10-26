-- The batch window: several GDKP auctions at once (Core/Batch.lua). Every item with its number, the highest bid and
-- a button to bid the least that counts (it types "#2 300" in raid chat, like anyone without the addon; shift-click
-- for a max bid), and the time left. The loot master's has "+10 sec", "Close now" and "Call off". Starting one:
-- UI.batchSheet (from the loot panel, the loot master window or /lr batch).
local _, LR = ...
local U, K, R = LR.U, LR.K, LR.Roll
local UI = LR.UI
local B = LR.Batch
local G = LR.Gdkp

local W = 340
local win

local function build()
  win = CreateFrame("Frame", "LootRulerBatchFrame", UIParent, "BackdropTemplate")
  win:SetSize(W, 200)
  win:SetBackdrop(K.ROCK)
  win:SetFrameStrata("HIGH")
  win:SetToplevel(true)
  win:SetClampedToScreen(true)
  win:SetMovable(true)
  win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", function(self) self:StartMoving() end)
  win:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    LR.db.ui.batchPoint = { point, relPoint, x, y }
  end)
  win.close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
  win.close:SetPoint("TOPRIGHT", -4, -4)
  win.close:SetScript("OnClick", function() win.hiddenFor = win.k win:Hide() end)
  K.tooltipOn(win.close, function(tt) tt:SetText("Hide (the auction goes on: /lr batch brings it back)", 1, 1, 1, 1, true) end)
  win.title = K.fs(win, "GameFontNormal")
  win.title:SetPoint("TOPLEFT", 18, -16)
  win.bar = CreateFrame("Frame", nil, win, "BackdropTemplate")
  win.bar:SetSize(W - 100, 12)
  win.bar:SetPoint("TOPLEFT", 18, -38)
  win.bar:SetBackdrop(K.FLAT)
  win.bar:SetBackdropColor(0, 0, 0, 1)
  win.bar:SetBackdropBorderColor(0.42, 0.33, 0.19, 1)
  win.bar.fill = win.bar:CreateTexture(nil, "ARTWORK")
  win.bar.fill:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
  win.bar.fill:SetPoint("TOPLEFT", 1, -1)
  win.bar.fill:SetPoint("BOTTOMLEFT", 1, 1)
  win.secs = K.fs(win, "GameFontHighlightSmall")
  win.secs:SetPoint("LEFT", win.bar, "RIGHT", 8, 0)
  win.secs:SetJustifyV("MIDDLE")
  win.body = CreateFrame("Frame", nil, win)
  win.body:SetPoint("TOPLEFT", 16, -58)
  win.body:SetSize(W - 32, 10)
  -- (the timer bar only: the rest is drawn when something changes)
  win:SetScript("OnUpdate", function() UI.batchTick() end)
  win:Hide()
end

--- the copy the window shows: the one on now, else the last one, for a minute after it ends
local function shown()
  local open = B.open()
  if open then return open end
  local last = B.order[#B.order] and B.seen[B.order[#B.order]]
  if last and last.endedAt and GetTime() - last.endedAt < 60 then return last end
end

function UI.batchTick()
  local copy = win and win:IsShown() and win.copy
  if not copy then return end
  local full = W - 102
  if copy.state == "open" then
    local left = math.max(0, (copy.ends or 0) - GetTime())
    win.bar.fill:SetWidth(math.max(1, full * math.min(1, left / math.max(1, copy.secs or 60))))
    win.bar.fill:SetVertexColor(1, left <= 5 and 0.35 or 1, 0)
    local whole = math.ceil(left)
    if win.shownSecs ~= whole then win.shownSecs = whole win.secs:SetText(whole .. " s left") end
  else
    win.bar.fill:SetWidth(full)
    win.bar.fill:SetVertexColor(0.45, 0.45, 0.45)
    win.shownSecs = nil
    win.secs:SetText(copy.state == "cancelled" and "Called off" or "Over")
  end
end

--- one item's line: who's highest, and mine
local function itemLine(copy, item, mine)
  local top = item.top
  if copy.state ~= "open" then
    if copy.state == "cancelled" then return "Called off" end
    return top and ("|cff1eff00Sold to %s for %s|r"):format(U.short(top.p), G.gold(top.n)) or "Not sold: nobody bid"
  end
  local text = top and ("Highest: %s, %s"):format(U.short(top.p), G.gold(top.n)) or ("No bids yet, from %s"):format(G.gold(item.min or 0))
  if top and U.samePlayer(top.p, U.me()) then text = "|cff1eff00You're highest: " .. G.gold(top.n) .. "|r" end
  if item.myMax then text = text .. (" |cff9d9d9d(your max %s)|r"):format(G.gold(item.myMax)) end
  return text
end

function UI.batchDraw()
  local copy = shown()
  if not copy then if win then win:Hide() end return end
  local mine = U.samePlayer(copy.by, U.me())
  -- raiders who don't want roll windows bid by chat (Settings: rollWindow); the loot master always gets theirs
  if not mine and not LR.db.settings.rollWindow then return end
  if not win then build() end
  if win.hiddenFor == copy.k then return end
  if win.k ~= copy.k then win.k, win.hiddenFor = copy.k, nil end
  win.copy = copy
  K.release("batch")
  win:ClearAllPoints()
  local pt = LR.db.ui.batchPoint
  if pt then win:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 540, -120) end
  local s = LR.Rolls.session()
  local by = (s and s.br and s.br.n) or (not mine and U.short(copy.by)) or nil
  win.title:SetText(("Auction: %d items%s"):format(#copy.items, by and (" by " .. by) or ""))
  local f = K.flow("batch", win.body, 0, 0, W - 32)
  for _, item in ipairs(copy.items) do
    local b = K.get(f.owner, "item", f.parent)
    local amount = R.nextBid(item)
    local canBid = copy.state == "open" and not (item.top and U.samePlayer(item.top.p, U.me()))
    K.setItem(b, f.width, LR.itemIcon(item.id), ("|cffffd100#%d|r %s"):format(item.n, LR.coloredName(item.id)), itemLine(copy, item, mine), "",
      copy.state == "open" and { text = G.gold(amount), width = 62, disabled = not canBid, tip = "Bid " .. G.gold(amount) .. " (shift-click: a max bid)", click = function()
        if IsShiftKeyDown() then
          UI.show()
          UI.goldSheet(("Max bid on #%d %s"):format(item.n, LR.itemName(item.id)), "LootRuler bids for you, as little as it takes to keep you on top, up to this. Nobody else sees it.",
            item.myMax or amount, function(g)
              local ok, why = B.myMax(copy, item.n, g)
              if not ok then UI.toast(why) end
            end)
          return
        end
        B.bid(copy, item.n, amount)
      end } or nil)
    b:SetScript("OnEnter", function(self) UI.itemTooltip(self, LR.Rolls.session(), item.id) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:place(b, 36)
    f:gap(2)
  end
  if copy.state == "open" then
    f:note(("Type the number and your bid in raid chat: \"%s\"."):format(B.bidText(1, copy.items[1].min or 0, copy.strict)))
    if mine then
      f:buttons({
        { label = "+10 sec", width = 70, click = function() B.extend(10) end },
        { label = "Close now", click = function() B.close() end },
        { label = "Call off", click = function() UI.confirm("Call off the auction", "Nothing is sold. The items stay where they are.", "Call it off", function() B.cancel() end) end },
      }, "left")
    end
  end
  win:SetHeight(58 + f.y + 14)
  win:Show()
  UI.batchTick()
end

--- /lr batch: the auction on now, again
function UI.showBatch()
  if win then win.hiddenFor = nil end
  if not shown() then LR.print("No auction of several items is on.") return end
  UI.batchDraw()
end

--- putting items up together: the loot window's (or the ones I hold), each ticked, and how long
local picked, pickSecs = {}, nil
function UI.batchSheet()
  local list = B.candidates()
  picked = {}
  for i = 1, math.min(#list, B.MAX) do picked[i] = true end
  pickSecs = LR.db.settings.batchSeconds or B.SECONDS
  UI.show()
  UI.openSheet("Auction several at once", function(f, h)
    f:note(("Up to %d items, all at once, ending together. Raiders bid by typing the item's number and the gold in raid chat (\"#2 300\"), or with the auction window. A bid at the last moment gives everyone a few more seconds."):format(B.MAX))
    if #list < 2 then f:note("Open a corpse with master loot on, or hold at least two items, to auction them together.", K.GOLD) return end
    local n = 0
    for i, it in ipairs(list) do
      local on = picked[i]
      if on then n = n + 1 end
      f:chips({ { label = (on and "[x] " or "[  ] ") .. LR.itemName(it.id), on = on, width = f.width,
        click = function() picked[i] = not on h.redraw(true) end } }, { gap = 2 })
    end
    local secs = { { plain = true, label = "Time:" } }
    for _, v in ipairs({ 30, 45, 60, 90, 120 }) do
      secs[#secs + 1] = { label = v .. " s", on = pickSecs == v, click = function() pickSecs = v LR.db.settings.batchSeconds = v h.redraw(true) end }
    end
    f:chips(secs, { gap = 2 })
    f:gap(6)
    f:buttons({
      { label = "Cancel", click = function() h.close() end },
      { label = ("Auction %d together"):format(n), disabled = n < 2 or n > B.MAX, click = function()
        local items = {}
        for i, it in ipairs(list) do if picked[i] then items[#items + 1] = it end end
        local ok, why = B.start(items, pickSecs)
        if not ok then UI.toast(why) return end
        h.close()
        UI.win:Hide()
      end },
    })
    if n > B.MAX then f:note(("At most %d at once."):format(B.MAX), K.RED) end
  end, { full = true })
end

LR.onChange(function(what)
  if what == "batch" and LR.db then UI.batchDraw() end
end)
