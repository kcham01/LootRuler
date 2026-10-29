-- The Test tab (switched on in Settings): pretend versions of what happens in a raid, to see how each part looks
-- before the real thing. Everything here stays on this screen: nothing is said in chat, sent to other addons, or
-- rolled with the game's /roll. Pretend rolls use made-up players (UI.PRETEND).
local _, LR = ...
local U, K = LR.U, LR.K
local UI = LR.UI

local test = { reservers = 6, secs = 20, mine = true, name = "", raid = "Karazhan", players = 8, sr = 2 }
local P = LR.Practice

--- two "- n +" on one line: the first after the row's label, the second with its own
local function twoSteppers(p, v1, min1, max1, on1, label2, v2, min2, max2, on2)
  p:chips({
    { label = "-", width = 24, click = function() if v1 > min1 then on1(v1 - 1) end end },
    { label = tostring(v1), on = true, width = 32, click = function() end },
    { label = "+", width = 24, click = function() if v1 < max1 then on1(v1 + 1) end end },
    { plain = true, label = "", width = 18 },
    { plain = true, label = label2 },
    { label = "-", width = 24, click = function() if v2 > min2 then on2(v2 - 1) end end },
    { label = tostring(v2), on = true, width = 32, click = function() end },
    { label = "+", width = 24, click = function() if v2 < max2 then on2(v2 + 1) end end },
  })
end

