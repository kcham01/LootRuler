-- A player's first look and later ones: a short tour the first time the window opens (/lr tour any time), a note on
-- what's new after an update (/lr whatsnew, and Settings > About), and settings saved under a name (profiles), to
-- switch between (say, one for running loot and one for raiding).
local _, LR = ...
local U, K = LR.U, LR.K
local UI = LR.UI

UI.TOUR = {
  { "Welcome to LootRuler", "It runs raid loot inside the game: soft reserves, rolling items out, the raid's loot list and trades. Only whoever runs the loot needs it: everyone else can whisper and /roll." },
  { "Reserving", "The Reserve tab: pick your items once the raid leader has opened soft reserves. Players without LootRuler type !lr and an item link in raid chat." },
  { "Running the raid", "The Session tab: open soft reserves (the raid, and how many each), bring in softres.it, set up the raid and hand it over. The Reserves tab shows who reserved what." },
  { "Loot", "As master looter, click an item in the list beside the loot window to roll it out. Everyone gets a roll window, and you click Give. The Loot tab lists every drop and what's still to trade." },
  { "Make it yours", "The Settings tab has every option, from roll windows to loot rules. /lr help lists the commands, and /lr tour shows this again." },
}

--- the tour, from a page
function UI.tour(page)
  page = math.max(1, math.min(#UI.TOUR, page or 1))
  local p = UI.TOUR[page]
  LR.db.ui.toured = true
  UI.show()
  UI.openSheet(p[1], function(f, h)
    f:text(p[2])
    f:gap(6)
    f:note(("%d of %d"):format(page, #UI.TOUR))
    local list = {}
    if page > 1 then list[#list + 1] = { label = "Back", click = function() h.close() UI.tour(page - 1) end } end
    if page < #UI.TOUR then list[#list + 1] = { label = "Next", click = function() h.close() UI.tour(page + 1) end } end
    list[#list + 1] = { label = page < #UI.TOUR and "Skip" or "Done", click = function() h.close() end }
    f:buttons(list)
  end)
end

--- the first time the window opens for a new player: the tour
function UI.firstLook()
  if LR.db and LR.db.ui.toured == false then UI.tour(1) end
end

---------------------------------------------------------------------- what's new
-- what each version brought, newest first (for players updating; a new player gets the tour instead)
UI.WHATS_NEW = {
  { "1.0.0-beta", {
    "Roll windows list everyone's rolls, show your item notes and the guild's wishlists, and what you wear in that slot.",
    "Roll types of your own, like Transmog (/roll 98).",
    "Trade timers: a bar for each item you hold, with the time left to trade it.",
    "Who has LootRuler (/lr versions), and raid setup: paste who's coming, invite and sort groups (/lr raid).",
    "Exports your own way, and several past raids at once.",
    "Need / Greed rules for group loot, and more loot rules (in turn, quality ranges, leave it, pick up the gold).",
    "softres.it spreadsheets, and its link posted in raid chat.",
    "GDKP: change or take back a sale, starting bids in and out, payouts filled in at the mailbox.",
    "Asked when you become master looter, and to record loot given without LootRuler.",
    "Settings profiles, and this note.",
  } },
}

--- what's new, in a sheet
function UI.whatsNew()
  UI.show()
  UI.openSheet("What's new", function(f, h)
    for i, v in ipairs(UI.WHATS_NEW) do
      if i > 3 then break end
      f:text("LootRuler " .. v[1], { font = "GameFontNormal", color = K.GOLD, gap = 2 })
      for _, line in ipairs(v[2]) do f:note("- " .. line) end
      f:gap(6)
    end
    f:buttons({ { label = "Close", click = function() h.close() end } })
  end)
end

-- after an update: one line in chat, once (a new player gets the tour instead)
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
  C_Timer.After(6, function()
    local ui = LR.db and LR.db.ui
    if not ui then return end
    if ui.seenVersion ~= LR.VERSION and ui.toured ~= false and UI.WHATS_NEW[1][1] == LR.VERSION then
      LR.print(("updated to %s. /lr whatsnew (or Settings, About) says what's new."):format(LR.VERSION))
    end
    ui.seenVersion = LR.VERSION
  end)
end)

---------------------------------------------------------------------- profiles
--- saves my settings under a name (replacing one of that name)
function LR.saveProfile(name)
  name = U.trim(tostring(name or "")):gsub("|", ""):sub(1, 24)
  if name == "" then return false end
  LR.db.profiles[name] = U.copy(LR.db.settings)
  return true
end
--- uses a saved profile's settings
function LR.useProfile(name)
  local p = LR.db.profiles[name]
  if not p then return false end
  LR.db.settings = LR.checkSettings(U.copy(p))
  LR.db.ui.profile = name
  if UI.rollWindows then UI.rollWindows() end
  LR.changed("settings")
  return true
end
function LR.deleteProfile(name) LR.db.profiles[name] = nil if LR.db.ui.profile == name then LR.db.ui.profile = nil end end

--- a sheet to name a profile
function UI.saveProfileSheet()
  local name = LR.db.ui.profile or ""
  UI.openSheet("Save these settings", function(f, h)
    f:note("A name for them, like \"Running loot\" or \"Raiding\". Saving under a name that's there already replaces it.")
    local e = K.get(f.owner, "edit", f.parent)
    f:place(e, 22, 6, f.width - 12)
    e:SetMaxLetters(24)
    e:SetText(name)
    e:SetScript("OnTextChanged", function(self, user) if user then name = self:GetText() end end)
    f:gap(8)
    f:buttons({ { label = "Cancel", click = function() h.close() end },
      { label = "Save", click = function()
        if not LR.saveProfile(name) then UI.toast("Give it a name.") return end
        LR.db.ui.profile = U.trim(name)
        h.close()
        UI.render()
      end } })
  end)
end

--- the Settings tab's panel
--- the Profiles section's contents (Settings tab)
function UI.profilesFill(p)
  p:note("Save all these settings under a name, and switch between them (they're shared by every character on this account).")
  local names = {}
  for name in pairs(LR.db.profiles) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local b = K.get(p.owner, "item", p.parent)
    K.setItem(b, p.width, "Interface\\Icons\\INV_Misc_Note_01", name, LR.db.ui.profile == name and "In use" or "", "",
      { text = "Use", width = 40, tip = "Use these settings", click = function() LR.useProfile(name) UI.toast(("Using \"%s\"."):format(name)) UI.render() end })
    b:SetScript("OnClick", function()
      UI.confirm("Delete the profile", ("\"%s\" is deleted. The settings you're using stay as they are."):format(name), "Delete", function() LR.deleteProfile(name) UI.render() end)
    end)
    p:place(b, 36)
    p:gap(2)
  end
  p:buttons({ { label = "Save these settings as...", click = function() UI.saveProfileSheet() end } }, "left")
end
