-- "Say it": trade lines to say nearby (/s) when the person running loot isn't in a group. Outside a dungeon or raid the
-- game lets an addon /say only on a click, so the lines wait here (Drops.sayNearby) until "Say it" is clicked. New
-- trades add to the list; it goes after WAIT seconds with nothing new, or when it's said or dismissed.
local _, LR = ...
local U, K = LR.U, LR.K
local UI = LR.UI

local W = 320
local MAX = 8                 -- lines kept (the oldest go first)
local WAIT = 120              -- seconds it stays up after the last trade
local win
local lines = {}              -- { t = text, pretend = true for the Test tab's (shown, never said) }
local shown = 0               -- bumped on each new line, so an older timer doesn't hide a newer list

local function hide()
  lines = {}
  if win then win:Hide() end
end

local function build()
  win = CreateFrame("Frame", "LootRulerSay", UIParent, "BackdropTemplate")
  win:SetWidth(W)
  win:SetFrameStrata("DIALOG")
  win:SetBackdrop(K.FLAT)
  win:SetBackdropColor(0.05, 0.04, 0.03, 0.92)
  win:SetBackdropBorderColor(0.72, 0.54, 0.23, 0.8)
  win:SetClampedToScreen(true)
  win:EnableMouse(true)
  win:SetPoint("TOP", UIParent, "TOP", 0, -140)
  win.title = K.fs(win, "GameFontNormal")
  win.title:SetPoint("TOPLEFT", 10, -9)
  win.title:SetPoint("RIGHT", win, "RIGHT", -10, 0)
  win.text = K.fs(win, "GameFontHighlightSmall")
  win.text:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -6)
  win.text:SetPoint("RIGHT", win, "RIGHT", -10, 0)
  win.say = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  win.say:SetSize(90, 22)
  win.say:SetText("Say it")
  win.say:SetScript("OnClick", function()
    for _, l in ipairs(lines) do
      if l.pretend then LR.print("(pretend, not said) " .. l.t) else LR.sayNow(l.t, "SAY") end
    end
    hide()
  end)
  win.no = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  win.no:SetSize(90, 22)
  win.no:SetText("Not now")
  win.no:SetPoint("LEFT", win.say, "RIGHT", 8, 0)
  win.no:SetScript("OnClick", hide)
  win:Hide()
end

--- adds trade lines to say nearby, and shows them with a "Say it" button. pretend: the Test tab's, only shown
function UI.sayPrompt(add, pretend)
  if not win then build() end
  for _, l in ipairs(add or {}) do lines[#lines + 1] = { t = l, pretend = pretend } end
  while #lines > MAX do table.remove(lines, 1) end
  if #lines == 0 then return end
  win.title:SetText(#lines == 1 and "Say this trade nearby?" or ("Say these %d trades nearby?"):format(#lines))
  local plain = {}
  local tag = LR.TAG .. " "
  for i, l in ipairs(lines) do plain[i] = l.t:sub(1, #tag) == tag and l.t:sub(#tag + 1) or l.t end
  win.text:SetText(table.concat(plain, "\n"))
  win.say:ClearAllPoints()
  win.say:SetPoint("TOPLEFT", win.text, "BOTTOMLEFT", 0, -8)
  win:SetHeight(9 + win.title:GetStringHeight() + 6 + win.text:GetStringHeight() + 8 + 22 + 10)
  win:Show()
  shown = shown + 1
  local mine = shown
  C_Timer.After(WAIT, function() if shown == mine then hide() end end)
end

--- the lines waiting to be said (for tests)
function UI.sayWaiting() return U.map(lines, function(l) return l.t end) end
