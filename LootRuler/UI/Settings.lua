-- The Settings tab: every option in one place, each with a line saying what it does. Features a raid
-- doesn't always use (plus ones, priority lists, GDKP, ...) get a switch here when they arrive, and stay out
-- of everyone's way until a leader turns them on.
local _, LR = ...
local U, K = LR.U, LR.K
local UI = LR.UI

--- a yes/no option: a chip, and what it does underneath
local function toggle(p, key, label, what, after)
  local set = LR.db.settings
  p:chips({ { label = (set[key] and "[x] " or "[  ] ") .. label, on = set[key], click = function()
    set[key] = not set[key]
    if after then after(set[key]) end
    UI.render()
  end } }, { gap = 2 })
  p:note(what)
end

function UI.settingsView(f)
  local set = LR.db.settings

  f:panel("Roll windows", function(p)
    p:note("When loot is rolled out with LootRuler, a roll window pops up: dice for main spec, coin for off spec, x to pass. On a reserved item only the players who reserved it can roll.")
    toggle(p, "rollWindow", "Show roll windows", "Off: roll by typing /roll like everyone without the addon.", function() UI.rollWindows() end)
    toggle(p, "rollOnlyMine", "Only for items I can roll on", "Leaves out items other players reserved, and ties you're not in.", function() UI.rollWindows() end)
    p:buttons({
      { label = "Try the roll window", click = function() UI.testRoll() end },
      { label = "Put windows back", click = function()
        LR.db.ui.rollPoint, LR.db.ui.masterPoint = nil, nil
        UI.resetPositions()
        UI.toast("Roll windows and the loot master window are back where they started.")
      end },
    }, "left")
    p:note("Drag a roll window to move them all.")
  end)

  f:panel("Running loot", function(p)
    p:note("For the raid leader, an assistant or the master looter.")
    local chips = { { plain = true, label = "Seconds to roll:" } }
    for _, n in ipairs(LR.Rolls.SECONDS) do
      chips[#chips + 1] = { label = tostring(n), width = 32, on = n == set.rollSeconds, click = function() set.rollSeconds = n UI.render() end }
    end
    p:chips(chips, { gap = 2 })
    p:note("How long everyone has to roll on an item (you can add time during a roll).")
    toggle(p, "raidWarning", "Announce rolls as raid warnings", "Off: in plain raid chat. (Raid warnings need you to lead or assist.)")
    toggle(p, "tradeHelp", "Put won items in trades for me", "When someone who won an item you're holding opens a trade with you, LootRuler puts it in.")
    toggle(p, "hideWhispers", "Hide !lr whispers in my chat", "Raiders' \"!lr\" whispers and LootRuler's answers stay out of your chat while you have soft reserves open.")
  end)

  f:panel("This window", function(p)
    p:chips({ { label = (LR.db.ui.hideMinimap and "[  ] " or "[x] ") .. "Minimap button", on = not LR.db.ui.hideMinimap, click = function()
      LR.db.ui.hideMinimap = not LR.db.ui.hideMinimap
      if LR.minimap then LR.minimap:SetShown(not LR.db.ui.hideMinimap) end
      UI.render()
    end } }, { gap = 2 })
    p:note("Without it, /lr opens LootRuler.")
  end)

  f:panel("About", function(p)
    p:kv({ { "Version", LR.VERSION } })
    p:gap(4)
    p:note("/lr opens this window. /lr help lists the rest.")
    p:note("Bugs and ideas: github.com/kcham01/LootRuler")
  end)
end

--- the slash commands, for /lr help
UI.COMMANDS = {
  { "/lr", "open or close LootRuler" },
  { "/lr session", "the Session tab (open reserves)" },
  { "/lr reserves", "everyone's reserves" },
  { "/lr loot", "the raid's loot" },
  { "/lr settings", "the Settings tab" },
  { "/lr roll [item]", "roll an item out" },
  { "/lr master", "bring back the loot master window" },
  { "/lr test", "a pretend roll window" },
  { "/lr minimap", "hide or show the minimap button" },
}
function UI.help()
  LR.print("commands:")
  for _, c in ipairs(UI.COMMANDS) do print(("  |cffffd100%s|r  %s"):format(c[1], c[2])) end
end
