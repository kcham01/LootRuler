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
      p:text("Nobody in your group has opened soft reserves in LootRuler yet. When the raid leader does, they show up here.")
    else
      p:text("When your raid leader opens soft reserves in LootRuler, they show up here: in your group, or before that if they share them with the guild.")
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
    local limit = S.limit(s, U.me())
    local extra = S.extra(s, U.me())
    local left = limit - #picks
    local line = (left > 0 and ("%s left of %d."):format(U.plural(left, "reserve"), limit) or ("All %d used."):format(limit))
      .. (extra > 0 and (" (" .. U.short(s.leader) .. " gave you " .. U.plural(extra, "extra reserve") .. ".)") or "")
    if s.dupes then line = line .. " You can put more than one on the same item." end
    p:text(line)
    if s.locked then
      p:note("|cffff5a4aReserves are locked.|r Ask " .. (LR.isLeader(s) and "yourself" or U.short(s.leader)) .. " if something needs changing.")
      -- a swap request (Core/Swap.lua): one of mine for another item, the leader allows it
      local asked = LR.Swap.mine[s.id]
      if asked then
        p:note(("You asked to swap %s for %s: waiting for %s."):format(LR.coloredName(asked.from), LR.coloredName(asked.to), U.short(s.leader)), K.GOLD)
      elseif not LR.isLeader(s) and #picks > 0 then
        p:buttons({ { label = "Ask to swap one", click = function() UI.swapSheet(s) end } }, "left")
      end
    end
    if s.go and not LR.isLeader(s) and not LR.inGroup(s.leader) then
      p:note(("|cffffd100Only players in %s's group can reserve.|r Ask them for an invite first."):format(U.short(s.leader)))
    end
    if LR.pending(s) then p:note(pendingNote(s), K.GOLD) end
    p:gap(2)
    if #picks == 0 then
      p:note(LR.raidOf(s).custom and "Nothing reserved yet: shift-click an item into the box below." or "Nothing reserved yet: pick from the list below.")
    end
    local counts, order = {}, {}
    for _, id in ipairs(picks) do
      if not counts[id] then order[#order + 1] = id end
      counts[id] = (counts[id] or 0) + 1
    end
    for _, id in ipairs(order) do
      local b = K.get(p.owner, "item", p.parent)
      local others = UI.whoLine(s, id, 4, U.me())
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

--- asking to swap a reserve once they're locked: which of mine, then which item instead
function UI.swapSheet(s)
  UI.openSheet("Swap a reserve", function(f, h)
    f:note(("Pick the reserve you'd give up, then the item you'd like instead. %s decides."):format(U.short(s.leader)))
    local seen = {}
    for _, id in ipairs(LR.myPicks(s)) do
      if not seen[id] then
        seen[id] = true
        local b = K.get(f.owner, "item", f.parent)
        K.setItem(b, f.width, LR.itemIcon(id), LR.coloredName(id), LR.itemKind(id), "", { text = "Swap", width = 50, click = function()
          h.close()
          UI.pickItem(s, ("Swap %s for which item?"):format(LR.itemName(id)), function(to)
            local ok, why = LR.Swap.request(s, id, to)
            UI.toast(ok and "Asked: you'll be told by whisper." or why)
          end, function(to) return to ~= id and not s.hr[to] end)
        end })
        f:place(b, 36)
        f:gap(2)
      end
    end
  end)
end

--- the search box (keeps its text and the cursor across redraws)
--- the words inside a session's search box
function UI.searchHint(s)
  local raid = LR.raidOf(s)
  if raid.custom then return "Shift-click any item into here, or type its name" end
  return "Search " .. raid.name .. (s.any and ", or shift-click any item" or "")
end

local function searchBox(f, placeholder)
  local e = K.get(f.owner, "edit", f.parent)
  f:place(e, 22, 6, f.width - 12)
  e:SetText(UI.q or "")
  K.setHint(e, placeholder)
  local seq = 0
  K.onText(e, function(self, user)
    if not user then return end
    UI.q = self:GetText()
    UI.searchFocus = true
    seq = seq + 1
    local mine = seq
    C_Timer.After(0.15, function() if mine == seq then UI.render() end end)
  end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() UI.searchFocus = false end)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() UI.searchFocus = false end)
  K.takeLinks(e)
  if UI.searchFocus then K.refocus(e) end
  f:gap(8)
