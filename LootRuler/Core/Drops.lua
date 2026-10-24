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
      Drops.slotKeys[it.slot] = d.k
    end
  end
  save(s, new)
end

--- the drop in a slot of the open loot window (nil when not known)
function Drops.forSlot(slot) return Drops.slotKeys[slot] end

---------------------------------------------------------------------- loot messages
--- "Bob receives loot: [Item]": the drop now belongs to Bob; an item we hadn't seen drop goes on the list
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
    return
  end
  -- not seen dropping (group loot, or picked up before LootRuler was watching): raid loot only
  local q = qualityOf(link, id)
  if q < 3 or not (LR.raidHas(s.raid, id) or q >= 4) then return end
  local ml = LR.masterLooter()
  save(s, { { k = newKey(id), i = id, b = LR.dropsFrom(s.raid, id)[1] or "", at = U.now(), by = ml, h = who, ht = U.now() } })
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
  trade.queue, trade.offered, trade.items = {}, {}, {}
  if not trade.partner or not LR.db.settings.tradeHelp then return end
  for i, x in ipairs(Drops.toDeliver(trade.partner)) do
    if i > 6 then break end                                -- the trade window takes six items
    trade.queue[#trade.queue + 1] = { id = x[1].i, k = x[1].k }
  end
  if #trade.queue > 0 then C_Timer.After(0.3, offerNext) end
end

--- what we're giving in the trade, kept up to date until it goes through
function Drops.tradeItems()
  trade.items = {}
  for i = 1, 6 do
    local id = idOf(GetTradePlayerItemLink(i))
    if id then trade.items[#trade.items + 1] = id end
  end
end

--- the trade went through: every raid drop we gave now belongs to the partner
function Drops.tradeDone()
  local s = Rolls.session()
  local partner = trade.partner
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
for _, e in ipairs({ "CHAT_MSG_LOOT", "TRADE_SHOW", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_ACCEPT_UPDATE", "UI_INFO_MESSAGE", "TRADE_CLOSED" }) do
  events:RegisterEvent(e)
end
events:SetScript("OnEvent", function(_, event, a1, a2)
  if not LR.db then return end
  local ok, err = pcall(function()
    if event == "CHAT_MSG_LOOT" then Drops.lootMessage(a1)
    elseif event == "TRADE_SHOW" then Drops.tradeShow()
    elseif event == "TRADE_PLAYER_ITEM_CHANGED" or event == "TRADE_ACCEPT_UPDATE" then Drops.tradeItems()
    elseif event == "UI_INFO_MESSAGE" then
      if a2 == ERR_TRADE_COMPLETE or a1 == ERR_TRADE_COMPLETE then Drops.tradeDone() end
    elseif event == "TRADE_CLOSED" then trade.queue = {}
    end
  end)
  if not ok then geterrorhandler()(err) end
end)
