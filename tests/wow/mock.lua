-- A strict stand-in for the parts of the WoW 2.5 (TBC Anniversary) client API the addon uses, so the UI
-- can be loaded, clicked through and drawn outside the game. (Shared with TBCrushCalc's tests. Each
-- dofile() of this file is a separate client, which tests/wow/server.lua uses to run a whole raid.)
--  * Every widget type only has the methods the real client has (from the widget API reference); calling
--    anything else is an error, as it would be in game.
--  * Reading a global the client doesn't have is an error (except a short list addons may probe).
--  * Frames are laid out from their anchors like the client does, and render() returns everything visible
--    (frames with backdrops, textures, text) with screen positions, for tools/render.mjs to draw.
local M = {}

local SCREEN_W, SCREEN_H = 1280, 800
M.SCREEN_W, M.SCREEN_H = SCREEN_W, SCREEN_H

local created = 0
local allFrames = {}
local named = {}
M.errors = {}
M.events = {}

local function fail(msg) error(msg, 3) end
local function plain(t) return ((t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "  ")) end

---------------------------------------------------------------------- fonts
local FONTS = {
  GameFontNormal = { size = 12, color = { 1, 0.82, 0 } },
  GameFontNormalSmall = { size = 10, color = { 1, 0.82, 0 } },
  GameFontNormalLarge = { size = 16, color = { 1, 0.82, 0 } },
  GameFontNormalHuge = { size = 20, color = { 1, 0.82, 0 } },
  GameFontHighlight = { size = 12, color = { 1, 1, 1 } },
  GameFontHighlightSmall = { size = 10, color = { 1, 1, 1 } },
  GameFontHighlightLarge = { size = 16, color = { 1, 1, 1 } },
  GameFontHighlightMedium = { size = 14, color = { 1, 1, 1 } },
  GameFontDisable = { size = 12, color = { 0.5, 0.5, 0.5 } },
  GameFontDisableSmall = { size = 10, color = { 0.5, 0.5, 0.5 } },
  GameFontGreen = { size = 12, color = { 0.1, 1, 0.1 } },
  GameFontRed = { size = 12, color = { 1, 0.1, 0.1 } },
  GameFontWhite = { size = 12, color = { 1, 1, 1 } },
  GameFontBlack = { size = 12, color = { 0, 0, 0 } },
  NumberFontNormal = { size = 14, color = { 1, 1, 1 } },
  NumberFontNormalSmall = { size = 12, color = { 1, 1, 1 } },
  ChatFontNormal = { size = 14, color = { 1, 1, 1 } },
  QuestTitleFont = { size = 18, color = { 1, 0.82, 0 } },
  SystemFont_Shadow_Small = { size = 10, color = { 1, 1, 1 } },
}
local fontObjects = {}
local FontMethods = {}
function FontMethods:GetFont() return "Fonts\\FRIZQT__.TTF", self._size, "" end
function FontMethods:GetTextColor() return unpack(self._color) end
function FontMethods:GetName() return self._name end
function FontMethods:IsObjectType(t) return t == "Font" end
for name, f in pairs(FONTS) do
  fontObjects[name] = setmetatable({ _name = name, _size = f.size, _color = f.color }, { __index = function(_, k)
    return FontMethods[k] or fail("Font has no method " .. tostring(k))
  end })
end

---------------------------------------------------------------------- widget methods
local methods = {}
local function define(kind, base, list) methods[kind] = { base = base, m = list } end

local function checkPoint(p)
  local ok = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 1, CENTER = 1, RIGHT = 1, BOTTOMLEFT = 1, BOTTOM = 1, BOTTOMRIGHT = 1 }
  if not ok[p] then fail("bad anchor point " .. tostring(p)) end
end

local Region = {}
function Region:SetPoint(point, rel, relPoint, x, y)
  checkPoint(point)
  if type(rel) == "number" then rel, relPoint, x, y = nil, nil, rel, relPoint end
  if type(rel) == "string" then rel = named[rel] or fail("no frame named " .. rel) end
  if rel == nil then rel = self._parent or M.UIParent end
  relPoint = relPoint or point
  if type(relPoint) == "number" then x, y, relPoint = relPoint, x, point end
  checkPoint(relPoint)
  if rel == self then fail("anchored to itself") end
  for i, p in ipairs(self._points) do if p.point == point then table.remove(self._points, i) break end end
  table.insert(self._points, { point = point, rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 })
  M.invalidate()
end
-- (a frame moved or resized: where everything is gets worked out again, as the game does)
function Region:ClearAllPoints() self._points = {} M.invalidate() end
function Region:SetAllPoints(rel)
  rel = rel or self._parent
  self._points = {}
  self:SetPoint("TOPLEFT", rel, "TOPLEFT", 0, 0)
  self:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0)
end
function Region:GetNumPoints() return #self._points end
function Region:GetPoint(i)
  local p = self._points[i or 1]
  if not p then return nil end
  return p.point, p.rel, p.relPoint, p.x, p.y
end
function Region:SetSize(w, h) self._w, self._h = w, h M.invalidate() end
function Region:SetWidth(w) self._w = w M.invalidate() end
function Region:SetHeight(h) self._h = h M.invalidate() end
function Region:GetSize() return self:GetWidth(), self:GetHeight() end
function Region:GetWidth() local r = M.rect(self) return r and (r.r - r.l) or (self._w or 0) end
function Region:GetHeight() local r = M.rect(self) return r and (r.t - r.b) or (self._h or 0) end
function Region:GetLeft() local r = M.rect(self) return r and r.l end
function Region:GetRight() local r = M.rect(self) return r and r.r end
function Region:GetTop() local r = M.rect(self) return r and r.t end
function Region:GetBottom() local r = M.rect(self) return r and r.b end
function Region:GetCenter() local r = M.rect(self) if r then return (r.l + r.r) / 2, (r.t + r.b) / 2 end end
function Region:Show()
  local was = self._shown
  self._shown = true
  if not was and self._scripts and self._scripts.OnShow then self._scripts.OnShow(self) end
end
function Region:Hide()
  local was = self._shown
  self._shown = false
  if was and self._scripts and self._scripts.OnHide then self._scripts.OnHide(self) end
end
function Region:SetShown(v) if v then self:Show() else self:Hide() end end
function Region:IsShown() return self._shown end
function Region:IsVisible()
  local f = self
  while f do if not f._shown then return false end f = f._parent end
  return true
end
function Region:SetAlpha(a) self._alpha = a end
function Region:GetAlpha() return self._alpha or 1 end
function Region:GetParent() return self._parent end
function Region:GetName() return self._name end
function Region:GetObjectType() return self._type end
function Region:IsObjectType(t) return self._type == t or (t == "Frame" and self._isFrame) or t == "Region" end

local Frame = setmetatable({}, { __index = Region })
function Frame:SetParent(p)
  if self._parent then
    local kids = self._parent._children
    for i, c in ipairs(kids) do if c == self then table.remove(kids, i) break end end
  end
  self._parent = p
  if p then table.insert(p._children, self) end
