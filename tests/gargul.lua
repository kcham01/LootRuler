-- LootRuler's Gargul export, read by Gargul's own code. Loads Gargul's soft-reserve importer
-- (Classes/SoftRes.lua, with its Base64, JSON, constants and table helpers) from a copy of Gargul, imports
-- the string LootRuler makes, and checks what Gargul ends up with: every player's reserves (doubled ones
-- counted twice), classes, and the hard reserves with who they're for. Also reads a softres.it-style export
-- back into a session.
--   GARGUL=<path to the Gargul addon folder> lua5.1 tests/gargul.lua
-- (CI clones github.com/papa-smurf/Gargul for this; Gargul isn't part of LootRuler.)
package.path = "./tests/?.lua;" .. package.path
local failed, passed = 0, 0
local function check(name, ok, detail)
  if ok then passed = passed + 1 else failed = failed + 1 end
  print((ok and "ok   " or "FAIL ") .. name .. ((not ok and detail ~= nil) and ("  " .. tostring(detail)) or ""))
end

---------------------------------------------------------------------- LootRuler's side (no game needed)
local LR = {}
local env = setmetatable({ bit = require("bit"), GetRealmName = function() return "Dreamscythe" end,
  GetNormalizedRealmName = function() return "Dreamscythe" end, RAID_CLASS_COLORS = {} }, { __index = _G })
env._G = env
local function run(path, ns, name)
  local chunk = assert(loadfile(path))
  setfenv(chunk, env)
  chunk(name or "LootRuler", ns)
end
run("LootRuler/Libs/LibStub/LibStub.lua")
run("LootRuler/Libs/LibDeflate/LibDeflate.lua")
for _, f in ipairs({ "Data/Loot.lua", "Core/Util.lua", "Core/Loot.lua", "Core/Session.lua", "Core/Gargul.lua" }) do run("LootRuler/" .. f, LR) end
local U, S = LR.U, LR.Session
LR.classOf = function() return nil end
LR.leaderChanged = function() end
env.GetServerTime = function() return 1760000000 end

local s = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 1760000000)
S.set(s, "Lead-Dreamscythe", "PALADIN", { 28529, 28762 })
S.set(s, "Ann-Dreamscythe", "PRIEST", { 28528, 28528 })
S.set(s, "Bob-Faerlina", "MAGE", { 28762 })
S.set(s, "Pug-Dreamscythe", nil, { 28525 })
S.setHR(s, 28770, "Ann", "healer priority")
S.setHR(s, 30480, "", "")

