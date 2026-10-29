-- The Session screen: opening soft reserves (raid, reserves each, doubling up, sharing with the guild),
-- running them (hard reserves, changing the rules, locking, softres.it imports, ending), and switching
-- between sessions.
local _, LR = ...
local U, K, S = LR.U, LR.K, LR.Session
local UI = LR.UI

UI.draft = { raid = "Karazhan", sr = 2, dupes = true }
local brand                   -- the branding being typed (Your raid's name), for the session it's for

local function stepper(p, label, value, minV, maxV, onChange)
  p:chips({
    label and { label = label, plain = true } or false,
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
  local link = s.url or ""
  UI.openSheet("Bring in reserves from softres.it", function(f, h)
    f:text("On softres.it, open the raid and click |cffffd100Gargul Export|r, copy what it shows, and paste it here (Ctrl+V). A spreadsheet works too: softres.it's CSV, or any with a column for the player's name and one for the item's number.")
    f:note("The sheet's reserves are added to this session's. Import again whenever the sheet changes: the reserves from the sheet are updated to match it, and reserves made in LootRuler stay. Items that don't drop in " .. LR.raidOf(s).name .. " are skipped, and so are reserves past the limit.")
    local e = K.get(f.owner, "memo", f.parent)
    f:place(e, 90, 0)
    K.setEditMemo(e, f.width, 90, text, function(t) text = t end, true)
    f:gap(6)
    f:text("The raid's softres.it link (optional)", { font = "GameFontNormalSmall", color = K.GOLD, gap = 2 })
    local le = K.get(f.owner, "edit", f.parent)
    f:place(le, 22, 6, f.width - 12)
    le:SetText(link)
    le:SetScript("OnTextChanged", function(self) link = self:GetText() end)
    f:note("To post in raid chat (Session tab), for players who'd rather reserve there. A Gargul Export from softres.it fills it in.")
    f:gap(10)
    f:buttons({ { label = "Cancel", click = function() h.close() end }, { label = "Import", click = function()
      if U.trim(link) ~= (s.url or "") and not LR.setLink(s, link) then UI.toast("That isn't a softres.it link (https://softres.it/...).") return end
      if U.trim(text) == "" and U.trim(link) ~= "" then h.close() return end
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
      if sum.used > 0 then msg = msg .. ("; %d kept (they already won with it)"):format(sum.used) end
      if sum.over > 0 then msg = msg .. ("; %d past someone's limit, skipped"):format(sum.over) end
      if sum.skipped > 0 then msg = msg .. ("; %d not from this raid, skipped"):format(sum.skipped) end
      LR.print(msg .. ".")
      UI.importSummary(s, sum, msg .. ".")
    end } })
  end)
end

UI.importSheet = importSheet

--- who's on the bench: guild members online and not in the group to tick, or names typed in
function UI.benchSheet(s)
  local on = {}
  for _, name in ipairs(s.bn or {}) do on[name] = true end
  local typed = ""
  UI.openSheet("The bench", function(f, h)
    f:text("Who came but sat out? They get the raid's points too, and count as there in the fairness history.")
    local names = LR.Guild.onlineOutside()
    for name in pairs(on) do if not U.indexOf(names, name) then names[#names + 1] = name end end
    table.sort(names)
    if #names == 0 then f:note("Nobody from your guild is online outside the group. Type names below.") end
    local chips = {}
    for _, name in ipairs(names) do
      chips[#chips + 1] = { tick = true, label = U.short(name), on = on[name] or false, click = function() on[name] = not on[name] or nil h.redraw(true) end }
    end
    if #chips > 0 then f:chips(chips) end
    f:text("Or type names", { font = "GameFontNormalSmall", color = K.GOLD, gap = 2 })
    local e = K.get(f.owner, "edit", f.parent)
    f:place(e, 22, 6, f.width - 12)
    e:SetText(typed)
    K.setHint(e, "Names, with commas between them")
    K.onText(e, function(self) typed = self:GetText() end)
    f:gap(8)
    f:buttons({ { label = "Cancel", click = function() h.close() end }, { label = "Save", click = function()
      for name in typed:gmatch("[^,%s]+") do on[U.full(name)] = true end
      local list = {}
      for name in pairs(on) do list[#list + 1] = name end
      table.sort(list)
      if #list > LR.Session.BENCH_MAX then UI.toast(("At most %d on the bench."):format(LR.Session.BENCH_MAX)) return end
      h.close()
      LR.setBench(s, list)
      UI.toast(#list > 0 and ("%s on the bench."):format(U.plural(#list, "player")) or "Nobody on the bench.")
    end } })
  end)
end

--- when reserves lock by themselves: in some minutes, or at a time of day
function UI.autoLockSheet(s)
  local typed = ""
  UI.openSheet("Lock reserves by themselves", function(f, h)
    f:text("When should reserves lock? The raid is told 5, 2 and 1 minute before, and when they lock.")
    local function set(at) h.close() LR.setAutoLock(s, at) UI.toast(("Reserves lock at %s."):format(LR.Lock.clock(at))) end
    local chips = {}
    for _, m in ipairs({ 10, 15, 30, 45, 60 }) do
      chips[#chips + 1] = { label = ("In %d min"):format(m), click = function() set(U.now() + m * 60) end }
    end
    f:chips(chips)
    f:text("Or at a time on your clock", { font = "GameFontNormalSmall", color = K.GOLD, gap = 2 })
    local e = K.get(f.owner, "edit", f.parent)
    f:place(e, 22, 6, 120)
    e:SetText(typed)
    K.setHint(e, "20:00")
    K.onText(e, function(self) typed = self:GetText() end)
    f:gap(8)
    f:buttons({ { label = "Cancel", click = function() h.close() end }, { label = "Lock at that time", click = function()
      local secs = LR.Lock.parseTime(typed)
      if not secs then UI.toast("Type a time like 20:00 or 8:30pm.") return end
      set(LR.Lock.atTime(secs))
    end } })
  end)
end

--- softres.it: importing (the first thing many raids do), and its link. It stands out: it's where a pug starts
local function softresPanel(f, s)
  f:hot("softres.it", function(p)
    local fromSheet = s.sx and #U.keys(s.sx) or 0
    p:note(fromSheet > 0 and ("%s's reserves came from the sheet. Import again whenever it changes: those are updated to match, and reserves made in LootRuler stay."):format(U.plural(fromSheet, "player"))
      or "The raid reserved on softres.it? Bring the sheet in, with the raid's link to post.", K.TEXT)
    p:buttons({
      { label = s.sx and "Import again" or "Import from softres.it", click = function() importSheet(s) end },
      s.url and { label = "Post the link in raid chat", style = "quiet", disabled = LR.groupChannel() == nil, click = function()
        if LR.postLink(s) then UI.toast("Posted in " .. (IsInRaid() and "raid" or "party") .. " chat.") end
      end } or nil,
    }, "left")
    if s.url then p:note(s.url) end
  end)
end

--- the Session tab's sections that open and close (kept per character): key -> true
local function sessionFolds()
  if type(LR.db.ui.sessionOpen) ~= "table" then LR.db.ui.sessionOpen = {} end
  return LR.db.ui.sessionOpen
end
local function fold(f, key, title, what, fill)
  local open = sessionFolds()
  f:fold(title, what, open[key] == true, function() open[key] = not open[key] or nil UI.render() end, fill)
end
UI.sessionFold = fold

--- my private session (Core/Net.lua): what it holds, its few settings, and closing it
local function privateView(f, s)
  local raid = LR.raidOf(s)
  f:strip(("Only on your screen: %s reserved, %s of loot listed. Nothing is sent to anyone or said in chat."):format(
    U.plural(#S.players(s), "player"), U.plural(#(s.drops or {}), "item")), "ok")
  f:hot("softres.it", function(p)
    p:note(s.sx and "Import again whenever the sheet changes: its reserves are updated to match."
      or "Bring in the raid's reserves from softres.it, to see who reserved what.", K.TEXT)
    p:buttons({ { label = s.sx and "Import again" or "Import from softres.it", click = function() importSheet(s) end } }, "left")
  end)
  f:panel("Your private session", function(p)
    p:row("Reserves each", function(r) stepper(r, nil, s.sr, S.MIN_SR, S.MAX_SR, function(v) LR.configure(s, v, s.dupes) end) end)
    p:row("Reserving", function(r)
      r:chips({
        { tick = true, label = "Same item more than once", on = s.dupes, click = function() LR.configure(s, s.sr, not s.dupes) end,
          tip = "Lets a player have more than one reserve on the same item (softres.it's \"x2\")." },
        not raid.custom and { tick = true, label = "Any item", on = s.any, click = function() LR.setAny(s, not s.any) end,
          tip = "Lets reserves be on any item, not just " .. raid.name .. "'s loot." } or false,
      }, { gap = 2 })
    end)
    p:note("It keeps the raid's loot list (from the game's loot lines and Gargul's awards) and the reserves you bring in. Nothing is rolled out from it. It closes by itself if you join someone's reserves or open your own.")
  end)
  f:buttons({ { label = "Close it", style = "link", danger = true, click = function()
    UI.confirm("Close your private session", "Its loot list and reserves are forgotten. Nobody else had them.", "Close it", function() LR.closePrivate() end)
  end } }, "left")
end

--- someone says they run these reserves now, and LootRuler couldn't confirm it: the player decides
local function claimPanel(f, s)
  local c = LR.claim(s.id)
  if not c then return end
  local who = U.short(c.leader)
  if LR.isLeader(s) then
    f:panel("Taken over while you were away?", function(p)
      p:note(("%s says they took these reserves over from you while you were away. LootRuler can't confirm it (nobody who leads the group or is its master looter has said so). If they did, let them run them; if not, keep running them yourself."):format(who), K.GOLD)
      p:buttons({
        { label = "Let " .. who .. " run them", click = function() LR.followClaim(s.id) UI.toast(who .. " runs the reserves now.") end },
        { label = "Keep running them", click = function() LR.dropClaim(s.id) end },
      }, "left")
    end)
  else
    f:panel("Someone else runs these now?", function(p)
      p:note(("%s says they run these reserves now. LootRuler can't confirm it: %s, who ran them, isn't here to say so. If %s does run them, follow them, so your reserves go to them."):format(
        who, U.short(c.was), who), K.GOLD)
      p:buttons({
        { label = "Follow " .. who, click = function() LR.followClaim(s.id) UI.toast("You follow " .. who .. "'s reserves now.") end },
        { label = "Not now", click = function() LR.dropClaim(s.id) end },
      }, "left")
    end)
  end
end

--- ending a session: asks first, and says what's still to do (gold owed, the raid's points)
local function endSession(s)
  local raid = LR.raidOf(s)
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
        { label = "Keep it open", style = "quiet", click = function() h.close() end },
        { label = "Payouts", style = "quiet", click = function() h.close() UI.payoutSheet(s) end },
        { label = "End it", click = function() h.close() LR.endSession(s) end },
      })
    end)
    return
  end
  if s.boost and UI.boostOn() and LR.canEditBook() and not LR.Guild.pointsGiven(s) and #LR.Guild.raidMembers(s) > 0 then
    -- the end of a raid is when its points are usually given
    UI.openSheet("End the session", function(sf, h)
      sf:text(text)
      sf:note(("This raid's points haven't been given yet (%d each for %s from the guild)."):format(LR.book().boost.perRaid,
        U.plural(#LR.Guild.raidMembers(s), "player")), K.GOLD)
      sf:gap(6)
      sf:buttons({
        { label = "Cancel", style = "quiet", click = function() h.close() end },
        { label = "End it", style = "quiet", click = function() h.close() LR.endSession(s) end },
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
end
UI.endSessionAsk = endSession

--- the loot council (Core/Council.lua): who's on it
local function councilPickSheet(s)
  UI.openSheet("Loot council", function(f, h)
    f:note("The council votes on who gets each item, from the players who roll for it. The loot master sees the votes and hands it over. Votes stay between the council and the loot master. Council members without LootRuler whisper you \"!reserve vote Name\".")
    local list, seen = {}, {}
    for _, m in ipairs(LR.roster()) do list[#list + 1] = { name = U.full(m.name), class = m.class } seen[U.full(m.name):lower()] = true end
    for _, n in ipairs(s.lc or {}) do if not seen[n:lower()] then list[#list + 1] = { name = n } end end
    table.sort(list, function(a, b) return a.name < b.name end)
    local chips = {}
    for _, m in ipairs(list) do
      local on = LR.Council.isMember(s, m.name)
      chips[#chips + 1] = { tick = true, label = U.short(m.name), on = on, click = function()
        local names = {}
        for _, n in ipairs(s.lc or {}) do if not U.samePlayer(n, m.name) then names[#names + 1] = n end end
        if not on then names[#names + 1] = m.name end
        LR.setCouncil(s, names)
        h.redraw(true)
      end }
    end
    if #chips > 0 then f:chips(chips, { gap = 2 }) else f:note("Nobody in the group yet.") end
    f:note(LR.Council.on(s) and ("On: %s on the council."):format(U.plural(#s.lc, "player")) or "Off: nobody on the council, so rolls decide.",
      LR.Council.on(s) and K.GREEN or nil)
    f:buttons({ { label = "Done", click = function() h.close() end } })
  end)
end
UI.councilPickSheet = councilPickSheet

--- "How loot goes": reserves, GDKP, or the guild's priority lists (first, or only)
local function lootModes(p, s)
  local prio = s.prio or UI.prioAvailable()
  local mode = s.gdkp and "gdkp" or s.prio or "res"
  local function pick(m)
    if m == mode then return end
    local function go()
      if m == "gdkp" then LR.setGdkp(s, true) return end
      if s.gdkp then LR.setGdkp(s, false) end
      LR.setSessionPrio(s, m ~= "res" and m or nil)
    end
    if m == "gdkp" and next(s.res) then
      UI.confirm("GDKP auctions", "Every item is auctioned for gold instead: reserves stop counting (they're kept, in case you switch back), and nobody can reserve.", "Auction", go)
    elseif m == "only" and next(s.res) then
      UI.confirm("Priority lists only", "Reserves stop counting (they're kept, in case you switch back), and nobody can reserve.", "Switch", go)
    else go() end
  end
  p:chips({
    { label = "Reserves and rolls", on = mode == "res", click = function() pick("res") end, tip = "Soft and hard reserves, then everyone rolls." },
    { label = "GDKP auction", on = mode == "gdkp", click = function() pick("gdkp") end,
      tip = "Items are auctioned for gold: raiders bid by typing an amount in raid chat. The gold goes in a pot that's split between everyone at the end." },
    prio and { label = "Priority lists first", on = mode == "both", click = function() pick("both") end, tip = UI.PRIO_MODES[2][3] } or false,
    prio and { label = "Priority lists only", on = mode == "only", click = function() pick("only") end, tip = UI.PRIO_MODES[3][3] } or false,
  }, { gap = 2 })
end

--- the rules, set once before the pull
local function rulesPanel(f, s)
  local raid = LR.raidOf(s)
  local reserving = not s.gdkp and s.prio ~= "only"
  f:panel("This raid's rules", function(p)
    p:row("How loot goes", function(r) lootModes(r, s) end)
    if not reserving then return end
    p:row("Reserves each", function(r)
      stepper(r, nil, s.sr, S.MIN_SR, S.MAX_SR, function(v)
        local cut = 0
        for _, pl in ipairs(S.players(s)) do if #pl.items > v then cut = cut + 1 end end
        local function go() local ok, why = LR.configure(s, v, s.dupes) if not ok then UI.refused(why) end end
        if cut > 0 then
          UI.confirm("Fewer reserves", ("%s already reserved more than %d: their last reserves go."):format(U.plural(cut, "player"), v), "Lower it", go)
        else go() end
      end)
    end)
    p:row("Reserving", function(r)
      r:chips({
        { tick = true, label = "Same item more than once", on = s.dupes, click = function()
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
        not raid.custom and { tick = true, label = "Any item", on = s.any, click = function() LR.setAny(s, not s.any) end,
          tip = "Lets people reserve any item, not just " .. raid.name .. "'s loot: for loot LootRuler's lists don't have yet. Reserves already made stay either way." } or false,
        { tick = true, label = "One reserve win each", on = s.ow, click = function() LR.setOneWin(s, not s.ow) end,
          tip = "Once a player wins one of their reserves, their other reserves stop counting for the rest of the session, so loot goes further. The raid is told when it happens." },
        { tick = true, label = "+1 rule", on = s.plusOne, click = function() LR.setPlusOne(s, not s.plusOne) end,
          tip = "Every item won on a main spec roll is a +1, and players with fewer +1s win main spec rolls over players with more. You can change anyone's +1s on the All reserves tab." },
        UI.boostOn() and { tick = true, label = "Boosted rolls", on = s.boost, click = function() LR.setSessionBoost(s, not s.boost) end,
          tip = "Guild members roll 1 to 100 plus their guild points on main spec (Guild tab). Whoever wins with a boosted roll spends their points." } or false,
      }, { gap = 2 })
    end)
    p:row("Who can reserve", function(r)
      r:chips({
        { tick = true, label = "Only the group", on = s.go, click = function() LR.setGroupOnly(s, not s.go) end,
          tip = "Players outside the group can't reserve for themselves (they're told to ask for an invite). You can still add reserves for anyone, and imports still come in. Switch it off to let guild members reserve before the raid forms." },
        { tick = true, label = "Share with my guild", on = s.guild, click = function()
          if not IsInGuild() then UI.toast("You're not in a guild.") return end
          LR.setGuild(s, not s.guild)
        end, tip = "Guild members with LootRuler can see the session. To let them reserve before the group is made, switch off \"Only the group\"." },
      }, { gap = 2 })
    end)
    p:row("Locking", function(r)
      if s.locked then
        r:inline("|cffff5a4aLocked now.|r", { { "Unlock", function() LR.setLocked(s, false) end } })
        return
      end
      r:chips({ { tick = true, label = s.al and ("Lock by itself at " .. LR.Lock.clock(s.al)) or "Lock by itself", on = s.al ~= nil, click = function()
        if s.al then LR.setAutoLock(s, nil) else UI.autoLockSheet(s) end
      end, tip = "Pick when reserves lock. The raid is told 5, 2 and 1 minute before, and when they lock." } }, { gap = 2 })
      if s.al then r:buttons({ { label = "Change the time", style = "link", click = function() UI.autoLockSheet(s) end } }, "left") end
    end)
  end)
end

--- who gets what, before anyone rolls: hard reserves, extra reserves, the disenchanter, the council
local function whoGetsWhat(f, s)
  f:panel("Who gets what", function(p)
    local hr = U.keys(s.hr)
    p:row("Hard reserves", function(r)
      for _, id in ipairs(hr) do
        local h = s.hr[id]
        local b = K.get(r.owner, "item", r.parent)
        K.setItem(b, r.width, LR.itemIcon(id), LR.coloredName(id), (h.f ~= "" and ("For " .. h.f) or "For nobody in particular") .. (h.n ~= "" and ("  -  " .. h.n) or ""), "",
          { text = "Lift", width = 36, tip = "Lift the hard reserve", click = function() LR.clearHR(s, id) end })
        b:SetScript("OnClick", function() hardReserveSheet(s, id) end)
        b:SetScript("OnEnter", function(self) UI.itemTooltip(self, s, id) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:place(b, 36)
        r:gap(3)
      end
      if #hr == 0 then r:note("None. A hard reserved item can't be soft reserved; you can say who it's for.") end
      r:buttons({ { label = "Add a hard reserve", style = "quiet", click = function()
        UI.pickItem(s, "Hard reserve an item", function(id) hardReserveSheet(s, id) end)
      end } }, "left")
    end)
    if not s.gdkp and s.prio ~= "only" then
      p:row("Extra reserves", function(r)
        local list = {}
        for name, n in pairs(s.xr or {}) do list[#list + 1] = { name, n } end
        table.sort(list, function(a, b) return a[1] < b[1] end)
        r:inline(#list == 0 and "|cff9d9d9dEveryone gets the same.|r"
          or table.concat(U.map(list, function(x) return U.classText(U.short(x[1]), LR.classOf(x[1])) .. " +" .. x[2] end), ", "),
          { { #list == 0 and "Give extra reserves" or "Change", function() UI.extraSheet(s) end } })
      end)
    end
    p:row("Disenchanter", function(r)
      r:inline(s.de and U.classText(U.short(s.de), LR.classOf(s.de)) or "|cff9d9d9dNobody yet.|r", {
        { s.de and "Change" or "Pick a disenchanter", function() UI.pickPlayer("Who disenchants?", function(name) LR.setDisenchanter(s, name) end) end },
        s.de and { "Nobody", function() LR.setDisenchanter(s, nil) end } or false,
      })
    end)
    if not s.gdkp then
      p:row("Loot council", function(r)
        local on = LR.Council.on(s)
        r:inline(on and table.concat(U.map(s.lc, U.short), ", ") or "|cff9d9d9dOff: rolls decide.|r", { { on and "Change" or "Pick a council", function() councilPickSheet(s) end } })
      end)
    end
  end)
end

local function manage(f, s)
  if s.pv then privateView(f, s) return end
  local raid = LR.raidOf(s)
  -- a GDKP raid: the auctions and the pot are what matter (UI/Gdkp.lua), then the rules
  if s.gdkp then UI.gdkpView(f, s) else softresPanel(f, s) end
  rulesPanel(f, s)
  whoGetsWhat(f, s)

  if s.plusOne then
    fold(f, "plusOne", "+1s", "everyone's are on the All reserves tab", function(p)
      p:buttons({
        { label = "Bring in from Gargul", style = "quiet", click = function()
          UI.countsSheet({ title = "+1s from Gargul", gargul = "plusOnes", max = 99,
            note = "Paste Gargul's +1 export (\"Name,+1s\" lines; Gargul: /gl po, Export), or read it straight from Gargul if it's loaded. Each player's +1s are set to these.",
            apply = function(list) UI.toast(("+1s for %s are in."):format(U.plural(LR.importPlusOnes(s, list), "player"))) end })
        end },
        { label = "Copy out", style = "quiet", click = function()
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

  if s.boost and UI.boostOn() then
    local bench = s.bn or {}
    local given = LR.Guild.pointsGiven(s)
    fold(f, "boost", "Boosted rolls and the bench", (given and "points given" or "points not given yet") .. (#bench > 0 and (", " .. #bench .. " on the bench") or ""), function(p)
      local book = LR.book()
      p:note(("Guild members with points can roll 1 to 100 plus their points on main spec. Each raid is worth %d points."):format(book.boost.perRaid))
      if LR.canEditBook() then
        p:buttons({ { label = given and "Give raid points again" or "Give raid points", style = "quiet", click = function() UI.giveRaidPoints(s) end } }, "left")
        p:note(given and "You've given this raid its points." or "Everyone from the guild in the group gets them, and the bench. You can also give them when you end the session.")
      else
        p:note("An officer gives the raid its points (Guild tab).")
      end
      -- the bench: players who came but sat out get the raid's points too, and count as there
      p:text("The bench", { font = "GameFontNormal", color = K.GOLD, gap = 2 })
      p:note(#bench > 0 and ("%s: %s."):format(U.plural(#bench, "player"), table.concat(U.map(bench, U.short), ", "))
        or "Nobody. Players on the bench get the raid's points too, and count as there in the fairness history.")
      p:buttons({ { label = #bench > 0 and "Change the bench" or "Bench players", style = "quiet", click = function() UI.benchSheet(s) end } }, "left")
    end)
  end

  -- the organiser's branding: a name, a message and an icon raiders see (Core/Session.lua)
  fold(f, "brand", "Your raid's name", s.br and s.br.n or "raiders see it in their window", function(p)
    p:note("Name your raid and add a short message (where to sign up, your rules). Raiders with LootRuler see it in their window, and the raid hears it when you post the reserves. It's kept for your next session.")
    brand = brand and brand.sid == s.id and brand or { sid = s.id, n = s.br and s.br.n or "", m = s.br and s.br.m or "", i = s.br and s.br.i }
    local function box(label, key, max, width)
      p:text(label, { font = "GameFontNormalSmall", color = K.GOLD, gap = 2 })
      local e = K.get(p.owner, "edit", p.parent)
      p:place(e, 22, 6, width)
      e:SetMaxLetters(max)
      e:SetText(brand[key] or "")
      e:SetScript("OnTextChanged", function(self, user) if user then brand[key] = self:GetText() end end)
    end
    box("Name", "n", S.BRAND_NAME, 240)
    box("Message", "m", S.BRAND_MSG, p.width - 12)
    local icons = { { plain = true, label = "Icon:" } }
    for i, x in ipairs(S.BRAND_ICONS) do
      icons[#icons + 1] = { label = x[1], on = brand.i == i, click = function() brand.i = brand.i ~= i and i or nil UI.render() end }
    end
    p:chips(icons, { gap = 2 })
    if s.br then
      local b = K.get(p.owner, "item", p.parent)
      K.setItem(b, p.width, S.brandIcon(s.br) or LR.raidIcon(s.raid), s.br.n or raid.name, s.br.m or "", "")
      p:place(b, 36)
      p:gap(2)
    end
    p:buttons({
      { label = "Save", click = function()
        LR.setBrand(s, { n = brand.n, m = brand.m, i = brand.i })
        UI.toast(s.br and "Saved: raiders see it now." or "Nothing to save.")
      end },
      s.br and { label = "Clear", style = "quiet", click = function() LR.setBrand(s, nil) brand = nil end } or nil,
    }, "left")
  end)

  fold(f, "handOver", "Hand over the reserves", s.next and ("waiting for " .. U.short(s.next)) or "when you leave, or someone else runs them", function(p)
    if s.next then
      p:note(("Waiting for %s's LootRuler to take the reserves over. It does as soon as it hears from yours."):format(U.short(s.next)), K.GOLD)
      p:buttons({ { label = "Take it back", style = "quiet", click = function() LR.handOver(s, nil) end } }, "left")
    else
      p:note("Leaving, or letting someone else run the reserves? Hand them over: everything reserved and given out stays, and the raid is told who to whisper.")
      p:buttons({ { label = "Hand the reserves over", style = "quiet", click = function()
        UI.pickLeader("Who runs the reserves now?", function(name)
          local ok, why = LR.handOver(s, name)
          if not ok and why then UI.toast(why) end
        end)
      end } }, "left")
    end
  end)

  f:gap(4)
  f:buttons({
    LR.canSetUp() and { label = "Raid setup", style = "quiet", click = function() UI.lineupSheet() end,
      tip = "Paste who's coming (from raid-helper, a spreadsheet, anywhere) to see who's missing, invite them and sort the raid into groups." } or nil,
    not s.gdkp and { label = "Tell the raid how to reserve", style = "quiet", disabled = LR.groupChannel() == nil, click = function()
      if LR.Whisper.postHowTo() then UI.toast("Posted in " .. (IsInRaid() and "raid" or "party") .. " chat.") end
    end, tip = "Posts: \"" .. LR.Whisper.howTo() .. "\"" } or nil,
    s.gdkp and { label = "Import from softres.it", style = "quiet", click = function() importSheet(s) end } or nil,
  }, "left")
  f:buttons({ { label = "End this session", style = "link", danger = true, click = function() endSession(s) end } }, "left")
end

--- the raid I'm in now (its key), if LootRuler knows it
local function raidHere()
  local w = LR.where()
  return w.kind == "raid" and LR.raidAt(w.map) or nil
end
UI.raidHere = raidHere

--- picks a raid (a sheet): done(key). allowCustom: "Another raid" too; all: "Search every raid" too (browsing)
function UI.pickRaid(title, current, done, allowCustom, all)
  UI.openSheet(title, function(f, h)
    for _, era in ipairs({ { "tbc", "Burning Crusade raids" }, { "classic", "Original raids" } }) do
      f:text(era[2], { font = "GameFontNormal", gap = 2 })
      local chips = {}
      for _, r in ipairs(LR.RAIDS) do
        if r.era == era[1] then
          chips[#chips + 1] = { label = r.name, on = current == r.key, click = function() h.close() done(r.key) end }
        end
      end
      f:chips(chips)
    end
    local more = {}
    if allowCustom then more[#more + 1] = { label = "Another raid", on = current == LR.CUSTOM, click = function() h.close() done(LR.CUSTOM) end,
      tip = "A raid that isn't in LootRuler's lists (a new one, or World of Warcraft: Forever's): name it, and any item can be reserved." } end
    if all then more[#more + 1] = { label = "Search every raid", on = current == "all", click = function() h.close() done("all") end } end
    if #more > 0 then f:gap(2) f:chips(more) end
  end)
end

--- opens reserves from the form: then_import opens the softres.it box straight away
local function openFromDraft(then_import)
  local d = UI.draft
  if d.guild == nil then d.guild = IsInGuild() and true or false end
  if d.raid == LR.CUSTOM and U.trim(d.name or "") == "" then UI.toast("Give the raid a name.") return end
  local s = LR.startSession(d.raid, d.sr, d.dupes, d.guild, d.name, d.any)
  UI.toast(("%s reserves are open."):format(LR.raidOf(s).name))
  UI.go("session")
  if then_import then importSheet(s) end
  return s
end
UI.openFromDraft = openFromDraft

--- a private session (Core/Net.lua) for the raid in the form: then_import opens the softres.it box straight away
local function privateFromDraft(then_import)
  local d = UI.draft
  local mine = LR.privateSession()
  if mine then LR.select(mine.id) UI.go("session") if then_import then importSheet(mine) end return end
  if d.raid == LR.CUSTOM and U.trim(d.name or "") == "" then UI.toast("Give the raid a name.") UI.go("session") return end
  local s = LR.startPrivate(d.raid, d.sr, d.dupes, d.name, d.any)
  UI.toast(("Your private session for %s is open."):format(LR.raidOf(s).name))
  UI.go("session")
  if then_import then importSheet(s) end
end
UI.privateFromDraft = privateFromDraft

--- the draft's raid: the one I'm in, until I pick another
local function draftRaid()
  local d = UI.draft
  if not d.picked then d.raid = raidHere() or d.raid end
  return d.raid
end
UI.draftRaid = draftRaid

local function newSession(f)
  local d = UI.draft
  if d.guild == nil then d.guild = IsInGuild() and true or false end
  draftRaid()
  f:row("Raid", function(r)
    local b = K.button(r.owner, r.parent, "quiet", (d.raid == LR.CUSTOM and "Another raid" or LR.raid(d.raid).name) .. "  v", 180)
    b.text:SetJustifyH("LEFT")
    b:SetScript("OnClick", function()
      UI.pickRaid("Which raid?", d.raid, function(key) d.raid = key d.picked = true UI.render() end, true)
    end)
    r:place(b, 24)
    local here = raidHere()
    local tag = K.get(r.owner, "label", r.parent)
    tag.text:SetFontObject("GameFontHighlightSmall")
    tag.text:SetTextColor(K.rgb(K.SUB))
    tag.text:SetJustifyV("MIDDLE")
    tag.text:SetText(here == d.raid and "you're in it" or "")
    tag:SetSize(110, 24)
    tag:SetPoint("LEFT", b, "RIGHT", 10, 0)
    r:gap(4)
    if d.raid == LR.CUSTOM then
      local e = K.get(r.owner, "edit", r.parent)
      r:place(e, 22, 6, r.width - 12)
      e:SetMaxLetters(40)
      e:SetText(d.name or "")
      K.setHint(e, "The raid's name")
      K.onText(e, function(self) d.name = self:GetText() end)
      r:gap(4)
    end
  end)
  f:gap(2)
  f:cols({
    function(c)
      return c:hot("From softres.it", function(p)
        p:note("The raid reserved on softres.it? Paste its Gargul Export: everyone's reserves come in, with the link to post.", K.TEXT)
        p:buttons({ { label = "Import from softres.it", width = p.width, click = function() openFromDraft(true) end } }, "left")
        p:note("Players can still reserve in LootRuler, or with !reserve, after.")
      end)
    end,
    function(c)
      return c:panel("In LootRuler", function(p)
        p:note("The raid reserves in the addon, or by typing !reserve [item].", K.TEXT)
        stepper(p, "Each", d.sr, S.MIN_SR, S.MAX_SR, function(v) d.sr = v UI.render() end)
        p:chips({
          { tick = true, label = "Same item twice", on = d.dupes, click = function() d.dupes = not d.dupes UI.render() end,
            tip = "Lets a player put more than one of their reserves on the same item (softres.it's \"x2\")." },
          { tick = true, label = "My guild can see it", on = d.guild, click = function()
            if not IsInGuild() then UI.toast("You're not in a guild.") return end
            d.guild = not d.guild UI.render()
          end, tip = "Guild members with LootRuler can see the session. To let them reserve before the group is made, switch off \"Only the group\" on the Session tab once it's open." },
        }, { gap = 4 })
        p:buttons({ { label = "Open reserves", style = "quiet", width = p.width, click = function() openFromDraft(false) end } }, "left")
      end)
    end,
  })
  if IsInGroup() and not UnitIsGroupLeader("player") then
    f:note("You're not the group leader. That's fine if you're running loot, but make sure only one of you opens reserves.", K.GOLD)
  end
  f:note("More rules (GDKP, +1s, priority lists, hard reserves) are on the Session tab once it's open.")
  f:gap(4)
  -- not running loot: a private session (Core/Net.lua), and raid setup for whoever forms the raid
  local mine = LR.privateSession()
  f:buttons({
    LR.canSetUp() and { label = "Raid setup", style = "quiet", click = function() UI.lineupSheet() end,
      tip = "Paste who's coming (from raid-helper, a spreadsheet, anywhere) to see who's missing, invite them and sort the raid into groups." } or nil,
    mine and { label = "Back to your private session", style = "quiet", click = function() LR.select(mine.id) UI.render() end }
      or { label = "Private session", style = "quiet", click = function() privateFromDraft(false) end,
        tip = "Not running loot? A private session keeps the loot list and reserves on your screen only, for this raid. Nothing is sent or said." },
  }, "left")
  f:note("Not running loot? A private session keeps the raid's loot and reserves on your screen only.")
end

local function others(f, current)
  local list = U.filter(LR.sessions(), function(x) return x ~= current end)
  if #list == 0 then return end
  f:panel("Other open sessions", function(p)
    for _, x in ipairs(list) do
      local b = K.get(p.owner, "item", p.parent)
      K.setItem(b, p.width, LR.raidIcon(x.raid), LR.raidOf(x).name,
        (x.pv and "Private, only on your screen" or LR.isLeader(x) and "Yours" or ("By " .. U.short(x.leader))) .. " - " .. U.plural(x.sr, "reserve") .. " each", "",
        not LR.isLeader(x) and { text = "x", tip = "Forget this session", click = function() LR.forget(x) end } or nil)
      b:SetScript("OnClick", function() LR.select(x.id) UI.go("reserve") end)
      p:place(b, 36)
      p:gap(3)
    end
  end)
end

--- someone in the group runs LootRuler reserves, and they don't show by themselves (they aren't the group's leader or
--- master looter, or I'm looking at another session): asked once, never switched without asking. In combat, a chat
--- line says how to get to it instead.
function UI.joinPrompt(t)
  local line = ("%s is running LootRuler reserves for %s here."):format(U.short(t.leader), LR.raidOf(t).name)
  if InCombatLockdown() then LR.print(line .. " Type |cffffd100/lr|r and pick it on the Session tab to join.") return end
  UI.show()
  UI.openSheet("Join their reserves?", function(f, h)
    f:text(line .. " Join them to see what's reserved, and to reserve in them?")
    local cur = LR.current()
    local mine = LR.privateSession()
    if mine then f:note("Joining closes your private session: its loot list and reserves are forgotten.", K.GOLD)
    elseif cur and cur.id ~= t.id then f:note(("You're looking at %s's reserves for %s now."):format(U.short(cur.leader), LR.raidOf(cur).name)) end
    f:gap(6)
    f:buttons({
      { label = "Join", click = function()
        h.close()
        LR.closePrivate()                    -- (in someone's reserves now: a private session isn't open alongside)
        LR.select(t.id)
        UI.toast(("You're in %s's reserves."):format(U.short(t.leader)))
      end },
      { label = "Not now", click = function() h.close() LR.decline(t.id) end },
    }, "left")
    f:note("Either way, it's in the list of sessions on the Session tab.")
  end)
end

--- someone else's session, for a raider: how it stands for me, its rules as a few facts, the leader's message
local function theirSession(f, s)
  local leader = U.short(s.leader)
  if LR.leaderGone(s) then
    f:panel("Nobody's running the reserves", function(p)
      local gone = LR.inGroup(s.leader) and "is offline" or "has left the group"
      if LR.mayTakeOver(s) then
        p:note(("%s, who runs these reserves, %s. As the raid leader (or the master looter) you can take them over: everything reserved and given out so far stays, and the raid is told who to whisper."):format(leader, gone), K.GOLD)
        p:buttons({
          { label = "Take over the reserves", click = function()
            local ok, why = LR.takeOver(s)
            if ok then UI.toast("You run the reserves now.") elseif why then UI.toast(why) end
          end },
          { label = "Hand them to someone else", style = "quiet", click = function()
            UI.pickLeader("Who runs the reserves now?", function(name)
              local ok, why = LR.passOn(s, name)
              if ok then UI.toast(("Handed to %s."):format(U.short(name))) elseif why then UI.toast(why) end
            end)
          end },
        }, "left")
      else
        p:note(("%s, who runs these reserves, %s. The raid leader or the master looter can take them over (Session tab)."):format(leader, gone), K.GOLD)
      end
    end)
  end
  if s.gdkp and s.gk then
    UI.gdkpView(f, s)
  else
    -- how it stands for me
    local used, limit = #LR.myPicks(s), S.limit(s, U.me())
    local lock = s.locked and "They're locked." or (s.al and ("They lock at %s."):format(LR.Lock.clock(s.al))) or ""
    if s.prio == "only" then
      f:strip(("Loot goes by the guild's priority lists. %s"):format(lock), "ok")
    elseif LR.pending(s) then
      f:strip("Your reserves haven't reached " .. leader .. " yet. They go as soon as " .. leader .. "'s addon hears from yours.", "warn")
    elseif used >= limit then
      f:strip(("|cffffffffYou're all set.|r %s in. %s"):format(limit == 1 and "Your reserve is" or (limit == 2 and "Both your reserves are" or ("All %d of your reserves are"):format(limit)), lock), "ok")
    elseif s.locked then
      f:strip(("Locked: %s left unused."):format(U.plural(limit - used, "reserve")), "bad")
    else
      f:strip(("You have %s left. %s"):format(U.plural(limit - used, "reserve"), lock), "warn")
    end
    -- the rules, as a few facts
    local hr = U.keys(s.hr)
    local hrText = #hr == 0 and "Nothing" or (LR.coloredName(hr[1]) .. ((s.hr[hr[1]].f ~= "" and (" for " .. s.hr[hr[1]].f)) or "") .. (#hr > 1 and (" and %d more"):format(#hr - 1) or ""))
    local rolls = {}
    if s.prio then rolls[#rolls + 1] = "priority lists" .. (s.prio == "both" and ", then reserves" or "") end
    if s.prio ~= "only" then rolls[#rolls + 1] = "reserves first" end
    rolls[#rolls + 1] = "then MS over OS"
    if s.plusOne then rolls[#rolls + 1] = "fewer +1s win" end
    if s.boost then rolls[#rolls + 1] = "boosted rolls" end
    f:facts({
      s.prio ~= "only" and { "Reserves each", s.sr .. (s.dupes and ", the same item twice is fine" or ", one per item") } or false,
      { "Hard reserved", hrText },
      { "Rolls", table.concat(rolls, ", ") },
      s.url and { "softres.it", s.url:gsub("^https://", "") } or { "Run by", leader },
    })
  end
  -- the organiser's message (Session tab: Your raid's name)
  if s.br and s.br.m then
    f:panel("From " .. leader, function(p) p:text("\"" .. s.br.m .. "\"") end)
  end
  f:buttons({
    { label = "Open your own reserves", style = "quiet", click = function() UI.ownForm = not UI.ownForm UI.render() end,
      tip = "Only if you run loot instead." },
    { label = "Leave these reserves", style = "quiet", click = function()
      UI.confirm("Leave these reserves?", ("They're taken off your screen. Your picks stay with %s, and if %s sends the reserves again, they come back here."):format(leader, leader),
        "Leave them", function() LR.forget(s) end)
    end },
  }, "left")
  if UI.ownForm then
    f:gap(6)
    f:heading("Open your own reserves", "if you run loot instead")
    newSession(f)
  end
end

function UI.sessionView(f, s)
  if s then claimPanel(f, s) end
  if s and LR.isLeader(s) then
    manage(f, s)
  elseif s then
    theirSession(f, s)
  else
    newSession(f)
  end
  others(f, s)
end
