-- Priority lists in and out: reading the lists other tools make, and writing ours for them. Nothing here
-- calls the game (tested on its own in tests/rolls.lua); the lists live in the guild book (Core/Book.lua).
--
-- Reads (Prio.parse, whichever it is):
--   Gargul's CSV        one line per item: "28525,ann,bob,cara" (in order), "28525,ann[1],bob[2],cara[2]"
--                       (numbered), or "28525,ann,bob|cara" (bob and cara equal second)
--   DFT                 the DFT sheet's Gargul export: items separated by ";", each "id^..." then a line per
--                       player with their priority ("Free Roll" items are left out)
--   thatsmybis          the Gargul download: JSON {"wishlists":{"id":["name|order|type|group",...]}}, or the
--                       same zlib-compressed and base64-encoded. Its priorities (type 1) are used; when it
--                       has none, its wishlists.
-- Writes (Prio.export): Gargul's CSV (Gargul and LootRuler read it back), or a spreadsheet.
local _, LR = ...
local U = LR.U

local P = {}
LR.Prio = P

P.FORMATS = { { "gargul", "Gargul / LootRuler" }, { "sheet", "Spreadsheet" } }
P.MAX_ITEMS = 1000
P.MAX_PER_ITEM = 100

local function name(text)
  text = U.trim(tostring(text or "")):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  text = U.trim(text)
  if text == "" or #text > 40 or text:find("[%s,;%[%]|:]") then return nil end
  -- "ann" -> "Ann"; a realm stays as it is
  return (text:gsub("^%l", string.upper))
end

local function add(out, id, player, n, note)
  id = tonumber(id)
  n = tonumber(n)
  player = name(player)
  if not id or id <= 0 or id % 1 ~= 0 or not player or not n or n <= 0 then return end
  out[id] = out[id] or {}
  if #out[id] < P.MAX_PER_ITEM then out[id][#out[id] + 1] = { p = player, n = math.floor(n), note = note } end
end

local function count(lists)
  local items, people = 0, 0
  for _, list in pairs(lists) do items = items + 1 people = people + #list end
  return items, people
end
P.count = count

--- Gargul's CSV
local function csv(text)
  local out = {}
  for line in text:gmatch("[^\r\n]+") do
    line = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local id, rest = line:match("^%s*(%d+)%s*,(.*)$")
    if id then
      local n = 1
      for part in (rest .. ","):gmatch("([^,]*),") do
        part = U.trim(part)
        local who, num = part:match("^(.-)%s*%[([%d%.]+)%]$")
        if who then
          add(out, id, who, num)
          n = math.floor(tonumber(num) or n) + 1
        elseif part ~= "" then
          for one in part:gmatch("[^|]+") do add(out, id, one, n) end
          n = n + 1
        end
      end
    end
  end
  return out
end

--- the DFT sheet's export
local function dft(text)
  local out = {}
  text = text:gsub('"', "")
  for entry in text:gmatch("[^;]+") do
    local id
    for line in entry:gmatch("[^\r\n]+") do
      if not id then
        id = tonumber(line:match("^%s*(%d+)"))
        if not id then break end
      else
        if line:find("Free Roll", 1, true) then break end
        local plain = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local who, n = plain:match("^%s*%d*%s*([^%s:|]+)[%s:|]+([%d%.]+)")
        if who then add(out, id, who, n) end
      end
    end
  end
  return out
end

