-- Rolling out loot. The loot master (or the raid leader, or an assistant) rolls an item out from the loot
-- window, from /lr roll, or from their bags; everyone in the group with LootRuler gets a roll window for it
-- (UI/RollFrame.lua) whose buttons simply /roll, and everyone without it is told in raid chat what to roll.
-- The rolls themselves are the game's own "Name rolls 57 (1-100)" messages, which nobody can fake, and
-- every addon reads them with the same rules (Core/Roll.lua).
--
-- Messages (on top of Core/Net.lua's, same prefix):
--   R  loot master -> group    a roll: started, or its time changed. { k, id, l = link, s = seconds, left,
--                              m = mode, w = who may roll (names, or { name, reserves }), tie = kind of a tie roll }
--   X  loot master -> group    a roll is over: { k, e = "closed" / "cancelled" / "awarded", p = winner, n, kd }
--   N  raider -> loot master   "I pass" on roll k
-- The leader of the soft reserves records who won what (so a reserve that has won its item is used up),
-- whether they rolled it out themselves or the loot master did.
local _, LR = ...
local U, S, R = LR.U, LR.Session, LR.Roll
local Net = LR.Net

local Rolls = { seen = {}, order = {} }
LR.Rolls = Rolls

Rolls.SECONDS = { 10, 15, 20, 30, 45, 60 }
Rolls.DEFAULT_SECONDS = 20
local LEEWAY = 1.5        -- rolls this soon after the time is up still count (chat lag)
local LATE = 10           -- rolls up to this long after closing are listed as late; later ones are ignored
local KEEP = 60           -- a finished roll from someone else is forgotten after this long

local parse
local function now() return GetTime() end
local function parser()
  parse = parse or R.parser(RANDOM_ROLL_RESULT)
  return parse
end

---------------------------------------------------------------------- who runs the loot
--- "Name-Realm" of the master looter, when the loot method is master loot
function LR.masterLooter()
  if not (C_PartyInfo and C_PartyInfo.GetLootMethod) or not IsInGroup() then return nil end
  local method, partyID, raidID = C_PartyInfo.GetLootMethod()
  local master = Enum and Enum.LootMethod and Enum.LootMethod.Masterlooter or 2
  if method ~= master then return nil end
  if IsInRaid() and raidID then
    local name = GetRaidRosterInfo(raidID)
    return name and U.full(name) or nil
  end
  if partyID == 0 then return U.me() end
  if partyID then
    local name, realm = UnitName("party" .. partyID)
    if name then return realm and realm ~= "" and (name .. "-" .. realm) or U.full(name) end
  end
end
function LR.isMasterLooter() local ml = LR.masterLooter() return ml ~= nil and U.samePlayer(ml, U.me()) end

--- whether a player may roll loot out: the group's leader or an assistant, the master looter, or the leader
--- of the soft reserves. On your own (trying it out) you may.
function LR.canRunLoot(name)
  name = name or U.me()
  if not IsInGroup() then return U.samePlayer(name, U.me()) end
  local m = LR.inGroup(name)
  if not m then return false end
  if m.leader or m.assist then return true end
  local ml = LR.masterLooter()
  if ml and U.samePlayer(ml, name) then return true end
  for _, s in pairs(LR.db.sessions) do
    if not s.ended and U.samePlayer(s.leader, name) and (LR.isLeader(s) or LR.inGroup(s.leader)) then return true end
  end
  return false
end

--- the soft reserves the loot in this group goes by: the current session, if its leader is with us
local function session()
  local s = LR.current()
  if s and (LR.isLeader(s) or LR.inGroup(s.leader)) then return s end
end
Rolls.session = session

---------------------------------------------------------------------- chat
local function chatChannel()
  local g = LR.groupChannel()
  if not g then return nil end
  return g
end
local function say(text, warning)
  local ch = chatChannel()
  if not ch then LR.print(U.plain(text)) return end
  if warning and ch == "RAID" and LR.db.settings.raidWarning and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then ch = "RAID_WARNING" end
  for _, line in ipairs(U.chatLines(LR.TAG .. " " .. text)) do LR.say(line, ch) end
end
Rolls.say = say

local function howTo(roll, link, secs)
  local t = U.plural(secs, "second")
  if roll.mode == "SR" then
    return ("%s is soft reserved by %s: only they roll (/roll). %s."):format(link, R.names(roll.who, 6), t)
  elseif roll.mode == "TIE" then
    return ("Tie for %s: %s roll again (%s). %s."):format(link, R.names(roll.who, 6), roll.tie == "OS" and "/roll 99" or "/roll", t)
  end
  local away = #roll.away > 0 and (" (Reserved by %s, who isn't here.)"):format(R.names(roll.away, 3)) or ""
  return ("Roll for %s: /roll for main spec, /roll 99 for off spec. %s.%s"):format(link, t, away)
end

local function resultText(roll, link)
  local top, tied = R.result(roll)
  if not top then return ("Rolls closed for %s: nobody rolled."):format(link) end
  if tied then
    return ("Rolls closed for %s: %s tied at %d."):format(link, R.names(tied), top.n)
  end
  return ("Rolls closed for %s: %s wins with %d (%s)."):format(link, U.short(top.p), top.n, R.LABEL[top.kind])
end

---------------------------------------------------------------------- sending
local function sendGroup(msg)
  local ch = LR.groupChannel()
  if ch then Net.send(msg, ch) end
end
local function wire(roll)
  local who = {}
  for _, w in ipairs(roll.who) do who[#who + 1] = type(w) == "table" and { w[1], w[2] } or w end
  return { t = "R", k = roll.k, id = roll.id, l = roll.link, s = roll.secs, left = math.max(0, roll.ends - now()),
    m = roll.mode, w = who, f = roll.f, tie = roll.tie }
end

---------------------------------------------------------------------- the loot master's roll
local seq = 0
local ticking = 0

local function changed() LR.changed("roll") end

--- the roll I'm running (or ran last), or nil
function Rolls.mine() return Rolls.current end

local close
local function tick(roll, mine)
  if ticking ~= mine or Rolls.current ~= roll then return end
  if roll.state == "open" then
    local left = roll.ends - now()
    if not roll.warned and roll.secs >= 10 and left <= 5.05 and left > 0 then
      roll.warned = true
      say(("5 seconds left to roll for %s."):format(roll.link))
    end
    if left <= -LEEWAY then close(roll) return end
    -- an SR or tie roll is over as soon as everyone who may roll has rolled or passed
    local waiting = R.waiting(roll)
    if waiting and #waiting == 0 and #roll.who > 0 then
      if not roll.allIn then roll.allIn = now() end
      if now() - roll.allIn >= LEEWAY then close(roll) return end
    end
  end
  C_Timer.After(0.25, function() tick(roll, mine) end)
end

local function startTicking(roll)
  ticking = ticking + 1
  local mine = ticking
  C_Timer.After(0.25, function() tick(roll, mine) end)
end

--- starts rolling an item out. opts: { link, slot (in the open loot window), secs, mode = "OPEN" (let
--- everyone roll, even on a reserved item), tie = { kind, names } }. A hard reserved item isn't rolled for
--- unless opts.mode says so: the roll comes back "closed", for the loot master to give it out.
--- Returns the roll, or nil and why not.
function Rolls.start(id, opts)
  opts = opts or {}
  if type(id) ~= "number" then return nil, "That isn't an item." end
  if not LR.canRunLoot() then return nil, "Only the raid leader, an assistant or the master looter can roll out loot." end
  local cur = Rolls.current
  if cur and cur.state == "open" then return nil, "Finish the roll for " .. U.plain(cur.link) .. " first." end
  local s = session()
  local plan
  if opts.tie then
    plan = { mode = "TIE", who = opts.tie.names, tie = opts.tie.kind }
  elseif opts.mode == "OPEN" then
    plan = R.plan(nil, id, LR.roster())
    if s then plan.away = R.plan(s, id, LR.roster()).away end
  else
    plan = R.plan(s, id, LR.roster())
  end
  seq = seq + 1
  local roll = R.new(U.me() .. ":" .. U.now() .. ":" .. seq, id, plan)
  roll.by = U.me()
  roll.link = opts.link or LR.itemLink(id)
  roll.slot = opts.slot
  -- which of the raid's drops this is: the one asked for, the one in that loot slot, else the first not given out
  roll.drop = opts.drop or (opts.slot and LR.Drops.forSlot(opts.slot)) or nil
  if not roll.drop and s then local d = S.openDrops(s, id)[1] roll.drop = d and d.k end
  roll.secs = math.max(5, math.min(120, tonumber(opts.secs) or LR.db.settings.rollSeconds or Rolls.DEFAULT_SECONDS))
  roll.started = now()
  roll.ends = now() + roll.secs
  roll.sid = s and s.id
  Rolls.current = roll
  if roll.mode == "HR" then
    roll.state = "closed"
    roll.ends = now()
    changed()
    return roll
  end
  roll.state = "open"
  sendGroup(wire(roll))
  say(howTo(roll, roll.link, roll.secs), true)
  Rolls.follow(wire(roll), U.me())           -- the loot master gets a roll window too: they may want it
  startTicking(roll)
  changed()
  return roll
end

--- more time for the roll that's open
function Rolls.extend(seconds)
  local roll = Rolls.current
  if not roll or roll.state ~= "open" then return false end
  roll.ends = math.max(roll.ends, now()) + (seconds or 10)
  roll.secs = roll.secs + (seconds or 10)
  roll.warned = false
  roll.allIn = nil
  sendGroup(wire(roll))
  Rolls.follow(wire(roll), U.me())
  say(("%s more seconds to roll for %s."):format(seconds or 10, roll.link))
  changed()
  return true
end

close = function(roll)
  if roll.state ~= "open" then return end
  roll.state = "closed"
  roll.closedAt = now()
  local top, tied = R.result(roll)
  sendGroup({ t = "X", k = roll.k, e = "closed", p = top and not tied and top.p or nil, n = top and top.n, kd = top and top.kind })
  Rolls.ended(roll.k, "closed", top and not tied and top.p or nil, top and top.n, top and top.kind)
  say(resultText(roll, roll.link))
  if tied then roll.tied = tied end
  ticking = ticking + 1
  changed()
end

--- closes the roll now (rolls already made count)
function Rolls.stop()
  local roll = Rolls.current
  if not roll or roll.state ~= "open" then return false end
  roll.ends = now()
  close(roll)
  return true
end

--- calls the roll off: nobody gets the item from it
function Rolls.cancel()
  local roll = Rolls.current
  if not roll then return false end
  local wasOpen = roll.state == "open"
  roll.state = "cancelled"
  ticking = ticking + 1
  sendGroup({ t = "X", k = roll.k, e = "cancelled" })
  Rolls.ended(roll.k, "cancelled")
  if wasOpen then say(("The roll for %s is called off."):format(roll.link)) end
  Rolls.current = nil
  changed()
  return true
end

--- forgets a finished roll (closes the loot master's window)
function Rolls.dismiss()
  local roll = Rolls.current
  if roll and roll.state == "open" then return false end
  Rolls.current = nil
  changed()
  return true
end

--- the same item again: a new roll for everyone who tied, or for everyone (mode "OPEN")
function Rolls.again(mode)
  local roll = Rolls.current
  if not roll or roll.state == "open" then return nil end
  local opts = { link = roll.link, slot = roll.slot, secs = roll.secs, drop = roll.drop }
  if mode == "TIE" and roll.tied then
    -- they roll the way they rolled before (a tie between reservers is still for the reserve)
    opts.tie = { kind = R.result(roll).kind, names = roll.tied }
  elseif mode == "OPEN" then
    opts.mode = "OPEN"
  end
  Rolls.current = nil
  local again, why = Rolls.start(roll.id, opts)
  if not again then Rolls.current = roll end       -- couldn't: keep the one we had
  return again, why
end

---------------------------------------------------------------------- giving it out
--- whether the item is still in the open loot window, in the slot it was rolled from; the slot if so
local function lootSlot(roll)
  if not roll.slot or not Rolls.lootOpen then return nil end
  local link = GetLootSlotLink(roll.slot)
  local id = link and tonumber(link:match("item:(%d+)"))
  if id == roll.id then return roll.slot end
  -- the loot window was closed and opened again, so its slots were numbered afresh: look for it
  for slot = 1, GetNumLootItems() do
    local l = GetLootSlotLink(slot)
    if l and tonumber(l:match("item:(%d+)")) == roll.id then return slot end
  end
end
Rolls.lootSlot = lootSlot

--- the master loot list's place for a player (for GiveMasterLoot), or nil
local function candidate(slot, player)
  for i = 1, 40 do
    local name = GetMasterLootCandidate(slot, i)
    if name and U.samePlayer(U.full(name), player) then return i end
  end
end

--- records that a player won an item (on the session, when I'm its leader)
local function record(s, id, player, kind, n, drop)
  if not s or not LR.isLeader(s) then return end
  if S.award(s, id, player, kind, n, U.now(), drop) then LR.leaderChanged(s) end
end

--- gives the item to a player: straight from the loot window when it's still there (master loot), else it's
--- recorded and announced, for the loot master to trade it. kind and n: how they won it (from the rolls if
--- not given). Returns true, and a note for the loot master when the item couldn't be handed over.
function Rolls.award(player, kind, n)
  local roll = Rolls.current
  if not roll or roll.state == "open" or roll.state == "cancelled" then return false, "There's no finished roll to give out." end
  player = U.full(player)
  if not kind then
    local e = roll.rolled[R.key(player)]
    kind, n = e and e.kind or (roll.mode == "HR" and "HR" or "MS"), e and e.n
  end
  local note
  local slot = lootSlot(roll)
  if slot then
    local i = candidate(slot, player)
    if i then GiveMasterLoot(slot, i)
    else note = ("%s isn't on the loot list for this item (too far away, or can't loot it), so it's marked as theirs: trade it to them."):format(U.short(player)) end
  end
  roll.state = "awarded"
  roll.winner = player
  local s = session()
  record(s, roll.id, player, kind, n, roll.drop)
  sendGroup({ t = "X", k = roll.k, id = roll.id, e = "awarded", p = player, n = n, kd = kind, sid = s and s.id, d = roll.drop })
  -- it's in my bags (rolled out later): it goes over in a trade
  local held = not slot and s and roll.drop and S.drop(s, roll.drop)
  if not note and held and held.h and U.samePlayer(held.h, U.me()) and not U.samePlayer(player, U.me()) then
    note = ("Open a trade with %s: LootRuler puts %s in it for you."):format(U.short(player), U.plain(roll.link))
  end
  Rolls.ended(roll.k, "awarded", player, n, kind)
  say(("%s goes to %s%s."):format(roll.link, U.short(player), n and (" (" .. R.LABEL[kind] .. " " .. n .. ")") or (kind == "HR" and " (hard reserved)" or "")))
  changed()
  return true, note
end

---------------------------------------------------------------------- following a roll (every raider)
--- a roll from the loot master (or our own): start or update our copy and show its window
function Rolls.follow(msg, sender)
  if type(msg.k) ~= "string" or type(msg.id) ~= "number" or type(msg.s) ~= "number" or type(msg.left) ~= "number" then return end
  if msg.m ~= "OPEN" and msg.m ~= "SR" and msg.m ~= "TIE" then return end
  local copy = Rolls.seen[msg.k]
  if not copy then
    local who = {}
    -- who may roll: names, or { name, reserves } on a reserved item
    if type(msg.w) == "table" then
      for _, w in ipairs(msg.w) do
        if type(w) == "string" then who[#who + 1] = w
        elseif type(w) == "table" and type(w[1]) == "string" then who[#who + 1] = { w[1], tonumber(w[2]) or 1 } end
      end
    end
    copy = R.new(msg.k, msg.id, { mode = msg.m, who = who, tie = R.KINDS[msg.tie] and msg.tie or (msg.m == "TIE" and "MS" or nil) })
    copy.by = sender
    copy.link = type(msg.l) == "string" and msg.l or LR.itemLink(msg.id)
    copy.state = "open"
    Rolls.seen[msg.k] = copy
    table.insert(Rolls.order, msg.k)
    -- a tie roll is only for the players who tied
    if copy.mode == "TIE" and not R.inList(copy.who, U.me()) then copy.hidden = true end
  end
  copy.secs = math.min(120, math.max(1, msg.s))
  copy.ends = now() + math.min(120, math.max(0, msg.left))
  copy.state = "open"
  copy.seenAt = now()
  if not copy.hidden and LR.UI and LR.UI.rollWindow then LR.UI.rollWindow(copy) end
  LR.changed("rolls")
end

--- a roll is over (from the loot master, or ourselves)
function Rolls.ended(k, how, winner, n, kind)
  local copy = Rolls.seen[k]
  if not copy then return end
  copy.state = how
  copy.winner = winner
  copy.winN, copy.winKind = n, kind
  copy.endedAt = now()
  if how == "closed" and not copy.closedAt then copy.closedAt = now() end
  if LR.UI and LR.UI.rollEnded then LR.UI.rollEnded(copy) end
  LR.changed("rolls")
end

--- I roll in a roll (the window's buttons)
function Rolls.roll(copy, kind)
  local r = R.KINDS[kind]
  if not r or copy.state ~= "open" then return false end
  RandomRoll(r[1], r[2])
  copy.myRoll = kind
  return true
end

--- I pass on a roll: the loot master is told, so a reserved item isn't held up waiting for me
function Rolls.pass(copy)
  copy.passedByMe = true
  if copy.state ~= "open" then return end
  if U.samePlayer(copy.by, U.me()) then
    local roll = Rolls.current
    if roll and roll.k == copy.k then R.pass(roll, U.me()) changed() end
  elseif LR.inGroup(copy.by) then
    Net.send({ t = "N", k = copy.k }, "WHISPER", copy.by)
  end
end

--- every roll message in chat: counted in the loot master's roll and in everyone's copies
function Rolls.onRoll(line)
  local name, n, lo, hi = parser()(line)
  if not name then return end
  local t = now()
  local roll = Rolls.current
  if roll and (roll.state == "open" or (roll.state == "closed" and roll.closedAt and t - roll.closedAt <= LATE)) and roll.mode ~= "HR" then
    if LR.inGroup(name) or not IsInGroup() then
      R.add(roll, name, n, lo, hi, roll.state ~= "open")
      changed()
    end
  end
  for _, k in ipairs(Rolls.order) do
    local copy = Rolls.seen[k]
    if copy and copy.state == "open" then R.add(copy, name, n, lo, hi, false) end
  end
  LR.changed("rolls")
end

---------------------------------------------------------------------- messages
local function fromLooter(sender) return LR.canRunLoot(sender) end

Net.handlers.R = function(msg, channel, sender)
  if not fromLooter(sender) then return end
  local copy = Rolls.seen[msg.k]
  if copy and not U.samePlayer(copy.by, sender) then return end
  Rolls.follow(msg, sender)
end

Net.handlers.X = function(msg, channel, sender)
  if type(msg.k) ~= "string" then return end
  local copy = Rolls.seen[msg.k]
  local winner = type(msg.p) == "string" and msg.p or nil
  local kind = R.KINDS[msg.kd] and msg.kd or (msg.kd == "HR" and "HR" or nil)
  if copy and U.samePlayer(copy.by, sender) and (msg.e == "closed" or msg.e == "cancelled" or msg.e == "awarded") then
    Rolls.ended(msg.k, msg.e, winner, tonumber(msg.n), kind)
  end
  -- the leader of the soft reserves records loot given out by the loot master
  if msg.e == "awarded" and winner and kind and fromLooter(sender) then
    local s = msg.sid and LR.session(msg.sid) or session()
    local id = copy and copy.id or tonumber(msg.id)
    if s and id and LR.isLeader(s) then record(s, id, winner, kind, msg.n, type(msg.d) == "string" and msg.d or nil) end
  end
end

Net.handlers.N = function(msg, channel, sender)
  local roll = Rolls.current
  if not roll or roll.k ~= msg.k or roll.state ~= "open" then return end
  R.pass(roll, sender)
  changed()
end

---------------------------------------------------------------------- the loot window
local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_SYSTEM")
events:RegisterEvent("LOOT_OPENED")
events:RegisterEvent("LOOT_CLOSED")
events:RegisterEvent("LOOT_SLOT_CLEARED")
events:SetScript("OnEvent", function(_, event, ...)
  if event == "CHAT_MSG_SYSTEM" then
    local ok, err = pcall(Rolls.onRoll, ...)
    if not ok then geterrorhandler()(err) end
  elseif event == "LOOT_OPENED" then
    Rolls.lootOpen = true
    local ok, err = pcall(LR.Drops.lootOpened)            -- the raid's loot list (Core/Drops.lua)
    if not ok then geterrorhandler()(err) end
    LR.changed("loot")
  elseif event == "LOOT_CLOSED" then
    Rolls.lootOpen = false
    LR.changed("loot")
  elseif event == "LOOT_SLOT_CLEARED" then
    LR.changed("loot")
  end
end)

--- what's in the open loot window that's worth rolling for: { { slot, id, link, quality } }
function Rolls.loot()
  local out = {}
  if not Rolls.lootOpen then return out end
  local threshold = GetLootThreshold and GetLootThreshold() or 2
  for slot = 1, GetNumLootItems() do
    if LootSlotHasItem(slot) then
      local link = GetLootSlotLink(slot)
      local id = link and tonumber(link:match("item:(%d+)"))
      local _, _, _, _, quality = GetLootSlotInfo(slot)
      if id and (quality or 0) >= threshold then out[#out + 1] = { slot = slot, id = id, link = link, quality = quality } end
    end
  end
  return out
end

-- finished rolls from others are forgotten after a while
C_Timer.After(1, function()
  local function sweep()
    local t = now()
    for i = #Rolls.order, 1, -1 do
      local k = Rolls.order[i]
      local c = Rolls.seen[k]
      if not c or (c.state ~= "open" and c.endedAt and t - c.endedAt > KEEP) then
        Rolls.seen[k] = nil
        table.remove(Rolls.order, i)
      end
    end
    C_Timer.After(15, sweep)
  end
  sweep()
end)
