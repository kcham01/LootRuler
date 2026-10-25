-- The Session screen: opening soft reserves (raid, reserves each, doubling up, sharing with the guild),
-- running them (hard reserves, changing the rules, locking, softres.it imports, ending), and switching
-- between sessions.
local _, LR = ...
local U, K, S = LR.U, LR.K, LR.Session
local UI = LR.UI

UI.draft = { raid = "Karazhan", sr = 2, dupes = true }

local function stepper(p, label, value, minV, maxV, onChange)
  p:chips({
    { label = label, plain = true },
    { label = "-", on = false, width = 24, click = function() if value > minV then onChange(value - 1) end end },
    { label = tostring(value), on = true, width = 32, click = function() end },
    { label = "+", on = false, width = 24, click = function() if value < maxV then onChange(value + 1) end end },
  })
end

--- a sheet to hard reserve an item: who it's for and a note (both optional)
local function hardReserveSheet(s, id)
  local forWho, note = s.hr[id] and s.hr[id].f or "", s.hr[id] and s.hr[id].n or ""
  UI.openSheet("Hard reserve", function(f, h)
    local b = K.get(f.owner, "item", f.parent)
    K.setItem(b, f.width, LR.itemIcon(id), LR.coloredName(id), LR.itemKind(id) .. "  -  " .. table.concat(LR.dropsFrom(s.raid, id), ", "))
    b:SetScript("OnEnter", function(self) UI.itemTooltip(self, s, id) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:place(b, 36)
    f:gap(8)
    local who = S.byItem(s)[id]
    if who then f:note(("Soft reserved by %s: they get those reserves back to use on something else."):format(UI.whoLine(s, id)), K.GOLD) end
    f:text("For (optional)", { font = "GameFontNormal", gap = 2 })
    local e1 = K.get(f.owner, "edit", f.parent)
    f:place(e1, 22, 6, f.width - 12)
    e1:SetMaxLetters(40)
    e1:SetText(forWho)
    e1:SetScript("OnTextChanged", function(self) forWho = self:GetText() end)
    f:gap(6)
    f:text("Note (optional)", { font = "GameFontNormal", gap = 2 })
    local e2 = K.get(f.owner, "edit", f.parent)
    f:place(e2, 22, 6, f.width - 12)
    e2:SetMaxLetters(80)
    e2:SetText(note)
    e2:SetScript("OnTextChanged", function(self) note = self:GetText() end)
    f:gap(10)
    local list = { { label = "Cancel", click = function() h.close() end } }
    if s.hr[id] then list[#list + 1] = { label = "Lift it", click = function() h.close() LR.clearHR(s, id) end } end
    list[#list + 1] = { label = "Hard reserve", click = function() h.close() LR.setHR(s, id, forWho, note) end }
    f:buttons(list)
  end)
end

local function importSheet(s)
  local text = ""
  UI.openSheet("Bring in reserves from softres.it", function(f, h)
    f:text("On softres.it, open the raid and click |cffffd100Gargul Export|r, copy what it shows, and paste it here (Ctrl+V).")
    f:note("The sheet's reserves are added to this session's. Import again whenever the sheet changes: the reserves from the sheet are updated to match it, and reserves made in LootRuler stay. Items that don't drop in " .. LR.raidOf(s).name .. " are skipped, and so are reserves past the limit.")
    local e = K.get(f.owner, "edit", f.parent)
    f:place(e, 22, 6, f.width - 12)
    e:SetText(text)
    e:SetScript("OnTextChanged", function(self) text = self:GetText() end)
    f:gap(10)
    f:buttons({ { label = "Cancel", click = function() h.close() end }, { label = "Import", click = function()
      local sum, err = LR.Gargul.importInto(s, text)
      if not sum then UI.toast(err) return end
      h.close()
      local msg = ("From softres.it: %s for %s"):format(U.plural(sum.items, "reserve"), U.plural(sum.players, "player"))
      local changes = {}
      if sum.added > 0 then changes[#changes + 1] = sum.added .. " new" end
      if sum.removed > 0 then changes[#changes + 1] = sum.removed .. " taken off" end
      if #changes > 0 then msg = msg .. " (" .. table.concat(changes, ", ") .. ")" elseif sum.items > 0 then msg = msg .. " (no changes)" end
      if sum.hard > 0 then msg = msg .. (", %d hard reserved"):format(sum.hard) end
      if sum.hardRemoved > 0 then msg = msg .. (", %d hard reserves taken off"):format(sum.hardRemoved) end
      if sum.skipped + sum.over > 0 then msg = msg .. ("; %d skipped"):format(sum.skipped + sum.over) end
      LR.print(msg .. ".")
      UI.importSummary(s, sum, msg .. ".")
    end } })
  end)
end

local function manage(f, s)
  local raid = LR.raidOf(s)
  if s.gdkp then UI.gdkpPanel(f, s) end          -- GDKP first: in a GDKP raid it's what matters
  f:panel("Your session", function(p)
    p:kv({
      { "Raid", raid.name },
      { "Reserved so far", U.plural(#S.players(s), "player") },
      { "Shared with", (LR.groupChannel() and "your group" or "nobody yet (no group)") .. (s.guild and " and your guild" or "") },
    })
    p:gap(6)
    stepper(p, "Reserves each", s.sr, S.MIN_SR, S.MAX_SR, function(v)
      local cut = 0
      for _, pl in ipairs(S.players(s)) do if #pl.items > v then cut = cut + 1 end end
      local function go() local ok, why = LR.configure(s, v, s.dupes) if not ok then UI.refused(why) end end
      if cut > 0 then
        UI.confirm("Fewer reserves", ("%s already reserved more than %d: their last reserves go."):format(U.plural(cut, "player"), v), "Lower it", go)
      else go() end
    end)
    p:chips({
      { label = (s.dupes and "[x] " or "[  ] ") .. "Same item more than once", on = s.dupes, click = function()
        local doubled = 0
        for _, pl in ipairs(S.players(s)) do
          local seen = {}
          for _, id in ipairs(pl.items) do if seen[id] then doubled = doubled + 1 break end seen[id] = true end
        end
        local function go() LR.configure(s, s.sr, not s.dupes) end
        if s.dupes and doubled > 0 then
          UI.confirm("One per item", ("%s put more than one reserve on the same item: the extra ones go."):format(U.plural(doubled, "player")), "Switch it off", go)
        else go() end
      end, tip = "Lets a player put more than one of their reserves on the same item (softres.it's \"x2\")." },
      { label = (s.guild and "[x] " or "[  ] ") .. "Share with my guild", on = s.guild, click = function()
        if not IsInGuild() then UI.toast("You're not in a guild.") return end
        LR.setGuild(s, not s.guild)
      end, tip = "Guild members with LootRuler can see the session and reserve before the group is made." },
      not LR.raidOf(s).custom and { label = (s.any and "[x] " or "[  ] ") .. "Any item", on = s.any, click = function() LR.setAny(s, not s.any) end,
        tip = "Lets people reserve any item, not just " .. LR.raidOf(s).name .. "'s loot: for loot LootRuler's lists don't have yet. Reserves already made stay either way." } or false,
      { label = (s.plusOne and "[x] " or "[  ] ") .. "+1 rule", on = s.plusOne, click = function() LR.setPlusOne(s, not s.plusOne) end,
        tip = "Every item won on a main spec roll is a +1, and players with fewer +1s win main spec rolls over players with more. You can change anyone's +1s on the Reserves tab (by player)." },
      { label = (s.gdkp and "[x] " or "[  ] ") .. "GDKP auctions", on = s.gdkp, click = function()
        if not s.gdkp and next(s.res) then
          UI.confirm("GDKP auctions", "Every item is auctioned for gold instead: reserves stop counting (they're kept, in case you switch back), and nobody can reserve.", "Auction", function() LR.setGdkp(s, true) end)
        else LR.setGdkp(s, not s.gdkp) end
      end, tip = "Items are auctioned for gold: raiders bid by typing an amount in raid chat. The gold goes in a pot that's split between everyone at the end." },
      UI.boostOn() and { label = (s.boost and "[x] " or "[  ] ") .. "Boosted rolls", on = s.boost, click = function() LR.setSessionBoost(s, not s.boost) end,
        tip = "Guild members roll 1 to 100 plus their guild points on main spec (Guild tab). Whoever wins with a boosted roll spends their points." } or false,
      { label = (s.locked and "[x] " or "[  ] ") .. "Locked", on = s.locked, click = function() LR.setLocked(s, not s.locked) end,
        tip = "Nobody can change their reserves (you still can). Locking sends the reserves to Gargul when it's loaded." },
    })
  end)

  f:panel("Hard reserves", function(p)
    local hr = U.keys(s.hr)
    if #hr == 0 then p:note("Nothing is hard reserved. A hard reserved item can't be soft reserved; you can say who it's for.") end
    for _, id in ipairs(hr) do
      local h = s.hr[id]
      local b = K.get(p.owner, "item", p.parent)
      K.setItem(b, p.width, LR.itemIcon(id), LR.coloredName(id), (h.f ~= "" and ("For " .. h.f) or "For nobody in particular") .. (h.n ~= "" and ("  -  " .. h.n) or ""), "",
        { text = "x", tip = "Lift the hard reserve", click = function() LR.clearHR(s, id) end })
      b:SetScript("OnClick", function() hardReserveSheet(s, id) end)
      b:SetScript("OnEnter", function(self) UI.itemTooltip(self, s, id) end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      p:place(b, 36)
      p:gap(3)
    end
    p:gap(2)
    p:buttons({ { label = "Add a hard reserve", click = function()
      UI.pickItem(s, "Hard reserve an item", function(id) hardReserveSheet(s, id) end)
    end } }, "left")
  end)

  if s.plusOne then
    f:panel("+1s", function(p)
      p:note("Everyone's +1s are on the Reserves tab (by player). Bring them in from Gargul, or copy them out for it.")
      p:buttons({
        { label = "Bring in from Gargul", click = function()
          UI.countsSheet({ title = "+1s from Gargul", gargul = "plusOnes", max = 99,
            note = "Paste Gargul's +1 export (\"Name,+1s\" lines; Gargul: /gl po, Export), or read it straight from Gargul if it's loaded. Each player's +1s are set to these.",
            apply = function(list) UI.toast(("+1s for %s are in."):format(U.plural(LR.importPlusOnes(s, list), "player"))) end })
        end },
        { label = "Copy out", click = function()
          local list = {}
          local names = {}
          for _, m in ipairs(LR.roster()) do names[U.full(m.name)] = true end
          for _, pl in ipairs(S.players(s)) do names[pl.name] = true end
          for _, w in ipairs(s.won or {}) do names[w.p] = true end
          for name in pairs(s.po or {}) do names[name] = true end
          for name in pairs(names) do local n = S.plusOnes(s, name) if n > 0 then list[#list + 1] = { p = name, n = n } end end
          UI.textSheet("+1s", "For Gargul's +1 importer, or a spreadsheet.", LR.Prio.countsText(list))
        end },
      }, "left")
    end)
  end

  if not s.gdkp and s.prio ~= "only" then
    f:panel("Extra reserves", function(p)
      local list = {}
      for name, n in pairs(s.xr or {}) do list[#list + 1] = { name, n } end
      table.sort(list, function(a, b) return a[1] < b[1] end)
      if #list == 0 then
        p:note("Everyone gets the same. Give tanks and healers (or anyone) extra reserves here.")
      else
        p:text(table.concat(U.map(list, function(x) return U.classText(U.short(x[1]), LR.classOf(x[1])) .. " +" .. x[2] end), ", "))
      end
      p:buttons({ { label = "Give extra reserves", click = function() UI.extraSheet(s) end } }, "left")
    end)
  end

  f:panel("Disenchanter", function(p)
    if s.de then
      p:text(U.classText(U.short(s.de), LR.classOf(s.de)) .. " disenchants what nobody wants: the loot master's window has a Disenchant button.")
    else
      p:note("Nobody yet. Pick who disenchants items nobody wants, and the loot master's window gets a one-click Disenchant button.")
    end
    p:buttons({
      { label = s.de and "Someone else" or "Pick a disenchanter", click = function() UI.pickPlayer("Who disenchants?", function(name) LR.setDisenchanter(s, name) end) end },
      s.de and { label = "Nobody", click = function() LR.setDisenchanter(s, nil) end } or nil,
    }, "left")
  end)

  if not s.gdkp and (s.prio or UI.prioAvailable()) then
    f:panel("Priority lists", function(p)
      p:chips(UI.prioChips(s.prio, function(mode)
        if mode == "only" and next(s.res) then
          UI.confirm("Priority lists only", "Reserves stop counting (they're kept, in case you switch back), and nobody can reserve.", "Switch", function() LR.setSessionPrio(s, mode) end)
        else LR.setSessionPrio(s, mode) end
      end), { gap = 4 })
      for _, m in ipairs(UI.PRIO_MODES) do if m[1] == s.prio then p:note(m[3]) end end
      if s.prio then p:note("The lists are the guild's (Guild tab). Whoever gets an item comes off its list. Raiders without the addon can whisper you \"!lr prio\".") end
    end)
  end

  if s.boost and UI.boostOn() then
    f:panel("Boosted rolls", function(p)
      local book = LR.book()
      p:note(("Guild members with points can roll 1 to 100 plus their points on main spec. Each raid is worth %d points."):format(book.boost.perRaid))
      if LR.canEditBook() then
        local given = LR.Guild.pointsGiven(s)
        p:buttons({ { label = given and "Give raid points again" or "Give raid points", click = function() UI.giveRaidPoints(s) end } }, "left")
        p:note(given and "You've given this raid its points." or "Everyone from the guild in the group gets them. You can also give them when you end the session.")
      else
        p:note("An officer gives the raid its points (Guild tab).")
      end
    end)
  end

  f:panel("More", function(p)
    p:buttons({
      { label = "Tell the raid how to SR without the addon", disabled = LR.groupChannel() == nil, click = function()
        if LR.Whisper.postHowTo() then UI.toast("Posted in " .. (IsInRaid() and "raid" or "party") .. " chat.") end
      end },
    }, "left")
    p:note("Posts: \"" .. LR.Whisper.howTo() .. "\"")
    p:buttons({
      { label = "Import from softres.it", click = function() importSheet(s) end },
      { label = "End session", click = function()
        local text = "Everyone's reserves for " .. raid.name .. " are cleared, for you and for every raider's addon. (Gargul keeps what you sent it.)"
        -- GDKP: ending it loses who owes what, so not while gold is still owed (unless they mean it)
        local owing = LR.Gdkp.unsettled(s)
        if #owing > 0 then
          UI.openSheet("Gold is still owed", function(sf, h)
            sf:text(("%s aren't settled yet:"):format(U.plural(#owing, "player")))
            for i, x in ipairs(owing) do
              if i > 8 then sf:note(("...and %d more."):format(#owing - 8)) break end
              sf:note(x[2] > 0 and ("%s: you give them %s"):format(U.short(x[1]), LR.Gdkp.gold(x[2]))
                or ("%s: they give you %s"):format(U.short(x[1]), LR.Gdkp.gold(-x[2])), x[2] > 0 and K.GOLD or { 1, 0.35, 0.29 })
            end
            sf:note("You can end it anyway: it's kept under Past raids (Loot tab), where you can finish the payouts, and trades with them still count for two weeks. Or keep it open: it stays for a week, even after you log out.")
            sf:gap(6)
            sf:buttons({
              { label = "Keep it open", click = function() h.close() end },
              { label = "Payouts", click = function() h.close() UI.payoutSheet(s) end },
              { label = "End it", click = function() h.close() LR.endSession(s) end },
            })
          end)
          return
        end
        if s.boost and UI.boostOn() and LR.canEditBook() and not LR.Guild.pointsGiven(s) and #LR.Guild.raidMembers() > 0 then
          -- the end of a raid is when its points are usually given
          UI.openSheet("End the session", function(sf, h)
            sf:text(text)
            sf:note(("This raid's points haven't been given yet (%d each for %s from the guild)."):format(LR.book().boost.perRaid,
              U.plural(#LR.Guild.raidMembers(), "player")), K.GOLD)
            sf:gap(6)
            sf:buttons({
              { label = "Cancel", click = function() h.close() end },
              { label = "End it", click = function() h.close() LR.endSession(s) end },
              { label = "Give points and end", click = function()
                h.close()
                local ok, why = LR.Guild.raidPoints(s)
                if not ok then UI.refused(why) end
                LR.endSession(s)
              end },
            })
          end)
          return
        end
        UI.confirm("End the session", text, "End it", function() LR.endSession(s) end)
      end },
    }, "left")
  end)
end

local function newSession(f)
  local d = UI.draft
  if d.guild == nil then d.guild = IsInGuild() and true or false end
  f:panel("Open soft reserves", function(p)
    for _, era in ipairs({ { "tbc", "Burning Crusade raids" }, { "classic", "Original raids" } }) do
      p:text(era[2], { font = "GameFontNormal", gap = 2 })
      local chips = {}
      for _, r in ipairs(LR.RAIDS) do
        if r.era == era[1] then
          chips[#chips + 1] = { label = r.name, on = d.raid == r.key, click = function() d.raid = r.key UI.render() end }
        end
      end
      p:chips(chips)
    end
    p:chips({ { label = "Another raid", on = d.raid == LR.CUSTOM, click = function() d.raid = LR.CUSTOM UI.render() end,
      tip = "A raid that isn't in LootRuler's lists (a new one, or World of Warcraft: Forever's): name it, and any item can be reserved." } })
    if d.raid == LR.CUSTOM then
      p:text("Raid name", { font = "GameFontNormalSmall", color = K.GOLD, gap = 2 })
      local e = K.get(p.owner, "edit", p.parent)
      p:place(e, 22, 6, p.width - 12)
      e:SetMaxLetters(40)
      e:SetText(d.name or "")
      e:SetScript("OnTextChanged", function(self) d.name = self:GetText() end)
      p:gap(6)
    end
    stepper(p, "Reserves each", d.sr, S.MIN_SR, S.MAX_SR, function(v) d.sr = v UI.render() end)
    p:chips({
      { label = (d.dupes and "[x] " or "[  ] ") .. "Same item more than once", on = d.dupes, click = function() d.dupes = not d.dupes UI.render() end,
        tip = "Lets a player put more than one of their reserves on the same item (softres.it's \"x2\")." },
      { label = (d.guild and "[x] " or "[  ] ") .. "Share with my guild", on = d.guild, click = function()
        if not IsInGuild() then UI.toast("You're not in a guild.") return end
        d.guild = not d.guild UI.render()
      end, tip = "Guild members with LootRuler can see the session and reserve before the group is made." },
      { label = (d.gdkp and "[x] " or "[  ] ") .. "GDKP auctions", on = d.gdkp, click = function() d.gdkp = not d.gdkp UI.render() end,
        tip = "Items are auctioned for gold instead of reserved and rolled for. The gold goes in a pot that's split between everyone at the end." },
      { label = (d.plusOne and "[x] " or "[  ] ") .. "+1 rule", on = d.plusOne, click = function() d.plusOne = not d.plusOne UI.render() end,
        tip = "Every item won on a main spec roll is a +1, and players with fewer +1s win main spec rolls over players with more." },
      UI.boostOn() and { label = (d.boost and "[x] " or "[  ] ") .. "Boosted rolls", on = d.boost, click = function() d.boost = not d.boost UI.render() end,
        tip = "Guild members roll 1 to 100 plus their guild points on main spec (Guild tab). Whoever wins with a boosted roll spends their points." } or false,
      d.raid ~= LR.CUSTOM and { label = (d.any and "[x] " or "[  ] ") .. "Any item", on = d.any, click = function() d.any = not d.any UI.render() end,
        tip = "Lets people reserve any item, not just the raid's loot: for loot LootRuler's lists don't have yet." } or false,
    })
    if UI.prioAvailable() then
      p:chips(UI.prioChips(d.prio, function(mode) d.prio = mode UI.render() end), { gap = 4 })
    end
    if IsInGroup() and not UnitIsGroupLeader("player") then
      p:note("You're not the group leader. That's fine if you're running loot, but make sure only one of you opens reserves.", K.GOLD)
    end
    p:note("Raiders reserve in LootRuler, or whisper you \"!lr <item link>\" if they don't have it. You reserve on the Reserve tab like everyone else; hard reserves come next.")
    p:buttons({ { label = "Open reserves", click = function()
      if d.raid == LR.CUSTOM and U.trim(d.name or "") == "" then UI.toast("Give the raid a name.") return end
      local s = LR.startSession(d.raid, d.sr, d.dupes, d.guild, d.name, d.any)
      if d.plusOne then LR.setPlusOne(s, true) end
      if d.gdkp then LR.setGdkp(s, true) end
      if d.boost and UI.boostOn() then LR.setSessionBoost(s, true) end
      if d.prio and UI.prioAvailable() then LR.setSessionPrio(s, d.prio) end
      UI.toast(("%s reserves are open."):format(LR.raidOf(s).name))
      UI.render()
    end } })
  end)
end

local function others(f, current)
  local list = U.filter(LR.sessions(), function(x) return x ~= current end)
  if #list == 0 then return end
  f:panel("Other open sessions", function(p)
    for _, x in ipairs(list) do
      local b = K.get(p.owner, "item", p.parent)
      K.setItem(b, p.width, LR.raidIcon(x.raid), LR.raidOf(x).name,
        (LR.isLeader(x) and "Yours" or ("By " .. U.short(x.leader))) .. " - " .. U.plural(x.sr, "reserve") .. " each", "",
        not LR.isLeader(x) and { text = "x", tip = "Forget this session", click = function() LR.forget(x) end } or nil)
      b:SetScript("OnClick", function() LR.select(x.id) UI.go("reserve") end)
      p:place(b, 36)
      p:gap(3)
    end
  end)
end

function UI.sessionView(f, s)
  if s and LR.isLeader(s) then
    manage(f, s)
  else
    if s then
      if s.gdkp and s.gk then UI.gdkpPanel(f, s) end
      f:panel("Session by " .. U.short(s.leader), function(p)
        p:kv({
          { "Raid", LR.raidOf(s).name },
          { "Reserves each", tostring(s.sr) },
          { "Same item more than once", s.dupes and "yes" or "no" },
          { "Hard reserves", tostring(#U.keys(s.hr)) },
          { "Locked", s.locked and "yes" or "no" },
        })
        if s.gdkp then p:note("Loot is auctioned for gold (GDKP): type your bid in raid chat when an item is up.", K.GOLD) end
        p:gap(4)
        p:buttons({ { label = "Forget it", click = function()
          UI.confirm("Forget the session", "It's only removed from your addon. If " .. U.short(s.leader) .. " sends it again, it comes back.", "Forget", function() LR.forget(s) end)
        end } }, "left")
      end)
    end
    newSession(f)
  end
  others(f, s)
end
