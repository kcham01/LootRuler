-- The practice raid (the Test tab): a pretend raid run alone, on LootRuler's real rules and screens. Made-up
-- players count as being in the group: they reserve by whisper and in raid chat, roll, pass and bid, through the
-- same code real players' messages go through (Whisper.handle, Rolls.onRoll, Rolls.onChat, the pass message).
-- Nothing leaves this screen: while it's on, chat lines are shown here instead of said (LR.say), addon messages
-- aren't sent (Net.send), the guild book is a copy that's thrown away, and the session is never kept under past
-- raids or past a reload. It only runs out of a group: joining one ends it.
local _, LR = ...
local U, S, R = LR.U, LR.Session, LR.Roll

local P = LR.Practice           -- (Init.lua makes it, off, so earlier files can ask)
P.players, P.byKey = {}, {}

-- the made-up players (also the Test tab's pretend roll windows)
P.PEOPLE = { { "Arthas", "PALADIN" }, { "Jaina", "MAGE" }, { "Thrall", "SHAMAN" }, { "Sylvanas", "HUNTER" }, { "Øyvind", "WARRIOR" },
  { "Valeera", "ROGUE" }, { "Malfurion", "DRUID" }, { "Anduin", "PRIEST" }, { "Kael", "WARLOCK" }, { "Tyrande", "PRIEST" },
  { "Muradin", "WARRIOR" }, { "Alleria", "HUNTER" } }
P.MIN, P.MAX = 3, #P.PEOPLE

local gen = 0                 -- bumped when practice ends, so timers from it do nothing
local reacted = {}            -- roll key -> true: the pretend players have answered it

--- runs fn after a while, unless practice has ended (or started again) since
local function after(secs, fn)
  local mine = gen
  C_Timer.After(secs, function() if P.on and gen == mine then fn() end end)
end

---------------------------------------------------------------------- what the raid would hear
local WHERE = { RAID = "raid", RAID_WARNING = "raid warning", PARTY = "party", GUILD = "guild", INSTANCE_CHAT = "raid" }

--- a line LootRuler would have said: shown here instead (LR.say)
local GROUP = { RAID = true, RAID_WARNING = true, PARTY = true, INSTANCE_CHAT = true }
local echoing = false
function P.show(text, channel, target)
  local where = channel == "WHISPER" and ("whisper to " .. U.short(target or "?")) or (WHERE[channel] or tostring(channel):lower())
  print(("|cff66bbffPractice|r |cff9d9d9d(%s)|r %s"):format(where, text))
  -- in a raid the game shows me my own raid lines, and LootRuler reads them like anyone's: a bid I clicked or typed
  -- counts, and so does an "!lr" line. Out of a group the game says nothing, so the practice raid does it.
  if GROUP[channel] and not echoing then
    echoing = true
    local ok, err = pcall(function()
      if LR.Whisper.isCommand(text) then
        if LR.db.settings.raidCommands then LR.Whisper.handle(text, U.me()) end
      else
        LR.Rolls.onChat(text, U.me())
      end
    end)
    echoing = false
    if not ok then geterrorhandler()(err) end
  end
end

--- a line I type for the practice raid's raid chat (/lr say): the game won't send raid chat out of a group
function P.say(text)
  text = U.trim(tostring(text or ""))
  if not P.on then return false, "/lr say is for a practice raid: in a real one, type in raid chat." end
  if text == "" then return false, "/lr say [what you'd type in raid chat], like \"/lr say 300\" to bid." end
  LR.say(text, "RAID")
  return true
end
--- what a pretend player says or does, as it would look in chat: "Jaina whispers: ...", "Jaina (raid): ..."
local function heard(player, text, how)
  print(("|cff66bbffPractice|r %s %s %s"):format(U.short(player.name), how, text))
end

---------------------------------------------------------------------- who's here
function P.isPretend(name) return P.on and name ~= nil and P.byKey[R.key(name)] ~= nil end
--- the pretend players as group members (LR.roster adds them)
function P.roster()
  local out = {}
  for _, x in ipairs(P.players) do out[#out + 1] = { name = x.name, class = x.class, online = true, leader = false, assist = false } end
  return out
end

--- whether a practice raid can start now; false and why when it can't
function P.canStart()
  if P.on then return false, "A practice raid is on already." end
  if IsInGroup() then return false, "Leave your group first: a practice raid only runs on your own." end
  local cur = LR.Rolls.current
  if cur and cur.state == "open" then return false, "Finish the roll for " .. U.plain(cur.link) .. " first." end
  return true
end

--- starts a practice raid. opts: { raid = key, players = how many, sr = reserves each }. Returns the session.
function P.start(opts)
  local ok, why = P.canStart()
  if not ok then return nil, why end
  opts = opts or {}
  local raid = LR.raid(opts.raid) and opts.raid or "Karazhan"
  P.prev = LR.db.current
  P.players, P.byKey = {}, {}
  for i = 1, math.max(P.MIN, math.min(opts.players or 8, P.MAX)) do
    local x = { name = U.full(P.PEOPLE[i][1]), class = P.PEOPLE[i][2] }
    P.players[i] = x
    P.byKey[R.key(x.name)] = x
  end
  -- the guild book: a copy to try priority lists and boosted rolls on, thrown away at the end
  local g = LR.guildName and LR.guildName()
  P.book = g and LR.db.guilds and LR.db.guilds[g] and U.copy(LR.db.guilds[g]) or nil
  gen = gen + 1
  reacted = {}
  P.on = true
  P.tie = false
  local s = LR.startSession(raid, math.max(1, math.min(opts.sr or 2, S.MAX_SR)), true, false)
  s.practice = true
  P.sid = s.id
  LR.print(("a practice raid of %s with %s. Nothing you do leaves your screen. End it on the Test tab."):format(
    LR.raidOf(s).name, U.plural(#P.players, "pretend player")))
  LR.changed("roster")
  LR.changed("session")
  return s
end

--- ends the practice raid: its session, rolls and guild book copy are forgotten. why: said in chat (optional)
function P.stop(why)
  if not P.on then return false end
  local Rolls = LR.Rolls
  local roll = Rolls.current
  if roll and roll.practice then
    if roll.state == "open" then Rolls.cancel() end
    Rolls.current = nil
  end
  for i = #Rolls.order, 1, -1 do
    local k = Rolls.order[i]
    local copy = Rolls.seen[k]
    if copy and copy.practice then Rolls.seen[k] = nil table.remove(Rolls.order, i) end
  end
  local batch = LR.Batch.current
  if batch and batch.practice then
    if batch.state == "open" then LR.Batch.cancel() end
    LR.Batch.current = nil
    LR.Batch.seen[batch.k] = nil
    for i = #LR.Batch.order, 1, -1 do if LR.Batch.order[i] == batch.k then table.remove(LR.Batch.order, i) end end
    LR.changed("batch")
  end
  if P.sid then
    LR.db.sessions[P.sid] = nil
    LR.db.mine[P.sid] = nil
    if LR.db.current == P.sid then LR.db.current = P.prev and LR.db.sessions[P.prev] and P.prev or nil end
  end
  P.on, P.sid, P.prev, P.book, P.tie = false, nil, nil, nil, false
  P.players, P.byKey = {}, {}
  gen = gen + 1
  reacted = {}
  LR.print(why or "the practice raid is over: it's forgotten.")
  if LR.UI and LR.UI.rollWindows then LR.UI.rollWindows() end
  LR.changed("roster")
  LR.changed("session")
  LR.changed("rolls")
  return true
end

--- the practice raid's session (nil when none)
function P.session() return P.on and P.sid and LR.db.sessions[P.sid] or nil end

---------------------------------------------------------------------- the pretend players
--- a pretend player whispers me (Core/Whisper.lua answers, as it would anyone)
function P.whisper(player, text)
  heard(player, text, "whispers:")
  LR.Whisper.handle(text, player.name)
end
--- a pretend player types in raid chat: "!lr" lines (when that's on) and bids
function P.raidSay(player, text)
  heard(player, text, "(raid):")
  if LR.Whisper.isCommand(text) then
    if LR.db.settings.raidCommands then LR.Whisper.handle(text, player.name) end
    return
  end
  LR.Rolls.onChat(text, player.name)
end
--- a pretend player rolls (the game's own roll line, read like any other)
function P.roll(player, n, lo, hi)
  local line = RANDOM_ROLL_RESULT:format(U.short(player.name), n, lo, hi)
  print(("|cff66bbffPractice|r |cffffff00%s|r"):format(line))
  LR.Rolls.onRoll(line)
end

local function pick(list) return list[math.random(1, #list)] end
local function shuffled(list)
  local out = U.copy(list)
  for i = #out, 2, -1 do local j = math.random(1, i) out[i], out[j] = out[j], out[i] end
  return out
end

--- everyone reserves what they still can: some by whisper, some in raid chat, a few seconds apart
function P.reserve()
  local s = P.session()
  if not s then return 0 end
  local raid = LR.raidOf(s)
  local items = {}
  for _, id in ipairs(raid.order or {}) do if not s.hr[id] then items[#items + 1] = id end end
  if #items == 0 then return 0 end
  -- a handful of items most people want, so reserved rolls have a few players in them
  local popular = {}
  for i = 1, math.min(4, #items) do popular[i] = items[math.random(1, #items)] end
  local n = 0
  for i, x in ipairs(P.players) do
    local left = S.limit(s, x.name) - #S.reservesOf(s, x.name)
    for j = 1, left do
      local id = (math.random() < 0.6) and pick(popular) or pick(items)
      local text = "!lr " .. LR.itemLink(id)
      n = n + 1
      after(0.4 * n, function()
        if math.random() < 0.5 and LR.db.settings.raidCommands then P.raidSay(x, text) else P.whisper(x, text) end
      end)
      if j == 1 and i == 2 then after(0.4 * n + 0.2, function() P.whisper(x, "!lr") end) end
    end
  end
  return n
end

--- a boss drops loot: some of its items (one or two of them reserved, when anyone did) go into my bags,
--- as if I'd looted them, and the raid hears what dropped. Returns the drops.
function P.drop(count)
  local s = P.session()
  if not s then return {} end
  local raid = LR.raidOf(s)
  -- a boss with something reserved, when there is one (that's what there's most to try with)
  local wanted = {}
  for _, b in ipairs(raid.bosses or {}) do
    for _, id in ipairs(b.items) do if S.byItem(s)[id] then wanted[#wanted + 1] = b break end end
  end
  local boss = (#wanted > 0 and pick(wanted)) or (raid.bosses and #raid.bosses > 0 and pick(raid.bosses)) or nil
  local pool = boss and U.copy(boss.items) or U.copy(raid.order or {})
  if #pool == 0 then pool = { 28830 } end
  local reserved = {}
  for id in pairs(S.byItem(s)) do if not boss or U.indexOf(boss.items, id) then reserved[#reserved + 1] = id end end
  local ids = {}
  for _, id in ipairs(shuffled(reserved)) do if #ids < 2 then ids[#ids + 1] = id end end
  for _, id in ipairs(shuffled(pool)) do if #ids < (count or 3) and not U.indexOf(ids, id) then ids[#ids + 1] = id end end
  local now = U.now()
  local list = {}
  for _, id in ipairs(ids) do
    local d = { k = LR.Drops.newKey(id), i = id, b = boss and boss.name or "", at = now, by = U.me(), src = "practice", h = U.me(), ht = now }
    if S.addDrop(s, d, now) then
      list[#list + 1] = { k = d.k, i = id, q = LR.quality(id), link = LR.itemLink(id) }
    end
  end
  LR.Drops.announce(s, list)
  LR.leaderChanged(s)
  return list
end

--- the next drop still to give out (for "Roll out the next item")
function P.nextDrop()
  local s = P.session()
  if not s then return nil end
  for _, d in ipairs(s.drops or {}) do
    local st = S.dropState(s, d)
    if st ~= "given" and st ~= "toTrade" and not S.dropWin(s, d.k) then return d end
  end
end

--- rolls the next drop out
function P.rollNext()
  local d = P.nextDrop()
  if not d then return nil, "Nothing left to give out: have a boss drop loot first." end
  return LR.Rolls.start(d.i, { drop = d.k, link = LR.itemLink(d.i) })
end

-- who may roll in a roll, of the pretend players
local function rollers(roll)
  if roll.mode == "HR" then return {} end
  if roll.mode == "OPEN" then return U.copy(P.players) end
  local out = {}
  for _, w in ipairs(roll.who or {}) do
    local x = P.byKey[R.key(type(w) == "table" and w[1] or w)]
    if x then out[#out + 1] = x end
  end
  return out
end

-- the kind a pretend player rolls: their reserve, a tie's kind, boosted when they have points, mostly main spec.
-- plain: no boosted or off spec rolls (a tie asked for: it's between two plain rolls of the best kind)
local function kindFor(roll, x, plain)
  if roll.mode == "SR" then return "SR" end
  if roll.mode == "TIE" then return roll.tie or "MS" end
  if roll.mode == "PR" or plain then return "MS" end
  if roll.bp and roll.bp[R.key(x.name)] and math.random() < 0.7 then return "BR" end
  local r = math.random()
  if roll.xk and #roll.xk > 0 and r < 0.15 then return "X" .. math.random(1, #roll.xk) end
  return r < 0.7 and "MS" or "OS"
end

-- answers a roll: on one open to everyone some pass; the rest roll within the time (a tie, when asked for,
-- between the first two)
local function answerRoll(roll)
  local who = shuffled(rollers(roll))
  local window = math.max(2, math.min((roll.secs or 20) - 4, 10))
  local tie = P.tie and #who >= 2 and roll.mode ~= "TIE"
  if tie then P.tie = false end            -- (kept for the next roll when this one can't tie: one roller)
  local tiedAt
  for i, x in ipairs(who) do
    local wait = 0.5 + math.random() * window
    if not tie and roll.mode == "OPEN" and math.random() < 0.15 then      -- (who reserved it, rolls for it)
      after(wait, function()
        if roll.state == "open" then
          LR.Net.handlers.N({ t = "N", k = roll.k }, "WHISPER", x.name)
          heard(x, "on " .. U.plain(roll.link or "?"), "passes")
        end
      end)
    else
      local kind = kindFor(roll, x, tie)
      local lo, hi
      if kind == "BR" then lo, hi = R.boostRange(roll, x.name) else lo, hi = R.kind(roll, kind) end
      if lo then
        local n = math.random(lo, hi)
        if tie and i <= 2 then
          tiedAt = tiedAt or hi
          n = tiedAt
          wait = 0.5 + i
        elseif tie then
          n = math.random(lo, math.max(lo, hi - 1))
        end
        after(wait, function() if roll.state == "open" then P.roll(x, n, lo, hi) end end)
      end
    end
  end
end

-- a loot council: the pretend players on it vote, once the rolls are in, for one of the best few
local function councilVotes(roll, wait)
  local s = P.session()
  if not (s and LR.Council.on(s)) then return end
  for _, x in ipairs(P.players) do
    if LR.Council.isMember(s, x.name) then
      after(wait + 1 + math.random() * 3, function()
        if not LR.Council.votable(roll) then return end
        local good = R.standings(roll)
        if #good == 0 then return end
        local e = good[math.random(1, math.min(3, #good))]
        heard(x, "for " .. U.short(e.p), "votes")
        LR.Council.vote(x.name, e.p)
      end)
    end
  end
end

-- answers an auction: a few bidders, each with a limit of their own; one of them sets a max bid by whisper.
-- They bid against each other, a few seconds apart, until nobody will go higher or it closes.
local function answerAuction(roll)
  local bidders = {}
  for i, x in ipairs(shuffled(P.players)) do
    if i > 4 then break end
    local min = roll.min or 1
    bidders[#bidders + 1] = { x = x, cap = math.floor(min * (1.5 + math.random() * 4)) }
  end
  if #bidders == 0 then return end
  local s = P.session()
  -- one of them bids ahead on something coming up after this (by whisper, as a player without the addon would)
  local nextUp = LR.Rolls.queue[1]
  if nextUp and s and s.gk then
    local x = pick(P.players)
    local g = math.floor(LR.Gdkp.minFor(s, nextUp.id) * (2 + math.random() * 2))
    after(1 + math.random() * 2, function() P.whisper(x, ("!lr bid %d %s"):format(g, LR.itemLink(nextUp.id))) end)
  end
  local maxer = #bidders >= 3 and bidders[#bidders] or nil
  if maxer then
    table.remove(bidders)
    after(1.5, function() if roll.state == "open" then P.whisper(maxer.x, "!lr max " .. maxer.cap) end end)
  end
  local function step()
    if roll.state ~= "open" then return end
    local need = R.nextBid(roll)
    local can = {}
    for _, b in ipairs(bidders) do
      if b.cap >= need and not (roll.top and U.samePlayer(roll.top.p, b.x.name)) then can[#can + 1] = b end
    end
    if #can == 0 then return end
    local b = pick(can)
    -- (some raise by a step or two, some jump a fifth, so a practice auction doesn't drag on)
    local jump = math.random() < 0.3 and math.floor(need * 0.2) or (roll.inc or 1) * math.random(0, 2)
    local g = math.min(b.cap, need + jump)
    P.raidSay(b.x, (s and s.gk and s.gk.strict) and ("bid " .. g) or tostring(g))
    after(1.5 + math.random() * 2.5, step)
  end
  after(2 + math.random() * 2, step)
end

-- answers several auctions at once: a few bidders with limits of their own on each item, bidding by number in raid
-- chat ("#2 300"), one item and one bidder at a time, a few seconds apart, until nobody will go higher or it ends
local function answerBatch(batch)
  local caps = {}                     -- item number -> { { x, cap } }
  for _, item in ipairs(batch.items) do
    caps[item.n] = {}
    for i, x in ipairs(shuffled(P.players)) do
      if i > 3 then break end
      table.insert(caps[item.n], { x = x, cap = math.floor((item.min or 1) * (1.5 + math.random() * 3)) })
    end
  end
  local function step()
    if batch.state ~= "open" then return end
    local can = {}
    for _, item in ipairs(batch.items) do
      local need = R.nextBid(item)
      for _, b in ipairs(caps[item.n]) do
        if b.cap >= need and not (item.top and U.samePlayer(item.top.p, b.x.name)) then can[#can + 1] = { item = item, b = b, need = need } end
      end
    end
    if #can == 0 then return end
    local c = pick(can)
    local jump = math.random() < 0.3 and math.floor(c.need * 0.2) or (c.item.inc or 1) * math.random(0, 2)
    P.raidSay(c.b.x, LR.Batch.bidText(c.item.n, math.min(c.b.cap, c.need + jump), batch.strict))
    after(1 + math.random() * 2, step)
  end
  after(2 + math.random() * 2, step)
end

-- items for each character slot, from the loot lists (made once, the first time a practice raid shows its gear)
local bySlot
local function itemsBySlot()
  if bySlot then return bySlot end
  bySlot = {}
  for id in pairs(LR.ITEMS or {}) do
    for _, slot in ipairs(LR.wornIn(id)) do
      bySlot[slot] = bySlot[slot] or {}
      table.insert(bySlot[slot], id)
    end
  end
  for _, list in pairs(bySlot) do table.sort(list) end
  return bySlot
end

--- the pretend players answer "what do you wear?" with made-up gear from the loot lists, a moment apart
function P.answerGear()
  local slots = itemsBySlot()
  for i, x in ipairs(P.players) do
    after(0.3 + 0.2 * i, function()
      local e = {}
      for _, slot in ipairs(LR.Overview.SLOTS) do
        local list = slots[slot]
        if list and #list > 0 and math.random() < 0.95 then e[slot] = LR.itemLink(pick(list)) end
      end
      heard(x, "their gear", "sent")
      LR.Overview.got(x.name, (LR.Overview.clean(e)), "addon")
    end)
  end
end

--- the pretend players answer a bag check, a moment apart: mostly a few of each, now and then none
function P.answerBags(check)
  for i, x in ipairs(P.players) do
    after(0.3 + 0.2 * i, function()
      local c = {}
      for _, id in ipairs(check.ids) do c[id] = math.random() < 0.2 and 0 or math.random(1, 5) end
      heard(x, "the bag check", "answered")
      LR.Bags.answered(check, x.name, c)
    end)
  end
end

--- the pretend players answer a roll or auction that's just started
function P.react()
  local roll = LR.Rolls.current
  if not (P.on and roll and roll.state == "open") or reacted[roll.k] then return end
  reacted[roll.k] = true
  roll.practice = true
  local copy = LR.Rolls.seen[roll.k]
  if copy then copy.practice = true end
  if roll.mode == "BID" then answerAuction(roll) else
    answerRoll(roll)
    councilVotes(roll, math.max(2, math.min((roll.secs or 20) - 4, 10)))
  end
end

-- reserves locked: one pretend player asks to swap a reserve, by whisper, as a player without the addon would
local swapAsked
LR.onChange(function(what)
  local s = what == "session" and P.session()
  if not s then return end
  if not s.locked then swapAsked = nil return end
  if swapAsked == s.id then return end
  swapAsked = s.id
  for _, x in ipairs(shuffled(P.players)) do
    local mine = S.reservesOf(s, x.name)
    if #mine > 0 then
      local items = {}
      for _, id in ipairs(LR.raidOf(s).order or {}) do if not s.hr[id] and not U.indexOf(mine, id) then items[#items + 1] = id end end
      if #items > 0 then
        local text = ("!lr swap %s %s"):format(LR.itemLink(mine[1]), LR.itemLink(pick(items)))
        after(1.5, function() P.whisper(x, text) end)
        return
      end
    end
  end
end)

LR.onChange(function(what)
  if P.on and (what == "roll" or what == "rolls") then P.react() end
  -- several auctions at once (Core/Batch.lua)
  local batch = P.on and what == "batch" and LR.Batch.current
  if batch and batch.state == "open" and not reacted[batch.k] then
    reacted[batch.k] = true
    batch.practice = true
    answerBatch(batch)
  end
end)
