-- "Picked up": a small note for raiders when the loot master picks up loot, saying what it was and who reserved it. It
-- sits at the top of the screen, takes no clicks, and goes by itself a few seconds after the last item. Only loot to
-- roll for (not the counted trade goods, LR.minorLoot), and not on the screen of whoever picked it up (they've seen it).
-- It comes from the session's loot list, so it works however the list was written (Core/Drops.lua). Settings: pickedUp.
local _, LR = ...
local U, K = LR.U, LR.K
local UI = LR.UI

local W, MAX = 320, 5
local WAIT = 10              -- seconds it stays after the last item
local box
local seen = {}              -- session id -> { drop key -> true }: what's been on its list
local items = {}             -- the lines showing now
local shown = 0

local function build()
  box = CreateFrame("Frame", "LootRulerPickedUp", UIParent, "BackdropTemplate")
  box:SetWidth(W)
  box:SetFrameStrata("MEDIUM")
  box:SetBackdrop(K.FLAT)
  box:SetBackdropColor(0.05, 0.04, 0.03, 0.8)
  box:SetBackdropBorderColor(0.72, 0.54, 0.23, 0.6)
  box:EnableMouse(false)                         -- (clicks go through)
  box:SetPoint("TOP", UIParent, "TOP", 0, -30)
  box.head = K.fs(box, "GameFontNormalSmall")
  box.head:SetPoint("TOPLEFT", 8, -6)
  box.text = K.fs(box, "GameFontHighlightSmall")
  box.text:SetPoint("TOPLEFT", box.head, "BOTTOMLEFT", 0, -3)
  box.text:SetWidth(W - 16)
  box:Hide()
end

--- one item's line: its name, and who reserved it (or that it's hard reserved, or mine)
local function line(s, id)
  local name = LR.coloredName(id)
  if s.hr[id] then return name .. "  |cffff5a4aHard reserved|r" .. ((s.hr[id].f or "") ~= "" and (" for " .. s.hr[id].f) or "") end
  if LR.Session.claims(s, U.me(), id) > 0 then
    local others = UI.whoLine(s, id, 3, U.me())
    return name .. "  |cff1eff00Yours|r" .. (others and (", also " .. others) or "")
  end
  local who = UI.whoLine(s, id, 4)
  return name .. (who and ("  SR: " .. who) or "")
end

--- shows new items picked up (lines of text)
function UI.pickedUp(lines)
  if #lines == 0 then return end
  if not box then build() end
  for _, l in ipairs(lines) do items[#items + 1] = l end
  while #items > MAX do table.remove(items, 1) end
  box.head:SetText("Picked up")
  box.text:SetText(table.concat(items, "\n"))
  box:SetHeight(6 + box.head:GetStringHeight() + 3 + box.text:GetStringHeight() + 7)
  box:Show()
  shown = shown + 1
  local mine = shown
  C_Timer.After(WAIT, function()
    if shown ~= mine then return end
    items = {}
    box:Hide()
  end)
end
function UI.pickedUpLines() return items end

--- the session's list changed: anything new on it (not mine to have seen) is shown. The first look at a session
--- (logging in, joining) only notes what's there.
local function check()
  if not LR.db then return end
  local s = LR.current()
  if not s or s.archived then return end
  local known = seen[s.id]
  local first = known == nil
  if first then known = {} seen[s.id] = known end
  local new = {}
  for _, d in ipairs(s.drops or {}) do
    if not known[d.k] then
      known[d.k] = true
      if not first and LR.db.settings.pickedUp and not LR.minorLoot(s, d.i)
        and (s.practice or not (d.by and U.samePlayer(d.by, U.me()))) then
        new[#new + 1] = line(s, d.i)
      end
    end
  end
  UI.pickedUp(new)
end
UI.pickedUpCheck = check

LR.onChange(function(what)
  if what == "session" then check() end
end)
