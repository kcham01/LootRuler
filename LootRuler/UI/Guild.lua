-- The Guild tab (shown to guild members): the guild book (Core/Book.lua), which lasts between raids and is
-- shared with everyone in the guild who has LootRuler. Boosted roll points and priority lists live here. The guild master and
-- the ranks they pick change it; everyone else sees it.
local _, LR = ...
local U, K, B = LR.U, LR.K, LR.Book
local UI = LR.UI
local Guild = LR.Guild

--- whether this guild has any priority lists (the Session tab only offers them then)
function UI.prioAvailable()
  local book = LR.book()
  if not book then return false end
  for _, e in pairs(book.prio) do if #e.list > 0 then return true end end
  return false
end

--- "Loot goes by": reserves, the guild's priority lists first, or only them (a session, or the new one)
UI.PRIO_MODES = {
  { nil, "Reserves", "Soft and hard reserves, then everyone rolls." },
  { "both", "Priority lists, then reserves", "An item on the guild's priority lists goes by them when someone on its list is here; anything else by reserves." },
  { "only", "Priority lists only", "No reserves: items on the priority lists go by them, everything else is rolled for." },
}
function UI.prioChips(current, pick)
  local chips = { { plain = true, label = "Loot goes by:" } }
  for _, m in ipairs(UI.PRIO_MODES) do
    chips[#chips + 1] = { label = m[2], on = current == m[1], click = function() pick(m[1]) end, tip = m[3] }
  end
  return chips
end

--- whether this guild uses boosted rolls (the Session tab's switch only shows then)
function UI.boostOn()
  local book = LR.book()
  return book ~= nil and book.boost.on
end

--- a sheet to set a player's points (name given: just the number)
local function pointsSheet(name)
  local who, n = name or "", name and tostring(B.points(LR.book(), name)) or ""
  UI.openSheet(name and ("Points for " .. U.short(name)) or "Give a player points", function(f, h)
    if not name then
      f:text("Player", { font = "GameFontNormal", gap = 2 })
      local e1 = K.get(f.owner, "edit", f.parent)
      f:place(e1, 22, 6, f.width - 12)
      e1:SetMaxLetters(40)
      e1:SetText(who)
      e1:SetScript("OnTextChanged", function(self) who = self:GetText() end)
      f:gap(6)
    end
    f:text("Points", { font = "GameFontNormal", gap = 2 })
    local e2 = K.get(f.owner, "edit", f.parent)
    f:place(e2, 22, 6, 80)
    e2:SetMaxLetters(4)
    e2:SetText(n)
    e2:SetScript("OnTextChanged", function(self) n = self:GetText() end)
    f:note(("0 to %d. A boosted roll is 1 to 100 plus the points."):format(B.MAX_POINTS))
    -- alts share their main's points: they roll with them and spend them
    if name then
      local book = LR.book()
      f:gap(4)
      f:text("Alts", { font = "GameFontNormal", gap = 2 })
      f:note("An alt rolls with " .. U.short(name) .. "'s points, and spends them if it wins.")
      for _, alt in ipairs(B.altsOf(book, name)) do
        f:chips({
          { plain = true, width = f.width - 120, label = U.classText(U.short(alt), LR.classOf(alt)) },
          { label = "Unlink", width = 60, tip = U.short(alt) .. " gets its own points again", click = function() Guild.unlinkAlt(alt) h.redraw(true) end },
        }, { gap = 2 })
      end
      f:note("Another alt's name:")
      local e3 = K.get(f.owner, "edit", f.parent)
      f:place(e3, 22, 6, 150)
      e3:SetMaxLetters(40)
      e3:SetText(h.altName or "")
      e3:SetScript("OnTextChanged", function(self) h.altName = self:GetText() end)
      f:buttons({ { label = "Link this alt", click = function()
        local alt = U.trim(h.altName or "")
        if alt == "" then UI.toast("Type the alt's name.") return end
        local ok, why = Guild.linkAlt(alt, name)
        if ok then h.altName = "" h.redraw(true) else UI.toast(why) end
      end } }, "left")
    end
    f:gap(6)
    f:buttons({
      { label = "Cancel", click = function() h.close() end },
      { label = "Save", click = function()
        local player = U.trim(who)
        local points = tonumber(n)
        if player == "" then UI.toast("Type the player's name.") return end
        if not points then UI.toast("Points are a number.") return end
        h.close()
        local ok, why = Guild.edit(function(book, now) return B.setPoints(book, player, points, now) end)
        if not ok then UI.refused(why) end
      end },
    })
  end)
end
UI.pointsSheet = pointsSheet

--- "Give raid points": everyone from the guild in the group, once per session (asks first)
function UI.giveRaidPoints(s, after)
  local book = LR.book()
  local who = Guild.raidMembers()
  if #who == 0 then UI.toast("Nobody from your guild is in the group.") return end
  local again = Guild.pointsGiven(s) and " You've already given points for this raid: this gives them again." or ""
  UI.confirm("Give raid points", ("%s from the guild in the group get %d points each.%s"):format(
    U.plural(#who, "player"), book.boost.perRaid, again), "Give points", function()
    local ok, why = Guild.raidPoints(s)
    if not ok then UI.refused(why) else UI.toast(("%s got %d points."):format(U.plural(#who, "player"), book.boost.perRaid)) end
    if after then after() end
  end)
end

local function boostPanel(f, book, editor)
  f:panel("Boosted rolls", function(p)
    p:note("Guild members get points for each raid they come to. In a session with boosted rolls on, a player with points can roll 1 to 100 plus their points on main spec (\"/roll 31 130\" with 30 points). If they win with it, their points are spent.")
    if editor then
      p:chips({ { tick = true, label = "Boosted rolls for this guild", on = book.boost.on, click = function()
        Guild.edit(function(b, now) return B.setBoost(b, not b.boost.on, b.boost.perRaid, now) end)
      end, tip = "Off: nobody's rolls are boosted, and the Session tab doesn't offer it." } }, { gap = 4 })
      local chips = { { plain = true, label = "Points for each raid:" } }
      for _, n in ipairs({ 5, 10, 15, 20, 25 }) do
        chips[#chips + 1] = { label = tostring(n), width = 32, on = book.boost.perRaid == n, click = function()
          Guild.edit(function(b, now) return B.setBoost(b, b.boost.on, n, now) end)
        end }
      end
      p:chips(chips, { gap = 4 })
      if book.boost.on then
        p:note("Turn boosted rolls on for a raid on the Session tab. Give the raid its points from there too, or when you end the session.")
      end
    else
      p:kv({
        { "Boosted rolls", book.boost.on and "On for this guild" or "Off" },
        { "Points for each raid", tostring(book.boost.perRaid) },
      })
    end
    local mine = B.points(book, U.me())
    p:gap(4)
    local main = B.mainOf(book, U.me())
    p:kv({ { "Your points", (mine > 0 and ("%d (a boosted roll is %d to %d)"):format(mine, B.boostRange(mine)) or "None yet")
      .. (U.samePlayer(main, U.me()) and "" or (", " .. U.short(main) .. "'s")), K.TEXT, K.GOLD } })
  end)
end

local function pointsPanel(f, book, editor)
  f:panel("Points", function(p)
    local list = {}
    -- (a linked alt is listed under its main)
    for name, e in pairs(book.points) do if e.n > 0 and B.mainOf(book, name) == name then list[#list + 1] = { name, e.n } end end
    table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    if #list == 0 then p:note("Nobody has points yet. They come from raids (Give raid points), or an officer can set them here.") end
    for _, x in ipairs(list) do
      local b = K.get(p.owner, "item", p.parent)
      local class = LR.classOf(x[1])
      local alts = B.altsOf(book, x[1])
      K.setItem(b, p.width, LR.LOGO, U.classText(U.short(x[1]), class), ("Boosted roll: /roll %d %d"):format(B.boostRange(x[2]))
        .. (#alts > 0 and ("  -  alts: " .. table.concat(U.map(alts, U.short), ", ")) or ""),
        "|cff1eff00" .. x[2] .. "|r", editor and { text = "Edit", width = 40, tip = "Change " .. U.short(x[1]) .. "'s points", click = function() pointsSheet(x[1]) end } or nil)
      p:place(b, 36)
      p:gap(2)
    end
    if editor then
      p:buttons({ { label = "Give a player points", click = function() pointsSheet(nil) end } }, "left")
      p:buttons({
        { label = "Bring in from Gargul", click = function()
          UI.countsSheet({ title = "Boosted roll points from Gargul", gargul = "boosted", max = B.MAX_POINTS,
            note = "Paste Gargul's boosted roll export (\"Name,Points,Alt,Alt\" lines; Gargul: /gl br, Export), or read it straight from Gargul if it's loaded. Each player's points are set to these, and their alts are linked to them.",
            apply = function(list)
              local ok, why = Guild.importPoints(list)
              if ok then UI.toast(("Points for %s are in, and shared with the guild."):format(U.plural(#list, "player"))) else UI.refused(why) end
            end })
        end },
        { label = "Copy out", disabled = #list == 0, click = function()
          UI.textSheet("Boosted roll points", "For Gargul's boosted roll importer, or a spreadsheet.",
            LR.Prio.countsText(U.map(list, function(x) return { p = x[1], n = x[2], alts = B.altsOf(book, x[1]) } end)))
        end },
      }, "left")
    end
  end)
end

local function whoPanel(f, book)
  f:panel("Who can change this", function(p)
    local ranks = {}
    for i = 1, GuildControlGetNumRanks() do ranks[#ranks + 1] = GuildControlGetRankName(i) or ("Rank " .. i) end
    local current = ranks[book.editRank + 1] or ("rank " .. (book.editRank + 1))
    if LR.isGuildMaster() then
      p:note("You're the guild master: pick the lowest rank that can change points and priority lists.")
      local chips = {}
      for i, name in ipairs(ranks) do
        chips[#chips + 1] = { label = i == 1 and "Only me" or (name .. (i < #ranks and " and up" or "")), on = book.editRank == i - 1, click = function()
          Guild.setEditRank(i - 1)
          UI.render()
        end }
      end
      p:chips(chips)
    else
      p:note(book.editRank == 0 and "Only the guild master can change points and priority lists."
        or ("The guild master and ranks up to %s can change points and priority lists."):format(current))
      p:note(LR.canEditBook() and "That includes you." or "Ask one of them to change your points.", LR.canEditBook() and K.GOLD or nil)
    end
  end)
end

---------------------------------------------------------------------- priority lists
local P = LR.Prio

--- an item's list in a line: "1. Ann, 2. Bob, Cara"
local function listLine(list, max)
  local parts, last = {}, nil
  for i, x in ipairs(list) do
    if i > (max or 6) then parts[#parts + 1] = "..." break end
    parts[#parts + 1] = (x.n ~= last and (x.n .. ". ") or "") .. U.short(x.p)
    last = x.n
  end
  return table.concat(parts, ", ")
end
UI.prioLine = listLine

--- the sheet to change one item's list (editors)
local function prioSheet(id)
  local who, num, note = "", "", ""
  local function save(list)
    local ok, why = Guild.edit(function(book, now) return B.setPrio(book, id, list, now) end)
    if not ok then UI.refused(why) end
  end
  UI.openSheet("Priority list", function(f, h)
    local book = LR.book()
    local list = B.prio(book, id)
    local b = K.get(f.owner, "item", f.parent)
    K.setItem(b, f.width, LR.itemIcon(id), LR.coloredName(id), LR.itemKind(id))
    b:SetScript("OnEnter", function(self) UI.itemTooltip(self, LR.current(), id) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:place(b, 36)
    f:gap(6)
    if #list == 0 then f:note("Nobody yet. Whoever is first gets it without a roll; players who share a place roll for it.") end
    for i, x in ipairs(list) do
      local copy = {}
      for j, y in ipairs(list) do copy[j] = { p = y.p, n = y.n, note = y.note } end
      f:chips({
        { plain = true, width = f.width - 116, label = ("%s  %s%s"):format(P.place(x.n), U.classText(U.short(x.p), LR.classOf(x.p)), x.note and ("  |cff9d9d9d" .. x.note .. "|r") or "") },
        { label = "Up", width = 36, click = function() copy[i].n = math.max(1, x.n - 1) save(copy) h.redraw(true) end, tip = "A better place (a lower number)" },
        { label = "Down", width = 44, click = function() copy[i].n = x.n + 1 save(copy) h.redraw(true) end, tip = "A worse place (a higher number)" },
        { label = "x", width = 24, click = function() table.remove(copy, i) save(copy) h.redraw(true) end, tip = "Take " .. U.short(x.p) .. " off the list" },
      }, { gap = 2 })
    end
    f:gap(8)
    f:text("Add a player", { font = "GameFontNormal", gap = 4 })
    f:note("Name")
    local e1 = K.get(f.owner, "edit", f.parent)
    f:place(e1, 22, 6, 150)
    e1:SetMaxLetters(40)
    e1:SetText(who)
    e1:SetScript("OnTextChanged", function(self) who = self:GetText() end)
    f:gap(4)
    f:note("Place (1 is first; players can share a place)")
    local e2 = K.get(f.owner, "edit", f.parent)
    f:place(e2, 22, 6, 50)
    e2:SetMaxLetters(3)
    e2:SetText(num ~= "" and num or tostring(#list > 0 and (list[#list].n + 1) or 1))
    e2:SetScript("OnTextChanged", function(self) num = self:GetText() end)
    f:gap(4)
    f:note("Note (if you like)")
    local e3 = K.get(f.owner, "edit", f.parent)
    f:place(e3, 22, 6, f.width - 12)
    e3:SetMaxLetters(60)
    e3:SetText(note)
    e3:SetScript("OnTextChanged", function(self) note = self:GetText() end)
    f:gap(8)
    f:buttons({
      { label = "Clear the list", disabled = #list == 0, click = function()
        UI.confirm("Clear the list", "Everyone comes off " .. LR.coloredName(id) .. "'s priority list: it's rolled for as usual.", "Clear it", function() save({}) end)
      end },
      { label = "Done", click = function() h.close() end },
      { label = "Add", click = function()
        local player, n = U.trim(who), tonumber(num ~= "" and num or e2:GetText())
        if player == "" then UI.toast("Type the player's name.") return end
        if not n or n < 1 then UI.toast("Their place is a number: 1 is first.") return end
        local copy = {}
        for j, y in ipairs(list) do if not U.samePlayer(y.p, player) then copy[#copy + 1] = { p = y.p, n = y.n, note = y.note } end end
        copy[#copy + 1] = { p = player, n = math.floor(n), note = U.trim(note) ~= "" and U.trim(note) or nil }
        save(copy)
        who, num, note = "", "", ""
        h.redraw(true)
      end },
    })
  end, { full = true })
end
UI.prioSheet = prioSheet

--- pasting lists from Gargul's CSV, DFT or thatsmybis (editors)
local function importSheet()
  local pasted, replaceAll = "", false
  UI.openSheet("Bring in priority lists", function(f, h)
    f:note("Paste the lists from your DFT sheet (its Gargul export), thatsmybis (the Gargul download), or Gargul's CSV (\"28525,Ann,Bob|Cara\": Bob and Cara share second).")
    local m = K.get(f.owner, "memo", f.parent)
    f:place(m, 140, 0)
    m:SetSize(f.width, 140)
    m.edit:SetWidth(f.width - 20)
    m.edit:SetHeight(128)
    m.edit:SetScript("OnTextChanged", function(self, user) if user then pasted = self:GetText() h.redraw(true) end end)
    if m.edit:GetText() ~= pasted then m.edit:SetText(pasted) end
    f:gap(6)
    local lists, kind = nil, nil
    if U.trim(pasted) ~= "" then
      local LibDeflate = LibStub and LibStub("LibDeflate", true)
      lists, kind = P.parse(pasted, LibDeflate and function(raw) return LibDeflate:DecompressZlib(raw) end)
      if lists then
        local items, people = P.count(lists)
        f:note(("%s: %s, %s on them."):format(kind, U.plural(items, "item"), U.plural(people, "place")), K.GOLD)
      else
        f:note(kind, { 1, 0.35, 0.29 })
      end
    end
    f:chips({ { tick = true, label = "Clear lists that aren't in this", on = replaceAll, click = function() replaceAll = not replaceAll h.redraw(true) end,
      tip = "Off: only the items in what you paste change. On: every other item's list is cleared too." } })
    f:buttons({
      { label = "Cancel", click = function() h.close() end },
      { label = "Bring them in", disabled = not lists, click = function()
        h.close()
        local ok, why = Guild.edit(function(book, now) return P.apply(book, lists, now, replaceAll) end)
        if not ok then UI.refused(why) else UI.toast(("Priority lists for %s are in, and shared with the guild."):format(U.plural(P.count(lists), "item"))) end
      end },
    })
  end)
end
UI.prioImport = importSheet

--- picks any item (a sheet): shift-click it into the box, or search every raid's loot by name; done(id)
function UI.pickAnyItem(title, done)
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
      K.setItem(b, f.width, LR.itemIcon(id), LR.coloredName(id), LR.itemKind(id))
      b:SetScript("OnClick", function() h.close() done(id) end)
      b:SetScript("OnEnter", function(self) UI.itemTooltip(self, LR.current(), id) end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      f:place(b, 36)
      f:gap(2)
    end
    local linked = LR.idFrom(q)
    if linked then row(linked) return end
    local want = U.lower(U.trim(q))
    if #want < 3 then f:note("Shift-click an item into the box, or type part of its name.") return end
    local found = {}
    for id, it in pairs(LR.ITEMS) do
      if type(it[1]) == "string" and it[1]:lower():find(want, 1, true) then found[#found + 1] = id end
    end
    table.sort(found, function(a, b) return LR.itemName(a) < LR.itemName(b) end)
    if #found == 0 then f:note("Nothing in LootRuler's loot lists is called that. Shift-click the item into the box instead.") end
    for i, id in ipairs(found) do
      if i > 30 then f:note("...and more: type more of its name.") break end
      row(id)
    end
  end, { full = true })
end

local exportFormat = "gargul"
local function exportSheet()
  UI.openSheet("Priority lists, to copy", function(f, h)
    local chips = {}
    for _, x in ipairs(P.FORMATS) do
      chips[#chips + 1] = { label = x[2], on = exportFormat == x[1], click = function() exportFormat = x[1] h.redraw() end }
    end
    f:chips(chips)
    f:note(exportFormat == "sheet" and "For a spreadsheet: paste into Google Sheets or Excel." or "Gargul's CSV: Gargul's thatsmybis importer reads it, and so does LootRuler.")
    local m = K.get(f.owner, "memo", f.parent)
    f:place(m, 200, 0)
    K.setMemo(m, f.width, 200, P.export(LR.book(), exportFormat, LR.itemName))
    f:gap(4)
    f:note("It's all selected: press Ctrl+C to copy it.")
  end)
end

local function prioPanel(f, book, editor)
  f:panel("Priority lists", function(p)
    p:note("Who gets an item first, kept between raids. In a session that goes by them, the best place in the raid gets the item without a roll; players who share a place roll for it. Whoever gets it comes off its list.")
    local ids = {}
    for id, e in pairs(book.prio) do if #e.list > 0 then ids[#ids + 1] = id end end
    table.sort(ids, function(a, b) return LR.itemName(a) < LR.itemName(b) end)
    if #ids == 0 then p:note(editor and "No lists yet: add an item, or bring them in from DFT or thatsmybis." or "No lists yet.") end
    for _, id in ipairs(ids) do
      local list = B.prio(book, id)
      local mine
      for _, x in ipairs(list) do if U.samePlayer(x.p, U.me()) then mine = x.n end end
      local b = K.get(p.owner, "item", p.parent)
      K.setItem(b, p.width, LR.itemIcon(id), LR.coloredName(id), listLine(list), mine and ("|cff1eff00" .. P.place(mine) .. "|r") or "",
        editor and { text = "Edit", width = 40, tip = "Change this list", click = function() prioSheet(id) end } or nil)
      b:SetScript("OnEnter", function(self) UI.itemTooltip(self, LR.current(), id) end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      p:place(b, 36)
      p:gap(2)
    end
    if editor then
      p:buttons({
        { label = "Add an item", click = function()
          UI.pickAnyItem("Priority list for which item?", function(id) prioSheet(id) end)
        end },
        { label = "Bring in", click = importSheet },
        { label = "Copy out", disabled = #ids == 0, click = exportSheet },
      }, "left")
    elseif #ids > 0 then
      p:buttons({ { label = "Copy out", click = exportSheet } }, "left")
    end
  end)
end

function UI.guildView(f)
  local book = LR.book()
  if not book then
    f:panel("Guild", function(p) p:text("You're not in a guild. Guild features (boosted rolls, priority lists) are for guilds that raid together.") end)
    return
  end
  local editor = LR.canEditBook()
  boostPanel(f, book, editor)
  if book.boost.on or next(book.points) then pointsPanel(f, book, editor) end
  prioPanel(f, book, editor)
  whoPanel(f, book)
  f:note("Everyone in " .. book.guild .. " with LootRuler gets a copy of this, and keeps it between raids.")
end
