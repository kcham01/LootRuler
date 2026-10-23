-- The Reserve screen: your reserves at the top, then the raid's loot boss by boss. Click an item to
-- reserve it, right-click to take a reserve back.
local _, LR = ...
local U, K, S = LR.U, LR.K, LR.Session
local UI = LR.UI

--- what to tell someone about their picks not having reached the leader yet
local function pendingNote(s)
  local m = LR.inGroup(s.leader)
  if m and m.online then return "Sending your reserves to " .. U.short(s.leader) .. "..." end
  return U.short(s.leader) .. " isn't online in your group right now: your reserves go to them as soon as their addon is back."
end

local function noSession(f)
  f:panel("No soft reserves open", function(p)
    if IsInGroup() then
      p:text("Nobody in your group has opened soft reserves in LootRuler yet.")
      p:note("When the raid leader opens them, they show up here. If they don't use the addon, nothing is lost: they can still whisper you about reserves the usual way.")
    else
      p:text("Join your raid group, or wait for your raid leader to open soft reserves in LootRuler. If they share them with the guild, they show up here even before the group is made.")
    end
    p:gap(4)
    p:buttons({
      { label = "Look again", click = function() LR.query() UI.toast("Asking your group and guild for open reserves...") end },
      { label = "Open reserves myself", click = function() UI.go("session") end },
    })
  end)
end