--- the practice raid: pretend players, the real screens, nothing leaving this one (Core/Practice.lua). It stands out:
--- it's what the tab is for
local function practicePanel(f)
  f:hot("Practice raid", function(p)
    if not P.on then
      p:note("A pretend raid with made-up players, to try reserves, rolling, giving out, GDKP and the loot list on the real screens. Nothing leaves your screen, and it isn't kept.", K.TEXT)
      local raids = {}
      for _, x in ipairs(LR.RAIDS) do
        if x.era == "tbc" and #x.bosses > 0 then raids[#raids + 1] = { label = x.name, key = x.key, on = test.raid == x.key } end
      end
      p:row("Raid", function(r)
        r:place(K.dropdown(r.owner, r.parent, 200, LR.raid(test.raid).name, raids, function(it) test.raid = it.key UI.render() end, "practiceRaid"), 26)
        r:gap(4)
      end, { lw = 110 })
      p:row("Players", function(r) twoSteppers(r, test.players, P.MIN, P.MAX, function(v) test.players = v UI.render() end,
        "Reserves", test.sr, 1, 3, function(v) test.sr = v UI.render() end) end, { lw = 110 })
      local ok, why = P.canStart()
      p:buttons({ { label = "Start the practice raid", disabled = not ok, click = function()
        local started, err = P.start({ raid = test.raid, players = test.players, sr = test.sr })
        if not started then UI.toast(err) end
        UI.render()
      end } }, "left")
      if not ok then p:note(why, K.GOLD) end
      return
    end
    local ps = P.session()
    p:note(("On: %s with %s. Nothing leaves your screen; what the raid would hear shows in your chat, marked Practice. Joining a group ends it."):format(
      ps and LR.raidOf(ps).name or "?", U.plural(#P.players, "pretend player")), K.GREEN)
    -- the next step of a raid night is the red one: reserving, then loot dropping, then rolling it out
    local reserved = 0
    for _, x in ipairs(P.players) do if ps and #LR.Session.reservesOf(ps, x.name) > 0 then reserved = reserved + 1 end end
    local nextStep = reserved == 0 and "reserve" or P.nextDrop() and "roll" or "drop"
    local steps = {
      reserve = { label = "They reserve", click = function()
        local n = P.reserve()
        UI.toast(n > 0 and ("%s on the way, by whisper and in raid chat."):format(U.plural(n, "reserve")) or "Everyone has reserved all they can.")
      end },
      drop = { label = "A boss drops loot", click = function()
        local list = P.drop(3)
        UI.toast(("%s in your bags. Roll them out from the Loot tab or the trade timers."):format(U.plural(#list, "item")))
      end },
      roll = { label = "Roll out the next item", disabled = P.nextDrop() == nil, click = function()
        local roll, why = P.rollNext()
        if not roll then UI.toast(why) end
      end },
    }
    p:text("Next:", { font = "GameFontNormalSmall", color = K.GOLD, gap = 2 })
    p:buttons({ steps[nextStep] }, "left")
    local rest = {}
    for _, k in ipairs({ "reserve", "drop", "roll" }) do
      if k ~= nextStep then local b = steps[k] b.style = "quiet" rest[#rest + 1] = b end
    end
    p:buttons(rest, "left")
    -- what raiders do that a raid leader has to deal with: a swap asked for once reserves are locked, someone leaving
    p:text("The raiders:", { font = "GameFontNormalSmall", color = K.GOLD, gap = 2 })
    local locked = ps and ps.locked
    p:buttons({
      { label = "A raider asks to swap", style = "quiet", disabled = not locked, click = function()
        local x, why = P.askSwap()
        UI.toast(x and ("%s asks to swap a reserve: see Swap requests on the Reserved tab."):format(U.short(x.name)) or why)
      end, tip = "A pretend player whispers \"!lr swap [their reserve] [another item]\", as a player without the addon would." },
      { label = "A raider leaves", style = "quiet", disabled = #P.players <= 1, click = function()
        local x, why = P.leave()
        UI.toast(x and ("%s left the group. Their reserves stay: the Reserved tab says so, with Clear their reserves."):format(U.short(x.name)) or why)
      end, tip = "A pretend player leaves the group, keeping their reserves (one with reserves, when anyone has some). They don't roll any more." },
      P.gone[1] and { label = "Bring " .. U.short(P.gone[#P.gone].name) .. " back", style = "quiet", click = function()
        local x = P.comeBack()
        if x then UI.toast(("%s is back in the group."):format(U.short(x.name))) end
      end } or nil,
    }, "left")
    if not locked then p:note("A swap is asked for once the reserves are locked (Reserved tab).") end
    p:chips({ { tick = true, label = "Make the next roll a tie", on = P.tie, click = function() P.tie = not P.tie UI.render() end } })
    p:note("Everything else works as it does in a raid: the Session tab (GDKP, priority lists, +1s, hard reserves), the reserves and Loot tabs, the loot master window and the trade timers. The pretend players roll, pass and bid on their own.")
    p:buttons({ { label = "End the practice raid", style = "link", danger = true, click = function() P.stop() UI.render() end } }, "left")
  end)
end

--- the Test tab: the practice raid first (it's what the tab is for), then pretend windows and messages, each one click,
--- all on show (nothing folded)
function UI.testView(f, s)
  practicePanel(f)
  f:panel("Roll windows", function(p)
    p:note("A roll window and the strip of who reserved the item, as raiders see them. The dice roll here, not with /roll.")
    p:row("Reserved by", function(r) twoSteppers(r, test.reservers, 0, #UI.PRETEND, function(v) test.reservers = v UI.render() end,
      "Seconds", test.secs, 5, 60, function(v) test.secs = v UI.render() end) end, { lw = 110 })
    p:chips({ { tick = true, label = "I reserved it too", on = test.mine, click = function() test.mine = not test.mine UI.render() end } })
    p:buttons({
      { label = "Open roll", style = "quiet", tip = "Anyone can roll: the window everyone gets.",
        click = function() UI.testRoll({ mode = "OPEN", secs = test.secs, quiet = true }) end },
      { label = "Reserved roll", style = "quiet", tip = "Only the players who reserved it roll, with the strip of who they are.",
        click = function() UI.testRoll({ mode = "SR", reservers = test.reservers, mine = test.mine, secs = test.secs, quiet = true }) end },
      { label = "Gargul roll", style = "quiet", tip = "The window raiders without Gargul get when Gargul rolls an item out (read from raid chat).",
        click = function() UI.testGargul(test.reservers, test.secs, test.mine) end },
    }, "left")
    p:buttons({ { label = "Put windows back", style = "link", click = function()
      LR.db.ui.rollPoint, LR.db.ui.masterPoint = nil, nil
      UI.resetPositions()
    end } }, "left")
  end)

  f:panel("Alerts and raid lines", function(p)
    p:note("What LootRuler would show you or say, shown only to you.")
    p:buttons({
      { label = "Trade time running out", style = "quiet", tip = "The warning when an item you hold has 15 or 5 minutes left to trade.", click = function()
        local line = ("14 minutes left to trade %s to %s."):format(LR.itemLink(UI.pretendItem()), UI.PRETEND[2][1])
        LR.print("(pretend) " .. line)
        if RaidNotice_AddMessage and RaidWarningFrame then RaidNotice_AddMessage(RaidWarningFrame, U.plain(line), ChatTypeInfo["RAID_WARNING"]) end
        LR.sound(SOUNDKIT.RAID_WARNING or 8959)
      end },
      { label = "Reserve reminder", style = "quiet", disabled = not s, tip = "The raid line naming who hasn't reserved yet.", click = function()
        local names = LR.Whisper.notReserved(s)
        if #names == 0 then names = U.map(UI.PRETEND, function(x) return x[1] end) names = { names[1], names[2], names[3] } end
        LR.print("(pretend, not posted) " .. LR.Whisper.reminderText(s, names))
      end },
      { label = "Changing raids", style = "quiet", disabled = not s, tip = "The question when you walk into a different raid than your session's.", click = function()
        local bt = s.raid == "BlackTemple" and "Karazhan" or "BlackTemple"
        UI.newRaidPrompt(s, { map = LR.RAID_MAPS[bt], kind = "raid", name = LR.raid(bt).name }, "raid", true)
      end },
    }, "left")
    if not s then p:note("The reminder and changing raids need a session open (Session tab).") end
  end)

  f:panel("softres.it names", function(p)
    p:note("Type a name as it might be on a softres.it sheet, to see who in your group it would go to.")
    local e = K.get(p.owner, "edit", p.parent)
    p:place(e, 22, 6, p.width - 12)
    e:SetText(test.name)
    K.setHint(e, "A name from the sheet")
    K.onText(e, function(self, user)
      if not user then return end
      test.name = self:GetText()
      UI.render()
      K.refocus(K.lastEdit)
    end)
    K.lastEdit = e
    local typed = U.trim(test.name)
    if typed ~= "" then
      local name = U.full(U.capitalize(typed))
      local m = LR.Gargul.findPlayer(name, LR.Gargul.people(s or { res = {} }, LR.roster()))
      local who = U.short(name)
      if m.to then p:note(("%s goes to %s."):format(who, U.classText(U.short(m.to), LR.classOf(m.to))), K.GREEN)
      elseif m.options then p:note(("%s could be %s: you'd be asked which."):format(who, table.concat(U.map(m.options, U.short), " or ")), K.GOLD)
      elseif #m.near > 0 then p:note(("Nobody in the group is called %s. Close: %s."):format(who, table.concat(U.map(m.near, U.short), ", ")), K.GOLD)
      else p:note(("Nobody in the group is called %s, or anything close."):format(who)) end
    end
  end)
end
