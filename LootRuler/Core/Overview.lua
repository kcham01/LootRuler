-- The gear overview: what everyone in the group wears, in one place. Whoever runs loot asks; every LootRuler in the
-- group answers by whisper with its player's gear (when they share it, Settings: shareGear), and anyone without the
-- addon, or who doesn't answer, is inspected the way the game does it (one at a time, close enough, out of combat;
-- Settings: inspectGear). Each player's gear is kept with when it was read, and how.
--
-- Messages (on top of Core/Net.lua's):
--   H  loot runner -> group    { k }: "what do you wear?"
--   I  raider -> loot runner   { k, e = { [slot] = link } }: the answer, by whisper
-- Older versions don't know them: their players are inspected instead.
local _, LR = ...
local U, R = LR.U, LR.Roll
local Net = LR.Net

local O = { data = {} }
LR.Overview = O

-- the slots that count (not the shirt or the tabard)
O.SLOTS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }
O.SLOT_NAME = { [1] = "Head", [2] = "Neck", [3] = "Shoulder", [15] = "Back", [5] = "Chest", [9] = "Wrist", [10] = "Hands",
  [6] = "Waist", [7] = "Legs", [8] = "Feet", [11] = "Ring", [12] = "Ring", [13] = "Trinket", [14] = "Trinket",
  [16] = "Main hand", [17] = "Off hand", [18] = "Ranged" }
O.WAIT = 6                 -- seconds for addons to answer before their players are inspected instead
local SLOT_OK = {}
for _, s in ipairs(O.SLOTS) do SLOT_OK[s] = true end

--- a gear table checked: slot -> link, item links only
function O.clean(e)
  local out, n = {}, 0
  if type(e) ~= "table" then return out, 0 end
  for slot, l in pairs(e) do
    if SLOT_OK[slot] and type(l) == "string" and #l <= 300 and l:find("|Hitem:%d+") then out[slot] = l n = n + 1 end
  end
  return out, n
end

--- what I wear
function O.mine()
  local e = {}
  for _, slot in ipairs(O.SLOTS) do e[slot] = GetInventoryItemLink("player", slot) end
  return (O.clean(e))
end

--- keeps a player's gear: how = "addon", "inspect" or "self"
function O.got(player, slots, how)
  player = U.full(player)
  O.data[R.key(player)] = { p = player, slots = slots, at = U.now(), how = how }
  LR.changed("gear")
end

--- the average item level of what someone wears (from the items the game has loaded), and how many items that is
function O.level(slots)
  local sum, n, items = 0, 0, 0
  for _, l in pairs(slots or {}) do
    items = items + 1
    local lvl = C_Item and C_Item.GetItemInfo and select(4, C_Item.GetItemInfo(l))
    if type(lvl) == "number" and lvl > 0 then sum, n = sum + lvl, n + 1 end
  end
  return n > 0 and math.floor(sum / n + 0.5) or nil, items
end

--- reads someone's gear from the game once it's inspected them
local function readUnit(player)
  return function(unit)
    local e = {}
    for _, slot in ipairs(O.SLOTS) do e[slot] = GetInventoryItemLink(unit, slot) end
    O.got(player, (O.clean(e)), "inspect")
  end
end

O.why = {}                  -- key -> why someone couldn't be read this time ("far", "gone", "silent", "off")

--- asks the group (whoever runs loot); returns true, or false and why not
function O.ask()
  if not LR.canRunLoot() then return false, "Only the master looter can ask (or the raid leader, without master loot)." end
  O.k = U.me() .. ":gear:" .. U.now()
  O.why = {}
  O.got(U.me(), O.mine(), "self")
  local ch = LR.groupChannel()
  if ch then Net.send({ t = "H", k = O.k }, ch) end
  if LR.Practice.on then LR.Practice.answerGear() end
  local k = O.k
  -- whoever hasn't answered by then: inspected (players without the addon at once)
  local function inspect(m)
    local key = R.key(m.name)
    if not LR.db.settings.inspectGear then O.why[key] = "off" return end
    LR.Rolls.inspect(m.name, readUnit(m.name), function(why) O.why[key] = why LR.changed("gear") end)
  end
  for _, m in ipairs(LR.roster()) do
    if not U.samePlayer(m.name, U.me()) and not LR.versionOf(m.name) and not LR.Practice.isPretend(m.name) then inspect(m) end
  end
  C_Timer.After(O.WAIT, function()
    if O.k ~= k then return end
    for _, m in ipairs(LR.roster()) do
      local d = O.data[R.key(m.name)]
      if LR.versionOf(m.name) and not U.samePlayer(m.name, U.me()) and not (d and d.at >= U.now() - O.WAIT - 1) then inspect(m) end
    end
    LR.changed("gear")
  end)
  LR.changed("gear")
  return true
end

--- the overview: everyone in the group, with their gear when it's been read (best item level first)
--- { { name, class, d = { slots, at, how } or nil, level, items, why } }
function O.list()
  local out = {}
  for _, m in ipairs(LR.roster()) do
    local key = R.key(m.name)
    local d = O.data[key]
    local level, items = O.level(d and d.slots)
    out[#out + 1] = { name = U.full(m.name), class = m.class, d = d, level = level, items = items, why = O.why[key] }
  end
  table.sort(out, function(a, b)
    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
    return a.name < b.name
  end)
  return out
end

--- "just now", "4 min ago", "2 h ago"
function O.age(at)
  local s = math.max(0, U.now() - (at or 0))
  if s < 60 then return "just now" end
  if s < 3600 then return ("%d min ago"):format(math.floor(s / 60)) end
  return ("%d h ago"):format(math.floor(s / 3600))
end

---------------------------------------------------------------------- answering
local answered = {}

Net.handlers.H = function(msg, channel, sender)
  if channel == "WHISPER" or type(msg.k) ~= "string" or #msg.k > 120 then return end
  if U.samePlayer(sender, U.me()) or not LR.canRunLoot(sender) or answered[msg.k] then return end
  if not LR.db.settings.shareGear then return end
  answered[msg.k] = true
  Net.send({ t = "I", k = msg.k, e = O.mine() }, "WHISPER", sender)
end

Net.handlers.I = function(msg, channel, sender)
  if channel ~= "WHISPER" or msg.k ~= O.k or not LR.inGroup(sender) then return end
  O.got(sender, (O.clean(msg.e)), "addon")
end
