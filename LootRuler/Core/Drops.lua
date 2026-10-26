-- The raid's loot list: every item that drops while soft reserves are open, who has it, and who won it. It's
-- kept on the session (Core/Session.lua: drops), so every raider's addon has a copy, and it goes when the
-- session ends.
--
-- Who writes it down:
--   master loot   the master looter's addon, when they open a corpse (and the loot messages say who got what)
--   other loot    the leader of the soft reserves' addon, from the loot messages ("Bob receives loot: [...]")
-- The leader's addon keeps the list; anyone else who writes something down sends it to them:
--   D  loot master -> group   drops, new or with a new holder: { sid, d = { { k, i, b, at, by, src, h, ht } } }
--
-- Trade help: the game lets raid loot be traded for 2 hours, to anyone who could have looted it. When the
-- loot master holds items (to roll them out later) and someone who won one opens a trade with them, LootRuler
-- puts it in the trade window; when the trade goes through, the list says they have it.
local _, LR = ...
local U, S = LR.U, LR.Session
local Net, Rolls = LR.Net, LR.Rolls

local Drops = { slotKeys = {} }
LR.Drops = Drops

Drops.TRADE_SECONDS = 2 * 60 * 60

local seq = 0
local patterns
local function lootPatterns()
  if patterns then return patterns end
  patterns = {}
  local function add(fmt, self) if type(fmt) == "string" then patterns[#patterns + 1] = { U.pattern(fmt), self } end end
  -- the "x2" forms first: the plain ones would take "[Item]x2" for the link
  add(LOOT_ITEM_SELF_MULTIPLE or "You receive loot: %sx%d.", true)
  add(LOOT_ITEM_MULTIPLE or "%s receives loot: %sx%d.", false)
  add(LOOT_ITEM_SELF or "You receive loot: %s.", true)
  add(LOOT_ITEM or "%s receives loot: %s.", false)
  return patterns
end

--- who got what, from a loot message: "Name-Realm", item link (or nil)
function Drops.parseLoot(line)
  for _, p in ipairs(lootPatterns()) do
    local a, b = tostring(line or ""):match(p[1])
    if a then
      if p[2] then return U.me(), a end
      return U.full(a), b
    end
  end
end

local function idOf(link) return link and tonumber(tostring(link):match("item:(%d+)")) end
local function qualityOf(link, id)
  local hex = tostring(link or ""):match("|c%x%x(%x%x%x%x%x%x)")
  local q = { ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5 }
  return (hex and q[hex:lower()]) or (LR.ITEMS[id] and LR.quality(id)) or 1
end

--- the session drops go on, when this client is the one writing them down (see the top)
local function writer()
  local s = Rolls.session()
  if not s or not IsInGroup() then return nil end
  if LR.masterLooter() then return LR.isMasterLooter() and s or nil end
  return LR.isLeader(s) and s or nil
end
Drops.writer = writer

--- puts drops on the list: straight on, for the leader; else sent to them
local function save(s, list)
  if #list == 0 then return end
  if LR.isLeader(s) then
    local changed = false
    for _, d in ipairs(list) do if S.addDrop(s, d, U.now()) then changed = true end end
    if changed then LR.leaderChanged(s) end
  else
    local ch = LR.groupChannel()
    if ch then Net.send({ t = "D", sid = s.id, d = list }, ch) end
    -- our copy shows it at once; the leader's next copy settles it (so ours mustn't look newer than that)
    local rev = s.rev
    for _, d in ipairs(list) do S.addDrop(s, d, s.updated) end
    s.rev = rev
    LR.changed("session")
  end
end
Drops.save = save

local function newKey(id)
  seq = seq + 1
  return ("%s:%d:%d:%d"):format(U.bare(U.me()), U.now() % 100000000, id, seq)
end
Drops.newKey = newKey

