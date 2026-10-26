-- Keeping everyone in step. The raid leader's addon holds the session that counts and sends a copy of it
-- (reserves and all) to the group, and to the guild when the leader shares it there, every time it
-- changes. Raiders' addons send the leader their own picks; the leader checks them against the rules and
-- answers. Players without the addon whisper the leader instead (Core/Whisper.lua).
--
-- Raiders can pick while the leader is offline or out of the group: their picks are kept and sent as soon
-- as the leader's addon is heard from again.
--
-- Messages (LibSerialize + LibDeflate over AceComm, prefix "LootRuler"):
--   T  leader -> group / guild    the whole session
--   E  leader -> group / guild    the session was ended
--   Q  anyone -> group / guild    "which sessions are open?" (leaders answer with T)
--   P  raider -> leader           my picks for session id: { c = class, i = items }
--   A  leader -> raider           the answer to P: ok, or why not, with the picks the leader now has
--   R, X, N                       rolling out loot (Core/Rolls.lua)
--   D                             the raid's drops (Core/Drops.lua)
--   V  anyone -> group            "I have LootRuler, this version" (on joining a group, and when asked)
-- Every message also says what the sender's addon can do (fl): 1 = it can take over a session (a new leader).
-- Who sent a message is told by the game, so nobody can send picks in someone else's name or a session
-- for a leader who isn't them.
--
-- Older and newer versions work together. Every message says which version sent it (av). A version
-- ignores message types and fields it doesn't know, and keeps what it doesn't understand (a raid it
-- doesn't know, a kind of award it doesn't know) instead of throwing the whole thing away. A message only
-- an up-to-date version can handle says so (mv: the oldest protocol that understands it) and older
-- versions leave it alone. Changes should be new fields and new message types, never new meanings for old
-- ones; `v` stays 1 because the first release ignores anything with a higher one.
local _, LR = ...
local U, S = LR.U, LR.Session

local PROTOCOL = 1
local FEATURES = 1          -- what this version can do, sent as fl (see the top)
local KEEP_DAYS = 7

local Net = {}
LR.Net = Net
local AceComm = LibStub("AceComm-3.0")
local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")
AceComm:Embed(Net)

local db              -- LootRulerDB: sessions, mine, current, settings
local listeners = {}

--- something changed that the window shows
function LR.changed(what)
  for _, fn in ipairs(listeners) do fn(what) end
