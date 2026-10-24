-- Sharing the guild book (Core/Book.lua) with the guild, and deciding who may change it: the guild master,
-- and the ranks they pick (officers by default). Everyone in the guild with LootRuler gets a copy.
--
-- Messages (guild channel, or a whisper to answer one player):
--   GB  editor -> guild    a change to the book (only the entries that changed), or the whole book
--   GQ  anyone -> guild    "send me the book" (editors answer by whisper, each player at most once a minute)
-- A change only counts when the game's guild list says its sender may edit. A message from someone whose
-- rank isn't known yet (the guild list hasn't loaded) waits until it has.
local _, LR = ...
local U, B = LR.U, LR.Book
local Net = LR.Net

local Guild = {}
LR.Guild = Guild

local ranks = {}           -- "name-realm" (lower case) -> rank index (0 = guild master)
local waiting = {}         -- messages from players whose rank isn't known yet

function LR.guildName()
  if not IsInGuild() then return nil end
  local name = GetGuildInfo("player")
  return name
end

--- the rank index of a guild member, or nil when not known
function Guild.rank(name)
  if U.samePlayer(name, U.me()) then
    local _, _, idx = GetGuildInfo("player")
    if idx then return idx end
  end
  return ranks[U.full(name):lower()]
end

--- reads the game's guild list
function Guild.readRoster()
  ranks = {}
  for i = 1, GetNumGuildMembers() do
    local name, _, rankIndex = GetGuildRosterInfo(i)
    if name then ranks[U.full(name):lower()] = rankIndex end
  end
end

--- this guild's book (made the first time); nil when not in a guild
function LR.book()
  local g = LR.guildName()
  if not g then return nil end
  LR.db.guilds = LR.db.guilds or {}
  local book = LR.db.guilds[g]
  if not book then book = B.new(g) LR.db.guilds[g] = book end
  return book
end

--- whether a player may change the book: the guild master, and ranks up to the one the guild master picked
function LR.canEditBook(name)
  local book = LR.book()
  local r = Guild.rank(name or U.me())
  return book ~= nil and r ~= nil and r <= book.editRank
end
function LR.isGuildMaster(name) return Guild.rank(name or U.me()) == 0 end

--- a change I made: it's already in my book; tell the guild
function Guild.share(change)
  if not change or not IsInGuild() then return end
  Net.send({ t = "GB", g = LR.guildName(), c = change }, "GUILD")
  LR.changed("book")
end

--- changes the book, if I may: fn(book, now) makes the change and returns it (Book.lua's functions)
function Guild.edit(fn)
  if not LR.canEditBook() then return false, "Only the guild master and the ranks they pick can change this." end
  local change = fn(LR.book(), U.now())
  Guild.share(change)
  return true
end

--- the guild master picks the highest rank that may edit (0: only themselves)
function Guild.setEditRank(rank)
  if not LR.isGuildMaster() then return false end
  local book = LR.book()
  book.editRank, book.et = rank, B.stamp({ t = book.et }, U.now())
  Guild.share({ editRank = book.editRank, et = book.et })
  return true
end

---------------------------------------------------------------------- priority lists
--- how an item is rolled for by the guild's priority lists: { mode = "PR", who = the best priority here
--- (names), n = that priority }, or nil when nobody on its list is here
function Guild.prioPlan(id)
  local book = LR.book()
  if not book then return nil end
  local here = U.map(LR.roster(), function(m) return m.name end)
  local first, n = B.first(book, id, here)
  if #first == 0 then return nil end
  return { mode = "PR", who = first, n = n, away = {} }
end

--- boosted roll points brought in (from Gargul, say): everyone's set, and their alts linked, in one change
function Guild.importPoints(list)
  return Guild.edit(function(book, now)
    local change = { points = {}, alts = {} }
    for _, x in ipairs(list) do
      -- (a main named on the line is a main: if it was someone's alt, it isn't any more)
      local un = B.unlinkAlt(book, x.p, now)
      if un then for k, v in pairs(un.alts) do change.alts[k] = v end end
      local c = B.setPoints(book, x.p, x.n, now)
      if c then for k, v in pairs(c.points) do change.points[k] = v end end
      for _, alt in ipairs(x.alts or {}) do
        local a = B.setAlt(book, alt, x.p, now)
        if a then for k, v in pairs(a.alts) do change.alts[k] = v end end
      end
    end
    return (next(change.points) or next(change.alts)) and change or nil
  end)
