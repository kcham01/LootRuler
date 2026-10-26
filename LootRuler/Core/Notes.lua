-- Item notes, with no game calls (tested on their own in tests/rolls.lua): the loot master's own note for an item,
-- like "Warrior > Rogue" or "Tanks first". They're kept between raids on that character, said in raid chat when the
-- item is rolled out, shown in everyone's roll window (they travel with the roll) and in the item's tooltip.
-- In and out as text, one item a line: "28525: Warrior > Rogue" (an item link instead of the number works too).
local _, LR = ...
local U = LR.U
local N = {}
LR.Notes = N

N.MAX_LEN = 100
N.MAX = 2000

--- a note made safe to show and send: no links or colours, one line, trimmed, short; nil when empty
function N.clean(text)
  if type(text) ~= "string" then return nil end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|", "")
  text = U.trim(text:gsub("[%c]", " "):gsub("%s+", " ")):sub(1, N.MAX_LEN)
  return text ~= "" and text or nil
end

--- notes saved or received, checked: item id -> note
function N.check(notes)
  local out, n = {}, 0
  if type(notes) ~= "table" then return out end
  for id, text in pairs(notes) do
    local note = type(id) == "number" and id > 0 and id == math.floor(id) and N.clean(text)
    if note and n < N.MAX then out[id] = note n = n + 1 end
  end
  return out
end

--- reads notes from text: item id -> note, and how many lines weren't understood
function N.parse(text)
  local out, bad = {}, 0
  for line in tostring(text or ""):gmatch("[^\r\n]+") do
    if line:find("%S") then
      local id, rest = line:match("item:(%d+)[^|]*|h[^|]*|h|r%s*[:,;%-]?%s*(.*)$")
      if not id then id, rest = line:match("^%s*(%d+)%s*[:,;%-=]%s*(.*)$") end
      local note = N.clean(rest)
      if id and tonumber(id) > 0 and note then out[tonumber(id)] = note else bad = bad + 1 end
    end
  end
  return out, bad
end

--- notes as text, one a line, by item number
function N.text(notes)
  local ids = {}
  for id in pairs(notes or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  local lines = {}
  for _, id in ipairs(ids) do lines[#lines + 1] = id .. ": " .. notes[id] end
  return table.concat(lines, "\n")
end
