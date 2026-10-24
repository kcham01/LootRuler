-- The Reserves screen: everything everyone reserved, by item or by player, the hard reserves, and who
-- in the group hasn't reserved yet. The leader can take reserves away, add them for people, and send it
-- all to Gargul from here.
local _, LR = ...
local U, K, S = LR.U, LR.K, LR.Session
local UI = LR.UI

--- the leader's tools for the whole list
local function leaderTools(f, s)
  local gargul = LR.Gargul.available()
  f:panel("Raid leader", function(p)
    local sent = s.sentToGargul
    if gargul then
      if sent == s.rev then p:note("Gargul has the reserves as they are now.", K.GREEN)
      elseif sent then p:note("Reserves changed since they went to Gargul: send them again.", K.GOLD)
      else p:note("Send the reserves to Gargul when everyone's in. Locking the reserves sends them too.") end
    else
      p:note("Gargul isn't loaded on this character. Copy the reserves and paste them into Gargul's soft-reserve importer (/gl sr) on the character running loot.")
    end
    p:buttons({
      { label = "Send to Gargul", disabled = not gargul, click = function()
        local ok, why = LR.Gargul.send(s, true)
        UI.toast(ok and "Gargul has the reserves." or why)
        UI.render()
      end },
      { label = "Copy for Gargul", click = function()
        UI.copyBox("Copy for Gargul", "Press Ctrl+C, then paste it into Gargul's soft-reserve importer (/gl sr). softres.it's \"Gargul export\" is the same kind of text.", LR.Gargul.export(s))
      end },
    }, "left")
    p:buttons({
      { label = s.locked and "Unlock reserves" or "Lock reserves", click = function() LR.setLocked(s, not s.locked) end },
      { label = "Post in raid chat", disabled = LR.groupChannel() == nil, click = function()
        if LR.Whisper.announce(s) then UI.toast("Posted.") end
      end },
    }, "left")
  end)
end

