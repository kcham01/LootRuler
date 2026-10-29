-- The Settings tab: every option in one place, each with a line saying what it does. Features a raid
-- doesn't always use (plus ones, priority lists, GDKP, ...) get a switch here when they arrive, and stay out
-- of everyone's way until a leader turns them on.
local _, LR = ...
local U, K, R = LR.U, LR.K, LR.Roll
local UI = LR.UI

--- a yes/no option: a chip, and what it does underneath
local function toggle(p, key, label, what, after)
  local set = LR.db.settings
  p:chips({ { tick = true, label = label, on = set[key], click = function()
    set[key] = not set[key]
    if after then after(set[key]) end
    UI.render()
  end } }, { gap = 2 })
  p:note(what)
end

-- The sections go down the side, under three headings; the one picked is shown beside them (kept per character in
-- db.ui.settingsPage). "All settings" shows every section on one page, and the search box shows every section whose
-- name or line matches.
local sections, groupName = {}, nil

--- a section: its title, a line saying what's in it now, and its contents (drawn when it's shown)
local function section(f, title, what, fill)
  sections[#sections + 1] = { group = groupName, title = title, what = what, fill = fill }
end

--- the sections after this go under a heading
local function group(f, text)
  groupName = text
end

local NAV = 128              -- the list of sections down the side

--- draws the list down the side and the section(s) shown beside it
local function drawSections(f)
  local page = LR.db.ui.settingsPage
  local q = U.lower(U.trim(UI.setQ or ""))
  local function matches(x) return q == "" or x.title:lower():find(q, 1, true) or (x.what or ""):lower():find(q, 1, true) end
  local known = page == "all"
  for _, x in ipairs(sections) do if x.title == page then known = true end end
  if not known then page = sections[1].title LR.db.ui.settingsPage = page end
  -- down the side: the search box, then each heading and its sections
  local nav = K.flow(f.owner, f.parent, f.x, f.y, NAV)
  local box = K.get(f.owner, "edit", f.parent)
  nav:place(box, 22, 4, NAV - 6)
  box:SetText(UI.setQ or "")
  K.setHint(box, "Search")
  local seq = 0
  K.onText(box, function(self, user)
    if not user then return end
    UI.setQ = self:GetText()
    UI.setFocus = true
    seq = seq + 1
    local mine = seq
    C_Timer.After(0.15, function() if mine == seq then UI.render() end end)
  end)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() UI.setFocus = false end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() UI.setFocus = false end)
  if UI.setFocus then K.refocus(box) end
  nav:gap(6)
  local shown, lastGroup = {}, nil
  local function navItem(title, label)
    local b = K.get(f.owner, "nav", f.parent)
    local h = K.setNav(b, NAV, label or title, q == "" and page == title)
    b:SetScript("OnClick", function()
      LR.db.ui.settingsPage = title
      UI.setQ, UI.setFocus = "", false
      UI.render()
    end)
    nav:place(b, h)
    nav:gap(1)
  end
  for _, x in ipairs(sections) do
    if matches(x) then
      shown[#shown + 1] = x
      if x.group ~= lastGroup then
        lastGroup = x.group
        nav:gap(4)
        nav:text(x.group, { font = "GameFontNormalSmall", color = K.GOLD, gap = 2 })
      end
      navItem(x.title)
    end
  end
  nav:gap(8)
  navItem("all", "All settings")
  -- beside it: the section picked, or every one (All settings, or a search)
  local content = K.flow(f.owner, f.parent, f.x + NAV + 12, f.y, f.width - NAV - 12)
  local list = (q ~= "" or page == "all") and shown or {}
  if q == "" and page ~= "all" then for _, x in ipairs(sections) do if x.title == page then list = { x } end end end
  if #list == 0 then content:note("No section matches your search.") end
  for i, x in ipairs(list) do
    if i > 1 then content:gap(10) end
    content:text(x.title, { font = "GameFontNormalLarge", color = K.GOLD, gap = 2 })
    if x.what and x.what ~= "" then content:note(x.what) end
    content:gap(2)
    x.fill(content)
  end
  f.y = math.max(nav.y, content.y)
end

local function count(n, one, zero) return n == 0 and zero or U.plural(n, one) end

function UI.settingsView(f)
  local set = LR.db.settings
  sections, groupName = {}, nil

  group(f, "For everyone")

  section(f, "Roll windows", "What pops up when loot is rolled out, and what it shows.", function(p)
    p:note("When loot is rolled out with LootRuler, a roll window pops up: dice for main spec, coin for off spec, x to pass. On a reserved item only the players who reserved it can roll.")
    toggle(p, "rollWindow", "Show roll windows", "Off: roll by typing /roll like everyone without the addon.", function() UI.rollWindows() end)
    toggle(p, "rollList", "Show everyone's rolls", "Roll windows list the best rolls so far (the ones that count), with who rolled them, under the timer.", function() UI.rollWindows() end)
    toggle(p, "reservedAlert", "Tell me when my item is rolled out", "When an item you reserved, are on the priority list for, or have on your thatsmybis wishlist is rolled out: a message in the middle of your screen, a sound, and the game's icon flashes if you're in another window.")
    toggle(p, "gargulWindows", "Roll windows for Gargul's rolls", "When Gargul rolls an item out (read from raid chat), a roll window like LootRuler's pops up, with the reserves. Not if you have Gargul yourself: it shows its own.", function() UI.rollWindows() end)
    toggle(p, "rollOnlyMine", "Only for items I can roll on", "Leaves out items other players reserved, and ties you're not in.", function() UI.rollWindows() end)
    toggle(p, "outbidAlert", "Tell me when I'm outbid", "In an auction, when someone bids more than you: a message in the middle of your screen and a sound.")
    toggle(p, "answerBagChecks", "Answer bag checks", "When whoever runs loot asks the group about some items (a flask, a key), LootRuler tells them how many you carry, in your bags and bank.")
    toggle(p, "rollHideUnusable", "Not for items my class can't use", "Leaves out items everyone can roll on that your class can't use (a plate chest for a mage, say). You can still /roll.", function() UI.rollWindows() end)
    toggle(p, "rollCloseAfter", "Close the window once I've rolled", "It goes a moment after you roll, instead of staying to show who wins.", function() UI.rollWindows() end)
    local sizes = { { plain = true, label = "Size:" } }
    for _, x in ipairs(UI.ROLL_SIZES) do
      sizes[#sizes + 1] = { label = x[2], on = set.rollScale == x[1], click = function() set.rollScale = x[1] UI.rollWindows() UI.render() end }
    end
    p:chips(sizes, { gap = 2 })
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

  section(f, "Sounds", (set.sounds and "On" or "Off") .. ": LootRuler's sounds, and which volume they follow.", function(p)
    toggle(p, "sounds", "LootRuler's sounds", "Off: LootRuler makes no sound (new roll windows, your item being up, being outbid, trade time running out).")
    local chips = { { plain = true, label = "Play them on:" } }
    for _, c in ipairs(LR.SOUND_CHANNELS) do
      chips[#chips + 1] = { label = c[2], on = set.soundChannel == c[1], click = function() set.soundChannel = c[1] LR.sound(SOUNDKIT.RAID_WARNING or 8959) UI.render() end }
    end
    p:chips(chips, { gap = 2 })
    p:note("The game's sound volume for that channel decides how loud they are.")
  end)

  local autoRules = 0
  for _ in pairs(set.autoRollRules) do autoRules = autoRules + 1 end
  section(f, "Auto-roll", "Rolls or passes for you on items you pick: " .. count(autoRules, "rule", "no rules yet") .. ".", function(p)
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

  section(f, "Need and Greed (group loot)", (set.groupLoot and "On" or "Off") .. ": your rules for the game's Need / Greed rolls ("
    .. count(#set.groupLootRules, "rule", "no rules yet") .. ").", function(p)
    p:note("Your own rules for the game's Need / Greed windows, when the group isn't on master loot. LootRuler rolls what the first matching rule says, and tells you.")
    toggle(p, "groupLoot", "Roll Need / Greed by my rules", "Off: you roll every item yourself.")
    toggle(p, "groupLootConfirm", "Don't ask \"this item will bind to you\" for my rules", "When a rule needs or greeds an item that binds when picked up, the game's question is answered yes. Only for rolls your rules make.")
    local G = LR.GroupLoot
    for i, rule in ipairs(set.groupLootRules) do
      local b = K.get(p.owner, "item", p.parent)
      local id = tonumber(rule.what:match("^item:(%d+)$"))
      K.setItem(b, p.width, id and LR.itemIcon(id) or "Interface\\Buttons\\UI-GroupLoot-Dice-Up", LR.AutoLoot.whatText(rule.what),
        G.actText(rule.act), "", { text = "x", tip = "Remove this rule", click = function() G.remove(i) UI.render() end })
      p:place(b, 36)
      p:gap(2)
    end
    if #set.groupLootRules == 0 then p:note("No rules yet.") end
    p:buttons({ { label = "Add a Need / Greed rule", click = function() UI.addGroupRule() end } }, "left")
  end)

  section(f, "Reserves where you see items", "Who reserved it: in tooltips, loot windows and roll windows.", function(p)
    toggle(p, "highlight", "Glow on my items in loot windows", "The game's loot window and need/greed windows glow on an item you reserved (or that's hard reserved for you).")
    toggle(p, "tooltipInfo", "Reserves in item tooltips", "Every item tooltip says who reserved it and who it went to, while soft reserves are open.")
    toggle(p, "lootTags", "Who reserved it, in the loot window", "The game's loot window marks every reserved item (SR, or HR when it's hard reserved) and says who reserved it, whoever you are.")
    toggle(p, "pickedUp", "Tell me what's picked up", "When the loot master picks up loot, a small note at the top of your screen says what it was and who reserved it. It takes no clicks and goes by itself.")
    toggle(p, "reserveStrip", "Who reserved it, while it's rolled for", "When an item is rolled for, with LootRuler or Gargul, a small strip above the roll window lists everyone who reserved it. It goes when the roll ends.")
  end)

  group(f, "Running loot", "For whoever runs the loot: the master looter, or the raid leader without master loot.")
  section(f, "Rolling out loot", "How long rolls last, shortcut keys, and what the raid hears.", function(p)
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
    toggle(p, "rollCountdown", "Count down the end of a roll", "Raid chat hears \"You have 10 seconds to roll on [item].\", then \"5...\", \"4...\", \"3...\", \"2...\", \"1...\". Off: one line, \"5 seconds left to roll\".")
    toggle(p, "confirmWinner", "Say the winner when I give it out", "When rolls close, nothing is said until you click Award (or Give) in the loot master window, so you can check the rolls first: the winner is the next line. Off: the winner is said as soon as rolls close, and again when it's given out.")
    toggle(p, "raidWarning", "Announce rolls as raid warnings", "Off: in plain raid chat. (Raid warnings need you to lead or assist.)")
    toggle(p, "announceLoot", "Post the loot in raid chat", "When you open a corpse with master loot, each epic item, and anything reserved, is posted in raid chat once, with who reserved it (or who it's hard reserved for).")
    toggle(p, "inspectGear", "Inspect raiders' gear", "When someone rolls, LootRuler looks at what they wear in that slot with the game's own inspect (when they're close, and not in combat), and shows it beside their roll. The Raid gear list (Loot tab) inspects the same way. Off: nobody is inspected.")
    toggle(p, "mlPrompt", "Ask me when I become master looter", "LootRuler asks whether to open the loot master window and tell the raid how loot works.")
    toggle(p, "mlAnnounce", "Tell the raid when I become master looter", "One line in raid chat: who runs loot, and how to roll.")
  end)

  section(f, "Giving out and trading", "Trades with winners, trade timers, and the list of loot given out.", function(p)
    toggle(p, "autoTrade", "Open a trade with the winner", "When you give out an item that's in your bags, a trade with the winner opens if they're close, and LootRuler puts the item in. Too far away: they're whispered to come and trade you.")
    toggle(p, "tradeHelp", "Put won items in trades for me", "When someone who won an item you're holding opens a trade with you, LootRuler puts it in.")
    toggle(p, "tradeTimers", "Trade timers on screen", "A small window with a bar for each item in your bags that you still have to roll out or trade, and how long is left of the 2 hours to trade it. Click one to roll it out, or to open a trade with whoever won it.", function() UI.tradeTimers() end)
    toggle(p, "tradeWarn", "Warn me before the 2 hours to trade run out", "For items you're holding, a message in the middle of your screen 15 minutes before you can't trade one any more, and again at 5: which item, who it's for, or that it hasn't been rolled out yet. Only you see it.")
    toggle(p, "tradeAnnounce", "Tell the raid what I trade", "While you're running loot, a line in raid chat says what you traded and to whom (\"Traded [item] x3 to Ann.\"), and what you enchanted for someone and what they paid, so nobody wonders where an item went.")
    toggle(p, "raidPrompt", "Ask for a new session in a new raid", "With a session open, going into a different raid, or into its raid on a new lockout, asks whether to start a new session there. Loot is only listed for a session while you're in its raid.")
    toggle(p, "remindUnrecorded", "Ask to record loot given without LootRuler", "When you give an item out with the game's own loot menu, LootRuler asks whether to put it on the list of loot given out (and how they got it).")
    toggle(p, "recordGargul", "Count Gargul's awards as given out", "When Gargul says in raid chat who an item was awarded to, it goes on the list of loot given out (their reserve if they had one on it, off spec if Gargul says so, else main spec). For the leader of the reserves.")
    toggle(p, "recordGroupWins", "Count group loot wins as given out", "Without a master looter, an epic item someone wins with the game's Need / Greed goes on the list of loot given out (their reserve if they had one on it, else main spec). For the leader of the reserves.")
    toggle(p, "awardGuild", "Tell my guild who got what", "Each item you give out (and any you take back) gets a line in guild chat too, with the raid's name: \"Karazhan: [item] goes to Ann (MS 85).\"")
  end)

  section(f, "Raiders without LootRuler", "!reserve in raid chat, and how people who join hear how to reserve.", function(p)
    toggle(p, "raidCommands", "!reserve in raid chat", "Raiders without the addon can type \"!reserve [item]\" in raid chat, not just whisper you (\"!lr\" works too). The answers still go by whisper.")
    toggle(p, "hideWhispers", "Hide !reserve messages in my chat", "\"!reserve\" and \"!lr\" whispers, those lines in raid chat and LootRuler's answers stay out of your chat while soft reserves are open.")
    toggle(p, "remindOnJoin", "Tell people who join how to reserve", "While your soft reserves are open, anyone who joins the group and hasn't reserved hears how to, in one raid chat line a few seconds after they join.")
  end)

  section(f, "Auctions (GDKP)", "Final calls and the pot, while items are auctioned for gold.", function(p)
    toggle(p, "finalCall", "Final call in auctions", "With 10 seconds left on an auction, raid chat hears the highest bid and who has it.")
    toggle(p, "potAfterSale", "Say the pot after each sale", "The line saying who bought an item ends with how big the pot is so far.")
  end)

  section(f, "Roll types", "Your own kinds of roll, like Transmog (/roll 98): " .. count(#set.rollKinds, "roll type", "none yet") .. ".", function(p)
    p:note("Besides main spec (/roll) and off spec (/roll 99), items rolled out to everyone can have your own kinds of roll, each with its own number. They count after off spec, in this order. Everyone sees them in the roll window and in raid chat.")
    for i, x in ipairs(set.rollKinds) do
      local b = K.get(p.owner, "item", p.parent)
      K.setItem(b, p.width, "Interface\\Buttons\\UI-GroupLoot-Dice-Up", x.n,
        ("/roll %d. Counts after %s."):format(x.hi, i == 1 and "off spec" or set.rollKinds[i - 1].n), "",
        { text = "x", tip = "Take it off", click = function() table.remove(set.rollKinds, i) UI.render() end })
      p:place(b, 36)
      p:gap(2)
    end
    local acts = {}
    local transmog = R.addKind(set.rollKinds, "Transmog", 98)
    if transmog then acts[#acts + 1] = { label = "Add Transmog (/roll 98)", click = function() set.rollKinds = transmog UI.render() end } end
    if #set.rollKinds < R.MAX_EXTRA then acts[#acts + 1] = { label = "Add a roll type", click = function() UI.addRollKind() end } end
    if #acts > 0 then p:buttons(acts, "left") end
  end)

  local noted = 0
  for _ in pairs(LR.db.notes) do noted = noted + 1 end
  section(f, "Item notes", "Your notes on items (\"Tanks first\"), shown when they're rolled out: " .. count(noted, "note", "none yet") .. ".", function(p)
    p:note("Your own note on an item, like \"Warrior > Rogue\" or \"Tanks first\". When you roll the item out, raid chat and everyone's roll window show it, and you see it in the item's tooltip. Kept between raids.")
    local ids = {}
    for id in pairs(LR.db.notes) do ids[#ids + 1] = id end
    table.sort(ids)
    for i, id in ipairs(ids) do
      if i > 8 then p:note(("...and %d more (Copy them out to see them all)."):format(#ids - 8)) break end
      local b = K.get(p.owner, "item", p.parent)
      K.setItem(b, p.width, LR.itemIcon(id), LR.coloredName(id), LR.db.notes[id], "",
        { text = "x", tip = "Take the note off", click = function() LR.setNote(id, nil) UI.render() end })
      b:SetScript("OnClick", function() UI.noteSheet(id) end)
      p:place(b, 36)
      p:gap(2)
    end
    p:buttons({
      { label = "Add a note", click = function() UI.noteSheet() end },
      { label = "Bring in or copy out", click = function() UI.notesSheet() end },
    }, "left")
  end)

  local wished = LR.Prio.count(LR.db.wish)
  section(f, "thatsmybis wishlists", "Who wishlisted an item, from thatsmybis.com: " .. (wished > 0 and U.plural(wished, "item") .. " on wishlists" or "none brought in") .. ".", function(p)
    local items, places = LR.Prio.count(LR.db.wish)
    p:note("Bring in your guild's wishlists from thatsmybis.com (its Gargul download). When you roll an item out, raid chat and everyone's roll window say who in the group wishlisted it, and so do the loot posts and the item's tooltip. Someone who has been given the item is left out.")
    if items > 0 then
      p:note(("%s on wishlists (%s)."):format(U.plural(items, "item"), U.plural(places, "place")), K.GOLD)
    end
    p:buttons({
      { label = "Bring in wishlists", click = function() UI.wishSheet() end },
      { label = "Forget them", disabled = items == 0, click = function()
        UI.confirm("Forget the wishlists", "The wishlists you brought in are taken off this character.", "Forget", function()
          LR.db.wish = {}
          LR.changed("notes")
          UI.render()
        end)
      end },
    }, "left")
  end)

  section(f, "Loot rules (master looter)", "Gold, and items your rules match, handed out as you loot: " .. count(#set.autoLootRules, "rule", "no rules yet") .. ".", function(p)
    toggle(p, "lootGold", "Pick up the gold", "When you open a corpse with master loot, its gold is picked up (the game shares it out with the group).")
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

  group(f, "More")
  section(f, "This window", "The minimap button.", function(p)
    p:chips({ { tick = true, label = "Minimap button", on = not LR.db.ui.hideMinimap, click = function()
      LR.db.ui.hideMinimap = not LR.db.ui.hideMinimap
      if LR.minimap then LR.minimap:SetShown(not LR.db.ui.hideMinimap) end
      UI.render()
    end } }, { gap = 2 })
    p:note("Without it, /lr opens LootRuler.")
  end)

  section(f, "Testing", "The Test tab: pretend rolls, messages and a practice raid.", function(p)
    toggle(p, "testTab", "Show the Test tab", "A tab of pretend rolls and messages, to see how LootRuler looks before a raid. Everything on it happens only on your screen: nothing is said in chat or sent to anyone.")
  end)

  local profiles = 0
  for _ in pairs(LR.db.profiles) do profiles = profiles + 1 end
  section(f, "Profiles", "Save these settings under a name, and switch between them: " .. count(profiles, "profile", "none saved") .. ".", UI.profilesFill)

  section(f, "About", "Version " .. LR.VERSION .. ", who has LootRuler, what's new and the tour.", function(p)
    p:kv({ { "Version", LR.VERSION } })
    p:gap(4)
    p:buttons({ { label = "Who has LootRuler", click = function() UI.versionSheet() end },
      { label = "What's new", click = function() UI.whatsNew() end },
      { label = "The tour", click = function() UI.tour(1) end } }, "left")
    p:note("/lr opens this window. /lr help lists the rest.")
    p:note("Bugs and ideas: github.com/kcham01/LootRuler")
  end)
  drawSections(f)
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
      { label = "Everyone in turn", on = to == "rr", click = function() to = "rr" h.redraw(true) end },
      { label = "Nobody: leave it", on = to == "skip", click = function() to = "skip" h.redraw(true) end },
      { label = (to and to ~= "de" and to ~= "me" and to ~= "rr" and to ~= "skip") and U.short(to) or "Someone in the group...", on = to ~= nil and to ~= "de" and to ~= "me" and to ~= "rr" and to ~= "skip",
        click = function() UI.pickPlayer("Who gets them?", function(name) to = name h.redraw(true) end) end },
    })
    if what and to then
      f:note(("%s will go to %s."):format(LR.AutoLoot.whatText(what), LR.AutoLoot.toText(to, LR.Rolls.session())), K.GREEN)
    end
    f:buttons({ { label = "Cancel", click = function() h.close() end },
      { label = "Add the rule", disabled = not (what and to), click = function() LR.AutoLoot.add(what, to) h.close() UI.render() end } })
  end)
end

--- a sheet to write my note on an item (id: that item, else shift-click one in)
function UI.noteSheet(id)
  local text, note = id and LR.itemLink(id) or "", id and LR.noteFor(id) or ""
  UI.show()
  UI.openSheet("Item note", function(f, h)
    f:text("Which item?", { font = "GameFontNormal", color = K.GOLD, gap = 2 })
    local e = K.get(f.owner, "edit", f.parent)
    f:place(e, 22, 6, f.width - 12)
    e:SetText(text)
    K.takeLinks(e)
    e:SetScript("OnTextChanged", function(self, user)
      if not user then return end
      text = self:GetText()
      local was = id
      id = LR.idFrom(text)
      if id ~= was then note = id and LR.noteFor(id) or note h.redraw(true) end
    end)
    f:note(id and LR.coloredName(id) or "Shift-click the item into the box (from your bags, a chat link, anywhere).")
    f:gap(6)
    f:text("The note", { font = "GameFontNormal", color = K.GOLD, gap = 2 })
    local n = K.get(f.owner, "edit", f.parent)
    f:place(n, 22, 6, f.width - 12)
    n:SetMaxLetters(LR.Notes.MAX_LEN)
    n:SetText(note)
    n:SetScript("OnTextChanged", function(self, user) if user then note = self:GetText() end end)
    f:note("Short and plain: it goes in raid chat. Leave it empty to take the note off.")
    f:buttons({ { label = "Cancel", click = function() h.close() end },
      { label = "Save", disabled = not id, click = function() LR.setNote(id, note) h.close() UI.render() end } })
  end)
end

--- thatsmybis's download, pasted in: its wishlists replace the ones brought in before
function UI.wishSheet()
  local pasted = ""
  UI.show()
  UI.openSheet("Bring in thatsmybis wishlists", function(f, h)
    f:note("On thatsmybis.com, open your guild's Export page, pick the Gargul download, copy it and paste it here (Ctrl+V). It replaces the wishlists you brought in before.")
    local m = K.get(f.owner, "memo", f.parent)
    f:place(m, 140, 0)
    K.setEditMemo(m, f.width, 140, pasted, function(t) pasted = t end)
    f:gap(4)
    f:buttons({ { label = "Read it", click = function() h.redraw(true) end } }, "left")
    local lists, why
    if U.trim(pasted) ~= "" then
      local LibDeflate = LibStub and LibStub("LibDeflate", true)
      lists, why = LR.Prio.wishlists(pasted, LibDeflate and function(raw) return LibDeflate:DecompressZlib(raw) end)
      if lists then
        local items, places = LR.Prio.count(lists)
        f:note(("%s on wishlists, %s."):format(U.plural(items, "item"), U.plural(places, "place")), K.GOLD)
      else
        f:note(why, K.RED)
      end
    end
    f:buttons({ { label = "Cancel", click = function() h.close() end },
      { label = "Bring them in", disabled = not lists, click = function()
        LR.db.wish = LR.Prio.checkWish(lists)
        LR.changed("notes")
        h.close()
        UI.render()
        UI.toast(("Wishlists for %s brought in."):format(U.plural((LR.Prio.count(LR.db.wish)), "item")))
      end } })
  end)
end

--- all my notes as text: copy them out, or paste notes in (one item a line, "28525: Warrior > Rogue")
function UI.notesSheet()
  local pasted = ""
  UI.show()
  UI.openSheet("Item notes in and out", function(f, h)
    f:text("Copy out", { font = "GameFontNormal", color = K.GOLD, gap = 2 })
    local out = K.get(f.owner, "memo", f.parent)
    f:place(out, 110, 0)
    K.setMemo(out, f.width, 110, LR.Notes.text(LR.db.notes))
    f:gap(8)
    f:text("Bring in", { font = "GameFontNormal", color = K.GOLD, gap = 2 })
    f:note("Paste notes, one item a line: its number or link, then the note (\"28525: Warrior > Rogue\"). A note for an item that has one already replaces it.")
    local into = K.get(f.owner, "memo", f.parent)
    f:place(into, 110, 0)
    K.setEditMemo(into, f.width, 110, pasted, function(t) pasted = t end)
    out.edit:ClearFocus()
    f:gap(6)
    f:buttons({ { label = "Close", click = function() h.close() end },
      { label = "Bring them in", click = function()
        local notes, bad = LR.Notes.parse(pasted)
        local n = 0
        for id, note in pairs(notes) do LR.db.notes[id] = note n = n + 1 end
        LR.db.notes = LR.Notes.check(LR.db.notes)
        LR.changed("notes")
        UI.toast(("%s brought in.%s"):format(U.plural(n, "note"), bad > 0 and (" %s not understood."):format(U.plural(bad, "line")) or ""))
        pasted = ""
        h.redraw(true)
        UI.render()
      end } })
  end)
end

--- a sheet to add one of my own roll types: a name and its /roll number
function UI.addRollKind()
  local name, num, why = "", "", nil
  UI.openSheet("Add a roll type", function(f, h)
    f:text("What it's for", { font = "GameFontNormal", color = K.GOLD, gap = 2 })
    local e = K.get(f.owner, "edit", f.parent)
    f:place(e, 22, 6, f.width - 12)
    e:SetText(name)
    e:SetScript("OnTextChanged", function(self, user) if user then name = self:GetText() end end)
    f:note("A short name, like Transmog, Alt or Pvp.")
    f:gap(6)
    f:text("Its roll: /roll ...", { font = "GameFontNormal", color = K.GOLD, gap = 2 })
    local n = K.get(f.owner, "edit", f.parent)
    f:place(n, 22, 6, 80)
    n:SetText(num)
    n:SetScript("OnTextChanged", function(self, user) if user then num = self:GetText() end end)
    f:note("A number from 2 to 98 that no other kind uses.")
    if why then f:note(why, K.RED) end
    f:buttons({ { label = "Cancel", click = function() h.close() end },
      { label = "Add it", click = function()
        local list, no = R.addKind(LR.db.settings.rollKinds, name, num)
        if not list then why = no h.redraw(true) return end
        LR.db.settings.rollKinds = list
        h.close()
        UI.render()
      end } })
  end)
end

--- a sheet to make a Need / Greed rule: which items, then what to roll
function UI.addGroupRule()
  local what, act, linked = nil, nil, ""
  UI.openSheet("Add a Need / Greed rule", function(f, h)
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
    f:text("Roll", { font = "GameFontNormal", color = K.GOLD, gap = 2 })
    local acts = {}
    for _, a in ipairs(LR.GroupLoot.choices()) do acts[#acts + 1] = { label = a[2], on = act == a[1], click = function() act = a[1] h.redraw(true) end } end
    f:chips(acts)
    if what and act then f:note(("%s: %s."):format(LR.AutoLoot.whatText(what), LR.GroupLoot.actText(act)), K.GREEN) end
    f:buttons({ { label = "Cancel", click = function() h.close() end },
      { label = "Add the rule", disabled = not (what and act), click = function() LR.GroupLoot.add(what, act) h.close() UI.render() end } })
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
  { "/lr history", "past raids: what each gave out" },
  { "/lr max 800", "GDKP: bid for me up to 800g on the item being auctioned" },
  { "/lr guild", "the Guild tab (boosted roll points)" },
  { "/lr settings", "the Settings tab" },
  { "/lr roll [item]", "roll an item out" },
  { "/lr master", "bring back the loot master window" },
  { "/lr de [name]", "who disenchants (the leader)" },
  { "/lr test", "a pretend roll window" },
  { "/lr raid", "raid setup: paste who's coming, invite them, sort groups" },
  { "/lr held", "post the items you hold to roll out or trade, with the time left" },
  { "/lr batch", "auction several items at once (GDKP), or bring back the auction window" },
  { "/lr bags", "a bag check: ask the group how many of some items they carry" },
  { "/lr gear", "what everyone in the group wears, with their item level" },
  { "/lr fair", "who got what over your past raids, and how many raids they came to" },
  { "/lr say <text>", "in a practice raid: say something in its raid chat (a bid, or \"!lr ...\")" },
  { "/lr tour", "a quick tour of LootRuler" },
  { "/lr whatsnew", "what's new in this version" },
  { "/lr versions", "who in the group has LootRuler, and which version" },
  { "/lr minimap", "hide or show the minimap button" },
}
--- who in the group has LootRuler, and which version; asking everyone again, and telling those with an older one
local versionSheet
local VERSION_TEXT = { older = "|cffff8040%s (older)|r", newer = "|cff40c0ff%s (newer)|r", same = "|cff1eff00%s|r" }
function UI.versionSheet()
  UI.show()
  UI.openSheet("Who has LootRuler", function(f, h)
    versionSheet = h
    local list = LR.versionList()
    if #list == 0 then
      f:note(("You're not in a group. You have LootRuler %s."):format(LR.VERSION))
    else
      local have, older = 0, 0
      for _, x in ipairs(list) do
        if x.version then have = have + 1 end
        if x.state == "older" then older = older + 1 end
      end
      f:note(("%d of %d in the group have LootRuler. You have %s."):format(have, #list, LR.VERSION), K.GOLD)
      if have < #list then f:note("Without it, players still reserve by whispering \"!reserve [item]\" and roll with /roll.") end
      local rows = {}
      for _, x in ipairs(list) do
        rows[#rows + 1] = { U.classText(U.short(x.name), x.class), x.version and VERSION_TEXT[x.state]:format(x.version) or "|cff9d9d9dno LootRuler|r" }
      end
      f:kv(rows)
      f:gap(6)
      f:note("Someone who just joined, or whose addon hasn't said anything yet, shows as having none until you ask again.")
      f:buttons({
        { label = "Ask again", disabled = LR.groupChannel() == nil, click = function()
          LR.query()
          UI.toast("Asked everyone. Answers come in over a few seconds.")
        end },
        { label = "Tell those with an older one", disabled = older == 0, click = function()
          local n = LR.tellOutdated()
          UI.toast(n > 0 and ("Whispered %s."):format(U.plural(n, "player")) or "They've been told already.")
        end },
      }, "left")
    end
    f:buttons({ { label = "Close", click = function() h.close() end } })
  end, { onClose = function() versionSheet = nil end })
end
LR.onChange(function(what)
  if (what == "versions" or what == "roster") and versionSheet then versionSheet.redraw(true) end
end)

function UI.help()
  LR.print("commands:")
  for _, c in ipairs(UI.COMMANDS) do print(("  |cffffd100%s|r  %s"):format(c[1], c[2])) end
end