end

--- links or unlinks an alt (editors)
function Guild.linkAlt(alt, main)
  local why
  local ok, err = Guild.edit(function(book, now)
    local c
    c, why = B.setAlt(book, alt, main, now)
    return c
  end)
  if not ok then return false, err end
  if why then return false, why end
  return true
end
function Guild.unlinkAlt(alt) return Guild.edit(function(book, now) return B.unlinkAlt(book, alt, now) end) end

---------------------------------------------------------------------- raid points
--- who in the group is in my guild (names)
function Guild.raidMembers()
  local out = {}
  for _, m in ipairs(LR.roster()) do if Guild.rank(m.name) ~= nil then out[#out + 1] = m.name end end
  return out
end

--- whether this raid's points were given already (by me): the session, else today
local function raidKey(s) return s and s.id or date("%Y-%m-%d") end
function Guild.pointsGiven(s)
  local given = LR.db.ui.pointsGiven
  return type(given) == "table" and given[raidKey(s)] ~= nil
end

--- everyone from the guild in the group gets the points for a raid
function Guild.raidPoints(s)
  local who = Guild.raidMembers()
  if #who == 0 then return false, "Nobody from your guild is in the group." end
  local ok, why = Guild.edit(function(book, now) return B.raidAttended(book, who, now) end)
  if not ok then return false, why end
  LR.db.ui.pointsGiven = type(LR.db.ui.pointsGiven) == "table" and LR.db.ui.pointsGiven or {}
  -- forget raids from more than a month ago
  for k, at in pairs(LR.db.ui.pointsGiven) do if type(at) ~= "number" or at < U.now() - 30 * 86400 then LR.db.ui.pointsGiven[k] = nil end end
  LR.db.ui.pointsGiven[raidKey(s)] = U.now()
  local book = LR.book()
  if IsInGroup() then
    LR.Rolls.say(("Raid points: %s from %s got %d points each for boosted rolls."):format(U.plural(#who, "player"), book.guild, book.boost.perRaid))
  end
  return true
end

---------------------------------------------------------------------- receiving
local answered = {}          -- who I've sent the book to, and when (each player at most once a minute)

local function apply(msg, sender)
  local book = LR.book()
  if not book or msg.g ~= book.guild or not B.valid(msg.c) then return end
  local r = Guild.rank(sender)
  if r == nil then
    if #waiting < 50 then waiting[#waiting + 1] = { msg, sender } end
    return
  end
  if r > book.editRank and not (msg.c.editRank and r == 0) then return end
  if B.merge(book, msg.c, r == 0) then LR.changed("book") end
end

Net.handlers.GB = function(msg, channel, sender)
  if channel ~= "GUILD" and channel ~= "WHISPER" then return end
  apply(msg, sender)
end

Net.handlers.GQ = function(msg, channel, sender)
  if channel ~= "GUILD" or not LR.canEditBook() or U.samePlayer(sender, U.me()) then return end
  local who = U.full(sender):lower()
  if answered[who] and GetTime() - answered[who] < 60 then return end
  answered[who] = GetTime()
  local book = LR.book()
  -- a little later, so several officers asked at once don't all answer at the same moment
  C_Timer.After(math.random() * 3, function()
    Net.send({ t = "GB", g = book.guild, c = { points = book.points, prio = book.prio, alts = book.alts, boost = book.boost, editRank = book.editRank, et = book.et } }, "WHISPER", sender)
  end)
end

--- asks the guild for the book
function Guild.query()
  if IsInGuild() then Net.send({ t = "GQ" }, "GUILD") end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("GUILD_ROSTER_UPDATE")
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    C_Timer.After(6, function()
      if not IsInGuild() then return end
      C_GuildInfo.GuildRoster()
      Guild.query()
    end)
  elseif event == "GUILD_ROSTER_UPDATE" then
    Guild.readRoster()
    local again = waiting
    waiting = {}
    for _, w in ipairs(again) do apply(w[1], w[2]) end
    LR.changed("book")
  end
end)
