-- Locking reserves by themselves: the leader picks when (in some minutes, or at a time of day), the raid is told 5, 2 and
-- 1 minute before, and when the time comes reserves lock and the raid hears that too. The time is the session's `al`
-- (server time), so the leader's addon keeps it over a reload; only the leader's addon locks and talks.
local _, LR = ...
local U, S = LR.U, LR.Session

local L = {}
LR.Lock = L

L.WARN = { 300, 120, 60 }           -- seconds before: the raid is told (largest first)
L.CHECK = 5                         -- seconds between checks while a time is set
local warned = {}                   -- session id .. ":" .. time .. ":" .. mark -> true
local first = {}                    -- session id .. ":" .. time -> seconds left when I first saw it (marks before that are skipped)

--- "20:00", "8:30", "8:30pm", "20.15": seconds into the day, or nil
function L.parseTime(text)
  local h, m, ap = tostring(text or ""):lower():match("^%s*(%d%d?)[:%.](%d%d)%s*([ap]?)m?%s*$")
  if not h then
    h, ap = tostring(text or ""):lower():match("^%s*(%d%d?)%s*([ap])m%s*$")
    m = h and "0"
  end
  h, m = tonumber(h), tonumber(m)
  if not h or h > 23 or m > 59 then return nil end
  if ap == "p" and h < 12 then h = h + 12 elseif ap == "a" and h == 12 then h = 0 end
  return h * 3600 + m * 60
end

--- the (server) time it'll next be that time of day on my clock
function L.atTime(secs)
  local t = date("*t")
  local into = t.hour * 3600 + t.min * 60 + t.sec
  local wait = secs - into
  if wait <= 0 then wait = wait + 24 * 3600 end
  return U.now() + wait
end

--- when a lock time is, on my clock: "20:15"
function L.clock(at) return (LR.Session.okTime(at) and date("%H:%M", time() + (at - U.now()))) or "?" end

--- what the raid hears before it locks
function L.warning(left)
  local mins = math.max(1, math.floor((left + 30) / 60))
  return ("Soft reserves lock in %s. %s"):format(U.plural(mins, "minute"), LR.Whisper.howTo())
end

--- checks the lock time of the session I lead: warns, or locks. Returns what it did ("warned", "locked") or nil.
function L.check()
  local s = LR.db and LR.current()
  if not s or not s.al or not LR.isLeader(s) or s.archived or s.pv then return nil end
  local left = s.al - U.now()
  local ch = LR.groupChannel()
  if left <= 0 then
    LR.setAutoLock(s, nil)
    if not s.locked then LR.setLocked(s, true) end          -- (the raid hears it from LR.setLocked)
    return "locked"
  end
  local k = s.id .. ":" .. s.al
  first[k] = first[k] or left
  for i, mark in ipairs(L.WARN) do
    local below = L.WARN[i + 1] or 0
    local key = k .. ":" .. mark
    -- (a mark already passed when the time was set isn't said late: set for 90 seconds, the raid hears just "1 minute")
    if left <= mark and left > below and mark <= first[k] + L.CHECK + 1 and not warned[key] then
      warned[key] = true
      if ch and not s.locked then
        for _, l in ipairs(U.chatLines(LR.TAG .. " " .. L.warning(left), 255)) do LR.say(l, ch) end
      end
      return "warned"
    end
  end
end

local function tick()
  local ok, err = pcall(L.check)
  if not ok then geterrorhandler()(err) end
  C_Timer.After(L.CHECK, tick)
end
C_Timer.After(L.CHECK, tick)
