-- Reserving without the addon. Raiders type in raid (or party) chat, or whisper the raid leader:
--   !lr <item link or name>     reserve an item (several links in one message reserve each)
--   !lr remove <item>           take a reserve back
--   !lr clear                   take all of them back
--   !lr                         what you have reserved
-- The leader's addon answers by whisper, so raid chat isn't flooded with answers. ("!sr" is left alone:
-- Gargul answers that one.)
local _, LR = ...
local U, S = LR.U, LR.Session

local W = {}
LR.Whisper = W

local COMMAND = "!lr"

--- the session a whisper is about: the newest open one we lead
function W.session(sender)
  local best
  local pretend = sender and LR.Practice.isPretend(sender)
  for _, s in ipairs(LR.sessions()) do
    -- (a practice raid only hears its pretend players, and they only it)
    local fits = sender == nil or (s.practice and true or false) == (pretend and true or false)
    if fits and LR.isLeader(s) and not s.ended and (not best or s.created > best.created) then best = s end
  end
  return best
end

local function chat(msg, channel, target) LR.say(msg, channel, target) end

--- whispers someone, in lines of up to 255 characters (item links are long), each starting with the tag
function W.reply(to, text)
  for _, line in ipairs(U.chatLines(text, 255 - #LR.TAG - 1)) do chat(LR.TAG .. " " .. line, "WHISPER", to) end
end

local function list(s, player)
  local items = S.reservesOf(s, player)
  if #items == 0 then return "nothing" end
  local counts, order = {}, {}
  for _, id in ipairs(items) do
    if not counts[id] then order[#order + 1] = id end
    counts[id] = (counts[id] or 0) + 1
  end
  return table.concat(U.map(order, function(id) return LR.itemLink(id) .. (counts[id] > 1 and (" x" .. counts[id]) or "") end), " ")
end

local function status(s, player)
  local limit = S.limit(s, player)
  local left = limit - #S.reservesOf(s, player)
  local extra = S.extra(s, player)
  local po = s.plusOne and (" You have %s."):format(S.plusOnes(s, player) == 1 and "a +1" or (S.plusOnes(s, player) .. " +1s")) or ""
  return ("You have reserved %s (%d of %d used%s%s).%s"):format(list(s, player), limit - left, limit,
    extra > 0 and (", with " .. U.plural(extra, "extra reserve")) or "", s.locked and ", reserves are locked" or "", po)
end

local function nameOf(s, id) return LR.itemLink(id) end

--- one item from what was typed; replies with what went wrong when it can't tell
local function pick(s, player, text)
  local faction = UnitFactionGroup("player")
  local id, close, linked = LR.findInSession(s, text, faction)
  if id then return id end
  if linked then
    W.reply(player, ("%s doesn't drop in %s, and only its loot can be reserved."):format(LR.itemLink(linked), LR.raidOf(s).name))
  elseif #close > 1 then
    local some = {}
    for i = 1, math.min(4, #close) do some[i] = LR.itemLink(close[i]) end
    W.reply(player, ("Which one? %s%s - use the item link to be sure."):format(table.concat(some, " "), #close > 4 and " ..." or ""))
  else
    W.reply(player, ("I couldn't find \"%s\" in %s. Shift-click the item to put its link after !lr."):format(U.plain(text), LR.raidOf(s).name))
  end
end

--- one of a player's own reserves from what they typed (a link, or part of the name), if it's clear which
local function ownReserve(s, player, text)
  local linked = tonumber(text:match("|Hitem:(%d+)"))
  local mine = S.reservesOf(s, player)
  if linked then return U.indexOf(mine, linked) and linked or nil end
  local want = U.plain(text):gsub("^%[", ""):gsub("%]$", ""):lower()
  local found
  for _, id in ipairs(mine) do
    local here, english = LR.itemName(id):lower(), (LR.ITEMS[id] and LR.ITEMS[id][1] or ""):lower()
    if here:find(want, 1, true) or english:find(want, 1, true) then
      if found and found ~= id then return nil end
      found = id
    end
  end
  return found
end

function W.handle(text, sender)
  local s = W.session(sender)
  if not s then
    -- a GDKP that's over, with payouts still to do: "!lr pot" still answers
    local lower = U.trim(text:sub(#COMMAND + 1)):lower()
    local past = (lower == "pot" or lower == "gdkp") and LR.History.owing(sender)
    if past then W.reply(U.full(sender), LR.Pot.line(past, U.full(sender))) end
    return
  end
  local player = U.full(sender)
  local class = LR.classOf(player)
  local args = U.trim(text:sub(#COMMAND + 1))
  local lower = args:lower()
  local now = U.now()

  if lower == "" or lower == "list" or lower == "help" or lower == "?" then
    if s.gdkp then
      W.reply(player, ("%s auctions its loot for gold (GDKP). When an item is up, type your bid in raid chat (just the number), or whisper me \"!lr bid 150\". \"!lr pot\": what you owe or are owed."):format(LR.raidOf(s).name))
      return
    end
    local extra = (s.prio and " \"!lr prio\": your place on the guild's priority lists." or "") .. (s.boost and " \"!lr points\": your points for boosted rolls." or "")
    if s.prio == "only" then
      W.reply(player, ("%s goes by the guild's priority lists, not reserves.%s"):format(LR.raidOf(s).name, extra))
      return
    end
    W.reply(player, ("Soft reserves for %s: %d each%s. %s Type \"!lr <item link>\" in raid chat or whisper me to reserve, \"!lr remove <item>\" to take one back.%s"):format(
      LR.raidOf(s).name, s.sr, s.dupes and "" or " (one per item)", status(s, player), extra))
    return
  end

  -- the loot council: "!lr vote Name" (Core/Council.lua), from a member without the addon
  local voteFor = lower:match("^vote%s*(.*)$")
  if voteFor and LR.Council.on(s) then
    local ok, who = LR.Council.vote(player, U.trim(args:sub(5)))
    if ok then W.reply(player, who and ("Your vote for %s is in."):format(U.short(who)) or "Your vote is taken back.") else W.reply(player, who) end
    return
  end
  -- GDKP: several auctions at once: "!lr bid #2 300", "!lr max #2 800" (Core/Batch.lua)
  local batch = LR.Batch.current
  if s.gdkp and batch and batch.state == "open" then
    local how, rest = lower:match("^(bid)%s+(.+)$")
    if not how then how, rest = lower:match("^(max)%s+(.+)$") end
    local n, g
    if rest then n, g = LR.Batch.parse(rest, false, #batch.items) end
    if how and not n then
      W.reply(player, ("Say which item by its number, then the gold: \"!lr %s #2 300\"."):format(how))
      return
    end
    if how == "bid" then
      local e = LR.Batch.onBid(player, n, g)
      local item = batch.items[n]
      if e and e.kind then
        local top = item.top
        W.reply(player, (top and U.samePlayer(top.p, player)) and ("Your bid of %s on #%d %s is the highest."):format(LR.Gdkp.gold(g), n, item.link)
          or ("Someone's max bid beat yours on #%d: the highest is %s."):format(n, LR.Gdkp.gold(top.n)))
      end
      return
    elseif how == "max" then
      local ok, why = LR.Batch.setMax(player, n, g)
      W.reply(player, ok and ("Your max bid of %s on #%d is in: LootRuler bids for you, as little as it takes, up to that."):format(LR.Gdkp.gold(g), n) or why)
      return
    end
  end
  -- GDKP: a bid ahead on an item coming up ("!lr bid 300 [item]", "!lr max 800 [item]": the most they'll pay, 0 takes it back)
  local linkId = tonumber(args:match("|Hitem:(%d+)"))
  if linkId and s.gdkp then
    local plain = U.trim((lower:gsub("|c%x+|hitem:.-|h.-|h|r", "")))
    local cur = LR.Rolls.current
    local onNow = cur and cur.mode == "BID" and cur.state == "open" and cur.id == linkId
    local amount = plain:match("^bid%s+(.+)$") or plain:match("^max%s+(.+)$")
    if amount and not onNow then
      local g = amount:match("^0+%s*g?$") and 0 or LR.Roll.parseBid(amount)
      if not g then W.reply(player, "A bid ahead is an amount of gold and the item: \"!lr bid 300 [item]\".") return end
      local ok, why = LR.Rolls.setAhead(player, linkId, g)
      local link = LR.itemLink(linkId)
      W.reply(player, not ok and why or (why == 0 and ("Your bid ahead on %s is taken back."):format(link))
        or ("Your bid ahead of up to %s on %s is in: when it comes up, LootRuler bids for you, as little as it takes."):format(LR.Gdkp.gold(g), link))
      return
    end
    if amount then lower = plain end            -- (the item on now: an ordinary bid or max bid on it)
  end
  -- GDKP: a bid by whisper, and what they owe or are owed
  local bidArg = lower:match("^bid%s+(.+)$")
  if bidArg and s.gdkp then
    local g = LR.Roll.parseBid(bidArg)
    local roll = LR.Rolls.current
    if not g then W.reply(player, "A bid is an amount of gold: \"!lr bid 150\".") return end
    if not (roll and roll.mode == "BID" and roll.state == "open") then W.reply(player, "Nothing is being auctioned right now.") return end
    local e = LR.Rolls.onBid(player, g)
    if e and e.kind then
      local top = roll.top
      if top and U.samePlayer(top.p, player) then W.reply(player, ("Your bid of %s on %s is the highest."):format(LR.Gdkp.gold(g), roll.link))
      elseif top then W.reply(player, ("Someone's max bid beat yours: the highest is %s."):format(LR.Gdkp.gold(top.n))) end
    end
    return
  end
  local maxArg = lower:match("^max%s+(.+)$")
  if maxArg and s.gdkp then
    local g = LR.Roll.parseBid(maxArg)
    if not g then W.reply(player, "A max bid is an amount of gold: \"!lr max 800\".") return end
    local ok, why = LR.Rolls.setMax(player, g)
    W.reply(player, ok and ("Your max bid of %s is in: LootRuler bids for you, as little as it takes, up to that."):format(LR.Gdkp.gold(g)) or why)
    return
  end
  if (lower == "pot" or lower == "gdkp") and s.gdkp then
    W.reply(player, LR.Pot.line(s, player))
    return
  end

  -- the guild's priority lists: theirs, or an item's
  local prioArg = lower:match("^prio%s*(.*)$") or lower:match("^priority%s*(.*)$")
  if prioArg then
    local book = LR.book and LR.book()
    if not (s.prio and book) then W.reply(player, "This raid doesn't go by priority lists.") return end
    local P, B = LR.Prio, LR.Book
    if prioArg == "" then
      local mine = B.prioOf(book, player)
      if #mine == 0 then W.reply(player, "You're not on any priority list. Ask an officer if you think you should be.") return end
      local parts = {}
      for i, x in ipairs(mine) do
        if i > 6 then parts[#parts + 1] = ("and %d more"):format(#mine - 6) break end
        parts[#parts + 1] = LR.itemLink(x[1]) .. " " .. P.place(x[2])
      end
      W.reply(player, "Your priorities: " .. table.concat(parts, ", ") .. ". \"!lr prio <item>\" says who else is on an item's list.")
      return
    end
    local itemText = U.trim(args:sub(#args - #prioArg + 1))
    local id = LR.idFrom(itemText) or pick(s, player, itemText)
    if not id then return end
    local list = B.prio(book, id)
    if #list == 0 then W.reply(player, ("%s has no priority list: it's rolled for as usual."):format(LR.itemLink(id))) return end
    W.reply(player, ("Priority for %s: %s."):format(LR.itemLink(id), LR.UI.prioLine(list, 8)))
    return
  end

  -- boosted rolls: what their guild points are, and how to roll with them
  if lower == "points" or lower == "boost" then
    local book = LR.book and LR.book()
    if not (s.boost and book and book.boost.on) then W.reply(player, "This raid doesn't use boosted rolls.") return end
    local n = LR.Book.points(book, player)
    if n == 0 then W.reply(player, ("You have no points for boosted rolls yet. Each raid with %s is worth %d."):format(book.guild, book.boost.perRaid)) return end
    local lo, hi = LR.Book.boostRange(n)
    local main = LR.Book.mainOf(book, player)
    local whose = U.samePlayer(main, player) and "You have" or ("You're " .. U.short(main) .. "'s alt: you share their")
    W.reply(player, ("%s %d points. For a boosted main spec roll, type /roll %d %d. If you win with it, the points are spent."):format(whose, n, lo, hi))
    return
  end

  if lower == "clear" or lower == "remove all" then
    local ok, why = S.set(s, player, class, {}, false, now)
    if ok then LR.leaderChanged(s) W.reply(player, "Your reserves are cleared.") else W.reply(player, S.WHY[why]) end
    return
  end

  -- a swap, once reserves are locked: "!lr swap [old] [new]", "!lr swap old for new" (Core/Swap.lua)
  local swapArg = args:match("^[Ss][Ww][Aa][Pp]%s+(.+)$")
  if swapArg then
    local ids = {}
    for id in swapArg:gmatch("|Hitem:(%d+)") do ids[#ids + 1] = tonumber(id) end
    local from, to
    if #ids >= 2 then
      from, to = ids[1], ids[2]
    else
      local a, b = swapArg:match("^(.-)%s+[Ff][Oo][Rr]%s+(.+)$")
      if a then
        from = ownReserve(s, player, a)
        if not from then W.reply(player, ("You haven't reserved \"%s\" (or it could be more than one of yours)."):format(U.plain(a))) return end
        to = pick(s, player, b)
        if not to then return end                -- (pick has said what went wrong)
      end
    end
    if not from or not to then W.reply(player, "To swap: \"!lr swap [old item] [new item]\", or \"!lr swap old for new\".") return end
    local ok, why = LR.Swap.ask(s, player, from, to)
    W.reply(player, ok and ("Your swap request is in: %s for %s. %s decides."):format(LR.itemLink(from), LR.itemLink(to), U.short(s.leader)) or why)
    return
  end
  local removeArg = args:match("^[Rr][Ee][Mm][Oo][Vv][Ee]%s+(.+)$") or args:match("^[Rr][Ee][Mm]%s+(.+)$") or args:match("^%-%s*(.+)$")
  if removeArg then
    -- look among their own reserves first ("remove signet" means the signet they reserved)
    local id = ownReserve(s, player, removeArg) or pick(s, player, removeArg)
    if not id then return end
    local ok, why = S.remove(s, player, id, false, now)
    if ok then LR.leaderChanged(s) W.reply(player, ("Removed %s. %s"):format(nameOf(s, id), status(s, player)))
    else W.reply(player, S.WHY[why] .. " " .. status(s, player)) end
    return
  end

  -- only the group can reserve (the leader's choice): someone outside it is told to ask for an invite
  if s.go and not LR.inGroup(player) then W.reply(player, S.WHY.GROUP_ONLY) return end

  -- one or more item links, or one item name
  local wanted = {}
  for link in args:gmatch("|c%x+|Hitem:[^|]+|h%[.-%]|h|r") do wanted[#wanted + 1] = link end
  if #wanted == 0 then wanted[1] = args end
  local done = {}
  for _, w in ipairs(wanted) do
    local id = pick(s, player, w)
    if not id then break end
    local ok, why = S.add(s, player, class, id, false, now)
    if not ok then
      W.reply(player, ("Couldn't reserve %s: %s %s"):format(nameOf(s, id), S.WHY[why], status(s, player)))
      break
    end
    done[#done + 1] = id
  end
  if #done > 0 then
    LR.leaderChanged(s)
    W.reply(player, ("Reserved %s. %s"):format(table.concat(U.map(done, function(id) return nameOf(s, id) end), " "), status(s, player)))
  end
end

---------------------------------------------------------------------- listening, and keeping the leader's chat tidy
local function isCommand(text) return text and text:lower():sub(1, #COMMAND) == COMMAND and (#text == #COMMAND or text:sub(#COMMAND + 1, #COMMAND + 1) == " ") end
W.isCommand = isCommand

-- raid and party chat count when the option's on (and only from people in the group)
local GROUP_CHAT = { CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true, CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true }

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_WHISPER")
for e in pairs(GROUP_CHAT) do frame:RegisterEvent(e) end
frame:SetScript("OnEvent", function(_, event, text, sender)
  if not LR.db or not isCommand(text) or not sender then return end
  if GROUP_CHAT[event] and not (LR.db.settings.raidCommands and LR.inGroup(U.full(sender))) then return end
  local ok, err = pcall(W.handle, text, sender)
  if not ok then geterrorhandler()(err) end
end)

-- hides "!lr" whispers to us and our answers (they'd flood the leader's chat during sign-ups), and "!lr" lines
-- in raid chat for anyone with soft reserves open
local function hideIncoming(_, _, text) return LR.db and LR.db.settings.hideWhispers and W.session() ~= nil and isCommand(text) end
local function hideGroup(_, _, text) return LR.db and LR.db.settings.hideWhispers and LR.current() ~= nil and isCommand(text) end
local function hideOutgoing(_, _, text) return LR.db and LR.db.settings.hideWhispers and text and text:sub(1, #LR.TAG) == LR.TAG end
local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
if addFilter then
  addFilter("CHAT_MSG_WHISPER", hideIncoming)
  addFilter("CHAT_MSG_WHISPER_INFORM", hideOutgoing)
  for e in pairs(GROUP_CHAT) do addFilter(e, hideGroup) end
end
W.hideIncoming, W.hideOutgoing, W.hideGroup = hideIncoming, hideOutgoing, hideGroup

--- the short how-to for raiders without the addon, posted to the group
function W.howTo()
  if LR.db and LR.db.settings.raidCommands then
    return "Type !lr [linked item] in raid chat to SR if you do not have the LootRuler addon."
  end
  return "Whisper me !lr [linked item] to SR if you do not have the LootRuler addon."
end
function W.postHowTo()
  local channel = LR.groupChannel()
  if not channel then return false end
  chat(W.howTo(), channel)
  return true
end

--- the line the leader posts to the raid
function W.announce(s)
  local text = ("%s Soft reserves are open for %s: %s each%s. Reserve in the LootRuler addon, or %s."):format(
    LR.TAG, LR.raidOf(s).name, U.plural(s.sr, "reserve"), s.dupes and "" or ", one per item",
    LR.db.settings.raidCommands and "type \"!lr <item link>\" in raid chat" or "whisper me \"!lr <item link>\"")
  local hr = U.keys(s.hr)
  if #hr > 0 then
    local links = U.map(hr, function(id) return LR.itemLink(id) end)
    text = text .. " Hard reserved: " .. table.concat(links, " ")
  end
  local channel = LR.groupChannel()
  if not channel then return false end
  for _, line in ipairs(U.chatLines(text, 255)) do chat(line, channel) end
  -- the organiser's branding: their raid's name and message, on a line of its own
  if s.br and (s.br.n or s.br.m) then
    local brand = (s.br.n and s.br.m) and (s.br.n .. ": " .. s.br.m) or s.br.n or s.br.m
    for _, line in ipairs(U.chatLines(LR.TAG .. " " .. brand, 255)) do chat(line, channel) end
  end
  return true
end

---------------------------------------------------------------------- reminding people who haven't reserved
--- how to reserve, in a few words, for a raid chat line
local function howTo(s)
  return ("Soft reserves are open for %s (%s each). %s, or reserve in the LootRuler addon."):format(LR.raidOf(s).name,
    s.sr, LR.db.settings.raidCommands and "Type \"!lr <item link>\" in raid chat" or ("Whisper " .. U.short(U.me()) .. " \"!lr <item link>\""))
end
--- whether players can reserve in a session now (open, and it goes by reserves)
local function open(s) return s and not s.locked and not s.gdkp and s.prio ~= "only" end

--- the players in the group who haven't reserved anything yet ("Name-Realm"), A to Z (not me: I'm asking)
function W.notReserved(s)
  local has, out = { [U.foldCase(U.me())] = true }, {}
  for name, r in pairs(s.res) do if #r.i > 0 then has[U.foldCase(name)] = true end end
  for _, m in ipairs(LR.roster()) do
    if not has[U.foldCase(U.full(m.name))] then out[#out + 1] = U.full(m.name) end
  end
  table.sort(out, function(a, b) return U.foldCase(U.short(a)) < U.foldCase(U.short(b)) end)
  return out
end

--- the reminder line for these names
function W.reminderText(s, names)
  return ("%s Not reserved yet: %s. %s"):format(LR.TAG, table.concat(U.map(names, U.short), ", "), howTo(s))
end

--- tells the raid who hasn't reserved yet, and how to. Returns true, or false and why not.
function W.remind(s)
  local channel = LR.groupChannel()
  if not channel then return false, "You're not in a group." end
  if not open(s) then return false, "Reserves aren't open: nobody can reserve now." end
  local names = W.notReserved(s)
  if #names == 0 then return false, "Everyone in the group has reserved." end
  local text = W.reminderText(s, names)
  for _, line in ipairs(U.chatLines(text, 255)) do chat(line, channel) end
  return true, #names
end

-- someone joins while my reserves are open (Settings: remindOnJoin): a few seconds later, one line for everyone who
-- joined meanwhile and still hasn't reserved. Whoever was in the group already isn't told again.
W.JOIN_WAIT = 15
local seen, joined, waiting = nil, {}, false
LR.onChange(function(what)
  if what ~= "roster" or not LR.db then return end
  local now = {}
  for _, m in ipairs(LR.roster()) do now[U.foldCase(U.full(m.name))] = U.full(m.name) end
  local s = W.session()
  if seen and IsInGroup() and LR.db.settings.remindOnJoin and open(s) then
    for key, name in pairs(now) do if not seen[key] and not U.samePlayer(name, U.me()) then joined[key] = name end end
  end
  seen = IsInGroup() and now or nil
  if next(joined) and not waiting then
    waiting = true
    C_Timer.After(W.JOIN_WAIT, function()
      waiting = false
      local list = joined
      joined = {}
      local sess = W.session()
      local channel = LR.groupChannel()
      if not channel or not LR.db.settings.remindOnJoin or not open(sess) then return end
      local still = {}
      for _, name in ipairs(W.notReserved(sess)) do if list[U.foldCase(name)] then still[#still + 1] = U.short(name) end end
      if #still == 0 then return end
      table.sort(still)
      local text = ("%s Welcome, %s! %s"):format(LR.TAG, table.concat(still, ", "), howTo(sess))
      for _, line in ipairs(U.chatLines(text, 255)) do chat(line, channel) end
    end)
  end
end)
