-- The Reserves screen: everything everyone reserved, by item or by player, the hard reserves, and who
-- in the group hasn't reserved yet. The leader can take reserves away, add them for people, and send it
-- all to Gargul from here.
local _, LR = ...
local U, K, S = LR.U, LR.K, LR.Session
local UI = LR.UI

--- the swap requests waiting (Core/Swap.lua): allow or refuse each
local function swapRequests(f, s)
  local list = LR.Swap.pending(s)
  if #list == 0 then return end
  f:panel(("Swap requests (%d)"):format(#list), function(p)
    for _, r in ipairs(list) do
      p:text(("%s: %s for %s"):format(U.classText(U.short(r.p), LR.classOf(r.p)), LR.coloredName(r.from), LR.coloredName(r.to)), { gap = 2 })
      p:buttons({
        { label = "Allow", width = 80, click = function()
          local ok, why = LR.Swap.allow(s, r)
          UI.toast(ok and "Swapped." or ("Couldn't swap: " .. why))
        end },
        { label = "No", width = 80, click = function() LR.Swap.deny(s, r) end },
      }, "left")
    end
  end)
end

--- the leader's tools for the whole list
local function leaderTools(f, s)
  swapRequests(f, s)
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
    local missing = LR.groupChannel() and #LR.Whisper.notReserved(s) or 0
    p:buttons({
      { label = missing > 0 and ("Remind who hasn't reserved (" .. missing .. ")") or "Remind who hasn't reserved", disabled = missing == 0, click = function()
        local ok, why = LR.Whisper.remind(s)
        UI.toast(ok and ("Reminded %s in raid chat."):format(U.plural(why, "player")) or why)
      end },
    }, "left")
    -- reserves of players who aren't in the group (left, or never came): cleared after a confirm
    local away = LR.absent(s)
    p:buttons({
      { label = #away > 0 and ("Clear reserves of players not in the group (" .. #away .. ")") or "Clear reserves of players not in the group",
        disabled = #away == 0, click = function()
          local names = table.concat(U.map(away, U.short), ", ")
          UI.confirm("Clear their reserves", ("%s: not in the group, so their reserves are taken off (and their items are free for others). Someone offline but still in the group keeps theirs.%s"):format(
            names, s.sx and " Importing the softres.it sheet again would bring back what it gave them." or ""),
            "Clear " .. #away, function()
              local cleared = LR.clearAbsent(s)
              UI.toast(("Cleared the reserves of %s."):format(U.plural(#cleared, "player")))
            end)
        end },
    }, "left")
  end)
end

--- picks an item for something (a sheet), then calls done(id): from the session's raid, the items it knows
--- of, or any item shift-clicked into the box (when the session allows it).
--- many: pick several, for one player, without the sheet closing (it closes with Done, its X or Escape):
---   { player, class } - each click reserves the item for them; clicking an item added here again takes it off
function UI.pickItem(s, title, done, filter, many)
  local q = ""
  local added, said = {}, nil         -- (many) items added in this sheet, in order; what the last click did
  local who = many and U.short(many.player)
  local function addedAt(id) for i = #added, 1, -1 do if added[i] == id then return i end end end
  local function click(id, h)
    if not many then h.close() done(id) return end
    local i = addedAt(id)
    if i then
      local ok, why = LR.leaderRemove(s, many.player, id)
      if ok or why == "NOT_RESERVED" then table.remove(added, i) end     -- (or it went some other way meanwhile)
      if ok then said = { "Took " .. LR.coloredName(id) .. " off." }
      elseif why == "NOT_RESERVED" then said = { ("%s doesn't have %s reserved any more."):format(who, LR.coloredName(id)), true }
      else said = { S.WHY[why] or tostring(why), true } end
    else
      local ok, why = LR.leaderAdd(s, many.player, many.class, id)
      if ok then added[#added + 1] = id said = { "Added " .. LR.coloredName(id) .. "." }
      elseif why == "TOO_MANY" then said = { ("%s has no reserves left. Click an item added here to take it off."):format(who), true }
      elseif why == "DUPLICATE" then said = { ("%s already reserved %s, and this raid allows one each per item."):format(who, LR.coloredName(id)), true }
      else said = { S.WHY[why] or tostring(why), true } end
    end
    h.redraw(true)
  end
  UI.openSheet(title, function(f, h)
    local used, limit, full
    if many then
      used, limit = #S.reservesOf(s, many.player), S.limit(s, many.player)
      full = used >= limit
      -- the count stays in sight in the title, however far down the list is scrolled
      h.frame.title:SetText(("%s  |cffffd100(%d of %d left)|r"):format(title, math.max(0, limit - used), limit))
      local list = U.map(added, LR.coloredName)
      f:note(#added > 0 and ("Added for %s: %s. Click one again to take it off."):format(who, table.concat(list, ", "))
        or ("Click items to reserve them for %s. This stays open until you're done."):format(who))
      if said then f:note(said[1], said[2] and { 1, 0.35, 0.29 } or K.GREEN) end
      f:buttons({ { label = "Done", click = function() h.close() end } }, "left")
      f:gap(2)
    end
    local e = K.get(f.owner, "edit", f.parent)
    f:place(e, 22, 6, f.width - 12)
    e:SetText(q)
    K.setHint(e, UI.searchHint(s))
    K.onText(e, function(self, user)
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
      local badge = s.hr[id] and "|cffff5a4aHR|r" or ""
      if many and addedAt(id) then badge = "|cff1eff00Added|r"
      elseif many and U.indexOf(S.reservesOf(s, many.player), id) then badge = "|cffffd100Reserved|r" end
      K.setItem(b, f.width, LR.itemIcon(id), LR.coloredName(id), LR.itemKind(id), badge)
      if many and full and not addedAt(id) then b:SetAlpha(0.5) end
      b:SetScript("OnClick", function() click(id, h) end)
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

--- a name from softres.it that isn't anyone in the group (LR.Gargul.unmatched): who it could be, a click each
function UI.nameFix(f, s, x, after)
  local from = U.short(x.from)
  local list = x.options or x.near or {}
  if #list == 0 then return end
  if x.options then
    f:note(("%s (from softres.it) could be %s. Which is it?"):format(from, table.concat(U.map(list, U.short), " or ")), K.GOLD)
  else
    f:note(("Nobody in the group is called %s (from softres.it). Did the sheet mean %s?"):format(from, table.concat(U.map(list, U.short), " or ")), K.GOLD)
  end
  local buttons = {}
  for _, to in ipairs(list) do
    buttons[#buttons + 1] = { label = from .. " -> " .. U.short(to), click = function()
      local ok, why = LR.matchName(s, x.from, to)
      if ok then UI.toast(("%s's reserves from softres.it are %s's now."):format(from, U.short(to))) elseif why then UI.toast(why) end
      if after then after() end
    end }
  end
  f:buttons(buttons, "left")
end

--- what a softres.it import did (Session tab): the counts, names matched to the group's spelling, and names to check
function UI.importSummary(s, sum, line)
  UI.openSheet("From softres.it", function(f, h)
    f:text(line)
    if #sum.matched > 0 then
      f:gap(4)
      f:note("Spelled differently on the sheet, so matched to who's in the group: "
        .. table.concat(U.map(sum.matched, function(m) return U.short(m[1]) .. " is " .. U.short(m[2]) end), ", ") .. ".", K.GREEN)
    end
    -- (worked out again on every redraw: a name sorted out here, or by someone joining, drops off the list)
    local left = LR.Gargul.unmatched(s, LR.roster(), true)
    local waiting = {}
    for _, x in ipairs(left) do
      if (x.options and #x.options > 0) or (x.near and #x.near > 0) then f:gap(4) UI.nameFix(f, s, x, function() h.redraw(true) end)
      else waiting[#waiting + 1] = U.short(x.from) end
    end
    if #waiting > 0 then
      f:gap(4)
      f:note(("Not in the group yet: %s. When they join, their reserves count for them, even if the sheet left out an accent."):format(table.concat(waiting, ", ")))
    end
    f:gap(6)
    f:buttons({ { label = "Close", click = function() h.close() end } })
  end)
end

--- extra reserves (tanks, healers, whoever the leader likes): pick players, then how many extra each
function UI.extraSheet(s, preset)
  local picked, n = {}, 1
  for _, name in ipairs(preset or {}) do picked[U.full(name)] = true n = math.max(1, S.extra(s, name)) end
  UI.openSheet("Extra reserves", function(f, h)
    f:note(("Everyone gets %s. Pick who gets more (tanks and healers, say), and how many more."):format(U.plural(s.sr, "reserve")))
    local people = LR.roster()
    local seen = {}
    for _, m in ipairs(people) do seen[U.full(m.name)] = true end
    -- (players who reserved but aren't in the group yet, and anyone already given extra)
    for _, pl in ipairs(S.players(s)) do if not seen[pl.name] then people[#people + 1] = { name = pl.name, class = pl.class } seen[pl.name] = true end end
    for name in pairs(s.xr or {}) do if not seen[name] then people[#people + 1] = { name = name } seen[name] = true end end
    for name in pairs(picked) do if not seen[name] then people[#people + 1] = { name = name } seen[name] = true end end
    table.sort(people, function(a, b) return a.name < b.name end)
    local chips = {}
    for _, m in ipairs(people) do
      local on = picked[U.full(m.name)]
      local x = S.extra(s, m.name)
      chips[#chips + 1] = { label = (on and "[x] " or "[  ] ") .. U.classText(U.short(m.name), m.class or LR.classOf(m.name)) .. (x > 0 and ("  +" .. x) or ""), on = on,
        click = function() picked[U.full(m.name)] = not on or nil h.redraw(true) end }
    end
    if #chips == 0 then f:note("Nobody in the group yet.") else f:chips(chips) end
    local amounts = { { plain = true, label = "Extra each:" } }
    for i = 0, 3 do amounts[#amounts + 1] = { label = i == 0 and "None" or ("+" .. i), width = i == 0 and 48 or 36, on = n == i, click = function() n = i h.redraw(true) end } end
    f:chips(amounts)
    if n == 0 then f:note("None takes extra reserves away: the last ones they picked over the limit go.", K.GOLD) end
    f:gap(4)
    local count = 0
    for _ in pairs(picked) do count = count + 1 end
    f:buttons({
      { label = "Cancel", click = function() h.close() end },
      { label = count > 0 and ("Save for " .. U.plural(count, "player")) or "Save", disabled = count == 0, click = function()
        h.close()
        local lost = {}
        for name in pairs(picked) do
          local _, l = LR.setExtra(s, name, n)
          if l then lost[#lost + 1] = U.short(name) end
        end
        if #lost > 0 then LR.print(("%s lost the reserves they had over their new limit."):format(table.concat(lost, ", "))) end
      end },
    })
  end)
end

--- bringing in "Name,Number" lines (Gargul's +1s or boosted roll points): pasted, or read from Gargul itself.
--- opts: { title, note, gargul = "plusOnes" / "boosted", max, apply(list) }
function UI.countsSheet(opts)
  local pasted = ""
  UI.openSheet(opts.title, function(f, h)
    f:note(opts.note)
    local fromGargul = LR.Gargul.counts(opts.gargul)
    if fromGargul then
      f:buttons({ { label = "Read them from Gargul", click = function() pasted = fromGargul h.redraw(true) end } }, "left")
    end
    local m = K.get(f.owner, "memo", f.parent)
    f:place(m, 120, 0)
    m:SetSize(f.width, 120)
    m.edit:SetWidth(f.width - 20)
    m.edit:SetHeight(108)
    m.edit:SetScript("OnTextChanged", function(self, user) if user then pasted = self:GetText() h.redraw(true) end end)
    if m.edit:GetText() ~= pasted then m.edit:SetText(pasted) end
    f:gap(6)
    local list, why
    if U.trim(pasted) ~= "" then
      list, why = LR.Prio.parseCounts(pasted, opts.max)
      if list then f:note(("%s, from %s to %s."):format(U.plural(#list, "player"), U.short(list[1].p), U.short(list[#list].p)), K.GOLD)
      else f:note(why, { 1, 0.35, 0.29 }) end
    end
    f:buttons({
      { label = "Cancel", click = function() h.close() end },
      { label = "Bring them in", disabled = not list, click = function() h.close() opts.apply(list) end },
    })
  end)
end

--- text to copy, several lines (a sheet)
function UI.textSheet(title, note, text)
  UI.openSheet(title, function(f)
    f:note(note)
    local m = K.get(f.owner, "memo", f.parent)
    f:place(m, 200, 0)
    K.setMemo(m, f.width, 200, text)
    f:gap(4)
    f:note("It's all selected: press Ctrl+C to copy it.")
  end)
end

--- picks someone in the group (a sheet), then calls done("Name-Realm"). only(name): who may be picked; note:
--- a line about who's left out
function UI.pickPlayer(title, done, only, note)
  UI.openSheet(title, function(f, h)
    local people = LR.roster()
    if #people == 0 then people = { { name = U.me(), class = LR.myClass() } } end
    table.sort(people, function(a, b) return a.name < b.name end)
    local chips = {}
    for _, m in ipairs(people) do
      if not only or only(m.name) then
        chips[#chips + 1] = { label = U.classText(U.short(m.name), m.class), click = function() h.close() done(m.name) end }
      end
    end
    if note then f:note(note) end
    if #chips == 0 then f:note("Nobody in the group can be picked.", K.GOLD) else f:chips(chips) end
  end)
end

--- who to hand the reserves to: someone else in the group whose LootRuler can take them
function UI.pickLeader(title, done)
  UI.pickPlayer(title, done, function(name) return LR.canLead(name) and not U.samePlayer(name, U.me()) end,
    "Only players whose LootRuler can take the reserves over are listed. Players with an older LootRuler, or none, aren't.")
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
  local list = {}
  for id, who in pairs(S.byItem(s)) do list[id] = who end      -- (a copy: items are taken off it below)
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
  for _, p in ipairs(S.players(s)) do people[#people + 1] = { name = p.name, class = p.class } seen[U.foldCase(p.name)] = true end
  local missing = 0
  for _, m in ipairs(LR.roster()) do
    if not seen[U.foldCase(m.name)] then
      people[#people + 1] = { name = m.name, class = m.class, none = true }
      seen[U.foldCase(m.name)] = true
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
  -- names from softres.it that aren't anyone in the group, but could be (the leader picks)
  local fixes = {}
  if leader then for _, x in ipairs(LR.Gargul.unmatched(s, LR.roster())) do fixes[x.from] = x end end
  for _, person in ipairs(people) do
    local items = S.reservesOf(s, person.name)
    local class = person.class or LR.classOf(person.name)
    local hd = K.get(f.owner, "head", f.parent)
    local inGroup = LR.inGroup(person.name)
    hd.text:SetText(U.classText(U.short(person.name), class) .. ((inGroup and not LR.versionOf(person.name)) and "  |cff9d9d9dno addon|r" or ""))
    local po = s.plusOne and S.plusOnes(s, person.name) or 0
    local limit, extra = S.limit(s, person.name), S.extra(s, person.name)
    hd.right:SetText((person.none and "|cffffd100nothing reserved|r" or (#items .. " / " .. limit)) .. (extra > 0 and ("  |cff69ccf0+" .. extra .. " extra|r") or "")
      .. (po > 0 and ("  |cff1eff00+" .. po .. "|r") or ""))
    hd:SetWidth(f.width)
    f:place(hd, 22)
    f:gap(3)
    if fixes[person.name] then UI.nameFix(f, s, fixes[person.name]) end
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
      if #items < limit then
        list[#list + 1] = { label = "Add a reserve for " .. U.short(person.name), click = function()
          UI.pickItem(s, "Reserve for " .. U.short(person.name), nil, function(id) return not s.hr[id] end,
            { player = person.name, class = class })
        end }
      end
      local extra = S.extra(s, person.name)
      list[#list + 1] = { label = extra > 0 and ("Extra reserves: " .. extra) or "Extra reserves", click = function() UI.extraSheet(s, { person.name }) end }
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