end
function Frame:SetFrameStrata(s) self._strata = s end
function Frame:GetFrameStrata() return self._strata or (self._parent and self._parent:GetFrameStrata()) or "MEDIUM" end
function Frame:SetFrameLevel(l) self._level = l end
function Frame:GetFrameLevel() return self._level or ((self._parent and self._parent:GetFrameLevel() or 0) + 1) end
function Frame:SetToplevel() end
function Frame:Raise() self._raised = (M._raise or 0) + 1 M._raise = self._raised end
function Frame:EnableMouse(v) self._mouse = v end
function Frame:IsMouseEnabled() return self._mouse end
function Frame:EnableMouseWheel(v) self._wheel = v end
function Frame:EnableKeyboard(v) self._keyboard = v end
function Frame:SetPropagateKeyboardInput() end
function Frame:SetMovable(v) self._movable = v end
function Frame:SetResizable() end
function Frame:SetClampedToScreen() end
function Frame:SetUserPlaced() end
function Frame:RegisterForDrag() end
function Frame:StartMoving() end
function Frame:StopMovingOrSizing() end
function Frame:SetHitRectInsets() end
function Frame:SetScale(s) self._scale = s end
function Frame:GetScale() return self._scale or 1 end
function Frame:GetEffectiveScale() return self._scale or 1 end
function Frame:SetID(id) self._id = id end
function Frame:GetID() return self._id or 0 end
function Frame:IsMouseOver() return false end
function Frame:SetClipsChildren(v) self._clips = v end
local SCRIPTS = {
  OnShow = 1, OnHide = 1, OnEvent = 1, OnUpdate = 1, OnClick = 1, OnEnter = 1, OnLeave = 1, OnMouseDown = 1, OnMouseUp = 1,
  OnMouseWheel = 1, OnDragStart = 1, OnDragStop = 1, OnTextChanged = 1, OnEnterPressed = 1, OnEscapePressed = 1,
  OnEditFocusGained = 1, OnEditFocusLost = 1, OnSizeChanged = 1, OnValueChanged = 1, OnKeyDown = 1, OnVerticalScroll = 1,
  OnScrollRangeChanged = 1, PostClick = 1, PreClick = 1, OnDoubleClick = 1, OnTabPressed = 1, OnChar = 1,
}
function Frame:SetScript(name, fn)
  if not SCRIPTS[name] then fail("unknown script " .. tostring(name)) end
  if not self:HasScript(name) then fail(self._type .. " has no " .. name .. " script") end
  self._scripts[name] = fn
end
function Frame:GetScript(name) return self._scripts[name] end
function Frame:HookScript(name, fn)
  local old = self._scripts[name]
  self._scripts[name] = function(...) if old then old(...) end fn(...) end
end
function Frame:HasScript(name)
  if name == "OnClick" or name == "PreClick" or name == "PostClick" or name == "OnDoubleClick" then return self._clickable == true end
  if name == "OnTextChanged" or name == "OnEnterPressed" or name == "OnEscapePressed" or name == "OnEditFocusGained" or name == "OnEditFocusLost" then return self._type == "EditBox" end
  if name == "OnValueChanged" then return self._type == "Slider" end
  if name == "OnVerticalScroll" or name == "OnScrollRangeChanged" then return self._type == "ScrollFrame" end
  return SCRIPTS[name] ~= nil
end
-- events the TBC client doesn't have (later expansions' ones): registering one is an error in the game, so here too
-- (tools/check_api.lua checks every event the addon registers against the client's own list)
M.MISSING_EVENTS = { CONFIRM_DISENCHANT_ROLL = true }
function Frame:RegisterEvent(e)
  if M.MISSING_EVENTS[e] then error(('Frame:RegisterEvent(): Attempt to register unknown event "%s"'):format(tostring(e)), 2) end
  self._events[e] = true M.events[e] = M.events[e] or {} M.events[e][self] = true
end
function Frame:UnregisterEvent(e) self._events[e] = nil if M.events[e] then M.events[e][self] = nil end end
function Frame:UnregisterAllEvents() for e in pairs(self._events) do self:UnregisterEvent(e) end end
function Frame:IsEventRegistered(e) return self._events[e] == true end
function Frame:GetChildren() return unpack(self._children) end
function Frame:GetNumChildren() return #self._children end
function Frame:GetRegions() return unpack(self._regions) end
function Frame:CreateTexture(name, layer, template, sub)
  local t = M.newRegion("Texture", self, name)
  t._layer = layer or "ARTWORK"
  t._sublevel = sub or 0
  return t
end
function Frame:CreateFontString(name, layer, font)
  local f = M.newRegion("FontString", self, name)
  f._layer = layer or "ARTWORK"
  if font then f:SetFontObject(font) end
  return f
end
-- BackdropTemplate
function Frame:SetBackdrop(b)
  if not self._backdropOk then fail("SetBackdrop needs BackdropTemplate in 2.5") end
  self._backdrop = b
end
function Frame:SetBackdropColor(r, g, b, a) self._bdColor = { r, g, b, a or 1 } end
function Frame:SetBackdropBorderColor(r, g, b, a) self._bdBorder = { r, g, b, a or 1 } end
function Frame:ApplyBackdrop() end

define("Frame", nil, Frame)

local Button = setmetatable({}, { __index = Frame })
function Button:SetText(t)
  self._text = t
  if not self._fs then
    self._fs = self:CreateFontString(nil, "OVERLAY")
    self._fs:SetFontObject(self._normalFont or "GameFontNormal")
    self._fs:SetPoint("CENTER")
  end
  self._fs:SetText(t)
end
function Button:GetText() return self._text end
function Button:GetFontString() return self._fs end
function Button:SetFontString(fs) self._fs = fs end
function Button:SetNormalFontObject(f) self._normalFont = f if self._fs then self._fs:SetFontObject(f) end end
function Button:SetHighlightFontObject() end
function Button:SetDisabledFontObject(f) self._disabledFont = f end
function Button:SetNormalTexture(t) self._normalTex = t end
function Button:SetPushedTexture(t) self._pushedTex = t end
function Button:SetHighlightTexture(t, mode) self._hlTex = t end
function Button:SetDisabledTexture(t) self._disabledTex = t end
function Button:GetNormalTexture() return nil end
function Button:GetHighlightTexture() return nil end
function Button:RegisterForClicks() end
function Button:Enable() self._enabled = true end
function Button:Disable() self._enabled = false end
function Button:SetEnabled(v) self._enabled = v and true or false end
function Button:IsEnabled() return self._enabled ~= false end
function Button:Click(button)
  if self._enabled == false then return end
  local fn = self._scripts.OnClick
  if fn then fn(self, button or "LeftButton", false) end
end
function Button:SetMotionScriptsWhileDisabled(v) self._motionDisabled = v end
function Button:GetMotionScriptsWhileDisabled() return self._motionDisabled end
function Button:LockHighlight() end
function Button:UnlockHighlight() end
function Button:SetButtonState() end
define("Button", "Frame", Button)
define("CheckButton", "Button", {
  SetChecked = function(self, v) self._checked = v and true or false end,
  GetChecked = function(self) return self._checked end,
  SetCheckedTexture = function() end,
})

local EditBox = setmetatable({}, { __index = Frame })
-- focus, highlight and the cursor behave like the game's: SetFocus fires OnEditFocusGained (where
-- InputBoxTemplate highlights everything), a key typed over a highlight replaces it, hiding drops focus
function EditBox:SetText(t) self._text = t and tostring(t) or "" self._sel = nil self._cursor = #self._text
  if self._scripts.OnTextChanged then self._scripts.OnTextChanged(self, false) end end
function EditBox:GetText() return self._text or "" end
function EditBox:SetAutoFocus(v) self._autofocus = v end
function EditBox:SetFocus()
  if M.focus == self then return end
  local old = M.focus
  if old then old:ClearFocus() end
  M.focus = self
  if self._scripts.OnEditFocusGained then self._scripts.OnEditFocusGained(self) end
end
function EditBox:ClearFocus()
  if M.focus ~= self then return end
  M.focus = nil
  if self._scripts.OnEditFocusLost then self._scripts.OnEditFocusLost(self) end
end
function EditBox:HasFocus() return M.focus == self end
function EditBox:HighlightText(a, b)
  local n = #self:GetText()
  a, b = a or 0, (b == nil or b == -1) and n or b
  if a > n then a = n end
  if b > n then b = n end
  self._sel = a < b and { a, b } or nil
