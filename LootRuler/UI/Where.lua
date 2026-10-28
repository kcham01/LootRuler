-- Which raid we're in. A session belongs to one raid, and its loot list only takes loot from inside it (Drops.here). When
-- the leader of an open session goes into a different raid, or into its own raid once the lockout it was for has ended,
-- they're asked whether to start a new session for this one (setting: raidPrompt). The lockout's end is kept on the
-- session (s.le), read from the game's raid info while the leader is inside its raid and saved to it.
local _, LR = ...
local U, K = LR.U, LR.K
local UI = LR.UI
local Drops = LR.Drops

local asked = {}      -- session id .. ":" .. instance -> true: asked already

--- the open session I lead (not a practice one), or nil
local function mine()
  local s = LR.current()
  if s and LR.isLeader(s) and not s.ended and not s.practice and not s.pv then return s end
end

--- when my lockout for the instance I'm in ends (a time), or nil when I'm not saved to it
local function lockoutEnds(where)
  for i = 1, GetNumSavedInstances() do
    local name, _, reset, _, locked, _, _, _, _, _, _, _, _, map = GetSavedInstanceInfo(i)
    if locked and (reset or 0) > 0 and (map == where.map or name == where.name) then return U.now() + reset end
  end
end

--- what to ask about here: "raid" (a different raid), "lockout" (its raid, but a later lockout), or nil
function UI.whereCheck(s, where)
  if where.kind ~= "raid" then return nil end
  if not Drops.here(s, where) then return "raid" end
  if s.le and U.now() > s.le then return "lockout" end
end

--- a new session for the raid I'm in, like the one I had (that one ends, and is kept under Past raids)
local function startHere(s, where)
  local key = LR.raidAt(where.map)
  LR.endSession(s)
  local n = LR.startSession(key or LR.CUSTOM, s.sr, s.dupes, s.guild, not key and where.name or nil, s.any)
  if s.plusOne then LR.setPlusOne(n, true) end
  if s.gdkp then LR.setGdkp(n, true) end
  if s.boost then LR.setSessionBoost(n, true) end
  return n
end

--- asks the leader whether to start a new session here. why: "raid" or "lockout"; pretend: the Test tab's (nothing changes)
function UI.newRaidPrompt(s, where, why, pretend)
  local key = LR.raidAt(where.map)
  local here = key and LR.raid(key).name or where.name
  local was = LR.raidOf(s).name
  UI.show()
  UI.openSheet(why == "lockout" and "A new lockout" or "A new raid", function(f, h)
    if why == "lockout" then
      f:text(("Your %s session is from an earlier lockout. Start a new one for this one?"):format(was))
    else
      f:text(("You're in %s, but your session is for %s. Start a new session for %s?"):format(here, was, here))
    end
    f:note(("Until you do, loot here doesn't go on %s's list. What the %s session gave out is kept under Past raids (Loot tab)%s.")
      :format(was, was, LR.Gdkp.unsettled(s)[1] and ", where you can finish its payouts" or ""))
    f:gap(6)
    f:buttons({
      { label = "Start " .. here, click = function()
        h.close()
        if pretend then LR.print(("(pretend) A new session for %s would start now."):format(here)) return end
        local n = startHere(s, where)
        UI.toast(("%s reserves are open."):format(LR.raidOf(n).name))
        UI.go("session")
      end },
      { label = "Keep " .. was, click = function() h.close() end },
    }, "left")
    local set = LR.db.settings
    f:chips({ { tick = true, label = "Don't ask again", on = not set.raidPrompt, click = function() set.raidPrompt = not set.raidPrompt h.redraw(true) end,
      tip = "Settings tab, Giving out and trading, to ask again." } })
  end)
end

local function check()
  if not LR.db then return end
  local s = mine()
  if not s then return end
  local where = LR.where()
  if not s.le and where.kind == "raid" and Drops.here(s, where) then RequestRaidInfo() end   -- (UPDATE_INSTANCE_INFO)
  local why = UI.whereCheck(s, where)
  local k = s.id .. ":" .. tostring(where.map) .. ":" .. tostring(why)
  if not why or asked[k] or not LR.db.settings.raidPrompt or InCombatLockdown() then return end
  asked[k] = true
  UI.newRaidPrompt(s, where, why)
end
UI.whereNow = check

--- the game's raid info came: the lockout my session's raid is on, the first time I'm in it saved
local function noteLockout()
  local s = mine()
  if not s or s.le then return end
  local where = LR.where()
  if where.kind ~= "raid" or not Drops.here(s, where) then return end
  s.le = lockoutEnds(where)
end
UI.whereLockout = noteLockout

local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "UPDATE_INSTANCE_INFO" }) do events:RegisterEvent(e) end
events:SetScript("OnEvent", function(_, event)
  if not LR.db then return end              -- (the game can say this before LootRuler has loaded its saved data)
  local ok, err = pcall(function()
    if event == "UPDATE_INSTANCE_INFO" then noteLockout()
    else C_Timer.After(2, check) end         -- (a moment after loading in, when the instance is known)
  end)
  if not ok then geterrorhandler()(err) end
end)
