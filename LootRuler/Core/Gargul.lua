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
local wasHere = {}           -- names seen in the group as they are: a later join never moves their reserves

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

--- the characters a name on the sheet could be: everyone in the group, and players who reserved in LootRuler
--- themselves (the game named them, so they're real). A name only the sheet brought could be the typo itself.
function G.people(s, roster)
  local out, seen = {}, {}
  local function add(name)
    name = U.full(name)
    if name and not seen[U.foldCase(name)] then seen[U.foldCase(name)] = true out[#out + 1] = name end
  end
  for _, m in ipairs(roster or {}) do add(m.name) end
  for name, r in pairs(s.res) do
    if #r.i > #(s.sx and s.sx[name] or {}) then add(name) end
  end
  table.sort(out)
  return out
end

--- which character a name typed on softres.it is, among people (G.people):
---   { to = name }      the same name (capitals aside), or the only one it can be once accents are put aside
---                      (and the realm, for a name typed without one)
---   { options = names } several could be: the leader picks, nothing is guessed
---   { near = names }    none: the closest spellings, if any are close
function G.findPlayer(typed, people)
  local full = U.full(typed)
  for _, p in ipairs(people) do if U.samePlayer(p, full) then return { to = p } end end
  -- typed without a realm (it reads as this realm's): characters from other realms with that name count too
  local realmless = U.short(full) == U.bare(full)
  local function key(name) return U.nameKey(realmless and U.bare(name) or name) end
  local want = key(full)
  local same, near = {}, {}
  local most = #U.letters(want) >= 5 and 2 or 1
  for _, p in ipairs(people) do
    local k = key(p)
    if k == want then same[#same + 1] = p
    else
      local d = U.distance(k, want)
      if d <= most then near[#near + 1] = { p, d } end
    end
  end
  if #same == 1 then return { to = same[1] } end
  if #same > 1 then return { options = same } end
  table.sort(near, function(a, b) if a[2] ~= b[2] then return a[2] < b[2] end return a[1] < b[1] end)
  local out = {}
  for i = 1, math.min(3, #near) do out[i] = near[i][1] end
  return { near = out }
end

--- moves what the sheet gave a name over to the character it really is (the leader's pick, or the only one it
--- can be), so the reserves count for them. What they reserved in LootRuler stays, and an item reserved in both
--- places counts once. Later imports bring that name's picks to them too (s.nm). Returns true, or false and why not.
function G.rename(s, from, to, class, now)
  from, to = U.full(from), U.full(to)
  if not from or not to or U.samePlayer(from, to) then return false, "That's the same name." end
  if s.sx and s.sx[to] then return false, ("%s already has reserves from the sheet."):format(U.short(to)) end
  now = now or U.now()
  local sheet = s.sx and s.sx[from] or {}
  local own = U.copy(S.reservesOf(s, from))
  takeOff(own, sheet)                            -- (anything the leader added for the name by hand)
  local mine = U.copy(S.reservesOf(s, to))
  local limit = S.limit(s, to)
  local function fits(id) return #mine < limit and (s.dupes or not U.indexOf(mine, id)) end
  for _, id in ipairs(own) do if fits(id) then mine[#mine + 1] = id end end
  local have, count, moved = {}, {}, {}
  for _, id in ipairs(mine) do have[id] = (have[id] or 0) + 1 end
  for _, id in ipairs(sheet) do
    count[id] = (count[id] or 0) + 1
    if count[id] > (have[id] or 0) and fits(id) then mine[#mine + 1] = id moved[#moved + 1] = id end
  end
  local oldClass = s.res[from] and s.res[from].c
  S.set(s, from, nil, {}, true, now)
  S.set(s, to, (s.res[to] and s.res[to].c) or class or oldClass, mine, true, now)
  if s.sx then
    s.sx[from] = nil
    s.sx[to] = #moved > 0 and moved or nil
    if not next(s.sx) then s.sx = nil end
  end
  s.nm = type(s.nm) == "table" and s.nm or {}
  for k, v in pairs(s.nm) do if v == from then s.nm[k] = to end end
  s.nm[from] = to
  if s.xr and s.xr[from] then
    s.xr[to] = s.xr[to] or s.xr[from]
    s.xr[from] = nil
  end
  S.bump(s, now)
  LR.leaderChanged(s)
  return true
end

--- names from the sheet that aren't anyone in the group, each with who it could be (G.findPlayer): for the
--- leader to sort out. Names nobody is close to are left out (they may not have joined yet) unless all.
function G.unmatched(s, roster, all)
  local out = {}
  if not s.sx then return out end
  local here, people = {}, G.people(s, roster)
  for _, m in ipairs(roster or {}) do here[U.foldCase(U.full(m.name))] = true end
  for name in pairs(s.sx) do
    if not here[U.foldCase(name)] then
      local m = G.findPlayer(name, U.filter(people, function(p) return not U.samePlayer(p, name) end))
      if m.options or (m.near and (#m.near > 0 or all)) then out[#out + 1] = { from = name, options = m.options, near = m.near } end
    end
  end
  table.sort(out, function(a, b) return a.from < b.from end)
  return out
end

--- someone joined (or reserved): a name from the sheet that is now clearly one of them moves to them. Names
--- seen in the group as they are stay put. Returns the moves: { { from, to } }
function G.recheck(s, roster)
  local moved = {}
  if not s.sx then return moved end
  for _, m in ipairs(roster or {}) do wasHere[U.foldCase(U.full(m.name))] = true end
  local people = G.people(s, roster)
  local names = U.keys(s.sx)
  for _, name in ipairs(names) do
    if not wasHere[U.foldCase(name)] then
      local m = G.findPlayer(name, U.filter(people, function(p) return not U.samePlayer(p, name) end))
      if m.to and not (s.sx and s.sx[m.to]) then
        local class
        for _, r in ipairs(roster or {}) do if U.samePlayer(r.name, m.to) then class = r.class end end
        if G.rename(s, name, m.to, class) then moved[#moved + 1] = { name, m.to } end
      end
    end
  end
  return moved
end

--- adds the reserves (and hard reserves) from a softres.it / Gargul export to a session the leader holds.
--- Items the session doesn't allow (not its raid's loot, unless any item is allowed) are skipped. Returns a summary.
--- brings a softres.it export into a session. Importing again (the sheet changed) updates the session: the
--- reserves the last import brought are replaced by the sheet's picks now, and anything gone from the sheet
--- comes off. Reserves made in LootRuler (the addon, or !lr) are never touched, and an item a player reserved
--- in both places counts once (twice only if the sheet itself has it twice). Hard reserves from the sheet
--- work the same way. s.sx: "Name-Realm" -> the items the sheet gave them; s.hx: the sheet's hard reserves.
--- Names on the sheet are matched to the characters in the group (roster: LR.roster()) and to players who
--- reserved in LootRuler, and the reserves go under the game's spelling of the name, so nothing else has to
--- match loosely (older versions included). A name that clearly is one character (capitals and accents aside,
--- "Ghost" for "Ghøst") goes to them; one that could be several is left for the leader to pick (never a guess);
--- one that's nobody's is kept as it is, with the closest spellings. s.nm remembers each match for next time.
--- Returns a summary { players, items (from the sheet now), added, removed, hard, hardRemoved, skipped, over,
--- matched = { { from, to } }, unsure = { { from, options } }, missing = { { from, near } } }, or nil and what's wrong.
function G.importInto(s, text, roster)
  local data, err = G.decode(text)
  if not data then return nil, err end
  local now = U.now()
  local sum = { players = 0, items = 0, added = 0, removed = 0, hard = 0, hardRemoved = 0, skipped = 0, over = 0,
    matched = {}, unsure = {}, missing = {} }
  roster = roster or (LR.roster and LR.roster()) or {}
  for _, m in ipairs(roster) do wasHere[U.foldCase(U.full(m.name))] = true end
  local people = G.people(s, roster)
  s.nm = type(s.nm) == "table" and s.nm or {}
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

  -- who each name on the sheet is. A name that is someone exactly comes first, then matches made before (an
  -- earlier import, or the leader's pick), then names that can only be one character; one character never
  -- takes two names' picks (the second is left for the leader to sort out).
  local list, claimed = {}, {}
  for _, e in ipairs(data.softreserves) do
    local name = type(e.name) == "string" and U.trim(e.name) or ""
    if name ~= "" then
      local typed = U.full(U.capitalize(name))
      list[#list + 1] = { e = e, typed = typed, m = G.findPlayer(typed, people) }
    end
  end
  local function claim(x, to)
    if claimed[U.foldCase(to)] then return false end
    claimed[U.foldCase(to)] = true
    x.player = to
    return true
  end
  for _, x in ipairs(list) do if x.m.to and U.samePlayer(x.typed, x.m.to) then claim(x, x.m.to) end end
  for _, x in ipairs(list) do if not x.player and s.nm[x.typed] then claim(x, s.nm[x.typed]) end end
  for _, x in ipairs(list) do
    local m = x.m
    if not x.player then
      if m.to and claim(x, m.to) then
        s.nm[x.typed] = m.to
        sum.matched[#sum.matched + 1] = { x.typed, m.to }
      elseif m.to and not U.samePlayer(x.typed, m.to) then sum.unsure[#sum.unsure + 1] = { x.typed, { m.to } }
      elseif m.options then sum.unsure[#sum.unsure + 1] = { x.typed, m.options }
      elseif not m.to then sum.missing[#sum.missing + 1] = { x.typed, m.near } end
      x.player = x.player or x.typed
    end
  end

  local seen = {}
  for _, x in ipairs(list) do
    local e, player = x.e, x.player
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
  if not next(s.nm) then s.nm = nil end
  LR.leaderChanged(s)
  return sum
end

---------------------------------------------------------------------- Gargul's rolls, read from raid chat
-- When Gargul rolls an item out, it says so in raid chat. LootRuler reads that line with its own pattern (nothing of
-- Gargul's is used) so raiders see who reserved the item (UI/ReserveStrip.lua). The roll is over when someone
-- loots the item, another roll starts, or its time is up.
-- Gargul's lines (English): "You have 20 seconds to roll on [item]" starts a roll; "Stop your rolls!" or
-- "[item] was awarded to Ann. Congrats!" ends it. Each start pattern captures { seconds, link } in the order named.
local LINK = "(|c%x+|Hitem:.-|h|r)"
G.ROLL_LINES = { { "You have (%d+) seconds to roll on " .. LINK, "secs", "link" } }
G.END_LINES = { "^Stop your rolls!", LINK .. " was awarded to .+%. Congrats!" }

--- a raid chat line: the item, its link and the seconds when it's Gargul starting a roll, else nil
function G.rollFromChat(text)
  text = tostring(text or "")
  for _, line in ipairs(G.ROLL_LINES) do
    local a, b = text:match(line[1])
    if a then
      local got = { [line[2]] = a, [line[3]] = b }
      local id = got.link and tonumber(got.link:match("item:(%d+)"))
      if id then return id, got.link, tonumber(got.secs) end
    end
  end
end
--- a raid chat line that ends Gargul's roll: true, and the item when the line names one
function G.rollEndFromChat(text)
  text = tostring(text or "")
  for _, pattern in ipairs(G.END_LINES) do
    local s, e, link = text:find(pattern)
    if s then return true, link and tonumber(link:match("item:(%d+)")) end
  end
  return false
end

G.DEFAULT_SECONDS = 60      -- (when the line doesn't say how long)
--- Gargul's roll that's on now: { id, link, mode = "GARGUL", state = "open", ends }, or nil
G.roll = nil
function G.startRoll(id, link, secs, now)
  G.roll = { id = id, link = link, mode = "GARGUL", state = "open", ends = now + (secs or G.DEFAULT_SECONDS) }
  if LR.changed then LR.changed("gargul") end
  return G.roll
end
--- the roll is over (any roll, or only the one for item id)
function G.endRoll(id)
  if not G.roll or (id and G.roll.id ~= id) then return false end
  G.roll = nil
  if LR.changed then LR.changed("gargul") end
  return true
end
