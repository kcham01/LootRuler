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
  local lines = { ("GDKP pot: %s from %d items. %s's cut: %s (%d%%)%s. Split %d ways: %s each."):format(
    G.gold(split.pot), #G.sales(s), U.short(s.leader), G.gold(split.cut), s.gk.cut,
    (split.bonuses > 0 and (", bonuses " .. G.gold(split.bonuses)) or "") .. (split.roles > 0 and (", tank and healer cuts " .. G.gold(split.roles)) or ""),
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
