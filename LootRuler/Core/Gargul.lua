-- Gargul. Gargul imports soft reserves as the string softres.it's "Gargul Export" button makes: JSON with
-- every player's reserves and the hard reserves, zlib-compressed and base64-encoded. LootRuler writes the
-- same string, so it can go into Gargul's own importer by hand, or straight in with one click through the
-- hook Gargul opens for other addons (Gargul.SoftRes:import). LootRuler also reads that string, to bring
-- reserves made on softres.it into a session.
--
-- None of Gargul's code is in LootRuler (Gargul's licence reserves all rights). LootRuler only writes and reads
-- the layout softres.it publishes, and calls Gargul's own functions when a player has both addons, the way any
-- addon works alongside another.
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
--- brings a softres.it export into a session. Importing again (the sheet changed) updates the session: the
--- reserves the last import brought are replaced by the sheet's picks now, and anything gone from the sheet
--- comes off. Reserves made in LootRuler (the addon, or !lr) are never touched, and an item a player reserved
--- in both places counts once (twice only if the sheet itself has it twice). Hard reserves from the sheet
--- work the same way. s.sx: "Name-Realm" -> the items the sheet gave them; s.hx: the sheet's hard reserves.
--- Returns a summary { players, items (from the sheet now), added, removed, hard, hardRemoved, skipped, over },
--- or nil and what's wrong.
function G.importInto(s, text)
  local data, err = G.decode(text)
  if not data then return nil, err end
  local now = U.now()
  local sum = { players = 0, items = 0, added = 0, removed = 0, hard = 0, hardRemoved = 0, skipped = 0, over = 0 }
  local classes = {}
  for token, name in pairs(CLASS_NAME) do classes[name] = token end
  s.sx = type(s.sx) == "table" and s.sx or {}

  -- hard reserves: the sheet's now; the ones an earlier import brought and the sheet dropped come off
  local sheetHR, order = {}, {}
  for _, h in ipairs(data.hardreserves or {}) do
    local id = tonumber(h.id)
    if id and LR.allowedItem(s, id) then
      if not sheetHR[id] then order[#order + 1] = id end
      sheetHR[id] = h
    elseif id then sum.skipped = sum.skipped + 1 end
  end
  for _, id in ipairs(type(s.hx) == "table" and s.hx or {}) do
    if not sheetHR[id] and s.hr[id] and S.clearHR(s, id, now) then sum.hardRemoved = sum.hardRemoved + 1 end
  end
  for _, id in ipairs(order) do
    local h, cur = sheetHR[id], s.hr[id]
    local f, n = U.trim(type(h["for"]) == "string" and h["for"] or ""), U.trim(type(h.note) == "string" and h.note or "")
    if not cur or cur.f ~= f or cur.n ~= n then S.setHR(s, id, f, n, now) end
    sum.hard = sum.hard + 1
  end
  s.hx = #order > 0 and order or nil

  -- a multiset difference: how many of a's ids aren't matched in b
  local function missing(a, b)
    local left = {}
    for _, id in ipairs(b) do left[id] = (left[id] or 0) + 1 end
    local n = 0
    for _, id in ipairs(a) do if (left[id] or 0) > 0 then left[id] = left[id] - 1 else n = n + 1 end end
    return n
  end
  -- takes one of each of ids off a list
  local function takeOff(list, ids)
    for _, id in ipairs(ids) do
      for k = #list, 1, -1 do if list[k] == id then table.remove(list, k) break end end
    end
  end

  local seen = {}
  for _, e in ipairs(data.softreserves) do
    local name = type(e.name) == "string" and U.trim(e.name) or ""
    if name ~= "" then
      name = name:sub(1, 1):upper() .. name:sub(2)
      local player = U.full(name)
      seen[player] = true
      local class = classes[U.lower(e.class)] or (s.res[player] and s.res[player].c)
      local before = s.sx[player] or {}
      local mine = U.copy(S.reservesOf(s, player))
      takeOff(mine, before)                          -- what the last import brought
      local own = {}                                 -- what they reserved in LootRuler
      for _, id in ipairs(mine) do own[id] = (own[id] or 0) + 1 end
      local fromSheet, count = {}, {}
      for _, it in ipairs(type(e.items) == "table" and e.items or {}) do
        local id = tonumber(type(it) == "table" and it.id or it)
        if not id or not LR.allowedItem(s, id) or s.hr[id] then
          if id then sum.skipped = sum.skipped + 1 end
        else
          count[id] = (count[id] or 0) + 1
          if count[id] <= (own[id] or 0) then
            -- (reserved in LootRuler too: it counts once)
          elseif #mine >= S.limit(s, player) or (not s.dupes and U.indexOf(mine, id)) then
            sum.over = sum.over + 1
          else
            mine[#mine + 1] = id
            fromSheet[#fromSheet + 1] = id
          end
        end
      end
      if S.set(s, player, class, mine, true, now) then
        sum.added = sum.added + missing(fromSheet, before)
        sum.removed = sum.removed + missing(before, fromSheet)
        s.sx[player] = #fromSheet > 0 and fromSheet or nil
        sum.items = sum.items + #fromSheet
        if #fromSheet > 0 then sum.players = sum.players + 1 end
      end
    end
  end
  -- players who aren't on the sheet any more: what it gave them comes off
  for player, ids in pairs(s.sx) do
    if not seen[player] then
      local mine = U.copy(S.reservesOf(s, player))
      takeOff(mine, ids)
      if S.set(s, player, s.res[player] and s.res[player].c, mine, true, now) then sum.removed = sum.removed + #ids end
      s.sx[player] = nil
    end
  end
  if not next(s.sx) then s.sx = nil end
  LR.leaderChanged(s)
  return sum
end
