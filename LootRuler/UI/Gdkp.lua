-- GDKP on the Session tab: the auction settings, the pot, and the payouts sheet (who owes whom). The rules
-- and the money are in Core/Gdkp.lua; Core/Pot.lua tells the raid.
local _, LR = ...
local U, K = LR.U, LR.K
local UI = LR.UI
local G = LR.Gdkp

local RED, GREEN = { 1, 0.35, 0.29 }, { 0.12, 1, 0 }

--- a sheet asking for an amount of gold; done(gold)
local function goldSheet(title, note, current, done)
  local text = current and tostring(current) or ""
  UI.openSheet(title, function(f, h)
    if note then f:note(note) end
    local e = K.get(f.owner, "edit", f.parent)
    f:place(e, 22, 6, 100)
    e:SetMaxLetters(8)
    e:SetText(text)
    e:SetScript("OnTextChanged", function(self) text = self:GetText() end)
    f:gap(8)
    f:buttons({
      { label = "Cancel", click = function() h.close() end },
      { label = "Save", click = function()
        local g = tonumber((U.trim(text):gsub("[gG]$", "")))
        if not g or g < 0 then UI.toast("That's not an amount of gold.") return end
        h.close()
        done(math.floor(g))
      end },
    })
  end)
end
UI.goldSheet = goldSheet

