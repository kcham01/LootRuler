-- The building blocks of the window, in the game's own look: framed panels with a gold title plate, red
-- panel buttons, gold "chips", item rows, text boxes, scroll areas. (The same kit as TBCrushCalc's.)
--
-- Screens are redrawn after every change (like the app). So nothing leaks, every widget comes from a pool:
-- K.get(owner, kind, parent) hands out a widget, and K.release(owner) puts back everything that owner had.
local _, LR = ...
local U = LR.U
local K = {}
LR.K = K

local floor, max, min = math.floor, math.max, math.min

K.GOLD = { 1, 0.82, 0 }
K.WHITE = { 1, 1, 1 }
K.GREY = { 0.62, 0.62, 0.62 }
K.GREEN = { 0.12, 1, 0 }
K.RED = { 1, 0.35, 0.3 }
K.TEXT = { 0.91, 0.89, 0.82 }        -- the app's panel text colour
K.SUB = { 0.74, 0.71, 0.64 }

K.WHITE8 = "Interface\\Buttons\\WHITE8X8"
K.ROCK = {
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32,
  insets = { left = 11, right = 12, top = 12, bottom = 11 },
}
K.PANEL = {
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
K.INSET = {
  bgFile = K.WHITE8, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = false, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
K.FLAT = { bgFile = K.WHITE8, edgeFile = K.WHITE8, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } }

function K.rgb(c) return c[1], c[2], c[3] end

---------------------------------------------------------------------- themes
-- A theme changes only how things look: frames, edges, buttons, ticks and fonts. Never where anything is, how big
-- it is, or what it does. The one in use is picked in Settings (settings.theme) and set when LootRuler's saved data is
-- read (K.useTheme, from LR.loadDB), before any window is made: every frame is made in its look, so a change comes in
-- with the next reload. Every look is drawn with the game's own textures and plain colours: nothing from another
-- addon is used, the ElvUI theme included.
local function flat(px)
  return { bgFile = K.WHITE8, edgeFile = K.WHITE8, edgeSize = px, insets = { left = px, right = px, top = px, bottom = px } }
end
local GOLD_EDGE = { 1, 0.82, 0, 1 }
K.THEMES = {
  -- the game's own look (what LootRuler always had)
  classic = {
    key = "classic", name = "Classic", what = "The game's own look: stone frames, gold title plates and red buttons.",
    rock = K.ROCK, sheet = K.ROCK, panel = K.PANEL, inset = K.INSET, flat = K.FLAT,
    plate = true, buttons = "game", close = "game", tick = "game", drop = "game", sign = "game", edit = "game",
    panelBg = { 1, 1, 1, 1 }, panelEdge = { 0.72, 0.56, 0.24, 1 }, hotBg = { 0.16, 0.12, 0.04, 1 }, hotEdge = GOLD_EDGE,
    foldBg = { 0.11, 0.09, 0.07, 1 }, foldEdge = { 0.72, 0.56, 0.24, 0.9 },
    quietBg = { 0.11, 0.09, 0.07, 1 }, quietEdge = { 0.55, 0.43, 0.2, 1 }, quietText = { 0.91, 0.89, 0.82 },
    chipOnBg = { 0.85, 0.66, 0.13, 1 }, chipOnEdge = { 0.36, 0.24, 0.06, 1 }, chipOnText = { 0, 0, 0 },
    chipBg = { 0.11, 0.09, 0.07, 1 }, chipEdge = { 0.42, 0.33, 0.19, 1 }, chipText = { 0.85, 0.81, 0.74 },
    navOnBg = { 0.85, 0.66, 0.13, 1 }, navOnEdge = { 0.36, 0.24, 0.06, 1 }, navOnText = { 0, 0, 0 },
    navBg = { 0, 0, 0, 0 }, navEdge = { 0, 0, 0, 0 }, navText = { 0.85, 0.81, 0.74 },
    factBg = { 0.08, 0.07, 0.05, 0.9 }, factEdge = { 0.42, 0.33, 0.19, 1 },
    rowBg = { 0, 0, 0, 0.35 }, rowEdge = { 0.42, 0.33, 0.19, 0.6 }, actBg = { 0.15, 0.12, 0.08, 1 }, actEdge = { 0.42, 0.33, 0.19, 1 },
    dropBg = { 0.02, 0.02, 0.02, 0.95 }, dropEdge = { 0.62, 0.52, 0.32, 1 },
    listBackdrop = { bgFile = K.WHITE8, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = false, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 } },
    listBg = { 0, 0, 0, 1 }, listEdge = { 0.8, 0.8, 0.8, 1 },
    memoBg = { 0, 0, 0, 0.8 }, memoEdge = { 0.42, 0.33, 0.19, 1 },
    line = { 0.72, 0.54, 0.23, 0.45 },
    tabOnBg = { 0.35, 0.27, 0.07, 1 }, tabOnEdge = GOLD_EDGE, tabBg = { 0.1, 0.08, 0.06, 1 }, tabEdge = { 0.42, 0.33, 0.19, 1 },
    bar = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
    hilite = "Interface\\Buttons\\ButtonHilight-Square", rowHilite = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
    foldHilite = "Interface\\Buttons\\UI-Listbox-Highlight2",
  },
  -- flat and dark like ElvUI: one-pixel black edges, dark grey frames, gold for what's picked, a narrow font.
  -- Made here from plain colours and the game's own textures and font
  elvui = {
    key = "elvui", name = "ElvUI", what = "Flat and dark, with thin black edges and a narrow font, to sit beside ElvUI.",
    rock = flat(1), sheet = flat(1), panel = flat(1), inset = flat(1), flat = flat(1),
    rockBg = { 0.06, 0.06, 0.06, 0.92 }, rockEdge = { 0, 0, 0, 1 },
    sheetBg = { 0.06, 0.06, 0.06, 1 }, sheetEdge = { 0, 0, 0, 1 },      -- (a pop-up over the window: solid)
    plate = false, buttons = "flat", close = "flat", tick = "flat", drop = "flat", sign = "flat", edit = "flat",
    font = "Fonts\\ARIALN.TTF", fontPlus = 0,
    panelBg = { 0.1, 0.1, 0.1, 0.8 }, panelEdge = { 0, 0, 0, 1 }, hotBg = { 0.13, 0.11, 0.05, 0.9 }, hotEdge = GOLD_EDGE,
    foldBg = { 0.1, 0.1, 0.1, 0.9 }, foldEdge = { 0, 0, 0, 1 },
    quietBg = { 0.1, 0.1, 0.1, 1 }, quietEdge = { 0, 0, 0, 1 }, quietText = { 0.9, 0.9, 0.9 },
    mainBg = { 0.1, 0.1, 0.1, 1 }, mainEdge = GOLD_EDGE, mainText = { 1, 0.82, 0 },
    chipOnBg = { 0.24, 0.2, 0.05, 1 }, chipOnEdge = GOLD_EDGE, chipOnText = { 1, 0.82, 0 },
    chipBg = { 0.1, 0.1, 0.1, 1 }, chipEdge = { 0, 0, 0, 1 }, chipText = { 0.85, 0.85, 0.85 },
    navOnBg = { 0.24, 0.2, 0.05, 1 }, navOnEdge = GOLD_EDGE, navOnText = { 1, 0.82, 0 },
    navBg = { 0.1, 0.1, 0.1, 0.9 }, navEdge = { 0, 0, 0, 1 }, navText = { 1, 0.82, 0 },
    factBg = { 0.08, 0.08, 0.08, 0.9 }, factEdge = { 0, 0, 0, 1 },
    rowBg = { 0.1, 0.1, 0.1, 0.75 }, rowEdge = { 0, 0, 0, 1 }, actBg = { 0.12, 0.12, 0.12, 1 }, actEdge = { 0, 0, 0, 1 },
    dropBg = { 0.1, 0.1, 0.1, 1 }, dropEdge = { 0, 0, 0, 1 },
    listBackdrop = flat(1), listBg = { 0.06, 0.06, 0.06, 1 }, listEdge = { 0, 0, 0, 1 },
    memoBg = { 0.04, 0.04, 0.04, 0.9 }, memoEdge = { 0, 0, 0, 1 },
    editBg = { 0.04, 0.04, 0.04, 1 }, editEdge = { 0, 0, 0, 1 },
    line = { 0.3, 0.3, 0.3, 0.9 },
    tabOnBg = { 0.24, 0.2, 0.05, 1 }, tabOnEdge = GOLD_EDGE, tabBg = { 0.1, 0.1, 0.1, 1 }, tabEdge = { 0, 0, 0, 1 },
    bar = K.WHITE8,
    hilite = "flat", rowHilite = "flat", foldHilite = "flat",
  },
}
K.THEME_ORDER = { "classic", "elvui" }

--- the look in use (K.T): call before any window is made
function K.useTheme(key)
  local t = K.THEMES[key] or K.THEMES.classic
  K.T = t
  K.ROCK, K.PANEL, K.INSET, K.FLAT = t.rock, t.panel, t.inset, t.flat
  return t
end
K.useTheme("classic")

--- colours from the theme (a list of r, g, b, a)
local function paint(f, bg, edge)
  if bg then f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1) end
  if edge then f:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1) end
