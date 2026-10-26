-- Raid setup, with no game calls (tested on their own in tests/session.lua): reading who's coming from text pasted
-- from anywhere (raid-helper, a spreadsheet, a forum post), comparing it with who's in the group, and working out
-- the moves that sort the raid into the groups the text asks for. UI/Lineup.lua does it in the game.
--
-- What's read: one name per line, or names separated by commas, tabs or semicolons. In each of those, the first word
-- that could be a character's name is the name, so "1. Ann (Holy Priest)", "Ann, Priest, Healer" and "Priest - Ann"
-- all read as Ann (class, spec and role words are passed over). A line "Group 2" (or "G2:", "Group 2: Ann, Bob")
-- puts the names after it in group 2, until the next one.
local _, LR = ...
local U = LR.U
local L = {}
LR.Lineup = L

L.MAX = 40
L.GROUP_SIZE = 5
local SKIP = {}
for w in ([[warrior paladin hunter rogue priest shaman mage warlock druid deathknight dk pally lock hunt sham
  arms fury prot protection holy ret retribution disc discipline shadow shadowpriest bm beast beastmastery mastery mm
  marksman marksmanship surv survival sv assa assassination combat sub subtlety ele elemental enh enhance enhancement
  resto restoration arcane fire frost aff affliction demo demonology destro destruction balance boomkin moonkin feral
  guardian tank tanks heal heals healer healers dps melee ranged caster casters physical support
  group grp bench benched late tentative absent absence signup signups roster raid raids
  and or the name names class spec role team party]]):gmatch("%a+") do SKIP[w] = true end

local CHAR = "[%z\1-\127\194-\244][\128-\191]*"
--- whether a word could be a character's name: letters only (any alphabet), 2 to 12 of them, maybe "-Realm"
local function nameLike(word)
  local bare, realm = word:match("^([^%-]+)%-?(.*)$")
  if not bare or bare:find("[%d%p%s]") then return false end
  if realm ~= "" and realm:find("[%d%s%-]") then return false end
  local n = 0
  for _ in bare:gmatch(CHAR) do n = n + 1 end
  return n >= 2 and n <= 12 and not SKIP[U.foldCase(bare)]
end

--- the first name in a piece of text, or nil
local function firstName(text)
  for word in text:gmatch("[^%s%(%)%[%]%*\"'<>@#:%.!%?=+]+") do
    word = word:gsub("^%-+", ""):gsub("%-+$", "")
    if nameLike(word) then return U.capitalize(word) end
  end
end

--- reads pasted text: { { name = "Ann" or "Ann-Realm", group = 1-8 or nil } }, in order, each once (40 at most)
function L.parse(text)
  local out, seen, group = {}, {}, nil
  for line in (tostring(text or "") .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    local g, rest = line:match("^%s*[Gg][Rr]?[Oo]?[Uu]?[Pp]?%s*(%d)%s*[:%-%.)]?%s*(.*)$")
    if g and tonumber(g) >= 1 and tonumber(g) <= 8 and (rest == "" or line:find("[:%-]") or line:lower():find("group", 1, true)) then
      group = tonumber(g)
      line = rest
    end
    for item in line:gmatch("[^,;\t|/]+") do
      local name = firstName(item)
      local key = name and U.foldCase(name)
      if name and not seen[key] and #out < L.MAX then
        seen[key] = true
        out[#out + 1] = { name = name, group = group }
      end
    end
  end
  return out
end

--- the character in the group a name on the list is (a name without a realm is anyone of that name, mine first)
local function find(roster, name)
  local full = U.full(name)
  for _, m in ipairs(roster) do if U.samePlayer(m.name, full) then return m end end
  if not name:find("-", 1, true) then
    for _, m in ipairs(roster) do if U.foldCase(U.bare(m.name)) == U.foldCase(name) then return m end end
  end
end
L.find = find

--- the list against the group: here ({ entry, member }), missing (entries), extra (members not on the list)
function L.compare(plan, roster)
  local here, missing, extra, used = {}, {}, {}, {}
  for _, e in ipairs(plan) do
    local m = find(roster, e.name)
    if m and not used[m] then used[m] = true here[#here + 1] = { e, m } else missing[#missing + 1] = e end
  end
  for _, m in ipairs(roster) do if not used[m] then extra[#extra + 1] = m end end
  return { here = here, missing = missing, extra = extra }
end

--- the next move to sort the raid into the list's groups, or nil when it's sorted (or can't be): { index, group } to
--- move someone into a group with room, or { index, with = index } to swap two. roster: { { name, group, index } }.
--- Each move puts one player where the list wants them for good, so it takes at most one move per player.
function L.nextMove(plan, roster)
  local want, count = {}, {}
  for _, m in ipairs(roster) do count[m.group] = (count[m.group] or 0) + 1 end
  for _, x in ipairs(L.compare(plan, roster).here) do if x[1].group then want[x[2]] = x[1].group end end
  for _, m in ipairs(roster) do
    local g = want[m]
    if g and m.group ~= g then
      if (count[g] or 0) < L.GROUP_SIZE then return { index = m.index, group = g } end
      for _, o in ipairs(roster) do
        if o.group == g and want[o] ~= g then return { index = m.index, with = o.index } end
      end
    end
  end
end

--- the moves applied to a copy of the roster (for checking a plan sorts out): the roster as it ends up
function L.apply(roster, move)
  if move.with then
    local a, b
    for _, m in ipairs(roster) do if m.index == move.index then a = m elseif m.index == move.with then b = m end end
    if a and b then a.group, b.group = b.group, a.group end
  else
    for _, m in ipairs(roster) do if m.index == move.index then m.group = move.group end end
  end
  return roster
end
