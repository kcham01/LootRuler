-- Reserves where you see items: the game's own loot window and group loot (need/greed) windows glow on an
-- item you reserved, and every item tooltip (bags, chat links, loot windows) says who reserved it, while soft
-- reserves are open. Both can be turned off (Settings tab).
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

-- the loot window (one button per item on the page)
if LootFrame_UpdateButton then
  hooksecurefunc("LootFrame_UpdateButton", function(index)
    local button = _G["LootButton" .. index]
    if not button or not LR.db then return end
    local slot = button.slot
    local id = slot and button:IsShown() and idOf(GetLootSlotLink(slot))
    glow(button, id ~= nil and LR.isMine(LR.current(), id), _G["LootButton" .. index .. "IconTexture"])
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
