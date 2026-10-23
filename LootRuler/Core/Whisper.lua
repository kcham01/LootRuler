-- Reserving by whisper, for raiders without the addon. They whisper the raid leader:
--   !lr <item link or name>     reserve an item (several links in one whisper reserve each)
--   !lr remove <item>           take a reserve back
--   !lr clear                   take all of them back
--   !lr                         what you have reserved
-- The leader's addon answers by whisper. ("!sr" is left alone: Gargul answers that one.)
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

local function chat(msg, channel, target)
  local fn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  fn(msg, channel, nil, target)
end

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
  return ("You have reserved %s (%d of %d used%s)."):format(list(s, player), s.sr - left, s.sr, s.locked and ", reserves are locked" or "")
end

local function nameOf(s, id) return LR.itemLink(id) end

--- one item from what was typed; replies with what went wrong when it can't tell
local function pick(s, player, text)
  local faction = UnitFactionGroup("player")
  local id, close, linked = LR.findItem(s.raid, text, faction)
  if id then return id end
  if linked then
    W.reply(player, ("%s doesn't drop in %s."):format(LR.itemLink(linked), LR.raid(s.raid).name))
  elseif #close > 1 then
    local some = {}
    for i = 1, math.min(4, #close) do some[i] = LR.itemLink(close[i]) end
    W.reply(player, ("Which one? %s%s - whisper the item link to be sure."):format(table.concat(some, " "), #close > 4 and " ..." or ""))
  else
    W.reply(player, ("I couldn't find \"%s\" in %s. Shift-click the item to whisper its link."):format(U.plain(text), LR.raid(s.raid).name))
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
    W.reply(player, ("Soft reserves for %s: %d each%s. %s Whisper \"!lr <item link>\" to reserve, \"!lr remove <item>\" to take one back."):format(
      LR.raid(s.raid).name, s.sr, s.dupes and "" or " (one per item)", status(s, player)))
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

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:SetScript("OnEvent", function(_, _, text, sender)
  if LR.db and isCommand(text) then
    local ok, err = pcall(W.handle, text, sender)
    if not ok then geterrorhandler()(err) end
  end
end)

-- hides "!lr" whispers to us and our answers (they'd flood the leader's chat during sign-ups)
local function hideIncoming(_, _, text) return LR.db and LR.db.settings.hideWhispers and W.session() ~= nil and isCommand(text) end
local function hideOutgoing(_, _, text) return LR.db and LR.db.settings.hideWhispers and text and text:sub(1, #LR.TAG) == LR.TAG end
local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
if addFilter then
  addFilter("CHAT_MSG_WHISPER", hideIncoming)
  addFilter("CHAT_MSG_WHISPER_INFORM", hideOutgoing)
end
W.hideIncoming, W.hideOutgoing = hideIncoming, hideOutgoing

--- the line the leader posts to the raid
function W.announce(s)
  local text = ("%s Soft reserves are open for %s: %s each%s. Reserve in the LootRuler addon, or whisper me \"!lr <item link>\"."):format(
    LR.TAG, LR.raid(s.raid).name, U.plural(s.sr, "reserve"), s.dupes and "" or ", one per item")
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