end
K.paint = paint

--- a window's frame (the stone frame, or the theme's): sets its backdrop and the theme's colours for it
function K.skin(f, role)
  f:SetBackdrop(K.T[role or "rock"])
  paint(f, K.T[(role or "rock") .. "Bg"], K.T[(role or "rock") .. "Edge"])
end

-- the classic look's brown and dim gold edges and dark brown fills, as the theme draws them: for colours the screens
-- set themselves (K.edge, K.bg). Bright gold, greens and reds keep their meaning in every theme
local function brownish(r, g, b) return r >= g and g >= b and r < 0.8 and r - b <= 0.6 and r - b >= 0.05 end
function K.edge(r, g, b, a)
  if K.T.key ~= "classic" and brownish(r, g, b) then return 0, 0, 0, (a or 1) > 0 and 1 or 0 end
  return r, g, b, a
end
function K.bg(r, g, b, a)
  if K.T.key ~= "classic" and r >= g and g >= b and r < 0.4 and g >= r * 0.6 then
    local m = math.min(0.2, (r + g + b) / 3 * 1.1)
    return m, m, m, a
  end
  return r, g, b, a
end

--- what shows while the mouse is over a button: the game's glow, or (flat looks) a gold edge
local function hover(b, art)
  local tex = K.T[art or "hilite"]
  if tex ~= "flat" then b:SetHighlightTexture(tex, "ADD") return end
  if b.hoverEdge then return end
  b.hoverEdge = {}
  for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1 }, { "TOPRIGHT", "BOTTOMRIGHT", 1 } }) do
    local t = b:CreateTexture(nil, "HIGHLIGHT")
    t:SetColorTexture(1, 0.82, 0, 0.9)
    t:SetPoint(side[1]) t:SetPoint(side[2])
    if side[3] then t:SetWidth(side[3]) else t:SetHeight(side[4]) end
    b.hoverEdge[#b.hoverEdge + 1] = t
  end
  local fill = b:CreateTexture(nil, "HIGHLIGHT")
  fill:SetColorTexture(1, 1, 1, 0.05)
  fill:SetAllPoints()
end
K.hover = hover

--- the game's close button, or the theme's: a plain x (for a window's corner; OnClick hides its parent until set)
function K.closeButton(parent, size)
  if K.T.close == "game" then return CreateFrame("Button", nil, parent, "UIPanelCloseButton") end
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size or 32, size or 32)
  b.cross = b:CreateTexture(nil, "ARTWORK")
  b.cross:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
  b.cross:SetDesaturated(true)
  b.cross:SetVertexColor(0.9, 0.9, 0.9)
  b.cross:SetSize(16, 16)
  b.cross:SetPoint("CENTER")
  b.glow = b:CreateTexture(nil, "HIGHLIGHT")
  b.glow:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
  b.glow:SetSize(16, 16)
  b.glow:SetPoint("CENTER")
  b:SetScript("OnClick", function(self) self:GetParent():Hide() end)
  return b
end

--- a flat button (the flat themes' main button): SetText / GetText like the game's, gold words that grey when disabled
local function flatButton(parent)
  local b = CreateFrame("Button", nil, parent or UIParent, "BackdropTemplate")
  b:SetBackdrop(K.T.inset)
  paint(b, K.T.mainBg, K.T.mainEdge)
  b.text = b:CreateFontString(nil, "OVERLAY")
  K.themeFont(b.text)
  b.text:SetFontObject("GameFontNormal")
  b.text:SetPoint("LEFT", 6, 0)
  b.text:SetPoint("RIGHT", -6, 0)
  b.text:SetJustifyH("CENTER")
  b.text:SetJustifyV("MIDDLE")
  b.text:SetWordWrap(false)
  b:SetFontString(b.text)
  hover(b)
  b:SetHeight(24)
  local enable, disable, setEnabled = b.Enable, b.Disable, b.SetEnabled
  local function look(self, on)
    local c = on and K.T.mainText or { 0.5, 0.5, 0.5 }
    self.text:SetTextColor(c[1], c[2], c[3])
    paint(self, nil, on and K.T.mainEdge or { 0, 0, 0, 1 })
  end
  b.Enable = function(self) enable(self) look(self, true) end
  b.Disable = function(self) disable(self) look(self, false) end
  b.SetEnabled = function(self, on) setEnabled(self, on) look(self, on and true or false) end
  return b
end

--- the screen's main button, outside the pools (a roll window's Bid): the game's red button, or the theme's
function K.mainButton(parent)
  if K.T.buttons == "game" then return CreateFrame("Button", nil, parent, "UIPanelButtonTemplate") end
  return flatButton(parent)
end

---------------------------------------------------------------------- pools
local pools, live = {}, {}
local linkBoxes = setmetatable({}, { __mode = "k" })   -- text boxes that take item links (K.takeLinks)
local makers, resets = {}, {}

function K.define(kind, make, reset) makers[kind] = make resets[kind] = reset end

--- hands out a widget of `kind` for `owner` (a screen or a sheet), parented to `parent` and shown
function K.get(owner, kind, parent)
  pools[kind] = pools[kind] or {}
  local w = table.remove(pools[kind])
  if not w then w = makers[kind]() w._kind = kind end
  w:SetParent(parent)
  if w.SetFrameStrata and parent.GetFrameStrata then w:SetFrameStrata(parent:GetFrameStrata()) end
  w:ClearAllPoints()
  w:SetAlpha(1)
  if w.SetFrameLevel and parent.GetFrameLevel then w:SetFrameLevel(parent:GetFrameLevel() + 1) end
  if resets[kind] then resets[kind](w) end
  w:Show()
  live[owner] = live[owner] or {}
  table.insert(live[owner], w)
  return w
end

--- puts back every widget an owner was given
function K.release(owner)
  local list = live[owner]
  if not list then return end
  for i = #list, 1, -1 do
    local w = list[i]
    w:Hide()
    w:ClearAllPoints()
    if w.SetScript then
      if w.HasScript and w:HasScript("OnClick") then w:SetScript("OnClick", nil) end
      w:SetScript("OnEnter", nil)
      w:SetScript("OnLeave", nil)
    end
    table.insert(pools[w._kind], w)
  end
  live[owner] = nil
end

function K.liveCount() local n = 0 for _, l in pairs(live) do n = n + #l end return n end

--- a theme with its own font: every font set on this text (the game's font objects, by name) is drawn in it, a size up
--- (the game's font objects are never changed: they're the whole game's)
function K.themeFont(f)
  if not K.T.font then return end
  local set = f.SetFontObject
  f.SetFontObject = function(self, font)
    set(self, font)
    local _, size = self:GetFont()
    if size then self:SetFont(K.T.font, size + (K.T.fontPlus or 0), "") end
  end
end

local function fs(parent, font, layer)
  local f = parent:CreateFontString(nil, layer or "OVERLAY")
  K.themeFont(f)
  f:SetFontObject(font or "GameFontHighlight")
  f:SetJustifyH("LEFT")
  f:SetJustifyV("TOP")
  return f
end
K.fs = fs

local function tooltipOn(w, fn)
  w:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    fn(GameTooltip)
    GameTooltip:Show()
  end)
  w:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
K.tooltipOn = tooltipOn

---------------------------------------------------------------------- widgets
local PLATE_H, PLATE_END = 35, 22       -- a title plate's height, and its ends' width
local PLATE_MIN, PLATE_PAD = 90, 12     -- its middle: at least this wide, and this much wider than the title
-- a framed panel with a gold title plate (the app's "frame rock")
K.define("panel", function()
  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f:SetBackdrop(K.PANEL)
  paint(f, nil, K.T.panelEdge)
  -- the plate in three pieces of the game's header art (its left end, a middle that stretches, its right end), so it
  -- grows with the title (K.fitPlate)
  local art = "Interface\\DialogFrame\\UI-DialogBox-Header"
  f.plate = f:CreateTexture(nil, "ARTWORK")
  f.plate:SetTexture(art)
  f.plate:SetTexCoord(0.31, 0.67, 0, 0.63)
  f.plate:SetSize(PLATE_MIN, PLATE_H)
  f.plate:SetPoint("TOP", 0, 15)
  f.plateL = f:CreateTexture(nil, "ARTWORK")
  f.plateL:SetTexture(art)
  f.plateL:SetTexCoord(0.21, 0.31, 0, 0.63)
  f.plateL:SetSize(PLATE_END, PLATE_H)
  f.plateL:SetPoint("RIGHT", f.plate, "LEFT")
  f.plateR = f:CreateTexture(nil, "ARTWORK")
  f.plateR:SetTexture(art)
  f.plateR:SetTexCoord(0.67, 0.77, 0, 0.63)
  f.plateR:SetSize(PLATE_END, PLATE_H)
  f.plateR:SetPoint("LEFT", f.plate, "RIGHT")
  f.title = fs(f, "GameFontNormal")
  if K.T.plate then
    f.title:SetJustifyH("CENTER")
    f.title:SetPoint("TOP", f.plate, "TOP", 0, -13)
  else
    -- (no plate: the title sits at the top left, inside, above what the panel holds)
    f.title:SetJustifyH("LEFT")
    f.title:SetPoint("TOPLEFT", 10, -7)
  end
  return f
end, function(f)
  f.title:SetText("") K.fitPlate(f)
  paint(f, K.T.panelBg, K.T.panelEdge)                  -- (a hot panel's colours, back to the usual)
end)

--- sizes a panel's title plate to its title (hidden with no title)
function K.fitPlate(f)
  local title = f.title:GetText()
  local on = title ~= nil and title ~= ""
  local plate = on and K.T.plate
  f.plate:SetShown(plate) f.plateL:SetShown(plate) f.plateR:SetShown(plate)
  if on then f.plate:SetWidth(max(PLATE_MIN, f.title:GetStringWidth() + PLATE_PAD)) end
end

-- a section that opens and closes (Flow:fold): a bar with a + or -, the section's name and a line saying what's in it
K.define("fold", function()
  local b = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
  b:SetBackdrop(K.INSET)
  paint(b, K.T.foldBg, K.T.foldEdge)
  b.sign = b:CreateTexture(nil, "ARTWORK")
  b.sign:SetSize(16, 16)
  b.sign:SetPoint("TOPLEFT", 9, -8)
  if K.T.sign ~= "game" then
    -- (flat looks: a gold + or - in a small dark box)
    b.signBox = b:CreateTexture(nil, "ARTWORK")
    b.signBox:SetColorTexture(0, 0, 0, 1)
    b.signBox:SetSize(14, 14)
    b.signBox:SetPoint("CENTER", b.sign, "CENTER")
    b.signText = fs(b, "GameFontNormal")
    b.signText:SetJustifyH("CENTER")
    b.signText:SetJustifyV("MIDDLE")
    b.signText:SetAllPoints(b.sign)
  end
  b.title = fs(b, "GameFontNormal")
  b.title:SetPoint("TOPLEFT", 32, -8)
  b.title:SetPoint("RIGHT", -10, 0)
  b.what = fs(b, "GameFontHighlightSmall")
  b.what:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -3)
  b.what:SetPoint("RIGHT", -10, 0)
  hover(b, "foldHilite")
  return b
end, function(b) b.title:SetText("") b.what:SetText("") b.what:SetTextColor(K.rgb(K.SUB)) end)

--- a fold's + or -
function K.foldSign(b, open)
  if b.signText then
    b.sign:SetTexture(nil)
    b.signText:SetText(open and "-" or "+")
  else
    b.sign:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
  end
end

-- a plain container (no look of its own)
K.define("box", function() return CreateFrame("Frame", nil, UIParent, "BackdropTemplate") end, function(f)
  f:SetBackdrop(nil)
  f:EnableMouse(false)
end)

-- one piece of text
K.define("label", function()
  local f = CreateFrame("Frame", nil, UIParent)
  f.text = fs(f)
  f.text:SetAllPoints()
  return f
end, function(f)
  f.text:SetFontObject("GameFontHighlight")
  f.text:SetTextColor(K.rgb(K.TEXT))
  f.text:SetJustifyH("LEFT")
  f.text:SetJustifyV("TOP")
  f.text:SetText("")
  f:EnableMouse(false)
end)

-- the game's red panel button
K.define("button", function()
  local b = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
  b:SetHeight(24)
  return b
end, function(b) b:Enable() b:SetText("") end)
-- the flat themes' main button (K.button's red, in those looks)
K.define("flatmain", function() return flatButton(UIParent) end, function(b) b:Enable() b:SetText("") end)

-- a quiet button: for everything that isn't the screen's main action (that one stays the game's red button). Dark, with a
-- thin gold edge, like the chips
K.define("quiet", function()
  local b = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
  b:SetBackdrop(K.INSET)
  b.text = fs(b, "GameFontHighlightSmall")
  b.text:SetJustifyH("CENTER")
  b.text:SetJustifyV("MIDDLE")
  b.text:SetPoint("LEFT", 8, 0)
  b.text:SetPoint("RIGHT", -8, 0)
  b.text:SetWordWrap(false)
  hover(b)
  b:SetHeight(24)
  return b
end, function(b)
  b:Enable()
  b.text:SetText("")
  paint(b, K.T.quietBg, K.T.quietEdge)
  b.text:SetTextColor(K.rgb(K.T.quietText))
end)

-- a link: words only, for rare or risky actions (Call off, Change). `danger` makes it red
K.define("link", function()
  local b = CreateFrame("Button", nil, UIParent)
  b.text = fs(b, "GameFontNormalSmall")
  b.text:SetJustifyV("MIDDLE")
  b.text:SetAllPoints()
  b.text:SetWordWrap(false)
  b.line = b:CreateTexture(nil, "HIGHLIGHT")             -- (an underline while the mouse is over it)
  b.line:SetColorTexture(1, 0.82, 0, 0.8)
  b.line:SetHeight(1)
  b.line:SetPoint("BOTTOMLEFT", 0, 3)
  b.line:SetPoint("BOTTOMRIGHT", 0, 3)
  b:SetHeight(20)
  return b
end, function(b) b:Enable() b.text:SetText("") b.text:SetTextColor(K.rgb(K.GOLD)) b.text:SetJustifyH("LEFT") end)

--- a button of one of the three weights: "red" (the screen's main action, the game's own button), "quiet" or "link";
--- returns it sized to its words (at least minW, at most maxW)
function K.button(owner, parent, style, label, minW, maxW, danger)
  local b
  if style == "quiet" or style == "link" then
    b = K.get(owner, style, parent)
    b.text:SetText(label)
    local w = b.text:GetStringWidth() + (style == "quiet" and 18 or 2)
    if style == "link" then
      if danger then b.text:SetTextColor(1, 0.35, 0.3) end
      b:SetWidth(min(maxW or w, w))
    else
      b:SetWidth(min(maxW or 9999, max(minW or 0, w)))
    end
  else
    b = K.get(owner, K.T.buttons == "game" and "button" or "flatmain", parent)
    b:SetText(label)
    b:SetWidth(min(maxW or 9999, max(minW or 80, b:GetFontString():GetStringWidth() + 28)))
  end
  return b
end

-- a line saying how things stand (open, locked, your reserves are in): a coloured dot, the words, and maybe a link
-- on the right. tone: "ok" (green), "warn" (gold) or "bad" (red)
local TONES = {
  ok = { dot = "Interface\\COMMON\\Indicator-Green", bg = { 0.07, 0.13, 0.06, 0.95 }, edge = { 0.25, 0.42, 0.16, 1 } },
  warn = { dot = "Interface\\COMMON\\Indicator-Yellow", bg = { 0.13, 0.1, 0.03, 0.95 }, edge = { 0.6, 0.47, 0.12, 1 } },
  bad = { dot = "Interface\\COMMON\\Indicator-Red", bg = { 0.15, 0.05, 0.04, 0.95 }, edge = { 0.6, 0.2, 0.15, 1 } },
}
K.define("strip", function()
  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f:SetBackdrop(K.INSET)
  f.dot = f:CreateTexture(nil, "ARTWORK")
  f.dot:SetSize(14, 14)
  f.dot:SetPoint("TOPLEFT", 8, -7)
  f.text = fs(f, "GameFontHighlightSmall")
  f.text:SetPoint("TOPLEFT", 26, -8)
  return f
end, function(f) f.text:SetText("") f:EnableMouse(false) end)

-- a small box with a gold heading and a line under it (the facts about someone else's session)
K.define("fact", function()
  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f:SetBackdrop(K.INSET)
  f.k = fs(f, "GameFontNormalSmall")
  f.k:SetPoint("TOPLEFT", 9, -8)
  f.v = fs(f, "GameFontHighlightSmall")
  f.v:SetPoint("TOPLEFT", f.k, "BOTTOMLEFT", 0, -3)
  return f
end, function(f)
  f.k:SetText("") f.v:SetText("")
  paint(f, K.T.factBg, K.T.factEdge)
end)

-- a row for a person (or anything with a few things under it): a name and a line under it on the left, words in the
-- middle, and maybe a link on the right (Flow:entry)
K.define("entry", function()
  local b = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
  b:SetBackdrop(K.FLAT)
  b.name = fs(b, "GameFontNormal")
  b.name:SetPoint("TOPLEFT", 8, -7)
  b.name:SetWordWrap(false)
  b.sub = fs(b, "GameFontHighlightSmall")
  b.sub:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -3)
  b.sub:SetWordWrap(false)
  b.body = fs(b, "GameFontHighlightSmall")
  hover(b, "rowHilite")
  return b
end, function(b)
  b.name:SetText("") b.sub:SetText("") b.body:SetText("")
  b.sub:SetTextColor(K.rgb(K.SUB)) b.body:SetTextColor(K.rgb(K.TEXT))
  paint(b, K.T.rowBg, K.T.rowEdge)
  b:Enable()
end)

-- one entry in a list down the side (the Settings tab's sections): its words, gold when it's the one shown
K.define("nav", function()
  local b = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
  b:SetBackdrop(K.FLAT)
  b.text = fs(b, "GameFontHighlightSmall")
  b.text:SetPoint("TOPLEFT", 6, -4)
  hover(b)
  return b
end, function(b) b:Enable() b.text:SetText("") end)

--- an entry down the side: width, its words, and whether it's the one shown; returns its height
function K.setNav(b, width, label, on)
  b:SetWidth(width)
  b.text:SetWidth(width - 12)
  b.text:SetText(label)
  if on then
    paint(b, K.T.navOnBg, K.T.navOnEdge) b.text:SetTextColor(K.rgb(K.T.navOnText))
  else
    paint(b, K.T.navBg, K.T.navEdge) b.text:SetTextColor(K.rgb(K.T.navText))
  end
  local h = math.max(20, b.text:GetStringHeight() + 8)
  b:SetHeight(h)
  return h
end

-- a rounded toggle "chip"
K.define("chip", function()
  local b = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
  b:SetBackdrop(K.INSET)
  b.text = fs(b, "GameFontHighlightSmall")
  b.text:SetJustifyH("CENTER")
  b.text:SetJustifyV("MIDDLE")
  b.text:SetPoint("LEFT", 6, 0)
  b.text:SetPoint("RIGHT", -6, 0)
  hover(b)
  b:SetHeight(20)
  return b
end, function(b) b:Enable() end)

function K.setChip(b, label, on)
  b.text:SetText(label)
  b:SetWidth(max(28, b.text:GetStringWidth() + 16))
  if on then
    paint(b, K.T.chipOnBg, K.T.chipOnEdge)
    b.text:SetTextColor(K.rgb(K.T.chipOnText))
  else
    paint(b, K.T.chipBg, K.T.chipEdge)
    b.text:SetTextColor(K.rgb(K.T.chipText))
  end
end

-- a drop-down in the game's own look: a dark box with the choice in it and the gold arrow button, and a list with round
-- ticks under it (K.dropdown). One list is shared; it sits over everything in the window, a click anywhere else or
-- Escape closes it.
local dropList, dropCatcher, dropOwner, dropId, dropSwapped
local dropRows = {}
local DROP_ROW = 16
K.define("drop", function()
  local b = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
  b:SetBackdrop(K.INSET)
  b:SetHeight(26)
  b.arrow = CreateFrame("Button", nil, b)
  b.arrow:SetSize(24, 24)
  b.arrow:SetPoint("RIGHT", -1, 0)
  if K.T.drop == "game" then
    b.arrow:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    b.arrow:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
    b.arrow:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  else
    -- (flat looks: just a gold arrow, no box)
    b.arrow:SetNormalTexture("Interface\\Buttons\\Arrow-Down-Up")
    b.arrow:SetPushedTexture("Interface\\Buttons\\Arrow-Down-Down")
    hover(b)
  end
  b.arrow:SetScript("OnClick", function() if b.toggle then b.toggle() end end)
  b.text = fs(b, "GameFontHighlightSmall")
  b.text:SetJustifyH("RIGHT")
  b.text:SetJustifyV("MIDDLE")
  b.text:SetPoint("LEFT", 8, 0)
  b.text:SetPoint("RIGHT", b.arrow, "LEFT", -2, 0)
  b.text:SetWordWrap(false)
  -- hidden: the window closed, or the screen is being redrawn (K.dropdown with the same id takes the list over); a moment
  -- later, a list nobody took over closes
  b:SetScript("OnHide", function(self)
    if dropOwner ~= self then return end
    C_Timer.After(0, function() if dropOwner == self and not self:IsVisible() then K.closeDrop() end end)
  end)
  return b
end, function(b)
  b.toggle = nil
  b.text:SetText("")
  paint(b, K.T.dropBg, K.T.dropEdge)
end)

-- while the list is open, Escape closes it and nothing else: our frames come off the game's Escape list until it closes
local function escapeToList(on)
  if on then
    dropSwapped = {}
    for i = #UISpecialFrames, 1, -1 do
      local n = UISpecialFrames[i]
      if type(n) == "string" and n:find("^LootRuler") then table.insert(dropSwapped, 1, n) table.remove(UISpecialFrames, i) end
    end
    tinsert(UISpecialFrames, "LootRulerDropList")
  else
    for i = #UISpecialFrames, 1, -1 do if UISpecialFrames[i] == "LootRulerDropList" then table.remove(UISpecialFrames, i) end end
    for _, n in ipairs(dropSwapped or {}) do tinsert(UISpecialFrames, n) end
    dropSwapped = nil
  end
end

local function makeDropList()
  dropCatcher = CreateFrame("Button", nil, UIParent)
  dropCatcher:SetAllPoints(UIParent)
  dropCatcher:SetScript("OnClick", function() K.closeDrop() end)
  dropCatcher:Hide()
  dropList = CreateFrame("Frame", "LootRulerDropList", UIParent, "BackdropTemplate")
  dropList:SetBackdrop(K.T.listBackdrop)
  paint(dropList, K.T.listBg, K.T.listEdge)
  dropList:EnableMouse(true)
  dropList:SetClampedToScreen(true)
  dropList:Hide()
  dropList:SetScript("OnHide", function()
    dropOwner, dropId = nil, nil
    dropCatcher:Hide()
    if dropSwapped then escapeToList(false) end
  end)
  K.dropList, K.dropCatcher = dropList, dropCatcher
end

local function dropRow(i)
  local r = dropRows[i]
  if r then return r end
  r = CreateFrame("Button", nil, dropList)
  r:SetHeight(DROP_ROW)
  r.tick = r:CreateTexture(nil, "ARTWORK")
  -- the round ticks of the game's drop-downs, or (flat looks) a gold tick by the one picked
  r.tick:SetTexture(K.T.drop == "game" and "Interface\\Common\\UI-DropDownRadioChecks" or "Interface\\Buttons\\UI-CheckBox-Check")
  r.tick:SetSize(16, 16)
  r.tick:SetPoint("LEFT", 0, 0)
  r.text = fs(r, "GameFontHighlightSmall")
  r.text:SetJustifyV("MIDDLE")
  r.text:SetPoint("LEFT", 20, 0)
  r.text:SetWordWrap(false)
  hover(r, "rowHilite")
  dropRows[i] = r
  return r
end

function K.closeDrop() if dropList and dropList:IsShown() then dropList:Hide() end end
function K.dropOpen() return dropList ~= nil and dropList:IsShown() and dropOwner end

-- fills the list for drop-down b and puts it under it
local function fillDrop(b, items, pick)
  -- the list goes in the window (not the scrolling area the box is in, which would cut it off), over everything
  local root = b
  while root:GetParent() and root:GetParent() ~= UIParent do root = root:GetParent() end
  dropCatcher:SetParent(root)
  dropCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
  dropList:SetParent(root)
  dropList:SetFrameStrata("FULLSCREEN_DIALOG")
  dropList:SetFrameLevel(dropCatcher:GetFrameLevel() + 5)
  local width, y = b:GetWidth(), 9
  for i, it in ipairs(items) do
    local r = dropRow(i)
    r:SetFrameLevel(dropList:GetFrameLevel() + 2)
    r.text:SetFontObject(it.head and "GameFontNormalSmall" or "GameFontHighlightSmall")
    r.text:SetText(it.label)
    if K.T.drop == "game" then
      r.tick:SetShown(not it.head)
      if it.on then r.tick:SetTexCoord(0, 0.5, 0.5, 1) else r.tick:SetTexCoord(0.5, 1, 0.5, 1) end
    else
      r.tick:SetShown(it.on and not it.head and true or false)
    end
    r.text:ClearAllPoints()
    r.text:SetPoint("LEFT", it.head and 0 or 20, 0)
    r:EnableMouse(not it.head)
    r:SetScript("OnClick", not it.head and function() K.closeDrop() pick(it) end or nil)
    if it.tip then tooltipOn(r, function(tt) tt:SetText(it.tip, 1, 1, 1, 1, true) end)
    else r:SetScript("OnEnter", nil) r:SetScript("OnLeave", nil) end
    if (it.head or it.gap) and i > 1 then y = y + 6 end
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", dropList, "TOPLEFT", 12, -y)
    r:SetPoint("RIGHT", dropList, "RIGHT", -12, 0)
    r:Show()
    width = max(width, r.text:GetStringWidth() + (it.head and 0 or 20) + 28)
    y = y + DROP_ROW
  end
  for i = #items + 1, #dropRows do dropRows[i]:Hide() end
  dropList:SetSize(width, y + 9)
  dropOwner = b
  K.placeDrop()
end

--- puts the list under its box, moved up as far as it takes to stay inside the window
function K.placeDrop()
  local b = dropOwner
  if not b then return end
  local root = dropList:GetParent()
  local up = 0
  local bottom, rootBottom, rootTop = b:GetBottom(), root:GetBottom(), root:GetTop()
  if bottom and rootBottom and rootTop then
    up = min(max(0, dropList:GetHeight() - (bottom - 2 - rootBottom - 10)), max(0, rootTop - 10 - (bottom - 2)))
  end
  dropList:ClearAllPoints()
  dropList:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2 + up)
end

--- opens the list under drop-down b: items are { label, on (ticked), head (a heading, not a choice), gap (a little space
--- before it), tip };
--- pick(item) gets the one clicked. id: the same drop-down drawn again keeps it open (K.dropdown)
function K.openDrop(b, items, pick, id)
  if not dropList then makeDropList() end
  K.closeDrop()
  fillDrop(b, items, pick)
  dropId = id
  dropCatcher:Show()
  dropList:Show()
  escapeToList(true)
end

--- a drop-down `width` wide showing `label`; a click lists `items` (K.openDrop) and pick(item) gets the one chosen.
--- id names it, so a list that's open stays open when the screen is redrawn (a change coming in while you choose)
function K.dropdown(owner, parent, width, label, items, pick, id)
  local b = K.get(owner, "drop", parent)
  b:SetWidth(width)
  b.text:SetText(label)
  b.toggle = function()
    if dropOwner == b then K.closeDrop() else K.openDrop(b, items, pick, id) end
  end
  b:SetScript("OnClick", b.toggle)
  -- (placed once the screen has put the box where it goes)
  if id and dropId == id and dropList:IsShown() then fillDrop(b, items, pick) C_Timer.After(0, K.placeDrop) end
  return b
end

-- the game's own close button (the red square with a gold x): every x that closes something or takes it away. Its art
-- has a margin round it, so K.X_SIZE is bigger than the square you see
K.X_SIZE = 30
--- the theme's x on its own (no script: the caller sets what it does)
function K.xButton(parent)
  local b
  if K.T.close == "game" then
    b = CreateFrame("Button", nil, parent, "UIPanelCloseButtonNoScripts")
  else
    b = K.closeButton(parent)
    b:SetScript("OnClick", nil)
  end
  b:SetSize(K.X_SIZE, K.X_SIZE)
  return b
end
K.define("x", function() return K.xButton(UIParent) end, function(b) b:Enable() end)

-- a tick box with its words beside it (an on / off switch): Flow:chips with tick = true
K.define("tick", function()
  local b = CreateFrame("Button", nil, UIParent)
  b.box = b:CreateTexture(nil, "ARTWORK")
  b.box:SetSize(22, 22)
  b.box:SetPoint("LEFT", -2, 0)
  b.check = b:CreateTexture(nil, "OVERLAY")
  if K.T.tick == "game" then
    b.box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    b.check:SetAllPoints(b.box)
  else
    -- (flat looks: a small dark square with a black edge, filled gold when it's on; the 22 by 22 box keeps its room)
    b.box:SetColorTexture(0, 0, 0, 0)
    b.edge = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.edge:SetColorTexture(0, 0, 0, 1)
    b.edge:SetSize(14, 14)
    b.edge:SetPoint("CENTER", b.box)
    b.inner = b:CreateTexture(nil, "ARTWORK", nil, 2)
    b.inner:SetColorTexture(0.12, 0.12, 0.12, 1)
    b.inner:SetSize(12, 12)
    b.inner:SetPoint("CENTER", b.box)
    b.check:SetColorTexture(1, 0.82, 0, 1)
    b.check:SetSize(10, 10)
    b.check:SetPoint("CENTER", b.box)
  end
  b.text = fs(b, "GameFontHighlightSmall")
  b.text:SetJustifyV("MIDDLE")
  b.text:SetPoint("LEFT", b.box, "RIGHT", 1, 0)
  b.text:SetPoint("RIGHT")
  b.glow = b:CreateTexture(nil, "HIGHLIGHT")              -- (the HIGHLIGHT layer shows while the mouse is over it)
  if K.T.tick == "game" then
    b.glow:SetTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
    b.glow:SetBlendMode("ADD")
    b.glow:SetAllPoints(b.box)
  else
    b.glow:SetColorTexture(1, 0.82, 0, 0.3)
    b.glow:SetSize(14, 14)
    b.glow:SetPoint("CENTER", b.box)
  end
  b:SetHeight(20)
  return b
end, function(b) b:Enable() end)

function K.setTick(b, label, on)
  b.text:SetText(label)
  b:SetWidth(b.text:GetStringWidth() + 26)
  b.check:SetShown(on and true or false)
  b.on = on and true or false
  if on then b.text:SetTextColor(1, 1, 1) else b.text:SetTextColor(0.85, 0.81, 0.74) end
end

-- an icon with a thin dark border
local function iconParts(f, size)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  f.border = f:CreateTexture(nil, "BACKGROUND", nil, 1)    -- above a backdrop's centre (BACKGROUND 0)
  f.border:SetColorTexture(0, 0, 0, 1)
end
function K.placeIcon(f, x, y, size, anchor)
  f.border:ClearAllPoints()
  f.border:SetPoint(anchor or "TOPLEFT", x, y)
  f.border:SetSize(size, size)
  f.icon:ClearAllPoints()
  f.icon:SetPoint("TOPLEFT", f.border, "TOPLEFT", 1, -1)
  f.icon:SetPoint("BOTTOMRIGHT", f.border, "BOTTOMRIGHT", -1, 1)
end
K.iconParts = iconParts

-- two texts on one line: a label and a value
K.define("kv", function()
  local f = CreateFrame("Frame", nil, UIParent)
  f.k = fs(f, "GameFontNormal")
  f.k:SetPoint("TOPLEFT")
  f.v = fs(f, "GameFontHighlight")
  f.v:SetJustifyH("RIGHT")
  f.v:SetPoint("TOPRIGHT")
  f:SetHeight(16)
  return f
end, function(f)
  f.k:SetFontObject("GameFontNormal") f.v:SetFontObject("GameFontHighlight")
  f.k:SetTextColor(K.rgb(K.GOLD)) f.v:SetTextColor(1, 1, 1)
  f.k:SetText("") f.v:SetText("")
end)

-- a text box
K.define("edit", function()
  local e
  if K.T.edit == "game" then
    e = CreateFrame("EditBox", nil, UIParent, "InputBoxTemplate")
  else
    -- (flat looks: a dark box with a black edge; the words start where the game's box has them)
    e = CreateFrame("EditBox", nil, UIParent, "BackdropTemplate")
    e:SetBackdrop(K.T.inset)
    paint(e, K.T.editBg, K.T.editEdge)
    e:SetTextInsets(4, 4, 0, 0)
    e:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
  end
  e:SetAutoFocus(false)
  e:SetHeight(22)
  e:SetFontObject("GameFontHighlight")
  if K.T.font then e:SetFont(K.T.font, 12 + (K.T.fontPlus or 0), "") end
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  -- InputBoxTemplate highlights all the text whenever the box gains focus, so the next key replaces it.
  -- Right when you click in; wrong when a redraw hands the focus back while you're typing (K.refocus)
  e:SetScript("OnEditFocusGained", function(self)
    if self.keepCursor then
      self.keepCursor = nil
      self:HighlightText(0, 0)
      self:SetCursorPosition(#self:GetText())
    else
      self:HighlightText()
    end
  end)
  -- greyed words inside the box while it's empty ("Search Karazhan"): K.setHint, K.onText
  e.hint = fs(e, "GameFontDisableSmall")
  e.hint:SetPoint("LEFT", K.T.edit == "game" and 2 or 5, 0)
  e.hint:SetPoint("RIGHT", -4, 0)
  e.hint:SetJustifyV("MIDDLE")
  e.hint:SetWordWrap(false)
  return e
end, function(e)
  e:SetScript("OnTextChanged", nil) e:SetScript("OnEnterPressed", nil) e:SetText("") e:SetMaxLetters(0) e:ClearFocus()
  e.keepCursor = nil linkBoxes[e] = nil
  e.hint:SetText("") e.hint:Hide()
end)

--- the greyed words shown inside an empty text box (set its text first)
function K.setHint(e, text)
  e.hint:SetText(text or "")
  e.hint:SetShown((text or "") ~= "" and e:GetText() == "")
end
--- what a text box does when its text changes; its hint goes while there's text
function K.onText(e, fn)
  e:SetScript("OnTextChanged", function(self, user)
    self.hint:SetShown(self.hint:GetText() ~= "" and self:GetText() == "")
    if fn then fn(self, user) end
  end)
end

-- a box of many lines of text to copy (exports), scrolling when it's long
K.define("memo", function()
  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f:SetBackdrop(K.INSET)
  paint(f, K.T.memoBg, K.T.memoEdge)
  f.scroll = K.scroller(f)
  f.scroll:SetPoint("TOPLEFT", 6, -6)
  f.scroll:SetPoint("BOTTOMRIGHT", -6, 6)
  f.edit = CreateFrame("EditBox", nil, f.scroll.child)
  f.edit:SetMultiLine(true)
  f.edit:SetAutoFocus(false)
  f.edit:SetFontObject("GameFontHighlightSmall")
  if K.T.font then f.edit:SetFont(K.T.font, 10 + (K.T.fontPlus or 0), "") end
  f.edit:SetPoint("TOPLEFT")
  f.edit:SetMaxLetters(0)                  -- (no limit: a softres.it export is thousands of letters)
  f.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  -- a click anywhere in the box puts the cursor in it (the text box itself is only as tall as its lines)
  f:EnableMouse(true)
  f:SetScript("OnMouseDown", function() f.edit:SetFocus() end)
  return f
end, function(f)
  f.edit:SetText("") f.edit:SetScript("OnTextChanged", nil) f.edit:ClearFocus()
  -- (made on UIParent and moved into a window: K.get raises the box itself, so raise what's inside it too,
  -- or the window's own frames can cover the text box and take its clicks)
  f.scroll:SetFrameLevel(f:GetFrameLevel() + 1)
  f.scroll.child:SetFrameLevel(f:GetFrameLevel() + 2)
  f.edit:SetFrameLevel(f:GetFrameLevel() + 3)
end)

--- fills a memo with text that can be copied but not changed; height: the box's height
function K.setMemo(f, width, height, text)
  f:SetSize(width, height)
  f.edit:SetWidth(width - 20)
  f.edit:SetText(text)
  local lines = select(2, text:gsub("\n", "\n")) + 1
  f.edit:SetHeight(math.max(height - 12, lines * 13 + 6))
  f.scroll:setContentHeight(lines * 13 + 6)
  f.edit:SetScript("OnTextChanged", function(self, user) if user then self:SetText(text) self:HighlightText() end end)
  f.edit:SetFocus()
  f.edit:HighlightText()
end

--- a memo that can be typed and pasted in (several lines); changed(text) on each change; focus: the cursor goes in
--- at once, ready to paste
function K.setEditMemo(f, width, height, text, changed, focus)
  f:SetSize(width, height)
  f.edit:SetWidth(width - 20)
  f.edit:SetText(text)
  f.edit:SetHeight(height - 12)
  f.scroll:setContentHeight(height - 12)
  f.edit:SetScript("OnTextChanged", function(self, user)
    if not user then return end
    local lines = select(2, self:GetText():gsub("\n", "\n")) + 1
    self:SetHeight(math.max(height - 12, lines * 13 + 6))
    f.scroll:setContentHeight(math.max(height - 12, lines * 13 + 6))
    changed(self:GetText())
  end)
  if focus then f.edit:SetFocus() end
end

--- text boxes that take item links: shift-clicking an item (in your bags, chat, anywhere) while one has the
--- focus puts the item's link in it, as it would in the chat box
function K.takeLinks(e) linkBoxes[e] = true end
if hooksecurefunc and ChatEdit_InsertLink then
  hooksecurefunc("ChatEdit_InsertLink", function(text)
    if type(text) ~= "string" or not text:find("|Hitem:", 1, true) then return end
    for e in pairs(linkBoxes) do
      if e:IsVisible() and e:HasFocus() then
        e:SetText(text)
        local fn = e:GetScript("OnTextChanged")
        if fn then fn(e, true) end
        return
      end
    end
  end)
end

--- gives a text box the focus back without highlighting its text: the cursor goes to the end, as if you'd
--- never stopped typing
function K.refocus(e)
  e.keepCursor = true
  e:SetFocus()
  e:HighlightText(0, 0)
  e:SetCursorPosition(#e:GetText())
end

-- an item row: icon, name in its quality colour, a line under it, a badge on the right and an optional
-- small button (x or +) at the far right
K.define("item", function()
  local b = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
  b:SetBackdrop(K.FLAT)
  iconParts(b)
  K.placeIcon(b, 4, -4, 28)
  b.name = fs(b, "GameFontHighlight")
  b.name:SetPoint("TOPLEFT", 38, -5)
  b.name:SetWordWrap(false)
  b.sub = fs(b, "GameFontHighlightSmall")
  b.sub:SetPoint("TOPLEFT", 38, -20)
  b.sub:SetWordWrap(false)
  b.badge = fs(b, "GameFontNormal")
  b.badge:SetJustifyH("RIGHT")
  b.badge:SetJustifyV("MIDDLE")
  b.act = CreateFrame("Button", nil, b, "BackdropTemplate")
  b.act:SetSize(20, 20)
  b.act:SetPoint("RIGHT", -6, 0)
  b.act:SetBackdrop(K.INSET)
  b.act.text = fs(b.act, "GameFontNormal")
  b.act.text:SetJustifyH("CENTER")
  b.act.text:SetJustifyV("MIDDLE")
  b.act.text:SetAllPoints()
  hover(b.act)
  -- (an "x" is the game's own close button: K.X_SIZE)
  b.x = K.xButton(b)
  b.x:SetPoint("RIGHT", 1, 0)
  hover(b, "rowHilite")
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetHeight(36)
  return b
end, function(b)
  b.name:SetText("") b.sub:SetText("") b.badge:SetText("")
  b.name:SetTextColor(1, 1, 1) b.sub:SetTextColor(K.rgb(K.SUB)) b.badge:SetTextColor(K.rgb(K.GOLD))
  b.act:Hide() b.act:SetWidth(20) b.act:SetScript("OnClick", nil) b.act:SetScript("OnEnter", nil) b.act:SetScript("OnLeave", nil)
  b.x:Hide() b.x:SetScript("OnClick", nil) b.x:SetScript("OnEnter", nil) b.x:SetScript("OnLeave", nil)
  b.icon:SetDesaturated(false) b.icon:SetAlpha(1)
  paint(b, K.T.rowBg, K.T.rowEdge)
  b:SetAlpha(1)
  b:Enable()
end)

--- fills an item row; width is the row's width, act = { text, tip, click, width } for the small button (text "x" is the
--- game's close button: row.x, not row.act)
function K.setItem(b, width, icon, name, sub, badge, act)
  b:SetWidth(width)
  b.icon:SetTexture(icon)
  b.name:SetText(name)
  b.sub:SetText(sub or "")
  b.badge:SetText(badge or "")
  local right = 8
  if act and act.text == "x" then
    b.x:Show()
    b.x:SetScript("OnClick", act.click)
    if act.tip then tooltipOn(b.x, function(tt) tt:SetText(act.tip, 1, 1, 1, 1, true) end) end
    right = K.X_SIZE - 2
  elseif act then
    b.act:Show()
    b.act:SetWidth(act.width or 20)
    b.act.text:SetText(act.text)
    paint(b.act, K.T.actBg, K.T.actEdge)
    b.act:SetScript("OnClick", act.click)
    if act.tip then tooltipOn(b.act, function(tt) tt:SetText(act.tip, 1, 1, 1, 1, true) end) end
    right = (act.width or 20) + 12
  end
  b.badge:ClearAllPoints()
  b.badge:SetPoint("RIGHT", b, "RIGHT", -right, 0)
  local bw = (badge and badge ~= "") and (b.badge:GetStringWidth() + 12) or 0
  b.name:SetWidth(width - 44 - right - bw)
  b.sub:SetWidth(width - 44 - right - bw)
end

-- a heading inside a list (a boss name)
K.define("head", function()
  local f = CreateFrame("Frame", nil, UIParent)
  f.text = fs(f, "GameFontNormal")
  f.text:SetPoint("BOTTOMLEFT", 2, 3)
  f.line = f:CreateTexture(nil, "ARTWORK")
  f.line:SetColorTexture(unpack(K.T.line))
  f.line:SetHeight(1)
  f.line:SetPoint("BOTTOMLEFT", 0, 0)
  f.line:SetPoint("BOTTOMRIGHT", 0, 0)
  f.right = fs(f, "GameFontHighlightSmall")
  f.right:SetJustifyH("RIGHT")
  f.right:SetPoint("BOTTOMRIGHT", -2, 4)
  f:SetHeight(22)
  return f
end, function(f) f.text:SetText("") f.right:SetText("") f.text:SetTextColor(K.rgb(K.GOLD)) end)

---------------------------------------------------------------------- vertical flow layout
local Flow = {}
Flow.__index = Flow

--- lays widgets out top to bottom inside `parent`, `width` wide, starting `x`, `y` from its top-left
function K.flow(owner, parent, x, y, width)
  return setmetatable({ owner = owner, parent = parent, x = x, y = y or 0, width = width, top = y or 0 }, Flow)
end

function Flow:place(w, h, dx, width)
  w:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x + (dx or 0), -self.y)
  if width then w:SetWidth(width) end
  if h then w:SetHeight(h) end
  self.y = self.y + (h or w:GetHeight())
  return w
end
function Flow:gap(n) self.y = self.y + (n or 6) return self end
function Flow:height() return self.y - self.top end

--- a paragraph of text; returns the label
function Flow:text(text, opts)
  opts = opts or {}
  local l = K.get(self.owner, "label", self.parent)
  l.text:SetFontObject(opts.font or "GameFontHighlight")
  local c = opts.color or K.TEXT
  l.text:SetTextColor(c[1], c[2], c[3])
  l.text:SetJustifyH(opts.justify or "LEFT")
  l.text:SetWordWrap(true)
  l.text:SetText(text)
  local w = opts.width or self.width
  l:SetWidth(w)
  l.text:SetWidth(w)
  local h = max(l.text:GetStringHeight(), 1) + 2
  self:place(l, h, opts.dx)
  if opts.gap ~= false then self:gap(opts.gap or 4) end
  return l
end
function Flow:note(text, color) return self:text(text, { font = "GameFontHighlightSmall", color = color or K.SUB, gap = 5 }) end

--- a section that opens and closes: its bar (title, and what's in it), then, while it's open, its contents in a panel.
--- toggle: what a click on the bar does (the caller keeps whether it's open)
function Flow:fold(title, what, open, toggle, fill)
  local b = K.get(self.owner, "fold", self.parent)
  K.foldSign(b, open)
  b.title:SetText(title)
  b.title:SetWidth(self.width - 42)
  b.what:SetText(what or "")
  b.what:SetWidth(self.width - 42)
  b:SetScript("OnClick", toggle)
  b.open = open and true or false
  local h = 8 + b.title:GetStringHeight() + ((what and what ~= "") and (3 + b.what:GetStringHeight()) or 0) + 8
  self:place(b, max(32, h), nil, self.width)
  if open then
    self:gap(2)
    self:panel(nil, fill)
  else
    self:gap(6)
  end
  return b
end

--- a framed panel with a title; `fill(flow)` lays out its contents; returns the panel
function Flow:panel(title, fill)
  local p = K.get(self.owner, "panel", self.parent)
  p.title:SetText(title)
  K.fitPlate(p)
  p:SetWidth(self.width)
  local inner = K.flow(self.owner, p, 12, (title and title ~= "") and 24 or 12, self.width - 24)
  fill(inner)
  local h = inner.y + 10
  self:gap(title and 14 or 4)
  self:place(p, h)
  self:gap(10)
  return p
end

--- a framed panel standing out from the rest (gold edge): the one box on a screen that matters most right now
function Flow:hot(title, fill)
  local p = self:panel(title, fill)
  paint(p, K.T.hotBg, K.T.hotEdge)
  return p
end

--- a heading for a part of a screen, with a short summary on the right ("To roll out ... 3 items")
function Flow:heading(title, sum)
  local h = K.get(self.owner, "head", self.parent)
  h.text:SetText(title)
  h.right:SetText(sum or "")
  self:place(h, 22, nil, self.width)
  self:gap(4)
  return h
end

--- a line saying how things stand: tone "ok" / "warn" / "bad"; link = { label, click } on the right
function Flow:strip(text, tone, link)
  local t = TONES[tone] or TONES.ok
  local f = K.get(self.owner, "strip", self.parent)
  f:SetBackdropColor(K.bg(t.bg[1], t.bg[2], t.bg[3], t.bg[4]))
  f:SetBackdropBorderColor(K.edge(t.edge[1], t.edge[2], t.edge[3], t.edge[4]))
  f.dot:SetTexture(t.dot)
  local right = 10
  if link then
    local b = K.button(self.owner, self.parent, "link", link[1])
    b:SetScript("OnClick", link[2])
    right = b:GetWidth() + 16
    b:SetPoint("TOPRIGHT", self.parent, "TOPLEFT", self.x + self.width - 8, -(self.y + 4))
    b:SetFrameLevel(f:GetFrameLevel() + 2)
  end
  f.text:SetWidth(self.width - 26 - right)
  f.text:SetText(text)
  self:place(f, max(28, f.text:GetStringHeight() + 16), nil, self.width)
  self:gap(8)
  return f
end

--- a row with its label in a column of its own, so every row's choices start at the same line; fill(flow) lays out the
--- choices to the right of it. opts.lw: the label column's width
function Flow:row(label, fill, opts)
  local lw = (opts and opts.lw) or 104
  local l = K.get(self.owner, "label", self.parent)
  l.text:SetFontObject("GameFontNormalSmall")
  l.text:SetTextColor(K.rgb(K.GOLD))
  l.text:SetWordWrap(true)
  l.text:SetText(label or "")
  l:SetWidth(lw - 8)
  l.text:SetWidth(lw - 8)
  local lh = max(l.text:GetStringHeight(), 1)
  l:SetHeight(lh + 2)
  l:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, -(self.y + 4))
  local inner = K.flow(self.owner, self.parent, self.x + lw, self.y, self.width - lw)
  fill(inner)
  self.y = max(inner.y, self.y + lh + 10)
  return self
end

--- a short line of text with links after it on the same line ("Ann +1, Bob +1   Change"); links = { { label, click, danger } }.
--- Text too long for one line wraps, and the links go under it
function Flow:inline(text, links)
  local l = K.get(self.owner, "label", self.parent)
  l.text:SetFontObject("GameFontHighlightSmall")
  l.text:SetJustifyV("MIDDLE")
  l.text:SetWordWrap(false)
  l.text:SetText(text or "")
  local tw = l.text:GetStringWidth() + 2
  local made, total = {}, 0
  for _, c in ipairs(links or {}) do if c then
    local b = K.button(self.owner, self.parent, "link", c[1], nil, nil, c[3])
    b:SetScript("OnClick", c[2])
    made[#made + 1] = b
    total = total + b:GetWidth() + 12
  end end
  if tw + total <= self.width then
    l:SetSize(tw, 20) l.text:SetWidth(tw)
    l:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, -self.y)
    local x = self.x + tw + 12
    for _, b in ipairs(made) do b:SetPoint("TOPLEFT", self.parent, "TOPLEFT", x, -self.y) x = x + b:GetWidth() + 12 end
    self.y = self.y + 22
  else
    l.text:SetWordWrap(true)
    l.text:SetJustifyV("TOP")
    l:SetWidth(self.width) l.text:SetWidth(self.width)
    local h = l.text:GetStringHeight() + 2
    l:SetHeight(h)
    l:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, -self.y)
    self.y = self.y + h + 2
    local x = self.x
    for _, b in ipairs(made) do b:SetPoint("TOPLEFT", self.parent, "TOPLEFT", x, -self.y) x = x + b:GetWidth() + 12 end
    self.y = self.y + (#made > 0 and 22 or 2)
  end
  return self
end

--- a row for a person: name, the line under it, words in the middle (wrapping), and maybe a link on the right
--- ({ label, click }). Returns the row (click it for more)
function Flow:entry(name, sub, body, link, lw)
  lw = lw or 112
  local b = K.get(self.owner, "entry", self.parent)
  b:SetWidth(self.width)
  b.name:SetText(name)
  b.name:SetWidth(lw - 12)
  b.sub:SetText(sub or "")
  b.sub:SetWidth(lw - 12)
  local right = 8
  if link then
    local l = K.button(self.owner, self.parent, "link", link[1])
    l:SetScript("OnClick", link[2])
    l:SetFrameLevel(b:GetFrameLevel() + 3)
    l:SetPoint("TOPRIGHT", self.parent, "TOPLEFT", self.x + self.width - 8, -(self.y + 6))
    right = l:GetWidth() + 18
  end
  b.body:ClearAllPoints()
  b.body:SetPoint("TOPLEFT", lw, -8)
  b.body:SetWidth(self.width - lw - right)
  b.body:SetText(body or "")
  local h = max(8 + b.name:GetStringHeight() + 3 + ((sub and sub ~= "") and b.sub:GetStringHeight() or 0) + 8, 8 + b.body:GetStringHeight() + 8, 34)
  self:place(b, h)
  self:gap(2)
  return b
end

--- side by side: fills (a list of functions) each lay out one column; the panels they return are made as tall as the
--- tallest, so the columns line up
function Flow:cols(fills, gap)
  gap = gap or 10
  local n = #fills
  local w = floor((self.width - gap * (n - 1)) / n)
  local bottom, made = self.y, {}
  for i, fill in ipairs(fills) do
    local col = K.flow(self.owner, self.parent, self.x + (i - 1) * (w + gap), self.y, w)
    local p = fill(col)
    if p then made[#made + 1] = { p, col } end
    bottom = max(bottom, col.y)
  end
  -- (a panel's flow ends 10 below it: stretch each to the lowest)
  for _, m in ipairs(made) do m[1]:SetHeight(m[1]:GetHeight() + (bottom - m[2].y)) end
  self.y = bottom
  return self
end

--- small boxes of facts, two to a row: list = { { heading, words }, ... }
function Flow:facts(list)
  local w = floor((self.width - 8) / 2)
  local i, rowTop, rowH, made = 0, self.y, 0, {}
  for _, x in ipairs(list) do if x then
    i = i + 1
    local f = K.get(self.owner, "fact", self.parent)
    f.k:SetText(x[1])
    f.v:SetWidth(w - 18)
    f.v:SetText(x[2])
    local h = 8 + f.k:GetStringHeight() + 3 + f.v:GetStringHeight() + 9
    f:SetWidth(w)
    local col = (i - 1) % 2
    if col == 0 and i > 1 then rowTop = rowTop + rowH + 8 rowH = 0 made = {} end
    f:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x + col * (w + 8), -rowTop)
    made[#made + 1] = f
    rowH = max(rowH, h)
    for _, g in ipairs(made) do g:SetHeight(rowH) end
  end end
  self.y = rowTop + rowH + 8
  return self
end

--- a row of chips (or other fixed-size buttons) that wraps onto more lines; `false` in the list is skipped
function Flow:chips(list, opts)
  opts = opts or {}
  local x, rowH = 0, 0
  local lineY = self.y
  for _, c in ipairs(list) do if c then
    local b
    if c.plain then
      b = K.get(self.owner, "label", self.parent)
      b.text:SetFontObject("GameFontNormalSmall")
      b.text:SetTextColor(K.rgb(K.GOLD))
      b.text:SetJustifyV("MIDDLE")
      b.text:SetText(c.label)
      b:SetSize(c.width or (b.text:GetStringWidth() + 4), 20)
      b.text:SetWordWrap(not c.width)
    elseif c.label == "x" then
      b = K.get(self.owner, "x", self.parent)
    elseif c.tick then
      b = K.get(self.owner, "tick", self.parent)
      K.setTick(b, c.label, c.on)
      if c.width then b:SetWidth(c.width) end
    else
      b = K.get(self.owner, "chip", self.parent)
      K.setChip(b, c.label, c.on)
      if c.width then b:SetWidth(c.width) end
    end
    -- (an x's art has a margin: it takes the room of the square you see, 20 by 20)
    local w = b._kind == "x" and 20 or b:GetWidth()
    if x > 0 and x + w > self.width then x = 0 lineY = lineY + rowH + 4 rowH = 0 end
    b:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x + x - (b._kind == "x" and 5 or 0), -lineY + (b._kind == "x" and 5 or 0))
    if not c.plain then b:SetScript("OnClick", c.click) end
    if c.tip then tooltipOn(b, function(tt) tt:SetText(c.tip, 1, 1, 1, 1, true) end) end
    x = x + w + 4
    rowH = max(rowH, b._kind == "x" and 20 or b:GetHeight())
  end end
  self.y = lineY + rowH + (opts.gap or 6)
  return self
end

--- red panel buttons in a row, right-aligned (or centered, or left). A row too wide for the space goes on over more
--- lines, each aligned the same way, so no button runs past the edge (one wider than the space is cut to fit)
--- Each is { label, click, style = "quiet" / "link" (else the red main button), danger (a red link), disabled, width, tip };
--- `false` / nil in the list are skipped.
function Flow:buttons(list, align)
  local widths, made = {}, {}
  local packed = {}
  for i = 1, table.maxn(list) do if list[i] then packed[#packed + 1] = list[i] end end
  list = packed
  for i, c in ipairs(list) do
    local b = K.button(self.owner, self.parent, c.style, c.label, c.style == "quiet" and 60 or nil, self.width, c.danger)
    if c.width then b:SetWidth(min(self.width, c.width)) end
    widths[i] = b:GetWidth()
    if c.disabled then
      b:Disable()
      if b.text then b.text:SetTextColor(0.5, 0.5, 0.5) end
    end
    b:SetScript("OnClick", c.click)
    if c.tip then tooltipOn(b, function(tt) tt:SetText(c.tip, 1, 1, 1, 1, true) end) end
    made[i] = b
  end
  -- lines: as many buttons as fit in each
  local lines, line, used = {}, {}, 0
  for i in ipairs(made) do
    local need = widths[i] + (#line > 0 and 6 or 0)
    if #line > 0 and used + need > self.width then lines[#lines + 1] = { line, used } line, used = {}, 0 need = widths[i] end
    line[#line + 1] = i
    used = used + need
  end
  if #line > 0 then lines[#lines + 1] = { line, used } end
  for n, l in ipairs(lines) do
    local total = l[2]
    local x = align == "center" and floor((self.width - total) / 2) or align == "left" and 0 or self.width - total
    for _, i in ipairs(l[1]) do
      made[i]:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x + x, -(self.y + floor((24 - made[i]:GetHeight()) / 2)))
      x = x + widths[i] + 6
    end
    self.y = self.y + 24 + (n < #lines and 4 or 6)
  end
  return made
end

--- label / value lines
function Flow:kv(pairsList, opts)
  for _, pr in ipairs(pairsList) do
    if pr then
      local f = K.get(self.owner, "kv", self.parent)
      if opts and opts.small then f.k:SetFontObject("GameFontNormalSmall") f.v:SetFontObject("GameFontHighlightSmall") end
      f.k:SetText(pr[1])
      f.v:SetText(pr[2])
      if pr[3] then f.v:SetTextColor(pr[3][1], pr[3][2], pr[3][3]) end
      if pr[4] then f.k:SetTextColor(pr[4][1], pr[4][2], pr[4][3]) end
      f:SetWidth(self.width - ((opts and opts.indent) or 0))
      self:place(f, (opts and opts.small) and 14 or 17, opts and opts.indent)
    end
  end
  return self
end

---------------------------------------------------------------------- scroll areas
--- a scroll frame with a child to draw into; the mouse wheel scrolls it and a thin bar shows where you are
function K.scroller(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(10, 10)
  sf:SetScrollChild(child)
  sf:EnableMouseWheel(true)
  local track = sf:CreateTexture(nil, "OVERLAY")
  track:SetColorTexture(1, 1, 1, 0.06)
  track:SetPoint("TOPRIGHT", 0, 0)
  track:SetPoint("BOTTOMRIGHT", 0, 0)
  track:SetWidth(4)
  local thumb = sf:CreateTexture(nil, "OVERLAY", nil, 1)
  thumb:SetColorTexture(1, 0.82, 0, 0.55)
  thumb:SetWidth(4)
  sf.child, sf.track, sf.thumb = child, track, thumb
  local function update()
    local range = sf:GetVerticalScrollRange()
    local hgt = sf:GetHeight()
    if range <= 0 or hgt <= 0 then thumb:Hide() track:Hide() return end
    thumb:Show() track:Show()
    local th = max(20, hgt * hgt / (hgt + range))
    thumb:SetHeight(th)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 0, -(hgt - th) * (sf:GetVerticalScroll() / range))
  end
  sf.updateBar = update
  sf:SetScript("OnMouseWheel", function(self, delta)
    local v = self:GetVerticalScroll() - delta * 48
    v = max(0, min(v, self:GetVerticalScrollRange()))
    self:SetVerticalScroll(v)
    update()
  end)
  sf:SetScript("OnVerticalScroll", function() update() end)
  sf:SetScript("OnSizeChanged", function(self, w) child:SetWidth(w) update() end)
  --- sets the content height, keeps the scroll position when it can
  function sf:setContentHeight(h, keep)
    child:SetHeight(max(h, 1))
    child:SetWidth(self:GetWidth())
    self:UpdateScrollChildRect()
    local v = keep and min(self:GetVerticalScroll(), self:GetVerticalScrollRange()) or 0
    self:SetVerticalScroll(max(0, v))
    update()
  end
  return sf
end
