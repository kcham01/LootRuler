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
--   M  raider -> loot master   a max bid on auction k: { k, g } (kept by the loot master; nobody else sees it)
-- An auction (GDKP, mode "BID") works the same way, with bids typed in raid chat instead of /rolls: R also
-- carries mn (the lowest first bid), inc (the least raise) and tb (the highest bid so far: { p, n }).
-- The leader of the soft reserves records who won what (so a reserve that has won its item is used up),
-- whether they rolled it out themselves or the loot master did.
local _, LR = ...
local U, S, R = LR.U, LR.Session, LR.Roll
local Net = LR.Net

local Rolls = { seen = {}, order = {}, queue = {} }
LR.Rolls = Rolls

Rolls.SECONDS = { 10, 15, 20, 30, 45, 60 }
Rolls.DEFAULT_SECONDS = 20
local LEEWAY = 1.5        -- rolls this soon after the time is up still count (chat lag)
local LATE = 10           -- rolls up to this long after closing are listed as late; later ones are ignored
local SNIPE = 8           -- a bid with less than this left gives everyone this long again
local NEXT = 3            -- seconds between one item of the queue and the next
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

--- who got what, in guild chat too (Settings: awardGuild), with the raid's name
local function toGuild(text)
  if not LR.db.settings.awardGuild or not IsInGuild() then return end
  local s = session()
  local raid = s and LR.raidOf(s).name
  for _, line in ipairs(U.chatLines(LR.TAG .. " " .. (raid and (raid .. ": ") or "") .. text)) do LR.say(line, "GUILD") end
end

