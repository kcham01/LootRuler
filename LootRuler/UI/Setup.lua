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
    f:note("The reserves are added to this session; items that don't drop in " .. LR.raid(s.raid).name .. " are skipped, and so are reserves past the limit.")
    local e = K.get(f.owner, "edit", f.parent)
    f:place(e, 22, 6, f.width - 12)
    e:SetText(text)
    e:SetScript("OnTextChanged", function(self) text = self:GetText() end)
    f:gap(10)
    f:buttons({ { label = "Cancel", click = function() h.close() end }, { label = "Import", click = function()
      local sum, err = LR.Gargul.importInto(s, text)
      if not sum then UI.toast(err) return end
      h.close()
      local msg = ("Added %s for %s"):format(U.plural(sum.items, "reserve"), U.plural(sum.players, "player"))
      if sum.hard > 0 then msg = msg .. (", %d hard reserved"):format(sum.hard) end
      if sum.skipped + sum.over > 0 then msg = msg .. ("; %d skipped"):format(sum.skipped + sum.over) end
      UI.toast(msg .. ".")
      LR.print(msg .. ".")
    end } })
  end)
end

local function manage(f, s)
  local raid = LR.raid(s.raid)
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

  f:panel("More", function(p)
    p:buttons({
      { label = "Import from softres.it", click = function() importSheet(s) end },
      { label = "End session", click = function()
        UI.confirm("End the session", "Everyone's reserves for " .. raid.name .. " are cleared, for you and for every raider's addon. (Gargul keeps what you sent it.)", "End it", function()
          LR.endSession(s)
        end)
      end },
    }, "left")
    p:chips({
      { label = (LR.db.settings.hideWhispers and "[x] " or "[  ] ") .. "Hide !lr whispers in my chat", on = LR.db.settings.hideWhispers, click = function()
        LR.db.settings.hideWhispers = not LR.db.settings.hideWhispers UI.render()
      end, tip = "Raiders' \"!lr\" whispers and the addon's answers don't show in your chat while you have a session open." },
    })
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
    stepper(p, "Reserves each", d.sr, S.MIN_SR, S.MAX_SR, function(v) d.sr = v UI.render() end)
    p:chips({
      { label = (d.dupes and "[x] " or "[  ] ") .. "Same item more than once", on = d.dupes, click = function() d.dupes = not d.dupes UI.render() end,
        tip = "Lets a player put more than one of their reserves on the same item (softres.it's \"x2\")." },
      { label = (d.guild and "[x] " or "[  ] ") .. "Share with my guild", on = d.guild, click = function()
        if not IsInGuild() then UI.toast("You're not in a guild.") return end
        d.guild = not d.guild UI.render()
      end, tip = "Guild members with LootRuler can see the session and reserve before the group is made." },
    })
    if IsInGroup() and not UnitIsGroupLeader("player") then
      p:note("You're not the group leader. That's fine if you're running loot, but make sure only one of you opens reserves.", K.GOLD)
    end
    p:note("Raiders reserve in LootRuler, or whisper you \"!lr <item link>\" if they don't have it. You reserve on the Reserve tab like everyone else; hard reserves come next.")
    p:buttons({ { label = "Open reserves", click = function()
      local s = LR.startSession(d.raid, d.sr, d.dupes, d.guild)
      UI.toast(("%s reserves are open."):format(LR.raid(s.raid).name))
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
      K.setItem(b, p.width, LR.raidIcon(x.raid), LR.raid(x.raid).name,
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
      f:panel("Session by " .. U.short(s.leader), function(p)
        p:kv({
          { "Raid", LR.raid(s.raid).name },
          { "Reserves each", tostring(s.sr) },
          { "Same item more than once", s.dupes and "yes" or "no" },
          { "Hard reserves", tostring(#U.keys(s.hr)) },
          { "Locked", s.locked and "yes" or "no" },
        })
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
