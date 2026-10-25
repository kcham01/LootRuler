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

print("== importing the sheet again, after it changed")
local function pack(t) return U.b64encode((LibDeflate:CompressZlib(U.toJSON(t)))) end
local function list(s, name) local o = U.copy(S.reservesOf(s, name)) table.sort(o) return table.concat(o, ",") end
local s3 = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 1760000000)
S.set(s3, "Ann-Dreamscythe", "PRIEST", { 28529 }, false, 1760000000)       -- Ann reserved one in LootRuler
local sheet = {
  metadata = { id = "x1", instance = "karazhan" },
  softreserves = {
    { name = "Zed", class = "rogue", items = { { id = 28528 }, { id = 28525 } } },
    { name = "Ann", class = "priest", items = { { id = 28762 } } },
    { name = "Cara", class = "druid", items = { { id = 28530 } } },
  },
  hardreserves = { { id = 28770, ["for"] = "Lead", note = "" } },
}
local r1 = LR.Gargul.importInto(s3, pack(sheet))
check("first import: the sheet's reserves join Ann's own", r1.added == 4 and list(s3, "Ann-Dreamscythe") == "28529,28762" and list(s3, "Zed-Dreamscythe") == "28525,28528")
local r2 = LR.Gargul.importInto(s3, pack(sheet))
check("importing the same sheet again changes nothing", r2.added == 0 and r2.removed == 0 and list(s3, "Zed-Dreamscythe") == "28525,28528"
  and list(s3, "Ann-Dreamscythe") == "28529,28762")
sheet.softreserves[1].items = { { id = 28528 }, { id = 28767 } }               -- Zed swaps one
sheet.softreserves[2].items = { { id = 28529 } }                               -- Ann picks the one she reserved in LootRuler
table.remove(sheet.softreserves, 3)                                             -- Cara's gone from the sheet
sheet.hardreserves = {}                                                         -- and the hard reserve
S.setHR(s3, 30480, "", "", 1760000001)                                         -- (one set in LootRuler)
local r3 = LR.Gargul.importInto(s3, pack(sheet))
check("an updated sheet: Zed's swap comes through", list(s3, "Zed-Dreamscythe") == "28528,28767")
check("Ann's own reserve stays, and the same item on the sheet counts once", list(s3, "Ann-Dreamscythe") == "28529")
check("whoever left the sheet loses what it gave them", list(s3, "Cara-Dreamscythe") == "")
check("hard reserves the sheet dropped come off; ones set in LootRuler stay", s3.hr[28770] == nil and s3.hr[30480] ~= nil)
check("and it says what changed", r3.added == 1 and r3.removed == 3 and r3.hardRemoved == 1, ("%d %d %d"):format(r3.added, r3.removed, r3.hardRemoved))
check("it's still a valid session", S.valid(s3))
s3.sx = { ["Zed-Dreamscythe"] = "lots" }
check("but not with nonsense in it", not S.valid(s3))
local bad, err = LR.Gargul.importInto(s2, "this isn't an export")
check("rubbish is refused with a reason", bad == nil and type(err) == "string")