local howTo
local function howToRoll(roll, link, secs)
  local t = U.plural(secs, "second")
  if roll.mode == "SR" then
    return ("%s is soft reserved by %s: only they roll (/roll). %s."):format(link, R.names(roll.who, 6), t)
  elseif roll.mode == "TIE" then
    local _, hi = R.kind(roll, roll.tie)
    return ("Tie for %s: %s roll again (%s). %s."):format(link, R.names(roll.who, 6), (hi or 100) < 100 and ("/roll " .. hi) or "/roll", t)
  elseif roll.mode == "BID" then
    local s = session()
    local max = (s and LR.isLeader(s)) and (" To bid up to a max, whisper %s \"!lr max 800\"."):format(U.short(U.me())) or ""
    return ("Auction: %s. Bids start at %s, each at least %s more than the last. Type your bid in raid chat (%s). %s.%s"):format(
      link, LR.Gdkp.gold(roll.min), LR.Gdkp.gold(roll.inc), roll.strict and ("\"bid " .. roll.min .. "\"") or "just the number", t, max)
  elseif roll.mode == "PR" then
    return ("%s: %s share the top priority, so only they roll (/roll). %s."):format(link, R.names(roll.who, 6), t)
  end
  local away = #roll.away > 0 and (" (Reserved by %s, who isn't here.)"):format(R.names(roll.away, 3)) or ""
  local po = roll.po and next(roll.po) and " Main spec: anyone with a +1 rolls after those without." or ""
  if roll.bp and next(roll.bp) then
    local list = {}
    for _, m in ipairs(LR.roster()) do
      local n = roll.bp[R.key(m.name)]
      if n then list[#list + 1] = { m.name, n } end
    end
    table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    local parts = {}
    for i, x in ipairs(list) do
      if i > 5 then parts[#parts + 1] = "and others with points" break end
      local lo, hi = LR.Book.boostRange(x[2])
      parts[#parts + 1] = ("%s /roll %d %d"):format(U.short(x[1]), lo, hi)
    end
    if #parts > 0 then po = po .. " Boosted rolls (your points are spent if you win): " .. table.concat(parts, ", ") .. "." end
  end
  local extra = ""
  for _, x in ipairs(roll.xk or {}) do extra = extra .. (", /roll %d for %s"):format(x.hi, x.n) end
  return ("Roll for %s: /roll for main spec, /roll 99 for off spec%s. %s.%s%s"):format(link, extra, t, po, away)
end

-- what to roll, then my note on the item and who in the group has it on their thatsmybis wishlist
howTo = function(roll, link, secs)
  local text = howToRoll(roll, link, secs)
  if roll.note then text = text .. (" Note: %s."):format((roll.note:gsub("%.$", ""))) end
  if roll.wish and #roll.wish > 0 and roll.mode ~= "BID" and roll.mode ~= "HR" then text = text .. (" Wishlisted: %s."):format(LR.wishLine(roll.wish)) end
  return text
end

local function resultText(roll, link)
  if roll.mode == "BID" then
    local top = R.topBid(roll)
    if not top then return ("Nobody bid on %s."):format(link) end
    return ("Sold: %s to %s for %s."):format(link, U.short(top.p), LR.Gdkp.gold(top.n))
  end
  local top, tied = R.result(roll)
  if not top then return ("Rolls closed for %s: nobody rolled."):format(link) end
  if tied then
    return ("Rolls closed for %s: %s tied at %d."):format(link, R.names(tied), top.n)
  end
  return ("Rolls closed for %s: %s wins with %d (%s)."):format(link, U.short(top.p), top.n, R.label(roll, top))
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
    m = roll.mode, w = who, f = roll.f, tie = roll.tie, po = roll.po, bp = roll.bp, xk = roll.xk, nt = roll.note, wl = roll.wish, pn = roll.mode == "PR" and roll.n or nil,
    mn = roll.min, inc = roll.inc, sb = roll.strict or nil, tb = roll.top and { roll.top.p, roll.top.n } or nil }
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
    plan = { mode = "TIE", who = opts.tie.names, tie = opts.tie.kind, xk = opts.tie.xk }
    plan.boosted = opts.tie.boosted
  elseif opts.mode == "OPEN" then
    plan = R.plan(nil, id, LR.roster())
    if s then plan.away = R.plan(s, id, LR.roster()).away end
  else
    plan = R.plan(s, id, LR.roster())
    -- GDKP: it's auctioned (a hard reserve still comes first)
    if s and s.gdkp and s.gk and plan.mode ~= "HR" then
      plan = { mode = "BID", min = LR.Gdkp.minFor(s, id), inc = s.gk.inc, strict = s.gk.strict, who = {}, away = {} }
    -- the guild's priority lists, when the session goes by them: the best priority here gets it (a hard
    -- reserve still comes first); with "only", reserves don't count
    elseif s and s.prio and plan.mode ~= "HR" then
      local pr = LR.Guild and LR.Guild.prioPlan(id)
      if pr then pr.away = plan.away plan = pr
      elseif s.prio == "only" then plan = R.plan(nil, id, LR.roster()) end
    end
  end
  -- my own roll types (Settings: rollKinds), when it's open to everyone
  if plan.mode == "OPEN" then plan.xk = R.checkKinds(LR.db.settings.rollKinds) end
  -- the +1 rule: everyone's +1s as the roll starts
  if s and s.plusOne then plan.po = S.plusOneTable(s, U.map(LR.roster(), function(m) return m.name end)) end
  -- boosted rolls: everyone's guild points (Core/Book.lua), when the session uses them
  local book = LR.book and LR.book()
  if s and s.boost and book and book.boost.on and plan.mode == "OPEN" then
    plan.bp = {}
    for _, m in ipairs(LR.roster()) do
      local n = LR.Book.points(book, m.name)
      if n > 0 then plan.bp[U.full(m.name):lower()] = n end
    end
  end
  seq = seq + 1
  local roll = R.new(U.me() .. ":" .. U.now() .. ":" .. seq, id, plan)
  roll.boosted = plan.boosted            -- (a tie roll) who rolled boosted before: name -> points
  roll.by = U.me()
  roll.note = LR.noteFor(id)
  local wish = LR.wishFor(id, true)
  roll.wish = #wish > 0 and { unpack(wish, 1, math.min(#wish, 8)) } or nil
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
  -- first on the priority list, alone: no roll, it's theirs
  if roll.mode == "PR" and #roll.who == 1 then
    roll.state = "closed"
    roll.ends = now()
    say(("%s: %s is first on the priority list, so it goes to them."):format(roll.link, U.short(roll.who[1])), true)
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
  if roll.mode == "BID" then
    -- an auction: sold to the highest bid, or left for the loot master when nobody bid
    local top = R.topBid(roll)
    sendGroup({ t = "X", k = roll.k, e = "closed", p = top and top.p, n = top and top.n, kd = top and "BID" })
    Rolls.ended(roll.k, "closed", top and top.p, top and top.n, top and "BID")
    ticking = ticking + 1
    if top then
      local ok, note = Rolls.award(top.p, "BID", top.n)
      if ok and note then roll.note = note end
    else
      say(resultText(roll, roll.link))
      if #Rolls.queue > 0 then Rolls.current = nil Rolls.queueNext() end
    end
    changed()
    return
  end
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
  if wasOpen then say(("The %s for %s is called off."):format(roll.mode == "BID" and "auction" or "roll", roll.link)) end
  Rolls.current = nil
  Rolls.queueNext()
  changed()
  return true
end

--- forgets a finished roll (closes the loot master's window)
function Rolls.dismiss()
  local roll = Rolls.current
  if roll and roll.state == "open" then return false end
  Rolls.current = nil
  Rolls.queueNext()
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
    local kind = R.result(roll).kind
    -- a tie between boosted rolls (or a boosted and a main spec roll) is rolled again as plain main spec;
    -- whoever had boosted still spends their points if they win
    local boosted
    if kind == "BR" or kind == "MS" then
      for _, name in ipairs(roll.tied) do
        local e = roll.rolled[R.key(name)]
        if e and e.kind == "BR" then boosted = boosted or {} boosted[R.key(name)] = roll.bp and roll.bp[R.key(name)] or 0 end
      end
      kind = "MS"
    end
    opts.tie = { kind = kind, names = roll.tied, boosted = boosted, xk = R.extra(roll, kind) and roll.xk or nil }
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
local function record(s, id, player, kind, n, drop, de, xn)
  if not s or not LR.isLeader(s) then return end
  local boosted = kind == "BR"
  if boosted then kind = "MS" end            -- a boosted roll is a main spec win (and a +1), marked as boosted
  if S.award(s, id, player, kind, n, U.now(), drop, de, boosted, xn) then LR.leaderChanged(s) end
end

--- gives the item to a player: straight from the loot window when it's still there (master loot), else it's
--- recorded and announced, for the loot master to trade it. kind and n: how they won it (from the rolls if
--- not given). Returns true, and a note for the loot master when the item couldn't be handed over.
function Rolls.award(player, kind, n, de)
  local roll = Rolls.current
  if not roll or roll.state == "open" or roll.state == "cancelled" then return false, "There's no finished roll to give out." end
  player = U.full(player)
  if de then kind, n = "OS", nil end
  if not kind then
    local e = roll.rolled[R.key(player)]
    kind, n = e and e.kind or (roll.mode == "HR" and "HR" or "MS"), e and e.n
  end
  -- won a tie roll after a boosted roll: still a boosted win
  if kind == "MS" and roll.boosted and roll.boosted[R.key(player)] then kind = "BR" end
  local note
  local slot = lootSlot(roll)
  if slot then
    local i = candidate(slot, player)
    if i then GiveMasterLoot(slot, i)
    else note = ("%s isn't on the loot list for this item (too far away, or can't loot it), so it's marked as theirs: trade it to them."):format(U.short(player)) end
  end
  roll.state = "awarded"
  roll.winner = player
  roll.winKind = kind
  roll.undoNote = nil
  roll.de = de
  local s = session()
  -- won on one of my own roll types: off spec, by its name (so older versions take it as off spec)
  local x = not de and R.extra(roll, kind)
  local xn = x and x.n or nil
  if x then kind = "OS" end
  record(s, roll.id, player, kind, n, roll.drop, de, xn)
  sendGroup({ t = "X", k = roll.k, id = roll.id, e = "awarded", p = player, n = n, kd = kind, sid = s and s.id, d = roll.drop, de = de or nil, xn = xn })
  -- the guild's priority lists: whoever gets an item comes off its list (not the disenchanter)
  local book = not de and s and s.prio and LR.book and LR.book()
  if book and R.inList(U.map(LR.Book.prio(book, roll.id), function(x) return x.p end), player) then
    if LR.canEditBook() then
      LR.Guild.edit(function(b, t) return LR.Book.received(b, roll.id, player, t) end)
      note = (note and (note .. " ") or "") .. ("%s comes off its priority list."):format(U.short(player))
    else
      note = (note and (note .. " ") or "") .. ("Ask an officer to take %s off its priority list: you can't change the lists."):format(U.short(player))
    end
  end
  -- won with a boosted roll: the points are spent (by whoever may change the guild book)
  if kind == "BR" then
    local spent = (roll.bp and roll.bp[R.key(player)]) or (roll.boosted and roll.boosted[R.key(player)]) or 0
    if LR.canEditBook() then
      LR.Guild.edit(function(book, now) return LR.Book.setPoints(book, player, 0, now) end)
      note = (note and (note .. " ") or "") .. ("%s's %d points are spent."):format(U.short(player), spent)
    else
      note = (note and (note .. " ") or "") .. ("Ask an officer to take %s's %d points: you can't change points."):format(U.short(player), spent)
    end
  end
  -- it's in my bags (rolled out later): it goes over in a trade
  local held = not slot and s and roll.drop and S.drop(s, roll.drop)
  if not note and held and held.h and U.samePlayer(held.h, U.me()) and not U.samePlayer(player, U.me()) then
    note = ("Open a trade with %s: LootRuler puts %s in it for you."):format(U.short(player), U.plain(roll.link))
    -- open the trade myself when they're close; when they're too far, they're asked to come and trade
    if LR.db.settings.autoTrade then
      local ok, why = LR.Drops.openTrade(player)
      if ok then note = ("A trade with %s is opening: LootRuler puts %s in it."):format(U.short(player), U.plain(roll.link))
      elseif why == "far" then
        note = ("%s is too far away to trade: they've been whispered to come and trade you."):format(U.short(player))
        LR.say(("%s I have %s for you. Come close and open a trade with me when you can."):format(LR.TAG, roll.link), "WHISPER", player)
      elseif why == "combat" then
        note = ("In combat: open a trade with %s when it's over, and LootRuler puts %s in it."):format(U.short(player), U.plain(roll.link))
      end
    end
  end
  Rolls.ended(roll.k, "awarded", player, n, kind)
  local line
  if kind == "BID" then line = ("Sold: %s to %s for %s."):format(roll.link, U.short(player), LR.Gdkp.gold(n))
  elseif de then line = ("%s goes to %s, to be disenchanted."):format(roll.link, U.short(player))
  elseif roll.given then
    line = ("%s goes to %s (%s, given out without a roll)."):format(roll.link, U.short(player),
      kind == "SR" and "their reserve" or kind == "OS" and "off spec" or "main spec")
  else line = ("%s goes to %s%s."):format(roll.link, U.short(player), n and (" (" .. (xn or R.LABEL[kind] or kind) .. " " .. n .. ")") or (kind == "HR" and " (hard reserved)" or "")) end
  say(line)
  toGuild(line)
  -- the next item in the queue, a moment later (the loot master's window shows this one until then; not if the
  -- award is undone meanwhile)
  if #Rolls.queue > 0 then
    C_Timer.After(NEXT, function() if Rolls.current == roll and roll.state == "awarded" then Rolls.current = nil Rolls.queueNext() end end)
  end
  changed()
  return true, note
end

--- gives an item to a player without a roll (the loot master's choice): through master loot when it's in the open
--- loot window, else marked for a trade, and recorded like a roll's award. kind: "MS", "OS", "SR" (their reserve)
--- or "DE" (to the disenchanter). opts: { link, slot, drop }. Returns true and a note, or false and why not.
function Rolls.give(id, player, kind, opts)
  opts = opts or {}
  if type(id) ~= "number" or not player then return false, "Pick who gets it." end
  if not LR.canRunLoot() then return false, "Only the raid leader, an assistant or the master looter can give out loot." end
  local cur = Rolls.current
  if cur and cur.state == "open" then return false, "Finish the roll for " .. U.plain(cur.link) .. " first." end
  local s = session()
  local roll = R.new(U.me() .. ":" .. U.now() .. ":give", id, { mode = "OPEN" })
  roll.by, roll.link, roll.slot, roll.state, roll.given = U.me(), opts.link or LR.itemLink(id), opts.slot, "closed", true
  roll.drop = opts.drop or (opts.slot and LR.Drops.forSlot(opts.slot)) or nil
  if not roll.drop and s then local d = S.openDrops(s, id)[1] roll.drop = d and d.k end
  roll.secs, roll.started, roll.ends = 0, now(), now()
  Rolls.current = roll
  if kind == "DE" then return Rolls.award(player, nil, nil, true) end
  return Rolls.award(player, kind == "SR" and "SR" or kind == "OS" and "OS" or "MS")
end

--- takes an award back from the list of loot given out (the leader's addon)
local function unrecord(s, id, player, drop)
  if not s or not LR.isLeader(s) then return end
  local i = S.findAward(s, id, player, drop)
  if i then LR.unaward(s, i) end
end

--- the item went to the wrong player: the award is undone, and the roll is back as it was when it closed, to give it
--- to someone else or roll it again. Returns true and a note for the loot master, or false and why not.
function Rolls.undo()
  local roll = Rolls.current
  if not roll or roll.state ~= "awarded" or not roll.winner then return false, "There's nothing given out to undo." end
  local player, kind = roll.winner, roll.winKind
  local s = session()
  unrecord(s, roll.id, player, roll.drop)
  local notes = {}
  -- a boosted win spent their points: they get them back
  if kind == "BR" then
    local spent = (roll.bp and roll.bp[R.key(player)]) or (roll.boosted and roll.boosted[R.key(player)]) or 0
    if LR.canEditBook() then
      LR.Guild.edit(function(book, now) return LR.Book.setPoints(book, player, spent, now) end)
      notes[#notes + 1] = ("%s gets their %d points back."):format(U.short(player), spent)
    else
      notes[#notes + 1] = ("Ask an officer to give %s their %d points back."):format(U.short(player), spent)
    end
  end
  local book = s and s.prio and LR.book and LR.book()
  if book and not roll.de and LR.Book.prio(book, roll.id) then
    notes[#notes + 1] = ("If %s came off its priority list, put them back on the Guild tab."):format(U.short(player))
  end
  -- did the item reach them already (master loot)? then they have it to trade on
  local d = s and roll.drop and S.drop(s, roll.drop)
  local theyHaveIt = d and d.h and U.samePlayer(d.h, player) and not U.samePlayer(player, U.me())
  if theyHaveIt then table.insert(notes, 1, ("%s has it already: they trade it to whoever gets it."):format(U.short(player))) end
  roll.state, roll.winner, roll.pick, roll.de, roll.winKind, roll.note = "closed", nil, nil, nil, nil, nil
  -- raiders' windows: "closed" again (older versions understand that); the leader takes the award off the list
  sendGroup({ t = "X", k = roll.k, id = roll.id, e = "closed" })
  sendGroup({ t = "X", k = roll.k, id = roll.id, e = "undone", p = player, sid = s and s.id, d = roll.drop })
  Rolls.ended(roll.k, "closed")
  say(("Undone: %s isn't %s's after all.%s"):format(roll.link, U.short(player),
    theyHaveIt and (" %s, please trade it to whoever gets it."):format(U.short(player)) or ""))
  toGuild(("Undone: %s isn't %s's after all."):format(roll.link, U.short(player)))
  changed()
  return true, #notes > 0 and table.concat(notes, " ") or nil
end

--- gives the item to the session's disenchanter
function Rolls.disenchant()
  local s = session()
  if not s or not s.de then return false, "Pick a disenchanter first (Session tab)." end
  return Rolls.award(s.de, nil, nil, true)
end

---------------------------------------------------------------------- following a roll (every raider)
--- a roll from the loot master (or our own): start or update our copy and show its window
function Rolls.follow(msg, sender)
  if type(msg.k) ~= "string" or type(msg.id) ~= "number" or type(msg.s) ~= "number" or type(msg.left) ~= "number" then return end
  if msg.m ~= "OPEN" and msg.m ~= "SR" and msg.m ~= "TIE" and msg.m ~= "PR" and msg.m ~= "BID" then return end
  local copy = Rolls.seen[msg.k]
  if not copy then
    local who = {}
    -- who may roll: names, or { name, reserves } on a reserved item
    if type(msg.w) == "table" then
      for i, w in ipairs(msg.w) do
        if i > 40 then break end
        if type(w) == "string" then who[#who + 1] = w
        elseif type(w) == "table" and type(w[1]) == "string" then who[#who + 1] = { w[1], tonumber(w[2]) or 1 } end
      end
    end
    -- +1s: names -> counts, checked
    local po
    if type(msg.po) == "table" then
      po = {}
      local n = 0
      for name, c in pairs(msg.po) do
        n = n + 1
        if n > 80 then break end
        if type(name) == "string" and type(c) == "number" and c > 0 and c < 100 then po[name:lower()] = math.floor(c) end
      end
    end
    local bp
    if type(msg.bp) == "table" then
      bp = {}
      local n = 0
      for name, c in pairs(msg.bp) do
        n = n + 1
        if n > 80 then break end
        if type(name) == "string" and type(c) == "number" and c > 0 and c <= LR.Book.MAX_POINTS then bp[name:lower()] = math.floor(c) end
      end
    end
    local bid = msg.m == "BID"
    local xk = R.checkKinds(msg.xk)
    local tie = msg.tie ~= "BID" and (R.KINDS[msg.tie] or R.extra({ xk = xk }, msg.tie)) and msg.tie or (msg.m == "TIE" and "MS" or nil)
    copy = R.new(msg.k, msg.id, { mode = msg.m, who = who, po = po, bp = bp, xk = xk, tie = tie,
      n = msg.m == "PR" and tonumber(msg.pn) or nil,
      min = bid and math.max(0, math.min(R.MAX_BID, tonumber(msg.mn) or 0)) or nil, inc = bid and math.max(1, math.min(R.MAX_BID, tonumber(msg.inc) or 1)) or nil,
      strict = bid and msg.sb == true or nil })
    copy.by = sender
    copy.note = LR.Notes.clean(msg.nt)
    -- who has it on their wishlist: { { p, n } }, checked
    if type(msg.wl) == "table" then
      local wish = {}
      for i, e in ipairs(msg.wl) do
        if i > 10 then break end
        if type(e) == "table" and type(e.p) == "string" and #e.p <= 40 and not e.p:find("|", 1, true) and type(e.n) == "number" then
          wish[#wish + 1] = { p = e.p, n = math.max(1, math.floor(e.n)) }
        end
      end
      copy.wish = #wish > 0 and wish or nil
    end
    copy.link = type(msg.l) == "string" and msg.l or LR.itemLink(msg.id)
    copy.state = "open"
    Rolls.seen[msg.k] = copy
    table.insert(Rolls.order, msg.k)
    -- a tie roll is only for the players who tied
    if copy.mode == "TIE" and not R.inList(copy.who, U.me()) then copy.hidden = true end
  end
  -- an auction: the highest bid so far (we may have missed some)
  if copy.mode == "BID" and type(msg.tb) == "table" and type(msg.tb[1]) == "string" and tonumber(msg.tb[2]) then
    local g = math.floor(tonumber(msg.tb[2]))
    if not copy.top or copy.top.n < g then R.bid(copy, msg.tb[1], g) end
  end
  copy.secs = math.min(120, math.max(1, msg.s))
  copy.ends = now() + math.min(120, math.max(0, msg.left))
  copy.state = "open"
  copy.seenAt = now()
  if not copy.hidden and not copy.gearSent then Rolls.sendGear(copy) end
  if not copy.hidden and LR.UI and LR.UI.rollWindow then LR.UI.rollWindow(copy) end
  if not copy.hidden and LR.AutoRoll then LR.AutoRoll.consider(copy) end      -- my own rules (Core/AutoRoll.lua)
  LR.changed("rolls")
end

---------------------------------------------------------------------- what everyone has on now (gear comparison)
--- what I wear where an item goes (links; none for an empty slot), for my window and for the loot master's: sent once
--- per roll, by whisper (Settings: shareGear). Not for an auction (gold decides).
function Rolls.sendGear(copy)
  copy.gearSent = true
  if copy.mode == "BID" or copy.test then return end
  local links = {}
  for _, slot in ipairs(LR.wornIn(copy.id)) do
    local l = GetInventoryItemLink("player", slot)
    if l then links[#links + 1] = l end
  end
  copy.mine = #links > 0 and links or nil
  if #links == 0 or not LR.db.settings.shareGear then return end
  local mine = Rolls.current
  if mine and mine.k == copy.k then mine.gear = mine.gear or {} mine.gear[R.key(U.me())] = links return end
  if copy.by and not U.samePlayer(copy.by, U.me()) then Net.send({ t = "W", k = copy.k, e = links }, "WHISPER", copy.by) end
end

-- what a roller wears there, at the loot master's (from their addon)
Net.handlers.W = function(msg, channel, sender)
  local roll = Rolls.current
  if not roll or roll.k ~= msg.k or type(msg.e) ~= "table" or not LR.inGroup(sender) then return end
  local links = {}
  for i, l in ipairs(msg.e) do
    if i > 2 then break end
    if type(l) == "string" and #l <= 200 and l:find("|Hitem:%d+") then links[#links + 1] = l end
  end
  roll.gear = roll.gear or {}
  roll.gear[R.key(sender)] = #links > 0 and links or nil
  changed()
end

---------------------------------------------------------------------- Gargul's rolls (read from raid chat)
--- Gargul started rolling an item out (its line in raid chat, Core/Gargul.lua): a roll window like ours, unless my
--- own Gargul is loaded (it shows its own) or that's switched off (Settings: gargulWindows). Its dice and coin just
--- /roll, which Gargul counts; who gets it is Gargul's call. The reserves are this session's (the leader sends the
--- same to Gargul). test: a pretend one (the Test tab), always shown, rolled here. Returns the copy.
function Rolls.followGargul(id, link, secs, sender, test)
  local s = session()
  local plan = s and R.plan(s, id, LR.roster()) or { mode = "OPEN" }
  if plan.mode ~= "SR" then plan = { mode = "OPEN", away = plan.away } end
  local k = "gargul:" .. id .. ":" .. now()
  local copy = R.new(k, id, plan)
  copy.by, copy.link, copy.gargul, copy.test = sender, link or LR.itemLink(id), true, test
  copy.secs = math.max(1, math.min(120, secs or 60))
  copy.ends = now() + copy.secs
  copy.state = "open"
  local own = type(_G.Gargul) == "table"
  if not test and (own or not LR.db.settings.gargulWindows) then copy.hidden = true end
  Rolls.seen[k] = copy
  table.insert(Rolls.order, k)
  Rolls.lastGargul = copy
  if not copy.hidden and LR.UI and LR.UI.rollWindow then LR.UI.rollWindow(copy)
  elseif LR.UI and LR.UI.reservedAlert then LR.UI.reservedAlert(copy) end      -- (no window: still told it's mine)
  LR.changed("rolls")
  return copy
end
--- Gargul's roll is over: closed, or given to someone (winner); id: the item, when the line says
function Rolls.gargulEnded(id, winner)
  local copy = Rolls.lastGargul
  if not copy or (id and copy.id ~= id) then return end
  if winner then Rolls.ended(copy.k, "awarded", U.full(winner))
  elseif copy.state == "open" then Rolls.ended(copy.k, "closed") end
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
  local a, b = R.kind(copy, kind)
  if not a or kind == "BID" or copy.state ~= "open" then return false end
  -- a pretend roll (the Test tab): rolled here, nobody else sees it
  if copy.test then
    local lo, hi = a, b
    if kind == "BR" then lo, hi = R.boostRange(copy, U.me()) end
    if not lo then return false end
    R.add(copy, U.me(), math.random(lo, hi), lo, hi)
    copy.myRoll = kind
    LR.changed("rolls")
    return true
  end
  if kind == "BR" then
    local lo, hi = R.boostRange(copy, U.me())
    if not lo then return false end
    RandomRoll(lo, hi)
    copy.myRoll = kind
    return true
  end
  RandomRoll(a, b)
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
  if roll and (roll.state == "open" or (roll.state == "closed" and roll.closedAt and t - roll.closedAt <= LATE)) and roll.mode ~= "HR" and roll.mode ~= "BID" then
    if LR.inGroup(name) or not IsInGroup() then
      R.add(roll, name, n, lo, hi, roll.state ~= "open")
      changed()
    end
  end
  for _, k in ipairs(Rolls.order) do
    local copy = Rolls.seen[k]
    if copy and copy.state == "open" and copy.mode ~= "BID" then R.add(copy, name, n, lo, hi, false) end
  end
  LR.changed("rolls")
end

---------------------------------------------------------------------- auctions: max bids
--- the loot master's addon bids for players with a max, as little as it takes (R.resolve); the raid hears
--- where it ended up, and everyone's windows get the highest bid
local function autoBids(roll)
  if not roll.maxes or not next(roll.maxes) then return end
  local made = R.resolve(roll, roll.maxes)
  if #made == 0 then return end
  local t = now()
  if roll.ends - t < SNIPE then roll.ends = t + SNIPE end
  local top = roll.top
  say(("Highest bid: %s, %s (bid for them by their max bid). Type a higher bid to beat it."):format(U.short(top.p), LR.Gdkp.gold(top.n)))
  sendGroup(wire(roll))
  Rolls.follow(wire(roll), U.me())
  changed()
end

--- a player's max bid on the auction that's on (the loot master's addon); returns true, or false and why
function Rolls.setMax(player, g)
  local roll = Rolls.current
  g = math.floor(tonumber(g) or 0)
  if not (roll and roll.mode == "BID" and roll.state == "open") then return false, "Nothing is being auctioned right now." end
  if g < R.nextBid(roll) then return false, ("A max bid has to be at least the lowest bid now, %s."):format(LR.Gdkp.gold(R.nextBid(roll))) end
  if g > R.MAX_BID then return false, "That's more gold than there is." end
  roll.maxes = roll.maxes or {}
  local k = R.key(player)
  if roll.maxes[k] and roll.maxes[k].g >= g then return false, ("Your max bid is %s already: it can only go up."):format(LR.Gdkp.gold(roll.maxes[k].g)) end
  roll.maxes[k] = { p = U.full(player), g = g, at = (roll.maxes[k] and roll.maxes[k].at) or now() }
  autoBids(roll)
  return true
end

--- my max bid on an auction (my window, /lr max): to the loot master's addon, or my own
function Rolls.myMax(copy, g)
  g = math.floor(tonumber(g) or 0)
  if not copy or copy.mode ~= "BID" or copy.state ~= "open" then return false, "Nothing is being auctioned right now." end
  copy.myMax = g
  if U.samePlayer(copy.by, U.me()) then
    local ok, why = Rolls.setMax(U.me(), g)
    if not ok then copy.myMax = nil end
    return ok, why
  end
  Net.send({ t = "M", k = copy.k, g = g }, "WHISPER", copy.by)
  LR.changed("rolls")
  return true
end

--- the auction that's open (my copy), if any
function Rolls.openAuction()
  for i = #Rolls.order, 1, -1 do
    local c = Rolls.seen[Rolls.order[i]]
    if c and c.mode == "BID" and c.state == "open" then return c end
  end
end

---------------------------------------------------------------------- auctions: bids typed in raid chat
--- a bid from a player (raid chat, or a whisper): counted in the loot master's auction and everyone's copies.
--- Returns the loot master's entry (nil when there's no auction of ours).
function Rolls.onBid(sender, g)
  local t = now()
  local roll = Rolls.current
  local entry
  if roll and roll.mode == "BID" and (roll.state == "open" or (roll.state == "closed" and roll.closedAt and t - roll.closedAt <= LEEWAY)) then
    if LR.inGroup(sender) or not IsInGroup() then
      entry = R.bid(roll, sender, g, roll.state ~= "open")
      if entry.kind then
        -- a bid at the last moment: everyone gets a few seconds to answer it
        if roll.ends - t < SNIPE then
          roll.ends = t + SNIPE
          roll.warned = roll.secs < 10 or false
          sendGroup(wire(roll))
        end
        autoBids(roll)                        -- anyone's max bid answers it
      elseif entry.why == "low" and not U.samePlayer(sender, U.me()) then
        LR.say(("%s The lowest bid now is %s."):format(LR.TAG, LR.Gdkp.gold(R.nextBid(roll))), "WHISPER", sender)
      end
      changed()
    end
  end
  for _, k in ipairs(Rolls.order) do
    local copy = Rolls.seen[k]
    if copy and copy.state == "open" and copy.mode == "BID" then
      local e = R.bid(copy, sender, g)
      if e.kind and copy.ends and copy.ends - t < SNIPE then copy.ends = t + SNIPE end
    end
  end
  LR.changed("rolls")
  return entry
end

--- a line in raid or party chat: a bid, when it's just an amount and an auction is open
function Rolls.onChat(text, sender)
  if not sender or sender == "" then return end
  local open = Rolls.current and Rolls.current.mode == "BID" and Rolls.current
  if not open then
    for _, k in ipairs(Rolls.order) do local c = Rolls.seen[k] if c and c.mode == "BID" and c.state == "open" then open = c break end end
  end
  if not open then return end
  local g = R.parseBid(text, open.strict)
  if g then Rolls.onBid(U.full(sender), g) end
end

--- I bid (the roll window's buttons): an amount in raid chat, like anyone without the addon
function Rolls.bid(copy, g)
  if copy.mode ~= "BID" or copy.state ~= "open" then return false end
  local ch = LR.groupChannel()
  if not ch then Rolls.onBid(U.me(), g) return true end
  LR.say((copy.strict and "bid " or "") .. math.floor(g), ch)
  return true
end

---------------------------------------------------------------------- the queue: one item after another
--- items to roll out (or auction) one after another: { { id, link, slot, drop } }
function Rolls.enqueue(items)
  for _, it in ipairs(items) do
    local dup = false
    for _, q in ipairs(Rolls.queue) do if (it.drop and q.drop == it.drop) or (it.slot and q.slot == it.slot and q.id == it.id) then dup = true end end
    if not dup and #Rolls.queue < 40 then Rolls.queue[#Rolls.queue + 1] = it end
  end
  if not Rolls.current then Rolls.queueNext() end
  changed()
end

--- starts the next item in the queue, when nothing is being rolled for
function Rolls.queueNext()
  while #Rolls.queue > 0 and not Rolls.current do
    local it = table.remove(Rolls.queue, 1)
    -- (an item already given out, or gone from the loot window, is skipped)
    local s = session()
    local gone = it.drop and s and S.dropWin(s, it.drop)
    if not gone then
      local ok, why = Rolls.start(it.id, { link = it.link, slot = it.slot, drop = it.drop })
      if not ok then LR.print(("couldn't start %s: %s"):format(it.link or LR.itemLink(it.id), why or "?")) end
      -- a hard reserved item doesn't wait for anyone: it waits for the loot master
    end
  end
  changed()
end

function Rolls.clearQueue() Rolls.queue = {} changed() end

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
  local kind = R.KINDS[msg.kd] and msg.kd or (msg.kd == "HR" and "HR" or nil)      -- (BID: a sale)
  if copy and U.samePlayer(copy.by, sender) and (msg.e == "closed" or msg.e == "cancelled" or msg.e == "awarded") then
    Rolls.ended(msg.k, msg.e, winner, tonumber(msg.n), kind)
  end
  -- the leader of the soft reserves records loot given out by the loot master (and takes back one that's undone)
  if msg.e == "awarded" and winner and kind and fromLooter(sender) then
    local s = msg.sid and LR.session(msg.sid) or session()
    local id = copy and copy.id or tonumber(msg.id)
    local xn = type(msg.xn) == "string" and msg.xn:gsub("[|%c]", ""):sub(1, R.EXTRA_NAME) or nil
    if s and id and LR.isLeader(s) then record(s, id, winner, kind, msg.n, type(msg.d) == "string" and msg.d or nil, msg.de == true, xn) end
  elseif msg.e == "undone" and winner and fromLooter(sender) and not U.samePlayer(sender, U.me()) then
    local s = msg.sid and LR.session(msg.sid) or session()
    local id = copy and copy.id or tonumber(msg.id)
    if id then unrecord(s, id, winner, type(msg.d) == "string" and msg.d or nil) end
  end
end

Net.handlers.M = function(msg, channel, sender)
  local roll = Rolls.current
  if channel ~= "WHISPER" or not roll or roll.k ~= msg.k or type(msg.g) ~= "number" then return end
  if not (LR.inGroup(sender) or not IsInGroup()) then return end
  local ok, why = Rolls.setMax(sender, msg.g)
  -- (said by whisper, so it reaches them whatever version they have)
  LR.say(LR.TAG .. " " .. (ok and ("Your max bid of %s on %s is in."):format(LR.Gdkp.gold(msg.g), U.plain(roll.link)) or why), "WHISPER", sender)
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
for _, e in ipairs({ "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" }) do
  events:RegisterEvent(e)
end
events:RegisterEvent("LOOT_OPENED")
events:RegisterEvent("LOOT_CLOSED")
events:RegisterEvent("LOOT_SLOT_CLEARED")
events:SetScript("OnEvent", function(_, event, ...)
  if event == "CHAT_MSG_SYSTEM" then
    local ok, err = pcall(Rolls.onRoll, ...)
    if not ok then geterrorhandler()(err) end
  elseif event:find("^CHAT_MSG_RAID") or event:find("^CHAT_MSG_PARTY") then
    local text, sender = ...
    local ok, err = pcall(Rolls.onChat, text, sender)
    if not ok then geterrorhandler()(err) end
  elseif event == "LOOT_OPENED" then
    Rolls.lootOpen = true
    local ok, err = pcall(LR.Drops.lootOpened)            -- the raid's loot list (Core/Drops.lua)
    if not ok then geterrorhandler()(err) end
    ok, err = pcall(LR.AutoLoot.apply)                    -- the loot master's rules (Core/AutoLoot.lua)
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
