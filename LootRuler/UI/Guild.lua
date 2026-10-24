-- The Guild tab (shown to guild members): the guild book (Core/Book.lua), which lasts between raids and is
-- shared with everyone in the guild who has LootRuler. Boosted roll points live here. The guild master and
-- the ranks they pick change it; everyone else sees it.
local _, LR = ...
local U, K, B = LR.U, LR.K, LR.Book
local UI = LR.UI
local Guild = LR.Guild

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
      p:chips({ { label = (book.boost.on and "[x] " or "[  ] ") .. "Boosted rolls for this guild", on = book.boost.on, click = function()
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
    p:kv({ { "Your points", mine > 0 and ("%d (a boosted roll is %d to %d)"):format(mine, B.boostRange(mine)) or "None yet", K.TEXT, K.GOLD } })
  end)
end

local function pointsPanel(f, book, editor)
  f:panel("Points", function(p)
    local list = {}
    for name, e in pairs(book.points) do if e.n > 0 then list[#list + 1] = { name, e.n } end end
    table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    if #list == 0 then p:note("Nobody has points yet. They come from raids (Give raid points), or an officer can set them here.") end
    for _, x in ipairs(list) do
      local b = K.get(p.owner, "item", p.parent)
      local class = LR.classOf(x[1])
      K.setItem(b, p.width, LR.LOGO, U.classText(U.short(x[1]), class), ("Boosted roll: /roll %d %d"):format(B.boostRange(x[2])),
        "|cff1eff00" .. x[2] .. "|r", editor and { text = "Edit", width = 40, tip = "Change " .. U.short(x[1]) .. "'s points", click = function() pointsSheet(x[1]) end } or nil)
      p:place(b, 36)
      p:gap(2)
    end
    if editor then
      p:buttons({ { label = "Give a player points", click = function() pointsSheet(nil) end } }, "left")
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

function UI.guildView(f)
  local book = LR.book()
  if not book then
    f:panel("Guild", function(p) p:text("You're not in a guild. Guild features (boosted rolls, priority lists) are for guilds that raid together.") end)
    return
  end
  local editor = LR.canEditBook()
  boostPanel(f, book, editor)
  if book.boost.on or next(book.points) then pointsPanel(f, book, editor) end
  whoPanel(f, book)
  f:note("Everyone in " .. book.guild .. " with LootRuler gets a copy of this, and keeps it between raids.")
end
