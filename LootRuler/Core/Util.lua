-- Small helpers: tables, text, player names, JSON and base64 (for Gargul strings).
local _, LR = ...
local U = {}
LR.U = U

local floor, byte, char = math.floor, string.byte, string.char

---------------------------------------------------------------------- tables
function U.copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = U.copy(v) end
  return out
end

function U.keys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out, function(a, b)
    if type(a) == type(b) then return a < b end
    return tostring(a) < tostring(b)
  end)
  return out
end

function U.find(list, fn) for _, v in ipairs(list) do if fn(v) then return v end end end
function U.indexOf(list, x) for i, v in ipairs(list) do if v == x then return i end end end
function U.count(list, x) local n = 0 for _, v in ipairs(list) do if v == x then n = n + 1 end end return n end
function U.map(list, fn) local out = {} for i, v in ipairs(list) do out[i] = fn(v, i) end return out end
function U.filter(list, fn) local out = {} for _, v in ipairs(list) do if fn(v) then out[#out + 1] = v end end return out end
function U.sameList(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end
--- the same items regardless of order
function U.sameItems(a, b)
  if #a ~= #b then return false end
  local n = {}
  for _, v in ipairs(a) do n[v] = (n[v] or 0) + 1 end
  for _, v in ipairs(b) do
    if not n[v] or n[v] == 0 then return false end
    n[v] = n[v] - 1
  end
  return true
end

--- a stable sort (equal items keep their order)
function U.sort(list, less)
  for i = 2, #list do
    local x, j = list[i], i - 1
    while j >= 1 and less(x, list[j]) do list[j + 1] = list[j] j = j - 1 end
    list[j + 1] = x
  end
  return list
end

---------------------------------------------------------------------- text
function U.trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
--- a Lua pattern that matches what a game string (GlobalStrings: "%s receives loot: %s.") makes, capturing
--- each %s and %d; translations that number their places ("%1$s") work too
function U.pattern(format)
  local p = tostring(format):gsub("%%%d%$", "%%")
  p = p:gsub("%%s", "\1"):gsub("%%d", "\2")
  p = p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
  return "^" .. p:gsub("\1", "(.+)"):gsub("\2", "(%%d+)") .. "$"
end
--- compares "1.2.0-beta" style versions: -1, 0, 1 (a beta comes before the release of the same number)
function U.compareVersions(a, b)
  local function parts(v)
    v = tostring(v or "")
    local nums = {}
    for n in v:gmatch("(%d+)") do nums[#nums + 1] = tonumber(n) if #nums == 3 then break end end
    return nums, v:find("%-") ~= nil
  end
  local pa, ba = parts(a)
  local pb, bb = parts(b)
  for i = 1, 3 do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then return x < y and -1 or 1 end
  end
  if ba ~= bb then return ba and -1 or 1 end
  return 0
end

function U.plural(n, one, many) return n .. " " .. (n == 1 and one or (many or one .. "s")) end
function U.hex(r, g, b) return ("%02x%02x%02x"):format(floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5)) end
function U.color(text, r, g, b) return "|cff" .. U.hex(r, g, b) .. text .. "|r" end
function U.lower(s) return tostring(s or ""):lower() end
--- strips colour codes and links down to their text
function U.plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")) end

--- splits a chat message into lines of at most `max` characters without breaking item links or words
function U.chatLines(text, max)
  max = max or 255
  local atoms, i = {}, 1
  while i <= #text do
    local a, b = text:find("|c%x%x%x%x%x%x%x%x|H.-|h.-|h|r", i)
    local plainPart = a and text:sub(i, a - 1) or text:sub(i)
    local pos = 1
    while true do
      local ws, we = plainPart:find("^%s*", pos)
      local s2, e2 = plainPart:find("^%S+", we + 1)
      if not s2 then
        if we >= ws and we > 0 and #atoms > 0 then atoms.trailingSpace = true end
        break
      end
      atoms[#atoms + 1] = { plainPart:sub(s2, e2), sp = (we >= ws and we - ws + 1 > 0) or #atoms == 0 }
      pos = e2 + 1
    end
    if not a then break end
    local before = text:sub(a - 1, a - 1)
    atoms[#atoms + 1] = { text:sub(a, b), sp = #atoms == 0 or before:match("%s") ~= nil or a == 1 }
    i = b + 1
  end
  local lines, line = {}, ""
  for _, at in ipairs(atoms) do
    local piece = (line ~= "" and at.sp) and (" " .. at[1]) or at[1]
    if line ~= "" and #line + #piece > max then
      lines[#lines + 1] = line
      line = at[1]
    else
      line = line .. piece
    end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end

---------------------------------------------------------------------- player names
-- Internally every player is "Name-Realm", the way the game names players from other realms. Shown
-- without the realm when it's your own.
function U.realm()
  local r = GetNormalizedRealmName and GetNormalizedRealmName()
  if not r or r == "" then r = (GetRealmName() or ""):gsub("[%s%-]", "") end
  return r
end
function U.full(name)
  if not name or name == "" then return nil end
  if name:find("-", 1, true) then return name end
  return name .. "-" .. U.realm()
end
function U.me()
  local name, realm = UnitFullName("player")
  if realm and realm ~= "" then return name .. "-" .. realm end
  return U.full(name or UnitName("player"))
end
--- "Name" for your own realm, "Name-Realm" for others
function U.short(full)
  if not full then return "?" end
  local name, realm = full:match("^(.-)%-(.+)$")
  if name and realm == U.realm() then return name end
  return full
end
--- the name only, for comparisons with names typed by people
function U.bare(full) return (tostring(full or ""):match("^([^%-]+)")) or "" end
function U.samePlayer(a, b) return a and b and U.full(a):lower() == U.full(b):lower() end

--- a class token ("PALADIN") coloured
function U.classColor(token)
  local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
  if c then return c.r, c.g, c.b end
  return 0.85, 0.85, 0.85
end
function U.classText(text, token) local r, g, b = U.classColor(token) return U.color(text, r, g, b) end

function U.now() return GetServerTime and GetServerTime() or time() end

---------------------------------------------------------------------- JSON
-- Enough JSON for Gargul imports and softres.it exports: objects, arrays, strings, numbers, booleans, null.
-- A table is written as an array when it has keys 1..n and nothing else (an empty table as {} unless
-- marked with U.array).
local ARRAY = setmetatable({}, { __mode = "k" })
function U.array(t) t = t or {} ARRAY[t] = true return t end

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function jstr(s)
  return '"' .. s:gsub('[%c"\\]', function(c) return ESC[c] or ("\\u%04x"):format(byte(c)) end) .. '"'
end

local function isArray(t)
  if ARRAY[t] then return true end
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
    n = n + 1
  end
  return n > 0 and n == #t
end

function U.toJSON(v)
  local tv = type(v)
  if tv == "nil" then return "null" end
  if tv == "boolean" then return v and "true" or "false" end
  if tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    if v % 1 == 0 and math.abs(v) < 2 ^ 53 then return ("%.0f"):format(v) end
    return ("%.14g"):format(v)
  end
  if tv == "string" then return jstr(v) end
  if tv == "table" then
    local out = {}
    if isArray(v) then
      for i = 1, #v do out[i] = U.toJSON(v[i]) end
      return "[" .. table.concat(out, ",") .. "]"
    end
    for _, k in ipairs(U.keys(v)) do out[#out + 1] = jstr(tostring(k)) .. ":" .. U.toJSON(v[k]) end
    return "{" .. table.concat(out, ",") .. "}"
  end
  error("can't write a " .. tv .. " as JSON")
end

--- reads JSON; returns the value, or nil and a reason
function U.fromJSON(s)
  local i = 1
  local function ws() i = s:find("[^ \t\r\n]", i) or #s + 1 end
  local value
  local function str()
    i = i + 1
    local out = {}
    while true do
      local c = s:sub(i, i)
      if c == "" then error("unfinished string") end
      if c == '"' then i = i + 1 break end
      if c == "\\" then
        local e = s:sub(i + 1, i + 1)
        if e == "u" then
          local code = tonumber(s:sub(i + 2, i + 5), 16) or error("bad \\u escape")
          i = i + 6
          if code >= 0xD800 and code <= 0xDBFF and s:sub(i, i + 1) == "\\u" then
            local lo = tonumber(s:sub(i + 2, i + 5), 16) or 0
            code = 0x10000 + (code - 0xD800) * 0x400 + (lo - 0xDC00)
            i = i + 6
          end
          if code < 0x80 then out[#out + 1] = char(code)
          elseif code < 0x800 then out[#out + 1] = char(0xC0 + floor(code / 64), 0x80 + code % 64)
          elseif code < 0x10000 then out[#out + 1] = char(0xE0 + floor(code / 4096), 0x80 + floor(code / 64) % 64, 0x80 + code % 64)
          else out[#out + 1] = char(0xF0 + floor(code / 262144), 0x80 + floor(code / 4096) % 64, 0x80 + floor(code / 64) % 64, 0x80 + code % 64) end
        else
          local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
          out[#out + 1] = map[e] or error("bad escape")
          i = i + 2
        end
      else
        local j = s:find('["\\]', i) or #s + 1
        out[#out + 1] = s:sub(i, j - 1)
        i = j
      end
    end
    return table.concat(out)
  end
  function value()
    ws()
    local c = s:sub(i, i)
    if c == "{" then
      local t = {}
      i = i + 1 ws()
      if s:sub(i, i) == "}" then i = i + 1 return t end
      while true do
        ws()
        if s:sub(i, i) ~= '"' then error("expected a key") end
        local k = str()
        ws()
        if s:sub(i, i) ~= ":" then error("expected :") end
        i = i + 1
        t[k] = value()
        ws()
        local d = s:sub(i, i)
        i = i + 1
        if d == "}" then return t end
        if d ~= "," then error("expected , or }") end
      end
    elseif c == "[" then
      local t = U.array({})
      i = i + 1 ws()
      if s:sub(i, i) == "]" then i = i + 1 return t end
      while true do
        t[#t + 1] = value()
        ws()
        local d = s:sub(i, i)
        i = i + 1
        if d == "]" then return t end
        if d ~= "," then error("expected , or ]") end
      end
    elseif c == '"' then return str()
    elseif s:sub(i, i + 3) == "true" then i = i + 4 return true
    elseif s:sub(i, i + 4) == "false" then i = i + 5 return false
    elseif s:sub(i, i + 3) == "null" then i = i + 4 return nil
    else
      local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
      if not num or num == "" then error("unexpected '" .. c .. "'") end
      i = i + #num
      return tonumber(num) or error("bad number")
    end
  end
  local ok, res = pcall(function()
    local v = value()
    ws()
    if i <= #s then error("text after the end") end
    return v
  end)
  if not ok then return nil, tostring(res):gsub("^.-:%d+: ", "") end
  return res
end

---------------------------------------------------------------------- base64 (standard alphabet, = padding)
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DEC = {}
for n = 1, 64 do DEC[byte(B64, n)] = n - 1 end

function U.b64encode(s)
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = byte(s, i, i + 2)
    local v = a * 65536 + (b or 0) * 256 + (c or 0)
    local q = { floor(v / 262144) % 64, floor(v / 4096) % 64, floor(v / 64) % 64, v % 64 }
    out[#out + 1] = B64:sub(q[1] + 1, q[1] + 1) .. B64:sub(q[2] + 1, q[2] + 1)
      .. (b and B64:sub(q[3] + 1, q[3] + 1) or "=") .. (c and B64:sub(q[4] + 1, q[4] + 1) or "=")
  end
  return table.concat(out)
end

--- decodes base64 (spaces and line breaks are ignored); nil when it isn't base64
function U.b64decode(s)
  s = s:gsub("[%s]", "")
  if s:find("[^%w%+/=]") then return nil end
  s = s:gsub("=", "")
  local out, bits, n = {}, 0, 0
  for i = 1, #s do
    bits = bits * 64 + DEC[byte(s, i)]
    n = n + 6
    if n >= 8 then
      n = n - 8
      local v = floor(bits / 2 ^ n)
      out[#out + 1] = char(v)
      bits = bits - v * 2 ^ n
    end
  end
  return table.concat(out)
end