local str = LR.Gargul.export(s)
check("the export is base64", str:match("^[%w%+/=]+$") ~= nil)
local back = LR.Gargul.decode(str)
check("LootRuler reads its own export back", back and #back.softreserves == 4 and #back.hardreserves == 2)

---------------------------------------------------------------------- Gargul's side
local GARGUL = os.getenv("GARGUL")
if not GARGUL or GARGUL == "" then
  print("(GARGUL isn't set: skipping the checks with Gargul's own code)")
else
  local GL = { Data = {}, version = "test", tocVersion = 20506, clientVersion = 20506 }
  local log = {}
  local genv = setmetatable({}, { __index = env })
  genv._G = genv
  -- Gargul's helpers fetch libraries it bundles (glow effects and the like) that the importer never uses
  genv.LibStub = setmetatable({}, { __call = function(_, name) return env.LibStub(name, true) or setmetatable({}, { __index = function() return function() end end }) end,
    __index = function(_, k) return env.LibStub[k] end })
  genv.Gargul_L = setmetatable({ CHAT = setmetatable({}, { __index = function(_, k) return k end }) }, { __index = function(_, k) return k end })
  genv.strtrim = function(x) return (x:gsub("^%s+", ""):gsub("%s+$", "")) end
  genv.strlower, genv.strupper, genv.strlen, genv.strsub, genv.strfind, genv.strmatch, genv.strsplit, genv.tinsert, genv.wipe =
    string.lower, string.upper, string.len, string.sub, string.find, string.match, function(sep, x) local o = {} for p in (x .. sep):gmatch("(.-)" .. sep) do o[#o + 1] = p end return unpack(o) end,
    table.insert, function(t) for k in pairs(t) do t[k] = nil end return t end
  genv.strchar, genv.strbyte, genv.strrep, genv.format, genv.gsub, genv.floor, genv.max, genv.min, genv.tremove, genv.sort =
    string.char, string.byte, string.rep, string.format, string.gsub, math.floor, math.max, math.min, table.remove, table.sort
  genv.GetServerTime = function() return 1760000000 end
  genv.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
  genv.GetBuildInfo = function() return "2.5.5", "70006", "Oct 1 2026", 20506 end
  local function load(file)
    local chunk = assert(loadfile(GARGUL .. "/" .. file))
    setfenv(chunk, genv)
    chunk("Gargul", GL)
  end
  load("Utils/Tables.lua")
  load("Utils/Strings.lua")
  load("Utils/Misc.lua")
  load("Classes/Base64.lua")
  load("Classes/JSON.lua")
  load("Data/Constants.lua")
  -- the parts of Gargul the importer touches, stood in for
  local store = { SoftRes = {} }
  GL.DB = setmetatable(store, { __index = {
    get = function(_, key, default) return GL:tableGet(store, key, default) end,
    set = function(_, key, value) return GL:tableSet(store, key, value) end,
    add = function(_, key, value) local t = GL:tableGet(store, key, {}) table.insert(t, value) GL:tableSet(store, key, t) end,
  } })
  GL.Settings = { get = function(_, _, default) return default end }
  GL.PlusOnes = { getPlusOnes = function() return 0 end, setPlusOnes = function() end, clearPlusOnes = function() end }
  -- windows Gargul would open or close: anything goes, nothing happens
  local nothing
  nothing = setmetatable({}, { __index = function() return nothing end, __call = function() return nil end })
  GL.Interface = setmetatable({ get = function() return { SetText = function(_, t) log[#log + 1] = t end } end }, { __index = function() return nothing end })
  GL.Events = { fire = function() end }
  GL.GetItemInfoInstant = function(id) return id, "Armor" end
  GL.BoostedRolls = { importFromSoftres = function() end }
  load("Classes/SoftRes.lua")
  local SoftRes = GL.SoftRes

  local ok = SoftRes:importGargulData(str)
  check("Gargul's importer accepts the string", ok == true, table.concat(log, " | "))
  local soft = GL.DB:get("SoftRes.SoftReserves", {})
  local hard = GL.DB:get("SoftRes.HardReserves", {})
  check("every player who reserved", #soft == 4)
  check("hard reserves", #hard == 2)
  check("Gargul keeps the softres metadata", GL.DB:get("SoftRes.MetaData.id", ""):find("^LootRuler") ~= nil)
  check("materialized", SoftRes:materializeData())
  local d = SoftRes.MaterializedData.DetailsByPlayerName
  check("the leader's reserves", d.lead and d.lead.Items["28529"] == 1 and d.lead.Items["28762"] == 1)
  check("doubled reserves count twice", d.ann and d.ann.Items["28528"] == 2)
  check("players from other realms keep their realm", d["bob-faerlina"] and d["bob-faerlina"].Items["28762"] == 1)
  check("classes", SoftRes.MaterializedData.ClassByPlayerName.ann == "priest" and SoftRes.MaterializedData.ClassByPlayerName.lead == "paladin")
  local names = SoftRes.MaterializedData.PlayerNamesByItemID["28762"] or {}
  table.sort(names)
  check("who reserved what", table.concat(names, ",") == "bob-faerlina,lead")
  local hr = SoftRes.MaterializedData.HardReserveDetailsByID
  check("hard reserve for a player", hr["28770"] and hr["28770"].reservedFor == "Ann" and hr["28770"].note == "healer priority")
  check("hard reserve for nobody in particular", hr["30480"] and hr["30480"].reservedFor == "")

  ---------------------------------------------------------------------- softres.it into LootRuler
  -- an export the way softres.it writes it (encoded with Gargul's own JSON and base64 code)
  local LibDeflate = env.LibStub("LibDeflate")
  local site = {
    metadata = { id = "abcd12", createdAt = 1, updatedAt = 2, hidden = false, discordUrl = "", instance = "karazhan" },
    softreserves = {
      { name = "Zed", class = "rogue", items = { { id = 28528 }, { id = 28830 } }, note = "", plusOnes = 0 },
      { name = "Ann", class = "priest", items = { { id = 28525 } }, note = "", plusOnes = 0 },
    },
    hardreserves = { { id = 28770, ["for"] = "Lead", note = "" } },
  }
  local siteString = GL.Base64.encode((LibDeflate:CompressZlib(GL.JSON:encode(site))))
  local s2 = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 1760000000)
  local sum = LR.Gargul.importInto(s2, siteString)
  check("a softres.it export comes into a session", sum and sum.players == 2 and sum.items == 2 and sum.hard == 1)
  check("items from other raids are skipped", sum and sum.skipped == 1)
  check("with classes", s2.res["Zed-Dreamscythe"] and s2.res["Zed-Dreamscythe"].c == "ROGUE")
  check("and hard reserves", s2.hr[28770] and s2.hr[28770].f == "Lead")
  local bad, err = LR.Gargul.importInto(s2, "this isn't an export")
  check("rubbish is refused with a reason", bad == nil and type(err) == "string")
end

print(("passed %d"):format(passed))
print(("errors %d"):format(failed))
os.exit(failed == 0 and 0 or 1)