print("== names on the sheet spelled differently from the characters")
local G = LR.Gargul
local function group(...) local o = {} for _, n in ipairs({ ... }) do o[#o + 1] = { name = n } end return o end
local function names(sum, field) local o = {} for _, x in ipairs(sum[field]) do o[#o + 1] = U.short(x[1]) end table.sort(o) return table.concat(o, ",") end
do
  local sn = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 1760000000)
  local roster = group("Lead-Dreamscythe", "Ghøst-Dreamscythe", "Øyvind-Dreamscythe", "Bob-Faerlina")
  local page = { metadata = { id = "n1" }, hardreserves = {}, softreserves = {
    { name = "ghost", class = "mage", items = { { id = 28528 } } },             -- no accent, no capital
    { name = "øYVIND", class = "warrior", items = { { id = 28525 } } },         -- capitals all over
    { name = "Bob", class = "mage", items = { { id = 28529 } } },               -- another realm, typed without it
    { name = "Zed", class = "rogue", items = { { id = 28762 } } },              -- not in the group yet
    { name = "Ghots", class = "rogue", items = { { id = 28530 } } },            -- a typo: close to Ghøst
  } }
  local sum = G.importInto(sn, pack(page), roster)
  check("a name without its accent goes to the character", list(sn, "Ghøst-Dreamscythe") == "28528" and list(sn, "Ghost-Dreamscythe") == "")
  check("capitals don't matter, accented ones either", list(sn, "Øyvind-Dreamscythe") == "28525" and sn.res["Øyvind-Dreamscythe"].c == "WARRIOR")
  check("a name typed without its realm finds the player from another realm", list(sn, "Bob-Faerlina") == "28529" and list(sn, "Bob-Dreamscythe") == "")
  check("the summary says which names were matched", names(sum, "matched") == "Bob,Ghost", names(sum, "matched"))
  check("names nobody in the group has are kept as they are", list(sn, "Zed-Dreamscythe") == "28762" and list(sn, "Ghots-Dreamscythe") == "28530")
  local miss = {}
  for _, x in ipairs(sum.missing) do miss[x[1]] = x[2] end
  check("and listed, with close spellings", names(sum, "missing") == "Ghots,Zed" and miss["Ghots-Dreamscythe"][1] == "Ghøst-Dreamscythe"
    and #miss["Zed-Dreamscythe"] == 0)
  -- what goes to Gargul (and to older versions of LootRuler) is the game's spelling, so exact matching works there
  local out = G.decode(G.export(sn))
  local sent = {}
  for _, r in ipairs(out.softreserves) do sent[r.name] = true end
  check("Gargul gets the game's spelling", sent["Ghøst"] and sent["Øyvind"] and sent["Bob-Faerlina"] and not sent["Ghost"])
  -- the same sheet again: no new phantom players, nothing changes
  local again = G.importInto(sn, pack(page), roster)
  check("importing again goes to the same characters", again.added == 0 and again.removed == 0 and list(sn, "Ghøst-Dreamscythe") == "28528"
    and list(sn, "Ghost-Dreamscythe") == "")
  -- the typo, sorted out by the leader: a click moves it, and later imports remember
  local left = G.unmatched(sn, roster)
  check("the typo is listed for the leader, Zed (no close spelling) isn't", #left == 1 and left[1].from == "Ghots-Dreamscythe" and left[1].near[1] == "Ghøst-Dreamscythe")
  check("one character can't take a second name's picks while it has the first's", not G.rename(sn, "Ghots-Dreamscythe", "Ghøst-Dreamscythe"))
  check("but someone without any can", G.rename(sn, "Ghots-Dreamscythe", "Lead-Dreamscythe", "PALADIN") and list(sn, "Lead-Dreamscythe") == "28530"
    and list(sn, "Ghots-Dreamscythe") == "" and sn.res["Lead-Dreamscythe"].c == "PALADIN")
  local third = G.importInto(sn, pack(page), roster)
  check("and the next import remembers it", third.added == 0 and third.removed == 0 and list(sn, "Lead-Dreamscythe") == "28530" and list(sn, "Ghots-Dreamscythe") == "")
  check("the session with its matches is valid", S.valid(sn) and sn.nm["Ghost-Dreamscythe"] == "Ghøst-Dreamscythe")
  -- Zed joins as Zéd: his reserves follow him
  roster[#roster + 1] = { name = "Zéd-Dreamscythe" }
  local moved = G.recheck(sn, roster)
  check("someone joining with the accent gets the sheet's reserves", #moved == 1 and moved[1][2] == "Zéd-Dreamscythe" and list(sn, "Zéd-Dreamscythe") == "28762"
    and list(sn, "Zed-Dreamscythe") == "")
  check("once is enough", #G.recheck(sn, roster) == 0)
end

do
  -- two characters in the group whose names only differ by an accent: never a guess
  local sa = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 1760000000)
  local roster = group("Ghøst-Dreamscythe", "Ghöst-Dreamscythe")
  local sum = G.importInto(sa, pack({ softreserves = { { name = "Ghost", items = { { id = 28528 } } } } }), roster)
  check("a name that could be two characters stays as it is", list(sa, "Ghost-Dreamscythe") == "28528" and list(sa, "Ghøst-Dreamscythe") == "" and list(sa, "Ghöst-Dreamscythe") == "")
  check("and the leader is asked which", #sum.unsure == 1 and #sum.unsure[1][2] == 2)
  local left = G.unmatched(sa, roster)
  check("it stays on the list until the leader picks", #left == 1 and #left[1].options == 2)
  check("a later join doesn't guess either", #G.recheck(sa, roster) == 0)
  check("the leader's pick", G.rename(sa, "Ghost-Dreamscythe", "Ghöst-Dreamscythe") and list(sa, "Ghöst-Dreamscythe") == "28528" and #G.unmatched(sa, roster) == 0)
end

do
  -- the sheet has the name without its accent, and the player reserved in LootRuler too (a whisper, before joining)
  local sw = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 1760000000)
  S.add(sw, "Ghøst-Dreamscythe", "MAGE", 28528, false, 1760000000)
  local sum = G.importInto(sw, pack({ softreserves = { { name = "Ghost", items = { { id = 28528 }, { id = 28525 } } } } }), {})
  check("no double entry: the sheet's picks join the player's own", list(sw, "Ghøst-Dreamscythe") == "28525,28528" and list(sw, "Ghost-Dreamscythe") == ""
    and #sum.matched == 1)
  -- both spellings on one sheet: the exact one is theirs, the other is left for the leader
  local sb = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 1760000000)
  local both = G.importInto(sb, pack({ softreserves = { { name = "Ghost", items = { { id = 28528 } } }, { name = "Ghøst", items = { { id = 28525 } } } } }),
    group("Ghøst-Dreamscythe"))
  check("both spellings on a sheet: the exact one wins, the other isn't lost", list(sb, "Ghøst-Dreamscythe") == "28525" and list(sb, "Ghost-Dreamscythe") == "28528"
    and #both.unsure == 1)
  -- someone who was in the group as the sheet spells them keeps their reserves, whoever joins later
  local sk = S.new("Lead-Dreamscythe", "Karazhan", 2, true, 1760000000)
  G.importInto(sk, pack({ softreserves = { { name = "Ann", items = { { id = 28528 } } } } }), group("Ann-Dreamscythe"))
  check("a name that was in the group isn't moved to a lookalike", #G.recheck(sk, group("Ånn-Dreamscythe")) == 0 and list(sk, "Ann-Dreamscythe") == "28528")
end

print("== Gargul's rolls, read from raid chat")
do
  local link = "|cffa335ee|Hitem:28528::::::::70:::::|h[Moroes' Lucky Pocket Watch]|h|r"
  local id, l, secs = G.rollFromChat("You have 20 seconds to roll on " .. link)
  check("Gargul's line gives the item, its link and the seconds", id == 28528 and l == link and secs == 20)
  check("with anything in front of it", G.rollFromChat("{rt1} You have 15 seconds to roll on " .. link) == 28528)
  check("other raid chat isn't a roll", G.rollFromChat("Roll for " .. link) == nil and G.rollFromChat("You have 20 seconds to roll on it") == nil
    and G.rollFromChat(nil) == nil)
  local stop = G.rollEndFromChat("Stop your rolls!")
  local awarded, which = G.rollEndFromChat(link .. " was awarded to Ann. Congrats!")
  check("\"Stop your rolls!\" ends it", stop == true)
  check("so does the item going to someone", awarded == true and which == 28528)
  check("the countdown doesn't", G.rollEndFromChat("5 seconds to roll") == false)
  local r = G.startRoll(28528, link, nil, 100)
  check("a roll that doesn't say how long lasts a minute", G.roll == r and r.ends == 160 and r.state == "open")
  check("looting another item doesn't end it", not G.endRoll(28525) and G.roll == r)
  check("looting the item does", G.endRoll(28528) and G.roll == nil)
end

print(("passed %d"):format(passed))
print(("errors %d"):format(failed))
os.exit(failed == 0 and 0 or 1)