local function myReserves(f, s)
  local picks = LR.myPicks(s)
  f:panel("Your reserves", function(p)
    local left = s.sr - #picks
    local line = left > 0 and ("%s left of %d."):format(U.plural(left, "reserve"), s.sr) or ("All %d used."):format(s.sr)
    if s.dupes then line = line .. " You can put more than one on the same item." end
    p:text(line)
    if s.locked then p:note("|cffff5a4aReserves are locked.|r Ask " .. (LR.isLeader(s) and "yourself" or U.short(s.leader)) .. " if something needs changing.") end
    if LR.pending(s) then p:note(pendingNote(s), K.GOLD) end
    p:gap(2)
    if #picks == 0 then
      p:note("Nothing reserved yet: pick from the list below.")
    end
    local counts, order = {}, {}
    for _, id in ipairs(picks) do
      if not counts[id] then order[#order + 1] = id end
      counts[id] = (counts[id] or 0) + 1
    end
    for _, id in ipairs(order) do
      local b = K.get(p.owner, "item", p.parent)
      local others = UI.whoLine(s, id, 4)
      K.setItem(b, p.width, LR.itemIcon(id), LR.coloredName(id), LR.itemKind(id) .. (others and ("  -  " .. others) or ""),
        counts[id] > 1 and ("x" .. counts[id]) or "",
        not s.locked and { text = "x", tip = "Take this reserve back", click = function()
          local ok, why = LR.unreserve(s, id)
          if not ok then UI.refused(why) end
        end } or nil)
      b:SetScript("OnEnter", function(self) UI.itemTooltip(self, s, id) end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      p:place(b, 36)
      p:gap(3)
    end
  end)
end

function UI.reserveView(f, s)
  if not s then return noSession(f) end
  myReserves(f, s)

  local myClass = LR.myClass()
  local faction = UnitFactionGroup("player")
  f:chips({
    { label = "Usable by me", on = UI.usable, click = function() UI.usable = not UI.usable LR.db.ui.usable = UI.usable UI.render() end,
      tip = "Only show items your class can use (tier tokens for your class, armour you can wear, weapons you can learn)." },
    { label = "Reserved only", on = UI.reservedOnly, click = function() UI.reservedOnly = not UI.reservedOnly UI.render() end,
      tip = "Only show items someone has reserved." },
  })

  -- search
  local e = K.get(f.owner, "edit", f.parent)
  f:place(e, 22, 6, f.width - 12)
  e:SetText(UI.q or "")
  local hint = K.get(f.owner, "label", f.parent)
  hint.text:SetFontObject("GameFontDisableSmall")
  hint.text:SetText("Search items")
  hint:SetPoint("LEFT", e, "LEFT", 4, 0)
  hint:SetSize(200, 14)
  hint.text:SetJustifyV("MIDDLE")
  hint:SetShown((UI.q or "") == "")
  local seq = 0
  e:SetScript("OnTextChanged", function(self, user)
    hint:SetShown(self:GetText() == "")
    if not user then return end
    UI.q = self:GetText()
    UI.searchFocus = true
    seq = seq + 1
    local mine = seq
    C_Timer.After(0.15, function() if mine == seq then UI.render() end end)
  end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() UI.searchFocus = false end)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() UI.searchFocus = false end)
  if UI.searchFocus then K.refocus(e) end
  f:gap(8)

  local q = U.lower(UI.q)
  local byItem = S.byItem(s)
  local picks = LR.myPicks(s)
  local shown = 0
  for _, boss in ipairs(LR.raid(s.raid).bosses) do
    local ids = {}
    for _, id in ipairs(boss.items) do
      local ok = LR.forFaction(id, faction)
      if ok and UI.usable and not LR.usableBy(id, myClass) and not U.indexOf(picks, id) then ok = false end
      if ok and UI.reservedOnly and not byItem[id] and not s.hr[id] then ok = false end
      if ok and q ~= "" then
        local name = LR.itemName(id):lower()
        local english = (LR.ITEMS[id] and LR.ITEMS[id][1] or ""):lower()
        if not (name:find(q, 1, true) or english:find(q, 1, true) or LR.itemKind(id):lower():find(q, 1, true) or boss.name:lower():find(q, 1, true)) then ok = false end
      end
      if ok then ids[#ids + 1] = id end
    end
    if #ids > 0 then
      local h = K.get(f.owner, "head", f.parent)
      h.text:SetText(boss.name)
      h.right:SetText(U.plural(#ids, "item"))
      h:SetWidth(f.width)
      f:place(h, 22)
      f:gap(4)
      for _, id in ipairs(ids) do
        local b = K.get(f.owner, "item", f.parent)
        local hr = s.hr[id]
        local mine = U.count(picks, id)
        local sub = LR.itemKind(id)
        local who = UI.whoLine(s, id, 3)
        if hr then sub = "|cffff5a4aHard reserved" .. (hr.f ~= "" and (" for " .. hr.f) or "") .. "|r"
        elseif who then sub = sub .. "  -  " .. who end
        local badge = hr and "|cffff5a4aHR|r" or (mine > 0 and ("|cff1eff00" .. (mine > 1 and ("x" .. mine) or "Yours") .. "|r") or "")
        K.setItem(b, f.width, LR.itemIcon(id), LR.coloredName(id), sub, badge)
        if hr then b.icon:SetDesaturated(true) b:SetBackdropColor(0.15, 0.03, 0.02, 0.5) end
        if mine > 0 then b:SetBackdropColor(0.05, 0.18, 0.03, 0.6) b:SetBackdropBorderColor(0.12, 0.6, 0.1, 0.8) end
        b:SetScript("OnClick", function(_, button)
          local ok, why
          if button == "RightButton" then
            if mine == 0 then return end
            ok, why = LR.unreserve(s, id)
          else
            if IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(LR.itemLink(id)) return end
            ok, why = LR.reserve(s, id)
          end
          if not ok then UI.refused(why) end
        end)
        b:SetScript("OnEnter", function(self)
          UI.itemTooltip(self, s, id)
          GameTooltip:AddLine(" ")
          GameTooltip:AddLine(hr and "Hard reserved: it can't be soft reserved." or "Click to reserve, right-click to take a reserve back.", 0.5, 0.8, 1, true)
          GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f:place(b, 36)
        f:gap(3)
        shown = shown + 1
      end
      f:gap(6)
    end
  end
  if shown == 0 then
    f:note(q ~= "" and "Nothing matches your search." or "Nothing to show with these filters.")
  end
end
