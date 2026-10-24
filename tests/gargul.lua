-- The reserves LootRuler hands to Gargul: the "Gargul export" layout softres.it publishes (zlib-compressed,
-- base64-encoded JSON: metadata, softreserves with each player's items, hardreserves). Checked with
-- LootRuler's own code only: no part of Gargul is used, downloaded or run here (Gargul's licence reserves
-- all rights). Also reads a softres.it-style export back into a session.
--   lua5.1 tests/gargul.lua
package.path = "./tests/?.lua;" .. package.path
local failed, passed = 0, 0
local function check(name, ok, detail)
  if ok then passed = passed + 1 else failed = failed + 1 end
  print((ok and "ok   " or "FAIL ") .. name .. ((not ok and detail ~= nil) and ("  " .. tostring(detail)) or ""))
end

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
local LibDeflate = env.LibStub("LibDeflate")

print("== the reserves, the way Gargul's soft-reserve importer takes them")
local s = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 1760000000)
S.set(s, "Lead-Dreamscythe", "PALADIN", { 28529, 28762 })
S.set(s, "Ann-Dreamscythe", "PRIEST", { 28528, 28528 })
S.set(s, "Bob-Faerlina", "MAGE", { 28762 })
S.set(s, "Pug-Dreamscythe", nil, { 28525 })
S.setHR(s, 28770, "Ann", "healer priority")
S.setHR(s, 30480, "", "")

local str = LR.Gargul.export(s)
check("one line of base64 (what Gargul's importer box takes)", str:match("^[%w%+/=]+$") ~= nil)
-- unpacked by hand, step by step, as any importer of the layout would
local raw = U.b64decode(str)
local json = raw and LibDeflate:DecompressZlib(raw)
local data = json and U.fromJSON(json)
check("zlib-compressed JSON inside", type(data) == "table")
local meta = data and data.metadata or {}
check("metadata: an id, the raid, when", type(meta.id) == "string" and meta.id:find("^LootRuler") and meta.instance == "Karazhan"
  and meta.createdAt == 1760000000 and meta.updatedAt == 1760000000 and meta.hidden == false)
local by = {}
for _, r in ipairs(data and data.softreserves or {}) do by[r.name] = r end
check("every player who reserved", #(data and data.softreserves or {}) == 4)
check("names without this realm, with other realms", by.Lead and by.Ann and by.Pug and by["Bob-Faerlina"])
local function ids(r) local o = {} for _, it in ipairs(r and r.items or {}) do o[#o + 1] = it.id end table.sort(o) return table.concat(o, ",") end
check("each player's items", ids(by.Lead) == "28529,28762" and ids(by["Bob-Faerlina"]) == "28762" and ids(by.Pug) == "28525")
check("doubled reserves listed twice", ids(by.Ann) == "28528,28528")
check("classes in lower case, or none", by.Ann.class == "priest" and by.Lead.class == "paladin" and (by.Pug.class == nil or by.Pug.class == ""))
check("the fields every entry has", by.Ann.note == "" and by.Ann.plusOnes == 0)
local hr = {}
for _, h in ipairs(data and data.hardreserves or {}) do hr[h.id] = h end
check("hard reserves, with who they're for and the note", hr[28770] and hr[28770]["for"] == "Ann" and hr[28770].note == "healer priority")
check("hard reserved for nobody in particular", hr[30480] and hr[30480]["for"] == "" and #(data.hardreserves) == 2)
local back = LR.Gargul.decode(str)
check("LootRuler reads its own export back", back and #back.softreserves == 4 and #back.hardreserves == 2)

print("== a softres.it export, into a session")
local site = {
  metadata = { id = "abcd12", createdAt = 1, updatedAt = 2, hidden = false, discordUrl = "", instance = "karazhan" },
  softreserves = {
    { name = "Zed", class = "rogue", items = { { id = 28528 }, { id = 28830 } }, note = "", plusOnes = 0 },
    { name = "Ann", class = "priest", items = { { id = 28525 } }, note = "", plusOnes = 0 },
  },
  hardreserves = { { id = 28770, ["for"] = "Lead", note = "" } },
}
local siteString = U.b64encode((LibDeflate:CompressZlib(U.toJSON(site))))
local s2 = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 1760000000)
local sum = LR.Gargul.importInto(s2, siteString)
check("a softres.it export comes into a session", sum and sum.players == 2 and sum.items == 2 and sum.hard == 1)
check("items from other raids are skipped", sum and sum.skipped == 1)
check("with classes", s2.res["Zed-Dreamscythe"] and s2.res["Zed-Dreamscythe"].c == "ROGUE")
check("and hard reserves", s2.hr[28770] and s2.hr[28770].f == "Lead")
local bad, err = LR.Gargul.importInto(s2, "this isn't an export")
check("rubbish is refused with a reason", bad == nil and type(err) == "string")

print(("passed %d"):format(passed))
print(("errors %d"):format(failed))
os.exit(failed == 0 and 0 or 1)
