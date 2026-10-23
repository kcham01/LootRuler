-- The raids and their loot: lookups, which items a class can use, and item names, links and icons from the
-- game (with the English names from Data/Loot.lua until the game has the item loaded).
local _, LR = ...
local U = LR.U

LR.RAID_BY_KEY = {}
for _, r in ipairs(LR.RAIDS) do
  LR.RAID_BY_KEY[r.key] = r
  r.has = {}           -- item id -> true
  r.order = {}         -- every item once, in list order
  for _, b in ipairs(r.bosses) do
    for _, id in ipairs(b.items) do
      if not r.has[id] then r.has[id] = true r.order[#r.order + 1] = id end
    end
  end
end

function LR.raid(key) return key and LR.RAID_BY_KEY[key] end
function LR.raidHas(key, id) local r = LR.RAID_BY_KEY[key] return r and r.has[id] or false end

--- which bosses in a raid drop an item (names)
function LR.dropsFrom(key, id)
  local out = {}
  local r = LR.RAID_BY_KEY[key]
  for _, b in ipairs(r and r.bosses or {}) do
    if U.indexOf(b.items, id) then out[#out + 1] = b.name end
  end
  return out
end

---------------------------------------------------------------------- who can use what (TBC)
LR.CLASS_BIT = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }
local ARMOR = {      -- item class 4 subclasses each class can wear
  [2] = { ROGUE = 1, HUNTER = 1, SHAMAN = 1, DRUID = 1, WARRIOR = 1, PALADIN = 1 },   -- leather
  [3] = { HUNTER = 1, SHAMAN = 1, WARRIOR = 1, PALADIN = 1 },                        -- mail
  [4] = { WARRIOR = 1, PALADIN = 1 },                                                -- plate
  [6] = { WARRIOR = 1, PALADIN = 1, SHAMAN = 1 },                                    -- shields
  [7] = { PALADIN = 1 }, [8] = { DRUID = 1 }, [9] = { SHAMAN = 1 },                  -- librams, idols, totems
}
local WEAPON = {     -- item class 2 subclasses each class can learn
  WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
  PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
  HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
  ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
  PRIEST = { 4, 10, 15, 19 },
  SHAMAN = { 0, 1, 4, 5, 10, 13, 15 },
  MAGE = { 7, 10, 15, 19 },
  WARLOCK = { 7, 10, 15, 19 },
  DRUID = { 4, 5, 10, 13, 15 },
}
local WEAPON_OK = {}
for cls, list in pairs(WEAPON) do WEAPON_OK[cls] = {} for _, s in ipairs(list) do WEAPON_OK[cls][s] = true end end

--- whether a class (token, "PALADIN") can use an item: class-only items (tier tokens) and the armour and
--- weapons it can equip. Recipes, gems, quest items and mounts are for everyone.
function LR.usableBy(id, cls)
  local it = LR.ITEMS[id]
  if not it or not cls then return true end
  local mask, class, sub = it[7], it[4], it[5]
  if mask and mask ~= -1 and LR.CLASS_BIT[cls] and bit.band(mask, LR.CLASS_BIT[cls]) == 0 then return false end
  if class == 4 and ARMOR[sub] then return ARMOR[sub][cls] == 1 end
  if class == 2 then return WEAPON_OK[cls] and WEAPON_OK[cls][sub] or false end
  return true
end

-- the armour each class wears (TBC, level 40 and up)
local BEST_ARMOR = { WARRIOR = 4, PALADIN = 4, HUNTER = 3, SHAMAN = 3, ROGUE = 2, DRUID = 2, PRIEST = 1, MAGE = 1, WARLOCK = 1 }

--- what a class would reserve: what it can use, and of armour only its own kind (plate for a paladin, not
--- the cloth it could also wear). Cloaks, jewellery, weapons, tokens and everything else as LR.usableBy.
function LR.forClass(id, cls)
  if not LR.usableBy(id, cls) then return false end
  local it = LR.ITEMS[id]
  if it and it[4] == 4 and it[5] >= 1 and it[5] <= 4 and it[3] ~= 16 and BEST_ARMOR[cls] then return it[5] == BEST_ARMOR[cls] end
  return true
end

local ALLIANCE, HORDE = 1101, 690
--- items that only drop for one faction (Magtheridon's Head) are hidden from the other
function LR.forFaction(id, faction)
  local it = LR.ITEMS[id]
  local race = it and it[8]
  if not race or race == -1 or not faction then return true end
  if faction == "Alliance" then return race == ALLIANCE end
  if faction == "Horde" then return race == HORDE end
  return true
end

---------------------------------------------------------------------- names, links, icons
local QUALITY = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }
local SLOT_NAME = {
  [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet", [9] = "Wrist",
  [10] = "Hands", [11] = "Finger", [12] = "Trinket", [13] = "One-Hand", [14] = "Off Hand", [15] = "Ranged", [16] = "Back",
  [17] = "Two-Hand", [20] = "Chest", [21] = "Main Hand", [22] = "Off Hand", [23] = "Held In Off-hand", [25] = "Thrown",
  [26] = "Ranged", [28] = "Relic",
}
local ARMOR_NAME = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate", [6] = "Shield", [7] = "Libram", [8] = "Idol", [9] = "Totem" }
local WEAPON_NAME = { [0] = "Axe", [1] = "Axe", [2] = "Bow", [3] = "Gun", [4] = "Mace", [5] = "Mace", [6] = "Polearm", [7] = "Sword",
  [8] = "Sword", [10] = "Staff", [13] = "Fist Weapon", [15] = "Dagger", [16] = "Thrown", [18] = "Crossbow", [19] = "Wand" }
local MISC_NAME = { [9] = "Recipe", [7] = "Trade Goods", [3] = "Gem", [12] = "Quest", [15] = "Miscellaneous", [0] = "Consumable" }

local function info(id)
  if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(id) end
end

--- the item's name in the game's language once it's loaded (the English name until then)
function LR.itemName(id)
  local name = info(id)
  if name then return name end
  local it = LR.ITEMS[id]
  return it and it[1] or ("item " .. tostring(id))
end
function LR.quality(id) local it = LR.ITEMS[id] return it and it[2] or 4 end
function LR.qualityHex(id) return QUALITY[LR.quality(id)] or "ffffff" end
function LR.coloredName(id) return "|cff" .. LR.qualityHex(id) .. LR.itemName(id) .. "|r" end
--- the game's link for chat ([Item] in its quality colour)
function LR.itemLink(id)
  local _, link = info(id)
  if link then return link end
  return ("|cff%s|Hitem:%d::::::::70:::::|h[%s]|h|r"):format(LR.qualityHex(id), id, LR.itemName(id))
end
function LR.itemIcon(id)
  local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
  return icon or 134400                          -- the question mark
end
--- "Plate Hands", "Trinket", "Recipe" ...
function LR.itemKind(id)
  local it = LR.ITEMS[id]
  if not it then return "" end
  local slot, class, sub = SLOT_NAME[it[3]], it[4], it[5]
  if class == 4 then
    local a = ARMOR_NAME[sub]
    if a and (sub >= 6) then return a end
    if a and slot and slot ~= "Back" then return a .. " " .. slot end
    return slot or a or "Armor"
  end
  if class == 2 then
    local w = WEAPON_NAME[sub] or "Weapon"
    if slot == "Two-Hand" then return "Two-Hand " .. w end
    if slot and slot ~= "Ranged" and slot ~= "Thrown" then return slot .. " " .. w end
    return w
  end
  if class == 15 and LR.ITEMS[id][7] ~= -1 then return "Tier token" end
  return MISC_NAME[class] or ""
end

--- asks the game for every item of a raid so names and icons are ready
function LR.preload(key)
  local r = LR.RAID_BY_KEY[key]
  if not r or not (C_Item and C_Item.RequestLoadItemDataByID) then return end
  for _, id in ipairs(r.order) do
    if not info(id) then C_Item.RequestLoadItemDataByID(id) end
  end
end

--- finds a raid item from what someone typed: an item link, an item id, or (part of) its name. Returns the
--- id, or nil and a list of close matches. Items for the other faction are skipped.
function LR.findItem(key, text, faction)
  local r = LR.RAID_BY_KEY[key]
  if not r then return nil, {} end
  text = U.trim(text)
  local linked = tonumber(text:match("|Hitem:(%d+)")) or tonumber(text:match("^%[?(%d+)%]?$"))
  if linked then return r.has[linked] and linked or nil, {}, linked end
  local want = U.plain(text):gsub("^%[", ""):gsub("%]$", ""):lower()
  if want == "" then return nil, {} end
  local exact, partial = {}, {}
  for _, id in ipairs(r.order) do
    if LR.forFaction(id, faction) then
      local here, english = LR.itemName(id):lower(), (LR.ITEMS[id] and LR.ITEMS[id][1] or ""):lower()
      if here == want or english == want then
        exact[#exact + 1] = id
      elseif here:find(want, 1, true) or english:find(want, 1, true) then
        partial[#partial + 1] = id
      end
    end
  end
  if #exact == 1 then return exact[1], {} end
  if #exact > 1 then return nil, exact end
  if #partial == 1 then return partial[1], {} end
  return nil, partial
end
