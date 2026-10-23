-- The session rules on their own (Core/Session.lua), plus the item lookups and Gargul strings.
--   lua5.1 tests/session.lua
package.path = "./tests/?.lua;" .. package.path
local failed, passed = 0, 0
local function check(name, ok, detail)
  if ok then passed = passed + 1 else failed = failed + 1 end
  if not ok then print("FAIL " .. name .. (detail and ("  " .. tostring(detail)) or "")) end
end

-- the files that don't need the game, in a plain environment
local LR = {}
local env = setmetatable({ bit = require("bit"), GetRealmName = function() return "Dreamscythe" end,
  GetNormalizedRealmName = function() return "Dreamscythe" end, RAID_CLASS_COLORS = {} }, { __index = _G })
for _, f in ipairs({ "Data/Loot.lua", "Core/Util.lua", "Core/Loot.lua", "Core/Session.lua" }) do
  local chunk = assert(loadfile("LootRuler/" .. f))
  setfenv(chunk, env)
  chunk("LootRuler", LR)
end
local U, S = LR.U, LR.Session

-- the loot data
check("every raid up to Zul'Aman", #LR.RAIDS == 16 and LR.raid("MoltenCore") and LR.raid("ZulAman") and not LR.raid("SunwellPlateau") and not LR.raid("Naxxramas"))
check("Hakkar's off-hand blade is Mandokir's", LR.raidHas("Zul'Gurub", 19866) and #LR.dropsFrom("Zul'Gurub", 19866) == 1 and LR.dropsFrom("Zul'Gurub", 19866)[1] == "Bloodlord Mandokir")
check("boss heads, one for each faction", LR.forFaction(18423, "Alliance") and not LR.forFaction(18423, "Horde") and LR.forFaction(18422, "Horde"))
check("cloth isn't for a paladin", LR.usableBy(28507, "PALADIN") and not LR.forClass(28507, "PALADIN") and LR.forClass(28518, "PALADIN"))
local kara = LR.raid("Karazhan")
check("Karazhan bosses in order", kara.bosses[1].name == "Attumen the Huntsman" and kara.bosses[#kara.bosses].name == "Trash")
check("Dragonspine Trophy drops from Gruul", LR.raidHas("GruulsLair", 28830) and U.indexOf(LR.dropsFrom("GruulsLair", 28830), "Gruul the Dragonkiller"))
check("no Badge of Justice", not LR.raidHas("ZulAman", 29434))
check("tier tokens are class items", not LR.usableBy(29760, "WARRIOR") and LR.usableBy(29761, "WARRIOR"),
  LR.ITEMS[29760][1] .. " / " .. LR.ITEMS[29761][1])
check("plate for plate wearers", LR.usableBy(28518, "PALADIN") and not LR.usableBy(28518, "MAGE"))
check("recipes for everyone", LR.usableBy(22559, "MAGE"))
check("Magtheridon's Head by faction", LR.forFaction(32385, "Alliance") and not LR.forFaction(32385, "Horde") and LR.forFaction(32386, "Horde"))
check("item kinds", LR.itemKind(28518) == "Plate Hands" and LR.itemKind(28830) == "Trinket", LR.itemKind(28518) .. ", " .. LR.itemKind(28830))
check("find by name", LR.findItem("GruulsLair", "dragonspine trophy") == 28830)
check("find by part of the name", LR.findItem("GruulsLair", "dragonspine") == 28830)
check("find by link", LR.findItem("GruulsLair", "|cffa335ee|Hitem:28830::::::::70:::::|h[Dragonspine Trophy]|h|r") == 28830)
local id, close, linked = LR.findItem("Karazhan", "|cffa335ee|Hitem:28830::::::::70:::::|h[Dragonspine Trophy]|h|r")
check("a link from another raid", id == nil and linked == 28830)
local _, many = LR.findItem("Karazhan", "bracers")
check("an unclear name lists the matches", #many > 1)
local g1, gl = LR.findItem("BlackTemple", "Warglaive of Azzinoth")
check("two items with one name ask which", g1 == nil and #gl == 2)
check("the other faction's head is skipped", LR.findItem("MagtheridonsLair", "magtheridon's head", "Horde") == 32386)

-- sessions
local s = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 1000)
check("new session", s.rev == 1 and s.sr == 2 and s.dupes and not s.locked and s.id == "Lead-Dreamscythe:1000")
local A, B = "Ann-Dreamscythe", "Bob-Faerlina"
check("reserve", S.add(s, A, "PRIEST", 28530) and #S.reservesOf(s, A) == 1 and s.rev == 2)
check("double up", S.add(s, A, "PRIEST", 28530) and #S.reservesOf(s, A) == 2)
local ok, why = S.add(s, A, "PRIEST", 28770)
check("no more than the limit", not ok and why == "TOO_MANY")
ok, why = S.add(s, A, "PRIEST", 28830)
check("only this raid's items", not ok and why == "NOT_IN_RAID")
check("take one back", S.remove(s, A, 28530) and #S.reservesOf(s, A) == 1)
ok, why = S.remove(s, A, 28770)
check("can't take back what isn't reserved", not ok and why == "NOT_RESERVED")
check("set a list", S.set(s, B, "MAGE", { 28770, 28762 }) and #S.reservesOf(s, B) == 2)
local rev = s.rev
check("setting the same list changes nothing", S.set(s, B, "MAGE", { 28770, 28762 }) and s.rev == rev)
ok, why = S.set(s, B, "MAGE", { 28770, 28762, 28530 })
check("lists over the limit are refused", not ok and why == "TOO_MANY")

-- hard reserves
local lost
ok, lost = S.setHR(s, 28770, "Lead", "for the tank")
check("hard reserve takes soft reserves away", ok and #lost == 1 and lost[1] == B and #S.reservesOf(s, B) == 1)
ok, why = S.add(s, A, "PRIEST", 28770)
check("hard reserved items can't be reserved", not ok and why == "HARD_RESERVED")
check("lift a hard reserve", S.clearHR(s, 28770) and S.add(s, A, "PRIEST", 28770))

-- options
S.set(s, A, "PRIEST", { 28530, 28530 })
local touched
ok, touched = S.configure(s, 2, false)
check("switching doubling off removes doubled picks", ok and #touched == 1 and #S.reservesOf(s, A) == 1)
ok, why = S.add(s, A, "PRIEST", 28530)
check("then the same item twice is refused", not ok and why == "DUPLICATE")
S.configure(s, 1, false)
check("fewer reserves trims lists", #S.reservesOf(s, B) == 1 and #S.reservesOf(s, A) == 1)
ok, why = S.configure(s, 0, true)
check("reserves each must be 1-10", not ok and why == "BAD_COUNT")
S.configure(s, 2, true)

-- locking
check("lock", S.setLocked(s, true) and s.locked)
ok, why = S.add(s, A, "PRIEST", 28762)
check("locked: raiders can't change", not ok and why == "LOCKED")
check("locked: the leader can", S.add(s, A, "PRIEST", 28762, true))
S.setLocked(s, false)

-- views
local by = S.byItem(s)
check("by item", by[28762] and #by[28762] == 2)
check("players", #S.players(s) == 2 and S.players(s)[1].name == A)
check("valid copy", S.valid(U.copy(s)))
local bad = U.copy(s) bad.sr = 99
check("a copy with nonsense is refused", not S.valid(bad))
bad = U.copy(s) bad.res[A].i[1] = "x"
check("a copy with a bad item is refused", not S.valid(bad))
bad = U.copy(s) bad.raid = "Naxxramas"
check("a copy for an unknown raid is refused", not S.valid(bad))

print(("passed %d"):format(passed))
print(("errors %d"):format(failed))
os.exit(failed == 0 and 0 or 1)
