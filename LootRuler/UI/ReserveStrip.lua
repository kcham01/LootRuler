-- A small strip that says who reserved the item being rolled for: every name in full, in class colours (the
-- roll windows only have room for a few). It shows when a roll starts, LootRuler's or Gargul's (read from raid
-- chat, Core/Gargul.lua), and goes when the roll ends. It sits just above the roll window (or the loot master
-- window), takes no clicks, and only shows when someone reserved the item. Settings tab: "reserveStrip".
local _, LR = ...
local U, K, R = LR.U, LR.K, LR.Roll
local UI = LR.UI

local strip

local function build()
  strip = CreateFrame("Frame", "LootRulerReserveStrip", UIParent, "BackdropTemplate")
  strip:SetFrameStrata("DIALOG")
  strip:SetBackdrop(K.FLAT)
  strip:SetBackdropColor(0.05, 0.04, 0.03, 0.85)
  strip:SetBackdropBorderColor(0.72, 0.54, 0.23, 0.8)
  strip:EnableMouse(false)                       -- (clicks go through to whatever is underneath)
  strip.head = K.fs(strip, "GameFontNormalSmall")
  strip.head:SetPoint("TOPLEFT", 8, -6)
  strip.head:SetWordWrap(false)
  strip.names = K.fs(strip, "GameFontHighlightSmall")
  strip.names:SetPoint("TOPLEFT", strip.head, "BOTTOMLEFT", 0, -2)
  strip.names:SetJustifyH("LEFT")
  strip.names:SetWordWrap(true)
  strip:Hide()
end

--- the roll on now: LootRuler's (the one I'm running, else the newest I'm following), else Gargul's
local function current()
  local Rolls = LR.Rolls
  local mine = Rolls.mine()
  if mine and mine.state == "open" then return mine end
  for i = #Rolls.order, 1, -1 do
    local c = Rolls.seen[Rolls.order[i]]
    if c and c.state == "open" and not c.test then return c end
  end
  return LR.Gargul.roll
end

--- what the strip says for a roll: a heading and the names, or nil when there's nothing to say
function UI.stripText(roll, s)
  if not roll or roll.mode == "BID" or roll.mode == "TIE" or roll.mode == "PR" then return nil end
  local name, hex = LR.linkParts(roll.link, roll.id)
  local item = "|cff" .. hex .. name .. "|r"
  local hr = s and s.hr[roll.id]
  if hr or roll.mode == "HR" then
    local f = hr and hr.f or roll.f or ""
    return "|cffff5a4aHard reserved:|r " .. item, f ~= "" and ("For " .. f) or "For nobody in particular."
  end
  -- everyone with a reserve left on it: from the session, else from the roll itself (who may roll)
  local list = UI.reservers(s, roll.id)
  if #list == 0 and roll.mode == "SR" then
    for _, w in ipairs(roll.who or {}) do list[#list + 1] = { R.nameOf(w), type(w) == "table" and w[2] or 1, LR.classOf(R.nameOf(w)) } end
  end
  if #list == 0 then return nil end
  local here, away = {}, {}
  for _, w in ipairs(list) do
    if LR.inGroup(w[1]) or not IsInGroup() then here[#here + 1] = UI.reserverText(w) else away[#away + 1] = U.short(w[1]) end
  end
  local text = #here > 0 and table.concat(here, ", ") or "Nobody who reserved it is here."
  if #away > 0 then text = text .. "\n|cff9d9d9dNot here: " .. table.concat(away, ", ") .. "|r" end
  return ("|cffffd100Soft reserved (%d):|r %s"):format(#list, item), text
end

--- shows, moves or hides the strip for the roll on now
function UI.reserveStrip()
  if not LR.db then return end
  local roll = LR.db.settings.reserveStrip and current()
  local head, text = UI.stripText(roll, roll and (roll.sid and LR.session(roll.sid) or LR.current()))
  if not head then
    if strip then strip:Hide() end
    return
  end
  if not strip then build() end
  -- above the loot master window when it's up, else above the roll windows (or where they'd be)
  strip:ClearAllPoints()
  local master, first = _G.LootRulerMasterFrame, UI.rollFrames()[1]
  local width = 256
  if master and master:IsShown() then
    width = master:GetWidth()
    strip:SetPoint("BOTTOMLEFT", master, "TOPLEFT", 0, 2)
  elseif first and first:IsShown() then
    strip:SetPoint("BOTTOM", first, "TOP", 0, 2)
  else
    strip:SetPoint("BOTTOM", UI.rollAnchor(), "TOP", 0, 2)
  end
  strip.head:SetWidth(width - 16)
  strip.names:SetWidth(width - 16)
  strip.head:SetText(head)
  strip.names:SetText(text)
  strip:SetSize(width, strip.head:GetStringHeight() + strip.names:GetStringHeight() + 16)
  strip:Show()
end

LR.onChange(function(what)
  if what == "roll" or what == "rolls" or what == "session" or what == "roster" or what == "gargul" then UI.reserveStrip() end
end)

-- Gargul's rolls: its line in raid chat starts one; its "stop" or "awarded" line, the item being looted, or its
-- time running out ends it
local events = CreateFrame("Frame")
for _, e in ipairs({ "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_LOOT" }) do events:RegisterEvent(e) end
events:SetScript("OnEvent", function(_, event, text)
  local G = LR.Gargul
  if event == "CHAT_MSG_LOOT" then
    local id = tonumber(tostring(text or ""):match("item:(%d+)"))
    if id then G.endRoll(id) end
    return
  end
  local ended, endedId = G.rollEndFromChat(text)
  if ended then G.endRoll(endedId) return end
  local id, link, secs = G.rollFromChat(text)
  if not id then return end
  local roll = G.startRoll(id, link, secs, GetTime())
  C_Timer.After(roll.ends - GetTime() + 2, function() if G.roll == roll then G.endRoll() end end)
end)
