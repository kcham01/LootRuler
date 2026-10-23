-- Reads AtlasLootClassic's raid tables (AtlasLootClassic_DungeonsAndRaids: data.lua for the original raids,
-- data-tbc.lua for TBC's) by running the files against a small stand-in for AtlasLoot set to the TBC
-- client, and prints the raids, their bosses and the item ids each one drops as JSON:
--   lua5.1 tools/atlasloot_extract.lua <AtlasLootClassic_DungeonsAndRaids folder> > out.json
local dir = assert(arg[1], "usage: atlasloot_extract.lua <AtlasLootClassic_DungeonsAndRaids folder>")

local function L(t) return setmetatable({}, { __index = function(_, k) return k end }) end
local diffs, made = {}, {}
local data = setmetatable({}, { __index = {
  AddDifficulty = function(_, name) diffs[name] = name return name end,
  AddItemTableType = function(_, a) return "ittype:" .. a end,
  AddExtraItemTableType = function(_, a) return "extra:" .. a end,
  AddContentType = function(_, a) return "content:" .. a end,
} })
-- AtlasLoot's version helpers (Init.lua), answering as the TBC client (version 2) does
local CURRENT = 2
local function cmp(test) return function(_, v, ret, retFalse) if test(CURRENT, v) then return ret or true end return retFalse end end
local AtlasLoot = {
  CLASSIC_VERSION_NUM = 1, BC_VERSION_NUM = 2, WRATH_VERSION_NUM = 3, RETAIL_VERSION_NUM = 99, CURRENT_VERSION_NUM = CURRENT,
  GameVersion_EQ = cmp(function(a, b) return a == b end), GameVersion_NE = cmp(function(a, b) return a ~= b end),
  GameVersion_GT = cmp(function(a, b) return a > b end), GameVersion_LT = cmp(function(a, b) return a < b end),
  GameVersion_GE = cmp(function(a, b) return a >= b end), GameVersion_LE = cmp(function(a, b) return a <= b end),
  GetGameVersion = function() return CURRENT end,
  ReturnForGameVersion = function(classic, bcc, wrath) return bcc or classic end,
  ItemDB = { Add = function() return data end },
  Locales = L(), IngameLocales = L(),
  Data = { ContentPhase = { GetActivePhase = function() return 99 end } },
}
local env = setmetatable({ AtlasLoot = AtlasLoot, C_Seasons = { GetActiveSeason = function() return 0 end },
  UnitFactionGroup = function() return "Alliance" end }, { __index = function(_, k)
  if _G[k] ~= nil then return _G[k] end
  -- the game's API (dungeon names from C_Map and the like): anything, answering "?"
  if type(k) == "string" and k:match("^C_") then
    local any
    any = setmetatable({}, { __index = function() return any end, __call = function() return "?" end })
    return any
  end
  return k   -- ATLASLOOT_* constants and colours: their own names are fine here
end })
env._G = env
env.getfenv = function() return env end
for _, file in ipairs({ "data.lua", "data-tbc.lua" }) do
  local chunk = assert(loadfile(dir .. "/" .. file))
  setfenv(chunk, env)
  chunk("AtlasLootClassic_DungeonsAndRaids")
end

local RAIDS = { "MoltenCore", "Onyxia", "BlackwingLair", "Zul'Gurub", "TheRuinsofAhnQiraj", "TheTempleofAhnQiraj", "WorldBosses",
  "Karazhan", "GruulsLair", "MagtheridonsLair", "SerpentshrineCavern", "TempestKeep", "HyjalSummit", "BlackTemple", "ZulAman",
  "SunwellPlateau", "WorldBossesBC" }

--- a list AtlasLoot wrote with holes in it (entries for other game versions are nil): its entries in order
local function entries(t)
  local n = 0
  for k in pairs(t) do if type(k) == "number" and k > n then n = k end end
  local out = {}
  for i = 1, n do if t[i] ~= nil then out[#out + 1] = t[i] end end
  return out
end

local function str(s) return '"' .. tostring(s):gsub('[%c"\\]', function(c) return ("\\u%04x"):format(c:byte()) end) .. '"' end
local function strip(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local out = {}
for _, key in ipairs(RAIDS) do
  local raid = data[key]
  assert(raid, "no raid " .. key)
  local bosses = {}
  for _, b in ipairs(entries(raid.items)) do if type(b) == "table" then
    local list
    for _, d in ipairs({ "NORMAL", "25RAID", "10RAID", "40RAID", "20RAID", "FACTION_ALLIANCE" }) do if type(b[d]) == "table" then list = b[d] break end end
    local items = {}
    for _, e in ipairs(entries(list or {})) do
      local id = e[2]
      if type(id) == "number" then
        local alt = {}
        for k, v in pairs(e) do if type(k) == "string" and type(v) == "number" then alt[#alt + 1] = str(k) .. ":" .. v end end
        items[#items + 1] = ("[%d,%d%s]"):format(e[1], id, #alt > 0 and (",{" .. table.concat(alt, ",") .. "}") or "")
      end
    end
    local npc = b.npcID
    if type(npc) == "table" then npc = "[" .. table.concat(npc, ",") .. "]" elseif npc then npc = tostring(npc) else npc = "null" end
    local name = b.nameFormat and b.nameFormat:format(b.name) or b.name
    bosses[#bosses + 1] = ('{"name":%s,"npc":%s,"extra":%s,"set":%s,"items":[%s]}'):format(str(strip(name or "?")), npc,
      tostring(b.ExtraList and true or false), tostring(b.TableType == "ittype:Set"), table.concat(items, ","))
  end end
  out[#out + 1] = ('{"key":%s,"instance":%s,"bosses":[%s]}'):format(str(key), tostring(raid.InstanceID or "null"), table.concat(bosses, ","))
end
print("[" .. table.concat(out, ",\n") .. "]")