end
function LR.onChange(fn) listeners[#listeners + 1] = fn end

function LR.print(msg) print("|cffffd100LootRuler|r: " .. msg) end

--- every LootRuler sound goes through here: none when they're switched off (Settings: sounds), on the channel picked
--- (soundChannel); a window's own click sound (ui) stays on the game's effects channel
LR.SOUND_CHANNELS = { { "Master", "Main" }, { "SFX", "Effects" }, { "Dialog", "Dialog" }, { "Ambience", "Ambience" } }
function LR.sound(id, ui)
  if not db or not db.settings.sounds or not id then return end
  PlaySound(id, ui and "SFX" or db.settings.soundChannel)
end

---------------------------------------------------------------------- saved state
-- every option, and what it is until changed (the Settings tab, UI/Settings.lua)
LR.DEFAULTS = {
  hideWhispers = true,     -- "!lr" messages (whispers and raid chat) and the answers don't show in my chat
  rollWindow = true,       -- roll windows pop up
  rollOnlyMine = false,    -- ...only for items I may roll on
  rollHideUnusable = false, -- ...not for items my class can't use (open to everyone)
  rollCloseAfter = false,  -- my roll window closes once I've rolled
  rollScale = 1,           -- how big roll windows are (UI.ROLL_SIZES)
  reservedAlert = true,    -- an item I reserved is rolled out: told on screen, with a sound (UI/RollFrame.lua)
  shareGear = true,
  inspectGear = true,      -- running loot: the game's inspect shows what raiders without LootRuler wear (Core/Rolls.lua)        -- when an item is rolled out, the loot master's addon is told what I wear in its slot
  sounds = true,           -- LootRuler's sounds (LR.sound)
  soundChannel = "Master", -- ...on this channel (LR.SOUND_CHANNELS)
  rollList = true,         -- roll windows list everyone's rolls that count, best first (UI/RollFrame.lua)
  tradeHelp = true,        -- won items go into trades with their winners
  tradeAnnounce = true,    -- when I'm running loot, the raid hears what I trade and to whom
  tradeTimers = true,      -- a bar for each item I hold to roll out or trade, with the time left (UI/Timers.lua)
  tradeWarn = true,        -- items I'm holding: told when 15 and 5 minutes are left to trade them (Core/Drops.lua)
  announceLoot = true,     -- the loot master opens a corpse: its epics, and anything reserved, go in raid chat (Core/Drops.lua)
  autoTrade = true,        -- giving out an item that's in my bags opens a trade with the winner (Core/Drops.lua)
  exportTemplate = "{date};{player};{item};{how}",   -- my own export layout: a line for each item (Core/Export.lua)
  exportHeader = "",       -- ...and its first line
  rollSeconds = 20,        -- how long everyone has to roll
  rollKinds = {},          -- my own roll types for rolls open to everyone: { { n = "Transmog", hi = 98 } } (Core/Roll.lua)
  raidCommands = true,     -- "!lr" works in raid and party chat, not just by whisper
  raidWarning = true,      -- rolls are announced as raid warnings (leader or assistant), not plain raid chat
  recordGroupWins = false, -- group loot: epics won with the game's Need / Greed count as given out (Core/Drops.lua)
  remindUnrecorded = true, -- the master looter gives an item out without LootRuler: asked whether to record it (UI/Master.lua)
  mlPrompt = true,         -- becoming the master looter: asked whether to open the loot master window and tell the raid
  mlAnnounce = false,      -- ...or the raid is told by itself (UI/Master.lua)
  outbidAlert = true,      -- someone bid more than me in an auction: told on screen, with a sound (UI/RollFrame.lua)
  finalCall = true,        -- running an auction: a final call in raid chat with 10 seconds left (Core/Rolls.lua)
  potAfterSale = true,     -- ...and the pot so far after each sale
  awardGuild = false,      -- who got what goes in guild chat too (Core/Rolls.lua)
  autoLoot = false,        -- the master looter's loot rules hand out what they match (Core/AutoLoot.lua)
  autoLootRules = {},      -- { { what, to } }, first match wins
  lootGold = false,        -- the master looter picks up a corpse's gold (Core/AutoLoot.lua)
  autoRollRules = {},      -- item id -> "pass" / "MS" / "OS": what my roll windows do on their own
  autoPassUnusable = false, -- pass on items my class can't use
  groupLoot = false,       -- the game's Need / Greed windows are rolled by my rules (Core/GroupLoot.lua)
  groupLootRules = {},     -- { { what, act } }, first match wins
  groupLootConfirm = false, -- ...and the game's "this item will bind to you" is answered yes for those rolls
  highlight = true,        -- the game's loot windows glow on items I reserved (UI/Highlight.lua)
  tooltipInfo = true,      -- item tooltips say who reserved the item
  lootTags = true,         -- the game's loot window marks reserved items with who reserved them (UI/Highlight.lua)
  gargulWindows = true,    -- Gargul's rolls get a roll window like LootRuler's, unless Gargul is loaded (Core/Rolls.lua)
  reserveStrip = true,     -- while an item is rolled for, a strip lists everyone who reserved it (UI/ReserveStrip.lua)
  remindOnJoin = false,    -- when I run reserves, people who join and haven't reserved are told how (Core/Whisper.lua)
  testTab = false,         -- the Test tab: pretend rolls and messages, only on my screen (UI/Test.lua)
  rollShortcut = "ctrlalt", -- clicking an item with these keys held rolls it out (UI/Shortcuts.lua)
}
--- settings checked like anything else saved: every option there with the right type, and rules that make sense
function LR.checkSettings(set)
  set = type(set) == "table" and set or {}
  for k, v in pairs(LR.DEFAULTS) do
    if set[k] == nil or type(set[k]) ~= type(v) then set[k] = type(v) == "table" and U.copy(v) or v end
  end
  set.autoLootRules = U.filter(set.autoLootRules, function(r)
    return type(r) == "table" and type(r.what) == "string" and type(r.to) == "string"
  end)
  for id, action in pairs(set.autoRollRules) do
    if type(id) ~= "number" or (action ~= "pass" and action ~= "MS" and action ~= "OS") then set.autoRollRules[id] = nil end
  end
  set.rollKinds = LR.Roll.checkKinds(set.rollKinds) or {}
  if set.rollScale < 0.5 or set.rollScale > 2 then set.rollScale = 1 end
  local okChannel = false
  for _, c in ipairs(LR.SOUND_CHANNELS) do if c[1] == set.soundChannel then okChannel = true end end
  if not okChannel then set.soundChannel = "Master" end
  set.groupLootRules = LR.GroupLoot.check(set.groupLootRules)
  return set
end

function LR.loadDB()
  local fresh = LootRulerDB == nil
  LootRulerDB = type(LootRulerDB) == "table" and LootRulerDB or {}
  db = LootRulerDB
  db.sessions = type(db.sessions) == "table" and db.sessions or {}  -- id -> session (ours as leader, or the latest copy from its leader)
  db.mine = type(db.mine) == "table" and db.mine or {}              -- id -> { i = my picks, dirty = not yet confirmed by the leader }
  db.ui = type(db.ui) == "table" and db.ui or {}
  if fresh then db.ui.toured = false end            -- (a new player: the welcome tour, the first time they open it)
  db.settings = LR.checkSettings(db.settings)
  -- settings saved under a name (UI/Welcome.lua): checked the same way
  db.profiles = type(db.profiles) == "table" and db.profiles or {}
  for name, set in pairs(db.profiles) do
    if type(name) ~= "string" or #name > 24 or type(set) ~= "table" then db.profiles[name] = nil else db.profiles[name] = LR.checkSettings(set) end
  end
  db.notes = LR.Notes.check(db.notes)        -- my item notes (Core/Notes.lua)
  db.wish = LR.Prio.checkWish(db.wish)       -- thatsmybis wishlists I brought in (Core/Prio.lua)
  -- guild books: checked like a message from another player
  db.guilds = type(db.guilds) == "table" and db.guilds or {}
  for g, book in pairs(db.guilds) do
    if type(g) ~= "string" or not LR.Book.validBook(book) then db.guilds[g] = nil end
  end
  -- past raids: checked like a session from someone else
  db.history = type(db.history) == "table" and U.filter(db.history, function(e) return LR.History.valid(e) end) or {}
  LR.db = db
  -- forget sessions nobody has touched for a week (what they gave out goes to past raids)
  local cutoff = U.now() - KEEP_DAYS * 86400
  for id, s in pairs(db.sessions) do
    if not S.valid(s) or s.practice then db.sessions[id] = nil db.mine[id] = nil   -- (a practice raid isn't kept)
    elseif (s.updated or 0) < cutoff then
      LR.History.archive(s, s.updated or U.now())
      db.sessions[id] = nil db.mine[id] = nil
    end
  end
  for id, m in pairs(db.mine) do
    local ok = db.sessions[id] and type(m) == "table" and type(m.i) == "table" and #m.i <= S.MAX_SR + S.MAX_EXTRA
    if ok then for _, item in ipairs(m.i) do if type(item) ~= "number" then ok = false end end end
    if not ok then db.mine[id] = nil end
  end
  if db.current and not db.sessions[db.current] then db.current = nil end
  LR.db = db
  return db
end

function LR.session(id) return id and db.sessions[id] end
function LR.isLeader(s) return s ~= nil and U.samePlayer(s.leader, U.me()) end
function LR.myClass() local _, c = UnitClass("player") return c end

--- the session the window shows: the chosen one, else the newest open one whose leader is in the group or is us
function LR.current()
  if db.current and db.sessions[db.current] then return db.sessions[db.current] end
  local best
  for _, s in pairs(db.sessions) do
    if not s.ended and (LR.isLeader(s) or LR.inGroup(s.leader)) and (not best or s.created > best.created) then best = s end
  end
  return best
end
function LR.select(id) db.current = id LR.changed("select") end

--- every known session, newest first
function LR.sessions()
  local out = {}
  for _, s in pairs(db.sessions) do out[#out + 1] = s end
  table.sort(out, function(a, b) return a.created > b.created end)
  return out
end

--- my picks in a session: as the leader has them, or as I've picked them and the leader hasn't confirmed yet
function LR.myPicks(s)
  if not s then return {} end
  local mine = db.mine[s.id]
  if not LR.isLeader(s) and mine and mine.dirty then return mine.i end
  return S.reservesOf(s, U.me())
end
function LR.pending(s) local m = s and db.mine[s.id] return m ~= nil and m.dirty == true end

---------------------------------------------------------------------- the group
function LR.groupChannel()
  if LR.Practice.on then return "RAID" end              -- (a practice raid: shown, never said; Core/Practice.lua)
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
end

--- group members: { name = "Name-Realm", class = "PALADIN", online = bool, leader = bool, assist = bool }
function LR.roster()
  local out = {}
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local name, rank, _, _, _, class, _, online = GetRaidRosterInfo(i)
      if name then out[#out + 1] = { name = U.full(name), class = class, online = online and true or false, leader = rank == 2, assist = rank == 1 } end
    end
  else
    local units = { "player" }
    if IsInGroup() then for i = 1, GetNumGroupMembers() - 1 do units[#units + 1] = "party" .. i end end
    for _, unit in ipairs(units) do
      if UnitExists(unit) then
        local name, realm = UnitName(unit)
        local _, class = UnitClass(unit)
        out[#out + 1] = { name = realm and realm ~= "" and (name .. "-" .. realm) or U.full(name), class = class,
          online = UnitIsConnected(unit) and true or false, leader = UnitIsGroupLeader(unit) and true or false,
          assist = UnitIsGroupAssistant(unit) and true or false }
      end
    end
  end
  if LR.Practice.on then
    out[1].leader = true
    for _, m in ipairs(LR.Practice.roster()) do out[#out + 1] = m end
  end
  return out
end
--- the unit ("raid3", "party1", "player") of someone in the group, for the game's functions that take one; nil if not
function LR.unitOf(name)
  if not name then return nil end
  if U.samePlayer(name, U.me()) then return "player" end
  local units = {}
  if IsInRaid() then for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
  elseif IsInGroup() then for i = 1, GetNumGroupMembers() - 1 do units[#units + 1] = "party" .. i end end
  for _, u in ipairs(units) do
    local n, r = UnitName(u)
    if n and U.samePlayer((r and r ~= "") and (n .. "-" .. r) or n, name) then return u end
  end
end
function LR.inGroup(name)
  if not name or not (IsInGroup() or LR.Practice.on) then return false end
  for _, m in ipairs(LR.roster()) do if U.samePlayer(m.name, name) then return m end end
  return false
end
function LR.classOf(name)
  local m = LR.inGroup(name)
  return m and m.class or nil
end

---------------------------------------------------------------------- sending
local function encode(msg)
  msg.v = 1                                         -- see the top: never raised
  msg.av = LR.VERSION
  msg.fl = FEATURES
  return LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(LibSerialize:Serialize(msg)))
end
local function decode(text)
  local raw = LibDeflate:DecodeForWoWAddonChannel(text)
  raw = raw and LibDeflate:DecompressDeflate(raw)
  if not raw then return nil end
  local ok, msg = LibSerialize:Deserialize(raw)
  if ok and type(msg) == "table" and type(msg.t) == "string" then return msg end
end
Net.encode, Net.decode = encode, decode

local function send(msg, channel, target)
  if not channel or LR.Practice.on then return end      -- (nothing is sent during a practice raid)
  Net:SendCommMessage(LR.PREFIX, encode(msg), channel, target, "NORMAL")
end
Net.send = send

--- says something in chat (raid, party, a whisper...). It goes through ChatThrottleLib, which spaces lines
--- out when there are many (answering a whole raid's "!lr"s at once would otherwise get you muted for spam).
function LR.say(text, channel, target)
  if not channel then return end
  if LR.Practice.on then LR.Practice.show(text, channel, target) return end
  if ChatThrottleLib and ChatThrottleLib.SendChatMessage then
    ChatThrottleLib:SendChatMessage("NORMAL", LR.PREFIX, text, channel, nil, target)
  else
    local fn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    fn(text, channel, nil, target)
  end
end

--- where the leader's messages go: the group (if any) and the guild (when shared)
local function publishTo(s)
  local out = {}
  local g = LR.groupChannel()
  if g then out[#out + 1] = g end
  if s.guild and IsInGuild() then out[#out + 1] = "GUILD" end
  return out
end

--- how to reach a session's leader: a whisper when they're in our group and online, else the guild
--- channel when the session came from there; nil when they can't be reached right now
local function routeTo(s)
  local m = LR.inGroup(s.leader)
  if m and m.online then return "WHISPER", s.leader end
  if s.guild and IsInGuild() then return "GUILD" end
end

--- the leader sends the session out (once, shortly after a burst of changes)
local publishSeq = {}
function LR.publish(s, now)
  if not LR.isLeader(s) then return end
  publishSeq[s.id] = (publishSeq[s.id] or 0) + 1
  local mine = publishSeq[s.id]
  local function go()
    if publishSeq[s.id] ~= mine then return end
    for _, ch in ipairs(publishTo(s)) do send({ t = "T", s = s }, ch) end
  end
  if now then go() else C_Timer.After(0.5, go) end
end

--- asks for open sessions
function LR.query()
  local g = LR.groupChannel()
  if g then send({ t = "Q" }, g) end
  if IsInGuild() then send({ t = "Q" }, "GUILD") end
end

--- sends my picks to the leader if they're waiting and the leader can be reached. The same picks aren't
--- sent again within a few seconds (group changes and the leader's updates both ask for a send).
local lastSent = {}
function LR.sendPicks(s, force)
  local mine = s and db.mine[s.id]
  if not mine or not mine.dirty or LR.isLeader(s) then return false end
  local channel, target = routeTo(s)
  if not channel then return false end
  local key = table.concat(mine.i, ",")
  local last = lastSent[s.id]
  if not force and last and last.key == key and GetTime() - last.at < 10 then return false end
  lastSent[s.id] = { key = key, at = GetTime() }
  send({ t = "P", id = s.id, c = LR.myClass(), i = mine.i }, channel, target)
  return true
end

---------------------------------------------------------------------- what the leader does
function LR.startSession(raidKey, sr, dupes, guild, name, any)
  local now = U.now()
  local s = S.new(U.me(), raidKey, sr, dupes, now, name, any)
  s.guild = guild and true or false
  s.go = true                  -- (only the group can reserve, until the leader says otherwise)
  db.sessions[s.id] = s
  db.current = s.id
  LR.preload(raidKey)
  LR.publish(s, true)
  LR.changed("session")
  return s
end

--- a change the leader made: save, tell everyone, redraw
local function leaderChanged(s)
  s.updated = U.now()
  LR.publish(s)
  LR.changed("session")
end
LR.leaderChanged = leaderChanged

function LR.configure(s, sr, dupes)
  local ok, touched = S.configure(s, sr, dupes, U.now())
  if ok then leaderChanged(s) end
  return ok, touched
end
function LR.setHR(s, id, forWho, note)
  local ok, lost = S.setHR(s, id, forWho, note, U.now())
  if ok then
    leaderChanged(s)
    if #lost > 0 then
      LR.print(("%s is now hard reserved; %s lost their reserve on it."):format(LR.itemLink(id), table.concat(U.map(lost, U.short), ", ")))
    end
  end
  return ok, lost
end
function LR.clearHR(s, id) if S.clearHR(s, id, U.now()) then leaderChanged(s) end end
function LR.setLocked(s, locked)
  if S.setLocked(s, locked, U.now()) then
    leaderChanged(s)
    if locked and LR.Gargul.available() then LR.Gargul.send(s, true) end
  end
end
function LR.setDisenchanter(s, player) if S.setDisenchanter(s, player, U.now()) then leaderChanged(s) end end
function LR.setPlusOne(s, on) if S.setPlusOne(s, on, U.now()) then leaderChanged(s) end end
function LR.setSessionBoost(s, on) if S.setBoost(s, on, U.now()) then leaderChanged(s) end end
function LR.setExtra(s, player, n)
  if not LR.isLeader(s) then return false end
  local ok, lost = S.setExtra(s, player, n, U.now())
  if ok then leaderChanged(s) end
  return ok, lost
end
--- +1s brought in (from Gargul, say): everyone's set, and the +1 rule switched on
function LR.importPlusOnes(s, list)
  if not LR.isLeader(s) then return false end
  local n = 0
  for _, x in ipairs(list) do if S.setPlusOnes(s, x.p, x.n, U.now()) then n = n + 1 end end
  S.setPlusOne(s, true, U.now())
  leaderChanged(s)
  return n
end
function LR.setSessionPrio(s, mode) if S.setPrio(s, mode, U.now()) then leaderChanged(s) end end
-- GDKP (Core/Gdkp.lua): only the leader's changes count
local function gdkp(fn)
  return function(s, ...)
    if not (LR.isLeader(s) and fn(s, ...)) then return false end
    -- a past raid (finishing its payouts): kept, not sent to anyone
    if s.archived then s.updated = U.now() LR.changed("history") else leaderChanged(s) end
    return true
  end
end
LR.setGdkp = gdkp(function(s, on, now)
  local changed = LR.Gdkp.set(s, on, U.now())
  if s.gdkp then LR.Gdkp.saw(s, U.map(LR.roster(), function(m) return m.name end), U.now()) end
  return changed
end)
LR.gdkpOption = gdkp(function(s, key, value) return LR.Gdkp.option(s, key, value, U.now()) end)
LR.gdkpStrict = gdkp(function(s, on) return LR.Gdkp.setStrict(s, on, U.now()) end)
LR.gdkpRoleCut = gdkp(function(s, role, pct) return LR.Gdkp.setRoleCut(s, role, pct, U.now()) end)
LR.gdkpRole = gdkp(function(s, player, role) return LR.Gdkp.setRole(s, player, role, U.now()) end)
LR.gdkpPrice = gdkp(function(s, id, gold) return LR.Gdkp.setPrice(s, id, gold, U.now()) end)
LR.gdkpBonus = gdkp(function(s, player, gold) return LR.Gdkp.setBonus(s, player, gold, U.now()) end)
LR.gdkpOut = gdkp(function(s, player, out) return LR.Gdkp.setOut(s, player, out, U.now()) end)
LR.gdkpPaid = gdkp(function(s, player, gold) return LR.Gdkp.paid(s, player, gold, U.now()) end)
LR.gdkpSalePrice = gdkp(function(s, index, gold) return LR.Gdkp.setSalePrice(s, index, gold, U.now()) end)
LR.gdkpPrices = gdkp(function(s, prices) return LR.Gdkp.setPrices(s, prices, U.now()) > 0 end)
function LR.adjustPlusOne(s, player, delta) if LR.isLeader(s) and S.adjustPlusOne(s, player, delta, U.now()) then leaderChanged(s) return true end return false end
function LR.setAny(s, any) if S.setAny(s, any, U.now()) then leaderChanged(s) end end
function LR.setGroupOnly(s, on) if LR.isLeader(s) and S.setGroupOnly(s, on, U.now()) then leaderChanged(s) end end
--- the session's softres.it page: set it (the leader; false when it isn't a softres.it link), and post it in raid chat
function LR.setLink(s, url)
  if not LR.isLeader(s) then return false end
  local t = U.trim(url or "")
  if t ~= "" and not S.okLink(t) then return false end
  if S.setLink(s, t, U.now()) then leaderChanged(s) end
  return true
end
function LR.postLink(s)
  local ch = LR.groupChannel()
  if not s.url or not ch then return false end
  LR.say(("%s Reserve on softres.it: %s"):format(LR.TAG, s.url), ch)
  return true
end
function LR.setGuild(s, guild)
  s.guild = guild and true or false
  leaderChanged(s)
end
function LR.leaderAdd(s, player, class, id) local ok, why = S.add(s, player, class, id, true, U.now()) if ok then leaderChanged(s) end return ok, why end
function LR.removeDrop(s, k) if LR.isLeader(s) and S.removeDrop(s, k, U.now()) then leaderChanged(s) return true end return false end
function LR.unaward(s, index) if LR.isLeader(s) and S.unaward(s, index, U.now()) then leaderChanged(s) return true end return false end
--- changes an award (the leader) and tells the raid
local HOW = { SR = "their reserve", MS = "main spec", OS = "off spec", DE = "to disenchant" }
function LR.editAward(s, index, player, kind)
  local w = s.won and s.won[index]
  local was = w and w.p
  if not LR.isLeader(s) or not S.editAward(s, index, player, kind, U.now()) then return false end
  leaderChanged(s)
  local link = LR.itemLink(w.i)
  local line = U.samePlayer(was, w.p) and ("Changed: %s is %s's for %s."):format(link, U.short(w.p), HOW[kind])
    or ("Changed: %s is %s's (%s), not %s's."):format(link, U.short(w.p), HOW[kind], U.short(was))
  LR.Rolls.say(line)
  return true
end
function LR.leaderRemove(s, player, id) local ok, why = S.remove(s, player, id, true, U.now()) if ok then leaderChanged(s) end return ok, why end

---------------------------------------------------------------------- a new leader for a session
--- the session's leader is away: we're in a group, and they're not in it or are offline
function LR.leaderGone(s)
  if not s or not IsInGroup() then return false end
  local m = LR.inGroup(s.leader)
  return not m or not m.online
end
--- someone leads or assists the group (the game says so)
function LR.groupBoss(name)
  local m = LR.inGroup(name)
  return m and (m.leader or m.assist) and true or false
end
--- whether I may take over a session: its leader is away, and I lead or assist the group
function LR.mayTakeOver(s) return s ~= nil and not LR.isLeader(s) and not s.archived and LR.leaderGone(s) and LR.groupBoss(U.me()) end

local function tellGroup(text)
  local ch = LR.groupChannel()
  if ch then for _, line in ipairs(U.chatLines(LR.TAG .. " " .. text)) do LR.say(line, ch) end end
end
--- I run the reserves from now on: the raid hears who to whisper
local function nowMine(s, from, quiet)
  S.newLeader(s, U.me(), U.now())
  -- my own picks the old leader hadn't confirmed yet go in now (as the leader's do)
  local mine = db.mine[s.id]
  if mine and mine.dirty then S.set(s, U.me(), LR.myClass(), mine.i, true, U.now()) end
  db.mine[s.id] = nil
  db.current = s.id
  leaderChanged(s)
  if quiet then return end
  tellGroup(("%s runs the soft reserves now (taking over from %s). Whisper %s \"!lr [item]\" to reserve or check yours."):format(
    U.short(U.me()), U.short(from), U.short(U.me())))
end
--- takes over a session whose leader is gone (I lead or assist the group). Returns true, or false and why not.
function LR.takeOver(s)
  if not LR.mayTakeOver(s) then return false, "Only the raid leader or an assistant can take over, while the reserves' leader is away." end
  nowMine(s, s.leader)
  return true
end
--- takes over a session whose leader is gone, to hand it straight to someone else (the raid hears from them)
function LR.passOn(s, player)
  if not LR.canLead(player) then return false, ("%s's LootRuler can't take the reserves over (it's too old, or not there)."):format(U.short(player)) end
  if U.samePlayer(player, U.me()) then return LR.takeOver(s) end
  if not LR.mayTakeOver(s) then return false, "Only the raid leader or an assistant can take over, while the reserves' leader is away." end
  nowMine(s, s.leader, true)
  return LR.handOver(s, player)
end
--- the leader hands the session to someone in the group with LootRuler (their addon takes it on); nil takes it back
function LR.handOver(s, player)
  if not LR.isLeader(s) then return false, "Only the reserves' leader can hand them over." end
  if player and not LR.canLead(player) then return false, ("%s's LootRuler can't take the reserves over (it's too old, or not there)."):format(U.short(player)) end
  if not S.handTo(s, player, U.now()) then return false end
  leaderChanged(s)
  return true
end
--- the session was handed to me: it's mine now
function LR.adopt(s)
  if not s.next or not U.samePlayer(s.next, U.me()) or LR.isLeader(s) then return end
  LR.print(("%s handed you the soft reserves: you run them now."):format(U.short(s.leader)))
  nowMine(s, s.leader)
end

-- the reserves' leader left (or went offline): tell the raid leader and assistants, once per session
local toldGone = {}
LR.onChange(function(what)
  if what ~= "roster" or not db then return end
  for id, s in pairs(db.sessions) do
    if LR.mayTakeOver(s) and not toldGone[id] and LR.inGroup(s.leader) == false then
      toldGone[id] = true
      LR.print(("%s, who runs the soft reserves, has left the group. Take them over on the Session tab (/lr)."):format(U.short(s.leader)))
    elseif not LR.leaderGone(s) then toldGone[id] = nil end
  end
end)

-- names from softres.it: someone joining (or reserving) may be who a name on the sheet really is (Core/Gargul.lua)
local recheckSoon = false
LR.onChange(function(what)
  if (what ~= "roster" and what ~= "session") or recheckSoon or not db then return end
  recheckSoon = true
  C_Timer.After(1, function()
    recheckSoon = false
    for _, s in pairs(db.sessions) do
      if s.sx and not s.archived and LR.isLeader(s) then
        for _, m in ipairs(LR.Gargul.recheck(s, LR.roster())) do
          LR.print(("%s on the softres.it sheet is %s: their reserves from the sheet count for them now."):format(U.short(m[1]), U.short(m[2])))
        end
      end
    end
  end)
end)
--- the leader puts a name from the sheet under the character it really is (Reserves tab, or after an import)
function LR.matchName(s, from, to)
  if not LR.isLeader(s) then return false end
  return LR.Gargul.rename(s, from, to, LR.classOf(to))
end

function LR.endSession(s)
  if s.practice then LR.Practice.stop() return end      -- (ending a practice raid's session ends the practice)
  if not LR.isLeader(s) then return end
  LR.History.archive(s, U.now())                -- what it gave out is kept under Past raids (Core/History.lua)
  for _, ch in ipairs(publishTo(s)) do send({ t = "E", id = s.id }, ch) end
  db.sessions[s.id] = nil
  db.mine[s.id] = nil
  if db.current == s.id then db.current = nil end
  LR.changed("session")
end

---------------------------------------------------------------------- what I do with my own reserves
--- reserve one more of an item in a session; returns true, or false and why
function LR.reserve(s, id) return LR.changeMine(s, function(items) items[#items + 1] = id end, id) end
function LR.unreserve(s, id)
  return LR.changeMine(s, function(items)
    local i = U.indexOf(items, id)
    if i then table.remove(items, i) end
  end, id)
end

function LR.changeMine(s, edit, id)
  if not s then return false, "NO_SESSION" end
  local me = U.me()
  if LR.isLeader(s) then
    local items = U.copy(S.reservesOf(s, me))
    edit(items)
    local ok, why = S.set(s, me, LR.myClass(), items, true, U.now())
    if ok then leaderChanged(s) end
    return ok, why
  end
  if s.locked then return false, "LOCKED" end
  local items = U.copy(LR.myPicks(s))
  local before = #items
  edit(items)
  -- only the group can reserve: outside it, I can take reserves back but not add (the leader's addon decides too)
  if #items > before and s.go and not LR.inGroup(s.leader) then return false, "GROUP_ONLY" end
  -- no reserves in a GDKP raid, or one that goes by priority lists only (taking them back is fine)
  if #items > before and s.gdkp then return false, "GDKP" end
  if #items > before and s.prio == "only" then return false, "PRIO_ONLY" end
  local ok, why = S.check(s, items, true, me)          -- which items are allowed is the leader's addon's call
  if not ok then return false, why end
  db.mine[s.id] = { i = items, dirty = true }
  LR.sendPicks(s, true)
  LR.changed("mine")
  return true
end

---------------------------------------------------------------------- receiving
local queryAnswered = {}

local handlers = {}
Net.handlers = handlers          -- Core/Rolls.lua adds the messages for rolling out loot

-- a session from its leader
function handlers.T(msg, channel, sender)
  local t = msg.s
  if not S.valid(t) or not U.samePlayer(t.leader, sender) then return end
  local known = db.sessions[t.id]
  local tookOurs = false
  if known and not U.samePlayer(known.leader, t.leader) then
    -- a new leader: only if it was handed to them, or they lead or assist the group and took it over while its
    -- leader was gone (or it was ours, and we were away). Anyone else claiming it is ignored.
    if not S.newLeaderOk(known, t.leader, LR.leaderGone(known), LR.groupBoss(sender), LR.isLeader(known), S.ledBy(t, U.me()), t.rev > known.rev) then return end
    tookOurs = LR.isLeader(known)
    if tookOurs then LR.print(("%s runs the soft reserves now: they were taken over while you were away."):format(U.short(sender))) end
  elseif LR.isLeader(known) then return                     -- ours: we're the one that knows best
  elseif known and known.rev >= t.rev then
    LR.sendPicks(known, true)                               -- the leader is there: anything still waiting goes now
    return
  end
  local first = not known
  t.guild = t.guild or channel == "GUILD"
  db.sessions[t.id] = t
  local mine = db.mine[t.id]
  local theirs = S.reservesOf(t, U.me())
  if mine and mine.dirty then
    if U.sameItems(mine.i, theirs) then mine.dirty = false mine.i = U.copy(theirs)
    elseif not t.locked then LR.sendPicks(t, true)
    else db.mine[t.id] = { i = U.copy(theirs), dirty = false } end
  else
    db.mine[t.id] = { i = U.copy(theirs), dirty = false }
  end
  -- handed to me: my addon takes it on
  if t.next and U.samePlayer(t.next, U.me()) then LR.adopt(t) end
  if first then
    LR.preload(t.raid)
    -- a new session from someone in our group is the one to show (last week's can go to the back)
    if LR.inGroup(t.leader) then db.current = t.id end
    if not t.ended then
      LR.print(("%s opened soft reserves for %s: %s each%s. Type |cffffd100/lr|r to reserve."):format(
        U.short(t.leader), LR.raidOf(t).name, U.plural(t.sr, "reserve"), t.dupes and "" or ", one per item"))
    end
  end
  LR.changed("session")
end

-- a session was ended by its leader
function handlers.E(msg, channel, sender)
  local s = db.sessions[msg.id]
  if not s or not U.samePlayer(s.leader, sender) or LR.isLeader(s) then return end
  LR.History.archive(s, U.now())
  db.sessions[msg.id] = nil
  db.mine[msg.id] = nil
  if db.current == msg.id then db.current = nil end
  LR.print(("%s closed the soft reserves for %s."):format(U.short(s.leader), LR.raidOf(s).name))
  LR.changed("session")
end

-- someone asks which sessions are open: leaders answer (once every few seconds per channel), and everyone
-- in the group says they have the addon
function handlers.Q(msg, channel, sender)
  if channel ~= "GUILD" then LR.hello(channel == "WHISPER" and sender or nil) end
  local now = GetTime()
  for _, s in pairs(db.sessions) do
    if LR.isLeader(s) and (channel ~= "GUILD" or s.guild) then
      local key = s.id .. channel
      if not queryAnswered[key] or now - queryAnswered[key] > 5 then
        queryAnswered[key] = now
        send({ t = "T", s = s }, channel == "WHISPER" and "WHISPER" or channel, channel == "WHISPER" and sender or nil)
      end
    end
  end
end

-- a raider's picks, at the leader
function handlers.P(msg, channel, sender)
  local s = db.sessions[msg.id]
  if not s or not LR.isLeader(s) or type(msg.i) ~= "table" then return end
  local items = {}
  for _, id in ipairs(msg.i) do if type(id) == "number" then items[#items + 1] = id end end
  local class = LR.classOf(sender) or (type(msg.c) == "string" and LR.CLASS_BIT[msg.c] and msg.c) or nil
  local rev = s.rev
  local ok, why, id = S.groupOk(s, sender, items, LR.inGroup(sender) and true or false)
  if ok then ok, why, id = S.set(s, sender, class, items, false, U.now()) end
  local answer = { t = "A", id = s.id, to = sender, ok = ok, why = why, item = id, i = S.reservesOf(s, sender) }
  local route, target = channel, nil
  if channel == "WHISPER" or LR.inGroup(sender) then route, target = "WHISPER", sender end
  send(answer, route, target)
  if s.rev ~= rev then leaderChanged(s) end
end

-- the leader's answer to my picks
function handlers.A(msg, channel, sender)
  if msg.to and not U.samePlayer(msg.to, U.me()) then return end
  local s = db.sessions[msg.id]
  if not s or not U.samePlayer(s.leader, sender) or type(msg.i) ~= "table" then return end
  local before = db.mine[s.id] and db.mine[s.id].i or {}
  db.mine[s.id] = { i = U.copy(msg.i), dirty = false }
  -- keep our copy of the session in step until the next full copy arrives
  if #msg.i > 0 then s.res[U.me()] = { c = LR.myClass(), i = U.copy(msg.i) } else s.res[U.me()] = nil end
  if not msg.ok then
    local why = S.WHY[msg.why] or "The leader didn't accept that."
    LR.print(("%s turned down your reserves: %s%s"):format(U.short(s.leader), why, msg.item and (" (" .. LR.itemLink(msg.item) .. ")") or ""))
    LR.toast(why)
  elseif not U.sameItems(before, msg.i) then
    LR.changed("mine")
  end
  LR.changed("mine")
end

function Net:OnComm(prefix, text, channel, sender)
  if prefix ~= LR.PREFIX or not sender then return end
  sender = U.full(sender)
  if U.samePlayer(sender, U.me()) then return end
  local msg = decode(text)
  if not msg or (msg.mv and (tonumber(msg.mv) or 0) > PROTOCOL) then return end
  LR.heardFrom(sender, msg.av, msg.fl)
  local fn = handlers[msg.t]
  if fn then
    local ok, err = pcall(fn, msg, channel, sender)
    if not ok then geterrorhandler()(err) end
  end
end

---------------------------------------------------------------------- who has the addon, which version
local versions = {}            -- "name-realm" (lower case) -> version string
local toldNewer = false

--- something came from a player's addon: remember its version; say once when there's a newer one
local features = {}          -- "name-realm" -> what their addon can do (fl)
function LR.heardFrom(sender, version, fl)
  if not sender then return end
  version = type(version) == "string" and version:sub(1, 20) or "1.0.0-beta"
  versions[U.full(sender):lower()] = version
  features[U.full(sender):lower()] = type(fl) == "number" and fl or 0
  if not toldNewer and U.compareVersions(LR.VERSION, version) < 0 then
    toldNewer = true
    LR.print(("%s has a newer LootRuler (%s; you have %s). It works with yours, but update when you can."):format(U.short(sender), version, LR.VERSION))
  end
  LR.changed("versions")
end

--- whether a player's LootRuler can take over a session (we've heard from it, and it's new enough)
function LR.canLead(name)
  if U.samePlayer(name, U.me()) then return true end
  return (name and features[U.full(name):lower()] or 0) >= 1
end

--- the version of LootRuler a player has, if we've heard from them (and nil if not)
function LR.versionOf(name)
  if U.samePlayer(name, U.me()) then return LR.VERSION end
  return name and versions[U.full(name):lower()] or nil
end

--- my note on an item (Core/Notes.lua), or nil
function LR.noteFor(id) return db and db.notes and db.notes[id] or nil end
--- sets or (with no text) takes off my note on an item
function LR.setNote(id, text)
  if type(id) ~= "number" then return end
  db.notes[id] = LR.Notes.clean(text)
  LR.changed("notes")
end

--- who has an item on their thatsmybis wishlist, in order: { { p, n } }. here: only players in the group. Anyone who
--- has already been given it this session is left out.
function LR.wishFor(id, here)
  local list = db and db.wish and db.wish[id]
  if not list then return {} end
  local s = LR.current()
  local got, inGroup = {}, {}
  if s then for _, w in ipairs(LR.Session.winners(s, id)) do got[U.foldCase(U.bare(w[1]))] = true end end
  if here then for _, m in ipairs(IsInGroup() and LR.roster() or {}) do inGroup[U.foldCase(U.bare(m.name))] = m.name end end
  local out = {}
  for _, e in ipairs(list) do
    local key = U.foldCase(U.bare(e.p))
    -- (in the group: named the way the game names them)
    if not got[key] and (not here or inGroup[key]) then out[#out + 1] = here and { p = inGroup[key], n = e.n } or e end
  end
  return out
end
--- a wishlist as a short line: "Ann (1), Bob (2), +3"
function LR.wishLine(list, limit)
  local parts = {}
  for i, e in ipairs(list) do
    if i > (limit or 5) then parts[#parts + 1] = "+" .. (#list - i + 1) break end
    parts[#parts + 1] = ("%s (%d)"):format(U.short(U.full(e.p)), e.n)
  end
  return table.concat(parts, ", ")
end

--- everyone in the group and their LootRuler, the ones to do something about first:
--- { { name, class, version (nil: not heard from), state = "older" / "none" / "newer" / "same" (as mine) } }
function LR.versionList()
  local out = {}
  for _, m in ipairs(LR.roster()) do
    local v = LR.versionOf(m.name)
    local c = v and U.compareVersions(v, LR.VERSION)
    out[#out + 1] = { name = m.name, class = m.class, version = v, state = not v and "none" or c < 0 and "older" or c > 0 and "newer" or "same" }
  end
  local order = { older = 1, none = 2, newer = 3, same = 4 }
  table.sort(out, function(a, b)
    if a.state ~= b.state then return order[a.state] < order[b.state] end
    return a.name < b.name
  end)
  return out
end

--- whispers everyone in the group with an older LootRuler that there's a newer one (once each). Returns how many.
local toldOld = {}
function LR.tellOutdated()
  local n = 0
  for _, x in ipairs(LR.versionList()) do
    local key = U.full(x.name):lower()
    if x.state == "older" and toldOld[key] ~= x.version then
      toldOld[key] = x.version
      n = n + 1
      LR.say(("%s You have LootRuler %s, and %s is out. Yours still works with it, but update when you can."):format(LR.TAG, x.version, LR.VERSION), "WHISPER", x.name)
    end
  end
  return n
end

--- tells the group (or one player) we have the addon; not more than once every few seconds
local lastHello = {}
function LR.hello(target)
  local key = target or "group"
  if lastHello[key] and GetTime() - lastHello[key] < 10 then return end
  lastHello[key] = GetTime()
  if target then send({ t = "V" }, "WHISPER", target) return end
  local g = LR.groupChannel()
  if g then
    -- a few seconds' spread, so a raid answering the same question doesn't all speak at once
    C_Timer.After(math.random() * 2, function() send({ t = "V" }, LR.groupChannel()) end)
  end
end
function handlers.V() end       -- heardFrom has done the work

---------------------------------------------------------------------- start up
function LR.toast(text) if LR.UI and LR.UI.toast then LR.UI.toast(text) end end

local wasGrouped = false
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    if not db then LR.loadDB() end
    C_ChatInfo.RegisterAddonMessagePrefix(LR.PREFIX)
    Net:RegisterComm(LR.PREFIX, "OnComm")
    wasGrouped = IsInGroup()
    -- once the game has settled: ask what's open, re-send our own sessions and anything we picked meanwhile
    C_Timer.After(5, function()
      LR.query()
      LR.hello()
      for _, s in pairs(db.sessions) do
        if LR.isLeader(s) then LR.publish(s, true) else LR.sendPicks(s) end
      end
    end)
  elseif event == "GROUP_ROSTER_UPDATE" then
    if not db then return end
    local grouped = IsInGroup()
    if grouped and LR.Practice.on then LR.Practice.stop("you joined a group, so the practice raid is over: it's forgotten.") end
    if grouped and not wasGrouped then
      C_Timer.After(2, function()
        LR.query()
        LR.hello()
        for _, s in pairs(db.sessions) do
          if LR.isLeader(s) then LR.publish(s, true) else LR.sendPicks(s) end
        end
      end)
    end
    wasGrouped = grouped
    -- someone came online or joined: if it's a leader we have picks waiting for, send them
    for _, s in pairs(db.sessions) do if not LR.isLeader(s) then LR.sendPicks(s) end end
    LR.changed("roster")
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    LR.changed("items")
  end
end)
