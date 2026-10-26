-- A stand-in for the game's servers, so several players' clients can run LootRuler side by side in one
-- test: each client is its own copy of the WoW stand-in (tests/wow/mock.lua) with its own globals, frames,
-- timers and saved variables. The server carries addon messages (group, guild and whisper channels, with
-- the sender's name attached by the "server", as in the game), whispers and raid chat between them, and
-- knows who is grouped with whom, who leads, who's in which guild and who's online.
local L = require("load")
local MOCK_PATH = "tests/wow/mock.lua"

local Server = {}
Server.__index = Server

function Server.new(root)
  return setmetatable({ root = root or ".", players = {}, queue = {}, group = nil, clock = 0, chat = {} }, Server)
end

local CLASS_NAME = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
  SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }

local function full(p) return p.name .. "-" .. p.realm end
Server.full = full

--- the name another player's client sees: "Name" on the same realm, "Name-Realm" otherwise
local function seenAs(p, viewer) if viewer and viewer.realm == p.realm then return p.name end return full(p) end

function Server:find(name)
  for _, p in ipairs(self.players) do
    if full(p):lower() == name:lower() or (not name:find("-") and p.name:lower() == name:lower()) then return p end
  end
end

Server.GUILD_RANKS = { "Guild Master", "Officer", "Veteran", "Member", "Initiate" }

--- a player without the addon (they can whisper and be grouped)
function Server:player(o)
  local p = { name = o.name, realm = o.realm or "Dreamscythe", class = o.class or "WARRIOR", guild = o.guild, rank = o.rank,
    faction = o.faction or "Alliance", online = true, inbox = {}, client = false, bags = {}, tradeItems = {} }
  table.insert(self.players, p)
  return p
end

--- a player running LootRuler; savedVariables: carry a LootRulerDB over (logging in again)
function Server:client(o, savedVariables)
  local p = o.client ~= nil and o or self:player(o)
  p.online = true
  local M = dofile(MOCK_PATH)
  local G = M.env({ name = p.name, realm = p.realm, class = p.class:lower() })
  p.M, p.G, p.client = M, G, true
  self:install(p)
  G.LootRulerDB = savedVariables
  if self.gargul and p.gargul then self.gargul(p) end
  p.LR = L.load(self.root, G)
  M.fire("ADDON_LOADED", "LootRuler")
  M.fire("PLAYER_LOGIN")
  return p
end

function Server:logout(p)
  p.online = false
  if p.M then p.M.fire("PLAYER_LOGOUT") end
  local db = p.G and p.G.LootRulerDB
  p.M, p.G, p.LR, p.client = nil, nil, nil, false
  self:rosterChanged()
  return db
end

function Server:login(p, db) self:client(p, db) self:rosterChanged() end

---------------------------------------------------------------------- the group
function Server:setGroup(list, leader, raid)
  self.group = { members = list, leader = leader, raid = raid ~= false, assists = {} }
  for _, p in ipairs(list) do p.inGroup = true end
  self:rosterChanged()
end
function Server:leaveGroup(p)
  if not self.group then return end
  for i, m in ipairs(self.group.members) do if m == p then table.remove(self.group.members, i) break end end
  p.inGroup = false
  self:rosterChanged(p)
