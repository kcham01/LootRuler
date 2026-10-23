-- Reads AtlasLootClassic's TBC raid tables (AtlasLootClassic_DungeonsAndRaids/data-tbc.lua) by running the
-- file against a small stand-in for AtlasLoot, and prints the raids, their bosses and the item ids each one
-- drops as JSON:   lua5.1 tools/atlasloot_extract.lua <path to data-tbc.lua> > out.json
local path = assert(arg[1], "usage: atlasloot_extract.lua <data-tbc.lua>")

local function L(t) return setmetatable({}, { __index = function(_, k) return k end }) end
local diffs, made = {}, {}
local data = setmetatable({}, { __index = {
  AddDifficulty = function(_, name) diffs[name] = name return name end,
  AddItemTableType = function(_, a) return "ittype:" .. a end,
  AddExtraItemTableType = function(_, a) return "extra:" .. a end,
  AddContentType = function(_, a) return "content:" .. a end,
} })
local AtlasLoot = {
  BC_VERSION_NUM = 2, GameVersion_LT = function() return false end, GameVersion_GT = function() return true end,
  GameVersion_GE = function() return true end, GameVersion_LE = function() return true end,
  ItemDB = { Add = function() return data end },
  Locales = L(), IngameLocales = L(),
}
local env = setmetatable({ AtlasLoot = AtlasLoot }, { __index = function(_, k)
  if _G[k] ~= nil then return _G[k] end
  return k   -- ATLASLOOT_* constants and colours: their own names are fine here
end })
env._G = env
env.getfenv = function() return env end
local chunk = assert(loadfile(path))
setfenv(chunk, env)
chunk("AtlasLootClassic_DungeonsAndRaids")

local RAIDS = { "Karazhan", "GruulsLair", "MagtheridonsLair", "SerpentshrineCavern", "TempestKeep", "HyjalSummit",
  "BlackTemple", "ZulAman", "SunwellPlateau", "WorldBossesBC" }

local function str(s) return '"' .. tostring(s):gsub('[%c"\\]', function(c) return ("\\u%04x"):format(c:byte()) end) .. '"' end
local function strip(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local out = {}
for _, key in ipairs(RAIDS) do
  local raid = data[key]
  assert(raid, "no raid " .. key)
  local bosses = {}
  for _, b in ipairs(raid.items) do if type(b) == "table" then
    local list
    for _, d in ipairs({ "NORMAL", "25RAID", "10RAID" }) do if b[d] then list = b[d] break end end
    local items = {}
    for _, e in ipairs(list or {}) do
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
