-- Loot council: the session's leader picks a council (Session tab), and when an item is rolled out the council votes
-- for who gets it, from the players who rolled (their rolls say who wants it and for what, and break ties). The loot
-- master sees the votes and gives it out as usual: the council decides, the loot master hands it over. Votes stay with
-- the loot master's addon, which tells the council members the counts; the raid doesn't see them.
--
-- s.lc = { "Name-Realm", ... } (at most Council.MAX): the council; nil: no council. Older versions don't know it.
-- Messages (on top of Core/Rolls.lua's):
--   C  council member -> loot master   my vote on roll k: { k, p = who ("": take my vote back) }
--   L  loot master -> council member   the votes so far on roll k: { k, vc = { ["Name-Realm"] = votes }, n = how many voted }
--                                      (not "v": every message's v is the protocol, Core/Net.lua)
-- Council members without the addon whisper the loot master "!lr vote Name".
local _, LR = ...
local U, S, R = LR.U, LR.Session, LR.Roll
local Net = LR.Net
local Rolls = LR.Rolls

local C = {}
LR.Council = C
C.MAX = S.COUNCIL_MAX

C.clean = S.cleanCouncil          -- (the council, checked: Core/Session.lua, so a session copy is checked with it)

function C.on(s) return s ~= nil and type(s.lc) == "table" and #s.lc > 0 end
function C.isMember(s, name)
  if not C.on(s) or not name then return false end
  for _, n in ipairs(s.lc) do if U.samePlayer(n, name) then return true end end
  return false
end

--- sets the council (the leader); names: a list, or nil for none
function C.set(s, names, now)
  local list = C.clean(names)
  local same = (list == nil and s.lc == nil) or (list and s.lc and table.concat(list, ",") == table.concat(s.lc, ","))
  if same then return false end
  s.lc = list
  S.bump(s, now)
  return true
end

--- whether a roll is one the council votes on: not an auction or a hard reserve, and not given out yet
local function votable(roll)
  return roll and roll.mode ~= "BID" and roll.mode ~= "HR" and (roll.state == "open" or roll.state == "closed")
end
C.votable = votable

--- the votes on a roll: { ["Name-Realm"] = votes }, and how many have voted
function C.counts(roll)
  local out, n = {}, 0
  for _, x in pairs(roll and roll.votes or {}) do
    out[x.p] = (out[x.p] or 0) + 1
    n = n + 1
  end
  return out, n
end

--- the council's choice: the player with the most votes (nil when nobody voted, or it's a tie), and how many
function C.choice(roll)
  local best, top, tie = nil, 0, false
  for p, n in pairs(C.counts(roll)) do
    if n > top then best, top, tie = p, n, false elseif n == top then tie = true end
  end
  if tie then return nil, top end
  return best, top
end

--- the loot master's addon: the council members hear the counts (by whisper; my own copy straight away)
local function share(roll, s)
  local counts, n = C.counts(roll)
  local copy = Rolls.seen[roll.k]
  if copy then copy.votes, copy.voted = counts, n end
  for _, member in ipairs(s and s.lc or {}) do
    if not U.samePlayer(member, U.me()) and LR.inGroup(member) and LR.versionOf(member) then
      Net.send({ t = "L", k = roll.k, vc = counts, n = n }, "WHISPER", member)
    end
  end
  LR.changed("roll")
  LR.changed("rolls")
end

--- a council member's vote on the roll that's on (the loot master's addon). candidate: who ("" or nil: take it back).
--- Returns true (and who), or false and why not.
function C.vote(voter, candidate)
  local roll = Rolls.current
  local s = Rolls.session()
  if not C.isMember(s, voter) then return false, "Only the loot council votes." end
  if not votable(roll) then return false, "There's nothing to vote on right now." end
  roll.votes = roll.votes or {}
  local k = R.key(voter)
  if not candidate or candidate == "" then
    roll.votes[k] = nil
    share(roll, s)
    return true, nil
  end
  -- someone who rolled (and whose roll counts), matched however the voter spelled them
  local who
  for _, e in pairs(roll.rolled) do
    if e.kind and (U.samePlayer(e.p, candidate) or U.foldCase(U.bare(e.p)) == U.foldCase(U.bare(candidate))) then who = e.p end
  end
  if not who then return false, ("%s didn't roll for %s."):format(U.short(candidate), U.plain(roll.link)) end
  roll.votes[k] = { v = U.full(voter), p = who }
  share(roll, s)
  return true, who
end

--- my vote (my roll window): to the loot master's addon, or my own
function C.myVote(copy, candidate)
  if not copy then return false, "There's nothing to vote on right now." end
  copy.myVote = candidate ~= "" and candidate or nil
  if U.samePlayer(copy.by, U.me()) then return C.vote(U.me(), candidate) end
  Net.send({ t = "C", k = copy.k, p = candidate or "" }, "WHISPER", copy.by)
  LR.changed("rolls")
  return true
end

--- what the raid hears when an item is rolled out with a council
function C.howTo() return "The loot council picks who gets it from those who roll." end

Net.handlers.C = function(msg, channel, sender)
  local roll = Rolls.current
  if channel ~= "WHISPER" or not roll or roll.k ~= msg.k or type(msg.p) ~= "string" or #msg.p > 60 then return end
  local ok, why = C.vote(sender, msg.p)
  if not ok then LR.say(LR.TAG .. " " .. why, "WHISPER", sender) end
end

Net.handlers.L = function(msg, channel, sender)
  local copy = type(msg.k) == "string" and Rolls.seen[msg.k]
  if channel ~= "WHISPER" or not copy or not U.samePlayer(copy.by, sender) or type(msg.vc) ~= "table" then return end
  local v, n = {}, 0
  for p, c in pairs(msg.vc) do
    n = n + 1
    if n > 40 then break end
    if type(p) == "string" and #p <= 60 and not p:find("|", 1, true) and type(c) == "number" then v[p] = math.max(0, math.floor(c)) end
  end
  copy.votes, copy.voted = v, math.max(0, math.floor(tonumber(msg.n) or 0))
  LR.changed("rolls")
end