--- thatsmybis (JSON, or compressed)
local function tmb(text, inflate)
  local json = text
  if not text:find("^%s*{") then
    local raw = U.b64decode(U.trim(text))
    json = raw and raw ~= "" and inflate and inflate(raw)
    if not json then return nil end
  end
  local data = U.fromJSON(json)
  if type(data) ~= "table" or type(data.wishlists) ~= "table" then return nil end
  local prio, wish = {}, {}
  for id, entries in pairs(data.wishlists) do
    if type(entries) == "table" then
      for _, e in ipairs(entries) do
        if type(e) == "string" then
          local parts = {}
          for x in (e .. "|"):gmatch("([^|]*)|") do parts[#parts + 1] = x end
          -- the old format has more parts: name, -, order, -, type
          local old = #parts > 4
          local who, order, kind = parts[1], parts[old and 3 or 2], tonumber(parts[old and 5 or 3])
          add(kind == 1 and prio or wish, id, who, order)
        end
      end
    end
  end
  if next(prio) then return prio end
  return wish
end

--- reads priority lists in any format this knows: returns { [item id] = { { p, n, note }, ... } } and the
--- format's name, or nil and what's wrong. inflate(raw): zlib-decompresses (LibDeflate's DecompressZlib).
function P.parse(text, inflate)
  text = U.trim(tostring(text or ""))
  if text == "" then return nil, "Paste the lists into the box first." end
  local first = text:match("[^\r\n]+") or ""
  local lists, kind
  if first:match("^%d+%s*,") then lists, kind = csv(text), "Gargul's CSV"
  elseif first:match('^"?%s*%d+%^') then lists, kind = dft(text), "DFT"
  else lists, kind = tmb(text, inflate), "thatsmybis" end
  if not lists then return nil, "That isn't a priority list LootRuler knows (Gargul's CSV, DFT, or thatsmybis's Gargul download)." end
  local items = count(lists)
  if items == 0 then return nil, ("That %s has no priorities in it."):format(kind == "thatsmybis" and "thatsmybis download" or kind) end
  if items > P.MAX_ITEMS then return nil, ("That's more than %d items."):format(P.MAX_ITEMS) end
  return lists, kind
end

--- puts imported lists in a book: each item's list is replaced. replaceAll: items that aren't in the import
--- lose their lists too. Returns the change to share.
function P.apply(book, lists, now, replaceAll)
  local change = { prio = {} }
  if replaceAll then
    for id, e in pairs(book.prio) do
      if not lists[id] and #e.list > 0 then
        book.prio[id] = { list = {}, t = LR.Book.stamp(e, now) }
        change.prio[id] = book.prio[id]
      end
    end
  end
  for id, list in pairs(lists) do
    local c = LR.Book.setPrio(book, id, list, now)
    change.prio[id] = c.prio[id]
  end
  return change
end

--- the book's lists as text: "gargul" (Gargul's CSV) or "sheet" (Item ID, Item, Player, Priority, Note)
function P.export(book, format, itemName)
  local ids = {}
  for id, e in pairs(book.prio) do if #e.list > 0 then ids[#ids + 1] = id end end
  table.sort(ids)
  local lines = {}
  if format == "sheet" then
    lines[1] = "Item ID,Item,Player,Priority,Note"
    local function field(v)
      v = tostring(v == nil and "" or v)
      if v:find('[",\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
      return v
    end
    for _, id in ipairs(ids) do
      for _, x in ipairs(LR.Book.prio(book, id)) do
        lines[#lines + 1] = table.concat({ id, field(itemName and itemName(id) or ""), field(U.bare(x.p)), x.n, field(x.note or "") }, ",")
      end
    end
  else
    for _, id in ipairs(ids) do
      local parts = { tostring(id) }
      for _, x in ipairs(LR.Book.prio(book, id)) do parts[#parts + 1] = ("%s[%d]"):format(U.bare(x.p), x.n) end
      lines[#lines + 1] = table.concat(parts, ",")
    end
  end
  return table.concat(lines, "\n")
end

---------------------------------------------------------------------- Gargul's +1s and boosted roll points
--- reads "Name,Number" lines (Gargul's +1 and boosted roll exports; also tabs or spaces, from a spreadsheet).
--- Names after the number are the player's alts, as in Gargul's boosted roll export ("Ann,40,Annalt").
--- Returns { { p = "Name", n, alts = { names } }, ... }, or nil and why
function P.parseCounts(text, max)
  local out, seen = {}, {}
  for line in tostring(text or ""):gsub('"', ""):gmatch("[^\r\n]+") do
    local who, n = line:match("^%s*([^,;\t%s]+)[,;\t%s]+([%d%.]+)")
    who, n = name(who), tonumber(n)
    if who and n and n >= 0 and n <= (max or 100000) and not seen[who:lower()] and #out < 2000 then
      seen[who:lower()] = true
      local alts = {}
      local rest = line:match("^%s*[^,;\t%s]+[,;\t%s]+[%d%.]+(.*)$") or ""
      for a in rest:gmatch("[^,;\t%s]+") do
        a = name(a)
        if a and not seen[a:lower()] and #alts < 20 then seen[a:lower()] = true alts[#alts + 1] = a end
      end
      out[#out + 1] = { p = who, n = math.floor(n), alts = alts }
    end
  end
  if #out == 0 then return nil, "Nothing in that is a name and a number on a line (\"Ann,3\")." end
  return out
end

--- "Name,Number" lines, for Gargul's importers (or a spreadsheet)
function P.countsText(list)
  local lines = {}
  table.sort(list, function(a, b) return a.p < b.p end)
  for _, x in ipairs(list) do
    local alts = U.map(x.alts or {}, function(a) return "," .. U.bare(a) end)
    lines[#lines + 1] = ("%s,%d%s"):format(U.bare(x.p), x.n, table.concat(alts))
  end
  return table.concat(lines, "\n")
end

--- "1st", "2nd", "3rd", "4th"...
function P.place(n)
  local last2 = n % 100
  local suffix = (last2 >= 11 and last2 <= 13) and "th" or ({ "st", "nd", "rd" })[n % 10] or "th"
  return n .. suffix
end