end

local function matches(q, id, boss)
  if q == "" then return true end
  local name = LR.itemName(id):lower()
  local english = (LR.ITEMS[id] and LR.ITEMS[id][1] or ""):lower()
  return name:find(q, 1, true) or english:find(q, 1, true) or LR.itemKind(id):lower():find(q, 1, true) or boss.name:lower():find(q, 1, true)
end

local LIMIT = 200

--- one item to reserve: click reserves, right-click takes a reserve back (with a session); key: the raid
--- it's listed under, for the tooltip
function UI.reserveRow(f, s, id, key, picks)
  picks = picks or (s and LR.myPicks(s) or {})
  local b = K.get(f.owner, "item", f.parent)
  local hr = s and s.hr[id]
  local mine = U.count(picks, id)
  local sub = LR.itemKind(id)
  local who = s and UI.whoLine(s, id, 3)
  if hr then sub = "|cffff5a4aHard reserved" .. (hr.f ~= "" and (" for " .. hr.f) or "") .. "|r"
  elseif who then sub = (sub ~= "" and (sub .. "  -  ") or "") .. who end
  local badge = hr and "|cffff5a4aHR|r" or (mine > 0 and ("|cff1eff00" .. (mine > 1 and ("x" .. mine) or "Yours") .. "|r") or "")
  K.setItem(b, f.width, LR.itemIcon(id), LR.coloredName(id), sub, badge)
  if hr then b.icon:SetDesaturated(true) b:SetBackdropColor(0.15, 0.03, 0.02, 0.5) end
  if mine > 0 then b:SetBackdropColor(0.05, 0.18, 0.03, 0.6) b:SetBackdropBorderColor(0.12, 0.6, 0.1, 0.8) end
  b:SetScript("OnClick", function(_, button)
    if UI.modifiedClick(LR.itemLink(id)) then return end
    if not s then return end
    local ok, why
    if button == "RightButton" then
      if mine == 0 then return end
      ok, why = LR.unreserve(s, id)
    else
      ok, why = LR.reserve(s, id)
    end
    if not ok then UI.refused(why) end
  end)
  b:SetScript("OnEnter", function(self)
    UI.itemTooltip(self, s, id, key)
    GameTooltip:AddLine(" ")
    if not s then GameTooltip:AddLine("Shift-click to link it in chat, Ctrl-click to try it on.", 0.5, 0.8, 1, true)
    else GameTooltip:AddLine(hr and "Hard reserved: it can't be soft reserved." or "Click to reserve, right-click to take a reserve back.", 0.5, 0.8, 1, true) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f:place(b, 36)
  f:gap(3)
  return b
end

---------------------------------------------------------------------- bosses that open and close
--- which bosses are open (saved, per character): "<where>:<raid>:<boss>" -> true. Closed to start with.
local function bossesOpen()
  if type(LR.db.ui.bossOpen) ~= "table" then LR.db.ui.bossOpen = {} end
  return LR.db.ui.bossOpen
end
--- one boss's items as a section that opens and closes (`where` keeps each tab's apart); `force` opens it (a search)
function UI.bossFold(f, where, key, name, what, fill, force)
  local open, k = bossesOpen(), where .. ":" .. key .. ":" .. name
  f:fold(name, what, force or open[k] == true, function() open[k] = not open[k] or nil UI.render() end, fill)
end
--- whether a boss's section is open
function UI.bossIsOpen(where, key, name) return bossesOpen()[where .. ":" .. key .. ":" .. name] == true end
--- "Open all" / "Close all" for these bosses: { { key, name }, ... }
function UI.bossChips(f, where, list)
  local open = bossesOpen()
  f:chips({
    { label = "Open all", click = function() for _, b in ipairs(list) do open[where .. ":" .. b[1] .. ":" .. b[2]] = true end UI.render() end,
      tip = "Opens every boss below." },
    { label = "Close all", click = function() for _, b in ipairs(list) do open[where .. ":" .. b[1] .. ":" .. b[2]] = nil end UI.render() end,
      tip = "Closes every boss, so you see just their names." },
  })