--- picks an item for something (a sheet), then calls done(id): from the session's raid, the items it knows
--- of, or any item shift-clicked into the box (when the session allows it)
function UI.pickItem(s, title, done, filter)
  local q = ""
  UI.openSheet(title, function(f, h)
    local e = K.get(f.owner, "edit", f.parent)
    f:place(e, 22, 6, f.width - 12)
    e:SetText(q)
    e:SetScript("OnTextChanged", function(self, user)
      if not user then return end
      q = self:GetText()
      h.redraw(true)
      K.refocus(K.lastEdit)
    end)
    K.takeLinks(e)
    K.lastEdit = e
    f:gap(6)
    local function row(id)
      local b = K.get(f.owner, "item", f.parent)
      K.setItem(b, f.width, LR.itemIcon(id), LR.coloredName(id), LR.itemKind(id), s.hr[id] and "|cffff5a4aHR|r" or "")
      b:SetScript("OnClick", function() h.close() done(id) end)
      b:SetScript("OnEnter", function(self) UI.itemTooltip(self, s, id) end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      f:place(b, 36)
      f:gap(2)
    end
    local function head(text)
      local hd = K.get(f.owner, "head", f.parent)
      hd.text:SetText(text)
      hd:SetWidth(f.width)
      f:place(hd, 22)
      f:gap(3)
    end
    local raid = LR.raidOf(s)
    local linked = LR.idFrom(q)
    if linked then
      if LR.allowedItem(s, linked) and (not filter or filter(linked)) then head("Linked item") row(linked)
      else f:note(("That item doesn't drop in %s. Allow any item (Session tab) to use it."):format(raid.name), K.GOLD) end
      return
    end
    f:note(s.any and "Pick one, or shift-click any item into the box." or "Pick one, or search by name.")
    local want = U.lower(q)
    local faction = UnitFactionGroup("player")
    for _, boss in ipairs(raid.bosses) do
      local first = true
      for _, id in ipairs(boss.items) do
        local name = LR.itemName(id):lower()
        if LR.forFaction(id, faction) and (not filter or filter(id)) and (want == "" or name:find(want, 1, true) or boss.name:lower():find(want, 1, true)) then
          if first then head(boss.name) first = false end
          row(id)
        end
      end
    end
    local first = true
    for _, id in ipairs(LR.sessionItems(s)) do
      if not raid.has[id] and (not filter or filter(id)) and (want == "" or LR.itemName(id):lower():find(want, 1, true)) then
        if first then head(raid.custom and "Reserved and dropped" or "Other items") first = false end
        row(id)
      end
    end
  end, { full = true })
end

--- picks someone in the group (a sheet), then calls done("Name-Realm")
function UI.pickPlayer(title, done)
  UI.openSheet(title, function(f, h)
    local people = LR.roster()
    if #people == 0 then people = { { name = U.me(), class = LR.myClass() } } end
    table.sort(people, function(a, b) return a.name < b.name end)
    local chips = {}
    for _, m in ipairs(people) do
      chips[#chips + 1] = { label = U.classText(U.short(m.name), m.class), click = function() h.close() done(m.name) end }
    end
    f:chips(chips)
  end)
end

local function byItem(f, s, leader)
  local hr = U.keys(s.hr)
  if #hr > 0 then
    f:panel("Hard reserves", function(p)
      for _, id in ipairs(hr) do
        local h = s.hr[id]
        local b = K.get(p.owner, "item", p.parent)
        local sub = (h.f ~= "" and ("For " .. h.f) or "Not soft reservable") .. (h.n ~= "" and ("  -  " .. h.n) or "")
        K.setItem(b, p.width, LR.itemIcon(id), LR.coloredName(id), sub, "|cffff5a4aHR|r")
        b:SetScript("OnEnter", function(self) UI.itemTooltip(self, s, id) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p:place(b, 36)
        p:gap(3)
      end
    end)
  end
  local list = S.byItem(s)
  local total = 0
  for _ in pairs(list) do total = total + 1 end
  f:panel("Soft reserves", function(p)
    if total == 0 then p:note("Nobody has reserved anything yet.") return end
    for _, boss in ipairs(LR.raidOf(s).bosses) do
      local ids = U.filter(boss.items, function(id) return list[id] ~= nil end)
      if #ids > 0 then
        local hd = K.get(p.owner, "head", p.parent)
        hd.text:SetText(boss.name)
        hd:SetWidth(p.width)
        p:place(hd, 22)
        p:gap(3)
        for _, id in ipairs(ids) do
          local who = list[id]
          local n = 0
          for _, w in ipairs(who) do n = n + w[2] end
          local b = K.get(p.owner, "item", p.parent)
          K.setItem(b, p.width, LR.itemIcon(id), LR.coloredName(id), UI.whoLine(s, id), n > 1 and (n .. " SR") or "1 SR")
          b:SetScript("OnEnter", function(self) UI.itemTooltip(self, s, id) end)
          b:SetScript("OnLeave", function() GameTooltip:Hide() end)
          p:place(b, 36)
          p:gap(3)
        end
        for _, id in ipairs(ids) do list[id] = nil end    -- an item two bosses drop is shown under the first
      end
    end
    -- reserves on items that aren't the raid's own loot (any item allowed, or a raid not in the lists)
    local rest = {}
    for id in pairs(list) do rest[#rest + 1] = id end
    table.sort(rest)
    if #rest > 0 then
      local hd = K.get(p.owner, "head", p.parent)
      hd.text:SetText(LR.raidOf(s).custom and "Reserved items" or "Other items")
      hd:SetWidth(p.width)
      p:place(hd, 22)
      p:gap(3)
      for _, id in ipairs(rest) do
        local n = 0
        for _, w in ipairs(list[id]) do n = n + w[2] end
        local b = K.get(p.owner, "item", p.parent)
        K.setItem(b, p.width, LR.itemIcon(id), LR.coloredName(id), UI.whoLine(s, id), n > 1 and (n .. " SR") or "1 SR")
        b:SetScript("OnEnter", function(self) UI.itemTooltip(self, s, id) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p:place(b, 36)
        p:gap(3)
      end
    end
  end)
end

local function byPlayer(f, s, leader)
  -- everyone in the group, and everyone who reserved
  local people, seen = {}, {}
  for _, p in ipairs(S.players(s)) do people[#people + 1] = { name = p.name, class = p.class } seen[p.name:lower()] = true end
  local missing = 0
  for _, m in ipairs(LR.roster()) do
    if not seen[m.name:lower()] then
      people[#people + 1] = { name = m.name, class = m.class, none = true }
      seen[m.name:lower()] = true
      missing = missing + 1
    end
  end
  table.sort(people, function(a, b)
    if (a.none or false) ~= (b.none or false) then return b.none == true end
    return a.name < b.name
  end)
  if missing > 0 then f:note(("%s in the group %s reserved anything yet."):format(U.plural(missing, "player"), missing == 1 and "hasn't" or "haven't"), K.GOLD) end
  -- who in the group we haven't heard from a LootRuler of: they reserve by whisper
  local without = 0
  for _, m in ipairs(LR.roster()) do if not LR.versionOf(m.name) then without = without + 1 end end
  if without > 0 then
    f:note(("%s in the group %s LootRuler, as far as your addon can tell: they can whisper %s \"!lr [item]\"."):format(
      U.plural(without, "player"), without == 1 and "doesn't have" or "don't have", leader and "you" or U.short(s.leader)))
  end
  for _, person in ipairs(people) do
    local items = S.reservesOf(s, person.name)
    local class = person.class or LR.classOf(person.name)
    local hd = K.get(f.owner, "head", f.parent)
    local inGroup = LR.inGroup(person.name)
    hd.text:SetText(U.classText(U.short(person.name), class) .. ((inGroup and not LR.versionOf(person.name)) and "  |cff9d9d9dno addon|r" or ""))
    local po = s.plusOne and S.plusOnes(s, person.name) or 0
    hd.right:SetText((person.none and "|cffffd100nothing reserved|r" or (#items .. " / " .. s.sr)) .. (po > 0 and ("  |cff1eff00+" .. po .. "|r") or ""))
    hd:SetWidth(f.width)
    f:place(hd, 22)
    f:gap(3)
    for _, id in ipairs(items) do
      local b = K.get(f.owner, "item", f.parent)
      K.setItem(b, f.width, LR.itemIcon(id), LR.coloredName(id), LR.itemKind(id), "",
        leader and { text = "x", tip = "Take this reserve away from " .. U.short(person.name), click = function()
          local ok, why = LR.leaderRemove(s, person.name, id)
          if not ok then UI.refused(why) end
        end } or nil)
      b:SetScript("OnEnter", function(self) UI.itemTooltip(self, s, id) end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      f:place(b, 36)
      f:gap(2)
    end
    if leader then
      local list = {}
      if #items < s.sr then
        list[#list + 1] = { label = "Add a reserve for " .. U.short(person.name), click = function()
          UI.pickItem(s, "Reserve for " .. U.short(person.name), function(id)
            local ok, why = LR.leaderAdd(s, person.name, class, id)
            if not ok then UI.refused(why) end
          end, function(id) return not s.hr[id] end)
        end }
      end
      if s.plusOne then
        list[#list + 1] = { label = "+1", width = 44, click = function() LR.adjustPlusOne(s, person.name, 1) end }
        list[#list + 1] = { label = "-1", width = 44, disabled = po == 0, click = function() LR.adjustPlusOne(s, person.name, -1) end }
      end
      if #list > 0 then f:buttons(list, "left") end
    end
    f:gap(6)
  end
end

function UI.reservesView(f, s)
  if not s then
    f:panel("No soft reserves open", function(p)
      p:text("There's nothing to show until someone opens soft reserves. The raid leader does that on the Session tab.")
    end)
    return
  end
  local leader = LR.isLeader(s)
  if leader then leaderTools(f, s) end
  f:chips({
    { label = "By item", on = UI.view == "item", click = function() UI.view = "item" UI.render() end },
    { label = "By player", on = UI.view == "player", click = function() UI.view = "player" UI.render() end },
  })
  if UI.view == "player" then byPlayer(f, s, leader) else byItem(f, s, leader) end
end
