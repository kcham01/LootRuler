-- The Test tab (switched on in Settings): pretend versions of what happens in a raid, to see how each part looks
-- before the real thing. Everything here stays on this screen: nothing is said in chat, sent to other addons, or
-- rolled with the game's /roll. Pretend rolls use made-up players (UI.PRETEND).
local _, LR = ...
local U, K = LR.U, LR.K
local UI = LR.UI

local test = { reservers = 6, secs = 20, mine = true, name = "", raid = "Karazhan", players = 8, sr = 2 }
local P = LR.Practice

--- a "- n +" row for a number
local function stepper(p, label, value, minV, maxV, onChange)
  p:chips({
    { label = label, plain = true },
    { label = "-", width = 24, click = function() if value > minV then onChange(value - 1) end end },
    { label = tostring(value), on = true, width = 32, click = function() end },
    { label = "+", width = 24, click = function() if value < maxV then onChange(value + 1) end end },
  })
end

--- the practice raid: pretend players, the real screens, nothing leaving this one (Core/Practice.lua)
local function practicePanel(f)
  f:panel("Practice raid", function(p)
    if not P.on then
      p:note("Run a pretend raid on your own, with made-up players, to try everything LootRuler does: reserves, rolling, giving out, GDKP, priority lists, the loot list and trades. It uses the real screens. Nothing is said in chat or sent to anyone, and the practice raid isn't kept.")
      local raids = { { plain = true, label = "Raid:" } }
      for _, r in ipairs(LR.RAIDS) do
        if r.era == "tbc" and #r.bosses > 0 then
          raids[#raids + 1] = { label = r.short, on = test.raid == r.key, click = function() test.raid = r.key UI.render() end }
        end
      end
      p:chips(raids, { gap = 2 })
      stepper(p, "Pretend players", test.players, P.MIN, P.MAX, function(v) test.players = v UI.render() end)
      stepper(p, "Reserves each", test.sr, 1, 3, function(v) test.sr = v UI.render() end)
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
    p:buttons({
      { label = "They reserve", click = function()
        local n = P.reserve()
        UI.toast(n > 0 and ("%s on the way, by whisper and in raid chat."):format(U.plural(n, "reserve")) or "Everyone has reserved all they can.")
      end },
      { label = "A boss drops loot", click = function()
        local list = P.drop(3)
        UI.toast(("%s in your bags. Roll them out from the Loot tab or the trade timers."):format(U.plural(#list, "item")))
      end },
    }, "left")
    p:buttons({
      { label = "Roll out the next item", disabled = P.nextDrop() == nil, click = function()
        local roll, why = P.rollNext()
        if not roll then UI.toast(why) end
      end },
      { label = "End the practice raid", click = function() P.stop() UI.render() end },
    }, "left")
    p:chips({ { tick = true, label = "Make the next roll a tie", on = P.tie, click = function() P.tie = not P.tie UI.render() end } })
    p:note("Everything else works as it does in a raid: the Session tab (GDKP, priority lists, +1s, hard reserves), the Reserves and Loot tabs, the loot master window and the trade timers. The pretend players roll, pass and bid on their own.")
  end)
end

function UI.testView(f, s)
  practicePanel(f)
  f:panel("Pretend rolls", function(p)
    p:note("A roll window and the strip of who reserved the item, as raiders see them. Only on your screen; clicking the dice rolls here, not with /roll.")
    stepper(p, "Players who reserved it", test.reservers, 0, #UI.PRETEND, function(v) test.reservers = v UI.render() end)
    stepper(p, "Seconds to roll", test.secs, 5, 60, function(v) test.secs = v UI.render() end)
    p:chips({ { tick = true, label = "I reserved it too", on = test.mine, click = function() test.mine = not test.mine UI.render() end } })
    p:buttons({
      { label = "LootRuler roll: everyone", click = function() UI.testRoll({ mode = "OPEN", secs = test.secs, quiet = true }) end },
      { label = "LootRuler roll: reserved", click = function()
        UI.testRoll({ mode = "SR", reservers = test.reservers, mine = test.mine, secs = test.secs, quiet = true })
      end },
    }, "left")
    p:buttons({
      { label = "Gargul roll", click = function() UI.testGargul(test.reservers, test.secs, test.mine) end },
      { label = "Put windows back", click = function()
        LR.db.ui.rollPoint, LR.db.ui.masterPoint = nil, nil
        UI.resetPositions()
      end },
    }, "left")
    p:note("A Gargul roll shows the window raiders without Gargul get when Gargul rolls an item out (read from raid chat).")
  end)

  f:panel("Pretend messages", function(p)
    p:note("What LootRuler would show or say, without saying it.")
    p:buttons({
      { label = "The 2 hours running out", click = function()
        local line = ("14 minutes left to trade %s to %s."):format(LR.itemLink(UI.pretendItem()), UI.PRETEND[2][1])
        LR.print("(pretend) " .. line)
        if RaidNotice_AddMessage and RaidWarningFrame then RaidNotice_AddMessage(RaidWarningFrame, U.plain(line), ChatTypeInfo["RAID_WARNING"]) end
        LR.sound(SOUNDKIT.RAID_WARNING or 8959)
      end },
      { label = "The reminder", disabled = not s, click = function()
        local names = LR.Whisper.notReserved(s)
        if #names == 0 then names = U.map(UI.PRETEND, function(x) return x[1] end) names = { names[1], names[2], names[3] } end
        LR.print("(pretend, not posted) " .. LR.Whisper.reminderText(s, names))
      end },
      { label = "A trade out of a group", click = function()
        local line = LR.Drops.tradeLine(UI.PRETEND[3][1], { LR.itemLink(UI.pretendItem()) }, 0, {}, 0)
        UI.sayPrompt({ LR.TAG .. " " .. line }, true)
      end },
    }, "left")
    if not s then p:note("The reminder needs a session open (Session tab).") end
  end)

  f:panel("Names from softres.it", function(p)
    p:note("Type a name as it might be on a softres.it sheet, to see who in your group it would go to.")
    local e = K.get(p.owner, "edit", p.parent)
    p:place(e, 22, 6, p.width - 12)
    e:SetText(test.name)
    e:SetScript("OnTextChanged", function(self, user)
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