end
function Server:inGroup(p) return self.group and p.inGroup end
--- p says yes to an invite (a party holds five: past that, the invite fails as the game's does)
function Server:acceptInvite(p)
  local ok = false
  for i, inv in ipairs(self.invites or {}) do
    if inv.name:lower() == p.name:lower() or inv.name:lower() == (p.name .. "-" .. p.realm):lower() then
      table.remove(self.invites, i)
      if not self.group then self.group = { members = { inv.from }, leader = inv.from, raid = false, assists = {} } inv.from.inGroup = true end
      if not self.group.raid and #self.group.members >= 5 then return false end
      table.insert(self.group.members, p)
      p.inGroup = true
      ok = true
      break
    end
  end
  if ok then self:rosterChanged() end
  return ok
end
function Server:rosterChanged(extra)
  for _, q in ipairs(self.players) do
    if q.client and (self:inGroup(q) or q == extra) then q.M.fire("GROUP_ROSTER_UPDATE") end
  end
end

---------------------------------------------------------------------- messages
function Server:deliver(fn) table.insert(self.queue, fn) end

--- delivers everything sent so far (and whatever that sends), in order
function Server:pump()
  local n = 0
  while #self.queue > 0 do
    local fn = table.remove(self.queue, 1)
    fn()
    n = n + 1
    if n > 100000 then error("message storm") end
  end
end

--- lets time pass for every client (timers, throttled sends) and delivers messages
function Server:tick(seconds, step)
  step = step or 0.1
  local t = 0
  repeat
    self.clock = self.clock + step
    for _, p in ipairs(self.players) do if p.client then p.M.tick(step) end end
    self:pump()
    t = t + step
  until t >= (seconds or step) - 1e-9
end

function Server:addonMessage(from, prefix, text, channel, target)
  local recipients = {}
  if channel == "RAID" or channel == "PARTY" then
    if not self:inGroup(from) then return 5 end              -- NotInGroup
    for _, q in ipairs(self.group.members) do recipients[#recipients + 1] = q end
  elseif channel == "GUILD" then
    if not from.guild then return 7 end
    for _, q in ipairs(self.players) do if q.guild == from.guild then recipients[#recipients + 1] = q end end
  elseif channel == "WHISPER" then
    local q = target and self:find(target)
    if not q or not q.online then
      self:deliver(function() if from.client then from.M.fire("CHAT_MSG_SYSTEM", "No player named '" .. tostring(target) .. "' is currently playing.") end end)
      return 0
    end
    recipients[1] = q
  else
    return 4
  end
  for _, q in ipairs(recipients) do
    self:deliver(function()
      if q.client and q.online and q.prefixes and q.prefixes[prefix] then
        q.M.fire("CHAT_MSG_ADDON", prefix, text, channel, full(from), full(q), 0, 0, "", 0)
      end
    end)
  end
  return 0
end

function Server:chatMessage(from, text, channel, target)
  if #text > 255 then error("chat message over 255 characters: " .. #text) end
  table.insert(self.chat, { from = full(from), text = text, channel = channel, target = target })
  if channel == "WHISPER" then
    local q = self:find(target)
    if not q or not q.online then return end
    self:deliver(function()
      table.insert(q.inbox, { from = full(from), text = text })
      if q.client then q.M.fire("CHAT_MSG_WHISPER", text, full(from), "", "", "", "", 0, 0, "", 0, 1, "") end
      if from.client then from.M.fire("CHAT_MSG_WHISPER_INFORM", text, full(q)) end
    end)
  elseif channel == "RAID" or channel == "PARTY" or channel == "RAID_WARNING" then
    for _, q in ipairs(self.group and self.group.members or {}) do
      self:deliver(function()
        table.insert(q.inbox, { from = full(from), text = text, channel = channel })
        if q.client then q.M.fire("CHAT_MSG_" .. channel, text, full(from)) end
      end)
    end
  end
end

--- a player (with or without the addon) whispers someone
function Server:whisper(from, to, text) self:chatMessage(from, text, "WHISPER", full(to)) end

---------------------------------------------------------------------- the client's view of all this
function Server:install(p)
  local srv, G, M = self, p.G, p.M
  p.prefixes = {}
  local function members() return srv:inGroup(p) and srv.group.members or { p } end
  local function unitPlayer(unit)
    if unit == "player" then return p end
    local list = {}
    for _, q in ipairs(members()) do if q ~= p then list[#list + 1] = q end end
    local n = unit and tonumber(unit:match("^party(%d+)$"))
    if n then return list[n] end
    n = unit and tonumber(unit:match("^raid(%d+)$"))
    if n then return members()[n] end
  end
  G.Ambiguate = function(name, context)
    local n, r = name:match("^(.-)%-(.+)$")
    if not n then return name end
    if context == "short" or r == p.realm then return n end
    return name
  end
  G.GetServerTime = function() return 1760000000 + math.floor(srv.clock) end
  G.GetNormalizedRealmName = function() return p.realm end
  G.GetRealmName = function() return p.realm end
  G.UnitFullName = function(unit) local q = unitPlayer(unit) if q then return q.name, q.realm end end
  G.UnitName = function(unit)
    if unit == "target" and p.target then return p.target.name end
    if unit == "NPC" or unit == "npc" then
      local q = p.trading
      if not q then return nil end
      if q.realm == p.realm then return q.name, nil end
      return q.name, q.realm
    end
    local q = unitPlayer(unit)
    if not q then return nil end
    if q.realm == p.realm then return q.name, nil end
    return q.name, q.realm
  end
  G.UnitClass = function(unit) local q = unitPlayer(unit) if q then return CLASS_NAME[q.class], q.class, 1 end end
  G.UnitExists = function(unit) if unit == "target" then return p.target ~= nil end return unitPlayer(unit) ~= nil end
  G.UnitIsDead = function(unit) return unit == "target" and p.target ~= nil and p.target.dead == true end
  G.UnitGUID = function(unit) if unit == "target" and p.target then return p.target.guid end end
  -- bags: the backpack only, 16 slots; { id, link, locked }
  p.bags = p.bags or {}
  local function bagItem(bag, slot) return bag == 0 and p.bags[slot] or nil end
  G.C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end,
    GetContainerItemID = function(bag, slot) local it = bagItem(bag, slot) return it and it.id or nil end,
    GetContainerItemInfo = function(bag, slot)
      local it = bagItem(bag, slot)
      if it then return { itemID = it.id, hyperlink = it.link, isLocked = it.locked or false, stackCount = it.count or 1 } end
    end,
    UseContainerItem = function(bag, slot)
      local it = bagItem(bag, slot)
      if not it then error("UseContainerItem on an empty slot") end
      if not (p.trading and G.TradeFrame:IsShown()) then error("used " .. it.id .. " with no trade open: the game would equip it") end
      if #p.tradeItems >= 6 then return end
      it.locked = true
      table.insert(p.tradeItems, it)
      srv:deliver(function() p.M.fire("TRADE_PLAYER_ITEM_CHANGED", #p.tradeItems) end)
    end,
  }
  -- a trade's slots: 1 to 6 are traded; 7 holds an item that isn't, to be enchanted (the game's TRADE_ENCHANT_SLOT)
  local function tradeSlot(q, i)
    if not q then return nil end
    if i == 7 then return q.tradeKeep end
    return q.tradeItems and q.tradeItems[i]
  end
  local function slotInfo(it)
    local d = srv.itemInfo and srv.itemInfo(it.id)
    return d and d.name or ("item " .. it.id), 134400, it.count or 1, d and d.quality or 4
  end
  G.GetTradePlayerItemLink = function(i) local it = tradeSlot(p, i) return it and it.link end
  G.GetTradeTargetItemLink = function(i) local it = tradeSlot(p.trading, i) return it and it.link end
  -- (the game's order: name, texture, numItems, quality, enchantment, canLoseTransmog, isBound, itemID)
  G.GetTradePlayerItemInfo = function(i)
    local it = tradeSlot(p, i)
    if not it then return nil end
    local name, tex, n, q = slotInfo(it)
    return name, tex, n, q, it.enchant, false, false, it.id
  end
  -- (name, texture, numItems, quality, isUsable, enchantment, itemID)
  G.GetTradeTargetItemInfo = function(i)
    local it = tradeSlot(p.trading, i)
    if not it then return nil end
    local name, tex, n, q = slotInfo(it)
    return name, tex, n, q, true, it.enchant, it.id
  end
  -- opening a trade with someone close enough (Server.farAway: who's too far)
  G.CheckInteractDistance = function(unit) local q = unitPlayer(unit) return q ~= nil and q.online and not (srv.farAway and srv.farAway[q]) end
  G.InitiateTrade = function(unit)
    local q = unitPlayer(unit)
    if q and q ~= p and not (srv.farAway and srv.farAway[q]) then srv:deliver(function() srv:openTrade(p, q) end) end
  end
  G.GetPlayerTradeMoney = function() return p.trading and p.tradeMoney or 0 end
  G.GetTargetTradeMoney = function() return p.trading and p.trading.tradeMoney or 0 end
  G.UnitIsConnected = function(unit) local q = unitPlayer(unit) return q and q.online or false end
  G.UnitIsGroupLeader = function(unit) local q = unitPlayer(unit) return srv:inGroup(p) and srv.group.leader == q or false end
  G.UnitIsGroupAssistant = function(unit) local q = unitPlayer(unit) return srv:inGroup(p) and q and srv.group.assists[q] or false end
  G.UnitFactionGroup = function() return p.faction, p.faction end
  G.IsInGroup = function() return srv:inGroup(p) and true or false end
  G.IsInRaid = function() return srv:inGroup(p) and srv.group.raid or false end
  G.IsInGuild = function() return p.guild ~= nil end
  -- the guild: ranks are numbered from 0 (the guild master); o.rank when the player was made (default 3)
  local function guildmates()
    local list = {}
    for _, q in ipairs(srv.players) do if p.guild and q.guild == p.guild then list[#list + 1] = q end end
    return list
  end
  G.GetGuildInfo = function(unit)
    local q = unit == "player" and p or unitPlayer(unit)
    if not q or not q.guild then return nil end
    return q.guild, Server.GUILD_RANKS[(q.rank or 3) + 1], q.rank or 3, nil
  end
  G.GetNumGuildMembers = function()
    if not p.guild then return 0, 0 end
    local list, on = guildmates(), 0
    for _, q in ipairs(list) do if q.online then on = on + 1 end end
    return #list, on, on
  end
  G.GetGuildRosterInfo = function(i)
    local q = guildmates()[i]
    if not q then return nil end
    return q.name .. "-" .. q.realm, Server.GUILD_RANKS[(q.rank or 3) + 1], q.rank or 3, 70, CLASS_NAME[q.class], "Shattrath City", "", "", q.online, 0, q.class
  end
  G.C_GuildInfo = { GuildRoster = function()
    if p.guild then srv:deliver(function() if p.client then p.M.fire("GUILD_ROSTER_UPDATE", false) end end) end
  end }
  G.IsGuildLeader = function() return p.guild ~= nil and (p.rank or 3) == 0 end
  G.GuildControlGetNumRanks = function() return p.guild and #Server.GUILD_RANKS or 0 end
  G.GuildControlGetRankName = function(i) return p.guild and Server.GUILD_RANKS[i] or nil end
  G.GetNumGroupMembers = function() return srv:inGroup(p) and #srv.group.members or 0 end
  G.GetRaidRosterInfo = function(i)
    local q = srv:inGroup(p) and srv.group.members[i]
    if not q then return nil end
    return seenAs(q, p), srv.group.leader == q and 2 or (srv.group.assists[q] and 1 or 0), q.subgroup or math.ceil(i / 5), 70, CLASS_NAME[q.class], q.class, "Karazhan", q.online, false, "NONE", false
  end
  -- forming the raid (the leader; an assistant may move people): invites wait for Server:acceptInvite
  G.ConvertToRaid = function()
    if srv:inGroup(p) and srv.group.leader == p and not srv.group.raid then srv.group.raid = true srv:deliver(function() srv:rosterChanged() end) end
  end
  local function mayMove() return srv:inGroup(p) and srv.group.raid and (srv.group.leader == p or srv.group.assists[p]) end
  local function groupOf(i) local q = srv.group.members[i] return q and (q.subgroup or math.ceil(i / 5)) end
  G.SetRaidSubgroup = function(i, g)
    if not mayMove() or not srv.group.members[i] then return end
    local n = 0
    for j = 1, #srv.group.members do if groupOf(j) == g then n = n + 1 end end
    if n >= 5 or (srv.inCombat and srv.inCombat[p]) then return end
    srv.group.members[i].subgroup = g
    srv:deliver(function() srv:rosterChanged() end)
  end
  G.SwapRaidSubgroup = function(i, j)
    if not mayMove() or not srv.group.members[i] or not srv.group.members[j] or (srv.inCombat and srv.inCombat[p]) then return end
    local gi, gj = groupOf(i), groupOf(j)
    srv.group.members[i].subgroup, srv.group.members[j].subgroup = gj, gi
    srv:deliver(function() srv:rosterChanged() end)
  end
  G.GetFramerate = function() return 60 end
  G.Enum = { TooltipDataType = { Item = 0 }, LootMethod = { Freeforall = 0, Roundrobin = 1, Masterlooter = 2, Group = 3, Needbeforegreed = 4, Personal = 5 },
    SendAddonMessageResult = { Success = 0, InvalidPrefix = 1, InvalidMessage = 2, AddonMessageThrottle = 3, InvalidChatType = 4,
    NotInGroup = 5, TargetRequired = 6, InvalidChannel = 7, ChannelThrottle = 8, GeneralError = 9, NotInGuild = 10 } }
  local function sendAddon(prefix, text, channel, target)
    if type(prefix) ~= "string" or #prefix > 16 then error("bad addon prefix " .. tostring(prefix) .. " " .. debug.traceback()) end
    if type(text) ~= "string" or #text > 255 then error("addon message over 255 characters") end
    if not p.online then return 9 end
    return srv:addonMessage(p, prefix, text, channel, target)
  end
  local function sendChat(text, channel, language, target)
    if type(text) ~= "string" then error("SendChatMessage needs text") end
    srv:chatMessage(p, text, channel, target)
  end
  G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix) p.prefixes[prefix] = true return true end,
    IsAddonMessagePrefixRegistered = function(prefix) return p.prefixes[prefix] == true end,
    SendAddonMessage = sendAddon,
    SendAddonMessageLogged = sendAddon,
    SendChatMessage = sendChat,
  }
  G.SendChatMessage = sendChat
  G.C_BattleNet = { SendGameData = function() return 0 end }
  G.BNSendGameData = function() end
  -- items: the test can say which ones the client has loaded (names from the data until then)
  G.C_Item = {
    GetItemInfo = function(id)
      local it = srv.itemInfo and srv.itemInfo(id)
      if not it then return nil end
      return it.name, it.link, it.quality, 115, 70, "Armor", "Plate", 1, "INVTYPE_HAND", 133000 + id % 100
    end,
    GetItemIconByID = function(id) return 133000 + id % 1000 end,
    RequestLoadItemDataByID = function(id) p.requested = (p.requested or 0) + 1 end,
  }
  G.IsModifiedClick = function() return false end
  G.ChatEdit_InsertLink = function() return false end
  G.RandomRoll = function(lo, hi) srv:roll(p, tonumber(lo), tonumber(hi)) end
  G.C_PartyInfo = {
    InviteUnit = function(name)
      if type(name) ~= "string" then error("InviteUnit needs a name") end
      srv.invites = srv.invites or {}
      table.insert(srv.invites, { from = p, name = name })
    end,
    GetLootMethod = function()
      local ml = srv:inGroup(p) and srv.masterLooter
      if not ml then return 3 end
      if srv.group.raid then
        for i, q in ipairs(srv.group.members) do if q == ml then return 2, nil, i end end
        return 2
      end
      if ml == p then return 2, 0 end
      local others = {}
      for _, q in ipairs(members()) do if q ~= p then others[#others + 1] = q end end
      for i, q in ipairs(others) do if q == ml then return 2, i end end
      return 2
    end,
  }
  -- a slot that's been given out stays empty (the others keep their places) until the corpse is opened again
  local function lootItem(slot) local it = p.loot and p.loot[slot] return it and not it.taken and it or nil end
  G.GetNumLootItems = function() return p.loot and #p.loot or 0 end
  G.LootSlotHasItem = function(slot) return lootItem(slot) ~= nil end
  G.GetLootSlotLink = function(slot)
    local it = lootItem(slot)
    if not it then return nil end
    local info = srv.itemInfo and srv.itemInfo(it.id)
    return info and info.link or ("|cffa335ee|Hitem:%d::::::::70:::::|h[item %d]|h|r"):format(it.id, it.id)
  end
  G.GetLootSlotInfo = function(slot)
    local it = lootItem(slot)
    if not it then return nil end
    local info = srv.itemInfo and srv.itemInfo(it.id)
    return 133000 + it.id % 1000, info and info.name or ("item " .. it.id), 1, nil, it.quality, false
  end
  G.GetMasterLootCandidate = function(slot, i)
    if not lootItem(slot) or srv.masterLooter ~= p then return nil end
    local q = srv:candidates()[i]
    if q then return seenAs(q, p), CLASS_NAME[q.class], q.class end
  end
  G.GiveMasterLoot = function(slot, i)
    local it = lootItem(slot)
    local q = srv:candidates()[i]
    if not it or not q or srv.masterLooter ~= p then error("GiveMasterLoot with nothing to give") end
    srv.given = srv.given or {}
    table.insert(srv.given, { id = it.id, to = q })
    it.taken = true
    srv:lootTo(q, it.id)
    srv:deliver(function() p.M.fire("LOOT_SLOT_CLEARED", slot) end)
  end
  G.ChatFrameUtil = { AddMessageEventFilter = function(event, fn) p.filters = p.filters or {} p.filters[event] = p.filters[event] or {} table.insert(p.filters[event], fn) end }
  -- the class colours (Blizzard_SharedXML/TBC/ClassColors.lua)
  local COLORS = { HUNTER = { 0.67, 0.83, 0.45 }, WARLOCK = { 0.53, 0.53, 0.93 }, PRIEST = { 1, 1, 1 }, PALADIN = { 0.96, 0.55, 0.73 },
    MAGE = { 0.25, 0.78, 0.92 }, ROGUE = { 1, 0.96, 0.41 }, DRUID = { 1, 0.49, 0.04 }, SHAMAN = { 0, 0.44, 0.87 }, WARRIOR = { 0.78, 0.61, 0.43 } }
  G.RAID_CLASS_COLORS = {}
  for token in pairs(CLASS_NAME) do
    local c = COLORS[token] or { 0.8, 0.8, 0.8 }
    G.RAID_CLASS_COLORS[token] = { r = c[1], g = c[2], b = c[3], colorStr = ("ff%02x%02x%02x"):format(c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5) }
  end
end

---------------------------------------------------------------------- rolling and master loot
function Server:setAssist(p, on) self.group.assists[p] = on and true or nil self:rosterChanged() end
--- master loot, with p as the master looter (nil: group loot)
function Server:setMasterLooter(p) self.masterLooter = p self:rosterChanged() end

--- p rolls lo-hi: everyone in the group (and p) sees "Name rolls n (lo-hi)". n: the result (else the next
--- one the test queued for p with Server:willRoll, else a made-up one)
function Server:roll(p, lo, hi, n)
  lo, hi = lo or 1, hi or 100
  if not n then
    local q = self.rolls and self.rolls[p]
    n = q and table.remove(q, 1)
    if not n then self.rollSeed = ((self.rollSeed or 7) * 31 + 17) % 1000 n = lo + self.rollSeed % (hi - lo + 1) end
  end
  local everyone = self:inGroup(p) and self.group.members or { p }
  for _, q in ipairs(everyone) do
    self:deliver(function()
      if q.client and q.online then q.M.fire("CHAT_MSG_SYSTEM", ("%s rolls %d (%d-%d)"):format(seenAs(p, q), n, lo, hi)) end
    end)
  end
  return n
end
function Server:willRoll(p, ...) self.rolls = self.rolls or {} self.rolls[p] = self.rolls[p] or {} for _, n in ipairs({ ... }) do table.insert(self.rolls[p], n) end end

--- p (the master looter) opens a corpse with these items: { { id, quality }, ... }
function Server:openLoot(p, items)
  p.loot = {}
  for _, it in ipairs(items) do p.loot[#p.loot + 1] = { id = it[1], quality = it[2] or 4 } end
  p.G.LootFrame:Show()
  p.M.fire("LOOT_OPENED", 0, false)
end
function Server:closeLoot(p) p.loot = nil p.G.LootFrame:Hide() p.M.fire("LOOT_CLOSED") end

--- puts an item in p's bags and tells the group "p receives loot: [item]" (master loot, or a roll won)
function Server:link(id)
  local info = self.itemInfo and self.itemInfo(id)
  return info and info.link or ("|cffa335ee|Hitem:%d::::::::70:::::|h[item %d]|h|r"):format(id, id)
end
function Server:lootTo(p, id)
  local link = self:link(id)
  p.bags = p.bags or {}
  local slot = 1
  while p.bags[slot] do slot = slot + 1 end
  p.bags[slot] = { id = id, link = link }
  for _, q in ipairs(self:inGroup(p) and self.group.members or { p }) do
    self:deliver(function()
      if q.client and q.online then
        q.M.fire("CHAT_MSG_LOOT", q == p and ("You receive loot: %s."):format(link) or ("%s receives loot: %s."):format(seenAs(p, q), link))
      end
    end)
  end
end
--- p targets a dead boss (for the loot window)
function Server:target(p, name, guid) p.target = name and { name = name, guid = guid or ("Creature-0-" .. name), dead = true } or nil end

--- puts a stack of an item in p's bags (count: how many in it); returns it
function Server:giveItem(p, id, count)
  p.bags = p.bags or {}
  local slot = 1
  while p.bags[slot] do slot = slot + 1 end
  p.bags[slot] = { id = id, link = self:link(id), count = count }
  return p.bags[slot], slot
end
--- p puts one of their items in the trade's "will not be traded" slot, to have it enchanted
function Server:tradeToEnchant(p, it)
  p.tradeKeep = it
  if p.client then self:deliver(function() p.M.fire("TRADE_PLAYER_ITEM_CHANGED", 7) end) end
  local q = p.trading
  if q and q.client then self:deliver(function() q.M.fire("TRADE_TARGET_ITEM_CHANGED", 7) end) end
end
--- p casts an enchant on the item in the other side's "will not be traded" slot
function Server:enchantInTrade(p, name)
  local q = p.trading
  q.tradeKeep.enchant = name
  if p.client then self:deliver(function() p.M.fire("TRADE_TARGET_ITEM_CHANGED", 7) end) end
  if q.client then self:deliver(function() q.M.fire("TRADE_PLAYER_ITEM_CHANGED", 7) end) end
end

--- a opens a trade with b
function Server:openTrade(a, b)
  a.trading, b.trading = b, a
  a.tradeItems, b.tradeItems = {}, {}
  a.tradeKeep, b.tradeKeep = nil, nil
  a.tradeMoney, b.tradeMoney = 0, 0
  for _, p in ipairs({ a, b }) do if p.client then p.G.TradeFrame:Show() p.M.fire("TRADE_SHOW") end end
end
--- p puts gold in the trade (copper)
function Server:setTradeMoney(p, copper)
  p.tradeMoney = copper
  for _, q in ipairs({ p, p.trading }) do
    if q and q.client then local who = q self:deliver(function() who.M.fire("TRADE_MONEY_CHANGED") end) end
  end
end

--- both accept: a's items go to b
function Server:completeTrade(a)
  local b = a.trading
  for _, it in ipairs(a.tradeItems) do
    for slot, x in pairs(a.bags) do if x == it then a.bags[slot] = nil end end
    it.locked = nil
    local slot = 1
    while b.bags[slot] do slot = slot + 1 end
    b.bags[slot] = it
  end
  for _, p in ipairs({ a, b }) do
    if p.client then
      p.M.fire("TRADE_ACCEPT_UPDATE", 1, 1)
      p.M.fire("TRADE_CLOSED")
      p.M.fire("UI_INFO_MESSAGE", 0, "Trade complete.")
      p.G.TradeFrame:Hide()
    end
    p.trading, p.tradeItems, p.tradeMoney, p.tradeKeep = nil, {}, 0, nil
  end
end

--- who can be given loot: everyone in the group who's online and not out of range (Server.farAway)
function Server:candidates()
  local out = {}
  for _, q in ipairs(self.group and self.group.members or {}) do
    if q.online and not (self.farAway and self.farAway[q]) then out[#out + 1] = q end
  end
  return out
end

--- whether a client's chat filters would hide a message
function Server:hidden(p, event, text)
  for _, fn in ipairs(p.filters and p.filters[event] or {}) do if fn(nil, event, text) then return true end end
  return false
end

return Server
