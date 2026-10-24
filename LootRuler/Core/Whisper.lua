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
function W.session()
  local best
  for _, s in ipairs(LR.sessions()) do
    if LR.isLeader(s) and not s.ended and (not best or s.created > best.created) then best = s end
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
  local left = s.sr - #S.reservesOf(s, player)
  local po = s.plusOne and (" You have %s."):format(S.plusOnes(s, player) == 1 and "a +1" or (S.plusOnes(s, player) .. " +1s")) or ""
  return ("You have reserved %s (%d of %d used%s).%s"):format(list(s, player), s.sr - left, s.sr, s.locked and ", reserves are locked" or "", po)
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
  local s = W.session()
  if not s then return end
  local player = U.full(sender)
  local class = LR.classOf(player)
  local args = U.trim(text:sub(#COMMAND + 1))
  local lower = args:lower()
  local now = U.now()

  if lower == "" or lower == "list" or lower == "help" or lower == "?" then
    W.reply(player, ("Soft reserves for %s: %d each%s. %s Type \"!lr <item link>\" in raid chat or whisper me to reserve, \"!lr remove <item>\" to take one back."):format(
      LR.raidOf(s).name, s.sr, s.dupes and "" or " (one per item)", status(s, player)))
    return
  end

  -- boosted rolls: what their guild points are, and how to roll with them
  if lower == "points" or lower == "boost" then
    local book = LR.book and LR.book()
    if not (s.boost and book and book.boost.on) then W.reply(player, "This raid doesn't use boosted rolls.") return end
    local n = LR.Book.points(book, player)
    if n == 0 then W.reply(player, ("You have no points for boosted rolls yet. Each raid with %s is worth %d."):format(book.guild, book.boost.perRaid)) return end
    local lo, hi = LR.Book.boostRange(n)
    W.reply(player, ("You have %d points. For a boosted main spec roll, type /roll %d %d. If you win with it, the points are spent."):format(n, lo, hi))
    return
  end

  if lower == "clear" or lower == "remove all" then
    local ok, why = S.set(s, player, class, {}, false, now)
    if ok then LR.leaderChanged(s) W.reply(player, "Your reserves are cleared.") else W.reply(player, S.WHY[why]) end
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
  return true
end
