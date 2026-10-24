-- Who won what, written out to copy somewhere else, and the same as lines for raid chat. Nothing here calls
-- the game except `date` (tested on its own in tests/rolls.lua).
--   csv    a spreadsheet: date, time, item, item id, player, how, roll, boss
--   tmb    thatsmybis.com's loot import (the same columns Gargul exports)
--   dftus  the DFT sheet's import, month/day dates
--   dfteu  the DFT sheet's import, day/month dates
local _, LR = ...
local U, S = LR.U, LR.Session

local E = {}
LR.Export = E

E.FORMATS = {
  { "csv", "Spreadsheet (CSV)" },
  { "tmb", "thatsmybis" },
  { "dftus", "DFT (US dates)" },
  { "dfteu", "DFT (EU dates)" },
}

-- items TMB knows by another id (the faction's own head is the same quest)
local TMB_ID = { [18423] = 18422, [19003] = 19002, [32386] = 32385 }

local function how(w)
  if w.de then return "disenchant" end
  return LR.Roll.LABEL[w.k] or tostring(w.k)
end

local function csvField(v)
  v = tostring(v == nil and "" or v)
  if v:find('[",\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
  return v
end

--- the loot given out in a session, oldest first: { won entry, boss }
function E.entries(s)
  local out = {}
  for _, w in ipairs(s.won or {}) do
    local d = w.d and S.drop(s, w.d)
    out[#out + 1] = { w = w, boss = d and d.b or (LR.dropsFrom(s.raid, w.i)[1] or "") }
  end
  return out
end

--- the session's loot given out, as text in a format (E.FORMATS)
function E.text(s, format)
  local lines = {}
  local fmt = date or os.date
  if format == "tmb" then
    lines[1] = "dateTime,character,itemID,offspec,id"
    for i, e in ipairs(E.entries(s)) do
      local w = e.w
      lines[#lines + 1] = ("%s,%s,%d,%d,%s"):format(fmt("%Y-%m-%d", w.at or 0), U.bare(w.p), TMB_ID[w.i] or w.i,
        (w.k == "OS" or w.de) and 1 or 0, csvField(s.id .. ":" .. i))
    end
  elseif format == "dftus" or format == "dfteu" then
    for _, e in ipairs(E.entries(s)) do
      local w = e.w
      if not w.de then
        lines[#lines + 1] = ("%s;[%d];%s"):format(fmt(format == "dfteu" and "%d/%m/%Y" or "%m/%d/%Y", w.at or 0), w.i, w.p)
      end
    end
  else
    lines[1] = "Date,Time,Item,Item ID,Player,How,Roll,Boss"
    for _, e in ipairs(E.entries(s)) do
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
    parts[#parts + 1] = ("%s %s%s"):format(LR.itemLink(w.i), U.short(w.p), w.de and " (disenchant)" or "")
  end
  if #parts == 0 then return {} end
  return U.chatLines(LR.TAG .. " Loot given out: " .. table.concat(parts, ", "), 255)
end