---------------------------------------------------------------------- corpses (master loot)
--- the loot window opened on the master looter's screen (Core/Rolls.lua tells us): anything new in it goes on the list
function Drops.lootOpened()
  Drops.slotKeys = {}
  local s = writer()
  if not s or not LR.isMasterLooter() then return end
  local target = UnitExists("target") and UnitIsDead("target")
  local src = target and UnitGUID("target") or "corpse"
  local boss = target and UnitName("target") or nil
  -- what's here, and which drops from this corpse are still on it
  local here = {}
  for _, it in ipairs(Rolls.loot()) do here[#here + 1] = it end
  local onCorpse = {}
  for _, d in ipairs(s.drops or {}) do
    if d.src == src and not d.h and not S.dropWin(s, d.k) then
      onCorpse[d.i] = onCorpse[d.i] or {}
      table.insert(onCorpse[d.i], d.k)
    end
  end
  local new = {}
  for _, it in ipairs(here) do
    local known = onCorpse[it.id]
    if known and #known > 0 then
      Drops.slotKeys[it.slot] = table.remove(known, 1)          -- seen it before: the corpse was opened again
    else
      local from = boss or (LR.dropsFrom(s.raid, it.id)[1]) or ""
      local d = { k = newKey(it.id), i = it.id, b = from, at = U.now(), by = U.me(), src = src }
      new[#new + 1] = d
      d.q = it.quality
      d.link = it.link
      Drops.slotKeys[it.slot] = d.k
    end
  end
  Drops.announce(s, new)
  for _, d in ipairs(new) do d.q, d.link = nil, nil end     -- (only for the announcement: not kept)
  save(s, new)
end

--- the raid hears what's on a corpse the first time the loot master opens it: every epic (or better) item, and
--- anything reserved, one line each, saying who reserved it or who it's hard reserved for. Settings: announceLoot.
function Drops.announce(s, list)
  local ch = LR.groupChannel()
  if not ch or not LR.db.settings.announceLoot then return end
  for _, d in ipairs(list) do
    local hr = s.hr[d.i]
    local who = {}
    for _, w in ipairs(S.byItem(s)[d.i] or {}) do
      local left = S.claims(s, w[1], d.i)
      if left > 0 then who[#who + 1] = U.short(w[1]) .. (left > 1 and (" x" .. left) or "") end
    end
    local link = d.link or LR.itemLink(d.i)
    local wish = LR.wishFor(d.i, true)
    local line
    if hr then line = ("%s (hard reserved%s)"):format(link, hr.f ~= "" and (" for " .. hr.f) or "")
    elseif #who > 0 then line = ("%s: reserved by %s"):format(link, table.concat(who, ", "))
    elseif (d.q or 0) >= 4 or #wish > 0 then line = link end
    if line and not hr and #wish > 0 then line = line .. (#who > 0 and "; " or ": ") .. "wishlisted by " .. LR.wishLine(wish) end
    if line then
      for _, l in ipairs(U.chatLines(LR.TAG .. " " .. line, 255)) do LR.say(l, ch) end
    end
  end
end

--- the drop in a slot of the open loot window (nil when not known)
function Drops.forSlot(slot) return Drops.slotKeys[slot] end

---------------------------------------------------------------------- loot messages
--- "Bob receives loot: [Item]": the drop now belongs to Bob; an item we hadn't seen drop goes on the list
--- group loot (no master looter): an item someone won with the game's Need / Greed counts as given out (Settings:
--- recordGroupWins, off to start with; epic and better). Their reserve, when they had one on it, else main spec.
local function recordGroupWin(s, key, id, who, q)
  if not LR.db.settings.recordGroupWins or not LR.isLeader(s) or LR.masterLooter() or (q or 0) < 4 or S.dropWin(s, key) then return end
  local kind = S.claims(s, who, id) > 0 and "SR" or "MS"
  if S.award(s, id, who, kind, nil, U.now(), key) then
    LR.leaderChanged(s)
    LR.print(("%s won %s with the game's group loot: it's on the list of loot given out (%s)."):format(U.short(who), LR.itemLink(id), kind == "SR" and "their reserve" or "main spec"))
  end
end

function Drops.lootMessage(line)
  local who, link = Drops.parseLoot(line)
  local id = idOf(link)
  if not who or not id then return end
  local s = writer()
  if not s then return end
  -- a drop of this item that nobody has yet: the one they won, else one in the open loot window, else the oldest
  local pick, inWindow = nil, {}
  for _, k in pairs(Drops.slotKeys) do inWindow[k] = true end
  for pass = 1, 3 do
    for _, d in ipairs(s.drops or {}) do
      if not pick and d.i == id and not d.h then
        local w = S.dropWin(s, d.k)
        if (pass == 1 and w and U.samePlayer(w.p, who)) or (pass == 2 and inWindow[d.k] and not w) or (pass == 3 and not w) then pick = d end
      end
    end
  end
  if pick then
    save(s, { { k = pick.k, i = pick.i, h = who, ht = U.now() } })
    recordGroupWin(s, pick.k, pick.i, who, qualityOf(link, id))
    -- the master looter gave it out with the game's own menu, not through LootRuler: offer to record it
    if inWindow[pick.k] and not S.dropWin(s, pick.k) and not Rolls.justGave(pick.i, who) and LR.isMasterLooter() and not U.samePlayer(who, U.me())
      and LR.db.settings.remindUnrecorded and LR.UI and LR.UI.unrecordedPrompt then
      LR.UI.unrecordedPrompt(s, pick, who)
    end
    return
  end
  -- not seen dropping (group loot, or picked up before LootRuler was watching): raid loot only
  local q = qualityOf(link, id)
  if q < 3 or not (LR.raidHas(s.raid, id) or q >= 4) then return end
  local ml = LR.masterLooter()
  local key = newKey(id)
  save(s, { { k = key, i = id, b = LR.dropsFrom(s.raid, id)[1] or "", at = U.now(), by = ml, h = who, ht = U.now() } })
  recordGroupWin(s, key, id, who, q)
end

-- drops from the loot master, at the leader
Net.handlers.D = function(msg, channel, sender)
  local s = type(msg.sid) == "string" and LR.session(msg.sid)
  if not s or not LR.isLeader(s) or type(msg.d) ~= "table" or not LR.canRunLoot(sender) then return end
  local changed = false
  for i, d in ipairs(msg.d) do
    if i > 40 then break end
    if S.addDrop(s, d, U.now()) then changed = true end
  end
  if changed then LR.leaderChanged(s) end
end

---------------------------------------------------------------------- what the list says
--- seconds left to trade a drop its holder has had since ht (nil when it doesn't apply)
function Drops.tradeLeft(d)
  if not d.ht then return nil end
  return math.max(0, d.ht + Drops.TRADE_SECONDS - U.now())
end

-- the 2 hours running out: for each item I'm holding to roll out or trade, I'm told 15 minutes before I can't trade
-- it any more, and again at 5: which item, who it's for (or that nobody has won it yet), and how long is left.
-- Only on my own screen. Settings: tradeWarn.
Drops.WARN_AT = { 15 * 60, 5 * 60 }       -- (largest first)
local warned = {}                         -- drop key -> the last mark I was told at
--- the warnings due now (and marks them told): lines of text
function Drops.tradeWarnings()
  local out = {}
  local s = Rolls.session()
  if not s or not LR.db.settings.tradeWarn then return out end
  for _, d in ipairs(s.drops or {}) do
    local left = d.h and U.samePlayer(d.h, U.me()) and Drops.tradeLeft(d)
    local state, w = S.dropState(s, d)
    if left and left > 0 and (state == "held" or state == "toTrade") then
      local mark
      for _, m in ipairs(Drops.WARN_AT) do if left <= m then mark = m end end
      if mark and (not warned[d.k] or warned[d.k] > mark) then
        warned[d.k] = mark
        local mins = math.max(1, math.ceil(left / 60))
        local time = U.plural(mins, "minute")
        out[#out + 1] = state == "toTrade" and ("%s left to trade %s to %s."):format(time, LR.itemLink(d.i), U.short(w.p))
          or ("%s left to roll out and trade %s: nobody has won it yet."):format(time, LR.itemLink(d.i))
      end
    end
  end
  return out
end
local function checkTradeTime()
  if LR.db then
    for _, line in ipairs(Drops.tradeWarnings()) do
      LR.print(line)
      if RaidNotice_AddMessage and RaidWarningFrame then RaidNotice_AddMessage(RaidWarningFrame, U.plain(line), ChatTypeInfo["RAID_WARNING"]) end
      LR.sound(SOUNDKIT.RAID_WARNING or 8959)
    end
  end
  C_Timer.After(30, checkTradeTime)
end
C_Timer.After(30, checkTradeTime)

--- items in my bags that are still to be rolled out or traded, with trade time left, the soonest to run out first:
--- { { d = the drop, state = "held" / "toTrade", left = seconds, to = the winner (toTrade) } }
function Drops.holding()
  local out = {}
  local s = Rolls.session()
  if not s then return out end
  for _, d in ipairs(s.drops or {}) do
    local left = d.h and U.samePlayer(d.h, U.me()) and Drops.tradeLeft(d)
    if left and left > 0 then
      local state, w = S.dropState(s, d)
      if state == "held" or state == "toTrade" then out[#out + 1] = { d = d, state = state, left = left, to = w and w.p } end
    end
  end
  table.sort(out, function(a, b) if a.left ~= b.left then return a.left < b.left end return a.d.k < b.d.k end)
  return out
end

--- what I'm holding, in raid chat: each item still to roll out or trade, with its time left (and who it's for).
--- Returns how many, or nil when there's nothing or no group.
function Drops.postHolding()
  local list = Drops.holding()
  local ch = LR.groupChannel()
  if #list == 0 or not ch then return nil end
  local parts = {}
  for _, x in ipairs(list) do
    local mins = math.max(1, math.floor(x.left / 60))
    local time = mins >= 60 and ("%dh %02dm"):format(math.floor(mins / 60), mins % 60) or (mins .. "m")
    parts[#parts + 1] = ("%s %s%s"):format(LR.itemLink(x.d.i), time, x.state == "toTrade" and (" (for " .. U.short(x.to) .. ")") or "")
  end
  for _, l in ipairs(U.chatLines(LR.TAG .. " Still to roll out or trade, with the time left: " .. table.concat(parts, ", ") .. ".")) do LR.say(l, ch) end
  return #list
end

--- drops I'm holding that someone else won: { { drop, winner } }, the ones for a player when one is given
function Drops.toDeliver(player)
  local out = {}
  local s = Rolls.session()
  if not s then return out end
  for _, d in ipairs(s.drops or {}) do
    if d.h and U.samePlayer(d.h, U.me()) then
      local state, w = S.dropState(s, d)
      if state == "toTrade" and (not player or U.samePlayer(w.p, player)) then out[#out + 1] = { d, w.p } end
    end
  end
  return out
end

---------------------------------------------------------------------- trade help
local trade = { partner = nil, queue = {}, offered = {} }
Drops.trade = trade
local BAGS = 4                                             -- the backpack (0) and four bags

--- the bag and slot of an item we can trade (not locked: one that's in the trade window already is)
local function findInBags(id)
  if not (C_Container and C_Container.GetContainerNumSlots) then return nil end
  for bag = 0, BAGS do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      if C_Container.GetContainerItemID(bag, slot) == id then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if not (info and info.isLocked) then return bag, slot end
      end
    end
  end
end
Drops.findInBags = findInBags

local function tradeOpen() return TradeFrame and TradeFrame:IsShown() end

local function offerNext()
  if not tradeOpen() or #trade.queue == 0 then return end
  local job = table.remove(trade.queue, 1)
  local bag, slot = findInBags(job.id)
  -- using an item while the trade window is open puts it in the trade (with it closed, it would be equipped!)
  if bag and tradeOpen() then
    C_Container.UseContainerItem(bag, slot)
    trade.offered[#trade.offered + 1] = job
    LR.print(("put %s in the trade for %s."):format(LR.itemLink(job.id), U.short(trade.partner)))
  elseif not bag then
    LR.print(("%s for %s isn't in your bags (or can't be traded any more)."):format(LR.itemLink(job.id), U.short(trade.partner)))
  end
  if #trade.queue > 0 then C_Timer.After(0.3, offerNext) end
end

function Drops.tradeShow()
  local name, realm = UnitName("NPC")
  trade.partner = name and (realm and realm ~= "" and (name .. "-" .. realm) or U.full(name)) or nil
  trade.queue, trade.offered, trade.items, trade.enchant = {}, {}, {}, nil
  if trade.partner and LR.Pot then LR.Pot.tradeNote(trade.partner) end      -- GDKP: who owes whom
  if not trade.partner or not LR.db.settings.tradeHelp then return end
  for i, x in ipairs(Drops.toDeliver(trade.partner)) do
    if i > 6 then break end                                -- the trade window takes six items
    trade.queue[#trade.queue + 1] = { id = x[1].i, k = x[1].k }
  end
  if #trade.queue > 0 then C_Timer.After(0.3, offerNext) end
end

local ENCHANT_SLOT = TRADE_ENCHANT_SLOT or 7     -- the trade's "will not be traded" slot: an item to be enchanted

--- opens a trade with someone in the group (an item they won is in my bags; trade help puts it in). Returns true, or
--- false and why not: "busy" (a trade is open), "combat", "away" (not in the group) or "far" (too far to trade)
function Drops.openTrade(player)
  if tradeOpen() then return false, "busy" end
  if InCombatLockdown() then return false, "combat" end
  local unit = LR.unitOf(player)
  if not unit or unit == "player" then return false, "away" end
  if not CheckInteractDistance(unit, 2) then return false, "far" end
  InitiateTrade(unit)
  return true
end

--- what's in the trade on both sides, kept up to date until it goes through: the items ({ link, how many }),
--- the gold, and an enchant (the game says which, once it's cast on the item in the "will not be traded" slot)
function Drops.tradeItems()
  trade.items, trade.gave, trade.got = {}, {}, {}
  for i = 1, 6 do
    local mine, theirs = GetTradePlayerItemLink(i), GetTradeTargetItemLink(i)
    local id = idOf(mine)
    if id then
      trade.items[#trade.items + 1] = id
      trade.gave[#trade.gave + 1] = { mine, select(3, GetTradePlayerItemInfo(i)) or 1 }
    end
    if theirs then trade.got[#trade.got + 1] = { theirs, select(3, GetTradeTargetItemInfo(i)) or 1 } end
  end
  trade.gaveMoney = GetPlayerTradeMoney and GetPlayerTradeMoney() or 0
  trade.gotMoney = GetTargetTradeMoney and GetTargetTradeMoney() or 0
  -- I enchant their item, or they enchant mine
  local theirs, mine = select(6, GetTradeTargetItemInfo(ENCHANT_SLOT)), select(5, GetTradePlayerItemInfo(ENCHANT_SLOT))
  if theirs and GetTradeTargetItemLink(ENCHANT_SLOT) then
    trade.enchant = { byMe = true, item = GetTradeTargetItemLink(ENCHANT_SLOT), what = theirs }
  elseif mine and GetTradePlayerItemLink(ENCHANT_SLOT) then
    trade.enchant = { byMe = false, item = GetTradePlayerItemLink(ENCHANT_SLOT), what = mine }
  else
    trade.enchant = nil
  end
end

--- "12g 50s" (copper in, the game's own coin names aren't needed in chat)
function Drops.money(copper)
  copper = math.floor(tonumber(copper) or 0)
  local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "g" end
  if s > 0 then parts[#parts + 1] = s .. "s" end
  if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
  return table.concat(parts, " ")
end

--- the line telling the raid what a trade was, or nil when nothing changed hands. gave, got: items (links, or
--- { link, how many }: a stack says "x3"); enchant: { byMe, item (link), what (the enchant's name) }, when an item
--- was enchanted in the trade
function Drops.tradeLine(partner, gave, gaveMoney, got, gotMoney, enchant)
  local function side(items, money)
    local list = {}
    for _, x in ipairs(items or {}) do
      local link, n = type(x) == "table" and x[1] or x, type(x) == "table" and x[2] or 1
      list[#list + 1] = (n or 1) > 1 and (link .. " x" .. n) or link
    end
    if (money or 0) > 0 then list[#list + 1] = Drops.money(money) end
    return #list > 0 and table.concat(list, " ") or nil
  end
  local g, r = side(gave, gaveMoney), side(got, gotMoney)
  local who = U.short(partner)
  if enchant then
    -- what was paid for it, and anything else that changed hands
    if enchant.byMe then
      return ("Enchanted %s's %s (%s)%s%s."):format(who, enchant.item, enchant.what, r and (" for " .. r) or "", g and ("; gave " .. g) or "")
    end
    return ("%s put %s on my %s%s%s."):format(who, enchant.what, enchant.item, g and (" for " .. g) or "", r and ("; got " .. r) or "")
  end
  if not g and not r then return nil end
  if g and r then return ("Traded %s to %s for %s."):format(g, who, r) end
  if g then return ("Traded %s to %s."):format(g, who) end
  return ("%s traded me %s."):format(who, r)
end

--- the trade went through: the raid hears what changed hands (the person running loot, when that's on), and
--- every raid drop we gave now belongs to the partner
function Drops.tradeDone()
  local partner = trade.partner
  local enchant = trade.enchant
  local line = partner and Drops.tradeLine(partner, trade.gave, trade.gaveMoney, trade.got, trade.gotMoney, enchant)
  if line and LR.db.settings.tradeAnnounce and IsInGroup() and LR.canRunLoot() then
    for _, l in ipairs(U.chatLines(LR.TAG .. " " .. line, 255)) do LR.say(l, LR.groupChannel()) end
  elseif line and enchant then
    LR.print(line)                     -- (an enchant is worth a note to me, whoever runs loot)
  end
  local gaveMoney, gotMoney = trade.gaveMoney or 0, trade.gotMoney or 0
  trade.gave, trade.got, trade.gaveMoney, trade.gotMoney, trade.enchant = {}, {}, 0, 0, nil
  local s = Rolls.session()
  -- GDKP: gold that changed hands counts towards what they owe, or what they're owed (Core/Gdkp.lua), in the
  -- raid going on, or one that ended with payouts left to do (Core/History.lua). Gold for an enchant doesn't.
  if partner and gotMoney ~= gaveMoney and not enchant then
    local pot = (s and s.gdkp and LR.isLeader(s)) and s or LR.History.owing(partner)
    if pot and LR.Gdkp.paid(pot, partner, (gotMoney - gaveMoney) / 10000, U.now()) then
      if pot.archived then LR.changed("history") else LR.leaderChanged(pot) end
    end
  end
  if not s or not partner then return end
  local list, used = {}, {}
  for _, id in ipairs(trade.items or {}) do
    local pick
    -- the drop they won first, else any of this item we were holding
    for _, x in ipairs(Drops.toDeliver(partner)) do if x[1].i == id and not used[x[1].k] then pick = x[1] break end end
    if not pick then
      for _, d in ipairs(s.drops or {}) do
        if d.i == id and d.h and U.samePlayer(d.h, U.me()) and not used[d.k] then pick = d break end
      end
    end
    if pick then
      used[pick.k] = true
      list[#list + 1] = { k = pick.k, i = pick.i, h = partner, ht = pick.ht }
    end
  end
  trade.items = {}
  save(s, list)
end

---------------------------------------------------------------------- events
local events = CreateFrame("Frame")
for _, e in ipairs({ "CHAT_MSG_LOOT", "TRADE_SHOW", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "TRADE_MONEY_CHANGED",
  "TRADE_ACCEPT_UPDATE", "TRADE_UPDATE", "UI_INFO_MESSAGE", "TRADE_CLOSED" }) do
  events:RegisterEvent(e)
end
events:SetScript("OnEvent", function(_, event, a1, a2)
  if not LR.db then return end
  local ok, err = pcall(function()
    if event == "CHAT_MSG_LOOT" then Drops.lootMessage(a1)
    elseif event == "TRADE_SHOW" then Drops.tradeShow()
    elseif event == "TRADE_PLAYER_ITEM_CHANGED" or event == "TRADE_TARGET_ITEM_CHANGED" or event == "TRADE_MONEY_CHANGED"
      or event == "TRADE_ACCEPT_UPDATE" or event == "TRADE_UPDATE" then Drops.tradeItems()
    elseif event == "UI_INFO_MESSAGE" then
      if a2 == ERR_TRADE_COMPLETE or a1 == ERR_TRADE_COMPLETE then Drops.tradeDone() end
    elseif event == "TRADE_CLOSED" then trade.queue = {}
    end
  end)
  if not ok then geterrorhandler()(err) end
end)
