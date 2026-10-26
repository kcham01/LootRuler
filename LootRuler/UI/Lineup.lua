-- Raid setup (the leader): paste who's coming, see who's missing and who isn't on the list, invite the missing,
-- tell the raid who's missing, and sort everyone into the groups the list asks for. Reading the list and working
-- out the moves is Core/Lineup.lua; this does it in the game. Nothing is accepted for anyone: invites are only sent.
local _, LR = ...
local U, K, L = LR.U, LR.K, LR.Lineup
local UI = LR.UI

local MAX_TEXT = 4000
local pending = {}            -- names to invite once the group has become a raid
local sorting = false

--- the raid, with each player's group and place, for sorting: { { name, class, group, index } }
function LR.raidRoster()
  local out = {}
  if not IsInRaid() then return out end
  for i = 1, GetNumGroupMembers() do
    local name, _, sub, _, _, class = GetRaidRosterInfo(i)
    if name then out[#out + 1] = { name = U.full(name), class = class, group = sub, index = i } end
  end
  return out
end

--- whether I may invite and move people: not in a group, or the leader, or an assistant in a raid
function LR.canSetUp()
  return not IsInGroup() or UnitIsGroupLeader("player") or (IsInRaid() and UnitIsGroupAssistant("player"))
end

--- the list I pasted last (kept between sessions)
function LR.lineupText()
  local t = LR.db.ui.lineup
  return type(t) == "string" and t:sub(1, MAX_TEXT) or ""
end

--- invites everyone on the list who isn't in the group. A party that would go over five becomes a raid first, and
--- the rest are invited once it has. Returns how many were invited now, and how many will be.
function LR.inviteMissing(plan)
  local missing = {}
  for _, e in ipairs(L.compare(plan, LR.roster()).missing) do
    if not U.samePlayer(U.full(e.name), U.me()) then missing[#missing + 1] = e.name end
  end
  pending = {}
  local size = math.max(1, GetNumGroupMembers())
  if not IsInRaid() and size + #missing > 5 then
    if IsInGroup() and UnitIsGroupLeader("player") then
      ConvertToRaid()
      pending = missing
      return 0, #pending
    end
    -- on my own: a party first; the rest once it's a raid
    for i = 5 - size + 1, #missing do pending[#pending + 1] = missing[i] end
    for i = #missing, 5 - size + 1, -1 do missing[i] = nil end
  end
  for _, name in ipairs(missing) do C_PartyInfo.InviteUnit(name) end
  return #missing, #pending
end

-- invites waiting for the group to become a raid
local events = CreateFrame("Frame")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:SetScript("OnEvent", function()
  if #pending == 0 or not IsInGroup() or not UnitIsGroupLeader("player") then return end
  if not IsInRaid() then ConvertToRaid() return end
  local list = pending
  pending = {}
  for _, name in ipairs(list) do
    if not LR.inGroup(name) then C_PartyInfo.InviteUnit(name) end
  end
end)

--- one raid chat line (or a few) naming who on the list isn't here yet. Returns how many.
function LR.postMissing(plan)
  local names = {}
  for _, e in ipairs(L.compare(plan, LR.roster()).missing) do names[#names + 1] = U.short(U.full(e.name)) end
  local ch = LR.groupChannel()
  if #names == 0 or not ch then return 0 end
  for _, line in ipairs(U.chatLines(("%s Not here yet (%d): %s."):format(LR.TAG, #names, table.concat(names, ", ")))) do LR.say(line, ch) end
  return #names
end

--- sorts the raid into the list's groups, one move at a time (each after the game has made the last). done(moves,
--- stuck) when it's finished: stuck when the game didn't make a move (in combat, say).
function LR.sortGroups(plan, done)
  if sorting or not IsInRaid() then return false end
  sorting = true
  local moves, last = 0, nil
  local function step()
    local m = L.nextMove(plan, LR.raidRoster())
    local key = m and (m.index .. ":" .. (m.with or "") .. ":" .. (m.group or ""))
    if not m or key == last or moves >= L.MAX then
      sorting = false
      if done then done(moves, m ~= nil) end
      return
    end
    last = key
    moves = moves + 1
    if m.with then SwapRaidSubgroup(m.index, m.with) else SetRaidSubgroup(m.index, m.group) end
    C_Timer.After(0.5, step)
  end
  step()
  return true
end

---------------------------------------------------------------------- the sheet
local sheet
function UI.lineupSheet()
  UI.show()
  UI.openSheet("Raid setup", function(f, h)
    sheet = h
    local text = LR.lineupText()
    f:note("Paste who's coming: one name per line, or names with commas, from raid-helper, a spreadsheet, anywhere. Class and spec words are skipped. A line \"Group 1\", \"Group 2\"... puts the names after it in that group.")
    local memo = K.get(f.owner, "memo", f.parent)
    f:place(memo, 140, 0, f.width)
    K.setEditMemo(memo, f.width, 140, text, function(t) LR.db.ui.lineup = t:sub(1, MAX_TEXT) end)
    f:gap(4)
    f:buttons({ { label = "Read the list", click = function() memo.edit:ClearFocus() h.redraw(true) end } }, "left")
    local plan = L.parse(text)
    if #plan == 0 then
      f:note("No names yet.")
    else
      local c = L.compare(plan, LR.roster())
      f:note(("%s on the list: %d here, %d not in the group."):format(U.plural(#plan, "name"), #c.here, #c.missing), K.GOLD)
      if #c.missing > 0 then
        local names = {}
        for _, e in ipairs(c.missing) do names[#names + 1] = e.name end
        f:note("Not here: " .. table.concat(names, ", "))
      end
      if #c.extra > 0 then
        local names = {}
        for _, m in ipairs(c.extra) do names[#names + 1] = U.classText(U.short(m.name), m.class) end
        f:note("In the group, not on the list: " .. table.concat(names, ", "))
      end
      local grouped = false
      for _, e in ipairs(plan) do if e.group then grouped = true end end
      local can = LR.canSetUp()
      if not can then f:note("Only the raid leader or an assistant can invite and move people.", K.RED) end
      f:buttons({
        { label = ("Invite %d"):format(#c.missing), disabled = not can or #c.missing == 0, click = function()
          local now, later = LR.inviteMissing(plan)
          UI.toast(later > 0 and ("Invited %d. %d more once the group is a raid."):format(now, later) or ("Invited %d."):format(now))
        end },
        { label = "Say who's missing", disabled = #c.missing == 0 or not LR.groupChannel(), click = function()
          LR.postMissing(plan)
        end },
        { label = "Sort into groups", disabled = not (can and grouped and IsInRaid()), click = function()
          LR.sortGroups(plan, function(moves, stuck)
            UI.toast(stuck and "The game didn't move everyone (it can't in combat). Try again." or
              moves == 0 and "Everyone's in their group already." or ("Groups sorted (%s)."):format(U.plural(moves, "move")))
          end)
        end },
      }, "left")
      if grouped and not IsInRaid() then f:note("Sorting into groups works once the group is a raid.") end
    end
    f:buttons({ { label = "Close", click = function() h.close() end } })
  end, { onClose = function() sheet = nil end })
end

LR.onChange(function(what)
  if what == "roster" and sheet then sheet.redraw(true) end
end)
