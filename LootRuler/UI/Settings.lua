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

  f:panel("Auto-roll", function(p)
    p:note("Your own rules for roll windows: LootRuler rolls or passes for you, and says so.")
    toggle(p, "autoPassUnusable", "Pass on items my class can't use", "Only for items everyone can roll on (not reserved ones).")
    local ids = {}
    for id in pairs(set.autoRollRules) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
      local b = K.get(p.owner, "item", p.parent)
      K.setItem(b, p.width, LR.itemIcon(id), LR.coloredName(id), "Always: " .. LR.AutoRoll.ACTIONS[set.autoRollRules[id]], "",
        { text = "x", tip = "Remove this rule", click = function() LR.AutoRoll.set(id, nil) UI.render() end })
      p:place(b, 36)
      p:gap(2)
    end
    if #ids == 0 then p:note("No item rules yet. Shift-click a roll window's dice, coin or x to always do that for its item, or add one here.") end
    p:buttons({ { label = "Add an item rule", click = function() UI.addRollRule() end } }, "left")
  end)

  f:panel("Reserves where you see items", function(p)
    toggle(p, "highlight", "Glow on my items in loot windows", "The game's loot window and need/greed windows glow on an item you reserved (or that's hard reserved for you).")
    toggle(p, "tooltipInfo", "Reserves in item tooltips", "Every item tooltip says who reserved it and who it went to, while soft reserves are open.")
  end)

  f:panel("Running loot", function(p)
    p:note("For the raid leader, an assistant or the master looter.")
    local chips = { { plain = true, label = "Seconds to roll:" } }
    for _, n in ipairs(LR.Rolls.SECONDS) do
      chips[#chips + 1] = { label = tostring(n), width = 32, on = n == set.rollSeconds, click = function() set.rollSeconds = n UI.render() end }
    end
    p:chips(chips, { gap = 2 })
    p:note("How long everyone has to roll on an item (you can add time during a roll).")
    local keys = { { plain = true, label = "Roll out with:" } }
    for _, x in ipairs(UI.SHORTCUTS) do
      keys[#keys + 1] = { label = x[2], on = set.rollShortcut == x[1], click = function() set.rollShortcut = x[1] UI.render() end }
    end
    p:chips(keys, { gap = 2 })
    p:note("Click an item with these keys held (in your bags, the loot window or a chat link) to roll it out.")
    toggle(p, "raidWarning", "Announce rolls as raid warnings", "Off: in plain raid chat. (Raid warnings need you to lead or assist.)")
    toggle(p, "tradeHelp", "Put won items in trades for me", "When someone who won an item you're holding opens a trade with you, LootRuler puts it in.")
    toggle(p, "tradeAnnounce", "Tell the raid what I trade", "While you're running loot, a line in raid chat says what you traded and to whom (\"Traded [item] to Ann.\"), so nobody wonders where an item went.")
    toggle(p, "raidCommands", "!lr in raid chat", "Raiders without the addon can type \"!lr [item]\" in raid chat, not just whisper you. The answers still go by whisper.")
    toggle(p, "hideWhispers", "Hide !lr messages in my chat", "\"!lr\" whispers, \"!lr\" lines in raid chat and LootRuler's answers stay out of your chat while soft reserves are open.")
  end)

  f:panel("Loot rules (master looter)", function(p)
    toggle(p, "autoLoot", "Hand out loot by my rules", "When you open a corpse with master loot, items your rules match go straight to whoever the rule says. Anything someone reserved is always rolled for instead.")
    local s = LR.Rolls.session()
    if #set.autoLootRules == 0 then
      p:note("No rules yet.")
    end
    for i, rule in ipairs(set.autoLootRules) do
      local b = K.get(p.owner, "item", p.parent)
      local id = tonumber(rule.what:match("^item:(%d+)$"))
      K.setItem(b, p.width, id and LR.itemIcon(id) or "Interface\\Icons\\INV_Misc_Bag_10", LR.AutoLoot.whatText(rule.what),
        "Goes to " .. LR.AutoLoot.toText(rule.to, s), "", { text = "x", tip = "Remove this rule", click = function() LR.AutoLoot.remove(i) UI.render() end })
      p:place(b, 36)
      p:gap(2)
    end
    p:buttons({ { label = "Add a rule", click = function() UI.addLootRule() end } }, "left")
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

--- a sheet to make a loot rule: what it's about, then who gets it
function UI.addLootRule()
  local what, to, linked = nil, nil, ""
  UI.openSheet("Add a loot rule", function(f, h)
    f:text("Which items?", { font = "GameFontNormal", color = K.GOLD, gap = 2 })
    local chips = {}
    for _, w in ipairs(LR.AutoLoot.WHAT) do
      chips[#chips + 1] = { label = w[2], on = what == w[1], click = function() what = w[1] h.redraw(true) end }
    end
    f:chips(chips)
    f:note("Or one item: shift-click it into the box.")
    local e = K.get(f.owner, "edit", f.parent)
    f:place(e, 22, 6, f.width - 12)
    e:SetText(linked)
    K.takeLinks(e)
    e:SetScript("OnTextChanged", function(self, user)
      if not user then return end
      linked = self:GetText()
      local id = LR.idFrom(linked)
      if id then what = "item:" .. id h.redraw(true) end
    end)
    f:gap(6)
    f:text("Who gets them?", { font = "GameFontNormal", color = K.GOLD, gap = 2 })
    f:chips({
      { label = "The disenchanter", on = to == "de", click = function() to = "de" h.redraw(true) end },
      { label = "Me", on = to == "me", click = function() to = "me" h.redraw(true) end },
      { label = (to and to ~= "de" and to ~= "me") and U.short(to) or "Someone in the group...", on = to ~= nil and to ~= "de" and to ~= "me",
        click = function() UI.pickPlayer("Who gets them?", function(name) to = name h.redraw(true) end) end },
    })
    if what and to then
      f:note(("%s will go to %s."):format(LR.AutoLoot.whatText(what), LR.AutoLoot.toText(to, LR.Rolls.session())), K.GREEN)
    end
    f:buttons({ { label = "Cancel", click = function() h.close() end },
      { label = "Add the rule", disabled = not (what and to), click = function() LR.AutoLoot.add(what, to) h.close() UI.render() end } })
  end)
end

--- a sheet to make an auto-roll rule: an item, then pass / main spec / off spec
function UI.addRollRule()
  local id, action, text = nil, nil, ""
  UI.openSheet("Add an auto-roll rule", function(f, h)
    f:note("Shift-click the item into the box (from your bags, a chat link, anywhere).")
    local e = K.get(f.owner, "edit", f.parent)
    f:place(e, 22, 6, f.width - 12)
    e:SetText(text)
    K.takeLinks(e)
    e:SetScript("OnTextChanged", function(self, user)
      if not user then return end
      text = self:GetText()
      id = LR.idFrom(text)
      h.redraw(true)
    end)
    f:gap(6)
    if id then f:text(LR.coloredName(id), { gap = 4 }) end
    f:chips({
      { label = "Always pass", on = action == "pass", click = function() action = "pass" h.redraw(true) end },
      { label = "Always main spec", on = action == "MS", click = function() action = "MS" h.redraw(true) end },
      { label = "Always off spec", on = action == "OS", click = function() action = "OS" h.redraw(true) end },
    })
    f:buttons({ { label = "Cancel", click = function() h.close() end },
      { label = "Add the rule", disabled = not (id and action), click = function() LR.AutoRoll.set(id, action) h.close() UI.render() end } })
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
  { "/lr de [name]", "who disenchants (the leader)" },
  { "/lr test", "a pretend roll window" },
  { "/lr minimap", "hide or show the minimap button" },
}
function UI.help()
  LR.print("commands:")
  for _, c in ipairs(UI.COMMANDS) do print(("  |cffffd100%s|r  %s"):format(c[1], c[2])) end
end
