-- GDKP in the game (the rules and the money are in Core/Gdkp.lua): keeping track of who's in the group for
-- their share, saying who owes whom when a trade opens, and telling the raid (and each player) the payouts.
-- Only the session's leader (the organiser) does any of this; raiders' addons just show it.
local _, LR = ...
local U = LR.U
local G = LR.Gdkp

local Pot = {}
LR.Pot = Pot

--- the GDKP session I'm organising, if any
function Pot.mine()
  local s = LR.Rolls.session()
  if s and s.gdkp and s.gk and LR.isLeader(s) then return s end
end

--- one player's payout, in words for them ("you" is them; the organiser is named)
function Pot.line(s, player)
  local split = G.split(s)
  local row = split.rows[U.full(player)]
  local org = U.short(s.leader)
  if U.samePlayer(player, s.leader) then
    return ("The pot is %s. You hold it: %s of it is your cut."):format(G.gold(split.pot), G.gold(split.cut))
  end
  if not row then return ("The pot is %s so far, split %d ways: %s each."):format(G.gold(split.pot), #split.players, G.gold(split.share)) end
  local parts = {}
  if row.spent > 0 then parts[#parts + 1] = "you bought " .. G.gold(row.spent) end
  local extras = {}
  if row.roleCut > 0 then extras[#extras + 1] = "a " .. G.gold(row.roleCut) .. " " .. row.role .. " cut" end
  if row.ruleCut > 0 then extras[#extras + 1] = G.gold(row.ruleCut) .. " for " .. table.concat(row.ruleNames or {}, " and ") end
  if row.bonus > 0 then extras[#extras + 1] = "a " .. G.gold(row.bonus) .. " bonus" end
  parts[#parts + 1] = row.out and "you're not in the split" or ("your share is " .. G.gold(row.gets) .. (#extras > 0 and (" (with " .. table.concat(extras, " and ") .. ")") or ""))
  if row.paid > 0 then parts[#parts + 1] = "you've paid " .. G.gold(row.paid) end
  if row.paid < 0 then parts[#parts + 1] = "you've had " .. G.gold(-row.paid) end
  local what
  if math.abs(row.owed) < 0.01 then what = "you're all settled"
  elseif row.owed > 0 then what = ("%s gives you %s"):format(org, G.gold(row.owed))
  else what = ("you give %s %s"):format(org, G.gold(-row.owed)) end
  local text = table.concat(parts, ", ")
  return "GDKP: " .. text:sub(1, 1):upper() .. text:sub(2) .. ", so " .. what .. "."
end

--- the raid's summary, in a few chat lines
function Pot.summary(s)
  local split = G.split(s)
  local own = ""
  for i, r in ipairs(s.gk.rules or {}) do
    if (split.ruleTotals[i] or 0) > 0 then own = own .. (", %s %s"):format(r.n, G.gold(split.ruleTotals[i])) end
  end
  local lines = { ("GDKP pot: %s from %d items. %s's cut: %s (%d%%)%s. Split %d ways: %s each."):format(
    G.gold(split.pot), #G.sales(s), U.short(s.leader), G.gold(split.cut), s.gk.cut,
    (split.bonuses > 0 and (", bonuses " .. G.gold(split.bonuses)) or "") .. (split.roles > 0 and (", tank and healer cuts " .. G.gold(split.roles)) or "") .. own,
    #split.players, G.gold(split.share)) }
  lines[#lines + 1] = ("Whisper %s \"!lr pot\" to see what you owe or are owed."):format(U.short(s.leader))
  return lines
end

--- posts the summary in raid chat
function Pot.post(s)
  local ch = LR.groupChannel()
  if not ch then return false end
  for _, line in ipairs(Pot.summary(s)) do
    for _, l in ipairs(U.chatLines(LR.TAG .. " " .. line, 255)) do LR.say(l, ch) end
  end
  return true
end

--- whispers everyone in the split (and every buyer) their payout
function Pot.whisperAll(s)
  local n = 0
  for name in pairs(G.split(s).rows) do
    if not U.samePlayer(name, U.me()) then
      for _, l in ipairs(U.chatLines(LR.TAG .. " " .. Pot.line(s, name), 255)) do LR.say(l, "WHISPER", name) end
      n = n + 1
    end
  end
  return n
end

--- a trade opened with someone: what they owe me, or I owe them
function Pot.tradeNote(partner)
  local s = Pot.mine() or LR.History.owing(partner)
  if not s then return end
  local row = G.split(s).rows[U.full(partner)]
  if not row or math.abs(row.owed) < 0.01 then return end
  local from = s.archived and (" (from " .. LR.raidOf(s).name .. ", " .. date("%b %d", s.ended) .. ")") or ""
  if row.owed > 0 then LR.print(("GDKP: put %s in the trade for %s (their payout%s)."):format(G.gold(row.owed), U.short(partner), from))
  else LR.print(("GDKP: %s owes you %s%s."):format(U.short(partner), G.gold(-row.owed), from)) end
end

-- everyone who's in the group while the organiser is gets a share
local events = CreateFrame("Frame")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:SetScript("OnEvent", function()
  local s = Pot.mine()
  if s and G.saw(s, U.map(LR.roster(), function(m) return m.name end), U.now()) then LR.leaderChanged(s) end
end)

---------------------------------------------------------------------- payouts by mail
-- At a mailbox, LootRuler fills in the Send Mail tab for the next player the organiser owes gold (their name, a
-- subject, the gold). The organiser checks it and presses the game's Send: an addon can't send mail with gold on
-- its own. When a mail with gold goes to someone in the split, that gold counts as handed over.
local filled                  -- { sid, p, copper }: the payout filled in last
local sending                 -- { sid, p, copper }: the mail the game is sending now

--- who the organiser still owes gold, the most first: { { name, gold } } (whole gold; what's under 1g is left)
function Pot.toMail(s)
  local out = {}
  for name, row in pairs(G.split(s).rows) do
    if not U.samePlayer(name, s.leader) and row.owed >= 1 then out[#out + 1] = { name, math.floor(row.owed) } end
  end
  table.sort(out, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
  return out
end

--- whether the game's Send Mail tab is open
function Pot.mailOpen() return SendMailFrame ~= nil and SendMailFrame:IsShown() end

--- fills in the Send Mail tab for a payout; true, or false and why not
function Pot.fillMail(s, name, gold)
  if s.practice then return false, "A practice raid's payouts aren't mailed." end
  if not Pot.mailOpen() then return false, "Open a mailbox, and its Send Mail tab, first." end
  SendMailNameEditBox:SetText(U.short(name))
  SendMailSubjectEditBox:SetText(("GDKP payout: %s"):format(LR.raidOf(s).name))
  MoneyInputFrame_SetCopper(SendMailMoney, math.floor(gold) * 10000)
  filled = { sid = s.id, p = name, copper = math.floor(gold) * 10000 }
  return true
end

-- what the game sends: noted as it goes, counted when it's gone
hooksecurefunc("SendMail", function(name)
  local x = filled
  filled, sending = nil, nil
  -- only the payout LootRuler filled in, to the same player; with what's in the mail (the organiser may have changed it)
  if not x or type(name) ~= "string" or not U.samePlayer(U.full(U.trim(name)), x.p) then return end
  local copper = GetSendMailMoney and GetSendMailMoney() or 0
  if copper <= 0 then return end
  sending = { sid = x.sid, p = x.p, copper = copper }
end)
local mail = CreateFrame("Frame")
mail:RegisterEvent("MAIL_SEND_SUCCESS")
mail:RegisterEvent("MAIL_FAILED")
mail:SetScript("OnEvent", function(_, event)
  local x = sending
  sending = nil
  if event ~= "MAIL_SEND_SUCCESS" or not x then return end
  local s = LR.session(x.sid)
  if s and LR.gdkpPaid(s, x.p, -x.copper / 10000) then
    LR.print(("mailed %s %s: it counts as paid."):format(U.short(x.p), G.gold(x.copper / 10000)))
  end
end)
