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
    label and { label = label, plain = true } or false,
    { label = "-", width = 24, click = function() if value > minV then onChange(value - 1) end end },
    { label = tostring(value), on = true, width = 32, click = function() end },
    { label = "+", width = 24, click = function() if value < maxV then onChange(value + 1) end end },
  })
end

--- the Test tab's parts that open and close (kept per character): key -> true
local function testFold(f, key, title, what, fill)
  if type(LR.db.ui.testOpen) ~= "table" then LR.db.ui.testOpen = {} end
  local open = LR.db.ui.testOpen
  f:fold(title, what, open[key] == true, function() open[key] = not open[key] or nil UI.render() end, fill)
end

--- the practice raid: pretend players, the real screens, nothing leaving this one (Core/Practice.lua). It stands out:
--- it's what the tab is for
local function practicePanel(f)
  f:hot("Practice raid", function(p)
    if not P.on then
      p:note("Run a pretend raid on your own, with made-up players, to try everything LootRuler does: reserves, rolling, giving out, GDKP, priority lists, the loot list and trades. It uses the real screens. Nothing is said in chat or sent to anyone, and the practice raid isn't kept.", K.TEXT)
      p:row("Raid", function(r)
        local raids = {}
        for _, x in ipairs(LR.RAIDS) do
          if x.era == "tbc" and #x.bosses > 0 then
            raids[#raids + 1] = { label = x.short, on = test.raid == x.key, click = function() test.raid = x.key UI.render() end }
          end
        end
        r:chips(raids, { gap = 2 })
      end, { lw = 110 })
      p:row("Pretend players", function(r) stepper(r, nil, test.players, P.MIN, P.MAX, function(v) test.players = v UI.render() end) end, { lw = 110 })
      p:row("Reserves each", function(r) stepper(r, nil, test.sr, 1, 3, function(v) test.sr = v UI.render() end) end, { lw = 110 })
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
    rest[#rest + 1] = { label = "End the practice raid", style = "link", danger = true, click = function() P.stop() UI.render() end }
    p:buttons(rest, "left")
    p:chips({ { tick = true, label = "Make the next roll a tie", on = P.tie, click = function() P.tie = not P.tie UI.render() end } })
    p:note("Everything else works as it does in a raid: the Session tab (GDKP, priority lists, +1s, hard reserves), the reserves and Loot tabs, the loot master window and the trade timers. The pretend players roll, pass and bid on their own.")
  end)
end

function UI.testView(f, s)
  practicePanel(f)
  testFold(f, "rolls", "Pretend rolls", "a roll window, only on your screen", function(p)
    p:note("A roll window and the strip of who reserved the item, as raiders see them. Clicking the dice rolls here, not with /roll.")
    p:row("Reserved by", function(r) stepper(r, nil, test.reservers, 0, #UI.PRETEND, function(v) test.reservers = v UI.render() end) end, { lw = 110 })
    p:row("Seconds to roll", function(r) stepper(r, nil, test.secs, 5, 60, function(v) test.secs = v UI.render() end) end, { lw = 110 })
    p:chips({ { tick = true, label = "I reserved it too", on = test.mine, click = function() test.mine = not test.mine UI.render() end } })
    p:buttons({
      { label = "LootRuler roll: everyone", style = "quiet", click = function() UI.testRoll({ mode = "OPEN", secs = test.secs, quiet = true }) end },
      { label = "LootRuler roll: reserved", style = "quiet", click = function()
        UI.testRoll({ mode = "SR", reservers = test.reservers, mine = test.mine, secs = test.secs, quiet = true })
      end },
    }, "left")
    p:buttons({ { label = "Put windows back", style = "link", click = function()
      LR.db.ui.rollPoint, LR.db.ui.masterPoint = nil, nil
      UI.resetPositions()
    end } }, "left")
  end)

  testFold(f, "messages", "Pretend messages", "trade warning, reminder line, name check", function(p)
    p:note("What LootRuler would show or say, without saying it.")
    p:buttons({
      { label = "The 2 hours running out", style = "quiet", click = function()
        local line = ("14 minutes left to trade %s to %s."):format(LR.itemLink(UI.pretendItem()), UI.PRETEND[2][1])
        LR.print("(pretend) " .. line)
        if RaidNotice_AddMessage and RaidWarningFrame then RaidNotice_AddMessage(RaidWarningFrame, U.plain(line), ChatTypeInfo["RAID_WARNING"]) end
        LR.sound(SOUNDKIT.RAID_WARNING or 8959)
      end },
      { label = "The reminder", style = "quiet", disabled = not s, click = function()
        local names = LR.Whisper.notReserved(s)
        if #names == 0 then names = U.map(UI.PRETEND, function(x) return x[1] end) names = { names[1], names[2], names[3] } end
        LR.print("(pretend, not posted) " .. LR.Whisper.reminderText(s, names))
      end },
      { label = "Changing raids", style = "quiet", disabled = not s, click = function()
        local bt = s.raid == "BlackTemple" and "Karazhan" or "BlackTemple"
        UI.newRaidPrompt(s, { map = LR.RAID_MAPS[bt], kind = "raid", name = LR.raid(bt).name }, "raid", true)
      end },
    }, "left")
    if not s then p:note("The reminder and changing raids need a session open (Session tab).") end
    p:gap(4)
    p:text("Names from softres.it", { font = "GameFontNormal", color = K.GOLD, gap = 2 })
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

  testFold(f, "gargul", "Gargul", "a pretend Gargul roll", function(p)
    p:note("The window raiders without Gargul get when Gargul rolls an item out (read from raid chat), with who reserved it.")
    p:buttons({ { label = "Gargul roll", style = "quiet", click = function() UI.testGargul(test.reservers, test.secs, test.mine) end } }, "left")
  end)
end
