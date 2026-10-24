-- Gargul. Gargul imports soft reserves as the string softres.it's "Gargul Export" button makes: JSON with
-- every player's reserves and the hard reserves, zlib-compressed and base64-encoded. LootRuler writes the
-- same string, so it can go into Gargul's own importer by hand, or straight in with one click through the
-- hook Gargul opens for other addons (Gargul.SoftRes:import). LootRuler also reads that string, to bring
-- reserves made on softres.it into a session.
local _, LR = ...
local U, S = LR.U, LR.Session
local LibDeflate = LibStub("LibDeflate")

local G = {}
LR.Gargul = G

local CLASS_NAME = { WARRIOR = "warrior", PALADIN = "paladin", HUNTER = "hunter", ROGUE = "rogue", PRIEST = "priest",
  SHAMAN = "shaman", MAGE = "mage", WARLOCK = "warlock", DRUID = "druid" }

--- the Gargul import data for a session (a table; G.export turns it into the string)
function G.data(s, plusOnesOf)
  local soft = U.array({})
  for _, p in ipairs(S.players(s)) do
    local class = p.class or LR.classOf(p.name)
    local items = U.array({})
    for _, id in ipairs(p.items) do items[#items + 1] = { id = id } end
    local name = U.short(p.name)
    soft[#soft + 1] = {
      name = name,
      class = CLASS_NAME[class or ""] or "",
      items = items,
      note = "",
      plusOnes = plusOnesOf and plusOnesOf(name) or 0,
    }
  end
  local hard = U.array({})
  for _, id in ipairs(U.keys(s.hr)) do
    local h = s.hr[id]
    hard[#hard + 1] = { id = id, ["for"] = h.f ~= "" and U.short(U.full(h.f)) or "", note = h.n or "" }
  end
  return {
    softreserves = soft,
    hardreserves = hard,
    metadata = {
      id = "LootRuler-" .. s.id:gsub("[^%w]", ""),
      createdAt = s.created,
      updatedAt = s.updated,
      raidStartsAt = 0,
      hidden = false,
      discordUrl = "",
      url = "https://github.com/kcham01/LootRuler",
      instance = LR.raidOf(s).name,
    },
  }
end

function G.encode(data) return U.b64encode(LibDeflate:CompressZlib(U.toJSON(data))) end

--- the string for Gargul's soft-reserve importer
function G.export(s) return G.encode(G.data(s, G.plusOnes())) end

--- reads a Gargul / softres.it string; returns the data, or nil and what's wrong with it
function G.decode(text)
  local raw = U.b64decode(U.trim(text or ""))
  if not raw or raw == "" then return nil, "That isn't a Gargul or softres.it export (it isn't base64)." end
  local json = LibDeflate:DecompressZlib(raw)
  if not json then return nil, "That isn't a Gargul or softres.it export (it doesn't unpack)." end
  local data, err = U.fromJSON(json)
  if type(data) ~= "table" or type(data.softreserves) ~= "table" then return nil, "That export has no soft reserves in it" .. (err and (" (" .. err .. ")") or "") .. "." end
  return data
end

---------------------------------------------------------------------- Gargul itself
local function gargul() return type(_G.Gargul) == "table" and _G.Gargul or nil end

--- Gargul's own +1s or boosted roll points, as its export writes them ("Name,Number" lines), when Gargul is
--- loaded and has some: kind "plusOnes" or "boosted"
function G.counts(kind)
  local g = gargul()
  local obj = g and (kind == "plusOnes" and g.PlusOnes or g.BoostedRolls)
  if type(obj) ~= "table" or type(obj.export) ~= "function" then return nil end
  local ok, csv = pcall(obj.export, obj, false)
  if ok and type(csv) == "string" and csv:find("%S") then return csv end
end

function G.available()
  local g = gargul()
  return g and type(g.SoftRes) == "table" and type(g.SoftRes.import) == "function" or false
end

--- Gargul's plus-one values, so importing doesn't ask to overwrite them
function G.plusOnes()
  local g = gargul()
  if not g or type(g.PlusOnes) ~= "table" or type(g.PlusOnes.getPlusOnes) ~= "function" then return nil end
  return function(name)
    local ok, v = pcall(g.PlusOnes.getPlusOnes, g.PlusOnes, name)
    return ok and tonumber(v) or 0
  end
end

--- hands the session to Gargul. show: open Gargul's soft-reserve overview (and let Gargul share it with
--- the raid, as its own importer does). Returns true when Gargul took it.
function G.send(s, show)
  if not G.available() then return false, "Gargul isn't loaded." end
  local g = gargul()
  local ok, res = pcall(g.SoftRes.import, g.SoftRes, G.export(s), show and true or false)
  if not ok then
    geterrorhandler()(res)
    return false, "Gargul ran into an error importing the reserves."
  end
  if res == false then return false, "Gargul didn't accept the reserves." end
  s.sentToGargul = s.rev
  return true
end

---------------------------------------------------------------------- softres.it into a session
--- adds the reserves (and hard reserves) from a softres.it / Gargul export to a session the leader holds.
--- Items the session doesn't allow (not its raid's loot, unless any item is allowed) are skipped. Returns a summary.
function G.importInto(s, text)
  local data, err = G.decode(text)
  if not data then return nil, err end
  local sum = { players = 0, items = 0, hard = 0, skipped = 0, over = 0 }
  local classes = {}
  for token, name in pairs(CLASS_NAME) do classes[name] = token end
  for _, h in ipairs(data.hardreserves or {}) do
    local id = tonumber(h.id)
    if id and LR.allowedItem(s, id) then
      S.setHR(s, id, h["for"] or "", h.note or "", U.now())
      sum.hard = sum.hard + 1
    elseif id then sum.skipped = sum.skipped + 1 end
  end
  for _, e in ipairs(data.softreserves) do
    local name = type(e.name) == "string" and U.trim(e.name) or ""
    if name ~= "" then
      name = name:sub(1, 1):upper() .. name:sub(2)
      local player = U.full(name)
      local class = classes[U.lower(e.class)]
      local added = false
      for _, it in ipairs(type(e.items) == "table" and e.items or {}) do
        local id = tonumber(type(it) == "table" and it.id or it)
        if id and LR.allowedItem(s, id) then
          local ok, why = S.add(s, player, class, id, true, U.now())
          if ok then sum.items = sum.items + 1 added = true
          elseif why == "TOO_MANY" or why == "DUPLICATE" then sum.over = sum.over + 1
          else sum.skipped = sum.skipped + 1 end
        elseif id then sum.skipped = sum.skipped + 1 end
      end
      if added then sum.players = sum.players + 1 end
    end
  end
  LR.leaderChanged(s)
  return sum
end
