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
  if row.spent > 0 then parts[#parts + 1] = "bought " .. G.gold(row.spent) end
  parts[#parts + 1] = row.out and "left out of the split" or ("share " .. G.gold(row.gets))
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
    }
    if math.abs(row.owed) >= 0.01 and not U.samePlayer(name, s.leader) then
      list[#list + 1] = { label = "Mark as settled", click = function()
        h.close()
        -- (gold handed over some other way: the mail, or someone else's trade)
        LR.gdkpPaid(s, name, -row.owed)
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
      split.roles > 0 and { "Tank and healer cuts", G.gold(split.roles) } or false,
      { "Split " .. #split.players .. " ways", G.gold(split.share) .. " each" },
    })
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
    f:note("Addons can't put gold in a trade: open a trade with each player and LootRuler says what to give or take. Gold that changes hands is counted.")
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
      p:chips({ { label = (gk.strict and "[x] " or "[  ] ") .. "Bids start with \"bid\"", on = gk.strict, click = function() LR.gdkpStrict(s, not gk.strict) end,
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
        { label = "A starting bid for an item", click = function()
          UI.pickAnyItem("Which item starts higher (or lower)?", function(id)
            goldSheet("Bids for " .. LR.itemName(id) .. " start at", nil, G.minFor(s, id), function(g) LR.gdkpPrice(s, id, g) end)
          end)
        end },
      }, "left")
    end
  end)
end
