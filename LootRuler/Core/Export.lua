-- Who won what, written out to copy somewhere else, and the same as lines for raid chat. Nothing here calls
-- the game except `date` (tested on its own in tests/rolls.lua).
--   csv    a spreadsheet: date, time, item, item id, player, how, roll, boss
--   tmb    thatsmybis.com's loot import (the same columns Gargul exports)
--   dftus  the DFT sheet's import, month/day dates
--   dfteu  the DFT sheet's import, day/month dates
--   own    the player's own layout: a line for each item from a template with {fields} (E.FIELDS), and a first line
-- Several raids (past raids, between two dates) go out as one list, oldest first.
local _, LR = ...
local U, S = LR.U, LR.Session

local E = {}
LR.Export = E

E.FORMATS = {
  { "csv", "Spreadsheet (CSV)" },
  { "tmb", "thatsmybis" },
  { "dftus", "DFT (US dates)" },
  { "dfteu", "DFT (EU dates)" },
  { "own", "Your own" },
}
E.MAX_TEMPLATE = 200

-- what a template can say, and what each is
E.FIELDS = {
  { "date", "2025-10-31" }, { "time", "21:05" }, { "item", "the item's name" }, { "id", "the item's number" },
  { "player", "who got it (Name, or Name-Realm from another realm)" }, { "name", "their name without the realm" },
  { "how", "MS, OS, SR, HR, disenchant, GDKP..." }, { "roll", "what they rolled, or the price" }, { "boss", "who dropped it" },
  { "raid", "the raid" }, { "leader", "who led it" },
}

-- items TMB knows by another id (the faction's own head is the same quest)
local TMB_ID = { [18423] = 18422, [19003] = 19002, [32386] = 32385 }

local function how(w)
  if w.de then return "disenchant" end
  if w.br then return "MS (boosted)" end
  if w.k == "BID" then return "GDKP" end
  if w.xn then return w.xn end
  return LR.Roll.LABEL[w.k] or tostring(w.k)
end

local function csvField(v)
  v = tostring(v == nil and "" or v)
  if v:find('[",\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
  return v
end

--- the loot given out in a session, oldest first: { w = won entry, boss, s = the session, n = its place }
function E.entries(s)
  local out = {}
  for i, w in ipairs(s.won or {}) do
    local d = w.d and S.drop(s, w.d)
    out[#out + 1] = { w = w, boss = d and d.b or (LR.dropsFrom(s.raid, w.i)[1] or ""), s = s, n = i }
  end
  return out
end

--- the loot given out in several sessions (or past raids) between two times (either may be nil), oldest first
function E.entriesOf(sessions, from, to)
  local out = {}
  for _, s in ipairs(sessions) do
    for _, e in ipairs(E.entries(s)) do
      local at = e.w.at or 0
      if (not from or at >= from) and (not to or at <= to) then out[#out + 1] = e end
    end
  end
  table.sort(out, function(a, b)
    if (a.w.at or 0) ~= (b.w.at or 0) then return (a.w.at or 0) < (b.w.at or 0) end
    if a.s.id ~= b.s.id then return a.s.id < b.s.id end
    return a.n < b.n
  end)
  return out
end

--- a template filled in for one item ({field} for each of E.FIELDS; anything else stays as it is)
function E.fill(template, e)
  local fmt = date or os.date
  local w = e.w
  local values = {
    date = fmt("%Y-%m-%d", w.at or 0), time = fmt("%H:%M", w.at or 0), item = LR.itemName(w.i), id = tostring(w.i),
    player = U.short(w.p), name = U.bare(w.p), how = how(w), roll = w.r and tostring(w.r) or "", boss = e.boss or "",
    raid = LR.raidOf(e.s).name, leader = U.short(e.s.leader),
  }
  return (tostring(template):sub(1, E.MAX_TEMPLATE):gsub("{(%a+)}", function(k) return values[k:lower()] end))
end

--- the session's loot given out, as text in a format (E.FORMATS). opts: { template, header } (the "own" format)
function E.text(s, format, opts)
  return E.write(E.entries(s), format, opts)
end

--- items (E.entries / E.entriesOf) as text in a format
function E.write(entries, format, opts)
  local lines = {}
  local fmt = date or os.date
  if format == "own" then
    opts = opts or {}
    local header = tostring(opts.header or ""):sub(1, E.MAX_TEMPLATE)
    if header ~= "" then lines[1] = header end
    for _, e in ipairs(entries) do lines[#lines + 1] = E.fill(opts.template or "{date};{player};{item};{how}", e) end
  elseif format == "tmb" then
    lines[1] = "dateTime,character,itemID,offspec,id"
    for _, e in ipairs(entries) do
      local w = e.w
      lines[#lines + 1] = ("%s,%s,%d,%d,%s"):format(fmt("%Y-%m-%d", w.at or 0), U.bare(w.p), TMB_ID[w.i] or w.i,
        (w.k == "OS" or w.de) and 1 or 0, csvField(e.s.id .. ":" .. e.n))
    end
  elseif format == "dftus" or format == "dfteu" then
    for _, e in ipairs(entries) do
      local w = e.w
      if not w.de then
        lines[#lines + 1] = ("%s;[%d];%s"):format(fmt(format == "dfteu" and "%d/%m/%Y" or "%m/%d/%Y", w.at or 0), w.i, w.p)
      end
    end
  else
    lines[1] = "Date,Time,Item,Item ID,Player,How,Roll,Boss"
    for _, e in ipairs(entries) do
      local w = e.w
      lines[#lines + 1] = table.concat({ fmt("%Y-%m-%d", w.at or 0), fmt("%H:%M", w.at or 0), csvField(LR.itemName(w.i)), w.i,
        csvField(U.short(w.p)), how(w), w.r or "", csvField(e.boss) }, ",")
    end
  end
  return table.concat(lines, "\n")
end

--- who won what, as raid chat lines (item links are long: several lines, none over 255 characters)
function E.chat(s)
  local parts = {}
  for _, e in ipairs(E.entries(s)) do
    local w = e.w
    parts[#parts + 1] = ("%s %s%s"):format(LR.itemLink(w.i), U.short(w.p), w.de and " (disenchant)" or (w.k == "BID" and LR.Gdkp) and (" (" .. LR.Gdkp.gold(w.r) .. ")") or "")
  end
  if #parts == 0 then return {} end
  return U.chatLines(LR.TAG .. " Loot given out: " .. table.concat(parts, ", "), 255)
end