end

--- the loot of one or more raids, boss by boss, each opening and closing (searching or "Reserved only" opens the bosses
--- with a match). With a session the rows reserve; without, they only show.
local function lootList(f, keys, s)
  local myClass = LR.myClass()
  local faction = UnitFactionGroup("player")
  local q = U.lower(U.trim(UI.q))
  local byItem = s and S.byItem(s) or {}
  local picks = s and LR.myPicks(s) or {}
  local force = q ~= "" or (s and UI.reservedOnly)
  local found, sections = 0, {}
  for _, key in ipairs(keys) do
    local raid = LR.raid(key)
    for _, boss in ipairs(raid.bosses) do
      local ids = {}
      for _, id in ipairs(boss.items) do
        local ok = LR.forFaction(id, faction)
        if ok and UI.usable and not LR.forClass(id, myClass) and not U.indexOf(picks, id) then ok = false end
        if ok and s and UI.reservedOnly and not byItem[id] and not s.hr[id] then ok = false end
        if ok and not matches(q, id, boss) then ok = false end
        if ok then ids[#ids + 1] = id end
      end
      if #ids > 0 then sections[#sections + 1] = { key = key, raid = raid, boss = boss, ids = ids } found = found + #ids end
    end
  end
  if found == 0 then f:note(q ~= "" and "Nothing matches your search." or "Nothing to show with these filters.") return end
  if not force then UI.bossChips(f, "reserve", U.map(sections, function(x) return { x.key, x.boss.name } end)) end
  local shown, more, lastRaid = 0, 0, nil
  for _, x in ipairs(sections) do
    if #keys > 1 and x.raid ~= lastRaid then
      f:text(x.raid.name, { font = "GameFontNormalLarge", color = K.GOLD, gap = 2 })
      lastRaid = x.raid
    end
    local mine = 0
    for _, id in ipairs(x.ids) do if U.indexOf(picks, id) then mine = mine + 1 end end
    local what = U.plural(#x.ids, "item") .. (mine > 0 and (", " .. mine .. " reserved by you") or "")
    local open = force or UI.bossIsOpen("reserve", x.key, x.boss.name)
    if open and shown >= LIMIT then
      more = more + #x.ids
    else
      UI.bossFold(f, "reserve", x.key, x.boss.name, what, function(p)
        for _, id in ipairs(x.ids) do UI.reserveRow(p, s, id, x.key, picks) end
      end, force)
      if open then shown = shown + #x.ids end
    end
  end
  if more > 0 then f:note(("...and %d more. Search to narrow it down."):format(more), K.GOLD) end
end

--- looking through any raid's loot without a session
local function browse(f)
  UI.browse = UI.browse or "Karazhan"
  f:panel("Browse the loot", function(p)
    for _, era in ipairs({ { "tbc", "Burning Crusade raids" }, { "classic", "Original raids" } }) do
      p:text(era[2], { font = "GameFontNormal", gap = 2 })
      local chips = {}
      for _, r in ipairs(LR.RAIDS) do
        if r.era == era[1] then chips[#chips + 1] = { label = r.name, on = UI.browse == r.key, click = function() UI.browse = r.key UI.render() end } end
      end
      p:chips(chips)
    end
    p:chips({ { label = "Search every raid", on = UI.browse == "all", click = function() UI.browse = "all" UI.render() end } })
  end)
  f:chips({
    { label = "For my class", on = UI.usable, click = function() UI.usable = not UI.usable LR.db.ui.usable = UI.usable UI.render() end,
      tip = "Only show what your class would reserve: tier tokens for your class, your kind of armour, weapons you can use." },
  })
  searchBox(f, UI.browse == "all" and "Search every raid's loot" or ("Search " .. LR.raid(UI.browse).name))
  if UI.browse ~= "all" and UI.preloaded ~= UI.browse then UI.preloaded = UI.browse LR.preload(UI.browse) end
  if UI.browse == "all" then
    if #U.trim(UI.q) < 2 then f:note("Type at least two letters to search every raid.") return end
    lootList(f, U.map(LR.RAIDS, function(r) return r.key end), nil)
  else
    lootList(f, { UI.browse }, nil)
  end
end

function UI.reserveView(f, s)
  if not s then
    noSession(f)
    return browse(f)
  end
  -- the organiser's message (Session tab: Your raid's name)
  if s.br and s.br.m and not LR.isLeader(s) then f:note((s.br.n and (s.br.n .. ": ") or "") .. s.br.m, K.GOLD) end
  if s.gdkp then
    f:panel("GDKP auctions", function(p)
      p:text(LR.raidOf(s).name .. " auctions its loot for gold: nobody reserves anything.")
      p:note("When an item is up, a window pops up with bids to click, or type an amount in raid chat. The highest bid buys it. The Session tab shows the pot and your share.")
    end)
    return
  end
  if s.prio == "only" then
    f:panel("Priority lists", function(p)
      p:text(LR.raidOf(s).name .. " goes by the guild's priority lists, not reserves: nobody reserves anything.")
      local book = LR.book()
      local mine = book and LR.Book.prioOf(book, U.me()) or {}
      if #mine == 0 then p:note("You're not on any priority list. The Guild tab has them.")
      else
        for _, x in ipairs(mine) do
          local b = K.get(p.owner, "item", p.parent)
          K.setItem(b, p.width, LR.itemIcon(x[1]), LR.coloredName(x[1]), "You're " .. LR.Prio.place(x[2]) .. ": " .. UI.prioLine(LR.Book.prio(book, x[1]), 4))
          b:SetScript("OnEnter", function(self) UI.itemTooltip(self, s, x[1]) end)
          b:SetScript("OnLeave", function() GameTooltip:Hide() end)
          p:place(b, 36)
          p:gap(2)
        end
      end
    end)
    return
  end
  myReserves(f, s)
  f:chips({
    not LR.raidOf(s).custom and { label = "For my class", on = UI.usable, click = function() UI.usable = not UI.usable LR.db.ui.usable = UI.usable UI.render() end,
      tip = "Only show what your class would reserve: tier tokens for your class, your kind of armour, weapons you can use." } or false,
    { label = "Reserved only", on = UI.reservedOnly, click = function() UI.reservedOnly = not UI.reservedOnly UI.render() end,
      tip = "Only show items someone has reserved." },
  })
  local raid = LR.raidOf(s)
  searchBox(f, UI.searchHint(s))
  -- an item linked (or its number typed) into the box: that item, whatever raid it's from
  local linked = LR.idFrom(UI.q)
  if linked then
    if C_Item and C_Item.RequestLoadItemDataByID and not C_Item.GetItemInfo(linked) then C_Item.RequestLoadItemDataByID(linked) end
    f:panel("Linked item", function(p)
      UI.reserveRow(p, s, linked, s.raid)
      if not LR.allowedItem(s, linked) then
        p:note(("It doesn't drop in %s, and only its loot can be reserved: %s can allow any item."):format(raid.name, U.short(s.leader)), K.GOLD)
      end
    end)
    return
  end
  if not raid.custom then lootList(f, { s.raid }, s) end
  -- items the session knows of that aren't the raid's own loot (or everything, for a raid not in the lists)
  local q = U.lower(U.trim(UI.q))
  local others = U.filter(LR.sessionItems(s), function(id)
    return not raid.has[id] and (q == "" or LR.itemName(id):lower():find(q, 1, true))
      and (not UI.reservedOnly or S.byItem(s)[id] or s.hr[id])
  end)
  if #others > 0 then
    local h = K.get(f.owner, "head", f.parent)
    h.text:SetText(raid.custom and "Reserved and dropped" or "Other items")
    h.right:SetText(U.plural(#others, "item"))
    h:SetWidth(f.width)
    f:place(h, 22)
    f:gap(4)
    local picks = LR.myPicks(s)
    for _, id in ipairs(others) do UI.reserveRow(f, s, id, nil, picks) end
  elseif raid.custom then
    f:note(q ~= "" and "Nothing reserved or dropped has that name. Shift-click the item itself into the box." or
      ("%s isn't in LootRuler's loot lists, so any item can be reserved: shift-click it into the box above (from your bags, a chat link, anywhere). Items others reserve, and items that drop, show up here."):format(raid.name))
  end
end
