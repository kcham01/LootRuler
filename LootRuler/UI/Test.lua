-- The Test tab (switched on in Settings): pretend versions of what happens in a raid, to see how each part looks
-- before the real thing. Everything here stays on this screen: nothing is said in chat, sent to other addons, or
-- rolled with the game's /roll. Pretend rolls use made-up players (UI.PRETEND).
local _, LR = ...
local U, K = LR.U, LR.K
local UI = LR.UI

local test = { reservers = 6, secs = 20, mine = true, name = "" }

--- a "- n +" row for a number
local function stepper(p, label, value, minV, maxV, onChange)
  p:chips({
    { label = label, plain = true },
    { label = "-", width = 24, click = function() if value > minV then onChange(value - 1) end end },
    { label = tostring(value), on = true, width = 32, click = function() end },
    { label = "+", width = 24, click = function() if value < maxV then onChange(value + 1) end end },
  })
end

function UI.testView(f, s)
  f:panel("Pretend rolls", function(p)
    p:note("A roll window and the strip of who reserved the item, as raiders see them. Only on your screen; clicking the dice rolls here, not with /roll.")
    stepper(p, "Players who reserved it", test.reservers, 0, #UI.PRETEND, function(v) test.reservers = v UI.render() end)
    stepper(p, "Seconds to roll", test.secs, 5, 60, function(v) test.secs = v UI.render() end)
    p:chips({ { label = (test.mine and "[x] " or "[  ] ") .. "I reserved it too", on = test.mine, click = function() test.mine = not test.mine UI.render() end } })
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
