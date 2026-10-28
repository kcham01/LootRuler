-- The gear overview: what everyone in the group wears, in one place. Whoever runs loot looks: everyone is inspected the
-- way the game does it (one at a time, close enough, out of combat; Settings: inspectGear), so what's shown is the game's
-- word, not an addon's. Each player's gear is kept with when it was read, and how.
--
-- Older versions asked the group (H) and raiders' addons answered (I); neither is sent or answered any more, so an
-- older loot master inspects everyone after its wait.
local _, LR = ...
local U, R = LR.U, LR.Roll

local O = { data = {} }
LR.Overview = O

-- the slots that count (not the shirt or the tabard)
O.SLOTS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }
O.SLOT_NAME = { [1] = "Head", [2] = "Neck", [3] = "Shoulder", [15] = "Back", [5] = "Chest", [9] = "Wrist", [10] = "Hands",
  [6] = "Waist", [7] = "Legs", [8] = "Feet", [11] = "Ring", [12] = "Ring", [13] = "Trinket", [14] = "Trinket",
  [16] = "Main hand", [17] = "Off hand", [18] = "Ranged" }
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
  if LR.Practice.on then LR.Practice.answerGear() end
  -- everyone else: inspected, one at a time
  for _, m in ipairs(LR.roster()) do
    if not U.samePlayer(m.name, U.me()) and not LR.Practice.isPretend(m.name) then
      local key = R.key(m.name)
      if not LR.db.settings.inspectGear then O.why[key] = "off"
      else LR.Rolls.inspect(m.name, readUnit(m.name), function(why) O.why[key] = why LR.changed("gear") end) end
    end
  end
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


