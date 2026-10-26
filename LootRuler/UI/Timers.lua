-- Trade timers: a small window for whoever holds the raid's loot, with a bar for each item in their bags that is
-- still to be rolled out or traded, and how much of the game's 2 hours to trade it is left. Click an item to roll it
-- out (once it's won: to open a trade with the winner); right-click to give it without a roll. It shows while there
-- is something to trade, can be dragged, and its x hides it until another item comes in. Settings: tradeTimers.
local _, LR = ...
local U, K = LR.U, LR.K
local UI = LR.UI
local Drops, Rolls = LR.Drops, LR.Rolls

local W, ROW, MAX = 250, 24, 8
local REFRESH = 15            -- seconds between redraws while it's up (the bars move slowly)
local win
local rows = {}
local dismissed = {}          -- drop key -> true: what was there when the x was clicked
local ticking = false

local WHY = {
  busy = "Finish the trade that's open first.",
  combat = "You're in combat: try again when it's over.",
  away = "%s isn't in the group.",
  far = "%s is too far away to trade. Ask them to come over.",
}

local function click(row, button)
  local x = row.x
  if not x then return end
  local link = LR.itemLink(x.d.i)
  if UI.modifiedClick(link) then return end
  if x.state == "held" and button == "RightButton" then
    UI.giveSheet({ id = x.d.i, link = link, drop = x.d.k })
  elseif x.state == "held" then
    local roll, why = Rolls.start(x.d.i, { drop = x.d.k, link = link })
    if not roll then UI.toast(why) return end
    UI.masterDraw()
  else
    local ok, why = Drops.openTrade(x.to)
    if not ok then UI.toast((WHY[why] or why):format(U.short(x.to))) end
  end
end

local function makeRow(i)
  local r = CreateFrame("Button", nil, win)
  r:SetSize(W - 16, ROW - 2)
  r:SetPoint("TOPLEFT", 8, -24 - (i - 1) * ROW)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(ROW - 2, ROW - 2)
  r.icon:SetPoint("LEFT")
  r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.bg:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 3, 0)
  r.bg:SetPoint("BOTTOMRIGHT")
  r.bg:SetColorTexture(0, 0, 0, 0.6)
  r.fill = r:CreateTexture(nil, "BORDER")
  r.fill:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
  r.fill:SetPoint("TOPLEFT", r.bg, "TOPLEFT")
  r.fill:SetPoint("BOTTOMLEFT", r.bg, "BOTTOMLEFT")
  r.name = K.fs(r, "GameFontHighlightSmall")
  r.name:SetPoint("LEFT", r.bg, "LEFT", 4, 0)
  r.name:SetPoint("RIGHT", r.bg, "RIGHT", -52, 0)
  r.name:SetJustifyV("MIDDLE")
  r.name:SetWordWrap(false)
  r.time = K.fs(r, "GameFontHighlightSmall")
  r.time:SetPoint("RIGHT", r.bg, "RIGHT", -4, 0)
  r.time:SetJustifyH("RIGHT")
  r.time:SetJustifyV("MIDDLE")
  r:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
  r:SetScript("OnClick", click)
  r:SetScript("OnEnter", function(self)
    local x = self.x
    if not x then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetHyperlink(LR.itemLink(x.d.i))
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("%s left to trade it."):format(UI.duration(x.left)), 1, 0.82, 0)
    if x.state == "held" then
      GameTooltip:AddLine("Click: roll it out. Right-click: give it to someone without a roll.", 0.7, 0.7, 0.7, true)
    else
      GameTooltip:AddLine(("Won by %s. Click: open a trade with them (LootRuler puts it in)."):format(U.short(x.to)), 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
  return r
end

local function build()
  win = CreateFrame("Frame", "LootRulerTimers", UIParent, "BackdropTemplate")
  win:SetSize(W, 60)
  win:SetFrameStrata("MEDIUM")
  win:SetBackdrop(K.FLAT)
  win:SetBackdropColor(0.05, 0.04, 0.03, 0.88)
  win:SetBackdropBorderColor(0.72, 0.54, 0.23, 0.8)
  win:SetClampedToScreen(true)
  win:EnableMouse(true)
  win:SetMovable(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", function(self) self:StartMoving() end)
  win:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    LR.db.ui.timersPoint = { point, relPoint, x, y }
  end)
  local pt = LR.db.ui.timersPoint
  if type(pt) == "table" and type(pt[1]) == "string" and type(pt[2]) == "string" and tonumber(pt[3]) and tonumber(pt[4]) then
    win:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
  else
    win:SetPoint("RIGHT", UIParent, "RIGHT", -40, 120)
  end
  win.title = K.fs(win, "GameFontNormalSmall")
  win.title:SetPoint("TOPLEFT", 8, -7)
  win.close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
  win.close:SetSize(22, 22)
  win.close:SetPoint("TOPRIGHT", 1, 1)
  win.close:SetScript("OnClick", function()
    for _, x in ipairs(Drops.holding()) do dismissed[x.d.k] = true end
    win:Hide()
  end)
  -- the list, in raid chat
  win.post = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  win.post:SetSize(48, 18)
  win.post:SetPoint("RIGHT", win.close, "LEFT", -2, 0)
  win.post:SetText("Post")
  win.post:SetScript("OnClick", function()
    if Drops.postHolding() then UI.toast("Posted in " .. (IsInRaid() and "raid" or "party") .. " chat.") end
  end)
  K.tooltipOn(win.post, function(tt)
    tt:SetText("Post the list", 1, 1, 1)
    tt:AddLine("One line in raid chat: each item still to roll out or trade, with the time left.", 1, 0.82, 0, true)
  end)
  win.more = K.fs(win, "GameFontDisableSmall")
  win:Hide()
end

local function colour(left)        -- (dimmed, so the item's name reads on top)
  if left <= 15 * 60 then return 0.9, 0.2, 0.15, 0.6 end
  if left <= 30 * 60 then return 0.95, 0.7, 0.1, 0.55 end
  return 0.2, 0.7, 0.25, 0.45
end

--- shows the window with what I'm holding now (or hides it when there's nothing, or it's switched off)
function UI.tradeTimers()
  if not LR.db then return end
  local list = LR.db.settings.tradeTimers and Drops.holding() or {}
  local fresh = false
  for _, x in ipairs(list) do if not dismissed[x.d.k] then fresh = true end end
  if #list == 0 or not fresh then
    if win then win:Hide() end
    if #list == 0 then dismissed = {} end
    return
  end
  if not win then build() end
  win.title:SetText(("To trade (%d)"):format(#list))
  local bar = W - 16 - ROW - 1
  for i = 1, MAX do
    local x = list[i]
    local r = rows[i] or (x and makeRow(i))
    if r then
      r.x = x
      if x then
        r.icon:SetTexture(LR.itemIcon(x.d.i))
        r.fill:SetWidth(math.max(1, bar * math.min(1, x.left / Drops.TRADE_SECONDS)))
        r.fill:SetVertexColor(colour(x.left))
        local name = LR.coloredName(x.d.i)
        r.name:SetText(x.state == "toTrade" and (name .. " |cffffffff> " .. U.short(x.to) .. "|r") or name)
        local h, m = math.floor(x.left / 3600), math.floor(x.left % 3600 / 60)
        r.time:SetText(h > 0 and ("%dh %02dm"):format(h, m) or (m > 0 and (m .. "m") or "<1m"))
        r:Show()
      else
        r:Hide()
      end
    end
  end
  local shown = math.min(#list, MAX)
  win.more:ClearAllPoints()
  win.more:SetPoint("TOPLEFT", 8, -24 - shown * ROW)
  win.more:SetText(#list > MAX and ("+%d more on the Loot tab"):format(#list - MAX) or "")
  win:SetHeight(28 + shown * ROW + (#list > MAX and 14 or 0))
  win:Show()
  -- the bars and times move on while it's up
  if not ticking then
    ticking = true
    C_Timer.After(REFRESH, function()
      ticking = false
      if win:IsShown() then UI.tradeTimers() end
    end)
  end
end

LR.onChange(function(what)
  if what == "session" or what == "loot" or what == "roll" then UI.tradeTimers() end
end)
