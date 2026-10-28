-- Several GDKP auctions at once (a batch): the loot master puts up to Batch.MAX items up together, numbered, and they
-- all end together. Bids are typed in raid chat with the item's number ("#2 300", "300 on 2"), whispered ("!lr bid #2
-- 300", "!lr max #2 800") or clicked in the batch window (UI/Batch.lua), which just types the line, so players without
-- the addon bid the same way. A bid in the last few seconds gives everyone a few more. When it ends, each item with a
-- bid is sold through the same award as a single auction (recorded, announced, handed out or traded, undoable);
-- items nobody bid on stay where they are.
--
-- Messages (on top of Core/Rolls.lua's):
--   Z  loot master -> group    the batch: { k, e = "open" / "closed" / "cancelled", left, s = seconds, sb = bids start
--                              with "bid", it = { { id, l = link, mn, inc, tb = { p, n } } } } (sent again when a bid
--                              changes the highest, or the time does). Older versions don't know it: they bid by chat.
--   Y  raider -> loot master   a max bid on item n of batch k: { k, n, g } (kept by the loot master; answered by whisper)
-- Each item is an auction of its own (Core/Roll.lua's roll of mode "BID"), so bids, max bids and the lowest next bid
-- work as they do for one item.
local _, LR = ...
local U, R = LR.U, LR.Roll
local Net = LR.Net
local Rolls = LR.Rolls

local B = { seen = {}, order = {} }
LR.Batch = B

B.MAX = 12
B.SECONDS = 60
local SNIPE = 8           -- a bid with less than this left gives everyone this long again
local FINAL_CALL = 10
local LEEWAY = 1.5
local KEEP = 60

local function now() return GetTime() end
local function changed() LR.changed("batch") end

---------------------------------------------------------------------- reading a bid with an item's number
--- "#2 300", "#2: 300", "2: 300", "300 on 2", "300 for #2", "bid #2 300", "bid 300 on 2" -> 2, 300; nil when it isn't
--- one, or the number isn't one of the count items. strict: it must start with "bid".
function B.parse(text, strict, count)
  local t = U.trim(tostring(text or "")):lower():gsub(",", "")
  if strict and not t:find("^bid") then return nil end
  t = U.trim(t:gsub("^bid%s*", ""))
  local n, amount = t:match("^#(%d+)%s*[:%-]?%s*(.+)$")
  if not n then n, amount = t:match("^(%d+)%s*:%s*(.+)$") end
  if not n then amount, n = t:match("^(.-)%s+on%s+#?(%d+)$") end
  if not n then amount, n = t:match("^(.-)%s+for%s+#?(%d+)$") end
  n = tonumber(n)
  if not n or n < 1 or n > (count or B.MAX) then return nil end
  local g = R.parseBid(amount)
  if not g then return nil end
  return n, g
end

--- how a bid on item n is typed
function B.bidText(n, g, strict) return ("%s#%d %d"):format(strict and "bid " or "", n, math.floor(g)) end

---------------------------------------------------------------------- the loot master's batch

-- (the items' links are only read when a raider first sees the batch, and they're most of its size: they go in the first
-- one and every LINKS_EVERY-th after it, for anyone who joins late; the rest carry the item numbers, which make links too)
local LINKS_EVERY = 10
local function wire(batch, links)
  local it = {}
  for i, item in ipairs(batch.items) do
    it[i] = { id = item.id, l = links and item.link or nil, mn = item.min, inc = item.inc, tb = item.top and { item.top.p, item.top.n } or nil }
  end
  local nb = batch.items[1] and LR.Rolls.noBidList(batch.items[1])
  return { t = "Z", k = batch.k, e = batch.state, left = math.max(0, batch.ends - now()), s = batch.secs, sb = batch.strict or nil, it = it, nb = nb }
end

-- the group hears the batch now, and again shortly after a burst of bids (once)
local sendSeq = 0
local function publish(batch, soon)
  sendSeq = sendSeq + 1
  local mine = sendSeq
  local function go()
    if mine ~= sendSeq then return end
    B.follow(wire(batch, true), U.me())
    -- (the newest only: one still waiting to go is made again when it goes, with the time left as it is then)
    Net.sendNewest("Z:" .. batch.k, function()
      batch.sent = (batch.sent or 0) + 1
      return wire(batch, batch.sent % LINKS_EVERY == 1)
    end, LR.groupChannel())
  end
  if soon then C_Timer.After(0.3, go) else go() end
end

local function say(text, warning) Rolls.say(text, warning) end

--- whose bids aren't taken changed (Core/Rolls.lua): my batch on now follows, at once
function B.applyNoBids(nb)
  local batch = B.current
  if not batch or batch.state ~= "open" then return end
  local any = false
  for _, item in ipairs(batch.items) do
    for _, name in pairs(nb) do if R.ban(item, name) then any = true end end
    for k in pairs(item.nb or {}) do if not nb[k] then item.nb[k] = nil any = true end end
  end
  if any then publish(batch) changed() end
end

--- puts items up together. items: { { id, link, slot, drop } } (2 to B.MAX). Returns the batch, or nil and why.
function B.start(items, secs)
  local s = Rolls.session()
  if s and s.pv then return nil, Rolls.PRIVATE end
  if not (s and s.gdkp and s.gk) then return nil, "Several auctions at once is for a GDKP: turn it on on the Session tab." end
  if not LR.canRunLoot() then return nil, "Only the master looter can auction loot (or the raid leader, without master loot)." end
  local cur = Rolls.current
  if cur and cur.state == "open" then return nil, "Finish the roll for " .. U.plain(cur.link) .. " first." end
  if B.current and B.current.state == "open" then return nil, "Finish the auction that's on first." end
  if #Rolls.queue > 0 then return nil, "Stop the queue first." end
  if type(items) ~= "table" or #items < 2 then return nil, "Pick at least two items." end
  local k = U.me() .. ":batch:" .. U.now() .. ":" .. math.random(1000)
  local batch = { k = k, by = U.me(), sid = s.id, items = {}, state = "open", strict = s.gk.strict or nil,
    secs = math.max(20, math.min(300, tonumber(secs) or LR.db.settings.batchSeconds or B.SECONDS)) }
  for i, it in ipairs(items) do
    if i > B.MAX then break end
    local item = R.new(k .. ":" .. i, it.id, { mode = "BID", min = LR.Gdkp.minFor(s, it.id), inc = s.gk.inc, strict = s.gk.strict,
      nb = LR.Gdkp.noBids(s), who = {}, away = {} })
    item.n, item.link, item.slot, item.drop, item.by, item.batch = i, it.link or LR.itemLink(it.id), it.slot, it.drop, U.me(), k
    item.state = "open"
    batch.items[i] = item
  end
  batch.started = now()
  batch.ends = now() + batch.secs
  B.current = batch
  -- the raid hears every item with its number, and how to bid
  local parts = {}
  for _, item in ipairs(batch.items) do parts[#parts + 1] = ("#%d %s"):format(item.n, item.link) end
  say(("Auction of %d items: %s."):format(#batch.items, table.concat(parts, " ")), true)
  say(("Type the item's number and your bid in raid chat: \"%s\". Bids start at %s, each at least %s more. %d seconds. To bid up to a max, whisper %s \"!lr max #1 800\".")
    :format(B.bidText(1, batch.items[1].min, batch.strict), LR.Gdkp.gold(s.gk.min), LR.Gdkp.gold(s.gk.inc), batch.secs, U.short(U.me())), true)
  publish(batch)
  B.tick(batch)
  changed()
  return batch
end

--- a bid on item n (raid chat, a whisper, my window): counted in my batch and everyone's copies
function B.onBid(sender, n, g)
  local batch = B.current
  local t = now()
  local entry
  if batch and batch.state == "open" and batch.items[n] and (LR.inGroup(sender) or not IsInGroup()) then
    local item = batch.items[n]
    entry = R.bid(item, sender, g)
    if entry.kind then
      if batch.ends - t < SNIPE then batch.ends = t + SNIPE batch.warned = false end
      B.autoBids(batch, item)
      publish(batch, true)
    elseif entry.why == "low" and not U.samePlayer(sender, U.me()) then
      LR.say(("%s The lowest bid on #%d now is %s."):format(LR.TAG, n, LR.Gdkp.gold(R.nextBid(item))), "WHISPER", sender)
    end
    changed()
  end
  -- everyone's copies: the highest so far (and whether mine was beaten)
  for _, k in ipairs(B.order) do
    local copy = B.seen[k]
    local item = copy and copy.state == "open" and copy.items[n]
    if item and not U.samePlayer(copy.by, U.me()) then
      local before = item.top
      R.bid(item, sender, g)
      Rolls.checkOutbid(item, before)
    end
  end
  return entry
end

--- max bids on an item bid for their players, as little as it takes
function B.autoBids(batch, item)
  if not item.maxes or not next(item.maxes) then return end
  if #R.resolve(item, item.maxes) == 0 then return end
  if batch.ends - now() < SNIPE then batch.ends = now() + SNIPE end
end

--- a player's max bid on item n (my addon is the loot master's); returns true, or false and why
function B.setMax(player, n, g)
  local batch = B.current
  g = math.floor(tonumber(g) or 0)
  local item = batch and batch.state == "open" and batch.items[n]
  if not item then return false, "There's no item with that number in the auction." end
  if g < R.nextBid(item) then return false, ("A max bid on #%d has to be at least the lowest bid now, %s."):format(n, LR.Gdkp.gold(R.nextBid(item))) end
  if g > R.MAX_BID then return false, "That's more gold than there is." end
  item.maxes = item.maxes or {}
  local k = R.key(player)
  if item.maxes[k] and item.maxes[k].g >= g then return false, ("Your max bid on #%d is %s already: it can only go up."):format(n, LR.Gdkp.gold(item.maxes[k].g)) end
  item.maxes[k] = { p = U.full(player), g = g, at = (item.maxes[k] and item.maxes[k].at) or now() }
  B.autoBids(batch, item)
  publish(batch, true)
  changed()
  return true
end

--- my max bid on item n of a batch (my window): to the loot master's addon, or my own
function B.myMax(copy, n, g)
  g = math.floor(tonumber(g) or 0)
  if not copy or copy.state ~= "open" or not copy.items[n] then return false, "There's no item with that number in the auction." end
  if U.samePlayer(copy.by, U.me()) then return B.setMax(U.me(), n, g) end
  Net.send({ t = "Y", k = copy.k, n = n, g = g }, "WHISPER", copy.by)
  copy.items[n].myMax = g
  changed()
  return true
end

--- I bid on item n (the window's button): typed in raid chat, like anyone without the addon
function B.bid(copy, n, g)
  if not copy or copy.state ~= "open" or not copy.items[n] then return false end
  local ch = LR.groupChannel()
  if not ch then B.onBid(U.me(), n, g) return true end
  LR.say(B.bidText(n, g, copy.strict), ch)
  return true
end

--- more time
function B.extend(seconds)
  local batch = B.current
  if not batch or batch.state ~= "open" then return false end
  batch.ends = math.max(batch.ends, now()) + (seconds or 10)
  batch.secs = batch.secs + (seconds or 10)
  batch.warned, batch.finalCalled = false, false
  say(("%d more seconds to bid in the auction."):format(seconds or 10))
  publish(batch)
  changed()
  return true
end

--- calls it off: nothing is sold
function B.cancel()
  local batch = B.current
  if not batch or batch.state ~= "open" then return false end
  batch.state = "cancelled"
  say("The auction is called off: nothing is sold.")
  publish(batch)
  changed()
  return true
end

--- it's over: each item with a bid is sold through the usual award, the rest stay. Returns how many were sold.
function B.close()
  local batch = B.current
  if not batch or batch.state ~= "open" then return 0 end
  batch.state = "closed"
  publish(batch)
  local sold, unsold, notes = 0, {}, {}
  local keep = Rolls.current
  for _, item in ipairs(batch.items) do
    local top = R.topBid(item)
    if top then
      -- (the usual award, on this item as if it had been auctioned on its own)
      item.state = "closed"
      item.closedAt = now()
      item.secs, item.ends, item.started = batch.secs, batch.ends, batch.started
      Rolls.current = item
      local ok, note = Rolls.award(top.p, "BID", top.n)
      if ok then sold = sold + 1 item.sold = { p = top.p, n = top.n } end
      if note then notes[#notes + 1] = note end
    else
      unsold[#unsold + 1] = ("#%d %s"):format(item.n, item.link)
    end
  end
  Rolls.current = keep
  if #unsold > 0 then say(("Nobody bid on %s: not sold."):format(table.concat(unsold, ", "))) end
  for _, note in ipairs(notes) do LR.print(note) end
  changed()
  LR.changed("roll")
  return sold
end

--- the loot master's clock: the final call, five seconds' warning, and the end
function B.tick(batch)
  if B.current ~= batch or batch.state ~= "open" then return end
  local left = batch.ends - now()
  if not batch.finalCalled and batch.secs >= 20 and left <= FINAL_CALL + 0.05 and left > 5.05 and LR.db.settings.finalCall then
    batch.finalCalled = true
    local parts = {}
    for _, item in ipairs(batch.items) do
      local top = R.topBid(item)
      parts[#parts + 1] = top and ("#%d %s by %s"):format(item.n, LR.Gdkp.gold(top.n), U.short(top.p)) or ("#%d no bids"):format(item.n)
    end
    say(("Final call, %d seconds: %s."):format(FINAL_CALL, table.concat(parts, ", ")), true)
  end
  if not batch.warned and left <= 5.05 and left > 0 then
    batch.warned = true
    say("5 seconds left to bid in the auction.")
  end
  if left <= -LEEWAY then B.close() return end
  C_Timer.After(0.25, function() B.tick(batch) end)
end

--- items I can put up together: the open loot window's (master loot), else the drops I hold, not given out yet
function B.candidates()
  local out = {}
  if Rolls.lootOpen then
    for _, it in ipairs(Rolls.loot()) do
      out[#out + 1] = { id = it.id, link = it.link, slot = it.slot, drop = LR.Drops.forSlot(it.slot) }
    end
    if #out > 0 then return out end
  end
  for _, x in ipairs(LR.Drops.holding()) do
    if x.state == "held" then out[#out + 1] = { id = x.d.i, link = LR.itemLink(x.d.i), drop = x.d.k } end
  end
  return out
end

---------------------------------------------------------------------- everyone's copies
--- the loot master's batch, as everyone (the loot master too) sees it; checked, since it came from another addon
function B.follow(msg, sender)
  if type(msg.k) ~= "string" or #msg.k > 120 or type(msg.it) ~= "table" or #msg.it < 1 or #msg.it > B.MAX then return end
  local copy = B.seen[msg.k]
  if copy and not U.samePlayer(copy.by, sender) then return end
  if not copy then
    if msg.e ~= "open" then return end
    copy = { k = msg.k, by = U.full(sender), items = {}, strict = msg.sb == true or nil, at = now() }
    for i, x in ipairs(msg.it) do
      if type(x) ~= "table" or type(x.id) ~= "number" then return end
      local item = R.new(msg.k .. ":" .. i, x.id, { mode = "BID", min = math.max(0, math.min(R.MAX_BID, tonumber(x.mn) or 0)),
        inc = math.max(1, math.min(R.MAX_BID, tonumber(x.inc) or 1)), strict = copy.strict, who = {}, away = {} })
      item.n, item.state, item.by = i, "open", copy.by
      item.link = type(x.l) == "string" and #x.l < 300 and x.l or LR.itemLink(x.id)
      copy.items[i] = item
    end
    B.seen[msg.k] = copy
    table.insert(B.order, msg.k)
  end
  copy.secs = math.max(1, math.min(600, tonumber(msg.s) or 60))
  copy.ends = now() + math.max(0, math.min(600, tonumber(msg.left) or 0))
  if msg.e == "open" or msg.e == "closed" or msg.e == "cancelled" then copy.state = msg.e end
  -- whose bids aren't taken (older versions don't send it)
  if type(msg.nb) == "table" then
    for j, name in ipairs(msg.nb) do
      if j > 40 then break end
      if type(name) == "string" and #name <= 60 then for _, item in ipairs(copy.items) do R.ban(item, name) end end
    end
  end
  -- the highest bids as the loot master has them (we may have missed some lines)
  for i, x in ipairs(msg.it) do
    local item = copy.items[i]
    local tb = type(x) == "table" and x.tb
    if item and type(tb) == "table" and type(tb[1]) == "string" and #tb[1] <= 60 and type(tb[2]) == "number" then
      local top = item.top
      if not top or top.n ~= tb[2] or not U.samePlayer(top.p, tb[1]) then
        local before = top
        local e = { p = U.full(tb[1]), n = math.floor(tb[2]), kind = "BID", seq = #item.entries + 1 }
        item.top = e
        item.rolled[R.key(e.p)] = e
        table.insert(item.entries, e)
        if not U.samePlayer(copy.by, U.me()) then Rolls.checkOutbid(item, before) end
      end
    end
    if copy.state ~= "open" and item then item.state = copy.state end
  end
  if copy.state ~= "open" then copy.endedAt = copy.endedAt or now() end
  -- forget old ones
  for i = #B.order, 1, -1 do
    local c = B.seen[B.order[i]]
    if c and c ~= copy and c.endedAt and now() - c.endedAt > KEEP then B.seen[B.order[i]] = nil table.remove(B.order, i) end
  end
  changed()
end

--- the batch on now (my copy), if any
function B.open()
  for i = #B.order, 1, -1 do
    local c = B.seen[B.order[i]]
    if c and c.state == "open" then return c end
  end
end

Net.handlers.Z = function(msg, channel, sender)
  if channel == "WHISPER" or not LR.canRunLoot(sender) or U.samePlayer(sender, U.me()) then return end
  B.follow(msg, sender)
end

Net.handlers.Y = function(msg, channel, sender)
  local batch = B.current
  if channel ~= "WHISPER" or not batch or batch.k ~= msg.k or type(msg.n) ~= "number" or type(msg.g) ~= "number" then return end
  if not (LR.inGroup(sender) or not IsInGroup()) then return end
  local ok, why = B.setMax(sender, msg.n, msg.g)
  LR.say(LR.TAG .. " " .. (ok and ("Your max bid of %s on #%d is in."):format(LR.Gdkp.gold(msg.g), msg.n) or why), "WHISPER", sender)
end

--- a line in raid chat: a bid with an item's number, when a batch is open (Core/Rolls.lua hands it on)
function B.onChat(text, sender)
  local open = (B.current and B.current.state == "open" and B.current) or B.open()
  if not open then return false end
  local n, g = B.parse(text, open.strict, #open.items)
  if not n then return false end
  B.onBid(U.full(sender), n, g)
  return true
end
