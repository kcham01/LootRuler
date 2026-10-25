-- Reserves where you see items: the game's own loot window and group loot (need/greed) windows glow on an
-- item you reserved, the loot window marks every reserved item with who reserved it (for everyone), and every
-- item tooltip (bags, chat links, loot windows) says who reserved it, while soft reserves are open. Each can be
-- turned off (Settings tab).
local _, LR = ...
local U, S = LR.U, LR.Session
local UI = LR.UI

--- whether an item is mine to get: I have a reserve on it that hasn't won it yet, or it's hard reserved for me
function LR.isMine(s, id)
  if not s or not id then return false end
  if S.claims(s, U.me(), id) > 0 then return true end
  local hr = s.hr[id]
  return hr ~= nil and hr.f ~= "" and (U.samePlayer(hr.f, U.me()) or U.foldCase(U.bare(hr.f)) == U.foldCase(U.bare(U.me())))
end

local function idOf(link) return link and tonumber(tostring(link):match("item:(%d+)")) end

--- a gold glow around an item button (made the first time)
local function glow(button, on, anchor)
  if not button then return end
  if not button.lrGlow then
    if not on then return end
    local g = button:CreateTexture(nil, "OVERLAY")
    g:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    g:SetBlendMode("ADD")
    g:SetVertexColor(1, 0.82, 0, 1)
    local a = anchor or button
    g:SetPoint("CENTER", a, "CENTER", 0, 0)
    g:SetSize(a:GetWidth() * 1.9, a:GetHeight() * 1.9)
    button.lrGlow = g
  end
  button.lrGlow:SetShown(on and LR.db.settings.highlight)
end
UI.glow = glow

---------------------------------------------------------------------- who reserved an item
--- the players who still have a reserve to claim on an item: { { name, n (reserves), class } }, in reserve order
function UI.reservers(s, id)
  local out = {}
  if not s or not id then return out end
  for _, w in ipairs(S.byItem(s)[id] or {}) do
    local left = S.claims(s, w[1], id)
    if left > 0 then out[#out + 1] = { w[1], left, (s.res[w[1]] and s.res[w[1]].c) or LR.classOf(w[1]) } end
  end
  return out
end
--- one name, in its class colour ("Bob x2" for two reserves)
function UI.reserverText(w) return U.classText(U.short(w[1]) .. ((w[2] or 1) > 1 and (" x" .. w[2]) or ""), w[3]) end
--- a font string set to prefix and as many names as fit in width, then "+N" for the rest
function UI.fitNames(fs, prefix, list, width)
  local shown = #list
  while true do
    local parts = {}
    for i = 1, shown do parts[i] = UI.reserverText(list[i]) end
    if shown < #list then parts[#parts + 1] = "+" .. (#list - shown) end
    fs:SetText(prefix .. table.concat(parts, ", "))
    if shown <= 1 or fs:GetStringWidth() <= width then return end
    shown = shown - 1
  end
end

-- the loot window: "SR" on the icon of an item someone reserved ("HR" when hard reserved), and who under its name
local NAME_W = 110          -- (the item's name plate behind the text is about this wide)
local function tag(button, index, s, id)
  local text, icon = _G["LootButton" .. index .. "Text"], _G["LootButton" .. index .. "IconTexture"]
  local hr = s and id and s.hr[id]
  local who = (s and id and not hr) and UI.reservers(s, id) or {}
  local on = LR.db.settings.lootTags and (hr ~= nil or #who > 0) and text ~= nil
  if not button.lrTag then
    if not on then return end
    button.lrTag = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.lrTag:SetPoint("TOPLEFT", icon or button, "TOPLEFT", 2, -2)
    button.lrTag:SetShadowOffset(1, -1)
    button.lrTag:SetShadowColor(0, 0, 0, 1)
    button.lrWho = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.lrWho:SetJustifyH("LEFT")
    button.lrWho:SetWordWrap(false)
    button.lrWho:SetWidth(NAME_W)
  end
  if not on then
    button.lrTag:Hide() button.lrWho:Hide()
    if button.lrMoved and text then            -- the item's name back where the game puts it
      text:ClearAllPoints() text:SetPoint("LEFT", button, "RIGHT", 8, 0) text:SetHeight(38) text:SetMaxLines(0)
      button.lrMoved = false
    end
    return
  end
  -- the item's name moves up a little to make room for the names under it
  text:ClearAllPoints()
  text:SetPoint("TOPLEFT", button, "TOPRIGHT", 8, 0)
  text:SetHeight(25)
  text:SetMaxLines(2)                            -- (a long name is cut short rather than running into them)
  button.lrMoved = true
  button.lrWho:ClearAllPoints()
  button.lrWho:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, 0)
  button.lrTag:SetText(hr and "|cffff5a4aHR|r" or "|cffffd100SR|r")
  if hr then button.lrWho:SetText(hr.f ~= "" and ("For " .. hr.f) or "Hard reserved")
  else UI.fitNames(button.lrWho, "", who, NAME_W) end
  button.lrTag:Show() button.lrWho:Show()
end

-- the loot window (one button per item on the page)
if LootFrame_UpdateButton then
  hooksecurefunc("LootFrame_UpdateButton", function(index)
    local button = _G["LootButton" .. index]
    if not button or not LR.db then return end
    local slot = button.slot
    local id = slot and button:IsShown() and idOf(GetLootSlotLink(slot))
    local s = LR.current()
    glow(button, id ~= nil and LR.isMine(s, id), _G["LootButton" .. index .. "IconTexture"])
    tag(button, index, s, id or nil)
  end)
end

-- group loot (need / greed) windows
if GroupLootFrame_OnShow then
  hooksecurefunc("GroupLootFrame_OnShow", function(frame)
    if not LR.db or not frame or not frame.rollID then return end
    local id = idOf(GetLootRollItemLink(frame.rollID))
    glow(frame.IconFrame, id ~= nil and LR.isMine(LR.current(), id))
  end)
end

---------------------------------------------------------------------- tooltips
--- the lines LootRuler adds to an item's tooltip: who reserved it, hard reserved for whom, who got it
function UI.tooltipLines(s, id)
  local out = {}
  if not s or not id then return out end
  local hr = s.hr[id]
  if hr then out[#out + 1] = { "LootRuler: hard reserved" .. (hr.f ~= "" and (" for " .. hr.f) or ""), 1, 0.35, 0.3 } end
  local who = UI.whoLine(s, id, 5)
  if who then out[#out + 1] = { "LootRuler: soft reserved by " .. who, 1, 0.82, 0 } end
  for _, w in ipairs(S.winners(s, id)) do
    out[#out + 1] = { "LootRuler: given to " .. U.short(w[1]), 0.12, 1, 0 }
  end
  -- the guild's priority list, when the session goes by them
  local book = s.prio and LR.book and LR.book()
  local list = book and LR.Book.prio(book, id)
  if list and #list > 0 then out[#out + 1] = { "LootRuler: priority " .. UI.prioLine(list, 5), 0.12, 1, 0 } end
  return out
end

local function addLines(tooltip, id)
  if not LR.db or not LR.db.settings.tooltipInfo or UI.ownTooltip then return end
  for _, l in ipairs(UI.tooltipLines(LR.current(), id)) do tooltip:AddLine(l[1], l[2], l[3], l[4], true) end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if tooltip == GameTooltip or tooltip == ItemRefTooltip then addLines(tooltip, data and data.id) end
  end)
end