--- one player's line on the payouts sheet: what they bought, their share, and who gives whom what
local function payoutText(s, name, row)
  local parts = {}
  if row.role then parts[#parts + 1] = row.role .. (row.roleCut > 0 and (" cut " .. G.gold(row.roleCut)) or "") end
  if (row.ruleCut or 0) > 0 then parts[#parts + 1] = table.concat(row.ruleNames or {}, ", ") .. " " .. G.gold(row.ruleCut) end
  if row.spent > 0 then parts[#parts + 1] = "bought " .. G.gold(row.spent) end
  parts[#parts + 1] = row.out and "left out of the split" or ((row.fixed and "payout set by hand " or "share ") .. G.gold(row.gets))
  if row.paid ~= 0 then parts[#parts + 1] = (row.paid > 0 and "paid " or "had ") .. G.gold(math.abs(row.paid)) end
  local badge
  if U.samePlayer(name, s.leader) then badge = "|cffffd100holds the pot|r"
  elseif math.abs(row.owed) < 0.01 then badge = "|cff1eff00settled|r"
  elseif row.owed > 0 then badge = "|cff1eff00gets " .. G.gold(row.owed) .. "|r"
  else badge = "|cffff5a4aowes " .. G.gold(-row.owed) .. "|r" end
  return table.concat(parts, ", "), badge
end

--- what can be done about one player: a bonus, leave them out, or mark them settled
local function playerSheet(s, name)
  UI.openSheet(U.short(name), function(f, h)
    local split = G.split(s)
    local row = split.rows[name] or { spent = 0, gets = 0, paid = 0, owed = 0, bonus = 0 }
    local sub = payoutText(s, name, row)
    f:text(U.classText(U.short(name), LR.classOf(name)) .. ": " .. sub)
    f:gap(6)
    local list = {
      { label = row.bonus > 0 and "Change the bonus" or "Give a bonus", click = function()
        h.close()
        goldSheet("Bonus for " .. U.short(name), "Gold out of the pot on top of their share (for tanks, healers, whoever you said).", row.bonus, function(g) LR.gdkpBonus(s, name, g) end)
      end },
      { label = s.gk.out[name] and "Put back in the split" or "Leave out of the split", click = function() h.close() LR.gdkpOut(s, name, not s.gk.out[name]) end },
      { label = row.fixed and "Change their payout" or "Set their payout", click = function()
        h.close()
        goldSheet("Payout for " .. U.short(name), "All they get from the pot, instead of a share (no bonus or cut on top). The others split what's left.",
          row.fixed and row.gets or nil, function(g) LR.gdkpFixed(s, name, g) end)
      end },
    }
    if row.fixed then list[#list + 1] = { label = "Back to their share", click = function() h.close() LR.gdkpFixed(s, name, nil) end } end
    if math.abs(row.owed) >= 0.01 and not U.samePlayer(name, s.leader) then
      list[#list + 1] = { label = "Mark as settled", click = function()
        h.close()
        -- (gold handed over some other way: the mail, or someone else's trade)
        LR.gdkpPaid(s, name, -row.owed, "hand")
      end }
    end
    f:buttons(list, "left")
    f:note("Gold that changes hands in a trade with you is counted on its own. \"Mark as settled\" is for gold sent another way (the mail, say).")
  end)
end

--- the payouts: the pot, the split, and everyone's line
function UI.payoutSheet(s)
  UI.openSheet("Payouts", function(f, h)
    local split = G.split(s)
    f:kv({
      { "Pot", G.gold(split.pot) .. "  (" .. U.plural(#G.sales(s), "item") .. ")" },
      { "Your cut (" .. s.gk.cut .. "%)", G.gold(split.cut) },
      split.bonuses > 0 and { "Bonuses", G.gold(split.bonuses) } or false,
      split.added ~= 0 and { split.added > 0 and "Added by hand" or "Taken out by hand", G.gold(math.abs(split.added)) } or false,
      split.roles > 0 and { "Tank and healer cuts", G.gold(split.roles) } or false,
    })
    local rows = {}
    for i, r in ipairs(s.gk.rules or {}) do
      if (split.ruleTotals[i] or 0) > 0 then rows[#rows + 1] = { r.n, G.gold(split.ruleTotals[i]) } end
    end
    if split.fixed > 0 then rows[#rows + 1] = { "Payouts set by hand", G.gold(split.fixed) } end
    rows[#rows + 1] = { "Split " .. split.sharers .. " ways", G.gold(split.share) .. " each" }
    f:kv(rows)
    f:gap(6)
    local names = {}
    for name in pairs(split.rows) do names[#names + 1] = name end
    table.sort(names, function(a, b)
      local ra, rb = split.rows[a], split.rows[b]
      if (ra.owed < 0) ~= (rb.owed < 0) then return ra.owed < 0 end
      return a < b
    end)
    for _, name in ipairs(names) do
      local row = split.rows[name]
      local sub, badge = payoutText(s, name, row)
      local b = K.get(f.owner, "item", f.parent)
      K.setItem(b, f.width, LR.LOGO, U.classText(U.short(name), LR.classOf(name)) .. (row.bonus > 0 and ("  |cffffd100+" .. G.gold(row.bonus) .. " bonus|r") or ""), sub, badge,
        { text = "...", width = 30, tip = "Bonus, leave out, settled", click = function() playerSheet(s, name) end })
      f:place(b, 36)
      f:gap(2)
    end
    if #names == 0 then f:note("Nobody yet: everyone in the group while you lead goes in the split.") end
    f:gap(6)
    f:buttons({
      { label = "Tell the raid", disabled = LR.groupChannel() == nil, click = function() if LR.Pot.post(s) then UI.toast("Posted in raid chat.") end end },
      { label = "Whisper everyone", disabled = not IsInGroup(), click = function() UI.toast(("Whispered %s their payout."):format(U.plural(LR.Pot.whisperAll(s), "player"))) end },
    }, "left")
    f:buttons({
      { label = "Copy out", click = function() UI.payoutsOutSheet(s) end },
      { label = "Bring in payouts", click = function() UI.payoutsInSheet(s) end },
      split.fixed > 0 and { label = "Back to an even split", click = function() LR.gdkpFixedAll(s, {}) h.redraw(true) end } or nil,
    }, "left")
    f:note("Addons can't put gold in a trade: open a trade with each player and LootRuler says what to give or take. Gold that changes hands is counted.")
    -- by mail: LootRuler fills in the Send Mail tab, the organiser presses Send
    local queue = LR.Pot.toMail(s)
    if #queue > 0 then
      f:gap(6)
      f:buttons({ { label = ("Mail %s %s"):format(U.short(queue[1][1]), G.gold(queue[1][2])), disabled = not LR.Pot.mailOpen(), click = function()
        local ok, why = LR.Pot.fillMail(s, queue[1][1], queue[1][2])
        UI.toast(ok and "It's filled in: check it and press Send. It counts as paid once it's sent." or why)
      end } }, "left")
      f:note(LR.Pot.mailOpen() and ("%s still to mail. Each click fills in the next one."):format(U.plural(#queue, "payout"))
        or "Or by mail: at a mailbox, open the Send Mail tab and LootRuler fills in each payout for you to send.")
    end
  end, { full = true })
end

--- the payouts as text: for a spreadsheet, or "Name,Gold" lines that bring back in as payouts set by hand
local payoutFormat = "sheet"
function UI.payoutsOutSheet(s)
  UI.openSheet("Payouts, to copy", function(f, h)
    f:chips({
      { label = "Spreadsheet", on = payoutFormat == "sheet", click = function() payoutFormat = "sheet" h.redraw() end },
      { label = "Name,Gold", on = payoutFormat == "cuts", click = function() payoutFormat = "cuts" h.redraw() end },
    })
    f:note(payoutFormat == "sheet" and "Name, what they bought, their payout, what they've paid (- what they've had) and what's still owed (- they owe you)."
      or "Each player's payout. Change it in a spreadsheet and bring it back in to pay those amounts instead.")
    local m = K.get(f.owner, "memo", f.parent)
    f:place(m, 200, 0)
    K.setMemo(m, f.width, 200, G.payoutsText(s, payoutFormat))
    f:gap(4)
    f:note("It's all selected: press Ctrl+C to copy it.")
  end)
end

--- payouts set by hand, pasted in as "Name,Gold" lines
function UI.payoutsInSheet(s)
  local pasted = ""
  UI.openSheet("Bring in payouts", function(f, h)
    f:note("One player a line, a name and gold (\"Ann,350\"), from a spreadsheet or \"Copy out\". Each player listed gets that much instead of a share; everyone else splits what's left. It replaces any payouts brought in before.")
    local into = K.get(f.owner, "memo", f.parent)
    f:place(into, 140, 0)
    K.setEditMemo(into, f.width, 140, pasted, function(t) pasted = t end)
    f:gap(6)
    f:buttons({ { label = "Cancel", click = function() h.close() end },
      { label = "Bring them in", click = function()
        local list, why = LR.Prio.parseCounts(pasted, G.MAX_GOLD)
        if not list then UI.toast(why) return end
        local total = 0
        for _, x in ipairs(list) do total = total + x.n end
        LR.gdkpFixedAll(s, list)
        h.close()
        UI.toast(("%s set by hand, %s in all."):format(U.plural(#list, "payout"), G.gold(total)))
      end } })
  end)
end

--- gold put in the pot by hand, or taken out: what's there, and a new one
function UI.goldInOutSheet(s)
  local amount, what = "", ""
  UI.openSheet("Gold in or out of the pot", function(f, h)
    f:note("Gold that wasn't from an auction: put in (vendor money, a donation), or taken out (repairs). The pot, the split and everyone's payout change with it.")
    for i, a in ipairs(s.gk.adds or {}) do
      local b = K.get(f.owner, "item", f.parent)
      K.setItem(b, f.width, LR.LOGO, (a.g > 0 and "|cff1eff00+" or "|cffff5a4a-") .. G.gold(math.abs(a.g)) .. "|r", a.n ~= "" and a.n or "(no note)",
        a.at and date("%H:%M", a.at) or "", { text = "x", tip = "Take this back", click = function() LR.gdkpRemoveAdd(s, i) h.redraw(true) end })
      f:place(b, 36)
      f:gap(2)
    end
    f:gap(4)
    f:text("Gold", { font = "GameFontNormal", color = K.GOLD, gap = 2 })
    local e = K.get(f.owner, "edit", f.parent)
    f:place(e, 22, 6, 100)
    e:SetMaxLetters(8)
    e:SetText(amount)
    e:SetScript("OnTextChanged", function(self) amount = self:GetText() end)
    f:text("What for", { font = "GameFontNormal", color = K.GOLD, gap = 2 })
    local n = K.get(f.owner, "edit", f.parent)
    f:place(n, 22, 6, 260)
    n:SetMaxLetters(G.MAX_NOTE)
    n:SetText(what)
    n:SetScript("OnTextChanged", function(self) what = self:GetText() end)
    f:gap(8)
    local function go(sign)
      local g = tonumber((U.trim(amount):gsub("[gG]$", "")))
      if not g or g <= 0 then UI.toast("That's not an amount of gold.") return end
      if LR.gdkpAddGold(s, sign * math.floor(g), what) then amount, what = "", "" h.redraw(true) end
    end
    f:buttons({
      { label = "Put in the pot", click = function() go(1) end },
      { label = "Take out of the pot", click = function() go(-1) end },
    }, "left")
  end, { full = true })
end

--- the ledger: every sale, gold put in or out, and payment, with its time
function UI.ledgerSheet(s)
  UI.openSheet("Ledger", function(f, h)
    local list = G.ledger(s)
    if #list == 0 then f:note("Nothing yet: sales, gold put in or out, and payments show here as they happen.") end
    for _, e in ipairs(list) do
      local when = e.at > 0 and ("|cff9d9d9d%s|r  "):format(date("%H:%M", e.at)) or ""
      local who = e.p and U.classText(U.short(e.p), LR.classOf(e.p)) or ""
      local text
      if e.kind == "sale" then text = ("%s bought %s for %s"):format(who, LR.coloredName(e.i), G.gold(e.g))
      elseif e.kind == "add" then text = (e.g > 0 and "Put in the pot: %s%s" or "Taken out of the pot: %s%s"):format(G.gold(math.abs(e.g)), e.n ~= "" and (" (" .. e.n .. ")") or "")
      elseif e.kind == "trade" then text = e.g > 0 and ("%s gave you %s in a trade"):format(who, G.gold(e.g)) or ("You gave %s %s in a trade"):format(who, G.gold(-e.g))
      elseif e.kind == "mail" then text = ("You mailed %s %s"):format(who, G.gold(math.abs(e.g)))
      else text = ("%s marked as settled (%s %s)"):format(who, G.gold(math.abs(e.g)), e.g > 0 and "paid" or "had") end
      f:text(when .. text, { font = "GameFontHighlightSmall", gap = 3 })
    end
    f:gap(6)
    f:note(("Pot %s. Payments counted from trades, the mail and \"Mark as settled\"."):format(G.gold(G.pot(s))))
  end, { full = true })
end

--- everything sold: change a price, or take a sale back
function UI.salesSheet(s)
  UI.openSheet("Sales", function(f, h)
    local any = false
    for i, w in ipairs(s.won or {}) do
      if w.k == "BID" then
        any = true
        local b = K.get(f.owner, "item", f.parent)
        K.setItem(b, f.width, LR.itemIcon(w.i), LR.coloredName(w.i), ("%s for %s"):format(U.short(w.p), G.gold(tonumber(w.r) or 0)), "",
          { text = "Price", width = 50, tip = "Change the price", click = function()
            goldSheet("Price of " .. LR.itemName(w.i), "What " .. U.short(w.p) .. " pays for it. The pot and the split change with it.", tonumber(w.r), function(g)
              LR.gdkpSalePrice(s, i, g)
              h.redraw(true)
            end)
          end })
        b:SetScript("OnClick", function()
          UI.confirm("Take the sale back", ("%s to %s for %s comes off the list, and out of the pot."):format(LR.itemName(w.i), U.short(w.p), G.gold(tonumber(w.r) or 0)),
            "Take it back", function() LR.unaward(s, i) h.redraw(true) end)
        end)
        f:place(b, 36)
        f:gap(2)
      end
    end
    if not any then f:note("Nothing sold yet.") else f:note("Click a sale to take it back (a mistake): it comes out of the pot.") end
  end, { full = true })
end

--- the starting bids as text: copy them out, or paste a list in ("28525: 500", one item a line)
function UI.pricesSheet(s)
  local pasted = ""
  UI.openSheet("Starting bids in and out", function(f, h)
    f:text("Copy out", { font = "GameFontNormal", color = K.GOLD, gap = 2 })
    local out = K.get(f.owner, "memo", f.parent)
    f:place(out, 90, 0)
    K.setMemo(out, f.width, 90, G.pricesText(s))
    out.edit:ClearFocus()
    f:gap(8)
    f:text("Bring in", { font = "GameFontNormal", color = K.GOLD, gap = 2 })
    f:note("One item a line: its number or link, then where bids start (\"28525: 500\"). An item that has a starting bid already gets the new one.")
    local into = K.get(f.owner, "memo", f.parent)
    f:place(into, 90, 0)
    K.setEditMemo(into, f.width, 90, pasted, function(t) pasted = t end)
    f:gap(6)
    f:buttons({ { label = "Close", click = function() h.close() end },
      { label = "Bring them in", click = function()
        local prices, bad = G.parsePrices(pasted)
        local n = 0
        for _ in pairs(prices) do n = n + 1 end
        LR.gdkpPrices(s, prices)
        UI.toast(("%s brought in.%s"):format(U.plural(n, "starting bid"), bad > 0 and (" %s not understood."):format(U.plural(bad, "line")) or ""))
        pasted = ""
        h.redraw(true)
      end } })
  end)
end

--- the people a rule can name: the group, and everyone who's been in the split
local function people(s)
  local out, seen = {}, {}
  for _, m in ipairs(LR.roster()) do out[#out + 1] = { name = U.full(m.name), class = m.class } seen[U.full(m.name)] = true end
  for name in pairs(s.gk.seen or {}) do if not seen[name] then out[#out + 1] = { name = name } seen[name] = true end end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

--- one of the organiser's own pot rules: its name, how much, and who gets it
local function ruleSheet(s, index)
  local typed
  UI.openSheet("A pot rule", function(f, h)
    local r = s.gk.rules and s.gk.rules[index]
    if not r then h.close() return end
    f:text("Name", { font = "GameFontNormal", color = K.GOLD, gap = 2 })
    local e = K.get(f.owner, "edit", f.parent)
    f:place(e, 22, 6, 200)
    e:SetMaxLetters(G.MAX_RULE_NAME)
    e:SetText(typed or r.n)
    e:SetScript("OnTextChanged", function(self, user) if user then typed = self:GetText() end end)
    e:SetScript("OnEnterPressed", function(self) LR.gdkpEditRule(s, index, { n = self:GetText() }) typed = nil self:ClearFocus() h.redraw(true) end)
    f:note("Press Enter to keep a new name.")
    local pcts = { { plain = true, label = "Percent of the pot:" } }
    for _, v in ipairs({ 0, 1, 2, 3, 5, 10 }) do
      pcts[#pcts + 1] = { label = v .. "%", on = (r.pct or 0) == v, click = function() LR.gdkpEditRule(s, index, { pct = v }) h.redraw(true) end }
    end
    f:chips(pcts, { gap = 2 })
    f:buttons({ { label = r.g and ("Gold: " .. G.gold(r.g)) or "Gold: none", click = function()
      goldSheet("Gold for " .. r.n, "Gold out of the pot for each player in this rule (0: none).", r.g or 0, function(g) LR.gdkpEditRule(s, index, { g = g }) end)
    end } }, "left")
    f:gap(4)
    f:text("Who gets it", { font = "GameFontNormal", color = K.GOLD, gap = 2 })
    local list = people(s)
    if #list == 0 then f:note("Nobody in the group yet.") end
    for _, m in ipairs(list) do
      local on = U.indexOf(r.to, m.name) ~= nil
      f:chips({ { tick = true, label = U.classText(U.short(m.name), m.class or LR.classOf(m.name)), on = on, width = 200,
        click = function() LR.gdkpRuleTo(s, index, m.name, not on) h.redraw(true) end } }, { gap = 2 })
    end
    f:gap(6)
    f:buttons({
      { label = "Take this rule away", click = function()
        UI.confirm("Take the rule away", ("%s comes out of the split."):format(r.n), "Take it away", function() LR.gdkpRemoveRule(s, index) h.close() end)
      end },
      { label = "Done", click = function() if typed then LR.gdkpEditRule(s, index, { n = typed }) end h.close() end },
    }, "left")
  end, { full = true })
end

--- the organiser's own pot rules: each with who gets it and how much
function UI.potRulesSheet(s)
  UI.openSheet("Your pot rules", function(f, h)
    f:note("Cuts of your own, paid out of the pot before it's split: a percent of the pot, gold, or both, for each player you pick (\"Raid leader: 5%\", \"Pumper: 500g\"). They come after your cut, bonuses and tank and healer cuts, and are made smaller if they'd ever add up to more than is left.")
    local split = G.split(s)
    for i, r in ipairs(s.gk.rules or {}) do
      local b = K.get(f.owner, "item", f.parent)
      local who = #r.to > 0 and table.concat(U.map(r.to, U.short), ", ") or "nobody yet"
      K.setItem(b, f.width, LR.LOGO, r.n, G.ruleText(r) .. ": " .. who, (split.ruleTotals[i] or 0) > 0 and G.gold(split.ruleTotals[i]) or "",
        { text = "Edit", width = 40, click = function() ruleSheet(s, i) end })
      b:SetScript("OnClick", function() ruleSheet(s, i) end)
      f:place(b, 36)
      f:gap(2)
    end
    if not s.gk.rules or #s.gk.rules == 0 then f:note("None yet.") end
    f:gap(6)
    f:buttons({ { label = "Add a rule", disabled = s.gk.rules ~= nil and #s.gk.rules >= G.MAX_RULES, click = function()
      if LR.gdkpAddRule(s) then ruleSheet(s, #s.gk.rules) end
    end } }, "left")
  end, { full = true })
end

--- who tanks and who heals (for their cuts): each player, and a choice
function UI.rolesSheet(s)
  UI.openSheet("Tanks and healers", function(f, h)
    f:note("Pick who tanks and who heals: each gets the cut for their role, out of the pot, on top of their share.")
    local people = {}
    local seen = {}
    for _, m in ipairs(LR.roster()) do people[#people + 1] = { name = U.full(m.name), class = m.class } seen[U.full(m.name)] = true end
    for name in pairs(s.gk.seen or {}) do if not seen[name] then people[#people + 1] = { name = name } seen[name] = true end end
    table.sort(people, function(a, b) return a.name < b.name end)
    if #people == 0 then f:note("Nobody in the group yet.") end
    for _, m in ipairs(people) do
      local role = s.gk.role and s.gk.role[m.name]
      local chips = { { plain = true, width = 150, label = U.classText(U.short(m.name), m.class or LR.classOf(m.name)) } }
      for _, r in ipairs(G.ROLES) do
        chips[#chips + 1] = { label = r[3]:gsub("^%l", string.upper), width = 64, on = role == r[1], click = function() LR.gdkpRole(s, m.name, role ~= r[1] and r[1] or nil) h.redraw(true) end }
      end
      f:chips(chips, { gap = 2 })
    end
  end, { full = true })
end

--- the GDKP panel on the Session tab
function UI.gdkpPanel(f, s)
  local leader = LR.isLeader(s)
  f:panel("GDKP auctions", function(p)
    local gk = s.gk
    local split = G.split(s)
    if leader then
      p:note("Every item is auctioned: raiders bid by typing an amount in raid chat (or with their roll window). The highest bid when time is up buys it, and the gold goes in the pot.")
      local function chips(label, key, values, fmt)
        local list = { { plain = true, label = label } }
        for _, v in ipairs(values) do
          list[#list + 1] = { label = fmt(v), on = gk[key] == v, click = function() LR.gdkpOption(s, key, v) end }
        end
        p:chips(list, { gap = 2 })
      end
      chips("Bids start at:", "min", { 50, 100, 250, 500, 1000 }, G.gold)
      chips("Raise by at least:", "inc", { 10, 25, 50, 100 }, G.gold)
      chips("Your cut:", "cut", { 0, 5, 10, 15, 20 }, function(v) return v .. "%" end)
      for _, r in ipairs(G.ROLES) do
        local list = { { plain = true, label = r[2] .. " each get:" } }
        for _, v in ipairs({ 0, 1, 2, 3, 5 }) do
          list[#list + 1] = { label = v .. "%", on = ((gk.rp and gk.rp[r[1]]) or 0) == v, click = function() LR.gdkpRoleCut(s, r[1], v) end }
        end
        p:chips(list, { gap = 2 })
      end
      p:chips({ { tick = true, label = "Bids start with \"bid\"", on = gk.strict, click = function() LR.gdkpStrict(s, not gk.strict) end,
        tip = "Only \"bid 150\" counts, not just \"150\": someone saying \"500\" in raid chat doesn't bid by accident." } }, { gap = 2 })
      p:gap(4)
    end
    p:kv({
      { "Pot", G.gold(split.pot) .. "  (" .. U.plural(#G.sales(s), "item") .. " sold)" },
      { "Split " .. #split.players .. " ways", G.gold(split.share) .. " each, after a " .. gk.cut .. "% cut" },
    })
    local mine = split.rows[U.me()]
    if not leader and mine then
      p:gap(2)
      p:text(LR.Pot.line(s, U.me()), { font = "GameFontHighlightSmall", color = K.GOLD })
    end
    -- items that start higher than the rest
    local priced = {}
    for id in pairs(gk.prices) do priced[#priced + 1] = id end
    table.sort(priced)
    for _, id in ipairs(priced) do
      local b = K.get(p.owner, "item", p.parent)
      K.setItem(b, p.width, LR.itemIcon(id), LR.coloredName(id), "Bids start at " .. G.gold(gk.prices[id]), "",
        leader and { text = "x", tip = "Back to the usual start", click = function() LR.gdkpPrice(s, id, nil) end } or nil)
      p:place(b, 36)
      p:gap(2)
    end
    if leader then
      p:gap(4)
      p:buttons({
        { label = "Payouts", click = function() UI.payoutSheet(s) end },
        { label = "Tanks and healers", click = function() UI.rolesSheet(s) end },
      }, "left")
      p:buttons({
        { label = ("Pot rules (%d)"):format(gk.rules and #gk.rules or 0), click = function() UI.potRulesSheet(s) end },
        { label = "Gold in or out", click = function() UI.goldInOutSheet(s) end },
      }, "left")
      p:buttons({
        { label = "Ledger", click = function() UI.ledgerSheet(s) end },
        { label = "Auction several at once", click = function() UI.batchSheet() end },
      }, "left")
      p:buttons({
        { label = ("Sales (%d)"):format(#G.sales(s)), click = function() UI.salesSheet(s) end },
        { label = "Starting bids in and out", click = function() UI.pricesSheet(s) end },
      }, "left")
      p:buttons({
        { label = "A starting bid for an item", click = function()
          UI.pickAnyItem("Which item starts higher (or lower)?", function(id)
            goldSheet("Bids for " .. LR.itemName(id) .. " start at", nil, G.minFor(s, id), function(g) LR.gdkpPrice(s, id, g) end)
          end)
        end },
      }, "left")
    end
  end)
end
