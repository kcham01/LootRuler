-- The window: the open session along the top, the screen in the middle, tabs along the bottom, and pop-up
-- panels ("sheets") over it. Also the minimap button and /lr.
local ADDON, LR = ...
local U, K, S = LR.U, LR.K, LR.Session

local floor, max, min = math.floor, math.max, math.min

local WIDTH, HEIGHT = 460, 640
local TOP_H, TAB_H, PAD = 54, 30, 14
LR.CONTENT_W = WIDTH - 2 * PAD - 22

local UI = { tab = "reserve", usable = true, view = "item", q = "" }
LR.UI = UI

local win, top, view, tabsBar, toastFrame
local TABS = { { "reserve", "Reserve" }, { "reserves", "Reserves" }, { "loot", "Loot" }, { "session", "Session" }, { "guild", "Guild" }, { "settings", "Settings" } }

---------------------------------------------------------------------- the window
local function build()
  win = CreateFrame("Frame", "LootRulerFrame", UIParent, "BackdropTemplate")
  win:SetSize(WIDTH, HEIGHT)
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
    LR.db.ui.point = { point, relPoint, x, y }
  end)
  local pt = LR.db.ui.point
  if pt then win:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else win:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
  win:Hide()
  win:SetScript("OnShow", function() PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) UI.render() end)
  win:SetScript("OnHide", function() UI.closeAll() PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE) end)
  -- Escape closes the top panel first, then the window (see TBCrushCalc: a hidden "catcher" frame stands in
  -- for the window in the game's list of frames Escape closes while a panel is open)
  local catcher = CreateFrame("Frame", "LootRulerEscapeCatcher", UIParent)
  catcher:Hide()
  catcher:SetScript("OnHide", function()
    if UI.closingAll then return end
    UI.closeTop()
  end)
  UI.catcher = catcher

  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)
  close:SetScript("OnClick", function() win:Hide() end)

  top = CreateFrame("Frame", nil, win)
  top:SetPoint("TOPLEFT", 12, -12)
  top:SetPoint("TOPRIGHT", -34, -12)
  top:SetHeight(TOP_H - 8)
  top.icon = top:CreateTexture(nil, "ARTWORK")
  top.icon:SetSize(38, 38)
  top.icon:SetPoint("LEFT", 4, 0)
  top.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  top.name = K.fs(top, "GameFontNormalLarge")
  top.name:SetPoint("TOPLEFT", 50, -4)
  top.name:SetPoint("RIGHT", top, "RIGHT", -96, 0)
  top.name:SetWordWrap(false)
  top.sub = K.fs(top, "GameFontHighlightSmall")
  top.sub:SetPoint("TOPLEFT", 50, -24)
  top.sub:SetPoint("RIGHT", top, "RIGHT", -96, 0)
  top.sub:SetWordWrap(false)
  top.count = CreateFrame("Button", nil, top, "BackdropTemplate")
  top.count:SetBackdrop(K.INSET)
  top.count:SetSize(88, 38)
  top.count:SetPoint("RIGHT", 0, 0)
  top.count.num = K.fs(top.count, "GameFontHighlightLarge")
  top.count.num:SetJustifyH("CENTER")
  top.count.num:SetPoint("TOP", 0, -4)
  top.count.word = K.fs(top.count, "GameFontNormalSmall")
  top.count.word:SetJustifyH("CENTER")
  top.count.word:SetPoint("TOP", 0, -23)
  top.count:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  top.count:SetScript("OnClick", function() UI.go("reserve") end)

  view = K.scroller(win)
  view:SetPoint("TOPLEFT", PAD, -(TOP_H + 8))
  view:SetPoint("BOTTOMRIGHT", -PAD, TAB_H + 16)

  tabsBar = CreateFrame("Frame", nil, win)
  tabsBar:SetPoint("BOTTOMLEFT", 12, 12)
  tabsBar:SetPoint("BOTTOMRIGHT", -12, 12)
  tabsBar:SetHeight(TAB_H)
  tabsBar.buttons = {}
  local tw = (WIDTH - 24 - (#TABS - 1) * 4) / #TABS
  for i, t in ipairs(TABS) do
    local b = CreateFrame("Button", nil, tabsBar, "BackdropTemplate")
    b:SetBackdrop(K.INSET)
    b:SetSize(tw, TAB_H)
    b:SetPoint("LEFT", (i - 1) * (tw + 4), 0)
    b.text = K.fs(b, "GameFontNormal")
    b.text:SetJustifyH("CENTER")
    b.text:SetJustifyV("MIDDLE")
    b.text:SetAllPoints()
    b.text:SetText(t[2])
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", function() UI.go(t[1]) end)
    b.id = t[1]
    tabsBar.buttons[i] = b
  end

  toastFrame = CreateFrame("Frame", nil, win, "BackdropTemplate")
  toastFrame:SetBackdrop(K.INSET)
  toastFrame:SetBackdropColor(0, 0, 0, 0.92)
  toastFrame:SetBackdropBorderColor(1, 0.82, 0, 1)
  toastFrame:SetFrameStrata("DIALOG")
  toastFrame:SetPoint("BOTTOM", win, "BOTTOM", 0, TAB_H + 26)
  toastFrame.text = K.fs(toastFrame, "GameFontHighlight")
  toastFrame.text:SetJustifyH("CENTER")
  toastFrame.text:SetPoint("CENTER")
  toastFrame:Hide()

  tinsert(UISpecialFrames, "LootRulerFrame")
  UI.win = win
end

local function setEscape(panelsOpen)
  local function drop(name) for i = #UISpecialFrames, 1, -1 do if UISpecialFrames[i] == name then table.remove(UISpecialFrames, i) end end end
  drop("LootRulerFrame") drop("LootRulerEscapeCatcher")
  tinsert(UISpecialFrames, panelsOpen and "LootRulerEscapeCatcher" or "LootRulerFrame")
  if panelsOpen then UI.catcher:Show() end
end

local toastSeq = 0
function UI.toast(text)
  if not win or not win:IsShown() then return end
  toastSeq = toastSeq + 1
  local mine = toastSeq
  toastFrame.text:SetWidth(0)
  toastFrame.text:SetText(text)
  local w = min(WIDTH - 40, toastFrame.text:GetStringWidth() + 28)
  toastFrame.text:SetWidth(w - 20)
  toastFrame:SetSize(w, toastFrame.text:GetStringHeight() + 16)
  toastFrame:Show()
  C_Timer.After(2.2, function() if toastSeq == mine then toastFrame:Hide() end end)
end

--- explains a refusal from the session rules
function UI.refused(why) UI.toast(S.WHY[why] or tostring(why)) end

---------------------------------------------------------------------- drawing
local lastTab, lastId

local function drawTop(s)
  if not s then
    top.icon:SetTexture(LR.LOGO)
    top.icon:SetTexCoord(0, 1, 0, 1)
    top.name:SetText("LootRuler")
    top.sub:SetText("Soft reserves inside the game")
    top.count:Hide()
    return
  end
  local raid = LR.raidOf(s)
  top.icon:SetTexture(LR.raidIcon(s.raid))
  top.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  top.name:SetText(raid.name)
  -- GDKP, or priority lists only: there are no reserves, so the box shows the pot (or nothing)
  if s.gdkp and s.gk then
    top.sub:SetText((LR.isLeader(s) and "Your GDKP" or ("GDKP by " .. U.short(s.leader))) .. " - bids from " .. LR.Gdkp.gold(s.gk.min))
    top.count:Show()
    top.count:SetBackdropColor(0.1, 0.08, 0.06, 0.9) top.count:SetBackdropBorderColor(0.42, 0.33, 0.19, 1)
    top.count.num:SetText(LR.Gdkp.gold(LR.Gdkp.pot(s)))
    top.count.word:SetText("POT") top.count.word:SetTextColor(1, 0.82, 0)
    return
  end
  if s.prio == "only" then
    top.sub:SetText((LR.isLeader(s) and "Your session" or ("By " .. U.short(s.leader))) .. " - the guild's priority lists")
    top.count:Hide()
    return
  end
  local bits = { (LR.isLeader(s) and "Your session" or ("By " .. U.short(s.leader))), U.plural(s.sr, "reserve") .. " each" }
  local hr = #U.keys(s.hr)
  if hr > 0 then bits[#bits + 1] = hr .. " hard reserved" end
  if s.locked then bits[#bits + 1] = "|cffff5a4alocked|r" end
  top.sub:SetText(table.concat(bits, " - "))
  top.count:Show()
  local used = #LR.myPicks(s)
  local limit = S.limit(s, U.me())
  top.count.num:SetText(used .. " / " .. limit)
  local done = used >= limit
  if LR.pending(s) then
    top.count:SetBackdropColor(0.25, 0.2, 0.03, 0.9) top.count:SetBackdropBorderColor(1, 0.82, 0, 1)
    top.count.word:SetText("NOT SENT YET") top.count.word:SetTextColor(1, 0.82, 0)
  elseif done then
    top.count:SetBackdropColor(0.05, 0.2, 0.03, 0.9) top.count:SetBackdropBorderColor(0.12, 0.7, 0.1, 1)
    top.count.word:SetText("RESERVED") top.count.word:SetTextColor(0.12, 1, 0)
  else
    top.count:SetBackdropColor(0.1, 0.08, 0.06, 0.9) top.count:SetBackdropBorderColor(0.42, 0.33, 0.19, 1)
    top.count.word:SetText((limit - used) .. " LEFT")
    top.count.word:SetTextColor(1, 0.82, 0)
  end
end

function UI.render()
  if not win or not win:IsShown() then return end
  local s = LR.current()
  local keep = lastTab == UI.tab and lastId == (s and s.id)
  lastTab, lastId = UI.tab, s and s.id
  drawTop(s)
  -- the Guild tab is only there for guild members
  if UI.tab == "guild" and not IsInGuild() then UI.tab = "settings" end
  local shown = {}
  for _, b in ipairs(tabsBar.buttons) do
    b:SetShown(b.id ~= "guild" or IsInGuild())
    if b:IsShown() then shown[#shown + 1] = b end
  end
  local tw = (WIDTH - 24 - (#shown - 1) * 4) / #shown
  for i, b in ipairs(shown) do
    b:SetWidth(tw)
    b:ClearAllPoints()
    b:SetPoint("LEFT", (i - 1) * (tw + 4), 0)
  end
  for _, b in ipairs(tabsBar.buttons) do
    local on = b.id == UI.tab
    b:SetBackdropColor(on and 0.35 or 0.1, on and 0.27 or 0.08, on and 0.07 or 0.06, 1)
    b:SetBackdropBorderColor(on and 1 or 0.42, on and 0.82 or 0.33, on and 0 or 0.19, 1)
    b.text:SetTextColor(on and 1 or 0.8, on and 0.82 or 0.7, on and 0 or 0.5)
  end
  K.release("view")
  local flow = K.flow("view", view.child, 0, 4, LR.CONTENT_W)
  local screens = { reserve = UI.reserveView, reserves = UI.reservesView, loot = UI.lootView, session = UI.sessionView, guild = UI.guildView, settings = UI.settingsView }
  local ok, err = pcall(screens[UI.tab], flow, s)
  if not ok then
    flow:text("|cffff5a4aSomething went wrong drawing this screen:|r " .. tostring(err), { font = "GameFontHighlightSmall" })
    geterrorhandler()(err)
  end
  view:setContentHeight(flow.y + 8, keep)
  for _, e in ipairs(UI.openSheets()) do e.handle.redraw(true) end
end

-- redraws soon (item names arrive by the hundred when a raid's items load)
local renderSoon = false
function UI.renderSoon()
  if renderSoon then return end
  renderSoon = true
  C_Timer.After(0.2, function() renderSoon = false UI.render() end)
end
LR.onChange(function(what)
  -- rolls are the roll windows' business (UI/RollFrame.lua, UI/Master.lua), but the Loot tab says what's being rolled for
  if what == "roll" or what == "rolls" or what == "loot" then
    if UI.tab == "loot" and what ~= "roll" then UI.renderSoon() end
    return
  end
  if what == "items" or what == "book" then UI.renderSoon() else UI.render() end
  if LR.minimapUpdate then LR.minimapUpdate() end
end)

function UI.go(tab)
  UI.closeAll()
  UI.tab = tab
  LR.db.ui.tab = tab
  UI.render()
end

function UI.toggle()
  UI.start()
  if win:IsShown() then win:Hide() else win:Show() end
end
function UI.show(tab)
  UI.start()
  if tab then UI.tab = tab end
  win:Show()
  win:Raise()
  UI.render()
end

---------------------------------------------------------------------- sheets (pop-up panels)
local sheets, stack = {}, {}

local function makeSheet(depth)
  local s = CreateFrame("Frame", nil, win, "BackdropTemplate")
  s:SetBackdrop(K.ROCK)
  s:EnableMouse(true)
  s:SetFrameLevel(win:GetFrameLevel() + 30 + depth * 12)
  s.shade = CreateFrame("Frame", nil, win)
  s.shade:SetFrameLevel(s:GetFrameLevel() - 2)
  s.shade:SetPoint("TOPLEFT", 6, -6)
  s.shade:SetPoint("BOTTOMRIGHT", -6, 6)
  s.shade:EnableMouse(true)
  s.shade.tex = s.shade:CreateTexture(nil, "BACKGROUND")
  s.shade.tex:SetAllPoints()
  s.shade.tex:SetColorTexture(0, 0, 0, 0.55)
  s.shade:SetScript("OnMouseUp", function() UI.closeTop() end)
  s.title = K.fs(s, "GameFontNormalLarge")
  s.title:SetPoint("TOPLEFT", 18, -18)
  s.title:SetPoint("RIGHT", s, "RIGHT", -40, 0)
  s.title:SetWordWrap(false)
  s.close = CreateFrame("Button", nil, s, "UIPanelCloseButton")
  s.close:SetPoint("TOPRIGHT", -6, -6)
  s.close:SetScript("OnClick", function() UI.closeTop() end)
  s.line = s:CreateTexture(nil, "ARTWORK")
  s.line:SetColorTexture(0.72, 0.54, 0.23, 0.45)
  s.line:SetHeight(1)
  s.line:SetPoint("TOPLEFT", 14, -40)
  s.line:SetPoint("TOPRIGHT", -14, -40)
  s.scroll = K.scroller(s)
  s.scroll:SetPoint("TOPLEFT", 16, -46)
  s.scroll:SetPoint("BOTTOMRIGHT", -14, 14)
  s:Hide()
  s.shade:Hide()
  return s
end

--- opens a panel over the window. build(flow, handle) draws it (again after handle.redraw()).
--- opts.full: as tall as the window allows. Returns { close, redraw, frame }.
function UI.openSheet(title, buildFn, opts)
  opts = opts or {}
  local depth = #stack + 1
  sheets[depth] = sheets[depth] or makeSheet(depth)
  local s = sheets[depth]
  local owner = "sheet" .. depth
  local handle = { frame = s, owner = owner }
  local entry = { s = s, owner = owner, onClose = opts.onClose, handle = handle }
  table.insert(stack, entry)
  s.title:SetText(title)
  local maxH = HEIGHT - 70
  function handle.close()
    for i, e in ipairs(stack) do
      if e == entry then
        for j = #stack, i, -1 do
          local x = table.remove(stack, j)
          K.release(x.owner)
          x.s:Hide() x.s.shade:Hide()
          if x.onClose then x.onClose() end
        end
        break
      end
    end
    if #stack == 0 then
      UI.closingAll = true
      UI.catcher:Hide()
      UI.closingAll = false
      setEscape(false)
    end
  end
  function handle.redraw(keep)
    K.release(owner)
    local flow = K.flow(owner, s.scroll.child, 0, 2, WIDTH - 64)
    buildFn(flow, handle)
    local contentH = flow.y + 6
    local h = opts.full and maxH or min(maxH, contentH + 62)
    s:SetHeight(h)
    s.scroll:setContentHeight(contentH, keep)
  end
  s:ClearAllPoints()
  s:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 8, 8)
  s:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -8, 8)
  s.shade:Show()
  s:Show()
  handle.redraw()
  setEscape(true)
  return handle
end
function UI.openSheets() return stack end
function UI.topSheet() local e = stack[#stack] return e and e.s end
function UI.closeTop()
  local e = stack[#stack]
  if not e then return false end
  e.handle.close()
  return true
end
function UI.closeAll() while UI.closeTop() do end end

function UI.confirm(title, text, yes, onYes)
  UI.openSheet(title, function(f, h)
    f:text(text)
    f:gap(6)
    f:buttons({ { label = "Cancel", click = function() h.close() end }, { label = yes, click = function() h.close() onYes() end } })
  end)
end

--- a box with text to copy
function UI.copyBox(title, note, text)
  UI.openSheet(title, function(f)
    f:note(note)
    local e = K.get(f.owner, "edit", f.parent)
    f:place(e, 22, 6, f.width - 12)
    e:SetText(text)
    e:SetScript("OnTextChanged", function(self, user) if user then self:SetText(text) self:HighlightText() end end)
    e:SetFocus()
    e:HighlightText()
    f:gap(8)
  end)
end

---------------------------------------------------------------------- shared bits for the screens
-- each raid's picture: the icon of one of its best-known drops
LR.RAID_ITEM = {
  MoltenCore = 17204, Onyxia = 18423, BlackwingLair = 19364, ["Zul'Gurub"] = 19902, TheRuinsofAhnQiraj = 21220,
  TheTempleofAhnQiraj = 21134, WorldBosses = 17070,
  Karazhan = 30480, GruulsLair = 28830, MagtheridonsLair = 32385, SerpentshrineCavern = 30627, TempestKeep = 32458,
  HyjalSummit = 30908, BlackTemple = 32837, ZulAman = 33467, SunwellPlateau = 34334, WorldBossesBC = 30729,
}
function LR.raidIcon(key) return LR.RAID_ITEM[key] and LR.itemIcon(LR.RAID_ITEM[key]) or LR.LOGO end

--- the game's tooltip for an item, with who reserved it underneath (and where it drops)
function UI.itemTooltip(owner, s, id, raidKey)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  UI.ownTooltip = true                -- our own lines follow: the tooltip hook (UI/Highlight.lua) stays out
  GameTooltip:SetHyperlink("item:" .. id)
  UI.ownTooltip = false
  if not s and raidKey then
    local from = LR.dropsFrom(raidKey, id)
    if #from > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(LR.raid(raidKey).name .. ": " .. table.concat(from, ", "), 0.7, 0.7, 0.7, true)
    end
  end
  -- the guild's priority list for it (Guild tab)
  local book = IsInGuild() and LR.book()
  local plist = book and LR.Book.prio(book, id)
  if plist and #plist > 0 then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Priority list: " .. UI.prioLine(plist, 6), 0.12, 1, 0, true)
  end
  if s then
    local hr = s.hr[id]
    if hr then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Hard reserved" .. (hr.f ~= "" and (" for " .. hr.f) or "") .. (hr.n ~= "" and (": " .. hr.n) or ""), 1, 0.35, 0.3, true)
    end
    local who = S.byItem(s)[id]
    if who then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Soft reserved by", 1, 0.82, 0)
      for _, w in ipairs(who) do
        local r, g, b = U.classColor(s.res[w[1]] and s.res[w[1]].c)
        GameTooltip:AddLine(U.short(w[1]) .. (w[2] > 1 and (" x" .. w[2]) or ""), r, g, b)
      end
    end
    local won = S.winners(s, id)
    if #won > 0 then
      GameTooltip:AddLine(" ")
      for _, w in ipairs(won) do GameTooltip:AddLine("Given to " .. U.short(w[1]) .. " (" .. (w[2] == "HR" and "hard reserved" or w[2] == "DE" and "to disenchant" or w[2]) .. ")", 0.12, 1, 0) end
    end
    local from = LR.dropsFrom(s.raid, id)
    if #from > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Drops from " .. table.concat(from, ", "), 0.7, 0.7, 0.7, true)
    end
  end
  GameTooltip:Show()
end

--- who reserved an item, as one short coloured line (leaving out `except`, usually yourself)
function UI.whoLine(s, id, limit, except)
  local who = S.byItem(s)[id]
  if not who then return nil end
  if except then who = U.filter(who, function(w) return not U.samePlayer(w[1], except) end) end
  if #who == 0 then return nil end
  local parts = {}
  for i, w in ipairs(who) do
    if limit and i > limit then parts[#parts + 1] = "+" .. (#who - limit) break end
    local wins = S.srWins(s, w[1], id)
    local name = U.classText(U.short(w[1]), s.res[w[1]] and s.res[w[1]].c) .. (w[2] > 1 and (" x" .. w[2]) or "")
    if wins >= w[2] then name = "|cff9d9d9d" .. U.short(w[1]) .. (w[2] > 1 and (" x" .. w[2]) or "") .. " (won)|r"
    elseif wins > 0 then name = name .. " |cff9d9d9d(won " .. wins .. ")|r" end
    parts[#parts + 1] = name
  end
  return table.concat(parts, ", ")
end

---------------------------------------------------------------------- minimap button
local function minimapButton()
  local db = LR.db
  local b = CreateFrame("Button", "LootRulerMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture(LR.LOGO)
  icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 7, -5)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  -- a gold dot while a session in the group waits for your reserves
  local dot = b:CreateTexture(nil, "OVERLAY", nil, 1)
  dot:SetTexture("Interface\\COMMON\\Indicator-Yellow")
  dot:SetSize(14, 14)
  dot:SetPoint("TOPRIGHT", -2, -2)
  dot:Hide()
  local function place()
    local a = math.rad(db.ui.minimap or 230)
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
  end
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      db.ui.minimap = math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
      place()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnClick", function() UI.toggle() end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("LootRuler")
    local s = LR.current()
    if s then
      GameTooltip:AddLine(("%s soft reserves by %s"):format(LR.raidOf(s).name, LR.isLeader(s) and "you" or U.short(s.leader)), 1, 1, 1)
      GameTooltip:AddLine(("You've used %d of %d."):format(#LR.myPicks(s), S.limit(s, U.me())), 1, 1, 1)
    else
      GameTooltip:AddLine("No soft reserves open.", 1, 1, 1)
    end
    GameTooltip:AddLine("Click to open. Drag to move. /lr also opens it.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  place()
  if db.ui.hideMinimap then b:Hide() end
  function LR.minimapUpdate()
    local s = LR.current()
    dot:SetShown(s ~= nil and not s.locked and #LR.myPicks(s) < S.limit(s, U.me()))
  end
  LR.minimapUpdate()
  LR.minimap = b
end

---------------------------------------------------------------------- start up
local started = false
function UI.start()
  if started then return end
  if LR.db.ui.tab then UI.tab = LR.db.ui.tab end
  if LR.db.ui.usable ~= nil then UI.usable = LR.db.ui.usable end
  build()
  started = true
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
  if not LR.db then LR.loadDB() end      -- Core/Net.lua normally has by now; the order isn't promised
  minimapButton()
end)

SLASH_LOOTRULER1 = "/lr"
SLASH_LOOTRULER2 = "/lootruler"
SlashCmdList.LOOTRULER = function(msg)
  local raw = msg or ""                 -- item links keep their case
  msg = U.trim(raw):lower()
  if msg == "minimap" then
    LR.db.ui.hideMinimap = not LR.db.ui.hideMinimap
    if LR.minimap then LR.minimap:SetShown(not LR.db.ui.hideMinimap) end
    LR.print("minimap button " .. (LR.db.ui.hideMinimap and "hidden" or "shown") .. ".")
  elseif msg == "new" or msg == "session" or msg == "setup" then
    UI.show("session")
  elseif msg == "list" or msg == "reserves" then
    UI.show("reserves")
  elseif msg == "loot" or msg == "drops" then
    UI.show("loot")
  elseif msg == "guild" or msg == "points" then
    if IsInGuild() then UI.show("guild") else LR.print("you're not in a guild.") end
  elseif msg == "settings" or msg == "options" or msg == "config" then
    UI.show("settings")
  elseif msg == "help" or msg == "?" then
    UI.help()
  elseif msg:match("^de%s") or msg:match("^disenchanter%s") then
    local s = LR.current()
    local name = U.trim(raw:gsub("^%s*%a+%s*", ""))
    if not s or not LR.isLeader(s) then LR.print("Only the leader of the soft reserves picks the disenchanter.")
    else
      local m = LR.inGroup(name)
      LR.setDisenchanter(s, m and m.name or name)
      LR.print((m and m.name or U.full(name)) .. " is the disenchanter.")
    end
  elseif msg == "master" then
    UI.showMaster()
  elseif msg == "test" then
    UI.testRoll()
  elseif msg:match("^roll") then
    UI.rollCommand(raw:gsub("^%s*[Rr][Oo][Ll][Ll]%s*", ""))
  else
    UI.toggle()
  end
end