end
function EditBox:SetMultiLine(v) self._multi = v end
function EditBox:SetMaxLetters(n) self._max = n end
function EditBox:SetFontObject(f) self._font = f end
function EditBox:SetTextInsets() end
function EditBox:SetJustifyH() end
function EditBox:SetCursorPosition(n) self._cursor = math.max(0, math.min(n or 0, #self:GetText())) end
function EditBox:GetCursorPosition() return self._cursor or #self:GetText() end
function EditBox:SetNumeric() end
function EditBox:Insert(t) self:SetText(self:GetText() .. t) end
function EditBox:SetTextColor(r, g, b) self._color = { r, g, b } end
function EditBox:Hide() self:ClearFocus() Region.Hide(self) end
define("EditBox", "Frame", EditBox)

local ScrollFrame = setmetatable({}, { __index = Frame })
function ScrollFrame:SetScrollChild(c) self._child = c c._scrollParent = self end
function ScrollFrame:GetScrollChild() return self._child end
function ScrollFrame:SetVerticalScroll(v) self._vscroll = v if self._scripts.OnVerticalScroll then self._scripts.OnVerticalScroll(self, v) end end
function ScrollFrame:GetVerticalScroll() return self._vscroll or 0 end
function ScrollFrame:GetVerticalScrollRange()
  if not self._child then return 0 end
  local h = self._child._h or 0
  local mine = self:GetHeight()
  return math.max(0, h - mine)
end
function ScrollFrame:SetHorizontalScroll() end
function ScrollFrame:UpdateScrollChildRect() end
define("ScrollFrame", "Frame", ScrollFrame)

local Slider = setmetatable({}, { __index = Frame })
function Slider:SetMinMaxValues(a, b) self._min, self._max = a, b end
function Slider:GetMinMaxValues() return self._min or 0, self._max or 0 end
function Slider:SetValue(v) self._value = v if self._scripts.OnValueChanged then self._scripts.OnValueChanged(self, v, true) end end
function Slider:GetValue() return self._value or 0 end
function Slider:SetValueStep(v) self._step = v end
function Slider:SetObeyStepOnDrag() end
function Slider:SetOrientation(o) self._orient = o end
function Slider:SetThumbTexture(t) self._thumb = t end
function Slider:GetThumbTexture() return nil end
function Slider:Enable() end
function Slider:Disable() end
define("Slider", "Frame", Slider)

local Model = setmetatable({}, { __index = Frame })
for _, k in ipairs({ "SetUnit", "SetCamDistanceScale", "SetPosition", "SetFacing", "SetRotation", "RefreshUnit", "SetPortraitZoom", "SetModelScale", "ClearModel" }) do
  Model[k] = function() end
end
define("PlayerModel", "Frame", Model)
local Dress = {}
for _, k in ipairs({ "Undress", "Dress", "UndressSlot" }) do Dress[k] = function() end end
function Dress:TryOn(link) self._worn = self._worn or {} table.insert(self._worn, link) end
function Dress:Undress() self._worn = {} end
define("DressUpModel", "PlayerModel", Dress)

local GameTooltipM = setmetatable({}, { __index = Frame })
--- the test can describe links: M.describeLink(link) -> { { text, r, g, b }, ... }
local function linkLines(l)
  if M.describeLink then return M.describeLink(l) or { { "link " .. tostring(l) } } end
  return { { "link " .. tostring(l) } }
end
function GameTooltipM:SetOwner(o) self._owner = o self._lines = {} self._minW = 0 end
function GameTooltipM:SetHyperlink(l)
  self._lines = linkLines(l)
  -- the game runs tooltip post-calls (TooltipDataProcessor) with the item's data
  local id = tonumber(tostring(l):match("item:(%d+)"))
  if id then for _, fn in ipairs(M.tooltipCalls or {}) do fn(self, { type = 0, id = id }) end end
end
function GameTooltipM:SetText(t, r, g, b) self._lines = { { t, r or 1, g or 0.82, b or 0 } } end
function GameTooltipM:AddLine(t, r, g, b) table.insert(self._lines, { t, r or 1, g or 0.82, b or 0 }) end
function GameTooltipM:AddDoubleLine(a, b) table.insert(self._lines, { a .. "    " .. b, 1, 1, 1 }) end
function GameTooltipM:ClearLines() self._lines = {} end
function GameTooltipM:SetSpellByID(id) self._lines = { { "spell " .. id, 1, 1, 1 } } end
-- a named tooltip made from GameTooltipTemplate has its lines as <name>TextLeft1, 2, ... like the game's
function GameTooltipM:NumLines()
  if self._name and self._fromTemplate then
    self._left = self._left or {}
    for i, l in ipairs(self._lines) do
      local fs = self._left[i]
      if not fs then
        fs = M.newRegion("FontString", self, self._name .. "TextLeft" .. i)
        fs:Hide()
        self._left[i] = fs
      end
      fs:SetText(l[1])
      fs:SetTextColor(l[2], l[3], l[4])
    end
    for i = #self._lines + 1, #self._left do self._left[i]:SetText("") end
  end
  return #self._lines
end
function GameTooltipM:SetMinimumWidth(w) self._minW = w end
function GameTooltipM:SetInventoryItem(unit, slot)
  self._lines = M.inventoryLines and M.inventoryLines(unit, slot) or { { "inventory", 1, 1, 1 } }
  return true
end
function GameTooltipM:Show()
  local w = self._minW or 0
  for _, l in ipairs(self._lines or {}) do w = math.max(w, #plain(l[1]) * 12 * 0.55 + 20) end
  self._w = math.min(w, 400)
  local h = 12
  for _, l in ipairs(self._lines or {}) do h = h + 14 * math.max(1, math.ceil(#plain(l[1]) * 12 * 0.55 / math.max(1, self._w - 20))) end
  self._h = h
  Region.Show(self)
end
define("GameTooltip", "Frame", GameTooltipM)

-- textures and font strings
local Texture = setmetatable({}, { __index = Region })
function Texture:SetTexture(t) self._tex = t self._color = nil self._atlas = nil end
function Texture:SetAtlas(a, useSize) if type(a) ~= "string" then fail("SetAtlas needs a name") end self._atlas = a self._tex = nil self._color = nil end
function Texture:GetAtlas() return self._atlas end
function Texture:GetTexture() return self._tex end
function Texture:SetColorTexture(r, g, b, a) self._color = { r, g, b, a or 1 } self._tex = nil end
function Texture:SetTexCoord(...) self._coord = { ... } end
function Texture:SetVertexColor(r, g, b, a) self._vertex = { r, g, b, a or 1 } end
function Texture:SetDesaturated(v) self._desat = v end
function Texture:SetBlendMode(m) self._blend = m end
function Texture:SetDrawLayer(l, s) self._layer = l self._sublevel = s or 0 end
function Texture:GetDrawLayer() return self._layer, self._sublevel end
function Texture:SetRotation(r) self._rot = r end
function Texture:SetHorizTile() end
function Texture:SetVertTile() end
function Texture:SetMask() end
define("Texture", nil, Texture)

local FontString = setmetatable({}, { __index = Region })
function FontString:SetText(t) self._text = t and tostring(t) or "" end
function FontString:GetText() return self._text end
function FontString:SetFormattedText(f, ...) self._text = f:format(...) end
function FontString:SetFontObject(f)
  if type(f) == "string" then f = fontObjects[f] or fail("no font object " .. f) end
  if not f or not f._size then fail("bad font object") end
  self._font = f
end
function FontString:GetFontObject() return self._font end
function FontString:SetFont(path, size, flags) self._fontSize = size self._fontPath = path end
function FontString:GetFont() return self._fontPath or "Fonts\\FRIZQT__.TTF", self._fontSize or (self._font and self._font._size) or 12 end
function FontString:SetTextColor(r, g, b, a) self._color = { r, g, b, a or 1 } end
function FontString:GetTextColor() local c = self._color or (self._font and self._font._color) or { 1, 1, 1 } return c[1], c[2], c[3] end
function FontString:SetJustifyH(j) self._justifyH = j end
function FontString:SetJustifyV(j) self._justifyV = j end
function FontString:SetWordWrap(v) self._wrap = v end
function FontString:SetNonSpaceWrap() end
function FontString:SetMaxLines(n) self._maxLines = n end
function FontString:SetShadowOffset() end
function FontString:SetShadowColor() end
function FontString:SetSpacing(s) self._spacing = s end
function FontString:SetIndentedWordWrap() end
--- text sizes: an estimate of Friz Quadrata's widths (about 0.55 em per character)
M.plain = plain
local function size(fs) return fs._fontSize or (fs._font and fs._font._size) or 12 end
function FontString:GetStringWidth()
  local w = 0
  for line in (plain(self._text) .. "\n"):gmatch("(.-)\n") do w = math.max(w, #line * size(self) * 0.55) end
  return w
end
function FontString:GetUnboundedStringWidth() return self:GetStringWidth() end
function FontString:GetNumLines()
  local width = self._w or (M.rect(self) and (M.rect(self).r - M.rect(self).l))
  local n = 0
  for line in (plain(self._text) .. "\n"):gmatch("(.-)\n") do
    local lw = #line * size(self) * 0.55
    n = n + ((width and width > 0 and self._wrap ~= false) and math.max(1, math.ceil(lw / width)) or 1)
  end
  if self._maxLines and self._maxLines > 0 then n = math.min(n, self._maxLines) end
  return n
end
function FontString:GetStringHeight()
  if (self._text or "") == "" then return 0 end
  return self:GetNumLines() * (size(self) + (self._spacing or 0) + 1)
end
function FontString:IsTruncated() return false end
define("FontString", nil, FontString)

---------------------------------------------------------------------- construction
local function lookup(kind, k)
  local d = methods[kind]
  while d do
    local v = d.m[k]
    if v ~= nil then return v end
    d = d.base and methods[d.base]
  end
  return nil
end

local function newObject(kind, parent, name)
  created = created + 1
  local o = { _type = kind, _parent = parent, _points = {}, _shown = true, _children = {}, _regions = {}, _scripts = {}, _events = {}, _order = created, _name = name }
  setmetatable(o, { __index = function(_, k)
    local v = lookup(kind, k)
    -- the client's methods are all CapitalCase; other keys are the addon's own fields (nil until set)
    if v == nil and type(k) == "string" and k:match("^%u") then error(kind .. " has no method " .. tostring(k), 2) end
    return v
  end })
  if name then named[name] = o _G[name] = o end
  return o
end

function M.newRegion(kind, parent, name)
  local o = newObject(kind, parent, name)
  if name and name:find("%$parent") then fail("$parent names need a named parent") end
  table.insert(parent._regions, o)
  return o
end

local TEMPLATES = {
  BackdropTemplate = function(f) f._backdropOk = true end,
  UIPanelButtonTemplate = function(f) f._template = "UIPanelButtonTemplate" f._normalFont = fontObjects.GameFontNormal end,
  UIPanelCloseButton = function(f) f._template = "UIPanelCloseButton" f:SetSize(32, 32) end,
  -- InputBoxScriptTemplate's scripts (SecureUIPanelTemplates.xml)
  InputBoxTemplate = function(f) f._template = "InputBoxTemplate"
    f._scripts.OnEditFocusGained = function(self) self:HighlightText() end
    f._scripts.OnEditFocusLost = function(self) self:HighlightText(0, 0) end
    f._scripts.OnEscapePressed = function(self) self:ClearFocus() end
  end,
  GameTooltipTemplate = function(f) f._fromTemplate = true end,
  UIPanelScrollFrameTemplate = function(f) f._template = "UIPanelScrollFrameTemplate" end,
}

function M.CreateFrame(kind, name, parent, template)
  if not methods[kind] or kind == "Texture" or kind == "FontString" then error("CreateFrame: unknown frame type " .. tostring(kind), 2) end
  local f = newObject(kind, nil, name)
  f._isFrame = true
  f._clickable = (kind == "Button" or kind == "CheckButton")
  if parent then f:SetParent(parent) else f:SetParent(M.UIParent) end
  if template then
    for tname in template:gmatch("[^,%s]+") do
      local fn = TEMPLATES[tname] or error("CreateFrame: unknown template " .. tname, 2)
      fn(f)
    end
  end
  table.insert(allFrames, f)
  return f
end

---------------------------------------------------------------------- layout
local POINTS = {
  TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 }, LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
  BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}
local cache, resolving = nil, {}
function M.invalidate() cache = nil end

--- the region's rectangle in screen coordinates (y up), or nil if it can't be placed
function M.rect(o)
  if o == M.UIParent then return { l = 0, r = SCREEN_W, b = 0, t = SCREEN_H } end
  cache = cache or {}
  if cache[o] ~= nil then return cache[o] or nil end
  if resolving[o] then error("anchor loop", 0) end
  resolving[o] = true
  local xs, ys = {}, {}
  for _, p in ipairs(o._points) do
    local rr = M.rect(p.rel)
    if rr then
      local rp = POINTS[p.relPoint]
      local ax = rr.l + (rr.r - rr.l) * rp[1] + p.x
      local ay = rr.b + (rr.t - rr.b) * rp[2] + p.y
      local mp = POINTS[p.point]
      table.insert(xs, { f = mp[1], v = ax })
      table.insert(ys, { f = mp[2], v = ay })
    end
  end
  local function axis(list, size)
    local lo, hi, mid
    for _, a in ipairs(list) do
      if a.f == 0 then lo = a.v elseif a.f == 1 then hi = a.v else mid = a.v end
    end
    if lo and hi then return lo, hi end
    -- a scroll child's height can be set before its width or vice versa; size may be nil
    size = size or 0
    if lo then return lo, lo + size end
    if hi then return hi - size, hi end
    if mid then return mid - size / 2, mid + size / 2 end
    return nil
  end
  local w, h = o._w, o._h
  if o._type == "FontString" then
    if not w or w == 0 then
      local hasLR = false
      local l, r
      for _, a in ipairs(xs) do if a.f == 0 then l = true elseif a.f == 1 then r = true end end
      hasLR = l and r
      if not hasLR then w = o:GetStringWidth() end
    end
    if not h or h == 0 then
      local saveW = o._w
      if not o._w or o._w == 0 then
        local l, r
        for _, a in ipairs(xs) do if a.f == 0 then l = a.v elseif a.f == 1 then r = a.v end end
        if l and r then o._w = r - l else o._w = w end
      end
      h = o:GetStringHeight()
      o._w = saveW
    end
  end
  local l, r = axis(xs, w)
  local b, t = axis(ys, h)
  local res = false
  if l and b then res = { l = l, r = r, b = b, t = t } end
  if o._scrollParent then
    -- a scroll child: its top-left sits at the scroll frame's top-left, moved by the scroll offset
    local sp = M.rect(o._scrollParent)
    if sp then
      local cw, ch = o._w or (sp.r - sp.l), o._h or 0
      local top = sp.t + (o._scrollParent._vscroll or 0)
      res = { l = sp.l, r = sp.l + cw, t = top, b = top - ch }
    end
  end
  resolving[o] = nil
  cache[o] = res
  return res or nil
end

---------------------------------------------------------------------- rendering
local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

local function intersect(a, b)
  if not a then return b end
  if not b then return a end
  return { l = math.max(a.l, b.l), r = math.min(a.r, b.r), b = math.max(a.b, b.b), t = math.min(a.t, b.t) }
end

--- everything drawn on screen, in draw order, with screen-space boxes (y down, like a web page)
function M.render()
  M.invalidate()
  local ops = {}
  local function box(r) return { x = r.l, y = SCREEN_H - r.t, w = r.r - r.l, h = r.t - r.b } end
  local function visit(f, clip, alpha)
    if not f._shown then return end
    alpha = alpha * (f._alpha or 1)
    local r = M.rect(f)
    local myClip = clip
    if f._type == "ScrollFrame" and r then myClip = intersect(clip, r) end
    if f._clips and r then myClip = intersect(clip, r) end
    -- Raise() lifts a frame with everything in it
    local raised, up = 0, f
    while up do raised = math.max(raised, up._raised or 0) up = up._parent end
    local key = { STRATA[f:GetFrameStrata()] or 3, raised, f:GetFrameLevel() }
    if r and f._type == "GameTooltip" and f._lines then
      table.insert(ops, { kind = "backdrop", key = key, order = f._order, box = box(r), clip = myClip and box(myClip), alpha = alpha,
        bg = "Interface\\Tooltips\\UI-Tooltip-Background", edge = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16, color = { 0, 0, 0, 0.9 }, border = { 0.6, 0.6, 0.6, 1 } })
      local y = r.t - 8
      for i, l in ipairs(f._lines) do
        local lines = math.max(1, math.ceil(#plain(l[1]) * 12 * 0.55 / math.max(1, (r.r - r.l) - 20)))
        table.insert(ops, { kind = "text", key = key, layer = 5, sub = i, order = f._order, alpha = alpha, clip = myClip and box(myClip),
          box = { x = r.l + 10, y = SCREEN_H - y, w = (r.r - r.l) - 20, h = 14 * lines }, text = l[1], size = i == 1 and 14 or 12,
          color = { l[2] or 1, l[3] or 1, l[4] or 1 }, justifyH = "LEFT", justifyV = "TOP", wrap = true })
        y = y - 14 * lines
      end
    end
    if r and f._type == "DressUpModel" then
      table.insert(ops, { kind = "model", key = key, order = f._order, box = box(r), clip = myClip and box(myClip), alpha = alpha * (f._alpha or 1), worn = #(f._worn or {}) })
    end
    if r and f._backdrop then
      table.insert(ops, { kind = "backdrop", key = key, order = f._order, box = box(r), clip = clip and box(clip), alpha = alpha,
        bg = f._backdrop.bgFile, edge = f._backdrop.edgeFile, edgeSize = f._backdrop.edgeSize, color = f._bdColor, border = f._bdBorder, name = f._name })
    end
    if r and f._type == "EditBox" then
      table.insert(ops, { kind = "edit", key = key, order = f._order, box = box(r), clip = clip and box(clip), alpha = alpha, text = f._text or "", template = f._template, multi = f._multi })
    end
    if r and f._type == "Button" and f._template == "UIPanelButtonTemplate" then
      table.insert(ops, { kind = "panelbutton", key = key, order = f._order, box = box(r), clip = clip and box(clip), alpha = alpha, enabled = f._enabled ~= false })
    end
    if r and f._type == "Button" and f._template == "UIPanelCloseButton" then
      table.insert(ops, { kind = "closebutton", key = key, order = f._order, box = box(r), clip = clip and box(clip), alpha = alpha })
    end
    for _, reg in ipairs(f._regions) do
      if reg._shown then
        local rr = M.rect(reg)
        if rr then
          local op = { key = key, layer = LAYERS[reg._layer] or 3, sub = reg._sublevel or 0, order = reg._order, box = box(rr), clip = myClip ~= clip and myClip and box(myClip) or (clip and box(clip)), alpha = alpha * (reg._alpha or 1) }
          if f._type == "ScrollFrame" then op.clip = clip and box(clip) end
          if reg._type == "Texture" then
            op.kind = reg._atlas and "atlas" or "texture"
            op.atlas = reg._atlas
            op.tex, op.color, op.vertex, op.desat, op.coord, op.blend = reg._tex, reg._color, reg._vertex, reg._desat, reg._coord, reg._blend
            if reg._layer ~= "HIGHLIGHT" then table.insert(ops, op) end
          else
            op.kind = "text"
            op.text = reg._text or ""
            op.size = reg._fontSize or (reg._font and reg._font._size) or 12
            op.color = reg._color or (reg._font and reg._font._color) or { 1, 1, 1 }
            op.justifyH, op.justifyV, op.wrap, op.maxLines = reg._justifyH or "CENTER", reg._justifyV or "MIDDLE", reg._wrap ~= false, reg._maxLines
            if op.text ~= "" then table.insert(ops, op) end
          end
        end
      end
    end
    for _, c in ipairs(f._children) do visit(c, myClip, alpha) end
  end
  visit(M.UIParent, nil, 1)
  table.sort(ops, function(a, b)
    for i = 1, 3 do if a.key[i] ~= b.key[i] then return a.key[i] < b.key[i] end end
    local la, lb = a.layer or 0, b.layer or 0
    if a.kind == "backdrop" or a.kind == "panelbutton" or a.kind == "closebutton" or a.kind == "edit" then la = 0 end
    if b.kind == "backdrop" or b.kind == "panelbutton" or b.kind == "closebutton" or b.kind == "edit" then lb = 0 end
    if la ~= lb then return la < lb end
    if (a.sub or 0) ~= (b.sub or 0) then return (a.sub or 0) < (b.sub or 0) end
    return a.order < b.order
  end)
  for _, op in ipairs(ops) do op.key = nil end
  return ops
end

---------------------------------------------------------------------- finding and clicking things (for tests)
--- every visible font string whose text contains `text`, with the nearest clickable frame above it
function M.findText(text, plainMatch, root)
  M.invalidate()
  local out = {}
  local function visible(o)
    local f = o
    while f do if not f._shown then return false end f = f._parent end
    return true
  end
  local function walk(f)
    for _, reg in ipairs(f._regions) do
      if reg._type == "FontString" and reg._text and plain(reg._text):find(text, 1, plainMatch ~= false) and visible(reg) and M.rect(reg) then
        local c = f
        while c and not (c._scripts.OnClick or c._scripts.OnMouseUp or c._scripts.OnMouseDown) do c = c._parent end
        table.insert(out, { fs = reg, frame = f, clickable = c })
      end
    end
    for _, c in ipairs(f._children) do walk(c) end
  end
  walk(root or M.UIParent)
  return out
end

function M.click(frame, button)
  if not frame then error("nothing to click", 2) end
  if frame._enabled == false then return false end
  M.hardware = true                      -- (a click: what the game calls a hardware event, until it's handled)
  local ok, err = xpcall(function() return M.clickNow(frame, button) end, debug.traceback)
  M.hardware = nil
  if not ok then error(err, 0) end
  return true
end
function M.clickNow(frame, button)
  local s = frame._scripts
  if frame._type == "EditBox" then frame:SetFocus() end
  if s.PreClick then s.PreClick(frame, button or "LeftButton") end
  if s.OnClick then s.OnClick(frame, button or "LeftButton", false)
  elseif s.OnMouseDown or s.OnMouseUp then
    if s.OnMouseDown then s.OnMouseDown(frame, button or "LeftButton") end
    if s.OnMouseUp then s.OnMouseUp(frame, button or "LeftButton") end
  end
  if s.PostClick then s.PostClick(frame, button or "LeftButton") end
  return true
end

function M.fire(event, ...)
  for f in pairs(M.events[event] or {}) do
    if f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
  end
end

function M.tick(elapsed)
  for _, f in ipairs(allFrames) do
    if f._scripts.OnUpdate and f:IsVisible() then f._scripts.OnUpdate(f, elapsed or 0.1) end
  end
  M.runTimers(elapsed or 0.1)
end

--- types into the focused edit box one key at a time, like a player (a key replaces any highlight)
function M.type(text, between)
  for c in text:gmatch(".") do
    local e = M.focus
    if not e then error("typing with nothing focused", 2) end
    local t = e:GetText()
    local a, b
    if e._sel then a, b = e._sel[1], e._sel[2] else a = e._cursor or #t b = a end
    e._text = t:sub(1, a) .. c .. t:sub(b + 1)
    e._sel = nil
    e._cursor = a + 1
    if e._scripts.OnTextChanged then e._scripts.OnTextChanged(e, true) end
    if between then between() end
  end
end

--- textures that share a draw layer and sublevel with a backdrop's own pieces (BackdropTemplate draws its
--- centre on BACKGROUND and its edges on BORDER, sublevel 0). The game doesn't define which of two such
--- textures is drawn on top, so the backdrop can hide them: each clash as "frame kind: layer"
function M.layerClashes()
  local out, seen = {}, {}
  for _, f in ipairs(allFrames) do
    local b = f._backdrop
    if b then
      for _, r in ipairs(f._regions) do
        if r._type == "Texture" and r._sublevel == 0 and ((r._layer == "BACKGROUND" and b.bgFile) or (r._layer == "BORDER" and b.edgeFile)) then
          local key = (f._kind or f._name or "frame") .. ": " .. r._layer
          if not seen[key] then seen[key] = true out[#out + 1] = key end
        end
      end
    end
  end
  return out
end

function M.frameCount() return #allFrames end
function M.allFrames() return allFrames end

--- every method name the stand-in gives a widget type (including what it inherits)
function M.methodNames(kind)
  local out = {}
  local function walk(tbl, seen)
    if not tbl or seen[tbl] then return end
    seen[tbl] = true
    for k, v in pairs(tbl) do if type(v) == "function" then out[k] = true end end
    local mt = getmetatable(tbl)
    if mt and type(mt.__index) == "table" then walk(mt.__index, seen) end
  end
  local d = methods[kind]
  while d do walk(d.m, {}) d = d.base and methods[d.base] end
  return out
end

---------------------------------------------------------------------- the global environment
local timers = {}
function M.runTimers(dt)
  M.clock = (M.clock or 0) + (dt or 0)
  local due = {}
  for i = #timers, 1, -1 do
    if timers[i].at <= M.clock then table.insert(due, timers[i].fn) table.remove(timers, i) end
  end
  for _, fn in ipairs(due) do fn() end
end

M.CLASS_ID = { warrior = 1, paladin = 2, hunter = 3, rogue = 4, priest = 5, shaman = 7, mage = 8, warlock = 9, druid = 11 }
function M.env(player)
  player = player or {}
  M.player = player                -- (a test can give them gear: M.player.links = { [slot] = link })
  local G = {}
  -- the Lua the client has
  for _, k in ipairs({ "assert", "error", "ipairs", "next", "pairs", "pcall", "print", "rawequal", "rawget", "rawset", "select",
    "setmetatable", "getmetatable", "tonumber", "tostring", "type", "unpack", "xpcall", "string", "table", "math", "coroutine", "loadstring", "setfenv", "getfenv" }) do
    G[k] = _G[k]
  end
  G.bit = require("bit")
  -- the game's xpcall passes extra arguments on to the function (Lua 5.1's doesn't)
  G.xpcall = function(f, handler, ...)
    local n, args = select("#", ...), { ... }
    return xpcall(function() return f(unpack(args, 1, n)) end, handler)
  end
  G.format, G.strlen, G.strsub, G.strfind, G.strmatch, G.gsub, G.strlower, G.strupper, G.strrep, G.strbyte, G.strchar =
    string.format, string.len, string.sub, string.find, string.match, string.gsub, string.lower, string.upper, string.rep, string.byte, string.char
  G.floor, G.ceil, G.abs, G.max, G.min, G.sqrt, G.random = math.floor, math.ceil, math.abs, math.max, math.min, math.sqrt, math.random
  G.tinsert, G.tremove, G.sort, G.tconcat = table.insert, table.remove, table.sort, table.concat
  G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
  G.table = setmetatable({ wipe = G.wipe }, { __index = table })          -- (the game's table library has wipe too)
  G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  G.strsplit = function(sep, s, n)
    local out = {}
    for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
    return unpack(out)
  end
  G.time, G.date = os.time, os.date
  G.GetTime = function() return M.clock or 0 end
  G.debugprofilestop = function() return os.clock() * 1000 end
  -- (M.VALID_EVENTS, when set: the client's own list, as tools/check_api.lua reads it from Blizzard's code)
  G.C_EventUtils = { IsEventValid = function(e)
    if M.VALID_EVENTS then return M.VALID_EVENTS[e] == true end
    return type(e) == "string" and not M.MISSING_EVENTS[e]
  end }
  G.C_Timer = { After = function(d, fn) table.insert(timers, { at = (M.clock or 0) + d, fn = fn }) end, NewTicker = function() return { Cancel = function() end } end }
  G.CreateFrame = M.CreateFrame
  M.UIParent = newObject("Frame", nil, "UIParent")
  M.UIParent._isFrame = true
  G.UIParent = M.UIParent
  G.WorldFrame = M.UIParent
  M.GameTooltip = M.CreateFrame("GameTooltip", "GameTooltip", M.UIParent, "GameTooltipTemplate")
  M.GameTooltip:Hide()
  G.GameTooltip = M.GameTooltip
  G.ItemRefTooltip = M.CreateFrame("GameTooltip", "ItemRefTooltip", M.UIParent, "GameTooltipTemplate")
  G.Minimap = M.CreateFrame("Frame", "Minimap", M.UIParent)
  G.Minimap:SetSize(140, 140) G.Minimap:SetPoint("TOPRIGHT", M.UIParent, "TOPRIGHT", -20, -20)
  G.CharacterFrame = M.CreateFrame("Frame", "CharacterFrame", M.UIParent)
  G.CharacterFrame:SetSize(384, 512) G.CharacterFrame:SetPoint("TOPLEFT", 0, -104) G.CharacterFrame:Hide()
  G.PaperDollFrame = M.CreateFrame("Frame", "PaperDollFrame", G.CharacterFrame)
  for name in pairs(FONTS) do G[name] = fontObjects[name] end
  G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
  G.UNKNOWN = "Unknown"
  G.SlashCmdList = {}
  G.UISpecialFrames = {}
  G.SOUNDKIT = { IG_MAINMENU_OPEN = 850, IG_MAINMENU_CLOSE = 851, IG_CHARACTER_INFO_TAB = 841, U_CHAT_SCROLL_BUTTON = 1115, IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857 }
  M.sounds = {}
  G.PlaySound = function(id, channel) table.insert(M.sounds, { id = id, channel = channel }) end
  G.hooksecurefunc = function(t, name, fn)
    if type(t) == "string" then t, name, fn = G, t, name end
    local old = t[name]
    t[name] = function(...) local r = { old(...) } fn(...) return unpack(r) end
  end
  G.securecallfunction = function(fn, ...) return fn(...) end
  G.securecall = function(fn, ...) if type(fn) == "string" then fn = G[fn] end return fn(...) end
  G.IsShiftKeyDown = function() return false end
  G.IsControlKeyDown = function() return false end
  G.IsAltKeyDown = function() return false end
  G.GetCursorPosition = function() return SCREEN_W / 2, SCREEN_H / 2 end
  G.InCombatLockdown = function() return false end
  G.GetLocale = function() return "enUS" end
  G.GetBuildInfo = function() return "2.5.5", "65000", "Oct 1 2026", 20506 end
  G.UnitName = function() return player.name or "Tankadin", player.realm end
  G.UnitClass = function() local c = (player.class or "paladin"):upper() return c:sub(1, 1) .. c:sub(2):lower(), c, 2 end
  G.UnitRace = function()
    local map = { human = "Human", dwarf = "Dwarf", nightelf = "NightElf", gnome = "Gnome", draenei = "Draenei", orc = "Orc", undead = "Scourge", tauren = "Tauren", troll = "Troll", bloodelf = "BloodElf" }
    local r = map[player.race or "human"]
    return r, r
  end
  G.UnitLevel = function() return 70 end
  G.GetRealmName = function() return "Dreamscythe" end
  G.GetInventoryItemLink = function(_, slot) return player.links and player.links[slot] end
  G.GetInventoryItemID = function(_, slot) local l = player.links and player.links[slot] return l and tonumber(l:match("item:(%d+)")) end
  G.GetInventorySlotInfo = function(name)
    local tex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. name:gsub("Slot$", ""):gsub("%d$", "")
    local slots = { HeadSlot = 1, NeckSlot = 2, ShoulderSlot = 3, BackSlot = 15, ChestSlot = 5, WristSlot = 9, HandsSlot = 10, WaistSlot = 6, LegsSlot = 7,
      FeetSlot = 8, Finger0Slot = 11, Finger1Slot = 12, Trinket0Slot = 13, Trinket1Slot = 14, MainHandSlot = 16, SecondaryHandSlot = 17, RangedSlot = 18 }
    slots.ShirtSlot, slots.TabardSlot = 4, 19
    return slots[name] or error("bad slot " .. tostring(name)), tex
  end
  G.GetNumTalentTabs = function() return 3 end
  G.GetTalentTabInfo = function(tab) local t = player.trees and player.trees[tab] return t and t.name or "Tree", "", 0, "" end
  G.GetNumTalents = function(tab) local t = player.trees and player.trees[tab] return t and #t.talents or 0 end
  G.GetTalentInfo = function(tab, i)
    local t = player.trees[tab].talents[i]
    return t.name, "", t.tier, t.column, t.rank, t.max
  end
  G.C_SpecializationInfo = {
  -- specId, name, description, icon, role, primaryStat, pointsSpent, background (the player's own class only)
  GetSpecializationInfo = function(i, inspect, pet, target, sex, group, classID)
    if type(i) ~= "number" then fail("GetSpecializationInfo needs an index") end
    if classID and classID ~= M.CLASS_ID[player.class] then return 0 end
    local tree = player.trees and player.trees[i]
    if not tree then return 0 end
    return 0, tree.name, "", 136243, nil, nil, 0, tree.background
  end,
  GetTalentInfo = function(q)
    local tree = player.trees and player.trees[q.specializationIndex]
    local t = tree and tree.talents[q.talentIndex]
    if not t then return nil end
    return { name = t.name, icon = 136243, tier = t.tier, column = t.column, rank = t.rank, maxRank = t.max, talentID = 1 }
  end }
  G.GetItemInfo = function(id) return nil end
  local defaultHandler = function(e) table.insert(M.errors, tostring(e)) end
  local errorHandler = defaultHandler
  G.geterrorhandler = function() return errorHandler end
  G.seterrorhandler = function(f) if type(f) ~= "function" then fail("seterrorhandler needs a function") end errorHandler = f end
  -- the Anniversary client has no raceicon atlases (C_Texture.GetAtlasInfo("raceicon128-human-male") is nil in game)
  G.C_Texture = { GetAtlasInfo = function(a) if type(a) ~= "string" then fail("GetAtlasInfo needs a name") end return M.atlases and M.atlases[a] or nil end }
  G.GetFileIDFromPath = function(path) if type(path) ~= "string" then fail("GetFileIDFromPath needs a path") end
    return path:lower():find("^interface\\") and not (M.missingFiles and M.missingFiles[path]) and 1000 + #path or nil end
  G.CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 }, DRUID = { 0.7421875, 0.98828125, 0, 0.25 }, PALADIN = { 0, 0.25, 0.5, 0.75 },
    MAGE = { 0.25, 0.49609375, 0, 0.25 }, ROGUE = { 0.49609375, 0.7421875, 0, 0.25 }, HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
    PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 } }
  G.TALENT_ARROW_TEXTURECOORDS = { top = { [1] = { 0, 0.5, 0, 0.5 }, [-1] = { 0, 0.5, 0.5, 1.0 } }, right = { [1] = { 1.0, 0.5, 0, 0.5 }, [-1] = { 1.0, 0.5, 0.5, 1.0 } },
    left = { [1] = { 0.5, 1.0, 0, 0.5 }, [-1] = { 0.5, 1.0, 0.5, 1.0 } } }
  G.GetItemIcon = function() return 134400 end
  G.GetSpellInfo = function(id) return "Spell " .. tostring(id), nil, 136243 end
  G.GetSpellTexture = function() return 136243 end
  G.ChatFrame_OpenChat = function() end
  G.HandleModifiedItemClick = function(link) return false end
  -- rolling and master loot (tests/wow/server.lua makes these work between clients)
  G.RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
  G.LOOT_ITEM, G.LOOT_ITEM_SELF = "%s receives loot: %s.", "You receive loot: %s."
  G.LOOT_ITEM_MULTIPLE, G.LOOT_ITEM_SELF_MULTIPLE = "%s receives loot: %sx%d.", "You receive loot: %sx%d."
  G.ERR_TRADE_COMPLETE = "Trade complete."
  G.TradeFrame = M.CreateFrame("Frame", "TradeFrame", M.UIParent)
  G.TradeFrame:Hide()
  G.UnitGUID = function() return nil end
  G.UnitIsDead = function() return false end
  G.GetTradePlayerItemLink = function() return nil end
  M.flashed = 0
  G.FlashClientIcon = function() M.flashed = M.flashed + 1 end
  G.InitiateTrade = function() end
  G.CheckInteractDistance = function() return true end
  G.TRADE_ENCHANT_SLOT = 7                  -- (Blizzard_UIPanels_Game/Classic/TradeFrame.lua)
  -- the big message in the middle of the screen (Blizzard_FrameXMLUtil/Classic/RaidWarning.lua): recorded
  M.notices = {}
  G.RaidWarningFrame = M.CreateFrame("Frame", "RaidWarningFrame", M.UIParent)
  G.RaidNotice_AddMessage = function(frame, text, info) table.insert(M.notices, text) end
  G.ChatTypeInfo = { RAID_WARNING = { r = 1, g = 0.28, b = 0 } }
  G.GetTradePlayerItemInfo = function() return nil end
  G.GetTradeTargetItemInfo = function() return nil end
  -- the game's loot window buttons and a group loot (need/greed) window
  for i = 1, 4 do
    local b = M.CreateFrame("Button", "LootButton" .. i, G.LootFrame)
    b:SetSize(34, 34)
    b:SetPoint("TOPLEFT", G.LootFrame, "TOPLEFT", 18, -40 - (i - 1) * 42)
    local ic = b:CreateTexture("LootButton" .. i .. "IconTexture", "ARTWORK")
    ic:SetAllPoints()
    G["LootButton" .. i .. "IconTexture"] = ic
    -- the item's name beside the icon, as the game lays it out (LootButtonTemplate: 93 x 38, 8 to the right)
    local tx = b:CreateFontString("LootButton" .. i .. "Text", "ARTWORK", "GameFontNormal")
    tx:SetSize(93, 38)
    tx:SetPoint("LEFT", b, "RIGHT", 8, 0)
    tx:SetJustifyH("LEFT")
    G["LootButton" .. i .. "Text"] = tx
    G["LootButton" .. i] = b
    b:Hide()
  end
  G.LootFrame_UpdateButton = function(index)
    local b = G["LootButton" .. index]
    b.slot = index
    b:SetShown(G.LootSlotHasItem(index))
    local _, name = G.GetLootSlotInfo(index)
    G["LootButton" .. index .. "Text"]:SetText(name or "")
  end
  G.GroupLootFrame1 = M.CreateFrame("Frame", "GroupLootFrame1", M.UIParent)
  G.GroupLootFrame1.IconFrame = M.CreateFrame("Button", nil, G.GroupLootFrame1)
  G.GroupLootFrame1.IconFrame:SetSize(34, 34)
  G.GroupLootFrame1.IconFrame:SetPoint("TOPLEFT", 18, -18)
  G.GroupLootFrame_OnShow = function(self) end
  G.GetLootRollItemLink = function(rollID) return M.lootRolls and M.lootRolls[rollID] end
  -- the game's inspect window (loaded once someone has inspected): hidden
  G.InspectFrame = M.CreateFrame("Frame", "InspectFrame", M.UIParent)
  G.InspectFrame:Hide()
  -- the game's error lines (GlobalStrings), in English
  G.ERR_LOOT_MASTER_INV_FULL = "That player's inventory is full"
  G.ERR_LOOT_MASTER_UNIQUE_ITEM = "The player has too many of that item already"
  G.ERR_ITEM_MAX_COUNT = "You can't carry any more of those items."
  G.ERR_LOOT_PLAYER_NOT_FOUND = "Player not found"
  G.ERR_LOOT_TOO_FAR = "You are too far away to loot that corpse."
  -- the mailbox's Send Mail tab (M.openMail()); SendMail succeeds, and M.mailed keeps what was sent
  G.SendMailFrame = M.CreateFrame("Frame", "SendMailFrame", M.UIParent)
  G.SendMailFrame:Hide()
  G.SendMailNameEditBox = M.CreateFrame("EditBox", "SendMailNameEditBox", G.SendMailFrame)
  G.SendMailSubjectEditBox = M.CreateFrame("EditBox", "SendMailSubjectEditBox", G.SendMailFrame)
  G.SendMailMoney = M.CreateFrame("Frame", "SendMailMoney", G.SendMailFrame)
  G.MoneyInputFrame_SetCopper = function(frame, copper) frame._copper = copper end
  G.GetSendMailMoney = function() return G.SendMailMoney._copper or 0 end
  M.mailed = {}
  G.SendMail = function(name, subject, body)
    if not G.SendMailFrame:IsShown() then error("SendMail with no mailbox open") end
    table.insert(M.mailed, { name = name, subject = subject, copper = G.GetSendMailMoney() })
    -- (the game says it's gone a moment later)
    G.C_Timer.After(0.1, function() G.SendMailMoney._copper = 0 M.fire("MAIL_SEND_SUCCESS") end)
  end
  function M.openMail() G.SendMailFrame:Show() M.fire("MAIL_SHOW") end
  -- the game's Need / Greed windows: M.groupRoll(rollID, link, quality, opts) starts one; rolls and confirms are kept
  M.lootRollInfo, M.lootRolled, M.lootConfirmed, M.popupsHidden = {}, {}, {}, {}
  G.GetLootRollItemInfo = function(rollID)
    local r = M.lootRollInfo[rollID]
    if not r then return nil end
    return 133000, r.name, 1, r.quality, r.bop, r.need ~= false, r.greed ~= false, r.de == true, nil, nil, nil, nil
  end
  G.RollOnLoot = function(rollID, kind)
    if not M.lootRollInfo[rollID] then error("RollOnLoot on a roll that isn't on") end
    M.lootRolled[rollID] = kind
    if kind == 3 and M.MISSING_EVENTS.CONFIRM_DISENCHANT_ROLL then error("RollOnLoot: TBC has no disenchant roll") end
    if M.lootRollInfo[rollID].bop and kind ~= 0 then M.fire(kind == 3 and "CONFIRM_DISENCHANT_ROLL" or "CONFIRM_LOOT_ROLL", rollID, kind) end
  end
  G.ConfirmLootRoll = function(rollID, kind) M.lootConfirmed[rollID] = kind end
  G.StaticPopup_Hide = function(which, data) table.insert(M.popupsHidden, { which, data }) end
  function M.groupRoll(rollID, link, quality, opts)
    opts = opts or {}
    M.lootRolls = M.lootRolls or {}
    M.lootRolls[rollID] = link
    M.lootRollInfo[rollID] = { name = link:match("%[(.-)%]"), quality = quality, bop = opts.bop, need = opts.need, greed = opts.greed, de = opts.de }
    M.fire("START_LOOT_ROLL", rollID, 60)
  end
  M.tooltipCalls = {}
  G.TooltipDataProcessor = { AllTypes = "ALL", AddTooltipPostCall = function(kind, fn) table.insert(M.tooltipCalls, fn) end }
  G.GetTradeTargetItemLink = function() return nil end
  G.GetPlayerTradeMoney = function() return 0 end
  G.GetTargetTradeMoney = function() return 0 end
  G.RandomRoll = function(lo, hi) M.rolled = M.rolled or {} table.insert(M.rolled, { tonumber(lo), tonumber(hi) }) end
  G.LootFrame = M.CreateFrame("Frame", "LootFrame", M.UIParent)
  G.LootFrame:SetSize(192, 300)
  G.LootFrame:SetPoint("TOPLEFT", M.UIParent, "TOPLEFT", 40, -120)
  G.LootFrame:Hide()
  G.GetLootThreshold = function() return 2 end
  G.GetNumLootItems = function() return 0 end
  G.LootSlotHasItem = function() return false end
  G.GetLootSlotLink = function() return nil end
  G.GetLootSlotInfo = function() return nil end
  G.GetMasterLootCandidate = function() return nil end
  G.GiveMasterLoot = function() end
  G.C_PartyInfo = { GetLootMethod = function() return 3 end }
  -- the guild (none, unless the test or the server says so)
  G.IsInGuild = G.IsInGuild or function() return false end
  G.IsInInstance = G.IsInInstance or function() return false, "none" end
  G.GetGuildInfo = function() return nil end
  G.GetNumGuildMembers = function() return 0, 0 end
  G.GetGuildRosterInfo = function() return nil end
  G.C_GuildInfo = { GuildRoster = function() end }
  G.IsGuildLeader = function() return false end
  G.GuildControlGetNumRanks = function() return 0 end
  G.GuildControlGetRankName = function() return nil end
  G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(M.chat, msg) end }
  M.chat = {}
  -- print() goes to the chat frame in game: keep it for the test to read
  G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    table.insert(M.chat, table.concat(parts, " "))
  end
  G.ShowUIPanel = function(f) f:Show() end
  G.HideUIPanel = function(f) f:Hide() end
  G.CloseDropDownMenus = function() end
  G.C_AddOns = { GetAddOnMetadata = function(_, k) return k == "Version" and "1.0.0-beta" or nil end,
    LoadAddOn = function(name)
      if M.loadAddOn then return M.loadAddOn(name) end
      return false, "MISSING"
    end,
    GetAddOnInfo = function(name)
      local loadable, reason = true, nil
      if M.addOnInfo then loadable, reason = M.addOnInfo(name) end
      return name, name, "", loadable, reason or "", "INSECURE", false
    end }
  G.ITEM_QUALITY_COLORS = {}
  -- globals that addons may check for; reading them is fine even though they are nil here
  local OPTIONAL = { DressUpModel = true, LibStub = true, C_Item = true, C_Container = true, Settings = true, ElvUI = true, BackdropTemplateMixin = true,
    ChatThrottleLib = true, Gargul = true, ChatFrameUtil = true, ChatFrame_AddMessageEventFilter = true, require = true, _ENV = true, io = true, os = true, debug = true, arg = true, issecretvalue = true }
  setmetatable(G, { __index = function(_, k)
    if OPTIONAL[k] then return nil end
    if type(k) == "string" and (k:match("^SLASH_") or k:match("^LootRuler")) then return nil end
    error("global '" .. tostring(k) .. "' does not exist in the client (or the mock)", 2)
  end })
  G._G = G
  M.G = G
  -- frames named via CreateFrame go into this environment
  _G_target = G
  return G
end

-- named frames are written into the mock environment instead of the real globals
local realNew = newObject
newObject = function(kind, parent, name)
  local o = realNew(kind, parent, nil)
  if name then o._name = name named[name] = o if M.G then rawset(M.G, name, o) end end
  return o
end

return M
